import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the autosave lives. Abstract so tests can run in memory.
abstract class SaveStore {
  Future<void> save(String json);
  Future<String?> load();
  Future<void> clear();
}

/// Platform-appropriate store: browser localStorage on web (files are not
/// available there), an atomic file on mobile/desktop.
SaveStore createSaveStore() => kIsWeb ? PrefsSaveStore() : FileSaveStore();

/// A store that forgets everything. The tutorial runs on its own controller
/// backed by this one, so a guided game can never overwrite - or resurrect -
/// the real autosave behind the menu's Continue button.
class NullSaveStore implements SaveStore {
  @override
  Future<void> save(String json) async {}

  @override
  Future<String?> load() async => null;

  @override
  Future<void> clear() async {}
}

/// Web autosave in localStorage via shared_preferences.
class PrefsSaveStore implements SaveStore {
  static const _key = 'autosave_v1';

  @override
  Future<void> save(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json);
  }

  @override
  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
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
