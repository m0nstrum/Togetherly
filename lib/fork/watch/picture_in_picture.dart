/// One Android PiP owner; prepare a video-only frame before entering the OS mode.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum ForkPipOutcome { entered, unsupported, failed }

class ForkPictureInPicture extends ChangeNotifier {
  ForkPictureInPicture({
    required this.available,
    required this.activate,
    required this.prepare,
  });
  final Future<bool> Function() available, activate;
  final Future<void> Function() prepare;
  static const _channel = MethodChannel('tethered/picture_in_picture');
  static final instance = _native();
  static ForkPictureInPicture _native() {
    final controller = ForkPictureInPicture(
      available: () async =>
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          (await _channel.invokeMethod<bool>('available') ?? false),
      activate: () async => await _channel.invokeMethod<bool>('enter') ?? false,
      prepare: () => WidgetsBinding.instance.endOfFrame,
    );
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'modeChanged') {
        controller.modeChanged(call.arguments == true);
      }
      if (call.method == 'closed') controller.closed();
    });
    return controller;
  }

  Object? owner;
  bool active = false, preparing = false;
  int closedSequence = 0, _revision = 0;
  bool _requesting = false;
  bool get busy => _requesting;
  bool get videoOnly => active || preparing;
  bool ownedBy(Object value) => identical(owner, value);

  Future<ForkPipOutcome> enter(
    Object value, {
    bool Function()? canEnter,
  }) async {
    if (_requesting) return ForkPipOutcome.failed;
    if (active) {
      return ownedBy(value) ? ForkPipOutcome.entered : ForkPipOutcome.failed;
    }
    _requesting = true;
    try {
      if (!await available()) return ForkPipOutcome.unsupported;
      if (active || canEnter?.call() == false) return ForkPipOutcome.failed;
      owner = value;
      preparing = true;
      notifyListeners();
      await prepare();
      if (!ownedBy(value) || !preparing || canEnter?.call() == false)
        return ForkPipOutcome.failed;
      final revision = _revision;
      final accepted = await activate();
      if (_revision == revision) active = accepted;
      return accepted ? ForkPipOutcome.entered : ForkPipOutcome.failed;
    } catch (_) {
      return ForkPipOutcome.failed;
    } finally {
      _requesting = false;
      preparing = false;
      notifyListeners();
    }
  }

  void modeChanged(bool value) {
    _revision++;
    active = value;
    preparing = false;
    notifyListeners();
  }

  void closed() {
    _revision++;
    active = false;
    preparing = false;
    closedSequence++;
    notifyListeners();
  }

  void release(Object value) {
    if (!ownedBy(value)) return;
    _revision++;
    owner = null;
    // Retain the OS mode: a late route removal must stay opaque in PiP.
    preparing = false;
    notifyListeners();
  }

  static Future<void> settings() => _channel.invokeMethod<void>('settings');
}

/// Hide global chrome without reparenting the Navigator or its platform views.
class ForkPipHideChrome extends StatelessWidget {
  const ForkPipHideChrome({super.key, required this.child, this.controller});
  final Widget child;
  final ForkPictureInPicture? controller;
  @override
  Widget build(BuildContext context) {
    final state = controller ?? ForkPictureInPicture.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (_, child) => Offstage(offstage: state.videoOnly, child: child),
      child: child,
    );
  }
}

/// A route removed while the OS transition is pending may never expose another
/// screen in the tiny window. Keep the Navigator mounted behind an opaque cover.
class ForkPipOrphanGuard extends StatelessWidget {
  const ForkPipOrphanGuard({super.key, required this.child, this.controller});
  final Widget child;
  final ForkPictureInPicture? controller;
  @override
  Widget build(BuildContext context) {
    final state = controller ?? ForkPictureInPicture.instance;
    return ListenableBuilder(
      listenable: state,
      child: child,
      builder: (_, child) {
        final orphan = state.active && state.owner == null;
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(offstage: orphan, child: child),
            if (orphan) const ColoredBox(color: Color(0xFF000000)),
          ],
        );
      },
    );
  }
}
