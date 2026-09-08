import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'auth_widgets.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
      );

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _done = false;
  String? _error;
  bool _obscurePwd = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = _token.text.trim();
    final pwd = _password.text;
    final confirm = _confirm.text;

    if (token.isEmpty || pwd.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'Tous les champs sont requis');
      return;
    }
    if (pwd != confirm) {
      setState(() => _error = 'Les mots de passe ne correspondent pas');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.resetPassword(token, pwd);
      if (mounted) setState(() => _done = true);
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
      form: _done ? _buildDone() : _buildForm(),
    );
  }

  Widget _buildForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Nouveau mot de passe',
              style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Copie le code présent dans le lien de ton e-mail et choisis un nouveau mot de passe.',
            style: TextStyle(color: kTextSecondary, fontSize: 14),
          ),
          const SizedBox(height: 28),
          if (_error != null) ...[
            AuthError(_error!),
            const SizedBox(height: 16),
          ],
          AuthField(
            controller: _token,
            label: 'Code de réinitialisation',
            icon: Icons.vpn_key_outlined,
          ),
          const SizedBox(height: 14),
          AuthField(
            controller: _password,
            label: 'Nouveau mot de passe',
            icon: Icons.lock_outline,
            obscure: _obscurePwd,
            suffix: IconButton(
              icon: Icon(_obscurePwd ? Icons.visibility_off : Icons.visibility,
                  color: kTextSecondary, size: 20),
              onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
            ),
          ),
          const SizedBox(height: 14),
          AuthField(
            controller: _confirm,
            label: 'Confirmer le mot de passe',
            icon: Icons.lock_outline,
            obscure: _obscureConfirm,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            suffix: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  color: kTextSecondary, size: 20),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          const SizedBox(height: 24),
          AuthButton(label: 'Réinitialiser', loading: _loading, onPressed: _submit),
        ],
      );

  Widget _buildDone() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_outline, color: kAccent, size: 52),
          const SizedBox(height: 20),
          const Text(
            'Mot de passe modifié',
            style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'Tu peux maintenant te connecter avec ton nouveau mot de passe.',
            style: TextStyle(color: kTextSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          AuthButton(
            label: 'Retour à la connexion',
            loading: false,
            onPressed: () {
              // Dépile jusqu'à la racine de la pile auth
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      );
}
