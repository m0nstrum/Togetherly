import 'dart:math';

/// Event-specific, bilingual lines. User names are inserted without declension.
/// Only explicit actions speak; there is no repeating nagging timer.
class PetDialogue {
  PetDialogue({Random? random}) : _random = random ?? Random();
  final Random _random;
  final Map<String, List<int>> _bags = {};

  String next(
    String event, {
    required bool english,
    required String me,
    String other = '',
  }) {
    final lines = petLines[event] ?? petLines['idle']!;
    final bag = _bags.putIfAbsent(event, () => []);
    if (bag.isEmpty) {
      bag.addAll(List.generate(lines.length, (i) => i)..shuffle(_random));
    }
    final text = lines[bag.removeLast()].split('|')[english ? 1 : 0];
    return text.replaceAllMapped(
      RegExp(r'\{(me|other)\}'),
      (match) => match[1] == 'me' ? me : other,
    );
  }
}

// A shuffle bag exhausts a category before repeating. No guilt on returning.
const petLines = <String, List<String>>{
  'welcome': [
    '{me}, привет! Я тут.|{me}, hello! Here I am.',
    'О, мои люди.|Oh, my people.',
    'Как раз оставил вам место.|Saved a spot for you.',
    'Дома хорошо. Особенно сейчас.|Home feels good. Especially now.',
    'У меня всё спокойно. А у тебя?|All peaceful here. How about you?',
    'Заходи, уют уже готов.|Come in. The cozy is ready.',
    'Тут можно просто побыть.|We can just hang out here.',
    '{me}, обнимемся?|{me}, hug?',
    'Я немного подремал. Очень успешно.|I had a nap. Very successfully.',
    'Мой любимый звук — вы дома.|My favourite sound: you’re home.',
    'Привет! Сегодня я особенно пушистый. Мысленно.|Hello! Extra fluffy today. In spirit.',
    'Можно ничего не делать. Вместе.|We can do nothing. Together.',
    'Новости дома: тут по-прежнему уютно.|Home news: still cozy.',
    'Тебе какое место на диване?|Which sofa spot would you like?',
    'Я тут берёг мягкое место.|I kept the soft spot for you.',
    'Хорошо, что заглянули.|Lovely to see you.',
  ],
  'feed': [
    'Это мне? Тогда очень удачно зашли.|For me? Excellent timing.',
    'Надо подумать. Вкусно подумать.|Let me think. Delicious thoughts.',
    'Спасибо, {me}. Это было убедительно.|Thanks, {me}. Very convincing.',
    'Миска стала легче. Я счастливее.|Lighter bowl. Happier me.',
    'Угощение принято с уважением.|Treat accepted with respect.',
    'О, мой любимый размер порции.|Oh, my favourite portion size.',
    'Вкусно. Даже ушами слышно.|So tasty I can hear it.',
    'Я запомню этот хрум.|I’ll remember that crunch.',
    'Жую. Важное совещание.|Chewing. Important meeting.',
    'Маленький ресторан на одного.|A tiny restaurant for one.',
    'Еда с заботой вкуснее.|Food tastes better with care.',
    'Кажется, я мурчу изнутри.|I think I’m purring inside.',
    'Крошки? Это декор.|Crumbs? Those are decor.',
    '{me}, у тебя талант к угощениям.|{me}, you have a gift for treats.',
    'Сейчас бы полежать после такого.|A little rest after that.',
    'Хрум. Это моя рецензия.|Crunch. That’s my review.',
  ],
  'wash': [
    'Теперь я пахну прилично.|Now I smell respectable.',
    'Пена большая. Я маленький.|Big bubbles. Little me.',
    'Смотрите, облако на голове.|Look, a cloud on my head.',
    'Пузырьки знают своё дело.|Bubbles know their business.',
    'Буль. Это спасибо.|Blub. That means thank you.',
    '{me}, полотенце очень кстати.|{me}, excellent towel timing.',
    'Свежесть: достигнута.|Freshness: achieved.',
    'Я теперь парадный.|All dressed up in clean.',
    'Можно завернуться в уют?|Can I wrap up in cozy?',
    'Был хорошенький. Стал чистенький.|Cute before. Clean now.',
    'У меня пенные усы.|I have a bubble moustache.',
    'Пахну домом и немного мылом.|Smells like home. And a little soap.',
    'Полотенце — это тоже объятие.|A towel is a kind of hug.',
    'Пузырь улетел. Передаст привет.|A bubble flew away. Sends its love.',
    'Водные процедуры с достоинством.|A dignified little bath.',
    'Готов к мягкому пледу.|Ready for a soft blanket.',
  ],
  'play': [
    'Мяч сам не покатится. Хотя попробуем.|The ball won’t roll itself. Let’s see.',
    'У меня лапки и большие планы.|Little paws. Big plans.',
    '{me}, лови хорошее настроение.|{me}, catch some good cheer.',
    'Это был спортивный подвиг.|That was an athletic achievement.',
    'Победила дружба. И немножко я.|Friendship won. And a little bit me.',
    'Я очень быстрый. Местами.|I’m very fast. In places.',
    'Пол — отличное игровое поле.|The floor makes a fine playing field.',
    'Прыжок маленький, радость большая.|Little jump. Big joy.',
    'Кажется, у мяча тоже весело.|I think the ball is having fun too.',
    'Поиграли. Можно гордиться собой.|We played. We can be proud.',
    'Серьёзные дела на мягком ковре.|Serious business on a soft rug.',
    'Ой. Это был мой лучший поворот.|Oh! My best turn yet.',
    'Сейчас покажу движение. Вот.|Watch this move. There.',
    'Ура можно тихо. Ура.|Hooray can be quiet. Hooray.',
    'Вот это приключение в пределах ковра.|An adventure within rug distance.',
    'Мяч круглый. День хороший.|Round ball. Good day.',
  ],
  'pet': [
    'Вот тут ещё.|A little more right there.',
    'Все дела немного подождут.|Everything else can wait a moment.',
    '{me}, у тебя тёплые руки.|{me}, your hands are warm.',
    'Я официально растаял.|Officially melted.',
    'Можно так и посидеть.|We can stay like this.',
    'Это моё любимое занятие без занятия.|My favourite thing that isn’t a thing.',
    'Мур. На всех доступных языках.|Purr. In every available language.',
    'Кнопка уюта найдена.|You found the cozy button.',
    'Я маленький, а нежности много.|Little me. Lots of affection.',
    'Так вот как выглядит хороший день.|So this is what a good day feels like.',
    'Сейчас я очень домашний.|Feeling very at home.',
    'Тихонько обнимаю в ответ.|A quiet hug back.',
    'Можно без слов. Вот так.|No words needed. Just this.',
    'Уши довольны. Всё остальное тоже.|Happy ears. Happy everything.',
    'Здесь мне хорошо.|I feel good here.',
    'Давай сохраним эту минутку.|Let’s keep this little moment.',
  ],
  'decorate': [
    'Проверка на уют: пройдена.|Cozy inspection: passed.',
    'Теперь это мой угол. И ваш тоже.|My corner now. Yours too.',
    'Новое место для важных лежаний.|A new spot for important lounging.',
    'Спасибо, {me}. Очень по-домашнему.|Thanks, {me}. Feels like home.',
    'Так. Тут будет хорошо.|Yes. This will feel good.',
    'Я уже мысленно тут устроился.|I’ve already settled in. Mentally.',
    'Дому идёт.|It suits our home.',
    'Важная перестановка маленького мира.|A big change in a little world.',
    'Стало ещё немного нашим.|A little more ours now.',
    'У меня хороший вкус. У вас тоже.|I have good taste. You do too.',
    'Одобряю всем своим видом.|Approved with my whole self.',
    'Комната улыбается.|The room is smiling.',
    'Тут будут жить хорошие вечера.|Good evenings will live here.',
    'Всё, я обживаюсь.|Right. Settling in.',
    'Мягкость надо проверить лично.|Softness needs personal testing.',
    'Каждая вещь — маленькое «мы».|Every little thing is a little us.',
  ],
  'idle': [
    'Сегодня планирую лежать с выражением.|Today: lying down expressively.',
    'Проверяю солнечное пятно.|Inspecting a patch of sunlight.',
    'Уют сам себя не наведёт. Хотя я пробую.|Cozy won’t make itself. I’m trying.',
    'Мысли мягкие. День тоже.|Soft thoughts. Soft day.',
    'Что-то хорошее просто так.|Something nice, just because.',
    'У окна интересный свет.|Interesting light by the window.',
    'Никаких срочных дел.|No urgent pet business.',
    'Мне подходит этот ковёр.|This rug suits me.',
    'Планы на вечер: быть тут.|Evening plans: being here.',
    'Тихий час — это состояние души.|Nap time is a state of mind.',
    'Дом — это когда есть своё место.|Home is having your own spot.',
    'Всё важное уже рядом.|The important things are close.',
    'Просто машу лапкой.|Just a little wave.',
    'Поймал хорошую мысль. Отпускать не буду.|Caught a nice thought. Keeping it.',
    'Тут живёт наша маленькая история.|Our little story lives here.',
    'Полежать? Сильная идея.|Lie down? Strong idea.',
  ],
};
