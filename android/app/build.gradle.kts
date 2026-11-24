import com.android.build.api.artifact.SingleArtifact
import java.util.Base64
import java.util.Properties
import java.util.zip.ZipFile

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Upload key for Play (Play App Signing holds the app signing key).
// Read from, in order:
//   1. environment variables VP_UPLOAD_STORE_FILE, VP_UPLOAD_STORE_PASSWORD,
//      VP_UPLOAD_KEY_ALIAS, VP_UPLOAD_KEY_PASSWORD (CI), or
//   2. android/key.properties with storeFile, storePassword, keyAlias, keyPassword
//      (local builds; never committed, it is in .gitignore).
// A relative storeFile is resolved against android/. No key is ever committed
// to this repo, and there is no fallback to one.
// With no upload key: CI (CI=true) builds the release unsigned; a local build
// signs the release with this machine's debug key so `flutter run --release`
// works. VP_REQUIRE_UPLOAD_KEY=true (the Play upload job) makes a missing key
// an error.
data class UploadKey(val source: String, val storeFile: File, val storePassword: String, val keyAlias: String, val keyPassword: String)

val uploadKey: UploadKey? = run {
    val envNames = listOf("VP_UPLOAD_STORE_FILE", "VP_UPLOAD_STORE_PASSWORD", "VP_UPLOAD_KEY_ALIAS", "VP_UPLOAD_KEY_PASSWORD")
    val env = envNames.associateWith { System.getenv(it)?.takeIf(String::isNotBlank) }
    val propsFile = rootProject.file("key.properties")
    val (source, values) =
        when {
            env.values.any { it != null } -> "environment" to envNames.zip(listOf("storeFile", "storePassword", "keyAlias", "keyPassword")).associate { (e, k) -> k to env[e] }
            propsFile.isFile -> {
                val p = Properties().apply { propsFile.inputStream().use { load(it) } }
                "android/key.properties" to listOf("storeFile", "storePassword", "keyAlias", "keyPassword").associateWith { p.getProperty(it)?.takeIf(String::isNotBlank) }
            }
            else -> return@run null
        }
    val missing = values.filterValues { it == null }.keys
    if (missing.isNotEmpty()) throw GradleException("Upload key from $source is incomplete; missing: ${missing.joinToString()}")
    val store = rootProject.file(values.getValue("storeFile")!!)
    if (!store.isFile) throw GradleException("Upload keystore named by $source does not exist")
    UploadKey(source, store, values.getValue("storePassword")!!, values.getValue("keyAlias")!!, values.getValue("keyPassword")!!)
}
val isCi = System.getenv("CI") == "true"
if (uploadKey == null && System.getenv("VP_REQUIRE_UPLOAD_KEY") == "true") {
    throw GradleException("VP_REQUIRE_UPLOAD_KEY=true but no upload key is configured")
}

// G8: a debug build may trust the test stack's CA (spec 22, S1); release and
// profile builds never. The CA comes from the VP_TEST_CA_B64 dart define
// (base64 of the CA's PEM file, the certificate only), which the Flutter tool
// passes to Gradle in -Pdart-defines. Only the debug build type gets it: as
// res/raw/vp_test_ca.pem and a network security config that trusts it beside
// the system's CAs (native HTTPS, such as voicemail streaming); the Dart side
// (lib/net/test_ca.dart) and liblinphone (TestCaTrust.kt) read the same CA.
// The CA is never committed. vpCheck<Release|Profile>NoTestCa below fails a
// release or profile build whose output has any of it.
val testCaDefine = "VP_TEST_CA_B64"
val vpTestCaPem: String? = run {
    val defines = findProperty("dart-defines")?.toString().orEmpty()
        .split(',').filter(String::isNotBlank)
        .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    val b64 = defines.firstOrNull { it.startsWith("$testCaDefine=") }
        ?.substringAfter('=')?.trim()?.takeIf(String::isNotEmpty) ?: return@run null
    val pem =
        try {
            String(Base64.getDecoder().decode(b64), Charsets.UTF_8)
        } catch (e: IllegalArgumentException) {
            throw GradleException("$testCaDefine is not base64 of a PEM file")
        }
    if ("PRIVATE KEY" in pem) throw GradleException("$testCaDefine holds a private key; give the CA certificate only")
    if ("-----BEGIN CERTIFICATE-----" !in pem) throw GradleException("$testCaDefine holds no PEM certificate")
    pem
}

/** Writes the debug build's test CA resources (G8). */
abstract class VpTestCaResources : DefaultTask() {
    @get:Input abstract val pem: Property<String>

    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val template: RegularFileProperty

    @get:OutputDirectory abstract val outputDir: DirectoryProperty

    @TaskAction
    fun write() {
        val out = outputDir.get().asFile
        out.deleteRecursively()
        File(out, "raw").mkdirs()
        File(out, "xml").mkdirs()
        File(out, "raw/vp_test_ca.pem").writeText(pem.get())
        template.get().asFile.copyTo(File(out, "xml/network_security_config_test_ca.xml"), overwrite = true)
    }
}

/**
 * Fails a release or profile build that has any part of the test CA (G8): a
 * network security config in the merged manifest, the debug build's resource
 * names in the APK's or bundle's resource table, or (when the define was given
 * to this build anyway) the CA's own text anywhere in the archive.
 */
abstract class VpNoTestCaCheck : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val mergedManifest: RegularFileProperty

    @get:Internal abstract val outputsDir: DirectoryProperty

    @get:Input abstract val variantName: Property<String>

    /** The given CA's longest base64 line, or empty when none was given. */
    @get:Input abstract val caMarker: Property<String>

    @TaskAction
    fun check() {
        val problems = mutableListOf<String>()
        if ("networkSecurityConfig" in mergedManifest.get().asFile.readText()) {
            problems += "the merged manifest sets android:networkSecurityConfig"
        }
        val archives = outputsDir.get().asFile.walkTopDown()
            .filter { it.isFile && it.extension in setOf("apk", "aab") && it.parentFile.name == variantName.get() }
            .toList()
        val marker = caMarker.get().toByteArray(Charsets.US_ASCII)
        val tables = setOf("resources.arsc", "base/resources.pb")
        val names = listOf("vp_test_ca", "network_security_config")
        for (a in archives) {
            ZipFile(a).use { zip ->
                for (e in zip.entries()) {
                    if (e.isDirectory) continue
                    if (names.any { it in e.name }) problems += "${a.name}: has ${e.name}"
                    val readTable = e.name in tables
                    if (!readTable && marker.isEmpty()) continue
                    val bytes = zip.getInputStream(e).use { it.readBytes() }
                    val text = String(bytes, Charsets.ISO_8859_1)
                    if (readTable) names.filter { it in text }.forEach { problems += "${a.name}: ${e.name} names $it" }
                    if (marker.isNotEmpty() && caMarker.get() in text) problems += "${a.name}: ${e.name} holds the test CA"
                }
            }
        }
        if (problems.isNotEmpty()) {
            throw GradleException("G8: the ${variantName.get()} build must not trust the test CA:\n" + problems.joinToString("\n"))
        }
        logger.lifecycle("G8: ${variantName.get()} build has no test CA (merged manifest and ${archives.size} archive(s) checked: ${archives.joinToString { it.name }})")
    }
}

android {
    namespace = "au.com.voiceplatform.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Registered in Play Console and Firebase; permanent (spec 22).
        applicationId = "au.com.voiceplatform.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (uploadKey != null) {
            create("upload") {
                storeFile = uploadKey.storeFile
                storePassword = uploadKey.storePassword
                keyAlias = uploadKey.keyAlias
                keyPassword = uploadKey.keyPassword
            }
        }
    }

    buildTypes {
        debug {
            // src/debug/AndroidManifest.xml; G8: the test CA's config when one is given.
            manifestPlaceholders["vpNetworkSecurityConfig"] =
                if (vpTestCaPem != null) "@xml/network_security_config_test_ca" else "@xml/network_security_config"
        }
        release {
            signingConfig =
                when {
                    uploadKey != null -> {
                        logger.lifecycle("Release signing: upload key from ${uploadKey.source}")
                        signingConfigs.getByName("upload")
                    }
                    isCi -> {
                        logger.warn("Release signing: no upload key configured; the release build is UNSIGNED")
                        null
                    }
                    else -> {
                        logger.warn("Release signing: no upload key configured; signing with the local debug key (not for Play)")
                        signingConfigs.getByName("debug")
                    }
                }
        }
    }
}

androidComponents {
    onVariants(selector().withBuildType("debug")) { variant ->
        val pem = vpTestCaPem ?: return@onVariants
        val task = tasks.register<VpTestCaResources>("vpTestCa${variant.name.replaceFirstChar(Char::uppercase)}Resources") {
            this.pem.set(pem)
            template.set(layout.projectDirectory.file("test-ca/network_security_config_test_ca.xml"))
        }
        variant.sources.res?.addGeneratedSourceDirectory(task, VpTestCaResources::outputDir)
        logger.lifecycle("G8: the ${variant.name} build trusts the test stack CA from $testCaDefine")
    }
    for (buildType in listOf("release", "profile")) {
        onVariants(selector().withBuildType(buildType)) { variant ->
            val v = variant.name.replaceFirstChar(Char::uppercase)
            if (vpTestCaPem != null) logger.warn("G8: $testCaDefine is ignored by the ${variant.name} build")
            val marker = vpTestCaPem?.lines()?.filter { !it.startsWith("-----") }?.maxByOrNull { it.length }?.trim().orEmpty()
            val check = tasks.register<VpNoTestCaCheck>("vpCheck${v}NoTestCa") {
                mergedManifest.set(variant.artifacts.get(SingleArtifact.MERGED_MANIFEST))
                outputsDir.set(layout.buildDirectory.dir("outputs"))
                variantName.set(variant.name)
                caMarker.set(marker)
                outputs.upToDateWhen { false }
                mustRunAfter(tasks.matching { it.name == "assemble$v" || it.name == "bundle$v" })
            }
            tasks.matching { it.name == "assemble$v" || it.name == "bundle$v" }.configureEach { finalizedBy(check) }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
