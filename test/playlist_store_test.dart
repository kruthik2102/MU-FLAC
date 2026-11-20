import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show ShuffleOrder;
import 'package:mu_flac/core/eq_controller.dart';
import 'package:mu_flac/core/models.dart';
import 'package:mu_flac/core/player_controller.dart' show QueueShuffleOrder;
import 'package:mu_flac/core/playlist_store.dart';
import 'package:path/path.dart' as p;

Track _t(String rel) => Track(
      root: 'docs',
      rel: rel,
      path: rel,
      title: rel,
      artist: 'A',
      album: 'B',
      albumArtist: 'A',
      durationMs: 1,
      sampleRate: 44100,
      bitDepth: 16,
      channels: 2,
      size: 1,
      mtime: 1,
    );

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('mu_flac_pl'));
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('PlaylistStore', () {
    final library = {for (final r in ['a', 'b', 'c', 'd']) 'docs|$r': _t(r)};
    PlaylistStore make() => PlaylistStore(resolver: (k) => library[k]);

    test('favorites always exists first and cannot be deleted/renamed', () async {
      final s = make();
      await s.load(path: p.join(tmp.path, 'pl.json'));
      expect(s.playlists.single.id, kFavoritesId);
      await s.create('Road trip');
      expect(s.playlists.first.id, kFavoritesId);
      await s.delete(kFavoritesId);
      await s.rename(kFavoritesId, 'Nope');
      expect(s.favorites.name, 'Favorites');
      expect(s.playlists.length, 2);
    });

    test('toggleFavorite / isFavorite', () async {
      final s = make();
      await s.load(path: p.join(tmp.path, 'pl.json'));
      expect(s.isFavorite('docs|a'), isFalse);
      expect(await s.toggleFavorite('docs|a'), isTrue);
      expect(await s.toggleFavorite('docs|b'), isTrue);
      expect(s.isFavorite('docs|a'), isTrue);
      expect(s.favorites.trackKeys, ['docs|b', 'docs|a']);
      expect(await s.toggleFavorite('docs|a'), isFalse);
      expect(s.isFavorite('docs|a'), isFalse);
    });

    test('create, add, remove, reorder, rename, delete + persistence', () async {
      final path = p.join(tmp.path, 'pl.json');
      final s = make();
      await s.load(path: path);
      final pl = await s.create('  Mix  ');
      expect(pl.name, 'Mix');
      expect(await s.addTracks(pl.id, ['docs|a', 'docs|b', 'docs|c']), 3);
      expect(await s.addTracks(pl.id, ['docs|a'], skipDuplicates: true), 0);
      await s.move(pl.id, 0, 2); // a b c -> b c a
      expect(s.byId(pl.id)!.trackKeys, ['docs|b', 'docs|c', 'docs|a']);
      await s.removeAt(pl.id, 1); // -> b a
      expect(s.byId(pl.id)!.trackKeys, ['docs|b', 'docs|a']);
      await s.addTracks(pl.id, ['docs|missing', 'docs|d']);
      expect(s.tracksOf(pl.id).map((t) => t.rel), ['b', 'a', 'd']);
      expect(s.entriesOf(pl.id).map((e) => e.index), [0, 1, 3]);
      await s.rename(pl.id, 'Evening');
      await s.toggleFavorite('docs|c');

      final s2 = make();
      await s2.load(path: path);
      expect(s2.byId(pl.id)!.name, 'Evening');
      expect(s2.byId(pl.id)!.trackKeys,
          ['docs|b', 'docs|a', 'docs|missing', 'docs|d']);
      expect(s2.isFavorite('docs|c'), isTrue);
      await s2.delete(pl.id);
      expect(s2.byId(pl.id), isNull);
    });
  });

  group('QueueShuffleOrder', () {
    test('insertAt places new items after the current position', () {
      final ShuffleOrder o = QueueShuffleOrder();
      o.insert(0, 5); // [0,1,2,3,4]
      expect(o.indices, [0, 1, 2, 3, 4]);
      (o as QueueShuffleOrder).insertAt = 1;
      o.insert(1, 2); // new seq items 1,2 ; old 1..4 -> 3..6
      expect(o.indices, [0, 1, 2, 3, 4, 5, 6]);
      o.insertAt = 0;
      o.insert(7, 1);
      expect(o.indices, [7, 0, 1, 2, 3, 4, 5, 6]);
      o.removeRange(0, 1); // remove seq 0, shift down
      expect(o.indices, [6, 0, 1, 2, 3, 4, 5]);
    });

    test('shuffle keeps initial index first and is a permutation', () {
      final o = QueueShuffleOrder()..insert(0, 20);
      o.shuffle(initialIndex: 7);
      expect(o.indices.first, 7);
      expect(o.indices.toSet().length, 20);
    });

    test('self-move with insertAt reorders only the shuffle order', () {
      final o = QueueShuffleOrder()..insert(0, 4);
      o.indices
        ..clear()
        ..addAll([2, 0, 3, 1]);
      // Move queue position 0 (seq 2) to position 2, as moveInQueue does.
      o.removeRange(2, 3);
      o.insertAt = 2;
      o.insert(2, 1);
      expect(o.indices, [0, 3, 2, 1]);
    });
  });

  group('EqController (no native)', () {
    test('gains clamp, presets save/apply/delete, persistence', () async {
      final path = p.join(tmp.path, 'eq.json');
      final eq = EqController();
      await eq.init(path: path);
      expect(eq.supported, isFalse); // not Android in tests
      expect(eq.presets.first.name, 'Flat');
      expect(eq.currentPresetName, 'Flat');
      eq.setGain(0, 20);
      eq.setGain(9, -3.5);
      expect(eq.gains.first, 12);
      expect(eq.currentPresetName, isNull);
      expect(await eq.savePreset('flat'), isFalse);
      expect(await eq.savePreset('Bass'), isTrue);
      expect(eq.currentPresetName, 'Bass');
      eq.reset();
      expect(eq.currentPresetName, 'Flat');
      eq.applyPreset('Bass');
      expect(eq.gains[9], -3.5);
      await eq.setEnabled(true);
      expect(eq.active, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 600));

      final eq2 = EqController();
      await eq2.init(path: path);
      expect(eq2.enabled, isTrue);
      expect(eq2.gains.first, 12);
      expect(eq2.presets.map((p) => p.name), ['Flat', 'Bass']);
      await eq2.deletePreset('Bass');
      expect(eq2.presets.length, 1);
      expect(EqController.bandLabel(5), '1k');
      expect(eq2.preampDb, -3);
      eq2.setPreamp(5);
      expect(eq2.preampDb, 0);
      eq2.setPreamp(-20);
      expect(eq2.preampDb, -12);
    });
  });
}
