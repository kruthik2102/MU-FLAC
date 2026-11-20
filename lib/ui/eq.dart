import 'package:material_ui/material_ui.dart';

import '../core/core.dart';
import 'theme.dart';
import 'widgets.dart';

String _db(double v) {
  final r = (v * 2).round() / 2;
  if (r == 0) return '0';
  final s = r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  return r > 0 ? '+$s' : s.replaceFirst('-', '−');
}

/// Equalizer (screen 15).
class EqualizerPage extends StatelessWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MF.bg,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: eqController,
          builder: (context, _) {
            final eq = eqController;
            return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              PageTop(
                title: 'Equalizer',
                trailing: eq.supported
                    ? GestureDetector(
                        onTap: eq.reset,
                        child: const SizedBox(
                          width: 64,
                          height: 44,
                          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            Icon(Icons.restart_alt_rounded, size: 18, color: MF.text3),
                            SizedBox(width: 4),
                            Text('Reset', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: MF.text3)),
                          ]),
                        ),
                      )
                    : null,
              ),
              if (!eq.supported)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyHint(
                    icon: Icons.graphic_eq_rounded,
                    title: 'EQ not available here yet',
                    body:
                        'On iPhone, MU-FLAC currently plays your files untouched (bit-perfect). The 10-band EQ works on Android 9 and newer; iPhone support is planned.',
                  ),
                )
              else ...[
                Group(children: [
                  ListItem(
                    icon: Icons.graphic_eq_rounded,
                    title: eq.enabled ? 'EQ on' : 'EQ off',
                    subtitle: 'Off = bit-perfect. On = audio is processed.',
                    trailing: MfToggle(value: eq.enabled, onChanged: eq.setEnabled),
                  ),
                ]),
                const SizedBox(height: 18),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
                    children: [
                      for (final p in eq.presets) ...[
                        MfChip(
                          label: p.name,
                          selected: eq.currentPresetName == p.name,
                          onTap: () => eq.applyPreset(p.name),
                          onLongPress: p.builtIn
                              ? null
                              : () async {
                                  final ok = await confirmDialog(context, title: 'Delete preset "${p.name}"?');
                                  if (ok) await eq.deletePreset(p.name);
                                },
                        ),
                        const SizedBox(width: 10),
                      ],
                      MfChip(
                        label: 'Save',
                        icon: Icons.add_rounded,
                        onTap: () async {
                          final name = await showTextDialog(context, title: 'Save preset', hint: 'Preset name', action: 'Save');
                          if (name == null) return;
                          final ok = await eq.savePreset(name);
                          toast(ok ? 'Saved "$name"' : 'Could not save "$name"');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: eq.enabled ? 1 : .45,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
                    decoration:
                        BoxDecoration(color: MF.card, borderRadius: BorderRadius.circular(22), boxShadow: MF.cardShadow),
                    child: Column(children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Row(children: [
                          Expanded(child: Text('10-BAND · dB', style: MF.cap)),
                          Text('+12 / 0 / −12', style: MF.meta),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        for (var i = 0; i < EqController.bandCount; i++)
                          Expanded(
                            child: _BandSlider(
                              value: eq.gains[i],
                              label: EqController.bandLabel(i),
                              onChanged: (v) => eq.setGain(i, v),
                            ),
                          ),
                      ]),
                    ]),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  decoration:
                      BoxDecoration(color: MF.card, borderRadius: BorderRadius.circular(22), boxShadow: MF.cardShadow),
                  child: Column(children: [
                    Row(children: [
                      const Expanded(child: Text('Preamp', style: MF.t2)),
                      Text('${_db(eq.preampDb)} dB', style: MF.meta.copyWith(color: MF.text, fontSize: 13)),
                    ]),
                    MfSlider(
                      value: eq.preampDb,
                      min: EqController.minPreamp,
                      max: EqController.maxPreamp,
                      onChanged: (v) => eq.setPreamp((v * 2).round() / 2),
                    ),
                    const Text('Lower the preamp if boosted bands clip.', style: MF.meta),
                  ]),
                ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

/// Vertical neumorphic band slider: double-tap resets to 0 dB.
class _BandSlider extends StatelessWidget {
  const _BandSlider({required this.value, required this.label, required this.onChanged});
  final double value;
  final String label;
  final ValueChanged<double> onChanged;

  static const double _h = 212;
  static const double _min = EqController.minGain, _max = EqController.maxGain;

  double _fromDy(double dy) {
    final f = 1 - (dy / _h).clamp(0.0, 1.0);
    final v = _min + f * (_max - _min);
    return (v * 2).round() / 2;
  }

  @override
  Widget build(BuildContext context) {
    final f = (value - _min) / (_max - _min);
    final y = (1 - f) * _h;
    const zero = _h / 2;
    return Column(children: [
      Text(_db(value), style: MF.meta.copyWith(fontSize: 11, color: value == 0 ? MF.text2 : MF.text)),
      const SizedBox(height: 10),
      Semantics(
        slider: true,
        label: '$label Hz',
        value: '${_db(value)} dB',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) => onChanged(_fromDy(d.localPosition.dy)),
          onVerticalDragUpdate: (d) => onChanged(_fromDy(d.localPosition.dy)),
          onTapUp: (d) => onChanged(_fromDy(d.localPosition.dy)),
          onDoubleTap: () => onChanged(0),
          child: SizedBox(
            width: 32,
            height: _h,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
              Container(
                width: 8,
                height: _h,
                decoration: BoxDecoration(color: MF.track, borderRadius: BorderRadius.circular(4)),
              ),
              const Positioned(
                top: zero - 1,
                child: SizedBox(width: 20, height: 2, child: ColoredBox(color: Color(0xFF3A3A3C))),
              ),
              Positioned(
                top: y < zero ? y : zero,
                child: Container(
                  width: 8,
                  height: (y - zero).abs(),
                  decoration: BoxDecoration(color: MF.chipOn, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Positioned(
                top: y - 9,
                child: Container(
                  width: 28,
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A3A3D), Color(0xFF262628)]),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0x0DFFFFFF)),
                    boxShadow: const [
                      BoxShadow(offset: Offset(3, 3), blurRadius: 7, color: Color(0x99000000)),
                      BoxShadow(offset: Offset(-1, -1), blurRadius: 3, color: Color(0x0FFFFFFF)),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Container(width: 12, height: 2, color: MF.text3),
                ),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Text(label, style: MF.meta.copyWith(fontSize: 10)),
    ]);
  }
}
