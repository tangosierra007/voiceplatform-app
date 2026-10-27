package au.com.voiceplatform.vp_linphone

import java.io.File
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * The rotating file log for the most recent call ("Send call logs to support").
 *
 * Every line is scrubbed before it reaches memory or disk. Lines outside a
 * call go to a small in-memory ring only (the lead-in: the REGISTER and setup
 * just before the call). When the first call starts the file is restarted with
 * that lead-in; lines are written until [endCall]. The file rotates once at
 * [maxBytes] (`lastcall.log` -> `lastcall.log.1`), so at most twice that is
 * kept. [export] returns both parts, oldest first.
 */
class CallLogFile(
    private val dir: File,
    private val scrubber: LogScrubber,
    private val maxBytes: Long = 512 * 1024,
    private val leadInLines: Int = 200,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val current = File(dir, "lastcall.log")
    private val previous = File(dir, "lastcall.log.1")
    private val ring = ArrayDeque<String>()
    private var inCall = false
    // "2026 Oct 27 03:15:00.123Z": no run of 6 digits, so scrubbing the whole
    // line again (on export, and in Dart) leaves the timestamp intact.
    private val format = SimpleDateFormat("yyyy MMM dd HH:mm:ss.SSS'Z'", Locale.ROOT).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    @Synchronized
    fun write(level: String, message: String) {
        val line = "${format.format(Date(clock()))} $level ${scrubber.scrub(message)}"
        if (inCall) {
            append(line)
        } else {
            ring.addLast(line)
            while (ring.size > leadInLines) ring.removeFirst()
        }
    }

    @Synchronized
    fun beginCall() {
        if (inCall) return
        inCall = true
        dir.mkdirs()
        previous.delete()
        current.writeText("")
        for (line in ring) append(line)
        ring.clear()
    }

    @Synchronized
    fun endCall() {
        inCall = false
    }

    @Synchronized
    fun export(): ByteArray {
        val parts = listOf(previous, current).filter { it.exists() }
        // Scrubbed again on the way out: a rule added later still applies.
        val text = parts.joinToString("") { it.readText() }
        return text.lineSequence().joinToString("\n") { scrubber.scrub(it) }.toByteArray(Charsets.UTF_8)
    }

    @Synchronized
    fun clear() {
        ring.clear()
        previous.delete()
        current.delete()
    }

    private fun append(line: String) {
        if (current.exists() && current.length() + line.length + 1 > maxBytes) {
            previous.delete()
            current.renameTo(previous)
        }
        current.appendText(line + "\n")
    }
}
