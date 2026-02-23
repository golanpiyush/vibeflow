// lib/screens/profile_setup_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeflow/api_base/db_actions.dart';
import 'package:vibeflow/constants/app_colors.dart';
import 'package:vibeflow/constants/app_spacing.dart';
import 'package:vibeflow/constants/app_typography.dart';
import 'package:vibeflow/database/listening_activity_service.dart';
import 'package:vibeflow/utils/secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import 'dart:io';
import 'dart:async';
import 'package:vibeflow/main.dart' show isMiniplayerVisible; // ADD THIS IMPORT

class ProfileSetupScreen extends ConsumerStatefulWidget {
  final String accessCode;

  const ProfileSetupScreen({super.key, required this.accessCode});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Step 1: User ID
  final _userIdController = TextEditingController();
  Timer? _userIdDebounce;
  bool _userIdChecking = false;
  String? _userIdError;
  bool _userIdAvailable = false;

  // Step 2: Email
  final _emailController = TextEditingController();
  Timer? _emailDebounce;
  bool _emailChecking = false;
  String? _emailError;
  bool _emailAvailable = false;

  // Step 3: Gender
  String? _selectedGender;
  final List<String> _genders = ['Male', 'Female'];

  // Step 4: Password
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  // Step 5: Profile Picture
  File? _profileImage;
  String? _selectedAvatarUrl;
  final ImagePicker _picker = ImagePicker();

  final List<String> _avatarUrls = [
    'https://i.pravatar.cc/300?img=1',
    'https://i.pravatar.cc/300?img=2',
    'https://i.pravatar.cc/300?img=3',
    'https://i.pravatar.cc/300?img=4',
    'https://i.pravatar.cc/300?img=5',
    'https://i.pravatar.cc/300?img=6',
  ];

  // Step 6: Terms
  bool _termsAccepted = false;

  // General
  bool _isLoading = false;
  String? _errorMessage;

  // Lottie animations for each step
  final List<String> _lottieAnimations = [
    'https://assets2.lottiefiles.com/packages/lf20_jtbfg2nb.json', // User ID
    'https://assets9.lottiefiles.com/packages/lf20_u25cckyh.json', // Email
    'https://assets4.lottiefiles.com/packages/lf20_x62chJ.json', // Gender
    'https://assets7.lottiefiles.com/packages/lf20_myejiggj.json', // Password
    'https://assets8.lottiefiles.com/packages/lf20_w51pcehl.json', // Profile
    'https://assets1.lottiefiles.com/packages/lf20_cbrbre30.json', // Terms
  ];

  @override
  void initState() {
    super.initState();
    isMiniplayerVisible.value = false;

    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_handleTabChange);
    _userIdController.addListener(_onUserIdChanged);
    _emailController.addListener(_onEmailChanged);
  }

  @override
  void dispose() {
    // RESTORE MINIPLAYER when this screen closes
    isMiniplayerVisible.value = true;
    _tabController.dispose();
    _userIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _scrollController.dispose();
    _userIdDebounce?.cancel();
    _emailDebounce?.cancel();
    super.dispose();
  }

  void _handleTabChange() {
    setState(() {
      _errorMessage = null;
    });
  }

  void _onUserIdChanged() {
    if (_userIdDebounce?.isActive ?? false) _userIdDebounce!.cancel();

    setState(() {
      _userIdAvailable = false;
      _userIdError = null;
    });

    if (_userIdController.text.isEmpty) return;

    // Validate format first
    if (!_validateUserIdFormat(_userIdController.text)) {
      setState(() {
        _userIdError = 'Invalid format';
      });
      return;
    }

    _userIdDebounce = Timer(const Duration(seconds: 1), () {
      _checkUserIdAvailability();
    });
  }

  bool _validateUserIdFormat(String userId) {
    if (userId.length < 3 || userId.length > 30) return false;
    if (userId.contains(' ')) return false;

    final validPattern = RegExp(r'^[a-zA-Z0-9._-]+$');
    return validPattern.hasMatch(userId);
  }

  Future<void> _checkUserIdAvailability() async {
    if (_userIdController.text.isEmpty) return;

    setState(() {
      _userIdChecking = true;
      _userIdError = null;
    });

    try {
      final db = ref.read(dbActionsProvider);
      final response = await db.supabaseClient
          .from('profiles')
          .select('userid')
          .eq('userid', _userIdController.text.toLowerCase())
          .maybeSingle();

      if (mounted) {
        setState(() {
          _userIdAvailable = response == null;
          _userIdError = response != null ? 'User ID already taken' : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userIdError = 'Error checking availability';
          _userIdAvailable = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _userIdChecking = false;
        });
      }
    }
  }

  void _onEmailChanged() {
    if (_emailDebounce?.isActive ?? false) {
      _emailDebounce!.cancel();
    }

    setState(() {
      _emailAvailable = false;
      _emailError = null;
    });

    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    // Validate format first
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    if (!emailRegex.hasMatch(email)) {
      setState(() {
        _emailError = 'Invalid email format';
      });
      return;
    }

    _emailDebounce = Timer(const Duration(seconds: 1), () {
      _checkEmailAvailability();
    });
  }

  Future<void> _checkEmailAvailability() async {
    if (_emailController.text.isEmpty) return;

    setState(() {
      _emailChecking = true;
      _emailError = null;
    });

    try {
      final db = ref.read(dbActionsProvider);
      final supabase = db.supabaseClient;
      final email = _emailController.text.trim().toLowerCase();

      // Method 1: Check profiles table first (faster, catches most duplicates)
      final profileResponse = await supabase
          .from('profiles')
          .select('email')
          .eq('email', email)
          .maybeSingle();

      if (profileResponse != null) {
        if (mounted) {
          setState(() {
            _emailAvailable = false;
            _emailError = 'Email already registered';
          });
        }
        return;
      }

      // Method 2: Check auth.users using RPC function
      // This catches emails that exist in auth but don't have profiles yet
      final authCheckResponse = await supabase.rpc(
        'check_email_exists',
        params: {'email_to_check': email},
      );

      final emailExistsInAuth = authCheckResponse as bool;

      if (mounted) {
        setState(() {
          _emailAvailable = !emailExistsInAuth;
          _emailError = emailExistsInAuth
              ? 'Email seems to be registered already'
              : null;
        });
      }
    } catch (e) {
      print('Error checking email availability: $e');
      if (mounted) {
        setState(() {
          // If we can't check, show a warning but don't block the user
          _emailAvailable = true;
          _emailError = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _emailChecking = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 800,
    );

    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
        _selectedAvatarUrl = null;
      });
    }
  }

  Future<void> _takePhoto() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 800,
    );

    if (pickedFile != null) {
      setState(() {
        _profileImage = File(pickedFile.path);
        _selectedAvatarUrl = null;
      });
    }
  }

  bool _validateCurrentStep() {
    switch (_tabController.index) {
      case 0: // User ID
        if (_userIdController.text.isEmpty) {
          setState(() {
            _userIdError = 'User ID is required';
          });
          return false;
        }
        if (!_validateUserIdFormat(_userIdController.text)) {
          setState(() {
            _userIdError = 'Invalid format';
          });
          return false;
        }
        if (_userIdError != null) return false;
        if (!_userIdAvailable) return false;
        return true;

      case 1: // Email
        final email = _emailController.text.trim();

        if (email.isEmpty) {
          setState(() {
            _emailError = 'Email is required';
          });
          return false;
        }

        final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
        if (!emailRegex.hasMatch(email)) {
          setState(() {
            _emailError = 'Please enter a valid email';
          });
          return false;
        }

        if (_emailError != null) return false;
        if (!_emailAvailable) return false;

        return true;

      case 2: // Gender
        return true;

      case 3: // Password
        if (_passwordController.text.isEmpty) {
          setState(() {
            _errorMessage = 'A Password is required';
          });
          return false;
        }
        if (_passwordController.text.length < 6) {
          setState(() {
            _errorMessage = 'Password must be at least 6 characters';
          });
          return false;
        }
        if (_passwordController.text != _confirmPasswordController.text) {
          setState(() {
            _errorMessage = 'Passwords do not match';
          });
          return false;
        }
        return true;

      case 4: // Profile Picture
        return true;

      case 5: // Terms
        if (!_termsAccepted) {
          setState(() {
            _errorMessage = 'You must accept the terms and conditions';
          });
          return false;
        }
        return true;

      default:
        return false;
    }
  }

  void _nextStep() {
    if (_validateCurrentStep()) {
      if (_tabController.index < 5) {
        _tabController.animateTo(_tabController.index + 1);
        setState(() {
          _errorMessage = null;
        });
      } else {
        _completeSetup();
      }
    }
  }

  void _previousStep() {
    if (_tabController.index > 0) {
      _tabController.animateTo(_tabController.index - 1);
      setState(() {
        _errorMessage = null;
      });
    }
  }

  Future<void> _completeSetup() async {
    if (!_validateCurrentStep()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = ref.read(dbActionsProvider);
      final supabase = db.supabaseClient;

      print('🔄 Starting signup process...');

      // 1. Create auth user
      final authResponse = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (authResponse.user == null) {
        throw Exception('Failed to create user');
      }

      final userId = authResponse.user!.id;
      print('✅ Auth user created: $userId');

      // 2. IMPORTANT: Get the session token to ensure we're authenticated
      final session = authResponse.session;
      if (session == null) {
        throw Exception(
          'No session created - email confirmation may be required',
        );
      }
      print('✅ Session established with token');

      // 3. Wait for auth to fully propagate
      await Future.delayed(const Duration(milliseconds: 800));

      // 4. Verify we're actually authenticated by checking current user
      final currentUser = supabase.auth.currentUser;
      print('🔍 Current user check: ${currentUser?.id}');
      print('🔍 User ID match: ${currentUser?.id == userId}');

      if (currentUser == null || currentUser.id != userId) {
        throw Exception('Authentication session not established properly');
      }

      // 5. Upload profile picture if exists
      String? profilePicUrl;
      if (_profileImage != null) {
        print('📸 Uploading profile picture...');
        profilePicUrl = await db.uploadProfilePicture(
          userId,
          _profileImage!.path,
        );
        print('✅ Profile picture uploaded: $profilePicUrl');
      } else if (_selectedAvatarUrl != null) {
        profilePicUrl = _selectedAvatarUrl;
        print('✅ Using avatar URL: $profilePicUrl');
      }

      // 6. Create profile record in the database
      print('📝 Creating profile record...');
      print('   - User ID: $userId');
      print('   - Username: ${_userIdController.text.toLowerCase()}');
      print('   - Email: ${_emailController.text.trim()}');
      print('   - Access Code: ${widget.accessCode}');
      print('   - Gender: $_selectedGender');
      print('   - Terms Accepted: $_termsAccepted');

      // First, verify the access code exists
      final codeCheck = await supabase
          .from('access_codes')
          .select('code, is_active')
          .eq('code', widget.accessCode)
          .maybeSingle();

      if (codeCheck == null) {
        throw Exception('Access code not found in database');
      }
      if (codeCheck['is_active'] != true) {
        throw Exception('Access code is not active');
      }
      print('✅ Access code verified: ${widget.accessCode}');

      final profileData = {
        'id': userId,
        'userid': _userIdController.text.toLowerCase(),
        'email': _emailController.text.trim(),
        'access_code_used': widget.accessCode,
        'has_agreed_to_rules': _termsAccepted,
      };

      // Add optional fields only if they have values
      if (_selectedGender != null) {
        profileData['gender'] = _selectedGender!.toLowerCase();
      }
      if (profilePicUrl != null) {
        profileData['profile_pic_url'] = profilePicUrl;
      }

      await supabase.from('profiles').insert(profileData);

      print('✅ Profile created successfully for user: $userId');

      // 7. Save user data to secure storage
      final secureStorage = SecureStorageService();
      await secureStorage.saveUserId(userId);
      await secureStorage.saveUserEmail(_emailController.text.trim());
      await secureStorage.markProfileSetupCompleted();
      // 8. Invalidate the hasAccessCodeProvider to refresh the UI
      ref.invalidate(hasAccessCodeProvider);

      // 9. Show success and navigate
      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e, stackTrace) {
      print('❌ Error creating account: $e');
      print('📍 Stack trace: $stackTrace');

      final userFriendlyError = _getErrorMessage(e);
      final targetTab = _getTabIndexForError(e);

      setState(() {
        _errorMessage = userFriendlyError;
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.error, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Registration Failed',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userFriendlyError,
                    style: AppTypography.subtitle(context),
                  ),
                  const SizedBox(height: 16),
                  if (e.toString().contains('user_already_exists')) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Already have an account?',
                            style: AppTypography.caption(
                              context,
                            ).copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try logging in instead of creating a new account.',
                            style: AppTypography.caption(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Navigate to the appropriate tab based on error
                  if (targetTab != _tabController.index) {
                    _tabController.animateTo(targetTab);
                  }
                },
                child: Text(
                  'OK',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 280,
                  child: Lottie.asset(
                    'assets/animations/success.json',
                    fit: BoxFit.contain,
                    repeat: false,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Account Created!',
                  style: AppTypography.pageTitle(context).copyWith(
                    color: AppColors.textPrimary, // ADD THIS
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Your account has been successfully created.',
                  style: AppTypography.subtitle(context).copyWith(
                    color: AppColors.textSecondary, // ADD THIS
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome, ${_userIdController.text}!',
                  style: AppTypography.songTitle(context).copyWith(
                    color: const Color.fromARGB(
                      255,
                      35,
                      143,
                      80,
                    ), // CHANGE THIS to accent for emphasis
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushReplacementNamed('/home');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color.fromARGB(
                        255,
                        39,
                        53,
                        176,
                      ), // ADD THIS
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMedium,
                        ),
                      ),
                    ),
                    child: Text(
                      'Get Started',
                      style: AppTypography.subtitle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLottieAnimation(int stepIndex) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final size = keyboardVisible ? 80.0 : 120.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: size,
      width: size,
      child: Lottie.network(
        _lottieAnimations[stepIndex],
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            _getIconForStep(stepIndex),
            size: size * 0.6,
            color: AppColors.textPrimary, // Updated
          );
        },
      ),
    );
  }

  IconData _getIconForStep(int stepIndex) {
    switch (stepIndex) {
      case 0:
        return Icons.person_outline;
      case 1:
        return Icons.email_outlined;
      case 2:
        return Icons.people_outline;
      case 3:
        return Icons.lock_outline;
      case 4:
        return Icons.camera_alt_outlined;
      case 5:
        return Icons.description_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Widget _buildRequirement(String text) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.sm,
        bottom: AppSpacing.xs,
      ), // Updated
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: AppColors.textPrimary,
          ), // Updated
          SizedBox(width: AppSpacing.sm), // Updated
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption(context).copyWith(
                color: AppColors.textSecondary, // Correct way to add color
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Update _buildPasswordRequirement (around line 556):
  Widget _buildPasswordRequirement(String text, bool isMet) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.sm,
        bottom: AppSpacing.xs,
      ), // Updated
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: isMet
                ? AppColors.success
                : AppColors.textSecondary, // Updated
          ),
          SizedBox(width: AppSpacing.sm), // Updated
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption(context).copyWith(
                color: isMet
                    ? AppColors.success
                    : AppColors.textSecondary, // Updated
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Update _buildTermItem (around line 578):
  Widget _buildTermItem(String text) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: AppSpacing.md,
        left: AppSpacing.sm,
      ), // Updated
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle,
            size: 20,
            color: AppColors.textPrimary,
          ), // Updated
          SizedBox(width: AppSpacing.md), // Updated
          Expanded(
            child: Text(
              text,
              style: AppTypography.subtitle(context), // Updated
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserIdStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(child: _buildLottieAnimation(0)),
                const SizedBox(height: 20),
                Text(
                  'Choose Your User ID',
                  style: AppTypography.pageTitle(context).copyWith(
                    color: AppColors.textPrimary, // ADD THIS
                  ),
                  textAlign: TextAlign.center,
                ),

                SizedBox(height: AppSpacing.sm), // Updated
                Text(
                  'This will be your unique identifier',
                  textAlign: TextAlign.center,
                  style: AppTypography.subtitle(context).copyWith(
                    color: AppColors.textSecondary, // ADD THIS
                  ),
                ),

                const SizedBox(height: 30),
                // In _buildUserIdStep():
                TextFormField(
                  controller: _userIdController,
                  cursorColor: AppColors.textPrimary,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'User ID',
                    labelStyle: TextStyle(
                      color: AppColors.textSecondary,
                    ), // ADD THIS
                    hintText: 'e.g., musiclover123',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.5),
                    ), // ADD THIS
                    prefixIcon: Icon(
                      Icons.alternate_email,
                      color: AppColors.textPrimary,
                    ), // ADD color
                    suffixIcon: _userIdChecking
                        ? Padding(
                            padding: EdgeInsets.all(AppSpacing.md),
                            child: const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _userIdAvailable
                        ? Icon(Icons.check_circle, color: AppColors.success)
                        : null,
                    errorText: _userIdError,
                    errorStyle: TextStyle(color: AppColors.error), // ADD THIS
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(
                        color: AppColors.textSecondary,
                      ), // ADD THIS
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(
                        color: AppColors.textSecondary,
                      ), // ADD THIS
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(
                        color: AppColors.textPrimary,
                        width: 2,
                      ), // ADD THIS
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(
                        color: AppColors.error,
                      ), // ADD THIS
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(
                        color: AppColors.error,
                        width: 2,
                      ), // ADD THIS
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 20),
                Text(
                  'Requirements:',
                  style: AppTypography.subtitle(context).copyWith(
                    fontWeight: FontWeight.w400,
                    color: AppColors.textPrimary, // ADD THIS
                  ),
                ),
                SizedBox(height: AppSpacing.xs),
                _buildRequirement('3-30 characters'),
                _buildRequirement('No spaces'),
                _buildRequirement(
                  'Letters, numbers, dots, dashes, underscores',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmailStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(child: _buildLottieAnimation(1)),
                const SizedBox(height: 20),
                Text(
                  'Your Email Address',
                  style: AppTypography.pageTitle(context).copyWith(
                    color: AppColors.textPrimary, // ADD THIS
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'For account recovery and notifications',
                  textAlign: TextAlign.center,
                  style: AppTypography.subtitle(context).copyWith(
                    color: AppColors.textSecondary, // ADD THIS
                  ),
                ),
                const SizedBox(height: 30),
                TextFormField(
                  controller: _emailController,
                  cursorColor: AppColors.textPrimary,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: TextStyle(
                      color: AppColors.textSecondary,
                    ), // ADD THIS
                    hintText: 'yourmail@gmail.com',
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.5),
                    ), // ADD THIS
                    prefixIcon: Icon(
                      Icons.email,
                      color: AppColors.textPrimary,
                    ), // ADD color
                    suffixIcon: _emailChecking
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _emailAvailable
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    errorText: _emailError,
                    errorStyle: TextStyle(color: AppColors.error), // ADD THIS
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.textSecondary,
                      ), // ADD THIS
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.textSecondary,
                      ), // ADD THIS
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.textPrimary,
                        width: 2,
                      ), // ADD THIS
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.error,
                      ), // ADD THIS
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.error,
                        width: 2,
                      ), // ADD THIS
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGenderStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(child: _buildLottieAnimation(2)),
                const SizedBox(height: 20),
                Text(
                  'Your Gender',
                  style: AppTypography.pageTitle(
                    context,
                  ).copyWith(color: AppColors.textPrimary),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'This helps system personalize your experience',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption(
                    context,
                  ).copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 30),
                ..._genders.map((gender) {
                  // Define colors based on gender
                  Color selectedColor = gender == 'Male'
                      ? Colors.blue
                      : Colors.pink;
                  Color unselectedColor = AppColors.textSecondary;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Card(
                      elevation: 2,
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMedium,
                        ),
                        side: BorderSide(
                          color: _selectedGender == gender
                              ? selectedColor // Use gender-specific color
                              : AppColors.surfaceLight,
                          width: 2,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMedium,
                        ),
                        onTap: () {
                          setState(() {
                            _selectedGender = gender;
                          });
                        },
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.lg),
                          child: Row(
                            children: [
                              Icon(
                                gender == 'Male' ? Icons.male : Icons.female,
                                color: _selectedGender == gender
                                    ? selectedColor // Use gender-specific color
                                    : unselectedColor,
                                size: 32,
                              ),
                              SizedBox(width: AppSpacing.lg),
                              Expanded(
                                child: Text(
                                  gender,
                                  style: AppTypography.songTitle(context)
                                      .copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: _selectedGender == gender
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                ),
                              ),
                              if (_selectedGender == gender)
                                Icon(
                                  Icons.check_circle,
                                  color:
                                      selectedColor, // Use gender-specific color
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
                Text(
                  'You can skip this step',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption(context).copyWith(
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPasswordStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(child: _buildLottieAnimation(3)),
                const SizedBox(height: 20),
                Text(
                  'Create a Password',
                  style: AppTypography.pageTitle(context).copyWith(
                    color: AppColors.textPrimary, // ADD THIS
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'Choose a strong password',
                  textAlign: TextAlign.center,
                  style: AppTypography.subtitle(context).copyWith(
                    color: AppColors.textSecondary, // ADD THIS
                  ),
                ),
                const SizedBox(height: 30),
                TextFormField(
                  controller: _passwordController,
                  cursorColor: AppColors.textPrimary,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    hintText: 'Enter your password', // ADD THIS
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.5),
                    ), // ADD THIS
                    prefixIcon: Icon(Icons.lock, color: AppColors.textPrimary),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword ? Icons.visibility : Icons.visibility_off,
                        color: AppColors.textPrimary,
                      ),
                      onPressed: () {
                        setState(() {
                          _showPassword = !_showPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(color: AppColors.textSecondary),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(color: AppColors.textSecondary),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(
                        color: AppColors.textPrimary,
                        width: 2,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(color: AppColors.error),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(color: AppColors.error, width: 2),
                    ),
                  ),
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _confirmPasswordController,
                  cursorColor: AppColors.textPrimary,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    hintText: 'Re-enter your password', // ADD THIS
                    hintStyle: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.5),
                    ), // ADD THIS
                    prefixIcon: Icon(
                      Icons.lock_reset,
                      color: AppColors.textPrimary,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showConfirmPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: AppColors.textPrimary,
                      ),
                      onPressed: () {
                        setState(() {
                          _showConfirmPassword = !_showConfirmPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(color: AppColors.textSecondary),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(color: AppColors.textSecondary),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(
                        color: AppColors.textPrimary,
                        width: 2,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(color: AppColors.error),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                      borderSide: BorderSide(color: AppColors.error, width: 2),
                    ),
                  ),
                  obscureText: !_showConfirmPassword,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 20),
                Text(
                  'Password Requirements:',
                  style: AppTypography.subtitle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary, // ADD THIS
                  ),
                ),
                const SizedBox(height: 10),
                _buildPasswordRequirement(
                  'At least 6 characters',
                  _passwordController.text.length >= 6,
                ),
                _buildPasswordRequirement(
                  'Passwords match',
                  _passwordController.text == _confirmPasswordController.text &&
                      _passwordController.text.isNotEmpty,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _errorMessage!,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfilePictureStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(child: _buildLottieAnimation(4)),
                const SizedBox(height: 20),
                Text(
                  'Add Profile Picture',
                  style: AppTypography.pageTitle(context).copyWith(
                    color: AppColors.textPrimary, // ADD THIS
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  'Personalize your account',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption(context).copyWith(
                    color: AppColors.textSecondary, // ADD THIS
                  ),
                ),
                const SizedBox(height: 30),
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.textPrimary,
                          width: 3,
                        ),
                      ),
                      child: ClipOval(
                        child: _profileImage != null
                            ? Image.file(
                                _profileImage!,
                                fit: BoxFit.cover,
                                width: 150,
                                height: 150,
                              )
                            : _selectedAvatarUrl != null
                            ? Image.network(
                                _selectedAvatarUrl!,
                                fit: BoxFit.cover,
                                width: 150,
                                height: 150,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color:
                                        AppColors.surfaceLight, // CHANGE THIS
                                    child: Icon(
                                      Icons.add_a_photo,
                                      size: 40,
                                      color:
                                          AppColors.textPrimary, // CHANGE THIS
                                    ),
                                  );
                                },
                              )
                            : Container(
                                color: AppColors.surfaceLight, // CHANGE THIS
                                child: Icon(
                                  Icons.add_a_photo,
                                  size: 40,
                                  color: AppColors.textPrimary, // CHANGE THIS
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _takePhoto,
                      icon: const Icon(Icons.camera_alt, size: 20),
                      label: const Text('Camera'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surfaceLight,
                        foregroundColor: AppColors.textPrimary,
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(42),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library, size: 20),
                      label: const Text('Gallery'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent, // CHANGE THIS
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(42),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                Text(
                  'Or choose an avatar:',
                  textAlign: TextAlign.center,
                  style: AppTypography.songTitle(context).copyWith(
                    color: AppColors.textPrimary, // ADD THIS
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: _avatarUrls.map((url) {
                    final isSelected = _selectedAvatarUrl == url;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedAvatarUrl = url;
                          _profileImage = null;
                        });
                      },
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppColors
                                      .accent // CHANGE THIS from textPrimary to accent
                                : AppColors
                                      .surfaceLight, // CHANGE THIS from success to surfaceLight
                            width: isSelected ? 3 : 2,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: AppColors.surfaceLight, // CHANGE THIS
                                child: Icon(
                                  Icons.person,
                                  size: 40,
                                  color: AppColors.textSecondary, // ADD THIS
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                if (_profileImage != null || _selectedAvatarUrl != null)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _profileImage = null;
                        _selectedAvatarUrl = null;
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary, // ADD THIS
                    ),
                    child: const Text('Remove Selection'),
                  ),
                const SizedBox(height: 20),
                Text(
                  'You can change this later',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption(context).copyWith(
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSecondary, // ADD THIS
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTermsStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(child: _buildLottieAnimation(5)),
                const SizedBox(height: 20),

                Text(
                  'One Last Thing',
                  style: AppTypography.pageTitle(context).copyWith(
                    color: AppColors.textPrimary, // ADD THIS
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                Text(
                  'By using Vibeflow, you agree to:',
                  style: AppTypography.songTitle(context).copyWith(
                    color: AppColors.textSecondary, // ADD THIS
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 30),

                _buildSimpleRule(
                  'Do not perform or attempt server abuse, including DDoS attacks, bot traffic, request flooding, or infrastructure misuse',
                ),

                _buildSimpleRule(
                  'Do not reverse-engineer, decompile, tamper with, or exploit the app, APIs, or network requests (including MITM, packet sniffing, or modified clients)',
                ),

                _buildSimpleRule(
                  'Do not redistribute, sideload, mirror, or share the app, builds, access links, or internal features with untrusted or unauthorized users',
                ),

                _buildSimpleRule(
                  'Do not attempt to access, collect, infer, or misuse other users’ data, activity, or private content without authorization',
                ),

                _buildSimpleRule(
                  'Do not automate, scrape, or overload Vibeflow through abnormal or non-human usage patterns',
                ),

                _buildSimpleRule('Use Vibeflow respectfully and lawfully'),

                _buildSimpleRule(
                  'Violation of these rules may result in an account suspension or a permanent ban',
                ),

                const SizedBox(height: 30),

                Card(
                  elevation: 0,
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusMedium,
                    ),
                    side: BorderSide(
                      color: _termsAccepted
                          ? const Color.fromARGB(255, 39, 76, 176)
                          : AppColors.surfaceLight,
                      width: 2,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusMedium,
                    ),
                    onTap: () {
                      setState(() {
                        _termsAccepted = !_termsAccepted;
                        _errorMessage = null;
                      });
                    },
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _termsAccepted,
                            activeColor: const Color.fromARGB(
                              255,
                              39,
                              103,
                              176,
                            ),
                            checkColor: Colors.white, // ADD THIS
                            side: BorderSide(
                              color: AppColors.textSecondary,
                            ), // ADD THIS
                            onChanged: (value) {
                              setState(() {
                                _termsAccepted = value ?? false;
                                _errorMessage = null;
                              });
                            },
                          ),
                          Expanded(
                            child: Text(
                              'I agree to follow these rules',
                              style: AppTypography.subtitle(context).copyWith(
                                color: AppColors.textPrimary, // ADD THIS
                                fontWeight: _termsAccepted
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // Add this missing method
  Widget _buildSimpleRule(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle,
            size: 20,
            color: const Color.fromARGB(255, 39, 114, 176), // ADD THIS
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTypography.subtitle(context).copyWith(
                color: AppColors.textSecondary, // ADD THIS
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Your Profile'), elevation: 0),
      body: Column(
        children: [
          // Progress indicator
          Container(
            padding: EdgeInsets.all(AppSpacing.lg), // Updated
            child: Row(
              children: List.generate(6, (index) {
                final isActive = index <= _tabController.index;
                return Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors
                                .textPrimary // Updated
                          : AppColors.surfaceLight, // Updated
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildUserIdStep(),
                _buildEmailStep(),
                _buildGenderStep(),
                _buildPasswordStep(),
                _buildProfilePictureStep(),
                _buildTermsStep(),
              ],
            ),
          ),

          // Navigation buttons
          Container(
            padding: EdgeInsets.all(AppSpacing.lg), // Updated
            decoration: BoxDecoration(
              color: AppColors.surface, // Updated
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  if (_tabController.index > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _previousStep,
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ), // Updated
                          foregroundColor: Colors.white,
                        ),

                        child: const Text('Back'),
                      ),
                    ),
                  if (_tabController.index > 0) const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _nextStep,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: AppSpacing.lg,
                        ), // Updated
                        backgroundColor: _validateCurrentStep()
                            ? Colors.white
                            : null,
                        foregroundColor: _validateCurrentStep()
                            ? Colors.black
                            : null,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              _tabController.index < 5
                                  ? 'Next'
                                  : 'Complete Setup',
                              style: const TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    // Auth errors
    if (errorString.contains('user already registered') ||
        errorString.contains('user_already_exists')) {
      return 'This email is already registered. Please use a different email or try logging in.';
    }

    if (errorString.contains('invalid email')) {
      return 'Please enter a valid email address.';
    }

    if (errorString.contains('weak password') ||
        errorString.contains('password is too short')) {
      return 'Password is too weak. Please use at least 6 characters.';
    }

    // RLS errors
    if (errorString.contains('row-level security') ||
        errorString.contains('42501')) {
      return 'Permission denied. Please contact support.';
    }

    // Foreign key errors
    if (errorString.contains('violates foreign key constraint')) {
      return 'Invalid access code. Please contact support.';
    }

    if (errorString.contains('access code not found')) {
      return 'Access code not found. Please check and try again.';
    }

    if (errorString.contains('access code is not active')) {
      return 'This access code has been deactivated. Please contact support.';
    }

    // Network errors
    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    }

    // Email confirmation errors
    if (errorString.contains('email confirmation')) {
      return 'Email confirmation required. Please check your inbox.';
    }

    // Generic fallback
    return 'An error occurred: ${error.toString()}';
  }

  int _getTabIndexForError(dynamic error) {
    final errorString = error.toString().toLowerCase();

    // Email-related errors -> go to email tab (index 1)
    if (errorString.contains('email') ||
        errorString.contains('user already registered') ||
        errorString.contains('user_already_exists')) {
      return 1;
    }

    // Password errors -> go to password tab (index 3)
    if (errorString.contains('password')) {
      return 3;
    }

    // Access code errors -> go to start (index 0)
    if (errorString.contains('access code')) {
      return 0;
    }

    // Default: stay on current tab
    return _tabController.index;
  }
}
