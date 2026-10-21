import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/memories/photo_batch.dart';
import 'package:love_app/models/upload_failure.dart';

void main() {
  test('частичный отказ: считает залитое и сохраняет порядок', () async {
    final batch = await PhotoBatch.upload(['a', 'b', 'c'], (p, i) async {
      return p == 'b'
          ? const UploadOutcome.failed(UploadFailure.network)
          : UploadOutcome.ok('pb://$p');
    });
    expect(batch.complete, isFalse);
    expect(batch.uploaded, 2);
    expect(batch.total, 3);
    expect(batch.failure, UploadFailure.network);
    expect(batch.urls, ['pb://a', 'pb://c']);
  });

  test('повтор заливает только упавшее и сохраняет места', () async {
    final calls = <String>[];
    var bFails = true;
    Future<UploadOutcome> up(String p, int i) async {
      calls.add(p);
      if (p == 'b' && bFails) {
        return const UploadOutcome.failed(UploadFailure.other);
      }
      return UploadOutcome.ok('pb://$p');
    }

    final first = await PhotoBatch.upload(['a', 'b', 'c'], up);
    bFails = false;
    calls.clear();
    final second = await first.retryFailed(up);
    expect(calls, ['b']);
    expect(second.complete, isTrue);
    expect(second.urls, ['pb://a', 'pb://b', 'pb://c']);
  });
}
