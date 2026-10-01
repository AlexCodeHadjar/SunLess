# SunLess — карта проекта для Claude

Карточная игра на Godot 4.7.2 по «Shadow Slave» (фанатская, некоммерческая). Владелец пишет по-русски, решения по механике принимает сам (спрашивать вариантами), после каждой фазы — коммит и push в `gameplay/missions` (GitHub AlexCodeHadjar/SunLess). Контекст владельца и история — `HANDOFF.md`; механика миссий — `docs/15`; план текущих фаз — `docs/16`.

## Как работать экономно

- **Сначала этот файл, потом `python tools/ctx.py …`** — справки по данным без чтения JSON целиком:
  `ctx.py missions [глава]` · `ctx.py mission MS05` · `ctx.py heroes` · `ctx.py hero P03` · `ctx.py enemy M02` ·
  `ctx.py tag Дуэль` (где используется) · `ctx.py locations [глава]` · `ctx.py shops` · `ctx.py fields MS05` (ключи миссии).
- Код читать по функции (`grep -n "func имя"`, затем `Read` с offset/limit), не файл целиком. Крупные файлы: `combat_screen.gd` (1200), `combat_session.gd`, `card_inspector.gd`, `mission_game.gd`, `mission_window.gd`, `card_aura.gd`, `card_view.gd` (по 550–670).
- Правки данных — python-скриптом в scratchpad (json.load → изменить → `json.dumps(ensure_ascii=False, indent=1)` + `\n`, `newline="\n"`). Bash heredoc портит `\n` и кавычки в GDScript — длинные правки писать через Write в файл-скрипт.
- **Каждая новая или изменённая механика — вместе с обучением игрока** (требование владельца): подсказки `data/tutorial.json` `{id, event, chapter, title, text, target}`, событие (`GameState.tutorial(...)` / `TutorialRules.state_events`), цель подсветки (`HintTargets`); устаревшие тексты подсказок переписать. Проверять автоснимком без `--nohints`.
- Новая механика — **новый файл** `core/rules/<механика>.gd` (class_name, static-функции) + свой тест `tests/test_<механика>.gd` (добавить в `SUITES` в `tests/run_tests.gd`). Интерфейс механики — свой файл в `scenes/missions/`.
- GDScript: табы, типы; `:=` не выводит тип из Variant/Dictionary — писать `var x: Тип =`. `--check-only` без автозагрузок врёт — проверять тестами (есть тест компиляции всех скриптов).

## Команды

```bash
G="/d/Godot_v4.7.2-stable_win64_console.exe"
"$G" --headless --path . --import                      # после новых файлов/ассетов
"$G" --headless --path . -s res://tests/run_tests.gd   # тесты (+ бот проходит демо 120 раз)
"$G" --headless --path . -s res://tests/run_tests.gd -- --only=test_gates   # только наборы с этим именем
python tools/import_map_kit.py academy                  # комплект карты (PNG) → art/map/<регион>/ webp
"$G" --path . --resolution 1920x1080 -- --mshots=<папка>   # автоснимки: tools/mission_shots.gd
python tools/ctx.py …                                  # справки по данным
python tools/editor/server.py                          # редактор контента (http://127.0.0.1:8765), вкладка «Сила» — баланс и статистика боёв
```

## Где что (код)

| Область | Файлы |
|---|---|
| Данные → память | `core/content/content.gd` (грузит `data/`), `content_validator.gd` (правила данных; ошибка = игра не стартует) |
| Состояние прохождения | `core/state/run_state.gd` (всё сохраняемое; `SAVE_VERSION`), `autoload/save_service.gd` |
| API для интерфейса | `autoload/game_state.gd` (запуск, тик часов, отряды, магазин, главы) |
| Миссии | `core/rules/mission_flow.gd` (открытие, герои, отряды, часы, действия, главы), `mission_forecast.gd` (слова прогноза), `mission_resolver.gd` (этапы, бой, последствия, отдых) |
| Правила | `chance_calculator.gd`, `stat_resolver.gd` (характеристики + бонусы по тегам), `condition_checker.gd`, `effect_applier.gd` (команды `cmd`), `injury_rules.gd` (износ, гибель), `edge_rules.gd` (грань смерти вместо травм: поражение → на грань, на грани → бросок смерти 35%; лагерь/удачная миссия снимают), `wear_rules.gd`, `shop_rules.gd`, `atmosphere.gd` (небо); живой отряд — `trust_rules.gd` (доверие пар), `bond_rules.gd` (связки, `data/bonds.json`), `psyche_rules.gd` (психика 100→0, кризис: паника / подъём духа, поступки героев, `data/psyche.json`); рост — `growth_rules.gd` (опыт тегов, эволюции/мутации, `data/tag_growth.json`); `service_rules.gd` (заточка, починка у торговца); `camp_rules.gd` (лагерь: койки, доска слухов); `onslaught_rules.gd` (Натиск Кошмара), `loot_rules.gd` (Воспоминания-добыча: шанс после боя по силе врагов, выбор 1 из 3, уровни карт, `data/loot.json`), `modifier_rules.gd` (модификаторы миссий: 1–2 у побочных и случайных основных глав), `day_rules.gd` (дни и неделя по фазам, лагерь-стоянка у последнего места, соседние места, усталость за выходы, ночь: нападения, отдых, вода; `data/days.json`; docs/16 §12), `travel_rules.gd` (переходы по карте-плану: маршрут по тропам мимо воды, шаги дня `steps_free`, марш-бросок, лавку — насквозь; docs/17 §2), `day_planner.gd` (планировщик дня: утром не меньше `min_options` миссий в досягаемости — иначе местные встречи `random.local`; дела лагеря Разведка/Сбор/Дозор; docs/17 §4–6), `gate_rules.gd` (угрозы-точки карты-плана: прорывы Академии, Врата города — сигнал → прорыв → рой по тропам к цели → повреждения → ремонт, Тревога; настройки `maps/<регион>.json → threat`, команда `threat`), `map_rules.gd` («Карта Спящего»: облик мест, новые места на площадках, следы `map_mark`/`emerge`, туман; docs/16 §11.6), `deck_rules.gd` (колода событий главы: часть побочных и случайных миссий на прохождение, цепочки, `data/deck.json`), `tide_rules.gd` (прилив Берега: команда `tide`, места по `height` low/mid/high тонут, застигнутый отряд бежит, отлив — новые проходы и встречи; docs/16 §11.1), `mission_debrief.gd` (разбор «что решило исход»), `journal_rules.gd` (бестиарий, слухи); `memory_rules.gd` (особые навыки карт в бою: условие на тегах → эффект, вместо приёмов); `tutorial_rules.gd` (механики по главам `UNLOCK`, подсказки `data/tutorial.json`) |
| Бой | `core/combat/combat_session.gd` (автобой, ledger — расчёт силы, запас сторон), `core/combat/strikes.gd` (удары: оружие, броня, окружение, прогноз `odds`; данные `data/combat/weapons.json`); экран — `scenes/combat/combat_screen.gd` (только просмотр); калибровка — `tools/strike_calib.gd`, статистика боёв для редактора — `tools/combat_stats.gd` |
| Экран карты | `scenes/missions/mission_game.gd` (карта, герои, небо, окна), `mission_marker.gd` (карта миссии + кольцо), `mission_window.gd` (брифинг → прибытие → отчёт), `shop_*.gd`, `drop_zone.gd`, `squad_life_ui.gd` (значки доверия/паники, строка брифинга), `camp_window.gd` (лагерь), `tide_layer.gd` (вода прилива на карте), `memory_choice.gd` (выбор Воспоминания 1 из 3), `journal_window.gd` (журнал), `hint_popup.gd` (подсказки-прожектор), `hint_targets.gd` (цели подсказок); `scenes/vfx/crisis_fx.gd` (момент кризиса психики) |
| Карты | `scenes/cards/card_view.gd` (отрисовка, арт `art/cards/<ID>.webp`), `card_inspector.gd` (планшет), `card_aura.gd` (облик по тегам) |
| Карта-план | `scenes/map/sleeper_map.gd` (основа, вода-шейдер по высотам, виньетки мест, тропы, туман неизвестного, небо цветом; основа покрывает всё окно с запасом — `set_pan`/`focus`, сдвиг мышью ловит `mission_game._gui_input`; `sleeper_water/fog.gdshader`) — для глав с `data/maps/<регион>.json`, арт `art/map/<регион>/` |
| Фон | `scenes/map/map_backdrop.gd` (рисунки неба `art/regions/<регион>_<небо>.webp` или процедурный), `map_life.gd` |
| Разработчику | `core/dev/autoplay.gd` (бот-игрок: тесты баланса и «к началу главы»), `scenes/menu/dev_panel.gd` (меню → «Разработчик»: начало любой главы, свои точки; F5 на карте — записать точку; только отладочная сборка) |
| Общее UI | `ui/theme/palette.gd`, `ui_theme.gd` (`UITheme.label/box/font/plural`), `scenes/vfx/vfx.gd` |

## Где что (данные `data/`)

| Файл | Что | Ключевые поля |
|---|---|---|
| `missions/ch1_*.json` | Первый Кошмар (обучение) | см. docs/15 §13, §17 |
| `missions/ch2_academy.json` | Академия (обучение) | docs/15 §18; прорывы BA01–BA27 и карта `maps/academy.json` — `tools/gen_academy_map.py` (лагеря корпусов, места admin/range/lab) |
| `missions/ch3_shore.json` | Забытый Берег | генерируется `tools/gen_shore.py` (docs/16 §9в); колода событий (RS05–10, SS04–06, цепочки SC01–06) — `tools/shore_deck.py`; местные встречи LS01–LS17 — `tools/shore_local.py` |
| `maps/<регион>.json` | карта-план главы (docs/16 §11.6) | `places{at,size,states}`, `variants`, `sockets` (площадки появляющихся мест), `paths`, `levels` (вода по высотам), `view_top`, `foot` |
| `days.json` | дни, неделя, лагерь (docs/16 §12) | `phases{sky, tide, fatigue_mult, sortie_psyche}`, `weeks{регион: [[фаза, дней]]}`, `fatigue`, `max_sorties`, `move_psyche`, `camp_default`, `night_attack`, `flooded_camp`; у мест — `camp{rest, beds, danger, services}` |
| `days.json` (добавлено, docs/17) | шаги и планировщик | `steps_free`, `march_psyche`, `min_options`, `tasks{scout, forage, watch}` |
| `deck.json` | колода событий глав (docs/16 §11.4) | `{глава: [{name, pick, min_chains, units: [id | {id, name, chain, missions}]}]}`; выпавшее — `state.flags.deck` |
| `locations.json` | места глав на карте | `chapter`, `region`, `pos`, `height` (прилив: low/mid/high), `random{pool,every,after_missions}` |
| `shops.json` | магазины глав | `stock[{card,price?}]`, `slots`, `refresh_every`, `services[heal,sharpen,unwear]` |
| `characters.json` | герои | `stats` или `stages`, `tags`, `support_tags`, `traits[].bonuses`, `start_abilities`, `status` (temporary уходят в конце главы, если не куплены) |
| `enhancements.json`, `abilities.json` | карты (у усилений `edge_shield`, `loot` — добыча 1 из 3, `rarity` common/rare/epic/legendary; у способностей `edge_soft`) | `bonuses[{stat,value,tags}]`, `memory{name, cond, text, phase, when, effect, once, wear, support}` — особый навык (docs/16 §9д) |
| `combat/*.json` | бой: теги, симбиозы, конфликты, поля, противники, приёмы | генерируются `tools/gen_combat_data.py` из docs/12 + `editor_overrides.json`; приёмов больше нет — особые навыки карт в поле `memory` усилений и способностей (`memory_rules.gd`) |
| `story.json` | сюжетные окна по главам (вступление, переходы) | `id`=глава, `pages[{image, crop:card, side:left|right, title, text}]` — `StoryRules`, `scenes/story/story_screen.gd` |
| `modifiers.json` | модификаторы миссий (docs/16 §11.2, `modifier_rules.gd`) | `chapters`, `types`, `two_chance`, `list[{id, name, tone, needs, enemy_tags, field_tags, enemy_power, extra_enemy, loot_mult, bonus_shards, threat, memory_bonus, expires_mult, check}]`; выпавшие — `state.missions[id].mods` |
| `psyche.json` | реплики героев в кризисе психики | `{panic, uplift, despair, blame, break, scar, rally, bond, insight: [строки с {name} {other} {card}]}` |
| `bonds.json` | связки героев | `heroes[2], name, text, effect{reveal, stat, combat, quarrel}, min_trust` |
| `onslaught.json` | натиск по главам | `chapter, first_after, every[от,до], pool` (миссии `type: onslaught` с `expires`, `on_expire`, `expire_panic`) |
| `tag_growth.json` | рост тегов героев | `id`=тег, `grow[check,combat,panic,any]`, `check_tags`, `stat`, `evo`/`mut` {name, text, эффекты — список ключей в шапке growth_rules.gd} |
| `tags.json` | теги проверок (контекст: combat, stealth…) | |
| `lore.json` | «По книге» (tools/gen_lore.py) | |

**Миссия (кратко):** `id, location, type(story|side|random|onslaught), title, briefing, rumors[{text с [намёком], tag}], threat 1–5, duration 5–15, rest (не используется), squad{min,max}, requires_heroes, exclude_heroes, enemies, field, known_tags, hidden_tags, context, arrival, actions[], on_complete, next[], unlock{after_missions, after_all}, start, end_chapter, next_chapter, sky(eclipse|blood_moon)`.
Ещё у миссии: `exclusive[]` (миссия-выбор, взаимно), `expires` (с, побочные/случайные), `boss{phases[{field,sky,text}]}` (заходы босса; фаза — `state.missions[id].phase`).
**Действие:** `id, label, text, story, retreat, guaranteed, requires_any(теги), requires_hero, conditions, cost{shards, sacrifice(карта), sacrifice_tag, rest(психика), edge(исполнитель — на грань)}, stages[1–3]{name, req{stat:n}|combat{enemies,field,spar}|watch{hero,enemies,field}|auto, tags, ok/partial/fail, fork{text, options[{id,label,text,then,stages,on_success,keep}]}}, on_success/on_partial/on_failure[cmd…]`. Резолвер: `resolve` → может вернуть `fork`; `resume(option)`; `resolve_through` проходит развилки первым вариантом.

## Главы

| id | Глава | Роль | Данные |
|---|---|---|---|
| `nightmare` | Первый Кошмар | обучение: базовый цикл | `ch1_*`, регион `mountain_pass` (4 фона неба) |
| `academy` | Академия | обучение: новые механики на простых примерах | `ch2_academy`, регион `academy` (карта-план кампуса, прорывы `gate_rules.gd`; Натиска нет) |
| `shore` | Забытый Берег (E19–E32) | **основной геймплей** начинается здесь | `ch3_shore` из `tools/gen_shore.py` (не править JSON руками), регион `forgotten_shore` (5 небес, с `storm`) |
| — | Древо Души (E33–E48) | следующая | — |

## Правила, которые нельзя ломать без владельца

Смерть навсегда (травм нет — грань смерти); ход — день, отдых только ночью в лагере-стоянке (docs/16 §12); шаги дня и «без тупиков» — docs/17 (проверка `tests/test_travel.gd`: пустых утр 0); финал Кошмара — только Санни; купленные спутники остаются после главы; автобой без вмешательства (приёмов нет — навыки карт срабатывают сами); прогноз — шесть слов; маны нет; магазин раз в 7 миссий; раны врага сохраняются; связи тегов открываются навсегда. Полный список — HANDOFF.md «Решения владельца» и docs/15 §11, §19; решения по фазам 7+ — docs/16.
