import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'native_audio.dart';

/// System media volume. Android: real get/set via the native channel.
/// iOS: [supported] is false (apps cannot set system volume; the UI should
/// hide the slider or show a "use the volume buttons" hint).
class VolumeController extends ChangeNotifier {
  bool _supported = false;
  double _value = 0;
  int _steps = 15;
  StreamSubscription<String>? _sub;

  bool get supported => _supported;

  /// 0..1.
  double get value => _value;

  /// Number of hardware volume steps (Android STREAM_MUSIC max index).
  int get steps => _steps;

  Future<void> init() async {
    if (!Platform.isAndroid) {
      _supported = false;
      return;
    }
    await refresh();
    _sub ??= NativeAudio.events.listen((e) {
      if (e == 'volumeChanged') refresh();
    });
  }

  /// Re-reads the system volume (e.g. when the volume UI becomes visible).
  Future<void> refresh() async {
    final v = await NativeAudio.getVolume();
    if (v == null) {
      if (_supported) {
        _supported = false;
        notifyListeners();
      }
      return;
    }
    final changed = !_supported || v.value != _value || v.steps != _steps;
    _supported = true;
    _value = v.value;
    _steps = v.steps;
    if (changed) notifyListeners();
  }

  /// Sets the system media volume (0..1, snapped to hardware steps).
  Future<void> setVolume(double value) async {
    if (!_supported) return;
    _value = value.clamp(0.0, 1.0);
    notifyListeners();
    final actual = await NativeAudio.setVolume(_value);
    if (actual != null && actual != _value) {
      _value = actual;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final VolumeController volumeController = VolumeController();
