import 'package:flutter/foundation.dart';
import 'package:vesper_player/vesper_player.dart';

typedef BiliDownloadPluginReferenceLoader =
    Future<List<VesperPluginReference>> Function();

final class BiliDownloadPluginResolver {
  const BiliDownloadPluginResolver({this.loader});

  final BiliDownloadPluginReferenceLoader? loader;

  Future<List<VesperPluginReference>> bundledDownloadPluginReferences() async {
    final configuredLoader = loader;
    if (configuredLoader != null) {
      return List<VesperPluginReference>.unmodifiable(await configuredLoader());
    }

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return const <VesperPluginReference>[];
    }

    return <VesperPluginReference>[VesperBundledPluginReferences.remuxFfmpeg];
  }
}
