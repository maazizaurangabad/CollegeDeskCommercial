import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Lets the user choose where to save a file. On Android the picker writes
/// the bytes itself; on Windows we write to the chosen path.
/// Returns false if the user cancelled.
Future<bool> saveBytesWithDialog({required String fileName, required List<int> bytes, required String title}) async {
  final data = Uint8List.fromList(bytes);
  final path = await FilePicker.platform.saveFile(dialogTitle: title, fileName: fileName, bytes: data);
  if (path == null) return false;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await File(path).writeAsBytes(data, flush: true);
  }
  return true;
}
