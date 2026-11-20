import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'flac_meta.dart';
import 'models.dart';

/// One FLAC file found on disk.
class FoundFile {
  /// `/`-separated path relative to the root.
  final String rel;
  final int size;
  final int mtime;
  const FoundFile(this.rel, this.size, this.mtime);
}

/// Result of walking one root.
class RootListing {
  final List<FoundFile> files;

  /// iCloud placeholders (`.Name.flac.icloud`): files not downloaded to the
  /// device. Relative paths of the real file names.
  final List<String> notDownloaded;

  /// False when the root folder itself could not be read.
  final bool readable;

  const RootListing(this.files, this.notDownloaded, this.readable);
}

/// Parsed metadata ready to become a [Track] (sendable between isolates).
class ParsedFile {
  final String rel;
  final int size;
  final int mtime;
  final bool ok;
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final int? trackNo;
  final int? trackTotal;
  final int? discNo;
  final int? year;
  final int durationMs;
  final int sampleRate;
  final int bitDepth;
  final int channels;
  final String? artHash;

  const ParsedFile({
    required this.rel,
    required this.size,
    required this.mtime,
    required this.ok,
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.trackNo,
    this.trackTotal,
    this.discNo,
    this.year,
    this.durationMs = 0,
    this.sampleRate = 0,
    this.bitDepth = 0,
    this.channels = 0,
    this.artHash,
  });
}

final RegExp _icloudPlaceholder =
    RegExp(r'^\.(.+\.flac)\.icloud$', caseSensitive: false);

/// Recursively lists `.flac` files under [rootPath]. Hidden files/folders
/// are skipped; unreadable sub-folders are skipped silently. Safe to run in
/// a background isolate.
Future<RootListing> listFlacFiles(String rootPath) async {
  final root = Directory(rootPath);
  if (!await root.exists()) return const RootListing([], [], false);
  final files = <FoundFile>[];
  final notDownloaded = <String>[];
  var rootReadable = true;

  Future<void> walk(Directory dir, String relDir, int depth) async {
    if (depth > 32) return;
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } catch (_) {
      if (relDir.isEmpty) rootReadable = false;
      return;
    }
    for (final e in entries) {
      final name = p.basename(e.path);
      final rel = relDir.isEmpty ? name : '$relDir/$name';
      if (e is Directory) {
        if (name.startsWith('.')) continue;
        await walk(e, rel, depth + 1);
      } else if (e is File) {
        final lower = name.toLowerCase();
        if (name.startsWith('.')) {
          final m = _icloudPlaceholder.firstMatch(name);
          if (m != null) {
            notDownloaded
                .add(relDir.isEmpty ? m.group(1)! : '$relDir/${m.group(1)!}');
          }
          continue;
        }
        if (!lower.endsWith('.flac')) continue;
        try {
          final st = await e.stat();
          files.add(
              FoundFile(rel, st.size, st.modified.millisecondsSinceEpoch));
        } catch (_) {}
      }
    }
  }

  await walk(root, '', 0);
  return RootListing(files, notDownloaded, rootReadable);
}

/// Parses [files] under [rootPath], caching embedded art into [artDir] as
/// `<sha1>.img`. Safe to run in a background isolate.
Future<List<ParsedFile>> parseFlacFiles(
    String rootPath, List<FoundFile> files, String artDir) async {
  final out = <ParsedFile>[];
  for (final f in files) {
    final path = joinRootRel(rootPath, f.rel);
    final meta = await FlacParser.parseFile(path);
    if (meta == null) {
      out.add(ParsedFile(rel: f.rel, size: f.size, mtime: f.mtime, ok: false));
      continue;
    }
    String? artHash;
    final pic = meta.picture;
    if (pic != null && pic.data.isNotEmpty) {
      artHash = sha1.convert(pic.data).toString().substring(0, 32);
      try {
        final art = File(p.join(artDir, '$artHash.img'));
        if (!await art.exists()) {
          final tmp = File('${art.path}.tmp');
          await tmp.writeAsBytes(pic.data, flush: true);
          await tmp.rename(art.path);
        }
      } catch (_) {
        artHash = null;
      }
    }
    out.add(ParsedFile(
      rel: f.rel,
      size: f.size,
      mtime: f.mtime,
      ok: true,
      title: meta.title,
      artist: meta.artist,
      album: meta.album,
      albumArtist: meta.albumArtist,
      genre: meta.genre,
      trackNo: meta.trackNumber,
      trackTotal: meta.trackTotal,
      discNo: meta.discNumber,
      year: meta.year,
      durationMs: meta.durationMs,
      sampleRate: meta.sampleRate,
      bitDepth: meta.bitsPerSample,
      channels: meta.channels,
      artHash: artHash,
    ));
  }
  return out;
}

/// Builds a [Track] applying fallbacks: title = file name, artist =
/// "Unknown Artist", album = containing folder name ([rootAlbumName] for
/// files directly in the root).
Track trackFromParsed({
  required String rootId,
  required String rootPath,
  required ParsedFile f,
  required String rootAlbumName,
}) {
  final fileName = f.rel.substring(f.rel.lastIndexOf('/') + 1);
  final baseName = fileName.toLowerCase().endsWith('.flac')
      ? fileName.substring(0, fileName.length - 5)
      : fileName;
  final slash = f.rel.lastIndexOf('/');
  final relDir = slash < 0 ? '' : f.rel.substring(0, slash);
  final folderName =
      relDir.isEmpty ? rootAlbumName : relDir.substring(relDir.lastIndexOf('/') + 1);
  final artist = _nz(f.artist) ?? kUnknownArtist;
  return Track(
    root: rootId,
    rel: f.rel,
    path: joinRootRel(rootPath, f.rel),
    title: _nz(f.title) ?? baseName,
    artist: artist,
    album: _nz(f.album) ?? folderName,
    albumArtist: _nz(f.albumArtist) ?? artist,
    genre: _nz(f.genre),
    trackNo: f.trackNo,
    trackTotal: f.trackTotal,
    discNo: f.discNo,
    year: f.year,
    durationMs: f.durationMs,
    sampleRate: f.sampleRate,
    bitDepth: f.bitDepth,
    channels: f.channels,
    size: f.size,
    mtime: f.mtime,
    artHash: f.artHash,
    hasTags: _nz(f.title) != null && _nz(f.artist) != null && _nz(f.album) != null,
  );
}

String? _nz(String? s) {
  if (s == null) return null;
  final t = s.trim();
  return t.isEmpty ? null : t;
}

/// Runs [listFlacFiles] in a background isolate. Top-level so the closure
/// captures only sendable arguments.
Future<RootListing> listFlacFilesInBackground(String rootPath) =>
    Isolate.run(() => listFlacFiles(rootPath));

/// Runs [parseFlacFiles] in a background isolate.
Future<List<ParsedFile>> parseFlacFilesInBackground(
        String rootPath, List<FoundFile> files, String artDir) =>
    Isolate.run(() => parseFlacFiles(rootPath, files, artDir));
