package au.com.voiceplatform.vp_linphone

import java.io.File
import java.text.SimpleDateFormat
import java.util.ArrayDeque
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * The engine's rotating per-call logs ("Send call logs to support"; spec 22
 * Diagnostics, decision 140; APP9).
 *
 * - Every line is scrubbed ([LogScrubber]) before it reaches memory or disk;
 *   this is the only writer.
 * - Lines outside a call go to a small in-memory ring (the lead-in: REGISTER
 *   and set-up just before the call). [beginCall] starts the call's files with
 *   that lead-in; lines go to them until [endCall].
 * - A call's log is a series of segments `calls/<call>-<n>.log` (calls numbered
 *   in order, not by the clock) of at most
 *   [segmentBytes]. The logs of the last [maxCalls] calls are kept, within
 *   [maxTotalBytes] in all, whichever limit comes first; the oldest segments
 *   go first, so a very long call loses its beginning (the export says so).
 * - The directory is app-private and excluded from backup (noBackupFilesDir).
 */
class CallLogFile(
    dir: File,
    private val scrubber: LogScrubber,
    private val segmentBytes: Long = 1024 * 1024,
    private val maxCalls: Int = 5,
    private val maxTotalBytes: Long = 10L * 1024 * 1024,
    private val leadInLines: Int = 200,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val callsDir = File(dir, "calls")
    private val ring = ArrayDeque<String>()
    private var currentCall: String? = null
    private var segment = 0
    private var currentFile: File? = null

    // "2026 Oct 27 03:15:00.123Z": no run of 6 digits, so scrubbing the whole
    // line again (on export, and in Dart) leaves the timestamp intact.
    private val format = SimpleDateFormat("yyyy MMM dd HH:mm:ss.SSS'Z'", Locale.ROOT).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    init {
        // 3.1's single-file log.
        File(dir, "lastcall.log").delete()
        File(dir, "lastcall.log.1").delete()
    }

    val inCall: Boolean @Synchronized get() = currentCall != null

    @Synchronized
    fun write(level: String, message: String) {
        val line = "${format.format(Date(clock()))} $level ${scrubber.scrub(message)}"
        if (currentCall != null) {
            append(line)
        } else {
            ring.addLast(line)
            while (ring.size > leadInLines) ring.removeFirst()
        }
    }

    @Synchronized
    fun beginCall() {
        if (currentCall != null) return
        callsDir.mkdirs()
        // Numbered, not timed: a clock that goes back or two starts in the same
        // millisecond must not reorder or overwrite calls.
        val next = (callKeys().lastOrNull()?.toLongOrNull() ?: 0L) + 1
        currentCall = "%013d".format(next)
        segment = 0
        currentFile = segmentFile(currentCall!!, 0).also { it.writeText("") }
        for (line in ring) append(line)
        ring.clear()
        enforceLimits()
    }

    @Synchronized
    fun endCall() {
        currentCall = null
        currentFile = null
    }

    /**
     * The last call's log as plain text, scrubbed again. Starts with a marker
     * when rotation removed its beginning. Empty when no call has been logged.
     */
    @Synchronized
    fun export(): ByteArray {
        val calls = callKeys()
        val key = currentCall ?: calls.lastOrNull() ?: return ByteArray(0)
        val parts = segments(key)
        if (parts.isEmpty()) return ByteArray(0)
        val sb = StringBuilder()
        if (seqOf(parts.first()) > 0) sb.append(ROTATED_MARKER).append('\n')
        for (f in parts) {
            for (line in f.readLines()) sb.append(scrubber.scrub(line)).append('\n')
        }
        return sb.toString().toByteArray(Charsets.UTF_8)
    }

    @Synchronized
    fun clear() {
        ring.clear()
        callsDir.listFiles()?.forEach { it.delete() }
    }

    /** For tests: the files kept, oldest first. */
    @Synchronized
    fun keptFiles(): List<File> = allSegments()

    private fun append(line: String) {
        var f = currentFile ?: return
        val bytes = line.toByteArray(Charsets.UTF_8).size + 1
        if (f.length() > 0 && f.length() + bytes > segmentBytes) {
            segment++
            f = segmentFile(currentCall!!, segment)
            currentFile = f
            f.writeText("")
            enforceLimits()
        }
        f.appendText(line + "\n")
    }

    private fun enforceLimits() {
        var calls = callKeys()
        while (calls.size > maxCalls) {
            segments(calls.first()).forEach { it.delete() }
            calls = callKeys()
        }
        var files = allSegments()
        var total = files.sumOf { it.length() }
        // Oldest first; never the segment being written.
        for (f in files) {
            if (total <= maxTotalBytes) break
            if (f == currentFile) continue
            total -= f.length()
            f.delete()
        }
    }

    private fun segmentFile(key: String, seq: Int) = File(callsDir, "$key-${"%04d".format(seq)}.log")

    private fun allSegments(): List<File> =
        callsDir.listFiles { f -> NAME.matches(f.name) }.orEmpty().sortedBy { it.name }

    private fun callKeys(): List<String> = allSegments().map { it.name.substringBefore('-') }.distinct()

    private fun segments(key: String): List<File> = allSegments().filter { it.name.startsWith("$key-") }

    private fun seqOf(f: File): Int = f.name.substringAfter('-').substringBefore('.').toInt()

    companion object {
        const val ROTATED_MARKER = "[vp_linphone: the start of this call's log was rotated out]"
        private val NAME = Regex("""^\d{13}-\d{4}\.log$""")
    }
}
