// lib/utils/page_transitions.dart
import 'package:flutter/material.dart';

/// Enum to define transition directions
enum SlideDirection { up, down, left, right }

/// Custom page transitions for smooth navigation
class PageTransitions {
  /// Smooth vertical slide transition with both pages animating
  ///
  /// Usage:
  /// ```dart
  /// Navigator.pushReplacement(
  ///   context,
  ///   PageTransitions.verticalSlide(
  ///     page: NextPage(),
  ///     direction: SlideDirection.up,
  ///   ),
  /// );
  /// ```
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
        // Incoming page animation
        final incomingOffset = Tween<Offset>(
          begin: isUp ? const Offset(0.0, 1.0) : const Offset(0.0, -1.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: curve));

        // Outgoing page animation
        final outgoingOffset = Tween<Offset>(
          begin: Offset.zero,
          end: isUp ? const Offset(0.0, -1.0) : const Offset(0.0, 1.0),
        ).animate(CurvedAnimation(parent: secondaryAnimation, curve: curve));

        // Fade animations for smoother effect
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
            // Outgoing page
            SlideTransition(
              position: outgoingOffset,
              child: FadeTransition(
                opacity: outgoingOpacity,
                child: Container(color: const Color(0xFF000000)),
              ),
            ),
            // Incoming page
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
  ///
  /// Usage:
  /// ```dart
  /// Navigator.push(
  ///   context,
  ///   PageTransitions.horizontalSlide(
  ///     page: NextPage(),
  ///     direction: SlideDirection.left,
  ///   ),
  /// );
  /// ```
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
  ///
  /// Usage:
  /// ```dart
  /// Navigator.push(
  ///   context,
  ///   PageTransitions.fade(page: NextPage()),
  /// );
  /// ```
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
  ///
  /// Usage:
  /// ```dart
  /// Navigator.push(
  ///   context,
  ///   PageTransitions.scale(page: NextPage()),
  /// );
  /// ```
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
  /// Automatically determines direction (up/down) based on indices
  ///
  /// Usage:
  /// ```dart
  /// Navigator.pushReplacement(
  ///   context,
  ///   PageTransitions.directionalSlide(
  ///     page: NextPage(),
  ///     currentIndex: 0,
  ///     targetIndex: 3,
  ///   ),
  /// );
  /// ```
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
}
