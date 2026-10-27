package au.com.voiceplatform.vp_linphone

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class EngineStartupTest {

    private val steps = mutableListOf<String>()

    private fun run(foregroundFails: Boolean = false, setUpFails: Throwable? = null) = EngineStartup.run(
        goForeground = {
            steps += "foreground"
            if (foregroundFails) throw IllegalStateException("not allowed")
        },
        setUp = {
            steps += "setUp"
            setUpFails?.let { throw it }
        },
        report = { steps += "report ${it.javaClass.simpleName}" },
        stop = { steps += "stop" },
    )

    @Test
    fun foregroundComesFirstThenSetUp() {
        assertTrue(run())
        assertEquals(listOf("foreground", "setUp"), steps)
    }

    @Test
    fun aRefusedForegroundIsReportedAndStopsWithoutSetUp() {
        assertFalse(run(foregroundFails = true))
        assertEquals(listOf("foreground", "report IllegalStateException", "stop"), steps)
    }

    @Test
    fun aFailedSetUpAfterForegroundIsReportedAndStops() {
        assertFalse(run(setUpFails = IllegalStateException("Core.start failed")))
        assertEquals(listOf("foreground", "setUp", "report IllegalStateException", "stop"), steps)
    }

    @Test
    fun nativeLoadErrorsAreCaughtToo() {
        assertFalse(run(setUpFails = UnsatisfiedLinkError("liblinphone.so")))
        assertEquals(listOf("foreground", "setUp", "report UnsatisfiedLinkError", "stop"), steps)
    }
}
