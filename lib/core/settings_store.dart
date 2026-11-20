import 'package:flutter/foundation.dart';

import 'app_paths.dart';
import 'json_file.dart';

/// Tiny persistent key/value store (`<support>/settings.json`) for UI prefs
/// and player resume state. Values must be JSON-encodable.
class SettingsStore extends ChangeNotifier {
  JsonFile? _file;
  final Map<String, Object?> _values = {};

  Future<void> load({String? path}) async {
    _file = JsonFile(path ?? AppPaths.supportFile('settings.json'));
    final j = await _file!.read();
    _values.clear();
    if (j is Map) {
      j.forEach((k, v) => _values[k as String] = v);
    }
    notifyListeners();
  }

  T? get<T>(String key) {
    final v = _values[key];
    return v is T ? v : null;
  }

  T getOr<T>(String key, T fallback) => get<T>(key) ?? fallback;

  Future<void> set(String key, Object? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    notifyListeners();
    await _file?.write(_values);
  }

  Future<void> remove(String key) => set(key, null);
}

final SettingsStore settingsStore = SettingsStore();
