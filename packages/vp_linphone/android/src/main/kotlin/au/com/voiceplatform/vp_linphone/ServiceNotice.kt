package au.com.voiceplatform.vp_linphone

/**
 * What the engine's foreground service shows, and with which types, for the
 * calls there are. One notification at a time:
 *
 * - no call: "Ready for calls";
 * - an outgoing call not yet answered: "Calling";
 * - an incoming call ringing, once its notification is built: the
 *   incoming-call notification itself (CallStyle, ringtone channel,
 *   full-screen intent) becomes the service's notification, so there is no
 *   second one beside it. As a foreground service notification its
 *   CallStyle is valid even when Android 14+ refuses the full-screen intent,
 *   and Android then shows it as a sticky heads-up;
 * - a call connected, held or being transferred: "Call in progress".
 *   Another call ringing meanwhile (call waiting) gets its own notification.
 *
 * The type is always `phoneCall`; `microphone` is added only while a call is
 * up and RECORD_AUDIO is granted (it may be refused while the app is in the
 * background, before an answer).
 *
 * Pure, so it runs in JVM tests; [EngineService] applies it.
 */
object ServiceNotice {

    enum class Kind { READY, CALLING, INCOMING, IN_CALL }

    data class Notice(val kind: Kind, val callId: String? = null, val microphone: Boolean = false)

    /** [answering]: Answer from the notification is on its way (the call is still INCOMING). */
    data class Call(val id: String, val incoming: Boolean, val state: CallStateMsg, val answering: Boolean = false)

    private val UP = setOf(
        CallStateMsg.CONNECTED,
        CallStateMsg.HELD_BY_ME,
        CallStateMsg.HELD_BY_REMOTE,
        CallStateMsg.TRANSFERRING,
    )

    /**
     * [calls] in the order they started; [ringing] are the calls whose
     * incoming-call notification has been built (Telecom asked to show it).
     */
    fun decide(calls: List<Call>, micGranted: Boolean, ringing: Set<String>): Notice {
        val live = calls.filter { it.state != CallStateMsg.ENDED }
        // An answered call stays "Call in progress" while its notification goes.
        if (live.any { it.state in UP || (it.state == CallStateMsg.INCOMING && it.answering) }) {
            return Notice(Kind.IN_CALL, microphone = micGranted)
        }
        live.firstOrNull { it.state == CallStateMsg.INCOMING && it.id in ringing }?.let {
            return Notice(Kind.INCOMING, it.id)
        }
        if (live.any { !it.incoming && (it.state == CallStateMsg.DIALLING || it.state == CallStateMsg.RINGING) }) {
            return Notice(Kind.CALLING)
        }
        return Notice(Kind.READY)
    }

    /**
     * Answer from the notification failed: if that call still rings, its
     * notification (taken away by the Answer tap) is shown again.
     */
    fun reshowAfterFailedAnswer(wasAnswering: Boolean, state: CallStateMsg): Boolean =
        wasAnswering && state == CallStateMsg.INCOMING

    /**
     * Put up while the app's notifications were off (Android ran the service
     * but showed nothing) and allowed now: put up again, so "Ready for calls"
     * shows without waiting for a call to change it (FU81).
     */
    fun needsRepost(postedHidden: Boolean, allowedNow: Boolean): Boolean = postedHidden && allowedNow

    /** How [show] put the service in the foreground. */
    enum class Shown { WITH_MICROPHONE, PLAIN, FAILED }

    /**
     * Calls [start] (startForeground with or without the microphone type),
     * dropping the microphone type if Android refuses it, and reports
     * [Shown.FAILED] rather than throwing if even the plain phoneCall type is
     * refused: a ringing call then falls back to a posted notification.
     */
    fun show(microphone: Boolean, start: (microphone: Boolean) -> Unit): Shown {
        if (microphone) {
            try {
                start(true)
                return Shown.WITH_MICROPHONE
            } catch (_: RuntimeException) {
                // The microphone type is refused while the app is in the background.
            }
        }
        return try {
            start(false)
            Shown.PLAIN
        } catch (_: RuntimeException) {
            Shown.FAILED
        }
    }
}
