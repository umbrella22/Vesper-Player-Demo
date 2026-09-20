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

val releaseKeystorePath = providers.environmentVariable("VESPER_ANDROID_KEYSTORE_PATH").orNull
val releaseStorePassword = providers.environmentVariable("VESPER_ANDROID_STORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("VESPER_ANDROID_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("VESPER_ANDROID_KEY_PASSWORD").orNull

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

    signingConfigs {
        create("release") {
            if (!releaseKeystorePath.isNullOrBlank()) {
                storeFile = file(releaseKeystorePath)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
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
            signingConfig = signingConfigs.getByName("release")
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

val validateReleaseSigningConfiguration = tasks.register("validateReleaseSigningConfiguration") {
    doLast {
        check(listOf(releaseKeystorePath, releaseStorePassword, releaseKeyAlias, releaseKeyPassword)
            .all { !it.isNullOrBlank() }) {
            "Release signing requires VESPER_ANDROID_KEYSTORE_PATH, VESPER_ANDROID_STORE_PASSWORD, " +
                "VESPER_ANDROID_KEY_ALIAS and VESPER_ANDROID_KEY_PASSWORD. See doc/app-update-notes.md."
        }
        check(file(releaseKeystorePath!!).isFile) { "Android release keystore was not found." }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(validateReleaseSigningConfiguration)
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
    val coreKtx = "androidx.core:core-ktx:1.19.0"
    val performanceDiagnostics =
        "io.github.umbrella22.vesper:vesper-player-kit-performance-diagnostics:0.6.2"

    implementation(coreKtx)
    debugImplementation(performanceDiagnostics)
    add("profileImplementation", performanceDiagnostics)
}
