import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shiksha_desk/platform/workspace/workspace_registry.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('sd_registry_'));
  tearDown(() async => dir.delete(recursive: true));

  test('workspaces saved by build 1b are treated as demo', () async {
    await File(p.join(dir.path, 'workspaces.json')).writeAsString(jsonEncode({
      'formatVersion': 1,
      'lastOpened': 'a',
      'workspaces': [
        {'id': 'a', 'name': 'Old demo', 'fileName': 'org_a.db', 'createdAt': '2026-10-01T00:00:00Z'},
      ],
    }));
    final registry = await WorkspaceRegistry.load(dir);
    expect(registry.lastOpened?.isDemo, isTrue);
  });

  test('create, rename, switch and remove survive a reload', () async {
    final registry = await WorkspaceRegistry.load(dir);
    final demo = await registry.create('Demo', isDemo: true);
    final real = await registry.create('Real College', isDemo: false);
    await registry.rename(real.id, 'Real College Renamed');
    await registry.setLastOpened(demo.id);

    final reloaded = await WorkspaceRegistry.load(dir);
    expect(reloaded.workspaces, hasLength(2));
    expect(reloaded.lastOpened?.id, demo.id);
    expect(reloaded.byId(real.id)?.name, 'Real College Renamed');
    expect(reloaded.byId(real.id)?.isDemo, isFalse);

    await reloaded.remove(real.id);
    expect((await WorkspaceRegistry.load(dir)).workspaces, hasLength(1));
  });
}
