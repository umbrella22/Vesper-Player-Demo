package dev.ikaros.bilibili_player

import android.app.UiModeManager
import android.content.res.Configuration
import android.content.Context
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import dalvik.system.BaseDexClassLoader
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.roundToInt

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.ikaros.bilibili_player/platform",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTv" -> result.success(isTvDevice())
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.ikaros.bilibili_player/device_controls",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBrightness" -> result.success(readBrightness().toDouble())
                "setBrightness" -> {
                    val value = call.argument<Double>("value") ?: 0.5
                    result.success(writeBrightness(value).toDouble())
                }
                "getVolume" -> result.success(readVolume().toDouble())
                "setVolume" -> {
                    val value = call.argument<Double>("value") ?: 0.5
                    result.success(writeVolume(value).toDouble())
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.ikaros.bilibili_player/download_plugin",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "bundledDownloadPluginLibraryPaths" ->
                    result.success(bundledDownloadPluginLibraryPaths())
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.ikaros.bilibili_player/storage_space",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageUsage" -> result.success(deviceStorageUsage())
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.ikaros.bilibili_player/media_export",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportMp4ToGallery" -> {
                    val sourcePath = call.argument<String>("sourcePath") ?: ""
                    val displayName =
                        call.argument<String>("displayName") ?: "bilibili-offline-video.mp4"
                    try {
                        result.success(exportMp4ToGallery(sourcePath, displayName))
                    } catch (error: Exception) {
                        result.error("EXPORT_FAILED", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readBrightness(): Float {
        val windowBrightness = window.attributes.screenBrightness
        if (windowBrightness >= 0f) {
            return windowBrightness.coerceIn(0f, 1f)
        }

        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
                .toFloat()
                .div(255f)
                .coerceIn(0f, 1f)
        } catch (_: Settings.SettingNotFoundException) {
            0.5f
        } catch (_: SecurityException) {
            0.5f
        }
    }

    private fun writeBrightness(value: Double): Float {
        val next = value.toFloat().coerceIn(0f, 1f)
        val attributes = window.attributes
        attributes.screenBrightness = next
        window.attributes = attributes
        return next
    }

    private fun audioManager(): AudioManager {
        return getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    private fun readVolume(): Float {
        val audio = audioManager()
        val maxVolume = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (maxVolume <= 0) {
            return 0f
        }
        return audio.getStreamVolume(AudioManager.STREAM_MUSIC)
            .toFloat()
            .div(maxVolume.toFloat())
            .coerceIn(0f, 1f)
    }

    private fun writeVolume(value: Double): Float {
        val audio = audioManager()
        val maxVolume = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (maxVolume <= 0) {
            return 0f
        }
        val target = (value.coerceIn(0.0, 1.0) * maxVolume).roundToInt()
            .coerceIn(0, maxVolume)
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
        return readVolume()
    }

    private fun bundledDownloadPluginLibraryPaths(): List<String> {
        val libraryNames = listOf("vesper_remux_ffmpeg", "player_remux_ffmpeg")
        return libraryNames
            .asSequence()
            .mapNotNull(::resolveNativeLibraryPath)
            .take(1)
            .toList()
    }

    private fun resolveNativeLibraryPath(libraryName: String): String? {
        val classLoaderPath =
            (classLoader as? BaseDexClassLoader)?.findLibrary(libraryName)?.takeIf { path ->
                path.isNotBlank() && File(path).isFile
            }
        if (classLoaderPath != null) {
            return classLoaderPath
        }

        val nativeLibraryDir = applicationInfo.nativeLibraryDir ?: return null
        val pluginLibrary = File(nativeLibraryDir, System.mapLibraryName(libraryName))
        return pluginLibrary.takeIf(File::isFile)?.absolutePath
    }

    private fun deviceStorageUsage(): Map<String, Long> {
        val stat = StatFs(filesDir.absolutePath)
        return mapOf(
            "freeBytes" to stat.availableBytes,
            "totalBytes" to stat.totalBytes,
        )
    }

    private fun exportMp4ToGallery(sourcePath: String, displayName: String): String {
        val source = File(sourcePath)
        if (!source.isFile) {
            throw IllegalArgumentException("缓存 MP4 文件不存在。")
        }
        if (!source.name.endsWith(".mp4", ignoreCase = true)) {
            throw IllegalArgumentException("只能导出 MP4 缓存文件。")
        }

        val safeName = sanitizedMp4Name(displayName)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            exportMp4ToMediaStore(source, safeName)
        } else {
            exportMp4ToPublicMovies(source, safeName)
        }
    }

    private fun exportMp4ToMediaStore(source: File, displayName: String): String {
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/Bilibili Player")
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("无法创建相册视频条目。")
        try {
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("无法写入相册视频文件。")
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun exportMp4ToPublicMovies(source: File, displayName: String): String {
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
            "Bilibili Player",
        )
        if (!directory.exists() && !directory.mkdirs()) {
            throw IllegalStateException("无法创建相册导出目录。")
        }
        val target = uniqueFile(directory, displayName)
        source.copyTo(target, overwrite = false)
        MediaScannerConnection.scanFile(
            this,
            arrayOf(target.absolutePath),
            arrayOf("video/mp4"),
            null,
        )
        return Uri.fromFile(target).toString()
    }

    private fun uniqueFile(directory: File, displayName: String): File {
        val base = displayName.removeSuffix(".mp4")
        var candidate = File(directory, "$base.mp4")
        var index = 1
        while (candidate.exists()) {
            candidate = File(directory, "$base-$index.mp4")
            index += 1
        }
        return candidate
    }

    private fun sanitizedMp4Name(displayName: String): String {
        val sanitized = displayName
            .replace(Regex("""[\\/:*?"<>|]+"""), "-")
            .trim()
            .ifBlank { "bilibili-offline-video.mp4" }
        return if (sanitized.endsWith(".mp4", ignoreCase = true)) sanitized else "$sanitized.mp4"
    }

    private fun isTvDevice(): Boolean {
        val pm = applicationContext.packageManager
        if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)) {
            return true
        }
        val uiModeManager = applicationContext.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager != null && uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) {
            return true
        }
        return false
    }
}
