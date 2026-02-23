// lib/pages/subpages/settings/changelog_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/services/changelog_service.dart';
import 'package:shimmer/shimmer.dart';
import 'package:highlight/highlight.dart' as highlight;
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as md;

// ─── Severity Classification ────────────────────────────────────────────────

enum SeverityFilter { all, lessSevere, mid, highlySevere }

extension SeverityFilterLabel on SeverityFilter {
  String get label {
    switch (this) {
      case SeverityFilter.all:
        return 'All';
      case SeverityFilter.lessSevere:
        return 'Less Severe';
      case SeverityFilter.mid:
        return 'Mid';
      case SeverityFilter.highlySevere:
        return 'Highly Severe';
    }
  }

  IconData get icon {
    switch (this) {
      case SeverityFilter.all:
        return Icons.list_alt;
      case SeverityFilter.lessSevere:
        return Icons.info_outline;
      case SeverityFilter.mid:
        return Icons.warning_amber_outlined;
      case SeverityFilter.highlySevere:
        return Icons.error_outline;
    }
  }

  Color get chipColor {
    switch (this) {
      case SeverityFilter.all:
        return Colors.grey;
      case SeverityFilter.lessSevere:
        return const Color(0xFF4CAF50);
      case SeverityFilter.mid:
        return const Color(0xFFFF9800);
      case SeverityFilter.highlySevere:
        return const Color(0xFFF44336);
    }
  }
}

/// Heuristically classify a changelog entry's severity.
SeverityFilter _classifyEntry(ChangelogEntry entry) {
  final text = '${entry.title} ${entry.content}'.toLowerCase();

  // Highly severe: crashes, critical, data loss, corruption, security
  const highKeywords = [
    'crash',
    'critical',
    'data loss',
    'corruption',
    'security',
    'fatal',
    'freeze',
    'broken',
    'stopped',
    'not working',
    'stuck',
    'race condition',
    'deadlock',
    'memory leak',
    'out of memory',
  ];
  for (final kw in highKeywords) {
    if (text.contains(kw)) return SeverityFilter.highlySevere;
  }

  // Mid: bug fix, wrong, incorrect, stale, flicker, unexpected, lag
  const midKeywords = [
    'bug fix',
    'bug',
    'wrong',
    'incorrect',
    'stale',
    'flicker',
    'unexpected',
    'lag',
    'delay',
    'timing',
    'race',
    'duplicate',
    'missing',
    'not showing',
    'overwrite',
    'conflict',
  ];
  for (final kw in midKeywords) {
    if (text.contains(kw)) return SeverityFilter.mid;
  }

  // Everything else is less severe (refactors, enhancements, new features)
  return SeverityFilter.lessSevere;
}

// ─── Main Page ───────────────────────────────────────────────────────────────

class ChangelogPage extends ConsumerStatefulWidget {
  const ChangelogPage({Key? key}) : super(key: key);

  @override
  ConsumerState<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends ConsumerState<ChangelogPage> {
  String? _currentVersion;
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;
  String _searchQuery = '';
  SeverityFilter _severityFilter = SeverityFilter.all;
  List<ChangelogEntry> _filteredChangelog = [];
  List<ChangelogEntry>? _lastChangelog;
  String _lastQuery = '';
  SeverityFilter _lastSeverity = SeverityFilter.all;

  // Track expanded states — default false (collapsed) for ALL entries
  final Map<String, bool> _expandedStates = {};

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final shouldShow = _scrollController.offset > 400;
    if (shouldShow != _showBackToTop) {
      setState(() => _showBackToTop = shouldShow);
    }
  }

  Future<void> _loadCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _currentVersion = info.version;
        _isLoading = false;
      });
    }
  }

  void _filterChangelog(List<ChangelogEntry> changelog) {
    // Skip recompute if nothing changed
    if (_lastChangelog == changelog &&
        _lastQuery == _searchQuery &&
        _lastSeverity == _severityFilter &&
        _filteredChangelog.isNotEmpty)
      return;

    _lastChangelog = changelog;
    _lastQuery = _searchQuery;
    _lastSeverity = _severityFilter;

    var results = changelog;

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      results = results.where((e) {
        return e.version.toLowerCase().contains(q) ||
            e.title.toLowerCase().contains(q) ||
            e.content.toLowerCase().contains(q);
      }).toList();
    }

    // Severity filter
    if (_severityFilter != SeverityFilter.all) {
      results = results
          .where((e) => _classifyEntry(e) == _severityFilter)
          .toList();
    }

    _filteredChangelog = results;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final changelogAsync = ref.watch(changelogProvider);

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildTopBar(context, colorScheme, iconActiveColor),
                _buildSearchBar(context, iconActiveColor),
                _buildSeverityFilter(context, iconActiveColor),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => ref.invalidate(changelogProvider),
                    color: iconActiveColor,
                    backgroundColor: colorScheme.surface,
                    child: changelogAsync.when(
                      data: (changelog) {
                        _filterChangelog(changelog);
                        if (changelog.isEmpty) {
                          return _buildEmptyState(context, iconActiveColor);
                        }
                        if (_filteredChangelog.isEmpty) {
                          return _buildNoSearchResults(
                            context,
                            iconActiveColor,
                          );
                        }
                        return _buildChangelogList(
                          context,
                          _filteredChangelog,
                          iconActiveColor,
                        );
                      },
                      loading: _buildShimmerLoading,
                      error: (error, _) => _buildErrorState(
                        context,
                        error.toString(),
                        iconActiveColor,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: AppSpacing.fourxxxl),
              ],
            ),
            if (_showBackToTop)
              Positioned(
                bottom: 20,
                right: 20,
                child: _buildBackToTopButton(iconActiveColor),
              ),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar(
    BuildContext context,
    ColorScheme colorScheme,
    Color iconActiveColor,
  ) {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(
              Icons.chevron_left,
              color: colorScheme.onSurface,
              size: 28,
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, color: iconActiveColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Changelog',
                  style: AppTypography.pageTitle(
                    context,
                  ).copyWith(color: colorScheme.onSurface),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  // ── Search Bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar(BuildContext context, Color iconActiveColor) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colorScheme.onSurface.withOpacity(0.1)),
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search versions...',
          hintStyle: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.4),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: iconActiveColor.withOpacity(0.7),
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: colorScheme.onSurface.withOpacity(0.4),
                    size: 18,
                  ),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
      ),
    );
  }

  // ── Severity Filter Chips ──────────────────────────────────────────────────

  Widget _buildSeverityFilter(BuildContext context, Color iconActiveColor) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: SeverityFilter.values.map((filter) {
          final selected = _severityFilter == filter;
          final chipColor = filter == SeverityFilter.all
              ? iconActiveColor
              : filter.chipColor;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _severityFilter = filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? chipColor.withOpacity(0.85)
                      : colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? chipColor
                        : colorScheme.onSurface.withOpacity(0.15),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      filter.icon,
                      size: 13,
                      color: selected
                          ? Colors.white
                          : colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      filter.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: selected
                            ? Colors.white
                            : colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Changelog List ─────────────────────────────────────────────────────────

  Widget _buildChangelogList(
    BuildContext context,
    List<ChangelogEntry> changelog,
    Color iconActiveColor,
  ) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: changelog.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildHeader(context, iconActiveColor, changelog);
        }
        final entry = changelog[index - 1];
        // Initialise all entries as collapsed
        _expandedStates.putIfAbsent(entry.id, () => false);

        return RepaintBoundary(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index > 1) _buildTimelineConnector(iconActiveColor),
              _ChangelogCard(
                key: ValueKey(entry.id),
                entry: entry,
                isLatest: index == 1,
                iconActiveColor: iconActiveColor,
                isExpanded: _expandedStates[entry.id] ?? false,
                onToggle: () => setState(() {
                  _expandedStates[entry.id] =
                      !(_expandedStates[entry.id] ?? false);
                }),
                severity: _classifyEntry(entry),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Header Card ────────────────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    Color iconActiveColor,
    List<ChangelogEntry> changelog,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            iconActiveColor.withOpacity(0.15),
            iconActiveColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: iconActiveColor.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconActiveColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.new_releases,
                  color: iconActiveColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Version History',
                      style: AppTypography.subtitle(context).copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      _isLoading ? 'Loading...' : 'Current: v$_currentVersion',
                      style: AppTypography.caption(
                        context,
                      ).copyWith(color: colorScheme.onSurface.withOpacity(0.6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                context,
                icon: Icons.update,
                value: '${changelog.length}',
                label: 'Updates',
                iconColor: iconActiveColor,
              ),
              _buildStatItem(
                context,
                icon: Icons.star,
                value: 'v${changelog.first.version}',
                label: 'Latest',
                iconColor: iconActiveColor,
              ),
              _buildStatItem(
                context,
                icon: Icons.calendar_today,
                value: _formatMonthYear(changelog.last.releaseDate),
                label: 'First release',
                iconColor: iconActiveColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 16, color: iconColor.withOpacity(0.8)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ],
    );
  }

  String _formatMonthYear(DateTime date) => '${date.month}/${date.year}';

  Widget _buildTimelineConnector(Color iconActiveColor) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      height: 30,
      width: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            iconActiveColor.withOpacity(0.5),
            iconActiveColor.withOpacity(0.2),
          ],
        ),
      ),
    );
  }

  // ── Shimmer / Empty / Error ────────────────────────────────────────────────

  Widget _buildShimmerLoading() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      children: const [
        ShimmerHeader(),
        SizedBox(height: 16),
        ShimmerChangelogCard(isLatest: true),
        SizedBox(height: 8),
        ShimmerChangelogCard(),
        SizedBox(height: 8),
        ShimmerChangelogCard(),
        SizedBox(height: 8),
        ShimmerChangelogCard(),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, Color iconActiveColor) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.new_releases_outlined,
            size: 64,
            color: iconActiveColor.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Changelog Entries',
            style: AppTypography.subtitle(
              context,
            ).copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later for updates\nand new features!',
            textAlign: TextAlign.center,
            style: AppTypography.caption(
              context,
            ).copyWith(color: colorScheme.onSurface.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSearchResults(BuildContext context, Color iconActiveColor) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = _severityFilter != SeverityFilter.all
        ? 'severity: ${_severityFilter.label}'
        : '"$_searchQuery"';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: iconActiveColor.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: AppTypography.subtitle(
              context,
            ).copyWith(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'No versions match $label',
            textAlign: TextAlign.center,
            style: AppTypography.caption(
              context,
            ).copyWith(color: colorScheme.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => setState(() {
              _searchQuery = '';
              _severityFilter = SeverityFilter.all;
            }),
            style: ElevatedButton.styleFrom(
              backgroundColor: iconActiveColor,
              foregroundColor: colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text('Clear Filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    String error,
    Color iconActiveColor,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red.withOpacity(0.7),
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load changelog',
            style: AppTypography.subtitle(
              context,
            ).copyWith(color: Colors.red, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error.length > 100 ? '${error.substring(0, 100)}...' : error,
              textAlign: TextAlign.center,
              style: AppTypography.caption(
                context,
              ).copyWith(color: Colors.red.withOpacity(0.7)),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => ref.invalidate(changelogProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: iconActiveColor,
              foregroundColor: colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackToTopButton(Color iconActiveColor) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: () => _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        ),
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: iconActiveColor.withOpacity(0.3)),
          ),
          child: Icon(Icons.arrow_upward, color: iconActiveColor, size: 24),
        ),
      ),
    );
  }
}

// ─── Changelog Card (extracted to StatefulWidget to avoid full-page rebuild) ─

class _ChangelogCard extends ConsumerStatefulWidget {
  final ChangelogEntry entry;
  final bool isLatest;
  final Color iconActiveColor;
  final bool isExpanded;
  final VoidCallback onToggle;
  final SeverityFilter severity;

  const _ChangelogCard({
    Key? key,
    required this.entry,
    required this.isLatest,
    required this.iconActiveColor,
    required this.isExpanded,
    required this.onToggle,
    required this.severity,
  }) : super(key: key);

  @override
  ConsumerState<_ChangelogCard> createState() => _ChangelogCardState();
}

class _ChangelogCardState extends ConsumerState<_ChangelogCard> {
  Future<void> _shareVersion() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sharing v${widget.entry.version}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyVersionLink() async {
    final versionNumber = widget.entry.version.startsWith('v')
        ? widget.entry.version
        : 'v${widget.entry.version}';
    final url =
        'https://github.com/golanpiyush/vibeflow/releases/tag/$versionNumber';
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Link copied to clipboard',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      versionNumber,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _viewOnGitHub() async {
    final versionNumber = widget.entry.version.startsWith('v')
        ? widget.entry.version
        : 'v${widget.entry.version}';
    final url =
        'https://github.com/golanpiyush/vibeflow/releases/tag/$versionNumber';

    // Check if the release exists on GitHub before redirecting
    bool releaseExists = false;
    try {
      final apiUrl =
          'https://api.github.com/repos/golanpiyush/vibeflow/releases/tags/$versionNumber';
      final response = await http
          .get(
            Uri.parse(apiUrl),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 6));
      releaseExists = response.statusCode == 200;
    } catch (_) {
      releaseExists = false;
    }

    if (!mounted) return;

    if (releaseExists) {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        debugPrint('Could not launch $url');
      }
    } else {
      _showInternalBuildDialog(versionNumber);
    }
  }

  void _showInternalBuildDialog(String versionNumber) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconActiveColor = widget.iconActiveColor;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: iconActiveColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.science_outlined,
                  color: iconActiveColor,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Internal Build',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),

              // Version chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: iconActiveColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: iconActiveColor.withOpacity(0.3)),
                ),
                child: Text(
                  versionNumber,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: iconActiveColor,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Body
              Text(
                'This version has not been published as a public release on GitHub. '
                'It is an internal or pre-release build distributed outside the standard release pipeline.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
              const SizedBox(height: 12),

              // Subtle note
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: colorScheme.onSurface.withOpacity(0.45),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Changes are logged here before a public tag is created.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.45),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Dismiss button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: iconActiveColor,
                    foregroundColor: colorScheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Got it',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  Color get _severityDotColor {
    switch (widget.severity) {
      case SeverityFilter.lessSevere:
        return const Color(0xFF4CAF50);
      case SeverityFilter.mid:
        return const Color(0xFFFF9800);
      case SeverityFilter.highlySevere:
        return const Color(0xFFF44336);
      case SeverityFilter.all:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconActiveColor = widget.iconActiveColor;
    final isExpanded = widget.isExpanded;
    final isLatest = widget.isLatest;
    final entry = widget.entry;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLatest
              ? iconActiveColor.withOpacity(0.5)
              : colorScheme.onSurface.withOpacity(0.1),
          width: isLatest ? 2 : 1,
        ),
        boxShadow: isLatest
            ? [
                BoxShadow(
                  color: iconActiveColor.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header (tappable) ──────────────────────────────────────────
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onToggle,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: isExpanded
                    ? Radius.zero
                    : const Radius.circular(20),
                bottomRight: isExpanded
                    ? Radius.zero
                    : const Radius.circular(20),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isLatest
                      ? iconActiveColor.withOpacity(0.1)
                      : colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: isExpanded
                        ? Radius.zero
                        : const Radius.circular(20),
                    bottomRight: isExpanded
                        ? Radius.zero
                        : const Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    // Version badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isLatest
                            ? iconActiveColor
                            : colorScheme.onSurface.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLatest) ...[
                            Icon(
                              Icons.star,
                              size: 14,
                              color: colorScheme.surface,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            'v${entry.version}',
                            style: TextStyle(
                              color: isLatest
                                  ? colorScheme.surface
                                  : colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Severity dot
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _severityDotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Auto-scrolling title
                    Expanded(
                      child: _MarqueeText(
                        text: entry.title,
                        style: AppTypography.subtitle(context).copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Date chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        entry.formattedDate,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Expand/collapse arrow
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: colorScheme.onSurface.withOpacity(0.5),
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Expandable body (AnimatedSize — much less laggy) ───────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: isExpanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(
                          height: 1,
                          color: colorScheme.onSurface.withOpacity(0.08),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: MarkdownBody(
                            data: entry.content,
                            styleSheet: MarkdownStyleSheet(
                              h1: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: iconActiveColor,
                                height: 1.3,
                              ),
                              h2: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                                height: 1.3,
                              ),
                              h3: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface.withOpacity(0.9),
                                height: 1.3,
                              ),
                              p: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurface.withOpacity(0.8),
                                height: 1.6,
                              ),
                              strong: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                              em: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: colorScheme.onSurface.withOpacity(0.9),
                              ),
                              code: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                backgroundColor: Colors.transparent,
                                color: Colors.transparent,
                              ),
                              listBullet: TextStyle(
                                fontSize: 14,
                                color: iconActiveColor,
                              ),
                              blockSpacing: 14,
                              listIndent: 20,
                            ),
                            onTapLink: (_, href, __) {
                              if (href != null) _launchUrl(href);
                            },
                            builders: {'code': CodeBlockBuilder()},
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              _ActionButton(
                                icon: Icons.open_in_new,
                                label: 'GitHub',
                                onTap: _viewOnGitHub,
                                iconColor: iconActiveColor,
                              ),
                              const SizedBox(width: 8),
                              _ActionButton(
                                icon: Icons.share_outlined,
                                label: 'Share',
                                onTap: _shareVersion,
                                iconColor: iconActiveColor,
                              ),
                              const SizedBox(width: 8),
                              _ActionButton(
                                icon: Icons.copy,
                                label: 'Copy',
                                onTap: _copyVersionLink,
                                iconColor: iconActiveColor,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Marquee (auto-scrolling) Text ───────────────────────────────────────────

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _MarqueeText({required this.text, this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late ScrollController _sc;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _sc = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndAnimate());
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  Future<void> _checkAndAnimate() async {
    if (!mounted) return;
    if (_sc.position.maxScrollExtent > 0) {
      if (!_needsScroll) setState(() => _needsScroll = true);
      _animate();
    }
  }

  Future<void> _animate() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || _sc.position.maxScrollExtent <= 0) break;
      await _sc.animateTo(
        _sc.position.maxScrollExtent,
        duration: Duration(
          milliseconds: (_sc.position.maxScrollExtent * 18).round(),
        ),
        curve: Curves.linear,
      );
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) break;
      await _sc.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _sc,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(widget.text, style: widget.style, maxLines: 1),
        );
      },
    );
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Syntax Highlighted Code Block ───────────────────────────────────────────

class SyntaxHighlightedCodeBlock extends ConsumerWidget {
  final String code;
  final String? language;
  final bool isInline;

  const SyntaxHighlightedCodeBlock({
    Key? key,
    required this.code,
    this.language,
    this.isInline = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    final result = highlight.highlight.parse(
      code,
      language: language ?? 'dart',
    );

    if (isInline) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isDark
              ? colorScheme.onSurface.withOpacity(0.15)
              : colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark
                ? colorScheme.primary.withOpacity(0.3)
                : colorScheme.primary.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: RichText(
          text: TextSpan(
            children: _buildSpans(result.nodes ?? [], colorScheme),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceVariant.withOpacity(0.3)
            : colorScheme.surfaceVariant.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? colorScheme.primary.withOpacity(0.2)
              : colorScheme.primary.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? colorScheme.primary.withOpacity(0.15)
                  : colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.code, size: 14, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  language ?? 'dart',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: RichText(
                text: TextSpan(
                  children: _buildSpans(result.nodes ?? [], colorScheme),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _buildSpans(
    List<highlight.Node> nodes,
    ColorScheme colorScheme,
  ) {
    final spans = <TextSpan>[];
    for (final node in nodes) {
      if (node.value is String) {
        spans.add(
          TextSpan(
            text: node.value as String,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: _getColorForClass(node.className, colorScheme),
            ),
          ),
        );
      } else if (node.children != null) {
        spans.addAll(_buildSpans(node.children!, colorScheme));
      }
    }
    return spans;
  }

  Color _getColorForClass(String? className, ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;
    switch (className) {
      case 'keyword':
        return isDark ? const Color(0xFFFF9E64) : const Color(0xFFD73A49);
      case 'string':
        return isDark ? const Color(0xFF9ECBFF) : const Color(0xFF032F62);
      case 'comment':
        return isDark ? const Color(0xFF7F848E) : const Color(0xFF6A737D);
      case 'number':
        return isDark ? const Color(0xFF79C0FF) : const Color(0xFF005CC5);
      case 'function':
        return isDark ? const Color(0xFFDCDCAA) : const Color(0xFF6F42C1);
      case 'class':
        return isDark ? const Color(0xFF4EC9B0) : const Color(0xFF22863A);
      default:
        return colorScheme.onSurface;
    }
  }
}

// ─── Markdown Builders ────────────────────────────────────────────────────────

class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? style) {
    final code = element.textContent;
    final language = element.attributes['class']?.replaceFirst('language-', '');
    return SyntaxHighlightedCodeBlock(
      code: code,
      language: language,
      isInline: false,
    );
  }
}

class InlineCodeBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? style) {
    return SyntaxHighlightedCodeBlock(
      code: element.textContent,
      isInline: true,
    );
  }
}

class PreBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? style) {
    if (element.children?.isNotEmpty == true) {
      final first = element.children!.first;
      if (first is md.Element) {
        final language = first.attributes['class']?.replaceFirst(
          'language-',
          '',
        );
        return SyntaxHighlightedCodeBlock(
          code: first.textContent,
          language: language,
          isInline: false,
        );
      }
    }
    return SyntaxHighlightedCodeBlock(
      code: element.textContent,
      isInline: false,
    );
  }
}

// ─── Shimmer Widgets ──────────────────────────────────────────────────────────

class ShimmerChangelogCard extends ConsumerWidget {
  final bool isLatest;
  const ShimmerChangelogCard({Key? key, this.isLatest = false})
    : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final baseColor = colorScheme.brightness == Brightness.dark
        ? Colors.grey[800]!
        : Colors.grey[300]!;
    final highlightColor = colorScheme.brightness == Brightness.dark
        ? Colors.grey[700]!
        : Colors.grey[100]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLatest
              ? iconActiveColor.withOpacity(0.5)
              : colorScheme.onSurface.withOpacity(0.1),
          width: isLatest ? 2 : 1,
        ),
      ),
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 70,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 60,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
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
}

class ShimmerHeader extends ConsumerWidget {
  const ShimmerHeader({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);
    final baseColor = colorScheme.brightness == Brightness.dark
        ? Colors.grey[800]!
        : Colors.grey[300]!;
    final highlightColor = colorScheme.brightness == Brightness.dark
        ? Colors.grey[700]!
        : Colors.grey[100]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            iconActiveColor.withOpacity(0.15),
            iconActiveColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: iconActiveColor.withOpacity(0.3), width: 1.5),
      ),
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 120,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 80,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Colors.transparent),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatShimmer(),
                _buildStatShimmer(),
                _buildStatShimmer(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatShimmer() {
    return Column(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 30,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 50,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

class ShimmerSearchBar extends ConsumerWidget {
  const ShimmerSearchBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.brightness == Brightness.dark
        ? Colors.grey[800]!
        : Colors.grey[300]!;
    final highlightColor = colorScheme.brightness == Brightness.dark
        ? Colors.grey[700]!
        : Colors.grey[100]!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),
    );
  }
}
