package au.com.voiceplatform.vp_linphone

/**
 * The order [EngineService.onCreate] starts in, kept apart so a JVM test can
 * check it: the foreground notification and `startForeground` (plain
 * `phoneCall` type) come first, before anything else that can throw, so the
 * system's start-foreground deadline is always met. If that or the later set-up
 * (loading liblinphone, creating and starting the Core) fails, the failure is
 * reported once and the service stops itself.
 */
internal object EngineStartup {
    /** Returns true when the engine is up. */
    fun run(
        goForeground: () -> Unit,
        setUp: () -> Unit,
        report: (Throwable) -> Unit,
        stop: () -> Unit,
    ): Boolean {
        try {
            goForeground()
        } catch (t: Throwable) {
            report(t)
            stop()
            return false
        }
        try {
            setUp()
        } catch (t: Throwable) {
            // Includes UnsatisfiedLinkError if liblinphone's native code can't load.
            report(t)
            stop()
            return false
        }
        return true
    }
}
