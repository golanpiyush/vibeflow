import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/constants/theme_colors.dart';
import 'package:vibeflow/managers/vibeflow_engine_logger.dart';
import 'package:vibeflow/models/engine_logs.dart';
import 'package:vibeflow/pages/subpages/engine_rate_limit_provider.dart';
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
  List<DateTime> _engineActionTimestamps = [];
  DateTime? _blockUntil;

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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: ref.watch(themeTextPrimaryColorProvider),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: ListenableBuilder(
          listenable: _logger,
          builder: (context, _) {
            final isRunning = _logger.isEngineInitialized;
            return Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Icon(
                    isRunning
                        ? Icons.settings_input_component
                        : Icons.power_settings_new,
                    key: ValueKey(isRunning),
                    color: isRunning ? Colors.green : Colors.red,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Engine Status',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: ref.watch(themeTextPrimaryColorProvider),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        isRunning ? 'Running' : 'Offline',
                        key: ValueKey(isRunning),
                        style: textTheme.bodySmall?.copyWith(
                          color: isRunning ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colorScheme.primary),
            onPressed: () => setState(() {}),
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: ref.watch(themeTextSecondaryColorProvider),
          indicatorColor: colorScheme.primary,
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

  Widget _buildOverviewTab() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

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
                      ref.watch(themeTextSecondaryColorProvider),
                    ),
                  ],
                  if (uptime != null) ...[
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      'Uptime',
                      _formatDuration(uptime),
                      ref.watch(themeTextSecondaryColorProvider),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ADD as first item in the Column children list in _buildOverviewTab:
              _buildEngineControls(),
              const SizedBox(height: AppSpacing.lg),

              // Active Operations Card
              _buildInfoCard(
                title: 'Active Operations',
                icon: Icons.sync,
                iconColor: _logger.activeOperations.isEmpty
                    ? colorScheme.onSurface.withOpacity(0.6)
                    : colorScheme.primary,
                children: [
                  if (_logger.activeOperations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No active operations',
                        style: textTheme.bodyMedium?.copyWith(
                          color: ref.watch(themeTextSecondaryColorProvider),
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
                                style: textTheme.bodyMedium?.copyWith(
                                  color: ref.watch(
                                    themeTextPrimaryColorProvider,
                                  ),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (duration != null)
                              Text(
                                '${duration.inSeconds}s',
                                style: textTheme.bodySmall?.copyWith(
                                  color: ref.watch(
                                    themeTextSecondaryColorProvider,
                                  ),
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
                iconColor: colorScheme.primary,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatItem(
                          'Total Fetches',
                          _logger.totalFetches.toString(),
                          Icons.download,
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          'Cache Hits',
                          _logger.cacheHits.toString(),
                          Icons.bolt,
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
                        ),
                      ),
                      Expanded(
                        child: _buildStatItem(
                          'Enrichments',
                          _logger.totalEnrichments.toString(),
                          Icons.auto_awesome,
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
                iconColor: colorScheme.primary,
                children: [
                  if (_logger.logs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No recent activity',
                        style: textTheme.bodyMedium?.copyWith(
                          color: ref.watch(themeTextPrimaryColorProvider),
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
                                    style: textTheme.bodySmall?.copyWith(
                                      color: ref.watch(
                                        themeTextPrimaryColorProvider,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    log.formattedTime,
                                    style: textTheme.bodySmall?.copyWith(
                                      fontSize: 10,
                                      color: ref.watch(
                                        themeTextSecondaryColorProvider,
                                      ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

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
              color: colorScheme.surface,
              child: Column(
                children: [
                  // Category Filter
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildCategoryChip('ALL'),
                        const SizedBox(width: 8),
                        _buildCategoryChip('INIT'),
                        const SizedBox(width: 8),
                        _buildCategoryChip('FETCH'),
                        const SizedBox(width: 8),
                        _buildCategoryChip('CACHE'),
                        const SizedBox(width: 8),
                        _buildCategoryChip('ENRICH'),
                        const SizedBox(width: 8),
                        _buildCategoryChip('BATCH'),
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
                                  : ref.watch(themeTextSecondaryColorProvider),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Auto-scroll',
                              style: textTheme.bodySmall?.copyWith(
                                color: ref.watch(themeTextPrimaryColorProvider),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Log count
                      Text(
                        '${filteredLogs.length} logs',
                        style: textTheme.bodySmall?.copyWith(
                          color: ref.watch(themeTextPrimaryColorProvider),
                        ),
                      ),

                      const SizedBox(width: 16),
                      // Clear button
                      TextButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: colorScheme.surface,
                              title: Text(
                                'Clear Logs?',
                                style: textTheme.titleLarge?.copyWith(
                                  color: ref.watch(
                                    themeTextPrimaryColorProvider,
                                  ),
                                ),
                              ),
                              content: Text(
                                'This will clear all log entries. This action cannot be undone.',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: ref.watch(
                                    themeTextSecondaryColorProvider,
                                  ),
                                ),
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
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Colors.red,
                        ),
                        label: Text(
                          'Clear',
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.red,
                          ),
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
                            color: ref.watch(themeTextSecondaryColorProvider),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No logs available',
                            style: textTheme.bodyMedium?.copyWith(
                              color: ref.watch(themeTextSecondaryColorProvider),
                            ),
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
            const SizedBox(height: AppSpacing.fourxxxl),
          ],
        );
      },
    );
  }

  // STATS TAB
  Widget _buildStatsTab() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

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
                iconColor: colorScheme.primary,
                children: [
                  _buildStatBar(
                    'Successful',
                    _logger.successfulFetches,
                    _logger.totalFetches,
                    Colors.green,
                  ),
                  const SizedBox(height: 12),
                  _buildStatBar(
                    'Failed',
                    _logger.failedFetches,
                    _logger.totalFetches,
                    Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            '${_logger.successRate.toStringAsFixed(1)}%',
                            style: textTheme.headlineMedium?.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Success Rate',
                            style: textTheme.bodySmall?.copyWith(
                              color: ref.watch(themeTextSecondaryColorProvider),
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            _logger.totalFetches.toString(),
                            style: textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: ref.watch(themeTextPrimaryColorProvider),
                            ),
                          ),
                          Text(
                            'Total Fetches',
                            style: textTheme.bodySmall?.copyWith(
                              color: ref.watch(themeTextSecondaryColorProvider),
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
                iconColor: colorScheme.primary,
                children: [
                  _buildStatBar(
                    'Cache Hits',
                    _logger.cacheHits,
                    _logger.cacheHits + _logger.cacheMisses,
                    Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  _buildStatBar(
                    'Cache Misses',
                    _logger.cacheMisses,
                    _logger.cacheHits + _logger.cacheMisses,
                    Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text(
                            '${_logger.cacheHitRate.toStringAsFixed(1)}%',
                            style: textTheme.headlineMedium?.copyWith(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Hit Rate',
                            style: textTheme.bodySmall?.copyWith(
                              color: ref.watch(themeTextSecondaryColorProvider),
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            '${_logger.cacheHits + _logger.cacheMisses}',
                            style: textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: ref.watch(themeTextPrimaryColorProvider),
                            ),
                          ),
                          Text(
                            'Total Requests',
                            style: textTheme.bodySmall?.copyWith(
                              color: ref.watch(themeTextSecondaryColorProvider),
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
                iconColor: colorScheme.primary,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Text(
                          _logger.totalEnrichments.toString(),
                          style: textTheme.displaySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Total Enrichments',
                          style: textTheme.bodyMedium?.copyWith(
                            color: ref.watch(themeTextSecondaryColorProvider),
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
                        backgroundColor: colorScheme.surface,
                        title: Text(
                          'Reset Statistics?',
                          style: textTheme.titleLarge?.copyWith(
                            color: ref.watch(themeTextPrimaryColorProvider),
                          ),
                        ),
                        content: Text(
                          'This will reset all statistics counters to zero. Logs will not be affected.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: ref.watch(themeTextSecondaryColorProvider),
                          ),
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
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    foregroundColor: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEngineControls() {
    final textPrimary = ref.watch(themeTextPrimaryColorProvider);
    final textSecondary = ref.watch(themeTextSecondaryColorProvider);
    final isStopped = !_logger.isEngineInitialized;

    // Watch rate limit notifier to get access to methods
    final rateLimitNotifier = ref.watch(engineRateLimitProvider.notifier);
    final rateLimitState = ref.watch(engineRateLimitProvider);

    // Access state properties directly
    final isBlocked =
        rateLimitState.blockUntil != null &&
        DateTime.now().isBefore(rateLimitState.blockUntil!);

    final remainingBlockSeconds = rateLimitState.blockUntil != null
        ? rateLimitState.blockUntil!.difference(DateTime.now()).inSeconds
        : 0;

    final isButtonDisabled = isBlocked;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        children: [
          // Block overlay message (shown when rate limited)
          if (isButtonDisabled)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.timer_off_rounded,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You seem to be abusing the engine wait for ${_formatBlockTime(remainingBlockSeconds)} before trying again xd.',
                      style: TextStyle(
                        color: Colors.orange.shade300,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              // Stop Button
              Expanded(
                child: GestureDetector(
                  onTap: isStopped || isButtonDisabled
                      ? null
                      : () => _showStopConfirmation(),
                  child: AnimatedOpacity(
                    opacity: isStopped || isButtonDisabled ? 0.35 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(
                          isStopped || isButtonDisabled ? 0.05 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withOpacity(
                            isStopped || isButtonDisabled ? 0.2 : 0.4,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.stop_circle_outlined,
                            color: Colors.red.withOpacity(
                              isStopped || isButtonDisabled ? 0.4 : 1.0,
                            ),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getStopButtonText(isStopped, isButtonDisabled),
                            style: TextStyle(
                              color: Colors.red.withOpacity(
                                isStopped || isButtonDisabled ? 0.4 : 1.0,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Restart Button
              Expanded(
                child: GestureDetector(
                  onTap: isButtonDisabled
                      ? null
                      : () => _showRestartConfirmation(),
                  child: AnimatedOpacity(
                    opacity: isButtonDisabled ? 0.35 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(
                          isButtonDisabled ? 0.05 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withOpacity(
                            isButtonDisabled ? 0.2 : 0.4,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.restart_alt,
                            color: Colors.green.withOpacity(
                              isButtonDisabled ? 0.4 : 1.0,
                            ),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getRestartButtonText(isStopped, isButtonDisabled),
                            style: TextStyle(
                              color: Colors.green.withOpacity(
                                isButtonDisabled ? 0.4 : 1.0,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  // HELPER WIDGETS

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
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
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ref.watch(themeTextPrimaryColorProvider),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(
            color: ref.watch(themeTextSecondaryColorProvider),
          ),
        ),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: ref.watch(themeTextSecondaryColorProvider),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: ref.watch(themeTextSecondaryColorProvider),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: ref.watch(themeTextPrimaryColorProvider),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(String category) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isSelected = _selectedCategory == category;

    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = category),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          category,
          style: textTheme.bodySmall?.copyWith(
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : ref.watch(themeTextSecondaryColorProvider),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLogEntry(EngineLogEntry log) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
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
                  style: textTheme.bodySmall?.copyWith(
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
                  color: colorScheme.outline.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  log.category,
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: ref.watch(themeTextPrimaryColorProvider),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                log.formattedTime,
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: ref.watch(themeTextSecondaryColorProvider),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Message
          Text(
            log.message,
            style: textTheme.bodyMedium?.copyWith(
              color: ref.watch(themeTextPrimaryColorProvider),
            ),
          ),

          // Video ID if present
          if (log.videoId != null) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: log.videoId!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Track-id copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Text(
                'Track-id: ${log.videoId}',
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: ref.watch(themeTextSecondaryColorProvider),
                ),
              ),
            ),
          ],

          // Song title if present
          if (log.songTitle != null) ...[
            const SizedBox(height: 4),
            Text(
              '♪ ${log.songTitle}',
              style: textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: ref.watch(themeTextSecondaryColorProvider),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatBar(String label, int value, int total, Color color) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final percentage = total > 0 ? (value / total) * 100 : 0.0;
    final textPrimary = ref.watch(themeTextPrimaryColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: textTheme.bodyMedium?.copyWith(color: textPrimary),
            ),

            Text(
              '$value / $total (${percentage.toStringAsFixed(1)}%)',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total > 0 ? value / total : 0,
            backgroundColor: colorScheme.outline.withOpacity(0.2),
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

  String _formatBlockTime(int seconds) {
    if (seconds >= 60) {
      final minutes = (seconds / 60).floor();
      final remainingSeconds = seconds % 60;
      return '$minutes min ${remainingSeconds} sec';
    }
    return '$seconds sec';
  }

  String _getStopButtonText(bool isStopped, bool isBlocked) {
    if (isBlocked) return 'Rate Limited';
    if (isStopped) return 'Already Stopped';
    return 'Stop Engine';
  }

  String _getRestartButtonText(bool isStopped, bool isBlocked) {
    if (isBlocked) return 'Rate Limited';
    return isStopped ? 'Restart Engine' : 'Restart';
  }

  void _recordEngineAction() {
    final now = DateTime.now();
    final actionType = _lastActionType;
    final rateLimitNotifier = ref.read(engineRateLimitProvider.notifier);
    final currentState = ref.read(engineRateLimitProvider);

    // Check if we're already blocked
    final isCurrentlyBlocked =
        currentState.blockUntil != null &&
        DateTime.now().isBefore(currentState.blockUntil!);

    if (isCurrentlyBlocked) {
      // Don't record actions if already blocked
      return;
    }

    // Log the action
    _logger.logInfo(
      'Engine action recorded: $actionType',
      category: 'ENGINE',
      metadata: {
        'action': actionType,
        'actions_in_last_10s': currentState.actionTimestamps.length + 1,
      },
    );

    // Check if we're approaching the limit (will be 3 after adding)
    if (currentState.actionTimestamps.length >= 2) {
      _logger.logWarning(
        '⚠️ Approaching rate limit: ${currentState.actionTimestamps.length + 1} actions in 10 seconds',
        category: 'ENGINE',
        metadata: {
          'action_count': currentState.actionTimestamps.length + 1,
          'remaining_before_block':
              4 - (currentState.actionTimestamps.length + 1),
        },
      );
    }

    // Add the action
    rateLimitNotifier.addAction();

    // Check if we've just become blocked
    final newState = ref.read(engineRateLimitProvider);
    final becameBlocked =
        !isCurrentlyBlocked &&
        newState.blockUntil != null &&
        DateTime.now().isBefore(newState.blockUntil!);

    if (becameBlocked) {
      _logger.logWarning(
        '🚫 RATE LIMIT TRIGGERED: 4 engine actions in 10 seconds',
        category: 'ENGINE',
        metadata: {
          'action_count': 4,
          'block_duration_minutes': 10,
          'block_until': newState.blockUntil!.toIso8601String(),
        },
      );

      // Show rate limit warning
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Too many engine operations. Please wait 10 minutes.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Schedule unblock
      Future.delayed(const Duration(minutes: 10), () {
        if (mounted) {
          rateLimitNotifier.clearBlock();

          _logger.logInfo(
            '✅ Rate limit expired - engine controls re-enabled',
            category: 'ENGINE',
            metadata: {'block_duration_minutes': 10},
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Engine controls are now available again.'),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    }
  }

  // Add this class variable to track the last action type
  String _lastActionType = 'unknown';

  void _showStopConfirmation() {
    final textPrimary = ref.watch(themeTextPrimaryColorProvider);
    final textSecondary = ref.watch(themeTextSecondaryColorProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          'Stop Engine?',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will stop the VibeFlow Engine and kill all playback.',
          style: TextStyle(color: textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: textSecondary)),
          ),
          TextButton(
            onPressed: () {
              _lastActionType = 'stop'; // Set action type
              _recordEngineAction();
              _logger.stopEngine();
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Stop', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRestartConfirmation() {
    final textPrimary = ref.watch(themeTextPrimaryColorProvider);
    final textSecondary = ref.watch(themeTextSecondaryColorProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text(
          'Restart Engine?',
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will restart the VibeFlow Engine.',
          style: TextStyle(color: textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: textSecondary)),
          ),
          TextButton(
            onPressed: () {
              _lastActionType = 'restart'; // Set action type
              _recordEngineAction();
              _logger.restartEngine();
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('Restart', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }
}
