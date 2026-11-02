package au.com.voiceplatform.vp_linphone

import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The account's addresses from a SipAccount (decision 70). Example names only. */
class AccountSetupTest {

    // What POST /devices/me/sip-credentials returns, in shape.
    private val user = "app-abcde12345"
    private val domain = "democo.sip.example.com"
    private val proxy = "sip:edge.example.com:5061;transport=tls"

    /** Records what the engine would set on liblinphone's AccountParams, in order. */
    private class FakeParams : AccountSetup.Params {
        val calls = mutableListOf<String>()
        var identity: String? = null
        var displayName: String? = null
        var serverUri: String? = null
        override fun setIdentity(uri: String, displayName: String) {
            calls += "identity"
            identity = uri
            this.displayName = displayName
        }
        override fun setServer(uri: String) {
            calls += "server"
            serverUri = uri
        }
        override var outboundProxyEnabled = false
            set(value) {
                calls += "outboundProxy $value"
                field = value
            }
    }

    private fun applied(proxyUri: String = proxy): FakeParams {
        val plan = AccountSetup.plan(user, domain, proxyUri)!!
        return FakeParams().also { AccountSetup.apply(plan, "Ava Nguyen", it) }
    }

    @Test
    fun registerGoesToTheOutboundProxyNotTheTenantDomain() {
        val p = applied()
        // liblinphone sends REGISTER to the server address: it must be the proxy.
        assertEquals("sip:edge.example.com:5061;transport=tls", p.serverUri)
        assertFalse(domain in p.serverUri!!, "never the tenant domain, which has no DNS")
        // And the proxy is the route for every other request (calls, SUBSCRIBE).
        assertTrue(p.outboundProxyEnabled)
    }

    @Test
    fun theIdentityStaysTheTenantDomain() {
        val p = applied()
        assertEquals("sip:app-abcde12345@democo.sip.example.com", p.identity)
        assertEquals("Ava Nguyen", p.displayName)
    }

    @Test
    fun theServerIsSetBeforeTheOutboundProxyIsEnabled() {
        // liblinphone refuses to enable the outbound proxy without a server address.
        assertEquals(listOf("identity", "server", "outboundProxy true"), applied().calls)
    }

    @Test
    fun tlsIsCheckedAgainstTheProxysHost() {
        assertEquals("edge.example.com", AccountSetup.plan(user, domain, proxy)!!.tlsHost)
    }

    @Test
    fun theProxyIsAlwaysPlainSipOverTls() {
        val cases = mapOf(
            "sip:edge.example.com:5061;transport=tls" to "sip:edge.example.com:5061;transport=tls",
            "sip:edge.example.com:5061" to "sip:edge.example.com:5061;transport=tls",
            "sip:edge.example.com;transport=tcp" to "sip:edge.example.com;transport=tls",
            "sips:edge.example.com:5061" to "sip:edge.example.com:5061;transport=tls",
            "<sip:edge.example.com:5061;transport=TLS;lr>" to "sip:edge.example.com:5061;transport=tls",
            "  sip:edge.example.com  " to "sip:edge.example.com;transport=tls",
            "sip:[2001:db8::1]:5061;transport=tls" to "sip:[2001:db8::1]:5061;transport=tls",
        )
        for ((given, server) in cases) assertEquals(server, applied(given).serverUri, given)
    }

    @Test
    fun anUnusableAccountIsRefusedNotSentToTheDomain() {
        for (bad in listOf("", "edge.example.com", "http://edge.example.com", "sip:", "sip:edge.example.com:0", "sip:edge.example.com:70000", "sip:edge example.com")) {
            assertNull(AccountSetup.plan(user, domain, bad), bad)
        }
        assertNull(AccountSetup.plan("", domain, proxy))
        assertNull(AccountSetup.plan("a@b", domain, proxy))
        assertNull(AccountSetup.plan(user, "", proxy))
        assertNull(AccountSetup.plan(user, "dom ain", proxy))
    }

    private val engine = File("src/main/kotlin/au/com/voiceplatform/vp_linphone/LinphoneEngine.kt").readText()

    @Test
    fun theEngineBuildsTheAccountFromThePlan() {
        val register = engine.substringAfter("    fun register(").substringBefore("    private fun applyPush(")
        // The plan is checked before anything is torn down.
        assertTrue(register.indexOf("AccountSetup.plan(authUsername, sipDomain, outboundProxy)") < register.indexOf("dropAccount(c)"))
        assertTrue("AccountSetup.apply(plan, displayName, LinphoneAccountParams(params, factory))" in register)
        // The push contact parameters are on the same account params, so REGISTER carries them via the proxy.
        assertTrue(register.indexOf("AccountSetup.apply(") < register.indexOf("applyPush(params,"))
        // No server address from the domain, no hand-made routes that REGISTER would ignore.
        assertFalse("sip:\$sipDomain;transport=tls" in engine)
        assertFalse("setRoutesAddresses" in engine)
        assertTrue("p.isOutboundProxyEnabled = value" in engine)
        // TLS verification stays on.
        assertTrue("c.verifyServerCertificates(true)" in engine)
        assertTrue("c.verifyServerCn(true)" in engine)
    }
}
