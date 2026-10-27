package au.com.voiceplatform.vp_linphone

/**
 * Removes secrets and personal data from a log line before it is written
 * anywhere (spec 22, Diagnostics; APP4, APP9). The same rules are mirrored in
 * Dart (lib/src/log_scrubber.dart), which scrubs the exported bytes again.
 *
 * Removed: SIP Authorization and Proxy-Authorization values, digest
 * parameters, password-like key/value pairs, push tokens (pn-prid), bearer
 * tokens, any exact secret registered with [addSecret], email addresses (SIP
 * URIs are kept), and runs of 6 or more digits (phone numbers), which may be
 * broken by single spaces, dashes or brackets.
 */
class LogScrubber {
    private val secrets = LinkedHashSet<String>()

    /** Registers an exact value (the SIP password, the push token) to remove. */
    @Synchronized
    fun addSecret(value: String?) {
        if (value != null && value.length >= MIN_SECRET_LENGTH) secrets.add(value)
    }

    @Synchronized
    fun clearSecrets() = secrets.clear()

    fun scrub(line: String): String {
        var out = line
        val known = synchronized(this) { secrets.toList() }
        // Exact secrets first, longest first, before any rule can split them.
        for (s in known.sortedByDescending { it.length }) out = out.replace(s, REDACTED)
        for ((regex, replacement) in RULES) out = regex.replace(out, replacement)
        return out
    }

    companion object {
        const val REDACTED = "[scrubbed]"
        const val NUMBER = "[n]"
        const val EMAIL = "[email]"
        private const val MIN_SECRET_LENGTH = 4

        private val RULES: List<Pair<Regex, String>> = listOf(
            // Whole value of an Authorization or Proxy-Authorization header.
            Regex("""(?i)\b((?:Proxy-)?Authorization\s*:)[^\r\n]*""") to "$1 $REDACTED",
            // Digest parameters wherever they appear (WWW-Authenticate too).
            Regex("""(?i)\b(response|cnonce|nonce|opaque|nc)\s*=\s*("[^"]*"|[^,\s;>]+)""") to "$1=$REDACTED",
            // password=..., passwd: ..., ha1 = "...", secret=...
            Regex("""(?i)\b(password|passwd|pwd|ha1|secret)(\s*[=:]\s*)("[^"]*"|[^\s,;&>]+)""") to "$1$2$REDACTED",
            // RFC 8599 push token and other tokens.
            Regex("""(?i)\b(pn-prid|prid|token|access_token|refresh_token)\s*=\s*("[^"]*"|[^;,\s>&]+)""") to "$1=$REDACTED",
            Regex("""(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+""") to "Bearer $REDACTED",
            // Email addresses; a SIP or tel URI's user@host is left alone.
            Regex("""(?<![\w.%+-])(?<!sips:)(?<!sip:)(?<!tel:)[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}""") to EMAIL,
            // Runs of 6 or more digits, allowing up to two of " -()" between digits.
            Regex("""\+?\d(?:[ ()\-]{0,2}\d){5,}""") to NUMBER,
        )
    }
}
