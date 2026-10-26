import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only the caller's ordinary reminder is eligible. Danger never uses this.
class ForkE2EBannerDefer extends StatefulWidget {
  const ForkE2EBannerDefer({
    super.key,
    required this.scope,
    required this.builder,
    this.now,
  });
  final String scope;
  final Widget Function(VoidCallback later) builder;
  final DateTime Function()? now;

  @override
  State<ForkE2EBannerDefer> createState() => _ForkE2EBannerDeferState();
}

class _ForkE2EBannerDeferState extends State<ForkE2EBannerDefer> {
  SharedPreferences? _prefs;
  int _until = 0;
  String get _key => 'fork.e2e.reminder.${widget.scope}';
  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ForkE2EBannerDefer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scope != oldWidget.scope) {
      _until = 0;
      _load();
    }
  }

  Future<void> _load() async {
    final key = _key;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted && key == _key) {
        setState(() {
          _prefs = prefs;
          final saved = prefs.getInt(key) ?? 0;
          if (saved > _until) {
            _until = saved;
          }
        });
      }
    } catch (_) {
      /* A failed preference read must not hide a reminder. */
    }
  }

  Future<void> _later() async {
    final key = _key;
    final until = _now.add(const Duration(days: 7)).millisecondsSinceEpoch;
    setState(() => _until = until);
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setInt(key, until);
    } catch (_) {
      /* In-memory only. */
    }
  }

  @override
  Widget build(BuildContext context) => _until > _now.millisecondsSinceEpoch
      ? const SizedBox.shrink()
      : widget.builder(_later);
}
