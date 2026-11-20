import 'dart:ui' show Color;

import 'package:path/path.dart' as p;

import 'app_paths.dart';

/// Root id of the iOS app Documents folder ("On My iPhone > MU-FLAC").
const String kDocsRootId = 'docs';

/// Prefix of iOS user-picked folder roots (security-scoped bookmarks).
const String kBookmarkRootPrefix = 'bm:';

/// Fixed id of the built-in Favorites playlist.
const String kFavoritesId = 'favorites';

const String kUnknownArtist = 'Unknown Artist';
const String kUnknownAlbum = 'Unknown Album';

/// Builds the stable key of a track: `<rootId>|<relativePath>` where the
/// relative path always uses `/`.
String trackKeyOf(String rootId, String rel) => '$rootId|$rel';

/// One FLAC file in the library.
///
/// Identity is ([root], [rel]); [path] is resolved at runtime from the root
/// (iOS container paths change between installs).
class Track {
  /// `<root>|<rel>`, stable across launches. Used by playlists/favorites.
  final String key;

  /// Root id: `docs`, `bm:<id>` (iOS picked folder) or an absolute folder
  /// path (Android).
  final String root;

  /// Path relative to the root, `/`-separated, e.g. `Pink Floyd/DSOTM/01.flac`.
  final String rel;

  /// Absolute path on this device right now.
  final String path;

  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String? genre;
  final int? trackNo;
  final int? trackTotal;
  final int? discNo;
  final int? year;
  final int durationMs;
  final int sampleRate;
  final int bitDepth;
  final int channels;
  final int size;

  /// File modification time, ms since epoch.
  final int mtime;

  /// Hash of the embedded cover (art cache file name), or null.
  final String? artHash;

  /// True when TITLE/ARTIST/ALBUM tags were missing and fallbacks were used.
  final bool hasTags;

  Track({
    required this.root,
    required this.rel,
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    this.genre,
    this.trackNo,
    this.trackTotal,
    this.discNo,
    this.year,
    required this.durationMs,
    required this.sampleRate,
    required this.bitDepth,
    required this.channels,
    required this.size,
    required this.mtime,
    this.artHash,
    this.hasTags = true,
  }) : key = trackKeyOf(root, rel);

  /// Resolved path of the cached cover image, or null when no embedded art.
  String? get artPath => artHash == null ? null : AppPaths.artFile(artHash!);

  /// `file://` URI of the cover (for MediaItem.artUri), or null.
  Uri? get artUri => artPath == null ? null : Uri.file(artPath!);

  Duration get duration => Duration(milliseconds: durationMs);

  /// Average bitrate in kbps (file size * 8 / duration), 0 if unknown.
  int get bitrateKbps =>
      durationMs <= 0 ? 0 : (size * 8 / durationMs).round(); // bits/ms = kbps

  /// Folder of the file relative to its root ('' = root itself).
  String get relDir {
    final i = rel.lastIndexOf('/');
    return i < 0 ? '' : rel.substring(0, i);
  }

  String get fileName => rel.substring(rel.lastIndexOf('/') + 1);

  /// e.g. "FLAC 24/96", "FLAC 16/44.1".
  String get formatLabel => 'FLAC $bitDepth/${formatKhz(sampleRate)}';

  /// Album grouping key (album artist + album, case-insensitive).
  String get albumId => albumIdOf(albumArtist, album);

  /// Deterministic placeholder colours for missing art (seeded by album).
  (Color, Color) get placeholderColors => placeholderColorsFor(album);

  Map<String, dynamic> toJson() => {
        'root': root,
        'rel': rel,
        'title': title,
        'artist': artist,
        'album': album,
        'albumArtist': albumArtist,
        if (genre != null) 'genre': genre,
        if (trackNo != null) 'trackNo': trackNo,
        if (trackTotal != null) 'trackTotal': trackTotal,
        if (discNo != null) 'discNo': discNo,
        if (year != null) 'year': year,
        'durationMs': durationMs,
        'sampleRate': sampleRate,
        'bitDepth': bitDepth,
        'channels': channels,
        'size': size,
        'mtime': mtime,
        if (artHash != null) 'artHash': artHash,
        if (!hasTags) 'hasTags': false,
      };

  /// [rootPath] is the current absolute path of the root.
  static Track fromJson(Map<String, dynamic> j, String rootPath) {
    final rel = j['rel'] as String;
    return Track(
      root: j['root'] as String,
      rel: rel,
      path: joinRootRel(rootPath, rel),
      title: j['title'] as String,
      artist: j['artist'] as String,
      album: j['album'] as String,
      albumArtist: j['albumArtist'] as String,
      genre: j['genre'] as String?,
      trackNo: j['trackNo'] as int?,
      trackTotal: j['trackTotal'] as int?,
      discNo: j['discNo'] as int?,
      year: j['year'] as int?,
      durationMs: j['durationMs'] as int? ?? 0,
      sampleRate: j['sampleRate'] as int? ?? 0,
      bitDepth: j['bitDepth'] as int? ?? 0,
      channels: j['channels'] as int? ?? 0,
      size: j['size'] as int? ?? 0,
      mtime: j['mtime'] as int? ?? 0,
      artHash: j['artHash'] as String?,
      hasTags: j['hasTags'] as bool? ?? true,
    );
  }

  /// Same track with a different absolute root path (root moved/resolved).
  Track withRootPath(String rootPath) => Track(
        root: root,
        rel: rel,
        path: joinRootRel(rootPath, rel),
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        genre: genre,
        trackNo: trackNo,
        trackTotal: trackTotal,
        discNo: discNo,
        year: year,
        durationMs: durationMs,
        sampleRate: sampleRate,
        bitDepth: bitDepth,
        channels: channels,
        size: size,
        mtime: mtime,
        artHash: artHash,
        hasTags: hasTags,
      );

  @override
  bool operator ==(Object other) => other is Track && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'Track($key)';
}

/// Joins a root path and a `/`-separated relative path for this platform.
String joinRootRel(String rootPath, String rel) =>
    rel.isEmpty ? rootPath : p.joinAll([rootPath, ...rel.split('/')]);

String albumIdOf(String albumArtist, String album) =>
    '${albumArtist.toLowerCase()}\u0000${album.toLowerCase()}';

/// 44100 -> "44.1", 96000 -> "96", 0 -> "?".
String formatKhz(int hz) {
  if (hz <= 0) return '?';
  if (hz % 1000 == 0) return '${hz ~/ 1000}';
  final s = (hz / 1000).toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// FNV-1a 32-bit hash (stable across runs/platforms).
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Deterministic two-colour gradient for missing art, seeded by [seed]
/// (usually the album name). Returns (start, end) colours.
(Color, Color) placeholderColorsFor(String seed) {
  final h = stableHash(seed.toLowerCase());
  final hue1 = (h % 360).toDouble();
  final hue2 = (hue1 + 35 + (h >> 9) % 50) % 360;
  return (_hsl(hue1, 0.55, 0.42), _hsl(hue2, 0.60, 0.28));
}

Color _hsl(double h, double s, double l) {
  final c = (1 - (2 * l - 1).abs()) * s;
  final hp = h / 60.0;
  final x = c * (1 - ((hp % 2) - 1).abs());
  double r = 0, g = 0, b = 0;
  if (hp < 1) {
    r = c;
    g = x;
  } else if (hp < 2) {
    r = x;
    g = c;
  } else if (hp < 3) {
    g = c;
    b = x;
  } else if (hp < 4) {
    g = x;
    b = c;
  } else if (hp < 5) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }
  final m = l - c / 2;
  int ch(double v) => ((v + m) * 255).round().clamp(0, 255);
  return Color.fromARGB(255, ch(r), ch(g), ch(b));
}

/// An album grouped from tags.
class Album {
  /// [albumIdOf] of albumArtist + title.
  final String id;
  final String title;

  /// Album artist (falls back to the track artist / "Various Artists").
  final String artist;
  final int? year;

  /// Sorted by disc, track number, then file name.
  final List<Track> tracks;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.tracks,
  });

  /// Art of the first track that has any.
  String? get artHash {
    for (final t in tracks) {
      if (t.artHash != null) return t.artHash;
    }
    return null;
  }

  String? get artPath => artHash == null ? null : AppPaths.artFile(artHash!);

  int get durationMs => tracks.fold(0, (a, t) => a + t.durationMs);

  int get discCount =>
      tracks.map((t) => t.discNo ?? 1).toSet().length;

  /// Highest-resolution format among the tracks, e.g. "FLAC 24/96".
  String get formatLabel {
    if (tracks.isEmpty) return 'FLAC';
    final best = tracks.reduce((a, b) =>
        (a.bitDepth * 1000000 + a.sampleRate) >=
                (b.bitDepth * 1000000 + b.sampleRate)
            ? a
            : b);
    return best.formatLabel;
  }

  (Color, Color) get placeholderColors => placeholderColorsFor(title);
}

/// An artist grouped from tags (by album artist, then track artist).
class Artist {
  final String name;
  final List<Album> albums;
  final List<Track> tracks;

  Artist({required this.name, required this.albums, required this.tracks});

  String? get artHash {
    for (final a in albums) {
      final h = a.artHash;
      if (h != null) return h;
    }
    return null;
  }

  String? get artPath => artHash == null ? null : AppPaths.artFile(artHash!);

  (Color, Color) get placeholderColors => placeholderColorsFor(name);
}

/// A manual playlist (or the built-in Favorites).
class Playlist {
  final String id;
  final String name;

  /// Track keys in order. Keys whose files are gone are kept (they reappear
  /// if the file comes back) but skipped by `playlistStore.tracksOf`.
  final List<String> trackKeys;
  final int createdAt;
  final int updatedAt;

  const Playlist({
    required this.id,
    required this.name,
    required this.trackKeys,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isFavorites => id == kFavoritesId;

  Playlist copyWith({String? name, List<String>? trackKeys, int? updatedAt}) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        trackKeys: trackKeys ?? this.trackKeys,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tracks': trackKeys,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  static Playlist fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        trackKeys: ((j['tracks'] as List?) ?? const []).cast<String>().toList(),
        createdAt: j['createdAt'] as int? ?? 0,
        updatedAt: j['updatedAt'] as int? ?? 0,
      );
}

/// A sub-folder entry inside a [FolderListing].
class FolderEntry {
  final String rootId;

  /// Folder path relative to the root (`/`-separated).
  final String relDir;

  /// Last path segment.
  final String name;

  /// Number of tracks anywhere below this folder.
  final int trackCount;

  const FolderEntry({
    required this.rootId,
    required this.relDir,
    required this.name,
    required this.trackCount,
  });
}

/// Contents of one folder: sub-folders (that contain FLACs somewhere below)
/// and the tracks directly inside it.
class FolderListing {
  final String rootId;

  /// '' = the root itself.
  final String relDir;

  /// Display name: root display name for the root, else the folder name.
  final String name;
  final List<FolderEntry> folders;
  final List<Track> tracks;

  const FolderListing({
    required this.rootId,
    required this.relDir,
    required this.name,
    required this.folders,
    required this.tracks,
  });

  bool get isRoot => relDir.isEmpty;

  /// Parent relDir, or null at the root.
  String? get parentRelDir {
    if (relDir.isEmpty) return null;
    final i = relDir.lastIndexOf('/');
    return i < 0 ? '' : relDir.substring(0, i);
  }

  bool get isEmpty => folders.isEmpty && tracks.isEmpty;
}

/// Kinds of library roots.
enum RootKind {
  /// iOS app Documents folder (always present on iOS).
  docs,

  /// iOS folder picked in the Files app (security-scoped bookmark).
  bookmark,

  /// Android folder picked by the user (absolute path).
  folder,
}

/// A configured music source folder.
class LibraryRoot {
  /// `docs`, `bm:<id>` or an absolute path (Android).
  final String id;
  final RootKind kind;

  /// Name to show (e.g. "On My iPhone", "Music").
  final String displayName;

  /// Absolute path right now, or null when unavailable (folder deleted,
  /// bookmark could not be resolved, permission missing).
  final String? path;

  /// Base64 bookmark data (iOS picked folders only).
  final String? bookmark;

  const LibraryRoot({
    required this.id,
    required this.kind,
    required this.displayName,
    this.path,
    this.bookmark,
  });

  bool get available => path != null;

  /// Docs root cannot be removed.
  bool get removable => kind != RootKind.docs;

  /// Longer location text, e.g. "On My iPhone › MU-FLAC" or the full path.
  String get locationLabel => switch (kind) {
        RootKind.docs => 'On My iPhone › MU-FLAC',
        RootKind.bookmark => path ?? displayName,
        RootKind.folder => id,
      };

  LibraryRoot copyWith({String? path, bool clearPath = false, String? bookmark, String? displayName}) =>
      LibraryRoot(
        id: id,
        kind: kind,
        displayName: displayName ?? this.displayName,
        path: clearPath ? null : (path ?? this.path),
        bookmark: bookmark ?? this.bookmark,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'displayName': displayName,
        if (bookmark != null) 'bookmark': bookmark,
      };

  static LibraryRoot fromJson(Map<String, dynamic> j) => LibraryRoot(
        id: j['id'] as String,
        kind: RootKind.values.firstWhere((k) => k.name == j['kind'],
            orElse: () => RootKind.folder),
        displayName: j['displayName'] as String? ?? '',
        bookmark: j['bookmark'] as String?,
      );
}

/// Where audio is currently going.
enum OutputKind { usb, bluetooth, wired, speaker, airplay, hdmi, other, unknown }

class OutputInfo {
  /// e.g. "Moondrop CHU II DSP", "Galaxy Buds2 Pro", "iPhone Speaker".
  final String deviceName;
  final OutputKind kind;

  /// Current hardware/mixer sample rate in Hz (0 = unknown).
  final int sampleRate;

  const OutputInfo({
    required this.deviceName,
    required this.kind,
    required this.sampleRate,
  });

  static const unknown =
      OutputInfo(deviceName: '', kind: OutputKind.unknown, sampleRate: 0);

  static OutputInfo fromMap(Map<dynamic, dynamic>? m) {
    if (m == null) return unknown;
    final kindName = (m['kind'] as String?) ?? 'unknown';
    return OutputInfo(
      deviceName: (m['name'] as String?) ?? '',
      kind: OutputKind.values.firstWhere((k) => k.name == kindName,
          orElse: () => OutputKind.other),
      sampleRate: (m['sampleRate'] as num?)?.round() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OutputInfo &&
      other.deviceName == deviceName &&
      other.kind == kind &&
      other.sampleRate == sampleRate;

  @override
  int get hashCode => Object.hash(deviceName, kind, sampleRate);

  @override
  String toString() => 'OutputInfo($deviceName, ${kind.name}, $sampleRate Hz)';
}

/// Repeat modes.
enum RepeatMode { off, all, one }
