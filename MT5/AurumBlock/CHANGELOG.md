# AurumBlock EA — Changelog

## v1.08 — 2026-06-09

### Fix — Dashboard HiDPI/Mac scaling (`InpUIScale`)

No Mac com ecrã Retina (ou qualquer display HiDPI), o `OBJ_BITMAP_LABEL` renderiza
o bitmap em **pixels físicos** (mapeamento 1:1), enquanto as coordenadas dos labels
(`CORNER_LEFT_LOWER`, `YDISTANCE`) usam **pixels lógicos** (já escalados pelo sistema).
Resultado: o fundo aparecia com metade do tamanho visual e as letras "vazavam" para fora.

**Solução:** novo parâmetro de input `InpUIScale` (padrão = 1).

| Valor | Quando usar |
|---|---|
| `1` | Windows / Mac ecrã não-Retina (comportamento anterior) |
| `2` | Mac com ecrã Retina / HiDPI 1920 × 1080 |

Com `InpUIScale = 2`:
- O bitmap é criado com `DASH_PAN_W × 2` por `DASH_PAN_H × 2` pixels físicos  
  → no ecrã Retina ocupa exactamente `DASH_PAN_W × DASH_PAN_H` pixels lógicos ✓  
- As coordenadas dos labels (`XDISTANCE`, `YDISTANCE`) são multiplicadas por 2  
  → permanecem alinhados dentro do bitmap ✓  
- O posicionamento do painel (`panTop`) usa `DASH_PAN_H × InpUIScale`  
  → o fundo cola-se correctamente à margem inferior do gráfico ✓

**Sem impacto na lógica de trading** — apenas visual.

---

## v1.07 — 2026-06-09

### Dashboard — linha de previsão de próximo evento

Nova linha no dashboard (entre o estado e a info do bloco) que avisa
antecipadamente quando o bot vai parar, antes de acontecer.

**Três modos de display (prioridade decrescente):**

| Situação | Texto | Cor |
|---|---|---|
| Session pause começa em < 60 min | `▸ ⏸ NY Forex pause  em 23m` | Âmbar |
| Pre-block de notícia começa em < 90 min | `▸ NEWS NFP 15:30  para em 45m` | Âmbar |
| Notícia dentro de 8 horas (informativo) | `◦ NFP 15:30  em 3h05m` | Dim |
| Sem eventos próximos | *(linha vazia)* | — |

**Novas funções:** `GetNextSessionPauseStart()` · `GetNextNewsInfo()`

**Ajustes de layout:** `DASH_PAN_H` 155 → 179 px · `N_DASH0` y=145 → y=169 · `N_DASHN` novo em y=145

---

## v1.06 — 2026-06-07

### Change — `InpMinOrderDist` external input

`MIN_ORDER_DIST` (previously a compile-time `#define` of 130.0 pips) is now an
external input parameter, allowing changes directly in the Strategy Tester
without recompiling.

- Default: **130.0 pips** (behaviour unchanged)
- Appears in the EA parameter dialog as **"Min distance to double position (pips)"**
- Used in backtests via the Optimisation tab to find the best martingale distance

---

## v1.05 — 2026-06-07

### Change — `GetLots()` formula

Replaced the linear balance formula with a square-root curve that grows more
slowly and stays at 0.01 lot for longer, protecting smaller accounts:

```
lots = 0.01 × MAX(1;  1 + FLOOR( (√(2×Balance − 700) − 30) / 20 ;  1))
```

| Balance range | Lots |
|---|---|
| < $1 600 | 0.01 |
| $1 600 – $2 799 | 0.02 |
| $2 800 – $4 399 | 0.03 |
| $4 400 – $6 399 | 0.04 |

Previous formula (`ROUND((Balance−400)/800)/100 + 0.01`) scaled more
aggressively (0.02 from $800, 0.03 from $1 600).

`InpFixedLots > 0` continues to override the formula unconditionally.

---

## v1.04 — 2026-06-07

### Dashboard — unified panel with countdown timer

**Consolidated**: the separate top-left status label (`N_INFO`) is removed. All
information now lives in a single bottom-left panel — no scattered labels.

**Status row** (top of panel): shows the bot's current state with a colour-coded dot:
- `◉ ACTIVE` — green
- `▶ NEWS  <EventName>  » 12m30s` — amber, with event name and countdown to resume
- `⏸ <Session> pause  » 8m15s` — amber, with session name and countdown to resume
- `■ PAUSED (web panel)` — red

**Box info row**: directly below the status row, shows the active FVG block's
high/low/size (`Box 4331.08 – 4325.56 [ 55.2 pips ]`).

**Timer logic**:
- `GetNewsBlockInfo()` — returns seconds until `event_time + NEWS_POST_SEC` and event name
- `GetSessionPauseInfo()` — returns seconds until `sessionOpen + PAUSE_WINDOW_MIN` and session name
- `FormatTimer()` — `< 1 h` → `"12m30s"`; `≥ 1 h` → `"1h05m"`

**Visual**:
- Panel size: 325 × 155 px (was 295 × 106 px)
- Background: `ColorToARGB(C'10,13,24', 220)` — true semi-transparent dark glass
- Border: `C'55,80,160'` cobalt
- Row spacing: 24 px, YDISTANCE 145 / 121 / 93 / 69 / 45 / 21

---

## v1.03 — 2026-06-04

### Change
- **`InpFixedLots` external input** — replaces the compile-time `#define FIXED_LOTS`.
  Setting it to `0.0` (default) keeps the automatic balance-scaled formula.
  Setting it to any positive value (e.g. `0.02`) fixes the initial lot without recompiling.
  Scale-in lots continue to double the last position's lot regardless of this setting.

---

Commercial build of the FVG Block strategy, specialised for XAUUSD M1.
Based on FvgBlock v3.87. No external inputs — all settings are `#define` constants.

---

## v1.02 — 2026-06-04

### Features
- **`FIXED_LOTS` constant** — optional fixed initial lot size.
  Set `FIXED_LOTS > 0.0` to override the automatic formula; `0.0` uses `GetLots()`.

### Visual
- **New colour scheme** — frosted-glass cobalt blue replaces the vivid orange/magenta:
  - `C_MIDBODY`  `C'224,232,247'` — body fill (15 % cobalt on white)
  - `C_EXTREME`  `C'194,209,242'` — top/bottom zone bands (30 %)
  - `C_MIDBAND`  `C'163,185,237'` — centre accent band (45 %)
  - `C_BORDER`   `C'50,100,210'`  — solid cobalt outline and labels
  - `C_UNSTABLE` `C'240,214,153'` — amber warning when zone is unstable
- Centre band (`N_MBAND`) now uses the distinct `C_MIDBAND` instead of the same
  colour as the extreme zones — creates a visible depth gradient.

### Dashboard redesign
- **Dark navy card** (`C'22,27,40'`) with cobalt border — readable on any chart
  background (white or dark); previous alpha-blended background was illegible on
  light charts.
- **Data fix — cycle counter**: `Ciclos` now counts only *initial* cycle entries
  (comments `AUR_SL`, `AUR_SM`, `AUR_BL`, `AUR_BM`). Scale-in entries
  (`AUR_SS`, `AUR_BS`) are excluded. Previously every individual entry was counted,
  inflating the number by the average martingale depth.
- **Data fix — cycle grouping**: EXIT deals are now grouped by *direction* within a
  30-second window (previously 5 s, no direction check). Prevents mixing unrelated
  BUY and SELL closes and handles martingale cycles where multiple positions close
  within seconds of each other.
- **Smart duration format**: values under 60 min show as `Xm`; values above show
  as `Xh Ym` (e.g. `1h56m`).
- Colour hierarchy: gold title → steel-blue stats → dimmed breakeven → green above-BE.

---

## v1.01 — 2026-06-03

### Bug fix — news calendar timezone
- **`SyncCalendarToFile()`**: restored `- SERVER_OFFSET * 3600` subtraction.
  `MqlCalendarValue.time` was confirmed (via live debug log) to be in broker server
  time (UTC+3), not UTC. Removing the subtraction caused new events to be written
  3 hours ahead of their actual UTC time (e.g. ADP at `15:15` instead of `12:15`).
- **Debug print removed** from `SyncCalendarToFile()` (TZ-CHECK confirmed correct).

### News calendar — whitelist expansion
- Added keywords: `"gross domestic product"`, `"durable goods"`,
  `"average hourly earnings"`, `"unemployment claims"`, `"jobless claims"`,
  `"jolts"`, `"job openings"`, `"fed member"`, `"fomc member"`.
- `"gdp"` substring was not matching `"Gross Domestic Product Annualized"` —
  full phrase added.
- Extended importance filter to include `CALENDAR_IMPORTANCE_MODERATE` (orange
  events) in addition to `CALENDAR_IMPORTANCE_HIGH` (red events).

### News calendar — event name storage
- `LoadNewsFile()` now populates a parallel `g_newsNames[]` array alongside
  `g_newsEvents[]`, enabling named diagnostics.
- `PrintUpcomingNews(int maxEvents)` added: on every news reload, prints the next
  N upcoming events in local UTC+1 time to the Experts log. Used to verify UTC
  conversion against Forex Factory without running a backtest.

### fvg_news.csv
- Rebuilt with correct UTC times cross-referenced against Forex Factory.
- Orange-impact events added for all months: JOLTS, ADP, Unemployment Claims,
  ISM Services PMI, Retail Sales, FOMC Press Conference, Powell Speeches.
- Jun 25 corrected from `PCE` (wrong) to `GDP Annualized + Durable Goods`.
- Powell Speech Jun 1 corrected to `00:30 UTC` (was `03:30`, 3 h off due to
  server-time bug in earlier sync).

---

## v1.00 — 2026-06-03

Initial release. Ported from FvgBlock v3.87. Key additions over the source:

### Architecture
- **No external inputs** — all tunable values are `#define` / compile-time constants.
  Users recompile to change settings; no accidental parameter changes at runtime.
- **Magic number** `20250528` — compatible with the FvgBlock web control panel.

### Session pause windows
New function `IsSessionPauseTime()` blocks new entries and cancels pending limits
during the ±`PAUSE_WINDOW_MIN` (15 min) window around each major session open.
Existing positions remain open and TP break-even continues to be calculated.

| Session   | Opens (UTC+1 summer) | Block window       |
|-----------|---------------------|--------------------|
| Sydney    | 23:00               | trading starts 23:15 (no pause) |
| Tokyo     | 01:00               | 00:45 – 01:15      |
| London    | 08:00               | 07:45 – 08:15      |
| NY Forex  | 13:00               | 12:45 – 13:15      |
| NYSE      | 14:30               | 14:15 – 14:45      |

### Asymmetric news filter
- Block window: **135 min before** the event → **15 min after** (previously ±15 min).
- `NEWS_PRE_SEC = 8100` (135 × 60), `NEWS_POST_SEC = 900` (15 × 60).

### External news calendar (single source of truth)
- `fvg_news.csv` in `%APPDATA%\MetaQuotes\Terminal\Common\Files\` is the only
  source read by both live trading and backtesting.
- **Live**: `SyncCalendarToFile()` merges new USD high-impact events from the MT5
  native economic calendar into the CSV daily (dedup, sort, history preserved).
- **Backtest**: Strategy Tester has no calendar API → reads the same CSV directly,
  so historical blocks are reproducible.
- Reload on day change — no EA restart required after news updates.

### Automatic lot sizing
`GetLots()` scales the initial lot with account balance:
```
lot = ROUND((Balance − 400) / 800) / 100 + 0.01
```
Examples: $400 → 0.01 | $1 200 → 0.02 | $2 000 → 0.03.
Scale-in lots continue to double the last position's lot regardless.

### Dashboard overlay
`OBJ_RECTANGLE_LABEL` panel, bottom-left corner, showing:
- Ciclos hoje / semana
- Tempo mín / avg / máx (per closed position)
- Breakeven cycles (net ≤ $0.10 after cost)
- Acima BE cycles (net > $0.10)

### Status label enhancements
Top-left label shows active state prefix:
- `⏸ PAUSED` (red) — web panel pause flag active
- `⏸ SESSION PAUSE` (yellow) — within session open window
- `📰 NEWS BLOCK` (yellow) — within news filter window
