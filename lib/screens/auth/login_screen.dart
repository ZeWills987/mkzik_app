import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import 'auth_widgets.dart';
import 'register_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      ref.read(authProvider.notifier).clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renseigne ton email et ton mot de passe')),
      );
      return;
    }
    await ref.read(authProvider.notifier).login(_email.text, _password.text);
    // La navigation est gérée par l'AuthGate qui écoute l'état.
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: MkzikLogo(size: 38)),
                const SizedBox(height: 40),
                const Text('Connexion',
                    style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Heureux de te revoir 👋',
                    style: TextStyle(color: kTextSecondary, fontSize: 14)),
                const SizedBox(height: 28),

                if (auth.error != null) ...[
                  AuthError(auth.error!),
                  const SizedBox(height: 16),
                ],

                AuthField(
                  controller: _email,
                  label: 'Adresse mail',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 14),
                AuthField(
                  controller: _password,
                  label: 'Mot de passe',
                  icon: Icons.lock_outline,
                  obscure: _obscure,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  suffix: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                        color: kTextSecondary, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                const SizedBox(height: 24),

                AuthButton(label: 'Se connecter', loading: auth.submitting, onPressed: _submit),

                const SizedBox(height: 20),
                Row(
                  children: const [
                    Expanded(child: Divider(color: kBorder)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('ou', style: TextStyle(color: kTextSecondary, fontSize: 12)),
                    ),
                    Expanded(child: Divider(color: kBorder)),
                  ],
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Pas de compte ? ', style: TextStyle(color: kTextSecondary, fontSize: 13)),
                    GestureDetector(
                      onTap: () {
                        ref.read(authProvider.notifier).clearError();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RegisterScreen()),
                        );
                      },
                      child: const Text('Inscris-toi',
                          style: TextStyle(color: kAccent, fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
