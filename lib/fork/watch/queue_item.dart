import 'room_picker.dart' show forkRoomPlayable;

class ForkQueuedVideo {
  const ForkQueuedVideo(this.id, this.url);
  final String id, url;
  static ForkQueuedVideo? parse(Object? value) {
    if (value is! Map) return null;
    final id = value['id'], url = value['url'];
    if (id is! String ||
        !RegExp(r'^[a-z0-9]{15}:[a-f0-9]{16}$').hasMatch(id) ||
        url is! String ||
        url.length > 2048 ||
        !forkRoomPlayable(url))
      return null;
    return ForkQueuedVideo(id, url);
  }
}
