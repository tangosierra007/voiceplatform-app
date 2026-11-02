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

    data class Call(val id: String, val incoming: Boolean, val state: CallStateMsg)

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
        if (live.any { it.state in UP }) return Notice(Kind.IN_CALL, microphone = micGranted)
        live.firstOrNull { it.state == CallStateMsg.INCOMING && it.id in ringing }?.let {
            return Notice(Kind.INCOMING, it.id)
        }
        if (live.any { !it.incoming && (it.state == CallStateMsg.DIALLING || it.state == CallStateMsg.RINGING) }) {
            return Notice(Kind.CALLING)
        }
        return Notice(Kind.READY)
    }
}
