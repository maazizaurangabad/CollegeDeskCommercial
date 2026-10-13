import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/ids/uuid7.dart';

/// One institution's data on this device.
class WorkspaceInfo {
  const WorkspaceInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.createdAt,
    required this.isDemo,
  });

  final String id;
  final String name;
  final String fileName;
  final String createdAt;

  /// Demo workspaces hold sample data only.
  final bool isDemo;

  WorkspaceInfo withName(String newName) =>
      WorkspaceInfo(id: id, name: newName, fileName: fileName, createdAt: createdAt, isDemo: isDemo);

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'fileName': fileName, 'createdAt': createdAt, 'isDemo': isDemo};

  /// Workspaces from build 1b have no isDemo flag; they were all demo.
  factory WorkspaceInfo.fromJson(Map<String, Object?> json) => WorkspaceInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        fileName: json['fileName'] as String,
        createdAt: json['createdAt'] as String,
        isDemo: json['isDemo'] as bool? ?? true,
      );
}

/// A small index file listing the institutions on this device.
/// It holds no student data, only names and file names.
class WorkspaceRegistry {
  WorkspaceRegistry._(this._file, this._workspaces, this._lastOpenedId);

  final File _file;
  final List<WorkspaceInfo> _workspaces;
  String? _lastOpenedId;

  static const _formatVersion = 1;

  static Future<WorkspaceRegistry> load(Directory dir) async {
    final file = File(p.join(dir.path, 'workspaces.json'));
    if (!file.existsSync()) return WorkspaceRegistry._(file, [], null);
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final list = (json['workspaces'] as List<Object?>? ?? [])
        .map((e) => WorkspaceInfo.fromJson(e! as Map<String, Object?>))
        .toList();
    return WorkspaceRegistry._(file, list, json['lastOpened'] as String?);
  }

  List<WorkspaceInfo> get workspaces => List.unmodifiable(_workspaces);

  WorkspaceInfo? get lastOpened {
    for (final w in _workspaces) {
      if (w.id == _lastOpenedId) return w;
    }
    return _workspaces.isEmpty ? null : _workspaces.first;
  }

  WorkspaceInfo? byId(String id) {
    for (final w in _workspaces) {
      if (w.id == id) return w;
    }
    return null;
  }

  Future<void> setLastOpened(String id) async {
    if (byId(id) == null || _lastOpenedId == id) return;
    _lastOpenedId = id;
    await _save();
  }

  /// Keeps the switcher's name in step when the institution is renamed.
  Future<void> rename(String id, String name) async {
    final index = _workspaces.indexWhere((w) => w.id == id);
    if (index < 0 || _workspaces[index].name == name) return;
    _workspaces[index] = _workspaces[index].withName(name);
    await _save();
  }

  /// Adds an institution restored from a backup, keeping its original id.
  Future<WorkspaceInfo> register({required String id, required String name, required bool isDemo}) async {
    final existing = byId(id);
    if (existing != null) return existing;
    final info = WorkspaceInfo(
      id: id,
      name: name,
      fileName: 'org_$id.db',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      isDemo: isDemo,
    );
    _workspaces.add(info);
    await _save();
    return info;
  }

  /// Used only to undo a workspace whose creation failed.
  Future<void> remove(String id) async {
    _workspaces.removeWhere((w) => w.id == id);
    if (_lastOpenedId == id) _lastOpenedId = _workspaces.isEmpty ? null : _workspaces.first.id;
    await _save();
  }

  Future<WorkspaceInfo> create(String name, {required bool isDemo}) async {
    final id = Uuid7.generate();
    final info = WorkspaceInfo(
      id: id,
      name: name,
      fileName: 'org_$id.db',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      isDemo: isDemo,
    );
    _workspaces.add(info);
    _lastOpenedId = id;
    await _save();
    return info;
  }

  /// Writes to a temporary file first, then renames, so a crash
  /// mid-write never leaves a half-written index.
  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'formatVersion': _formatVersion,
      'lastOpened': _lastOpenedId,
      'workspaces': _workspaces.map((w) => w.toJson()).toList(),
    }));
    await tmp.rename(_file.path);
  }
}
