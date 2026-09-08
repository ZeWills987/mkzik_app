import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'auth_widgets.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
      );

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Saisis ton adresse e-mail');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.forgotPassword(email);
      if (mounted) setState(() => _sent = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      onBack: () => Navigator.of(context).maybePop(),
      form: _sent ? _buildSent() : _buildForm(),
    );
  }

  Widget _buildForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Mot de passe oublié',
              style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Entre ton adresse mail et on t\'envoie un lien pour réinitialiser ton mot de passe.',
            style: TextStyle(color: kTextSecondary, fontSize: 14),
          ),
          const SizedBox(height: 28),
          if (_error != null) ...[
            AuthError(_error!),
            const SizedBox(height: 16),
          ],
          AuthField(
            controller: _email,
            label: 'Adresse mail',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          AuthButton(label: 'Envoyer le lien', loading: _loading, onPressed: _submit),
        ],
      );

  Widget _buildSent() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.mark_email_read_outlined, color: kAccent, size: 52),
          const SizedBox(height: 20),
          const Text(
            'E-mail envoyé',
            style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Si un compte existe pour ${_email.text.trim()}, tu as reçu un e-mail avec un lien de réinitialisation.',
            style: const TextStyle(color: kTextSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          AuthButton(
            label: 'Réinitialiser avec un code',
            loading: false,
            onPressed: () => ResetPasswordScreen.open(context),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Retour à la connexion',
                style: TextStyle(color: kTextSecondary, fontSize: 13)),
          ),
        ],
      );
}
