import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val configuredAndroidAbis =
    sequenceOf(
        "vesper.player.android.app.abis",
        "vesper.player.android.abis",
    ).mapNotNull { propertyName ->
        providers.gradleProperty(propertyName).orNull
    }.firstOrNull()
        ?.split(',', ' ')
        ?.map(String::trim)
        ?.filter(String::isNotEmpty)
        ?: listOf("arm64-v8a")

val excludedAndroidAbiPatterns =
    listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
        .filterNot(configuredAndroidAbis::contains)
        .map { abi -> "lib/$abi/**" }

android {
    namespace = "dev.ikaros.vesper_player"
    compileSdk = 37
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.ikaros.vesper_player"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["mainActivityName"] = ".MainActivity"

        ndk {
            abiFilters += configuredAndroidAbis
        }
    }

    buildTypes {
        getByName("debug") {
            manifestPlaceholders["mainActivityName"] = ".DiagnosticsMainActivity"
        }

        getByName("profile") {
            matchingFallbacks.clear()
            matchingFallbacks += "release"
            manifestPlaceholders["mainActivityName"] = ".DiagnosticsMainActivity"
        }

        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    sourceSets {
        getByName("debug") {
            java.srcDir("src/diagnostics/kotlin")
            res.srcDir("src/diagnostics/res")
        }
        getByName("profile") {
            java.srcDir("src/diagnostics/kotlin")
            res.srcDir("src/diagnostics/res")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            excludes += excludedAndroidAbiPatterns
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    debugImplementation("androidx.core:core-ktx:1.17.0")
    add("profileImplementation", "androidx.core:core-ktx:1.17.0")
    debugImplementation(
        "io.github.umbrella22.vesper:vesper-player-kit-performance-diagnostics:0.5.2-rc.4",
    )
    add(
        "profileImplementation",
        "io.github.umbrella22.vesper:vesper-player-kit-performance-diagnostics:0.5.2-rc.4",
    )
}
