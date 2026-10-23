import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/ui/feedback.dart';
import 'package:love_app/services/coloring_upload_queue.dart';

void main() {
  test('failed coloring persists a reason and no raw exception', () {
    const item = ColoringUpload(
      id: 'id',
      title: 'title',
      status: ColoringUploadStatus.failed,
      failure: ForkFailure.network,
    );
    final restored = ColoringUpload.fromJson(item.toJson());
    expect(restored.failure, ForkFailure.network);
    expect(restored.error, ForkFailure.network.text);
    expect(item.toJson()['error'], '');
    expect(
      restored.copyWith(status: ColoringUploadStatus.processing).failure,
      isNull,
    );
  });
  test(
    'old stored exceptions are hidden while ordinary validation reasons survive',
    () {
      final data = {
        'id': 'id',
        'title': 'title',
        'status': 'failed',
        'error': 'ClientException: https://private.invalid',
      };
      expect(ColoringUpload.fromJson(data).error, ForkFailure.unknown.text);
      data['error'] = 'Линии не замкнуты';
      expect(ColoringUpload.fromJson(data).error, 'Линии не замкнуты');
    },
  );
}
