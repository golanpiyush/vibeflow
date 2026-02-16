// lib/providers/miniplayer_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Controls whether the global miniplayer should be visible
/// Set to false on HomePage and NewPlayerPage
final showGlobalMiniplayerProvider = StateProvider<bool>((ref) => true);
