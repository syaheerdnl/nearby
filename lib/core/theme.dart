import 'package:flutter/material.dart';

/// Nearby's look: plain Material with one indigo accent. Colour for places
/// comes from PlaceCategory, not from the theme.
class AppTheme {
  const AppTheme._();

  static const Color indigo = Color(0xFF3D3AA8);
  static const Color paper = Color(0xFFFBFBF9);
  static const Color line = Color(0xFFECEBE5);
  static const Color ink = Color(0xFF1B1B1F);
  static const Color muted = Color(0xFF6D6B63);
  static const Color okBg = Color(0xFFEEF3EA);
  static const Color okFg = Color(0xFF2F5A22);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: indigo,
      brightness: Brightness.light,
    ).copyWith(
      primary: indigo,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE5E4F6),
      onPrimaryContainer: const Color(0xFF2B2890),
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: muted,
      outline: const Color(0xFFC9C6BB),
      outlineVariant: line,
    );
    return _base(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: indigo,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFFB9B7F5),
      onPrimary: const Color(0xFF1E1B6E),
      surface: const Color(0xFF151518),
      outlineVariant: const Color(0xFF2C2C31),
    );
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    final r8 = BorderRadius.circular(8);
    final r10 = BorderRadius.circular(10);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: r8),
        enabledBorder: OutlineInputBorder(
          borderRadius: r8,
          borderSide: BorderSide(color: scheme.outline),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: r10),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: r10),
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: r8),
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: r8),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: r8),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}
