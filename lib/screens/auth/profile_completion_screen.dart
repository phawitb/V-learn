import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../home/root_shell.dart';

/// Shown once, right after a user's first Google sign-in — Google doesn't
/// give us a phone number, and this app requires first name, last name,
/// and phone before letting anyone into the app proper.
class ProfileCompletionScreen extends StatefulWidget {
  const ProfileCompletionScreen({super.key});

  @override
  State<ProfileCompletionScreen> createState() => _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  final _phone = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser;
    final parts = (user?.displayName ?? '').trim().split(RegExp(r'\s+'));
    _firstName = TextEditingController(text: user?.firstName ?? (parts.isNotEmpty ? parts.first : ''));
    _lastName = TextEditingController(text: user?.lastName ?? (parts.length > 1 ? parts.sublist(1).join(' ') : ''));
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await context.read<AppState>().completeProfile(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            phone: _phone.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RootShell()));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('กรอกข้อมูลเพื่อเริ่มใช้งาน', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.ink)),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _firstName,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\p{L}\s]', unicode: true))],
                      decoration: const InputDecoration(labelText: 'ชื่อ'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกชื่อ' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _lastName,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\p{L}\s]', unicode: true))],
                      decoration: const InputDecoration(labelText: 'นามสกุล'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกนามสกุล' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
                      decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์'),
                      validator: (v) {
                        final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                        if (digits.length < 9) return 'กรอกเบอร์โทรศัพท์ให้ถูกต้อง';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : const Text('เริ่มใช้งาน'),
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
