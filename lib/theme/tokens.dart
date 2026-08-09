import 'package:flutter/material.dart';

/// How a recipe photograph is treated so it sits into the page.
///
/// This is one of the four things the handoff flags as genuinely per-theme
/// rather than a palette lookup: Nocturne blends images with the ground so
/// dark backgrounds fall away, Organic washes them so they sit back into the
/// cream.
enum PhotoTreatment { lightenOntoGround, washed }

/// Every design value the two themes disagree about, carried as a
/// [ThemeExtension] so no widget ever hard-codes a colour, a radius or a gap.
///
/// The handoff is explicit that radius and spacing are the single biggest
/// source of drift between the modes, so they live here alongside the colours
/// and are read the same way.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.ground,
    required this.surface,
    required this.chrome,
    required this.titleBar,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accentText,
    required this.accentFill,
    required this.accent2,
    required this.accent2Text,
    required this.accent2Fill,
    required this.textStrong,
    required this.tagAccentBg,
    required this.tagAccentFg,
    required this.tagAccent2Bg,
    required this.tagAccent2Fg,
    required this.tagNeutralBg,
    required this.tagNeutralFg,
    required this.toggleTrackOff,
    required this.toggleKnob,
    required this.neutral,
    required this.accentRamp,
    required this.radiusSmall,
    required this.radiusContainer,
    required this.radiusControl,
    required this.radiusLarge,
    required this.density,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
    required this.headingFamily,
    required this.headingWeight,
    required this.bodyFamily,
    required this.primaryButtonIsFilled,
    required this.photoTreatment,
    required this.cookModeGlow,
  });

  // ── Grounds ──────────────────────────────────────────────────────────────
  /// Window and page background.
  final Color ground;

  /// Cards, panels, raised rows.
  final Color surface;

  /// Sidebar and side panels.
  final Color chrome;

  /// The app's own title bar.
  final Color titleBar;

  // ── Text ─────────────────────────────────────────────────────────────────
  final Color text;

  /// Nav items and labels.
  final Color textSecondary;

  /// Meta, units, counts.
  final Color textMuted;

  /// Disabled and secondary counts.
  final Color textFaint;

  // ── Accent ───────────────────────────────────────────────────────────────
  /// Selection, active tab, links.
  final Color accent;

  /// Accent-coloured body text.
  final Color accentText;

  /// Tinted chips and badges.
  final Color accentFill;

  /// Sage. Light mode only — it carries the pantry's "in stock" state there.
  /// Dark mode is a mono palette and falls back to [accent] for the same job,
  /// so this is never null; it simply resolves to the accent on Nocturne.
  final Color accent2;
  final Color accent2Text;
  final Color accent2Fill;

  // ── Roles that cross over between the ramps ──────────────────────────────
  // These are the ones that would silently break if a widget reached for a
  // ramp step by number: on the dark ground a higher step is fainter, on the
  // light ground it is stronger, so "neutral300" is a highlight in one theme
  // and near-invisible in the other.

  /// Emphasised body text — a card's calorie figure, a method step. Brighter
  /// than [text] on Nocturne, darker than it on Organic.
  final Color textStrong;

  final Color tagAccentBg;
  final Color tagAccentFg;
  final Color tagAccent2Bg;
  final Color tagAccent2Fg;
  final Color tagNeutralBg;
  final Color tagNeutralFg;

  final Color toggleTrackOff;
  final Color toggleKnob;

  // ── Ramps ────────────────────────────────────────────────────────────────
  /// The 100–900 tonal ramps, index 0 == step 100.
  ///
  /// The ramps invert between themes: on the dark ground a higher step is
  /// fainter, on the light ground it is stronger. Prefer the semantic roles
  /// above; reach for a ramp step only where the design names one directly.
  final List<Color> neutral;
  final List<Color> accentRamp;

  // ── Shape ────────────────────────────────────────────────────────────────
  final double radiusSmall;

  /// Cards, panels — 8px dark, 16px light.
  final double radiusContainer;

  /// Buttons, inputs, tags — 8px dark, a full pill on light.
  final double radiusControl;

  /// Large surfaces — 12px dark, 28px light.
  final double radiusLarge;

  // ── Spacing ──────────────────────────────────────────────────────────────
  /// 0.70 on Nocturne, 1.10 on Organic. Applied through [space].
  final double density;

  // ── Elevation ────────────────────────────────────────────────────────────
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;

  // ── Type ─────────────────────────────────────────────────────────────────
  final String headingFamily;

  /// The `wght` axis value for headings — 500 on Inter, 600 on Baloo 2.
  final double headingWeight;
  final String bodyFamily;

  // ── Genuinely per-theme behaviour ────────────────────────────────────────
  /// Organic's primary is a solid accent fill with ground-coloured text;
  /// Nocturne's is a 1px accent outline on transparent.
  final bool primaryButtonIsFilled;
  final PhotoTreatment photoTreatment;

  /// The accent line and soft shadow that lift cook mode's step card off the
  /// ground do almost nothing on cream, so the light theme drops them and
  /// leans on the surface fill and a divider instead.
  final bool cookModeGlow;

  /// The spacing scale, in the same steps the stylesheets name.
  ///
  /// `space(1)` … `space(8)` map onto a 4/8/12/16/24/32 base multiplied by the
  /// theme's [density], which is where the two modes' different airiness comes
  /// from.
  double space(int step) {
    const base = <int, double>{1: 4, 2: 8, 3: 12, 4: 16, 6: 24, 8: 32};
    final v = base[step];
    assert(v != null, 'space($step) is not one of 1, 2, 3, 4, 6, 8');
    return (v ?? 4 * step) * density;
  }

  /// Divider colour — 16% of the text colour, the same formula in both themes.
  Color get divider => text.withValues(alpha: 0.16);

  /// A tint of the accent at [percent], used for active nav rows and the
  /// component headings inside ingredient lists.
  Color accentTint(double percent) => accent.withValues(alpha: percent);

  BorderRadius get brContainer => BorderRadius.circular(radiusContainer);
  BorderRadius get brControl => BorderRadius.circular(radiusControl);
  BorderRadius get brLarge => BorderRadius.circular(radiusLarge);
  BorderRadius get brSmall => BorderRadius.circular(radiusSmall);

  // ── Nocturne (dark) ──────────────────────────────────────────────────────
  static const nocturne = AppTokens(
    ground: Color(0xFF161826),
    surface: Color(0xFF232532),
    chrome: Color(0xFF12141F),
    titleBar: Color(0xFF0F111C),
    text: Color(0xFFE9E9ED),
    textSecondary: Color(0xFFB2B6CA), // neutral-400
    textMuted: Color(0xFF9397AB), // neutral-500
    textFaint: Color(0xFF75798C), // neutral-600
    accent: Color(0xFF9184D9),
    accentText: Color(0xFFD2CEFD), // accent-300
    accentFill: Color(0xFF423A6A), // accent-800
    // Nocturne is a mono palette: the second accent resolves to the accent.
    accent2: Color(0xFF9184D9),
    accent2Text: Color(0xFFD2CEFD),
    accent2Fill: Color(0xFF423A6A),
    textStrong: Color(0xFFE4E7F5), // neutral-200 — brighter than body
    tagAccentBg: Color(0xFF423A6A), // accent-800
    tagAccentFg: Color(0xFFF5F4FF), // accent-100
    tagAccent2Bg: Color(0xFF423E5D),
    tagAccent2Fg: Color(0xFFF5F4FF),
    tagNeutralBg: Color(0xFF3F424D), // neutral-800
    tagNeutralFg: Color(0xFFF3F5FE), // neutral-100
    toggleTrackOff: Color(0xFF3F424D),
    toggleKnob: Color(0xFFF3F5FE),
    neutral: [
      Color(0xFFF3F5FE),
      Color(0xFFE4E7F5),
      Color(0xFFCFD3E5),
      Color(0xFFB2B6CA),
      Color(0xFF9397AB),
      Color(0xFF75798C),
      Color(0xFF595D6C),
      Color(0xFF3F424D),
      Color(0xFF292B31),
    ],
    accentRamp: [
      Color(0xFFF5F4FF),
      Color(0xFFE7E5FE),
      Color(0xFFD2CEFD),
      Color(0xFFB5ABFC),
      Color(0xFF968AE0),
      Color(0xFF796CBF),
      Color(0xFF5D5294),
      Color(0xFF423A6A),
      Color(0xFF2B2741),
    ],
    radiusSmall: 4,
    radiusContainer: 8,
    radiusControl: 8,
    radiusLarge: 12,
    density: 0.70,
    // An edge plus ambient darkness; heavy stacked shadows do not read here.
    shadowSm: [
      BoxShadow(color: Color(0xFF3F424D), spreadRadius: 1, blurRadius: 0),
    ],
    shadowMd: [
      BoxShadow(color: Color(0xFF595D6C), spreadRadius: 1, blurRadius: 0),
      BoxShadow(
        color: Color(0x8C000000),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
    ],
    shadowLg: [
      BoxShadow(color: Color(0xFF9397AB), spreadRadius: 1, blurRadius: 0),
      BoxShadow(
        color: Color(0xA6000000),
        blurRadius: 40,
        offset: Offset(0, 16),
      ),
    ],
    headingFamily: 'Inter',
    headingWeight: 500,
    bodyFamily: 'Inter',
    primaryButtonIsFilled: false,
    photoTreatment: PhotoTreatment.lightenOntoGround,
    cookModeGlow: true,
  );

  // ── Organic (light) ──────────────────────────────────────────────────────
  static const organic = AppTokens(
    ground: Color(0xFFF5EAD8),
    surface: Color(0xFFEBDDC5),
    chrome: Color(0xFFEBDDC5),
    titleBar: Color(0xFFE0D0B2),
    text: Color(0xFF201E1D),
    textSecondary: Color(0xFF645C50), // neutral-700
    textMuted: Color(0xFF82796A), // neutral-600
    textFaint: Color(0xFFA19786), // neutral-500
    accent: Color(0xFFC67139),
    accentText: Color(0xFF8C491A), // accent-700
    accentFill: Color(0xFFFFE1D0), // accent-200
    accent2: Color(0xFF7A8A5E), // sage
    accent2Text: Color(0xFF3D472B), // accent-2-800
    accent2Fill: Color(0xFFF0FAE1), // accent-2-100
    // The mirror image of Nocturne's: the ramps invert, so the tag fills and
    // their text swap ends.
    textStrong: Color(0xFF474238), // neutral-800 — darker than body
    tagAccentBg: Color(0xFFFFF2EB), // accent-100
    tagAccentFg: Color(0xFF643312), // accent-800
    tagAccent2Bg: Color(0xFFF0FAE1),
    tagAccent2Fg: Color(0xFF3D472B),
    tagNeutralBg: Color(0xFFF9F4ED), // neutral-100
    tagNeutralFg: Color(0xFF474238), // neutral-800
    toggleTrackOff: Color(0xFFC0B6A5),
    toggleKnob: Color(0xFFF9F4ED),
    neutral: [
      Color(0xFFF9F4ED),
      Color(0xFFEEE7DB),
      Color(0xFFDCD3C4),
      Color(0xFFC0B6A5),
      Color(0xFFA19786),
      Color(0xFF82796A),
      Color(0xFF645C50),
      Color(0xFF474238),
      Color(0xFF2E2B25),
    ],
    accentRamp: [
      Color(0xFFFFF2EB),
      Color(0xFFFFE1D0),
      Color(0xFFFFC6A5),
      Color(0xFFF6A06B),
      Color(0xFFD67F48),
      Color(0xFFB2622D),
      Color(0xFF8C491A),
      Color(0xFF643312),
      Color(0xFF402310),
    ],
    radiusSmall: 8,
    radiusContainer: 16,
    // Buttons, inputs and tags go full pill on Organic.
    radiusControl: 999,
    radiusLarge: 28,
    density: 1.10,
    // Soft ink-tinted shadows, derived from the ground.
    shadowSm: [
      BoxShadow(
        color: Color(0x242E2B25),
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x292E2B25),
        blurRadius: 10,
        offset: Offset(0, 3),
      ),
    ],
    shadowLg: [
      BoxShadow(
        color: Color(0x382E2B25),
        blurRadius: 32,
        offset: Offset(0, 12),
      ),
    ],
    // Baloo 2 rather than the design's Caprasimo: same warm, rounded display
    // voice, but it holds up at the 14.5–27px interface sizes the app actually
    // sets headings at. 600 carries the weight Caprasimo had without its bulk.
    headingFamily: 'Baloo2',
    headingWeight: 600,
    bodyFamily: 'Figtree',
    primaryButtonIsFilled: true,
    photoTreatment: PhotoTreatment.washed,
    cookModeGlow: false,
  );

  @override
  AppTokens copyWith({
    Color? ground,
    Color? surface,
    Color? chrome,
    Color? titleBar,
    Color? text,
    Color? textSecondary,
    Color? textMuted,
    Color? textFaint,
    Color? accent,
    Color? accentText,
    Color? accentFill,
    Color? accent2,
    Color? accent2Text,
    Color? accent2Fill,
    Color? textStrong,
    Color? tagAccentBg,
    Color? tagAccentFg,
    Color? tagAccent2Bg,
    Color? tagAccent2Fg,
    Color? tagNeutralBg,
    Color? tagNeutralFg,
    Color? toggleTrackOff,
    Color? toggleKnob,
    List<Color>? neutral,
    List<Color>? accentRamp,
    double? radiusSmall,
    double? radiusContainer,
    double? radiusControl,
    double? radiusLarge,
    double? density,
    List<BoxShadow>? shadowSm,
    List<BoxShadow>? shadowMd,
    List<BoxShadow>? shadowLg,
    String? headingFamily,
    double? headingWeight,
    String? bodyFamily,
    bool? primaryButtonIsFilled,
    PhotoTreatment? photoTreatment,
    bool? cookModeGlow,
  }) {
    return AppTokens(
      ground: ground ?? this.ground,
      surface: surface ?? this.surface,
      chrome: chrome ?? this.chrome,
      titleBar: titleBar ?? this.titleBar,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      accent: accent ?? this.accent,
      accentText: accentText ?? this.accentText,
      accentFill: accentFill ?? this.accentFill,
      accent2: accent2 ?? this.accent2,
      accent2Text: accent2Text ?? this.accent2Text,
      accent2Fill: accent2Fill ?? this.accent2Fill,
      textStrong: textStrong ?? this.textStrong,
      tagAccentBg: tagAccentBg ?? this.tagAccentBg,
      tagAccentFg: tagAccentFg ?? this.tagAccentFg,
      tagAccent2Bg: tagAccent2Bg ?? this.tagAccent2Bg,
      tagAccent2Fg: tagAccent2Fg ?? this.tagAccent2Fg,
      tagNeutralBg: tagNeutralBg ?? this.tagNeutralBg,
      tagNeutralFg: tagNeutralFg ?? this.tagNeutralFg,
      toggleTrackOff: toggleTrackOff ?? this.toggleTrackOff,
      toggleKnob: toggleKnob ?? this.toggleKnob,
      neutral: neutral ?? this.neutral,
      accentRamp: accentRamp ?? this.accentRamp,
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radiusContainer: radiusContainer ?? this.radiusContainer,
      radiusControl: radiusControl ?? this.radiusControl,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      density: density ?? this.density,
      shadowSm: shadowSm ?? this.shadowSm,
      shadowMd: shadowMd ?? this.shadowMd,
      shadowLg: shadowLg ?? this.shadowLg,
      headingFamily: headingFamily ?? this.headingFamily,
      headingWeight: headingWeight ?? this.headingWeight,
      bodyFamily: bodyFamily ?? this.bodyFamily,
      primaryButtonIsFilled:
          primaryButtonIsFilled ?? this.primaryButtonIsFilled,
      photoTreatment: photoTreatment ?? this.photoTreatment,
      cookModeGlow: cookModeGlow ?? this.cookModeGlow,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    List<Color> lerpRamp(List<Color> a, List<Color> b) => <Color>[
          for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!,
        ];
    // The two themes' shadow stacks have different lengths, so snap rather
    // than interpolate — a half-blended elevation reads as neither.
    List<BoxShadow> snapShadow(List<BoxShadow> a, List<BoxShadow> b) =>
        t < 0.5 ? a : b;

    return AppTokens(
      ground: Color.lerp(ground, other.ground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      chrome: Color.lerp(chrome, other.chrome, t)!,
      titleBar: Color.lerp(titleBar, other.titleBar, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      accentFill: Color.lerp(accentFill, other.accentFill, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accent2Text: Color.lerp(accent2Text, other.accent2Text, t)!,
      accent2Fill: Color.lerp(accent2Fill, other.accent2Fill, t)!,
      textStrong: Color.lerp(textStrong, other.textStrong, t)!,
      tagAccentBg: Color.lerp(tagAccentBg, other.tagAccentBg, t)!,
      tagAccentFg: Color.lerp(tagAccentFg, other.tagAccentFg, t)!,
      tagAccent2Bg: Color.lerp(tagAccent2Bg, other.tagAccent2Bg, t)!,
      tagAccent2Fg: Color.lerp(tagAccent2Fg, other.tagAccent2Fg, t)!,
      tagNeutralBg: Color.lerp(tagNeutralBg, other.tagNeutralBg, t)!,
      tagNeutralFg: Color.lerp(tagNeutralFg, other.tagNeutralFg, t)!,
      toggleTrackOff: Color.lerp(toggleTrackOff, other.toggleTrackOff, t)!,
      toggleKnob: Color.lerp(toggleKnob, other.toggleKnob, t)!,
      neutral: lerpRamp(neutral, other.neutral),
      accentRamp: lerpRamp(accentRamp, other.accentRamp),
      radiusSmall: lerpDouble(radiusSmall, other.radiusSmall, t),
      radiusContainer: lerpDouble(radiusContainer, other.radiusContainer, t),
      radiusControl: lerpDouble(radiusControl, other.radiusControl, t),
      radiusLarge: lerpDouble(radiusLarge, other.radiusLarge, t),
      density: lerpDouble(density, other.density, t),
      shadowSm: snapShadow(shadowSm, other.shadowSm),
      shadowMd: snapShadow(shadowMd, other.shadowMd),
      shadowLg: snapShadow(shadowLg, other.shadowLg),
      headingFamily: t < 0.5 ? headingFamily : other.headingFamily,
      headingWeight: lerpDouble(headingWeight, other.headingWeight, t),
      bodyFamily: t < 0.5 ? bodyFamily : other.bodyFamily,
      primaryButtonIsFilled:
          t < 0.5 ? primaryButtonIsFilled : other.primaryButtonIsFilled,
      photoTreatment: t < 0.5 ? photoTreatment : other.photoTreatment,
      cookModeGlow: t < 0.5 ? cookModeGlow : other.cookModeGlow,
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// `context.tokens` — the shorthand every widget in the app uses.
extension AppTokensContext on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}
