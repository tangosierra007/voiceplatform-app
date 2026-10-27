import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
