package au.com.voiceplatform.vp_linphone

import java.io.File
import java.nio.file.Files
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class CallLogFileTest {

    private fun dir(): File = Files.createTempDirectory("vp_linphone_log").toFile()

    /** A clock that moves 1 s per reading, so every call has its own start. */
    private fun ticking(start: Long = 1_761_534_900_123L): () -> Long {
        var t = start
        return { t.also { t += 1000 } }
    }

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
        assertTrue(text.startsWith("2025 Oct 27 03:15:00.123Z WARNING"))
    }

    @Test
    fun theExportIsTheLastCallOnly() {
        val log = CallLogFile(dir(), LogScrubber(), clock = ticking())
        log.beginCall()
        log.write("ENGINE", "first call")
        log.endCall()
        log.beginCall()
        log.write("ENGINE", "second call")
        log.endCall()
        val text = log.export().toString(Charsets.UTF_8)
        assertFalse("first call" in text)
        assertTrue("second call" in text)
    }

    @Test
    fun keepsTheLastFiveCalls() {
        val log = CallLogFile(dir(), LogScrubber(), clock = ticking())
        repeat(7) { i ->
            log.beginCall()
            log.write("ENGINE", "call number $i")
            log.endCall()
        }
        val kept = log.keptFiles().map { it.readText() }
        assertEquals(5, kept.size)
        assertTrue(kept.first().contains("call number 2"))
        assertTrue(kept.last().contains("call number 6"))
    }

    @Test
    fun keepsWithinTheTotalSizeOldestFirst() {
        // 3 calls of ~3 KB each in 1 KB segments, 5 KB in all.
        val log = CallLogFile(dir(), LogScrubber(), segmentBytes = 1000, maxTotalBytes = 5000, clock = ticking())
        repeat(3) { c ->
            log.beginCall()
            repeat(60) { log.write("ENGINE", "call $c line $it of the call log") }
            log.endCall()
        }
        val files = log.keptFiles()
        assertTrue(files.sumOf { it.length() } <= 5000 + 1000, "total ${files.sumOf { it.length() }}")
        assertTrue(files.all { it.length() <= 1000 })
        // The oldest call went first, the newest call is whole.
        assertFalse(files.any { it.readText().contains("call 0 line") })
        val text = log.export().toString(Charsets.UTF_8)
        assertTrue("call 2 line 0 " in text)
        assertTrue("call 2 line 59 " in text)
        assertFalse(CallLogFile.ROTATED_MARKER in text)
    }

    @Test
    fun aVeryLongCallLosesItsStartAndSaysSo() {
        val log = CallLogFile(dir(), LogScrubber(), segmentBytes = 1000, maxTotalBytes = 3000, clock = ticking())
        log.beginCall()
        repeat(200) { log.write("ENGINE", "line $it of a long call") }
        val text = log.export().toString(Charsets.UTF_8)
        assertTrue(text.startsWith(CallLogFile.ROTATED_MARKER))
        assertFalse("line 0 of" in text)
        assertTrue("line 199 of" in text)
        assertTrue(log.keptFiles().sumOf { it.length() } <= 3000 + 1000)
    }

    @Test
    fun aClockGoingBackStillExportsTheNewestCallAndKeepsIt() {
        var now = 2_000_000_000_000L
        val log = CallLogFile(dir(), LogScrubber(), maxCalls = 2, clock = { now })
        log.beginCall()
        log.write("ENGINE", "older call")
        log.endCall()
        now -= 3_600_000 // the clock is set back an hour
        log.beginCall()
        log.write("ENGINE", "newer call")
        log.endCall()
        now -= 3_600_000
        log.beginCall()
        log.write("ENGINE", "newest call")
        log.endCall()
        assertTrue("newest call" in log.export().toString(Charsets.UTF_8))
        val kept = log.keptFiles().joinToString { it.readText() }
        assertTrue("newest call" in kept && "newer call" in kept)
        assertFalse("older call" in kept)
    }

    @Test
    fun twoCallsInTheSameMillisecondKeepTheirOwnLogs() {
        val log = CallLogFile(dir(), LogScrubber(), clock = { 1_761_534_900_123L })
        log.beginCall()
        log.write("ENGINE", "first call")
        log.endCall()
        log.beginCall()
        log.write("ENGINE", "second call")
        log.endCall()
        val files = log.keptFiles()
        assertEquals(2, files.size)
        assertTrue("first call" in files[0].readText())
        assertTrue("second call" in files[1].readText())
        assertTrue("second call" in log.export().toString(Charsets.UTF_8))
    }

    @Test
    fun nothingWritesToLogcat() {
        // The scrubbing sink is the only log; liblinphone's logcat output is off.
        val sources = File("src/main/kotlin").walk().filter { it.isFile && it.extension == "kt" }.toList()
        assertTrue(sources.isNotEmpty())
        val logcat = Regex("""\bLog\.(v|d|i|w|e|wtf)\(|\bprintln\(|printStackTrace\(""")
        for (f in sources) assertFalse(logcat.containsMatchIn(f.readText()), f.name)
        val engine = sources.single { it.name == "LinphoneEngine.kt" }.readText()
        assertTrue("enableLogcatLogs(false)" in engine)
    }

    @Test
    fun theLegacySingleFileIsRemoved() {
        val d = dir()
        File(d, "lastcall.log").writeText("old")
        CallLogFile(d, LogScrubber())
        assertFalse(File(d, "lastcall.log").exists())
    }
}
