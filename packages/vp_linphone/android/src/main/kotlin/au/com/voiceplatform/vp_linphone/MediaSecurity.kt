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
     * When each is judged is [checkAt]'s business. Not [Call.State.Connected]:
     * the streams have not started there, and SDES reads None until they
     * have, so checking it would end every call. Audio cannot flow until one
     * of the checked states follows. liblinphone itself, with encryption
     * mandatory, answers 488 to an offer without crypto and never sends
     * unencrypted RTP; this is the engine's own check on top.
     */
    fun checksMedia(state: Call.State): Boolean = state in CHECKED_STATES

    /** The states [checksMedia] checks. */
    val CHECKED_STATES: Set<Call.State> = setOf(
        Call.State.StreamsRunning,
        Call.State.OutgoingEarlyMedia,
        Call.State.PausedByRemote,
    )

    /** When a state's media is judged. */
    enum class Check {
        /** In the state callback: the streams were updated before the state was set. */
        NOW,

        /**
         * After the state callback has returned (posted to the main thread).
         * For [Call.State.OutgoingEarlyMedia], liblinphone (`remoteRinging()`)
         * sets the state before `updateStreams()`, and the SDES encryption
         * reaches `currentParams` only once a stream has started: in the
         * callback it still reads None on a good call.
         */
        AFTER_STREAMS_START,

        /** Not checked. */
        NONE,
    }

    fun checkAt(state: Call.State): Check = when {
        state == Call.State.OutgoingEarlyMedia -> Check.AFTER_STREAMS_START
        state in CHECKED_STATES -> Check.NOW
        else -> Check.NONE
    }

    /**
     * Runs the check for [state] at the time [checkAt] gives. [judge] ends the
     * call if its media is not SRTP and returns true if it did. [post] runs a
     * task on the main thread after the current callback has returned.
     * [stateNow] is the call's state when the posted task runs, or null if
     * the call is no longer tracked or has ended; the posted check judges
     * that state if it is a checked one (early media still, or a later one).
     * True only when the call is being ended now, so [state] is not shown.
     */
    fun runCheck(
        state: Call.State,
        post: (Runnable) -> Unit,
        stateNow: () -> Call.State?,
        judge: (Call.State) -> Boolean,
    ): Boolean = when (checkAt(state)) {
        Check.NOW -> judge(state)
        Check.AFTER_STREAMS_START -> {
            post(Runnable {
                val now = stateNow()
                if (now != null && checksMedia(now)) judge(now)
            })
            false
        }
        Check.NONE -> false
    }

    /** [current] is `call.currentParams?.mediaEncryption`; unknown counts as plain. */
    fun verdict(state: Call.State, current: MediaEncryption?): Verdict =
        if (checksMedia(state) && current != REQUIRED) Verdict.END else Verdict.ALLOW

    /** States in which liblinphone has ended the call. */
    val ENDED_STATES: Set<Call.State> = setOf(Call.State.End, Call.State.Error, Call.State.Released)

    /** How [endInsecure] got the call ending. */
    enum class Ending {
        /** `call.terminate()` accepted. */
        TERMINATED,

        /** `terminate()` refused, but the call had ended meanwhile: nothing to escalate. */
        ALREADY_ENDED,

        /** `terminate()` refused, so every call on the Core was ended. */
        ALL_TERMINATED,

        /** Both refused: the engine reports an error and tries again. */
        FAILED,
    }

    /**
     * Ends a call whose media is not SRTP. If liblinphone refuses to end
     * that one call and it has not ended ([stateNow] re-read: End, Error,
     * Released or unknown), it ends every call on the Core rather than leave
     * plain media up; [beforeTerminateAll] runs first (the engine marks the
     * other calls so their end reason is `failed` too).
     */
    fun endInsecure(
        terminate: () -> Int,
        stateNow: () -> Call.State?,
        beforeTerminateAll: () -> Unit,
        terminateAll: () -> Int,
    ): Ending {
        if (terminate() == 0) return Ending.TERMINATED
        val now = stateNow()
        if (now == null || now in ENDED_STATES) return Ending.ALREADY_ENDED
        beforeTerminateAll()
        return if (terminateAll() == 0) Ending.ALL_TERMINATED else Ending.FAILED
    }

    /** At most one pending retry per call, however many states ask for one. */
    class Retry {
        var pending = false
            private set

        /** Posts [run] with [post] unless a retry is already pending; true if it posted. */
        fun schedule(post: (Runnable) -> Unit, run: () -> Unit): Boolean {
            if (pending) return false
            pending = true
            post(Runnable {
                pending = false
                run()
            })
            return true
        }
    }

    /** SIP 488 Not Acceptable Here: what liblinphone answers to an offer without crypto. */
    const val NOT_ACCEPTABLE = 488
}
