// lib/widgets/ban_wrapper.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
                      'Account Suspended',
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
                            'If you believe this is a mistake, please contact our support team.',
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

                    // Logout Button
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Supabase.instance.client.auth.signOut();
                        if (context.mounted) {
                          Navigator.of(
                            context,
                          ).pushNamedAndRemoveUntil('/login', (route) => false);
                        }
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign Out'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
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
        return data.first['is_banned'] == true;
      });

  return stream;
});

// ==================== BAN WRAPPER WIDGET ====================
class BanWrapper extends ConsumerWidget {
  final Widget child;

  const BanWrapper({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banStatusAsync = ref.watch(banStatusProvider);

    return banStatusAsync.when(
      data: (isBanned) {
        if (isBanned) {
          return const BannedScreen();
        }
        return child;
      },
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
      error: (error, stack) {
        // On error, show the child (fail open for better UX)
        print('❌ Error checking ban status: $error');
        return child;
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
