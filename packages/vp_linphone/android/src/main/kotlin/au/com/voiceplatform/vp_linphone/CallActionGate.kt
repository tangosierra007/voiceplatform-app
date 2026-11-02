package au.com.voiceplatform.vp_linphone

import java.security.SecureRandom

/**
 * Who may act on a ringing call from outside the Flutter API: only our own
 * notification. Each notification carries a random token for its call;
 * Answer and Decline must present it, and it is used once. The pending UI
 * request for the app is handed over in process memory, never in an intent
 * extra the exported launcher activity could be sent by another app.
 */
class CallActionGate(private val random: () -> String = ::randomToken) {
    enum class Action { SHOW_INCOMING, ANSWER, DECLINE }

    private val tokens = HashMap<String, String>()

    /** A fresh token for this call's notification (replaces any earlier one). */
    @Synchronized
    fun issue(callId: String): String = random().also { tokens[callId] = it }

    /** True when [token] is this call's; Answer and Decline use it up. */
    @Synchronized
    fun authorise(action: Action, callId: String?, token: String?): Boolean {
        if (callId == null || token == null) return false
        val expected = tokens[callId] ?: return false
        if (!constantTimeEquals(expected, token)) return false
        if (action != Action.SHOW_INCOMING) tokens.remove(callId)
        return true
    }

    @Synchronized
    fun forget(callId: String) {
        tokens.remove(callId)
    }

    companion object {
        private val rng = SecureRandom()

        fun randomToken(): String {
            val b = ByteArray(16)
            rng.nextBytes(b)
            return b.joinToString("") { "%02x".format(it) }
        }

        /** An engine-local call id that can't be guessed from outside. */
        fun randomCallId(): String = "call-" + randomToken().take(16)

        private fun constantTimeEquals(a: String, b: String): Boolean {
            if (a.length != b.length) return false
            var diff = 0
            for (i in a.indices) diff = diff or (a[i].code xor b[i].code)
            return diff == 0
        }
    }
}

/** The UI request the trampoline hands to the plugin, in process memory only. */
object PendingUiRequest {
    @Volatile private var request: UiRequestMsg? = null
    @Volatile private var delivered = false
    var listener: ((UiRequestMsg) -> Unit)? = null

    /**
     * Sent live when a Flutter engine is attached, and kept for [take] until
     * Dart has received it ([delivered]): an engine that is attached but whose
     * Dart side isn't listening yet (a cold start from the full-screen intent)
     * must not lose it.
     */
    @Synchronized
    fun post(r: UiRequestMsg) {
        request = r
        delivered = false
        listener?.invoke(r)
    }

    /** Dart received [r] live: [take] won't hand it out again. */
    @Synchronized
    fun delivered(r: UiRequestMsg) {
        if (request == r) delivered = true
    }

    /** The latest request, for the lock-screen decision. */
    fun peek(): UiRequestMsg? = request

    /** For Dart's takeUiRequest(): once, and not if it was delivered live. */
    @Synchronized
    fun take(): UiRequestMsg? = if (delivered) null else request.also { delivered = true }
}

/**
 * Whether the app's activity may show over the lock screen for the request
 * [CallActionActivity] left in memory: the incoming screen while that call
 * rings, the call screen (after Answer from the locked phone's notification)
 * while that call is live. Cleared when the last call ends.
 */
object LockScreenPolicy {
    fun showOverLock(kind: UiRequestKindMsg, callState: CallStateMsg?): Boolean = when (kind) {
        UiRequestKindMsg.SHOW_INCOMING -> callState == CallStateMsg.INCOMING
        UiRequestKindMsg.SHOW_CALL -> callState != null && callState != CallStateMsg.ENDED
    }
}
