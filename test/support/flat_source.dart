import 'dart:io';

/// Исходник без комментариев в конце строк, пробелов, переносов и висячих
/// запятых: проверки проводки сверяют код по смыслу, а не по тому, как его
/// разложил `dart format`.
String flat(String code) => code
    .replaceAll(RegExp(r'(?<=[\s,;{}()\[\]])//[^\n]*'), '')
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

/// [flat] от файла по пути [path].
String flatSource(String path) => flat(File(path).readAsStringSync());
