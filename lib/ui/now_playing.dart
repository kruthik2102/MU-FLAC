import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide RepeatMode;

import '../core/core.dart';
import 'sheets.dart';
import 'shell.dart';
import 'theme.dart';
import 'widgets.dart';

/// Now Playing (screen 01) - charcoal neumorphic layout with the click wheel.
class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  static const double _panel = 304;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: MF.bg,
      body: ValueListenableBuilder<Track?>(
        valueListenable: playerController.current,
        builder: (context, t, _) {
          if (t == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.of(context).maybePop();
            });
            return const SizedBox.shrink();
          }
          return GestureDetector(
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 400) Navigator.of(context).maybePop();
            },
            child: LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              final topH = c.maxHeight - _panel - pad.bottom - pad.top;
              // 60 top bar + 14 + 22 + 68 card + 26 + 30 progress + 16 slack
              final art = math.min(w * .62, topH - 236).clamp(120.0, 340.0);
              return Stack(children: [
                Positioned.fill(
                  bottom: _panel + pad.bottom,
                  child: Padding(
                    padding: EdgeInsets.only(top: pad.top),
                    child: Column(children: [
                      PageTop(
                        title: 'Now Playing',
                        onBack: () => Navigator.of(context).maybePop(),
                        trailing: SquareButton(
                          icon: Icons.info_outline_rounded,
                          label: 'Track info',
                          onTap: () => showTrackInfo(context, t),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onHorizontalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          if (v < -300) playerController.next();
                          if (v > 300) playerController.previous();
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: CoverArt(
                            key: ValueKey(t.artHash ?? t.album),
                            path: t.artPath,
                            seed: t.album,
                            size: art,
                            radius: 12,
                            shadow: MF.heroShadow,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _InfoCard(track: t),
                      const SizedBox(height: 22),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: _SeekBar()),
                      const Spacer(),
                    ]),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: _panel + pad.bottom,
                  child: _ControlPanel(track: t),
                ),
              ]);
            }),
          );
        },
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) => Container(
        height: 68,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: MF.card, borderRadius: BorderRadius.circular(22), boxShadow: MF.cardShadow),
        child: Row(children: [
          GestureDetector(
            onTap: () => AppNav.album(track.albumId),
            child: CoverArt(path: track.artPath, seed: track.album, size: 44, radius: 9),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => AppNav.artist(track.albumArtist.isNotEmpty ? track.albumArtist : track.artist),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: MF.t3),
                const SizedBox(height: 2),
                Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: MF.t1),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          FormatPill(track.formatLabel, onTap: () => showTrackInfo(context, track)),
        ]),
      );
}

class _SeekBar extends StatefulWidget {
  const _SeekBar();
  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag; // 0..1 while dragging

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: playerController.duration,
      builder: (context, dur, _) => StreamBuilder<Duration>(
        stream: playerController.positionStream,
        initialData: playerController.position,
        builder: (context, snap) {
          final pos = snap.data ?? Duration.zero;
          final total = dur.inMilliseconds;
          final live = total <= 0 ? 0.0 : (pos.inMilliseconds / total).clamp(0.0, 1.0);
          final f = _drag ?? live;
          final shown = Duration(milliseconds: (f * total).round());
          return LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            double at(double dx) => (dx / w).clamp(0.0, 1.0);
            void end() {
              final d = _drag;
              setState(() => _drag = null);
              if (d != null && total > 0) playerController.seek(Duration(milliseconds: (d * total).round()));
            }

            return Column(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (d) => setState(() => _drag = at(d.localPosition.dx)),
                onHorizontalDragUpdate: (d) => setState(() => _drag = at(d.localPosition.dx)),
                onHorizontalDragEnd: (_) => end(),
                onTapUp: (d) {
                  if (total > 0) {
                    playerController.seek(Duration(milliseconds: (at(d.localPosition.dx) * total).round()));
                  }
                },
                child: SizedBox(
                  height: 24,
                  child: Stack(alignment: Alignment.centerLeft, clipBehavior: Clip.none, children: [
                    Container(
                        height: _drag == null ? 4 : 6,
                        decoration: BoxDecoration(color: MF.track, borderRadius: BorderRadius.circular(3))),
                    Container(
                        width: w * f,
                        height: _drag == null ? 4 : 6,
                        decoration: BoxDecoration(color: MF.text, borderRadius: BorderRadius.circular(3))),
                  ]),
                ),
              ),
              const SizedBox(height: 2),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(fmtDuration(shown), style: MF.meta),
                Text(fmtDuration(dur - shown, negative: true), style: MF.meta),
              ]),
            ]);
          });
        },
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MF.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: Color(0x0DFFFFFF))),
        boxShadow: [BoxShadow(offset: Offset(0, -14), blurRadius: 30, color: Color(0x59000000))],
      ),
      child: Stack(children: [
        Positioned(
          top: 44,
          left: 0,
          right: 0,
          child: Center(child: _ClickWheel(track: track)),
        ),
        Positioned(
          left: 32,
          top: 44,
          child: RoundButton(
            icon: Icons.more_horiz_rounded,
            label: 'Track actions',
            onTap: () => showTrackActions(context, track),
          ),
        ),
        Positioned(
          right: 32,
          top: 44,
          child: RoundButton(icon: Icons.format_list_bulleted_rounded, label: 'Queue', onTap: () => showQueue(context)),
        ),
        Positioned(
          left: 32,
          top: 172,
          child: ValueListenableBuilder<RepeatMode>(
            valueListenable: playerController.repeat,
            builder: (_, r, _) => RoundButton(
              icon: r == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              label: 'Repeat: ${r.name}',
              color: r == RepeatMode.off ? MF.text2 : MF.text,
              dot: r != RepeatMode.off,
              onTap: () {
                playerController.cycleRepeat();
                final next = switch (r) { RepeatMode.off => 'all', RepeatMode.all => 'one', RepeatMode.one => 'off' };
                toast('Repeat $next');
              },
            ),
          ),
        ),
        Positioned(
          right: 32,
          top: 172,
          child: RoundButton(icon: Icons.music_note_rounded, label: 'Library', onTap: AppNav.library),
        ),
      ]),
    );
  }
}

/// The 180 px dial: heart / volume / prev / next on the ring, play in the middle.
/// Dragging around the ring scrubs through the track (like a click wheel).
class _ClickWheel extends StatefulWidget {
  const _ClickWheel({required this.track});
  final Track track;
  @override
  State<_ClickWheel> createState() => _ClickWheelState();
}

class _ClickWheelState extends State<_ClickWheel> {
  static const double _size = 180;
  double? _lastAngle;
  Duration? _scrubTarget;
  Timer? _commit;

  double _angle(Offset p) => math.atan2(p.dy - _size / 2, p.dx - _size / 2);

  bool _onRing(Offset p) {
    final r = (p - const Offset(_size / 2, _size / 2)).distance;
    return r > 48 && r < _size / 2 + 6;
  }

  void _scrubBy(double delta) {
    final dur = playerController.duration.value;
    if (dur <= Duration.zero) return;
    // One full turn = 60 s.
    final base = _scrubTarget ?? playerController.position;
    var ms = base.inMilliseconds + (delta / (2 * math.pi) * 60000).round();
    ms = ms.clamp(0, dur.inMilliseconds - 500);
    setState(() => _scrubTarget = Duration(milliseconds: ms));
    _commit?.cancel();
    _commit = Timer(const Duration(milliseconds: 120), () {
      final t = _scrubTarget;
      if (t != null) playerController.seek(t);
    });
  }

  @override
  void dispose() {
    _commit?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return GestureDetector(
      onPanStart: (d) {
        _lastAngle = _onRing(d.localPosition) ? _angle(d.localPosition) : null;
        if (_lastAngle != null) HapticFeedback.selectionClick();
      },
      onPanUpdate: (d) {
        final last = _lastAngle;
        if (last == null) return;
        final a = _angle(d.localPosition);
        var delta = a - last;
        if (delta > math.pi) delta -= 2 * math.pi;
        if (delta < -math.pi) delta += 2 * math.pi;
        _lastAngle = a;
        _scrubBy(delta);
      },
      onPanEnd: (_) {
        _lastAngle = null;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _scrubTarget = null);
        });
      },
      child: Container(
        width: _size,
        height: _size,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: MF.dialGradient, boxShadow: MF.dialShadow),
        child: Stack(children: [
          // heart (top)
          Positioned(
            left: 68,
            top: 0,
            child: ListenableBuilder(
              listenable: playlistStore,
              builder: (_, _) {
                final fav = playlistStore.isFavorite(t.key);
                return _DialKey(
                  icon: fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  label: fav ? 'Remove from Favorites' : 'Add to Favorites',
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final now = await playlistStore.toggleFavorite(t.key);
                    toast(now ? 'Added to Favorites' : 'Removed from Favorites');
                  },
                );
              },
            ),
          ),
          // volume (bottom)
          Positioned(
            left: 68,
            bottom: 0,
            child: _DialKey(icon: Icons.volume_up_rounded, label: 'Volume', onTap: () => showVolumePopover(context)),
          ),
          Positioned(
            left: 0,
            top: 68,
            child: _DialKey(icon: Icons.fast_rewind_rounded, label: 'Previous track', onTap: playerController.previous),
          ),
          Positioned(
            right: 0,
            top: 68,
            child: _DialKey(icon: Icons.fast_forward_rounded, label: 'Next track', onTap: playerController.next),
          ),
          // recessed well + centre button
          Positioned(
            left: 44,
            top: 44,
            child: Container(
              width: 92,
              height: 92,
              decoration: MF.wellDecoration.copyWith(shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: 52,
            top: 52,
            child: ValueListenableBuilder<bool>(
              valueListenable: playerController.playing,
              builder: (_, playing, _) => Raised(
                width: 76,
                height: 76,
                circle: true,
                gradient: MF.dialCenterGradient,
                label: playing ? 'Pause' : 'Play',
                onTap: () {
                  HapticFeedback.lightImpact();
                  playerController.togglePlay();
                },
                child: _scrubTarget != null
                    ? Text(fmtDuration(_scrubTarget!), style: MF.meta.copyWith(color: MF.text, fontSize: 13))
                    : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 34, color: MF.text),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DialKey extends StatelessWidget {
  const _DialKey({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 22, color: MF.icon)),
        ),
      );
}

/// Volume popover (screen 02).
Future<void> showVolumePopover(BuildContext context) async {
  if (volumeController.supported) await volumeController.refresh();
  if (!context.mounted) return;
  final bottom = MediaQuery.paddingOf(context).bottom;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close volume',
    barrierColor: const Color(0x66080809),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, NowPlayingPage._panel + bottom - 30),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: BoxDecoration(color: MF.mini, borderRadius: BorderRadius.circular(20), boxShadow: MF.miniShadow),
            child: volumeController.supported
                ? ListenableBuilder(
                    listenable: volumeController,
                    builder: (_, _) => Row(children: [
                      const Icon(Icons.volume_mute_rounded, color: MF.text2, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: MfSlider(
                          value: volumeController.value,
                          min: 0,
                          max: 1,
                          onChanged: volumeController.setVolume,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.volume_up_rounded, color: MF.text, size: 20),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 36,
                        child: Text('${(volumeController.value * 100).round()}',
                            textAlign: TextAlign.right, style: MF.meta.copyWith(color: MF.text)),
                      ),
                    ]),
                  )
                : const Row(children: [
                    Icon(Icons.volume_up_rounded, color: MF.text, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('Use the volume buttons on the side of your iPhone.', style: MF.t3),
                    ),
                  ]),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, a, _, child) => FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .05), end: Offset.zero).animate(a),
        child: child,
      ),
    ),
  );
}
