package au.com.voiceplatform.vp_linphone

/**
 * What the incoming-call notification is, whatever state the app and phone
 * are in. A locked or backgrounded phone answers from this notification, so
 * it always has Answer and Decline (CallStyle.forIncomingCall), CATEGORY_CALL,
 * the high-importance ringtone channel (or its silent twin after the volume
 * key), public on the lock screen, and a full-screen intent. Nothing about it
 * depends on whether Android allows the full-screen intent: if it doesn't,
 * Android shows the same notification as a sticky heads-up.
 *
 * Pure, so the rule runs in JVM tests; [IncomingCallNotifier.build] turns it
 * into the Android notification.
 */
object IncomingSpec {

    enum class AppState { KILLED, BACKGROUND, LOCKED, FOREGROUND }

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
    )

    const val CHANNEL_RING = "vp_linphone_incoming"
    const val CHANNEL_SILENT = "vp_linphone_incoming_silent"

    /** NotificationCompat.CATEGORY_CALL. */
    const val CATEGORY_CALL = "call"

    @Suppress("UNUSED_PARAMETER")
    fun spec(app: AppState, fullScreenAllowed: Boolean, silent: Boolean): Spec = Spec(
        channel = if (silent) CHANNEL_SILENT else CHANNEL_RING,
        buttons = listOf(Button.DECLINE, Button.ANSWER),
        category = CATEGORY_CALL,
        fullScreenIntent = true,
        publicOnLockScreen = true,
        ongoing = true,
        insistent = !silent,
    )
}
