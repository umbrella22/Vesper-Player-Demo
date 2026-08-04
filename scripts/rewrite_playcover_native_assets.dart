import 'dart:convert';
import 'dart:io';

const _manifestRelativePath =
    'Frameworks/App.framework/flutter_assets/NativeAssetsManifest.json';

int rewritePlayCoverNativeAssetPaths(Map<String, dynamic> manifest) {
  final nativeAssets = manifest['native-assets'];
  if (nativeAssets is! Map<String, dynamic>) {
    return 0;
  }

  var rewrittenCount = 0;
  for (final platformAssets in nativeAssets.values) {
    if (platformAssets is! Map<String, dynamic>) {
      continue;
    }
    for (final descriptor in platformAssets.values) {
      if (descriptor is! List ||
          descriptor.length < 2 ||
          descriptor[0] != 'absolute' ||
          descriptor[1] is! String) {
        continue;
      }

      final currentPath = descriptor[1] as String;
      final rewrittenPath = _playCoverNativeAssetPath(currentPath);
      if (rewrittenPath == currentPath) {
        continue;
      }
      descriptor[1] = rewrittenPath;
      rewrittenCount += 1;
    }
  }
  return rewrittenCount;
}

String _playCoverNativeAssetPath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.startsWith('@')) {
    return path;
  }
  if (path.startsWith('Frameworks/')) {
    return '@executable_path/$path';
  }
  return '@executable_path/Frameworks/$path';
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run scripts/rewrite_playcover_native_assets.dart '
      '<Runner.app>',
    );
    exitCode = 64;
    return;
  }

  final appDirectory = Directory(arguments.single);
  if (!await appDirectory.exists()) {
    stderr.writeln(
      'PlayCover application does not exist: ${appDirectory.path}',
    );
    exitCode = 66;
    return;
  }

  final manifestFile = File('${appDirectory.path}/$_manifestRelativePath');
  if (!await manifestFile.exists()) {
    stdout.writeln('No Flutter native asset manifest to rewrite.');
    return;
  }

  final decoded = jsonDecode(await manifestFile.readAsString());
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln(
      'Invalid Flutter native asset manifest: ${manifestFile.path}',
    );
    exitCode = 65;
    return;
  }

  final rewrittenCount = rewritePlayCoverNativeAssetPaths(decoded);
  if (rewrittenCount > 0) {
    await manifestFile.writeAsString('${jsonEncode(decoded)}\n');
  }
  stdout.writeln(
    'Rewrote $rewrittenCount Flutter native asset path(s) for PlayCover.',
  );
}
