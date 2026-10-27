package au.com.voiceplatform.vp_linphone

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** The account register() was given, as needed to re-register after a push wake. */
data class AccountRecord(
    val authUsername: String,
    val password: String,
    val domain: String,
    val outboundProxy: String,
    val displayName: String,
    val expiresSeconds: Int,
    val instanceId: String,
    val pushProvider: String?,
    val pushPrid: String?,
    val pushParam: String?,
) {
    override fun toString() = "AccountRecord($authUsername@$domain)"

    fun encode(): ByteArray {
        val fields = listOf(
            authUsername, password, domain, outboundProxy, displayName, expiresSeconds.toString(), instanceId,
            pushProvider, pushPrid, pushParam,
        )
        val sb = StringBuilder(VERSION_TAG)
        for (f in fields) {
            if (f == null) sb.append('-') else sb.append(f.length).append(':').append(f)
        }
        return sb.toString().toByteArray(Charsets.UTF_8)
    }

    companion object {
        private const val VERSION_TAG = "v1|"

        fun decode(bytes: ByteArray): AccountRecord? {
            val s = bytes.toString(Charsets.UTF_8)
            if (!s.startsWith(VERSION_TAG)) return null
            var i = VERSION_TAG.length
            val out = mutableListOf<String?>()
            while (i < s.length) {
                if (s[i] == '-') {
                    out += null
                    i++
                    continue
                }
                val colon = s.indexOf(':', i)
                if (colon < 0) return null
                val len = s.substring(i, colon).toIntOrNull() ?: return null
                val end = colon + 1 + len
                if (end > s.length) return null
                out += s.substring(colon + 1, end)
                i = end
            }
            if (out.size != 10) return null
            return AccountRecord(
                out[0] ?: return null, out[1] ?: return null, out[2] ?: return null, out[3] ?: return null,
                out[4] ?: return null, out[5]?.toIntOrNull() ?: return null, out[6] ?: return null,
                out[7], out[8], out[9],
            )
        }
    }
}

/**
 * Keeps the [AccountRecord] across process death so a push can wake the
 * engine and re-register while the app is not running (spec 22: credentials
 * in memory and the platform keystore only). AES-256-GCM with a key that
 * never leaves Android Keystore; the file is in noBackupFilesDir. Nothing
 * here is readable back through the Flutter API (APP4). Cleared by
 * unregister().
 */
class CredentialStore(context: Context) {
    private val file = File(context.noBackupFilesDir, "vp_linphone/account.bin")

    fun save(record: AccountRecord) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.doFinal(record.encode())
        file.parentFile?.mkdirs()
        file.writeBytes(byteArrayOf(cipher.iv.size.toByte()) + cipher.iv + sealed)
    }

    fun load(): AccountRecord? {
        if (!file.exists()) return null
        return runCatching {
            val bytes = file.readBytes()
            val ivLen = bytes[0].toInt()
            val iv = bytes.copyOfRange(1, 1 + ivLen)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
            AccountRecord.decode(cipher.doFinal(bytes.copyOfRange(1 + ivLen, bytes.size)))
        }.getOrNull()
    }

    fun clear() {
        file.delete()
    }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    companion object {
        private const val ALIAS = "vp_linphone_account"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
