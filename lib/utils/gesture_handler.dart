// import 'package:flutter/material.dart';

// class AlbumArtGestureHandler extends StatefulWidget {
//   final Widget child;
//   final VoidCallback onSwipeLeft; // Next song
//   final VoidCallback onSwipeRight; // Previous song
//   final VoidCallback onSwipeDown; // Go back
//   final VoidCallback onSwipeUp; // Show lyrics
//   final VoidCallback onTap; // Play/Pause

//   const AlbumArtGestureHandler({
//     Key? key,
//     required this.child,
//     required this.onSwipeLeft,
//     required this.onSwipeRight,
//     required this.onSwipeDown,
//     required this.onSwipeUp,
//     required this.onTap,
//   }) : super(key: key);

//   @override
//   State<AlbumArtGestureHandler> createState() => _AlbumArtGestureHandlerState();
// }

// class _AlbumArtGestureHandlerState extends State<AlbumArtGestureHandler> {
//   double _dragStartX = 0;
//   double _dragStartY = 0;
//   double _currentDragX = 0;
//   double _currentDragY = 0;
//   bool _isDragging = false;

//   // Sensitivity thresholds
//   static const double _horizontalThreshold = 80.0;
//   static const double _verticalThreshold = 80.0;

//   void _onPanStart(DragStartDetails details) {
//     setState(() {
//       _dragStartX = details.localPosition.dx;
//       _dragStartY = details.localPosition.dy;
//       _currentDragX = 0;
//       _currentDragY = 0;
//       _isDragging = true;
//     });
//   }

//   void _onPanUpdate(DragUpdateDetails details) {
//     setState(() {
//       _currentDragX = details.localPosition.dx - _dragStartX;
//       _currentDragY = details.localPosition.dy - _dragStartY;
//     });
//   }

//   void _onPanEnd(DragEndDetails details) {
//     final absX = _currentDragX.abs();
//     final absY = _currentDragY.abs();

//     // Determine if horizontal or vertical swipe is dominant
//     if (absX > absY) {
//       // Horizontal swipe
//       if (absX > _horizontalThreshold) {
//         if (_currentDragX > 0) {
//           // Swipe right - Previous song
//           widget.onSwipeRight();
//         } else {
//           // Swipe left - Next song
//           widget.onSwipeLeft();
//         }
//       }
//     } else {
//       // Vertical swipe
//       if (absY > _verticalThreshold) {
//         if (_currentDragY > 0) {
//           // Swipe down - Go back
//           widget.onSwipeDown();
//         } else {
//           // Swipe up - Show lyrics
//           widget.onSwipeUp();
//         }
//       }
//     }

//     setState(() {
//       _isDragging = false;
//       _currentDragX = 0;
//       _currentDragY = 0;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: widget.onTap,
//       onPanStart: _onPanStart,
//       onPanUpdate: _onPanUpdate,
//       onPanEnd: _onPanEnd,
//       child: AnimatedContainer(
//         duration: const Duration(milliseconds: 200),
//         transform: Matrix4.identity()
//           ..translate(
//             _isDragging ? _currentDragX * 0.15 : 0.0,
//             _isDragging ? _currentDragY * 0.15 : 0.0,
//           ),
//         child: widget.child,
//       ),
//     );
//   }
// }
