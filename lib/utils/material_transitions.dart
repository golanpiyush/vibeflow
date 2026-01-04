// ============================================================================
// lib/utils/material_transitions.dart
// Reusable Material Motion transitions following Google's guidelines
// ============================================================================

import 'package:flutter/material.dart';

/// Material Motion transition types
enum MaterialMotionType {
  sharedAxisVertical,
  sharedAxisHorizontal,
  fadeThrough,
  fade,
  scaleUp,
}

/// Reusable Material Motion transitions with parallax support
class MaterialTransitions {
  /// Shared Axis transition (Vertical) - Material Design recommended
  /// Used for hierarchical navigation (list -> detail)
  static PageRouteBuilder sharedAxisVertical({
    required Widget page,
    bool slideUp = true,
    Duration duration = const Duration(milliseconds: 600),
  }) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: duration,
      reverseTransitionDuration: const Duration(milliseconds: 500),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curve = Curves.fastOutSlowIn;

        final offset = Tween<Offset>(
          begin: slideUp ? const Offset(0, 0.18) : const Offset(0, -0.18),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: curve));

        final fade = Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
          ),
        );

        return SlideTransition(
          position: offset,
          child: FadeTransition(opacity: fade, child: child),
        );
      },
    );
  }

  /// Shared Axis Horizontal - for peer navigation
  static PageRouteBuilder sharedAxisHorizontal({
    required Widget page,
    bool fromRight = true,
    Duration duration = const Duration(milliseconds: 400),
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slideAnimation =
            Tween<Offset>(
              begin: fromRight ? const Offset(0.3, 0) : const Offset(-0.3, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.fastOutSlowIn),
            );

        final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
          ),
        );

        return SlideTransition(
          position: slideAnimation,
          child: FadeTransition(opacity: fadeAnimation, child: child),
        );
      },
    );
  }

  /// Fade Through - for switching between tabs/views
  static PageRouteBuilder fadeThrough({
    required Widget page,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
          ),
        );

        final fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.35, 1.0, curve: Curves.easeIn),
          ),
        );

        final scaleOut = Tween<double>(begin: 1.0, end: 0.92).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
          ),
        );

        return Stack(
          children: [
            ScaleTransition(
              scale: scaleOut,
              child: FadeTransition(
                opacity: fadeOut,
                child: Container(color: Colors.black),
              ),
            ),
            FadeTransition(opacity: fadeIn, child: child),
          ],
        );
      },
    );
  }

  /// Simple fade for quick transitions
  static PageRouteBuilder fade({
    required Widget page,
    Duration duration = const Duration(milliseconds: 250),
  }) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        );
      },
    );
  }
}

/// Navigator extension for easy usage
extension MaterialNavigatorExtension on NavigatorState {
  Future<T?> pushMaterialVertical<T>(
    Widget page, {
    bool slideUp = true,
    bool enableParallax = false,
  }) {
    return push<T>(
      MaterialTransitions.sharedAxisVertical(page: page, slideUp: slideUp)
          as Route<T>,
    );
  }

  Future<T?> pushMaterialHorizontal<T>(Widget page, {bool fromRight = true}) {
    return push<T>(
      MaterialTransitions.sharedAxisHorizontal(page: page, fromRight: fromRight)
          as Route<T>,
    );
  }

  Future<T?> pushMaterialFade<T>(Widget page) {
    return push<T>(MaterialTransitions.fade(page: page) as Route<T>);
  }

  Future<T?> pushMaterialFadeThrough<T>(Widget page) {
    return push<T>(MaterialTransitions.fadeThrough(page: page) as Route<T>);
  }
}
