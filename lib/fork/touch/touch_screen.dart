import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../dict_strings.dart' show ruEn;
import '../../services/centrifugo_service.dart';
import '../../services/pocketbase_service.dart';
import '../../services/presence_service.dart';
import '../e2e/e2e_service.dart' show PairE2EStatus;
import '../e2e/fork_e2e.dart';
import '../e2e/room_chat.dart' show RoomTransport;
import '../ui/feedback.dart';
import 'touch_session.dart';

class _Transport implements RoomTransport {
  _Transport(this.channel);
  final String channel;
  @override
  Future<void> send(Map<String, dynamic> msg) =>
      CentrifugoService.instance.publish(channel, msg, requireDelivery: true);
  @override
  Future<Future<void> Function()> listen(
    void Function(Map<String, dynamic>) handler,
  ) => CentrifugoService.instance.subscribeRaw(channel, handler);
}

class ForkTouchScreen extends StatefulWidget {
  const ForkTouchScreen({
    super.key,
    required this.groupId,
    required this.myUid,
    required this.partnerUid,
    this.session,
  });
  final ForkTouchSession? session;
  final String groupId, myUid, partnerUid;
  static Future<void> open(
    BuildContext context, {
    required String groupId,
    required String myUid,
    required String partnerUid,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ForkTouchScreen(
        groupId: groupId,
        myUid: myUid,
        partnerUid: partnerUid,
      ),
    ),
  );
  @override
  State<ForkTouchScreen> createState() => _ForkTouchScreenState();
}

class _ForkTouchScreenState extends State<ForkTouchScreen>
    with WidgetsBindingObserver {
  ForkTouchSession? _session;
  bool _loading = true, _inviting = false, _invited = false, _front = true;
  int? _pointer;
  bool _member = false, _starting = false;

  /// Не дошли до сервера (пара, ключи) — это «нет связи», а не «нет ключей»:
  /// раньше любой сбой старта звал проверить шифрование (B11).
  bool _unreachable = false;
  Future<void> Function()? _groupSub;
  bool _allowed() {
    final status = ForkE2E.service.value?.status.value[widget.groupId];
    return _member &&
        _front &&
        PocketBaseService().userId == widget.myUid &&
        (status == PairE2EStatus.verified ||
            status == PairE2EStatus.unverified);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    _member = false;
    setState(() {
      _loading = true;
      _unreachable = false;
    });
    try {
      if (widget.session != null) {
        _session = widget.session!;
        _session!.addListener(_changed);
        await _session!.start();
        return;
      }
      final pb = PocketBaseService().pb;
      final group = await pb.collection('groups').getOne(widget.groupId);
      final members = group.data['members'];
      _member =
          members is List &&
          members.contains(widget.myUid) &&
          members.contains(widget.partnerUid);
      if (!_member) throw StateError('Not current pair members');
      await _groupSub?.call();
      final unsub = await CentrifugoService.instance.subscribeDelta(
        'pair:${widget.groupId}',
        'groups',
        (event) {
          if (event.record?.id != widget.groupId) return;
          final current = event.record?.data['members'];
          _member =
              event.action != 'delete' &&
              current is List &&
              current.contains(widget.myUid) &&
              current.contains(widget.partnerUid);
          if (!_member) _session?.suspend();
        },
      );
      if (!mounted) {
        await unsub();
        return;
      }
      _groupSub = unsub;
      await ForkE2E.sync(widget.groupId);
      final codec = await ForkE2E.codec();
      if (!mounted) return;
      if (codec == null || codec.crypto == null || !_allowed()) {
        throw StateError('Key unavailable');
      }
      final session = ForkTouchSession(
        group: widget.groupId,
        me: widget.myUid,
        partner: widget.partnerUid,
        codec: codec,
        transport: _Transport('pair:${widget.groupId}'),
        allowed: _allowed,
        vibrate: HapticFeedback.vibrate,
        linkUp: () =>
            CentrifugoService.instance.linkUp('pair:${widget.groupId}'),
        onPartnerSeen: () => PresenceService().noteActivity(widget.partnerUid),
      );
      _session?.removeListener(_changed);
      _session?.dispose();
      _session = session;
      session.addListener(_changed);
      await session.start();
    } on StateError {
      // тихо: не пара или нет ключа — экран скажет про ключи; открытого
      // запасного пути нет
    } catch (_) {
      // Сеть, сервер, таймаут: повторить, а не чинить шифрование.
      _unreachable = true;
    } finally {
      _starting = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _pointer = null;
      _session?.suspend();
    }
    _front = state == AppLifecycleState.resumed;
    if (_front && widget.session == null) unawaited(_start());
    if (mounted) setState(() {});
  }

  Future<void> _invite() async {
    setState(() => _inviting = true);
    try {
      await PocketBaseService().pb.send(
        '/api/fork/ring',
        method: 'POST',
        body: {'group_id': widget.groupId, 'kind': 'touch'},
      );
      if (mounted) setState(() => _invited = true);
    } catch (e) {
      if (mounted) {
        ForkNotice.failure(context, ForkFailure.of(e), retry: _invite);
      }
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.removeListener(_changed);
    _session?.dispose();
    final unsub = _groupSub;
    if (unsub != null) unawaited(unsub().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final cs = Theme.of(context).colorScheme;
    final size = math.max(
      80.0,
      math.min(
        MediaQuery.sizeOf(context).width - 32,
        MediaQuery.sizeOf(context).height * .45,
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(ruEn('Прикосновение', 'Touch'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                ruEn(
                  'Коснитесь экрана и найдите палец партнёра. Когда точки совпадут, телефон завибрирует.',
                  'Touch the screen and find your partner’s finger. When your points meet, your phone vibrates.',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (_loading)
                const CircularProgressIndicator()
              else if (s == null || !s.canTouch) ...[
                Text(
                  _unreachable
                      ? ruEn(
                          'Нет связи с сервером. Проверьте интернет и повторите.',
                          'Can’t reach the server. Check your connection and try again.',
                        )
                      : ruEn(
                          'Нужны действующие ключи пары. Проверьте шифрование и повторите.',
                          'Current pair keys are required. Check encryption and try again.',
                        ),
                ),
                TextButton(
                  onPressed: _start,
                  child: Text(ruEn('Повторить', 'Retry')),
                ),
              ] else ...[
                Text(
                  key: const ValueKey('fork-touch-status'),
                  // «Нет связи» — только когда нет СВОЕЙ связи. Партнёр не на
                  // экране — отдельное состояние с приглашением (B11).
                  s.offline
                      ? ruEn(
                          'Нет связи — переподключаемся…',
                          'Offline — reconnecting…',
                        )
                      : s.matched
                      ? ruEn('Вы рядом', 'You are together')
                      : s.peer != null
                      ? ruEn(
                          'Найдите точку партнёра',
                          'Find your partner’s point',
                        )
                      : s.partnerHere
                      ? ruEn(
                          'Партнёр здесь — коснитесь экрана',
                          'Your partner is here — touch the screen',
                        )
                      : ruEn(
                          'Партнёра нет на этом экране — позовите его',
                          'Your partner isn’t on this screen — invite them',
                        ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Semantics(
                    label: ruEn('Поле прикосновения', 'Touch area'),
                    child: Listener(
                      onPointerDown: (event) {
                        if (_pointer != null) return;
                        _pointer = event.pointer;
                        s.point(
                          Offset(
                            event.localPosition.dx / size,
                            event.localPosition.dy / size,
                          ),
                        );
                      },
                      onPointerMove: (event) {
                        if (_pointer == event.pointer) {
                          s.point(
                            Offset(
                              event.localPosition.dx / size,
                              event.localPosition.dy / size,
                            ),
                          );
                        }
                      },
                      onPointerUp: (event) {
                        if (_pointer == event.pointer) {
                          _pointer = null;
                          s.point(null);
                        }
                      },
                      onPointerCancel: (event) {
                        if (_pointer == event.pointer) {
                          _pointer = null;
                          s.point(null);
                        }
                      },
                      child: GestureDetector(
                        onPanStart: (_) {},
                        onPanUpdate: (_) {},
                        onPanEnd: (_) {},
                        child: Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            color: s.matched
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Stack(
                            children: [
                              if (s.peer != null)
                                _dot(s.peer!, size, cs.tertiary),
                              if (s.mine != null)
                                _dot(s.mine!, size, cs.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                ruEn(
                  '🔒 Только между вами, без истории',
                  '🔒 Between the two of you, without history',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _inviting ? null : _invite,
                icon: const Icon(Icons.waving_hand_rounded),
                label: Text(
                  _inviting
                      ? ruEn('Отправляем…', 'Sending…')
                      : _invited
                      ? ruEn('Позвать ещё раз', 'Invite again')
                      : ruEn('Позвать партнёра', 'Invite your partner'),
                ),
              ),
              if (_invited)
                Text(ruEn('Приглашение отправлено', 'Invitation sent')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Offset point, double size, Color color) => Positioned(
    left: (point.dx * (size - 32)),
    top: (point.dy * (size - 32)),
    child: IgnorePointer(
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    ),
  );
}
