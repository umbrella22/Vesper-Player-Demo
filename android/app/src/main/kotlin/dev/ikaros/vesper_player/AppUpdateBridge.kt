package dev.ikaros.vesper_player

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class AppUpdateFileProvider : FileProvider()

class AppUpdateBridge(private val activity: Activity, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, "dev.ikaros.vesper_player/app_update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "platform" -> result.success(
                        if (Build.SUPPORTED_ABIS.contains("arm64-v8a")) "androidArm64" else "unsupported",
                    )
                    "canInstall" -> result.success(activity.packageManager.canRequestPackageInstalls())
                    "install" -> {
                        val path = call.argument<String>("path") ?: ""
                        // Parsing the APK and its certificates can read tens of MB.
                        Thread {
                            try {
                                val file = validateInstaller(path)
                                activity.runOnUiThread {
                                    try {
                                        openInstaller(file, result)
                                    } catch (error: Exception) {
                                        result.error("INSTALL_FAILED", "无法打开系统安装器：${error.message}", null)
                                    }
                                }
                            } catch (error: Exception) {
                                activity.runOnUiThread {
                                    result.error("INSTALL_FAILED", error.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun validateInstaller(path: String): File {
        val directory = File(activity.cacheDir, "vesper-updates").canonicalFile
        val file = File(path).canonicalFile
        require(file.parentFile == directory && file.extension == "apk" && file.isFile) {
            "安装包文件无效，请重新下载。"
        }
        val flags = if (Build.VERSION.SDK_INT >= 28) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val manager = activity.packageManager
        val archive = manager.getPackageArchiveInfo(file.path, flags)
            ?: throw IllegalArgumentException("无法读取安装包，请重新下载。")
        val installed = manager.getPackageInfo(activity.packageName, flags)
        require(archive.packageName == activity.packageName) { "安装包不属于 Vesper。" }
        require(PackageInfoCompat.getLongVersionCode(archive) >= PackageInfoCompat.getLongVersionCode(installed)) {
            "安装包版本低于当前版本，不能覆盖安装。"
        }
        require(hasCompatibleSigners(installed, archive)) {
            "安装包签名与当前应用不同，无法覆盖安装。请使用同一发布来源的版本。"
        }
        return file
    }

    @Suppress("DEPRECATION")
    private fun hasCompatibleSigners(installed: PackageInfo, archive: PackageInfo): Boolean {
        if (Build.VERSION.SDK_INT >= 28) {
            val current = installed.signingInfo ?: return false
            val next = archive.signingInfo ?: return false
            if (!current.hasMultipleSigners() && !next.hasMultipleSigners()) {
                val history = next.signingCertificateHistory?.toSet().orEmpty()
                return current.apkContentsSigners.isNotEmpty() &&
                    current.apkContentsSigners.all { history.contains(it) }
            }
            return current.apkContentsSigners.isNotEmpty() &&
                current.apkContentsSigners.toSet() == next.apkContentsSigners.toSet()
        }
        val current = installed.signatures?.toSet().orEmpty()
        return current.isNotEmpty() && current == archive.signatures?.toSet()
    }

    private fun openInstaller(file: File, result: MethodChannel.Result) {
        if (!activity.packageManager.canRequestPackageInstalls()) {
            activity.startActivity(Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}"),
            ))
            result.success("permissionRequired")
            return
        }
        val uri = FileProvider.getUriForFile(
            activity, "${activity.packageName}.app_updates", file,
        )
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newRawUri("Vesper update", uri)
        })
        result.success("opened")
    }
}
