import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const String _applicationStorageFolderName = 'vesper-player';

Future<Directory> resolveApplicationStorageDirectory({
  Directory? baseDirectory,
}) async {
  final directory =
      baseDirectory ?? await _defaultApplicationStorageDirectory();
  await directory.create(recursive: true);
  return directory;
}

Future<File> resolveApplicationStorageFile({
  required String fileName,
  Directory? baseDirectory,
  Directory? legacyDirectory,
}) async {
  final directory = await resolveApplicationStorageDirectory(
    baseDirectory: baseDirectory,
  );
  final file = File('${directory.path}/$fileName');
  if (await file.exists()) {
    return file;
  }

  final legacyFile = File(
    '${(legacyDirectory ?? legacyApplicationStorageDirectory()).path}/$fileName',
  );
  if (await legacyFile.exists()) {
    await legacyFile.copy(file.path);
  }
  return file;
}

Future<void> clearApplicationStorageFile({
  required String fileName,
  Directory? baseDirectory,
  Directory? legacyDirectory,
}) async {
  final currentDirectory = await resolveApplicationStorageDirectory(
    baseDirectory: baseDirectory,
  );
  final currentFile = File('${currentDirectory.path}/$fileName');
  if (await currentFile.exists()) {
    await currentFile.delete();
  }

  final legacyFile = File(
    '${(legacyDirectory ?? legacyApplicationStorageDirectory()).path}/$fileName',
  );
  if (legacyFile.path != currentFile.path && await legacyFile.exists()) {
    await legacyFile.delete();
  }
}

Directory legacyApplicationStorageDirectory() {
  return Directory(
    '${Directory.systemTemp.path}/$_applicationStorageFolderName',
  );
}

Future<Directory> _defaultApplicationStorageDirectory() async {
  try {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory('${supportDirectory.path}/$_applicationStorageFolderName');
  } on MissingPluginException {
    return legacyApplicationStorageDirectory();
  }
}
