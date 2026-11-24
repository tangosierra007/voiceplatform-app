package au.com.voiceplatform.vp_linphone

import android.content.Context
import android.content.pm.ApplicationInfo
import java.io.File

/**
 * G8: a debug build may trust one extra CA for SIP TLS, the test stack's, so it
 * can register there. Release and profile builds never do (spec 22, S1).
 *
 * The app's debug build writes the CA to the raw resource [RESOURCE] from the
 * `VP_TEST_CA_B64` dart define (android/app/build.gradle.kts); no other build
 * type has that resource. This side also refuses it unless the app is
 * debuggable, so a release build ignores it even if the resource were there.
 * liblinphone then trusts its bundled roots plus that CA; the server
 * certificate and name are still verified.
 *
 * [rootCaData] is pure, so the rule runs in JVM unit tests.
 */
object TestCaTrust {

    /** The app's raw resource name (res/raw/vp_test_ca.pem, debug only). */
    const val RESOURCE = "vp_test_ca"

    private const val BEGIN = "-----BEGIN CERTIFICATE-----"

    /**
     * The root CA data to give liblinphone: [bundled] and then [testPem], or
     * null to keep liblinphone's own roots (not [debuggable], or no test CA).
     */
    fun rootCaData(debuggable: Boolean, testPem: String?, bundled: String?): String? {
        if (!debuggable) return null
        val pem = testPem?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        require("PRIVATE KEY" !in pem) { "$RESOURCE holds a private key; give the CA certificate only" }
        require(BEGIN in pem) { "$RESOURCE holds no PEM certificate" }
        val roots = bundled?.trimEnd()?.takeIf { it.isNotEmpty() }
        return listOfNotNull(roots, pem).joinToString("\n") + "\n"
    }

    /** Whether the app was built debuggable (only the debug build type is). */
    fun isDebuggable(context: Context): Boolean =
        (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    /** The app's test CA resource, or null (release and profile builds, or none given). */
    @Suppress("DiscouragedApi") // looked up by name: only the debug build has it
    fun testPem(context: Context): String? {
        val id = context.resources.getIdentifier(RESOURCE, "raw", context.packageName)
        if (id == 0) return null
        return context.resources.openRawResource(id).bufferedReader().use { it.readText() }
    }

    /**
     * The root CA data for this app, or null to leave liblinphone as it is.
     * [bundledPath] is liblinphone's own root CA file (Core.rootCa).
     */
    fun forApp(context: Context, bundledPath: String?): String? {
        if (!isDebuggable(context)) return null
        val pem = testPem(context) ?: return null
        val bundled = bundledPath?.let(::File)?.takeIf { it.isFile }?.readText()
        return rootCaData(true, pem, bundled)
    }
}
