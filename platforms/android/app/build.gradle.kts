import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
}

android {
    namespace = "com.smartdolphin.vpn"
    compileSdk = 36
    // NDK 26.x is the only fully-installed NDK here; 27.0.12077973 is a partial
    // (failed) install missing build/cmake/android.toolchain.cmake. The plugin
    // "wants NDK 27" message is just a warning — NDK is backward compatible.
    ndkVersion = "26.1.10909125"

    val signingProperties = Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }
    val releaseStoreFile = signingProperties.getProperty("storeFile")
    val releaseSigning = if (!releaseStoreFile.isNullOrBlank()) {
        signingConfigs.create("smartDolphinRelease") {
            storeFile = rootProject.file(releaseStoreFile)
            storePassword = signingProperties.getProperty("storePassword")
            keyAlias = signingProperties.getProperty("keyAlias")
            keyPassword = signingProperties.getProperty("keyPassword")
        }
    } else null

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
        freeCompilerArgs += "-Xjvm-default=all"
    }

    defaultConfig {
        applicationId = "com.smartdolphin.vpn"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode?.toInt() ?: 1
        versionName = flutter.versionName ?: "1.0.0"
        multiDexEnabled = true
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            versionNameSuffix = ""
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = releaseSigning
                ?: error("Release signing requires platforms/android/key.properties")
            // Avoid llvm-strip/llvm-objcopy on Windows when NDK tools fail to launch (e.g. network drive).
            ndk {
                debugSymbolLevel = "NONE"
            }
        }
        debug {
            isMinifyEnabled = false
        }
    }

    buildFeatures {
        viewBinding = true
    }

    lint {
        disable += "InvalidPackage"
        checkReleaseBuilds = false
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            // Release libraries are stripped by AGP/NDK. Keeping debug symbols
            // here made the universal APK exceed 170 MB and the arm64 APK 74 MB.
        }
    }
}


flutter {
    // Gradle canonicalizes the Android junction to platforms/android. Point to
    // the real Flutter project so lib/main.dart remains reachable either way.
    source = "../../../apps/mobile-flutter"
}

// Local Dolphin-Core (Go/libbox) archive lives in app/libs.
repositories {
    flatDir { dirs("libs") }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    // Dolphin-Core engine (the entire VPN backend, compiled Go).
    implementation(":libbox@aar")
}

// Flutter applies generated metadata late in this shared Android project.
// Preserve the version passed by `flutter build` instead of hardcoding it.
androidComponents {
    val bridgeVersionName = providers.gradleProperty("bridgeVersionName").orNull
    onVariants(selector().withBuildType("release")) { variant ->
        variant.outputs.forEach { output ->
            output.versionName.set(bridgeVersionName ?: flutter.versionName ?: "1.0.0")
            output.versionCode.set(flutter.versionCode?.toInt() ?: 1)
        }
    }
}

configurations.all {
    resolutionStrategy {
        force("org.jetbrains.kotlin:kotlin-stdlib:1.9.22")
        force("org.jetbrains.kotlin:kotlin-stdlib-common:1.9.22")
    }
}
