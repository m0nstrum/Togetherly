/// Причина отказа заливки — человеку (D4/D5): мост от `UploadFailure`
/// сервиса заливки к общим кирпичикам `ForkNotice`.
library;

import 'package:flutter/material.dart';

import '../../models/upload_failure.dart';
import 'feedback.dart';

ForkFailure forkFailureOfUpload(UploadFailure? failure) => switch (failure) {
  UploadFailure.network => ForkFailure.network,
  UploadFailure.sessionExpired => ForkFailure.session,
  UploadFailure.tooLarge => ForkFailure.tooLarge,
  UploadFailure.emptyFile || UploadFailure.other || null => ForkFailure.unknown,
};

/// «[what]. Причина.» с повтором, если он осмысленный.
void showUploadFailure(
  BuildContext context,
  UploadFailure? failure, {
  required String what,
  VoidCallback? retry,
}) => ForkNotice.failure(
  context,
  forkFailureOfUpload(failure),
  what: what,
  retry: retry,
);
