import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Brand purples for gradients and glows (keeps dark + purple scheme).
const Color kBrandPurpleLight = Color(0xFFB8AEFF);
const Color kBrandPurpleMid = Color(0xFF6D5EF5);
const Color kBrandPurpleDeep = Color(0xFF4A3AB8);
const Color kAccentMint = Color(0xFF3AE4C2);

EdgeInsets groceryPagePadding(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  final h = w >= 600 ? 28.0 : 18.0;
  return EdgeInsets.symmetric(horizontal: h);
}

double groceryMaxContentWidth(BuildContext context) => 560;

/// Soft vertical gradient behind scrollable content (grocery-app “aisle lighting”).
class GroceryAmbientBackdrop extends StatelessWidget {
  const GroceryAmbientBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kBrandPurpleDeep.withValues(alpha: 0.35),
                kBrandCanvas,
                const Color(0xFF0D0C1F),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        CustomPaint(
          painter: _SoftGridPainter(
            color: Colors.white.withValues(alpha: 0.03),
          ),
          child: const SizedBox.expand(),
        ),
        child,
      ],
    );
  }
}

class _SoftGridPainter extends CustomPainter {
  _SoftGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Glowing gradient progress (0–1). Used on list cards and detail header.
class GroceryProgressBar extends StatelessWidget {
  const GroceryProgressBar({
    super.key,
    required this.value,
    this.height = 12,
    this.semanticsLabel,
  });

  final double value;
  final double height;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticsLabel,
      value: '${(v * 100).round()}%',
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            height: height + 6,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: height,
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(height / 2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  height: height,
                  width: (constraints.maxWidth * v).clamp(0.0, constraints.maxWidth),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(height / 2),
                    gradient: const LinearGradient(
                      colors: [
                        kBrandPurpleLight,
                        kBrandPurpleMid,
                        kBrandPurpleDeep,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kBrandPurpleMid.withValues(alpha: 0.55),
                        blurRadius: 14,
                        spreadRadius: -2,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Header avatar: rounded “tile” with person glyph + glow (profile / grocery identity).
class GroceryProfilePersonBadge extends StatelessWidget {
  const GroceryProfilePersonBadge({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    final r = size * 0.28;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kBrandPurpleLight.withValues(alpha: 0.95),
            kBrandPurpleMid,
            kBrandPurpleDeep,
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: kBrandPurpleMid.withValues(alpha: 0.55),
            blurRadius: 22,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        Icons.person_rounded,
        size: size * 0.52,
        color: Colors.white,
        semanticLabel: 'Profile',
      ),
    );
  }
}

/// Primary CTA with outer glow (Save, Create account, etc.).
class GroceryGlowButton extends StatelessWidget {
  const GroceryGlowButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: disabled
            ? []
            : [
                BoxShadow(
                  color: kBrandPurpleMid.withValues(alpha: 0.45),
                  blurRadius: 22,
                  spreadRadius: -2,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Polished list card shell (used on dashboard list tiles).
class GroceryListCardShell extends StatelessWidget {
  const GroceryListCardShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF252344).withValues(alpha: 0.95),
            const Color(0xFF1A1D2E),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: kBrandPurpleMid.withValues(alpha: 0.12),
            blurRadius: 24,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: child,
      ),
    );
  }
}
