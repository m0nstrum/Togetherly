import '../../dict_strings.dart' show ruEn;

String forkRuCountWord(int count, String one, String few, String many) {
  final n = count.abs();
  if (n % 100 >= 11 && n % 100 <= 14) return many;
  if (n % 10 == 1) return one;
  if (n % 10 >= 2 && n % 10 <= 4) return few;
  return many;
}

String forkDaysWord(int n) => ruEn(forkRuCountWord(n, 'день', 'дня', 'дней'), n == 1 ? 'day' : 'days');
String forkMemoriesWord(int n) => ruEn(forkRuCountWord(n, 'воспоминание', 'воспоминания', 'воспоминаний'), n == 1 ? 'memory' : 'memories');
String forkMessagesWord(int n) => ruEn(forkRuCountWord(n, 'сообщение', 'сообщения', 'сообщений'), n == 1 ? 'message' : 'messages');

String forkCanvasesWord(int n) => ruEn(forkRuCountWord(n, 'холст', 'холста', 'холстов'), n == 1 ? 'canvas' : 'canvases');
