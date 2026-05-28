import 'package:flutter/foundation.dart';

import 'package:bilibili_player/download/download.dart';

import 'bili_client.dart';
import 'bili_session_store.dart';

final class BiliLogoutResult {
  const BiliLogoutResult({this.downloadPauseError});

  final Object? downloadPauseError;

  bool get pausedDownloadsSuccessfully => downloadPauseError == null;
}

Future<BiliLogoutResult> clearBiliAuthenticatedSession({
  required BiliClient client,
  required BiliSessionStore sessionStore,
  required BiliOfflineDownloadController offlineController,
}) async {
  Object? downloadPauseError;
  try {
    await offlineController.pauseAllActive();
  } catch (error, stackTrace) {
    downloadPauseError = error;
    debugPrint('[BiliAuth] failed to pause offline downloads: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  client.clearSession();
  await sessionStore.clear();
  return BiliLogoutResult(downloadPauseError: downloadPauseError);
}
