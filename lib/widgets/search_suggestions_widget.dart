// lib/widgets/search_suggestions_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/api_base/yt_music_search_suggestor.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';

/// Widget that displays search suggestions or recent searches
/// Shows history when query is empty, suggestions when typing
class SearchSuggestionsWidget extends ConsumerStatefulWidget {
  final String query;
  final Function(String) onSuggestionTap;
  final VoidCallback? onClearHistory;

  const SearchSuggestionsWidget({
    Key? key,
    required this.query,
    required this.onSuggestionTap,
    this.onClearHistory,
  }) : super(key: key);

  @override
  ConsumerState<SearchSuggestionsWidget> createState() =>
      _SearchSuggestionsWidgetState();
}

class _SearchSuggestionsWidgetState
    extends ConsumerState<SearchSuggestionsWidget> {
  final YTMusicSuggestionsHelper _suggestionsHelper =
      YTMusicSuggestionsHelper();
  List<SearchSuggestion> _suggestions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void didUpdateWidget(SearchSuggestionsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _loadSuggestions();
    }
  }

  Future<void> _loadSuggestions() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final suggestions = await _suggestionsHelper.getCombinedSuggestions(
        widget.query,
      );
      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _isLoading = false;
        });
        print(
          '🎯 Loaded ${suggestions.length} suggestions for "${widget.query}"',
        );
      }
    } catch (e) {
      print('❌ Error loading suggestions: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removeHistoryItem(String query) async {
    await _suggestionsHelper.removeFromHistory(query);
    _loadSuggestions();
  }

  Future<void> _clearAllHistory() async {
    await _suggestionsHelper.clearHistory();
    _loadSuggestions();
    widget.onClearHistory?.call();
  }

  @override
  void dispose() {
    _suggestionsHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isEmpty = widget.query.trim().isEmpty;
    final hasHistory = _suggestions.any((s) => s.isHistory);

    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header for recent searches
          if (isEmpty && hasHistory)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Searches',
                    style:
                        theme.textTheme.titleSmall?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ) ??
                        AppTypography.sectionHeader(
                          context,
                        ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  TextButton(
                    onPressed: _clearAllHistory,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Clear All',
                      style:
                          theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.primary,
                            fontSize: 12,
                          ) ??
                          AppTypography.caption(
                            context,
                          ).copyWith(color: colorScheme.primary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // Loading indicator
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: CircularProgressIndicator(
                  color: colorScheme.onSurface.withOpacity(0.6),
                  strokeWidth: 2,
                ),
              ),
            ),

          // Suggestions list
          if (!_isLoading && _suggestions.isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return _buildSuggestionItem(suggestion, theme, colorScheme);
                },
              ),
            ),

          // Empty state for history
          if (!_isLoading && _suggestions.isEmpty && isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 56,
                        color: colorScheme.onSurface.withOpacity(0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No recent searches',
                        style:
                            theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ) ??
                            AppTypography.subtitle(context).copyWith(
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your search history will appear here',
                        style:
                            theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.5),
                              fontSize: 12,
                            ) ??
                            AppTypography.caption(context).copyWith(
                              color: colorScheme.onSurface.withOpacity(0.5),
                              fontSize: 12,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestionItem(
    SearchSuggestion suggestion,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSuggestionTap(suggestion.text),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              // Icon (history or search)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: suggestion.isHistory
                      ? colorScheme.primary.withOpacity(0.12)
                      : theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  suggestion.isHistory ? Icons.history : Icons.search,
                  color: suggestion.isHistory
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(0.6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Suggestion text
              Expanded(
                child: Text(
                  suggestion.text,
                  style:
                      theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                      ) ??
                      AppTypography.songTitle(
                        context,
                      ).copyWith(color: colorScheme.onSurface, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Actions
              if (suggestion.isHistory)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                  onPressed: () => _removeHistoryItem(suggestion.text),
                  splashRadius: 20,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                )
              else
                Icon(
                  Icons.north_west,
                  size: 16,
                  color: colorScheme.onSurface.withOpacity(0.4),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact version for use in overlays or dropdowns
class CompactSearchSuggestions extends ConsumerWidget {
  final String query;
  final Function(String) onSuggestionTap;
  final int maxItems;

  const CompactSearchSuggestions({
    Key? key,
    required this.query,
    required this.onSuggestionTap,
    this.maxItems = 8,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SearchSuggestionsWidget(
        query: query,
        onSuggestionTap: onSuggestionTap,
      ),
    );
  }
}
