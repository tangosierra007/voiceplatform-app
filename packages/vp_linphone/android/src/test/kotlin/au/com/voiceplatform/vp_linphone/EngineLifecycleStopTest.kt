package au.com.voiceplatform.vp_linphone

import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** When a destroyed service is reported to the app as `cleared` (WS6 on PR 53). */
class EngineLifecycleStopTest {

    private val lifecycle = EngineLifecycle(startService = {}, stopService = {})

    @Test
    fun aServiceTheAppStartedThatStopsUnderItIsReportedEvenWithNoAccount() {
        // Stopped mid-POST: no account yet, but the app thinks the engine runs.
        lifecycle.requestStart(byApp = true) {}
        assertTrue(lifecycle.stoppedUnderTheApp(hadAccount = false))
        assertTrue(lifecycle.stoppedUnderTheApp(hadAccount = true))
    }

    @Test
    fun aStopTheAppAskedForIsNotReported() {
        lifecycle.requestStart(byApp = true) {}
        lifecycle.onServiceCreated()
        lifecycle.onCoreStarted()
        lifecycle.requestStop {}
        assertFalse(lifecycle.stoppedUnderTheApp(hadAccount = false))
    }

    @Test
    fun aPushWakeAloneIsReportedOnlyWithAnAccount() {
        lifecycle.requestStart(byApp = false) {}
        assertFalse(lifecycle.stoppedUnderTheApp(hadAccount = false))
        assertTrue(lifecycle.stoppedUnderTheApp(hadAccount = true))
    }
}
