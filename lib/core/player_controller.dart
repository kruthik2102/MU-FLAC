import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

import 'eq_controller.dart';
import 'library_store.dart';
import 'models.dart';
import 'native_audio.dart';
import 'playlist_store.dart';
import 'settings_store.dart';

/// Shuffle order we control, so "Play next" lands right after the current
/// item and "Add to queue" lands at the end even while shuffled, and queue
/// reordering works in shuffled view.
class QueueShuffleOrder extends ShuffleOrder {
  QueueShuffleOrder({Random? random}) : _random = random ?? Random();

  final Random _random;

  @override
  final List<int> indices = <int>[];

  /// Position in [indices] where the next [insert] places new items
  /// (consumed by that insert). Null = append at the end.
  int? insertAt;

  @override
  void shuffle({int? initialIndex}) {
    if (indices.length <= 1) return;
    indices.shuffle(_random);
    if (initialIndex == null) return;
    final swapPos = indices.indexOf(initialIndex);
    if (swapPos < 0) return;
    indices[swapPos] = indices[0];
    indices[0] = initialIndex;
  }

  @override
  void insert(int index, int count) {
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) indices[i] += count;
    }
    final at = (insertAt ?? indices.length).clamp(0, indices.length);
    insertAt = null;
    indices.insertAll(at, List.generate(count, (i) => index + i));
  }

  @override
  void removeRange(int start, int end) {
    final count = end - start;
    indices.removeWhere((i) => i >= start && i < end);
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= end) indices[i] -= count;
    }
  }

  @override
  void clear() {
    indices.clear();
    insertAt = null;
  }
}

/// Playback: wraps a single just_audio [AudioPlayer] (with
/// just_audio_background for lock screen / notification / headset buttons).
///
/// "Queue positions" used by this API are positions in the play order the
/// user sees ([queue]), which equals the shuffled order while shuffle is on.
class PlayerController {
  AudioPlayer? _player;

  /// The underlying player (for advanced UI needs). Valid after [init].
  AudioPlayer get player => _player!;

  final ValueNotifier<Track?> _current = ValueNotifier(null);
  final ValueNotifier<List<Track>> _queue = ValueNotifier(const []);
  final ValueNotifier<int> _queueIndex = ValueNotifier(-1);
  final ValueNotifier<bool> _playing = ValueNotifier(false);
  final ValueNotifier<Duration> _duration = ValueNotifier(Duration.zero);
  final ValueNotifier<RepeatMode> _repeat = ValueNotifier(RepeatMode.off);
  final ValueNotifier<bool> _shuffle = ValueNotifier(false);
  final ValueNotifier<OutputInfo> _output = ValueNotifier(OutputInfo.unknown);
  final ValueNotifier<bool> _matched = ValueNotifier(false);
  final ValueNotifier<bool> _buffering = ValueNotifier(false);
  final ValueNotifier<bool> _completed = ValueNotifier(false);

  /// Currently playing/paused track (null = nothing loaded).
  ValueListenable<Track?> get current => _current;

  /// Tracks in play order (shuffled order while shuffle is on).
  ValueListenable<List<Track>> get queue => _queue;

  /// Position of [current] inside [queue] (-1 = none).
  ValueListenable<int> get queueIndex => _queueIndex;

  ValueListenable<bool> get playing => _playing;
  ValueListenable<Duration> get duration => _duration;
  ValueListenable<RepeatMode> get repeat => _repeat;
  ValueListenable<bool> get shuffle => _shuffle;

  /// Where audio goes now: device name, kind, hardware sample rate.
  ValueListenable<OutputInfo> get output => _output;

  /// True when hardware rate == track rate and EQ is off (bit-perfect path
  /// as far as the OS lets us know).
  ValueListenable<bool> get matched => _matched;

  ValueListenable<bool> get buffering => _buffering;

  /// True when the queue played to the end (repeat off).
  ValueListenable<bool> get completed => _completed;

  /// Playback position (emits frequently while playing).
  Stream<Duration> get positionStream =>
      _player?.positionStream ?? const Stream<Duration>.empty();
  Duration get position => _player?.position ?? Duration.zero;

  /// Buffered position (local files buffer quickly; mostly for seek bars).
  Stream<Duration> get bufferedPositionStream =>
      _player?.bufferedPositionStream ?? const Stream<Duration>.empty();

  bool get hasQueue => _queue.value.isNotEmpty;

  QueueShuffleOrder _order = QueueShuffleOrder();
  final Map<String, Track> _byUid = {};
  int _uidCounter = 0;
  String? _currentUid;
  Future<void> _lock = Future.value();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _saveTimer;

  static const _kResume = 'player.resume';
  static const _kRepeat = 'player.repeat';

  /// Creates the player. Call after `JustAudioBackground.init` and after the
  /// library is loaded (to restore the last queue).
  Future<void> init({bool restore = true}) async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      debugPrint('AudioSession configure failed: $e');
    }

    final p = _player = AudioPlayer(
      useProxyForRequestHeaders: false, // local files only, no HTTP proxy
      maxSkipsOnError: 3,
    );

    _subs.add(p.sequenceStateStream.listen(_onSequenceState));
    _subs.add(p.playingStream.listen((v) {
      _playing.value = v;
      if (!v) _saveResume();
    }));
    _subs.add(p.durationStream.listen((d) {
      _duration.value = d ?? _current.value?.duration ?? Duration.zero;
    }));
    _subs.add(p.processingStateStream.listen((s) {
      _buffering.value =
          s == ProcessingState.loading || s == ProcessingState.buffering;
      _completed.value = s == ProcessingState.completed;
    }));
    _subs.add(p.errorStream.listen((e) {
      debugPrint('Playback error: ${e.code} ${e.message}');
    }));
    _subs.add(p.androidAudioSessionIdStream.listen(eqController.attachSession));
    _subs.add(NativeAudio.events.listen((e) {
      if (e == 'outputChanged') _onOutputChanged();
      if (e == 'favoriteToggle') {
        final t = _current.value;
        if (t != null) playlistStore.toggleFavorite(t.key);
      }
    }));
    // Keep the notification's heart in sync with Favorites.
    _current.addListener(_syncNotificationFavorite);
    playlistStore.addListener(_syncNotificationFavorite);
    eqController.addListener(_recomputeMatched);

    final savedRepeat = settingsStore.get<String>(_kRepeat);
    final rm = RepeatMode.values
        .firstWhere((m) => m.name == savedRepeat, orElse: () => RepeatMode.off);
    _repeat.value = rm;
    await p.setLoopMode(_loopFor(rm));

    unawaited(refreshOutput());
    if (restore) await _restoreResume();

    // Persist position periodically while playing.
    _subs.add(Stream.periodic(const Duration(seconds: 15)).listen((_) {
      if (_playing.value) _saveResume();
    }));
  }

  // ---------------------------------------------------------------------
  // Queue building
  // ---------------------------------------------------------------------

  Future<T> _run<T>(Future<T> Function() op) {
    final c = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        c.complete(await op());
      } catch (e, st) {
        debugPrint('Player op failed: $e');
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  bool? _lastNotifFav;
  void _syncNotificationFavorite() {
    final t = _current.value;
    final fav = t != null && playlistStore.isFavorite(t.key);
    if (fav == _lastNotifFav) return;
    _lastNotifFav = fav;
    unawaited(NativeAudio.setNotificationFavorite(fav));
  }

  AudioSource _source(Track t) {
    final uid = '${t.key}#${_uidCounter++}';
    _byUid[uid] = t;
    return AudioSource.file(
      t.path,
      tag: MediaItem(
        id: uid,
        title: t.title,
        artist: t.artist,
        album: t.album,
        genre: t.genre,
        duration: t.durationMs > 0 ? t.duration : null,
        artUri: t.artUri,
        // Shown by the custom Android notification: title / artist / format pill.
        displayTitle: t.title,
        displaySubtitle: t.artist,
        displayDescription: t.formatLabel,
        extras: {'key': t.key, 'format': t.formatLabel},
      ),
    );
  }

  Track? _trackOf(IndexedAudioSource s) {
    final tag = s.tag;
    if (tag is MediaItem) return _byUid[tag.id];
    return null;
  }

  String? _uidOf(IndexedAudioSource? s) {
    final tag = s?.tag;
    return tag is MediaItem ? tag.id : null;
  }

  /// Replaces the queue with [tracks] and starts playing at [index].
  /// With [shuffle], play order is shuffled (starting from [index], or a
  /// random track when [index] is null).
  /// Android 13+: the custom notification needs POST_NOTIFICATIONS.
  /// Asked once, the first time something is played.
  Future<void> _askNotificationPermissionOnce() async {
    if (!Platform.isAndroid || settingsStore.get<bool>(_kAskedNotif) == true) return;
    await settingsStore.set(_kAskedNotif, true);
    try {
      if (await NativeAudio.androidSdkInt() >= 33) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
  }

  static const _kAskedNotif = 'askedNotificationPermission';

  Future<void> playTracks(List<Track> tracks,
      {int? index, bool shuffle = false, bool autoPlay = true}) {
    if (tracks.isEmpty) return Future.value();
    unawaited(_askNotificationPermissionOnce());
    return _run(() async {
      final p = player;
      _byUid.clear();
      final sources = [for (final t in tracks) _source(t)];
      final start = (index ??
              (shuffle ? Random().nextInt(tracks.length) : 0))
          .clamp(0, tracks.length - 1);
      _order = QueueShuffleOrder();
      // Prime the hardware rate before the first buffer is rendered (iOS).
      unawaited(_applySampleRate(tracks[start]));
      await p.setAudioSources(sources,
          initialIndex: start,
          initialPosition: Duration.zero,
          shuffleOrder: _order);
      if (shuffle) await p.shuffle();
      await p.setShuffleModeEnabled(shuffle);
      if (autoPlay) unawaited(p.play());
    });
  }

  /// Inserts [tracks] right after the current track (in play order).
  Future<void> playNext(List<Track> tracks) {
    if (tracks.isEmpty) return Future.value();
    if (!hasQueue) return playTracks(tracks);
    return _run(() async {
      final p = player;
      final ci = p.currentIndex ?? -1;
      final seqIdx = (ci + 1).clamp(0, p.sequence.length);
      if (p.shuffleModeEnabled && ci >= 0) {
        _order.insertAt = p.shuffleIndices.indexOf(ci) + 1;
      } else {
        _order.insertAt = null;
      }
      await p.insertAudioSources(seqIdx, [for (final t in tracks) _source(t)]);
    });
  }

  /// Appends [tracks] to the end of the queue (in play order). Starts
  /// playback when nothing is queued.
  Future<void> addToQueue(List<Track> tracks) {
    if (tracks.isEmpty) return Future.value();
    if (!hasQueue) return playTracks(tracks);
    return _run(() async {
      _order.insertAt = null;
      await player.addAudioSources([for (final t in tracks) _source(t)]);
    });
  }

  /// Removes the item at queue position [queuePos].
  Future<void> removeFromQueue(int queuePos) => _run(() async {
        final p = player;
        final eff = p.effectiveIndices;
        if (queuePos < 0 || queuePos >= eff.length) return;
        final seqIdx = eff[queuePos];
        final uid = _uidOf(p.sequence[seqIdx]);
        await p.removeAudioSourceAt(seqIdx);
        if (uid != null) _byUid.remove(uid);
      });

  /// Moves the queue item at [from] to [to] (final positions, like
  /// `list.insert(to, list.removeAt(from))`).
  Future<void> moveInQueue(int from, int to) => _run(() async {
        final p = player;
        final n = p.sequence.length;
        if (from < 0 || from >= n || to < 0 || to >= n || from == to) return;
        if (p.shuffleModeEnabled) {
          // Reorder only the shuffle order: move sequence item s onto itself
          // while our order re-inserts it at position `to`.
          final s = p.shuffleIndices[from];
          _order.insertAt = to;
          await p.moveAudioSource(s, s);
        } else {
          _order.insertAt = null;
          await p.moveAudioSource(from, to);
        }
      });

  /// Jumps to queue position [queuePos] and plays.
  Future<void> jumpTo(int queuePos) => _run(() async {
        final p = player;
        final eff = p.effectiveIndices;
        if (queuePos < 0 || queuePos >= eff.length) return;
        await p.seek(Duration.zero, index: eff[queuePos]);
        if (!p.playing) unawaited(p.play());
      });

  /// Empties the queue and stops.
  Future<void> clearQueue() => _run(() async {
        await player.stop();
        await player.clearAudioSources();
        _byUid.clear();
        await settingsStore.remove(_kResume);
      });

  // ---------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------

  Future<void> play() async {
    final p = player;
    if (p.processingState == ProcessingState.completed) {
      final eff = p.effectiveIndices;
      if (eff.isNotEmpty) await p.seek(Duration.zero, index: eff.first);
    }
    unawaited(p.play());
  }

  Future<void> pause() => player.pause();

  Future<void> togglePlay() async {
    if (player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> next() async {
    if (player.hasNext) await player.seekToNext();
  }

  /// Restarts the track if more than 3 s in (or no previous), else goes to
  /// the previous track.
  Future<void> previous() async {
    final p = player;
    if (p.position > const Duration(seconds: 3) || !p.hasPrevious) {
      await p.seek(Duration.zero);
    } else {
      await p.seekToPrevious();
    }
  }

  Future<void> seek(Duration position) => player.seek(position);

  /// off -> all -> one -> off.
  Future<void> cycleRepeat() {
    final next = RepeatMode.values[(_repeat.value.index + 1) % 3];
    return setRepeat(next);
  }

  Future<void> setRepeat(RepeatMode mode) async {
    _repeat.value = mode;
    await player.setLoopMode(_loopFor(mode));
    await settingsStore.set(_kRepeat, mode.name);
  }

  static LoopMode _loopFor(RepeatMode m) => switch (m) {
        RepeatMode.off => LoopMode.off,
        RepeatMode.all => LoopMode.all,
        RepeatMode.one => LoopMode.one,
      };

  /// Turning shuffle on reshuffles with the current track first; turning it
  /// off returns to the original order.
  Future<void> toggleShuffle() => setShuffle(!player.shuffleModeEnabled);

  Future<void> setShuffle(bool on) => _run(() async {
        final p = player;
        if (on && p.sequence.isNotEmpty) await p.shuffle();
        await p.setShuffleModeEnabled(on);
      });

  // ---------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------

  void _onSequenceState(SequenceState s) {
    final seq = s.sequence;
    final eff = s.shuffleModeEnabled && s.shuffleIndices.length == seq.length
        ? s.shuffleIndices
        : List<int>.generate(seq.length, (i) => i);
    final q = <Track>[];
    var qi = -1;
    for (var pos = 0; pos < eff.length; pos++) {
      final idx = eff[pos];
      if (idx < 0 || idx >= seq.length) continue;
      final t = _trackOf(seq[idx]);
      if (t == null) continue;
      if (idx == s.currentIndex) qi = q.length;
      q.add(t);
    }
    _queue.value = List.unmodifiable(q);
    _queueIndex.value = qi;
    _shuffle.value = s.shuffleModeEnabled;

    final cur = s.currentSource;
    final uid = _uidOf(cur);
    final track = cur == null ? null : _trackOf(cur);
    if (uid != _currentUid) {
      _currentUid = uid;
      _current.value = track;
      _duration.value = player.duration ?? track?.duration ?? Duration.zero;
      if (track != null) {
        unawaited(_applySampleRate(track).then((_) => refreshOutput()));
      } else {
        _recomputeMatched();
      }
      _saveResume();
    }
  }

  Future<void> _applySampleRate(Track t) async {
    if (!Platform.isIOS || t.sampleRate <= 0) return;
    await NativeAudio.setPreferredSampleRate(t.sampleRate);
  }

  void _onOutputChanged() {
    final t = _current.value;
    if (t != null) {
      unawaited(_applySampleRate(t).then((_) => refreshOutput()));
    } else {
      unawaited(refreshOutput());
    }
  }

  /// Re-queries the native output route + hardware sample rate.
  Future<OutputInfo> refreshOutput() async {
    final info = await NativeAudio.outputInfo();
    _output.value = info;
    _recomputeMatched();
    // The hardware may switch rate a moment after the request (USB DACs).
    if (Platform.isIOS && _current.value != null &&
        info.sampleRate != _current.value!.sampleRate) {
      Future.delayed(const Duration(milliseconds: 600), () async {
        final again = await NativeAudio.outputInfo();
        _output.value = again;
        _recomputeMatched();
      });
    }
    return info;
  }

  void _recomputeMatched() {
    final t = _current.value;
    final o = _output.value;
    _matched.value = t != null &&
        o.sampleRate > 0 &&
        o.sampleRate == t.sampleRate &&
        !eqController.active;
  }

  // ---------------------------------------------------------------------
  // Resume
  // ---------------------------------------------------------------------

  void _saveResume() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      final p = _player;
      if (p == null) return;
      final seq = p.sequence;
      if (seq.isEmpty) return;
      final keys = <String>[];
      for (final s in seq) {
        final t = _trackOf(s);
        if (t != null) keys.add(t.key);
      }
      unawaited(settingsStore.set(_kResume, {
        'keys': keys,
        'index': p.currentIndex ?? 0,
        'posMs': p.position.inMilliseconds,
        'shuffle': p.shuffleModeEnabled,
      }));
    });
  }

  Future<void> _restoreResume() async {
    final m = settingsStore.get<Map<String, dynamic>>(_kResume);
    if (m == null) return;
    try {
      final keys = (m['keys'] as List?)?.cast<String>() ?? const <String>[];
      var index = (m['index'] as int?) ?? 0;
      final tracks = <Track>[];
      for (var i = 0; i < keys.length; i++) {
        final t = libraryStore.track(keys[i]);
        if (t == null) {
          if (i < index) index--;
          continue;
        }
        tracks.add(t);
      }
      if (tracks.isEmpty) return;
      index = index.clamp(0, tracks.length - 1);
      final pos = Duration(milliseconds: (m['posMs'] as int?) ?? 0);
      final shuffle = m['shuffle'] == true;
      await _run(() async {
        final p = player;
        _byUid.clear();
        _order = QueueShuffleOrder();
        await p.setAudioSources([for (final t in tracks) _source(t)],
            initialIndex: index,
            initialPosition: pos,
            shuffleOrder: _order,
            preload: false);
        if (shuffle) await p.shuffle();
        await p.setShuffleModeEnabled(shuffle);
      });
    } catch (e) {
      debugPrint('Resume failed: $e');
    }
  }
}

final PlayerController playerController = PlayerController();
