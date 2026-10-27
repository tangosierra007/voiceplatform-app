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
    }

    testOptions {
        unitTests {
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

    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.junit.jupiter:junit-jupiter:5.12.2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}
