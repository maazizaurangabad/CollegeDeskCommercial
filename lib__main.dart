import 'package:flutter/material.dart';

import 'app/startup/app_bootstrap.dart';
import 'app/startup/startup_error_app.dart';
import 'app/workspace_host.dart';
import 'platform/modules/module_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final registry = buildModuleRegistry();
  try {
    final startup = await AppBootstrap.open(registry);
    runApp(WorkspaceHost(initial: startup, registry: registry));
  } catch (error) {
    runApp(StartupErrorApp(details: '$error'));
  }
}
