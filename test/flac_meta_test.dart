import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mu_flac/core/flac_meta.dart';

import 'flac_builder.dart';

FlacBuilder _full() {
  final b = FlacBuilder()
    ..sampleRate = 96000
    ..bitsPerSample = 24
    ..channels = 2
    ..totalSamples = 96000 * 245 + 48000 // 4:05.5
    ..paddingBytes = 128;
  b.comment('TITLE', 'Time');
  b.comment('artist', 'Pink Floyd'); // lower-case key
  b.comment('Album', 'The Dark Side of the Moon');
  b.comment('ALBUMARTIST', 'Pink Floyd');
  b.comment('TRACKNUMBER', '4/10');
  b.comment('DISCNUMBER', '1/1');
  b.comment('DATE', '1973-03-01');
  b.comment('GENRE', 'Rock');
  b.comment('GENRE', 'Progressive Rock');
  b.picture(4, 'image/jpeg', [9, 9, 9]); // back cover first
  b.picture(3, 'image/png', [1, 2, 3, 4, 5]); // front cover
  return b;
}

void main() {
  group('FlacParser', () {
    test('parses STREAMINFO, VORBIS_COMMENT and prefers front cover', () async {
      final meta = await FlacParser.parseBytes(_full().build());
      expect(meta, isNotNull);
      final m = meta!;
      expect(m.sampleRate, 96000);
      expect(m.bitsPerSample, 24);
      expect(m.channels, 2);
      expect(m.totalSamples, 96000 * 245 + 48000);
      expect(m.durationMs, 245500);
      expect(m.title, 'Time');
      expect(m.artist, 'Pink Floyd');
      expect(m.album, 'The Dark Side of the Moon');
      expect(m.albumArtist, 'Pink Floyd');
      expect(m.trackNumber, 4);
      expect(m.trackTotal, 10);
      expect(m.discNumber, 1);
      expect(m.year, 1973);
      expect(m.genre, 'Rock, Progressive Rock');
      expect(m.tagAll('genre'), ['Rock', 'Progressive Rock']);
      expect(m.vendor, 'test vendor');
      expect(m.picture, isNotNull);
      expect(m.picture!.type, 3);
      expect(m.picture!.mime, 'image/png');
      expect(m.picture!.data, [1, 2, 3, 4, 5]);
    });

    test('falls back to first picture when there is no front cover', () async {
      final b = FlacBuilder()..picture(0, 'image/jpeg', [7, 7]);
      final m = await FlacParser.parseBytes(b.build());
      expect(m!.picture!.type, 0);
      expect(m.picture!.data, [7, 7]);
    });

    test('readPicture: false skips art', () async {
      final m = await FlacParser.parseBytes(_full().build(), readPicture: false);
      expect(m!.picture, isNull);
      expect(m.title, 'Time');
    });

    test('skips a leading ID3v2 tag (with and without footer)', () async {
      for (final footer in [false, true]) {
        final b = _full()
          ..id3Size = 300
          ..id3Footer = footer;
        final m = await FlacParser.parseBytes(b.build());
        expect(m, isNotNull, reason: 'footer=$footer');
        expect(m!.sampleRate, 96000);
        expect(m.title, 'Time');
        expect(m.picture!.type, 3);
      }
    });

    test('handles CD-quality file without tags', () async {
      final m = await FlacParser.parseBytes(FlacBuilder().build());
      expect(m!.sampleRate, 44100);
      expect(m.bitsPerSample, 16);
      expect(m.durationMs, 180000);
      expect(m.title, isNull);
      expect(m.tags, isEmpty);
      expect(m.picture, isNull);
    });

    test('returns null for non-FLAC data', () async {
      expect(await FlacParser.parseBytes(Uint8List(0)), isNull);
      expect(await FlacParser.parseBytes(Uint8List.fromList([1, 2, 3])), isNull);
      expect(
          await FlacParser.parseBytes(
              Uint8List.fromList('OggS and some more bytes'.codeUnits)),
          isNull);
    });

    test('returns null when STREAMINFO is missing or truncated', () async {
      final noInfo = (FlacBuilder()
            ..includeStreamInfo = false
            ..comment('TITLE', 'x'))
          .build();
      expect(await FlacParser.parseBytes(noInfo), isNull);

      final full = _full().build();
      // "fLaC" + 4-byte header + 10 of 34 STREAMINFO bytes.
      expect(await FlacParser.parseBytes(Uint8List.sublistView(full, 0, 18)),
          isNull);
    });

    test('truncated after STREAMINFO yields partial metadata', () async {
      final full = _full().build();
      // Cut in the middle of the vorbis comment block.
      final cut = 4 + 4 + 34 + 4 + 128 + 30;
      final m = await FlacParser.parseBytes(Uint8List.sublistView(full, 0, cut));
      expect(m, isNotNull);
      expect(m!.sampleRate, 96000);
      expect(m.picture, isNull);
    });

    test('corrupt block length does not throw', () async {
      final bytes = Uint8List.fromList(_full().build());
      // Corrupt the vorbis comment count to a huge number.
      final vorbisStart = 4 + 4 + 34 + 4 + 128 + 4;
      final countOffset = vorbisStart + 4 + 'test vendor'.length;
      bytes[countOffset + 3] = 0x7F;
      final m = await FlacParser.parseBytes(bytes);
      expect(m, isNotNull);
      expect(m!.sampleRate, 96000);
      // Garbage everywhere after the marker.
      final junk = Uint8List.fromList(
          [0x66, 0x4C, 0x61, 0x43, ...List.generate(200, (i) => (i * 37) & 0xFF)]);
      expect(() => FlacParser.parseBytes(junk), returnsNormally);
    });

    test('parseFile reads from disk', () async {
      final dir = await Directory.systemTemp.createTemp('mu_flac_meta');
      try {
        final f = File('${dir.path}/a.flac');
        await f.writeAsBytes(_full().build());
        final m = await FlacParser.parseFile(f.path);
        expect(m!.title, 'Time');
        expect(m.picture!.data, [1, 2, 3, 4, 5]);
        expect(await FlacParser.parseFile('${dir.path}/missing.flac'), isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
