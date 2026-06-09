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

val vesperSdkRootDir = rootProject.layout.projectDirectory.dir("../third_party/vesper-player-sdk")
val vesperSdkBuildRootDirFile =
    providers.gradleProperty("vesper.player.sdk.sourceDir")
        .map { path -> file(path) }
        .orElse(vesperSdkRootDir.asFile)
        .get()
val playerFfmpegRuntimePrebuiltsDir = layout.buildDirectory.dir("generated/playerFfmpeg/runtime/prebuilts")
val playerFfmpegRuntimePrebuiltsDirFile = playerFfmpegRuntimePrebuiltsDir.get().asFile
val playerFfmpegRuntimeDepsDir = layout.buildDirectory.dir("generated/playerFfmpeg/runtime/deps")
val playerFfmpegRuntimeDepsDirFile = playerFfmpegRuntimeDepsDir.get().asFile
val playerFfmpegRuntimeOpenSslDirFile = playerFfmpegRuntimeDepsDirFile.resolve("openssl")
val playerFfmpegRuntimeLibxml2DirFile = playerFfmpegRuntimeDepsDirFile.resolve("libxml2")
val playerFfmpegRuntimeAssetsRootDir = layout.buildDirectory.dir("generated/playerFfmpeg/runtime/assets")
val playerFfmpegRuntimeAssetsRootDirFile = playerFfmpegRuntimeAssetsRootDir.get().asFile
val playerFfmpegRuntimeAssetsDirFile =
    playerFfmpegRuntimeAssetsRootDirFile.resolve("vesper-ffmpeg-runtime")
val playerFfmpegRuntimeJniLibsDir = layout.buildDirectory.dir("generated/playerFfmpeg/runtime/jniLibs")
val playerFfmpegRuntimeJniLibsDirFile = playerFfmpegRuntimeJniLibsDir.get().asFile
val playerFfmpegPluginJniLibsDir = layout.buildDirectory.dir("generated/playerFfmpeg/jniLibs")
val playerFfmpegPluginJniLibsDirFile = playerFfmpegPluginJniLibsDir.get().asFile
val playerSourceNormalizerPluginJniLibsDir =
    layout.buildDirectory.dir("generated/playerSourceNormalizerFfmpeg/jniLibs")
val playerSourceNormalizerPluginJniLibsDirFile =
    playerSourceNormalizerPluginJniLibsDir.get().asFile
val playerSourceNormalizerAssetsRootDir =
    layout.buildDirectory.dir("generated/playerSourceNormalizerFfmpeg/assets")
val playerSourceNormalizerAssetsRootDirFile = playerSourceNormalizerAssetsRootDir.get().asFile
val playerSourceNormalizerMetadataDirFile =
    playerSourceNormalizerAssetsRootDirFile.resolve("vesper-source-normalizer-ffmpeg")
val playerFfmpegPluginBuildProfile =
    providers.provider {
        if (gradle.startParameter.taskNames.any { taskName ->
                taskName.contains("Release", ignoreCase = true)
            }
        ) {
            "release"
        } else {
            "debug"
        }
    }
val playerFfmpegPluginFfmpegProfile =
    providers.gradleProperty("vesper.player.ffmpeg.profile")
        .orElse("default")
val playerFfmpegOpenSslVersion =
    providers.gradleProperty("vesper.player.openssl.version")
        .orElse("3.6.1")
val playerFfmpegOpenSslSourceArchive =
    providers.gradleProperty("vesper.player.openssl.sourceArchive")
        .map { path -> file(path) }
        .orElse(
            providers.provider {
                vesperSdkBuildRootDirFile.resolve(
                    "openssl-${playerFfmpegOpenSslVersion.get()}.tar.gz",
                )
            },
        )
val vesperGradleUserHomeDir =
    providers.gradleProperty("vesper.player.gradle.userHome")
        .orElse(providers.systemProperty("vesper.player.gradle.userHome"))
        .map { path -> file(path) }

android {
    namespace = "dev.ikaros.bilibili_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.ikaros.bilibili_player"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += configuredAndroidAbis
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    sourceSets {
        getByName("main").jniLibs.directories.add(playerFfmpegPluginJniLibsDirFile.absolutePath)
        getByName("main").jniLibs.directories.add(
            playerSourceNormalizerPluginJniLibsDirFile.absolutePath,
        )
        getByName("main").jniLibs.directories.add(playerFfmpegRuntimeJniLibsDirFile.absolutePath)
        getByName("main").assets.srcDir(playerFfmpegRuntimeAssetsRootDirFile)
        getByName("main").assets.srcDir(playerSourceNormalizerAssetsRootDirFile)
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
    implementation(project(":vesper-player-kit-ffmpeg-runtime"))
    implementation(project(":vesper-player-kit-external-playback"))
    implementation(project(":vesper-player-kit-source-normalizer-ffmpeg"))
}

val buildPlayerRemuxFfmpegAndroidPlugin by tasks.registering(Exec::class) {
    description = "Builds the Android player-remux-ffmpeg plugin libraries used by offline cache."
    group = "vesper"

    val scriptFile = vesperSdkBuildRootDirFile.resolve(
        "scripts/android/build-player-remux-ffmpeg-plugin.sh",
    )

    inputs.file(scriptFile)
    inputs.file(vesperSdkBuildRootDirFile.resolve("scripts/android/build-ffmpeg-runtime-aar.sh"))
    inputs.file(vesperSdkBuildRootDirFile.resolve("Cargo.toml"))
    inputs.file(vesperSdkBuildRootDirFile.resolve("Cargo.lock"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/plugin-remux/player-remux-ffmpeg"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/plugin/player-plugin"))
    listOf(
        "third_party/ffmpeg/android",
        "third_party/openssl/android",
        "third_party/libxml2/android",
    ).map { relativePath -> vesperSdkBuildRootDirFile.resolve(relativePath) }
        .filter { directory -> directory.isDirectory }
        .forEach { directory -> inputs.dir(directory) }
    inputs.property("abis", configuredAndroidAbis)
    inputs.property("profile", playerFfmpegPluginBuildProfile)
    inputs.property("ffmpegProfile", playerFfmpegPluginFfmpegProfile)
    inputs.property("opensslVersion", playerFfmpegOpenSslVersion)
    inputs.property("opensslSourceArchive", playerFfmpegOpenSslSourceArchive.map { it.absolutePath })
    outputs.dir(playerFfmpegPluginJniLibsDirFile)
    outputs.dir(playerFfmpegRuntimeDepsDirFile)
    outputs.dir(playerFfmpegRuntimeAssetsRootDirFile)
    outputs.dir(playerFfmpegRuntimeJniLibsDirFile)

    workingDir = vesperSdkBuildRootDirFile

    doFirst {
        environment("RUST_ANDROID_ABIS", configuredAndroidAbis.joinToString(","))
        environment("VESPER_ANDROID_FFMPEG_OUTPUT_DIR", playerFfmpegRuntimePrebuiltsDirFile.absolutePath)
        environment("VESPER_ANDROID_LIBXML2_OUTPUT_DIR", playerFfmpegRuntimeLibxml2DirFile.absolutePath)
        environment("VESPER_ANDROID_OPENSSL_OUTPUT_DIR", playerFfmpegRuntimeOpenSslDirFile.absolutePath)
        environment("VESPER_ANDROID_OPENSSL_VERSION", playerFfmpegOpenSslVersion.get())
        environment(
            "VESPER_ANDROID_OPENSSL_SOURCE_ARCHIVE",
            playerFfmpegOpenSslSourceArchive.get().absolutePath,
        )
        vesperGradleUserHomeDir.orNull?.let { gradleUserHome ->
            environment("GRADLE_USER_HOME", gradleUserHome.absolutePath)
        }
        commandLine(
            scriptFile.absolutePath,
            playerFfmpegPluginJniLibsDirFile.absolutePath,
            playerFfmpegPluginBuildProfile.get(),
            "--profile",
            playerFfmpegPluginFfmpegProfile.get(),
        )
    }

    doLast {
        project.delete(playerFfmpegRuntimeJniLibsDirFile, playerFfmpegRuntimeAssetsRootDirFile)
        playerFfmpegRuntimeJniLibsDirFile.mkdirs()
        playerFfmpegRuntimeAssetsDirFile.mkdirs()

        var expectedProfileHash: String? = null
        configuredAndroidAbis.forEach { abi ->
            val ffmpegAbiDir = playerFfmpegRuntimePrebuiltsDirFile.resolve(abi)
            val ffmpegLibDir = ffmpegAbiDir.resolve("lib")
            require(ffmpegLibDir.isDirectory) {
                "Missing FFmpeg runtime libraries for ABI $abi: $ffmpegLibDir"
            }

            val targetAbiDir = playerFfmpegRuntimeJniLibsDirFile.resolve(abi)
            targetAbiDir.mkdirs()
            val runtimeLibraries = ffmpegLibDir.listFiles { file ->
                file.isFile && file.name.startsWith("lib") && file.name.endsWith(".so")
            }?.toList().orEmpty()
            require(runtimeLibraries.isNotEmpty()) {
                "No FFmpeg runtime .so files found for ABI $abi in $ffmpegLibDir"
            }
            runtimeLibraries.forEach { library ->
                library.copyTo(targetAbiDir.resolve(library.name), overwrite = true)
            }

            val metadataFile = ffmpegAbiDir.resolve("vesper-ffmpeg-build-metadata.txt")
            require(metadataFile.isFile) {
                "Missing FFmpeg build metadata for ABI $abi: $metadataFile"
            }
            val metadataText = metadataFile.readText()
            metadataFile.copyTo(
                playerFfmpegRuntimeAssetsDirFile.resolve("$abi-metadata.txt"),
                overwrite = true,
            )
            val profileHash = metadataText
                .lineSequence()
                .firstOrNull { line -> line.startsWith("profile_hash=") }
                ?.substringAfter("=")
                ?.trim()
            require(!profileHash.isNullOrEmpty()) {
                "Missing profile_hash in FFmpeg metadata for ABI $abi: $metadataFile"
            }
            if (expectedProfileHash == null) {
                expectedProfileHash = profileHash
            } else {
                require(expectedProfileHash == profileHash) {
                    "Mismatched FFmpeg profile hash for ABI $abi: $profileHash != $expectedProfileHash"
                }
            }

            val externalDependencies = metadataText
                .lineSequence()
                .firstOrNull { line -> line.startsWith("external_dependencies=") }
                ?.substringAfter("=")
                ?.split(",")
                ?.map(String::trim)
                ?.filter(String::isNotEmpty)
                .orEmpty()
            externalDependencies.forEach { dependency ->
                val dependencyLibDir = when (dependency) {
                    "libxml2" -> playerFfmpegRuntimeLibxml2DirFile.resolve("$abi/lib")
                    "openssl" -> playerFfmpegRuntimeOpenSslDirFile.resolve("$abi/lib")
                    else -> error("Unsupported FFmpeg external dependency '$dependency' for ABI $abi.")
                }
                require(dependencyLibDir.isDirectory) {
                    "Missing FFmpeg external dependency '$dependency' for ABI $abi: $dependencyLibDir"
                }
                val dependencyLibraries = dependencyLibDir.listFiles { file ->
                    file.isFile && file.name.startsWith("lib") && file.name.endsWith(".so")
                }?.toList().orEmpty()
                require(dependencyLibraries.isNotEmpty()) {
                    "No shared libraries found for FFmpeg external dependency '$dependency' in $dependencyLibDir"
                }
                dependencyLibraries.forEach { library ->
                    library.copyTo(targetAbiDir.resolve(library.name), overwrite = true)
                }
            }
        }

        playerFfmpegRuntimeAssetsDirFile
            .resolve("profile-hash.txt")
            .writeText("${requireNotNull(expectedProfileHash)}\n")
    }
}

val buildPlayerSourceNormalizerFfmpegAndroidPlugin by tasks.registering(Exec::class) {
    description = "Builds the Android player-source-normalizer-ffmpeg plugin libraries."
    group = "vesper"

    val scriptFile = vesperSdkBuildRootDirFile.resolve(
        "scripts/android/build-player-source-normalizer-ffmpeg-plugin.sh",
    )

    inputs.file(scriptFile)
    inputs.file(vesperSdkBuildRootDirFile.resolve("scripts/android/build-ffmpeg-runtime-aar.sh"))
    inputs.file(vesperSdkBuildRootDirFile.resolve("Cargo.toml"))
    inputs.file(vesperSdkBuildRootDirFile.resolve("Cargo.lock"))
    inputs.file(vesperSdkBuildRootDirFile.resolve("scripts/source-normalizer-profiles.toml"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/core/player-source-normalizer"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/plugin/player-source-normalizer-ffmpeg"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/plugin/player-plugin"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/plugin/player-plugin-loader"))
    listOf(
        "third_party/ffmpeg/android",
        "third_party/openssl/android",
        "third_party/libxml2/android",
    ).map { relativePath -> vesperSdkBuildRootDirFile.resolve(relativePath) }
        .filter { directory -> directory.isDirectory }
        .forEach { directory -> inputs.dir(directory) }
    inputs.property("abis", configuredAndroidAbis)
    inputs.property("profile", playerFfmpegPluginBuildProfile)
    inputs.property("ffmpegProfile", playerFfmpegPluginFfmpegProfile)
    inputs.property("opensslVersion", playerFfmpegOpenSslVersion)
    inputs.property("opensslSourceArchive", playerFfmpegOpenSslSourceArchive.map { it.absolutePath })
    outputs.dir(playerSourceNormalizerPluginJniLibsDirFile)
    outputs.dir(playerSourceNormalizerAssetsRootDirFile)

    workingDir = vesperSdkBuildRootDirFile

    doFirst {
        environment("RUST_ANDROID_ABIS", configuredAndroidAbis.joinToString(","))
        environment("VESPER_ANDROID_FFMPEG_OUTPUT_DIR", playerFfmpegRuntimePrebuiltsDirFile.absolutePath)
        environment("VESPER_ANDROID_LIBXML2_OUTPUT_DIR", playerFfmpegRuntimeLibxml2DirFile.absolutePath)
        environment("VESPER_ANDROID_OPENSSL_OUTPUT_DIR", playerFfmpegRuntimeOpenSslDirFile.absolutePath)
        environment("VESPER_ANDROID_OPENSSL_VERSION", playerFfmpegOpenSslVersion.get())
        environment(
            "VESPER_ANDROID_OPENSSL_SOURCE_ARCHIVE",
            playerFfmpegOpenSslSourceArchive.get().absolutePath,
        )
        vesperGradleUserHomeDir.orNull?.let { gradleUserHome ->
            environment("GRADLE_USER_HOME", gradleUserHome.absolutePath)
        }
        commandLine(
            scriptFile.absolutePath,
            playerSourceNormalizerPluginJniLibsDirFile.absolutePath,
            playerFfmpegPluginBuildProfile.get(),
            "--profile",
            playerFfmpegPluginFfmpegProfile.get(),
            "--metadata-dir",
            playerSourceNormalizerMetadataDirFile.absolutePath,
        )
    }
}

tasks.matching { task ->
    (task.name.startsWith("merge") && task.name.endsWith("JniLibFolders")) ||
        (task.name.startsWith("generate") && task.name.contains("Lint") && task.name.endsWith("Model")) ||
        (task.name.startsWith("lint") && task.name.contains("Analyze"))
}.configureEach {
    dependsOn(buildPlayerRemuxFfmpegAndroidPlugin)
    dependsOn(buildPlayerSourceNormalizerFfmpegAndroidPlugin)
}

val ffmpegRuntimeProject = rootProject.project(":vesper-player-kit-ffmpeg-runtime")
ffmpegRuntimeProject.plugins.withId("com.android.library") {
    ffmpegRuntimeProject.tasks.matching { task ->
        (task.name.startsWith("merge") &&
            (task.name.endsWith("Assets") || task.name.endsWith("JniLibFolders"))) ||
            (task.name.startsWith("generate") && task.name.contains("Lint") && task.name.endsWith("Model")) ||
            (task.name.startsWith("lint") && task.name.contains("Analyze"))
    }.configureEach {
        dependsOn(buildPlayerRemuxFfmpegAndroidPlugin)
        dependsOn(buildPlayerSourceNormalizerFfmpegAndroidPlugin)
    }
}

val externalPlaybackProject = rootProject.project(":vesper-player-kit-external-playback")
externalPlaybackProject.plugins.withId("com.android.library") {
    externalPlaybackProject.tasks.matching { task ->
        task.name == "buildRelayFfmpegAndroidJni"
    }.configureEach {
        dependsOn(buildPlayerRemuxFfmpegAndroidPlugin)
    }
    externalPlaybackProject.tasks.matching { task ->
        (task.name.startsWith("merge") && task.name.endsWith("JniLibFolders")) ||
            (task.name.startsWith("generate") && task.name.contains("Lint") && task.name.endsWith("Model")) ||
            (task.name.startsWith("lint") && task.name.contains("Analyze"))
    }.configureEach {
        dependsOn(buildPlayerRemuxFfmpegAndroidPlugin)
    }
}

val sourceNormalizerFfmpegProject = rootProject.project(":vesper-player-kit-source-normalizer-ffmpeg")
sourceNormalizerFfmpegProject.plugins.withId("com.android.library") {
    sourceNormalizerFfmpegProject.tasks.matching { task ->
        (task.name.startsWith("merge") &&
            (task.name.endsWith("Assets") || task.name.endsWith("JniLibFolders"))) ||
            (task.name.startsWith("generate") && task.name.contains("Lint") && task.name.endsWith("Model")) ||
            (task.name.startsWith("lint") && task.name.contains("Analyze"))
    }.configureEach {
        dependsOn(buildPlayerSourceNormalizerFfmpegAndroidPlugin)
    }
}

tasks.named("preBuild").configure {
    dependsOn(buildPlayerRemuxFfmpegAndroidPlugin)
    dependsOn(buildPlayerSourceNormalizerFfmpegAndroidPlugin)
}
