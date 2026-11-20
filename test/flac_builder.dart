import 'dart:convert';
import 'dart:typed_data';

/// Builds synthetic FLAC metadata (no audio frames) for tests.
class FlacBuilder {
  int sampleRate = 44100;
  int channels = 2;
  int bitsPerSample = 16;
  int totalSamples = 44100 * 180; // 3:00
  final Map<String, List<String>> comments = {};
  final List<({int type, String mime, Uint8List data})> pictures = [];
  int paddingBytes = 0;
  int id3Size = 0; // > 0 => prepend an ID3v2 tag with this payload size
  bool id3Footer = false;
  bool includeStreamInfo = true;

  void comment(String key, String value) =>
      (comments[key] ??= []).add(value);

  void picture(int type, String mime, List<int> data) =>
      pictures.add((type: type, mime: mime, data: Uint8List.fromList(data)));

  Uint8List build() {
    final blocks = <(int, Uint8List)>[];
    if (includeStreamInfo) blocks.add((0, _streamInfo()));
    if (paddingBytes > 0) blocks.add((1, Uint8List(paddingBytes)));
    if (comments.isNotEmpty) blocks.add((4, _vorbis()));
    for (final p in pictures) {
      blocks.add((6, _picture(p.type, p.mime, p.data)));
    }
    final out = BytesBuilder();
    if (id3Size > 0) {
      out.add([0x49, 0x44, 0x33, 4, 0, id3Footer ? 0x10 : 0]);
      out.add(_syncsafe(id3Size));
      out.add(Uint8List(id3Size));
      if (id3Footer) {
        out.add([0x33, 0x44, 0x49, 4, 0, 0x10]);
        out.add(_syncsafe(id3Size));
      }
    }
    out.add(ascii.encode('fLaC'));
    for (var i = 0; i < blocks.length; i++) {
      final (type, data) = blocks[i];
      final last = i == blocks.length - 1;
      out.addByte((last ? 0x80 : 0) | type);
      out.add([(data.length >> 16) & 0xFF, (data.length >> 8) & 0xFF, data.length & 0xFF]);
      out.add(data);
    }
    // A couple of fake frame bytes after metadata.
    out.add([0xFF, 0xF8, 0x00, 0x00]);
    return out.toBytes();
  }

  static List<int> _syncsafe(int n) =>
      [(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F];

  Uint8List _streamInfo() {
    final b = Uint8List(34);
    b[0] = 0x10; // min block 4096
    b[2] = 0x10; // max block 4096
    b[10] = (sampleRate >> 12) & 0xFF;
    b[11] = (sampleRate >> 4) & 0xFF;
    b[12] = ((sampleRate & 0x0F) << 4) |
        (((channels - 1) & 0x07) << 1) |
        (((bitsPerSample - 1) >> 4) & 0x01);
    final hi = totalSamples ~/ 4294967296;
    final lo = totalSamples % 4294967296;
    b[13] = (((bitsPerSample - 1) & 0x0F) << 4) | (hi & 0x0F);
    b[14] = (lo >> 24) & 0xFF;
    b[15] = (lo >> 16) & 0xFF;
    b[16] = (lo >> 8) & 0xFF;
    b[17] = lo & 0xFF;
    return b;
  }

  static List<int> _le32(int n) =>
      [n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF];
  static List<int> _be32(int n) =>
      [(n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];

  Uint8List _vorbis() {
    final out = BytesBuilder();
    final vendor = utf8.encode('test vendor');
    out.add(_le32(vendor.length));
    out.add(vendor);
    final entries = <List<int>>[];
    comments.forEach((k, vs) {
      for (final v in vs) {
        entries.add(utf8.encode('$k=$v'));
      }
    });
    out.add(_le32(entries.length));
    for (final e in entries) {
      out.add(_le32(e.length));
      out.add(e);
    }
    return out.toBytes();
  }

  Uint8List _picture(int type, String mime, Uint8List data) {
    final out = BytesBuilder();
    final m = ascii.encode(mime);
    final d = utf8.encode('cover');
    out.add(_be32(type));
    out.add(_be32(m.length));
    out.add(m);
    out.add(_be32(d.length));
    out.add(d);
    out.add(_be32(500)); // width
    out.add(_be32(500)); // height
    out.add(_be32(24)); // depth
    out.add(_be32(0)); // colors
    out.add(_be32(data.length));
    out.add(data);
    return out.toBytes();
  }
}
