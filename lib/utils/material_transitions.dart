// ============================================================================
// lib/utils/material_transitions.dart - UPDATED WITH PUSH REPLACEMENT METHODS
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
  /// Shared Axis transition (Vertical)
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

  /// Simple fade
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

  // ─────────────────────────────────────────────────────────────────
  // viMusic-style sidebar navigation transition
  //
  // Behaviour observed in video:
  //  • Content area slides horizontally (new page comes from right/left)
  //  • Title slides in from the opposite side with a slight overshoot
  //  • Active sidebar label gets a pill highlight that animates in
  //  • Page fades in over a very short interval (snappy, not slow)
  // ─────────────────────────────────────────────────────────────────

  /// Sidebar nav transition — horizontal slide with title pop-in
  /// [forward] = true  → new page comes from right (going deeper/forward)
  /// [forward] = false → new page comes from left  (going back)
  static PageRouteBuilder sidebarNav({
    required Widget page,
    bool forward = true,
    Duration duration = const Duration(milliseconds: 380),
  }) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: duration,
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const curve = Curves.fastOutSlowIn;

        // Incoming content slides from right (forward) or left (back)
        final slideIn = Tween<Offset>(
          begin: forward ? const Offset(0.08, 0) : const Offset(-0.08, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: curve));

        // Outgoing content slides out opposite direction
        final slideOut = Tween<Offset>(
          begin: Offset.zero,
          end: forward ? const Offset(-0.06, 0) : const Offset(0.06, 0),
        ).animate(CurvedAnimation(parent: secondaryAnimation, curve: curve));

        // Incoming fades in quickly
        final fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
          ),
        );

        // Outgoing fades out
        final fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: const Interval(0.1, 0.6, curve: Curves.easeIn),
          ),
        );

        return Stack(
          children: [
            // Outgoing page
            SlideTransition(
              position: slideOut,
              child: FadeTransition(opacity: fadeOut, child: Container()),
            ),
            // Incoming page
            SlideTransition(
              position: slideIn,
              child: FadeTransition(opacity: fadeIn, child: child),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ViMusic-style Sidebar Nav Rail Widget
//
// Drop-in replacement for your rotated-text sidebar.
// Shows vertical labels. Active item gets a rounded pill highlight.
// On tap — the label animates (scale pop) and calls onTap.
// ─────────────────────────────────────────────────────────────────────────────

class ViMusicSidebarItem {
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  const ViMusicSidebarItem({
    required this.label,
    this.onTap,
    this.isActive = false,
  });
}

class ViMusicSidebarNavRail extends StatelessWidget {
  final List<ViMusicSidebarItem> items;
  final Color activeColor;
  final Color inactiveColor;
  final Color pillColor;
  final double width;
  final double itemSpacing;
  final double fontSize;

  const ViMusicSidebarNavRail({
    Key? key,
    required this.items,
    required this.activeColor,
    required this.inactiveColor,
    required this.pillColor,
    this.width = 62,
    this.itemSpacing = 24,
    this.fontSize = 14,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: items.map((item) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: itemSpacing / 2),
            child: _SidebarNavItem(
              item: item,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              pillColor: pillColor,
              width: width,
              fontSize: fontSize,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  final ViMusicSidebarItem item;
  final Color activeColor;
  final Color inactiveColor;
  final Color pillColor;
  final double width;
  final double fontSize;

  const _SidebarNavItem({
    required this.item,
    required this.activeColor,
    required this.inactiveColor,
    required this.pillColor,
    required this.width,
    required this.fontSize,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _pillAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    // Scale pop on tap
    _scaleAnim = TweenSequence([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.88,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.88,
          end: 1.05,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.05,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25,
      ),
    ]).animate(_controller);

    // Pill fade in when active
    _pillAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    if (widget.item.isActive) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_SidebarNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.isActive && !oldWidget.item.isActive) {
      _controller.forward(from: 0.0);
    } else if (!widget.item.isActive && oldWidget.item.isActive) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _controller.forward(from: 0.0);
        widget.item.onTap?.call();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: Container(
              width: widget.width,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: BoxDecoration(
                // Pill highlight for active item
                color: widget.item.isActive
                    ? widget.pillColor.withOpacity(0.15 * _pillAnim.value)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: RotatedBox(
                quarterTurns: -1,
                child: Text(
                  widget.item.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    fontWeight: widget.item.isActive
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: widget.item.isActive
                        ? widget.activeColor
                        : widget.inactiveColor,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                ),
              ),
            ),
          );
        },
      ),
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

  Future<T?>
  pushReplacementMaterialVertical<T extends Object?, TO extends Object?>(
    Widget page, {
    bool slideUp = true,
    bool enableParallax = false,
    TO? result,
  }) {
    return pushReplacement<T, TO>(
      MaterialTransitions.sharedAxisVertical(page: page, slideUp: slideUp)
          as Route<T>,
      result: result,
    );
  }

  Future<T?> pushMaterialHorizontal<T>(Widget page, {bool fromRight = true}) {
    return push<T>(
      MaterialTransitions.sharedAxisHorizontal(page: page, fromRight: fromRight)
          as Route<T>,
    );
  }

  Future<T?> pushReplacementMaterialHorizontal<
    T extends Object?,
    TO extends Object?
  >(Widget page, {bool fromRight = true, TO? result}) {
    return pushReplacement<T, TO>(
      MaterialTransitions.sharedAxisHorizontal(page: page, fromRight: fromRight)
          as Route<T>,
      result: result,
    );
  }

  Future<T?> pushMaterialFade<T>(Widget page) {
    return push<T>(MaterialTransitions.fade(page: page) as Route<T>);
  }

  Future<T?> pushReplacementMaterialFade<T extends Object?, TO extends Object?>(
    Widget page, {
    TO? result,
  }) {
    return pushReplacement<T, TO>(
      MaterialTransitions.fade(page: page) as Route<T>,
      result: result,
    );
  }

  Future<T?> pushMaterialFadeThrough<T>(Widget page) {
    return push<T>(MaterialTransitions.fadeThrough(page: page) as Route<T>);
  }

  Future<T?> pushReplacementMaterialFadeThrough<
    T extends Object?,
    TO extends Object?
  >(Widget page, {TO? result}) {
    return pushReplacement<T, TO>(
      MaterialTransitions.fadeThrough(page: page) as Route<T>,
      result: result,
    );
  }

  /// Push with viMusic sidebar nav transition
  Future<T?> pushSidebarNav<T>(Widget page, {bool forward = true}) {
    return push<T>(
      MaterialTransitions.sidebarNav(page: page, forward: forward) as Route<T>,
    );
  }

  Future<T?> pushReplacementSidebarNav<T extends Object?, TO extends Object?>(
    Widget page, {
    bool forward = true,
    TO? result,
  }) {
    return pushReplacement<T, TO>(
      MaterialTransitions.sidebarNav(page: page, forward: forward) as Route<T>,
      result: result,
    );
  }
}
