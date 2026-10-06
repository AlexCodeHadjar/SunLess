# SunLess — карта проекта для Claude

Карточная игра на Godot 4.7.2 по «Shadow Slave» (фанатская, некоммерческая). **Ветка `gameplay/figure` — экспериментальное передвижение фигурой (docs/18); откат — ветка `gameplay/missions`.** Владелец пишет по-русски, решения по механике принимает сам (спрашивать вариантами), после каждой фазы — коммит и push в `gameplay/missions` (GitHub AlexCodeHadjar/SunLess). Контекст владельца и история — `HANDOFF.md`; механика миссий — `docs/15`; план текущих фаз — `docs/16`.

## Карты-планы — через редактор карт (решение владельца 05.10)

Любая работа с картой главы (`data/maps/<регион>.json`, места региона в `locations.json`, `art/map/<регион>/`) —
**через редактор карт** `../SunLessMapEditor` (репозиторий AlexCodeHadjar/sunless-map-editor), а не правкой JSON и
не скриптами: он проверяет карту правилами `content_validator.gd`, считает маршруты как игра, пишет файлы в формате игры
(только изменённое, с резервной копией) и не даёт занять код места другого региона.
Агенту — команда `cli-anything-sunless-map --json …` (skill `.claude/skills/cli-anything-sunless-map/SKILL.md`):
`project open-game --region R -o R.mapproj` → `place/path/socket/map …` или `batch ops.json` → `check` →
`preview capture --recipe overview` (посмотреть PNG) → `export --dry-run` → `export --reimport` → `game-shot` (карту рисует игра).
Карты, которые генерируют скрипты `tools/gen_*.py`, после правки в редакторе перегенерировать нельзя без переноса правок в скрипт — сначала спросить владельца.

## Как работать экономно

- **Сначала этот файл, потом `python tools/ctx.py …`** — справки по данным без чтения JSON целиком:
  `ctx.py missions [глава]` · `ctx.py mission MS05` · `ctx.py heroes` · `ctx.py hero P03` · `ctx.py enemy M02` ·
  `ctx.py tag Дуэль` (где используется) · `ctx.py locations [глава]` · `ctx.py shops` · `ctx.py fields MS05` (ключи миссии).
- Код читать по функции (`grep -n "func имя"`, затем `Read` с offset/limit), не файл целиком. Крупные файлы: `combat_screen.gd` (1200), `combat_session.gd`, `card_inspector.gd`, `mission_game.gd`, `mission_window.gd`, `card_aura.gd`, `card_view.gd` (по 550–670).
- Правки данных — python-скриптом в scratchpad (json.load → изменить → `json.dumps(ensure_ascii=False, indent=1)` + `\n`, `newline="\n"`). Bash heredoc портит `\n` и кавычки в GDScript — длинные правки писать через Write в файл-скрипт.
- **Каждая новая или изменённая механика — вместе с обучением игрока** (требование владельца): подсказки `data/tutorial.json` `{id, event, chapter, title, text, target}`, событие (`GameState.tutorial(...)` / `TutorialRules.state_events`), цель подсветки (`HintTargets`); устаревшие тексты подсказок переписать. Проверять автоснимком без `--nohints`.
- Новая механика — **новый файл** `core/rules/<механика>.gd` (class_name, static-функции) + свой тест `tests/test_<механика>.gd` (добавить в `SUITES` в `tests/run_tests.gd`). Интерфейс механики — свой файл в `scenes/missions/`.
- GDScript: табы, типы; `:=` не выводит тип из Variant/Dictionary — писать `var x: Тип =`.
- **Промты для генерации артов** (решение владельца 03.10): к промтам карт — всегда шаблон
  `docs/assets/cards/templates` (пустая обложка 7:12 и её настройки) и образцы готовых карт; ко всем промтам —
  ссылки на материалы-образцы из проекта (лучше и картинками в документе); фишки на карте — 4 ракурса.
  Пример — `tools/gen_boss_prompts.py`, `tools/gen_skirmish_docs.py`; Word без сторонних библиотек — `tools/docx_lib.py`
  (абзацы, таблицы, картинки внутри документа, ссылки на файлы проекта, перевод Markdown → Word).
- **Все материалы игры — в проекте** (просьба владельца 05.10): игра берёт картинки только из `res://` (art/, audio/),
  исходники — в `docs/assets/`; инструменты импорта читают исходники из проекта, а не из папок Codex/загрузок.
  Новый комплект от владельца — сначала скопировать в `docs/assets/…`, потом импортировать. Комплекты карт-планов —
  `docs/assets/kits/` (~600 МБ, в git не входят — решение владельца 05.10; Godot их не импортирует — `docs/.gdignore`).
- Производительность (docs/21): ничего тяжёлого в `_process` — экран обновляется по сигналам (`_queue_refresh`) и
  «слепку» состояния; досягаемость многих событий — `FigureRules.reach_all` (один обход графа); производное из данных —
  в `content.memo`; туман — маска в своей текстуре. После правок экрана карты — замер `--mshots-from=perf`. `--check-only` без автозагрузок врёт — проверять тестами (есть тест компиляции всех скриптов).

## Команды

```bash
G="/d/Godot_v4.7.2-stable_win64_console.exe"
"$G" --headless --path . --import                      # после новых файлов/ассетов
"$G" --headless --path . -s res://tests/run_tests.gd   # тесты (+ бот проходит демо 120 раз)
"$G" --headless --path . -s res://tests/run_tests.gd -- --only=test_gates   # только наборы с этим именем
python tools/import_map_kit.py academy                  # комплект карты (PNG) → art/map/<регион>/ webp
"$G" --path . --resolution 1920x1080 -- --mshots=<папка>   # автоснимки: tools/mission_shots.gd (+ --mshots-from=ch4 | timeline | figure | events | labels | icons | chatter | quests | mods | resize | live | bosses | perf — замер кадра и тяжёлых функций, docs/21)
python tools/gen_figure.py                              # фигура: режим в days.json и подсказки T90–T96
python tools/gen_chatter.py                             # мысли и реплики героев → data/chatter.json (docs/19)
python tools/gen_quests.py                              # цели глав для заданий → data/quests.json (docs/20)
python tools/gen_wanderers.py                           # бродячие боссы → data/wanderers.json и события (docs/22)
python tools/gen_core.py                                # испытания души → data/missions/trials.json (docs/23)
python tools/import_wanderers.py                        # картинки боссов из docs/assets/art/wanderers → art/ (docs/22)
python tools/gen_skirmish_docs.py                       # «Схватка» (docs/24): Word-ТЗ из docs/24 и промты артов боя → docs/*.docx
python tools/skirmish_mockup.py                         # макет экрана «Схватки» → docs/assets/art/combat/mockup_skirmish.png
python tools/gen_skirmish.py                            # «Схватка»: навыки, свойства тегов, враги, свет → data/combat/skirmish.json
"$G" --headless --path . -s res://tools/skirmish_sim.gd -- --n=50   # «Схватка»: бои ИИ против ИИ по составам — победы, раунды, грань, гибель (--enemies — каждый враг → tools/editor/skirmish_stats.json)
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
| Правила | `chance_calculator.gd`, `stat_resolver.gd` (характеристики + бонусы по тегам), `condition_checker.gd`, `effect_applier.gd` (команды `cmd`), `injury_rules.gd` (износ, гибель), `edge_rules.gd` (грань смерти вместо травм: поражение → на грань, на грани → бросок смерти 35%; лагерь/удачная миссия снимают), `wear_rules.gd`, `shop_rules.gd`, `atmosphere.gd` (небо); живой отряд — `trust_rules.gd` (доверие пар), `bond_rules.gd` (связки, `data/bonds.json`), `psyche_rules.gd` (психика 100→0, кризис: паника / подъём духа, поступки героев, `data/psyche.json`); рост — `growth_rules.gd` (опыт тегов, эволюции/мутации, `data/tag_growth.json`); `service_rules.gd` (заточка, починка у торговца); `camp_rules.gd` (лагерь: койки, доска слухов); `onslaught_rules.gd` (Натиск Кошмара), `loot_rules.gd` (Воспоминания-добыча: шанс после боя по силе врагов, выбор 1 из 3, уровни карт, `data/loot.json`), `modifier_rules.gd` (модификаторы миссий: 1–2 у побочных и случайных основных глав), `day_rules.gd` (дни и неделя по фазам, лагерь-стоянка у последнего места, соседние места, усталость за выходы, ночь: нападения, отдых, вода; `data/days.json`; docs/16 §12), `figure_rules.gd` (**фигура, docs/18**: с Академии отряд — каменная фигура главного героя; где фигура — там лагерь; день — две половины `half` (флаг `figure_half`), действие — полдня `spend`: шаг на соседний участок `move`, событие там, где фигура (`end_after_event`, флаг `event_done` ставит резолвер), дело лагеря `task`, ожидание `wait`; вторая половина — ночь (`is_night`); прыжка нет; режим — `days.json movement` = figure | steps, тесты старых шагов — `state.flags.movement = "steps"`), `travel_rules.gd` (переходы по карте-плану: маршрут по тропам мимо воды, шаги дня `steps_free`, марш-бросок, лавку — насквозь; docs/17 §2), `day_planner.gd` (планировщик дня: утром не меньше `min_options` миссий в досягаемости — иначе местные встречи `random.local`; дела лагеря Разведка/Сбор/Дозор; docs/17 §4–6), `gate_rules.gd` (угрозы-точки карты-плана, `threat.kind`: breach — прорывы Академии: сигнал → пролом → рой к цели → повреждения → ремонт; gate — Врата Города: предвестие → открываются ночью → волна каждую ночь в квартал, где больше людей → повреждён/разрушен → закрыты → шрам, ранги (модификаторы gate_rankN), эвакуация, взорванный мост, паника 0–100, Тревога при двух Вратах, сюжет по закрытым Вратам `unlock.gates_closed`; настройки `maps/<регион>.json → threat`, команда `threat`), `map_rules.gd` («Карта Спящего»: облик мест, новые места на площадках, следы `map_mark`/`emerge`, туман; docs/16 §11.6), `map_event_rules.gd` (следы событий на карте-плане — всё из `maps/<регион>.json`: `event_states` облики по фазе/неделе/лагерю, `place_decals`/`path_decals` метки у мест и полосы на тропах, `mod_decals` по модификаторам встреч, `traces` следы на дни — отступили, погибли (+ Могилы Спящих), ночное нападение, шторм; `haze`, `edge_glow`, `storm_band`), Глава 4: `terrain_rules.gd` (местность: сети троп бури `path_sets` — буря меняет тропы и прячет открытое, хрупкий мост `fragile`, опасный спуск `risky`, Чёрная вода `water_paths` — только с лодкой `flags.boat` и в `water_phases`, котловины и островки `emerge_groups`, облик по фазе `phase_states`, завалы `rubble`, дань лагеря `camp.tribute`; команда `terrain`), `zone_rules.gd` (зоны: гнев Владыки шире ночью, Очарование Древа — 3 ночи и отряд не уходит, территории хозяев растут по ночам; `unlock.zones_cleared`; команда `zone`), `mover_rules.gd` (подвижные угрозы: Демон идёт к лагерю, приманка-огонь, сцепка с хозяином зоны, охотники на шум боя, патрули; ночью у лагеря — испытание; команда `mover`), `deck_rules.gd` (колода событий главы: часть побочных и случайных миссий на прохождение, цепочки, `data/deck.json`), `tide_rules.gd` (прилив Берега: команда `tide`, места по `height` low/mid/high тонут, застигнутый отряд бежит, отлив — новые проходы и встречи; docs/16 §11.1), `mission_debrief.gd` (разбор «что решило исход»), `journal_rules.gd` (бестиарий, слухи); `memory_rules.gd` (особые навыки карт в бою: условие на тегах → эффект, вместо приёмов); `chatter_rules.gd` (мысли и реплики героев над картами, docs/19: редко, о месте, сюжете, Воспоминаниях при себе; без цифр и игровых слов); `quest_rules.gd` (задания справа, docs/20: сюжет, угрозы, побочные линии колоды, «сюжет ждёт», строка «что делать»); `core_rules.gd` (ядро души, docs/23: осколки → уровни ядра героя, +1 к характеристике на выбор; полное ядро → испытание души TR1/TR2 → новый ранг, `CombatSession.hero_rank`); `start_rules.gd` (старт «разбитое стекло», docs/16 §11.5: Санни / Нефис / Касси, с Берега, доступен сразу при новой игре; экран — `scenes/menu/start_screen.gd`, данные — `tools/gen_starts.py` → `data/starts.json`); `wander_rules.gd` (бродячие боссы, docs/22: появляются, стоят 2–3 дня в стороне от пути игрока, уходят ночью; событие на месте — поле `wander`; победа — легендарное Воспоминание); `tutorial_rules.gd` (механики по главам `UNLOCK`, подсказки `data/tutorial.json`; `skip_before` — начало главы из «Разработчика»: обучение прошлых глав отмечено показанным) |
| Бой | **замена в работе: пошаговый бой «Схватка» по образцу Darkest Dungeon — ТЗ docs/24, фазы Ф1–Ф8; Ф1–Ф3 готовы: `core/combat/skirmish/` — `skirmish.gd` (бой: раунды, очередь, ход, урон, грань, психика, трупы, Эхо, отступление, итог), `sk_fighter.gd`, `sk_build.gd` (параметры из Силы/Воли/Хитрости и тегов, навыки героев и карт, Эхо, враги), `sk_strike.gd` (попадание, урон, крит, «почему»), `sk_status.gd`, `sk_formation.gd`, `sk_pack.gd` (строй врагов), `sk_ai.gd`; тесты `test_skirmish*.gd`; таблица врагов — редактор, «Сила» → «Схватка»; Ф4 — экран `scenes/combat/skirmish_screen.gd` (+ `sk_fighter_view.gd`), пробный бой в «Разработчике», автоснимки `--mshots-from=skirmish`; Ф5 (основное): `core/rules/skirmish_rules.gd` — переключатель (`state.flags.combat`, «Разработчик» → «Бой в событиях — «Схватка»», по умолчанию «Столкновение»), резолвер на боевом этапе встаёт на паузу (`sq.phase = "combat"`, ответ `{skirmish: spec}`), продолжение — `MissionResolver.resume_combat`; бот играет её ИИ; свет, засада, раны до ночи (`night_heal`)**; сейчас — `core/combat/combat_session.gd` (автобой, ledger — расчёт силы, запас сторон), `core/combat/strikes.gd` (удары: оружие, броня, окружение, прогноз `odds`; данные `data/combat/weapons.json`); экран — `scenes/combat/combat_screen.gd` (только просмотр); калибровка — `tools/strike_calib.gd`, статистика боёв для редактора — `tools/combat_stats.gd` |
| Экран карты | `scenes/missions/mission_game.gd` (карта, герои, небо, окна), `mission_marker.gd` (карта миссии + кольцо; на карте-плане — ромб `make_icon`: наведение → круг загрузки → подробная карточка, настройка `event_icons`, docs/18 §6б), `figure_piece.gd` (фигура: перетаскивание, свечение, рисунок `art/map/figure/<герой>` или каменная пешка; сцена лагеря и наезд камеры — `SleeperMap.camera_to/camp_scene`, разрыв карты события — `Vfx.shatter`), `mission_window.gd` (брифинг → прибытие → отчёт), `shop_*.gd`, `drop_zone.gd`, `squad_life_ui.gd` (значки доверия/паники, строка брифинга), `chatter_layer.gd` (пузыри реплик над картами героев), `quest_panel.gd` (задания справа, прицел → `SleeperMap.show_quest`), `day_icon.gd` (дела дня и «Переждать» — иконками, без надписей), `camp_window.gd` (лагерь), `tide_layer.gd` (вода прилива на карте), `memory_choice.gd` (выбор Воспоминания 1 из 3), `journal_window.gd` (журнал), `hint_popup.gd` (подсказки-прожектор), `hint_targets.gd` (цели подсказок); `scenes/vfx/crisis_fx.gd` (момент кризиса психики) |
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
| `missions/ch6_city.json` | Город людей (глава-черновик) | `tools/gen_city.py`: сюжет CS01–CS08 (черновики), предвестия CO, Врата CG, шрамы CX, волны CW, встречи CR; карта `maps/real_city.json`; регион `real_city` (`start_heroes`, `start_cards` — старт главы-черновика) |
| `missions/ch4_tree.json`, `ch5_dark_city.json` | Глава 4 (черновики): Древо Души (Пепельный путь) и Мрачный город | `tools/gen_chapter4.py` (не править JSON руками): сюжет TS01–TS14, DS01–DS12, заказы Гильдии DK01–DK03, встречи TL/DL; карты `maps/ash_path.json`, `maps/dark_city.json`; у боя этапа `combat.power` — сила врагов (боссы черновиков слабее общего списка) |
| `missions/ch3_shore_events.json` | Места событий Берега | `tools/shore_events_map.py` (после gen_shore): 11 мест событий на площадках S7–S14 (чужой лагерь, туша исполина, грот, звёздный осколок, колодец Легиона, провал, голем, гнездо посланника, логово многоножек, могилы, островок) — по две встречи SE01–SE22; карта Берега: `emerge_groups`, `ebb_sockets`, облики и метки событий; картинки — `python tools/import_map_kit.py shore_events` (лагерь отряда → `art/map/figure/camp_*`) |
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
| `combat/skirmish.json` | «Схватка» (docs/24) | `tools/gen_skirmish.py` (не править руками): навыки, свойства тегов, параметры и особое врагов, свет |
| `quests.json` | цели глав для заданий справа (docs/20) | `tools/gen_quests.py` (+ подсказка T99) |
| `wanderers.json`, `missions/wanderers.json` | бродячие боссы и их события на местах (docs/22) | `tools/gen_wanderers.py` (противники MW1–MW4, награды LW1–LW4, T100); промты картинок — `tools/gen_boss_prompts.py` → docs/*.docx |
| `chatter.json` | мысли, реплики, диалоги героев над картами (docs/19) | `tools/gen_chatter.py` (не править руками): `settings{every, first, poke_chance, recent}`, `lines[{id, hero, kind, when, text}]`, `dialogs[{id, heroes, when, lines}]` |
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
| `tree` | Древо Души (E33–E48) | глава-черновик: Пепельное море (буря меняет тропы), Демон по следу, Владыка Пепла, мост над Бездной, Древо и Очарование, лодка по Чёрной воде; после Берега (SH32 → tree) | `ch4_tree` из `tools/gen_chapter4.py`, регион `ash_path`, неделя Ночь 2 · Рассвет 2 · Пепельная буря 1 · Кровавая луна 2 |
| `dark_city` | Мрачный город | глава-черновик: Светлый замок за дань, территории хозяев, ночные охотники, завалы; сюжет после Гильдии ждёт трёх зачищенных районов (заказы DK); после Древа (TS14 → dark_city) | `ch5_dark_city` из `tools/gen_chapter4.py`, регион `dark_city` |
| `city` | Город людей (реальный мир) | глава-черновик: Врата Кошмара; по сюжету — после Мрачного города (DS12 → city) | `ch6_city` из `tools/gen_city.py`, регион `real_city`, неделя День 2 · Сумерки 1 · Ночь 2 |

## Правила, которые нельзя ломать без владельца

Смерть навсегда (травм нет — грань смерти); ход — день, отдых только ночью в лагере-стоянке (docs/16 §12); шаги дня и «без тупиков» — docs/17 (проверка `tests/test_travel.gd`: пустых утр 0); финал Кошмара — только Санни; купленные спутники остаются после главы; автобой без вмешательства (приёмов нет — навыки карт срабатывают сами) — **владелец 05.10 решил заменить его пошаговым боем «Схватка» по образцу Darkest Dungeon (docs/24, фазы Ф1–Ф8); до готовности «Схватки» действует автобой**; прогноз — шесть слов; маны нет; магазин раз в 7 миссий; раны врага сохраняются; связи тегов открываются навсегда. Полный список — HANDOFF.md «Решения владельца» и docs/15 §11, §19; решения по фазам 7+ — docs/16.
