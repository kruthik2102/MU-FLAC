import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../core/core.dart';
import 'sheets.dart';
import 'theme.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

void toast(String msg) {
  final m = messengerKey.currentState;
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

/// Neumorphic raised surface that sinks slightly while pressed.
class Raised extends StatefulWidget {
  const Raised({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.width,
    this.height,
    this.radius = 14,
    this.circle = false,
    this.gradient = MF.raisedGradient,
    this.shadow = MF.raisedShadow,
    this.label,
    this.padding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double? width, height;
  final double radius;
  final bool circle;
  final Gradient gradient;
  final List<BoxShadow> shadow;
  final String? label;
  final EdgeInsetsGeometry? padding;

  @override
  State<Raised> createState() => _RaisedState();
}

class _RaisedState extends State<Raised> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: widget.width,
          height: widget.height,
          padding: widget.padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: _down ? MF.pressedGradient : widget.gradient,
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.circle ? null : BorderRadius.circular(widget.radius),
            boxShadow: _down ? MF.smallShadow : widget.shadow,
          ),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 90),
            scale: _down ? 0.96 : 1,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class SquareButton extends StatelessWidget {
  const SquareButton({super.key, required this.icon, this.onTap, required this.label, this.size = 22});
  final IconData icon;
  final VoidCallback? onTap;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) => Raised(
        width: 44,
        height: 44,
        radius: 14,
        onTap: onTap,
        label: label,
        child: Icon(icon, size: size, color: MF.text),
      );
}

class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    this.onTap,
    required this.label,
    this.diameter = 52,
    this.iconSize = 22,
    this.color = MF.text,
    this.dot = false,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String label;
  final double diameter, iconSize;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) => Raised(
        width: diameter,
        height: diameter,
        circle: true,
        onTap: onTap,
        label: label,
        child: Stack(alignment: Alignment.center, children: [
          Icon(icon, size: iconSize, color: color),
          if (dot)
            Positioned(
              bottom: diameter * .16,
              child: Container(
                  width: 4, height: 4, decoration: const BoxDecoration(color: MF.text, shape: BoxShape.circle)),
            ),
        ]),
      );
}

class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, this.icon, this.onTap, this.primary = false, this.height = 48});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? MF.bg : MF.text;
    return Raised(
      height: height,
      radius: height / 2,
      gradient: primary ? MF.primaryGradient : MF.raisedGradient,
      onTap: onTap,
      label: label,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
        Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

class FormatPill extends StatelessWidget {
  const FormatPill(this.text, {super.key, this.onTap, this.grey = false});
  final String text;
  final VoidCallback? onTap;
  final bool grey;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: grey ? MF.tile : MF.light,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(text, style: MF.pill.copyWith(color: grey ? MF.text3 : MF.bg)),
        ),
      );
}

/// Album art from the cached embedded picture, or a generated placeholder.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.path,
    required this.seed,
    this.size,
    this.radius = 12,
    this.shadow,
    this.circle = false,
  });

  final String? path;
  final String seed;
  final double? size;
  final double radius;
  final List<BoxShadow>? shadow;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final side = size ?? (c.maxWidth.isFinite ? c.maxWidth : 120.0);
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final br = circle ? BorderRadius.circular(side) : BorderRadius.circular(radius);
      Widget img = path == null
          ? _Placeholder(seed: seed, side: side)
          : Image.file(
              File(path!),
              width: side,
              height: side,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: (side * dpr).round().clamp(32, 2048),
              errorBuilder: (_, _, _) => _Placeholder(seed: seed, side: side),
            );
      return Container(
        width: side,
        height: side,
        decoration: BoxDecoration(borderRadius: br, boxShadow: shadow),
        child: ClipRRect(borderRadius: br, child: img),
      );
    });
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.seed, required this.side});
  final String seed;
  final double side;

  @override
  Widget build(BuildContext context) {
    final (a, b) = placeholderColorsFor(seed);
    final words = seed.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty
        ? '♪'
        : words.take(2).map((w) => w.characters.first.toUpperCase()).join();
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]),
      ),
      child: Stack(children: [
        Positioned(
          right: -side * .18,
          top: -side * .12,
          child: Container(
            width: side * .72,
            height: side * .72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .10),
            ),
          ),
        ),
        if (side >= 40)
          Positioned(
            left: side * .1,
            bottom: side * .08,
            child: Text(initials,
                style: TextStyle(
                    fontSize: side * .2,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: .85),
                    letterSpacing: -0.5)),
          ),
      ]),
    );
  }
}

/// 2x2 cover collage for playlists.
class Collage extends StatelessWidget {
  const Collage({super.key, required this.tracks, required this.size, this.seed = '', this.favorites = false});
  final List<Track> tracks;
  final double size;
  final String seed;
  final bool favorites;

  @override
  Widget build(BuildContext context) {
    if (favorites) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            gradient: MF.raisedGradient, borderRadius: BorderRadius.circular(12), boxShadow: MF.smallShadow),
        child: Icon(Icons.favorite_rounded, color: MF.text, size: size * .42),
      );
    }
    final seen = <String>{};
    final arts = <Track>[];
    for (final t in tracks) {
      if (seen.add(t.albumId)) arts.add(t);
      if (arts.length == 4) break;
    }
    if (arts.length < 4) {
      return CoverArt(
          path: arts.isEmpty ? null : arts.first.artPath,
          seed: arts.isEmpty ? seed : arts.first.album,
          size: size,
          radius: 12);
    }
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: Wrap(children: [
          for (final t in arts) CoverArt(path: t.artPath, seed: t.album, size: half, radius: 0),
        ]),
      ),
    );
  }
}

/// Top bar: [back] title [trailing].
class PageTop extends StatelessWidget {
  const PageTop({super.key, this.title = '', this.trailing, this.back = true, this.onBack});
  final String title;
  final Widget? trailing;
  final bool back;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            if (back)
              SquareButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  label: 'Back',
                  onTap: onBack ?? () => Navigator.of(context).maybePop())
            else
              const SizedBox(width: 44),
            Expanded(
              child: Text(title,
                  textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: MF.t1),
            ),
            trailing ?? const SizedBox(width: 44),
          ]),
        ),
      );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 10), this.trailing});
  final String text;
  final EdgeInsets padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Text(text.toUpperCase(), style: MF.cap)),
          ?trailing,
        ]),
      );
}

/// Rounded card group of rows (settings style).
class Group extends StatelessWidget {
  const Group({super.key, required this.children, this.margin = const EdgeInsets.symmetric(horizontal: 20)});
  final List<Widget> children;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(Container(height: 1, color: MF.divider));
      items.add(children[i]);
    }
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: MF.card, borderRadius: BorderRadius.circular(22), boxShadow: MF.cardShadow),
      child: Column(mainAxisSize: MainAxisSize.min, children: items),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 34});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: MF.tile, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: size * .56, color: MF.chipOn),
      );
}

class ListItem extends StatelessWidget {
  const ListItem({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.chevron = false,
  });
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              if (leading != null) leading! else if (icon != null) IconTile(icon!),
              if (leading != null || icon != null) const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: MF.t2, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: MF.t3, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (chevron) const Icon(Icons.chevron_right_rounded, color: MF.text2, size: 22),
            ]),
          ),
        ),
      );
}

class KV extends StatelessWidget {
  const KV(this.k, this.v, {super.key});
  final String k, v;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: MF.t2.copyWith(color: MF.text2, fontWeight: FontWeight.w400)),
            const SizedBox(width: 16),
            Expanded(child: Text(v, textAlign: TextAlign.right, style: MF.t2)),
          ]),
        ),
      );
}

class MfToggle extends StatelessWidget {
  const MfToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 51,
            height: 31,
            padding: const EdgeInsets.all(3),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: value
                ? BoxDecoration(color: MF.chipOn, borderRadius: BorderRadius.circular(16))
                : MF.wellDecoration.copyWith(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? MF.panel : null,
                gradient: value
                    ? null
                    : const LinearGradient(colors: [Color(0xFF48484A), Color(0xFF3A3A3C)]),
                boxShadow: const [BoxShadow(offset: Offset(2, 2), blurRadius: 5, color: Color(0x80000000))],
              ),
            ),
          ),
        ),
      );
}

/// Horizontal slider: dark recessed track, white fill, light knob.
class MfSlider extends StatefulWidget {
  const MfSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.knob = true,
  });
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final bool knob;

  @override
  State<MfSlider> createState() => _MfSliderState();
}

class _MfSliderState extends State<MfSlider> {
  double? _drag;

  double _valueAt(double dx, double w) {
    final f = (dx / w).clamp(0.0, 1.0);
    return widget.min + f * (widget.max - widget.min);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final v = (_drag ?? widget.value).clamp(widget.min, widget.max);
      final span = widget.max - widget.min;
      final f = span == 0 ? 0.0 : (v - widget.min) / span;
      void update(double dx) {
        final nv = _valueAt(dx, w);
        setState(() => _drag = nv);
        widget.onChanged(nv);
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => update(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
        onHorizontalDragEnd: (_) {
          final end = _drag;
          setState(() => _drag = null);
          if (end != null) widget.onChangeEnd?.call(end);
        },
        onTapUp: (d) {
          final nv = _valueAt(d.localPosition.dx, w);
          widget.onChanged(nv);
          widget.onChangeEnd?.call(nv);
        },
        child: SizedBox(
          height: 30,
          child: Stack(alignment: Alignment.centerLeft, clipBehavior: Clip.none, children: [
            Container(
              height: 4,
              decoration: BoxDecoration(color: MF.track, borderRadius: BorderRadius.circular(2)),
            ),
            Container(
              width: (w * f).clamp(0.0, w),
              height: 4,
              decoration: BoxDecoration(color: MF.text, borderRadius: BorderRadius.circular(2)),
            ),
            if (widget.knob)
              Positioned(
                left: (w * f - 11).clamp(-11.0, w - 11),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [MF.text, MF.text3]),
                    boxShadow: [BoxShadow(offset: Offset(2, 3), blurRadius: 6, color: Color(0x99000000))],
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

/// Neumorphic segmented control.
class Segmented extends StatelessWidget {
  const Segmented({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: MF.wellDecoration.copyWith(borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 36,
                  alignment: Alignment.center,
                  decoration: i == index
                      ? BoxDecoration(
                          gradient: MF.segOnGradient,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: MF.smallShadow)
                      : null,
                  child: Text(labels[i],
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: i == index ? MF.text : MF.text2)),
                ),
              ),
            ),
        ]),
      );
}

class MfChip extends StatelessWidget {
  const MfChip({super.key, required this.label, this.selected = false, this.onTap, this.onLongPress, this.icon});
  final String label;
  final bool selected;
  final VoidCallback? onTap, onLongPress;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? MF.chipOn : null,
            gradient: selected ? null : MF.raisedGradient,
            borderRadius: BorderRadius.circular(17),
            boxShadow: selected ? null : MF.smallShadow,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: selected ? MF.bg : MF.text3), const SizedBox(width: 6)],
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: selected ? MF.bg : MF.text3)),
          ]),
        ),
      );
}

/// Song row used in every list.
class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.onTap,
    this.number,
    this.showArt = true,
    this.trailing,
    this.onRemove,
    this.removeLabel,
  });

  final Track track;
  final VoidCallback onTap;
  final int? number;
  final bool showArt;
  final Widget? trailing;
  final VoidCallback? onRemove;
  final String? removeLabel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Track?>(
      valueListenable: playerController.current,
      builder: (context, cur, _) {
        final isCur = cur?.key == track.key;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onLongPress: () => showTrackActions(context, track, onRemove: onRemove, removeLabel: removeLabel),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: isCur
                ? BoxDecoration(color: MF.menu, borderRadius: BorderRadius.circular(16))
                : null,
            child: Row(children: [
              if (number != null)
                SizedBox(
                  width: 28,
                  child: isCur
                      ? const Icon(Icons.graphic_eq_rounded, size: 18, color: MF.text)
                      : Text('$number', style: MF.meta.copyWith(fontSize: 14)),
                )
              else if (showArt)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: CoverArt(path: track.artPath, seed: track.album, size: 44, radius: 8),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MF.t2.copyWith(fontWeight: isCur ? FontWeight.w600 : FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text('${track.artist} · ${track.formatLabel.replaceFirst('FLAC ', '')}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: MF.t3),
                ]),
              ),
              const SizedBox(width: 8),
              Text(fmtDuration(track.duration), style: MF.meta),
              trailing ??
                  IconButton(
                    tooltip: 'More',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_horiz_rounded, color: MF.text2, size: 20),
                    onPressed: () =>
                        showTrackActions(context, track, onRemove: onRemove, removeLabel: removeLabel),
                  ),
            ]),
          ),
        );
      },
    );
  }
}

/// Play + Shuffle buttons row.
class PlayShuffleRow extends StatelessWidget {
  const PlayShuffleRow({super.key, required this.tracks, this.playLabel = 'Play'});
  final List<Track> tracks;
  final String playLabel;

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        PillButton(
          label: playLabel,
          icon: Icons.play_arrow_rounded,
          primary: true,
          onTap: tracks.isEmpty ? null : () => playerController.playTracks(tracks),
        ),
        const SizedBox(width: 14),
        PillButton(
          label: 'Shuffle',
          icon: Icons.shuffle_rounded,
          onTap: tracks.isEmpty ? null : () => playerController.playTracks(tracks, shuffle: true),
        ),
      ]);
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.title, this.body, this.action});
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Raised(width: 88, height: 88, circle: true, child: Icon(icon, size: 36, color: MF.text)),
            const SizedBox(height: 22),
            Text(title, style: MF.h2, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body!, style: MF.t3.copyWith(fontSize: 14, height: 1.4), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ]),
        ),
      );
}

/// Bottom sheet in the MU-FLAC style.
Future<T?> showMfSheet<T>(BuildContext context, WidgetBuilder builder, {bool expand = false}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: MF.sheet,
    barrierColor: MF.barrier,
    elevation: 0,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (expand ? .88 : .85)),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: MF.grab, borderRadius: BorderRadius.circular(3))),
          Flexible(child: builder(ctx)),
        ]),
      ),
    ),
  );
}

Future<String?> showTextDialog(BuildContext context,
    {required String title, String initial = '', String hint = '', String action = 'Create'}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    barrierColor: MF.barrier,
    builder: (ctx) {
      void submit() {
        final v = ctl.text.trim();
        if (v.isNotEmpty) Navigator.of(ctx).pop(v);
      }

      return Dialog(
        backgroundColor: MF.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: MF.t1, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: MF.wellDecoration.copyWith(borderRadius: BorderRadius.circular(14)),
              child: TextField(
                controller: ctl,
                autofocus: true,
                style: MF.t2,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: MF.t2.copyWith(color: MF.text2),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: PillButton(label: 'Cancel', height: 44, onTap: () => Navigator.of(ctx).pop())),
              const SizedBox(width: 12),
              Expanded(child: PillButton(label: action, height: 44, primary: true, onTap: submit)),
            ]),
          ]),
        ),
      );
    },
  );
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, String? body, String action = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierColor: MF.barrier,
    builder: (ctx) => Dialog(
      backgroundColor: MF.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: MF.t1, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(body, style: MF.t3, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: PillButton(label: 'Cancel', height: 44, onTap: () => Navigator.of(ctx).pop(false))),
            const SizedBox(width: 12),
            Expanded(
                child: PillButton(label: action, height: 44, primary: true, onTap: () => Navigator.of(ctx).pop(true))),
          ]),
        ]),
      ),
    ),
  );
  return r ?? false;
}
