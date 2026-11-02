package au.com.voiceplatform.vp_linphone

import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.ToneGenerator
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person

/**
 * The incoming-call notification: CallStyle with Answer and Decline, ringing
 * on the ringtone channel, and a full-screen intent to the app's activity so a
 * locked phone shows the incoming screen (WS4's AppIncoming, reached through
 * VpLinphoneEngine.uiRequests). The same notification in every state (see
 * [IncomingSpec]); on Android 14+ without full-screen access Android shows it
 * as a sticky heads-up, and the app is told (onFullScreenIntentDenied).
 *
 * No caller facts beyond the name or number the screen shows (APP5).
 */
object IncomingCallNotifier {
    private const val CHANNEL_ID = IncomingSpec.CHANNEL_RING
    private const val CHANNEL_SILENT_ID = IncomingSpec.CHANNEL_SILENT
    const val EXTRA_ACTION = "au.com.voiceplatform.vp_linphone.ACTION"
    const val ACTION_SHOW_INCOMING = "show_incoming"
    const val ACTION_ANSWER = "answer"
    const val EXTRA_TOKEN = "au.com.voiceplatform.vp_linphone.TOKEN"

    /** Tokens for this process's notifications (see [CallActionGate]). */
    val gate = CallActionGate()

    fun canUseFullScreenIntent(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        return context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
    }

    /** For the log and [IncomingSpec] (which gives the same notification in every state). */
    private fun appState(context: Context): IncomingSpec.AppState {
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        if (keyguard?.isKeyguardLocked == true) return IncomingSpec.AppState.LOCKED
        val info = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(info)
        return when {
            info.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND -> IncomingSpec.AppState.FOREGROUND
            else -> IncomingSpec.AppState.BACKGROUND // or started by a push after the app was swiped away
        }
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
        // A second call while one is up: heads-up with Answer and Decline, no
        // ringtone or vibration over the call; one call-waiting tone instead.
        val waiting = NotificationChannel(IncomingSpec.CHANNEL_WAITING, context.getString(R.string.vp_linphone_incoming_waiting_channel), NotificationManager.IMPORTANCE_HIGH)
        waiting.setSound(null, null)
        waiting.enableVibration(false)
        waiting.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        nm.createNotificationChannels(listOf(ring, silent, waiting))
    }

    /**
     * The app's launcher activity with the non-exported [CallActionActivity]
     * (and the call's token) on top, started together by the system from the
     * notification: the token is checked on top, and the app's activity is
     * already there underneath when it finishes. No activity is started from
     * the background, which Android 10+ blocks (the trampoline's own
     * `startActivity` was refused on a locked phone).
     */
    private fun activityIntent(context: Context, action: String, callId: String, token: String): PendingIntent {
        val gate = Intent(context, CallActionActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
            .putExtra(EXTRA_ACTION, action)
            .putExtra(TelecomBridge.EXTRA_CALL_ID, callId)
            .putExtra(EXTRA_TOKEN, token)
        val app = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        return if (app != null) {
            PendingIntent.getActivities(context, requestCode(callId, action), arrayOf(app, gate), flags)
        } else {
            PendingIntent.getActivity(context, requestCode(callId, action), gate.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), flags)
        }
    }

    fun show(context: Context, info: TelecomBridge.CallInfo, silent: Boolean = false) {
        channels(context)
        val title = info.name ?: info.number
        val person = Person.Builder().setName(title).setImportant(true).build()
        val token = gate.issue(info.callId)
        val content = activityIntent(context, ACTION_SHOW_INCOMING, info.callId, token)
        val answer = activityIntent(context, ACTION_ANSWER, info.callId, token)
        val decline = PendingIntent.getBroadcast(
            context,
            requestCode(info.callId, "decline"),
            Intent(context, CallActionReceiver::class.java)
                .setAction(CallActionReceiver.ACTION_DECLINE)
                .putExtra(TelecomBridge.EXTRA_CALL_ID, info.callId)
                .putExtra(EXTRA_TOKEN, token),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        // Always CallStyle with a full-screen intent. If Android 14+ refuses the
        // full-screen intent, it keeps the notification, marks it "requested but
        // denied" and shows it as a sticky heads-up; the CallStyle stays valid.
        // As the engine service's foreground notification ([RingHost]) it is
        // valid either way.
        val fullScreen = canUseFullScreenIntent(context)
        val state = appState(context)
        val isWaiting = LinphoneEngine.hasOtherCallUp(info.callId)
        if (isWaiting) waitingCalls[info.callId] = info else waitingCalls.remove(info.callId)
        val spec = IncomingSpec.spec(silent, isWaiting)
        val n = build(context, spec, title, person, content, answer, decline)
        if (!fullScreen) {
            LinphoneEngine.logLine("TELECOM", "full-screen intent not allowed; sticky heads-up")
            TelecomBridge.uiListener?.onFullScreenIntentDenied(info.callId)
        }
        val id = notificationId(info.callId)
        val viaService = ringHost?.ring(info.callId, id, n) == true
        LinphoneEngine.logLine(
            "TELECOM",
            "incoming notification: app $state, ${if (isWaiting) "waiting" else "ringing"}, full-screen ${if (fullScreen) "allowed" else "denied"}, " +
                if (viaService) "as the service notification" else "posted",
        )
        if (spec.waitingTone) playWaitingTone()
        if (viaService) return
        try {
            NotificationManagerCompat.from(context).notify(id, n)
        } catch (e: RuntimeException) {
            // POST_NOTIFICATIONS refused (SecurityException) or the system refused the
            // style (IllegalArgumentException): Telecom still knows the call.
            LinphoneEngine.logLine("TELECOM", "incoming notification refused: ${e.javaClass.simpleName}")
        }
    }

    /** Calls shown as waiting, by id: they ring properly once no other call is up. */
    private val waitingCalls = HashMap<String, TelecomBridge.CallInfo>()

    /**
     * After a call ends: a call that was waiting and now has no other call
     * up rings like any incoming call (ringtone channel, as the service
     * notification).
     */
    fun ringWaitingCalls(context: Context) {
        for ((id, info) in waitingCalls.toList()) {
            if (LinphoneEngine.callState(id) == CallStateMsg.INCOMING && !LinphoneEngine.hasOtherCallUp(id)) show(context, info)
        }
    }

    /** One call-waiting tone in the call's audio; never fatal. */
    private fun playWaitingTone() {
        try {
            val tone = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 60)
            tone.startTone(ToneGenerator.TONE_SUP_CALL_WAITING, 1500)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ tone.release() }, 2000)
        } catch (e: RuntimeException) {
            LinphoneEngine.logLine("TELECOM", "call-waiting tone failed: ${e.javaClass.simpleName}")
        }
    }

    /** The ringer was silenced (volume key): same notification, no sound. */
    fun silence(context: Context, info: TelecomBridge.CallInfo) = show(context, info, silent = true)

    fun cancel(context: Context, callId: String) {
        gate.forget(callId)
        waitingCalls.remove(callId)
        // First move the service's foreground off it, then remove it.
        ringHost?.unring(callId)
        NotificationManagerCompat.from(context).cancel(notificationId(callId))
    }

    /**
     * The incoming-call notification: CallStyle.forIncomingCall, the ringtone
     * channel (high importance) or its silent twin, CATEGORY_CALL, public on
     * the lock screen, and the full-screen intent to the incoming screen.
     */
    internal fun build(
        context: Context,
        spec: IncomingSpec.Spec,
        title: String,
        person: Person,
        content: PendingIntent,
        answer: PendingIntent,
        decline: PendingIntent,
    ): Notification {
        check(spec.buttons == listOf(IncomingSpec.Button.DECLINE, IncomingSpec.Button.ANSWER))
        val b = NotificationCompat.Builder(context, spec.channel)
            .setSmallIcon(R.drawable.vp_linphone_ic_call)
            .setContentTitle(title)
            .setContentText(context.getString(R.string.vp_linphone_incoming_text))
            .setStyle(NotificationCompat.CallStyle.forIncomingCall(person, decline, answer))
            .setCategory(spec.category)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(if (spec.publicOnLockScreen) NotificationCompat.VISIBILITY_PUBLIC else NotificationCompat.VISIBILITY_PRIVATE)
            .setOngoing(spec.ongoing)
            .setAutoCancel(false)
            .setContentIntent(content)
        if (spec.fullScreenIntent) b.setFullScreenIntent(content, true)
        val n = b.build()
        if (spec.insistent) n.flags = n.flags or Notification.FLAG_INSISTENT
        return n
    }

    /** The engine's foreground service, which shows a ringing call's notification as its own. */
    interface RingHost {
        /** True if the service now shows [notification] as its foreground notification. */
        fun ring(callId: String, notificationId: Int, notification: Notification): Boolean
        fun unring(callId: String)
    }

    @Volatile
    var ringHost: RingHost? = null

    private fun notificationId(callId: String) = 0x5700 + (callId.hashCode() and 0xff)
    private fun requestCode(callId: String, action: String) = (callId + action).hashCode()
}

/** The Decline button of the incoming-call notification. */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val callId = intent.getStringExtra(TelecomBridge.EXTRA_CALL_ID) ?: return
        val token = intent.getStringExtra(IncomingCallNotifier.EXTRA_TOKEN)
        if (intent.action != ACTION_DECLINE) return
        if (!IncomingCallNotifier.gate.authorise(CallActionGate.Action.DECLINE, callId, token)) {
            LinphoneEngine.logLine("TELECOM", "decline refused: bad or used token")
            return
        }
        TelecomBridge.declineFromNotification(context, callId)
    }

    companion object {
        const val ACTION_DECLINE = "au.com.voiceplatform.vp_linphone.DECLINE"
    }
}
