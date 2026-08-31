import 'dart:io';

import 'package:vesper_media/common/storage/application_storage.dart';

@Deprecated('Use resolveApplicationStorageDirectory instead.')
Future<Directory> resolveBiliStorageDirectory({Directory? baseDirectory}) {
  return resolveApplicationStorageDirectory(baseDirectory: baseDirectory);
}

@Deprecated('Use resolveApplicationStorageFile instead.')
Future<File> resolveBiliStorageFile({
  required String fileName,
  Directory? baseDirectory,
  Directory? legacyDirectory,
}) {
  return resolveApplicationStorageFile(
    fileName: fileName,
    baseDirectory: baseDirectory,
    legacyDirectory: legacyDirectory,
  );
}

@Deprecated('Use clearApplicationStorageFile instead.')
Future<void> clearBiliStorageFile({
  required String fileName,
  Directory? baseDirectory,
  Directory? legacyDirectory,
}) {
  return clearApplicationStorageFile(
    fileName: fileName,
    baseDirectory: baseDirectory,
    legacyDirectory: legacyDirectory,
  );
}

@Deprecated('Use legacyApplicationStorageDirectory instead.')
Directory legacyBiliStorageDirectory() {
  return legacyApplicationStorageDirectory();
}
