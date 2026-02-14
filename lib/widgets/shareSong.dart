import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/database/song_sharingService.dart';
import 'package:vibeflow/models/quick_picks_model.dart';

/// Share button that requires access code
class SongShareButton extends ConsumerWidget {
  final QuickPick song;

  const SongShareButton({super.key, required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAccessCodeAsync = ref.watch(hasAccessCodeProvider);

    return hasAccessCodeAsync.when(
      data: (hasAccessCode) {
        return IconButton(
          icon: const Icon(Icons.share),
          onPressed: hasAccessCode
              ? () => _shareSong(ref, context)
              : () => _showNoAccessDialog(context),
        );
      },
      loading: () => const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _shareSong(WidgetRef ref, BuildContext context) async {
    try {
      final sharingService = ref.read(songSharingServiceProvider);
      await sharingService.shareSong();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
      }
    }
  }

  void _showNoAccessDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text(
          'Access Code Required',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'You need an access code to share songs. Please contact support to get one.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// Public share button (no access code required)
class PublicSongShareButton extends ConsumerWidget {
  final QuickPick song;

  const PublicSongShareButton({super.key, required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.share, color: Colors.white),
      onPressed: () async {
        try {
          final sharingService = ref.read(songSharingServiceProvider);
          await sharingService.shareSongPublic();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
          }
        }
      },
    );
  }
}
