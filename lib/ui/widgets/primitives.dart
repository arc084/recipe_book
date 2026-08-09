import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Tags
// ═══════════════════════════════════════════════════════════════════════════

enum TagStyle { accent, accent2, neutral, outline }

/// The design's `.tag` — 11px, tight padding, radius from the theme so it goes
/// pill on Organic and 6px on Nocturne.
class Tag extends StatelessWidget {
  const Tag(
    this.label, {
    super.key,
    this.style = TagStyle.neutral,
    this.trailing,
    this.onTap,
    this.dense = false,
  });

  final String label;
  final TagStyle style;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    final (Color bg, Color fg, Border? border) = switch (style) {
      TagStyle.accent => (t.tagAccentBg, t.tagAccentFg, null),
      TagStyle.accent2 => (t.tagAccent2Bg, t.tagAccent2Fg, null),
      TagStyle.neutral => (t.tagNeutralBg, t.tagNeutralFg, null),
      TagStyle.outline => (
          Colors.transparent,
          t.accent,
          Border.fromBorderSide(BorderSide(color: t.accent)),
        ),
    };

    // `.tag` sits at 0.75 of the control radius on Nocturne; on Organic it is
    // a full pill like every other small control.
    final radius = t.radiusControl > 100 ? 999.0 : t.radiusControl * 0.75;

    final child = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        border: border,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: fg, letterSpacing: 0.02 * 11, height: 1.35),
          ),
          if (trailing != null) ...[const SizedBox(width: 5), trailing!],
        ],
      ),
    );

    if (onTap == null) return child;
    return _Hoverable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Buttons
// ═══════════════════════════════════════════════════════════════════════════

enum ButtonKind { primary, secondary, ghost }

/// One button widget, two theme personalities.
///
/// Nocturne's primary is a 1px accent outline on transparent; Organic's is a
/// solid accent fill with ground-coloured text. That is a per-theme
/// [ButtonStyle], not a palette lookup, so it is decided here.
class AppButton extends StatefulWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = ButtonKind.secondary,
    this.icon,
    this.fontSize = 12.5,
    this.height,
  });

  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final IconData? icon;
  final double fontSize;
  final double? height;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = widget.onPressed != null;

    Color bg = Colors.transparent;
    Color fg = t.text;
    BoxBorder? border;

    switch (widget.kind) {
      case ButtonKind.primary:
        if (t.primaryButtonIsFilled) {
          bg = _down
              ? t.accentRamp[6]
              : _hover
                  ? t.accentRamp[5]
                  : t.accent;
          fg = t.ground;
        } else {
          fg = t.accent;
          border = Border.fromBorderSide(BorderSide(color: t.accent));
          bg = _down
              ? t.accent.withValues(alpha: 0.22)
              : _hover
                  ? t.accent.withValues(alpha: 0.12)
                  : Colors.transparent;
        }
      case ButtonKind.secondary:
        border = Border.fromBorderSide(BorderSide(color: t.divider));
        bg = _down
            ? t.text.withValues(alpha: 0.14)
            : _hover
                ? t.text.withValues(alpha: 0.07)
                : Colors.transparent;
      case ButtonKind.ghost:
        fg = t.accent;
        bg = _down
            ? t.accent.withValues(alpha: 0.18)
            : _hover
                ? t.accent.withValues(alpha: 0.10)
                : Colors.transparent;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: widget.height ?? 32,
            padding: EdgeInsets.symmetric(horizontal: t.space(3) * 1.2),
            decoration: BoxDecoration(
              color: bg,
              border: border,
              borderRadius: t.brControl,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 15, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontFamily: t.headingFamily,
                    fontSize: widget.fontSize,
                    height: 1.2,
                    color: fg,
                    fontVariations: [FontVariation('wght', t.headingWeight)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A square icon button — the `.btn-icon` in the design.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 32,
    this.iconSize = 16,
    this.tooltip,
    this.bordered = true,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;
  final bool bordered;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final button = _Hoverable(
      onTap: onPressed,
      borderRadius: t.brControl,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: bordered
              ? Border.fromBorderSide(BorderSide(color: t.divider))
              : null,
          borderRadius: t.brControl,
        ),
        child: Icon(icon, size: iconSize, color: color ?? t.textSecondary),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Hover tint + click plumbing, shared by everything that reacts to a pointer.
class _Hoverable extends StatefulWidget {
  const _Hoverable({
    required this.child,
    this.onTap,
    this.borderRadius,
    this.hoverOpacity = 0.07,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final double hoverOpacity;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _hover
                ? t.text.withValues(alpha: widget.hoverOpacity)
                : Colors.transparent,
            borderRadius: widget.borderRadius,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Public wrapper so screens can reuse the same hover behaviour on rows.
class HoverRow extends StatelessWidget {
  const HoverRow({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) => _Hoverable(
        onTap: onTap,
        borderRadius: borderRadius,
        hoverOpacity: 0.04,
        child: child,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// Text and labels
// ═══════════════════════════════════════════════════════════════════════════

/// The design's `h6` — 10–11px, uppercase, wide tracking.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color, this.size = 11});

  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: t.headingFamily,
        fontSize: size,
        letterSpacing: 0.08 * size,
        height: 1.2,
        color: color ?? t.textSecondary,
        fontVariations: [FontVariation('wght', t.headingWeight)],
      ),
    );
  }
}

/// A search / text input matching the design's `.input`.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.hint,
    this.icon,
    this.onChanged,
    this.onSubmitted,
    this.height = 36,
    this.fontSize = 13,
    this.autofocus = false,
    this.focusNode,
    this.filled = true,
    this.keyboardType,
    this.textAlign = TextAlign.start,
  });

  final TextEditingController? controller;
  final String? hint;
  final IconData? icon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final double height;
  final double fontSize;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool filled;
  final TextInputType? keyboardType;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        keyboardType: keyboardType,
        textAlign: textAlign,
        cursorColor: t.accent,
        cursorWidth: 1.5,
        style: TextStyle(
          fontFamily: t.bodyFamily,
          fontSize: fontSize,
          color: t.text,
          height: 1.2,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: filled,
          fillColor: filled ? t.surface : Colors.transparent,
          hintText: hint,
          hintStyle: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: fontSize,
            color: t.textFaint,
            height: 1.2,
          ),
          prefixIcon: icon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(left: 11, right: 7),
                  child: Icon(icon, size: 16, color: t.textMuted),
                ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          contentPadding: EdgeInsets.symmetric(
            horizontal: t.radiusControl > 100 ? 14 : 10,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: t.brControl,
            borderSide: BorderSide(color: t.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: t.brControl,
            borderSide: BorderSide(color: t.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: t.brControl,
            borderSide: BorderSide(color: t.accent),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Surfaces
// ═══════════════════════════════════════════════════════════════════════════

/// A surface panel carrying the theme's own container radius and elevation.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding,
    this.elevation = PanelElevation.sm,
    this.color,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final PanelElevation elevation;
  final Color? color;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shadows = switch (elevation) {
      PanelElevation.none => const <BoxShadow>[],
      PanelElevation.sm => t.shadowSm,
      PanelElevation.md => t.shadowMd,
      PanelElevation.lg => t.shadowLg,
    };
    return Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color ?? t.surface,
        borderRadius: t.brContainer,
        boxShadow: shadows,
      ),
      child: child,
    );
  }
}

enum PanelElevation { none, sm, md, lg }

/// The divided figure strip used on the recipe header and the pantry item —
/// value above, label below, hairline between cells.
class StatStrip extends StatelessWidget {
  const StatStrip({
    super.key,
    required this.cells,
    this.valueSize = 14,
    this.labelSize = 10,
    this.padding = 11,
  });

  final List<({String value, String label})> cells;
  final double valueSize;
  final double labelSize;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Panel(
      child: SizedBox(
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0) Container(width: 1, height: 34, color: t.divider),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: padding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cells[i].value,
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: valueSize,
                          color: t.text,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cells[i].label,
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: labelSize,
                          color: t.textMuted,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Photographs
// ═══════════════════════════════════════════════════════════════════════════

/// A recipe photograph, or the placeholder that stands in for one.
///
/// No stock imagery is ever substituted — where a recipe has no photo the
/// user sees a drop target saying so. The two themes treat a real photograph
/// differently: Nocturne blends it with the ground so dark backgrounds fall
/// away, Organic washes it so it sits back into the cream.
class RecipePhoto extends StatelessWidget {
  const RecipePhoto({
    super.key,
    required this.path,
    required this.placeholder,
    this.fit = BoxFit.cover,
    this.hovering = false,
  });

  final String? path;
  final String placeholder;
  final BoxFit fit;

  /// True while a file is being dragged over the slot.
  final bool hovering;

  /// saturate(.6) contrast(.85) brightness(1.1), pre-multiplied into one
  /// matrix. CSS applies those left to right, so the scale is 0.85 × 1.1 and
  /// the offset is the contrast pivot carried through the brightness step.
  static const _washed = <double>[
    0.64051, 0.26749, 0.02700, 0, 21.04, //
    0.07951, 0.82849, 0.02700, 0, 21.04, //
    0.07951, 0.26749, 0.58800, 0, 21.04, //
    0, 0, 0, 1, 0, //
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    if (path == null || !File(path!).existsSync()) {
      return _Placeholder(text: placeholder, hovering: hovering);
    }

    return LayoutBuilder(
      builder: (context, constraints) => _paint(
        context,
        t,
        _decoded(context, constraints),
      ),
    );
  }

  /// The photograph, decoded no larger than the box it is drawn into.
  ///
  /// Photos come from the user's camera, so a 12-megapixel file filling a
  /// 104px card is normal. Decoding that at source size costs ~48 MB of bitmap
  /// per image, and a gridful will exhaust the texture memory Impeller has to
  /// play with — on device that shows up not as an exception but as a frame
  /// that never paints, leaving the previous surface on screen. Sizing the
  /// decode to the layout keeps it to what is actually drawn.
  Widget _decoded(BuildContext context, BoxConstraints constraints) {
    final ratio = MediaQuery.devicePixelRatioOf(context);

    int? cap(double extent) {
      if (!extent.isFinite || extent <= 0) return null;
      return (extent * ratio).round();
    }

    return Image.file(
      File(path!),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: cap(constraints.maxWidth),
      cacheHeight: cap(constraints.maxHeight),
      // Downscaling by this much needs better than nearest-neighbour.
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) =>
          _Placeholder(text: placeholder, hovering: hovering),
    );
  }

  Widget _paint(BuildContext context, AppTokens t, Widget image) {
    // Both treatments wrap the photo in a layer, and a layer is not bound by
    // the widget's own box: Nocturne's `lighten` against the ground turns
    // every transparent pixel in that layer into solid ground, so the filter
    // paints across whatever bounds the layer ends up with. Where an ancestor
    // already clips — the Library card's rounded container — that goes
    // unnoticed; where nothing does, the photo paints straight over the
    // content beneath it until it scrolls out of view. Clipping here makes the
    // slot the limit, wherever the photo is used.
    return ClipRect(child: _treated(context, t, image));
  }

  Widget _treated(BuildContext context, AppTokens t, Widget image) {
    return switch (t.photoTreatment) {
      PhotoTreatment.lightenOntoGround => ColorFiltered(
          colorFilter: ColorFilter.mode(t.ground, BlendMode.lighten),
          child: image,
        ),
      PhotoTreatment.washed => Opacity(
          opacity: 0.94,
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(_washed),
            child: image,
          ),
        ),
    };
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text, required this.hovering});

  final String text;
  final bool hovering;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hovering
            ? t.accent.withValues(alpha: 0.12)
            : t.text.withValues(alpha: 0.04),
        border: hovering
            ? Border.fromBorderSide(
                BorderSide(color: t.accent, width: 1.5),
              )
            : null,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                size: 20,
                color: hovering ? t.accent : t.textFaint,
              ),
              const SizedBox(height: 6),
              Text(
                text,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 10.5,
                  height: 1.3,
                  color: hovering ? t.accent : t.textFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
