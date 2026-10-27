package au.com.voiceplatform.vp_linphone

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager

/**
 * Every call as a self-managed Telecom connection (spec 22, Android
 * specifics; decision 141), so the system UI, the lock screen, Bluetooth
 * headsets and cars can answer, reject, hold, end and send DTMF, and audio
 * routes come from Telecom.
 *
 * The engine (or, in the example app, a fake) is the [Control]; it tells the
 * bridge about calls and every snapshot, and the bridge turns system-side
 * requests back into engine commands through [ConnectionMachine].
 */
object TelecomBridge {

    interface Control {
        fun execute(command: EngineCommand)

        /** Telecom's audio route and what is available, for CallEngine.audio. */
        fun onTelecomAudio(route: AudioRouteMsg, available: List<AudioRouteMsg>)

        /** Telecom refused the call (for example a cellular call is up); end it. */
        fun onTelecomRefused(callId: String, incoming: Boolean)
    }

    interface UiListener {
        fun onFullScreenIntentDenied(callId: String)
    }

    data class CallInfo(val callId: String, val incoming: Boolean, val number: String, val name: String?)

    const val EXTRA_CALL_ID = "au.com.voiceplatform.vp_linphone.CALL_ID"
    private const val ACCOUNT_ID = "vp_linphone"

    var control: Control? = null
    var uiListener: UiListener? = null

    private val pending = HashMap<String, CallInfo>()
    private val connections = HashMap<String, VpConnection>()
    private var appContext: Context? = null

    val hasConnections: Boolean get() = connections.isNotEmpty()

    fun connection(callId: String): VpConnection? = connections[callId]

    private fun log(message: String) = LinphoneEngine.logLine("TELECOM", message)

    fun handle(context: Context): PhoneAccountHandle =
        PhoneAccountHandle(ComponentName(context, VpConnectionService::class.java), ACCOUNT_ID)

    private fun telecom(context: Context) = context.getSystemService(TelecomManager::class.java)

    fun ensurePhoneAccount(context: Context) {
        appContext = context.applicationContext
        val label = context.applicationInfo.loadLabel(context.packageManager)
        val account = PhoneAccount.builder(handle(context), label)
            .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
            .addSupportedUriScheme(PhoneAccount.SCHEME_SIP)
            .addSupportedUriScheme(PhoneAccount.SCHEME_TEL)
            .build()
        telecom(context).registerPhoneAccount(account)
    }

    /** An outgoing call the engine has just started (never an emergency number). */
    fun placeOutgoing(context: Context, info: CallInfo) {
        // Rule: never a self-managed emergency call, whatever the path.
        if (Rules.isEmergency(info.number)) throw VpFlutterError("emergency_use_dialler", "Emergency numbers use the phone dialler")
        try {
            ensurePhoneAccount(context)
            pending[info.callId] = info
            val inner = Bundle().apply { putString(EXTRA_CALL_ID, info.callId) }
            val extras = Bundle().apply {
                putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle(context))
                putBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, inner)
            }
            telecom(context).placeCall(Uri.fromParts(PhoneAccount.SCHEME_SIP, info.number, null), extras)
            log("placeCall ${info.callId}")
        } catch (e: RuntimeException) {
            // SecurityException without MANAGE_OWN_CALLS, IllegalStateException...
            pending.remove(info.callId)
            log("placeCall refused: ${e.javaClass.simpleName}")
        }
    }

    /** An incoming INVITE: Telecom then asks for the connection and its UI. */
    fun addIncoming(context: Context, info: CallInfo) {
        if (Rules.isEmergency(info.number)) {
            // Not ours to ring as a self-managed call; still shown, never placed.
            log("incoming from an emergency-like number ${info.callId}")
        }
        try {
            ensurePhoneAccount(context)
            pending[info.callId] = info
            val inner = Bundle().apply { putString(EXTRA_CALL_ID, info.callId) }
            val extras = Bundle().apply { putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, inner) }
            telecom(context).addNewIncomingCall(handle(context), extras)
            log("addNewIncomingCall ${info.callId}")
        } catch (e: RuntimeException) {
            pending.remove(info.callId)
            log("addNewIncomingCall refused: ${e.javaClass.simpleName}; notification only")
            IncomingCallNotifier.show(context, info)
        }
    }

    /** Every engine snapshot. */
    fun onSnapshot(context: Context, call: CallMsg) {
        connections[call.id]?.apply(call)
        if (call.state != CallStateMsg.INCOMING) IncomingCallNotifier.cancel(context, call.id)
        if (call.state == CallStateMsg.ENDED) {
            connections.remove(call.id)
            pending.remove(call.id)
        }
    }

    /** Asks Telecom for a route; false when no connection can take it (the engine routes itself). */
    fun requestRoute(route: AudioRouteMsg): Boolean {
        val c = connections.values.firstOrNull { it.machine.state != TelecomState.DISCONNECTED } ?: return false
        return c.requestRoute(route)
    }

    // ---- from VpConnectionService

    internal fun createConnection(context: Context, request: ConnectionRequest, incoming: Boolean): Connection {
        // Never a self-managed emergency call, whoever asked Telecom for it.
        val dialled = request.address?.schemeSpecificPart.orEmpty()
        if (!incoming && Rules.isEmergency(dialled)) {
            log("outgoing emergency connection refused")
            return Connection.createFailedConnection(android.telecom.DisconnectCause(android.telecom.DisconnectCause.RESTRICTED))
        }
        val extras = if (incoming) {
            request.extras?.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS) ?: request.extras
        } else {
            request.extras?.getBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS) ?: request.extras
        }
        val callId = extras?.getString(EXTRA_CALL_ID)
        val info = callId?.let { pending.remove(it) }
        if (callId == null || info == null) {
            log("connection request for an unknown call")
            return Connection.createFailedConnection(android.telecom.DisconnectCause(android.telecom.DisconnectCause.ERROR))
        }
        val c = VpConnection(context.applicationContext, info)
        connections[callId] = c
        log("connection created ${info.callId}")
        return c
    }

    internal fun creationFailed(request: ConnectionRequest?, incoming: Boolean) {
        val bundleKey = if (incoming) TelecomManager.EXTRA_INCOMING_CALL_EXTRAS else TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS
        val callId = request?.extras?.getBundle(bundleKey)?.getString(EXTRA_CALL_ID)
            ?: request?.extras?.getString(EXTRA_CALL_ID) ?: return
        val info = pending.remove(callId)
        log("connection refused by Telecom $callId")
        if (incoming && info != null) appContext?.let { IncomingCallNotifier.show(it, info) }
        // Telecom refused an outgoing call (a cellular call is up): end ours.
        if (!incoming) control?.onTelecomRefused(callId, false)
    }

    internal fun onUserEvent(connection: VpConnection, event: UserEvent) {
        val command = connection.machine.onUser(event) ?: return
        log("system ${event.javaClass.simpleName} ${connection.info.callId}")
        control?.execute(command)
    }

    internal fun onAudio(route: AudioRouteMsg, available: List<AudioRouteMsg>) {
        control?.onTelecomAudio(route, available)
    }

    /** Answer from our notification's Answer button (opens the app first). */
    fun answerFromNotification(context: Context, callId: String) {
        IncomingCallNotifier.cancel(context, callId)
        val c = connections[callId]
        if (c != null) onUserEvent(c, UserEvent.Answer) else control?.execute(EngineCommand.Answer(callId))
    }

    fun declineFromNotification(context: Context, callId: String) {
        IncomingCallNotifier.cancel(context, callId)
        val c = connections[callId]
        if (c != null) onUserEvent(c, UserEvent.Reject) else control?.execute(EngineCommand.Decline(callId))
    }
}
