import 'package:flutter/services.dart';

final class BiliDownloadPluginResolver {
  const BiliDownloadPluginResolver({
    MethodChannel channel = const MethodChannel(
      'dev.ikaros.bilibili_player/download_plugin',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<List<String>> bundledDownloadPluginLibraryPaths() async {
    try {
      final result = await _channel.invokeListMethod<String>(
        'bundledDownloadPluginLibraryPaths',
      );
      return (result ?? const <String>[])
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
    } on MissingPluginException {
      return const <String>[];
    } on PlatformException {
      return const <String>[];
    }
  }
}
