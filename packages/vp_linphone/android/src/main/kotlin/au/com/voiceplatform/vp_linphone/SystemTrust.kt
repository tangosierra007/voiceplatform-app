package au.com.voiceplatform.vp_linphone

import java.io.File
import java.security.KeyStore
import java.security.cert.X509Certificate
import java.util.Base64

/**
 * The trust anchors for the engine's SIP TLS: Android's system certificate
 * store, the same one the app's HTTPS client trusts, instead of the static
 * `rootca.pem` snapshot inside the liblinphone SDK. The system store is
 * updated with the OS (on Android 14 and later through the Conscrypt module),
 * so a new root such as ISRG Root YE is trusted as soon as Android trusts it.
 *
 * Only system CAs (`system:` aliases of `AndroidCAStore`) are used: never
 * user-installed CAs, as Android's own default for apps. Certificate
 * verification and the CN check stay on; this changes only which roots are
 * trusted.
 *
 * The roots are written as one PEM file and given to liblinphone as a path
 * (`Core.rootCa`), not as data: belle-sip accepts a file in which some
 * certificates don't parse (mbedTLS skips them), but rejects the whole
 * bundle if one certificate in a data string doesn't.
 */
object SystemTrust {

    /** One trusted certificate as the store lists it. */
    data class Entry(val alias: String, val certificate: X509Certificate)

    /** System CAs only: Android's own aliases are `system:<hash>.<n>`; `user:` ones are user-installed. */
    fun isSystem(alias: String): Boolean = alias.startsWith("system:")

    /** PEM, 64 characters a line, one block per certificate, in [entries]' order, without duplicates. */
    fun pem(entries: List<Entry>): String {
        val encoder = Base64.getMimeEncoder(64, "\n".toByteArray())
        val seen = HashSet<String>()
        val out = StringBuilder()
        for (e in entries) {
            if (!isSystem(e.alias)) continue
            val der = e.certificate.encoded
            if (!seen.add(Base64.getEncoder().encodeToString(der))) continue
            out.append("-----BEGIN CERTIFICATE-----\n")
            out.append(encoder.encodeToString(der))
            out.append("\n-----END CERTIFICATE-----\n")
        }
        return out.toString()
    }

    /** Every entry of Android's `AndroidCAStore` (system and user; [pem] keeps the system ones). */
    fun androidStore(): List<Entry> {
        val ks = KeyStore.getInstance("AndroidCAStore")
        ks.load(null)
        return ks.aliases().toList().mapNotNull { alias ->
            (ks.getCertificate(alias) as? X509Certificate)?.let { Entry(alias, it) }
        }
    }

    /** What [install] did. */
    sealed class Result {
        /** [count] system roots written to [file]: the Core uses it. */
        data class Installed(val file: File, val count: Int) : Result()

        /** No system roots could be read: the Core keeps the SDK's `rootca.pem`. Verification stays on. */
        data class Unavailable(val why: String) : Result()
    }

    /**
     * Writes the system roots from [store] to [file] (replaced atomically)
     * and returns the result. [store] is [androidStore] on a device.
     */
    fun install(file: File, store: () -> List<Entry>): Result {
        val entries = try {
            store()
        } catch (e: Exception) {
            return Result.Unavailable(e.javaClass.simpleName)
        }
        val text = pem(entries)
        val count = BEGIN.findAll(text).count()
        if (count == 0) return Result.Unavailable("no system certificates")
        return try {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(text, Charsets.US_ASCII)
            if (!tmp.renameTo(file)) {
                file.delete()
                if (!tmp.renameTo(file)) return Result.Unavailable("could not write ${file.name}")
            }
            Result.Installed(file, count)
        } catch (e: Exception) {
            Result.Unavailable(e.javaClass.simpleName)
        }
    }

    private val BEGIN = Regex("-----BEGIN CERTIFICATE-----")
}
