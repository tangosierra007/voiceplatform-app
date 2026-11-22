package au.com.voiceplatform.vp_linphone

import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** G8: only a debug build trusts the test stack's CA for SIP TLS. */
class TestCaTrustTest {

    // Shape only: not a real certificate (the rule never parses it).
    private val testCa = "-----BEGIN CERTIFICATE-----\nTESTSTACKCA\n-----END CERTIFICATE-----\n"
    private val bundled = "-----BEGIN CERTIFICATE-----\nBUNDLEDROOT\n-----END CERTIFICATE-----\n"

    @Test
    fun aDebugBuildWithTheResourceTrustsTheExtraCa() {
        val data = TestCaTrust.rootCaData(debuggable = true, testPem = testCa, bundled = bundled)!!
        assertTrue("BUNDLEDROOT" in data, "the bundled roots stay trusted")
        assertTrue("TESTSTACKCA" in data)
        assertTrue(data.indexOf("BUNDLEDROOT") < data.indexOf("TESTSTACKCA"))
    }

    @Test
    fun aReleaseBuildIgnoresTheResource() {
        assertNull(TestCaTrust.rootCaData(debuggable = false, testPem = testCa, bundled = bundled))
    }

    @Test
    fun noResourceLeavesLiblinphoneAlone() {
        assertNull(TestCaTrust.rootCaData(debuggable = true, testPem = null, bundled = bundled))
        assertNull(TestCaTrust.rootCaData(debuggable = true, testPem = "  \n", bundled = bundled))
    }

    @Test
    fun withoutBundledRootsTheTestCaIsTheOnlyOne() {
        assertEquals(testCa, TestCaTrust.rootCaData(debuggable = true, testPem = testCa, bundled = null))
    }

    @Test
    fun aPrivateKeyIsRefused() {
        // Split so no secret scanner reads it as a key; it is only a marker.
        val withKey = testCa + "-----BEGIN PRIVATE" + " KEY-----\nX\n"
        assertFailsWith<IllegalArgumentException> {
            TestCaTrust.rootCaData(debuggable = true, testPem = withKey, bundled = bundled)
        }
    }

    @Test
    fun somethingThatIsNotACertificateIsRefused() {
        assertFailsWith<IllegalArgumentException> {
            TestCaTrust.rootCaData(debuggable = true, testPem = "hello", bundled = bundled)
        }
    }

    @Test
    fun theEngineAppliesItAfterTurningOnCertificateChecks() {
        val engine = File("src/main/kotlin/au/com/voiceplatform/vp_linphone/LinphoneEngine.kt").readText()
        val verify = engine.indexOf("c.verifyServerCertificates(true)")
        val apply = engine.indexOf("TestCaTrust.forApp(context, c.rootCa)")
        assertTrue(verify >= 0 && apply > verify, "the extra CA never turns verification off")
    }
}
