import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Well-known app directories. Call [AppPaths.init] once at startup (done by
/// `bootstrap()`).
///
/// iOS container paths change between installs/updates, so never persist an
/// absolute path that points inside them: persist ids/hashes and resolve the
/// path at runtime through this class.
class AppPaths {
  AppPaths._();

  static Directory? _docs;
  static Directory? _support;
  static Directory? _art;

  /// The app's Documents directory. On iOS this is the folder visible in the
  /// Files app ("On My iPhone > MU-FLAC") and in Finder / Apple Devices file
  /// sharing. Root id `docs` resolves here.
  static Directory get docs => _docs!;

  /// Private app support dir (library cache, playlists, settings, art cache).
  static Directory get support => _support!;

  /// Album art cache: `<support>/art/<hash>.img`.
  static Directory get art => _art!;

  static bool get isInitialized => _support != null;

  /// Resolves directories. [docsOverride]/[supportOverride] are for tests.
  static Future<void> init({
    Directory? docsOverride,
    Directory? supportOverride,
  }) async {
    _docs = docsOverride ?? await getApplicationDocumentsDirectory();
    _support = supportOverride ?? await getApplicationSupportDirectory();
    _art = Directory(p.join(_support!.path, 'art'));
    await _docs!.create(recursive: true);
    await _support!.create(recursive: true);
    await _art!.create(recursive: true);
  }

  /// Path of the cached art image for [hash].
  static String artFile(String hash) => p.join(art.path, '$hash.img');

  /// Path of a JSON/data file inside the support dir.
  static String supportFile(String name) => p.join(support.path, name);
}
