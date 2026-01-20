// lib/pages/settings/cache_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibeflow/api_base/ytmusic_artists_scraper.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/pages/subpages/settings/about_page.dart';
import 'package:vibeflow/pages/subpages/settings/database_page.dart';
import 'package:vibeflow/pages/subpages/settings/other_page.dart';
import 'package:vibeflow/pages/subpages/settings/player_settings_page.dart';
import 'package:vibeflow/services/cacheManager.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/api_base/cache_manager.dart';

// StateProvider for cache expiry hours (default: 2 hours)
final cacheExpiryHoursProvider = StateProvider<int>((ref) => 2);
final cacheSizeGBProvider = StateProvider<double>(
  (ref) => 0.5,
); // Default 500MB

// FutureProvider for cache stats
final cacheStatsProvider = FutureProvider.autoDispose<CacheStats>((ref) async {
  final audioCache = AudioUrlCache();
  return await audioCache.getStats();
});

class CachePage extends ConsumerStatefulWidget {
  const CachePage({Key? key}) : super(key: key);

  @override
  ConsumerState<CachePage> createState() => _CachePageState();
}

class _CachePageState extends ConsumerState<CachePage> {
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _loadCacheExpiry();
    _loadCacheSize();
  }

  Future<void> _loadCacheExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    final hours = prefs.getInt('cache_expiry_hours') ?? 2;
    ref.read(cacheExpiryHoursProvider.notifier).state = hours;
  }

  Future<void> _saveCacheExpiry(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('cache_expiry_hours', hours);
    ref.read(cacheExpiryHoursProvider.notifier).state = hours;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cache expiry set to $hours ${hours == 1 ? 'hour' : 'hours'}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _loadCacheSize() async {
    final prefs = await SharedPreferences.getInstance();
    final sizeGB = prefs.getDouble('cache_size_gb') ?? 1.0;
    ref.read(cacheSizeGBProvider.notifier).state = sizeGB;
  }

  Future<void> _saveCacheSize(double sizeGB) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cache_size_gb', sizeGB);
    ref.read(cacheSizeGBProvider.notifier).state = sizeGB;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cache size set to ${sizeGB.toStringAsFixed(1)} GB'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _clearArtistsCache() async {
    setState(() => _isClearing = true);

    try {
      final artistsScraper = YTMusicArtistsScraper();
      artistsScraper.clearCaches();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Artists cache cleared successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing artists cache: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  // Update the _clearAllCaches method to include artists cache
  Future<void> _clearAllCaches() async {
    setState(() => _isClearing = true);

    try {
      final audioCache = AudioUrlCache();
      final cacheManager = CacheManager.instance;
      final artistsScraper = YTMusicArtistsScraper();

      await audioCache.clearAll();
      await cacheManager.clearAll();
      artistsScraper.clearCaches();

      // Refresh stats
      ref.invalidate(cacheStatsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All caches cleared successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing all caches: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  Future<void> _clearAudioCache() async {
    setState(() => _isClearing = true);

    try {
      final audioCache = AudioUrlCache();
      await audioCache.clearAll();

      // Refresh stats
      ref.invalidate(cacheStatsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio cache cleared successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing cache: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  Future<void> _clearExpiredCache() async {
    setState(() => _isClearing = true);

    try {
      final audioCache = AudioUrlCache();
      final count = await audioCache.cleanExpired();

      // Refresh stats
      ref.invalidate(cacheStatsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Removed $count expired ${count == 1 ? 'item' : 'items'}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cleaning cache: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return 'N/A';

    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m ago';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ago';
    } else {
      return '${duration.inSeconds}s ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final cacheExpiryHours = ref.watch(cacheExpiryHoursProvider);
    final cacheStatsAsync = ref.watch(cacheStatsProvider);
    final cacheSizeGB = ref.watch(cacheSizeGBProvider);

    return _SettingsPageTemplate(
      title: 'Cache',
      currentIndex: 1,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info text
          Text(
            'When the cache runs out of space, the resources that haven\'t been accessed for the longest time are cleared',
            style: AppTypography.subtitle(
              context,
            ).copyWith(color: textSecondaryColor, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.xl),

          // AUDIO CACHE SECTION
          Text(
            'AUDIO CACHE',
            style: AppTypography.caption(context).copyWith(
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Cache stats
          cacheStatsAsync.when(
            data: (stats) {
              final usedBytes = stats.totalSizeBytes;
              final maxBytes = 10 * 1024 * 1024; // 10MB max
              final percentUsed = (usedBytes / maxBytes * 100).toInt();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_formatBytes(usedBytes)} used ($percentUsed%)',
                    style: AppTypography.subtitle(
                      context,
                    ).copyWith(color: textSecondaryColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stats.count} ${stats.count == 1 ? 'item' : 'items'} cached',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor),
                  ),
                  if (stats.oldest != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Oldest: ${_formatDuration(DateTime.now().difference(stats.oldest!))}',
                      style: AppTypography.subtitle(
                        context,
                      ).copyWith(color: textSecondaryColor),
                    ),
                  ],
                ],
              );
            },
            loading: () => Text(
              'Loading...',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textSecondaryColor),
            ),
            error: (_, __) => Text(
              'Error loading cache stats',
              style: AppTypography.subtitle(
                context,
              ).copyWith(color: textSecondaryColor),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),
          Text(
            'CACHE SIZE LIMIT',
            style: AppTypography.caption(context).copyWith(
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          Text(
            'Maximum storage for cached data',
            style: AppTypography.subtitle(
              context,
            ).copyWith(fontWeight: FontWeight.w500, color: textPrimaryColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Currently set to ${cacheSizeGB.toStringAsFixed(1)} GB',
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondaryColor),
          ),
          const SizedBox(height: 12),

          // Size selector buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0].map((sizeGB) {
              final isSelected = (cacheSizeGB - sizeGB).abs() < 0.01;
              return GestureDetector(
                onTap: () => _saveCacheSize(sizeGB),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? iconActiveColor.withOpacity(0.2)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? iconActiveColor
                          : textSecondaryColor.withOpacity(0.3),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${sizeGB.toStringAsFixed(1)} GB',
                    style: AppTypography.caption(context).copyWith(
                      color: isSelected ? iconActiveColor : textPrimaryColor,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // Info about cache size
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconActiveColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: iconActiveColor.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: iconActiveColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Larger cache means more data stored locally for faster access, but uses more device storage',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),
          // Cache expiry setting
          Text(
            'Auto Cache Expiry',
            style: AppTypography.subtitle(
              context,
            ).copyWith(fontWeight: FontWeight.w500, color: textPrimaryColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Audio URLs will be cached for $cacheExpiryHours ${cacheExpiryHours == 1 ? 'hour' : 'hours'}',
            style: AppTypography.caption(
              context,
            ).copyWith(color: textSecondaryColor),
          ),
          const SizedBox(height: 12),

          // Hour selector buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [1, 2, 3, 4, 5, 6].map((hours) {
              final isSelected = cacheExpiryHours == hours;
              return GestureDetector(
                onTap: () => _saveCacheExpiry(hours),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? iconActiveColor.withOpacity(0.2)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? iconActiveColor
                          : textSecondaryColor.withOpacity(0.3),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$hours ${hours == 1 ? 'hr' : 'hrs'}',
                    style: AppTypography.caption(context).copyWith(
                      color: isSelected ? iconActiveColor : textPrimaryColor,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Cache actions
          Text(
            'CACHE ACTIONS',
            style: AppTypography.caption(context).copyWith(
              color: iconActiveColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Clear expired button
          _buildActionButton(
            context,
            label: 'Clear Expired Cache',
            description: 'Remove only expired items',
            onTap: _isClearing ? null : _clearExpiredCache,
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),

          const SizedBox(height: 12),

          // Clear audio cache button
          _buildActionButton(
            context,
            label: 'Clear Audio Cache',
            description: 'Remove all cached audio URLs',
            onTap: _isClearing ? null : _clearAudioCache,
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),

          const SizedBox(height: 12),

          // Clear artists cache button (NEW)
          _buildActionButton(
            context,
            label: 'Clear Artists Cache',
            description: 'Remove all cached artists and genres data',
            onTap: _isClearing ? null : _clearArtistsCache,
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
          ),
          const SizedBox(height: 12),
          // Clear all caches button
          _buildActionButton(
            context,
            label: 'Clear All Caches',
            description: 'Remove all cached data (audio, artists, albums)',
            onTap: _isClearing ? null : _clearAllCaches,
            textPrimaryColor: textPrimaryColor,
            textSecondaryColor: textSecondaryColor,
            iconActiveColor: iconActiveColor,
            isDanger: true,
          ),

          if (_isClearing) ...[
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(iconActiveColor),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required String description,
    required VoidCallback? onTap,
    required Color textPrimaryColor,
    required Color textSecondaryColor,
    required Color iconActiveColor,
    bool isDanger = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDanger
              ? Colors.red.withOpacity(0.1)
              : iconActiveColor.withOpacity(0.05),
          border: Border.all(
            color: isDanger
                ? Colors.red.withOpacity(0.3)
                : iconActiveColor.withOpacity(0.2),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.subtitle(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDanger ? Colors.red : textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isDanger
                  ? Colors.red.withOpacity(0.5)
                  : textSecondaryColor.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }
}

// Template for settings pages (keeping existing implementation)
class _SettingsPageTemplate extends ConsumerWidget {
  final String title;
  final int currentIndex;
  final Widget content;

  const _SettingsPageTemplate({
    required this.title,
    required this.currentIndex,
    required this.content,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backgroundColor = ref.watch(themeBackgroundColorProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, ref),
            Expanded(
              child: Row(
                children: [
                  _buildSidebar(context, ref),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [content, const SizedBox(height: 100)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, WidgetRef ref) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.chevron_left, color: textPrimaryColor, size: 28),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                title,
                style: AppTypography.pageTitle(
                  context,
                ).copyWith(color: textPrimaryColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, WidgetRef ref) {
    final double availableHeight = MediaQuery.of(context).size.height;
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final iconInactiveColor = ref.watch(themeTextSecondaryColorProvider);
    final sidebarLabelColor = ref.watch(themeTextPrimaryColorProvider);
    final sidebarLabelActiveColor = ref.watch(themeIconActiveColorProvider);

    final sidebarLabelStyle = AppTypography.sidebarLabel(
      context,
    ).copyWith(color: sidebarLabelColor);
    final sidebarLabelActiveStyle = AppTypography.sidebarLabelActive(
      context,
    ).copyWith(color: sidebarLabelActiveColor);

    return SizedBox(
      width: 65,
      height: availableHeight,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 200),
            _buildSidebarItem(
              context,
              icon: Icons.edit_square,
              label: '',
              isActive: false,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: sidebarLabelStyle,
              index: -1,
            ),
            const SizedBox(height: 32),
            _buildSidebarItem(
              context,
              label: 'Player',
              isActive: currentIndex == 0,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 0
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 0,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Cache',
              isActive: currentIndex == 1,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 1
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 1,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Database',
              isActive: currentIndex == 2,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 2
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 2,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'Other',
              isActive: currentIndex == 3,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 3
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 3,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              context,
              label: 'About',
              isActive: currentIndex == 4,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelStyle: currentIndex == 4
                  ? sidebarLabelActiveStyle
                  : sidebarLabelStyle,
              index: 4,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    BuildContext context, {
    IconData? icon,
    required String label,
    bool isActive = false,
    required Color iconActiveColor,
    required Color iconInactiveColor,
    required TextStyle labelStyle,
    required int index,
  }) {
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          _navigateToPage(context, index, currentIndex: currentIndex);
        }
      },
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 28,
                color: isActive ? iconActiveColor : iconInactiveColor,
              ),
              const SizedBox(height: 16),
            ],
            RotatedBox(
              quarterTurns: -1,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: labelStyle.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToPage(
    BuildContext context,
    int targetIndex, {
    required int currentIndex,
  }) {
    Widget page;
    switch (targetIndex) {
      case -1:
        Navigator.popUntil(context, (route) => route.isFirst);
        return;
      case 0:
        page = const PlayerSettingsPage();
        break;
      case 1:
        page = const CachePage();
        break;
      case 2:
        page = const DatabasePage();
        break;
      case 3:
        page = const OtherPage();
        break;
      case 4:
        page = const AboutPage();
        break;
      default:
        return;
    }

    Navigator.of(context).pushReplacementDirectional(
      page,
      currentIndex: currentIndex,
      targetIndex: targetIndex,
    );
  }
}
