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
import androidx.core.app.ServiceCompat

/**
 * The foreground service that owns the liblinphone Core. Type `phoneCall`
 * while it runs, plus `microphone` during a call when RECORD_AUDIO is granted.
 * Started by CallEngine.start(), stopped by CallEngine.stop(); not sticky
 * (credentials are in memory only, so a restarted service would have nothing
 * to register with; 3.2 wakes it from FCM instead).
 */
class EngineService : Service() {

    private var inCall = false

    override fun onCreate() {
        super.onCreate()
        EngineStartup.run(
            // First, before anything else can throw: the notification and
            // startForeground with the plain phoneCall type.
            goForeground = {
                createChannel()
                goForeground(inCall = false, mic = false)
            },
            // Then liblinphone: native libraries, the Core, its start.
            setUp = { LinphoneEngine.onServiceCreated(this) },
            report = { LinphoneEngine.onServiceStartFailed(it) },
            stop = { stopSelf() },
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        LinphoneEngine.onServiceDestroyed()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    /** Called by the engine when the first call starts and the last one ends. */
    fun setInCall(inCall: Boolean, mic: Boolean) {
        this.inCall = inCall
        try {
            goForeground(inCall, mic)
        } catch (e: RuntimeException) {
            // Keep the phoneCall type if the microphone type is refused.
            if (mic) goForeground(inCall, mic = false)
        }
    }

    private fun goForeground(inCall: Boolean, mic: Boolean) {
        var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
        if (mic && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification(inCall), type)
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

    private fun notification(inCall: Boolean): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val content = launch?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.vp_linphone_ic_call)
            .setContentTitle(getString(R.string.vp_linphone_notification_title))
            .setContentText(
                getString(if (inCall) R.string.vp_linphone_notification_in_call else R.string.vp_linphone_notification_ready),
            )
            .setOngoing(true)
            .setCategory(if (inCall) NotificationCompat.CATEGORY_CALL else NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(content)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "vp_linphone_engine"
        private const val NOTIFICATION_ID = 0x5650
    }
}
