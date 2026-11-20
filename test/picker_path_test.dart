import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mu_flac/core/library_store.dart';
import 'package:mu_flac/core/playlist_store.dart';
import 'package:path/path.dart' as p;

void main() {
  group('fixPickerPath', () {
    test('collapses a doubled storage prefix (seen on HyperOS Download)', () {
      expect(LibraryStore.fixPickerPath('/storage/emulated/0/storage/emulated/0/Download'),
          '/storage/emulated/0/Download');
    });
    test('leaves normal paths alone', () {
      expect(LibraryStore.fixPickerPath('/storage/emulated/0/Download/Music'), '/storage/emulated/0/Download/Music');
      expect(LibraryStore.fixPickerPath('/storage/1A2B-3C4D/FLAC'), '/storage/1A2B-3C4D/FLAC');
    });
    test('keeps a real folder named storage deeper in the path', () {
      expect(LibraryStore.fixPickerPath('/storage/emulated/0/Backup/storage/x'), '/storage/emulated/0/Backup/storage/x');
    });
    test('trailing slash and dots are normalized', () {
      expect(LibraryStore.fixPickerPath('/storage/emulated/0/Music/./'), '/storage/emulated/0/Music');
    });
  });

  test('playlist keys follow merged roots', () async {
    final dir = await Directory.systemTemp.createTemp('muflac_pl');
    addTearDown(() => dir.delete(recursive: true));
    final store = PlaylistStore(resolver: (_) => null);
    await store.load(path: p.join(dir.path, 'playlists.json'));
    final pl = await store.create('Mix', trackKeys: ['/s/0/Download/Music|a.flac', '/s/0/Other|b.flac']);
    await store.toggleFavorite('/s/0/Download/Music|sub/c.flac');
    await store.remapKeyPrefixes({'/s/0/Download/Music|': '/s/0/Download|Music/'});
    expect(store.byId(pl.id)!.trackKeys, ['/s/0/Download|Music/a.flac', '/s/0/Other|b.flac']);
    expect(store.isFavorite('/s/0/Download|Music/sub/c.flac'), isTrue);
  });
}
