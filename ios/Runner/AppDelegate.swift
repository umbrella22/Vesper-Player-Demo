import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var downloadPluginChannel: FlutterMethodChannel?
  private var storageSpaceChannel: FlutterMethodChannel?
  private var mediaExportChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let channel = FlutterMethodChannel(
      name: "dev.ikaros.bilibili_player/download_plugin",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "bundledDownloadPluginLibraryPaths":
        result(self?.bundledDownloadPluginLibraryPaths() ?? [])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    downloadPluginChannel = channel

    let storageChannel = FlutterMethodChannel(
      name: "dev.ikaros.bilibili_player/storage_space",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    storageChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getStorageUsage":
        result(self?.deviceStorageUsage() ?? ["freeBytes": 0, "totalBytes": 0])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    storageSpaceChannel = storageChannel

    let mediaChannel = FlutterMethodChannel(
      name: "dev.ikaros.bilibili_player/media_export",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    mediaChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "exportMp4ToGallery":
        self?.exportMp4ToGallery(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    mediaExportChannel = mediaChannel

    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func bundledDownloadPluginLibraryPaths() -> [String] {
    let fileManager = FileManager.default
    let frameworksPath = Bundle.main.privateFrameworksPath ?? Bundle.main.bundlePath + "/Frameworks"
    let candidates = [
      frameworksPath + "/vesper_player_ios.framework/libplayer_remux_ffmpeg.dylib",
      frameworksPath + "/VesperPlayerKit.framework/libplayer_remux_ffmpeg.dylib",
      frameworksPath + "/libplayer_remux_ffmpeg.dylib",
      Bundle.main.bundlePath + "/libplayer_remux_ffmpeg.dylib",
    ]

    return candidates.compactMap { candidate in
      fileManager.fileExists(atPath: candidate) ? candidate : nil
    }
  }

  private func deviceStorageUsage() -> [String: Int64] {
    do {
      let attributes = try FileManager.default.attributesOfFileSystem(
        forPath: NSHomeDirectory()
      )
      let freeBytes = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
      let totalBytes = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
      return ["freeBytes": freeBytes, "totalBytes": totalBytes]
    } catch {
      return ["freeBytes": 0, "totalBytes": 0]
    }
  }

  private func exportMp4ToGallery(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "导出参数无效。", details: nil))
      return
    }
    guard let sourcePath = arguments["sourcePath"] as? String, !sourcePath.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "缓存文件路径为空。", details: nil))
      return
    }
    let sourceURL = URL(fileURLWithPath: sourcePath)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      result(FlutterError(code: "EXPORT_FAILED", message: "缓存 MP4 文件不存在。", details: nil))
      return
    }
    guard sourceURL.pathExtension.lowercased() == "mp4" else {
      result(FlutterError(code: "EXPORT_FAILED", message: "只能导出 MP4 缓存文件。", details: nil))
      return
    }

    let displayName = sanitizedMp4Name(arguments["displayName"] as? String)
    let exportURL: URL
    do {
      exportURL = try temporaryExportURL(displayName: displayName)
      if FileManager.default.fileExists(atPath: exportURL.path) {
        try FileManager.default.removeItem(at: exportURL)
      }
      try FileManager.default.copyItem(at: sourceURL, to: exportURL)
    } catch {
      result(FlutterError(code: "EXPORT_FAILED", message: "准备导出文件失败：\(error.localizedDescription)", details: nil))
      return
    }

    let save = {
      var localIdentifier: String?
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: exportURL)
        localIdentifier = request?.placeholderForCreatedAsset?.localIdentifier
      }) { success, error in
        try? FileManager.default.removeItem(at: exportURL)
        DispatchQueue.main.async {
          if success {
            result(localIdentifier ?? exportURL.absoluteString)
          } else {
            result(FlutterError(
              code: "EXPORT_FAILED",
              message: error?.localizedDescription ?? "导出到相册失败。",
              details: nil
            ))
          }
        }
      }
    }

    switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
    case .authorized, .limited:
      save()
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        DispatchQueue.main.async {
          if status == .authorized || status == .limited {
            save()
          } else {
            try? FileManager.default.removeItem(at: exportURL)
            result(FlutterError(code: "PERMISSION_DENIED", message: "没有相册写入权限。", details: nil))
          }
        }
      }
    case .denied, .restricted:
      try? FileManager.default.removeItem(at: exportURL)
      result(FlutterError(code: "PERMISSION_DENIED", message: "没有相册写入权限。", details: nil))
    @unknown default:
      try? FileManager.default.removeItem(at: exportURL)
      result(FlutterError(code: "PERMISSION_DENIED", message: "没有相册写入权限。", details: nil))
    }
  }

  private func temporaryExportURL(displayName: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("bilibili-player-export", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent(displayName)
  }

  private func sanitizedMp4Name(_ value: String?) -> String {
    let raw = (value ?? "bilibili-offline-video.mp4").trimmingCharacters(in: .whitespacesAndNewlines)
    let replaced = raw
      .replacingOccurrences(of: "[\\\\/:*?\"<>|]+", with: "-", options: .regularExpression)
    let name = replaced.isEmpty ? "bilibili-offline-video.mp4" : replaced
    return name.lowercased().hasSuffix(".mp4") ? name : "\(name).mp4"
  }
}
