# F1 True Conditions — real F1 session conditions for Pure Planner

Version 1.9 · CSP Lua app for Assetto Corsa. Pick an F1 circuit, a season (2023 → today) and a session
(Sprint Qualifying/Shootout, Sprint, Qualifying, Race) and apply the conditions the real
session started in to Pure Planner: air temp, track temp, humidity, wind speed/direction,
sky (cloud cover) and rain.

## Requirements

- Content Manager + Custom Shaders Patch (Lua apps), Pure + Pure Planner (tested with v1.81).
- Internet access for the daily database download (works offline with the bundled copy).

## Install

Drop the release zip into Content Manager (or extract it into the Assetto Corsa folder). Result:
`assettocorsa/apps/lua/F1TrueConditions/`.

### Upgrading from "F1 Real Weather" (≤ 1.8)

The app was renamed. **Delete `assettocorsa/apps/lua/F1RealWeather/`** — with both installed, two
apps load weather into Pure Planner. The new app warns (red text) as long as the old folder exists.
Settings start fresh; presets exported earlier stay in `Plans\Stamp\F1 Real Weather\` (new
exports go to `Plans\Stamp\F1 True Conditions\`).

## Use

### Automatic

With a VRC Formula Alpha car (any car id containing `vrc_formula_alpha`) the app picks the
circuit from the loaded track and loads the real conditions into Pure Planner by itself:

| AC session | Real session used |
|---|---|
| Hotlap, practice, qualifying, time attack | Qualifying |
| Race | Race |

- **Session load:** the app starts before Pure Planner (apps load alphabetically) and writes the
  plan to `Plans\last_used.json`. With Pure's controller on *Load last used plan* (the default, and
  your current setting) Pure Planner starts on it without any extra step.
- **Session change** inside one load (race weekend: practice → qualifying → race): the app sends
  the new plan to Pure Planner through its controller state (the same `PURE.initPlan` +
  `PureCtrl.restarted` path Content Manager uses) and retries up to 3 times.
- **Confirmation:** the app reads back the air and track temperature Pure Planner is actually
  driving and only reports success when both match the plan. The status line says which step it is on.
- If Pure's controller is set to *Live* or a fixed plan in CM, the start-up file is ignored and the
  app falls back to sending the plan after 12 s.
- Settings: auto on/off, any car, and which season to use (latest by default).

### Pit window

When you are in the pits (setup screen) the app opens its **F1 True Conditions - Pits** window by itself. If
CSP doesn't show it there, the app draws the same panel directly on the pit screen instead
(drag it by the header; the position is remembered). It is styled like the CSP/VRC setup panels: one column per real session (Sprint Q, Sprint,
Qualifying, Race) with air and track temperature, humidity, wind, sky, rain and local start time.
The chosen session has a red box; click a column header to apply that session. The switch in the
top-right corner turns F1 True Conditions on or off (off = no auto-load, Pure Planner keeps its current
plan). The footer turns green when Pure Planner confirms the conditions.

The panel scales with your screen: designed at 1440p, x0.75 at 1080p, x1.5 at 4K. *Pit panel size*
in the main window adds your own adjustment (60–160 %). Turn it off with *Show weather panel in the pits*.

### Qualifying Q1 / Q2 / Q3

Qualifying (and sprint qualifying) can use each segment instead of the session start. Pick
**Q1, Q2 or Q3** under the Qualifying column in the pit panel (or the *Segment* list in the main
window); the choice is remembered and also used by the automatic loading.

Each segment is a **snapshot of its final laps**: the conditions of the last 5 minutes before the
chequered flag, at that time of day, with the real fastest lap of the segment as a target
(*Real best lap*). Nothing changes during the AC session: rain, wetness and standing water are
fixed (all Pure dynamics off), so every attempt is made in the same conditions.

Track surface: *Raining*, *Wet* (rain stopped < ~12 min ago), *Damp*, *Drying* or *Dry*. How long
ago the rain stopped is scaled by track temperature (a cold night track dries slowly). Example,
Las Vegas 2025: Q1 raining (RUS 1:53.144), Q2 wet (RUS 1:50.935), Q3 damp (NOR 1:47.934).

All other sessions (race, sprint, qualifying without segments) are frozen the same way at their
start-of-session conditions.

### Overrides (haze, sky corrections)

The timing feed has no visibility or haze data, so `data/f1_weather_overrides.csv` (downloaded next
to the shared CSV, so changes reach everyone at their next game start) lets you correct the look:

```
year,event,session,segment,pure_weather,mist_pct,note
2026,sepang,,,17,50,Haze across Malaysia (scattered clouds + 50% mist)
```

- `event`: part of the circuit / display / meeting name or a track keyword (`sepang`).
- `session`: `Qualifying`, `Race`, … — empty or `*` = the whole weekend.
- `segment`: `Q1`/`Q2`/`Q3` (`SQ1`…) — empty or `*` = all.
- `pure_weather`: Pure sky type (15 clear, 16 few, 17 scattered, 18 broken, 19 overcast, 23 haze).
  Only the sky changes; rain and track surface stay as measured.
- `mist_pct`: Pure mist 0–100 (empty = automatic from humidity).
- Empty value = keep the data's value; later lines win. Overridden sessions show `[override]`.

### Manual

1. Open **F1 True Conditions**, choose circuit, year and session, press **Apply to Pure Planner**.
2. **Use real session date & time (Stamp)** on: Stamp plan at the real local start time — the sim
   clock jumps there, so night races are dark. Off: Daycycle plan that keeps your sim time.
3. **Export all as presets** writes all sessions to `Plans\Stamp\F1 True Conditions\<year>\`.

## Data

`data/f1_weather_db.csv`, one row per session. Values are medians of the official timing
weather feed (OpenF1) from 5 min before to 10 min after the session start; min/max cover the
whole session. Cloud cover and precipitation come from the Open-Meteo historical archive at the
circuit's coordinates for the start hour, and set the Pure weather type (`pure_weather`):

| cloud % | Pure weather |
|---|---|
| < 10 | 15 clear (23 haze if humidity > 85 %) |
| 10–30 | 16 few clouds |
| 30–60 | 17 scattered clouds |
| 60–88 | 18 broken clouds |
| ≥ 88 | 19 overcast |
| rain at start | 6 light rain / 7 rain / 8 heavy rain (by mm/h) |

Rain = the timing feed's rainfall flag at the start. `rain_frac` is the share of the whole
session with rain flagged, shown for information only (the preset is a start snapshot).
Pure limits: air 0–45 °C, road 0–80 °C, wind 0–150 km/h — values are clamped.

### Shared database

At every start the app downloads the shared CSV from the address in `data/db_url.txt` (set by the
mod author; a GitHub raw link). The download is cached in `data/f1_weather_db_online.csv`. If the
row in use changed (fresh forecast, or real data after the session) the new values are pushed to
Pure Planner immediately. Upcoming sessions (next 16 days) are Open-Meteo forecasts, marked
**Forecast** in the pit panel's *Data* row; they are replaced by timing data after the session.
New circuits (e.g. Sepang, listed by OpenF1 as *Kuala Lumpur*) come with their own display name
and AC track keywords in the CSV, so no app update is needed. See the repo's SETUP.md.

## Pure Planner plan format (v1.81)

`{"control":{"type":3,"loop":false,"timemulti":1},"container":[{"data":{"timestamp":…,"duration":14400,"weather":{…}}}]}`
— type 1 = Daycycle, 2 = Timed, 3 = Stamp. Weather keys: `index, rain_amount, rain_probability, rain_variance,
rain_wetness, rain_water, wind_direction, wind_strength (km/h), humidity (0–1), mist (0–1),
temp_air, temp_road (°C)`, plus `*_dyn` flags (false = keep our value, not CM's) and `*_range` (0).
