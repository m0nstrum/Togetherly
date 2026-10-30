import 'dart:io';

/// Исходник экрана целиком: файл экрана и его части в папке рядом
/// (`lib/screens/widget_screen.dart` + `lib/screens/widget_screen/*.dart`).
///
/// Большие экраны режутся на части (A12): сторожу всё равно, в каком файле
/// лежит проверяемая строка, лишь бы она была у экрана.
String screenSource(String screenPath) {
  final buf = StringBuffer(File(screenPath).readAsStringSync());
  final dir = Directory(screenPath.replaceFirst(RegExp(r'\.dart$'), ''));
  if (dir.existsSync()) {
    final parts =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in parts) {
      buf
        ..writeln()
        ..write(f.readAsStringSync());
    }
  }
  return buf.toString();
}
