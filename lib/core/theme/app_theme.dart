import 'package:flutter/material.dart';

class AppPalette {
  AppPalette(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  const AppPalette.forBrightness(Brightness brightness)
    : dark = brightness == Brightness.dark;
  final bool dark;
  Color get background =>
      dark ? const Color(0xff171916) : const Color(0xfffcfbf8);
  Color get surface => dark ? const Color(0xff20231f) : Colors.white;
  Color get ink => dark ? const Color(0xfff3f2ec) : const Color(0xff242721);
  Color get muted => dark ? const Color(0xffb2b5aa) : const Color(0xff72766c);
  Color get border => dark ? const Color(0xff383d33) : const Color(0xffe5e6de);
  Color get blush => dark ? const Color(0xff2d3228) : const Color(0xffefefe8);
  Color get accentInk => dark ? const Color(0xffc5cdb7) : baseAccent;
  static const baseAccent = Color(0xff6d755f);
}

class AppTheme {
  static ThemeData build(Brightness brightness, {ThemeData? baseTheme}) {
    final p = AppPalette.forBrightness(brightness);
    final base =
        baseTheme ?? ThemeData(useMaterial3: true, brightness: brightness);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    return base.copyWith(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      colorScheme: base.colorScheme.copyWith(
        primary: p.ink,
        onPrimary: p.background,
        secondary: p.ink,
        surface: p.surface,
        onSurface: p.ink,
        onSurfaceVariant: p.muted,
        primaryContainer: p.blush,
        onPrimaryContainer: p.ink,
        secondaryContainer: p.blush,
        onSecondaryContainer: p.ink,
        tertiary: p.accentInk,
        onTertiary: p.background,
        tertiaryContainer: p.blush,
        onTertiaryContainer: p.ink,
        surfaceContainerLow: p.background,
        surfaceContainer: p.surface,
        surfaceContainerHigh: p.blush,
        outlineVariant: p.border,
        surfaceContainerHighest: p.blush,
        outline: p.border,
      ),
      scaffoldBackgroundColor: p.background,
      dividerColor: p.border,
      textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
      appBarTheme: AppBarTheme(
        iconTheme: IconThemeData(color: p.ink, size: 22),
        actionsIconTheme: IconThemeData(color: p.ink, size: 22),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: p.background,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: p.ink,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: .5,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        labelStyle: TextStyle(color: p.muted, fontSize: 13),
        hintStyle: TextStyle(color: p.muted, fontSize: 13, height: 1.7),
        helperStyle: TextStyle(color: p.muted, fontSize: 11, height: 1.6),
        helperMaxLines: 4,
        errorMaxLines: 4,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: p.ink),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.ink,
          foregroundColor: p.background,
          shape: shape,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: .5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          side: BorderSide(color: p.border),
          shape: shape,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size(48, 48),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.background,
        selectedColor: p.blush,
        side: BorderSide(color: p.border),
        shape: shape,
        labelStyle: TextStyle(color: p.ink, fontSize: 12),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(shape),
          side: WidgetStatePropertyAll(BorderSide(color: p.border)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? p.blush : p.surface,
          ),
          foregroundColor: WidgetStatePropertyAll(p.ink),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: p.border),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: p.ink,
        thumbColor: p.ink,
        inactiveTrackColor: p.border,
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.ink),
    );
  }
}

class AppThemeScope extends StatelessWidget {
  const AppThemeScope({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.build(
      Theme.of(context).brightness,
      baseTheme: Theme.of(context),
    ),
    child: child,
  );
}
