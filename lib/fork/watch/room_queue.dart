import 'package:flutter/material.dart';
import '../../dict_strings.dart' show ruEn;
import 'room_live.dart';

class ForkRoomQueueScreen extends StatelessWidget {
  const ForkRoomQueueScreen({
    super.key,
    required this.live,
    required this.onAdd,
    required this.onPlay,
    required this.onRemove,
    required this.onNext,
  });
  final ForkRoomLive live;
  final VoidCallback onAdd, onNext;
  final ValueChanged<String> onPlay, onRemove;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: live,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(ruEn('Очередь видео', 'Video queue'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            ruEn('Сейчас играет', 'Now playing'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            live.hasVideo
                ? (live.title.isNotEmpty
                      ? live.title
                      : live.url.isNotEmpty
                      ? live.url
                      : live.label)
                : ruEn('Видео ещё не выбрано', 'No video selected'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: live.offline ? null : onAdd,
                icon: const Icon(Icons.add_rounded),
                label: Text(ruEn('Добавить видео', 'Add video')),
              ),
              OutlinedButton.icon(
                onPressed: live.offline || live.queue.isEmpty ? null : onNext,
                icon: const Icon(Icons.skip_next_rounded),
                label: Text(ruEn('Следующее', 'Next')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            ruEn(
              'Очередь общая и живёт, пока хотя бы один из вас в комнате. До 20 видео.',
              'The shared queue lasts while at least one of you stays in the room. Up to 20 videos.',
            ),
          ),
          if (live.offline)
            Text(
              ruEn(
                'Нет связи — изменения недоступны',
                'Offline — changes are unavailable',
              ),
            ),
          if (live.queue.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(ruEn('Очередь пуста', 'Queue is empty')),
            ),
          for (var i = 0; i < live.queue.length; i++)
            Card(
              child: ListTile(
                leading: Text('${i + 1}'),
                title: Text(
                  live.queue[i].url,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: live.offline ? null : () => onPlay(live.queue[i].id),
                trailing: IconButton(
                  tooltip: ruEn('Убрать из очереди', 'Remove from queue'),
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: live.offline
                      ? null
                      : () => onRemove(live.queue[i].id),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
