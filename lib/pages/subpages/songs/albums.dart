// // ============================================================================
// // lib/pages/subpages/albums_screen.dart
// // ============================================================================

// import 'package:flutter/material.dart';
// import 'package:vibeflow/constants/app_colors.dart';
// import 'package:vibeflow/constants/app_spacing.dart';
// import 'package:vibeflow/constants/app_typography.dart';
// import 'package:vibeflow/widgets/shimmer_loadings.dart';
// import 'package:lottie/lottie.dart';

// class AlbumsScreen extends StatefulWidget {
//   const AlbumsScreen({Key? key}) : super(key: key);

//   @override
//   State<AlbumsScreen> createState() => _AlbumsScreenState();
// }

// class _AlbumsScreenState extends State<AlbumsScreen> {
//   bool _isLoading = false;
//   List<AlbumItem> _albums = [];
//   String _sortBy = 'recent'; // 'recent', 'title', 'artist'

//   @override
//   void initState() {
//     super.initState();
//     _loadAlbums();
//   }

//   Future<void> _loadAlbums() async {
//     setState(() => _isLoading = true);

//     await Future.delayed(const Duration(seconds: 1));

//     setState(() {
//       _albums = [
//         AlbumItem(
//           id: '1',
//           title: 'After Hours',
//           artist: 'The Weeknd',
//           year: 2020,
//           coverUrl:
//               'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=400',
//         ),
//         AlbumItem(
//           id: '2',
//           title: 'Midnights',
//           artist: 'Taylor Swift',
//           year: 2022,
//           coverUrl:
//               'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=400',
//         ),
//         AlbumItem(
//           id: '3',
//           title: 'Certified Lover Boy',
//           artist: 'Drake',
//           year: 2021,
//           coverUrl:
//               'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=400',
//         ),
//         AlbumItem(
//           id: '4',
//           title: 'Positions',
//           artist: 'Ariana Grande',
//           year: 2020,
//           coverUrl:
//               'https://images.unsplash.com/photo-1487180144351-b8472da7d491?w=400',
//         ),
//       ];
//       _isLoading = false;
//     });
//   }

//   void _applySorting() {
//     setState(() {
//       switch (_sortBy) {
//         case 'title':
//           _albums.sort((a, b) => a.title.compareTo(b.title));
//           break;
//         case 'artist':
//           _albums.sort((a, b) => a.artist.compareTo(b.artist));
//           break;
//         case 'recent':
//         default:
//           _albums.sort((a, b) => b.year.compareTo(a.year));
//           break;
//       }
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
//                   : _albums.isEmpty
//                   ? _buildEmptyState()
//                   : _buildAlbumsGrid(),
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
//           Text('Albums', style: AppTypography.pageTitle),
//           const SizedBox(width: 8),
//           PopupMenuButton<String>(
//             icon: const Icon(Icons.sort, color: AppColors.iconInactive),
//             color: const Color(0xFF2A2A2A),
//             onSelected: (value) {
//               setState(() => _sortBy = value);
//               _applySorting();
//             },
//             itemBuilder: (context) => [
//               _buildSortMenuItem('recent', 'Recent', Icons.access_time),
//               _buildSortMenuItem('title', 'Title', Icons.sort_by_alpha),
//               _buildSortMenuItem('artist', 'Artist', Icons.person),
//             ],
//           ),
//         ],
//       ),
//     );
//   }

//   PopupMenuItem<String> _buildSortMenuItem(
//     String value,
//     String label,
//     IconData icon,
//   ) {
//     final isSelected = _sortBy == value;
//     return PopupMenuItem(
//       value: value,
//       child: Row(
//         children: [
//           Icon(icon, color: isSelected ? AppColors.iconActive : Colors.white70),
//           const SizedBox(width: 12),
//           Text(
//             label,
//             style: TextStyle(
//               color: isSelected ? AppColors.iconActive : Colors.white,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildLoadingState() {
//     return ShimmerLoading(
//       child: GridView.builder(
//         padding: const EdgeInsets.all(AppSpacing.lg),
//         gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//           crossAxisCount: 2,
//           childAspectRatio: 0.75,
//           crossAxisSpacing: AppSpacing.md,
//           mainAxisSpacing: AppSpacing.md,
//         ),
//         itemCount: 6,
//         itemBuilder: (context, index) {
//           return Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               SkeletonBox(
//                 width: double.infinity,
//                 height: 160,
//                 borderRadius: AppSpacing.radiusMedium,
//               ),
//               const SizedBox(height: AppSpacing.sm),
//               SkeletonBox(width: 120, height: 14, borderRadius: 4),
//               const SizedBox(height: 6),
//               SkeletonBox(width: 80, height: 12, borderRadius: 4),
//             ],
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
//             'No albums found',
//             style: AppTypography.subtitle.copyWith(
//               color: AppColors.textSecondary,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildAlbumsGrid() {
//     return GridView.builder(
//       padding: const EdgeInsets.all(AppSpacing.lg),
//       gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//         crossAxisCount: 2,
//         childAspectRatio: 0.75,
//         crossAxisSpacing: AppSpacing.md,
//         mainAxisSpacing: AppSpacing.md,
//       ),
//       itemCount: _albums.length,
//       itemBuilder: (context, index) {
//         return _buildAlbumCard(_albums[index]);
//       },
//     );
//   }

//   Widget _buildAlbumCard(AlbumItem album) {
//     return GestureDetector(
//       onTap: () {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Opening ${album.title}'),
//             duration: const Duration(seconds: 1),
//           ),
//         );
//       },
//       child: Container(
//         decoration: BoxDecoration(
//           color: AppColors.cardBackground,
//           borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
//         ),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             // Album Cover
//             AspectRatio(
//               aspectRatio: 1,
//               child: Container(
//                 decoration: BoxDecoration(
//                   color: AppColors.background,
//                   borderRadius: const BorderRadius.vertical(
//                     top: Radius.circular(AppSpacing.radiusMedium),
//                   ),
//                 ),
//                 child: album.coverUrl != null
//                     ? ClipRRect(
//                         borderRadius: const BorderRadius.vertical(
//                           top: Radius.circular(AppSpacing.radiusMedium),
//                         ),
//                         child: Image.network(
//                           album.coverUrl!,
//                           fit: BoxFit.cover,
//                           errorBuilder: (_, __, ___) => _buildAlbumIcon(),
//                         ),
//                       )
//                     : _buildAlbumIcon(),
//               ),
//             ),
//             // Album Info
//             Padding(
//               padding: const EdgeInsets.all(AppSpacing.sm),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     album.title,
//                     style: AppTypography.subtitle.copyWith(
//                       fontWeight: FontWeight.w600,
//                     ),
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     album.artist,
//                     style: AppTypography.caption.copyWith(
//                       color: AppColors.textSecondary,
//                     ),
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis,
//                   ),
//                   const SizedBox(height: 2),
//                   Text(
//                     album.year.toString(),
//                     style: AppTypography.captionSmall.copyWith(
//                       color: AppColors.textSecondary.withOpacity(0.7),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildAlbumIcon() {
//     return const Center(
//       child: Icon(Icons.album, size: 48, color: AppColors.iconInactive),
//     );
//   }
// }

// class AlbumItem {
//   final String id;
//   final String title;
//   final String artist;
//   final int year;
//   final String? coverUrl;

//   AlbumItem({
//     required this.id,
//     required this.title,
//     required this.artist,
//     required this.year,
//     this.coverUrl,
//   });
// }
