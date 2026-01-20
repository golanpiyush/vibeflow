import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/models/listening_activity_modelandProvider.dart';

final hasAccessCodeProvider = FutureProvider<bool>((ref) async {
  final accessCodeService = ref.watch(accessCodeServiceProvider);
  final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;

  if (userId == null) return false;

  return await accessCodeService.checkIfUserHasAccessCode(userId);
});
