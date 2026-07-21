/// How the prebuilt walls look.
///
/// The defaults are deliberately plain — a neutral surface, your accent on the
/// one button, generous spacing — because these screens appear at the worst
/// possible moment and the last thing anyone wants is a branded interstitial
/// that looks like an ad. Override anything; the shape stays.
library;

import 'package:flutter/material.dart';

@immutable
class RsTheme {
  const RsTheme({
    required this.background,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.onAccent,
    this.logo,
    this.titleStyle,
    this.bodyStyle,
    this.buttonRadius = 999,
    this.maxContentWidth = 380,
  });

  final Color background;
  final Color foreground;
  final Color muted;
  final Color accent;
  final Color onAccent;

  /// Shown above the title. Keep it small; this is not a splash screen.
  final Widget? logo;

  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;
  final double buttonRadius;
  final double maxContentWidth;

  /// The pip beside "you" on the version ladder, and the wash behind a
  /// required update. Defaults to the accent so a themed wall stays coherent.
  Color get accentPip => const Color(0xFFFF453A);

  /// Reserved for the two screens that mean something has gone wrong.
  Color get dangerPip => const Color(0xFFFF453A);

  factory RsTheme.dark() => const RsTheme(
        background: Color(0xFF0B0B0D),
        foreground: Color(0xFFF2F2F3),
        muted: Color(0x9EF2F2F3),
        accent: Color(0xFFFFFFFF),
        onAccent: Color(0xFF0B0B0D),
      );

  factory RsTheme.light() => const RsTheme(
        background: Color(0xFFFFFFFF),
        foreground: Color(0xFF0B0B0D),
        muted: Color(0x8A0B0B0D),
        accent: Color(0xFF0B0B0D),
        onAccent: Color(0xFFFFFFFF),
      );

  /// Follows the surrounding app, which is usually what you want: the wall
  /// should feel like part of the product, not a visitation.
  static RsTheme of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RsTheme(
      background: scheme.surface,
      foreground: scheme.onSurface,
      muted: scheme.onSurface.withValues(alpha: 0.62),
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
    );
  }

  RsTheme copyWith({
    Color? background,
    Color? foreground,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Widget? logo,
    TextStyle? titleStyle,
    TextStyle? bodyStyle,
    double? buttonRadius,
    double? maxContentWidth,
  }) =>
      RsTheme(
        background: background ?? this.background,
        foreground: foreground ?? this.foreground,
        muted: muted ?? this.muted,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        logo: logo ?? this.logo,
        titleStyle: titleStyle ?? this.titleStyle,
        bodyStyle: bodyStyle ?? this.bodyStyle,
        buttonRadius: buttonRadius ?? this.buttonRadius,
        maxContentWidth: maxContentWidth ?? this.maxContentWidth,
      );
}
