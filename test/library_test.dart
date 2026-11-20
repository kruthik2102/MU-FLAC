import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mu_flac/core/app_paths.dart';
import 'package:mu_flac/core/library_index.dart';
import 'package:mu_flac/core/library_scanner.dart';
import 'package:mu_flac/core/library_store.dart';
import 'package:mu_flac/core/models.dart';
import 'package:path/path.dart' as p;

import 'flac_builder.dart';

Track _t(String root, String rel,
    {String? album, int? trackNo, String artist = 'A', String? title}) {
  return Track(
    root: root,
    rel: rel,
    path: '/x/$rel',
    title: title ?? rel.split('/').last,
    artist: artist,
    album: album ?? 'Album',
    albumArtist: artist,
    trackNo: trackNo,
    durationMs: 1000,
    sampleRate: 44100,
    bitDepth: 16,
    channels: 2,
    size: 1,
    mtime: 1,
  );
}

void main() {
  group('LibraryIndex folders', () {
    final tracks = [
      _t('docs', 'loose.flac'),
      _t('docs', 'Pink Floyd/DSOTM/02 Breathe.flac', album: 'DSOTM', trackNo: 2),
      _t('docs', 'Pink Floyd/DSOTM/01 Speak.flac', album: 'DSOTM', trackNo: 1),
      _t('docs', 'Pink Floyd/Wall/CD1/01.flac', album: 'Wall', trackNo: 1),
      _t('docs', 'Adele/25/01 Hello.flac', album: '25', trackNo: 1),
      _t('/sdcard/Music', 'x/y.flac'),
    ];
    final index = LibraryIndex.build(tracks);

    test('root listing shows sub-folders and loose tracks', () {
      final l = index.listFolder('docs', '', rootName: 'On My iPhone');
      expect(l.name, 'On My iPhone');
      expect(l.isRoot, isTrue);
      expect(l.folders.map((f) => f.name), ['Adele', 'Pink Floyd']);
      expect(l.folders.map((f) => f.trackCount), [1, 3]);
      expect(l.tracks.map((t) => t.rel), ['loose.flac']);
    });

    test('nested listing and sorting by track number', () {
      final l = index.listFolder('docs', 'Pink Floyd/DSOTM');
      expect(l.name, 'DSOTM');
      expect(l.parentRelDir, 'Pink Floyd');
      expect(l.folders, isEmpty);
      expect(l.tracks.map((t) => t.trackNo), [1, 2]);

      final pf = index.listFolder('docs', '/Pink Floyd/');
      expect(pf.relDir, 'Pink Floyd');
      expect(pf.folders.map((f) => f.relDir), ['Pink Floyd/DSOTM', 'Pink Floyd/Wall']);
      expect(pf.tracks, isEmpty);
    });

    test('tracksUnder is recursive, depth-first, sorted', () {
      final all = index.tracksUnder('docs', 'Pink Floyd');
      expect(all.map((t) => t.rel), [
        'Pink Floyd/DSOTM/01 Speak.flac',
        'Pink Floyd/DSOTM/02 Breathe.flac',
        'Pink Floyd/Wall/CD1/01.flac',
      ]);
      expect(index.tracksUnder('docs', '').length, 5);
      expect(index.countUnder('docs', 'Pink Floyd'), 3);
      expect(index.tracksUnder('/sdcard/Music', '').length, 1);
    });

    test('unknown folder is empty', () {
      final l = index.listFolder('docs', 'Nope');
      expect(l.isEmpty, isTrue);
      expect(index.tracksUnder('nope', ''), isEmpty);
    });

    test('albums and artists are grouped', () {
      expect(index.albums.map((a) => a.title), containsAll(['DSOTM', 'Wall', '25']));
      final dsotm = index.albums.firstWhere((a) => a.title == 'DSOTM');
      expect(dsotm.tracks.map((t) => t.trackNo), [1, 2]);
      expect(index.artists.single.name, 'A');
      expect(index.byKey['docs|loose.flac'], isNotNull);
    });
  });

  group('helpers', () {
    test('formatLabel / formatKhz', () {
      expect(formatKhz(44100), '44.1');
      expect(formatKhz(96000), '96');
      expect(formatKhz(88200), '88.2');
      expect(_t('docs', 'a.flac').formatLabel, 'FLAC 16/44.1');
      final big = Track(
          root: 'docs', rel: 'b.flac', path: 'b', title: 'b', artist: 'a',
          album: 'x', albumArtist: 'a', durationMs: 200000, sampleRate: 44100,
          bitDepth: 16, channels: 2, size: 25000000, mtime: 0);
      expect(big.bitrateKbps, 1000);
    });

    test('placeholder colours are deterministic', () {
      expect(placeholderColorsFor('Abbey Road'), placeholderColorsFor('abbey road'));
      expect(placeholderColorsFor('Abbey Road') == placeholderColorsFor('Revolver'),
          isFalse);
    });

    test('track json round-trip resolves path from root', () {
      final t = _t('docs', 'A/b.flac', trackNo: 3);
      final back = Track.fromJson(t.toJson(), p.join('root'));
      expect(back.key, 'docs|A/b.flac');
      expect(back.trackNo, 3);
      expect(back.path, p.join('root', 'A', 'b.flac'));
    });
  });

  group('scanner + store (filesystem)', () {
    late Directory tmp;
    late Directory music;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('mu_flac_lib');
      music = Directory(p.join(tmp.path, 'Music'));
      await Directory(p.join(music.path, 'Artist', 'Album')).create(recursive: true);
      await Directory(p.join(music.path, '.hidden')).create();
      final tagged = FlacBuilder()
        ..sampleRate = 48000
        ..bitsPerSample = 24;
      tagged
        ..comment('TITLE', 'Song One')
        ..comment('ARTIST', 'Artist')
        ..comment('ALBUM', 'Album')
        ..comment('TRACKNUMBER', '1/2')
        ..picture(3, 'image/jpeg', [1, 2, 3]);
      await File(p.join(music.path, 'Artist', 'Album', '01.flac'))
          .writeAsBytes(tagged.build());
      await File(p.join(music.path, 'Artist', 'Album', 'untagged.FLAC'))
          .writeAsBytes(FlacBuilder().build());
      await File(p.join(music.path, 'Artist', 'Album', 'notes.txt')).writeAsString('x');
      await File(p.join(music.path, 'broken.flac')).writeAsBytes([1, 2, 3]);
      await File(p.join(music.path, '.hidden', 'h.flac'))
          .writeAsBytes(FlacBuilder().build());
      await File(p.join(music.path, 'Artist', '.Cloud Song.flac.icloud'))
          .writeAsString('placeholder');
      await AppPaths.init(
        docsOverride: Directory(p.join(tmp.path, 'docs')),
        supportOverride: Directory(p.join(tmp.path, 'support')),
      );
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('listFlacFiles finds flac, skips hidden, counts iCloud placeholders',
        () async {
      final l = await listFlacFiles(music.path);
      expect(l.readable, isTrue);
      expect(l.files.map((f) => f.rel).toSet(), {
        'Artist/Album/01.flac',
        'Artist/Album/untagged.FLAC',
        'broken.flac',
      });
      expect(l.notDownloaded, ['Artist/Cloud Song.flac']);
    });

    test('parse + fallbacks', () async {
      final l = await listFlacFiles(music.path);
      final parsed = await parseFlacFiles(music.path, l.files, AppPaths.art.path);
      final byRel = {for (final f in parsed) f.rel: f};
      expect(byRel['broken.flac']!.ok, isFalse);
      final tagged = trackFromParsed(
          rootId: 'r', rootPath: music.path,
          f: byRel['Artist/Album/01.flac']!, rootAlbumName: 'Music');
      expect(tagged.title, 'Song One');
      expect(tagged.formatLabel, 'FLAC 24/48');
      expect(tagged.trackNo, 1);
      expect(tagged.artHash, isNotNull);
      expect(File(tagged.artPath!).existsSync(), isTrue);
      final untagged = trackFromParsed(
          rootId: 'r', rootPath: music.path,
          f: byRel['Artist/Album/untagged.FLAC']!, rootAlbumName: 'Music');
      expect(untagged.title, 'untagged');
      expect(untagged.artist, kUnknownArtist);
      expect(untagged.album, 'Album');
      expect(untagged.hasTags, isFalse);
    });

    test('LibraryStore scans, rescans incrementally, removes roots', () async {
      final store = LibraryStore(isIOS: false, isAndroid: false);
      await store.init(scan: false);
      expect(store.tracks, isEmpty);
      final root = await store.addRootPath(music.path, scan: false);
      expect(root, isNotNull);
      expect(await store.addRootPath(p.join(music.path, 'Artist'), scan: false),
          isNull, reason: 'nested folder rejected');
      await store.rescan();
      expect(store.tracks.length, 2);
      expect(store.unreadableCount, 1);
      expect(store.notDownloadedCount, 1);
      expect(store.rootDisplayName(root!.id), 'Music');
      final listing = store.listFolder(root.id, '');
      expect(listing.folders.single.name, 'Artist');
      expect(store.tracksUnder(root.id, '').length, 2);

      // Reload from cache in a fresh store.
      final store2 = LibraryStore(isIOS: false, isAndroid: false);
      await store2.init(scan: false);
      expect(store2.tracks.length, 2);

      // Delete a file -> rescan drops it.
      await File(p.join(music.path, 'Artist', 'Album', 'untagged.FLAC')).delete();
      await store2.rescan();
      expect(store2.tracks.length, 1);
      expect(store2.tracks.single.title, 'Song One');

      await store2.removeRoot(root.id);
      expect(store2.tracks, isEmpty);
      expect(store2.roots, isEmpty);
    });
  });
}
