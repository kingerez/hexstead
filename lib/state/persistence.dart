import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where the autosave lives. Abstract so tests can run in memory.
abstract class SaveStore {
  Future<void> save(String json);
  Future<String?> load();
  Future<void> clear();
}

/// Atomic file autosave: write to .tmp, then rename, so a mid-write kill
/// never corrupts the previous save.
class FileSaveStore implements SaveStore {
  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/autosave.json');
  }

  @override
  Future<void> save(String json) async {
    final file = await _file;
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<String?> load() async {
    final file = await _file;
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    final file = await _file;
    if (await file.exists()) await file.delete();
  }
}
