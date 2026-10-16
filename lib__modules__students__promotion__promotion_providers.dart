import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/academic/academic_controller.dart';
import '../../../platform/data/data_providers.dart';
import '../../fees/application/fees_providers.dart';
import '../../results/application/results_providers.dart';
import '../application/students_providers.dart';
import 'promotion_repository.dart';

final promotionRepositoryProvider = Provider<PromotionRepository>(
  (ref) => PromotionRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(sessionProvider),
    ref.watch(studentRepositoryProvider),
    ref.watch(academicRepositoryProvider),
    ref.watch(resultRepositoryProvider),
    ref.watch(feeRepositoryProvider),
  ),
);
