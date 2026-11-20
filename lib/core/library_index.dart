import 'models.dart';

/// Pure, platform-free indexes over a list of tracks: albums, artists,
/// key lookup and the folder tree. Rebuilt by `libraryStore` after scans.
class LibraryIndex {
  /// All tracks sorted by title.
  final List<Track> tracks;
  final Map<String, Track> byKey;

  /// Sorted by title.
  final List<Album> albums;
  final Map<String, Album> albumById;

  /// Sorted by name.
  final List<Artist> artists;
  final Map<String, Artist> artistByName;

  /// rootId -> relDir -> tracks directly in that folder.
  final Map<String, Map<String, List<Track>>> _filesByDir;

  /// rootId -> relDir -> child folder names.
  final Map<String, Map<String, Set<String>>> _childDirs;

  /// rootId -> relDir -> number of tracks at or below the folder.
  final Map<String, Map<String, int>> _countBelow;

  LibraryIndex._(
    this.tracks,
    this.byKey,
    this.albums,
    this.albumById,
    this.artists,
    this.artistByName,
    this._filesByDir,
    this._childDirs,
    this._countBelow,
  );

  static final empty = LibraryIndex.build(const []);

  static int _cmpText(String a, String b) =>
      _sortKey(a).compareTo(_sortKey(b));

  /// Case-insensitive, ignores a leading "The ".
  static String _sortKey(String s) {
    final l = s.toLowerCase().trim();
    return l.startsWith('the ') ? l.substring(4) : l;
  }

  static int compareInAlbum(Track a, Track b) {
    final d = (a.discNo ?? 1).compareTo(b.discNo ?? 1);
    if (d != 0) return d;
    final t = (a.trackNo ?? 1 << 20).compareTo(b.trackNo ?? 1 << 20);
    if (t != 0) return t;
    return a.rel.toLowerCase().compareTo(b.rel.toLowerCase());
  }

  /// Natural-ish file order inside a folder: by track number when both have
  /// one and share the album, else by file name.
  static int compareInFolder(Track a, Track b) {
    if (a.album == b.album && a.trackNo != null && b.trackNo != null) {
      return compareInAlbum(a, b);
    }
    return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
  }

  factory LibraryIndex.build(List<Track> input) {
    final byKey = <String, Track>{};
    for (final t in input) {
      byKey[t.key] = t;
    }
    final tracks = byKey.values.toList()
      ..sort((a, b) {
        final c = _cmpText(a.title, b.title);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

    // Albums.
    final albumTracks = <String, List<Track>>{};
    for (final t in tracks) {
      (albumTracks[t.albumId] ??= []).add(t);
    }
    final albums = <Album>[];
    final albumById = <String, Album>{};
    albumTracks.forEach((id, list) {
      list.sort(compareInAlbum);
      final first = list.first;
      int? year;
      for (final t in list) {
        if (t.year != null) {
          year = t.year;
          break;
        }
      }
      final a = Album(
        id: id,
        title: first.album,
        artist: first.albumArtist,
        year: year,
        tracks: List.unmodifiable(list),
      );
      albums.add(a);
      albumById[id] = a;
    });
    albums.sort((a, b) {
      final c = _cmpText(a.title, b.title);
      return c != 0 ? c : _cmpText(a.artist, b.artist);
    });

    // Artists: by album artist (so compilations group sensibly).
    final artistAlbums = <String, List<Album>>{};
    final artistNames = <String, String>{};
    for (final a in albums) {
      final k = a.artist.toLowerCase();
      artistNames.putIfAbsent(k, () => a.artist);
      (artistAlbums[k] ??= []).add(a);
    }
    final artists = <Artist>[];
    final artistByName = <String, Artist>{};
    artistAlbums.forEach((k, albs) {
      albs.sort((x, y) {
        final c = (x.year ?? 0).compareTo(y.year ?? 0);
        return c != 0 ? c : _cmpText(x.title, y.title);
      });
      final ts = <Track>[for (final a in albs) ...a.tracks];
      final ar = Artist(
          name: artistNames[k]!,
          albums: List.unmodifiable(albs),
          tracks: List.unmodifiable(ts));
      artists.add(ar);
      artistByName[k] = ar;
    });
    artists.sort((a, b) => _cmpText(a.name, b.name));

    // Folder tree.
    final filesByDir = <String, Map<String, List<Track>>>{};
    final childDirs = <String, Map<String, Set<String>>>{};
    final countBelow = <String, Map<String, int>>{};
    for (final t in tracks) {
      final files = filesByDir[t.root] ??= {};
      final children = childDirs[t.root] ??= {};
      final counts = countBelow[t.root] ??= {};
      final dir = t.relDir;
      (files[dir] ??= []).add(t);
      // Walk up: register each segment as child of its parent and count.
      var cur = dir;
      while (true) {
        counts[cur] = (counts[cur] ?? 0) + 1;
        if (cur.isEmpty) break;
        final i = cur.lastIndexOf('/');
        final parent = i < 0 ? '' : cur.substring(0, i);
        final name = i < 0 ? cur : cur.substring(i + 1);
        (children[parent] ??= <String>{}).add(name);
        cur = parent;
      }
    }
    for (final m in filesByDir.values) {
      for (final l in m.values) {
        l.sort(compareInFolder);
      }
    }

    return LibraryIndex._(
      List.unmodifiable(tracks),
      byKey,
      List.unmodifiable(albums),
      albumById,
      List.unmodifiable(artists),
      artistByName,
      filesByDir,
      childDirs,
      countBelow,
    );
  }

  /// Album for an artist name lookup is case-insensitive.
  Artist? artist(String name) => artistByName[name.toLowerCase()];

  /// Sub-folders + tracks directly in [relDir] of [rootId].
  /// [rootName] is used as the listing name at the root.
  FolderListing listFolder(String rootId, String relDir, {String? rootName}) {
    final dir = _normDir(relDir);
    final names = (_childDirs[rootId]?[dir] ?? const <String>{}).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final counts = _countBelow[rootId] ?? const <String, int>{};
    final folders = [
      for (final n in names)
        FolderEntry(
          rootId: rootId,
          relDir: dir.isEmpty ? n : '$dir/$n',
          name: n,
          trackCount: counts[dir.isEmpty ? n : '$dir/$n'] ?? 0,
        ),
    ];
    final tracks = List<Track>.unmodifiable(
        _filesByDir[rootId]?[dir] ?? const <Track>[]);
    final name = dir.isEmpty
        ? (rootName ?? rootId)
        : dir.substring(dir.lastIndexOf('/') + 1);
    return FolderListing(
      rootId: rootId,
      relDir: dir,
      name: name,
      folders: folders,
      tracks: tracks,
    );
  }

  /// All tracks at or below [relDir], in folder order (depth-first, folders
  /// sorted by name, files in folder order). Used for "Play folder".
  List<Track> tracksUnder(String rootId, String relDir) {
    final out = <Track>[];
    void walk(String dir) {
      out.addAll(_filesByDir[rootId]?[dir] ?? const <Track>[]);
      final names = (_childDirs[rootId]?[dir] ?? const <String>{}).toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      for (final n in names) {
        walk(dir.isEmpty ? n : '$dir/$n');
      }
    }

    walk(_normDir(relDir));
    return out;
  }

  /// Number of tracks at or below [relDir].
  int countUnder(String rootId, String relDir) =>
      _countBelow[rootId]?[_normDir(relDir)] ?? 0;

  static String _normDir(String d) {
    var s = d.replaceAll('\\', '/');
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}
