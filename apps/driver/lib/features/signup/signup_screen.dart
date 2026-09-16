import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/auth_validators.dart';
import '../../core/utils/phone_utils.dart';
import '../../models/terminal.dart';
import '../../widgets/common_widgets.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _agreed = false;
  bool _submitting = false;
  String? _terminalId;
  List<Terminal> _terminals = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadTerminals);
  }

  Future<void> _loadTerminals() async {
    try {
      final list = await ref.read(driverRepositoryProvider).fetchTerminals();
      if (!mounted) return;
      setState(() => _terminals = list);
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No terminals available yet. Ask an admin to add one.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not load terminals: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _licenseCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the Terms and Privacy Policy.'),
        ),
      );
      return;
    }
    if (_terminalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your assigned terminal.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(sessionProvider.notifier).signUp(
            fullName: _nameCtrl.text.trim(),
            mobile: _mobileCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            licenseNumber: _licenseCtrl.text.trim(),
            plateNumber: _plateCtrl.text.trim(),
            assignedTerminalId: _terminalId!,
          );
      if (!mounted) return;
      await _showSignupSuccessDialog();
    } catch (err) {
      if (!mounted) return;
      final message = AuthValidators.friendlyAuthError(err);
      final success = err is AuthFlowException && err.isSuccessInfo;
      if (success) {
        await _showSignupSuccessDialog(message: message);
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign up failed'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showSignupSuccessDialog({String? message}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Account created'),
        content: Text(
          message ??
              'Your driver account was created and is waiting for administrator verification. '
              'An admin must verify your license before you can sign in with your mobile number.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/login');
            },
            child: const Text('Go to login'),
          ),
        ],
      ),
    );
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SkylineBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              28,
              12,
              28,
              48 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandHeader(dense: true)),
                  const SizedBox(height: 22),
                  Text(
                    'Create your account',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'We save your email on the profile. After an administrator verifies your license, sign in with your mobile number.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign up to get started as a driver.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppTextField(
                    controller: _nameCtrl,
                    hint: 'Full Name',
                    icon: Icons.person_outline_rounded,
                    textInputAction: TextInputAction.next,
                    validator: AuthValidators.fullName,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _mobileCtrl,
                    hint: 'Mobile Number (09XXXXXXXXX)',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    maxLength: PhoneUtils.localDigitCount,
                    inputFormatters: PhoneUtils.mobileInputFormatters(),
                    validator: AuthValidators.mobile,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _emailCtrl,
                    hint: 'Email Address (optional)',
                    icon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: AuthValidators.email,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _passwordCtrl,
                    hint: 'Create Password',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscurePass,
                    onToggleObscure: () =>
                        setState(() => _obscurePass = !_obscurePass),
                    textInputAction: TextInputAction.next,
                    validator: AuthValidators.password,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _confirmCtrl,
                    hint: 'Confirm Password',
                    icon: Icons.lock_outline_rounded,
                    obscure: _obscureConfirm,
                    onToggleObscure: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        AuthValidators.confirmPassword(v, _passwordCtrl.text),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _licenseCtrl,
                    hint: "Driver's License Number",
                    icon: Icons.badge_outlined,
                    textInputAction: TextInputAction.next,
                    validator: AuthValidators.license,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _plateCtrl,
                    hint: 'Plate Number',
                    icon: Icons.directions_car_filled_outlined,
                    textInputAction: TextInputAction.next,
                    validator: AuthValidators.plate,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _terminalId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: 'Assigned Terminal',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        color: AppColors.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      prefixIcon: const Icon(
                        Icons.location_on_outlined,
                        color: AppColors.textMuted,
                        size: 22,
                      ),
                    ),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textMuted,
                    ),
                    items: _terminals
                        .map(
                          (t) => DropdownMenuItem(
                            value: t.id,
                            child: Text(
                              t.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _terminalId = v),
                    validator: (v) =>
                        v == null ? 'Select your assigned terminal' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Checkbox(
                        value: _agreed,
                        activeColor: AppColors.primary,
                        checkColor: Colors.white,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        side: const BorderSide(
                          color: AppColors.textSecondary,
                          width: 1.6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(3),
                        ),
                        onChanged: (v) => setState(() => _agreed = v ?? false),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: 'I agree to the ',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.35,
                            ),
                            children: [
                              TextSpan(
                                text: 'Terms and Conditions',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Terms and Conditions',
                                        ),
                                      ),
                                    );
                                  },
                              ),
                              TextSpan(
                                text: ' and ',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              TextSpan(
                                text: 'Privacy Policy.',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Privacy Policy'),
                                      ),
                                    );
                                  },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Sign Up'),
                  ),
                  const SizedBox(height: 20),
                  const SectionOrDivider(),
                  const SizedBox(height: 8),
                  Center(
                    child: Text.rich(
                      TextSpan(
                        text: 'Already have an account? ',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                        children: [
                          TextSpan(
                            text: 'Log in',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => context.go('/login'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
