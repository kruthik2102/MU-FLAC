import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Small JSON file helper with atomic writes (temp file + rename) and
/// serialized saves, so a crash never leaves a half-written file.
class JsonFile {
  final String path;
  Future<void> _pending = Future.value();

  JsonFile(this.path);

  /// Returns the decoded JSON, or null if missing/corrupt.
  Future<Object?> read() async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      final s = await f.readAsString();
      if (s.trim().isEmpty) return null;
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  /// Queues a write of [data]; writes are applied in order.
  Future<void> write(Object? data) {
    final encoded = jsonEncode(data);
    final next = _pending.then((_) => _write(encoded));
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> _write(String encoded) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(encoded, flush: true);
    try {
      await tmp.rename(path);
    } on FileSystemException {
      // Windows (tests) cannot rename over an existing file.
      if (await f.exists()) await f.delete();
      await tmp.rename(path);
    }
  }
}
