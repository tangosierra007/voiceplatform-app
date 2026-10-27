package au.com.voiceplatform.vp_linphone

import java.time.Instant

fun interface Cancellable {
    fun cancel()
}

fun interface Scheduler {
    fun schedule(delayMs: Long, task: () -> Unit): Cancellable
}

/**
 * FCM data messages (the contract's PushMessage: `type`, `pushId`, `sentAt`;
 * nothing personal, APP5), free of Android types so the timing runs in JVM
 * tests with a fake clock.
 *
 * - `incoming_call`: wake the engine (foreground service, Core) and
 *   re-register with the same pn-prid, so the platform can relay the held
 *   INVITE. The 8 s budget runs from `sentAt` (from receipt when it is
 *   missing); a later registration is recorded in [WakeLog].
 * - `call_cancelled`: end the wake at once (well inside the 2 s budget)
 *   unless a call is up.
 * - No INVITE within [IDLE_WAKE_MS] of the wake: back to sleep.
 * - `signed_out`: forget the stored account and stop the engine natively,
 *   then hand it to the app like the others.
 * - `voicemail`, `message`, `signed_out`, `config`: handed to the app.
 * - Duplicates (same pushId) are dropped.
 */
class PushHandler(
    private val clock: () -> Long,
    private val wallClock: () -> Long,
    private val scheduler: Scheduler,
    private val actions: Actions,
    private val wakeLog: WakeLog,
) {
    interface Actions {
        /** Start the service and Core if needed, then register (or refresh) with the stored account. */
        fun wakeAndRegister()

        /** Stop the engine if nothing but a push wake keeps it running. */
        fun sleep()
        fun hasLiveCall(): Boolean

        /** `signed_out`: forget the stored account and stop the engine. */
        fun signOut()
        fun deliver(push: PushData)
    }

    data class PushData(val type: PushTypeMsg, val pushId: String, val sentAt: String?)

    private class Wake(val pushId: String, val receivedAt: Long, val sentAtEpoch: Long?) {
        var registered = false
        var idle: Cancellable? = null
    }

    private val seen = ArrayDeque<String>()
    private var wake: Wake? = null

    val wakeInProgress: Boolean get() = wake != null

    /** Returns false when the message is not one of ours. */
    fun onMessage(data: Map<String, String?>): Boolean {
        val type = parseType(data["type"]) ?: return false
        val id = data["pushId"]?.takeIf { it.isNotBlank() } ?: return false
        if (id in seen) return true
        seen.addLast(id)
        while (seen.size > DEDUP_SIZE) seen.removeFirst()
        when (type) {
            PushTypeMsg.INCOMING_CALL -> onIncomingCall(id, data["sentAt"])
            PushTypeMsg.CALL_CANCELLED -> onCallCancelled()
            PushTypeMsg.SIGNED_OUT -> {
                // Natively first, so a revoked device stops even with no Flutter running.
                wake?.idle?.cancel()
                wake = null
                actions.signOut()
                actions.deliver(PushData(type, id, data["sentAt"]))
            }
            else -> actions.deliver(PushData(type, id, data["sentAt"]))
        }
        return true
    }

    private fun onIncomingCall(pushId: String, sentAt: String?) {
        wake?.idle?.cancel()
        val w = Wake(pushId, clock(), parseInstant(sentAt))
        wake = w
        actions.wakeAndRegister()
        w.idle = scheduler.schedule(IDLE_WAKE_MS) {
            if (wake === w) {
                wake = null
                if (!actions.hasLiveCall()) actions.sleep()
            }
        }
    }

    private fun onCallCancelled() {
        wake?.idle?.cancel()
        wake = null
        if (!actions.hasLiveCall()) actions.sleep()
    }

    /** The engine's registration reached 200 OK. */
    fun onRegistered() {
        val w = wake ?: return
        if (w.registered) return
        w.registered = true
        val sinceReceipt = clock() - w.receivedAt
        val sinceSent = w.sentAtEpoch?.let { wallClock() - it }
        if ((sinceSent ?: sinceReceipt) > REGISTER_BUDGET_MS) {
            wakeLog.recordLate(wallClock(), sinceReceipt, sinceSent)
        }
    }

    /** The woken engine got its INVITE: the call's own lifecycle takes over. */
    fun onCallArrived() {
        wake?.idle?.cancel()
        wake = null
    }

    companion object {
        const val REGISTER_BUDGET_MS = 8_000L
        const val IDLE_WAKE_MS = 30_000L
        private const val DEDUP_SIZE = 64

        fun parseType(type: String?): PushTypeMsg? = when (type) {
            "incoming_call" -> PushTypeMsg.INCOMING_CALL
            "call_cancelled" -> PushTypeMsg.CALL_CANCELLED
            "voicemail" -> PushTypeMsg.VOICEMAIL
            "message" -> PushTypeMsg.MESSAGE
            "signed_out" -> PushTypeMsg.SIGNED_OUT
            "config" -> PushTypeMsg.CONFIG
            else -> null
        }

        fun parseInstant(s: String?): Long? =
            if (s.isNullOrBlank()) null else runCatching { Instant.parse(s).toEpochMilli() }.getOrNull()
    }
}

/**
 * Registrations that came later than the 8 s budget after a push, for the Me
 * card "Calls may be missed while this phone saves battery" (spec 22,
 * Battery optimisation; 4.4 decides when to show it).
 */
class WakeLog(private val store: Store) {
    interface Store {
        fun load(): List<Long>
        fun save(times: List<Long>)
    }

    fun recordLate(atEpochMs: Long, sinceReceiptMs: Long, sinceSentMs: Long?) {
        val times = (store.load() + atEpochMs).takeLast(MAX)
        store.save(times)
        lastLate = Late(atEpochMs, sinceReceiptMs, sinceSentMs)
    }

    fun lateInLastWeek(nowEpochMs: Long): Int = store.load().count { nowEpochMs - it in 0..WEEK_MS }

    data class Late(val atEpochMs: Long, val sinceReceiptMs: Long, val sinceSentMs: Long?)

    var lastLate: Late? = null
        private set

    companion object {
        const val WEEK_MS = 7L * 24 * 60 * 60 * 1000
        private const val MAX = 50
    }
}
