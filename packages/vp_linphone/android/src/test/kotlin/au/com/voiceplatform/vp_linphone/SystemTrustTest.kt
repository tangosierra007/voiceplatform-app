package au.com.voiceplatform.vp_linphone

import java.io.File
import java.nio.file.Files
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The engine's SIP TLS trusts Android's system store (public ISRG roots as fixtures). */
class SystemTrustTest {

    private val cf = CertificateFactory.getInstance("X.509")
    private fun load(name: String) =
        File("src/test/resources/trust/$name").inputStream().use { cf.generateCertificate(it) as X509Certificate }

    private val x1 = load("isrg-root-x1.pem")
    private val x2 = load("isrg-root-x2.pem")

    private fun parse(pem: String): List<X509Certificate> =
        cf.generateCertificates(pem.byteInputStream()).map { it as X509Certificate }

    @Test
    fun onlySystemCasAreTrustedNeverUserInstalledOnes() {
        assertTrue(SystemTrust.isSystem("system:6187b673.0"))
        assertFalse(SystemTrust.isSystem("user:6187b673.0"))
        assertFalse(SystemTrust.isSystem("6187b673.0"))
        val pem = SystemTrust.pem(
            listOf(
                SystemTrust.Entry("system:6187b673.0", x1),
                SystemTrust.Entry("user:0b9bbbd8.0", x2),
            ),
        )
        assertEquals(listOf(x1), parse(pem))
    }

    @Test
    fun thePemRoundTripsInOrderWithoutDuplicates() {
        val pem = SystemTrust.pem(
            listOf(
                SystemTrust.Entry("system:6187b673.0", x1),
                SystemTrust.Entry("system:0b9bbbd8.0", x2),
                SystemTrust.Entry("system:6187b673.1", x1),
            ),
        )
        assertEquals(listOf(x1, x2), parse(pem))
        for (line in pem.lines()) assertTrue(line.length <= 64, line)
        assertTrue(pem.startsWith("-----BEGIN CERTIFICATE-----\n"))
        assertTrue(pem.endsWith("-----END CERTIFICATE-----\n"))
    }

    @Test
    fun installWritesTheSystemRootsAndReplacesAnOldFile() {
        val dir = Files.createTempDirectory("trust").toFile()
        try {
            val file = File(dir, "vp_linphone/system-roots.pem")
            file.parentFile!!.mkdirs()
            file.writeText("old")
            val r = SystemTrust.install(file) {
                listOf(SystemTrust.Entry("system:a.0", x1), SystemTrust.Entry("system:b.0", x2))
            }
            assertIs<SystemTrust.Result.Installed>(r)
            assertEquals(2, r.count)
            assertEquals(listOf(x1, x2), parse(file.readText()))
            assertFalse(File(file.parentFile, file.name + ".tmp").exists())
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun withoutReadableSystemRootsTheSdkBundleStays() {
        val dir = Files.createTempDirectory("trust").toFile()
        try {
            val file = File(dir, "system-roots.pem")
            assertIs<SystemTrust.Result.Unavailable>(SystemTrust.install(file) { error("no AndroidCAStore") })
            assertIs<SystemTrust.Result.Unavailable>(SystemTrust.install(file) { emptyList() })
            assertIs<SystemTrust.Result.Unavailable>(
                SystemTrust.install(file) { listOf(SystemTrust.Entry("user:a.0", x1)) },
            )
            assertFalse(file.exists())
        } finally {
            dir.deleteRecursively()
        }
    }

    private val engine = File("src/main/kotlin/au/com/voiceplatform/vp_linphone/LinphoneEngine.kt").readText()

    @Test
    fun theCoreUsesTheSystemRootsBeforeItStartsAndStillVerifies() {
        val start = engine.substringAfter("private fun startCore(").substringBefore("core = c")
        val roots = start.indexOf("useSystemRoots(c, context)")
        assertTrue(roots > start.indexOf("configure(c)"), "after configure")
        assertTrue(roots < start.indexOf("c.start()"), "before the Core starts")
        assertTrue("c.rootCa = r.file.absolutePath" in engine)
        assertTrue("SystemTrust.install(file, SystemTrust::androidStore)" in engine)
        // Verification and the CN check stay on; nothing turns them off.
        assertTrue("c.verifyServerCertificates(true)" in engine)
        assertTrue("c.verifyServerCn(true)" in engine)
        val sources = File("src/main/kotlin").walk().filter { it.isFile && it.extension == "kt" }
        for (f in sources) {
            val text = f.readText()
            assertFalse(Regex("""verifyServerCertificates\(\s*false""").containsMatchIn(text), f.name)
            assertFalse(Regex("""verifyServerCn\(\s*false""").containsMatchIn(text), f.name)
            assertFalse("tlsVerifyException" in text || "setTlsCertificateVerify" in text, f.name)
        }
    }
}
