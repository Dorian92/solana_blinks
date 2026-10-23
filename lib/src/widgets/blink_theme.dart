/// Colors and text styles for a blink card.
library;

import 'package:flutter/material.dart';

/// Visual style for a blink card.
class BlinkTheme {
  /// Creates a theme.
  const BlinkTheme({
    required this.background,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.error,
    required this.success,
    required this.radius,
    required this.title,
    required this.body,
    required this.label,
    required this.caption,
  });

  /// Builds a theme from [theme]'s color scheme and text styles.
  factory BlinkTheme.fromMaterial(ThemeData theme) {
    final scheme = theme.colorScheme;
    return BlinkTheme(
      background: scheme.surface,
      foreground: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      error: scheme.error,
      success: scheme.tertiary,
      radius: 16,
      title:
          theme.textTheme.titleLarge ??
          const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      body: theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 14),
      label:
          theme.textTheme.labelLarge ??
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      caption: theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12),
    );
  }

  /// Card background.
  final Color background;

  /// Primary text color.
  final Color foreground;

  /// Secondary text color, used for the description and domain.
  final Color muted;

  /// Button and focus color.
  final Color accent;

  /// Text and icons drawn on [accent].
  final Color onAccent;

  /// Error text and borders.
  final Color error;

  /// Success accent.
  final Color success;

  /// Corner radius of the card and its buttons.
  final double radius;

  /// Action title style.
  final TextStyle title;

  /// Description style.
  final TextStyle body;

  /// Button and field label style.
  final TextStyle label;

  /// Domain, hints, and signature style.
  final TextStyle caption;

  /// Returns a copy with the given fields replaced.
  BlinkTheme copyWith({
    Color? background,
    Color? foreground,
    Color? muted,
    Color? accent,
    Color? onAccent,
    Color? error,
    Color? success,
    double? radius,
    TextStyle? title,
    TextStyle? body,
    TextStyle? label,
    TextStyle? caption,
  }) {
    return BlinkTheme(
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      error: error ?? this.error,
      success: success ?? this.success,
      radius: radius ?? this.radius,
      title: title ?? this.title,
      body: body ?? this.body,
      label: label ?? this.label,
      caption: caption ?? this.caption,
    );
  }
}
