# ChillZone Fork Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Превратить форк Olympus 1.5.1 в аддон ChillZone для гильдий «Чиллзон» и «Чиллзон Навсегда» (WoW: Forever, Альянс), сохранив возможность выборочно переносить исправления оригинала.

**Architecture:** Механический ребрендинг одним скриптом (`scripts/rebrand.py`), который потом же фильтрует патчи оригинала (`scripts/port-upstream.sh`). Логические места (членство, люди, ключ, тексты про Asmon) правятся руками отдельными коммитами. Тесты оригинала продолжают работать на «тестовой личности» (`tests/fixtures/identity.lua`): выдуманные гильдии и люди Olympus подставляются только в тестах, а релиз несёт личность ChillZone.

**Tech Stack:** Lua 5.1 (WoW: Forever, LuaJIT в тестах), Bash, Python 3 (+ Pillow для логотипа, cryptography уже стоит), git.

**Spec:** `docs/superpowers/specs/2026-11-06-chillzone-fork-design.md`

## Global Constraints

- Бренд везде латиницей: `ChillZone` / `chillzone` / `CHILLZONE`; участник — `ChillZoner(s)`.
- Слэш-команды: `/chillzone`, `/cz` (главная), `/cza` (арена), `/czarmy`, `/czn` (общий канал, было `/ol`), `/czc` (капитаны, было `/olc`), `/czl` (лорды, было `/oll`).
- Префикс аддон-сообщений `CHILLZONE`; каналы `ChillZoneNet` / `ChillZoneNetH`.
- Гильдии релиза: главная `Чиллзон` (`ns.KING_GUILD.Alliance`), встроенная `Чиллзон Навсегда` (`ns.APPROVED_BUILTIN.Alliance`). Названия хранятся ровно как в игре; сравнение — через `ns.Fold`, никогда через `:lower()` с литералом в нижнем регистре.
- Релиз — только Альянс; Орда без главной гильдии.
- В коде релиза нет имён людей: `KING_CHARACTER = {}`, `KING_NAME = nil`, `TREASURER = nil`, `TREASURER_CHARACTERS = {}`, `AUTHOR = nil`, `Relay.LAUNCH_PINS = {}`, `API.AUTHORIZED = {}`.
- Ставки и рынки остаются выключенными (`Compliance.lua`, `scripts/bets-only.txt` не трогаем).
- `LICENSE` сохраняет копирайт Olympus; строки `olympus-…` (соли хешей и форматы: `"olympus-record-1|"`, `"olympus-strike-1:"`, `"olympus-api-authorized:"`…) и адрес `dnl-gentile/olympus-addon` не переименовываются.
- После каждой задачи `bash scripts/check.sh` завершается с кодом 0.
- `S=/tmp/claude-1000/-home-fenx/82c0fc03-4181-4a73-9315-00c8991ace19/scratchpad` — папка для временных файлов (логи прогонов); задать в начале сессии.
- Коммиты — в ветке `rebrand`, автор `Bezoutoff <alekdelom@gmail.com>` (уже прописан), сообщение заканчивается строкой `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Правила репозитория из `AGENTS.md`: каждое изменение поведения — с тестом; код, трогающий UI игры, — через gamepad gate (этот план такого кода не добавляет).

## Уточнения к спецификации (найдены при планировании)

1. **Тестовая личность.** ~300 выдуманных гильдий в тестах («Olympus Zeus», «Olympus Ember»…) своими делало правило «слово в названии»; ещё 264 раза тесты опираются на зашитых людей бета-версии, а `tests/run.lua` проверяет подписи ключом Olympus. Поэтому: нечёткое правило заменяется простым `ns.NAME_WORD` (целое слово, `nil` в релизе), а `tests/fixtures/identity.lua` подставляет тестам слово, людей и ключ Olympus сразу после загрузки `Core.lua`, `Relay.lua` и `Sign.lua`. Отдельный набор `tests/chillzone.lua` проверяет то, что несёт релиз.
2. **`OlympusSiteAggregate` остаётся** (переименованным и бездействующим): его требуют `package.sh`, `tests/check-scripts.sh` и тесты упаковки — вырезание затронуло бы 30+ проверок и мешало переносу патчей. Документы CurseForge остаются по той же причине (тесты сверяют `README.md` и `docs/CURSEFORGE.md` с кодом).
3. **Asmon/Asmongold** заменяются в игровых текстах (`Locales*`) и значениях в коде; комментарии и справочные разделы документации не трогаем (меньше конфликтов при переносе).
4. **Командам канала** `/ol`, `/olc`, `/oll` даны имена `/czn`, `/czc`, `/czl`.
5. **Найден баг кириллицы**: `Crafters.lua` ограничивает название профессии 24 байтами — русские «Кузнечное дело» (27 байт) и «Инженерное дело» (29) отбрасываются. Чиним подсчётом символов.

## Файлы

| Файл | Что | Задача |
|---|---|---|
| `scripts/rebrand.py` | правила ребрендинга; режимы `tree` и `patch` | 2 |
| `tests/rebrand_test.py` | тесты правил | 2 |
| `scripts/check.sh` | + тест правил, + проверка логотипа | 2, 10 |
| `Olympus/Core.lua` → `ChillZone/Core.lua` | правило по слову, точные имена главной гильдии, `WHO_WORD`, личность релиза, `KingName` | 3, 6 |
| `Olympus/Who.lua`, `Data.lua`, `Views.lua` | `/who` по `WHO_WORD`, главная гильдия через `ns.IsMainGuildName` | 3 |
| всё дерево | ребрендинг скриптом | 4 |
| `tests/fixtures/identity.lua` | тестовая личность | 5, 7 |
| `tests/run.lua`, `tests/sign-roundtrip.lua` | подключение личности, удаление тестов нечёткого правила, подключение `tests/chillzone.lua` | 3, 5, 6 |
| `ChillZone/Relay.lua`, `ChillZone/API.lua` | пустые пины и доверенные аддоны | 6 |
| `tests/chillzone.lua` | тесты релиза и изменений форка | 6, 7, 9 |
| `ChillZone/Sign.lua` | новый публичный ключ | 7 |
| `ChillZone/Locales.lua`, `ChillZone/Locales/*.lua` | тексты без Asmon, «олимпиец» | 8 |
| `ChillZone/Crafters.lua` | лимит названия профессии в символах | 9 |
| `scripts/make-logo.py`, `media/logo/src/chillzone.png`, `ChillZone/media/{logo64,logo128,emblem128}.tga`, `docs/logo.png` | логотип | 10 |
| `ChillZone/ChillZone.toc`, `ChillZone_Arena/ChillZone_Arena.toc`, `LICENSE`, `README.md`, `UPSTREAM.md` | метаданные | 11 |
| `scripts/port-upstream.sh` | перенос патчей оригинала | 12 |

---

### Task 1: Подготовка и базовый прогон

**Files:** нет изменений.

- [ ] **Step 1: Проверить luajit**

Run: `command -v luajit && luajit -v`
Expected: путь и `LuaJIT 2.1…`. Если пусто — остановиться и попросить пользователя выполнить `! sudo apt install luajit`.

- [ ] **Step 2: Базовый прогон оригинала**

Run: `cd /home/fenx/Documents/chillzone-addon && time bash scripts/check.sh > $S/baseline.txt 2>&1; echo "exit $?"`
Expected: `exit 0`, в конце файла `N passed, 0 failed`. Записать время прогона и число тестов — они нужны для оценки следующих шагов. Если оригинал уже падает, записать имена упавших тестов: это базовая линия, не наша регрессия (перенести их в `UPSTREAM.md` в задаче 11).

---

### Task 2: Скрипт ребрендинга

**Files:**
- Create: `scripts/rebrand.py`
- Create: `tests/rebrand_test.py`
- Modify: `scripts/check.sh` (после блока «Checking Python syntax…»)

**Interfaces:**
- Produces: `rebrand.rebrand(text) -> str` (все правила), `rebrand.words(text) -> str` (только слова, для путей), `rebrand.skipped(path) -> bool`; CLI `python3 scripts/rebrand.py tree|patch`.

- [ ] **Step 1: Написать тесты**

`tests/rebrand_test.py`:

```python
#!/usr/bin/env python3
"""scripts/rebrand.py's rules (run: python3 tests/rebrand_test.py)."""
import importlib.util
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_spec = importlib.util.spec_from_file_location("rebrand", os.path.join(ROOT, "scripts", "rebrand.py"))
rebrand = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rebrand)


class Rules(unittest.TestCase):
    def test_brand_in_every_case(self):
        self.assertEqual(rebrand.rebrand("Olympus II, OLYMPUS X, olympus"), "ChillZone II, CHILLZONE X, chillzone")

    def test_members(self):
        self.assertEqual(rebrand.rebrand("Olympians, OLYMPIAN, olympian"), "ChillZoners, CHILLZONER, chillzoner")

    def test_identifiers(self):
        self.assertEqual(rebrand.rebrand("IsOlympusMember(SLASH_OLYMPUS1, OlympusDB, OLYMPUS_TEST_FILTER)"),
                         "IsChillZoneMember(SLASH_CHILLZONE1, ChillZoneDB, CHILLZONE_TEST_FILTER)")

    def test_slash_commands(self):
        self.assertEqual(rebrand.rebrand('"/olympus", "/oly", /oly status, /ola, /ol hi, /olc, /oll, /ogarmy'),
                         '"/chillzone", "/cz", /cz status, /cza, /czn hi, /czc, /czl, /czarmy')

    def test_paths(self):
        self.assertEqual(rebrand.rebrand("Interface\\AddOns\\Olympus\\media\\logo64 ~/.olympus/council-key.json"),
                         "Interface\\AddOns\\ChillZone\\media\\logo64 ~/.chillzone/council-key.json")
        self.assertEqual(rebrand.words("Olympus_Arena/Olympus_Arena.toc"), "ChillZone_Arena/ChillZone_Arena.toc")
        self.assertEqual(rebrand.words("OlympusSiteAggregate/OlympusSiteAggregate.toc"),
                         "ChillZoneSiteAggregate/ChillZoneSiteAggregate.toc")

    def test_protected(self):
        for text in ("https://github.com/dnl-gentile/olympus-addon", '"olympus-record-1|"',
                     'S.SALT = "olympus-strike-1:"', '"olympus-api-authorized:"'):
            self.assertEqual(rebrand.rebrand(text), text)

    def test_other_words_untouched(self):
        text = "Olympia, Olympic, OLYMPVS, Olimpo, Developus Olympicus, /old, /olive, /ollie"
        self.assertEqual(rebrand.rebrand(text), text)

    def test_skipped_files(self):
        self.assertTrue(rebrand.skipped("LICENSE"))
        self.assertTrue(rebrand.skipped("UPSTREAM.md"))
        self.assertTrue(rebrand.skipped("docs/superpowers/specs/2026-11-06-chillzone-fork-design.md"))
        self.assertTrue(rebrand.skipped("tests/rebrand_test.py"))
        self.assertFalse(rebrand.skipped("Olympus/Core.lua"))

    def test_patch_headers(self):
        patch = ("diff --git a/Olympus/Core.lua b/Olympus/Core.lua\n--- a/Olympus/Core.lua\n"
                 "+++ b/Olympus/Core.lua\n-ns.NAME = \"Olympus\"\n")
        self.assertEqual(rebrand.rebrand(patch),
                         "diff --git a/ChillZone/Core.lua b/ChillZone/Core.lua\n--- a/ChillZone/Core.lua\n"
                         "+++ b/ChillZone/Core.lua\n-ns.NAME = \"ChillZone\"\n")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `python3 tests/rebrand_test.py`
Expected: FAIL — `FileNotFoundError` на `scripts/rebrand.py`.

- [ ] **Step 3: Написать скрипт**

`scripts/rebrand.py`:

```python
#!/usr/bin/env python3
"""ChillZone's rebranding of Olympus: one set of rules for the tree (once) and for upstream's patches.

  python3 scripts/rebrand.py tree     # every tracked file's text and path, in the working tree
  python3 scripts/rebrand.py patch    # stdin -> stdout: a patch of upstream's (git format-patch)

The rules: docs/superpowers/specs/2026-11-06-chillzone-fork-design.md, section 1.
"""
import os
import re
import subprocess
import sys

# Left as they are: the original's address, and the format and hash words ("olympus-record-1|",
# "olympus-strike-1:", "olympus-api-authorized:"...) that tests and saved data pin.
PROTECTED = re.compile(r"dnl-gentile/olympus-addon|olympus-(?=[a-z0-9])")
# The slash commands with no "olympus" in them, whole words only ("/oly" is not "/olympus").
SLASH = [
    (re.compile(r"/oly\b"), "/cz"),
    (re.compile(r"/ola\b"), "/cza"),
    (re.compile(r"/olc\b"), "/czc"),
    (re.compile(r"/oll\b"), "/czl"),
    (re.compile(r"/ol\b"), "/czn"),
    (re.compile(r"/ogarmy\b"), "/czarmy"),
]
# The words, the members' before the realm's.
WORDS = [
    ("OLYMPIAN", "CHILLZONER"), ("Olympian", "ChillZoner"), ("olympian", "chillzoner"),
    ("OLYMPUS", "CHILLZONE"), ("Olympus", "ChillZone"), ("olympus", "chillzone"),
]
WORD_RE = re.compile("|".join(re.escape(old) for old, _ in WORDS))
WORD_MAP = dict(WORDS)

SKIP = {"LICENSE", "UPSTREAM.md", "scripts/rebrand.py", "scripts/port-upstream.sh", "tests/rebrand_test.py"}
SKIP_DIRS = ("docs/superpowers/",)
BINARY = {".tga", ".png", ".jpg", ".jpeg", ".blp", ".ogg", ".mp3", ".wav", ".ttf", ".zip", ".pdf"}


def words(text):
    return WORD_RE.sub(lambda m: WORD_MAP[m.group(0)], text)


def rebrand(text):
    kept = []

    def keep(m):
        kept.append(m.group(0))
        return "\0%d\0" % (len(kept) - 1)

    text = PROTECTED.sub(keep, text)
    for pattern, new in SLASH:
        text = pattern.sub(new, text)
    text = words(text)
    return re.sub(r"\0(\d+)\0", lambda m: kept[int(m.group(1))], text)


def skipped(path):
    return path in SKIP or path.startswith(SKIP_DIRS)


def tracked():
    out = subprocess.run(["git", "ls-files", "-z"], check=True, capture_output=True).stdout
    return [p for p in out.decode("utf-8").split("\0") if p]


def tree():
    changed, moved, left = 0, 0, set()
    for path in tracked():
        if skipped(path):
            continue
        with open(path, "rb") as f:
            raw = f.read()
        if os.path.splitext(path)[1].lower() not in BINARY and b"\0" not in raw:
            text = raw.decode("utf-8", "surrogateescape")
            new = rebrand(text)
            if new != text:
                with open(path, "wb") as f:
                    f.write(new.encode("utf-8", "surrogateescape"))
                changed += 1
        target = words(path)
        if target != path:
            os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
            subprocess.run(["git", "mv", path, target], check=True)
            left.add(os.path.dirname(path))
            moved += 1
    for folder in sorted(left, key=len, reverse=True):
        while folder and os.path.isdir(folder) and not os.listdir(folder):
            os.rmdir(folder)
            folder = os.path.dirname(folder)
    print("rebrand: %d files rewritten, %d moved" % (changed, moved))


def patch():
    raw = sys.stdin.buffer.read()
    sys.stdout.buffer.write(rebrand(raw.decode("utf-8", "surrogateescape")).encode("utf-8", "surrogateescape"))


if __name__ == "__main__":
    if sys.argv[1:] == ["tree"]:
        tree()
    elif sys.argv[1:] == ["patch"]:
        patch()
    else:
        sys.exit(__doc__)
```

- [ ] **Step 4: Тесты проходят**

Run: `python3 tests/rebrand_test.py`
Expected: `OK` (9 tests).

- [ ] **Step 5: Подключить тест к check.sh**

В `scripts/check.sh` сразу после строки `	printf 'python3 not found: Python checks skipped.\n'` и закрывающего её `fi` (конец блока «Checking Python syntax») вставить:

```bash

if command -v python3 >/dev/null 2>&1; then
	printf 'Checking the rebranding rules...\n'
	python3 tests/rebrand_test.py
fi
```

- [ ] **Step 6: Полная проверка**

Run: `bash scripts/check.sh > $S/check.txt 2>&1; echo "exit $?"; tail -3 $S/check.txt`
Expected: `exit 0`. Если упал `tests/check-scripts.sh` (CI-шаг «Verify check script failure handling» копирует `check.sh` в песочницу) — запустить `bash tests/check-scripts.sh`; при падении из-за отсутствия `tests/rebrand_test.py` в песочнице обернуть вставку условием `[ -f tests/rebrand_test.py ] &&`.

- [ ] **Step 7: Commit**

```bash
git add scripts/rebrand.py tests/rebrand_test.py scripts/check.sh
git commit -m "Add the rebranding script and its rules' tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Членство по точным именам (до ребрендинга)

Цель — чтобы после механической замены не осталось логики, завязанной на слово «olympus». Значения пока Olympus-овские; тесты должны остаться зелёными.

**Files:**
- Modify: `Olympus/Core.lua` (IsTreasurer ~1025, KING_GUILD/IsKingGuild ~1072–1077, KingGuildName ~1669–1674, правило названия ~1792–1902)
- Modify: `Olympus/Who.lua:52-56`
- Modify: `Olympus/Data.lua:854-866`
- Modify: `Olympus/Views.lua:2283`
- Modify: `tests/run.lua` (тесты на ~268, ~276, ~337 и ~5015)
- Delete: `tests/fixtures/olympus-yes.txt`, `tests/fixtures/olympus-no.txt`

**Interfaces:**
- Produces: `ns.NAME_WORD` (string|nil, сложенное слово), `ns.WHO_WORD` (string), `ns.IsMainGuildName(guild) -> bool`; `ns.KING_GUILD` хранит имена как в игре; `ns.KingGuildName()` возвращает сохранённое имя.

- [ ] **Step 1: Тест на новое поведение главной гильдии**

В `tests/run.lua` заменить тест `test("federation filter matches any guild with 'olympus' in the name", …)` (строки ~268–274) целиком на:

```lua
test("federation filter: a whole word of the name (ns.NAME_WORD), the main guild by its exact name", function()
	eq(ns.IsFederation("Olympus"), true)
	eq(ns.IsFederation("OLYMPUS IV"), true)
	eq(ns.IsFederation("Sons of olympus"), true)
	eq(ns.IsFederation("Olympia"), false)
	eq(ns.IsFederation("OLYMPVS"), false, "no misspellings: the network is a list of names")
	eq(ns.IsFederation("Olympian Might"), false, "Olympian is another word")
	eq(ns.IsFederation(nil), false)
	eq(ns.IsMainGuildName("OLYMPUS"), true); eq(ns.IsMainGuildName("Olympus II"), false)
	local savedFaction = ns.faction
	ns.faction = "Horde"
	eq(ns.IsKingGuild("MUDHUTTERS"), true, "the King's guild in any case")
	eq(ns.KingGuildName(), "Mudhutters", "as the game writes it")
	eq(ns.IsMainGuildName("Olympus"), true, "the Alliance's main guild on either side")
	ns.faction = savedFaction
	local savedGuild = GetGuildInfo
	GetGuildInfo = function() return "Olympus", "Knight", 3 end
	local crowned = { ns.IsCrownRank("Olympus VI", 1), ns.IsCrownRank("Olympus", 1) }
	GetGuildInfo = savedGuild
	eq(crowned[1], false, "an officer of another guild of the network is no Crown officer")
	eq(crowned[2], true)
end)
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `OLYMPUS_TEST_FILTER='federation filter: a whole word' luajit tests/run.lua 2>&1 | tail -5`
Expected: FAIL — `OLYMPVS` ещё свой по нечёткому правилу (или `attempt to call field 'IsMainGuildName' (a nil value)`).

- [ ] **Step 3: Удалить тесты нечёткого правила**

В `tests/run.lua` удалить целиком:
- `test("federation filter against 250 misspellings and 400 look-alike guild names (tests/fixtures)", …)` (~276–298);
- `test("federation filter: Olympus however it was spelled, but not other words", …)` (~337–375, до её `end)` включительно; проверка IsCrownRank из её конца уже перенесена в Step 1).

В тесте с `/who` (~5012–5021) удалить фрагмент от строки `		-- Then the misspelled names, one per click: a player of <OLYMPVS> counts.` до строки `		eq(ns.Who.sweep.byName.Olaf, nil, "a guild that is not Olympus does not")` включительно (цикл по `ns.Who.VARIANTS` и два assert после него). Строку `eq(ns.Who.sweep.done, true, "still complete")` оставить.

Run: `git rm tests/fixtures/olympus-yes.txt tests/fixtures/olympus-no.txt`

- [ ] **Step 4: Core.lua — главная гильдия по точному имени**

Заменить строку 1072 и функцию под ней:

```lua
ns.KING_GUILD = { Alliance = "Olympus", Horde = "Mudhutters" } -- (the Horde's: <Mudhutters>, 0.9.4)
-- (ChillZone: each name as the game writes it, matched folded, ns.Fold. Lua's lower() leaves
-- Cyrillic letters alone, so a name is never kept lowercased here.)
function ns.IsKingGuild(guild)
	if type(guild) ~= "string" then return false end
	local want = ns.KING_GUILD[ns.faction or "Alliance"]
	return want ~= nil and ns.Fold(guild) == ns.Fold(want)
end
-- The Alliance King's guild by its exact name, on either side: the Treasurer's guild and the
-- census's standard-bearer (Olympus's <Olympus>, on both sides).
function ns.IsMainGuildName(guild)
	local main = ns.KING_GUILD.Alliance
	return type(guild) == "string" and type(main) == "string" and ns.Fold(guild) == ns.Fold(main)
end
-- The /who search for the network's players (Who.QUERY): a part of every guild's name.
ns.WHO_WORD = "Olympus"
```

В `ns.IsTreasurer` (~1025) заменить первую строку тела:

```lua
	if type(name) ~= "string" or not ns.IsMainGuildName(guild) then return false end
```

`ns.KingGuildName` (~1669) заменить на:

```lua
function ns.KingGuildName()
	local mine = GetGuildInfo and GetGuildInfo("player")
	if ns.IsKingGuild(mine) then return mine end
	return ns.KING_GUILD[ns.faction or "Alliance"] or ""
end
```

- [ ] **Step 5: Core.lua — правило по слову вместо нечёткого**

Удалить блок от строки `-- Fixed on purpose: only guilds with "Olympus" in their name belong to the realm, however` (~1792) до `end`, закрывающего `local function Federation(guild)` (строка перед `-- The name rule alone (cached): …`), включительно — вместе с `REALM_WORDS`, `OTHER`, `Sounds`, `OlympusWord`, `Against`, `ns.Sounds`, `ns.Slips` и строкой `local federation, federationSize = {}, 0`. На его место вставить:

```lua
-- ChillZone: the network is a list of guilds by their exact names: the King's (ns.KING_GUILD), those
-- the addon ships with (ns.APPROVED_BUILTIN) and the author's signed list. A word of a guild's name
-- makes it ours only where ns.NAME_WORD is set (folded, a whole word): the offline tests' made-up
-- guilds (tests/fixtures/identity.lua). A release leaves it nil.
ns.NAME_WORD = "olympus"
local federation, federationSize = {}, 0 -- [name] = true|false, asked often: kept
local function Federation(guild)
	local want = ns.NAME_WORD
	if type(want) ~= "string" or want == "" then return false end
	for word in ns.Fold(guild):gmatch("%a+") do
		if word == want then return true end
	end
	return false
end
```

Run: `grep -nE 'ns\.(Sounds|Slips)|OlympusWord|REALM_WORDS|Against\(' Olympus/*.lua tests/*.lua tests/arena/*.lua`
Expected: пусто. Если что-то нашлось в тестах — это тест нечёткого правила: удалить его.

- [ ] **Step 6: Who.lua, Data.lua, Views.lua**

`Olympus/Who.lua` — строки 52–56 (`Who.QUERY …` и `Who.VARIANTS …` с комментарием между ними) заменить на:

```lua
Who.QUERY = ('g-"%s"'):format(tostring(ns.WHO_WORD or ""))
-- ChillZone: no misspelled names to search, the network is a list of exact names (Core.lua).
Who.VARIANTS = {}
```

`Olympus/Data.lua` — `Data.IsStandardBearer` и строку с `olympusA, olympusB` заменить:

```lua
-- The standard-bearer: the Alliance King's guild by its exact name (any case, ns.IsMainGuildName),
-- first on a tie of any order of guilds, the default one's and a column's whichever way it runs,
-- before the average level (the author's ask).
local function MainSortName()
	local main = ns.KING_GUILD and ns.KING_GUILD.Alliance
	return type(main) == "string" and GuildSortName(main) or nil
end
function Data.IsStandardBearer(name)
	return type(name) == "string" and GuildSortName(name) == MainSortName()
end
```

и в `Data.GuildDefaultLess`:

```lua
	local main = MainSortName()
	local olympusA, olympusB = nameA == main, nameB == main
```

`Olympus/Views.lua:2283`:

```lua
		for _, o in ipairs(ns.IsMainGuildName(king.name) and king.g.officers or {}) do -- (the Treasurer: <Olympus>, the Alliance's)
```

- [ ] **Step 7: Тест проходит, полная проверка**

Run: `OLYMPUS_TEST_FILTER='federation filter: a whole word' luajit tests/run.lua 2>&1 | tail -3`
Expected: `1 passed, 0 failed`.

Run: `bash scripts/check.sh > $S/check.txt 2>&1; echo "exit $?"; grep -nE 'FAIL|failed' $S/check.txt | head -30`
Expected: `exit 0`. Возможные падения и что с ними делать:
- тест ждёт поиск `/who` по вариантам написания (число отправленных запросов за раунд) — уменьшить ожидание на `#VARIANTS` оригинала (5), в сообщении коммита перечислить такие тесты;
- тест ждёт `KingGuildName()` == «Olympus», а гильдия хранилась в нижнем регистре в фикстуре — поправить фикстуру на точное имя;
- `Data.GuildKey` чувствителен к регистру (`Borders.lua:1568` передаёт `ns.KING_GUILD[...]`) — заменить там `king` на `ns.Fold(king)`.

- [ ] **Step 8: Commit**

```bash
git add -A Olympus tests
git commit -m "Count guilds by exact names and a test-only name word

The fuzzy Olympus name rule goes; ns.NAME_WORD keeps the tests' made-up
guilds. The main guild is kept as the game writes it and matched folded.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Ребрендинг дерева

**Files:** всё дерево (кроме исключений `rebrand.skipped`); каталоги `Olympus/` → `ChillZone/`, `Olympus_Arena/` → `ChillZone_Arena/`, `OlympusSiteAggregate/` → `ChillZoneSiteAggregate/`.

- [ ] **Step 1: Прогнать скрипт**

Run: `git status --porcelain | head -1` — Expected: пусто (чистое дерево).
Run: `python3 scripts/rebrand.py tree`
Expected: `rebrand: N files rewritten, M moved` с N > 300 и M > 900.

- [ ] **Step 2: Проверить остатки**

Run: `git grep -nIiE 'olympus|olympian' -- . ':!LICENSE' ':!docs/superpowers' ':!scripts/rebrand.py' ':!tests/rebrand_test.py' | grep -vE 'olympus-[a-z0-9]|dnl-gentile/olympus-addon' | head -20`
Expected: пусто.

Run: `git grep -nE '"/(oly|ola|olc|oll|ol|ogarmy)"' | head`
Expected: пусто.

- [ ] **Step 3: Полная проверка**

Run: `bash scripts/check.sh > $S/check.txt 2>&1; echo "exit $?"; grep -nE 'FAIL|failed|Cannot|not what' $S/check.txt | head -30`
Expected: `exit 0`. Возможные падения:
- `curseforge-size.lua --check`: страница выросла (каждое «ChillZone» на 2 символа длиннее «Olympus») — перегенерировать `luajit scripts/curseforge-page.lua`; если превышен бюджет, поднять константу бюджета в `scripts/curseforge-size.lua` до нового размера с комментарием `-- ChillZone: not published on CurseForge; the budget follows the rebranded page.`;
- тест сравнивает ширину или длину текста с «Olympus» (лимит 255 байт на сообщение, ширина строки окна) — уменьшить только ожидание, если превышение — прямое следствие длины бренда; иначе разбираться отдельно и описать в сообщении коммита.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Rebrand Olympus as ChillZone (scripts/rebrand.py tree)

Mechanical: names, paths, slash commands, prefix and channels.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Тестовая личность

Тесты оригинала продолжают видеть сеть Olympus (переименованную): гильдии по слову, людей беты. Пока значения в фикстуре совпадают с кодом — это подготовка, поведение не меняется.

**Files:**
- Create: `tests/fixtures/identity.lua`
- Modify: `tests/run.lua` (после `local ADDON_DIR = ROOT .. "ChillZone/"`)
- Modify: `tests/sign-roundtrip.lua` (в начале, до первого `loadfile`)

**Interfaces:**
- Produces: глобальная функция-обёртка `loadfile`, глобальная `RAW_LOADFILE` (настоящий `loadfile`, для тестов релиза).

- [ ] **Step 1: Написать фикстуру**

`tests/fixtures/identity.lua`:

```lua
-- ChillZone's offline tests run on the network the original's tests were written for: made-up guilds
-- named after the brand ("ChillZone II", "ChillZone Zeus": ours by the name word) and the beta's King,
-- Treasurer, author and relays. A release has none of these (Core.lua: the guilds by their exact
-- names, no people; tests/chillzone.lua checks it). Each harness loads this file once, before any
-- addon file; every later loadfile of ChillZone/<file> named below gets these values right after the
-- file runs. RAW_LOADFILE is the real loadfile, for loading a file as a release has it.
--   assert(loadfile(ROOT .. "tests/fixtures/identity.lua"))()
local AFTER = {
	["Core.lua"] = function(ns)
		ns.NAME_WORD = "chillzone"
		ns.WHO_WORD = "ChillZone"
		ns.KING_GUILD = { Alliance = "ChillZone", Horde = "Mudhutters" }
		ns.KING_NAME = "Asmon"
		ns.KING_CHARACTER = { Alliance = "Asmongold Asmongler", Horde = "Duskmonkey Boneback" }
		ns.KING_REALM, ns.KING_REALM_HORDE = "ClassicBetaPvP", nil
		ns.TREASURER, ns.TREASURER_REALM = "Pyralis Ashandar", "ClassicBetaPvP"
		ns.TREASURER_CHARACTERS = { "Pyralis Ashandar", "Pyralis Andarai" }
		ns.AUTHOR, ns.AUTHOR_REALM = "Faladoriel Skylance", "ClassicBetaPvP"
		ns.APPROVED_BUILTIN = { Alliance = { "CHILLZONER", "CHILLZONERS" } }
		ns.REMOVED_BUILTIN = { Alliance = { realm = "ClassicBetaPvP", "ChillZone Defense Force" } }
	end,
	["Relay.lua"] = function(ns)
		ns.Relay.LAUNCH_PINS = { ForeverPvE = { "Developus Olympicus", "Asmongold Thereal" }, ForeverPvP = { "Twalin Firebraid" } }
	end,
}

local raw = loadfile
RAW_LOADFILE = raw
function loadfile(path, ...)
	local chunk, err = raw(path, ...)
	local after = chunk and AFTER[tostring(path):match("ChillZone[/\\]([%w]+%.lua)$") or ""]
	if not after then return chunk, err end
	return function(...)
		setfenv(chunk, getfenv(1)) -- (a harness's setfenv on this function reaches the file)
		chunk(...)
		after((select(2, ...)))
	end
end
```

- [ ] **Step 2: Подключить фикстуру**

`tests/run.lua`, сразу после строки `local ADDON_DIR = ROOT .. "ChillZone/"`:

```lua
-- ChillZone: the tests' network and people (tests/fixtures/identity.lua), before any addon file.
assert(loadfile(ROOT .. "tests/fixtures/identity.lua"))()
```

`tests/sign-roundtrip.lua`: найти определение корня (`ROOT`/`root`) и вставить ту же строку сразу после него, до цикла `for _, file in ipairs({ "Locales", "Core", … })`.

- [ ] **Step 3: Полная проверка**

Run: `bash scripts/check.sh > $S/check.txt 2>&1; echo "exit $?"`
Expected: `exit 0` (значения фикстуры равны значениям кода, поведение то же). Если упал тест из-за `setfenv`/окружения — проверить, что он вызывает `loadfile` для `ChillZone/Core.lua`, `Relay.lua` и что обёртка передала окружение.

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/identity.lua tests/run.lua tests/sign-roundtrip.lua
git commit -m "Give the offline tests their own network and people

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Личность ChillZone в релизе

**Files:**
- Modify: `ChillZone/Core.lua` (KING_NAME ~919, AUTHOR ~924–925, TREASURER ~989–990, TREASURER_CHARACTERS ~1037, KING_GUILD/WHO_WORD ~1072, KING_CHARACTER/KING_REALM ~1091–1092, KingName ~1063, APPROVED_BUILTIN ~1530, REMOVED_BUILTIN ~1541, NAME_WORD)
- Modify: `ChillZone/Relay.lua:55`, `ChillZone/API.lua:146-148`
- Create: `tests/chillzone.lua`
- Modify: `tests/run.lua` (в конце, перед `print(("\n%d passed, %d failed")…`)

**Interfaces:**
- Consumes: `RAW_LOADFILE` (задача 5), `ns.IsMainGuildName`, `ns.WHO_WORD`, `ns.NAME_WORD` (задача 3).
- Produces: `tests/chillzone.lua(ns, test, eq, h)` с `h = { ADDON_DIR, ROOT, WithCraft }`; функция `Release()` внутри него.

- [ ] **Step 1: Написать тесты релиза**

`tests/chillzone.lua`:

```lua
-- ChillZone's own tests: what a release holds (Core.lua's network and people as the release has
-- them, not tests/fixtures/identity.lua's) and what the fork changed.
local ns, test, eq, h = ...

local function ReadFile(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- Core.lua as a release loads it (RAW_LOADFILE: no test identity), in a table of its own.
local function Release()
	local r = {}
	for _, file in ipairs({ "Bootstrap", "Locales" }) do assert(loadfile(h.ADDON_DIR .. file .. ".lua"))("ChillZone", r) end
	assert(RAW_LOADFILE(h.ADDON_DIR .. "Core.lua"))("ChillZone", r)
	r.faction, r.realm, r.me, r.db = "Alliance", "Realm", "Tester-Realm", { guilds = {} }
	return r
end

test("ChillZone release: the network is <Чиллзон> and <Чиллзон Навсегда> by their exact names, no name word", function()
	local r = Release()
	eq(r.NAME_WORD, nil)
	eq(r.IsFederation("Чиллзон"), true, "the King's guild")
	eq(r.IsFederation("Чиллзон Навсегда"), true, "shipped with the addon")
	eq(r.IsFederation("ChillZone II"), false, "no word of a name makes a guild ours in a release")
	eq(r.IsFederation("Чиллзон Навсегда II"), false, "nor a longer name")
	eq(r.IsFederation("Olympus"), false)
	eq(r.IsKingGuild("Чиллзон"), true); eq(r.IsKingGuild("Чиллзон Навсегда"), false)
	eq(r.IsMainGuildName("Чиллзон"), true)
	eq(r.WHO_WORD, "Чиллзон")
	r.faction = "Horde"
	eq(r.IsKingGuild("Чиллзон"), false, "no King's guild on the Horde")
end)

test("ChillZone release: no person is named in the code (the author's signed list names them)", function()
	local r = Release()
	eq(next(r.KING_CHARACTER), nil); eq(r.KING_NAME, nil)
	eq(r.TREASURER, nil); eq(#r.TREASURER_CHARACTERS, 0); eq(r.AUTHOR, nil)
	eq(next(r.REMOVED_BUILTIN), nil)
	eq(r.IsKingCharacter("Asmongold Asmongler-ClassicBetaPvP"), false)
	eq(r.IsTreasurer("Pyralis Ashandar-ClassicBetaPvP", "Чиллзон"), false)
	eq(#(r.AuthorCharacters()), 0)
	eq(r.KingName("Lead Chill-Realm"), "Lead Chill", "the King by his character's name")
	assert(ReadFile(h.ADDON_DIR .. "Relay.lua"):find("Relay.LAUNCH_PINS = {}", 1, true), "no relays pinned")
	assert(ReadFile(h.ADDON_DIR .. "API.lua"):find("API.AUTHORIZED = {}", 1, true), "no partner addon trusted")
end)
```

В конец `tests/run.lua`, перед `print(("\n%d passed, %d failed"):format(passed, failed))`:

```lua
-- ChillZone (tests/chillzone.lua): what a release holds, and the fork's own changes.
print("tests/chillzone.lua")
assert(loadfile(ROOT .. "tests/chillzone.lua"))(ns, test, eq, { ADDON_DIR = ADDON_DIR, ROOT = ROOT, WithCraft = WithCraft })
```

- [ ] **Step 2: Тесты падают**

Run: `CHILLZONE_TEST_FILTER='ChillZone release' luajit tests/run.lua 2>&1 | tail -8`
Expected: 2 FAIL (`IsFederation("Чиллзон")` → false, `KING_NAME` = "Asmon").

- [ ] **Step 3: Значения релиза**

`ChillZone/Core.lua`:

```lua
ns.KING_NAME = nil -- (ChillZone: none; the King goes by his character's name, ns.KingName)
```
```lua
ns.AUTHOR = nil -- (ChillZone: the author's signed titles list names his characters)
ns.AUTHOR_REALM = nil
```
```lua
ns.TREASURER = nil -- (ChillZone: the signed titles list names the Treasurer)
ns.TREASURER_REALM = nil
```
```lua
ns.TREASURER_CHARACTERS = {}
```
```lua
ns.KING_GUILD = { Alliance = "Чиллзон" } -- (ChillZone: the Alliance alone)
```
```lua
ns.WHO_WORD = "Чиллзон"
```
```lua
ns.KING_CHARACTER = {} -- (ChillZone: the signed titles list names the King)
ns.KING_REALM = nil
```
```lua
ns.APPROVED_BUILTIN = { Alliance = { "Чиллзон Навсегда" } }
```
```lua
ns.REMOVED_BUILTIN = {}
```
```lua
ns.NAME_WORD = nil
```

`ns.KingName` (~1063) — не опираться на пустой `KING_NAME`:

```lua
function ns.KingName(leader)
	if ns.faction == "Horde" or not ns.KING_NAME then return leader and ns.ShortName(leader) or "?" end
	return ns.KING_NAME
end
```

`ChillZone/Relay.lua:55`: `Relay.LAUNCH_PINS = {}`
`ChillZone/API.lua` — таблицу `API.AUTHORIZED` (с единственным хешем) заменить на `API.AUTHORIZED = {}`.

- [ ] **Step 4: Тесты проходят**

Run: `CHILLZONE_TEST_FILTER='ChillZone release' luajit tests/run.lua 2>&1 | tail -3`
Expected: `2 passed, 0 failed`. Если `Release()` падает на загрузке `Core.lua` в пустую таблицу — дополнить `r` полями, которые читает загрузка (ориентир: `tests/run.lua` ~29056 грузит `{ "Bootstrap", "Locales", "Core" }` в свежую таблицу так же).

- [ ] **Step 5: Полная проверка**

Run: `bash scripts/check.sh > $S/check.txt 2>&1; echo "exit $?"`
Expected: `exit 0`. Если `tests/check-affected-selector.lua` требует, чтобы каждый `tests/*.lua` был в карте — добавить `["tests/chillzone.lua"] = …` в `scripts/check-affected.lua` по образцу `tests/launch-identity.lua`. Если упал тест `tests/arena/api.lua`, ожидающий непустой `API.AUTHORIZED`, — он проверяет отгруженный хеш Olympus: удалить эту проверку и указать в сообщении коммита.

- [ ] **Step 6: Commit**

```bash
git add -A ChillZone tests scripts
git commit -m "Ship ChillZone's network: Чиллзон and Чиллзон Навсегда, no people in the code

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Новый ключ подписи

**Files:**
- Modify: `tests/fixtures/identity.lua` (+ `AFTER["Sign.lua"]`)
- Modify: `ChillZone/Sign.lua:123-125`
- Modify: `tests/chillzone.lua` (+ тест ключа)

- [ ] **Step 1: Сохранить ключ Olympus для тестов**

Скопировать шестнадцатеричные строки из `ChillZone/Sign.lua:123` (`Sign.N = FromHex("…")`) и `:124` (`Sign.MU = FromHex("…")`) в `AFTER` фикстуры:

```lua
	-- The original's public key: tests/run.lua's lists were signed with it (the author's key there).
	["Sign.lua"] = function(ns)
		local S = ns.Sign
		local n, mu
		S.WithKey(UPSTREAM_N, UPSTREAM_MU, 86, function() n, mu = S.N, S.MU end)
		S.N, S.MU, S.K = n, mu, 86
	end,
```

и над `local AFTER` объявить `local UPSTREAM_N = "<строка из :123>"` и `local UPSTREAM_MU = "<строка из :124>"` (вставить фактические строки целиком).

Run: `bash scripts/check.sh > $S/check.txt 2>&1; echo "exit $?"` — Expected: `exit 0` (ключ пока тот же).

- [ ] **Step 2: Тест на ключ релиза (падает)**

Добавить в `tests/chillzone.lua`:

```lua
test("ChillZone release: the signed lists are checked with ChillZone's key, not Olympus's", function()
	local text = ReadFile(h.ADDON_DIR .. "Sign.lua")
	assert(not text:find("84a62410ffd1872739d169af98d461de", 1, true), "Olympus's key is gone")
	assert(text:find('Sign.N = FromHex("' .. CHILLZONE_N_PREFIX, 1, true), "ChillZone's key")
end)
```

где `CHILLZONE_N_PREFIX` — локальная константа в начале файла: первые 32 hex-символа нового `N` (заполнить в Step 4).

- [ ] **Step 3: Создать ключ**

Run: `python3 scripts/council-sign.py keygen`
Expected: строки `N = …`, `MU = …`, `K = 86`; файл `~/.chillzone/council-key.json` с правами 600. **Приватную часть не печатать и не коммитить.** Сообщить пользователю: этот файл нужно добавить в бэкап.

- [ ] **Step 4: Вписать публичный ключ**

`ChillZone/Sign.lua:123-125`: заменить hex в `Sign.N = FromHex("…")` и `Sign.MU = FromHex("…")` на выведенные `N` и `MU`; `Sign.K` — на выведенный `K`. В `tests/chillzone.lua` задать `local CHILLZONE_N_PREFIX = "<первые 32 символа N>"`.

Run: `git grep -nE '[0-9a-f]{256,}' -- scripts | head` — если в скриптах (например, `scripts/record-verify.lua`) встречается старый `N` (`84a62410…`), заменить и там.

- [ ] **Step 5: Полная проверка**

Run: `bash scripts/check.sh > $S/check.txt 2>&1; echo "exit $?"`
Expected: `exit 0`, включая `tests/sign-roundtrip.sh` (одноразовый ключ) и `tests/records-seal-roundtrip.sh`.

- [ ] **Step 6: Commit**

```bash
git add ChillZone/Sign.lua tests/fixtures/identity.lua tests/chillzone.lua scripts
git commit -m "Check signed lists with ChillZone's own key

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Asmon и «олимпиец» в игровых текстах

**Files:**
- Modify: `ChillZone/Locales.lua` (английский и блок pt-BR), `ChillZone/Locales/{ruRU,deDE,esES,frFR,itIT}.lua`, `ChillZone/Locales/ChurchText.lua`, `ChillZone/Locales/AccordText.lua`

- [ ] **Step 1: Найти все строки**

Run: `git grep -nE 'Asmon' -- 'ChillZone/Locales.lua' 'ChillZone/Locales/*.lua' | grep -vE ':[0-9]+:\s*--'`
Expected: ~95 строк в ключах `DEV_KING_VIEW_ON/OFF/NOW_ON/NOW_OFF`, `COUNCIL_CENSUS_TIP`, `APPROVED_LIST`, `APPROVED_NOT_MINE`, `APPROVED_JOIN_HINT`, `LETTER_1_2_0`, `WATCHCHAT_STRIKE_1`, `ACCORD_T1_1`, `CHURCH_ASOF_TIP`, `CHURCH_HEAD_NAME`, `CHURCH_HEAD_NONE`, `CHURCH_HEAD_TIP`.

- [ ] **Step 2: Заменить по правилам**

Английский (`Locales.lua`, `ChurchText.lua`, `AccordText.lua`):

| Ключ | Было (фрагмент) | Стало |
|---|---|---|
| `DEV_KING_VIEW_*` | `Asmon's view` | `King's view` |
| `COUNCIL_CENSUS_TIP` | `chosen by Asmongold's team.` | `chosen by the King.` |
| `APPROVED_LIST` | `Guilds of Asmon's ChillZone the author's signed list names (their names don't say ChillZone): %s` | `Guilds of ChillZone the author's signed list names: %s` |
| `APPROVED_NOT_MINE` | `If it belongs to Asmon's ChillZone,` | `If it belongs to ChillZone,` |
| `APPROVED_JOIN_HINT` | `Is <%s> one of Asmon's ChillZone guilds whose name doesn't say ChillZone?` | `Is <%s> one of ChillZone's guilds?` |
| `LETTER_1_2_0` | `Asmongold is its Head` / `Asmongold` | `the King is its Head` / `the King` |
| `WATCHCHAT_STRIKE_1` | `by Asmongold's team` | `by the King's moderators` |
| `ACCORD_T1_1` | `The free addon of Asmongold's ChillZone guilds` | `The free addon of the ChillZone guilds` |
| `CHURCH_ASOF_TIP` | `Asmongold's client` | `The King's client` |
| `CHURCH_HEAD_NAME`, `CHURCH_HEAD_NONE` | `"Asmongold"` | `"The King"` |
| `CHURCH_HEAD_TIP` | `Asmongold himself is the Head of the Church.` | `The King himself is the Head of the Church.` |

Русский (`ruRU.lua`):

| Ключ | Было | Стало |
|---|---|---|
| `DEV_KING_VIEW_*` | `Вид Asmon` | `Вид Короля` |
| `COUNCIL_CENSUS_TIP` | `выбранные командой Asmongold.` | `выбранные Королём.` |
| `APPROVED_LIST` | `Гильдии ChillZone от Asmon из подписанного списка автора (в их названиях нет слова ChillZone): %s` | `Гильдии ChillZone из подписанного списка автора: %s` |
| `APPROVED_NOT_MINE` | `Если она входит в ChillZone от Asmon,` | `Если она входит в ChillZone,` |
| `APPROVED_JOIN_HINT` | `<%s> - одна из гильдий ChillZone от Asmon, в названии которой нет слова ChillZone?` | `<%s> - одна из гильдий ChillZone?` |
| `LETTER_1_2_0` | `{church} Asmongold - её Глава.` | `{church} Король - её Глава.` |
| `WATCHCHAT_STRIKE_1` | `Модерацией здесь занимается команда Asmongold.` | `Модерацией здесь занимаются модераторы Короля.` |
| `ACCORD_T1_1` | `Бесплатный аддон гильдий ChillZone, сообщества Asmongold:` | `Бесплатный аддон гильдий ChillZone:` |
| `CHURCH_ASOF_TIP` | `Клиент Asmongold не выполняет` | `Клиент Короля не выполняет` |
| `CHURCH_HEAD_NAME`, `CHURCH_HEAD_NONE` | `"Asmongold"` | `"Король"` |
| `CHURCH_HEAD_TIP` | `Глава Церкви - сам Asmongold.` | `Глава Церкви - сам Король.` |

«Олимпиец» в `ruRU.lua` (строки ~2009, 2018, 2026, 4821–4823, 4862, 4881, 4883):

| Было | Стало |
|---|---|
| `с другими олимпийцами` | `с другими участниками ChillZone` |
| `"Найти олимпийца"` | `"Найти участника ChillZone"` |
| `с товарищами-олимпийцами` | `с товарищами из ChillZone` |
| `убил олимпиец` | `убил участник ChillZone` |
| `убил олимпийца` | `убил участника ChillZone` |
| `Клиент олимпийца` | `Клиент участника ChillZone` |
| `где стоял олимпиец` | `где стоял участник ChillZone` |
| `между олимпийцем и` | `между участником ChillZone и` |
| `сторона олимпийца` | `сторона участника ChillZone` |

Немецкий, испанский, французский, итальянский и pt-BR — те же ключи по тому же правилу: «Asmon/Asmongold» в роли главы → слово «Король» этого файла (`König`, `Rey`, `Roi`, `Re`, `Rei`; взять форму, которой файл уже называет Короля, например в `NETOFF_NOT_KING_GUILD`), «Asmon's ChillZone» → «ChillZone», оговорка «в названии нет слова ChillZone» удаляется.

- [ ] **Step 3: Остатков нет**

Run: `git grep -nE 'Asmon' -- 'ChillZone/Locales.lua' 'ChillZone/Locales/*.lua' | grep -vE ':[0-9]+:\s*--'; git grep -nE '[Оо]лимпи' -- ChillZone`
Expected: пусто.

- [ ] **Step 4: Полная проверка**

Run: `bash scripts/check.sh > $S/check.txt 2>&1; echo "exit $?"`
Expected: `exit 0`. Тесты, сверяющие эти строки с прежним текстом (например, `CHURCH_HEAD_NAME == "Asmongold"` или длина строки ≤ 255 байт), поправить на новый текст; `tests/locales-full.lua` должен остаться зелёным (все ключи есть во всех языках).

- [ ] **Step 5: Commit**

```bash
git add -A ChillZone tests
git commit -m "Name the King, not Asmongold, in every language

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Кириллица — названия профессий

**Files:**
- Modify: `ChillZone/Crafters.lua:411`
- Modify: `tests/chillzone.lua`

- [ ] **Step 1: Тест (падает)**

Добавить в `tests/chillzone.lua`:

```lua
test("ChillZone: crafters: a Russian client's profession names (two bytes a letter) are listed whole", function()
	h.WithCraft(function(w, Cr)
		Cr.HandleListing("CHANNEL", "Kuznec-Realm",
			"W1~ChillZone Zeus~164:Кузнечное дело:150:300:12,Инженерное дело:Инженерное дело:120:300:8")
		local b = Cr.Board()
		eq(#b, 1)
		eq(#b[1].profs, 2, "27 and 29 bytes, 14 and 15 letters: both kept")
		eq(b[1].profs[1].name, "Кузнечное дело")
		Cr.HandleListing("CHANNEL", "Long-Realm", "W1~ChillZone Zeus~164:" .. ("Ж"):rep(25) .. ":150:300:12")
		eq(#Cr.Board(), 1, "more than 24 letters: still refused")
	end)
end)
```

Run: `CHILLZONE_TEST_FILTER='Russian client' luajit tests/run.lua 2>&1 | tail -5`
Expected: FAIL — `0 ~= 2` в «both kept».

- [ ] **Step 2: Исправление**

`ChillZone/Crafters.lua:411` — заменить `#key <= 24 and #name <= 24` на подсчёт символов (тот же приём, что `Board.lua:120`):

```lua
		if key and Letters(key) <= 24 and Letters(name) <= 24 and rank and max and n and #profs < Crafters.PROFS_MAX then
```

и над `function Crafters.HandleListing` добавить:

```lua
-- A name's letters, not its bytes (a Cyrillic letter is two in UTF-8), at most 72 bytes in all.
local function Letters(s)
	if #s > 72 then return math.huge end
	return select(2, s:gsub("[^\128-\191]", ""))
end
```

- [ ] **Step 3: Тест проходит, полная проверка**

Run: `CHILLZONE_TEST_FILTER='Russian client' luajit tests/run.lua 2>&1 | tail -3` — Expected: `1 passed`.

- [ ] **Step 4: Имена настоящих офицеров через проверки имён**

Офицеры гильдий, которые принимают игроков (от пользователя, 2026-11-06). Добавить в `tests/chillzone.lua`:

```lua
-- The guilds' officers who take recruits (the owner's list, 2026-11-06): Forever's "First Surname",
-- Latin and Cyrillic (up to 31 bytes, 42 with "-ForeverPvP").
local OFFICERS = { "Wipe Copium", "Татарин Уфимский", "Peepo Ingore", "Vladimir Goyda", "Гулдан Казмодан",
	"Сундук Открою", "Yara Pimaru", "Джейн Джинджер", "Наруто Узумаки", "Метал Чел" }

test("ChillZone: the officers' names, Cyrillic and Latin, pass the addon's name checks whole", function()
	for _, name in ipairs(OFFICERS) do
		local full = ns.FullName(name, "ForeverPvP")
		eq(full, name .. "-ForeverPvP", name)
		eq(ns.ShortName(full), name, name)
		eq(ns.Workshop.NameLike(full), true, name)
		eq(ns.Workshop.NameLike(name), true, name)
	end
end)
```

Run: `CHILLZONE_TEST_FILTER="officers' names" luajit tests/run.lua 2>&1 | tail -5`
Expected: `1 passed`. Если какое-то имя не проходит — это баг кириллицы того же рода, что в Step 1: найти проверку (`FullName`/`ShortName` в `ChillZone/Core.lua:100-130`, `NameLike` в `ChillZone/Workshop.lua:262`), исправить подсчётом символов и оставить тест.

Run: `bash scripts/check.sh > $S/check.txt 2>&1; echo "exit $?"` — Expected: `exit 0`.

- [ ] **Step 5: Commit**

```bash
git add ChillZone/Crafters.lua tests/chillzone.lua
git commit -m "Keep Russian profession names on the crafters board

Their 24-letter limit counted bytes, so Кузнечное дело (27) was dropped.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Логотип

**Files:**
- Create: `media/logo/src/chillzone.png` (из присланной картинки VK)
- Create: `scripts/make-logo.py`
- Modify (перезапись): `ChillZone/media/logo64.tga`, `ChillZone/media/logo128.tga`, `ChillZone/media/emblem128.tga`, `docs/logo.png`
- Modify: `scripts/check.sh` (+ проверка после блока borders)

- [ ] **Step 1: Исходник без потерь**

Run:
```bash
mkdir -p media/logo/src
python3 -I -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).convert("L").save(sys.argv[2])' \
  $S/logo-dl/logo-source.jpg media/logo/src/chillzone.png
```
Если файла в scratchpad уже нет — скачать заново в отдельную папку: `curl -s -o <папка>/logo-source.jpg 'https://sun9-87.vkuserphoto.ru/s/v1/ig2/SujDEkk_6KZVt4r5XW-Uoo_AotnBU-sIU8diGTNOX4OlgiolauQ4pkOC2p8CxkFsmwC2MqKbBC4VbOrGNPLuDyVz.jpg?quality=96&as=32x32,48x48,72x72,108x108,160x160,240x240,360x360,480x480,500x500&from=bu&cs=500x0'`.
Expected: `media/logo/src/chillzone.png` 500×500, режим `L`.

- [ ] **Step 2: Скрипт**

`scripts/make-logo.py`:

```python
#!/usr/bin/env python3
"""Builds ChillZone's logo textures from the guild's picture.

The picture (media/logo/src/chillzone.png, black on white, from the guild's VK group) becomes the
addon's gold (ns.COLOR, e6c35c) on transparency, its white parts (the face, the "M") clear:
  ChillZone/media/emblem128.tga   the emblem alone, 128 x 128
  ChillZone/media/logo128.tga     the emblem on the dark square of Olympus's logo, 128 x 128
  ChillZone/media/logo64.tga      the same, 64 x 64
  docs/logo.png                   logo128, for the README (built, never checked: PNG bytes vary)
The TGA files as scripts/make-borders.py writes them (type 2, 32 bits, bottom-left origin).

Usage (needs Pillow):
  python3 scripts/make-logo.py          build them
  python3 scripts/make-logo.py --check  fail unless the .tga files are what it would build
"""
import importlib.util
import io
import os
import sys

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SOURCE = os.path.join(ROOT, "media", "logo", "src", "chillzone.png")
GOLD = (0xE6, 0xC3, 0x5C)
GROUND = (4, 37, 44, 255)  # Olympus's logo square, kept
INK, PAPER = 40, 215       # source grey at or below INK: solid; at or above PAPER: clear (JPEG noise)
FILL = 108 / 128           # the emblem's share of the canvas, as Olympus's (10 to 118 of 128)

_spec = importlib.util.spec_from_file_location("make_borders", os.path.join(ROOT, "scripts", "make-borders.py"))
_borders = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_borders)


def emblem(size):
    grey = Image.open(SOURCE).convert("L")
    alpha = grey.point(lambda v: 255 if v <= INK else 0 if v >= PAPER else (PAPER - v) * 255 // (PAPER - INK))
    x0, y0, x1, y1 = alpha.getbbox()
    side = max(x1 - x0, y1 - y0)
    left, top = (x0 + x1) // 2 - side // 2, (y0 + y1) // 2 - side // 2
    square = alpha.crop((left, top, left + side, top + side))
    inner = round(size * FILL)
    mark = Image.new("RGBA", (inner, inner), GOLD + (0,))
    mark.putalpha(square.resize((inner, inner), Image.LANCZOS))
    out = Image.new("RGBA", (size, size), GOLD + (0,))
    out.alpha_composite(mark, ((size - inner) // 2, (size - inner) // 2))
    return out


def logo(size):
    out = Image.new("RGBA", (size, size), GROUND)
    out.alpha_composite(emblem(size))
    return out


def tga(image):
    w, h = image.size
    raw = image.tobytes()
    return _borders.tga(w, h, [raw[y * w * 4:(y + 1) * w * 4] for y in range(h)])


def png(image):
    buf = io.BytesIO()
    image.save(buf, "PNG")
    return buf.getvalue()


CHECKED = {
    "ChillZone/media/emblem128.tga": lambda: tga(emblem(128)),
    "ChillZone/media/logo128.tga": lambda: tga(logo(128)),
    "ChillZone/media/logo64.tga": lambda: tga(logo(64)),
}
BUILT_ONLY = {"docs/logo.png": lambda: png(logo(128))}


def main(argv):
    check = argv[1:] == ["--check"]
    if argv[1:] and not check:
        raise SystemExit(__doc__)
    stale = []
    for rel, build in sorted(CHECKED.items()) + ([] if check else sorted(BUILT_ONLY.items())):
        data, target = build(), os.path.join(ROOT, rel)
        if check:
            try:
                with open(target, "rb") as f:
                    same = f.read() == data
            except OSError:
                same = False
            if not same:
                stale.append(rel)
        else:
            with open(target, "wb") as f:
                f.write(data)
            print(rel)
    if stale:
        sys.stderr.write("Not what scripts/make-logo.py builds (run it): %s\n" % ", ".join(stale))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 3: Проверка падает, сборка, проверка проходит**

Run: `python3 scripts/make-logo.py --check; echo "exit $?"` — Expected: `exit 1` (в файлах ещё знак Olympus).
Run: `python3 scripts/make-logo.py && python3 scripts/make-logo.py --check; echo "exit $?"` — Expected: 4 пути и `exit 0`.
Посмотреть результат: открыть `docs/logo.png` (Read) — золотой силуэт на тёмно-бирюзовом квадрате.

- [ ] **Step 4: check.sh**

После блока `if [ -f scripts/make-borders.py ]; then … fi` вставить:

```bash

# ChillZone's logo (ChillZone/media/logo*.tga, emblem128.tga): what scripts/make-logo.py builds from
# media/logo/src/chillzone.png (the script changes nothing with --check).
if [ -f scripts/make-logo.py ]; then
	printf 'Checking the logo textures against their source...\n'
	if command -v python3 >/dev/null 2>&1 && python3 -c 'import PIL' >/dev/null 2>&1; then
		PYTHONDONTWRITEBYTECODE=1 python3 scripts/make-logo.py --check
	else
		printf 'python3 with Pillow not found: the logo textures check skipped.\n'
	fi
fi
```

Run: `bash scripts/check.sh > $S/check.txt 2>&1; echo "exit $?"` — Expected: `exit 0`.

- [ ] **Step 5: Commit**

```bash
git add media/logo scripts/make-logo.py scripts/check.sh ChillZone/media/logo64.tga ChillZone/media/logo128.tga ChillZone/media/emblem128.tga docs/logo.png
git commit -m "Draw ChillZone's logo from the guild's picture

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Метаданные, README, UPSTREAM.md

**Files:**
- Modify: `ChillZone/ChillZone.toc`, `ChillZone_Arena/ChillZone_Arena.toc`, `ChillZoneSiteAggregate/ChillZoneSiteAggregate.toc` (если там есть `X-Website`)
- Modify: `LICENSE`, `README.md` (вводная часть)
- Create: `UPSTREAM.md`
- Delete: `docs/olympus-1.jpg` … `docs/olympus-5.jpg`, `docs/curseforge-logo-400.jpg`, `docs/curseforge-logo-400.png`, `docs/RELEASE-1.2.1.md` … `docs/RELEASE-1.2.4.md`

- [ ] **Step 1: TOC**

В `ChillZone/ChillZone.toc`: удалить строку `## X-Curse-Project-ID: 1708200`; `## X-Website:` → `https://github.com/Bezoutoff/ChillZone-addon`; `## Author:` → `ChillZone addon contributors (based on Olympus)`. В `ChillZone_Arena/ChillZone_Arena.toc` и TOC сайдкара — те же `## Author:` и `## X-Website:`.

Run: `git grep -n 'X-Curse-Project-ID\|1708200' -- tests scripts` — если тест или `package.sh` требует этот ID, удалить это требование и указать в сообщении коммита.

- [ ] **Step 2: LICENSE**

После строки `Copyright (c) 2026 Olympus addon contributors` добавить строку `Copyright (c) 2026 ChillZone addon contributors`.

- [ ] **Step 3: README — вводная часть**

Заменить в `README.md` всё от первой строки до первой строки `---` (включительно: логотип, заголовок, абзац про Asmongold, таблица скриншотов, блок Status) на:

```markdown
<p align="center"><img src="docs/logo.png" width="96" alt=""></p>

# ChillZone

**The whole ChillZone network in one window, inside World of Warcraft: Forever.**

ChillZone is a family of guilds on WoW: Forever (Alliance): <Чиллзон> and <Чиллзон Навсегда>. In
game each player only sees the roster of their own guild; this addon adds up every ChillZone guild
live, in a window that looks like Blizzard's Guild window and docks right next to it.

ChillZone is a fork of [Olympus](https://github.com/dnl-gentile/olympus-addon) (MIT). The rest of
this manual is Olympus's with the names changed. Where it differs: the guilds are those the code
names (<Чиллзон>, the King's, and <Чиллзон Навсегда>) and those the author's signed list adds, never
a guild for a word in its name; the King, the Treasurer and the author are named by that signed
list alone; the logo is ChillZone's. See UPSTREAM.md for the commits taken from Olympus since.

> **Status:** a fork in progress, not released yet.

---
```

Run: `git rm docs/olympus-[1-5].jpg docs/curseforge-logo-400.jpg docs/curseforge-logo-400.png docs/RELEASE-1.2.*.md` (после ребрендинга эти файлы называются `docs/chillzone-[1-5].jpg` — удалить по фактическим именам: `git ls-files docs | grep -E 'jpg|RELEASE|curseforge-logo'`).

- [ ] **Step 4: UPSTREAM.md**

```markdown
# Upstream

ChillZone is a fork of Olympus: https://github.com/dnl-gentile/olympus-addon (git remote `upstream`).

Base: `ed7a81e`, Olympus 1.5.1 (2026-11-05).

Commits are taken one by one with `bash scripts/port-upstream.sh <commit>|<from>..<to>`, which
rebrands each patch (`scripts/rebrand.py patch`) and applies it; it adds a row below for each.

| Upstream | ChillZone | Subject |
|---|---|---|
```

Если в задаче 1 оригинал уже падал — добавить после таблицы раздел «Known upstream failures» с именами тестов.

- [ ] **Step 5: Полная проверка**

Run: `bash scripts/check.sh > $S/check.txt 2>&1; echo "exit $?"`
Expected: `exit 0`. Тесты читают `README.md` по разделам (`Section(Doc("README.md"), …)`); если какой-то ищет текст из удалённой вводной части — перенести нужную фразу в новый вводный абзац, а не ослаблять тест.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Describe ChillZone: TOC, license, README intro, upstream log

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Перенос патчей оригинала

**Files:**
- Create: `scripts/port-upstream.sh`

- [ ] **Step 1: Проверка преобразования на уже взятом коммите (должна пройти)**

Run: `git fetch --quiet upstream && for c in $(git log --no-merges --format=%h -15 upstream/main); do if git format-patch -1 --stdout "$c" | python3 scripts/rebrand.py patch | git apply -R --check 2>/dev/null; then echo "ok $c"; else echo "no $c"; fi; done`
Expected: хотя бы несколько `ok` — переименованный патч уже входящего в базу коммита обратно применяется к нашему дереву, значит преобразование путей и текста верно. `no` ожидаемы для коммитов, задевающих то, что мы правили руками (Core.lua, тексты).

- [ ] **Step 2: Скрипт**

`scripts/port-upstream.sh`:

```bash
#!/usr/bin/env bash
# Ports commits of Olympus (the remote "upstream") into ChillZone: each one rebranded by
# scripts/rebrand.py patch, then applied with git am, so it keeps its author, date and message.
#   bash scripts/port-upstream.sh <commit>          one commit
#   bash scripts/port-upstream.sh <from>..<to>      the commits after <from> up to <to> (merges left out)
# Each one ported gets a row in UPSTREAM.md's table; commit that file afterwards.
# A patch that does not apply (it touches what ChillZone changed by hand: the membership, the people,
# the texts about Asmon) stops the run: its rejected hunks are left in *.rej files beside their files
# for a hand merge, then: git add -A && git commit -C <upstream commit>.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" -eq 1 ] || { printf 'Usage: bash scripts/port-upstream.sh <commit>|<from>..<to>\n' >&2; exit 2; }
if ! git diff --quiet || ! git diff --cached --quiet; then
	printf 'The working tree has changes: commit or stash them first.\n' >&2
	exit 1
fi
git fetch --quiet upstream
case "$1" in
	*..*) range=$1 ;;
	*) range="$1^!" ;;
esac
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
git format-patch --quiet -o "$scratch" "$range"
set -- "$scratch"/*.patch
[ -e "$1" ] || { printf 'No commits to port in that range.\n' >&2; exit 1; }
for patch in "$@"; do
	sha=$(sed -n '1s/^From \([0-9a-f]*\) .*/\1/p' "$patch")
	python3 scripts/rebrand.py patch < "$patch" > "$patch.cz"
	if ! git am --quiet "$patch.cz"; then
		git am --abort
		git apply --reject "$patch.cz" || true
		printf '\n%s did not apply cleanly. Merge the *.rej hunks by hand, delete the .rej files, then:\n' "${sha:0:7}" >&2
		printf '  git add -A && git commit -C %s\n' "$sha" >&2
		exit 1
	fi
	printf '| %s | %s | %s |\n' "${sha:0:7}" "$(git rev-parse --short HEAD)" "$(git log -1 --format=%s)" >> UPSTREAM.md
done
printf 'Ported. Record them: git commit -m "Record ported upstream commits" UPSTREAM.md\n'
```

Run: `chmod +x scripts/port-upstream.sh && bash -n scripts/port-upstream.sh && bash scripts/port-upstream.sh; echo "exit $?"`
Expected: строка Usage и `exit 2`.

- [ ] **Step 3: Пробный перенос**

На временной ветке откатить один уже взятый коммит оригинала (из `ok` в Step 1) и перенести его обратно скриптом:

```bash
git switch -c port-smoke
c=<первый хеш с ok из Step 1>
git format-patch -1 --stdout "$c" | python3 scripts/rebrand.py patch | git apply -R
git commit -qam "smoke: undo $c"
bash scripts/port-upstream.sh "$c"
git diff HEAD~2 --stat -- . ':!UPSTREAM.md'
```

Expected: `Ported.`, в `UPSTREAM.md` новая строка таблицы, последний `git diff` пуст (дерево вернулось к исходному). Затем: `git checkout -- UPSTREAM.md; git switch rebrand && git branch -D port-smoke`.

- [ ] **Step 4: Commit**

```bash
git add scripts/port-upstream.sh
git commit -m "Add the upstream porting script

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Сборка и передача

- [ ] **Step 1: Полная проверка**

Run: `bash scripts/check.sh > $S/final.txt 2>&1; echo "exit $?"; tail -3 $S/final.txt`
Expected: `exit 0`, `N passed, 0 failed` (N ≈ базовое число из задачи 1 − удалённые тесты нечёткого правила + новые тесты ChillZone).

- [ ] **Step 2: Пакет**

Run: `bash scripts/package.sh && ls dist/ && unzip -l dist/ChillZone-*.zip | awk '{print $4}' | cut -d/ -f1 | sort -u`
Expected: zip `dist/ChillZone-1.5.1.zip`; верхние папки `ChillZone`, `ChillZone_Arena`, `ChillZoneSiteAggregate`. Проверить, что в zip нет `Markets.lua`, `MarketBank.lua`, `Bicho.lua` (ставки) и нет `CouncilList.lua`: `unzip -l dist/ChillZone-*.zip | grep -E 'Markets|MarketBank|Bicho|CouncilList'` — пусто.

- [ ] **Step 3: Отчёт пользователю**

Сообщить: что сделано (по коммитам), результат `check.sh`, где zip, что `~/.chillzone/council-key.json` нужно положить в бэкап, и чек-лист проверки в игре из спецификации (раздел 5). Для публикации — `git push -u origin rebrand` требует входа: предложить `! gh auth login`, затем запушить и (по желанию пользователя) открыть PR `rebrand` → `main` в форке.

- [ ] **Step 4: Убрать временные файлы**

Run: `rm -rf $S/*` и `rm -rf dist` (если пользователь не попросил оставить zip — спросить).
