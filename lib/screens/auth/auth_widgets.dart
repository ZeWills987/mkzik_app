import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Logo MKZIK réutilisé sur les écrans d'auth.
class MkzikLogo extends StatelessWidget {
  final double size;
  const MkzikLogo({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
        ),
        SizedBox(width: size * 0.3),
        RichText(
          text: TextSpan(
            style: TextStyle(fontSize: size * 0.7, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            children: const [
              TextSpan(text: 'MK', style: TextStyle(color: kTextPrimary)),
              TextSpan(text: 'ZIK', style: TextStyle(color: kAccent)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Champ de formulaire stylé (dark + accent).
class AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final Widget? suffix;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool readOnly;

  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.suffix,
    this.maxLines = 1,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: obscure ? 1 : maxLines,
      onSubmitted: onSubmitted,
      onTap: onTap,
      readOnly: readOnly,
      style: const TextStyle(color: kTextPrimary, fontSize: 14),
      cursorColor: kAccent,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: kTextSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: kTextSecondary, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: kSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kAccent, width: 1.5),
        ),
      ),
    );
  }
}

/// Bouton principal plein accent avec état de chargement.
class AuthButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  const AuthButton({super.key, required this.label, required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: kAccent,
          disabledBackgroundColor: kAccent.withValues(alpha: 0.5),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        ),
        child: loading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Bannière d'erreur.
class AuthError extends StatelessWidget {
  final String message;
  const AuthError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kError.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kError.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: kErrorText, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(color: kErrorText, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
