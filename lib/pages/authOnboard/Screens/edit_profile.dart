// lib/screens/edit_profile_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibeflow/database/profile_service.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/utils/theme_provider.dart';

final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(Supabase.instance.client);
});

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();

  String? _selectedGender;
  String? _currentProfilePic;
  File? _newProfilePicFile;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _showListeningActivity = true;
  bool _isJammerOn = false;

  // Username change tracking
  int _usernameChangesThisMonth = 0;
  DateTime? _lastUsernameChange;
  String _originalUsername = '';

  // Email change tracking
  bool _emailHasBeenChanged = false;
  DateTime? _profileCreatedAt;
  String _originalEmail = '';

  final List<String> _genderOptions = ['Male', 'Female'];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }

  bool _canChangeEmail() {
    if (_emailHasBeenChanged) return false;
    if (_profileCreatedAt == null) return false;

    final now = DateTime.now();
    final daysSinceCreation = now.difference(_profileCreatedAt!).inDays;
    return daysSinceCreation >= 30;
  }

  int _daysUntilEmailChange() {
    if (_profileCreatedAt == null) return 0;
    final now = DateTime.now();
    final daysSinceCreation = now.difference(_profileCreatedAt!).inDays;
    return 30 - daysSinceCreation;
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('*')
          .eq('id', currentUser.id)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _usernameController.text = response['userid'] ?? '';
          _originalUsername = response['userid'] ?? '';
          _emailController.text = response['email'] ?? currentUser.email ?? '';
          _originalEmail = response['email'] ?? currentUser.email ?? '';

          final dbGender = response['gender'];
          _selectedGender = dbGender != null ? _capitalize(dbGender) : null;

          _currentProfilePic = response['profile_pic_url'];
          _showListeningActivity = response['show_listening_activity'] ?? true;
          _isJammerOn = response['is_jammer_on'] ?? false;

          _usernameChangesThisMonth =
              response['username_changes_this_month'] ?? 0;
          _lastUsernameChange = response['last_username_change'] != null
              ? DateTime.parse(response['last_username_change'])
              : null;

          _emailHasBeenChanged = response['email_has_been_changed'] ?? false;
          _profileCreatedAt = response['created_at'] != null
              ? DateTime.parse(response['created_at'])
              : null;

          if (_lastUsernameChange != null) {
            final now = DateTime.now();
            if (now.month != _lastUsernameChange!.month ||
                now.year != _lastUsernameChange!.year) {
              _usernameChangesThisMonth = 0;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _newProfilePicFile = File(pickedFile.path);
      });
    }
  }

  bool _canChangeUsername() {
    return _usernameChangesThisMonth < 3;
  }

  Future<void> _updateEmailInAuth(String newEmail) async {
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: newEmail),
      );
    } catch (e) {
      throw Exception('Failed to update email in authentication: $e');
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    final newUsername = _usernameController.text.trim();
    final isUsernameChanged = newUsername != _originalUsername;

    if (isUsernameChanged && !_canChangeUsername()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can only change your username 3 times per month. Changes used: $_usernameChangesThisMonth/3',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    final newEmail = _emailController.text.trim();
    final isEmailChanged = newEmail != _originalEmail;

    if (isEmailChanged) {
      if (_emailHasBeenChanged) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You have already changed your email once. No more changes allowed.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      if (!_canChangeEmail()) {
        final daysRemaining = _daysUntilEmailChange();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You can change your email after 30 days from profile creation. $daysRemaining days remaining.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final profileService = ref.read(profileServiceProvider);
      String? newProfilePicUrl;

      // Handle profile picture upload and old picture deletion
      if (_newProfilePicFile != null) {
        // Delete old profile picture if exists
        if (_currentProfilePic != null && _currentProfilePic!.isNotEmpty) {
          await profileService.deleteProfilePictureByFileName(
            _currentProfilePic!,
          );
        }

        // Upload new profile picture
        newProfilePicUrl = await profileService.uploadProfilePicture(
          currentUser.id,
          _newProfilePicFile!.path,
        );

        if (newProfilePicUrl == null) {
          throw Exception('Failed to upload profile picture');
        }
      }

      final updateData = <String, dynamic>{
        'show_listening_activity': _showListeningActivity,
        'is_jammer_on': _isJammerOn,
      };

      // Only update profile_pic_url if a new one was uploaded
      if (newProfilePicUrl != null) {
        updateData['profile_pic_url'] = newProfilePicUrl;
      }

      if (_selectedGender != null) {
        updateData['gender'] = _selectedGender!.toLowerCase();
      }

      if (isUsernameChanged) {
        updateData['userid'] = newUsername;
        updateData['username_changes_this_month'] =
            _usernameChangesThisMonth + 1;
        updateData['last_username_change'] = DateTime.now().toIso8601String();
      }

      if (isEmailChanged) {
        await _updateEmailInAuth(newEmail);
        updateData['email'] = newEmail;
        updateData['email_has_been_changed'] = true;
      }

      await Supabase.instance.client
          .from('profiles')
          .update(updateData)
          .eq('id', currentUser.id);

      if (mounted) {
        String successMessage = 'Profile updated successfully!';

        if (isUsernameChanged) {
          successMessage =
              'Profile updated! Username changes remaining: ${2 - _usernameChangesThisMonth}/3 this month';
        }

        if (isEmailChanged) {
          successMessage =
              'Profile updated! Check your new email for verification. Email can no longer be changed.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );

        await _loadUserProfile();
        setState(() => _newProfilePicFile = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);
    final colorScheme = themeData.colorScheme;
    final themeState = ref.watch(themeProvider);

    // THEME-AWARE COLORS - These will properly respect Pure Black vs Material You
    Color bgColor;
    Color surfaceColor;
    Color cardColor;
    Color primaryColor;
    Color accentColor;
    Color textPrimary;
    Color textSecondary;
    Color textMuted;
    Color textDisabled;

    // Determine colors based on actual theme type
    switch (themeState.themeType) {
      case ThemeType.pureBlack:
        // Pure Black theme - true AMOLED black
        bgColor = Colors.black;
        surfaceColor = const Color(0xFF1A1A1A); // Dark gray for surfaces
        cardColor = const Color(0xFF0A0A0A); // Near black for cards
        primaryColor = const Color(0xFF6B4CE8); // Your purple
        accentColor = const Color(0xFF6B4CE8); // Use same purple for accent
        textPrimary = Colors.white;
        textSecondary = Colors.white.withOpacity(0.7);
        textMuted = Colors.white.withOpacity(0.5);
        textDisabled = Colors.white.withOpacity(0.3);
        break;

      case ThemeType.material:
        // Material You theme - use colorScheme but ensure proper contrast
        bgColor = colorScheme.background;
        surfaceColor = colorScheme.surfaceVariant;
        cardColor = colorScheme.surface;
        primaryColor = colorScheme.primary;
        accentColor = colorScheme.primary; // or colorScheme.secondary

        // For Material You dark mode, ensure text is pure white
        if (themeState.systemThemeMode == AppThemeMode.dark) {
          textPrimary = Colors.white;
          textSecondary = Colors.white.withOpacity(0.7);
          textMuted = Colors.white.withOpacity(0.5);
          textDisabled = Colors.white.withOpacity(0.3);
        } else {
          textPrimary = colorScheme.onSurface;
          textSecondary = colorScheme.onSurface.withOpacity(0.7);
          textMuted = colorScheme.onSurface.withOpacity(0.5);
          textDisabled = colorScheme.onSurface.withOpacity(0.3);
        }
        break;

      case ThemeType.light:
      default:
        // Light theme
        bgColor = colorScheme.background;
        surfaceColor = colorScheme.surfaceVariant;
        cardColor = colorScheme.surface;
        primaryColor = colorScheme.primary;
        accentColor = colorScheme.primary;
        textPrimary = colorScheme.onSurface;
        textSecondary = colorScheme.onSurface.withOpacity(0.7);
        textMuted = colorScheme.onSurface.withOpacity(0.5);
        textDisabled = colorScheme.onSurface.withOpacity(0.3);
        break;
    }

    // Rest of your build method remains the same...
    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: CircularProgressIndicator(
            color: primaryColor,
            backgroundColor: surfaceColor,
          ),
        ),
      );
    }

    final canChangeUsername = _canChangeUsername();
    final changesRemaining = 3 - _usernameChangesThisMonth;
    final canChangeEmail = _canChangeEmail();
    final daysUntilEmailChange = _daysUntilEmailChange();

    final hasImage = _newProfilePicFile != null || _currentProfilePic != null;

    return Scaffold(
      backgroundColor: bgColor,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Picture Section
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 64,
                          backgroundColor: surfaceColor,
                          foregroundImage: _newProfilePicFile != null
                              ? FileImage(_newProfilePicFile!)
                              : (_currentProfilePic != null
                                    ? NetworkImage(
                                        ref
                                            .read(profileServiceProvider)
                                            .buildProfileImageUrl(
                                              _currentProfilePic!,
                                            )!,
                                      )
                                    : null),
                          child: !hasImage
                              ? Icon(Icons.person, size: 64, color: textMuted)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: bgColor, width: 3),
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: _pickImage,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.lg),
                    TextButton.icon(
                      onPressed: _pickImage,
                      icon: Icon(Icons.upload, color: accentColor),
                      label: Text(
                        'Change Photo',
                        style: AppTypography.subtitle(
                          context,
                        ).copyWith(color: accentColor),
                      ),
                      style: TextButton.styleFrom(foregroundColor: accentColor),
                    ),
                  ],
                ),
              ),
              SizedBox(height: AppSpacing.xxl),

              // Username Field
              Text(
                'Username',
                style: AppTypography.songTitle(
                  context,
                ).copyWith(color: textSecondary),
              ),
              SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _usernameController,
                enabled: canChangeUsername,
                style: AppTypography.songTitle(context).copyWith(
                  color: canChangeUsername ? textPrimary : textDisabled,
                ),
                decoration: InputDecoration(
                  labelText: 'Username',
                  labelStyle: TextStyle(
                    color: canChangeUsername ? textSecondary : textDisabled,
                  ),
                  hintText: canChangeUsername
                      ? 'Enter your username'
                      : 'Username changes limit reached',
                  hintStyle: AppTypography.caption(
                    context,
                  ).copyWith(color: textMuted),
                  filled: true,
                  fillColor: canChangeUsername ? cardColor : surfaceColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                    borderSide: BorderSide(color: textMuted),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                    borderSide: BorderSide(color: textMuted.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                    borderSide: BorderSide(color: accentColor, width: 2),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                    borderSide: BorderSide(color: textMuted.withOpacity(0.2)),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.lg,
                  ),
                  suffixIcon: Icon(
                    canChangeUsername ? Icons.edit : Icons.lock,
                    color: canChangeUsername ? accentColor : textMuted,
                    size: 20,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Username is required';
                  }
                  if (value.trim().length < 3) {
                    return 'Username must be at least 3 characters';
                  }
                  return null;
                },
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                canChangeUsername
                    ? 'You can change your username $changesRemaining more time${changesRemaining != 1 ? 's' : ''} this month'
                    : 'Username change limit reached (3/3). Resets next month.',
                style: AppTypography.captionSmall(context).copyWith(
                  color: canChangeUsername ? accentColor : colorScheme.error,
                ),
              ),
              SizedBox(height: AppSpacing.xl),

              // Email Field
              Text(
                'Email',
                style: AppTypography.songTitle(
                  context,
                ).copyWith(color: textSecondary),
              ),
              SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _emailController,
                enabled: canChangeEmail,
                style: AppTypography.songTitle(
                  context,
                ).copyWith(color: canChangeEmail ? textPrimary : textDisabled),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(
                    color: canChangeEmail ? textSecondary : textDisabled,
                  ),
                  hintText: _emailHasBeenChanged
                      ? 'Email already changed (permanent)'
                      : (canChangeEmail
                            ? 'Enter your email'
                            : 'Email change locked'),
                  hintStyle: AppTypography.caption(
                    context,
                  ).copyWith(color: textMuted),
                  filled: true,
                  fillColor: canChangeEmail ? cardColor : surfaceColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                    borderSide: BorderSide(color: textMuted),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                    borderSide: BorderSide(color: textMuted.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                    borderSide: BorderSide(color: accentColor, width: 2),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                    borderSide: BorderSide(color: textMuted.withOpacity(0.2)),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.lg,
                  ),
                  suffixIcon: Icon(
                    canChangeEmail ? Icons.edit : Icons.lock,
                    color: canChangeEmail ? accentColor : textMuted,
                    size: 20,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!RegExp(
                    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                  ).hasMatch(value)) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                _emailHasBeenChanged
                    ? 'Email has been changed. No more changes allowed.'
                    : (canChangeEmail
                          ? 'You can change your email once (1 time only)'
                          : 'Email can be changed after 30 days ($daysUntilEmailChange days remaining)'),
                style: AppTypography.captionSmall(context).copyWith(
                  color: _emailHasBeenChanged
                      ? colorScheme.error
                      : (canChangeEmail ? accentColor : Colors.orange),
                ),
              ),
              SizedBox(height: AppSpacing.xxl),

              // Privacy Settings Section
              Container(
                padding: EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                  border: Border.all(
                    color: _showListeningActivity ? accentColor : surfaceColor,
                    width: _showListeningActivity ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: _showListeningActivity
                                ? accentColor.withOpacity(0.1)
                                : surfaceColor,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMedium,
                            ),
                          ),
                          child: Icon(
                            Icons.privacy_tip,
                            color: _showListeningActivity
                                ? accentColor
                                : textMuted,
                            size: 24,
                          ),
                        ),
                        SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Privacy Settings',
                            style: AppTypography.songTitle(context).copyWith(
                              color: textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: _showListeningActivity
                                ? accentColor.withOpacity(0.1)
                                : surfaceColor,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSmall,
                            ),
                          ),
                          child: Text(
                            _showListeningActivity ? 'ON' : 'OFF',
                            style: AppTypography.captionSmall(context).copyWith(
                              color: _showListeningActivity
                                  ? accentColor
                                  : textMuted,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Show Listening Activity',
                                style: AppTypography.songTitle(context)
                                    .copyWith(
                                      color: textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                              SizedBox(height: AppSpacing.xs),
                              Text(
                                'Let others see what you\'re currently listening to',
                                style: AppTypography.captionSmall(context)
                                    .copyWith(
                                      color: _showListeningActivity
                                          ? accentColor
                                          : textMuted,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _showListeningActivity,
                          onChanged: (value) {
                            setState(() {
                              _showListeningActivity = value;
                            });
                          },
                          activeColor: accentColor,
                          activeTrackColor: accentColor.withOpacity(0.5),
                          inactiveThumbColor: textMuted,
                          inactiveTrackColor: surfaceColor,
                        ),
                      ],
                    ),
                    if (_showListeningActivity) ...[
                      SizedBox(height: AppSpacing.md),
                      Container(
                        padding: EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMedium,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: accentColor,
                            ),
                            SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Your friends can see what you\'re listening to in real-time',
                                style: AppTypography.captionSmall(
                                  context,
                                ).copyWith(color: accentColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: AppSpacing.xxl),

              // Jammer Mode Section
              Container(
                padding: EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                  border: Border.all(
                    color: _isJammerOn ? Colors.green : surfaceColor,
                    width: _isJammerOn ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: _isJammerOn
                                ? Colors.green.withOpacity(0.1)
                                : surfaceColor,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMedium,
                            ),
                          ),
                          child: Icon(
                            _isJammerOn ? Icons.music_note : Icons.music_off,
                            color: _isJammerOn ? Colors.green : accentColor,
                            size: 24,
                          ),
                        ),
                        SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Jammer Mode',
                            style: AppTypography.songTitle(context).copyWith(
                              color: textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: _isJammerOn
                                ? Colors.green.withOpacity(0.1)
                                : surfaceColor,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSmall,
                            ),
                          ),
                          child: Text(
                            _isJammerOn ? 'ON' : 'OFF',
                            style: AppTypography.captionSmall(context).copyWith(
                              color: _isJammerOn ? Colors.green : textMuted,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Real-time Activity Sync',
                                style: AppTypography.songTitle(
                                  context,
                                ).copyWith(color: textPrimary),
                              ),
                              SizedBox(height: AppSpacing.xs),
                              Text(
                                _isJammerOn
                                    ? '🎵 Now they can join your jammer session'
                                    : '🔇 Your Friends cannot invite you to join a jammer session.',
                                style: AppTypography.captionSmall(context)
                                    .copyWith(
                                      color: _isJammerOn
                                          ? Colors.green
                                          : textMuted,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isJammerOn,
                          onChanged: (value) {
                            setState(() {
                              _isJammerOn = value;
                            });
                          },
                          activeColor: Colors.green,
                          activeTrackColor: Colors.green.withOpacity(0.5),
                          inactiveThumbColor: textMuted,
                          inactiveTrackColor: surfaceColor,
                        ),
                      ],
                    ),
                    if (_isJammerOn) ...[
                      SizedBox(height: AppSpacing.md),
                      Container(
                        padding: EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMedium,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.green,
                            ),
                            SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'You can also invite your friends into a jammer session.',
                                style: AppTypography.captionSmall(
                                  context,
                                ).copyWith(color: Colors.green),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: AppSpacing.xxl),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    disabledBackgroundColor: surfaceColor,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: textDisabled,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusLarge,
                      ),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Save Changes',
                          style: AppTypography.songTitle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              SizedBox(height: AppSpacing.fourxxxl),
            ],
          ),
        ),
      ),
    );
  }
}
