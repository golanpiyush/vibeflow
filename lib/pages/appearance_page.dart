// lib/pages/appearance_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/pages/subpages/settings/about_page.dart';
import 'package:vibeflow/pages/subpages/settings/cache_page.dart';
import 'package:vibeflow/pages/subpages/settings/database_page.dart';
import 'package:vibeflow/pages/subpages/settings/other_page.dart';
import 'package:vibeflow/pages/subpages/settings/player_settings_page.dart';
import 'package:vibeflow/providers/immersive_mode_provider.dart';
import 'package:vibeflow/utils/page_transitions.dart';
import 'package:vibeflow/utils/settings_provider.dart';
import 'package:vibeflow/utils/theme_provider.dart';
import 'package:vibeflow/utils/lyrics_provider.dart' as lyrics_provider;

class AppearancePage extends ConsumerStatefulWidget {
  const AppearancePage({Key? key}) : super(key: key);

  @override
  ConsumerState<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends ConsumerState<AppearancePage> {
  String selectedTheme = 'PureBlack';
  String thumbnailRoundness = 'Heavy';
  bool useSystemFont = false;
  bool applyFontPadding = false;

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xxxl),
                _buildTopBar(ref, themeData),
                Expanded(
                  child: Row(
                    children: [
                      _buildSidebar(themeData),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildImmersiveSection(ref),
                              const SizedBox(height: AppSpacing.xxxl),
                              _buildColorsSection(ref),
                              const SizedBox(height: AppSpacing.xxxl),
                              _buildShapesSection(ref),
                              const SizedBox(height: AppSpacing.xxxl),
                              _buildTextSection(ref),
                              // const SizedBox(height: 100),
                              const SizedBox(height: AppSpacing.xxxl),
                              _buildLyricsSection(ref),
                              const SizedBox(height: AppSpacing.fourxxxl),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(WidgetRef ref, ThemeData themeData) {
    final textPrimaryColor = themeData.colorScheme.onSurface;
    final pageTitleStyle = AppTypography.pageTitle(
      context,
    ).copyWith(color: textPrimaryColor);
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 60, bottom: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.chevron_left, color: textPrimaryColor, size: 28),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Appearance', style: pageTitleStyle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(ThemeData themeData) {
    final iconActiveColor = themeData.colorScheme.primary;
    final iconInactiveColor = themeData.colorScheme.onSurfaceVariant;
    final sidebarLabelColor = themeData.colorScheme.onSurface;
    final sidebarLabelActiveColor = themeData.colorScheme.primary;
    final double availableHeight = MediaQuery.of(context).size.height;

    return SizedBox(
      width: 65,
      height: availableHeight,
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 200),
            _buildSidebarItem(
              icon: Icons.edit_square,
              label: '',
              isActive: true,
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelColor: sidebarLabelActiveColor,
              index: -1,
            ),
            const SizedBox(height: 32),
            _buildSidebarItem(
              label: 'Player',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelColor: sidebarLabelActiveColor,
              index: 0,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Cache',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelColor: sidebarLabelActiveColor,
              index: 1,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Database',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelColor: sidebarLabelActiveColor,
              index: 2,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'Other',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelColor: sidebarLabelActiveColor,
              index: 3,
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(
              label: 'About',
              iconActiveColor: iconActiveColor,
              iconInactiveColor: iconInactiveColor,
              labelColor: sidebarLabelActiveColor,
              index: 4,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    IconData? icon,
    required String label,
    bool isActive = false,
    required Color iconActiveColor,
    required Color iconInactiveColor,
    required Color labelColor,
    required int index,
  }) {
    return GestureDetector(
      onTap: () {
        if (!isActive && index != -1) {
          _navigateToPage(context, index, currentIndex: -1);
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
                style: AppTypography.sidebarLabel(
                  context,
                ).copyWith(color: labelColor, fontSize: 16),
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

  // Update your AppearancePage's _buildColorsSection method
  Widget _buildColorsSection(WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COLORS',
          style: AppTypography.caption(context).copyWith(
            color: iconActiveColor,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildSettingItem(
          title: 'Theme',
          subtitle: _getThemeTypeLabel(themeState.themeType),
          textSecondaryColor: textSecondaryColor,
          onTap: () {
            _showThemeTypePicker(ref);
          },
        ),
        const SizedBox(height: AppSpacing.md),

        if (themeState.themeType == ThemeType.material) ...[
          _buildSettingItem(
            title: 'Theme mode',
            subtitle: _getThemeModeLabel(themeState.systemThemeMode),
            textSecondaryColor: textSecondaryColor,
            onTap: () {
              _showThemeModePicker(ref); // Pass ref
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _buildSettingItem(
            title: 'Color',
            subtitle: _getColorLabel(themeState.seedColor),
            textSecondaryColor: textSecondaryColor,
            onTap: () {
              _showColorPicker(ref); // Pass ref
            },
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }

  String _getThemeModeLabel(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
    }
  }

  // Add this inside _buildColorsSection or create a new _buildImmersiveSection:
  Widget _buildImmersiveSection(WidgetRef ref) {
    final isImmersive = ref.watch(immersiveModeProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DISPLAY',
          style: AppTypography.caption(context).copyWith(
            color: iconActiveColor,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildSwitchItem(
          title: 'Immersive mode',
          subtitle: 'Miniplayer covers navigation bar',
          value: isImmersive,
          textPrimaryColor: textPrimaryColor,
          textSecondaryColor: textSecondaryColor,
          onChanged: (_) => ref.read(immersiveModeProvider.notifier).toggle(),
        ),
      ],
    );
  }

  // Add these helper methods
  String _getThemeTypeLabel(ThemeType type) {
    switch (type) {
      case ThemeType.light:
        return 'Light';
      case ThemeType.material:
        return 'Material You';
      case ThemeType.pureBlack:
        return 'Pure Black';
    }
  }

  String _getColorLabel(Color? color) {
    if (color == null) return 'Default (Purple)';

    final value = color.value;

    // Core
    if (value == const Color(0xFF6B4CE8).value) return 'Purple';
    if (value == const Color(0xFF2196F3).value) return 'Blue';
    if (value == const Color(0xFF009688).value) return 'Teal';
    if (value == const Color(0xFF4CAF50).value) return 'Green';
    if (value == const Color(0xFFFF9800).value) return 'Orange';
    if (value == const Color(0xFFF44336).value) return 'Red';
    if (value == const Color(0xFFE91E63).value) return 'Pink';

    // Dark / Neutral
    if (value == const Color(0xFF000000).value) return 'Black';
    if (value == const Color(0xFF424242).value) return 'Dark Grey';
    if (value == const Color(0xFF9E9E9E).value) return 'Grey';
    if (value == const Color(0xFFFFFFFF).value) return 'White';

    // Cool tones
    if (value == const Color(0xFF3F51B5).value) return 'Indigo';
    if (value == const Color(0xFF00BCD4).value) return 'Cyan';
    if (value == const Color(0xFF03A9F4).value) return 'Light Blue';

    // Warm tones
    if (value == const Color(0xFFFFC107).value) return 'Amber';
    if (value == const Color(0xFFFF5722).value) return 'Deep Orange';
    if (value == const Color(0xFFFFEB3B).value) return 'Yellow';

    // Aesthetic / modern
    if (value == const Color(0xFF795548).value) return 'Brown';
    if (value == const Color(0xFF607D8B).value) return 'Blue Grey';
    if (value == const Color(0xFF673AB7).value) return 'Deep Purple';
    if (value == const Color(0xFF1DE9B6).value) return 'Mint';

    return 'Custom';
  }

  IconData _getThemeTypeIcon(ThemeType type) {
    switch (type) {
      case ThemeType.light:
        return Icons.light_mode;
      case ThemeType.material:
        return Icons.palette;
      case ThemeType.pureBlack:
        return Icons.dark_mode;
    }
  }

  String _getThemeTypeDescription(ThemeType type) {
    switch (type) {
      case ThemeType.light:
        return 'Clean white interface';
      case ThemeType.material:
        return 'Dynamic colors from wallpaper';
      case ThemeType.pureBlack:
        return 'True black OLED theme';
    }
  }

  void _showColorPicker(WidgetRef ref) {
    final themeNotifier = ref.read(themeProvider.notifier);
    final currentColor = ref.read(themeProvider).seedColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textPrimaryColor = colorScheme.onSurface;
        final textSecondaryColor = colorScheme.onSurface.withOpacity(0.6);
        final iconActiveColor = colorScheme.primary;

        final colorOptions = [
          ('Purple', const Color(0xFF6B4CE8)),
          ('Blue', const Color(0xFF2196F3)),
          ('Teal', const Color(0xFF009688)),
          ('Green', const Color(0xFF4CAF50)),
          ('Orange', const Color(0xFFFF9800)),
          ('Red', const Color(0xFFF44336)),
          ('Pink', const Color(0xFFE91E63)),
        ];

        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: textSecondaryColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Select Color',
                style: AppTypography.sectionHeader(
                  context,
                ).copyWith(color: textPrimaryColor),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: colorOptions.map((option) {
                  return _buildColorOption(
                    option.$1,
                    option.$2,
                    currentColor,
                    themeNotifier,
                    iconActiveColor,
                    textSecondaryColor,
                    textPrimaryColor,
                  );
                }).toList(),
              ),
              const SizedBox(height: 90),
            ],
          ),
        );
      },
    );
  }

  void _showThemeModePicker(WidgetRef ref) {
    final themeNotifier = ref.read(themeProvider.notifier);
    final currentMode = ref.read(themeProvider).systemThemeMode;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textPrimaryColor = colorScheme.onSurface;
        final textSecondaryColor = colorScheme.onSurface.withOpacity(0.6);
        final iconActiveColor = colorScheme.primary;

        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: textSecondaryColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Select Theme Mode',
                style: AppTypography.sectionHeader(
                  context,
                ).copyWith(color: textPrimaryColor),
              ),
              const SizedBox(height: 20),
              ...AppThemeMode.values.map((mode) {
                final isSelected = currentMode == mode;
                return ListTile(
                  leading: Icon(
                    mode == AppThemeMode.light
                        ? Icons.light_mode
                        : Icons.dark_mode,
                    color: isSelected ? iconActiveColor : textPrimaryColor,
                  ),
                  title: Text(
                    _getThemeModeLabel(mode),
                    style: AppTypography.subtitle(context).copyWith(
                      color: isSelected ? iconActiveColor : textPrimaryColor,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check, color: iconActiveColor)
                      : null,
                  onTap: () {
                    themeNotifier.setSystemThemeMode(mode);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
              const SizedBox(height: 90),
            ],
          ),
        );
      },
    );
  }

  void _showThemeTypePicker(WidgetRef ref) {
    final themeNotifier = ref.read(themeProvider.notifier);
    final currentType = ref.read(themeProvider).themeType;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textPrimaryColor = colorScheme.onSurface;
        final textSecondaryColor = colorScheme.onSurface.withOpacity(0.6);
        final iconActiveColor = colorScheme.primary;

        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: textSecondaryColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Select Theme',
                style: AppTypography.sectionHeader(
                  context,
                ).copyWith(color: textPrimaryColor),
              ),
              const SizedBox(height: 20),
              ...ThemeType.values.map((type) {
                final isSelected = currentType == type;
                final icon = _getThemeTypeIcon(type);
                final description = _getThemeTypeDescription(type);

                return ListTile(
                  leading: Icon(
                    icon,
                    color: isSelected ? iconActiveColor : textPrimaryColor,
                  ),
                  title: Text(
                    _getThemeTypeLabel(type),
                    style: AppTypography.subtitle(context).copyWith(
                      color: isSelected ? iconActiveColor : textPrimaryColor,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    description,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor, fontSize: 11),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check, color: iconActiveColor)
                      : null,
                  onTap: () {
                    themeNotifier.setThemeType(type);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
              const SizedBox(height: 90),
            ],
          ),
        );
      },
    );
  }

  void _showLyricsProviderPicker() {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final currentProvider = ref.read(settingsProvider).lyricsProvider;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textPrimaryColor = colorScheme.onSurface;
        final textSecondaryColor = colorScheme.onSurface.withOpacity(0.6);
        final iconActiveColor = colorScheme.primary;

        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: textSecondaryColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Select Lyrics Provider',
                style: AppTypography.sectionHeader(
                  context,
                ).copyWith(color: textPrimaryColor),
              ),
              const SizedBox(height: 20),
              ...lyrics_provider.LyricsSource.values.map((source) {
                final isSelected = currentProvider == source;
                return ListTile(
                  title: Text(
                    _getLyricsProviderLabel(source),
                    style: AppTypography.subtitle(context).copyWith(
                      color: isSelected ? iconActiveColor : textPrimaryColor,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    source == lyrics_provider.LyricsSource.kugou
                        ? 'Synchronized word by word timing'
                        : 'Simple line by line format',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: textSecondaryColor, fontSize: 12),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check, color: iconActiveColor)
                      : null,
                  onTap: () {
                    settingsNotifier.setLyricsProvider(source);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
              const SizedBox(height: 90),
            ],
          ),
        );
      },
    );
  }

  void _showFontFamilyPicker() {
    final themeNotifier = ref.read(themeProvider.notifier);
    final currentFont = ref.read(themeProvider).fontFamily;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textPrimaryColor = colorScheme.onSurface;
        final textSecondaryColor = colorScheme.onSurface.withOpacity(0.6);
        final iconActiveColor = colorScheme.primary;

        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: textSecondaryColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Select Font Family',
                  style: AppTypography.sectionHeader(
                    context,
                  ).copyWith(color: textPrimaryColor),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: currentFont == AppFontFamily.system
                                  ? iconActiveColor
                                  : textSecondaryColor.withOpacity(0.3),
                              width: currentFont == AppFontFamily.system
                                  ? 2
                                  : 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: Icon(
                              Icons.smartphone,
                              color: currentFont == AppFontFamily.system
                                  ? iconActiveColor
                                  : textPrimaryColor,
                            ),
                            title: Text(
                              'System Default',
                              style: AppTypography.subtitle(context).copyWith(
                                color: currentFont == AppFontFamily.system
                                    ? iconActiveColor
                                    : textPrimaryColor,
                                fontWeight: currentFont == AppFontFamily.system
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              'Use device default font',
                              style: AppTypography.caption(context).copyWith(
                                color: textSecondaryColor,
                                fontSize: 12,
                              ),
                            ),
                            trailing: currentFont == AppFontFamily.system
                                ? Icon(Icons.check, color: iconActiveColor)
                                : null,
                            onTap: () {
                              themeNotifier.setFontFamily(AppFontFamily.system);
                              Navigator.pop(context);
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...AppFontFamily.values
                            .where((font) => font != AppFontFamily.system)
                            .map((font) {
                              final isSelected = currentFont == font;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: ListTile(
                                  title: Text(
                                    _getFontFamilyLabel(font),
                                    style: AppTypography.subtitle(context)
                                        .copyWith(
                                          color: isSelected
                                              ? iconActiveColor
                                              : textPrimaryColor,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                  ),
                                  subtitle: Text(
                                    _getFontFamilyDescription(font),
                                    style: AppTypography.caption(context)
                                        .copyWith(
                                          color: textSecondaryColor,
                                          fontSize: 12,
                                        ),
                                  ),
                                  trailing: isSelected
                                      ? Icon(
                                          Icons.check,
                                          color: iconActiveColor,
                                        )
                                      : null,
                                  onTap: () {
                                    themeNotifier.setFontFamily(font);
                                    Navigator.pop(context);
                                  },
                                ),
                              );
                            })
                            .toList(),
                        const SizedBox(height: 90),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRoundnessPicker() {
    final themeNotifier = ref.read(themeProvider.notifier);
    final currentRoundness = ref.read(themeProvider).thumbnailRoundness;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final textPrimaryColor = colorScheme.onSurface;
        final textSecondaryColor = colorScheme.onSurface.withOpacity(0.6);
        final iconActiveColor = colorScheme.primary;

        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: textSecondaryColor.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Select Thumbnail Roundness',
                style: AppTypography.sectionHeader(
                  context,
                ).copyWith(color: textPrimaryColor),
              ),
              const SizedBox(height: 20),
              ...ThumbnailRoundness.values.map((roundness) {
                final isSelected = currentRoundness == roundness;
                final radius = _getRadiusForRoundness(roundness);

                return ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconActiveColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(48 * radius),
                      border: Border.all(color: iconActiveColor, width: 2),
                    ),
                  ),
                  title: Text(
                    _getRoundnessLabel(roundness),
                    style: AppTypography.subtitle(context).copyWith(
                      color: isSelected ? iconActiveColor : textPrimaryColor,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check, color: iconActiveColor)
                      : null,
                  onTap: () {
                    themeNotifier.setThumbnailRoundness(roundness);
                    setState(() {
                      thumbnailRoundness = _getRoundnessLabel(roundness);
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
              const SizedBox(height: 90),
            ],
          ),
        );
      },
    );
  }

  Widget _buildColorOption(
    String label,
    Color color,
    Color? currentColor,
    ThemeNotifier themeNotifier,
    Color iconActiveColor,
    Color textSecondaryColor,
    Color textPrimaryColor,
  ) {
    final isSelected =
        currentColor == color || (currentColor == null && label == 'Purple');

    return GestureDetector(
      onTap: () {
        themeNotifier.setSeedColor(color);
        Navigator.pop(context);
      },
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? iconActiveColor
                    : textSecondaryColor.withOpacity(0.3),
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: isSelected
                ? Icon(Icons.check, color: Colors.white, size: 28)
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTypography.caption(context).copyWith(
              color: isSelected ? iconActiveColor : textPrimaryColor,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShapesSection(WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final radiusMultiplier = ref.watch(thumbnailRadiusProvider);

    // Get theme-aware colors
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SHAPES',
          style: AppTypography.caption(context).copyWith(
            color: iconActiveColor,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        GestureDetector(
          onTap: () => _showRoundnessPicker(),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thumbnail roundness',
                      style: AppTypography.subtitle(context).copyWith(
                        fontWeight: FontWeight.w500,
                        color: textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getRoundnessLabel(themeState.thumbnailRoundness),
                      style: AppTypography.caption(
                        context,
                      ).copyWith(color: textSecondaryColor),
                    ),
                  ],
                ),
              ),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: cardBackgroundColor,
                  borderRadius: BorderRadius.circular(54 * radiusMultiplier),
                  border: Border.all(color: iconActiveColor, width: 2),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextSection(WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TEXT',
          style: AppTypography.caption(context).copyWith(
            color: iconActiveColor,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ✅ Font Family Setting
        _buildSettingItem(
          title: 'Font family',
          subtitle: _getFontFamilyLabel(themeState.fontFamily),
          textSecondaryColor: textSecondaryColor,
          onTap: () {
            _showFontFamilyPicker();
          },
        ),
        const SizedBox(height: AppSpacing.lg),

        // Apply Font Padding Switch
        _buildSwitchItem(
          title: 'Apply font padding',
          subtitle: 'Add spacing around texts',
          value: themeState.applyFontPadding,
          textPrimaryColor: textPrimaryColor,
          textSecondaryColor: textSecondaryColor,
          onChanged: (value) {
            ref.read(themeProvider.notifier).setApplyFontPadding(value);
          },
        ),
      ],
    );
  }

  Widget _buildLyricsSection(WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LYRICS',
          style: AppTypography.caption(context).copyWith(
            color: iconActiveColor,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildSettingItem(
          title: 'Lyrics provider',
          subtitle: _getLyricsProviderLabel(settings.lyricsProvider),
          textSecondaryColor: textSecondaryColor,
          onTap: () {
            _showLyricsProviderPicker();
          },
        ),
        const SizedBox(height: 8),
        Text(
          settings.lyricsProvider == lyrics_provider.LyricsSource.kugou
              ? 'Word by word synchronized lyrics'
              : 'Line by line lyrics',
          style: AppTypography.caption(
            context,
          ).copyWith(color: textSecondaryColor.withOpacity(0.7), fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ADD THIS SECTION - Message about auto API fallback
        Container(
          padding: EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            border: Border.all(
              color: iconActiveColor.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: iconActiveColor),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Note',
                      style: AppTypography.caption(context).copyWith(
                        color: textPrimaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: AppSpacing.xs),
                    Text(
                      'VibeFlow can and will automatically switch between the API which works. To get lyrics even if one provider is temporarily unavailable.',
                      style: AppTypography.caption(context).copyWith(
                        color: textSecondaryColor,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.xxxl),
      ],
    );
  }

  Widget _buildSettingItem({
    required String title,
    required String subtitle,
    required Color textSecondaryColor,
    required VoidCallback onTap,
  }) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.subtitle(
                context,
              ).copyWith(fontWeight: FontWeight.w500, color: textPrimaryColor),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: AppTypography.caption(
                context,
              ).copyWith(color: textSecondaryColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchItem({
    required String title,
    required String subtitle,
    required bool value,
    required Color textPrimaryColor,
    required Color textSecondaryColor,
    required ValueChanged<bool> onChanged,
  }) {
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.subtitle(context).copyWith(
                  fontWeight: FontWeight.w500,
                  color: textPrimaryColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTypography.caption(
                  context,
                ).copyWith(color: textSecondaryColor),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: iconActiveColor,
          inactiveThumbColor: textSecondaryColor,
          inactiveTrackColor: cardBackgroundColor,
        ),
      ],
    );
  }

  String _getFontFamilyLabel(AppFontFamily font) {
    switch (font) {
      case AppFontFamily.system:
        return 'System Default';
      case AppFontFamily.inter:
        return 'Inter';
      case AppFontFamily.poppins:
        return 'Poppins';
      case AppFontFamily.roboto:
        return 'Roboto';
      case AppFontFamily.montserrat:
        return 'Montserrat';
      case AppFontFamily.notoSans:
        return 'Noto Sans';
    }
  }

  String _getFontFamilyDescription(AppFontFamily font) {
    switch (font) {
      case AppFontFamily.system:
        return 'Use device default font';
      case AppFontFamily.inter:
        return 'Modern & clean design';
      case AppFontFamily.poppins:
        return 'Geometric sans-serif';
      case AppFontFamily.roboto:
        return 'Google\'s signature font';
      case AppFontFamily.montserrat:
        return 'Elegant & versatile';
      case AppFontFamily.notoSans:
        return 'Highly readable';
    }
  }

  // Replace your _showFontFamilyPicker method in appearance_page.dart with this:

  String _getRoundnessLabel(ThumbnailRoundness roundness) {
    switch (roundness) {
      case ThumbnailRoundness.light:
        return 'Light (15%)';
      case ThumbnailRoundness.medium:
        return 'Medium (25%)';
      case ThumbnailRoundness.heavy:
        return 'Heavy (50%)';
    }
  }

  double _getRadiusForRoundness(ThumbnailRoundness roundness) {
    switch (roundness) {
      case ThumbnailRoundness.light:
        return 0.15;
      case ThumbnailRoundness.medium:
        return 0.25;
      case ThumbnailRoundness.heavy:
        return 0.50;
    }
  }

  String _getLyricsProviderLabel(lyrics_provider.LyricsSource source) {
    switch (source) {
      case lyrics_provider.LyricsSource.kugou:
        return 'KuGou (Word by word)';
      case lyrics_provider.LyricsSource.someRandomApi:
        return 'SomeRandomAPI (Line by line)';
    }
  }
}
