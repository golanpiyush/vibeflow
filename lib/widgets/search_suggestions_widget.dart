// lib/widgets/search_suggestions_widget.dart
import 'package:flutter/material.dart';
import 'package:vibeflow/api_base/yt_music_search_suggestor.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';

/// Widget that displays search suggestions or recent searches
/// Shows history when query is empty, suggestions when typing
class SearchSuggestionsWidget extends StatefulWidget {
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
  State<SearchSuggestionsWidget> createState() =>
      _SearchSuggestionsWidgetState();
}

class _SearchSuggestionsWidgetState extends State<SearchSuggestionsWidget> {
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
    final isEmpty = widget.query.trim().isEmpty;
    final hasHistory = _suggestions.any((s) => s.isHistory);

    return Container(
      color: AppColors.background,
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
                    style: AppTypography.sectionHeader.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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
                      style: AppTypography.caption.copyWith(
                        color: AppColors.accent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Loading indicator
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.textSecondary,
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
                  return _buildSuggestionItem(suggestion);
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
                        color: AppColors.textSecondary.withOpacity(0.4),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No recent searches',
                        style: AppTypography.subtitle.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your search history will appear here',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary.withOpacity(0.7),
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

  Widget _buildSuggestionItem(SearchSuggestion suggestion) {
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
                      ? AppColors.accent.withOpacity(0.12)
                      : AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  suggestion.isHistory ? Icons.history : Icons.search,
                  color: suggestion.isHistory
                      ? AppColors.accent
                      : AppColors.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // Suggestion text
              Expanded(
                child: Text(
                  suggestion.text,
                  style: AppTypography.songTitle.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Actions
              if (suggestion.isHistory)
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.textSecondary,
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
                  color: AppColors.textSecondary.withOpacity(0.6),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact version for use in overlays or dropdowns
class CompactSearchSuggestions extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
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
