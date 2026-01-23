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

      if (_newProfilePicFile != null) {
        newProfilePicUrl = await profileService.uploadProfilePicture(
          currentUser.id,
          _newProfilePicFile!.path,
        );

        if (newProfilePicUrl == null) {
          throw Exception('Failed to upload profile picture');
        }
      }

      final updateData = <String, dynamic>{
        'profile_pic_url': newProfilePicUrl ?? _currentProfilePic,
        'show_listening_activity': _showListeningActivity,
        'is_jammer_on': _isJammerOn,
      };

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
    final themeState = ref.watch(themeProvider);
    final isDark =
        themeState.themeType == ThemeType.pureBlack ||
        (themeState.themeType == ThemeType.material &&
            themeState.systemThemeMode == AppThemeMode.dark);

    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final surfaceColor = isDark ? const Color(0xFF1A1A1A) : Colors.grey[100];
    final cardColor = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final accentColor = themeState.themeType == ThemeType.pureBlack
        ? Colors.purple[400]
        : primaryColor;

    final textPrimaryColor = isDark ? Colors.white : Colors.black;

    final textSecondaryColor = isDark ? Colors.grey[400]! : Colors.grey[700]!;

    final textMutedColor = isDark ? Colors.grey[500]! : Colors.grey[600]!;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: accentColor)),
      );
    }

    final canChangeUsername = _canChangeUsername();
    final changesRemaining = 3 - _usernameChangesThisMonth;
    final canChangeEmail = _canChangeEmail();
    final daysUntilEmailChange = _daysUntilEmailChange();

    return Scaffold(
      backgroundColor: bgColor,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header

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
                                    ? NetworkImage(_currentProfilePic!)
                                    : null),
                          child:
                              (_newProfilePicFile == null &&
                                  _currentProfilePic == null)
                              ? Icon(
                                  Icons.person,
                                  size: 64,
                                  color: isDark
                                      ? Colors.grey[700]
                                      : Colors.grey[400],
                                )
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
                      icon: const Icon(Icons.upload),
                      label: Text(
                        'Change Photo',
                        style: AppTypography.subtitle(context),
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
                ).copyWith(color: textSecondaryColor),
              ),

              SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _usernameController,
                enabled: canChangeUsername,
                style: AppTypography.songTitle(context).copyWith(
                  color: textPrimaryColor, // main text color
                ),
                decoration: InputDecoration(
                  hintText: canChangeUsername
                      ? 'Enter your username'
                      : 'Username changes limit reached',
                  hintStyle: AppTypography.caption(context).copyWith(
                    color: isDark
                        ? Colors.grey[400]
                        : Colors.white, // hint text color white in light theme
                  ),
                  filled: true,
                  fillColor: canChangeUsername ? cardColor : surfaceColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.lg,
                  ),
                  suffixIcon: canChangeUsername
                      ? Icon(Icons.edit, color: accentColor, size: 20)
                      : Icon(Icons.lock, color: Colors.grey, size: 20),
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
                  color: canChangeUsername
                      ? accentColor
                      : isDark
                      ? Colors.orange
                      : Colors.deepOrange, // lighter orange for light theme
                ),
              ),
              SizedBox(height: AppSpacing.xl),

              // Email Field
              // Email Field
              Text(
                'Email',
                style: AppTypography.songTitle(
                  context,
                ).copyWith(color: textSecondaryColor),
              ),
              SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _emailController,
                enabled: canChangeEmail,
                style: AppTypography.songTitle(
                  context,
                ).copyWith(color: textPrimaryColor),
                decoration: InputDecoration(
                  hintText: _emailHasBeenChanged
                      ? 'Email already changed (permanent)'
                      : (canChangeEmail ? 'Email' : 'Email change locked'),
                  hintStyle: AppTypography.caption(
                    context,
                  ).copyWith(color: textMutedColor),
                  filled: true,
                  fillColor: canChangeEmail ? cardColor : surfaceColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.lg,
                  ),
                  suffixIcon: canChangeEmail
                      ? Icon(Icons.edit, color: accentColor, size: 20)
                      : Icon(Icons.lock, color: Colors.grey, size: 20),
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
                      ? Colors.red
                      : (canChangeEmail ? Colors.blue : Colors.orange),
                ),
              ),

              SizedBox(height: AppSpacing.xxl),

              // Privacy Settings Section
              Container(
                padding: EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                  border: Border.all(color: surfaceColor!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.privacy_tip, color: accentColor, size: 24),
                        SizedBox(width: AppSpacing.md),
                        Text(
                          'Privacy Settings',
                          style: AppTypography.songTitle(
                            context,
                          ).copyWith(color: textPrimaryColor),
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
                                style: AppTypography.songTitle(
                                  context,
                                ).copyWith(color: textPrimaryColor),
                              ),
                              SizedBox(height: AppSpacing.xs),
                              Text(
                                'Let others see what you\'re currently listening to',
                                style: AppTypography.captionSmall(
                                  context,
                                ).copyWith(color: textMutedColor),
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
                        ),
                      ],
                    ),
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
                    color: _isJammerOn
                        ? (isDark ? Colors.green[700]! : Colors.green[300]!)
                        : surfaceColor!,
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
                                ? (isDark
                                      ? Colors.green[900]!.withOpacity(0.3)
                                      : Colors.green[100])
                                : surfaceColor,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMedium,
                            ),
                          ),
                          child: Icon(
                            _isJammerOn ? Icons.music_note : Icons.music_off,
                            color: _isJammerOn
                                ? (isDark
                                      ? Colors.green[400]
                                      : Colors.green[700])
                                : accentColor,
                            size: 24,
                          ),
                        ),
                        SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Jammer Mode',
                            style: AppTypography.songTitle(context).copyWith(
                              color: textPrimaryColor,
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
                                ? (isDark
                                      ? Colors.green[900]!.withOpacity(0.5)
                                      : Colors.green[100])
                                : (isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[200]),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSmall,
                            ),
                          ),
                          child: Text(
                            _isJammerOn ? 'ON' : 'OFF',
                            style: AppTypography.captionSmall(context).copyWith(
                              color: _isJammerOn
                                  ? (isDark
                                        ? Colors.green[400]
                                        : Colors.green[700])
                                  : textMutedColor,
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
                                ).copyWith(color: textPrimaryColor),
                              ),
                              SizedBox(height: AppSpacing.xs),
                              Text(
                                _isJammerOn
                                    ? '🎵 Now they can'
                                    : '🔇 Your Friends cannot invite you to join a jammer session.',
                                style: AppTypography.captionSmall(context)
                                    .copyWith(
                                      color: _isJammerOn
                                          ? (isDark
                                                ? Colors.green[400]
                                                : Colors.green[700])
                                          : textMutedColor,
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
                          activeColor: isDark
                              ? Colors.green[400]
                              : Colors.green[600],
                        ),
                      ],
                    ),
                    if (_isJammerOn) ...[
                      SizedBox(height: AppSpacing.md),
                      Container(
                        padding: EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.green[900]!.withOpacity(0.2)
                              : Colors.green[50],
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMedium,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: isDark
                                  ? Colors.green[400]
                                  : Colors.green[700],
                            ),
                            SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'You can also invite your friends into a jammer session.',
                                style: AppTypography.captionSmall(context)
                                    .copyWith(
                                      color: isDark
                                          ? Colors.green[400]
                                          : Colors.green[700],
                                    ),
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
            ],
          ),
        ),
      ),
    );
  }
}
