import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the two [ThemeData]s from [AppTokens].
///
/// Nothing moves between the themes — the layouts are identical and only the
/// tokens change. Semantic roles are named in the [ColorScheme] and each theme
/// fills them, because the tonal ramps invert and `neutral500` does not mean
/// the same thing in both.
abstract final class AppTheme {
  static ThemeData dark() => _build(AppTokens.nocturne, Brightness.dark);
  static ThemeData light() => _build(AppTokens.organic, Brightness.light);

  static ThemeData _build(AppTokens t, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: t.accent,
      onPrimary: t.primaryButtonIsFilled ? t.ground : t.accent,
      primaryContainer: t.accentFill,
      onPrimaryContainer: t.accentText,
      secondary: t.accent2,
      onSecondary: t.ground,
      secondaryContainer: t.accent2Fill,
      onSecondaryContainer: t.accent2Text,
      surface: t.surface,
      onSurface: t.text,
      onSurfaceVariant: t.textMuted,
      surfaceContainerLowest: t.titleBar,
      surfaceContainerLow: t.chrome,
      surfaceContainer: t.surface,
      surfaceContainerHigh: t.surface,
      surfaceContainerHighest: t.surface,
      surfaceDim: t.ground,
      surfaceBright: t.surface,
      outline: t.divider,
      outlineVariant: t.divider,
      // The app has no destructive-red in its palette; errors borrow the
      // accent so nothing arrives unthemed.
      error: t.accent,
      onError: t.ground,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: t.text,
      onInverseSurface: t.ground,
      inversePrimary: t.accentText,
    );

    final body = TextStyle(
      fontFamily: t.bodyFamily,
      color: t.text,
      fontSize: 13.5,
      height: 1.55,
      fontVariations: _wght(400),
    );

    TextStyle heading(double size, {double? height}) => TextStyle(
      fontFamily: t.headingFamily,
      color: t.text,
      fontSize: size,
      height: height ?? 1.15,
      letterSpacing: -0.015 * size,
      fontVariations: _wght(t.headingWeight),
      fontWeight: _nearestWeight(t.headingWeight),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.ground,
      canvasColor: t.ground,
      dividerColor: t.divider,
      fontFamily: t.bodyFamily,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[t],
      dividerTheme: DividerThemeData(color: t.divider, thickness: 1, space: 1),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: t.accent,
        selectionColor: t.accent.withValues(alpha: 0.30),
        selectionHandleColor: t.accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(t.text.withValues(alpha: 0.18)),
        thickness: const WidgetStatePropertyAll(7),
        radius: const Radius.circular(4),
        crossAxisMargin: 2,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: t.brSmall,
          boxShadow: t.shadowMd,
        ),
        textStyle: body.copyWith(fontSize: 11.5, color: t.textSecondary),
        waitDuration: const Duration(milliseconds: 500),
      ),
      // The design's type sizes, mapped onto the roles the app actually uses:
      // 11px meta, 12px labels, 13.5px nav and body, 14.5px card titles,
      // 16px brand. Cook mode sets its own, much larger, sizes locally.
      textTheme: TextTheme(
        displayLarge: heading(42),
        displayMedium: heading(32),
        displaySmall: heading(27),
        headlineMedium: heading(22),
        headlineSmall: heading(19),
        titleLarge: heading(18),
        titleMedium: heading(16), // brand
        titleSmall: body.copyWith(fontSize: 14.5, height: 1.25), // card titles
        bodyLarge: body.copyWith(fontSize: 14),
        bodyMedium: body, // 13.5 — nav and body
        bodySmall: body.copyWith(fontSize: 12.5, color: t.textSecondary),
        labelLarge: body.copyWith(fontSize: 12, color: t.textSecondary),
        labelMedium: body.copyWith(fontSize: 11, color: t.textMuted),
        labelSmall: body.copyWith(
          fontSize: 10,
          color: t.textMuted,
          letterSpacing: 0.8,
          height: 1.2,
        ),
      ),
    );
  }

  /// Variable-font weight selection.
  ///
  /// All three bundled faces — Inter, Figtree and Baloo 2 — are variable, so a
  /// weight is a `wght` axis value rather than a separate font file.
  static List<FontVariation> _wght(double weight) => <FontVariation>[
    FontVariation('wght', weight),
  ];

  /// The nearest [FontWeight] to the axis value, set alongside the variation
  /// so text still lands close if a face ever falls back to a static instance.
  static FontWeight _nearestWeight(double weight) {
    final index = ((weight / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[index];
  }
}
