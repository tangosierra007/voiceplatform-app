package au.com.voiceplatform.vp_linphone

/**
 * The Telecom side of one call, free of Android types so it runs in JVM
 * tests. [VpConnection] feeds it engine snapshots and system-UI events and
 * applies what it returns to the real `android.telecom.Connection`.
 */
enum class TelecomState { NEW, DIALING, RINGING, ACTIVE, HOLDING, DISCONNECTED }

/** Mirrors `android.telecom.DisconnectCause` codes; mapped in [VpConnection]. */
enum class DisconnectKind { LOCAL, REMOTE, REJECTED, BUSY, MISSED, ANSWERED_ELSEWHERE, ERROR, OTHER }

/** What the system UI, a headset or a car asked for. */
sealed class UserEvent {
    object Answer : UserEvent()
    object Reject : UserEvent()
    object Disconnect : UserEvent()
    object Hold : UserEvent()
    object Unhold : UserEvent()
    data class Dtmf(val digit: Char) : UserEvent()
}

/** What the engine is asked to do in response. */
sealed class EngineCommand {
    data class Answer(val callId: String) : EngineCommand()
    data class Decline(val callId: String) : EngineCommand()
    data class Hangup(val callId: String) : EngineCommand()
    data class Hold(val callId: String) : EngineCommand()
    data class Resume(val callId: String) : EngineCommand()
    data class Dtmf(val callId: String, val digits: String) : EngineCommand()
}

/** What to do to the Telecom connection. */
sealed class TelecomAction {
    data class SetState(val state: TelecomState) : TelecomAction()
    data class Disconnect(val kind: DisconnectKind) : TelecomAction()
}

class ConnectionMachine(val callId: String, val incoming: Boolean) {
    var state: TelecomState = TelecomState.NEW
        private set
    private var wasActive = false

    /** An engine snapshot arrived; returns the change to make, if any. */
    fun onEngine(engineState: CallStateMsg, endReason: EndReasonMsg?): TelecomAction? {
        if (state == TelecomState.DISCONNECTED) return null
        if (engineState == CallStateMsg.ENDED) {
            state = TelecomState.DISCONNECTED
            return TelecomAction.Disconnect(disconnect(endReason, incoming, wasActive))
        }
        val next = when (engineState) {
            CallStateMsg.DIALLING, CallStateMsg.RINGING -> TelecomState.DIALING
            CallStateMsg.INCOMING -> TelecomState.RINGING
            CallStateMsg.CONNECTED, CallStateMsg.HELD_BY_REMOTE, CallStateMsg.TRANSFERRING -> TelecomState.ACTIVE
            CallStateMsg.HELD_BY_ME -> TelecomState.HOLDING
            CallStateMsg.ENDED -> TelecomState.DISCONNECTED
        }
        // Never back to ringing or dialing once the call was up.
        if (wasActive && (next == TelecomState.RINGING || next == TelecomState.DIALING)) return null
        if (next == state) return null
        state = next
        if (next == TelecomState.ACTIVE) wasActive = true
        return TelecomAction.SetState(next)
    }

    /** The system asked for something; returns the engine command, if any. */
    fun onUser(event: UserEvent): EngineCommand? = when (event) {
        UserEvent.Answer -> if (state == TelecomState.RINGING) EngineCommand.Answer(callId) else null
        UserEvent.Reject -> if (state == TelecomState.RINGING) EngineCommand.Decline(callId) else null
        UserEvent.Disconnect -> when (state) {
            TelecomState.DISCONNECTED -> null
            // Hanging up a ringing call from a headset is a decline for this device.
            TelecomState.RINGING -> EngineCommand.Decline(callId)
            else -> EngineCommand.Hangup(callId)
        }
        UserEvent.Hold -> if (state == TelecomState.ACTIVE) EngineCommand.Hold(callId) else null
        UserEvent.Unhold -> if (state == TelecomState.HOLDING) EngineCommand.Resume(callId) else null
        is UserEvent.Dtmf ->
            if (state == TelecomState.ACTIVE && Rules.isValidDtmf(event.digit.toString())) {
                EngineCommand.Dtmf(callId, event.digit.toString())
            } else {
                null
            }
    }

    companion object {
        fun disconnect(reason: EndReasonMsg?, incoming: Boolean, wasActive: Boolean): DisconnectKind = when (reason) {
            EndReasonMsg.LOCAL -> DisconnectKind.LOCAL
            EndReasonMsg.REMOTE -> if (incoming && !wasActive) DisconnectKind.MISSED else DisconnectKind.REMOTE
            EndReasonMsg.DECLINED -> if (incoming) DisconnectKind.REJECTED else DisconnectKind.REMOTE
            EndReasonMsg.BUSY -> DisconnectKind.BUSY
            EndReasonMsg.NO_ANSWER -> if (incoming) DisconnectKind.MISSED else DisconnectKind.REMOTE
            EndReasonMsg.ANSWERED_ELSEWHERE -> DisconnectKind.ANSWERED_ELSEWHERE
            EndReasonMsg.TO_VOICEMAIL -> DisconnectKind.REJECTED
            EndReasonMsg.NETWORK_LOST, EndReasonMsg.FAILED -> DisconnectKind.ERROR
            null -> DisconnectKind.OTHER
        }
    }
}
