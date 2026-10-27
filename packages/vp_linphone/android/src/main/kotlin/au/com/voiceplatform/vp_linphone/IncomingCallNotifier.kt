package au.com.voiceplatform.vp_linphone

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person

/**
 * The incoming-call notification: CallStyle with Answer and Decline, ringing
 * on the ringtone channel, and a full-screen intent to the app's activity so a
 * locked phone shows the incoming screen (WS4's AppIncoming, reached through
 * VpLinphoneEngine.uiRequests). On Android 14+ without the full-screen intent
 * permission it falls back to a heads-up notification and reports it.
 *
 * No caller facts beyond the name or number the screen shows (APP5).
 */
object IncomingCallNotifier {
    private const val CHANNEL_ID = "vp_linphone_incoming"
    private const val CHANNEL_SILENT_ID = "vp_linphone_incoming_silent"
    const val EXTRA_ACTION = "au.com.voiceplatform.vp_linphone.ACTION"
    const val ACTION_SHOW_INCOMING = "show_incoming"
    const val ACTION_ANSWER = "answer"
    const val ACTION_SHOW_CALL = "show_call"

    fun canUseFullScreenIntent(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        return context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
    }

    private fun channels(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        val ring = NotificationChannel(CHANNEL_ID, context.getString(R.string.vp_linphone_incoming_channel), NotificationManager.IMPORTANCE_HIGH)
        ring.setSound(
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        ring.enableVibration(true)
        ring.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        val silent = NotificationChannel(CHANNEL_SILENT_ID, context.getString(R.string.vp_linphone_incoming_silent_channel), NotificationManager.IMPORTANCE_HIGH)
        silent.setSound(null, null)
        silent.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        nm.createNotificationChannels(listOf(ring, silent))
    }

    fun activityIntent(context: Context, action: String, callId: String): PendingIntent? {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        launch.putExtra(EXTRA_ACTION, action)
        launch.putExtra(TelecomBridge.EXTRA_CALL_ID, callId)
        return PendingIntent.getActivity(
            context,
            requestCode(callId, action),
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    fun show(context: Context, info: TelecomBridge.CallInfo, silent: Boolean = false) {
        channels(context)
        val title = info.name ?: info.number
        val person = Person.Builder().setName(title).setImportant(true).build()
        val content = activityIntent(context, ACTION_SHOW_INCOMING, info.callId) ?: return
        val answer = activityIntent(context, ACTION_ANSWER, info.callId) ?: return
        val decline = PendingIntent.getBroadcast(
            context,
            requestCode(info.callId, "decline"),
            Intent(context, CallActionReceiver::class.java)
                .setAction(CallActionReceiver.ACTION_DECLINE)
                .putExtra(TelecomBridge.EXTRA_CALL_ID, info.callId),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val fullScreen = canUseFullScreenIntent(context)
        val builder = NotificationCompat.Builder(context, if (silent) CHANNEL_SILENT_ID else CHANNEL_ID)
            .setSmallIcon(R.drawable.vp_linphone_ic_call)
            .setContentTitle(title)
            .setContentText(context.getString(R.string.vp_linphone_incoming_text))
        if (fullScreen) {
            builder.setStyle(NotificationCompat.CallStyle.forIncomingCall(person, decline, answer))
        } else {
            // Android refuses a CallStyle notification without a full-screen intent
            // (or a foreground service of its own): plain heads-up with two actions.
            builder.addAction(0, context.getString(R.string.vp_linphone_decline), decline)
            builder.addAction(0, context.getString(R.string.vp_linphone_answer), answer)
        }
        builder
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(content)
        if (fullScreen) {
            builder.setFullScreenIntent(content, true)
        } else {
            LinphoneEngine.logLine("TELECOM", "full-screen intent not allowed; heads-up only")
            TelecomBridge.uiListener?.onFullScreenIntentDenied(info.callId)
        }
        val n = builder.build()
        if (!silent) n.flags = n.flags or Notification.FLAG_INSISTENT
        try {
            NotificationManagerCompat.from(context).notify(notificationId(info.callId), n)
        } catch (e: RuntimeException) {
            // POST_NOTIFICATIONS refused (SecurityException) or the system refused the
            // style (IllegalArgumentException): Telecom still knows the call.
            LinphoneEngine.logLine("TELECOM", "incoming notification refused: ${e.javaClass.simpleName}")
        }
    }

    /** The ringer was silenced (volume key): same notification, no sound. */
    fun silence(context: Context, info: TelecomBridge.CallInfo) = show(context, info, silent = true)

    fun cancel(context: Context, callId: String) {
        NotificationManagerCompat.from(context).cancel(notificationId(callId))
    }

    private fun notificationId(callId: String) = 0x5700 + (callId.hashCode() and 0xff)
    private fun requestCode(callId: String, action: String) = (callId + action).hashCode()
}

/** The Decline button of the incoming-call notification. */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val callId = intent.getStringExtra(TelecomBridge.EXTRA_CALL_ID) ?: return
        if (intent.action == ACTION_DECLINE) TelecomBridge.declineFromNotification(context, callId)
    }

    companion object {
        const val ACTION_DECLINE = "au.com.voiceplatform.vp_linphone.DECLINE"
    }
}
