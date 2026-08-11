import com.android.build.gradle.LibraryExtension
import java.io.File

import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

data class VesperAppPluginRegistryMetadata(
    val taskSegment: String,
    val manifestPath: String,
    val libraryName: String,
    val pluginId: String,
)

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
val playerFfmpegNativeWorkRootDirFile =
    providers.gradleProperty("vesper.player.ffmpeg.nativeWorkDir")
        .map { path -> file(path) }
        .orElse(
            providers.provider {
                val projectHash = Integer.toHexString(
                    rootProject.layout.projectDirectory.asFile.absolutePath.hashCode(),
                )
                File(System.getProperty("java.io.tmpdir"), "vesper/playerFfmpeg/$projectHash")
            },
        )
        .get()
val playerFfmpegRuntimePrebuiltsDirFile =
    playerFfmpegNativeWorkRootDirFile.resolve("runtime/prebuilts")
val playerFfmpegRuntimeDepsDirFile =
    playerFfmpegNativeWorkRootDirFile.resolve("runtime/deps")
val playerFfmpegRuntimeOpenSslDirFile = playerFfmpegRuntimeDepsDirFile.resolve("openssl")
val playerFfmpegRuntimeLibxml2DirFile = playerFfmpegRuntimeDepsDirFile.resolve("libxml2")
val playerFfmpegRuntimeAssetsRootDir = layout.buildDirectory.dir("generated/playerFfmpeg/runtime/assets")
val playerFfmpegRuntimeAssetsRootDirFile = playerFfmpegRuntimeAssetsRootDir.get().asFile
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
val playerSourceNormalizerAssetsRootDirFile =
    playerSourceNormalizerAssetsRootDir.get().asFile
val playerSourceNormalizerMetadataDirFile =
    playerSourceNormalizerAssetsRootDirFile.resolve("vesper-source-normalizer-ffmpeg")
val playerFfmpegPluginBuildProfile =
    providers.provider {
        if (gradle.startParameter.taskNames.any { taskName ->
                taskName.contains("Release", ignoreCase = true) ||
                    taskName.contains("Profile", ignoreCase = true)
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
val vesperAppPluginRegistries =
    listOf(
        VesperAppPluginRegistryMetadata(
            taskSegment = "RemuxFfmpeg",
            manifestPath = "plugins/remux-ffmpeg/vesper-plugin.toml",
            libraryName = "vesper_remux_ffmpeg",
            pluginId = "io.github.ikaros.vesper.remux-ffmpeg",
        ),
        VesperAppPluginRegistryMetadata(
            taskSegment = "SourceNormalizerFfmpeg",
            manifestPath = "plugins/source-normalizer-ffmpeg/vesper-plugin.toml",
            libraryName = "vesper_source_normalizer_ffmpeg",
            pluginId = "io.github.ikaros.vesper.source-normalizer-ffmpeg",
        ),
    )
val configuredVesperCli = providers.environmentVariable("VESPER_CLI")
val defaultVesperCli = vesperSdkBuildRootDirFile.resolve("target/release/vesper")
val vesperCli =
    configuredVesperCli
        .map { configuredPath ->
            val configuredFile = File(configuredPath)
            if (configuredFile.isAbsolute) {
                configuredFile
            } else {
                vesperSdkBuildRootDirFile.resolve(configuredPath)
            }
        }.orElse(defaultVesperCli)
val buildVesperPluginCli =
    tasks.register<Exec>("buildVesperPluginCli") {
        group = "vesper"
        description = "Builds the Rust CLI used to generate app plugin registry fragments."
        onlyIf { !configuredVesperCli.isPresent }
        workingDir = vesperSdkBuildRootDirFile
        commandLine("cargo", "build", "-p", "player-cli", "--bin", "vesper", "--release")
        outputs.file(defaultVesperCli)
        outputs.upToDateWhen { false }
    }

android {
    namespace = "dev.ikaros.vesper_player"
    compileSdk = flutter.compileSdkVersion
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

        ndk {
            abiFilters += configuredAndroidAbis
        }
    }

    buildTypes {
        getByName("profile") {
            matchingFallbacks.clear()
            matchingFallbacks += "release"
        }

        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    sourceSets {
        getByName("main").jniLibs.directories.add(playerFfmpegPluginJniLibsDirFile.absolutePath)
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

val buildPlayerFfmpegRuntimeAndroid = tasks.register<Exec>("buildPlayerFfmpegRuntimeAndroid") {
    description = "Builds and stages the Android FFmpeg runtime consumed through its AAR module."
    group = "vesper"

    val vesperScript = vesperSdkBuildRootDirFile.resolve("scripts/vesper")

    inputs.file(vesperScript)
    inputs.file(vesperSdkBuildRootDirFile.resolve("Cargo.toml"))
    inputs.file(vesperSdkBuildRootDirFile.resolve("Cargo.lock"))
    inputs.file(vesperSdkBuildRootDirFile.resolve("scripts/ffmpeg-profiles.toml"))
    inputs.file(vesperSdkBuildRootDirFile.resolve("scripts/ffmpeg-source-policy.toml"))
    inputs.property("abis", configuredAndroidAbis)
    inputs.property("ffmpegProfile", playerFfmpegPluginFfmpegProfile)
    inputs.property("opensslVersion", playerFfmpegOpenSslVersion)
    inputs.property("opensslSourceArchive", playerFfmpegOpenSslSourceArchive.map { it.absolutePath })
    outputs.dir(playerFfmpegRuntimeJniLibsDirFile)
    outputs.dir(playerFfmpegRuntimeAssetsRootDirFile)

    workingDir = vesperSdkBuildRootDirFile

    doFirst {
        project.delete(playerFfmpegRuntimeJniLibsDirFile, playerFfmpegRuntimeAssetsRootDirFile)
        playerFfmpegRuntimeJniLibsDirFile.mkdirs()
        playerFfmpegRuntimeAssetsRootDirFile.mkdirs()
        environment("RUST_ANDROID_ABIS", configuredAndroidAbis.joinToString(","))
        environment("VESPER_ANDROID_FFMPEG_OUTPUT_DIR", playerFfmpegRuntimePrebuiltsDirFile.absolutePath)
        environment("VESPER_ANDROID_LIBXML2_OUTPUT_DIR", playerFfmpegRuntimeLibxml2DirFile.absolutePath)
        environment("VESPER_ANDROID_OPENSSL_OUTPUT_DIR", playerFfmpegRuntimeOpenSslDirFile.absolutePath)
        environment("VESPER_ANDROID_OPENSSL_VERSION", playerFfmpegOpenSslVersion.get())
        environment(
            "VESPER_ANDROID_OPENSSL_SOURCE_ARCHIVE",
            playerFfmpegOpenSslSourceArchive.get().absolutePath,
        )
        environment(
            "VESPER_ANDROID_FFMPEG_RUNTIME_JNI_LIBS",
            playerFfmpegRuntimeJniLibsDirFile.absolutePath,
        )
        environment(
            "VESPER_ANDROID_FFMPEG_RUNTIME_ASSETS",
            playerFfmpegRuntimeAssetsRootDirFile.absolutePath,
        )
        vesperGradleUserHomeDir.orNull?.let { gradleUserHome ->
            environment("GRADLE_USER_HOME", gradleUserHome.absolutePath)
        }
        commandLine(
            listOf(
                vesperScript.absolutePath,
                "ffmpeg",
                "--platform",
                "android",
                "--profile",
                playerFfmpegPluginFfmpegProfile.get(),
                "--android-artifact",
                "runtime-aar",
            ) + configuredAndroidAbis.flatMap { abi -> listOf("--abi", abi) },
        )
    }
}

val buildPlayerRemuxFfmpegAndroidPlugin = tasks.register<Exec>("buildPlayerRemuxFfmpegAndroidPlugin") {
    description = "Builds the Android player-remux-ffmpeg plugin libraries used by offline cache."
    group = "vesper"

    val vesperScript = vesperSdkBuildRootDirFile.resolve("scripts/vesper")

    dependsOn(buildPlayerFfmpegRuntimeAndroid)
    inputs.file(vesperScript)
    inputs.file(vesperSdkBuildRootDirFile.resolve("Cargo.toml"))
    inputs.file(vesperSdkBuildRootDirFile.resolve("Cargo.lock"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/plugin-remux/player-remux-ffmpeg"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/plugin/player-plugin"))
    inputs.property("abis", configuredAndroidAbis)
    inputs.property("profile", playerFfmpegPluginBuildProfile)
    inputs.property("ffmpegProfile", playerFfmpegPluginFfmpegProfile)
    outputs.dir(playerFfmpegPluginJniLibsDirFile)

    workingDir = vesperSdkBuildRootDirFile

    doFirst {
        environment("RUST_ANDROID_ABIS", configuredAndroidAbis.joinToString(","))
        environment("VESPER_ANDROID_FFMPEG_OUTPUT_DIR", playerFfmpegRuntimePrebuiltsDirFile.absolutePath)
        environment("VESPER_ANDROID_LIBXML2_OUTPUT_DIR", playerFfmpegRuntimeLibxml2DirFile.absolutePath)
        environment("VESPER_ANDROID_OPENSSL_OUTPUT_DIR", playerFfmpegRuntimeOpenSslDirFile.absolutePath)
        vesperGradleUserHomeDir.orNull?.let { gradleUserHome ->
            environment("GRADLE_USER_HOME", gradleUserHome.absolutePath)
        }
        commandLine(
            vesperScript.absolutePath,
            "android",
            "remux-plugin",
            playerFfmpegPluginJniLibsDirFile.absolutePath,
            playerFfmpegPluginBuildProfile.get(),
            "--profile",
            playerFfmpegPluginFfmpegProfile.get(),
        )
    }
}

val buildPlayerSourceNormalizerFfmpegAndroidPlugin =
    tasks.register<Exec>("buildPlayerSourceNormalizerFfmpegAndroidPlugin") {
    description = "Builds the Android player-source-normalizer-ffmpeg plugin libraries."
    group = "vesper"

    val vesperScript = vesperSdkBuildRootDirFile.resolve("scripts/vesper")

    dependsOn(buildPlayerFfmpegRuntimeAndroid)
    inputs.file(vesperScript)
    inputs.file(vesperSdkBuildRootDirFile.resolve("Cargo.toml"))
    inputs.file(vesperSdkBuildRootDirFile.resolve("Cargo.lock"))
    inputs.file(vesperSdkBuildRootDirFile.resolve("scripts/source-normalizer-profiles.toml"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/core/player-source-normalizer"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/plugin/player-source-normalizer-ffmpeg"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/plugin/player-plugin"))
    inputs.dir(vesperSdkBuildRootDirFile.resolve("crates/plugin/player-plugin-loader"))
    inputs.property("abis", configuredAndroidAbis)
    inputs.property("profile", playerFfmpegPluginBuildProfile)
    inputs.property("ffmpegProfile", playerFfmpegPluginFfmpegProfile)
    outputs.dir(playerSourceNormalizerPluginJniLibsDirFile)
    outputs.dir(playerSourceNormalizerAssetsRootDirFile)

    workingDir = vesperSdkBuildRootDirFile

    doFirst {
        project.delete(playerSourceNormalizerPluginJniLibsDirFile, playerSourceNormalizerAssetsRootDirFile)
        playerSourceNormalizerPluginJniLibsDirFile.mkdirs()
        playerSourceNormalizerAssetsRootDirFile.mkdirs()
        environment("RUST_ANDROID_ABIS", configuredAndroidAbis.joinToString(","))
        environment("VESPER_ANDROID_FFMPEG_OUTPUT_DIR", playerFfmpegRuntimePrebuiltsDirFile.absolutePath)
        environment("VESPER_ANDROID_LIBXML2_OUTPUT_DIR", playerFfmpegRuntimeLibxml2DirFile.absolutePath)
        environment("VESPER_ANDROID_OPENSSL_OUTPUT_DIR", playerFfmpegRuntimeOpenSslDirFile.absolutePath)
        vesperGradleUserHomeDir.orNull?.let { gradleUserHome ->
            environment("GRADLE_USER_HOME", gradleUserHome.absolutePath)
        }
        commandLine(
            vesperScript.absolutePath,
            "android",
            "source-normalizer-plugin",
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
    ffmpegRuntimeProject.extensions
        .getByType(LibraryExtension::class.java)
        .sourceSets
        .getByName("main")
        .apply {
            jniLibs.setSrcDirs(listOf(playerFfmpegRuntimeJniLibsDirFile))
            assets.setSrcDirs(listOf(playerFfmpegRuntimeAssetsRootDirFile))
        }
    ffmpegRuntimeProject.afterEvaluate {
        extensions
            .getByType(LibraryExtension::class.java)
            .sourceSets
            .getByName("main")
            .apply {
                jniLibs.setSrcDirs(listOf(playerFfmpegRuntimeJniLibsDirFile))
                assets.setSrcDirs(listOf(playerFfmpegRuntimeAssetsRootDirFile))
            }
    }
    ffmpegRuntimeProject.tasks.matching { task ->
        (task.name.startsWith("merge") &&
            (task.name.endsWith("Assets") || task.name.endsWith("JniLibFolders"))) ||
            (task.name.startsWith("generate") && task.name.contains("Lint") && task.name.endsWith("Model")) ||
            (task.name.startsWith("lint") && task.name.contains("Analyze"))
    }.configureEach {
        dependsOn(buildPlayerFfmpegRuntimeAndroid)
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
    sourceNormalizerFfmpegProject.extensions
        .getByType(LibraryExtension::class.java)
        .sourceSets
        .getByName("main")
        .jniLibs
        .setSrcDirs(listOf(playerSourceNormalizerPluginJniLibsDirFile))
    sourceNormalizerFfmpegProject.afterEvaluate {
        extensions
            .getByType(LibraryExtension::class.java)
            .sourceSets
            .getByName("main")
            .apply {
                jniLibs.setSrcDirs(listOf(playerSourceNormalizerPluginJniLibsDirFile))
                assets.setSrcDirs(listOf(playerSourceNormalizerAssetsRootDirFile))
            }
    }
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
    dependsOn(buildPlayerFfmpegRuntimeAndroid)
    dependsOn(buildPlayerRemuxFfmpegAndroidPlugin)
    dependsOn(buildPlayerSourceNormalizerFfmpegAndroidPlugin)
}

listOf("debug", "profile", "release").forEach { variant ->
    val variantTitle = variant.replaceFirstChar(Char::uppercaseChar)
    val generatedAssets = layout.buildDirectory.dir("generated/vesperPluginRegistryAssets/$variant")
    android.sourceSets.maybeCreate(variant).assets.directories.add(
        generatedAssets.get().asFile.absolutePath,
    )
    val stripTaskName = "strip${variantTitle}DebugSymbols"
    val registryTasks =
        vesperAppPluginRegistries.map { metadata ->
            val pluginManifest = vesperSdkBuildRootDirFile.resolve(metadata.manifestPath)
            val strippedPlugin =
                layout.buildDirectory.file(
                    "intermediates/stripped_native_libs/$variant/$stripTaskName/out/" +
                        "lib/arm64-v8a/lib${metadata.libraryName}.so",
                )
            val registryFragment =
                generatedAssets.map { directory ->
                    directory.file("vesper/plugins/arm64-v8a/${metadata.pluginId}.json")
                }
            tasks.register<Exec>(
                "generate${variantTitle}Vesper${metadata.taskSegment}PluginRegistry",
            ) {
                group = "vesper"
                description =
                    "Generates the $variant ${metadata.pluginId} registry from final stripped bytes."
                dependsOn(stripTaskName)
                dependsOn(buildVesperPluginCli)
                inputs.file(vesperCli)
                inputs.file(pluginManifest)
                inputs.file(strippedPlugin)
                inputs.property("target", "aarch64-linux-android")
                inputs.property("architecture", "arm64-v8a")
                inputs.property("minimumOs", "26")
                inputs.property("locatorName", metadata.libraryName)
                outputs.file(registryFragment)

                doFirst {
                    registryFragment.get().asFile.parentFile.mkdirs()
                    commandLine(
                        vesperCli.get().absolutePath,
                        "plugin",
                        "registry-fragment",
                        pluginManifest.absolutePath,
                        "--platform",
                        "android",
                        "--target",
                        "aarch64-linux-android",
                        "--architecture",
                        "arm64-v8a",
                        "--minimum-os",
                        "26",
                        "--locator-name",
                        metadata.libraryName,
                        "--artifact",
                        strippedPlugin.get().asFile.absolutePath,
                        "--output",
                        registryFragment.get().asFile.absolutePath,
                    )
                }
            }
        }
    tasks.matching { task ->
        task.name == "merge${variantTitle}Assets" ||
            (task.name.startsWith("generate$variantTitle") &&
                task.name.contains("Lint") &&
                task.name.endsWith("Model")) ||
            (task.name.startsWith("lint") &&
                task.name.contains(variantTitle) &&
                task.name.contains("Analyze"))
    }.configureEach {
        dependsOn(registryTasks)
    }
}
