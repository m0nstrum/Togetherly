/// Страж пары (своя версия модуля апстрима pocketbase/pb_hooks/groups_guard.pb.js).
///
/// Апстрим: через API участника состав можно только сократить, а служебные
/// поля пары с пустым местом пишет только сервер.
///
/// Форк (M3): роуты /api/group/* уже действуют от имени вошедшего, но тот же
/// PATCH /api/collections/groups шёл мимо них. Партнёр мог выкинуть тебя из
/// пары и переписать твоё имя, аватар, настроение: шифр значения привязан к
/// `поле/uid`, а ключ пары у обоих общий, так что подделка открывалась бы как
/// настоящая. Поэтому:
///   • из `members` можно убрать только себя;
///   • в словарях `member_*` можно менять только свой ключ — чужие значения
///     обязаны совпасть с сохранёнными байт в байт (уже запечатанные значения
///     клиент пересылает как есть).
///
/// ВАЖНО (PB JSVM): обработчик исполняется в изолированном пуле и НЕ видит
/// функций уровня файла — разбор инлайнится внутрь.

onRecordUpdateRequest((e) => {
  let isSuper = false;
  try {
    isSuper = !!(e.auth && e.auth.collection() && e.auth.collection().name === "_superusers");
  } catch (_) {
    isSuper = false;
  }

  if (!isSuper) {
    const body = (e.requestInfo().body || {});
    // Значение json-поля из тела: строка, байты или уже объект.
    const decode = (raw) => {
      if (raw === null || raw === undefined) return null;
      if (typeof raw === "string") {
        try { return JSON.parse(raw || "null"); } catch (_) { return undefined; }
      }
      if (Array.isArray(raw) && raw.length > 0 && typeof raw[0] === "number") {
        let s = "";
        for (let i = 0; i < raw.length; i++) s += String.fromCharCode(raw[i]);
        try { return JSON.parse(s || "null"); } catch (_) { return undefined; }
      }
      return raw;
    };
    let saved = null;
    try { saved = $app.findRecordById("groups", e.record.id); } catch (_) { saved = null; }
    const stored = (k, fb) => {
      if (!saved) return fb;
      try { const v = JSON.parse(saved.getString(k) || "null"); return v == null ? fb : v; }
      catch (_) { return fb; }
    };
    const me = e.auth ? e.auth.id : "";

    if ("members" in body) {
      const next = decode(body.members);
      if (!Array.isArray(next)) {
        throw new ForbiddenError("members must be a list");
      }
      const current = stored("members", []);
      for (let i = 0; i < next.length; i++) {
        if (current.indexOf(String(next[i])) === -1) {
          throw new ForbiddenError("cannot add members directly");
        }
      }
      // fork (M3): уйти можно только самому.
      for (let i = 0; i < current.length; i++) {
        const m = String(current[i]);
        if (m !== me && next.map(String).indexOf(m) === -1) {
          throw new ForbiddenError("cannot remove another member");
        }
      }
    }

    // fork (M3): в словарях участников — только свой ключ.
    const maps = ["member_names", "member_avatars", "member_cards", "member_moods",
      "member_ailments", "member_birthdays"];
    for (let i = 0; i < maps.length; i++) {
      const field = maps[i];
      if (!(field in body)) continue;
      let next = decode(body[field]);
      if (next === null) next = {};
      if (typeof next !== "object" || Array.isArray(next)) {
        throw new ForbiddenError(field + " must be an object");
      }
      const current = stored(field, {});
      const keys = {};
      Object.keys(current).forEach((k) => { keys[k] = true; });
      Object.keys(next).forEach((k) => { keys[k] = true; });
      Object.keys(keys).forEach((k) => {
        if (k === me) return;
        if (JSON.stringify(current[k]) !== JSON.stringify(next[k])) {
          throw new ForbiddenError("cannot change another member's " + field);
        }
      });
    }

    const locked = ["claim_token", "claim_uid", "claim_name", "claim_at", "waiting_mode"];
    for (let i = 0; i < locked.length; i++) {
      if (locked[i] in body) {
        throw new ForbiddenError("read-only pairing field: " + locked[i]);
      }
    }
  }

  e.next();
}, "groups");
