import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Thin wrapper over the `mu_flac/audio` MethodChannel and the
/// `mu_flac/audio_events` EventChannel (Kotlin: MainActivity.kt,
/// Swift: AppDelegate.swift). Every call is failure-tolerant: a missing
/// implementation (tests, unsupported platform) yields a neutral value.
class NativeAudio {
  NativeAudio._();

  static const MethodChannel _ch = MethodChannel('mu_flac/audio');
  static const EventChannel _events = EventChannel('mu_flac/audio_events');

  static Stream<String>? _eventStream;

  /// Native events: `outputChanged` (route / device change),
  /// `volumeChanged` (Android media volume changed).
  static Stream<String> get events => _eventStream ??= _events
      .receiveBroadcastStream()
      .map((e) => e is Map ? (e['event'] as String? ?? '') : '$e')
      .handleError((Object _) {})
      .asBroadcastStream();

  static bool get _mobile => Platform.isAndroid || Platform.isIOS;

  static Future<T?> _call<T>(String method, [Object? args]) async {
    if (!_mobile) return null;
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('NativeAudio.$method failed: ${e.code} ${e.message}');
      return null;
    }
  }

  // ---- Output / bit-perfect -------------------------------------------

  /// iOS: AVAudioSession.setPreferredSampleRate. Returns the hardware rate
  /// after the request (0 when unsupported).
  static Future<int> setPreferredSampleRate(int hz) async {
    if (!Platform.isIOS || hz <= 0) return 0;
    final r = await _call<num>('setPreferredSampleRate', {'sampleRate': hz});
    return r?.round() ?? 0;
  }

  static Future<OutputInfo> outputInfo() async {
    final m = await _call<Map<dynamic, dynamic>>('outputInfo');
    return OutputInfo.fromMap(m);
  }

  /// Android: heart state shown in the custom MU-FLAC notification.
  static Future<void> setNotificationFavorite(bool favorite) async {
    if (!Platform.isAndroid) return;
    await _call<void>('setNotificationFavorite', {'favorite': favorite});
  }

  /// Android API level (0 on iOS / unknown).
  static Future<int> androidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    return (await _call<int>('sdkInt')) ?? 0;
  }

  // ---- EQ (Android DynamicsProcessing) -----------------------------------

  static Future<bool> eqSupported() async =>
      Platform.isAndroid && ((await _call<bool>('eqSupported')) ?? false);

  /// Applies the whole EQ state in one call. With `enabled == false` or no
  /// session, native releases the effect (untouched signal path).
  static Future<bool> eqApply({
    required int sessionId,
    required bool enabled,
    required List<int> frequencies,
    required List<double> gains,
    double preampDb = 0,
  }) async {
    if (!Platform.isAndroid) return false;
    final ok = await _call<bool>('eqApply', {
      'sessionId': sessionId,
      'enabled': enabled,
      'frequencies': frequencies,
      'gains': gains,
      'preamp': preampDb,
    });
    return ok ?? false;
  }

  // ---- Volume (Android) ---------------------------------------------------

  /// Returns {value: 0..1, steps: max index} or null when unsupported.
  static Future<({double value, int steps})?> getVolume() async {
    if (!Platform.isAndroid) return null;
    final m = await _call<Map<dynamic, dynamic>>('getVolume');
    if (m == null) return null;
    return (
      value: (m['value'] as num?)?.toDouble() ?? 0,
      steps: (m['steps'] as num?)?.toInt() ?? 15,
    );
  }

  static Future<double?> setVolume(double value) async {
    if (!Platform.isAndroid) return null;
    final r = await _call<num>('setVolume', {'value': value.clamp(0.0, 1.0)});
    return r?.toDouble();
  }

  // ---- iOS folder bookmarks ------------------------------------------------

  /// Presents the Files folder picker. Returns null when cancelled.
  /// Result: {id, displayName, path, bookmark(base64)}.
  static Future<Map<String, dynamic>?> pickFolder() async {
    if (!Platform.isIOS) return null;
    final m = await _call<Map<dynamic, dynamic>>('pickFolder');
    return m?.cast<String, dynamic>();
  }

  /// Resolves stored bookmarks and starts security-scoped access for the app
  /// lifetime. Input: [{id, bookmark}]. Output per id:
  /// {ok, path, displayName, bookmark (refreshed if stale)}.
  static Future<Map<String, Map<String, dynamic>>> resolveFolders(
      List<Map<String, String>> items) async {
    if (!Platform.isIOS || items.isEmpty) return {};
    final m = await _call<Map<dynamic, dynamic>>(
        'resolveFolders', {'items': items});
    if (m == null) return {};
    return m.map((k, v) =>
        MapEntry(k as String, (v as Map).cast<String, dynamic>()));
  }

  static Future<void> releaseFolder(String id) async {
    if (!Platform.isIOS) return;
    await _call<void>('releaseFolder', {'id': id});
  }
}
