package au.com.voiceplatform.vp_linphone

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings

/**
 * FCM data messages, received natively so an incoming call wakes the engine
 * without starting Flutter. Google Play services delivers the
 * `com.google.android.c2dm.intent.RECEIVE` broadcast to every receiver in the
 * app that holds the SEND permission check, the firebase_messaging plugin's
 * included; this one acts only on the contract's PushMessage types.
 */
class PushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        val data = mapOf(
            "type" to extras.getString("type"),
            "pushId" to extras.getString("pushId"),
            "sentAt" to extras.getString("sentAt"),
        )
        VpPush.get(context).onMessage(data)
    }
}

object VpPush {
    interface AppListener {
        fun onPush(push: PushMsg)
    }

    private const val PREFS = "vp_linphone_push"
    private const val MAX_PENDING = 20

    @Volatile private var handler: PushHandler? = null
    private var wakeLog: WakeLog? = null
    private val appListeners = LinkedHashSet<AppListener>()
    private val main = Handler(Looper.getMainLooper())

    fun addAppListener(l: AppListener) = appListeners.add(l)
    fun removeAppListener(l: AppListener) = appListeners.remove(l)

    @Synchronized
    fun get(context: Context): PushHandler {
        handler?.let { return it }
        val app = context.applicationContext
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val log = WakeLog(object : WakeLog.Store {
            override fun load() = prefs.getString("late", "").orEmpty().split(',').mapNotNull { it.toLongOrNull() }
            override fun save(times: List<Long>) = prefs.edit().putString("late", times.joinToString(",")).apply()
        })
        wakeLog = log
        val h = PushHandler(
            clock = SystemClock::elapsedRealtime,
            wallClock = System::currentTimeMillis,
            scheduler = { delay, task ->
                val r = Runnable { task() }
                main.postDelayed(r, delay)
                Cancellable { main.removeCallbacks(r) }
            },
            actions = object : PushHandler.Actions {
                override fun wakeAndRegister() = LinphoneEngine.wakeForPush(app)
                override fun sleep() = LinphoneEngine.sleepAfterPush(app)
                override fun hasLiveCall() = LinphoneEngine.hasLiveCall
                override fun signOut() = LinphoneEngine.signOutFromPush(app)
                override fun deliver(push: PushHandler.PushData) {
                    val msg = PushMsg(push.type, push.pushId, push.sentAt)
                    if (appListeners.isEmpty()) addPending(app, msg) else appListeners.forEach { it.onPush(msg) }
                }
            },
            wakeLog = log,
        )
        handler = h
        return h
    }

    /** Debug and example-app entry: hand a data message to the handler as FCM would. */
    fun simulate(context: Context, type: String, pushId: String, sentAt: String? = null): Boolean =
        get(context).onMessage(mapOf("type" to type, "pushId" to pushId, "sentAt" to sentAt))

    private fun addPending(context: Context, msg: PushMsg) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val lines = prefs.getString("pending", "").orEmpty().lines().filter { it.isNotBlank() }
        val line = listOf(msg.type.name, msg.pushId, msg.sentAt.orEmpty()).joinToString("|")
        prefs.edit().putString("pending", (lines + line).takeLast(MAX_PENDING).joinToString("\n")).apply()
    }

    fun takePending(context: Context): List<PushMsg> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val lines = prefs.getString("pending", "").orEmpty().lines().filter { it.isNotBlank() }
        prefs.edit().remove("pending").apply()
        return lines.mapNotNull { line ->
            val p = line.split('|')
            if (p.size < 3) return@mapNotNull null
            val type = runCatching { PushTypeMsg.valueOf(p[0]) }.getOrNull() ?: return@mapNotNull null
            PushMsg(type, p[1], p[2].ifEmpty { null })
        }
    }

    fun battery(context: Context): BatteryMsg {
        get(context)
        val pm = context.getSystemService(PowerManager::class.java)
        return BatteryMsg(
            ignoringOptimizations = pm.isIgnoringBatteryOptimizations(context.packageName),
            lateWakesLastWeek = (wakeLog?.lateInLastWeek(System.currentTimeMillis()) ?: 0).toLong(),
            manufacturer = Build.MANUFACTURER.orEmpty(),
        )
    }

    /** Android's own list; no permission and no exemption request (spec 22). */
    fun openBatterySettings(context: Context) {
        context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    fun openFullScreenIntentSettings(context: Context) {
        val intent = if (Build.VERSION.SDK_INT >= 34) {
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:${context.packageName}"))
        } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        }
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
