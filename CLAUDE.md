# SunLess — коротко для Claude

Карточная игра на Godot 4.7.2 по «Shadow Slave» (фанатская, некоммерческая). Ветка `gameplay/figure` (откат — `gameplay/missions`), репозиторий GitHub AlexCodeHadjar/SunLess. Владелец пишет по-русски, решения по механике принимает сам (спрашивать вариантами). После фазы — коммит и push. Подробная карта кода и данных — `docs/26`; история и решения — `HANDOFF.md`, `docs/15`, `docs/16`.

## Правила работы

- **Экономия:** справки по данным — `python tools/ctx.py missions|mission MS05|heroes|hero P03|enemy M02|tag Дуэль|locations|shops|fields MS05`. Код читать по функции (`grep -n "func имя"`, `Read` с offset/limit). Вывод тестов и логов сжимать до итога.
- **Правки данных** — python-скриптом (json.load → правка → `json.dumps(ensure_ascii=False, indent=1)` + `\n`). Длинные правки GDScript писать через Write/скрипт, не heredoc (портит кавычки). Сгенерированные JSON (`tools/gen_*.py`) руками не править.
- **Каждая новая или изменённая механика — с обучением:** подсказки `data/tutorial.json`, событие, цель подсветки (`HintTargets`); устаревшие тексты переписать.
- **Новая механика** — новый файл `core/rules/<имя>.gd` + тест `tests/test_<имя>.gd` (в `SUITES` в `tests/run_tests.gd`). Рискованные переделки (бой, смерть) — отдельным коммитом.
- **GDScript:** табы, явные типы; `:=` не выводит тип из Variant/Dictionary — писать `var x: Тип =`.
- **Промты артов:** к картам — шаблон `docs/assets/cards/templates` и образцы готовых карт; ко всем — образцы картинками и ссылками; фишки на карте — 4 ракурса. Пример — `tools/gen_boss_prompts.py`, `tools/gen_skirmish_docs.py` (Word без библиотек — `tools/docx_lib.py`).
- **Материалы — внутри проекта:** игра берёт картинки только из `res://`; исходники — `docs/assets/…`, импорт — `tools/import_*.py`. Комплекты карт-планов — `docs/assets/kits/` (в git не входят).
- **Карты глав** (`data/maps/<регион>.json`, места в `locations.json`, `art/map/<регион>/`) — только через редактор карт: skill `cli-anything-sunless-map` (`../SunLessMapEditor`). Карты из `tools/gen_*.py` после правки в редакторе не перегенерировать без вопроса владельцу.
- **Производительность** (docs/21): ничего тяжёлого в `_process`; экран по сигналам и слепку состояния; в `content.memo` — производное из данных. После правок экрана карты — `--mshots-from=perf`.
- **Не трогать:** `docs/Вельмор*`, `docs/Карта главы — руководство.docx` (чужие файлы владельца). Папку Codex `SunLess-wandering-bosses` не использовать.

## Команды

```bash
G="/d/Godot_v4.7.2-stable_win64_console.exe"
"$G" --headless --path . --import                       # после новых файлов и ассетов
"$G" --headless --path . -s res://tests/run_tests.gd    # все тесты (~30 мин, в фоне)
"$G" --headless --path . -s res://tests/run_tests.gd -- --only=test_gates   # один набор
"$G" --path . --resolution 1920x1080 -- --mshots=<папка> --mshots-from=<режим>   # автоснимки (ch4|timeline|figure|events|icons|chatter|quests|mods|bosses|perf|fog|start|skirmish…)
python tools/gen_skirmish.py        # «Схватка»: данные боя → data/combat/skirmish.json
python tools/gen_skirmish_docs.py   # ТЗ «Схватки» и промты артов → docs/*.docx (рус. и англ.)
python tools/import_combat_art.py   # картинки боя docs/assets → art/combat
"$G" --headless --path . -s res://tools/skirmish_sim.gd -- --n=50   # бои ИИ против ИИ (--enemies — по врагам)
python tools/editor/server.py       # редактор контента (127.0.0.1:8765), «Сила» — баланс и «Схватка»
```
Другие генераторы (`gen_figure/chatter/quests/wanderers/core/starts…`) — см. `docs/26`.

## Карта кода (самое важное)

- **Данные → память:** `core/content/content.gd`, `content_validator.gd` (ошибка данных = игра не стартует). **Состояние:** `core/state/run_state.gd` (`SAVE_VERSION`), `autoload/save_service.gd`, `autoload/game_state.gd` (API для интерфейса).
- **Миссии:** `core/rules/mission_flow.gd`, `mission_resolver.gd` (этапы, бой, итог), `mission_forecast.gd`. **Правила** (`core/rules/*`): грань смерти `edge_rules`, психика `psyche_rules`, доверие `trust_rules`, рост тегов `growth_rules`, ядро души `core_rules`, дни `day_rules`, фигура `figure_rules`, переходы `travel_rules`, угрозы `gate_rules`, местность `terrain_rules`, подвижные угрозы `mover_rules`, бродячие боссы `wander_rules`, подсказки `tutorial_rules` — подробности в `docs/26`.
- **Бой «Столкновение»** (автобой, пока основной): `core/combat/combat_session.gd`, `strikes.gd`; экран — `scenes/combat/combat_screen.gd`.
- **Бой «Схватка»** (пошаговый, по образцу Darkest Dungeon — ТЗ `docs/24`; Ф1–Ф4 готовы, Ф5 — основное): `core/combat/skirmish/` (`skirmish.gd`, `sk_build`, `sk_strike`, `sk_status`, `sk_formation`, `sk_pack`, `sk_ai`), `core/rules/skirmish_rules.gd` (переключатель `state.flags.combat`, «Разработчик» → «Бой в событиях — «Схватка»»; резолвер на боевом этапе ставит паузу `sq.phase="combat"`, продолжение — `MissionResolver.resume_combat`), экран `scenes/combat/skirmish_screen.gd` + `sk_fighter_view.gd`, данные `data/combat/skirmish.json`. Тесты `test_skirmish*.gd`. Осталось: строй в окне отряда, кризис-поведение в бою, рост тегов и доверие, ночное нападение, Натиск/Врата волнами, прогноз, `SAVE_VERSION`; затем Ф6 (лагерные навыки), Ф7 (арт), Ф8 (баланс и включение по умолчанию).
- **Экран карты:** `scenes/missions/mission_game.gd`, `mission_window.gd`, `mission_marker.gd`, `figure_piece.gd`; карта-план `scenes/map/sleeper_map.gd`. **Карты и интерфейс:** `scenes/cards/*`, `ui/theme/palette.gd`, `ui_theme.gd`.
- **Разработчику:** `core/dev/autoplay.gd` (бот), `scenes/menu/dev_panel.gd` («Разработчик»), `tools/mission_shots.gd` (автоснимки).

## Данные `data/` (кратко)

Миссии — `missions/ch*_*.json` (глава → файл: nightmare `ch1`, academy `ch2`, shore `ch3`, tree `ch4`, dark_city `ch5`, city `ch6`); карты — `maps/<регион>.json`; `locations.json`, `days.json` (дни, неделя, лагерь, `movement`, `combat`), `characters.json`, `enhancements.json`, `abilities.json`, `combat/*.json` (теги, поля, враги, `skirmish.json`), `tutorial.json`, `chatter.json`, `psyche.json`, `bonds.json`, `loot.json`, `modifiers.json`, `deck.json`, `quests.json`, `wanderers.json`. Поля миссии и действия — `docs/15`, `python tools/ctx.py fields MS05`.

## Главы

`nightmare` Первый Кошмар (обучение) · `academy` Академия (обучение) · `shore` Забытый Берег (основной геймплей) · `tree` Древо Души · `dark_city` Мрачный город · `city` Город людей (последние три — черновики).

## Нельзя ломать без владельца

Смерть навсегда (травм нет — грань смерти); ход — день, отдых только ночью в лагере (docs/16 §12); «без тупиков» (`tests/test_travel.gd`: пустых утр 0); финал Кошмара — только Санни; купленные спутники остаются после главы; прогноз — шесть слов; маны нет; магазин раз в 7 миссий; раны врага сохраняются; связи тегов открываются навсегда. Автобой «Столкновение» владелец решил заменить боем «Схватка» (05.10) — после готовности; до тех пор он основной. Полный список — `HANDOFF.md`, `docs/15 §11, §19`, `docs/16`.
