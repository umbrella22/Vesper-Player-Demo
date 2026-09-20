import 'package:pub_semver/pub_semver.dart';

enum AppUpdatePlatform {
  androidArm64('android-arm64-release.apk'),
  playCover('ios-playcover.ipa'),
  unsupported('');

  const AppUpdatePlatform(this.assetSuffix);

  final String assetSuffix;
}

final class AppUpdateAsset {
  const AppUpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
    this.checksumUrl,
  });

  final String name;
  final Uri url;
  final int size;
  final String? sha256;
  final Uri? checksumUrl;
}

final class AppUpdateRelease {
  const AppUpdateRelease({
    required this.version,
    required this.tag,
    required this.notes,
    required this.pageUrl,
    this.asset,
  });

  final Version version;
  final String tag;
  final String notes;
  final Uri pageUrl;

  // Android and iOS jobs upload independently. A published release can exist
  // before the installer for this platform is ready.
  final AppUpdateAsset? asset;
}

const appUpdateRepository = 'umbrella22/Vesper-Player-Demo';

bool isAppUpdateNewer(Version available, Version installed) {
  // pub_semver also sorts build metadata. App release precedence follows
  // SemVer: build metadata identifies a build, not a newer release.
  Version precedence(Version version) => Version(
    version.major,
    version.minor,
    version.patch,
    pre: version.preRelease.isEmpty ? null : version.preRelease.join('.'),
  );
  return precedence(available) > precedence(installed);
}

/// Accept only this repository's stable release tags and exact asset names.
/// Release labels and publication dates do not define version ordering.
AppUpdateRelease? parseAppUpdateRelease(
  Map<String, dynamic> json,
  AppUpdatePlatform platform,
) {
  if (json['draft'] != false || json['prerelease'] != false) return null;
  final tag = json['tag_name'];
  if (tag is! String) throw const FormatException('发布版本号缺失');
  final versionText = tag.startsWith('vesper_media-v')
      ? tag.substring('vesper_media-v'.length)
      : tag.startsWith('v')
      ? tag.substring(1)
      : null;
  if (versionText == null) throw const FormatException('无法识别发布版本号');
  final version = Version.parse(versionText);
  if (version.isPreRelease) return null;
  final name = 'vesper-v$version-${platform.assetSuffix}';
  final assets = (json['assets'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .toList();
  Uri assetUrl(Map<String, dynamic> item, String expectedName) {
    final expected = Uri(
      scheme: 'https',
      host: 'github.com',
      pathSegments: [
        ...appUpdateRepository.split('/'),
        'releases',
        'download',
        tag,
        expectedName,
      ],
    );
    if (item['browser_download_url'] != expected.toString()) {
      throw const FormatException('安装包下载地址与发布仓库不符');
    }
    return expected;
  }

  AppUpdateAsset? asset;
  for (final item in assets) {
    if (item['name'] != name || platform == AppUpdatePlatform.unsupported) {
      continue;
    }
    final size = item['size'];
    if (size is! int || size <= 0) continue;
    final digest = item['digest'];
    final digestMatch = digest is String
        ? RegExp(r'^sha256:([a-fA-F0-9]{64})$').firstMatch(digest)
        : null;
    Uri? checksumUrl;
    for (final checksum in assets) {
      if (checksum['name'] == '$name.sha256') {
        checksumUrl = assetUrl(checksum, '$name.sha256');
        break;
      }
    }
    if (digestMatch == null && checksumUrl == null) continue;
    asset = AppUpdateAsset(
      name: name,
      url: assetUrl(item, name),
      size: size,
      sha256: digestMatch?.group(1)?.toLowerCase(),
      checksumUrl: checksumUrl,
    );
    break;
  }
  return AppUpdateRelease(
    version: version,
    tag: tag,
    notes: json['body'] is String ? json['body'] as String : '',
    pageUrl: Uri.https('github.com', '/$appUpdateRepository/releases/tag/$tag'),
    asset: asset,
  );
}
