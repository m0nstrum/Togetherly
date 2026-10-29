/// Preserve the HTTP outcome even when legacy service methods catch errors
/// and return false. A zone keeps parallel outbox lanes independent.
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

class ForkOutboxAttempt {
  static final _zoneKey = Object();
  int? _status;

  bool get permanent =>
      _status != null &&
      _status! >= 400 &&
      _status! < 500 &&
      _status != 408 &&
      _status != 429;

  /// HTTP-код последнего ответа (null — сети не было или таймаут).
  int? get status => _status;

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});

  void transient() => _status = null;
  void error(Object error) =>
      _status = error is ClientException ? error.statusCode : null;
}

class ForkOutboxHttpClient extends http.BaseClient {
  ForkOutboxHttpClient(this.inner);
  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final attempt =
        Zone.current[ForkOutboxAttempt._zoneKey] as ForkOutboxAttempt?;
    try {
      final response = await inner.send(request);
      attempt?._status = response.statusCode;
      return response;
    } catch (_) {
      attempt?.transient();
      rethrow;
    }
  }

  @override
  void close() => inner.close();
}
