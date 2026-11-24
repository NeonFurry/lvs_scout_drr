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

*organic tendrils · cryo discharge · predatory AI · hive radar*

[![CEPH](https://img.shields.io/badge/%E2%AC%A2-CEPH%20STRAIN-7cff5a?style=for-the-badge&labelColor=06120b)](https://gmod.facepunch.com/)
[![DRR](https://img.shields.io/badge/%E2%AC%A3-DRONES%20REWRITE-00ffd0?style=for-the-badge&labelColor=06120b)](https://github.com/calafex/DronesRewrite)
[![SYNC](https://img.shields.io/badge/%E2%AC%A1-SIGNAL%20STABLE-9dff3d?style=for-the-badge&labelColor=06120b)]()

</div>

```text
⬢ ⬢ ⬢   D E P E N D E N C I E S   ⬢ ⬢ ⬢
```

<div align="center">

| # | DEPENDENCY | STATUS | NEEDED FOR |
|:--:|:--|:--|:--|
| 1 | **[Drones Rewrite](https://github.com/calafex/DronesRewrite)** | 🔴 **ОБЯЗАТЕЛЬНО** | база дрона, полёт, камера, HUD, оружие — без него аддон не работает |
| 2 | **GWeather** (аддон с сущностью `gw_t1_night`) | 🟡 опционально | ночной режим и фонарь из F3 (пункт «НОЧЬ») |

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
| SENSOR | first-person, bone `Bip01_Head` |
| BEHAVIOUR | dormant → autonomous predation |

</div>

---

## ◈ TENDRILS

- ⬢ Спавн как штатный дрон DRR: полёт, мотор, камера, HUD — через базу.
- ⬢ **Сенсор в голове** — вид привязан к кости `Bip01_Head`, пересчёт каждый кадр.
- ⬢ **Живая плоть**: волна идёт по всем костям (`rope1..6_seg01..13`), амплитуда растёт к кончику, у каждого сегмента своя инерция и фаза. Клешни и фаланги дышат отдельно; анимация модели заморожена, чтобы не перебивать процедурную.
- ⬢ Прокси-хитбоксы на костях: попадания цепляют видимые части, а не пустоту внутри коробки.
- ⬢ Серво-гул: громкость и тон зависят от скорости.

## ◈ DISCHARGE

- ⬢ **Cryo beam (ЛКМ)**: NPC 20 с, игроки 5 с, продлевается пока луч держится.
- ⬢ **Shards (ПКМ)**: скорость 7000, урон 16, замороженную цель добивает мгновенно.
- ⬢ **Упреждение**: скорость цели измеряется по смещению позиции (у антлионов `GetVelocity()` всегда 0), точка встречи решается итеративно.
- ⬢ **Линия огня**: если рельеф мешает, точка прицела поднимается (0/18/36/60) до свободной трассы; иначе выстрел не тратится.
- ⬢ **Адаптация**: если защита гасит урон полностью, после серии попаданий организм пробивает её напрямую.

## ◈ PREDATION

- ⬢ Автономность по умолчанию **спит**; будится в F3 или кнопкой «включить всем».
- ⬢ Поиск целей `lvs_scout_ai_range`, отдельный предел огня `lvs_scout_engage_range`.
- ⬢ Задержка захвата 0.6 с — цель не умирает в момент своего появления.
- ⬢ Приоритет тяжёлой техники, цели распределяются между особями.
- ⬢ Патруль по навигации (`0` выкл · `1` NavMesh · `2` AI Nodes), возврат в зону при выходе за неё.
- ⬢ Обход стен, минимальная высота над землёй, поправка на потолок, расхождение группы.
- ⬢ Нет попаданий 5 с — смена позиции вбок и выше, чтобы открыть линию огня.
- ⬢ Уклонение под огнём и возврат к патрулю.

## ◈ CARAPACE

- ⬢ Модуль `Shield`: вручную в F3 или автоматически при HP ниже 20%.
- ⬢ Держит любой урон, пока есть заряд; тратится только джаммером(`weapon_drr_jammer`).
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
[01] Скачай репозиторий: Code → Download ZIP  (или git clone)
[02] Установи зависимости:  Drones Rewrite (обязательно) + GWeather (для ночного режима)
[03] Распакуй аддон в:  <Steam>/steamapps/common/GarrysMod/garrysmod/addons/lvs_scout_drr/
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
│   │   ├── lvs_scout_freeze.lua        # заморозка, IsFrozen
│   │   ├── lvs_scout_friendly_dmg.lua  # дружественный огонь, нейтралитет друзей
│   │   ├── lvs_scout_gweather.lua      # синхронизация ночи GWeather
│   │   ├── lvs_scout_jammer_range.lua  # джаммер без лимита дистанции
│   │   └── lvs_scout_pilot_body.lua    # тело пилота заморожено
│   └── client/
│       ├── lvs_scout_hud_crysis.lua    # пресет "Crysis Ceph" + радар
│       ├── lvs_scout_hud_scifi2.lua    # обёртка пресета Sci Fi 2
│       ├── lvs_scout_hudfix.lua        # стабилизация центра HUD
│       ├── lvs_scout_skin_menu.lua     # F3-меню, друзья
│       ├── lvs_scout_vision.lua        # подсветка целей, цвета
│       ├── lvs_scout_jammer_screen.lua # таймер на экране джаммера
│       ├── lvs_scout_shield_hud.lua    # плашки щита
│       ├── lvs_scout_frozen_*.lua      # визуал заморозки
│       ├── lvs_scout_pilot_model.lua   # скрытие модели пилота
│       ├── lvs_scout_auto_cam.lua      # камера автопилота
│       └── lvs_scout_muzzle.lua        # вспышка дула
└── effects/lvs_ice_shatter.lua
```

Всего **27** Lua-файлов.

---

## ◈ DEFECTS // ограничения

- ⬢ Радар — векторные иконки: рендер 3D-моделей внутри `HUDPaint` ломает HUD, поэтому от него отказались.
- ⬢ `info_node*` в GMod обычно не существуют как сущности (граф запечён в BSP), поэтому режим `2` на большинстве карт работает через откат на NavMesh.
- ⬢ Карты без nodegraph: привязка к навигации отключается, патруль идёт по свободному курсу.
- ⬢ Заморозка использует `NPC_STATE_SCRIPT` + `MOVETYPE_NONE`; отдельные кастомные ИИ могут вести себя иначе.
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
   ⬢ CARCASS .............. модель и текстуры автора модели
░▒▓██████████████████████████████████████████████████████████▓▒░
```

**CODE** — код аддона распространяется «как есть».
**ASSETS** — модель и текстуры подчиняются лицензиям их авторов.

`⟡ CEPH · SCOUT · UNIT 01 — HIVE LINK ESTABLISHED ⟡`

</div>
