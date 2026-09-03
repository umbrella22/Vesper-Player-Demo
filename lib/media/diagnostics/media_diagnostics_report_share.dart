import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class MediaDiagnosticsReportShare {
  const MediaDiagnosticsReportShare();

  static const MethodChannel _channel = MethodChannel(
    'dev.ikaros.vesper_player/performance_diagnostics_share',
  );

  Future<void> shareJson(String json, {required bool clipboardOnly}) async {
    if (clipboardOnly ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      await Clipboard.setData(ClipboardData(text: json));
      return;
    }
    await _channel.invokeMethod<void>('shareReport', <String, Object?>{
      'json': json,
    });
  }
}
