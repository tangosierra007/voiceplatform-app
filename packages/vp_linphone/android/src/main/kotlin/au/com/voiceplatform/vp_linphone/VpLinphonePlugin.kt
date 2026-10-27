package au.com.voiceplatform.vp_linphone

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
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
 */
class VpLinphonePlugin : FlutterPlugin, VpLinphoneHostApi {

    private lateinit var context: Context
    private var events: VpLinphoneEventsApi? = null
    private var scope: CoroutineScope? = null

    private val listener = object : LinphoneEngine.Listener {
        override fun onRegistration(event: RegistrationMsg) = send { it.onRegistration(event) }
        override fun onCall(call: CallMsg) = send { it.onCall(call) }
        override fun onAudio(audio: AudioMsg) = send { it.onAudio(audio) }
        override fun onInputLevel(dbm0: Double) = send { it.onInputLevel(dbm0) }
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
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        LinphoneEngine.removeListener(listener)
        VpLinphoneHostApi.setUp(binding.binaryMessenger, null)
        events = null
        scope?.cancel()
        scope = null
    }

    override suspend fun start() = suspendCancellableCoroutine { cont ->
        LinphoneEngine.requestStart(context) { error ->
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
        pushProvider: String?,
        pushPrid: String?,
        pushParam: String?,
    ) = LinphoneEngine.register(
        authUsername, password, domain, outboundProxy, displayName,
        expiresSeconds.coerceIn(60, 86400).toInt(), pushProvider, pushPrid, pushParam,
    )

    override suspend fun unregister() = suspendCancellableCoroutine { cont ->
        LinphoneEngine.unregister { cont.resume(Unit) }
    }

    override fun updatePush(provider: String, prid: String, param: String) =
        LinphoneEngine.updatePush(provider, prid, param)

    override fun call(number: String, callerId: String?): String = LinphoneEngine.call(number, callerId)
    override fun answer(callId: String) = LinphoneEngine.answer(callId)
    override fun decline(callId: String) = LinphoneEngine.decline(callId)
    override fun toVoicemail(callId: String) = LinphoneEngine.toVoicemail(callId)
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
}
