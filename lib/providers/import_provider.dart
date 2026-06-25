import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/download_service.dart';

/// Étapes d'un import externe (alignées sur les statuts du service Python).
/// `streaming` est à part : il décrit le chargement d'un flux temps réel
/// (mode `EXTERNAL_STREAM`), pas un import S3.
enum ImportStatus { pending, downloading, extracting, validating, uploading, saving, streaming, completed, error }

/// Un import en cours (ou récemment terminé) — affiché dans la bannière.
class ImportJob {
  final String id; // = track.id
  final String title;
  final ImportStatus status;
  final String? error;

  const ImportJob({required this.id, required this.title, required this.status, this.error});

  ImportJob copyWith({ImportStatus? status, String? error}) => ImportJob(
        id: id,
        title: title,
        status: status ?? this.status,
        error: error ?? this.error,
      );

  bool get isDone => status == ImportStatus.completed || status == ImportStatus.error;

  /// Libellé lisible de l'étape courante.
  String get label => switch (status) {
        ImportStatus.pending => 'En attente…',
        ImportStatus.downloading => 'Téléchargement…',
        ImportStatus.extracting => 'Extraction…',
        ImportStatus.validating => 'Validation…',
        ImportStatus.uploading => 'Envoi…',
        ImportStatus.saving => 'Enregistrement…',
        ImportStatus.streaming => 'Chargement du flux…',
        ImportStatus.completed => 'Importé sur Mkzik ✓',
        ImportStatus.error => error ?? 'Échec de l\'import',
      };
}

ImportStatus _statusFrom(String s) => switch (s) {
      'extracting' => ImportStatus.extracting,
      'validating' => ImportStatus.validating,
      'uploading' => ImportStatus.uploading,
      'saving' => ImportStatus.saving,
      'downloading' => ImportStatus.downloading,
      _ => ImportStatus.pending,
    };

/// Gère les imports externes et leurs notifications.
class ImportNotifier extends StateNotifier<List<ImportJob>> {
  ImportNotifier() : super(const []);

  /// Lance l'import d'un track externe et suit sa progression dans la bannière.
  /// Renvoie le track intégré (jouable), ou null en cas d'échec.
  Future<Track?> startAndWait(Track track) async {
    final id = track.id;
    // Évite de relancer un import déjà en cours pour le même titre
    final existing = state.where((j) => j.id == id && !j.isDone);
    if (existing.isNotEmpty) return null;

    _upsert(ImportJob(id: id, title: track.title, status: ImportStatus.pending));

    String? errorMsg;
    final imported = await DownloadService.importAndWait(
      track,
      onStatus: (s) => _patch(id, status: _statusFrom(s)),
      onError: (m) => errorMsg = m,
    );

    if (imported != null) {
      _patch(id, status: ImportStatus.completed);
      _autoDismiss(id, const Duration(seconds: 3));
    } else {
      _patch(id, status: ImportStatus.error, error: errorMsg ?? 'Import impossible');
      _autoDismiss(id, const Duration(seconds: 6));
    }
    return imported;
  }

  // ── Stream temps réel (mode EXTERNAL_STREAM) ────────────────────────────────

  /// Affiche un spinner « Chargement du flux… » le temps que le stream temps réel
  /// (yt-dlp) se résolve et se mette en mémoire tampon. Renvoie l'id du job, à
  /// passer à [dismiss] dès que la lecture démarre, ou à [streamError] si échec.
  String startStream(Track track) {
    final id = 'stream-${track.id}';
    _upsert(ImportJob(id: id, title: track.title, status: ImportStatus.streaming));
    return id;
  }

  /// Bascule un job de stream en erreur (affiché brièvement puis auto-fermé).
  void streamError(String id, String message) {
    _patch(id, status: ImportStatus.error, error: message);
    _autoDismiss(id, const Duration(seconds: 5));
  }

  void dismiss(String id) => state = state.where((j) => j.id != id).toList();

  void _upsert(ImportJob job) {
    final i = state.indexWhere((j) => j.id == job.id);
    if (i < 0) {
      state = [...state, job];
    } else {
      final copy = [...state]..[i] = job;
      state = copy;
    }
  }

  void _patch(String id, {ImportStatus? status, String? error}) {
    state = [
      for (final j in state)
        if (j.id == id) j.copyWith(status: status, error: error) else j,
    ];
  }

  void _autoDismiss(String id, Duration d) => Future.delayed(d, () => dismiss(id));
}

final importProvider = StateNotifierProvider<ImportNotifier, List<ImportJob>>((ref) => ImportNotifier());
