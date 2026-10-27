package au.com.voiceplatform.vp_linphone

/** The start of the engine was called off (a stop came while it was starting). */
class StartCancelled : RuntimeException("Engine start cancelled")

/**
 * Start and stop of the foreground service and its Core, free of Android
 * types for JVM tests. A stop that arrives while the service is still
 * starting is not lost: the service is stopped as soon as it is in the
 * foreground (stopping it before then would break the start-foreground
 * contract), and the start's callbacks get [StartCancelled] so nothing
 * registers. A start from the app after that stop wins over it.
 */
class EngineLifecycle(
    private val startService: () -> Unit,
    private val stopService: () -> Unit,
) {
    enum class State { STOPPED, STARTING, RUNNING }

    var state = State.STOPPED
        private set

    /** True when CallEngine.start() asked; a push wake alone leaves it false. */
    var startedByApp = false
        private set

    private var stopWhenStarted = false
    private val startWaiters = mutableListOf<(Throwable?) -> Unit>()
    private val stopWaiters = mutableListOf<() -> Unit>()

    fun requestStart(byApp: Boolean, done: (Throwable?) -> Unit) {
        if (byApp) {
            startedByApp = true
            stopWhenStarted = false
        }
        when (state) {
            State.RUNNING -> done(null)
            State.STARTING -> startWaiters += done
            State.STOPPED -> {
                state = State.STARTING
                startWaiters += done
                try {
                    startService()
                } catch (e: RuntimeException) {
                    onStartFailed(e)
                }
            }
        }
    }

    fun requestStop(done: () -> Unit) {
        startedByApp = false
        when (state) {
            State.STOPPED -> done()
            State.STARTING -> {
                stopWhenStarted = true
                stopWaiters += done
            }
            State.RUNNING -> {
                stopWaiters += done
                stopService()
            }
        }
    }

    /** The service is in the foreground. Returns true when the Core should start. */
    fun onServiceCreated(): Boolean {
        if (!stopWhenStarted) return true
        stopWhenStarted = false
        finishStart(StartCancelled())
        stopService()
        return false
    }

    fun onCoreStarted() {
        state = State.RUNNING
        finishStart(null)
    }

    fun onStartFailed(error: Throwable) {
        state = State.STOPPED
        stopWhenStarted = false
        finishStart(error)
        finishStop()
    }

    fun onServiceDestroyed() {
        state = State.STOPPED
        stopWhenStarted = false
        finishStart(StartCancelled())
        finishStop()
    }

    private fun finishStart(error: Throwable?) {
        val waiters = startWaiters.toList()
        startWaiters.clear()
        waiters.forEach { it(error) }
    }

    private fun finishStop() {
        val waiters = stopWaiters.toList()
        stopWaiters.clear()
        waiters.forEach { it() }
    }
}
