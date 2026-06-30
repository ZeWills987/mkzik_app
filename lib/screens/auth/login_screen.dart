import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import 'auth_widgets.dart';
import 'register_screen.dart';

class _GoogleButton extends ConsumerWidget {
  final bool loading;
  const _GoogleButton({required this.loading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
      onPressed: loading ? null : () => ref.read(authProvider.notifier).loginWithGoogle(),
      style: OutlinedButton.styleFrom(
        foregroundColor: kTextPrimary,
        side: const BorderSide(color: kBorder),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: kSurface,
      ),
      child: loading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GoogleLogo(),
                const SizedBox(width: 12),
                const Text('Continuer avec Google', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Quadrants colorés (rouge, bleu, jaune, vert) simulés avec des arcs
    final colors = [
      const Color(0xFF4285F4), // bleu (haut droite)
      const Color(0xFFEA4335), // rouge (haut gauche)
      const Color(0xFFFBBC05), // jaune (bas gauche)
      const Color(0xFF34A853), // vert (bas droite)
    ];
    final starts = [0.0, 90.0, 180.0, 270.0];

    for (int i = 0; i < 4; i++) {
      final paint = Paint()..color = colors[i]..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        _deg(starts[i]),
        _deg(90),
        true,
        paint,
      );
    }

    // Cercle blanc central
    canvas.drawCircle(Offset(cx, cy), r * 0.55, Paint()..color = Colors.white);

    // Lettre G simplifiée : un arc épais bleu
    final gPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.15
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.38),
      _deg(10),
      _deg(320),
      false,
      gPaint,
    );
    // Trait horizontal du G
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + r * 0.38, cy),
      gPaint..strokeWidth = size.width * 0.13,
    );
  }

  double _deg(double d) => d * 3.14159265 / 180;

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

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

                _GoogleButton(loading: auth.submitting),

                const SizedBox(height: 24),

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
