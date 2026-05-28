import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const String _biliStorageFolderName = 'bilibili-player';

Future<Directory> resolveBiliStorageDirectory({
  Directory? baseDirectory,
}) async {
  final directory = baseDirectory ?? await _defaultBiliStorageDirectory();
  await directory.create(recursive: true);
  return directory;
}

Future<File> resolveBiliStorageFile({
  required String fileName,
  Directory? baseDirectory,
  Directory? legacyDirectory,
}) async {
  final directory = await resolveBiliStorageDirectory(
    baseDirectory: baseDirectory,
  );
  final file = File('${directory.path}/$fileName');
  if (await file.exists()) {
    return file;
  }

  final legacyFile = File(
    '${(legacyDirectory ?? legacyBiliStorageDirectory()).path}/$fileName',
  );
  if (await legacyFile.exists()) {
    await legacyFile.copy(file.path);
  }
  return file;
}

Future<void> clearBiliStorageFile({
  required String fileName,
  Directory? baseDirectory,
  Directory? legacyDirectory,
}) async {
  final currentFile = File(
    '${(await resolveBiliStorageDirectory(baseDirectory: baseDirectory)).path}/$fileName',
  );
  if (await currentFile.exists()) {
    await currentFile.delete();
  }

  final oldFile = File(
    '${(legacyDirectory ?? legacyBiliStorageDirectory()).path}/$fileName',
  );
  if (oldFile.path != currentFile.path && await oldFile.exists()) {
    await oldFile.delete();
  }
}

Directory legacyBiliStorageDirectory() {
  return Directory('${Directory.systemTemp.path}/$_biliStorageFolderName');
}

Future<Directory> _defaultBiliStorageDirectory() async {
  try {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory('${supportDirectory.path}/$_biliStorageFolderName');
  } on MissingPluginException {
    return legacyBiliStorageDirectory();
  }
}
