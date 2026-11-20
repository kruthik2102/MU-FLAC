import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import 'app_paths.dart';
import 'json_file.dart';
import 'library_index.dart';
import 'library_scanner.dart';
import 'models.dart';
import 'native_audio.dart';

/// The music library: source folders (roots), the scanned track cache and
/// the browse indexes (albums, artists, folders).
///
/// Android: roots are user-picked folders (absolute paths).
/// iOS: the app Documents folder (`docs`, always present) plus folders
/// picked in the Files app (`bm:<id>`, security-scoped bookmarks resolved
/// natively at launch).
class LibraryStore extends ChangeNotifier {
  LibraryStore({bool? isIOS, bool? isAndroid})
      : _isIOS = isIOS ?? Platform.isIOS,
        _isAndroid = isAndroid ?? Platform.isAndroid;

  final bool _isIOS;
  final bool _isAndroid;

  static const int _cacheVersion = 1;
  static const int _batchSize = 24;

  late JsonFile _rootsFile;
  late JsonFile _cacheFile;

  List<LibraryRoot> _roots = [];

  /// All cached tracks (including those of currently unavailable roots).
  final Map<String, Track> _cache = {};
  LibraryIndex _index = LibraryIndex.empty;

  bool _initialized = false;
  bool _scanning = false;
  int _scanDone = 0;
  int _scanTotal = 0;
  String _scanStatus = '';
  Future<void>? _scanFuture;
  bool _rescanQueued = false;
  bool _needsPermission = false;
  List<String> _notDownloaded = const [];
  int _unreadable = 0;
  DateTime? _lastScan;

  // ---------------------------------------------------------------------
  // Public state
  // ---------------------------------------------------------------------

  bool get initialized => _initialized;
  bool get isIOS => _isIOS;

  /// Configured roots, docs first on iOS.
  List<LibraryRoot> get roots => List.unmodifiable(_roots);

  /// Playable tracks (from available roots), sorted by title.
  List<Track> get tracks => _index.tracks;
  List<Album> get albums => _index.albums;
  List<Artist> get artists => _index.artists;
  Map<String, Track> get byKey => _index.byKey;
  LibraryIndex get index => _index;

  Track? track(String key) => _index.byKey[key];
  Album? album(String id) => _index.albumById[id];
  Artist? artist(String name) => _index.artist(name);

  bool get isEmpty => _index.tracks.isEmpty;
  bool get scanning => _scanning;

  /// 0..1 while scanning (parsing phase), 0 otherwise.
  double get progress =>
      _scanTotal == 0 ? 0 : (_scanDone / _scanTotal).clamp(0.0, 1.0);
  int get scanDone => _scanDone;
  int get scanTotal => _scanTotal;

  /// Human-readable phase, e.g. "Looking for files…", "Reading 12 / 340".
  String get scanStatus => _scanStatus;
  DateTime? get lastScan => _lastScan;

  /// Android: media permission not granted yet (call [requestPermission]).
  bool get needsPermission => _needsPermission;

  /// iCloud files present only as placeholders (not downloaded). The UI can
  /// say "Download these in the Files app first". Entries: `rootId|rel`.
  List<String> get notDownloaded => _notDownloaded;
  int get notDownloadedCount => _notDownloaded.length;

  /// `.flac` files that could not be parsed in the last scan.
  int get unreadableCount => _unreadable;

  /// "Import files" (copy into Documents) is offered on iOS.
  bool get canImport => _isIOS;

  /// Both platforms can add folders (Android: folder picker, iOS: Files).
  bool get canAddRoots => _isIOS || _isAndroid;

  LibraryRoot? root(String id) {
    for (final r in _roots) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// "On My iPhone" for `docs`, the folder's name otherwise.
  String rootDisplayName(String rootId) {
    if (rootId == kDocsRootId) return 'On My iPhone';
    final r = root(rootId);
    if (r != null && r.displayName.isNotEmpty) return r.displayName;
    if (rootId.startsWith(kBookmarkRootPrefix)) return 'Folder';
    final b = p.basename(rootId);
    return b.isEmpty ? rootId : b;
  }

  /// Sub-folders + tracks directly in [relDir] ('' = root).
  FolderListing listFolder(String rootId, String relDir) =>
      _index.listFolder(rootId, relDir, rootName: rootDisplayName(rootId));

  /// Every track at or below [relDir], in folder order ("Play folder").
  List<Track> tracksUnder(String rootId, String relDir) =>
      _index.tracksUnder(rootId, relDir);

  /// Resolves keys to tracks, skipping missing ones.
  List<Track> tracksFor(Iterable<String> keys) => [
        for (final k in keys)
          if (_index.byKey[k] != null) _index.byKey[k]!,
      ];

  /// Simple case-insensitive search over title/artist/album.
  List<Track> searchTracks(String query, {int limit = 200}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <Track>[];
    for (final t in _index.tracks) {
      if (t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          t.album.toLowerCase().contains(q)) {
        out.add(t);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  /// Loads roots + cache and starts a background rescan (not awaited).
  Future<void> init({bool scan = true}) async {
    _rootsFile = JsonFile(AppPaths.supportFile('roots.json'));
    _cacheFile = JsonFile(AppPaths.supportFile('library.json'));
    await _loadRoots();
    await _resolveRoots();
    await _loadCache();
    if (_isAndroid) {
      _needsPermission = !await _hasMediaPermission();
    }
    _rebuildIndex();
    _initialized = true;
    notifyListeners();
    if (scan && !_needsPermission) unawaited(rescan());
  }

  Future<void> _loadRoots() async {
    final j = await _rootsFile.read();
    final list = <LibraryRoot>[];
    if (j is List) {
      for (final e in j) {
        if (e is Map) {
          try {
            list.add(LibraryRoot.fromJson(e.cast<String, dynamic>()));
          } catch (_) {}
        }
      }
    }
    if (_isIOS) {
      list.removeWhere((r) => r.kind == RootKind.docs);
      list.insert(
          0,
          const LibraryRoot(
              id: kDocsRootId, kind: RootKind.docs, displayName: 'On My iPhone'));
    }
    _roots = list;
  }

  Future<void> _saveRoots() => _rootsFile.write([
        for (final r in _roots)
          if (r.kind != RootKind.docs) r.toJson(),
      ]);

  /// Fills in the current absolute path of each root.
  Future<void> _resolveRoots() async {
    final bookmarks = <Map<String, String>>[];
    for (final r in _roots) {
      if (r.kind == RootKind.bookmark && r.bookmark != null) {
        bookmarks.add({
          'id': r.id.substring(kBookmarkRootPrefix.length),
          'bookmark': r.bookmark!,
        });
      }
    }
    final resolved = await NativeAudio.resolveFolders(bookmarks);
    var changed = false;
    final out = <LibraryRoot>[];
    for (final r in _roots) {
      switch (r.kind) {
        case RootKind.docs:
          out.add(r.copyWith(path: AppPaths.docs.path));
        case RootKind.folder:
          final exists = await Directory(r.id).exists();
          out.add(exists ? r.copyWith(path: r.id) : r.copyWith(clearPath: true));
        case RootKind.bookmark:
          final res = resolved[r.id.substring(kBookmarkRootPrefix.length)];
          if (res != null && res['ok'] == true && res['path'] is String) {
            final newBm = res['bookmark'] as String?;
            final newName = res['displayName'] as String?;
            if ((newBm != null && newBm != r.bookmark) ||
                (newName != null && newName.isNotEmpty && newName != r.displayName)) {
              changed = true;
            }
            out.add(r.copyWith(
              path: res['path'] as String,
              bookmark: newBm,
              displayName: (newName != null && newName.isNotEmpty) ? newName : null,
            ));
          } else {
            out.add(r.copyWith(clearPath: true));
          }
      }
    }
    _roots = out;
    if (changed) await _saveRoots();
  }

  Future<void> _loadCache() async {
    _cache.clear();
    final j = await _cacheFile.read();
    if (j is! Map || j['v'] != _cacheVersion) return;
    final list = j['tracks'];
    if (list is! List) return;
    final rootPaths = {for (final r in _roots) r.id: r.path ?? ''};
    final knownRoots = rootPaths.keys.toSet();
    for (final e in list) {
      if (e is! Map) continue;
      try {
        final m = e.cast<String, dynamic>();
        final rootId = m['root'] as String;
        if (!knownRoots.contains(rootId)) continue;
        final t = Track.fromJson(m, rootPaths[rootId]!);
        _cache[t.key] = t;
      } catch (_) {}
    }
  }

  Future<void> _saveCache() => _cacheFile.write({
        'v': _cacheVersion,
        'tracks': [for (final t in _cache.values) t.toJson()],
      });

  void _rebuildIndex() {
    final available = {
      for (final r in _roots)
        if (r.available) r.id,
    };
    _index = LibraryIndex.build(
        [for (final t in _cache.values) if (available.contains(t.root)) t]);
  }

  // ---------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------

  /// Incremental rescan (size + mtime). [full] re-reads every file.
  /// Concurrent calls coalesce into one extra pass.
  Future<void> rescan({bool full = false}) {
    if (_scanFuture != null) {
      _rescanQueued = true;
      return _scanFuture!;
    }
    final f = _scanLoop(full);
    _scanFuture = f;
    return f;
  }

  Future<void> _scanLoop(bool full) async {
    try {
      do {
        _rescanQueued = false;
        await _scanOnce(full);
        full = false;
      } while (_rescanQueued);
    } finally {
      _scanFuture = null;
    }
  }

  Future<void> _scanOnce(bool full) async {
    if (_isAndroid) {
      _needsPermission = !await _hasMediaPermission();
      if (_needsPermission) {
        notifyListeners();
        return;
      }
    }
    _scanning = true;
    _scanDone = 0;
    _scanTotal = 0;
    _scanStatus = 'Looking for files…';
    notifyListeners();

    try {
      await _resolveRootPathsQuick();
      final artDir = AppPaths.art.path;
      final notDownloaded = <String>[];
      var unreadable = 0;
      var cacheChanged = false;

      // Phase 1: list every available root.
      final listings = <LibraryRoot, RootListing>{};
      for (final r in List.of(_roots)) {
        if (!r.available) continue;
        final path = r.path!;
        final listing = await listFlacFilesInBackground(path);
        if (!listing.readable) continue; // keep its cache untouched
        listings[r] = listing;
        notDownloaded.addAll(listing.notDownloaded.map((rel) => '${r.id}|$rel'));
      }

      // Phase 2: decide what needs parsing.
      final toParse = <LibraryRoot, List<FoundFile>>{};
      for (final entry in listings.entries) {
        final r = entry.key;
        final seen = <String>{};
        for (final f in entry.value.files) {
          final key = trackKeyOf(r.id, f.rel);
          seen.add(key);
          final cached = _cache[key];
          if (!full &&
              cached != null &&
              cached.size == f.size &&
              cached.mtime == f.mtime) {
            if (cached.path != joinRootRel(r.path!, f.rel)) {
              _cache[key] = cached.withRootPath(r.path!);
            }
            continue;
          }
          (toParse[r] ??= []).add(f);
        }
        if (root(r.id) == null) continue; // removed meanwhile
        // Drop cache entries whose files disappeared.
        final before = _cache.length;
        _cache.removeWhere((k, t) => t.root == r.id && !seen.contains(k));
        if (_cache.length != before) cacheChanged = true;
      }

      _scanTotal = toParse.values.fold(0, (a, l) => a + l.length);
      _scanStatus = _scanTotal == 0 ? 'Up to date' : 'Reading 0 / $_scanTotal';
      notifyListeners();

      // Phase 3: parse in background isolates, in batches.
      for (final entry in toParse.entries) {
        final r = entry.key;
        final rootPath = r.path!;
        final albumFallback =
            r.kind == RootKind.docs ? kUnknownAlbum : rootDisplayName(r.id);
        final files = entry.value;
        for (var i = 0; i < files.length; i += _batchSize) {
          final batch = files.sublist(i, (i + _batchSize).clamp(0, files.length));
          final parsed =
              await parseFlacFilesInBackground(rootPath, batch, artDir);
          if (root(r.id) == null) break; // root removed meanwhile
          for (final pf in parsed) {
            final key = trackKeyOf(r.id, pf.rel);
            if (!pf.ok) {
              unreadable++;
              if (_cache.remove(key) != null) cacheChanged = true;
              continue;
            }
            _cache[key] = trackFromParsed(
                rootId: r.id, rootPath: rootPath, f: pf, rootAlbumName: albumFallback);
            cacheChanged = true;
          }
          _scanDone += batch.length;
          _scanStatus = 'Reading $_scanDone / $_scanTotal';
          // Publish partial results every few batches for a live library.
          if ((i ~/ _batchSize) % 4 == 3) _rebuildIndex();
          notifyListeners();
        }
      }

      _notDownloaded = List.unmodifiable(notDownloaded);
      _unreadable = unreadable;
      _rebuildIndex();
      if (cacheChanged) await _saveCache();
      _lastScan = DateTime.now();
      await _gcArt();
    } catch (e, st) {
      debugPrint('Library scan failed: $e\n$st');
    } finally {
      _scanning = false;
      _scanStatus = '';
      _scanDone = 0;
      _scanTotal = 0;
      notifyListeners();
    }
  }

  /// Re-checks folder roots' existence (cheap) before a scan.
  Future<void> _resolveRootPathsQuick() async {
    final exists = <String, bool>{};
    for (final r in List.of(_roots)) {
      if (r.kind == RootKind.folder) exists[r.id] = await Directory(r.id).exists();
    }
    // Apply to the current list (roots may have changed while awaiting).
    _roots = [
      for (final r in _roots)
        switch (r.kind) {
          RootKind.folder => (exists[r.id] ?? r.available)
              ? r.copyWith(path: r.id)
              : r.copyWith(clearPath: true),
          RootKind.docs => r.copyWith(path: AppPaths.docs.path),
          RootKind.bookmark => r,
        },
    ];
  }

  /// Deletes cached art files no track references any more.
  Future<void> _gcArt() async {
    try {
      final used = {
        for (final t in _cache.values)
          if (t.artHash != null) '${t.artHash}.img',
      };
      await for (final e in AppPaths.art.list(followLinks: false)) {
        if (e is File) {
          final name = p.basename(e.path);
          if (!used.contains(name)) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Roots
  // ---------------------------------------------------------------------

  /// Android: media-library permission (READ_MEDIA_AUDIO on 13+,
  /// READ_EXTERNAL_STORAGE below). Always true elsewhere.
  Future<bool> requestPermission() async {
    if (!_isAndroid) return true;
    final perm = await _mediaPermission();
    var status = await perm.status;
    if (!status.isGranted) status = await perm.request();
    final granted = status.isGranted || status.isLimited;
    final was = _needsPermission;
    _needsPermission = !granted;
    notifyListeners();
    if (granted && was) unawaited(rescan());
    return granted;
  }

  /// True when the user permanently denied the permission (UI should offer
  /// `openAppSettings()` from permission_handler).
  Future<bool> permissionPermanentlyDenied() async {
    if (!_isAndroid) return false;
    return (await (await _mediaPermission()).status).isPermanentlyDenied;
  }

  Future<Permission> _mediaPermission() async {
    final sdk = await NativeAudio.androidSdkInt();
    return sdk >= 33 ? Permission.audio : Permission.storage;
  }

  Future<bool> _hasMediaPermission() async {
    if (!_isAndroid) return true;
    try {
      final st = await (await _mediaPermission()).status;
      return st.isGranted || st.isLimited;
    } catch (_) {
      return true;
    }
  }

  /// Lets the user pick a music folder and adds it as a root, then rescans.
  /// Android: system folder picker (asks for media permission first).
  /// iOS: Files folder picker (security-scoped bookmark).
  /// Returns the new root, or null if cancelled/failed/duplicate.
  Future<LibraryRoot?> addRoot() async {
    if (_isIOS) return _addBookmarkRoot();
    if (_isAndroid) {
      if (!await requestPermission()) return null;
      String? path;
      try {
        // getDirectoryPath returns a real filesystem path on Android, which
        // Dart IO can read with the media permission (pickDirectory returns
        // a content:// URI that dart:io cannot open).
        // ignore: deprecated_member_use
        path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose music folder');
      } catch (e) {
        debugPrint('Folder picker failed: $e');
      }
      if (path == null || path.isEmpty) return null;
      return addRootPath(path);
    }
    return null;
  }

  /// Adds an absolute folder path as a root (Android / tests). Rejects
  /// duplicates and folders already inside an existing root; a new folder
  /// that contains existing roots replaces them.
  Future<LibraryRoot?> addRootPath(String path, {bool scan = true}) async {
    final norm = p.normalize(path);
    for (final r in _roots) {
      if (r.kind != RootKind.folder) continue;
      if (r.id == norm || p.isWithin(r.id, norm)) return null;
    }
    final inside = _roots
        .where((r) => r.kind == RootKind.folder && p.isWithin(norm, r.id))
        .map((r) => r.id)
        .toSet();
    if (inside.isNotEmpty) {
      _roots.removeWhere((r) => inside.contains(r.id));
      _cache.removeWhere((k, t) => inside.contains(t.root));
    }
    final exists = await Directory(norm).exists();
    final root = LibraryRoot(
      id: norm,
      kind: RootKind.folder,
      displayName: p.basename(norm).isEmpty ? norm : p.basename(norm),
      path: exists ? norm : null,
    );
    _roots.add(root);
    await _saveRoots();
    _rebuildIndex();
    notifyListeners();
    if (scan) unawaited(rescan());
    return root;
  }

  Future<LibraryRoot?> _addBookmarkRoot() async {
    final res = await NativeAudio.pickFolder();
    if (res == null) return null;
    final id = res['id'] as String?;
    final bookmark = res['bookmark'] as String?;
    final path = res['path'] as String?;
    if (id == null || bookmark == null || path == null) return null;
    // Same folder picked twice: keep the existing root.
    for (final r in _roots) {
      if (r.kind == RootKind.bookmark && r.path == path) {
        await NativeAudio.releaseFolder(id);
        return null;
      }
    }
    final root = LibraryRoot(
      id: '$kBookmarkRootPrefix$id',
      kind: RootKind.bookmark,
      displayName: (res['displayName'] as String?) ?? p.basename(path),
      path: path,
      bookmark: bookmark,
    );
    _roots.add(root);
    await _saveRoots();
    notifyListeners();
    unawaited(rescan());
    return root;
  }

  /// Removes a root (not `docs`) and forgets its tracks. Playlists keep the
  /// keys, so re-adding the same Android folder restores them.
  Future<void> removeRoot(String rootId) async {
    final r = root(rootId);
    if (r == null || !r.removable) return;
    if (r.kind == RootKind.bookmark) {
      await NativeAudio.releaseFolder(rootId.substring(kBookmarkRootPrefix.length));
    }
    _roots.removeWhere((x) => x.id == rootId);
    _cache.removeWhere((k, t) => t.root == rootId);
    _notDownloaded =
        List.unmodifiable(_notDownloaded.where((k) => !k.startsWith('$rootId|')));
    await _saveRoots();
    await _saveCache();
    _rebuildIndex();
    notifyListeners();
    unawaited(_gcArt());
  }

  /// iOS: pick `.flac` files in the Files app and copy them into Documents.
  /// Returns the number of files imported.
  Future<int> importFiles() async {
    if (!_isIOS) return 0;
    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: const ['flac']);
    } catch (_) {
      try {
        picked = await FilePicker.pickFiles(type: FileType.any);
      } catch (e) {
        debugPrint('Import picker failed: $e');
        return 0;
      }
    }
    var count = 0;
    for (final f in picked) {
      final src = f.path;
      if (src == null || !f.name.toLowerCase().endsWith('.flac')) continue;
      try {
        final dest = await _uniqueDocsPath(f.name);
        await File(src).copy(dest);
        count++;
      } catch (e) {
        debugPrint('Import of ${f.name} failed: $e');
      }
    }
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {}
    if (count > 0) unawaited(rescan());
    return count;
  }

  Future<String> _uniqueDocsPath(String name) async {
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    var candidate = p.join(AppPaths.docs.path, name);
    var n = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(AppPaths.docs.path, '$base ($n)$ext');
      n++;
    }
    return candidate;
  }
}

final LibraryStore libraryStore = LibraryStore();
