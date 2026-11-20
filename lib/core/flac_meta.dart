import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart FLAC metadata reader (no tag package).
///
/// Supports: optional leading ID3v2 tag(s), STREAMINFO, VORBIS_COMMENT and
/// PICTURE blocks. Other blocks (PADDING, SEEKTABLE, APPLICATION, CUESHEET)
/// are skipped without being read.
///
/// Never throws: returns `null` when the data is not a FLAC stream or the
/// STREAMINFO block is missing/truncated. Damage after STREAMINFO yields a
/// partial result (whatever was parsed before the damage).

/// An embedded picture (METADATA_BLOCK_PICTURE).
class FlacPicture {
  /// ID3v2 APIC picture type. 3 = front cover.
  final int type;
  final String mime;
  final String description;
  final int width;
  final int height;
  final Uint8List data;

  const FlacPicture({
    required this.type,
    required this.mime,
    required this.description,
    required this.width,
    required this.height,
    required this.data,
  });
}

/// Parsed metadata of one FLAC file.
class FlacMeta {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  /// Total inter-channel samples; 0 = unknown.
  final int totalSamples;

  /// Vorbis comments, keys upper-cased, values in file order.
  final Map<String, List<String>> tags;

  /// Chosen picture (front cover preferred), if any.
  final FlacPicture? picture;

  final String vendor;

  const FlacMeta({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.totalSamples,
    this.tags = const {},
    this.picture,
    this.vendor = '',
  });

  int get durationMs => (sampleRate <= 0 || totalSamples <= 0)
      ? 0
      : (totalSamples * 1000 ~/ sampleRate);

  /// First value of [key] (case-insensitive), trimmed; null if absent/empty.
  String? tag(String key) {
    final v = tags[key.toUpperCase()];
    if (v == null) return null;
    for (final s in v) {
      final t = s.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// All non-empty values of [key].
  List<String> tagAll(String key) => (tags[key.toUpperCase()] ?? const [])
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// Multi-values joined with ", " (e.g. several ARTIST entries).
  String? joined(String key) {
    final all = tagAll(key);
    return all.isEmpty ? null : all.join(', ');
  }

  String? get title => tag('TITLE');
  String? get artist => joined('ARTIST');
  String? get album => tag('ALBUM');
  String? get albumArtist =>
      joined('ALBUMARTIST') ?? joined('ALBUM ARTIST') ?? joined('ALBUM_ARTIST');
  String? get genre => joined('GENRE');
  String? get date => tag('DATE') ?? tag('YEAR');

  /// Track number from "3" or "3/12".
  int? get trackNumber => _leadingInt(tag('TRACKNUMBER'));
  int? get trackTotal =>
      _leadingInt(tag('TRACKTOTAL') ?? tag('TOTALTRACKS')) ??
      _afterSlash(tag('TRACKNUMBER'));
  int? get discNumber => _leadingInt(tag('DISCNUMBER'));
  int? get discTotal =>
      _leadingInt(tag('DISCTOTAL') ?? tag('TOTALDISCS')) ??
      _afterSlash(tag('DISCNUMBER'));

  /// 4-digit year found in DATE (e.g. "2019-05-01" -> 2019).
  int? get year {
    final d = date;
    if (d == null) return null;
    final m = RegExp(r'(\d{4})').firstMatch(d);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static int? _leadingInt(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^\s*(\d+)').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static int? _afterSlash(String? s) {
    if (s == null) return null;
    final m = RegExp(r'/\s*(\d+)').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(1)!);
  }
}

/// Abstract random-access byte source so the parser works on files and on
/// in-memory bytes (tests).
abstract class _Source {
  int get length;

  /// Reads up to [len] bytes at [offset]; may return fewer at EOF.
  Future<Uint8List> read(int offset, int len);
  Future<void> close() async {}
}

class _BytesSource extends _Source {
  final Uint8List bytes;
  _BytesSource(this.bytes);
  @override
  int get length => bytes.length;
  @override
  Future<Uint8List> read(int offset, int len) async {
    if (offset >= bytes.length || offset < 0) return Uint8List(0);
    final end = math.min(bytes.length, offset + len);
    return Uint8List.sublistView(bytes, offset, end);
  }
}

class _FileSource extends _Source {
  final RandomAccessFile raf;
  @override
  final int length;
  _FileSource(this.raf, this.length);
  @override
  Future<Uint8List> read(int offset, int len) async {
    if (offset >= length || offset < 0) return Uint8List(0);
    await raf.setPosition(offset);
    return raf.read(math.min(len, length - offset));
  }

  @override
  Future<void> close() => raf.close();
}

class FlacParser {
  FlacParser._();

  /// Pictures larger than this are ignored (protects memory).
  static const int maxPictureBytes = 24 * 1024 * 1024;

  /// Vorbis comment blocks larger than this are ignored.
  static const int maxCommentBytes = 4 * 1024 * 1024;

  static const int _blockStreamInfo = 0;
  static const int _blockVorbisComment = 4;
  static const int _blockPicture = 6;

  /// Parses an in-memory FLAC file (or its head).
  static Future<FlacMeta?> parseBytes(Uint8List bytes,
      {bool readPicture = true}) async {
    try {
      return await _parse(_BytesSource(bytes), readPicture: readPicture);
    } catch (_) {
      return null;
    }
  }

  /// Parses a FLAC file on disk, reading only the metadata blocks.
  static Future<FlacMeta?> parseFile(String path,
      {bool readPicture = true}) async {
    RandomAccessFile? raf;
    try {
      raf = await File(path).open();
      final len = await raf.length();
      final src = _FileSource(raf, len);
      return await _parse(src, readPicture: readPicture);
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  /// Returns the offset just past any leading ID3v2 tags.
  static Future<int> _skipId3(_Source src) async {
    var offset = 0;
    // Some files carry more than one ID3v2 tag back to back.
    for (var i = 0; i < 4; i++) {
      final h = await src.read(offset, 10);
      if (h.length < 10) return offset;
      if (h[0] != 0x49 || h[1] != 0x44 || h[2] != 0x33) return offset; // "ID3"
      // Syncsafe size: 4 x 7 bits.
      if ((h[6] | h[7] | h[8] | h[9]) & 0x80 != 0) return offset;
      final size = (h[6] << 21) | (h[7] << 14) | (h[8] << 7) | h[9];
      final hasFooter = (h[5] & 0x10) != 0;
      offset += 10 + size + (hasFooter ? 10 : 0);
    }
    return offset;
  }

  static bool _isMarker(Uint8List b, int i) =>
      i + 4 <= b.length &&
      b[i] == 0x66 && // f
      b[i + 1] == 0x4C && // L
      b[i + 2] == 0x61 && // a
      b[i + 3] == 0x43; // C

  /// Finds "fLaC" at [start], or (for files with junk/padding after an ID3
  /// tag) within the next 64 KiB. Returns -1 if absent.
  static Future<int> _findMarker(_Source src, int start) async {
    final head = await src.read(start, 4);
    if (_isMarker(head, 0)) return start;
    if (start == 0) return -1; // plain file must start with the marker
    final window = await src.read(start, 64 * 1024);
    for (var i = 0; i + 4 <= window.length; i++) {
      if (_isMarker(window, i)) return start + i;
    }
    return -1;
  }

  static Future<FlacMeta?> _parse(_Source src, {required bool readPicture}) async {
    final afterId3 = await _skipId3(src);
    final marker = await _findMarker(src, afterId3);
    if (marker < 0) return null;

    var pos = marker + 4;
    int? sampleRate;
    var channels = 0;
    var bps = 0;
    var totalSamples = 0;
    String vendor = '';
    final tags = <String, List<String>>{};
    FlacPicture? bestPicture;
    var first = true;

    for (var guard = 0; guard < 1024; guard++) {
      final hdr = await src.read(pos, 4);
      if (hdr.length < 4) break; // truncated
      final isLast = (hdr[0] & 0x80) != 0;
      final type = hdr[0] & 0x7F;
      final len = (hdr[1] << 16) | (hdr[2] << 8) | hdr[3];
      final dataStart = pos + 4;
      if (first && type != _blockStreamInfo) return null; // must be first
      first = false;
      if (type == 127) break; // invalid block type

      if (type == _blockStreamInfo) {
        if (len < 34) return null;
        final b = await src.read(dataStart, 34);
        if (b.length < 34) return null;
        sampleRate = (b[10] << 12) | (b[11] << 4) | (b[12] >> 4);
        channels = ((b[12] >> 1) & 0x07) + 1;
        bps = (((b[12] & 0x01) << 4) | (b[13] >> 4)) + 1;
        // 36-bit total samples; use multiplication to stay safe on web/JS.
        totalSamples = (b[13] & 0x0F) * 4294967296 +
            ((b[14] << 24) | (b[15] << 16) | (b[16] << 8) | b[17]);
        if (sampleRate == 0) return null;
      } else if (type == _blockVorbisComment) {
        if (len <= maxCommentBytes) {
          final b = await src.read(dataStart, len);
          vendor = _parseVorbis(b, tags) ?? vendor;
          if (b.length < len) break; // truncated inside the block
        }
      } else if (type == _blockPicture && readPicture) {
        if (len <= maxPictureBytes + 4096) {
          final b = await src.read(dataStart, len);
          final pic = _parsePicture(b);
          if (pic != null) {
            if (bestPicture == null ||
                (pic.type == 3 && bestPicture.type != 3)) {
              bestPicture = pic;
            }
          }
          if (b.length < len) break;
        }
      }

      pos = dataStart + len;
      if (isLast) break;
      if (pos > src.length) break;
    }

    if (sampleRate == null) return null;
    return FlacMeta(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bps,
      totalSamples: totalSamples,
      tags: tags,
      picture: bestPicture,
      vendor: vendor,
    );
  }

  static int _le32(Uint8List b, int i) =>
      b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

  static int _be32(Uint8List b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

  /// Parses a VORBIS_COMMENT body into [out]. Returns the vendor string.
  /// Stops quietly at the first inconsistency (keeps what was read).
  static String? _parseVorbis(Uint8List b, Map<String, List<String>> out) {
    var i = 0;
    if (b.length < 4) return null;
    final vendorLen = _le32(b, 0);
    i = 4;
    if (vendorLen < 0 || i + vendorLen > b.length) return null;
    final vendor = utf8.decode(
        Uint8List.sublistView(b, i, i + vendorLen),
        allowMalformed: true);
    i += vendorLen;
    if (i + 4 > b.length) return vendor;
    final count = _le32(b, i);
    i += 4;
    for (var n = 0; n < count; n++) {
      if (i + 4 > b.length) break;
      final l = _le32(b, i);
      i += 4;
      if (l < 0 || i + l > b.length) break;
      final s = utf8.decode(Uint8List.sublistView(b, i, i + l),
          allowMalformed: true);
      i += l;
      final eq = s.indexOf('=');
      if (eq <= 0) continue;
      final key = s.substring(0, eq).trim().toUpperCase();
      final value = s.substring(eq + 1);
      (out[key] ??= <String>[]).add(value);
    }
    return vendor;
  }

  static FlacPicture? _parsePicture(Uint8List b) {
    var i = 0;
    bool need(int n) => i + n <= b.length;
    if (!need(8)) return null;
    final type = _be32(b, i);
    i += 4;
    final mimeLen = _be32(b, i);
    i += 4;
    if (mimeLen < 0 || !need(mimeLen)) return null;
    final mime = latin1.decode(Uint8List.sublistView(b, i, i + mimeLen),
        allowInvalid: true);
    i += mimeLen;
    if (!need(4)) return null;
    final descLen = _be32(b, i);
    i += 4;
    if (descLen < 0 || !need(descLen)) return null;
    final desc = utf8.decode(Uint8List.sublistView(b, i, i + descLen),
        allowMalformed: true);
    i += descLen;
    if (!need(20)) return null;
    final width = _be32(b, i);
    final height = _be32(b, i + 4);
    // depth (4) + colors (4) skipped
    i += 16;
    final dataLen = _be32(b, i);
    i += 4;
    if (dataLen <= 0 || dataLen > maxPictureBytes || !need(dataLen)) {
      return null;
    }
    if (mime == '-->') return null; // URL reference: never fetched (offline)
    final data = Uint8List.fromList(Uint8List.sublistView(b, i, i + dataLen));
    return FlacPicture(
      type: type,
      mime: mime,
      description: desc,
      width: width,
      height: height,
      data: data,
    );
  }
}
