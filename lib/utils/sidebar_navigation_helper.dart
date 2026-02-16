// // lib/utils/sidebar_navigation_helper.dart
// import 'package:flutter/material.dart';

// class SidebarNavigation {
//   /// Navigate to a page, replacing the current page in the stack
//   /// This prevents sidebar navigation from stacking pages
//   static void navigateTo(
//     BuildContext context,
//     Widget page, {
//     bool slideUp = false,
//     bool enableParallax = false,
//   }) {
//     Navigator.of(
//       context,
//     ).pushReplacement(MaterialPageRoute(builder: (context) => page));
//   }

//   /// Navigate with custom transition (for vertical slides)
//   static void navigateWithTransition(
//     BuildContext context,
//     Widget page, {
//     bool slideUp = false,
//     bool enableParallax = false,
//   }) {
//     Navigator.of(context).pushReplacement(
//       PageRouteBuilder(
//         pageBuilder: (context, animation, secondaryAnimation) => page,
//         transitionsBuilder: (context, animation, secondaryAnimation, child) {
//           if (slideUp) {
//             const begin = Offset(0.0, 1.0);
//             const end = Offset.zero;
//             const curve = Curves.easeInOut;

//             var tween = Tween(
//               begin: begin,
//               end: end,
//             ).chain(CurveTween(curve: curve));

//             return SlideTransition(
//               position: animation.drive(tween),
//               child: child,
//             );
//           }

//           return FadeTransition(opacity: animation, child: child);
//         },
//         transitionDuration: const Duration(milliseconds: 300),
//       ),
//     );
//   }

//   /// Navigate back to home (removes all pages from stack)
//   static void navigateToHome(BuildContext context) {
//     Navigator.of(context).popUntil((route) => route.isFirst);
//   }
// }
