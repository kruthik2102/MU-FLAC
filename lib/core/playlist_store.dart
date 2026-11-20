import 'dart:math';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';
import 'json_file.dart';
import 'library_store.dart';
import 'models.dart';

/// Manual playlists + the built-in Favorites (`favorites`, always first,
/// cannot be deleted or renamed). Persisted to `<support>/playlists.json`.
class PlaylistStore extends ChangeNotifier {
  PlaylistStore({this.resolver});

  /// Key -> track lookup (defaults to `libraryStore.track`; tests inject).
  final Track? Function(String key)? resolver;
  JsonFile? _file;
  final List<Playlist> _lists = [];
  Set<String> _favSet = {};
  final Random _rng = Random();

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// All playlists, Favorites first, then by creation time.
  List<Playlist> get playlists => List.unmodifiable(_lists);

  /// User playlists only (no Favorites).
  List<Playlist> get userPlaylists =>
      List.unmodifiable(_lists.where((p) => !p.isFavorites));

  Playlist get favorites => _lists.firstWhere((p) => p.isFavorites);

  Playlist? byId(String id) {
    for (final p in _lists) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> load({String? path}) async {
    _file = JsonFile(path ?? AppPaths.supportFile('playlists.json'));
    final j = await _file!.read();
    _lists.clear();
    if (j is Map && j['playlists'] is List) {
      for (final e in j['playlists'] as List) {
        if (e is Map) {
          try {
            _lists.add(Playlist.fromJson(e.cast<String, dynamic>()));
          } catch (_) {}
        }
      }
    }
    _ensureFavorites();
    notifyListeners();
  }

  void _ensureFavorites() {
    final i = _lists.indexWhere((p) => p.isFavorites);
    Playlist fav;
    if (i < 0) {
      final t = _now();
      fav = Playlist(
          id: kFavoritesId,
          name: 'Favorites',
          trackKeys: const [],
          createdAt: t,
          updatedAt: t);
    } else {
      fav = _lists.removeAt(i);
    }
    _lists.insert(0, fav.copyWith(name: 'Favorites'));
    _favSet = fav.trackKeys.toSet();
  }

  Future<void> _save() async {
    notifyListeners();
    await _file?.write({
      'v': 1,
      'playlists': [for (final p in _lists) p.toJson()],
    });
  }

  void _replace(Playlist updated) {
    final i = _lists.indexWhere((p) => p.id == updated.id);
    if (i >= 0) _lists[i] = updated;
    if (updated.isFavorites) _favSet = updated.trackKeys.toSet();
  }

  String _newId() {
    String id;
    do {
      id = 'pl_${_now().toRadixString(36)}${_rng.nextInt(1 << 30).toRadixString(36)}';
    } while (byId(id) != null);
    return id;
  }

  // ---- CRUD ---------------------------------------------------------------

  Future<Playlist> create(String name, {List<String> trackKeys = const []}) async {
    final t = _now();
    final pl = Playlist(
      id: _newId(),
      name: name.trim().isEmpty ? 'New Playlist' : name.trim(),
      trackKeys: List.of(trackKeys),
      createdAt: t,
      updatedAt: t,
    );
    _lists.add(pl);
    await _save();
    return pl;
  }

  /// Favorites cannot be renamed.
  Future<void> rename(String id, String name) async {
    final pl = byId(id);
    if (pl == null || pl.isFavorites || name.trim().isEmpty) return;
    _replace(pl.copyWith(name: name.trim(), updatedAt: _now()));
    await _save();
  }

  /// Favorites cannot be deleted.
  Future<void> delete(String id) async {
    if (id == kFavoritesId) return;
    final before = _lists.length;
    _lists.removeWhere((p) => p.id == id);
    if (_lists.length != before) await _save();
  }

  /// Appends [keys]. With [skipDuplicates], keys already present are skipped.
  /// Returns how many were added.
  Future<int> addTracks(String id, List<String> keys,
      {bool skipDuplicates = false}) async {
    final pl = byId(id);
    if (pl == null || keys.isEmpty) return 0;
    final list = List.of(pl.trackKeys);
    final present = list.toSet();
    var added = 0;
    for (final k in keys) {
      if (skipDuplicates && present.contains(k)) continue;
      list.add(k);
      present.add(k);
      added++;
    }
    if (added == 0) return 0;
    _replace(pl.copyWith(trackKeys: list, updatedAt: _now()));
    await _save();
    return added;
  }

  /// Removes the entry at [index] (positions refer to [Playlist.trackKeys]).
  Future<void> removeAt(String id, int index) async {
    final pl = byId(id);
    if (pl == null || index < 0 || index >= pl.trackKeys.length) return;
    final list = List.of(pl.trackKeys)..removeAt(index);
    _replace(pl.copyWith(trackKeys: list, updatedAt: _now()));
    await _save();
  }

  /// Removes every occurrence of [key].
  Future<void> removeTrack(String id, String key) async {
    final pl = byId(id);
    if (pl == null || !pl.trackKeys.contains(key)) return;
    final list = pl.trackKeys.where((k) => k != key).toList();
    _replace(pl.copyWith(trackKeys: list, updatedAt: _now()));
    await _save();
  }

  /// Moves the entry at [from] so it ends up at [to] (both are final
  /// positions in the list, like `List.insert(to, removeAt(from))`).
  Future<void> move(String id, int from, int to) async {
    final pl = byId(id);
    if (pl == null) return;
    final n = pl.trackKeys.length;
    if (from < 0 || from >= n || to < 0 || to >= n || from == to) return;
    final list = List.of(pl.trackKeys);
    list.insert(to, list.removeAt(from));
    _replace(pl.copyWith(trackKeys: list, updatedAt: _now()));
    await _save();
  }

  // ---- Favorites ----------------------------------------------------------

  bool isFavorite(String trackKey) => _favSet.contains(trackKey);

  /// Returns the new state (true = now a favorite). Newest favorites are
  /// added at the top.
  Future<bool> toggleFavorite(String trackKey) async {
    final fav = favorites;
    final List<String> list;
    final bool nowFav;
    if (_favSet.contains(trackKey)) {
      list = fav.trackKeys.where((k) => k != trackKey).toList();
      nowFav = false;
    } else {
      list = [trackKey, ...fav.trackKeys];
      nowFav = true;
    }
    _replace(fav.copyWith(trackKeys: list, updatedAt: _now()));
    await _save();
    return nowFav;
  }

  // ---- Resolution ---------------------------------------------------------

  /// Tracks of a playlist that exist in the library right now (missing
  /// files are skipped, their keys are kept).
  List<Track> tracksOf(String id) {
    final pl = byId(id);
    if (pl == null) return const [];
    final resolve = resolver ?? libraryStore.track;
    return [
      for (final k in pl.trackKeys) ?resolve(k),
    ];
  }

  /// Playable entries with their position in [Playlist.trackKeys]; use
  /// `index` with [removeAt]/[move] when some files are missing.
  List<({int index, Track track})> entriesOf(String id) {
    final pl = byId(id);
    if (pl == null) return const [];
    final resolve = resolver ?? libraryStore.track;
    final out = <({int index, Track track})>[];
    for (var i = 0; i < pl.trackKeys.length; i++) {
      final t = resolve(pl.trackKeys[i]);
      if (t != null) out.add((index: i, track: t));
    }
    return out;
  }

  /// Number of playable tracks in a playlist.
  int playableCount(String id) => tracksOf(id).length;
}

final PlaylistStore playlistStore = PlaylistStore();
