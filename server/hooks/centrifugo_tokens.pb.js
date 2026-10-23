/// Токены подключения к Centrifugo.
///
/// Рассылка изменений уехала в саму сборку PocketBase 14.08.2026 (нативный Go
/// вместо goja — четверть его процессора уходила на JavaScript). А выдача
/// токенов осталась здесь: без этих двух маршрутов приложение не может ни
/// подключиться к Centrifugo, ни подписаться на канал пары — живые обновления
/// умирают молча. Отключая хук целиком, я это и сломал; файл разделён.

routerAdd("POST", "/api/centrifugo/connection-token", (e) => {
  const secret = $os.getenv("CENTRIFUGO_TOKEN_HMAC");
  if (!secret) return e.json(500, { error: "not configured" });
  return e.json(200, { token: $security.createJWT({ sub: e.auth.id }, secret, 120) });
}, $apis.requireAuth());

// Доступ к конкретному приватному каналу (проверка членства).
routerAdd("POST", "/api/centrifugo/subscription-token", (e) => {
  const uid = e.auth.id;
  const body = e.requestInfo().body || {};
  const channel = String(body.channel || "");
  // Signal namespaces use the same membership check, never the server namespace.
  const membershipChannel = channel.indexOf("signal:") === 0 ? "pair:" + channel.substring(7)
    : channel.indexOf("locsignal:") === 0 ? "loc:" + channel.substring(10) : channel;
  if (!channel) return e.json(400, { error: "channel required" });

  let allowed = false;
  if (membershipChannel.indexOf("pair:") === 0) {
    const gid = membershipChannel.substring(5);
    try {
      const rows = $app.findRecordsByFilter("groups", "id = {:g} && members ~ {:u} && disbanded = false", "", 1, 0, { g: gid, u: uid });
      allowed = !!(rows && rows.length > 0);
    } catch (_) {}
  } else if (membershipChannel.indexOf("user:") === 0) {
    const target = membershipChannel.substring(5);
    if (target === uid) { allowed = true; }
    else {
      try {
        const rows = $app.findRecordsByFilter("groups", "members ~ {:a} && members ~ {:b} && disbanded = false", "", 1, 0, { a: uid, b: target });
        allowed = !!(rows && rows.length > 0);
      } catch (_) {}
    }
  } else if (membershipChannel.indexOf("loc:") === 0) {
    // Геопозиция только настоящей действующей пары.
    const parts = membershipChannel.substring(4).split("_");
    if (parts.length === 3 && parts[0] === "pair" && (parts[1] === uid || parts[2] === uid)) {
      try {
        const rows = $app.findRecordsByFilter("groups", "members ~ {:a} && members ~ {:b} && disbanded = false", "", 1, 0, {a: parts[1], b: parts[2]});
        allowed = rows.length > 0;
      } catch (_) {}
    }
  } else if (membershipChannel.indexOf("watch:") === 0) {
    // Комната совместного просмотра. Её код — HMAC от group_id (см. watch.pb.js),
    // поэтому просто проверяем, что код совпал с одной из групп человека.
    const room = membershipChannel.substring(6);
    const secret = $os.getenv("CENTRIFUGO_TOKEN_HMAC");
    if (secret) {
      const abc = "abcdefghjkmnpqrstuvwxyz23456789";
      try {
        const rows = $app.findRecordsByFilter("groups", "members ~ {:u} && disbanded = false", "", 20, 0, { u: uid });
        for (let i = 0; i < rows.length; i++) {
          const digest = $security.hs256(rows[i].id, secret);
          let code = "";
          for (let j = 0; j < 8; j++) code += abc[digest.charCodeAt(j) % abc.length];
          if (code === room) { allowed = true; break; }
        }
      } catch (_) {}
    }
  } else if (membershipChannel.indexOf("draw:") === 0) {
    // draw:<groupId> — эфемерные live-штрихи рисования (доступ члену группы)
    const gid = membershipChannel.substring(5);
    try {
      const rows = $app.findRecordsByFilter("groups", "id = {:g} && members ~ {:u} && disbanded = false", "", 1, 0, { g: gid, u: uid });
      allowed = !!(rows && rows.length > 0);
    } catch (_) {}
  }
  if (!allowed) return e.json(403, { error: "forbidden" });

  const secret = $os.getenv("CENTRIFUGO_TOKEN_HMAC");
  if (!secret) return e.json(500, { error: "not configured" });
  const claims = { sub: uid, channel: channel };
  // Экран комнаты держит своё подключение к каналу ради голоса: WebRTC поднимает
  // приложение, а зов партнёра ходит там же. Зрителем оно не является, и без
  // метки страница считала его вторым человеком — «смотрят: 2» у зашедшего
  // одного (жалоба 20.08.2026). `info` уезжает в chan_info присутствия, счёт
  // ведёт countViewers в room.js. Метка серверная, поэтому чинит и выпущенные
  // сборки: им хватит обновить пропуск подписки.
  if (membershipChannel.indexOf("watch:") === 0) claims.info = { app: 1 };
  return e.json(200, { token: $security.createJWT(claims, secret, 120) });
}, $apis.requireAuth());
