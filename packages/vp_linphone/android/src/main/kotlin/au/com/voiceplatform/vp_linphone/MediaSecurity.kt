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
     * The states in which audio can flow, so `currentParams.mediaEncryption`
     * must be [REQUIRED]:
     * - [Call.State.StreamsRunning]: an outgoing call's answer, an incoming
     *   call's answer (late offer included), and every accepted re-INVITE or
     *   UPDATE that leaves the call active (a resume from hold too);
     * - [Call.State.OutgoingEarlyMedia]: a 183 with SDP, whose early media
     *   (ringback, announcements) plays before any answer;
     * - [Call.State.PausedByRemote]: a remote hold, where music on hold may
     *   play; it does not pass through StreamsRunning.
     *
     * Not [Call.State.Connected]: the streams have not started there, and
     * SDES reads None until they have, so checking it would end every call.
     * Audio cannot flow until one of the checked states follows. liblinphone
     * itself, with encryption mandatory, answers 488 to an offer without
     * crypto and never sends unencrypted RTP; this is the engine's own check
     * on top.
     */
    fun checksMedia(state: Call.State): Boolean = state in CHECKED_STATES

    /** The states [checksMedia] checks. */
    val CHECKED_STATES: Set<Call.State> = setOf(
        Call.State.StreamsRunning,
        Call.State.OutgoingEarlyMedia,
        Call.State.PausedByRemote,
    )

    /** [current] is `call.currentParams?.mediaEncryption`; unknown counts as plain. */
    fun verdict(state: Call.State, current: MediaEncryption?): Verdict =
        if (checksMedia(state) && current != REQUIRED) Verdict.END else Verdict.ALLOW

    /** How [endInsecure] got the call ending. */
    enum class Ending {
        /** `call.terminate()` accepted. */
        TERMINATED,

        /** `terminate()` refused, so every call on the Core was ended. */
        ALL_TERMINATED,

        /** Both refused: the engine reports an error and checks again at the next state. */
        FAILED,
    }

    /**
     * Ends a call whose media is not SRTP. If liblinphone refuses to end
     * that one call, it ends every call on the Core rather than leave plain
     * media up. The engine runs the check at every later state until the
     * call has ended, whatever this returns.
     */
    fun endInsecure(terminate: () -> Int, terminateAll: () -> Int): Ending = when {
        terminate() == 0 -> Ending.TERMINATED
        terminateAll() == 0 -> Ending.ALL_TERMINATED
        else -> Ending.FAILED
    }

    /** SIP 488 Not Acceptable Here: what liblinphone answers to an offer without crypto. */
    const val NOT_ACCEPTABLE = 488
}
