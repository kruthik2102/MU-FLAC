import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_paths.dart';
import 'json_file.dart';
import 'native_audio.dart';

/// A named set of 10 band gains (dB).
class EqPreset {
  final String name;
  final List<double> gains;

  /// Built-in presets ("Flat") cannot be deleted/overwritten.
  final bool builtIn;

  const EqPreset(this.name, this.gains, {this.builtIn = false});

  Map<String, dynamic> toJson() => {'name': name, 'gains': gains};

  static EqPreset? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    final gains = j['gains'];
    if (name is! String || gains is! List || gains.length != EqController.bandCount) {
      return null;
    }
    return EqPreset(name,
        gains.map((g) => (g as num).toDouble().clamp(-12.0, 12.0)).toList());
  }
}

/// 10-band graphic EQ (31 Hz … 16 kHz, ±12 dB) with bypass and presets.
///
/// Android: native DynamicsProcessing pre-EQ (API 28+) attached to
/// just_audio's audio session. When disabled the effect is released, so the
/// signal path is untouched. iOS: [supported] is false for now (AVPlayer has
/// no EQ hook); the API still works and persists state.
class EqController extends ChangeNotifier {
  static const List<int> bandFrequencies = [
    31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
  ];
  static const int bandCount = 10;
  static const double minGain = -12;
  static const double maxGain = 12;
  static const String flatName = 'Flat';
  static const double minPreamp = -12;
  static const double maxPreamp = 0;
  static const double defaultPreamp = -3;

  static final EqPreset flat =
      EqPreset(flatName, List.filled(bandCount, 0.0), builtIn: true);

  JsonFile? _file;
  bool _supported = false;
  bool _enabled = false;
  List<double> _gains = List.filled(bandCount, 0.0);
  double _preamp = defaultPreamp;
  final List<EqPreset> _userPresets = [];
  int _sessionId = 0;

  // Coalesces rapid slider updates into at most one in-flight native call.
  bool _applying = false;
  bool _dirty = false;
  Timer? _saveTimer;

  /// Whether the platform can apply the EQ (Android 9+).
  bool get supported => _supported;

  /// EQ on/off. Off = bypass (no effect in the path).
  bool get enabled => _enabled;

  /// True when the EQ is actually changing the sound (on + supported).
  bool get active => _enabled && _supported;

  List<double> get gains => List.unmodifiable(_gains);

  /// Preamp in dB (-12..0, default -3): headroom applied before the bands
  /// while the EQ is on (Android: DynamicsProcessing input gain).
  double get preampDb => _preamp;

  /// Label for a band, e.g. "31", "1k", "16k".
  static String bandLabel(int i) {
    final f = bandFrequencies[i];
    return f >= 1000 ? '${f ~/ 1000}k' : '$f';
  }

  /// "Flat" first, then user presets in save order.
  List<EqPreset> get presets => [flat, ..._userPresets];

  /// Name of the preset matching the current gains, or null ("Custom").
  String? get currentPresetName {
    for (final p in presets) {
      if (_sameGains(p.gains, _gains)) return p.name;
    }
    return null;
  }

  static bool _sameGains(List<double> a, List<double> b) {
    for (var i = 0; i < bandCount; i++) {
      if ((a[i] - b[i]).abs() > 0.05) return false;
    }
    return true;
  }

  Future<void> init({String? path}) async {
    _file = JsonFile(path ?? AppPaths.supportFile('eq.json'));
    final j = await _file!.read();
    if (j is Map) {
      _enabled = j['enabled'] == true;
      final g = j['gains'];
      if (g is List && g.length == bandCount) {
        _gains = g.map((e) => (e as num).toDouble().clamp(minGain, maxGain)).toList();
      }
      final pre = j['preamp'];
      if (pre is num) {
        _preamp = pre.toDouble().clamp(minPreamp, maxPreamp);
      }
      final ps = j['presets'];
      if (ps is List) {
        for (final e in ps) {
          final p = EqPreset.fromJson(e);
          if (p != null && p.name != flatName) _userPresets.add(p);
        }
      }
    }
    try {
      _supported = Platform.isAndroid && await NativeAudio.eqSupported();
    } catch (_) {
      _supported = false;
    }
    notifyListeners();
  }

  /// Called with just_audio's Android audio session id (follows changes).
  void attachSession(int? sessionId) {
    final id = sessionId ?? 0;
    if (id == _sessionId) return;
    _sessionId = id;
    _apply();
  }

  Future<void> setEnabled(bool on) async {
    if (_enabled == on) return;
    _enabled = on;
    notifyListeners();
    _apply();
    _scheduleSave();
  }

  /// Sets one band (clamped to ±12 dB).
  void setGain(int band, double db) {
    if (band < 0 || band >= bandCount) return;
    final v = db.clamp(minGain, maxGain).toDouble();
    if (_gains[band] == v) return;
    _gains = List.of(_gains)..[band] = v;
    notifyListeners();
    _apply();
    _scheduleSave();
  }

  void setGains(List<double> gains) {
    if (gains.length != bandCount) return;
    _gains = gains.map((g) => g.clamp(minGain, maxGain).toDouble()).toList();
    notifyListeners();
    _apply();
    _scheduleSave();
  }

  /// Sets the preamp (clamped to -12..0 dB).
  void setPreamp(double db) {
    final v = db.clamp(minPreamp, maxPreamp).toDouble();
    if (v == _preamp) return;
    _preamp = v;
    notifyListeners();
    _apply();
    _scheduleSave();
  }

  /// All bands to 0 dB (preamp unchanged).
  void reset() => setGains(List.filled(bandCount, 0.0));

  void applyPreset(String name) {
    for (final p in presets) {
      if (p.name == name) {
        setGains(p.gains);
        return;
      }
    }
  }

  /// Saves the current gains as [name] (overwrites a user preset with the
  /// same name; "Flat" is reserved). Returns false if the name is invalid.
  Future<bool> savePreset(String name) async {
    final n = name.trim();
    if (n.isEmpty || n.toLowerCase() == flatName.toLowerCase()) return false;
    final i = _userPresets.indexWhere((p) => p.name.toLowerCase() == n.toLowerCase());
    final preset = EqPreset(n, List.of(_gains));
    if (i >= 0) {
      _userPresets[i] = preset;
    } else {
      _userPresets.add(preset);
    }
    notifyListeners();
    await _save();
    return true;
  }

  Future<void> deletePreset(String name) async {
    final before = _userPresets.length;
    _userPresets.removeWhere((p) => p.name == name);
    if (_userPresets.length != before) {
      notifyListeners();
      await _save();
    }
  }

  Future<void> _apply() async {
    if (!_supported) return;
    if (_applying) {
      _dirty = true;
      return;
    }
    _applying = true;
    try {
      do {
        _dirty = false;
        await NativeAudio.eqApply(
          sessionId: _sessionId,
          enabled: _enabled,
          frequencies: bandFrequencies,
          gains: _gains,
          preampDb: _preamp,
        );
      } while (_dirty);
    } finally {
      _applying = false;
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    _saveTimer?.cancel();
    await _file?.write({
      'enabled': _enabled,
      'gains': _gains,
      'preamp': _preamp,
      'presets': [for (final p in _userPresets) p.toJson()],
    });
  }
}

final EqController eqController = EqController();
