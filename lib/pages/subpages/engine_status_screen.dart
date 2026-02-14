import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/managers/vibeflow_engine_logger.dart';
import 'package:vibeflow/models/engine_logs.dart';
import 'package:vibeflow/utils/theme_provider.dart';

class EngineStatusScreen extends ConsumerStatefulWidget {
  const EngineStatusScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<EngineStatusScreen> createState() => _EngineStatusScreenState();
}

class _EngineStatusScreenState extends ConsumerState<EngineStatusScreen>
    with SingleTickerProviderStateMixin {
  final _logger = VibeFlowEngineLogger();
  late TabController _tabController;
  String _selectedCategory = 'ALL';
  bool _autoScroll = true;
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Listen for log updates and auto-scroll
    _logger.addListener(_onLogUpdate);
  }

  void _onLogUpdate() {
    if (_autoScroll && _logScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _logScrollController.dispose();
    _logger.removeListener(_onLogUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = ref.watch(themeBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimaryColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(
              Icons.settings_input_component,
              color: _logger.isEngineInitialized ? Colors.green : Colors.grey,
              size: 24,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Engine Status',
                  style: AppTypography.pageTitle(
                    context,
                  ).copyWith(color: textPrimaryColor, fontSize: 18),
                ),
                Text(
                  _logger.isEngineInitialized ? 'Running' : 'Offline',
                  style: TextStyle(
                    color: _logger.isEngineInitialized
                        ? Colors.green
                        : textSecondaryColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: iconActiveColor),
            onPressed: () => setState(() {}),
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: iconActiveColor,
          unselectedLabelColor: textSecondaryColor,
          indicatorColor: iconActiveColor,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Logs'),
            Tab(text: 'Stats'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildOverviewTab(), _buildLogsTab(), _buildStatsTab()],
      ),
    );
  }

  // OVERVIEW TAB
  Widget _buildOverviewTab() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return ListenableBuilder(
      listenable: _logger,
      builder: (context, _) {
        final uptime = _logger.initializationTime != null
            ? DateTime.now().difference(_logger.initializationTime!)
            : null;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Engine Status Card
              _buildInfoCard(
                title: 'Engine Status',
                icon: Icons.settings_input_component,
                iconColor: _logger.isEngineInitialized
                    ? Colors.green
                    : Colors.grey,
                children: [
                  _buildInfoRow(
                    'Status',
                    _logger.isEngineInitialized
                        ? 'Initialized ✓'
                        : 'Not Initialized',
                    _logger.isEngineInitialized ? Colors.green : Colors.orange,
                  ),
                  if (_logger.initializationTime != null) ...[
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      'Initialized At',
                      _formatDateTime(_logger.initializationTime!),
                      textSecondaryColor,
                    ),
                  ],
                  if (uptime != null) ...[
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      'Uptime',
                      _formatDuration(uptime),
                      textSecondaryColor,
                    ),
                  ],
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // Active Operations Card
              _buildInfoCard(
                title: 'Active Operations',
                icon: Icons.sync,
                iconColor: _logger.activeOperations.isEmpty
                    ? textSecondaryColor
                    : iconActiveColor,
                children: [
                  if (_logger.activeOperations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No active operations',
                        style: TextStyle(
                          color: textSecondaryColor,
                          fontSize: 14,
                        ),
                      ),
                    )
                  else
                    ..._logger.activeOperations.map((op) {
                      final duration = _logger.getOperationDuration(op);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                op,
                                style: TextStyle(
                                  color: textPrimaryColor,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (duration != null)
                              Text(
                                '${duration.inSeconds}s',
                                style: TextStyle(
                                  color: textSecondaryColor,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // Quick Stats Card
              _buildInfoCard(
                title: 'Quick Stats',
                icon: Icons.analytics,
                iconColor: iconActiveColor,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          'Total Fetches',
                          _logger.totalFetches.toString(),
                          Icons.download,
                          textPrimaryColor,
                          textSecondaryColor,
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          'Cache Hits',
                          _logger.cacheHits.toString(),
                          Icons.bolt,
                          textPrimaryColor,
                          textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          'Success Rate',
                          '${_logger.successRate.toStringAsFixed(1)}%',
                          Icons.check_circle,
                          textPrimaryColor,
                          textSecondaryColor,
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          'Enrichments',
                          _logger.totalEnrichments.toString(),
                          Icons.auto_awesome,
                          textPrimaryColor,
                          textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // Recent Activity
              _buildInfoCard(
                title: 'Recent Activity',
                icon: Icons.history,
                iconColor: iconActiveColor,
                children: [
                  if (_logger.logs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No recent activity',
                        style: TextStyle(
                          color: textSecondaryColor,
                          fontSize: 14,
                        ),
                      ),
                    )
                  else
                    ..._logger.getRecentLogs(5).reversed.map((log) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _getLogIcon(log.level),
                              size: 16,
                              color: _getLogColor(log.level),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    log.message,
                                    style: TextStyle(
                                      color: textPrimaryColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    log.formattedTime,
                                    style: TextStyle(
                                      color: textSecondaryColor,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // LOGS TAB
  Widget _buildLogsTab() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return ListenableBuilder(
      listenable: _logger,
      builder: (context, _) {
        final filteredLogs = _selectedCategory == 'ALL'
            ? _logger.logs
            : _logger.getLogsByCategory(_selectedCategory);

        return Column(
          children: [
            // Filter and Controls
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              color: cardBackgroundColor,
              child: Column(
                children: [
                  // Category Filter
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildCategoryChip(
                          'ALL',
                          textPrimaryColor,
                          textSecondaryColor,
                          iconActiveColor,
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'INIT',
                          textPrimaryColor,
                          textSecondaryColor,
                          iconActiveColor,
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'FETCH',
                          textPrimaryColor,
                          textSecondaryColor,
                          iconActiveColor,
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'CACHE',
                          textPrimaryColor,
                          textSecondaryColor,
                          iconActiveColor,
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'ENRICH',
                          textPrimaryColor,
                          textSecondaryColor,
                          iconActiveColor,
                        ),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                          'BATCH',
                          textPrimaryColor,
                          textSecondaryColor,
                          iconActiveColor,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Controls
                  Row(
                    children: [
                      // Auto-scroll toggle
                      InkWell(
                        onTap: () => setState(() => _autoScroll = !_autoScroll),
                        child: Row(
                          children: [
                            Icon(
                              _autoScroll ? Icons.play_arrow : Icons.pause,
                              size: 18,
                              color: _autoScroll
                                  ? Colors.green
                                  : textSecondaryColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Auto-scroll',
                              style: TextStyle(
                                color: textSecondaryColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Log count
                      Text(
                        '${filteredLogs.length} logs',
                        style: TextStyle(
                          color: textSecondaryColor,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Clear button
                      TextButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Clear Logs?'),
                              content: const Text(
                                'This will clear all log entries. This action cannot be undone.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _logger.clearLogs();
                                    Navigator.pop(context);
                                  },
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Colors.red,
                        ),
                        label: Text(
                          'Clear',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Logs List
            Expanded(
              child: filteredLogs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 48,
                            color: textSecondaryColor.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No logs available',
                            style: TextStyle(color: textSecondaryColor),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _logScrollController,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, index) {
                        final log = filteredLogs[index];
                        return _buildLogEntry(log);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // STATS TAB
  Widget _buildStatsTab() {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final iconActiveColor = ref.watch(themeIconActiveColorProvider);

    return ListenableBuilder(
      listenable: _logger,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fetch Statistics
              _buildInfoCard(
                title: 'Fetch Statistics',
                icon: Icons.download,
                iconColor: iconActiveColor,
                children: [
                  _buildStatBar(
                    'Successful',
                    _logger.successfulFetches,
                    _logger.totalFetches,
                    Colors.green,
                    textPrimaryColor,
                    textSecondaryColor,
                  ),
                  const SizedBox(height: 12),
                  _buildStatBar(
                    'Failed',
                    _logger.failedFetches,
                    _logger.totalFetches,
                    Colors.red,
                    textPrimaryColor,
                    textSecondaryColor,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            '${_logger.successRate.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Success Rate',
                            style: TextStyle(
                              color: textSecondaryColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            _logger.totalFetches.toString(),
                            style: TextStyle(
                              color: textPrimaryColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Total Fetches',
                            style: TextStyle(
                              color: textSecondaryColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // Cache Statistics
              _buildInfoCard(
                title: 'Cache Statistics',
                icon: Icons.storage,
                iconColor: iconActiveColor,
                children: [
                  _buildStatBar(
                    'Cache Hits',
                    _logger.cacheHits,
                    _logger.cacheHits + _logger.cacheMisses,
                    Colors.blue,
                    textPrimaryColor,
                    textSecondaryColor,
                  ),
                  const SizedBox(height: 12),
                  _buildStatBar(
                    'Cache Misses',
                    _logger.cacheMisses,
                    _logger.cacheHits + _logger.cacheMisses,
                    Colors.orange,
                    textPrimaryColor,
                    textSecondaryColor,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            '${_logger.cacheHitRate.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Hit Rate',
                            style: TextStyle(
                              color: textSecondaryColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            '${_logger.cacheHits + _logger.cacheMisses}',
                            style: TextStyle(
                              color: textPrimaryColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Total Requests',
                            style: TextStyle(
                              color: textSecondaryColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // Enrichment Statistics
              _buildInfoCard(
                title: 'Enrichment Statistics',
                icon: Icons.auto_awesome,
                iconColor: iconActiveColor,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Text(
                          _logger.totalEnrichments.toString(),
                          style: TextStyle(
                            color: iconActiveColor,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Total Enrichments',
                          style: TextStyle(
                            color: textSecondaryColor,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // Reset Stats Button
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Reset Statistics?'),
                        content: const Text(
                          'This will reset all statistics counters to zero. Logs will not be affected.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              _logger.resetStats();
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Statistics reset'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset Statistics'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cardBackgroundColor,
                    foregroundColor: iconActiveColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Helper Widgets

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: textPrimaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color valueColor) {
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: textSecondaryColor, fontSize: 14)),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color textPrimaryColor,
    Color textSecondaryColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: textSecondaryColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: textSecondaryColor, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: textPrimaryColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(
    String category,
    Color textPrimaryColor,
    Color textSecondaryColor,
    Color activeColor,
  ) {
    final isSelected = _selectedCategory == category;

    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = category),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? activeColor
                : textSecondaryColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          category,
          style: TextStyle(
            color: isSelected ? activeColor : textSecondaryColor,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLogEntry(EngineLogEntry log) {
    final textPrimaryColor = ref.watch(themeTextPrimaryColorProvider);
    final textSecondaryColor = ref.watch(themeTextSecondaryColorProvider);
    final cardBackgroundColor = ref.watch(themeCardBackgroundColorProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getLogColor(log.level).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(
                _getLogIcon(log.level),
                size: 16,
                color: _getLogColor(log.level),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getLogColor(log.level).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  log.level,
                  style: TextStyle(
                    color: _getLogColor(log.level),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: textSecondaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  log.category,
                  style: TextStyle(color: textSecondaryColor, fontSize: 10),
                ),
              ),
              const Spacer(),
              Text(
                log.formattedTime,
                style: TextStyle(
                  color: textSecondaryColor,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Message
          Text(
            log.message,
            style: TextStyle(color: textPrimaryColor, fontSize: 13),
          ),

          // Video ID if present
          if (log.videoId != null) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: log.videoId!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Video ID copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Text(
                'ID: ${log.videoId}',
                style: TextStyle(
                  color: textSecondaryColor,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],

          // Song title if present
          if (log.songTitle != null) ...[
            const SizedBox(height: 4),
            Text(
              '♪ ${log.songTitle}',
              style: TextStyle(
                color: textSecondaryColor,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatBar(
    String label,
    int value,
    int total,
    Color color,
    Color textPrimaryColor,
    Color textSecondaryColor,
  ) {
    final percentage = total > 0 ? (value / total) * 100 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: textSecondaryColor, fontSize: 14),
            ),
            Text(
              '$value / $total (${percentage.toStringAsFixed(1)}%)',
              style: TextStyle(color: textPrimaryColor, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total > 0 ? value / total : 0,
            backgroundColor: textSecondaryColor.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  // Helper Methods

  IconData _getLogIcon(String level) {
    switch (level) {
      case 'SUCCESS':
        return Icons.check_circle;
      case 'ERROR':
        return Icons.error;
      case 'WARNING':
        return Icons.warning;
      case 'INFO':
      default:
        return Icons.info;
    }
  }

  Color _getLogColor(String level) {
    switch (level) {
      case 'SUCCESS':
        return Colors.green;
      case 'ERROR':
        return Colors.red;
      case 'WARNING':
        return Colors.orange;
      case 'INFO':
      default:
        return Colors.blue;
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}
