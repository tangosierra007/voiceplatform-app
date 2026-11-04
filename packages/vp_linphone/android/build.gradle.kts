group = "au.com.voiceplatform.vp_linphone"
version = "0.1.0"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

// rootProject: the app that includes this plugin resolves liblinphone too.
rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
        // Belledonne's Maven repository, for liblinphone only.
        maven {
            url = uri("https://download.linphone.org/maven_repository")
            content { includeGroup("org.linphone") }
        }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "au.com.voiceplatform.vp_linphone"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 29
        consumerProguardFiles("consumer-rules.pro")
    }

    testOptions {
        unitTests {
            // Robolectric (the WorkManager tests) reads the merged manifest and resources.
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()
                it.outputs.upToDateWhen { false }
                it.testLogging {
                    events("passed", "skipped", "failed")
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

dependencies {
    // Pinned (spec 22, decision 135). Licence as found in the release's files: see NOTICE.
    implementation("org.linphone:linphone-sdk-android:5.5.39")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // The re-registration after a phone restart or an app update (ReregisterWorker).
    implementation("androidx.work:work-runtime-ktx:2.10.1")
    // The FCM token check in that job. The same BoM as firebase_core 5.1.0's
    // FirebaseSDKVersion, so the app resolves one firebase-messaging.
    implementation(platform("com.google.firebase:firebase-bom:35.1.0"))
    implementation("com.google.firebase:firebase-messaging")

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.junit.jupiter:junit-jupiter:5.12.2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    // WorkManager's test helpers need an Android Context: Robolectric, on JUnit 4
    // (run by the vintage engine beside the JUnit 5 tests).
    testImplementation("junit:junit:4.13.2")
    testRuntimeOnly("org.junit.vintage:junit-vintage-engine:5.12.2")
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("androidx.work:work-testing:2.10.1")
}
