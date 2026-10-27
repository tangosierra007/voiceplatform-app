package au.com.voiceplatform.vp_linphone

import org.linphone.core.Call
import org.linphone.core.MediaEncryption

/**
 * APP13: every app call's audio is SRTP. SDES keys (RFC 4568, `a=crypto`) as
 * spec 22 and the edge use, never optional: the SDP offers RTP/SAVP only, never
 * RTP/AVP, and a call that would carry plain RTP is refused or ended.
 *
 * Pure, so the policy and the decision run in JVM unit tests. [LinphoneEngine]
 * applies them to the Core and to every call's params through [Settings].
 */
object MediaSecurity {

    /** The only media encryption an app call may use. */
    val REQUIRED: MediaEncryption = MediaEncryption.SRTP

    /** The media-encryption knobs of a liblinphone Core or a call's params. */
    interface Settings {
        var encryption: MediaEncryption

        /**
         * RFC 5939 capability negotiation. Off: with it on, liblinphone may put
         * RTP/AVP on the m-line and offer SRTP only as a potential config.
         */
        var capabilityNegotiation: Boolean
    }

    /** A Core's knobs: also whether encryption is mandatory, and what the build supports. */
    interface CoreSettings : Settings {
        var mandatory: Boolean
        fun supports(encryption: MediaEncryption): Boolean
    }

    /** SRTP is not in this liblinphone build: the engine refuses to start rather than run plain RTP. */
    class Unavailable : IllegalStateException("SRTP is not available in this liblinphone build (APP13)")

    /** Core set-up: SRTP, mandatory, no capability negotiation. Throws [Unavailable] if SRTP is missing. */
    fun applyToCore(core: CoreSettings) {
        if (!core.supports(REQUIRED)) throw Unavailable()
        core.encryption = REQUIRED
        core.mandatory = true
        core.capabilityNegotiation = false
    }

    /** Every outgoing INVITE's and every answer's params. */
    fun applyToCall(params: Settings) {
        params.encryption = REQUIRED
        params.capabilityNegotiation = false
    }

    /** True when a Core is set up as [applyToCore] leaves it; calls are refused otherwise. */
    fun coreCompliant(encryption: MediaEncryption?, mandatory: Boolean): Boolean =
        encryption == REQUIRED && mandatory

    enum class Verdict {
        /** Media is SRTP, or this state carries no negotiated media to check. */
        ALLOW,

        /** Media was negotiated without SRTP: end the call (end reason `failed`). */
        END,
    }

    /**
     * The state where the call's media has been negotiated and is running, so
     * `currentParams.mediaEncryption` must be [REQUIRED]. Every negotiation
     * that leads to audio ends here: an outgoing call's answer, an incoming
     * call's answer (late offer included), and every accepted re-INVITE or
     * UPDATE (a resume from hold too). So this covers an answer without
     * crypto and a re-INVITE that dropped it. liblinphone itself, with
     * encryption mandatory, answers 488 to an offer without crypto and never
     * sends unencrypted RTP; this is the engine's own check on top.
     */
    fun checksMedia(state: Call.State): Boolean = state == Call.State.StreamsRunning

    /** [current] is `call.currentParams?.mediaEncryption`; unknown counts as plain. */
    fun verdict(state: Call.State, current: MediaEncryption?): Verdict =
        if (checksMedia(state) && current != REQUIRED) Verdict.END else Verdict.ALLOW

    /** SIP 488 Not Acceptable Here: what liblinphone answers to an offer without crypto. */
    const val NOT_ACCEPTABLE = 488
}
