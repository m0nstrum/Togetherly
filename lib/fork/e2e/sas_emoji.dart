// Сгенерировано из sas-emoji.json спецификации Matrix
// (matrix-org/matrix-spec, data-definitions/sas-emoji.json). Порядок и
// номера — как в спецификации: индекс = 6 бит кода сверки.
//
// fork: в русском переводе Matrix 🔧 и 🔑 оба «Ключ» — голосом не различить,
// поэтому 🔧 здесь «Гаечный ключ». Уникальность названий проверяет тест.

class SasEmoji {
  const SasEmoji(this.symbol, this.en, this.ru);

  final String symbol;
  final String en;
  final String ru;

  String name(String languageCode) => languageCode == 'ru' ? ru : en;
}

const List<SasEmoji> sasEmoji = [
  SasEmoji('🐶', 'Dog', 'Собака'),
  SasEmoji('🐱', 'Cat', 'Кошка'),
  SasEmoji('🦁', 'Lion', 'Лев'),
  SasEmoji('🐎', 'Horse', 'Лошадь'),
  SasEmoji('🦄', 'Unicorn', 'Единорог'),
  SasEmoji('🐷', 'Pig', 'Свинья'),
  SasEmoji('🐘', 'Elephant', 'Слон'),
  SasEmoji('🐰', 'Rabbit', 'Кролик'),
  SasEmoji('🐼', 'Panda', 'Панда'),
  SasEmoji('🐓', 'Rooster', 'Петух'),
  SasEmoji('🐧', 'Penguin', 'Пингвин'),
  SasEmoji('🐢', 'Turtle', 'Черепаха'),
  SasEmoji('🐟', 'Fish', 'Рыба'),
  SasEmoji('🐙', 'Octopus', 'Осьминог'),
  SasEmoji('🦋', 'Butterfly', 'Бабочка'),
  SasEmoji('🌷', 'Flower', 'Цветок'),
  SasEmoji('🌳', 'Tree', 'Дерево'),
  SasEmoji('🌵', 'Cactus', 'Кактус'),
  SasEmoji('🍄', 'Mushroom', 'Гриб'),
  SasEmoji('🌏', 'Globe', 'Глобус'),
  SasEmoji('🌙', 'Moon', 'Луна'),
  SasEmoji('☁️', 'Cloud', 'Облако'),
  SasEmoji('🔥', 'Fire', 'Огонь'),
  SasEmoji('🍌', 'Banana', 'Банан'),
  SasEmoji('🍎', 'Apple', 'Яблоко'),
  SasEmoji('🍓', 'Strawberry', 'Клубника'),
  SasEmoji('🌽', 'Corn', 'Кукуруза'),
  SasEmoji('🍕', 'Pizza', 'Пицца'),
  SasEmoji('🎂', 'Cake', 'Торт'),
  SasEmoji('❤️', 'Heart', 'Сердце'),
  SasEmoji('😀', 'Smiley', 'Улыбка'),
  SasEmoji('🤖', 'Robot', 'Робот'),
  SasEmoji('🎩', 'Hat', 'Шляпа'),
  SasEmoji('👓', 'Glasses', 'Очки'),
  SasEmoji('🔧', 'Spanner', 'Гаечный ключ'),
  SasEmoji('🎅', 'Santa', 'Санта'),
  SasEmoji('👍', 'Thumbs Up', 'Большой палец вверх'),
  SasEmoji('☂️', 'Umbrella', 'Зонт'),
  SasEmoji('⌛', 'Hourglass', 'Песочные часы'),
  SasEmoji('⏰', 'Clock', 'Часы'),
  SasEmoji('🎁', 'Gift', 'Подарок'),
  SasEmoji('💡', 'Light Bulb', 'Лампочка'),
  SasEmoji('📕', 'Book', 'Книга'),
  SasEmoji('✏️', 'Pencil', 'Карандаш'),
  SasEmoji('📎', 'Paperclip', 'Скрепка'),
  SasEmoji('✂️', 'Scissors', 'Ножницы'),
  SasEmoji('🔒', 'Lock', 'Замок'),
  SasEmoji('🔑', 'Key', 'Ключ'),
  SasEmoji('🔨', 'Hammer', 'Молоток'),
  SasEmoji('☎️', 'Telephone', 'Телефон'),
  SasEmoji('🏁', 'Flag', 'Флаг'),
  SasEmoji('🚂', 'Train', 'Поезд'),
  SasEmoji('🚲', 'Bicycle', 'Велосипед'),
  SasEmoji('✈️', 'Aeroplane', 'Самолёт'),
  SasEmoji('🚀', 'Rocket', 'Ракета'),
  SasEmoji('🏆', 'Trophy', 'Кубок'),
  SasEmoji('⚽', 'Ball', 'Мяч'),
  SasEmoji('🎸', 'Guitar', 'Гитара'),
  SasEmoji('🎺', 'Trumpet', 'Труба'),
  SasEmoji('🔔', 'Bell', 'Колокол'),
  SasEmoji('⚓', 'Anchor', 'Якорь'),
  SasEmoji('🎧', 'Headphones', 'Наушники'),
  SasEmoji('📁', 'Folder', 'Папка'),
  SasEmoji('📌', 'Pin', 'Булавка'),
];
