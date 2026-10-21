import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/land_service.dart';

/// Calm dark slate + liquid glass. Burgundy glow only on primary/active.
class C {
  static const bg = Color(0xFF12171D);
  static const bg2 = Color(0xFF1B232C);
  static const slate = Color(0xFF24303B);
  static const text = Color(0xFFF2F4F5);
  static const text2 = Color(0xFFB9C3CB);
  static const text3 = Color(0xFF8A96A0);
  static const burgundy = Color(0xFF7A1F2B);
  static const burgundyHi = Color(0xFFA33445);
  static const sage = Color(0xFF8FC79A);
  static const sageDeep = Color(0xFF5E9A6B);
  static const rose = Color(0xFFC98A8F);
  static const amber = Color(0xFFE0A84F);
  static const red = Color(0xFFE0605A);
  static const trail = Color(0xFFF0A05A);

  static Color status(ShootStatus s) => switch (s) {
        ShootStatus.allowed => sage,
        ShootStatus.restricted => amber,
        ShootStatus.check => amber,
        ShootStatus.prohibited => red,
        ShootStatus.unknown => red,
      };
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.burgundyHi,
      secondary: C.sage,
      surface: C.bg2,
      onSurface: C.text,
      error: C.red,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: C.text, displayColor: C.text)
        .copyWith(
          bodyMedium: const TextStyle(fontSize: 17, height: 1.35, color: C.text),
          bodyLarge: const TextStyle(fontSize: 18, height: 1.35, color: C.text),
          bodySmall: const TextStyle(fontSize: 15, color: C.text2),
          titleLarge: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: C.text),
          titleMedium: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: C.text),
          labelLarge: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      hintStyle: const TextStyle(color: C.text3, fontSize: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: C.burgundyHi, width: 1.5)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.sageDeep : Colors.transparent),
      side: const BorderSide(color: C.text3, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: C.slate,
      contentTextStyle: TextStyle(color: C.text, fontSize: 16),
      behavior: SnackBarBehavior.floating,
    ),
    dividerColor: Colors.white12,
  );
}

/// Frosted translucent panel with a soft rim highlight.
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final double opacity;
  final Color? tint;
  final VoidCallback? onTap;
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.blur = 18,
    this.opacity = 0.10,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    Widget inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (tint ?? Colors.white).withValues(alpha: opacity + 0.05),
            (tint ?? Colors.white).withValues(alpha: opacity * 0.5),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Stack(children: [
        child,
      ]),
    );
    if (onTap != null) {
      inner = Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: r, onTap: onTap, child: inner),
      );
    }
    // Real-time blur over the native map view is very slow on Android; use a solid frosted tint there.
    if (!kIsWeb) {
      return ClipRRect(
        borderRadius: r,
        child: DecoratedBox(
          decoration: BoxDecoration(color: C.bg.withValues(alpha: 0.80), borderRadius: r),
          child: inner,
        ),
      );
    }
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: inner),
    );
  }
}

/// Burgundy-glow primary pill button.
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  const PrimaryButton(this.label, {super.key, this.icon, this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [BoxShadow(color: C.burgundy.withValues(alpha: 0.65), blurRadius: 22, spreadRadius: 1)],
          gradient: const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.burgundyHi, C.burgundy]),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (busy)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                else if (icon != null)
                  Icon(icon, size: 22, color: Colors.white),
                if (icon != null || busy) const SizedBox(width: 10),
                Flexible(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary glass pill button.
class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;
  const GlassButton(this.label, {super.key, this.icon, this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 30,
      padding: EdgeInsets.zero,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) Icon(icon, size: 21, color: color ?? C.text),
          if (icon != null) const SizedBox(width: 8),
          Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color ?? C.text))),
        ]),
      ),
    );
  }
}

/// Very rounded segmented control; the active segment glows burgundy.
class PillSegments extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final Color? activeColor;
  const PillSegments({super.key, required this.labels, required this.index, required this.onChanged, this.activeColor});

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 30,
      padding: const EdgeInsets.all(4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < labels.length; i++)
          Flexible(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: i == index
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        color: (activeColor ?? C.burgundy).withValues(alpha: 0.55),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        boxShadow: [
                          BoxShadow(color: (activeColor ?? C.burgundy).withValues(alpha: 0.6), blurRadius: 14)
                        ],
                      )
                    : null,
                child: Text(labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                        color: i == index ? Colors.white : C.text2)),
              ),
            ),
          ),
      ]),
    );
  }
}

class StatusDot extends StatelessWidget {
  final Color color;
  final double size;
  const StatusDot(this.color, {super.key, this.size = 12});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)],
        ),
      );
}

class Chip2 extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Chip2(this.text, {super.key, this.color = C.text2, this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: color.withValues(alpha: 0.14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Icon(icon, size: 16, color: color),
          if (icon != null) const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
          ?trailing,
        ]),
      );
}

/// Ambient background: soft sage and rose blobs evoking the map, behind glass.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  const AmbientBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.bg2, C.bg]),
          ),
        ),
      ),
      Positioned(top: 160, left: -80, child: _blob(C.sageDeep, 300)),
      Positioned(top: 420, right: -120, child: _blob(C.sage, 340)),
      Positioned(top: 260, right: 40, child: _blob(C.rose, 160)),
      Positioned(bottom: -60, left: 20, child: _blob(C.sageDeep, 260)),
      Positioned.fill(child: child),
    ]);
  }

  Widget _blob(Color c, double s) => IgnorePointer(
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c.withValues(alpha: 0.30), c.withValues(alpha: 0.0)]),
          ),
        ),
      );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Bottom sheet styled as glass.
Future<T?> showGlassSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black38,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
        child: Glass(
          radius: 30,
          opacity: 0.16,
          tint: const Color(0xFF2A3540),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 44, height: 5, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(3))),
            const SizedBox(height: 12),
            Flexible(child: builder(ctx)),
          ]),
        ),
      ),
    ),
  );
}
