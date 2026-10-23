import 'package:flutter/foundation.dart';

// Each background isolate has its own Flutter globals. Call before plugin init.
void configureForkLogging({bool release = kReleaseMode}) {
  if (release) debugPrint = _discard;
}

void _discard(String? message, {int? wrapWidth}) {}
