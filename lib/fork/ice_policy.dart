/// Голос в «Смотрим вместе» только через свой coturn (deploy/README.md, «Порты»).
///
/// Оба телефона берут лишь relay-кандидаты: разговор идёт через порт 3478
/// сервера, диапазон ретранслятора наружу не открывается (два relay на одной
/// машине говорят друг с другом локально), а партнёры не видят IP друг друга.
/// Звук и так зашифрован DTLS-SRTP между телефонами — TURN его не читает.
library;

/// Настройки `createPeerConnection` для списка ICE-серверов от сервера.
/// Без TURN в списке — как у апстрима: прямое соединение.
Map<String, dynamic> forkPeerConfig(List<Map<String, dynamic>> ice) {
  final turn = ice.any((s) {
    final urls = s['urls'];
    final list = urls is List ? urls : [urls];
    return list.any(
      (u) => '$u'.startsWith('turn:') || '$u'.startsWith('turns:'),
    );
  });
  return {
    'iceServers': ice,
    'sdpSemantics': 'unified-plan',
    if (turn) 'iceTransportPolicy': 'relay',
  };
}
