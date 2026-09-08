import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';

class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
      );

  @override
  ConsumerState<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  // Change password
  final _newPwd = TextEditingController();
  final _confirmPwd = TextEditingController();
  bool _pwdLoading = false;
  bool _pwdSuccess = false;
  String? _pwdError;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // Sessions actives
  List<AppSession>? _sessions;
  bool _sessionsLoading = false;
  bool _revokeOthersLoading = false;
  Set<int> _revokingIds = {};

  // Delete account
  final _delPwd = TextEditingController();
  final _delPwdConfirm = TextEditingController();
  bool _delLoading = false;
  String? _delError;
  bool _obscureDel = true;
  bool _obscureDelConfirm = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _sessionsLoading = true);
    final s = await SessionService.getSessions();
    if (mounted) setState(() { _sessions = s; _sessionsLoading = false; });
  }

  Future<void> _revokeSession(int id) async {
    setState(() => _revokingIds = {..._revokingIds, id});
    final ok = await SessionService.revokeSession(id);
    if (!mounted) return;
    if (ok) {
      setState(() => _sessions = _sessions?.where((s) => s.id != id).toList());
    }
    setState(() => _revokingIds = _revokingIds.difference({id}));
  }

  Future<void> _revokeOthers() async {
    setState(() => _revokeOthersLoading = true);
    final n = await SessionService.revokeOthers();
    if (!mounted) return;
    setState(() => _revokeOthersLoading = false);
    if (n > 0) await _loadSessions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(n > 0 ? '$n session${n > 1 ? 's' : ''} déconnectée${n > 1 ? 's' : ''}' : 'Aucune autre session active'),
      ));
    }
  }

  @override
  void dispose() {
    _newPwd.dispose();
    _confirmPwd.dispose();
    _delPwd.dispose();
    _delPwdConfirm.dispose();
    super.dispose();
  }

  // ── Change password ─────────────────────────────────────────────────────────

  Future<void> _changePassword() async {
    final pwd = _newPwd.text;
    final confirm = _confirmPwd.text;
    setState(() { _pwdError = null; _pwdSuccess = false; });

    if (pwd.isEmpty || confirm.isEmpty) {
      setState(() => _pwdError = 'Remplis les deux champs');
      return;
    }
    if (pwd != confirm) {
      setState(() => _pwdError = 'Les mots de passe ne correspondent pas');
      return;
    }
    setState(() => _pwdLoading = true);
    try {
      await AuthService.updateAccount(password: pwd);
      if (!mounted) return;
      _newPwd.clear();
      _confirmPwd.clear();
      setState(() => _pwdSuccess = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _pwdError = e.message);
    } finally {
      if (mounted) setState(() => _pwdLoading = false);
    }
  }

  // ── Delete account ──────────────────────────────────────────────────────────

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('Supprimer le compte ?',
            style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          'Cette action est irréversible. Toutes tes données seront supprimées définitivement.',
          style: TextStyle(color: kTextSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler', style: TextStyle(color: kTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Supprimer', style: TextStyle(color: kError)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    final pwd = _delPwd.text;
    final confirm = _delPwdConfirm.text;
    setState(() => _delError = null);

    if (pwd.isEmpty || confirm.isEmpty) {
      setState(() => _delError = 'Saisis ton mot de passe et sa confirmation');
      return;
    }
    setState(() => _delLoading = true);
    try {
      await AuthService.deleteAccount(pwd, confirm);
      if (!mounted) return;
      await ref.read(authProvider.notifier).logout();
    } on AuthException catch (e) {
      if (mounted) setState(() => _delError = e.message);
    } finally {
      if (mounted) setState(() => _delLoading = false);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 24, 0, 12),
        child: Text(text,
            style: const TextStyle(color: kTextPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
      );

  InputDecoration _inputDec(String label, IconData icon, {Widget? suffix}) => InputDecoration(
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
      );

  Widget _errorBanner(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: kError.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kError.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: kErrorText, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(color: kErrorText, fontSize: 12.5))),
        ]),
      );

  Widget _successBanner(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1B9265).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1B9265).withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF1B9265), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(color: Color(0xFF1B9265), fontSize: 12.5))),
        ]),
      );

  Widget _primaryBtn({required String label, required bool loading, required VoidCallback onPressed}) =>
      SizedBox(
        width: double.infinity,
        height: 48,
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
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      );

  Widget _dangerBtn({required String label, required bool loading, required VoidCallback onPressed}) =>
      SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: kError,
            side: BorderSide(color: kError.withValues(alpha: 0.6)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          ),
          child: loading
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: kError, strokeWidth: 2.5))
              : Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      );

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Paramètres du compte',
            style: TextStyle(color: kTextPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Changer le mot de passe ─────────────────────────────────────
            _sectionTitle('Changer le mot de passe'),

            if (_pwdError != null) _errorBanner(_pwdError!),
            if (_pwdSuccess) _successBanner('Mot de passe mis à jour.'),

            TextField(
              controller: _newPwd,
              obscureText: _obscureNew,
              style: const TextStyle(color: kTextPrimary, fontSize: 14),
              cursorColor: kAccent,
              decoration: _inputDec('Nouveau mot de passe', Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility,
                        color: kTextSecondary, size: 20),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  )),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPwd,
              obscureText: _obscureConfirm,
              style: const TextStyle(color: kTextPrimary, fontSize: 14),
              cursorColor: kAccent,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _changePassword(),
              decoration: _inputDec('Confirmer le nouveau mot de passe', Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility,
                        color: kTextSecondary, size: 20),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  )),
            ),
            const SizedBox(height: 16),
            _primaryBtn(
              label: 'Enregistrer le nouveau mot de passe',
              loading: _pwdLoading,
              onPressed: _changePassword,
            ),

            const SizedBox(height: 8),
            Divider(color: kBorder, height: 36),

            // ── Sessions actives ────────────────────────────────────────────
            _sectionTitle('Sessions actives'),

            if (_sessionsLoading && (_sessions == null))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: kAccent, strokeWidth: 2.5)),
              )
            else if (_sessions != null && _sessions!.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Aucune session trouvée.',
                    style: const TextStyle(color: kTextSecondary, fontSize: 13)),
              )
            else
              ...?_sessions?.map((s) => _SessionCard(
                    session: s,
                    loading: _revokingIds.contains(s.id),
                    onRevoke: s.isCurrent ? null : () => _revokeSession(s.id),
                  )),

            if ((_sessions?.any((s) => !s.isCurrent) ?? false)) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _revokeOthersLoading ? null : _revokeOthers,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kTextSecondary,
                    side: const BorderSide(color: kBorderSoft),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  ),
                  icon: _revokeOthersLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kTextSecondary))
                      : const Icon(Icons.logout_rounded, size: 17),
                  label: const Text('Déconnecter toutes les autres sessions',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],

            const SizedBox(height: 8),
            Divider(color: kBorder, height: 36),

            // ── Mentions légales ────────────────────────────────────────────
            _sectionTitle('Mentions légales'),
            _LegalRow(
              icon: Icons.description_outlined,
              label: "Conditions générales d'utilisation",
              onTap: () => _launch('https://william-tchang.fr/cgu'),
            ),
            const SizedBox(height: 8),
            _LegalRow(
              icon: Icons.privacy_tip_outlined,
              label: 'Politique de confidentialité',
              onTap: () => _launch('https://william-tchang.fr/privacy'),
            ),

            const SizedBox(height: 8),
            Divider(color: kBorder, height: 36),

            // ── Zone de danger ──────────────────────────────────────────────
            _sectionTitle('Zone de danger'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kError.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kError.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Supprimer mon compte',
                    style: TextStyle(color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cette action est irréversible. Toutes tes données (tracks, playlists, favoris) seront supprimées définitivement.',
                    style: TextStyle(color: kTextSecondary, fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  if (_delError != null) _errorBanner(_delError!),
                  TextField(
                    controller: _delPwd,
                    obscureText: _obscureDel,
                    style: const TextStyle(color: kTextPrimary, fontSize: 14),
                    cursorColor: kError,
                    decoration: _inputDec('Mot de passe actuel', Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(_obscureDel ? Icons.visibility_off : Icons.visibility,
                              color: kTextSecondary, size: 20),
                          onPressed: () => setState(() => _obscureDel = !_obscureDel),
                        )).copyWith(
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: kError.withValues(alpha: 0.8), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _delPwdConfirm,
                    obscureText: _obscureDelConfirm,
                    style: const TextStyle(color: kTextPrimary, fontSize: 14),
                    cursorColor: kError,
                    textInputAction: TextInputAction.done,
                    decoration: _inputDec('Confirmer le mot de passe', Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(_obscureDelConfirm ? Icons.visibility_off : Icons.visibility,
                              color: kTextSecondary, size: 20),
                          onPressed: () => setState(() => _obscureDelConfirm = !_obscureDelConfirm),
                        )).copyWith(
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: kError.withValues(alpha: 0.8), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _dangerBtn(
                    label: 'Supprimer mon compte',
                    loading: _delLoading,
                    onPressed: _confirmDeleteAccount,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final AppSession session;
  final bool loading;
  final VoidCallback? onRevoke;
  const _SessionCard({required this.session, required this.loading, this.onRevoke});

  String _formatDate(DateTime d) {
    final now = DateTime.now().toUtc();
    final dt = d.toUtc();
    final diff = now.difference(dt);
    if (diff.inMinutes < 2) return "À l'instant";
    if (diff.inHours < 1) return 'Il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: session.isCurrent ? kAccent.withValues(alpha: 0.4) : kBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            session.deviceLabel.contains('Android')
                ? Icons.phone_android_rounded
                : session.deviceLabel.contains('iPhone')
                    ? Icons.phone_iphone_rounded
                    : Icons.computer_rounded,
            color: session.isCurrent ? kAccent : kTextSecondary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(session.deviceLabel,
                      style: const TextStyle(color: kTextPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  if (session.isCurrent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: kAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Actuelle',
                          style: TextStyle(color: kAccent, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text('${session.ipAddress} · ${_formatDate(session.loginDate)}',
                    style: const TextStyle(color: kTextSecondary, fontSize: 11.5)),
              ],
            ),
          ),
          if (!session.isCurrent)
            loading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kTextSecondary))
                : IconButton(
                    icon: const Icon(Icons.close_rounded, color: kTextSecondary, size: 20),
                    tooltip: 'Déconnecter',
                    onPressed: onRevoke,
                    splashRadius: 20,
                  ),
        ],
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LegalRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kSurface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon, color: kTextSecondary, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: kTextPrimary, fontSize: 13.5, fontWeight: FontWeight.w500)),
            ),
            const Icon(Icons.open_in_new, color: kTextSecondary, size: 16),
          ]),
        ),
      ),
    );
  }
}
