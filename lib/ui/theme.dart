// MU-FLAC design tokens (from the approved "MU-FLAC Screens" canvas).

import 'package:material_ui/material_ui.dart';

const String kAppVersion = '0.1.3';

abstract final class MF {
  // Surfaces
  static const bg = Color(0xFF161618);
  static const panel = Color(0xFF1C1C1E);
  static const sheet = Color(0xFF1E1E20);
  static const card = Color(0xFF242426);
  static const row = Color(0xFF262628);
  static const mini = Color(0xFF2A2A2D);
  static const menu = Color(0xFF2C2C2F);
  static const well = Color(0xFF121214);
  static const track = Color(0xFF0C0C0E);
  static const tile = Color(0xFF2E2E31);
  static const barrier = Color(0xA3080809);

  // Text / icons
  static const text = Color(0xFFF5F5F7);
  static const text2 = Color(0xFF8E8E93);
  static const text3 = Color(0xFFC7C7CC);
  static const icon = Color(0xFFD1D1D6);
  static const light = Color(0xFFD1D1D6);
  static const chipOn = Color(0xFFE5E5EA);
  static const divider = Color(0x0FFFFFFF);
  static const grab = Color(0xFF48484A);

  // Gradients
  static const raisedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2E2E31), Color(0xFF222224)],
  );
  static const pressedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1F1F21), Color(0xFF2A2A2C)],
  );
  static const dialGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2D2D30), Color(0xFF1F1F21)],
  );
  static const dialCenterGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF323235), Color(0xFF232325)],
  );
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF2F2F7), Color(0xFFD1D1D6)],
  );
  static const segOnGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF303033), Color(0xFF252527)],
  );

  // Shadows (Flutter has no inset shadows; recessed looks use gradients)
  static const raisedShadow = [
    BoxShadow(offset: Offset(5, 5), blurRadius: 12, color: Color(0x8C000000)),
    BoxShadow(offset: Offset(-3, -3), blurRadius: 8, color: Color(0x0AFFFFFF)),
  ];
  static const smallShadow = [
    BoxShadow(offset: Offset(3, 3), blurRadius: 8, color: Color(0x80000000)),
    BoxShadow(offset: Offset(-2, -2), blurRadius: 6, color: Color(0x0AFFFFFF)),
  ];
  static const cardShadow = [
    BoxShadow(offset: Offset(6, 6), blurRadius: 16, color: Color(0x80000000)),
    BoxShadow(offset: Offset(-3, -3), blurRadius: 10, color: Color(0x08FFFFFF)),
  ];
  static const dialShadow = [
    BoxShadow(offset: Offset(10, 10), blurRadius: 24, color: Color(0x9E000000)),
    BoxShadow(offset: Offset(-6, -6), blurRadius: 16, color: Color(0x0AFFFFFF)),
  ];
  static const heroShadow = [
    BoxShadow(offset: Offset(0, 18), blurRadius: 40, color: Color(0x8C000000)),
    BoxShadow(offset: Offset(-4, -4), blurRadius: 14, color: Color(0x08FFFFFF)),
  ];
  static const miniShadow = [
    BoxShadow(offset: Offset(0, 10), blurRadius: 24, color: Color(0x8C000000)),
    BoxShadow(offset: Offset(-2, -2), blurRadius: 8, color: Color(0x08FFFFFF)),
  ];

  // Recessed "well" (simulated inset shadow).
  static const wellDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0B0B0C), Color(0xFF121214), Color(0xFF17171A)],
      stops: [0, .45, 1],
    ),
  );

  // Text styles
  static const _tab = [FontFeature.tabularFigures()];
  static const h1 = TextStyle(
      fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.56, color: text, height: 1.15);
  static const h2 = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.33, color: text, height: 1.2);
  static const t1 = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.17, color: text, height: 1.25);
  static const t2 = TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: text, height: 1.25);
  static const t3 = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: text2, height: 1.25);
  static const meta = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w500, color: text2, fontFeatures: _tab);
  static const cap = TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.88, color: text2);
  static const tabLabel = TextStyle(fontSize: 10, fontWeight: FontWeight.w600);
  static const pill = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.24, color: bg, fontFeatures: _tab);

  static ThemeData theme() {
    final scheme = const ColorScheme.dark(
      primary: chipOn,
      onPrimary: bg,
      secondary: light,
      onSecondary: bg,
      surface: bg,
      onSurface: text,
      surfaceContainerHighest: card,
      error: Color(0xFFFF6961),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerColor: divider,
      textSelectionTheme: const TextSelectionThemeData(
          cursorColor: text, selectionColor: Color(0x55FFFFFF), selectionHandleColor: text),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: mini,
        contentTextStyle: t2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: text, linearTrackColor: track),
      popupMenuTheme: const PopupMenuThemeData(
        color: menu,
        textStyle: t2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      ),
    );
  }
}

String fmtDuration(Duration d, {bool negative = false}) {
  final s = d.inSeconds.abs();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final body = h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
      : '$m:${sec.toString().padLeft(2, '0')}';
  return negative ? '-$body' : body;
}

String fmtTotal(int ms) {
  final min = (ms / 60000).round();
  if (min < 60) return '$min min';
  return '${min ~/ 60} h ${min % 60} min';
}

String fmtSize(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';
