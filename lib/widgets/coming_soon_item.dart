// lib/widgets/coming_soon_item.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';

class ComingSoonItem extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const ComingSoonItem({
    Key? key,
    required this.title,
    this.subtitle,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final accentColor = ref.watch(themeIconActiveColorProvider);

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.subtitle(context).copyWith(
                      fontWeight: FontWeight.w500,
                      color: textPrimaryColor,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: textPrimaryColor.withOpacity(0.6),
                      decorationThickness: 2,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: accentColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'COMING SOON',
                    style: AppTypography.caption(context).copyWith(
                      color: accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: AppTypography.caption(context).copyWith(
                  color: textSecondaryColor,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: textSecondaryColor.withOpacity(0.6),
                  decorationThickness: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Alternative version with toggle switch (disabled)
class ComingSoonToggleItem extends ConsumerWidget {
  final String title;
  final String subtitle;
  final bool value;

  const ComingSoonToggleItem({
    Key? key,
    required this.title,
    required this.subtitle,
    this.value = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final accentColor = ref.watch(themeIconActiveColorProvider);

    return Opacity(
      opacity: 0.5,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.subtitle(context).copyWith(
                          fontWeight: FontWeight.w500,
                          color: textPrimaryColor,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: textPrimaryColor.withOpacity(0.6),
                          decorationThickness: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: accentColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'COMING SOON',
                        style: AppTypography.caption(context).copyWith(
                          color: accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTypography.caption(context).copyWith(
                    color: textSecondaryColor,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: textSecondaryColor.withOpacity(0.6),
                    decorationThickness: 1.5,
                  ),
                ),
              ],
            ),
          ),
          IgnorePointer(
            child: Switch(
              value: value,
              onChanged: null,
              activeColor: textSecondaryColor.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }
}

// Alternative version with navigation arrow (disabled)
class ComingSoonNavigationItem extends ConsumerWidget {
  final String title;
  final String subtitle;

  const ComingSoonNavigationItem({
    Key? key,
    required this.title,
    required this.subtitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final accentColor = ref.watch(themeIconActiveColorProvider);

    return Opacity(
      opacity: 0.5,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.subtitle(context).copyWith(
                          fontWeight: FontWeight.w500,
                          color: textPrimaryColor,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: textPrimaryColor.withOpacity(0.6),
                          decorationThickness: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: accentColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'COMING SOON',
                        style: AppTypography.caption(context).copyWith(
                          color: accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTypography.caption(context).copyWith(
                    color: textSecondaryColor,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: textSecondaryColor.withOpacity(0.6),
                    decorationThickness: 1.5,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: textSecondaryColor.withOpacity(0.3),
            size: 24,
          ),
        ],
      ),
    );
  }
}
