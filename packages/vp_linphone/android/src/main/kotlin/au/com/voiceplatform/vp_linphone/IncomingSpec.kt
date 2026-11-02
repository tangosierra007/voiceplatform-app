package au.com.voiceplatform.vp_linphone

/**
 * What the incoming-call notification is. A locked or backgrounded phone
 * answers from it, so it always has Answer and Decline
 * (CallStyle.forIncomingCall), CATEGORY_CALL, a high-importance channel,
 * public on the lock screen, and a full-screen intent.
 *
 * Deliberately not an input: the app's state (killed, backgrounded, locked,
 * in front) and whether Android allows the full-screen intent. If it doesn't,
 * Android shows the same notification as a sticky heads-up. The only inputs
 * are how it sounds:
 * - ringing: the ringtone channel, insistent;
 * - silenced (the volume key): the silent channel;
 * - waiting (another call is up): the call-waiting channel, no ringtone and
 *   no vibration, plus one call-waiting tone in the call's audio.
 *
 * Pure, so the rule runs in JVM tests; [IncomingCallNotifier.build] turns it
 * into the Android notification.
 */
object IncomingSpec {

    /** For the call log only: the notification is the same in every state. */
    enum class AppState { BACKGROUND, LOCKED, FOREGROUND }

    enum class Button { DECLINE, ANSWER }

    data class Spec(
        val channel: String,
        /** CallStyle.forIncomingCall with these buttons, Decline first as Android draws them. */
        val buttons: List<Button>,
        val category: String,
        val fullScreenIntent: Boolean,
        val publicOnLockScreen: Boolean,
        val ongoing: Boolean,
        /** Rings until answered, declined or silenced. */
        val insistent: Boolean,
        /** Play the call-waiting tone once. */
        val waitingTone: Boolean,
    )

    const val CHANNEL_RING = "vp_linphone_incoming"
    const val CHANNEL_SILENT = "vp_linphone_incoming_silent"
    const val CHANNEL_WAITING = "vp_linphone_incoming_waiting"

    /** NotificationCompat.CATEGORY_CALL. */
    const val CATEGORY_CALL = "call"

    fun spec(silent: Boolean, waiting: Boolean): Spec = Spec(
        channel = when {
            waiting -> CHANNEL_WAITING
            silent -> CHANNEL_SILENT
            else -> CHANNEL_RING
        },
        buttons = listOf(Button.DECLINE, Button.ANSWER),
        category = CATEGORY_CALL,
        fullScreenIntent = true,
        publicOnLockScreen = true,
        ongoing = true,
        insistent = !silent && !waiting,
        waitingTone = waiting && !silent,
    )
}
