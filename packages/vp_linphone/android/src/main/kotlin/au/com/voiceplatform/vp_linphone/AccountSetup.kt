package au.com.voiceplatform.vp_linphone

/**
 * The SIP account's addresses (decision 70): the identity is the tenant's
 * domain, and every request, REGISTER included, goes to the edge's outbound
 * proxy over TLS.
 *
 * liblinphone 5.5.39 sends REGISTER to the account's *server address*
 * (`SalRegisterOp::sendRegister` replaces the op's routes with it); the
 * account's routes apply only to other requests. So the server address is
 * the outbound proxy, and "outbound proxy enabled" makes it the single route
 * for calls, SUBSCRIBE and the rest. The Request-URI stays the tenant
 * domain (liblinphone builds it from the identity), the TLS connection and
 * its name check go to the proxy's host, and the RFC 8599 push parameters
 * ride on the REGISTER's Contact, so they take the same path.
 *
 * Pure, so it runs in JVM tests; [LinphoneEngine] applies it through [Params].
 */
object AccountSetup {

    data class Plan(
        /** `sip:<authUsername>@<domain>`: From, To and the Request-URI's domain. */
        val identity: String,
        /** The outbound proxy, `sip:<host>[:<port>];transport=tls`: where REGISTER and every request go. */
        val server: String,
        /** The host the TLS certificate is checked against. */
        val tlsHost: String,
    )

    /** The account params liblinphone needs from [Plan]. */
    interface Params {
        fun setIdentity(uri: String, displayName: String)
        fun setServer(uri: String)
        var outboundProxyEnabled: Boolean
    }

    private val PROXY = Regex("""^<?(sips?):(?:[^@;>]*@)?(\[[0-9A-Fa-f:.]+]|[A-Za-z0-9.-]+)(?::(\d{1,5}))?(?:;[^>]*)?>?$""")
    private val USER = Regex("""^[A-Za-z0-9._~!$&'()*+,=-]+$""")
    private val DOMAIN = Regex("""^[A-Za-z0-9.-]+$""")

    /**
     * The plan for an account, or null if the outbound proxy, user or domain
     * is unusable (the engine refuses rather than send REGISTER anywhere
     * else). `sips:` and any other transport become `sip:` with
     * `transport=tls`, as decision 70 says; the port is kept.
     */
    fun plan(authUsername: String, sipDomain: String, outboundProxy: String): Plan? {
        if (!USER.matches(authUsername) || !DOMAIN.matches(sipDomain)) return null
        val m = PROXY.matchEntire(outboundProxy.trim()) ?: return null
        val host = m.groupValues[2]
        val port = m.groupValues[3]
        if (port.isNotEmpty() && port.toInt() !in 1..65535) return null
        val server = buildString {
            append("sip:").append(host)
            if (port.isNotEmpty()) append(':').append(port)
            append(";transport=tls")
        }
        return Plan("sip:$authUsername@$sipDomain", server, host.trim('[', ']'))
    }

    /**
     * The REGISTER expiry from the API's `expiresSeconds` (the only source,
     * decision 170), kept within [MIN_EXPIRES_S]..[MAX_EXPIRES_S]: up to 7
     * days, what the edge grants a contact with push parameters.
     */
    fun expires(expiresSeconds: Long): Int = expiresSeconds.coerceIn(MIN_EXPIRES_S.toLong(), MAX_EXPIRES_S.toLong()).toInt()

    const val MIN_EXPIRES_S = 60
    const val MAX_EXPIRES_S = 604_800

    /** Server address before outbound proxy: liblinphone makes the server address the route. */
    fun apply(plan: Plan, displayName: String, params: Params) {
        params.setIdentity(plan.identity, displayName)
        params.setServer(plan.server)
        params.outboundProxyEnabled = true
    }
}
