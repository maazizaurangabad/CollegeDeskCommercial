import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/data/data_providers.dart';
import 'document_files.dart';
import 'document_models.dart';
import 'document_repository.dart';

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(sessionProvider),
    ref.watch(appSettingsRepositoryProvider),
  ),
);

/// Bumped after any document change.
final documentsRevisionProvider = StateProvider<int>((ref) => 0);

final documentTypesProvider = FutureProvider<List<DocumentType>>((ref) {
  ref.watch(documentsRevisionProvider);
  return ref.watch(documentRepositoryProvider).types();
});

final studentDocumentsProvider = FutureProvider.autoDispose.family<List<StudentDocument>, String>((ref, studentId) {
  ref.watch(documentsRevisionProvider);
  return ref.watch(documentRepositoryProvider).forStudent(studentId);
});

/// Where scans are kept; null before the institution's folder is ready.
final documentFilesProvider = Provider<DocumentFiles?>((ref) {
  final dir = ref.watch(startupStateProvider).mediaDir;
  return dir == null ? null : DocumentFiles(dir);
});
