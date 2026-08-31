import 'dart:io';

/// Replaces [file] with [contents] through a flushed sibling temporary file.
///
/// Some platforms do not allow a rename over an existing file. In that case,
/// the existing target is removed before retrying the rename.
Future<void> writeStringAtomically(File file, String contents) async {
  await file.parent.create(recursive: true);
  final temporaryFile = File(
    '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-$pid',
  );
  await temporaryFile.writeAsString(contents, flush: true);
  try {
    await temporaryFile.rename(file.path);
  } on FileSystemException {
    if (await file.exists()) {
      await file.delete();
    }
    await temporaryFile.rename(file.path);
  }
}
