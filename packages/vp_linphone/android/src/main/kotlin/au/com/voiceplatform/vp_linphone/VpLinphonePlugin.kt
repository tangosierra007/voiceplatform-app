package au.com.voiceplatform.vp_linphone

import android.app.Activity
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Flutter side of the engine: the Pigeon host API delegates to
 * [LinphoneEngine]; engine events go back through [VpLinphoneEventsApi].
 * As [ActivityAware] it reads the incoming-call intents (full-screen intent,
 * notification tap, Answer button) and turns them into UI requests for WS4.
 */
class VpLinphonePlugin : FlutterPlugin, ActivityAware, VpLinphoneHostApi {

    private lateinit var context: Context
    private var events: VpLinphoneEventsApi? = null
    private var scope: CoroutineScope? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingUi: UiRequestMsg? = null

    private val listener = object : LinphoneEngine.Listener {
        override fun onRegistration(event: RegistrationMsg) = send { it.onRegistration(event) }
        override fun onCall(call: CallMsg) {
            send { it.onCall(call) }
            if (call.state == CallStateMsg.ENDED && !LinphoneEngine.hasLiveCall) showOverLock(false)
        }
        override fun onAudio(audio: AudioMsg) = send { it.onAudio(audio) }
        override fun onInputLevel(dbm0: Double) = send { it.onInputLevel(dbm0) }
    }

    private val pushListener = object : VpPush.AppListener {
        override fun onPush(push: PushMsg) = send { it.onPush(push) }
    }

    private val uiListener = object : TelecomBridge.UiListener {
        override fun onFullScreenIntentDenied(callId: String) = send { it.onFullScreenIntentDenied(callId) }
    }

    private val newIntentListener = PluginRegistry.NewIntentListener { intent ->
        handleIntent(intent)
        false
    }

    private fun send(block: suspend (VpLinphoneEventsApi) -> Unit) {
        val api = events ?: return
        // Main.immediate keeps events in order: each send starts in place.
        scope?.launch {
            try {
                block(api)
            } catch (_: VpFlutterError) {
                // No Dart listener (engine detached); nothing to do.
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        events = VpLinphoneEventsApi(binding.binaryMessenger)
        VpLinphoneHostApi.setUp(binding.binaryMessenger, this)
        LinphoneEngine.attach(context)
        LinphoneEngine.addListener(listener)
        VpPush.addAppListener(pushListener)
        TelecomBridge.uiListener = uiListener
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        LinphoneEngine.removeListener(listener)
        VpPush.removeAppListener(pushListener)
        if (TelecomBridge.uiListener === uiListener) TelecomBridge.uiListener = null
        VpLinphoneHostApi.setUp(binding.binaryMessenger, null)
        events = null
        scope?.cancel()
        scope = null
    }

    // ---- activity: incoming-call intents

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addOnNewIntentListener(newIntentListener)
        handleIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(newIntentListener)
        activityBinding = null
        activity = null
    }

    private fun handleIntent(intent: Intent?) {
        intent ?: return
        val action = intent.getStringExtra(IncomingCallNotifier.EXTRA_ACTION) ?: return
        val callId = intent.getStringExtra(TelecomBridge.EXTRA_CALL_ID) ?: return
        // Once only: a re-created activity must not answer again.
        intent.removeExtra(IncomingCallNotifier.EXTRA_ACTION)
        val request = when (action) {
            IncomingCallNotifier.ACTION_ANSWER -> {
                TelecomBridge.answerFromNotification(context, callId)
                UiRequestMsg(UiRequestKindMsg.SHOW_CALL, callId)
            }
            IncomingCallNotifier.ACTION_SHOW_INCOMING -> {
                showOverLock(true)
                UiRequestMsg(UiRequestKindMsg.SHOW_INCOMING, callId)
            }
            IncomingCallNotifier.ACTION_SHOW_CALL -> UiRequestMsg(UiRequestKindMsg.SHOW_CALL, callId)
            else -> return
        }
        pendingUi = request
        send { it.onUiRequest(request) }
    }

    /** The incoming screen over the lock screen, and the screen on, while a call rings. */
    private fun showOverLock(on: Boolean) {
        val a = activity ?: return
        a.setShowWhenLocked(on)
        a.setTurnScreenOn(on)
    }

    // ---- host API

    override suspend fun start() = suspendCancellableCoroutine { cont ->
        LinphoneEngine.requestStart(context, byApp = true) { error ->
            if (error == null) {
                cont.resume(Unit)
            } else {
                cont.resumeWithException(VpFlutterError("invalid_state", "Engine could not start: ${error.javaClass.simpleName}"))
            }
        }
    }

    override suspend fun stop() = suspendCancellableCoroutine { cont ->
        LinphoneEngine.requestStop(context) { cont.resume(Unit) }
    }

    override fun register(
        authUsername: String,
        password: String,
        domain: String,
        outboundProxy: String,
        displayName: String,
        expiresSeconds: Long,
        instanceId: String,
        pushProvider: String?,
        pushPrid: String?,
        pushParam: String?,
    ) = LinphoneEngine.register(
        authUsername, password, domain, outboundProxy, displayName,
        expiresSeconds.coerceIn(60, 86400).toInt(), instanceId, pushProvider, pushPrid, pushParam,
    )

    override suspend fun unregister() = suspendCancellableCoroutine { cont ->
        LinphoneEngine.unregister { cont.resume(Unit) }
    }

    override fun updatePush(provider: String, prid: String, param: String) =
        LinphoneEngine.updatePush(provider, prid, param)

    override fun call(number: String, callerId: String?): String = LinphoneEngine.call(number, callerId)
    override fun answer(callId: String) {
        IncomingCallNotifier.cancel(context, callId)
        LinphoneEngine.answer(callId)
    }
    override fun decline(callId: String) = LinphoneEngine.decline(callId)
    override fun toVoicemail(callId: String, voicemailUser: String) = LinphoneEngine.toVoicemail(callId, voicemailUser)
    override fun hangup(callId: String) = LinphoneEngine.hangup(callId)
    override fun hold(callId: String) = LinphoneEngine.hold(callId)
    override fun resume(callId: String) = LinphoneEngine.resume(callId)
    override fun setMuted(muted: Boolean) = LinphoneEngine.setMuted(muted)
    override fun sendDtmf(callId: String, digits: String) = LinphoneEngine.sendDtmf(callId, digits)
    override fun transferBlind(callId: String, target: String) = LinphoneEngine.transferBlind(callId, target)
    override fun transferAttended(callId: String, consultCallId: String) =
        LinphoneEngine.transferAttended(callId, consultCallId)
    override fun merge(callIdA: String, callIdB: String) = LinphoneEngine.merge(callIdA, callIdB)
    override fun setAudioRoute(route: AudioRouteMsg) = LinphoneEngine.setAudioRoute(route)
    override suspend fun exportLastCallLog(): ByteArray = LinphoneEngine.exportLastCallLog()

    override fun syncState() = LinphoneEngine.syncState()
    override fun takePendingPushes(): List<PushMsg> = VpPush.takePending(context)
    override fun takeUiRequest(): UiRequestMsg? = pendingUi.also { pendingUi = null }
    override fun batteryStatus(): BatteryMsg = VpPush.battery(context)
    override fun openBatteryOptimizationSettings() = VpPush.openBatterySettings(context)
    override fun canUseFullScreenIntent(): Boolean = IncomingCallNotifier.canUseFullScreenIntent(context)
    override fun openFullScreenIntentSettings() = VpPush.openFullScreenIntentSettings(context)
}
