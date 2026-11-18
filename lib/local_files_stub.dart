import 'dart:typed_data';

/// Web-də mahnı faylları bazada (IndexedDB) saxlanır, ona görə burada heç nə etmirik.
Future<void> initLocalFiles() async {}

String? audioPathFor(String? file) => null;

Future<String?> importAudioFile({
  required String sourcePath,
  required String fileName,
}) async =>
    null;

Future<void> deleteAudioFile(String? file) async {}

/// Web-də kilid ekranı yoxdur.
Future<Uri?> writeCoverFile(String key, Uint8List bytes) async => null;