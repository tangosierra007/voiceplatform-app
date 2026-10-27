package au.com.voiceplatform.vp_linphone

import java.io.File
import java.nio.file.Files
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class CallLogFileTest {

    private fun dir(): File = Files.createTempDirectory("vp_linphone_log").toFile()

    @Test
    fun nothingBeforeTheFirstCall() {
        val log = CallLogFile(dir(), LogScrubber())
        log.write("ENGINE", "registration Ok")
        assertEquals(0, log.export().size)
    }

    @Test
    fun leadInAndCallLinesAreKeptScrubbed() {
        val s = LogScrubber().apply { addSecret("testpasswordtestpassword") }
        val log = CallLogFile(dir(), s, clock = { 1_761_534_900_123L })
        log.write("WARNING", "REGISTER with password testpasswordtestpassword")
        log.beginCall()
        log.write("ENGINE", "call call-1 from 0491 570 737")
        log.endCall()
        log.write("ENGINE", "after the call")
        val text = log.export().toString(Charsets.UTF_8)
        assertTrue("REGISTER with password [scrubbed]" in text)
        assertTrue("call call-1 from [n]" in text)
        assertFalse("after the call" in text)
        assertFalse("testpasswordtestpassword" in text)
        assertFalse(Regex("""\d{6,}""").containsMatchIn(text))
        // The timestamp survives the second scrub on export.
        assertTrue(text.startsWith("2025 Oct 27 03:15:00.123Z WARNING"))
    }

    @Test
    fun aNewCallStartsAFreshLog() {
        val log = CallLogFile(dir(), LogScrubber())
        log.beginCall()
        log.write("ENGINE", "first call")
        log.endCall()
        log.beginCall()
        log.write("ENGINE", "second call")
        val text = log.export().toString(Charsets.UTF_8)
        assertFalse("first call" in text)
        assertTrue("second call" in text)
    }

    @Test
    fun rotatesAtTheSizeLimit() {
        val d = dir()
        val log = CallLogFile(d, LogScrubber(), maxBytes = 1000)
        log.beginCall()
        repeat(100) { log.write("ENGINE", "line $it of the call log") }
        assertTrue(File(d, "lastcall.log.1").exists())
        assertTrue(File(d, "lastcall.log").length() <= 1000)
        val text = log.export().toString(Charsets.UTF_8)
        assertTrue("line 99 " in text)
        assertTrue(text.length <= 2000)
    }
}
