package au.com.voiceplatform.app.keys

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * The device key that binds this phone's refresh token (spec 22, Sign-in
 * item 6): a P-256 signing key in Android Keystore, in StrongBox when the
 * phone has one. The private key never leaves the Keystore; nothing here logs.
 */
class DeviceKeyStore(private val context: Context) : DeviceKeysApi {
    companion object {
        const val ALIAS = "voiceplatform.device.v1"
        private const val PROVIDER = "AndroidKeyStore"
        private const val B64 = Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING
    }

    private val keyStore: KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    override fun ensureKey(): DeviceKeyInfo {
        if (!keyStore.containsAlias(ALIAS)) generate()
        val cert = keyStore.getCertificate(ALIAS)
        return DeviceKeyInfo(
            publicKeySpki = Base64.encodeToString(cert.publicKey.encoded, B64),
            strongBox = isStrongBox(),
        )
    }

    override fun sign(message: String): String {
        if (!keyStore.containsAlias(ALIAS)) throw FlutterError("no_key", "No device key", null)
        val key = keyStore.getKey(ALIAS, null) as PrivateKey
        val sig = Signature.getInstance("SHA256withECDSA")
        sig.initSign(key)
        sig.update(message.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(sig.sign(), B64)
    }

    override fun deleteKey() {
        if (keyStore.containsAlias(ALIAS)) keyStore.deleteEntry(ALIAS)
    }

    private var generatedInStrongBox: Boolean? = null

    /** From the key itself on Android 12+; otherwise as generated this run. */
    private fun isStrongBox(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val key = keyStore.getKey(ALIAS, null) as PrivateKey
            val info = KeyFactory.getInstance(key.algorithm, PROVIDER).getKeySpec(key, KeyInfo::class.java)
            return info.securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX
        }
        return generatedInStrongBox ?: false
    }

    private fun generate() {
        val hasStrongBox = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        if (hasStrongBox) {
            try {
                generate(strongBox = true)
                generatedInStrongBox = true
                return
            } catch (e: StrongBoxUnavailableException) {
                // Fall back to the TEE-backed Keystore below.
            }
        }
        generate(strongBox = false)
        generatedInStrongBox = false
    }

    private fun generate(strongBox: Boolean) {
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .apply { if (strongBox) setIsStrongBoxBacked(true) }
            .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER).run {
            initialize(spec)
            generateKeyPair()
        }
    }
}
