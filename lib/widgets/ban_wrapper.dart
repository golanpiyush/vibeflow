// lib/widgets/ban_wrapper.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/services/bg_audio_handler.dart'; // Import your audio handler

// ==================== BANNED SCREEN ====================
class BannedScreen extends StatelessWidget {
  const BannedScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back button
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.red.shade900.withOpacity(0.3),
                Colors.black,
                Colors.black,
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Ban Icon
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.red.shade400,
                          width: 3,
                        ),
                      ),
                      child: Icon(
                        Icons.block,
                        size: 80,
                        color: Colors.red.shade400,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Title
                    Text(
                      'You Seem to be Banned',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade400,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // Message
                    Text(
                      'Your account has been suspended due to violation of our terms of service.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.7),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    // Info Container
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.white.withOpacity(0.6),
                            size: 32,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'If you believe this is a mistake, please contact me golanpiyush32@gmail.com',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.6),
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Disabled message
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade400,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Access to login and registration is currently disabled for your account.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.7),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Sign Out Button
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Supabase.instance.client.auth.signOut();
                      },
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: Text(
                        'Sign Out',
                        style: TextStyle(color: Colors.red.shade400),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        side: BorderSide(
                          color: Colors.red.shade400,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== BAN STATUS PROVIDER ====================
final banStatusProvider = StreamProvider.autoDispose<bool>((ref) {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;

  if (userId == null) {
    return Stream.value(false);
  }

  // Listen to realtime changes in ban status
  final stream = supabase
      .from('profiles')
      .stream(primaryKey: ['id'])
      .eq('id', userId)
      .map((data) {
        if (data.isEmpty) return false;
        final isBanned = data.first['is_banned'] == true;

        // CRITICAL: If banned status detected, immediately stop audio
        if (isBanned) {
          _stopAudioImmediately();
        }

        return isBanned;
      });

  return stream;
});

// ==================== IMMEDIATE AUDIO STOP FUNCTION ====================
// ==================== IMMEDIATE AUDIO STOP FUNCTION ====================
void _stopAudioImmediately() {
  try {
    final audioHandler = getAudioHandler();
    if (audioHandler != null) {
      print('🚨 [BAN DETECTED] Stopping audio immediately...');

      // Use the public method
      audioHandler.stopImmediately();

      print('✅ [BAN DETECTED] Audio stopped and trackers suspended');
    } else {
      print('⚠️ [BAN DETECTED] Audio handler not initialized');
    }
  } catch (e) {
    print('❌ [BAN DETECTED] Error stopping audio: $e');
  }
}

// ==================== BAN WRAPPER WIDGET ====================
class BanWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const BanWrapper({Key? key, required this.child}) : super(key: key);

  @override
  ConsumerState<BanWrapper> createState() => _BanWrapperState();
}

class _BanWrapperState extends ConsumerState<BanWrapper> {
  bool _wasPlayingBeforeBan = false;

  @override
  Widget build(BuildContext context) {
    final banStatusAsync = ref.watch(banStatusProvider);

    return banStatusAsync.when(
      data: (isBanned) {
        if (isBanned) {
          // Track if audio was playing when ban occurred
          if (!_wasPlayingBeforeBan) {
            final audioHandler = getAudioHandler();
            _wasPlayingBeforeBan = audioHandler?.isPlaying ?? false;

            if (_wasPlayingBeforeBan) {
              print('🎵 [BAN WRAPPER] Audio was playing, stopping now...');
              _stopAudioImmediately();
            }
          }

          // Always show BannedScreen when banned
          return const BannedScreen();
        }

        // Reset flag when unbanned
        _wasPlayingBeforeBan = false;
        return widget.child;
      },
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      error: (error, stack) {
        // On error, show the child (fail open for better UX)
        print('❌ Error checking ban status: $error');
        return widget.child;
      },
    );
  }
}

// ==================== USAGE EXAMPLE ====================
/*
// In your main.dart or app wrapper:

class MyApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      home: BanWrapper(
        child: HomePage(), // Your main app content
      ),
    );
  }
}

// Or wrap individual routes that require ban checking:

Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => BanWrapper(
      child: HomePage(),
    ),
  ),
);

// ==================== DATABASE SETUP ====================
/*
Make sure your profiles table has the is_banned column:

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS is_banned BOOLEAN DEFAULT FALSE;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_profiles_is_banned 
ON profiles(is_banned) 
WHERE is_banned = TRUE;

-- Enable realtime for the profiles table
ALTER PUBLICATION supabase_realtime ADD TABLE profiles;
*/
*/
