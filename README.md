<div align="center">

```text
░▒▓██████████████████████████████████████████████████████████▓▒░
      ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
      █ ░  C E P H   ·   S C O U T   ·   U N I T   0 1  ░ █
      ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
        ⬢ ▣ ⬢ ▣ ⬢ ▣ ⬢ ▣ ⬢ ▣ ⬢ ▣ ⬢ ▣ ⬢ ▣ ⬢ ▣ ⬢ ▣ ⬢ ▣ ⬢ ▣ ⬢
░▒▓██████████████████████████████████████████████████████████▓▒░
```

### Bio-mechanical hunter for **Drones Rewrite**

*organic tendrils · cryo discharge · emp pulse · predatory AI · swarm · hive radar*

[![CEPH](https://img.shields.io/badge/%E2%AC%A2-CEPH%20STRAIN-7cff5a?style=for-the-badge&labelColor=06120b)](https://gmod.facepunch.com/)
[![DRR](https://img.shields.io/badge/%E2%AC%A3-DRONES%20REWRITE-00ffd0?style=for-the-badge&labelColor=06120b)](https://github.com/calafex/DronesRewrite)
[![SYNC](https://img.shields.io/badge/%E2%AC%A1-SIGNAL%20STABLE-9dff3d?style=for-the-badge&labelColor=06120b)]()
[![REPO](https://img.shields.io/badge/GITHUB-NeonFurry%2Flvs__scout__drr-1f6feb?style=for-the-badge&logo=github&labelColor=06120b)](https://github.com/NeonFurry/lvs_scout_drr)

</div>

```text
⬢ ⬢ ⬢   D E P E N D E N C I E S   ⬢ ⬢ ⬢
```

<div align="center">

| # | DEPENDENCY | STATUS | NEEDED FOR |
|:--:|:--|:--|:--|
| 1 | **[Drones Rewrite](https://github.com/calafex/DronesRewrite)** | 🔴 **ОБЯЗАТЕЛЬНО** | база дрона, полёт, камера, HUD, оружие — без него аддон не работает |
| 2 | **[GWeather](https://steamcommunity.com/workshop/filedetails/?id=3322707383)** (аддон с сущностью `gw_t1_night`) | 🟡 опционально | ночной режим и фонарь из F3 (пункт «НОЧЬ») |

</div>

> [!IMPORTANT]
> **⟡ CEPH TRANSMISSION // ОБЯЗАТЕЛЬНАЯ ЗАВИСИМОСТЬ**
> Ставь **Drones Rewrite** в первую очередь: без него `dronesrewrite_base` не зарегистрируется, и дрон не заспавнится — останется пустая оболочка.
> **GWeather** нужен только для ночного режима: без него дрон летает и стреляет как обычно, но кнопка «НОЧЬ» в F3 и фонарь не включатся.

---

```text
⬢ ⬢ ⬢   S C A N   S E Q U E N C E   ⬢ ⬢ ⬢
```

## ◈ ORGANISM

<div align="center">

| FIELD | READING |
|:--|:--|
| CLASS | `lvs_scout_drr` |
| HOST | Drones Rewrite |
| LIMBS | 6 tendrils × 13 segments + claws |
| PRIMARY | cryo discharge (freeze) |
| SECONDARY | cryo shards (machine gun) |
| E.M.P. | 2000 units · 30 s recharge · ragdoll 10 s |
| SENSOR | first-person, bone `Bip01_Head` |
| BEHAVIOUR | dormant → autonomous predation |

</div>

---

## ◈ TENDRILS

- ⬢ Спавн как штатный дрон DRR: полёт, мотор, камера, HUD — через базу.
- ⬢ **Сенсор в голове** — вид привязан к кости `Bip01_Head`, пересчёт каждый кадр.
- ⬢ **Живая плоть**: волна идёт по всем 102 костям щупалец (`rope1..6_seg01..13` и клешни `claw_rope*`), амплитуда растёт к кончику, у каждого сегмента своя фаза. На скорости волна бежит вдоль тела, в покое — медленное дыхание.
- ⬢ **Ключи из модели**: в `autorun/server/lvs_scout_tent_keyframes.lua` лежат клипы `fly_idle` (48 кадров) и `fly_slow` (40), снятые с декомпилированной модели Crysis; переход между ними — по фактической скорости полёта, наклон на развороте — от изменения курса.
- ⬢ Настройка на живую: `lvs_tent_wave <P> <Y>` (частота и амплитуда), `lvs_tent_test <град> [x|y|z]` (проверка осей костей), `lvs_tent_debug` (карта отклонений).
- ⬢ Прокси-хитбоксы на костях: попадания цепляют видимые части, а не пустоту внутри коробки.
- ⬢ Серво-гул: громкость и тон зависят от скорости.

## ◈ DISCHARGE

- ⬢ **Cryo beam (ЛКМ)**: NPC 20 с, игроки 5 с, продлевается пока луч держится.
- ⬢ **Shards (ПКМ)**: скорость 7000, урон 16, замороженную цель добивает мгновенно.
- ⬢ **Упреждение**: скорость цели измеряется по смещению позиции (у антлионов `GetVelocity()` всегда 0), точка встречи решается итеративно.
- ⬢ **Линия огня**: если рельеф мешает, точка прицела поднимается (0/18/36/60) до свободной трассы; иначе выстрел не тратится.
- ⬢ **Свой тип урона** `DMG_CRYO` у пулемёта: страйдер получает его через обёртку (`autorun/server/lvs_scout_cryo_damage.lua`), которая пересобирает урон в `DMG_BLAST` без импульса — броня пробивается, но страйдер не вздрагивает. Для прочих целей остаётся добивающий удар `DMG_BLAST`, если броня погасила первый.

## ◈ E.M.P.

- ⬢ **H** в дроне (или команда `lvs_scout_emp`): импульс радиусом 2000, перезарядка 30 с.
- ⬢ **НПС**: остаётся живым, но уходит в регдол на 10 с — физическое тело, ИИ заморожен (`NPC_STATE_NONE` + `SCHED_NPC_FREEZE`), враг сброшен. Ни стрелять, ни двигаться не может; после эффекта поднимается и продолжает бой.
- ⬢ **Игроки**: вспышка как от флешки в CS — белый экран, нарастание 0.35 с, удержание, спад 1.7 с, всего около 5 с.
- ⬢ **Владелец**: по умолчанию слепнет вместе со всеми, отключается `lvs_scout_emp_blind_owner 0`.
- ⬢ **Визуал Ceph**: шестигранный панцирь, ломаные разряды, гекс-кольца по земле и шестигранная сетка на экране ослеплённого; палитра — холодный циан с фиолетовыми акцентами.
- ⬢ В виде от третьего лица готовность импульса выводится отдельной строкой внизу экрана.

## ◈ PREDATION

- ⬢ Автономность по умолчанию **спит**; будится в F3 или кнопкой «включить всем».
- ⬢ Поиск целей `lvs_scout_ai_range`, отдельный предел огня `lvs_scout_engage_range`.
- ⬢ Задержка захвата 0.6 с — цель не умирает в момент своего появления.
- ⬢ Приоритет тяжёлой техники, груз дропшипа вместо корабля, цели распределяются между особями.
- ⬢ **Стая идёт на одну цель**: увидя врага, особь передаёт саму цель всем свободным дронам носителя — часть не остаётся патрулировать, пока другие воюют. Предел одновременных атакующих — `lvs_scout_swarm` (`0` — все).
- ⬢ По переданной цели огонь открывается только при прямой видимости: дрон летит к ней, но не стреляет в стену.
- ⬢ Патруль по навигации (`0` выкл · `1` NavMesh · `2` AI Nodes), возврат в зону при выходе за неё.
- ⬢ Обход стен, минимальная высота над землёй, поправка на потолок, расхождение группы.
- ⬢ Нет попаданий 5 с — смена позиции вбок и выше, чтобы открыть линию огня.
- ⬢ Уклонение под огнём и возврат к патрулю.

## ◈ CARAPACE

- ⬢ Модуль `Shield`: вручную в F3 или автоматически при HP ниже 20%.
- ⬢ Держит любой урон, пока есть заряд; тратится только джаммером.
- ⬢ После пробоя — **30 с перезарядки**, включить нельзя ни вручную, ни автоматически.
- ⬢ Пока джаммер грызёт щит, автореген не поднимает заряд.

## ◈ INTERFERENCE

- ⬢ `weapon_drr_jammer` переопределён: работает **на любой дистанции**, нужна лишь видимость особи в конусе прицела.
- ⬢ Режим по площади (ПКМ) сохранён.
- ⬢ На экране оружия — режим и таймер (`RELOAD` / `READY`), плюс резервный индикатор под прицелом.

## ◈ HIVE RADAR

- ⬢ В пресете **Crysis Ceph**, правый нижний угол: тёмная подложка, кольца, масштаб 6K.
- ⬢ Иконки по типам (дрон, антлион, страйдер, вертолёт, ганшип, дропшип, манхак, охотник, комбайн, сканер, игрок), повёрнутые по курсу.

| MARK | ENTITY | COLOR |
|:--|:--|:--|
| ⬢ фиолетовый | своя особь | `190,120,255` |
| ⬢ жёлтый | чужая особь / нейтрал | `255,220,90` |
| ⬢ зелёный | друг-NPC | `120,255,150` |
| ⬢ салатовый | друг-игрок | `170,255,90` |
| ⬢ красный | враг | `255,70,70` |

## ◈ SYMBIOSIS

- ⬢ Список классов NPC и ников игроков (по SteamID, показываются ником).
- ⬢ Дружественные NPC не атакуют дрон: отношение `D_LI`, их урон блокируется. Убрал класс — снова обычный NPC.
- ⬢ Дружественные игроки исключены из целей.
- ⬢ Список общий на носителя: правка с одной особи действует на все, переживает переспавн.
- ⬢ Подсветка по `F` использует те же цвета.

## ◈ REGENERATION

- ⬢ Особи одного носителя не ранят друг друга; особи разных игроков — ранят.
- ⬢ Уничтоженная особь не восстанавливается от автолечения и модулей.
- ⬢ Поднять её можно только ремонтным инструментом (`weapon_drr_repairtool` и подобные) — при этом автоматически включается щит.

---

```text
⬢ ⬢ ⬢   G R O W T H   P R O T O C O L   ⬢ ⬢ ⬢
```

## ◈ DEPLOY

```text
[01] git clone https://github.com/NeonFurry/lvs_scout_drr.git
     (или Code → Download ZIP на странице репозитория)
[02] Установи зависимости:  Drones Rewrite (обязательно) + GWeather (для ночного режима)
[03] Положи папку в:  <Steam>/steamapps/common/GarrysMod/garrysmod/addons/lvs_scout_drr/
[04] Полностью перезапусти GMod и зайди на карту
```

```text
lvs_scout_drr/
├── lua/
├── models/
├── materials/
├── addon.json
└── README.md
```

Появится в **Q → Entities → Drones Rewrite → LVS Scout**.

> [!WARNING]
> **⟡ SUIT UPDATE // обновление на лету**
> - `lua/entities/**` (ИИ, оружие, щупальца, щит) — только **полный перезапуск GMod** + переспавн дрона.
> - `lua/autorun/**` (HUD, меню, подсветка, джаммер) — достаточно `lua_refresh` / LUARefresher.
> Класс из `entities/` уже в памяти, `lua_refresh` его не перечитывает.

---

## ◈ BOND // управление

<div align="center">

| ACTION | KEY |
|:--|:--|
| Занять особь | `E` (навестись) |
| Cryo beam | **ЛКМ** (удерживать) |
| Shards | **ПКМ** (удерживать) |
| Полёт | `WASD`, подъём/спуск — как в DRR |
| Меню оператора | **F3** (`gm_showspare1`) |
| ЭМИ-импульс | **H** или `lvs_scout_emp` |
| Подсветка целей | **F** или `lvs_scout_vision` |
| Выход | привязка **Exit** в DRR |

</div>

### ⬢ F3 // MENU

- Расцветка (красная / обычная).
- Щит: вкл/выкл (во время перезарядки — `ПЕРЕЗАГРУЗКА N с`).
- Ночь (GWeather) — ночной режим и фонарь.
- Автономный модуль: вкл/выкл.
- «Автономность включить всем» + счётчик `N/M`.
- Дружественные NPC и игроки: поле ввода, «ДОБАВИТЬ», список с удалением по клику.

---

## ◈ SIGNALS // команды и конвары

| COMMAND / CVAR | DEFAULT | EFFECT |
|:--|:--|:--|
| `lvs_scout_vision` | — | Переключить подсветку целей |
| `lvs_scout_vision_dump` | — | Дамп целей: класс, `dormant`, кость головы, дистанция |
| `lvs_scout_hud_debug` | — | Диагностика HUD-пресета |
| `lvs_scout_perf` | `1` | Экономные частоты пересчётов |
| `lvs_scout_ai_range` | `16000` | Радиус поиска; `0`/`inf`/`max` — вся карта |
| `lvs_scout_engage_range` | `0` | Дистанция огня; `0`/`inf` — без лимита |
| `lvs_scout_nav_mode` | `1` | Патруль: `0` выкл · `1` NavMesh · `2` AI Nodes |
| `lvs_scout_swarm` | `0` | Сколько дронов бьют одну цель; `0` — вся стая |
| `lvs_scout_emp` | — | Импульс ЭМИ (то же, что клавиша `H`) |
| `lvs_scout_emp_blind_owner` | `1` | Слепить владельца дрона: `0` — водитель не слепнет |
| `lvs_tent_wave` | — | `<P> <Y>` — частота и амплитуда волны щупалец |
| `lvs_tent_test` | — | `<град> [x\|y\|z]` — проверка осей костей |
| `lvs_tent_debug` | — | Карта отклонений костей щупалец |
| `lvs_scout_debug` | `0` | Отладка ИИ (`mg aim`, `ice impact`, `scan`) |

<details>
<summary><b>⬢ TELEMETRY // что печатает <code>lvs_scout_debug 1</code></b></summary>

```text
[LVS] scan:  cand=25 npc=23 enemyNPC=2 contact=true target=... radius=0 engage=0
[LVS] mg aim: npc_antlion dist=1595 vel=109 lead=27 lift=18
[LVS] ice:   dir=0.697 -0.248 -0.672 startDist=1412 muzzleDist=1348
[LVS] ice impact: NPC [135][npc_antlion] frac=0.36
[LVS] mg path blocked: рельеф по всей линии
```

`radius`/`engage` — лимиты поиска и огня, `lead` — упреждение, `lift` — подъём точки прицела над целью.

</details>

---

## ◈ MUTATION // настройка

- `lua/entities/lvs_scout_drr/shared.lua`
  - полёт: `Speed`, `UpSpeed`, `RotateSpeed`, `Weight`, `YawMin/Max`, `PitchMin/Max`;
  - ИИ: `LvsAiStandoff`, `LvsAiFlyStandoff`, `LvsAiAltitudeOffset`, `LvsMinAltitude`, `LvsPatrolAltitudeMin/Max`, `LvsFreezeTime`, `LvsRegenRate`;
  - урон: `LvsAdaptLimit`, `LvsAdaptMul`, `LvsAiHeavyDamageMul`;
  - прочее: `LvsHeavyHighPriority`, `LvsServoSound`, `LvsServoVolume`.
- `lua/entities/lvs_scout_drr/init.lua`
  - `SEGS_PER_ROPE`, `TENTACLE_WAVE`, `TENTACLE_MAX_BEND`, `TENTACLE_SPEED` — щупальца;
  - `SHIELD_REGEN_DELAY` — перезарядка щита после джаммера;
  - `LvsRandomNavCenter(..., 4500)` — радиус выбора навигационной зоны.
- `lua/autorun/server/lvs_scout_emp.lua` — `RADIUS` (2000), `RAGDOLL_NPC` (10 с), `BLIND_PLY` (5 с).
- `lua/autorun/server/lvs_scout_tentacles.lua` — `SEG_LIMIT`, `AMP`, `WAVE_P`, `WAVE_Y`, `UPDATE_RATE`.
- `lua/autorun/client/lvs_scout_emp_fx.lua` — палитра `CEPH`, число сегментов `ROWS` сферы.
- `lua/entities/lvs_scout_ice/init.lua` — `SPEED`, `DAMAGE`, `LIFE` осколка.
- `lua/autorun/server/lvs_scout_jammer_range.lua` — `MAX_DIST` и конус наведения джаммера.
- `lua/autorun/client/lvs_scout_vision.lua` — `LvsBlipColor` (цвета), `MAX_DIST` подсветки.
- `lua/autorun/client/lvs_scout_hud_crysis.lua` — радар: `RADAR_RANGE`, `ICONS`, `ICON_SCALE`.

---

## ◈ GENOME // структура

```text
lua/
├── entities/
│   ├── lvs_scout_drr/          # дрон: ИИ, щупальца, оружие, камера, HUD-пресет
│   ├── lvs_scout_ice/          # ледяной осколок (пулемёт)
│   └── lvs_scout_hitbox/       # прокси-хитбоксы на костях
├── autorun/
│   ├── server/
│   │   ├── lvs_scout_ai_report.lua      # дамп целей ИИ
│   │   ├── lvs_scout_bones_report.lua   # сверка костей модели и таблиц
│   │   ├── lvs_scout_cryo_damage.lua    # тип DMG_CRYO + обёртка страйдера
│   │   ├── lvs_scout_emp.lua            # ЭМИ: регдол НПС, вспышка игрокам
│   │   ├── lvs_scout_freeze.lua         # заморозка, IsFrozen
│   │   ├── lvs_scout_friendly_dmg.lua   # дружественный огонь, нейтралитет друзей
│   │   ├── lvs_scout_gweather.lua       # синхронизация ночи GWeather
│   │   ├── lvs_scout_jammer_range.lua   # джаммер без лимита дистанции
│   │   ├── lvs_scout_mark.lua           # метка цели пилотом
│   │   ├── lvs_scout_nodes_report.lua   # состояние навигации на карте
│   │   ├── lvs_scout_pilot_body.lua     # тело пилота заморожено
│   │   ├── lvs_scout_tentacles.lua      # решатель волны щупалец + отладка
│   │   └── lvs_scout_tent_keyframes.lua # клипы fly_idle / fly_slow (скрипт)
│   └── client/
│       ├── lvs_scout_hud_crysis.lua     # пресет "Crysis Ceph" + радар, ЭМИ в 3-м лице
│       ├── lvs_scout_hud_scifi2.lua     # обёртка пресета Sci Fi 2
│       ├── lvs_scout_hudfix.lua         # стабилизация центра HUD
│       ├── lvs_scout_skin_menu.lua      # F3-меню, друзья
│       ├── lvs_scout_vision.lua         # подсветка целей, цвета
│       ├── lvs_scout_emp_fx.lua         # визуал ЭМИ и вспышка экрана
│       ├── lvs_scout_nightvision.lua    # ночная оптика
│       ├── lvs_scout_overlay.lua        # оверлей кабины
│       ├── lvs_scout_class.lua          # общие клиентские поля класса
│       ├── lvs_scout_jammer_screen.lua  # таймер на экране джаммера
│       ├── lvs_scout_shield_hud.lua     # плашки щита
│       ├── lvs_scout_frozen_*.lua       # визуал заморозки
│       ├── lvs_scout_freeze_*.lua       # эффекты и следы заморозки
│       ├── lvs_scout_pilot_model.lua    # скрытие модели пилота
│       ├── lvs_scout_auto_cam.lua       # камера автопилота
│       └── lvs_scout_muzzle.lua         # вспышка дула
└── effects/lvs_ice_shatter.lua
```

Всего **40** Lua-файлов.

---

## ◈ LINEAGE // лицензия и права на ассеты

**Код аддона** — **MIT**, полный текст в [`LICENSE`](LICENSE). Менять, форкать и публиковать доработки можно свободно; обязательное условие одно — сохранять уведомление об авторе:

```text
Copyright (c) 2026 NeonFurry — LVS Scout for Drones Rewrite
```

**Модель и текстуры** — `models/crysis/scout/*` и `materials/models/crysis/scout/*` — © **Crytek GmbH**, из игры **Crysis** (2007). Это фанатский некоммерческий порт: права на модель, текстуры, облик существа Ceph и исходные анимации принадлежат Crytek. Аддон распространяется бесплатно, с Crytek не связан и ею не одобрен; лицензия MIT на эти файлы **не распространяется**.

**Клипы щупалец** — `lua/autorun/server/lvs_scout_tent_keyframes.lua` снят с анимаций `fly_idle` / `fly_slow` той же модели Crysis, то есть является производным материалом от неё.

**База дрона** — [Drones Rewrite](https://github.com/calafex/DronesRewrite), автор **calafex**. Код DRR в этот аддон не входит и здесь не распространяется: он нужен как отдельная зависимость.

**Опционально** — GWeather (`gw_t1_night`) только как источник ночного режима; его код также не распространяется.

---

## ◈ DEFECTS // ограничения

- ⬢ Радар — векторные иконки: рендер 3D-моделей внутри `HUDPaint` ломает HUD, поэтому от него отказались.
- ⬢ `info_node*` в GMod обычно не существуют как сущности (граф запечён в BSP), поэтому режим `2` на большинстве карт работает через откат на NavMesh.
- ⬢ Карты без nodegraph: привязка к навигации отключается, патруль идёт по свободному курсу.
- ⬢ Заморозка использует `NPC_STATE_SCRIPT` + `MOVETYPE_NONE`; отдельные кастомные ИИ могут вести себя иначе.
- ⬢ Регдол ЭМИ — физический трюк на живом НПС. У юнитов без физического тела (страйдер, ганшип, часть NextBot) остаётся только заморозка ИИ: стоять и стрелять они не могут, но и падать не будут.
- ⬢ Клипы щупалец в оригинальной модели Crysis почти статичны (медиана смещения 0.03°): видимый рисунок даёт процедурная волна, ключи добавляют микронеровность и синхронность с полётом.
- ⬢ Звук пулемёта отдалён (`soundlevel 110`): на дистанции он слышен хуже, это задумано.
- ⬢ Оси наведения головы/оружия и плоскость изгиба щупалец зависят от рига модели — правятся знаками в `UpdateHead` / `UpdateTentacles`.
- ⬢ Минимальная высота полёта ограничена потолком: в очень низких помещениях особь держится под сводом.
- ⬢ **GWeather** опционален: без аддона с gw_t1_night кнопка «НОЧЬ» в F3 и фонарь не работают, остальное — без изменений.
- ⬢ Список друзей и состояние щита живут в памяти сессии, в файл не пишутся.
- ⬢ `lvs_scout_engage_range` архивный: если в `cfg` сохранено старое `3000`, выставь вручную `0` или `inf`.

---

<div align="center">

```text
░▒▓██████████████████████████████████████████████████████████▓▒░
   ⬢ BIOMASS ............... STABLE
   ⬢ CARAPACE .............. 100%
   ⬢ HIVE LINK ............. SYNCED
   ⬢ HOSTILES .............. NONE
  ────────────────────────────────────────────────────────────
   ⬢ GENOME ............... Drones Rewrite · calafex
   ⬢ CARCASS .............. модель и текстуры © Crytek (Crysis)
░▒▓██████████████████████████████████████████████████████████▓▒░
```

**CODE** — MIT: изменять можно, уведомление об авторе сохраняется.
**ASSETS** — модель и текстуры © Crytek GmbH (Crysis); MIT на них не распространяется.

`⟡ CEPH · SCOUT · UNIT 01 — HIVE LINK ESTABLISHED ⟡`

[Репозиторий](https://github.com/NeonFurry/lvs_scout_drr) · [Issues](https://github.com/NeonFurry/lvs_scout_drr/issues) · [Releases](https://github.com/NeonFurry/lvs_scout_drr/releases)

</div>
