import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/fork/e2e/pb_backend.dart';

void main() {
  test('handshake query excludes expired SAS and old invite proofs', () async {
    late String filter;
    final pb = PocketBase(
      'https://example.test',
      httpClientFactory: () => MockClient((request) async {
        filter = request.url.queryParameters['filter']!;
        return http.Response(
          jsonEncode({
            'page': 1,
            'perPage': 500,
            'totalItems': 0,
            'totalPages': 0,
            'items': [],
          }),
          200,
        );
      }),
    );
    final before = DateTime.now().toUtc();
    expect(await PbE2EBackend(pb).handshakes('pair'), isEmpty);
    expect(filter, contains("group_id = 'pair'"));
    expect(filter, contains('kind = "invite_proof"'));
    expect(filter, contains('kind != "invite_proof"'));
    final dates = RegExp(
      r"created >= '([^']+)'",
    ).allMatches(filter).map((m) => DateTime.parse(m[1]!)).toList();
    expect(dates, hasLength(2));
    expect(before.difference(dates[0]).inDays, 29);
    expect(before.difference(dates[1]).inMinutes, 9);
  });
}
