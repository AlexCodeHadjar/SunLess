# SunLess — карта проекта для Claude

Карточная игра на Godot 4.7.2 по «Shadow Slave» (фанатская, некоммерческая). Владелец пишет по-русски, решения по механике принимает сам (спрашивать вариантами), после каждой фазы — коммит и push в `gameplay/missions` (GitHub AlexCodeHadjar/SunLess). Контекст владельца и история — `HANDOFF.md`; механика миссий — `docs/15`; план текущих фаз — `docs/16`.

## Как работать экономно

- **Сначала этот файл, потом `python tools/ctx.py …`** — справки по данным без чтения JSON целиком:
  `ctx.py missions [глава]` · `ctx.py mission MS05` · `ctx.py heroes` · `ctx.py hero P03` · `ctx.py enemy M02` ·
  `ctx.py tag Дуэль` (где используется) · `ctx.py locations [глава]` · `ctx.py shops` · `ctx.py fields MS05` (ключи миссии).
- Код читать по функции (`grep -n "func имя"`, затем `Read` с offset/limit), не файл целиком. Крупные файлы: `combat_screen.gd` (1200), `combat_session.gd`, `card_inspector.gd`, `mission_game.gd`, `mission_window.gd`, `card_aura.gd`, `card_view.gd` (по 550–670).
- Правки данных — python-скриптом в scratchpad (json.load → изменить → `json.dumps(ensure_ascii=False, indent=1)` + `\n`, `newline="\n"`). Bash heredoc портит `\n` и кавычки в GDScript — длинные правки писать через Write в файл-скрипт.
- Новая механика — **новый файл** `core/rules/<механика>.gd` (class_name, static-функции) + свой тест `tests/test_<механика>.gd` (добавить в `SUITES` в `tests/run_tests.gd`). Интерфейс механики — свой файл в `scenes/missions/`.
- GDScript: табы, типы; `:=` не выводит тип из Variant/Dictionary — писать `var x: Тип =`. `--check-only` без автозагрузок врёт — проверять тестами (есть тест компиляции всех скриптов).

## Команды

```bash
G="/d/Godot_v4.7.2-stable_win64_console.exe"
"$G" --headless --path . --import                      # после новых файлов/ассетов
"$G" --headless --path . -s res://tests/run_tests.gd   # тесты (+ бот проходит демо 120 раз)
"$G" --path . --resolution 1920x1080 -- --mshots=<папка>   # автоснимки: tools/mission_shots.gd
python tools/ctx.py …                                  # справки по данным
python tools/editor/server.py                          # редактор контента (http://127.0.0.1:8765)
```

## Где что (код)

| Область | Файлы |
|---|---|
| Данные → память | `core/content/content.gd` (грузит `data/`), `content_validator.gd` (правила данных; ошибка = игра не стартует) |
| Состояние прохождения | `core/state/run_state.gd` (всё сохраняемое; `SAVE_VERSION`), `autoload/save_service.gd` |
| API для интерфейса | `autoload/game_state.gd` (запуск, тик часов, отряды, магазин, главы) |
| Миссии | `core/rules/mission_flow.gd` (открытие, герои, отряды, часы, действия, главы), `mission_forecast.gd` (слова прогноза), `mission_resolver.gd` (этапы, бой, последствия, отдых) |
| Правила | `chance_calculator.gd`, `stat_resolver.gd` (характеристики + бонусы по тегам), `condition_checker.gd`, `effect_applier.gd` (команды `cmd`), `injury_rules.gd` (травмы/износ/смерть), `trauma_rules.gd`, `wear_rules.gd`, `shop_rules.gd`, `atmosphere.gd` (небо) |
| Бой | `core/combat/combat_session.gd` (автобой, ledger — расчёт силы); экран — `scenes/combat/combat_screen.gd` (только просмотр) |
| Экран карты | `scenes/missions/mission_game.gd` (карта, герои, небо, окна), `mission_marker.gd` (карта миссии + кольцо), `mission_window.gd` (брифинг → прибытие → отчёт), `shop_*.gd`, `drop_zone.gd` |
| Карты | `scenes/cards/card_view.gd` (отрисовка, арт `art/cards/<ID>.webp`), `card_inspector.gd` (планшет), `card_aura.gd` (облик по тегам) |
| Фон | `scenes/map/map_backdrop.gd` (рисунки неба `art/regions/<регион>_<небо>.webp` или процедурный), `map_life.gd` |
| Общее UI | `ui/theme/palette.gd`, `ui_theme.gd` (`UITheme.label/box/font/plural`), `scenes/vfx/vfx.gd` |

## Где что (данные `data/`)

| Файл | Что | Ключевые поля |
|---|---|---|
| `missions/ch1_*.json` | Первый Кошмар (обучение) | см. docs/15 §13, §17 |
| `missions/ch2_academy.json` | Академия (обучение) | docs/15 §18 |
| `locations.json` | места глав на карте | `chapter`, `region`, `pos`, `random{pool,every,after_missions}` |
| `shops.json` | магазины глав | `stock[{card,price?}]`, `slots`, `refresh_every` |
| `characters.json` | герои | `stats` или `stages`, `tags`, `support_tags`, `traits[].bonuses`, `start_abilities`, `status` (temporary уходят в конце главы, если не куплены) |
| `enhancements.json`, `abilities.json`, `traumas.json` | карты | `bonuses[{stat,value,tags}]` |
| `combat/*.json` | бой: теги, симбиозы, конфликты, поля, противники, приёмы | генерируются `tools/gen_combat_data.py` из docs/12 + `editor_overrides.json`; `tactics.json` правится вручную |
| `tags.json` | теги проверок (контекст: combat, stealth…) | |
| `lore.json` | «По книге» (tools/gen_lore.py) | |

**Миссия (кратко):** `id, location, type(story|side|random), title, briefing, rumors[{text с [намёком], tag}], threat 1–5, duration 5–15, rest, squad{min,max}, requires_heroes, exclude_heroes, enemies, field, known_tags, hidden_tags, context, trauma_pool, arrival, actions[], on_complete, next[], unlock{after_missions, after_all}, start, end_chapter, next_chapter, sky(eclipse|blood_moon)`.
Ещё у миссии: `exclusive[]` (миссия-выбор, взаимно), `expires` (с, побочные/случайные), `boss{phases[{field,sky,text}]}` (заходы босса; фаза — `state.missions[id].phase`).
**Действие:** `id, label, text, story, retreat, guaranteed, requires_any(теги), requires_hero, conditions, cost{shards, sacrifice(карта), sacrifice_tag, rest, trauma}, stages[1–3]{name, req{stat:n}|combat{enemies,field}|auto, tags, ok/partial/fail, fork{text, options[{id,label,text,then,stages,on_success,keep}]}}, on_success/on_partial/on_failure[cmd…]`. Резолвер: `resolve` → может вернуть `fork`; `resume(option)`; `resolve_through` проходит развилки первым вариантом.

## Главы

| id | Глава | Роль | Данные |
|---|---|---|---|
| `nightmare` | Первый Кошмар | обучение: базовый цикл | `ch1_*`, регион `mountain_pass` (4 фона неба) |
| `academy` | Академия | обучение: новые механики на простых примерах | `ch2_academy`, регион `academy` (процедурный) |
| `shore` | Забытый Берег (E19–E32) | **основной геймплей** начинается здесь | в работе (docs/16) |
| — | Древо Души (E33–E48) | следующая | — |

## Правила, которые нельзя ломать без владельца

Смерть навсегда; финал Кошмара — только Санни; купленные спутники остаются после главы; автобой без вмешательства; прогноз — шесть слов; маны нет; магазин раз в 7 миссий; раны врага сохраняются; связи тегов открываются навсегда. Полный список — HANDOFF.md «Решения владельца» и docs/15 §11, §19; решения по фазам 7+ — docs/16.
