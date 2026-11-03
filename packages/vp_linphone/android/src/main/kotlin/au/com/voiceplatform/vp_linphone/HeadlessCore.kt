package au.com.voiceplatform.vp_linphone

/**
 * Who stops the Core a background registration ([ReregisterWorker]) created
 * without the foreground service, free of Android types for JVM tests.
 *
 * While [owned], no service has taken the Core over and it is the job's to
 * stop. A service that starts (a push, the app) takes it over and from then
 * on the service's lifecycle decides. Rules:
 * - The job ends with the engine stopped: the Core stops, unless a call is
 *   on it (then when its last call ends).
 * - The job ends while a service is starting: the Core is left for it,
 *   never stopped under a push wake that is about to relay its INVITE.
 * - A service that is destroyed without having taken the Core over (a
 *   `call_cancelled` while it started) leaves it alone.
 * - A call that lands on the Core with no service: the push that comes with
 *   it should start the service within [TAKEOVER_MS]. If none has, the call
 *   is declined (480) and the Core stops shortly after ([DECLINE_FLUSH_MS],
 *   so the 480 goes out), or as soon as the call has ended.
 * - A call answered on the Core cancels both timers (the engine starts the
 *   service, which takes the Core over); nothing releases the Core while a
 *   call on it is connected.
 * - Whenever the Core is released, ringing calls are declined with 480
 *   first, never ended with the 603 a bare stop may send (that could stop
 *   the edge trying the user's other devices).
 */
class HeadlessCore(private val scheduler: Scheduler, private val actions: Actions) {

    interface Actions {
        fun stopCore()

        /** Decline every still-ringing (INCOMING) call on the Core with 480 Temporarily Unavailable. */
        fun declineCalls()

        /** A call on the Core is answered or connected: the Core must not stop under it. */
        fun hasConnectedCall(): Boolean
        fun log(message: String)
    }

    var owned = false
        private set
    private var jobRunning = false
    private var takeover: Cancellable? = null
    private var flush: Cancellable? = null

    /** The job created the Core. */
    fun onCoreCreated() {
        owned = true
        jobRunning = true
    }

    /** A service is in the foreground with this Core. */
    fun onServiceTookOver() {
        if (!owned) return
        owned = false
        cancelTimers()
        actions.log("service took over the background registration's core")
    }

    fun onJobEnded(engineStopped: Boolean, liveCall: Boolean) {
        jobRunning = false
        if (!owned) return
        if (!engineStopped) {
            owned = false
            cancelTimers()
            actions.log("background registration over: core left to the starting service")
            return
        }
        if (liveCall || actions.hasConnectedCall()) {
            actions.log("background registration over: core kept for its call")
            return
        }
        release("background registration over: core stopped")
    }

    /** The service is being destroyed: true when it may stop the Core. */
    fun serviceMayStopCore(): Boolean = !owned

    /** A call arrived on the Core; [serviceUp] when a service holds it. */
    fun onIncomingCall(serviceUp: Boolean) {
        if (!owned || serviceUp || takeover != null || flush != null) return
        takeover = scheduler.schedule(TAKEOVER_MS) {
            takeover = null
            if (!owned || actions.hasConnectedCall()) return@schedule
            actions.log("call on the background core: no service took it over, declined 480")
            actions.declineCalls()
            flush = scheduler.schedule(DECLINE_FLUSH_MS) {
                flush = null
                if (owned && !actions.hasConnectedCall()) release("background core stopped after the declined call")
            }
        }
    }

    /** A call on the Core was answered: no decline, no release under it. */
    fun onCallAnswered() {
        if (!owned) return
        cancelTimers()
        actions.log("call answered on the background core: waiting for the service")
    }

    /** The Core's last call ended. */
    fun onLastCallEnded() {
        if (!owned) return
        if (jobRunning && flush == null) return
        if (actions.hasConnectedCall()) return
        release("background core stopped: its call ended")
    }

    private fun release(message: String) {
        owned = false
        cancelTimers()
        actions.declineCalls()
        actions.stopCore()
        actions.log(message)
    }

    private fun cancelTimers() {
        takeover?.cancel()
        takeover = null
        flush?.cancel()
        flush = null
    }

    companion object {
        const val TAKEOVER_MS = 10_000L
        const val DECLINE_FLUSH_MS = 2_000L
    }
}
