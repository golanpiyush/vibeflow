// lib/pages/user_taste_screen.dart
//
// "What VibeFlow knows about you" — user preference stats screen
// Shows: top artists, skip patterns, listening streaks, taste profile

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vibeflow/utils/user_preference_tracker.dart';

class UserTasteScreen extends StatefulWidget {
  const UserTasteScreen({Key? key}) : super(key: key);

  @override
  State<UserTasteScreen> createState() => _UserTasteScreenState();
}

class _UserTasteScreenState extends State<UserTasteScreen>
    with TickerProviderStateMixin {
  final _prefs = UserPreferenceTracker();

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;

  List<String> _topArtists = [];
  List<String> _avoidedArtists = [];
  Map<String, double> _artistScores = {};
  SkipAnalysis? _skipAnalysis;
  Map<String, dynamic> _stats = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadData();
  }

  Future<void> _loadData() async {
    await _prefs.initialize();

    final topArtists = _prefs.getTopArtists(limit: 10);
    final avoided = _prefs.getLeastPreferredArtists(limit: 5);
    final stats = _prefs.getStatistics();
    final skipAnalysis = _prefs.analyzeRecentSkips(lookbackCount: 10);

    // Get scores for top artists
    final scores = _prefs.getArtistScores(topArtists);

    // Just add this to setState:
    setState(() {
      _topArtists = topArtists;
      _avoidedArtists = avoided;
      _artistScores = scores;
      _skipAnalysis = skipAnalysis;
      _stats = stats;
      // completed songs are accessed directly via _prefs.getMostPlayedSongs()
      _isLoading = false;
    });

    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // Taste profile label based on skip & listen patterns
  String get _tasteProfile {
    final skips = _stats['total_skips_recorded'] as int? ?? 0;
    final artists = _stats['total_artists_tracked'] as int? ?? 0;

    if (artists == 0) return 'Explorer';
    if (skips == 0) return 'Easy Listener';

    final ratio = skips / (artists + 1);
    if (ratio > 5) return 'Picky Listener';
    if (ratio > 2) return 'Selective Ear';
    if (_topArtists.length > 5) return 'Genre Traveller';
    return 'Loyal Fan';
  }

  String get _tasteEmoji {
    switch (_tasteProfile) {
      case 'Picky Listener':
        return '🎯';
      case 'Selective Ear':
        return '👂';
      case 'Genre Traveller':
        return '🌍';
      case 'Loyal Fan':
        return '❤️';
      case 'Easy Listener':
        return '🌊';
      default:
        return '🔍';
    }
  }

  String get _tasteDescription {
    switch (_tasteProfile) {
      case 'Picky Listener':
        return 'You know exactly what you want. High standards, curated taste.';
      case 'Selective Ear':
        return 'Thoughtful listener. You give songs a chance but don\'t settle.';
      case 'Genre Traveller':
        return 'Wide taste, loves variety. Never stuck in one lane.';
      case 'Loyal Fan':
        return 'When you find an artist you love, you stick with them.';
      case 'Easy Listener':
        return 'Chill and open-minded. Almost everything sounds good to you.';
      default:
        return 'Just getting started. Keep listening to build your profile.';
    }
  }

  Color _scoreColor(double score) {
    if (score > 40) return const Color(0xFF4ADE80);
    if (score > 10) return const Color(0xFF86EFAC);
    if (score < -20) return const Color(0xFFF87171);
    if (score < -5) return const Color(0xFFFCA5A5);
    return const Color(0xFF94A3B8);
  }

  Color _barColor(double score) => _scoreColor(score);

  double _barWidth(double score, double maxScore) {
    if (maxScore == 0) return 0;
    return (score.abs() / maxScore).clamp(0.1, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF6EE7B7)),
            )
          : FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(
                slivers: [
                  _buildAppBar(),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 24),
                        _buildTasteProfileCard(),
                        const SizedBox(height: 28),
                        _buildStatsRow(),
                        const SizedBox(height: 28),
                        if (_topArtists.isNotEmpty) ...[
                          _buildSectionHeader('🎵', 'Top Artists'),
                          const SizedBox(height: 14),
                          _buildArtistBars(),
                          const SizedBox(height: 28),
                        ],
                        if (_avoidedArtists.isNotEmpty) ...[
                          _buildSectionHeader('⏭️', 'Frequently Skipped'),
                          const SizedBox(height: 14),
                          _buildAvoidedArtists(),
                          const SizedBox(height: 28),
                        ],
                        _buildSectionHeader('📊', 'Skip Behaviour'),
                        const SizedBox(height: 14),
                        _buildSkipInsights(),
                        const SizedBox(height: 14),
                        _buildSectionHeader('🎵', 'Most Played Songs'),
                        const SizedBox(height: 14),
                        _buildMostPlayedSongs(),
                        const SizedBox(height: 28),
                        _buildSectionHeader('⏱️', 'Listening Time'),
                        const SizedBox(height: 14),
                        _buildListeningTime(),
                        const SizedBox(height: 28),
                        _buildSectionHeader('🧠', 'How This Helps You'),
                        const SizedBox(height: 14),
                        _buildHowItHelps(),
                        const SizedBox(height: 28),
                        _buildResetButton(),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: const Color(0xFF080C14),
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: Colors.white,
          size: 18,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Taste Profile',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'What VibeFlow learned about you',
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasteProfileCard() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A2535), Color(0xFF0F1923)],
            ),
            border: Border.all(
              color: const Color(
                0xFF6EE7B7,
              ).withOpacity(0.15 * _pulseAnim.value),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF6EE7B7,
                ).withOpacity(0.06 * _pulseAnim.value),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6EE7B7).withOpacity(0.1),
                  border: Border.all(
                    color: const Color(0xFF6EE7B7).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    _tasteEmoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tasteProfile,
                      style: const TextStyle(
                        color: Color(0xFF6EE7B7),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _tasteDescription,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMostPlayedSongs() {
    final songs = _prefs.getMostPlayedSongs(limit: 5);
    if (songs.isEmpty)
      return _buildEmptyState('Listen to songs fully to see them here.');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0F1923),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: songs.asMap().entries.map((entry) {
          final i = entry.key;
          final song = entry.value;
          final isLast = i == songs.length - 1;
          return Container(
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
                    ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '#${i + 1}',
                    style: TextStyle(
                      color: i == 0
                          ? const Color(0xFF6EE7B7)
                          : Colors.white.withOpacity(0.3),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _capitalize(song.artist),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${song.playCount}x',
                      style: const TextStyle(
                        color: Color(0xFF6EE7B7),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      song.formattedListenTime,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildListeningTime() {
    final stats = _prefs.getCompletedSongsStats();
    final totalSecs = stats['total_listen_time_seconds'] as int? ?? 0;
    final hours = totalSecs ~/ 3600;
    final minutes = (totalSecs % 3600) ~/ 60;
    final uniqueSongs = stats['unique_songs'] as int? ?? 0;
    final totalPlays = stats['total_plays'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0F1923),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTimeChip(
              '${hours}h ${minutes}m',
              'Total Listened',
              const Color(0xFF818CF8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildTimeChip(
              '$uniqueSongs',
              'Unique Songs',
              const Color(0xFF6EE7B7),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildTimeChip(
              '$totalPlays',
              'Total Plays',
              const Color(0xFFFBBF24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeChip(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 10.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    final artists = _stats['total_artists_tracked'] as int? ?? 0;
    final skips = _stats['total_skips_recorded'] as int? ?? 0;
    final topCount = _topArtists.length;

    return Row(
      children: [
        _buildStatChip('$artists', 'Artists\nTracked', const Color(0xFF818CF8)),
        const SizedBox(width: 12),
        _buildStatChip('$skips', 'Songs\nSkipped', const Color(0xFFF472B6)),
        const SizedBox(width: 12),
        _buildStatChip(
          '$topCount',
          'Favourites\nLearned',
          const Color(0xFF6EE7B7),
        ),
      ],
    );
  }

  Widget _buildStatChip(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: color.withOpacity(0.07),
          border: Border.all(color: color.withOpacity(0.18), width: 1),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String emoji, String title) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildArtistBars() {
    if (_topArtists.isEmpty)
      return _buildEmptyState('No artist data yet. Keep listening!');

    final maxScore = _artistScores.values.isEmpty
        ? 1.0
        : _artistScores.values.reduce(max).clamp(1.0, double.infinity);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0F1923),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: _topArtists.asMap().entries.map((entry) {
          final index = entry.key;
          final artist = entry.value;
          final score = _artistScores[artist] ?? 0.0;
          final barW = _barWidth(score, maxScore);
          final isLast = index == _topArtists.length - 1;

          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: barW),
            duration: Duration(milliseconds: 600 + index * 80),
            curve: Curves.easeOutCubic,
            builder: (context, animW, _) {
              return Container(
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : Border(
                          bottom: BorderSide(
                            color: Colors.white.withOpacity(0.05),
                          ),
                        ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      // Rank
                      SizedBox(
                        width: 24,
                        child: Text(
                          '#${index + 1}',
                          style: TextStyle(
                            color: index == 0
                                ? const Color(0xFF6EE7B7)
                                : Colors.white.withOpacity(0.3),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Artist name
                      Expanded(
                        flex: 3,
                        child: Text(
                          _capitalize(artist),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Bar
                      Expanded(
                        flex: 4,
                        child: Stack(
                          children: [
                            Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: animW,
                              child: Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _barColor(score),
                                  borderRadius: BorderRadius.circular(3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _barColor(score).withOpacity(0.4),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Score
                      Text(
                        score.toStringAsFixed(0),
                        style: TextStyle(
                          color: _scoreColor(score),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAvoidedArtists() {
    if (_avoidedArtists.isEmpty)
      return _buildEmptyState('No skipped artists yet.');

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _avoidedArtists.map((artist) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: const Color(0xFFF87171).withOpacity(0.08),
            border: Border.all(
              color: const Color(0xFFF87171).withOpacity(0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.skip_next, color: Color(0xFFF87171), size: 13),
              const SizedBox(width: 5),
              Text(
                _capitalize(artist),
                style: const TextStyle(
                  color: Color(0xFFF87171),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSkipInsights() {
    final analysis = _skipAnalysis;
    if (analysis == null) return _buildEmptyState('No skip data yet.');

    final avgPos = analysis.averageSkipPosition;
    final skipCount = analysis.recentSkipCount;

    String skipStyle;
    String skipDesc;
    Color skipColor;

    if (avgPos < 10) {
      skipStyle = 'Instant Skipper';
      skipDesc = 'You decide within seconds. Trust your gut.';
      skipColor = const Color(0xFFF87171);
    } else if (avgPos < 30) {
      skipStyle = 'Quick Judge';
      skipDesc = 'You give songs a short window to impress.';
      skipColor = const Color(0xFFFBBF24);
    } else if (avgPos < 90) {
      skipStyle = 'Fair Listener';
      skipDesc = 'You listen before deciding. Patient approach.';
      skipColor = const Color(0xFF6EE7B7);
    } else {
      skipStyle = 'Full Commitment';
      skipDesc = 'You rarely skip. Every song gets its moment.';
      skipColor = const Color(0xFF818CF8);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0F1923),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: skipColor.withOpacity(0.12),
                  border: Border.all(color: skipColor.withOpacity(0.3)),
                ),
                child: Text(
                  skipStyle,
                  style: TextStyle(
                    color: skipColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'avg ${avgPos.toStringAsFixed(0)}s in',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            skipDesc,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // Visual: skip timing bar
          Row(
            children: [
              Text(
                '0s',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.25),
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: (avgPos / 180).clamp(0, 1)),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, val, _) => FractionallySizedBox(
                        widthFactor: val,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: skipColor,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: skipColor.withOpacity(0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '3m+',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.25),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          if (skipCount > 0) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _buildInsightChip(
                  '${analysis.uniqueArtistsSkipped}',
                  'artists skipped',
                  const Color(0xFFF87171),
                ),
                const SizedBox(width: 8),
                _buildInsightChip(
                  analysis.isBurstSkipping ? 'Yes' : 'No',
                  'burst skipping',
                  const Color(0xFFFBBF24),
                ),
                const SizedBox(width: 8),
                _buildInsightChip(
                  analysis.shouldRefetchRadio ? 'Yes' : 'No',
                  'radio refresh',
                  const Color(0xFF818CF8),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInsightChip(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withOpacity(0.07),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 9.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHowItHelps() {
    final items = [
      (
        '🎵',
        'Quick Picks',
        'Songs from your favourite artists appear first',
        const Color(0xFF6EE7B7),
      ),
      (
        '🔍',
        'Search Results',
        'Results ranked by your listening history',
        const Color(0xFF818CF8),
      ),
      (
        '📻',
        'Radio Queue',
        'Skipped artists are filtered out automatically',
        const Color(0xFFFBBF24),
      ),
      (
        '🚫',
        'Artist Avoid',
        'Frequently skipped artists appear less often',
        const Color(0xFFF87171),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0F1923),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isLast = i == items.length - 1;
          return Container(
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
                    ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Text(item.$1, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$2,
                        style: TextStyle(
                          color: item.$4,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.$3,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildResetButton() {
    return GestureDetector(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A2535),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Reset Taste Profile?',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            content: Text(
              'This will clear all your listening history and preferences. '
              'VibeFlow will start learning from scratch.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 13,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Reset',
                  style: TextStyle(color: Color(0xFFF87171)),
                ),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await _prefs.resetAllPreferences();
          if (mounted) {
            setState(() {
              _topArtists = [];
              _avoidedArtists = [];
              _artistScores = {};
              _stats = {};
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Taste profile reset'),
                backgroundColor: const Color(0xFF1A2535),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFFF87171).withOpacity(0.07),
          border: Border.all(color: const Color(0xFFF87171).withOpacity(0.2)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.refresh, color: Color(0xFFF87171), size: 16),
            SizedBox(width: 8),
            Text(
              'Reset Taste Profile',
              style: TextStyle(
                color: Color(0xFFF87171),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF0F1923),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
