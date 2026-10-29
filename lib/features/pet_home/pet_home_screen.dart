import 'dart:async';
import 'package:flutter/material.dart';
import '../../fork/e2e/record_codec.dart';
import '../../services/catch_up_driver.dart';
import '../../services/centrifugo_service.dart';
import '../../services/locale_service.dart';
import '../../widgets/app_sheet.dart';
import 'pet_dialogue.dart';
import 'pet_home_model.dart';
import 'pet_home_repository.dart';
import 'pet_room.dart';

class PetHomeScreen extends StatelessWidget {
  const PetHomeScreen({
    super.key,
    required this.groupId,
    required this.uid,
    required this.names,
    required this.family,
    required this.pet,
    required this.openGallery,
    required this.sharedXp,
    this.repository,
    this.isCurrent,
    this.readOnly = false,
  });
  final String groupId, uid;
  final Map<String, String> names;
  final bool family, readOnly;
  final Widget pet;
  final VoidCallback openGallery;
  final int Function() sharedXp;
  final bool Function()? isCurrent;
  final PetHomeRepository? repository;
  @override
  Widget build(BuildContext context) => Theme(
    data: _homeTheme,
    child: _PetHomeContent(key: ValueKey('$groupId/$uid'), screen: this),
  );
}

class _PetHomeContent extends StatefulWidget {
  const _PetHomeContent({super.key, required this.screen});
  final PetHomeScreen screen;
  @override
  State<_PetHomeContent> createState() => _PetHomeScreenState();
}

final _homeTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'Onest',
  colorScheme: ColorScheme.fromSeed(
    seedColor: petSage,
    brightness: Brightness.light,
    surface: petCream,
    onSurface: petInk,
    primary: const Color(0xFF67724E),
  ),
  scaffoldBackgroundColor: petCream,
);

class _PetHomeScreenState extends State<_PetHomeContent>
    with WidgetsBindingObserver {
  PetHomeScreen get config => widget.screen;
  late final PetHomeRepository _repo =
      config.repository ?? PetHomeRepository.production();
  final _dialogue = PetDialogue();
  PetHome? _home;
  bool _busy = false, _loading = false, _foreground = true;
  String? _error, _speech;
  PetCare? _action;
  int _animation = 0, _generation = 0;
  Timer? _bubbleTimer;

  /// Догон того, что прошло мимо сокета: после переподключения и, пока
  /// подписки на канал пары нет, раз в 15 с. Возврат в приложение экран
  /// перечитывает сам ([didChangeAppLifecycleState]).
  CatchUpDriver? _catchUp;
  final StreamController<bool> _visible = StreamController<bool>.broadcast();
  RtUnsub? _unsubscribe;
  bool get _english => !LocaleService.instance.isRussian;
  String t(String ru, String en) => _english ? en : ru;
  bool get _current =>
      _repo.uid() == config.uid && (config.isCurrent?.call() ?? true);
  bool get _canAct => _current && !config.readOnly && !_busy && _home != null;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh(greet: true));
    if (config.repository == null) unawaited(_listen());
    final channel = 'pair:${config.groupId}';
    _catchUp = CatchUpDriver(
      catchUp: _refresh,
      reconnected: CentrifugoService.instance.reconnected,
      foreground: _visible.stream,
      subscribed: () => CentrifugoService.instance.isSubscribed(channel),
      // Возврат в приложение догоняет сам экран.
      minAway: const Duration(days: 365),
    );
  }

  Future<void> _listen() async {
    try {
      final unsub = await CentrifugoService.instance.subscribeDelta(
        'pair:${config.groupId}',
        'pet_homes',
        (_) {
          if (mounted && _foreground) unawaited(_refresh());
        },
        match: (r) => r.data['group_id'] == config.groupId,
      );
      if (!mounted) {
        await unsub();
      } else {
        _unsubscribe = unsub;
      }
    } catch (_) {
      // Foreground refresh also reconciles missed socket events.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _visible.add(_foreground);
    if (_foreground) {
      unawaited(_refresh());
    } else {
      _bubbleTimer?.cancel();
      if (mounted) {
        setState(() {
          _speech = null;
          _action = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _bubbleTimer?.cancel();
    _catchUp?.dispose();
    unawaited(_visible.close());
    _unsubscribe?.call();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _address(String uid) {
    var role = _home?.roles[uid];
    if (!config.family && (role?.kind == 'mom' || role?.kind == 'dad')) {
      role = const PetRole('name');
    }
    return (role ?? const PetRole('name')).address(
      config.names[uid] ?? '',
      _english,
    );
  }

  Future<void> _refresh({bool greet = false}) async {
    if (_loading || _busy || !_current) return;
    _loading = true;
    final generation = _generation;
    try {
      final snapshot = await _repo.load(config.groupId);
      if (!mounted || generation != _generation || !_current) return;
      final previous = _home;
      setState(() {
        _home = snapshot.home..creditActivity(config.sharedXp());
        _error = null;
      });
      if (greet) {
        _say('welcome');
      } else if (previous != null &&
          snapshot.home.lastAt != previous.lastAt &&
          snapshot.home.lastActor != config.uid &&
          snapshot.home.lastCare != null) {
        setState(() {
          _action = snapshot.home.lastCare;
          _animation++;
        });
        _say(snapshot.home.lastCare!.name, actor: snapshot.home.lastActor);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _message(Object error) {
    if (error is E2ENoKeyError) {
      return t(
        'Дом закрыт ключом связи. Откройте ключи и попробуйте ещё раз.',
        'The home needs your connection key. Unlock keys and try again.',
      );
    }
    if (error is PetNotEnoughCozy) {
      return t(
        'Пока мало очков уюта. Забота и ваши общие дела постепенно добавят ещё.',
        'Not enough cozy points yet. Care and shared activities will add more.',
      );
    }
    if (error is PetHomeBusy) {
      return t(
        'Дома сейчас перестановка. Попробуйте ещё раз.',
        'Someone is decorating. Please try again.',
      );
    }
    return t(
      'Не удалось связаться с домом. Попробуйте ещё раз.',
      'Could not reach your home. Please try again.',
    );
  }

  void _say(String event, {String? actor}) {
    if (!mounted || !_foreground) return;
    _bubbleTimer?.cancel();
    setState(
      () => _speech = _dialogue.next(
        event,
        english: _english,
        me: _address(actor ?? config.uid),
      ),
    );
    _bubbleTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) {
        setState(() {
          _speech = null;
          _action = null;
        });
      }
    });
  }

  Future<void> _change(
    void Function(PetHome) mutate, {
    String? event,
    PetCare? action,
  }) async {
    if (!_canAct) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Invalidate refreshes started before this action, so old GET responses
    // cannot replace an acknowledged purchase or newly chosen role.
    final generation = ++_generation;
    try {
      final result = await _repo.change(
        config.groupId,
        mutate,
        xp: config.sharedXp(),
      );
      if (!mounted || generation != _generation || !_current) return;
      setState(() {
        _home = result.home;
        _action = action;
        _animation++;
      });
      if (event != null) _say(event);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  void _poke() {
    if (!_canAct) return;
    setState(() {
      _action = PetCare.pet;
      _animation++;
    });
    _say('idle');
  }

  void _care(PetCare care) {
    final now = DateTime.now().millisecondsSinceEpoch;
    unawaited(
      _change(
        (h) => h.careFor(care, config.uid, now),
        event: care.name,
        action: care,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = _home;
    return Theme(
      data: _homeTheme,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: petCream,
          foregroundColor: petInk,
          title: Text(
            t('Наш дом', 'Our home'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: [
            IconButton(
              tooltip: t(
                'Выбрать, нарисовать или загрузить питомца',
                'Choose, draw or upload a pet',
              ),
              onPressed: config.openGallery,
              icon: const Icon(Icons.photo_library_outlined),
            ),
            IconButton(
              tooltip: t('Обращения питомца', 'Pet names for you'),
              onPressed: home == null ? null : _roles,
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: home == null
              ? Center(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => _refresh(greet: true),
                                child: Text(
                                  t('Попробовать снова', 'Try again'),
                                ),
                              ),
                            ],
                          ),
                        ),
                )
              : SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PetRoom(
                            home: home,
                            pet: config.pet,
                            speech: _speech,
                            action: _action,
                            animationKey: _animation,
                            onPet: _canAct ? _poke : null,
                            petLabel: t(
                              'Питомец. Поздороваться',
                              'Pet. Say hello',
                            ),
                            speechLabel: t('Питомец говорит', 'Pet says'),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final care in PetCare.values)
                                  _careButton(care),
                                _actionButton(
                                  'armchair',
                                  t('Обустроить', 'Furnish'),
                                  _canAct ? _furnish : null,
                                ),
                              ],
                            ),
                          ),
                          if (_busy)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: LinearProgressIndicator(minHeight: 2),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF8B4935),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 18,
                                  color: petInk,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    t(
                                      '${home.balance} очков уюта',
                                      '${home.balance} cozy points',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: t(
                                    'Откуда очки уюта',
                                    'About cozy points',
                                  ),
                                  onPressed: _aboutCredit,
                                  icon: const Icon(
                                    Icons.info_outline,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (home.lastCare != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Text(
                                '${_lastCareLabel(home.lastCare!)} · ${_address(home.lastActor)}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: petInk.withValues(alpha: .8),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                            child: Text(
                              config.readOnly
                                  ? t(
                                      'Дом сохранён в архиве связи.',
                                      'This connection’s home is archived.',
                                    )
                                  : t(
                                      'Заглядывайте, когда хочется. Дома всё хорошо.',
                                      'Drop by whenever you feel like it. All is well at home.',
                                    ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: petInk.withValues(alpha: .8),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  String _lastCareLabel(PetCare care) => switch (care) {
    PetCare.feed => t('Угощение', 'Treat'),
    PetCare.wash => t('Пенные процедуры', 'Bubble bath'),
    PetCare.play => t('Весёлая игра', 'Playtime'),
    PetCare.pet => t('Немного нежности', 'A little affection'),
  };
  Widget _careButton(PetCare care) {
    final (asset, label) = switch (care) {
      PetCare.feed => ('bowl', t('Кормить', 'Feed')),
      PetCare.wash => ('sponge', t('Помыть', 'Wash')),
      PetCare.play => ('ball', t('Играть', 'Play')),
      PetCare.pet => ('petting', t('Погладить', 'Stroke')),
    };
    return _actionButton(
      asset,
      label,
      _canAct ? () => care == PetCare.feed ? _feed() : _care(care) : null,
    );
  }

  Widget _actionButton(String asset, String label, VoidCallback? tap) =>
      SizedBox(
        width:
            MediaQuery.sizeOf(context).width >= 382 &&
                MediaQuery.textScalerOf(context).scale(13) < 18
            ? (MediaQuery.sizeOf(context).width.clamp(382, 620) - 64) / 5
            : 96,
        child: TextButton(
          onPressed: tap,
          style: TextButton.styleFrom(
            foregroundColor: petInk,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          ),
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFF6E6),
                ),
                child: Image.asset(
                  'assets/pet_home/$asset.webp',
                  excludeFromSemantics: true,
                ),
              ),
              const SizedBox(height: 4),
              if (MediaQuery.textScalerOf(context).scale(13) < 18)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(fontSize: 13),
                  ),
                )
              else
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                ),
            ],
          ),
        ),
      );

  void _feed() {
    showModalSheet<void>(
      context: context,
      backgroundColor: petCream,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('Чем угостим?', 'A little treat?'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'Любое угощение — просто радость. Обязательного рациона нет.',
                'Every treat is just for joy. No required diet.',
              ),
            ),
            const SizedBox(height: 12),
            for (final treat in [
              ('bowl', t('Хрустяшки', 'Crunchies')),
              ('strawberry', t('Ягодка', 'A berry')),
            ])
              ListTile(
                leading: Image.asset(
                  'assets/pet_home/${treat.$1}.webp',
                  width: 56,
                  height: 56,
                ),
                minTileHeight: 72,
                title: Text(treat.$2),
                trailing: const Icon(Icons.favorite_outline),
                onTap: () {
                  Navigator.pop(sheet);
                  _care(PetCare.feed);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _aboutCredit() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(t('Очки уюта', 'Cozy points')),
      content: Text(
        t(
          '40 очков — подарок на новоселье. За первое кормление, мытьё, игру и ласку — по 5. Следующие постоянные награды: 5, 20, 50 и 100 занятий каждого вида. Каждые 50 очков общего опыта добавляют ещё 5 очков уюта.\n\nДневной нормы нет. Очки и покупки не сгорают, уход бесплатный. Купленный предмет доступен всем в этой связи.',
          '40 points are a housewarming gift. First feed, wash, play and stroke each earn 5. More permanent milestones at 5, 20, 50 and 100 of each activity. Every 50 shared XP adds 5 cozy points.\n\nNo daily quota. Points and purchases never expire. Care is free. Purchased items belong to everyone in this connection.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(t('Понятно', 'Got it')),
        ),
      ],
    ),
  );

  void _furnish() {
    showModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: petCream,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .72,
          minChildSize: .4,
          maxChildSize: .95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Text(
                t('Обустроим дом', 'Make it home'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  '${_home!.balance} очков уюта · покупки общие',
                  '${_home!.balance} cozy points · shared purchases',
                ),
              ),
              const SizedBox(height: 12),
              for (final item in petItems) _furnitureTile(item, sheet, update),
            ],
          ),
        ),
      ),
    );
  }

  Widget _furnitureTile(PetItem item, BuildContext sheet, StateSetter update) {
    final home = _home!,
        owned = home.owned.contains(item.id),
        equipped = home.equipped[item.slot] == item.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: const Color(0xFFFFF8EB),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Image.asset(
                item.asset,
                width: 76,
                height: 76,
                excludeFromSemantics: true,
              ),
              SizedBox(
                width: 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label(_english),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      owned
                          ? t('Уже наше', 'Already ours')
                          : t(
                              '${item.price} очков уюта',
                              '${item.price} cozy points',
                            ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: !_canAct
                    ? null
                    : () async {
                        // Close first; saving/error state remains visible on the actual room.
                        Navigator.pop(sheet);
                        await _change((h) {
                          if (equipped) {
                            h.equipped.remove(item.slot);
                          } else {
                            h.furnish(item.id);
                          }
                        }, event: 'decorate');
                      },
                child: Text(
                  equipped
                      ? t('Убрать', 'Put away')
                      : owned
                      ? t('Поставить', 'Place')
                      : t('Купить', 'Buy'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _roles() async {
    final current = _home!.roles[config.uid] ?? const PetRole('name');
    var kind =
        !config.family && (current.kind == 'mom' || current.kind == 'dad')
        ? 'name'
        : current.kind;
    final text = TextEditingController(text: current.custom);
    final selected = await showDialog<PetRole>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          scrollable: true,
          title: Text(t('Как тебя называть?', 'What should I call you?')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                config.family
                    ? t(
                        'Можно выбрать семейное обращение или своё имя. Каждый выбирает за себя.',
                        'Choose a family role or your name. Everyone chooses their own.',
                      )
                    : t(
                        'Для вашей компании подойдут имена и прозвища.',
                        'Names and nicknames suit your group.',
                      ),
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: kind,
                onChanged: (value) {
                  if (!config.readOnly && value != null) {
                    update(() => kind = value);
                  }
                },
                child: Column(
                  children: [
                    for (final choice in [
                      if (config.family) 'mom',
                      if (config.family) 'dad',
                      'name',
                      'custom',
                    ])
                      RadioListTile<String>(
                        title: Text(switch (choice) {
                          'mom' => t('Мама', 'Mom'),
                          'dad' => t('Папа', 'Dad'),
                          'name' => t(
                            'Моё имя: ${config.names[config.uid] ?? ''}',
                            'My name: ${config.names[config.uid] ?? ''}',
                          ),
                          _ => t('Своё обращение', 'Custom name'),
                        }),
                        value: choice,
                        enabled: !config.readOnly,
                      ),
                  ],
                ),
              ),
              if (kind == 'custom')
                TextField(
                  controller: text,
                  maxLength: 40,
                  decoration: InputDecoration(
                    labelText: t('Обращение', 'Name'),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(t('Отмена', 'Cancel')),
            ),
            FilledButton(
              onPressed: config.readOnly
                  ? null
                  : () {
                      if (kind == 'custom' && text.text.trim().isEmpty) return;
                      Navigator.pop(dialog, PetRole(kind, text.text.trim()));
                    },
              child: Text(t('Сохранить', 'Save')),
            ),
          ],
        ),
      ),
    );
    // The route exit animation may still reference the text field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    text.dispose();
    if (selected != null && mounted) {
      await _change((h) => h.roles[config.uid] = selected, event: 'welcome');
    }
  }
}
