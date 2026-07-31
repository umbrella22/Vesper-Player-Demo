import 'package:package_info_plus/package_info_plus.dart';

/// 应用版本号的统一读取入口。
///
/// 通过 `package_info_plus` 读取原生构建配置中的版本号：Android 的
/// `versionName` / iOS 的 `CFBundleShortVersionString`，两者都由
/// `pubspec.yaml` 的 `version` 字段在构建时生成。这样版本唯一来源仍是
/// pubspec，但不需要把 `pubspec.yaml` 打包进应用 asset。
///
/// 读取失败时返回空字符串，由调用方决定兜底展示；不向上抛出异常。
/// `PackageInfo.fromPlatform()` 内部自带缓存，重复调用不会重复走平台通道。
final class AppVersion {
  const AppVersion._();

  /// 返回当前应用的版本号（例如 `1.3.2`）。
  static Future<String> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      // 忽略读取失败，返回空字符串。
    }
    return '';
  }
}
