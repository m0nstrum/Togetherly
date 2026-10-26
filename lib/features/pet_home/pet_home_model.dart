/// Shared pet home. No need meters, decay, daily quotas, or expiring rewards.
library;

import 'package:characters/characters.dart';

enum PetCare { feed, wash, play, pet }

enum PetSlot { seat, bed, rug, plant, decor, picture }

class PetItem {
  const PetItem(this.id, this.ru, this.en, this.slot, this.price);
  final String id, ru, en;
  final PetSlot slot;
  final int price;
  String get asset => 'assets/pet_home/$id.webp';
  String label(bool english) => english ? en : ru;
}

const petItems = <PetItem>[
  PetItem('sofa', 'Диван для всех', 'Everyone’s sofa', PetSlot.seat, 0),
  PetItem('armchair', 'Персиковое кресло', 'Peach armchair', PetSlot.seat, 16),
  PetItem('daybed', 'Мягкая лежанка', 'Soft daybed', PetSlot.bed, 22),
  PetItem('cottage', 'Личный домик', 'Little cottage', PetSlot.bed, 30),
  PetItem('rug_cream', 'Плетёный ковёр', 'Braided rug', PetSlot.rug, 0),
  PetItem('rug_sage', 'Шалфейный ковёр', 'Sage rug', PetSlot.rug, 10),
  PetItem('monstera', 'Зелёный сосед', 'Leafy neighbour', PetSlot.plant, 14),
  PetItem('daisies', 'Ромашки на столике', 'Daisy table', PetSlot.decor, 12),
  PetItem('lamp', 'Вечерний свет', 'Evening glow', PetSlot.decor, 16),
  PetItem('frame', 'Сердечко в рамке', 'Framed heart', PetSlot.picture, 8),
];

PetItem petItem(String id) => petItems.firstWhere((item) => item.id == id);

class PetRole {
  const PetRole(this.kind, [this.custom = '']);
  final String kind, custom;
  String address(String name, bool english) => switch (kind) {
    'mom' => english ? 'Mom' : 'Мама',
    'dad' => english ? 'Dad' : 'Папа',
    'custom' when custom.trim().isNotEmpty => custom.trim(),
    _ => name.trim().isEmpty ? (english ? 'Friend' : 'Друг') : name.trim(),
  };
  Map<String, dynamic> toJson() => {'kind': kind, 'custom': custom};
  factory PetRole.fromJson(Map data) => PetRole(
    {'mom', 'dad', 'name', 'custom'}.contains(data['kind'])
        ? data['kind'] as String
        : 'name',
    data['custom'] is String
        ? (data['custom'] as String).characters.take(40).toString()
        : '',
  );
}

class PetHome {
  PetHome({
    this.balance = 40,
    Set<String>? owned,
    Map<PetSlot, String>? equipped,
    Map<String, int>? care,
    Map<String, PetRole>? roles,
    this.activityLevel = 0,
    this.lastCare,
    this.lastActor = '',
    this.lastAt = 0,
    List<String>? operations,
  }) : owned = owned ?? {'sofa', 'rug_cream'},
       equipped = equipped ?? {PetSlot.seat: 'sofa', PetSlot.rug: 'rug_cream'},
       care = care ?? {},
       roles = roles ?? {},
       operations = operations ?? [];

  int balance, activityLevel, lastAt;
  final Set<String> owned;
  final Map<PetSlot, String> equipped;
  final Map<String, int> care;
  final Map<String, PetRole> roles;
  final List<String> operations;
  PetCare? lastCare;
  String lastActor;

  PetHome copy() => PetHome.fromJson(toJson());

  /// Permanent milestones, identical whether actions happen today or next year.
  int careFor(PetCare action, String uid, int at) {
    final n = (care[action.name] ?? 0) + 1;
    care[action.name] = n;
    final reward = switch (n) {
      1 => 5,
      5 => 5,
      20 => 10,
      50 => 15,
      100 => 20,
      _ => 0,
    };
    balance += reward;
    lastCare = action;
    lastActor = uid;
    lastAt = at;
    return reward;
  }

  /// Existing shared XP earns permanent furnishing credit, not a daily task.
  void creditActivity(int xp) {
    final level = (xp ~/ 50).clamp(0, 10000);
    if (level > activityLevel) {
      balance += (level - activityLevel) * 5;
      activityLevel = level;
    }
  }

  void furnish(String id) {
    final item = petItem(id);
    if (!owned.contains(id)) {
      if (balance < item.price) throw const PetNotEnoughCozy();
      balance -= item.price;
      owned.add(id);
    }
    equipped[item.slot] = id;
  }

  void remember(String operation) {
    operations.add(operation);
    if (operations.length > 128) {
      operations.removeRange(0, operations.length - 128);
    }
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'balance': balance,
    'owned': owned.toList(),
    'equipped': equipped.map((key, value) => MapEntry(key.name, value)),
    'care': care,
    'roles': roles.map((key, value) => MapEntry(key, value.toJson())),
    'activity': activityLevel,
    'lastCare': lastCare?.name,
    'lastActor': lastActor,
    'lastAt': lastAt,
    'operations': operations,
  };

  factory PetHome.fromJson(Map data) {
    if (data['v'] != 1 ||
        data['owned'] is! List ||
        data['equipped'] is! Map ||
        data['balance'] is! int ||
        (data['balance'] as int) < 0) {
      throw const FormatException('Invalid pet home');
    }
    final valid = petItems.map((item) => item.id).toSet();
    final owned = (data['owned'] as List)
        .whereType<String>()
        .where(valid.contains)
        .toSet();
    final equipped = <PetSlot, String>{};
    for (final slot in PetSlot.values) {
      final id = data['equipped'][slot.name];
      if (id is String && owned.contains(id) && petItem(id).slot == slot) {
        equipped[slot] = id;
      }
    }
    final care = <String, int>{};
    if (data['care'] is Map) {
      for (final action in PetCare.values) {
        final value = data['care'][action.name];
        if (value is int && value >= 0 && value <= 100000000) {
          care[action.name] = value;
        }
      }
    }
    final roles = <String, PetRole>{};
    if (data['roles'] is Map) {
      for (final e in (data['roles'] as Map).entries.take(20)) {
        if (e.key is String && e.value is Map) {
          roles[e.key as String] = PetRole.fromJson(e.value as Map);
        }
      }
    }
    return PetHome(
      balance: (data['balance'] as int).clamp(0, 100000000),
      owned: owned,
      equipped: equipped,
      care: care,
      roles: roles,
      activityLevel: data['activity'] is int
          ? (data['activity'] as int).clamp(0, 10000)
          : 0,
      lastCare: PetCare.values
          .where((a) => a.name == data['lastCare'])
          .firstOrNull,
      lastActor: data['lastActor'] is String ? data['lastActor'] as String : '',
      lastAt: data['lastAt'] is int ? data['lastAt'] as int : 0,
      operations: data['operations'] is List
          ? (data['operations'] as List).whereType<String>().take(128).toList()
          : [],
    );
  }
}

class PetNotEnoughCozy implements Exception {
  const PetNotEnoughCozy();
}
