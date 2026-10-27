package au.com.voiceplatform.vp_linphone

import android.annotation.SuppressLint
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.OutcomeReceiver
import android.telecom.CallAudioState
import android.telecom.CallEndpoint
import android.telecom.CallEndpointException
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import androidx.core.content.ContextCompat

/** The self-managed ConnectionService; all logic is in [TelecomBridge]. */
class VpConnectionService : ConnectionService() {
    override fun onCreateIncomingConnection(handle: PhoneAccountHandle?, request: ConnectionRequest): Connection =
        TelecomBridge.createConnection(this, request, incoming = true)

    override fun onCreateOutgoingConnection(handle: PhoneAccountHandle?, request: ConnectionRequest): Connection =
        TelecomBridge.createConnection(this, request, incoming = false)

    override fun onCreateIncomingConnectionFailed(handle: PhoneAccountHandle?, request: ConnectionRequest?) =
        TelecomBridge.creationFailed(request, incoming = true)

    override fun onCreateOutgoingConnectionFailed(handle: PhoneAccountHandle?, request: ConnectionRequest?) =
        TelecomBridge.creationFailed(request, incoming = false)
}

/** One call as Telecom sees it. */
class VpConnection(private val context: Context, val info: TelecomBridge.CallInfo) : Connection() {
    val machine = ConnectionMachine(info.callId, info.incoming)
    private var endpoints: List<CallEndpoint> = emptyList()

    init {
        connectionProperties = PROPERTY_SELF_MANAGED
        connectionCapabilities = CAPABILITY_HOLD or CAPABILITY_SUPPORT_HOLD or CAPABILITY_MUTE
        audioModeIsVoip = true
        setAddress(Uri.fromParts(PhoneAccount.SCHEME_SIP, info.number, null), TelecomManager.PRESENTATION_ALLOWED)
        info.name?.let { setCallerDisplayName(it, TelecomManager.PRESENTATION_ALLOWED) }
        apply(if (info.incoming) CallStateMsg.INCOMING else CallStateMsg.DIALLING, null)
    }

    fun apply(call: CallMsg) = apply(call.state, call.endReason)

    private fun apply(state: CallStateMsg, endReason: EndReasonMsg?) {
        when (val action = machine.onEngine(state, endReason)) {
            null -> {}
            is TelecomAction.SetState -> when (action.state) {
                TelecomState.DIALING -> setDialing()
                TelecomState.RINGING -> setRinging()
                TelecomState.ACTIVE -> setActive()
                TelecomState.HOLDING -> setOnHold()
                TelecomState.NEW, TelecomState.DISCONNECTED -> {}
            }
            is TelecomAction.Disconnect -> {
                setDisconnected(DisconnectCause(code(action.kind)))
                destroy()
            }
        }
    }

    // ---- system side

    override fun onShowIncomingCallUi() = IncomingCallNotifier.show(context, info)
    override fun onAnswer() = TelecomBridge.onUserEvent(this, UserEvent.Answer)
    override fun onAnswer(videoState: Int) = TelecomBridge.onUserEvent(this, UserEvent.Answer)
    override fun onReject() = TelecomBridge.onUserEvent(this, UserEvent.Reject)
    override fun onReject(replyMessage: String?) = TelecomBridge.onUserEvent(this, UserEvent.Reject)
    override fun onDisconnect() = TelecomBridge.onUserEvent(this, UserEvent.Disconnect)
    override fun onAbort() = TelecomBridge.onUserEvent(this, UserEvent.Disconnect)
    override fun onHold() = TelecomBridge.onUserEvent(this, UserEvent.Hold)
    override fun onUnhold() = TelecomBridge.onUserEvent(this, UserEvent.Unhold)
    override fun onPlayDtmfTone(c: Char) = TelecomBridge.onUserEvent(this, UserEvent.Dtmf(c))
    override fun onSilence() = IncomingCallNotifier.silence(context, info)

    // ---- audio routes

    @Deprecated("Below Android 14 Telecom reports routes through CallAudioState")
    override fun onCallAudioStateChanged(state: CallAudioState) {
        if (Build.VERSION.SDK_INT >= 34) return
        val available = mutableListOf<AudioRouteMsg>()
        val mask = state.supportedRouteMask
        if (mask and CallAudioState.ROUTE_EARPIECE != 0) available += AudioRouteMsg.EARPIECE
        if (mask and CallAudioState.ROUTE_SPEAKER != 0) available += AudioRouteMsg.SPEAKER
        if (mask and CallAudioState.ROUTE_WIRED_HEADSET != 0) available += AudioRouteMsg.WIRED_HEADSET
        if (mask and CallAudioState.ROUTE_BLUETOOTH != 0) {
            available += AudioRouteMsg.BLUETOOTH
            if (state.supportedBluetoothDevices.any { isCar(it) }) available += AudioRouteMsg.CAR
        }
        val route = when (state.route) {
            CallAudioState.ROUTE_SPEAKER -> AudioRouteMsg.SPEAKER
            CallAudioState.ROUTE_WIRED_HEADSET -> AudioRouteMsg.WIRED_HEADSET
            CallAudioState.ROUTE_BLUETOOTH ->
                if (state.activeBluetoothDevice?.let { isCar(it) } == true) AudioRouteMsg.CAR else AudioRouteMsg.BLUETOOTH
            else -> AudioRouteMsg.EARPIECE
        }
        TelecomBridge.onAudio(route, available.distinct())
    }

    override fun onAvailableCallEndpointsChanged(available: MutableList<CallEndpoint>) {
        endpoints = available.toList()
        currentEndpoint?.let { report(it) }
    }

    private var currentEndpoint: CallEndpoint? = null

    override fun onCallEndpointChanged(endpoint: CallEndpoint) {
        currentEndpoint = endpoint
        report(endpoint)
    }

    private fun report(current: CallEndpoint) {
        val available = endpoints.mapNotNull { routeOf(it) }.distinct().toMutableList()
        TelecomBridge.onAudio(routeOf(current) ?: AudioRouteMsg.EARPIECE, available)
    }

    private fun routeOf(e: CallEndpoint): AudioRouteMsg? = when (e.endpointType) {
        CallEndpoint.TYPE_EARPIECE -> AudioRouteMsg.EARPIECE
        CallEndpoint.TYPE_SPEAKER -> AudioRouteMsg.SPEAKER
        CallEndpoint.TYPE_WIRED_HEADSET -> AudioRouteMsg.WIRED_HEADSET
        CallEndpoint.TYPE_BLUETOOTH -> if (e.endpointName.toString() in carNames()) AudioRouteMsg.CAR else AudioRouteMsg.BLUETOOTH
        else -> null
    }

    fun requestRoute(route: AudioRouteMsg): Boolean {
        if (Build.VERSION.SDK_INT >= 34) {
            val target = endpoints.firstOrNull { routeOf(it) == route }
                ?: if (route == AudioRouteMsg.CAR) null else endpoints.firstOrNull { routeOf(it) == route }
            target ?: return false
            requestCallEndpointChange(
                target,
                ContextCompat.getMainExecutor(context),
                object : OutcomeReceiver<Void, CallEndpointException> {
                    override fun onResult(result: Void?) {}
                    override fun onError(error: CallEndpointException) {
                        LinphoneEngine.logLine("TELECOM", "route change refused ${error.code}")
                    }
                },
            )
            return true
        }
        @Suppress("DEPRECATION")
        when (route) {
            AudioRouteMsg.EARPIECE -> setAudioRoute(CallAudioState.ROUTE_EARPIECE)
            AudioRouteMsg.SPEAKER -> setAudioRoute(CallAudioState.ROUTE_SPEAKER)
            AudioRouteMsg.WIRED_HEADSET -> setAudioRoute(CallAudioState.ROUTE_WIRED_HEADSET)
            AudioRouteMsg.BLUETOOTH -> setAudioRoute(CallAudioState.ROUTE_BLUETOOTH)
            AudioRouteMsg.CAR -> {
                val car = callAudioState?.supportedBluetoothDevices?.firstOrNull { isCar(it) } ?: return false
                requestBluetoothAudio(car)
            }
        }
        return true
    }

    /** Car kits by Bluetooth class; needs BLUETOOTH_CONNECT, else none are cars. */
    @SuppressLint("MissingPermission")
    private fun isCar(device: BluetoothDevice): Boolean = try {
        device.bluetoothClass?.deviceClass == BluetoothClass.Device.AUDIO_VIDEO_CAR_AUDIO
    } catch (_: SecurityException) {
        false
    }

    @SuppressLint("MissingPermission")
    private fun carNames(): Set<String> = try {
        val adapter = context.getSystemService(android.bluetooth.BluetoothManager::class.java)?.adapter
        adapter?.bondedDevices.orEmpty().filter { isCar(it) }.mapNotNull { it.name }.toSet()
    } catch (_: SecurityException) {
        emptySet()
    }

    companion object {
        fun code(kind: DisconnectKind): Int = when (kind) {
            DisconnectKind.LOCAL -> DisconnectCause.LOCAL
            DisconnectKind.REMOTE -> DisconnectCause.REMOTE
            DisconnectKind.REJECTED -> DisconnectCause.REJECTED
            DisconnectKind.BUSY -> DisconnectCause.BUSY
            DisconnectKind.MISSED -> DisconnectCause.MISSED
            DisconnectKind.ANSWERED_ELSEWHERE -> DisconnectCause.ANSWERED_ELSEWHERE
            DisconnectKind.ERROR -> DisconnectCause.ERROR
            DisconnectKind.OTHER -> DisconnectCause.OTHER
        }
    }
}
