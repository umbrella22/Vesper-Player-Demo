package dev.ikaros.vesper_player

import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class DiagnosticsMainActivity : MainActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.ikaros.vesper_player/performance_diagnostics_share",
        ).setMethodCallHandler { call, result ->
            if (call.method != "shareReport") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val json = call.argument<String>("json").orEmpty()
            try {
                shareReport(json)
                result.success(null)
            } catch (error: Exception) {
                result.error("SHARE_FAILED", "Unable to share diagnostics report.", null)
            }
        }
    }

    private fun shareReport(json: String) {
        val bytes = json.toByteArray(Charsets.UTF_8)
        require(bytes.isNotEmpty() && bytes.size <= MAX_REPORT_BYTES) {
            "Diagnostics report size is invalid."
        }
        val directory = File(cacheDir, "vesper-performance-diagnostics")
        require(directory.exists() || directory.mkdirs()) {
            "Unable to prepare diagnostics cache directory."
        }
        directory.listFiles()?.forEach { stale -> stale.delete() }
        val report = File(directory, "vesper-performance-report.json")
        report.outputStream().use { output -> output.write(bytes) }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.performance-diagnostics.files",
            report,
        )
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("Vesper performance report", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(sendIntent, "分享性能诊断报告"))
    }

    private companion object {
        const val MAX_REPORT_BYTES = 4 * 1024 * 1024
    }
}
