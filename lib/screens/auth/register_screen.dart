import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import 'auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _description = TextEditingController();
  final _birthDate = TextEditingController();

  bool _obscure = true;
  bool _rgpd = false;
  String? _localError;

  @override
  void dispose() {
    for (final c in [_username, _email, _password, _confirm, _firstName, _lastName, _description, _birthDate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18),
      firstDate: DateTime(1920),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(primary: kAccent, surface: kSurface),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      _birthDate.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _submit() async {
    setState(() => _localError = null);

    // Validations locales (champs requis + confirmation + RGPD)
    if (_username.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _localError = 'Pseudo, email et mot de passe sont obligatoires');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _localError = 'Les mots de passe ne correspondent pas');
      return;
    }
    if (!_rgpd) {
      setState(() => _localError = 'Tu dois accepter les conditions RGPD');
      return;
    }

    final ok = await ref.read(authProvider.notifier).register(
          username: _username.text,
          email: _email.text,
          password: _password.text,
          rgpdConsent: _rgpd,
          firstName: _firstName.text,
          lastName: _lastName.text,
          description: _description.text,
          birthDate: _birthDate.text,
        );
    // Succès → l'AuthGate bascule automatiquement vers l'app.
    if (ok && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final error = _localError ?? auth.error;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: MkzikLogo(size: 34)),
              const SizedBox(height: 24),
              const Text('Inscription',
                  style: TextStyle(color: kTextPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Crée ton compte Mkzik',
                  style: TextStyle(color: kTextSecondary, fontSize: 14)),
              const SizedBox(height: 24),

              if (error != null) ...[
                AuthError(error),
                const SizedBox(height: 16),
              ],

              AuthField(controller: _username, label: 'Pseudo *', icon: Icons.person_outline),
              const SizedBox(height: 14),
              AuthField(
                controller: _email,
                label: 'Adresse mail *',
                icon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              AuthField(
                controller: _password,
                label: 'Mot de passe *',
                icon: Icons.lock_outline,
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: kTextSecondary, size: 20),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              const SizedBox(height: 14),
              AuthField(
                controller: _confirm,
                label: 'Confirmer le mot de passe *',
                icon: Icons.lock_outline,
                obscure: _obscure,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: AuthField(controller: _lastName, label: 'Nom', icon: Icons.badge_outlined)),
                  const SizedBox(width: 12),
                  Expanded(child: AuthField(controller: _firstName, label: 'Prénom', icon: Icons.badge_outlined)),
                ],
              ),
              const SizedBox(height: 14),
              AuthField(
                controller: _birthDate,
                label: 'Date de naissance',
                icon: Icons.cake_outlined,
                readOnly: true,
                onTap: _pickBirthDate,
              ),
              const SizedBox(height: 14),
              AuthField(
                controller: _description,
                label: 'Description',
                icon: Icons.notes_outlined,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: 18),

              // Consentement RGPD
              GestureDetector(
                onTap: () => setState(() => _rgpd = !_rgpd),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: _rgpd ? kAccent : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _rgpd ? kAccent : kTextSecondary, width: 1.5),
                      ),
                      child: _rgpd ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        "J'accepte les conditions d'utilisation et la politique de confidentialité. *",
                        style: TextStyle(color: kTextSecondary, fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              AuthButton(label: "S'inscrire", loading: auth.submitting, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
