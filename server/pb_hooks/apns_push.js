/// Рассылка пушей для хуков апстрима — версия форка (кладётся поверх
/// server/pb_hooks/apns_push.js скриптом scripts/sync-hooks.sh).
///
/// API тот же: notifyGroup, sendTo, isOnline, wakeUp, wakeGroup — хуки
/// апстрима (coins) не меняются; зовы порисовать и в ленту — на Go (handler.Calls). Правила «кому не
/// слать» тоже его: не автору, не тому, кто на связи (если не force), не
/// тому, кто выключил этот вид в настройках.
///
/// Транспорт другой. У апстрима — релеи APNs и FCM; в форке нет ни того, ни
/// другого (решение 2): уведомление уходит в канал `user:<uid>` Centrifugo
/// через внутренний API сервера, а телефон рисует его сам — из приложения или
/// из фонового сервиса, который держит сокет (lib/fork/push_relay.dart).
///
/// Тихие пуши «обнови виджеты» (wakeUp) не нужны: тот же фоновый сервис
/// слушает widget_data и обновляет виджеты сразу.

const NOTIFY = "http://127.0.0.1:8120/internal/notify";
const ONLINE_WINDOW_MS = 25 * 1000;

const NOTIF_FIELD = {
  chat: "notif_chat",
  mood: "notif_mood",
  memory: "notif_new_memory",
  miss: "notif_miss_you",
  comment: "notif_comments",
  draw: "notif_draw",
};

function membersOf(group) {
  try { return JSON.parse(group.getString("members") || "[]") || []; }
  catch (_) { return []; }
}

function isOnline(uid) {
  try {
    const p = $app.findFirstRecordByFilter(
      "user_presence", "user_uid = {:u}", { u: uid });
    let ms = Number(p.get("seen_at"));
    if (!isFinite(ms) || ms <= 0) {
      const seen = p.getString("updated") || "";
      if (!seen) return false;
      ms = new Date(String(seen).replace(" ", "T")).getTime();
    }
    if (!ms || !isFinite(ms)) return false;
    return (Date.now() - ms) < ONLINE_WINDOW_MS;
  } catch (_) {
    return false;
  }
}

function sendTo(uid, title, body, thread, opts) {
  let user;
  try { user = $app.findRecordById("users", uid); } catch (_) { return; }
  if (!(opts && opts.force) && isOnline(uid)) return;
  const field = NOTIF_FIELD[thread];
  if (field) {
    const raw = user.get(field);
    if (raw === false || raw === 0) return;
  }
  const data = {};
  if (opts && opts.data) {
    for (const k in opts.data) data[k] = String(opts.data[k]);
  }
  try {
    const res = $http.send({
      url: NOTIFY,
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ uid: uid, thread: thread, title: title, body: body, data: data }),
      timeout: 5,
    });
    if (res.statusCode !== 200) {
      $app.logger().warn("notify: не доставлено", "uid", uid, "status", res.statusCode);
    }
  } catch (e) {
    $app.logger().warn("notify: сервер не ответил", "err", String(e));
  }
}

function notifyGroup(groupId, authorUid, title, body, thread, opts) {
  if (!groupId) return;
  let group;
  try { group = $app.findRecordById("groups", groupId); } catch (_) { return; }
  if (group.get("disbanded")) return;
  const members = membersOf(group);
  for (let i = 0; i < members.length; i++) {
    const uid = String(members[i] || "");
    if (!uid || uid === authorUid) continue;
    sendTo(uid, title, body, thread, opts);
  }
}

function wakeUp() {}
function wakeGroup() {}

module.exports = {
  notifyGroup: notifyGroup,
  sendTo: sendTo,
  isOnline: isOnline,
  wakeUp: wakeUp,
  wakeGroup: wakeGroup,
};
