// lib/utils/page_transitions.dart
import 'package:flutter/material.dart';

/// Enum to define transition directions
enum SlideDirection { up, down, left, right }

/// Custom page transitions for smooth navigation
class PageTransitions {
  /// Smooth vertical slide transition with both pages animating
  static PageRouteBuilder verticalSlide({
    required Widget page,
    required SlideDirection direction,
    Duration duration = const Duration(milliseconds: 350),
    Curve curve = Curves.easeInOutCubic,
  }) {
    assert(
      direction == SlideDirection.up || direction == SlideDirection.down,
      'Use SlideDirection.up or SlideDirection.down for vertical slides',
    );

    final bool isUp = direction == SlideDirection.up;

    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final incomingOffset = Tween<Offset>(
          begin: isUp ? const Offset(0.0, 1.0) : const Offset(0.0, -1.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: curve));

        final outgoingOffset = Tween<Offset>(
          begin: Offset.zero,
          end: isUp ? const Offset(0.0, -1.0) : const Offset(0.0, 1.0),
        ).animate(CurvedAnimation(parent: secondaryAnimation, curve: curve));

        final incomingOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: Interval(0.0, 0.6, curve: curve),
          ),
        );

        final outgoingOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: Interval(0.4, 1.0, curve: curve),
          ),
        );

        return Stack(
          children: [
            SlideTransition(
              position: outgoingOffset,
              child: FadeTransition(
                opacity: outgoingOpacity,
                child: Container(color: const Color(0xFF000000)),
              ),
            ),
            SlideTransition(
              position: incomingOffset,
              child: FadeTransition(opacity: incomingOpacity, child: child),
            ),
          ],
        );
      },
      transitionDuration: duration,
      reverseTransitionDuration: duration,
    );
  }

  /// Horizontal slide transition
  static PageRouteBuilder horizontalSlide({
    required Widget page,
    required SlideDirection direction,
    Duration duration = const Duration(milliseconds: 350),
    Curve curve = Curves.easeInOutCubic,
  }) {
    assert(
      direction == SlideDirection.left || direction == SlideDirection.right,
      'Use SlideDirection.left or SlideDirection.right for horizontal slides',
    );

    final bool isLeft = direction == SlideDirection.left;

    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final incomingOffset = Tween<Offset>(
          begin: isLeft ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: curve));

        final outgoingOffset = Tween<Offset>(
          begin: Offset.zero,
          end: isLeft ? const Offset(-1.0, 0.0) : const Offset(1.0, 0.0),
        ).animate(CurvedAnimation(parent: secondaryAnimation, curve: curve));

        return Stack(
          children: [
            SlideTransition(
              position: outgoingOffset,
              child: Container(color: const Color(0xFF000000)),
            ),
            SlideTransition(position: incomingOffset, child: child),
          ],
        );
      },
      transitionDuration: duration,
      reverseTransitionDuration: duration,
    );
  }

  /// Smooth fade transition
  static PageRouteBuilder fade({
    required Widget page,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOut,
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: curve),
          child: child,
        );
      },
      transitionDuration: duration,
    );
  }

  /// Scale transition with fade
  static PageRouteBuilder scale({
    required Widget page,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeInOutBack,
    double beginScale = 0.8,
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final scaleAnimation = Tween<double>(
          begin: beginScale,
          end: 1.0,
        ).animate(CurvedAnimation(parent: animation, curve: curve));

        final fadeAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeIn));

        return FadeTransition(
          opacity: fadeAnimation,
          child: ScaleTransition(scale: scaleAnimation, child: child),
        );
      },
      transitionDuration: duration,
    );
  }

  /// Optimized scale transition specifically for player pages
  static PageRouteBuilder playerScale({
    required Widget page,
    Duration duration = const Duration(milliseconds: 400),
    Curve curve = Curves.easeOutCubic,
    double beginScale = 0.92,
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final scaleAnimation = Tween<double>(
          begin: beginScale,
          end: 1.0,
        ).animate(CurvedAnimation(parent: animation, curve: curve));

        final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
          ),
        );

        return FadeTransition(
          opacity: fadeAnimation,
          child: ScaleTransition(scale: scaleAnimation, child: child),
        );
      },
      transitionDuration: duration,
      reverseTransitionDuration: const Duration(milliseconds: 350),
    );
  }

  /// Directional slide based on index comparison
  static PageRouteBuilder directionalSlide({
    required Widget page,
    required int currentIndex,
    required int targetIndex,
    Duration duration = const Duration(milliseconds: 350),
    Curve curve = Curves.easeInOutCubic,
  }) {
    final direction = targetIndex > currentIndex
        ? SlideDirection.up
        : SlideDirection.down;

    return verticalSlide(
      page: page,
      direction: direction,
      duration: duration,
      curve: curve,
    );
  }

  /// No transition - instant page change
  static PageRouteBuilder instant({required Widget page}) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: Duration.zero,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // DROP FALL 3D PARALLAX
  // Page drops in from above with a gravity bounce + perspective tilt.
  // The outgoing page shrinks away into the background (Z-depth feel).
  // On reverse (pop), the page rises back up and exits top.
  // ─────────────────────────────────────────────────────────────────────

  /// Drop fall with 3D parallax — page falls from above with depth
  ///
  /// Usage:
  /// ```dart
  /// Navigator.of(context).pushDropFall(MyPage());
  /// // or
  /// Navigator.push(context, PageTransitions.dropFall(page: MyPage()));
  /// ```
  static PageRouteBuilder dropFall({
    required Widget page,
    Duration duration = const Duration(milliseconds: 520),
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // ── Incoming: drop from above with overshoot bounce ──
        final dropCurve = CurvedAnimation(
          parent: animation,
          curve: const _GravityBounceCurve(),
        );

        // Y: starts -0.18 (above screen) → 0.0 (resting position)
        final slideIn = Tween<Offset>(
          begin: const Offset(0.0, -0.18),
          end: Offset.zero,
        ).animate(dropCurve);

        // Fade in quickly at start
        final fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
          ),
        );

        // Perspective tilt: slight X-axis rotation as it falls
        // Goes from ~3° tilt → 0° (flattens as it lands)
        final tiltIn = Tween<double>(begin: 0.04, end: 0.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
          ),
        );

        // Scale: starts slightly large (close to camera) → normal
        final scaleIn = Tween<double>(begin: 1.04, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
          ),
        );

        // ── Outgoing: shrinks back into depth (Z recession) ──
        final shrinkOut = Tween<double>(begin: 1.0, end: 0.88).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: Curves.easeInCubic,
          ),
        );

        final fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: const Interval(0.3, 1.0, curve: Curves.easeIn),
          ),
        );

        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            return Stack(
              children: [
                // Outgoing page — recedes into background
                AnimatedBuilder(
                  animation: secondaryAnimation,
                  builder: (context, outChild) {
                    return Transform.scale(
                      scale: shrinkOut.value,
                      child: FadeTransition(opacity: fadeOut, child: outChild),
                    );
                  },
                  child: Container(color: const Color(0xFF000000)),
                ),

                // Incoming page — falls from above with tilt + bounce
                SlideTransition(
                  position: slideIn,
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001) // perspective
                      ..rotateX(tiltIn.value), // X-axis tilt (forward lean)
                    child: ScaleTransition(
                      scale: scaleIn,
                      child: FadeTransition(opacity: fadeIn, child: child),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
      transitionDuration: duration,
      reverseTransitionDuration: const Duration(milliseconds: 400),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Custom gravity bounce curve
// Mimics a physical object falling with slight overshoot on landing
// ─────────────────────────────────────────────────────────────────────
class _GravityBounceCurve extends Curve {
  const _GravityBounceCurve();

  @override
  double transformInternal(double t) {
    // Accelerate quickly (gravity), then tiny bounce at end
    if (t < 0.75) {
      // Fast drop — cubic ease in
      return (t / 0.75) * (t / 0.75) * 0.97;
    } else {
      // Micro bounce settle
      final s = (t - 0.75) / 0.25; // 0..1 in settle phase
      return 0.97 + (0.03 * (1.0 - (1.0 - s) * (1.0 - s)));
    }
  }
}

/// Extension on Navigator for easier usage
extension NavigatorTransitionExtension on NavigatorState {
  /// Push with vertical slide
  Future<dynamic> pushVerticalSlide(
    Widget page, {
    SlideDirection direction = SlideDirection.up,
  }) {
    return push(
      PageTransitions.verticalSlide(page: page, direction: direction),
    );
  }

  /// Push replacement with vertical slide
  Future<dynamic> pushReplacementVerticalSlide(
    Widget page, {
    SlideDirection direction = SlideDirection.up,
    Object? result,
  }) {
    return pushReplacement(
      PageTransitions.verticalSlide(page: page, direction: direction),
      result: result,
    );
  }

  /// Push with fade
  Future<dynamic> pushFade(Widget page) {
    return push(PageTransitions.fade(page: page));
  }

  /// Push replacement with fade
  Future<dynamic> pushReplacementFade(Widget page, {Object? result}) {
    return pushReplacement(PageTransitions.fade(page: page), result: result);
  }

  /// Push with directional slide based on indices
  Future<dynamic> pushReplacementDirectional(
    Widget page, {
    required int currentIndex,
    required int targetIndex,
    Object? result,
  }) {
    return pushReplacement(
      PageTransitions.directionalSlide(
        page: page,
        currentIndex: currentIndex,
        targetIndex: targetIndex,
      ),
      result: result,
    );
  }

  /// Push with drop fall 3D parallax
  Future<dynamic> pushDropFall(Widget page) {
    return push(PageTransitions.dropFall(page: page));
  }

  /// Push replacement with drop fall 3D parallax
  Future<dynamic> pushReplacementDropFall(Widget page, {Object? result}) {
    return pushReplacement(
      PageTransitions.dropFall(page: page),
      result: result,
    );
  }
}
