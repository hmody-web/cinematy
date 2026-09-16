import 'dart:io';

Future<String?> readTvLocalText(String path) async {
  var value = path.trim();
  if (value.startsWith('file://')) {
    value = Uri.parse(value).toFilePath();
  }
  final file = File(value);
  if (!await file.exists()) return null;
  return file.readAsString();
}
