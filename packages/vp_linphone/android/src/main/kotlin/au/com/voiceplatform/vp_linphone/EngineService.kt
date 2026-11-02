package au.com.voiceplatform.vp_linphone

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat

/**
 * The foreground service that owns the liblinphone Core. Type `phoneCall`
 * while it runs, plus `microphone` while a call is up and RECORD_AUDIO is
 * granted. Started by CallEngine.start(), stopped by CallEngine.stop(); not
 * sticky (credentials are in memory only, so a restarted service would have
 * nothing to register with; 3.2 wakes it from FCM instead).
 *
 * Its notification follows the calls ([ServiceNotice]): "Ready for calls",
 * "Calling", the incoming-call notification itself while one rings, or
 * "Call in progress" once a call is up. Never two at once for one call.
 */
class EngineService : Service(), IncomingCallNotifier.RingHost {

    private var calls: List<ServiceNotice.Call> = emptyList()
    private var micGranted = false

    /** Incoming-call notifications built for ringing calls: id and notification. */
    private val ringing = LinkedHashMap<String, Pair<Int, Notification>>()

    /** What is in the foreground now, and the incoming notification it is, if one. */
    private var shown: ServiceNotice.Notice? = null
    private var shownRing: Notification? = null

    override fun onCreate() {
        super.onCreate()
        EngineStartup.run(
            // First, before anything else can throw: the notification and
            // startForeground with the plain phoneCall type.
            goForeground = {
                createChannel()
                apply(strict = true)
            },
            // Then liblinphone: native libraries, the Core, its start.
            setUp = {
                IncomingCallNotifier.ringHost = this
                LinphoneEngine.onServiceCreated(this)
            },
            report = { LinphoneEngine.onServiceStartFailed(it) },
            stop = { stopSelf() },
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        if (IncomingCallNotifier.ringHost === this) IncomingCallNotifier.ringHost = null
        LinphoneEngine.onServiceDestroyed()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    /** Called by the engine on every call change. */
    fun update(calls: List<ServiceNotice.Call>, micGranted: Boolean) {
        this.calls = calls
        this.micGranted = micGranted
        apply()
    }

    override fun ring(callId: String, notificationId: Int, notification: Notification): Boolean {
        ringing[callId] = notificationId to notification
        if (!apply()) return false
        return shown?.kind == ServiceNotice.Kind.INCOMING && shown?.callId == callId
    }

    override fun unring(callId: String) {
        if (ringing.remove(callId) != null) apply()
    }

    /**
     * Puts the notice for the calls in the foreground. False if Android
     * refused startForeground even without the microphone type: what was
     * shown stays, and a ringing call's notification is posted by
     * [IncomingCallNotifier] instead. [strict] (service start) throws then.
     */
    private fun apply(strict: Boolean = false): Boolean {
        val notice = ServiceNotice.decide(calls, micGranted, ringing.keys)
        val ring = notice.callId?.let { ringing[it] }
        if (notice == shown && ring?.second === shownRing) return true
        val before = shown
        val result = ServiceNotice.show(notice.microphone) { mic ->
            if (notice.kind == ServiceNotice.Kind.INCOMING && ring != null) {
                startForeground(ring.first, ring.second, mic)
            } else {
                startForeground(NOTIFICATION_ID, notification(notice.kind), mic)
            }
        }
        if (result == ServiceNotice.Shown.FAILED) {
            LinphoneEngine.logLine("TELECOM", "foreground notification refused for ${notice.kind}")
            if (strict) throw IllegalStateException("startForeground refused")
            return false
        }
        shown = notice
        shownRing = ring?.second
        // Moving the foreground to another id removes the old notification: an
        // incoming call that still rings keeps its own (call waiting).
        val left = before?.takeIf { it.kind == ServiceNotice.Kind.INCOMING && it.callId != notice.callId }?.callId
        val still = left?.let { ringing[it] }
        if (still != null) {
            try {
                NotificationManagerCompat.from(this).notify(still.first, still.second)
            } catch (e: RuntimeException) {
                LinphoneEngine.logLine("TELECOM", "incoming notification refused: ${e.javaClass.simpleName}")
            }
        }
        return true
    }

    private fun startForeground(id: Int, notification: Notification, mic: Boolean) {
        var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
        if (mic && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }
        ServiceCompat.startForeground(this, id, notification, type)
    }

    private fun createChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.vp_linphone_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.setShowBadge(false)
        nm.createNotificationChannel(channel)
    }

    private fun notification(kind: ServiceNotice.Kind): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val content = launch?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val text = when (kind) {
            ServiceNotice.Kind.IN_CALL -> R.string.vp_linphone_notification_in_call
            ServiceNotice.Kind.CALLING -> R.string.vp_linphone_notification_calling
            else -> R.string.vp_linphone_notification_ready
        }
        val call = kind == ServiceNotice.Kind.IN_CALL || kind == ServiceNotice.Kind.CALLING
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.vp_linphone_ic_call)
            .setContentTitle(getString(R.string.vp_linphone_notification_title))
            .setContentText(getString(text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(if (call) NotificationCompat.CATEGORY_CALL else NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(content)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "vp_linphone_engine"
        const val NOTIFICATION_ID = 0x5650
    }
}
