// // lib/widgets/animated_sidebar.dart
// import 'package:flutter/material.dart';
// import 'package:vibeflow/constants/app_typography.dart';

// class AnimatedSidebarItem extends StatefulWidget {
//   final IconData? icon;
//   final String label;
//   final bool isActive;
//   final Color iconActiveColor;
//   final Color iconInactiveColor;
//   final Color labelColor;
//   final Color labelActiveColor;
//   final VoidCallback? onTap;

//   const AnimatedSidebarItem({
//     Key? key,
//     this.icon,
//     required this.label,
//     required this.isActive,
//     required this.iconActiveColor,
//     required this.iconInactiveColor,
//     required this.labelColor,
//     required this.labelActiveColor,
//     this.onTap,
//   }) : super(key: key);

//   @override
//   State<AnimatedSidebarItem> createState() => _AnimatedSidebarItemState();
// }

// class _AnimatedSidebarItemState extends State<AnimatedSidebarItem>
//     with SingleTickerProviderStateMixin {
//   late AnimationController _controller;
//   late Animation<double> _scaleAnimation;
//   late Animation<double> _opacityAnimation;
//   late Animation<Offset> _slideAnimation;

//   @override
//   void initState() {
//     super.initState();
//     _controller = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 400),
//     );

//     _scaleAnimation = Tween<double>(
//       begin: 0.0,
//       end: 1.0,
//     ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

//     _opacityAnimation = Tween<double>(
//       begin: 0.0,
//       end: 1.0,
//     ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

//     // Slide animation from left
//     _slideAnimation = Tween<Offset>(
//       begin: const Offset(-1.5, 0), // Start from left
//       end: Offset.zero, // End at center
//     ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

//     if (widget.isActive) {
//       _controller.forward();
//     }
//   }

//   @override
//   void didUpdateWidget(AnimatedSidebarItem oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     if (widget.isActive != oldWidget.isActive) {
//       if (widget.isActive) {
//         _controller.forward();
//       } else {
//         _controller.reverse();
//       }
//     }
//   }

//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final labelStyle = AppTypography.sidebarLabel(context).copyWith(
//       color: widget.isActive ? widget.labelActiveColor : widget.labelColor,
//     );

//     return GestureDetector(
//       onTap: widget.onTap,
//       behavior: HitTestBehavior.opaque,
//       child: SizedBox(
//         width: 72,
//         child: Stack(
//           alignment: Alignment.center,
//           children: [
//             // Animated pill background (smaller)
//             AnimatedBuilder(
//               animation: _scaleAnimation,
//               builder: (context, child) {
//                 return Transform.scale(
//                   scale: _scaleAnimation.value,
//                   child: Opacity(
//                     opacity: _opacityAnimation.value,
//                     child: Container(
//                       width: 32, // Smaller width
//                       height: 100, // Smaller height
//                       decoration: BoxDecoration(
//                         color: widget.iconActiveColor.withOpacity(0.12),
//                         borderRadius: BorderRadius.circular(16),
//                       ),
//                     ),
//                   ),
//                 );
//               },
//             ),

//             // Content
//             Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 // Animated icon at top (only if active and icon exists)
//                 if (widget.icon != null)
//                   AnimatedBuilder(
//                     animation: _controller,
//                     builder: (context, child) {
//                       // Only show icon when active
//                       if (!widget.isActive) {
//                         return const SizedBox(height: 0);
//                       }

//                       return SlideTransition(
//                         position: _slideAnimation,
//                         child: FadeTransition(
//                           opacity: _opacityAnimation,
//                           child: Transform.scale(
//                             scale: 1.0 + (_scaleAnimation.value * 0.1),
//                             child: Icon(
//                               widget.icon,
//                               size: 20, // Smaller icon
//                               color: widget.iconActiveColor,
//                             ),
//                           ),
//                         ),
//                       );
//                     },
//                   ),

//                 // Add spacing only when icon is active
//                 if (widget.icon != null && widget.isActive)
//                   const SizedBox(height: 12),

//                 // Rotated text label
//                 RotatedBox(
//                   quarterTurns: -1,
//                   child: AnimatedDefaultTextStyle(
//                     duration: const Duration(milliseconds: 300),
//                     curve: Curves.easeOut,
//                     style: labelStyle.copyWith(
//                       fontSize: 15, // Slightly smaller font
//                       fontWeight: widget.isActive
//                           ? FontWeight.w600
//                           : FontWeight.w400,
//                     ),
//                     child: Text(widget.label, textAlign: TextAlign.center),
//                   ),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
