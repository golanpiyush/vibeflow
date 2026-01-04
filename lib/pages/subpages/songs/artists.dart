// // ============================================================================
// // lib/pages/subpages/artists_screen.dart
// // ============================================================================

// import 'package:flutter/material.dart';
// import 'package:vibeflow/constants/app_colors.dart';
// import 'package:vibeflow/constants/app_spacing.dart';
// import 'package:vibeflow/constants/app_typography.dart';
// import 'package:vibeflow/widgets/shimmer_loadings.dart';
// import 'package:lottie/lottie.dart';

// class ArtistsScreen extends StatefulWidget {
//   const ArtistsScreen({Key? key}) : super(key: key);

//   @override
//   State<ArtistsScreen> createState() => _ArtistsScreenState();
// }

// class _ArtistsScreenState extends State<ArtistsScreen> {
//   bool _isLoading = false;
//   List<ArtistItem> _artists = [];

//   @override
//   void initState() {
//     super.initState();
//     _loadArtists();
//   }

//   Future<void> _loadArtists() async {
//     setState(() => _isLoading = true);

//     await Future.delayed(const Duration(seconds: 1));

//     setState(() {
//       _artists = [
//         ArtistItem(
//           id: '1',
//           name: 'The Weeknd',
//           subscribers: '95M subscribers',
//           imageUrl:
//               'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400',
//         ),
//         ArtistItem(
//           id: '2',
//           name: 'Taylor Swift',
//           subscribers: '82M subscribers',
//           imageUrl:
//               'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=400',
//         ),
//         ArtistItem(
//           id: '3',
//           name: 'Drake',
//           subscribers: '67M subscribers',
//           imageUrl:
//               'https://images.unsplash.com/photo-1511367461989-f85a21fda167?w=400',
//         ),
//         ArtistItem(
//           id: '4',
//           name: 'Ariana Grande',
//           subscribers: '51M subscribers',
//           imageUrl:
//               'https://images.unsplash.com/photo-1487180144351-b8472da7d491?w=400',
//         ),
//       ];
//       _isLoading = false;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AppColors.background,
//       body: SafeArea(
//         child: Column(
//           children: [
//             const SizedBox(height: AppSpacing.xxxl),
//             _buildTopBar(),
//             Expanded(
//               child: _isLoading
//                   ? _buildLoadingState()
//                   : _artists.isEmpty
//                   ? _buildEmptyState()
//                   : _buildArtistsList(),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildTopBar() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//       child: Row(
//         children: [
//           IconButton(
//             icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
//             onPressed: () => Navigator.pop(context),
//           ),
//           const Spacer(),
//           Text('Artists', style: AppTypography.pageTitle),
//         ],
//       ),
//     );
//   }

//   Widget _buildLoadingState() {
//     return ShimmerLoading(
//       child: ListView.builder(
//         padding: const EdgeInsets.all(AppSpacing.lg),
//         itemCount: 6,
//         itemBuilder: (context, index) {
//           return Padding(
//             padding: const EdgeInsets.only(bottom: AppSpacing.md),
//             child: Row(
//               children: [
//                 SkeletonBox(width: 80, height: 80, borderRadius: 40),
//                 const SizedBox(width: AppSpacing.md),
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       SkeletonBox(width: 150, height: 16, borderRadius: 4),
//                       const SizedBox(height: 8),
//                       SkeletonBox(width: 100, height: 12, borderRadius: 4),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildEmptyState() {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Lottie.asset(
//             'assets/animations/not_found.json',
//             width: 300,
//             height: 300,
//             repeat: true,
//           ),
//           const SizedBox(height: 16),
//           Text(
//             'No artists found',
//             style: AppTypography.subtitle.copyWith(
//               color: AppColors.textSecondary,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildArtistsList() {
//     return ListView.builder(
//       padding: const EdgeInsets.all(AppSpacing.lg),
//       itemCount: _artists.length,
//       itemBuilder: (context, index) {
//         return _buildArtistCard(_artists[index]);
//       },
//     );
//   }

//   Widget _buildArtistCard(ArtistItem artist) {
//     return GestureDetector(
//       onTap: () {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Opening ${artist.name}'),
//             duration: const Duration(seconds: 1),
//           ),
//         );
//       },
//       child: Container(
//         margin: const EdgeInsets.only(bottom: AppSpacing.md),
//         padding: const EdgeInsets.all(AppSpacing.sm),
//         decoration: BoxDecoration(
//           color: AppColors.cardBackground,
//           borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
//         ),
//         child: Row(
//           children: [
//             // Profile Image
//             ClipOval(
//               child: Container(
//                 width: 80,
//                 height: 80,
//                 color: AppColors.background,
//                 child: artist.imageUrl != null
//                     ? Image.network(
//                         artist.imageUrl!,
//                         fit: BoxFit.cover,
//                         errorBuilder: (_, __, ___) => const Icon(
//                           Icons.person,
//                           size: 40,
//                           color: AppColors.iconInactive,
//                         ),
//                       )
//                     : const Icon(
//                         Icons.person,
//                         size: 40,
//                         color: AppColors.iconInactive,
//                       ),
//               ),
//             ),
//             const SizedBox(width: AppSpacing.md),
//             // Artist Info
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     artist.name,
//                     style: AppTypography.subtitle.copyWith(
//                       fontWeight: FontWeight.w600,
//                       fontSize: 16,
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     artist.subscribers,
//                     style: AppTypography.caption.copyWith(
//                       color: AppColors.textSecondary,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             // Action Button
//             IconButton(
//               icon: const Icon(Icons.more_vert, color: AppColors.iconInactive),
//               onPressed: () {},
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class ArtistItem {
//   final String id;
//   final String name;
//   final String subscribers;
//   final String? imageUrl;

//   ArtistItem({
//     required this.id,
//     required this.name,
//     required this.subscribers,
//     this.imageUrl,
//   });
// }
