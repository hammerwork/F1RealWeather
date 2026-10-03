# F1 True Conditions

**Race in the real conditions of every F1 qualifying, sprint and race since 2023, in Assetto Corsa.**

F1 True Conditions is a Custom Shaders Patch (CSP) app that loads the measured conditions of the real F1
session into the Pure weather mod: air temperature, track temperature, humidity, wind, sky and rain.
You can set the conditions for Q1, Q2 or Q3 of a real qualifying, then try to beat the real pole lap.

The weather database updates itself several times a day. Before a Grand Prix weekend you get the
forecast for the real track. After each session it switches to the measured conditions. You don't
need to download anything new.

> Made for the **VRC Formula Alpha** cars (loads automatically with them), and works with any car.

---

## What you need

| | Download | Notes |
|---|---|---|
| **Content Manager** | [assettocorsa.club/content-manager](https://assettocorsa.club/content-manager.html) | To launch AC and to install the app |
| **Custom Shaders Patch (CSP)** | [patreon.com/c/x4fab/posts](https://www.patreon.com/c/x4fab/posts) | Runs the app. Use a recent version |
| **Pure** (with Pure Planner) | [patreon.com/c/peterboese/posts](https://www.patreon.com/c/peterboese/posts) | The weather mod the app controls. Make sure the **Pure Planner** app is installed |
| **F1 True Conditions** | [Releases](../../releases/latest) | This app |

An internet connection is needed for the daily data. Without one, the app uses the copy of the
database that ships with it.

---

## Installation

1. **Install CSP**, following the instructions on its Patreon page (in Content Manager: *Settings → Custom
   Shaders Patch*).
2. **Install Pure**, following its instructions. In Content Manager go to *Settings → Custom Shaders Patch →
   Weather FX* and select **Pure**.
3. **Download F1 True Conditions**: open [Releases](../../releases/latest) and download
   `F1TrueConditions_vX.X.zip` (not "Source code").
4. **Install it.** Either drag the zip into Content Manager and click **Install**, or extract it into your
   Assetto Corsa folder. The result should be:

   ```
   assettocorsa\apps\lua\F1TrueConditions\
   ```
5. **Weather settings in Content Manager**: on the race/drive screen pick Pure's weather controller
   (Pure Planner) and keep its default **Load last used plan**. The app writes the real
   conditions into that plan before the session starts.

> **Upgrading from "F1 Real Weather"** (the old name, v1.8 or older): delete
> `assettocorsa\apps\lua\F1RealWeather\`. With both installed, two apps load weather at the same time.
> The new app shows a red warning until the old folder is gone.

---

## How to use it

### Automatic (VRC Formula Alpha)

Pick a VRC Formula Alpha car and an F1 track and drive. Nothing else to do:

| Assetto Corsa session | Real conditions used |
|---|---|
| Hotlap, practice, qualifying | the real **Qualifying** |
| Race | the real **Race** |

The app recognises the circuit from the track you loaded (for example `chq_sepang` → Sepang). It uses
the latest season available for that circuit, and the time of day is set to the real session time.

### The pit panel

In the pits (setup screen) a panel opens next to the other setup apps:

- **One column per real session**: Sprint Q, Sprint, Qualifying, Race. Click a column header to switch.
  A red box marks the session in use.
- **Q1 / Q2 / Q3** under Qualifying load the conditions of the **final laps** of that segment and
  show the **real best lap** as your target, e.g. Sepang 2026 Q3: *1:35.130 VER*.
- Rows: air and track temperature, humidity, wind, sky, haze/mist, track surface (dry / damp / wet /
  raining), real local time, real best lap, and whether the data is a **Forecast** or **Timing**
  (measured).
- **On/off switch** (top right): off = the app does nothing, Pure keeps its own weather.
- **Green footer text** = Pure Planner has confirmed it is running the conditions.

The conditions are **fixed for the whole session**. Rain, track wetness and temperatures don't change
while you drive, so every lap is comparable with the real one.

### The main window

Open **F1 True Conditions** from the CSP app bar for manual control:

- Choose **circuit, season, session** (and Q segment) and press **Apply to Pure Planner**. This works with
  any car.
- **Any car**: auto-load with every car, not only the VRC Formula Alpha.
- **Season**: latest (default) or a fixed year (2023 → today).
- **Use real session date & time**: on = the sim clock jumps to the real start time (night races are
  dark). Off = keep your own time of day.
- **Show weather panel in the pits** and **Pit panel size** (scales with 1080p / 1440p / 4K
  automatically).
- **Export all as presets**: saves every session as a Pure Planner preset in
  `Plans\Stamp\F1 True Conditions\`.

---

## How upcoming events are updated

You never need to update the app to get new races. The database lives in this repository and keeps
itself up to date:

```
 every 3 hours                      this GitHub repo                 your game
┌──────────────────┐   commits   ┌──────────────────────┐ download ┌──────────────────────┐
│ GitHub Action     │ ──────────► │ data/*.csv           │ ───────► │ F1 True Conditions   │
│ OpenF1 + Open-Meteo│            │ (sessions, Q1/Q2/Q3, │ at start │  → Pure Planner      │
└──────────────────┘             │  overrides)          │          └──────────────────────┘
                                 └──────────────────────┘
```

**Over a race weekend:**

| When | What you get in the game |
|---|---|
| **Up to 16 days before** a session | A **weather forecast** for the circuit at the real session time. It's refreshed every 3 hours, so it gets more accurate as the weekend approaches. Track temperature is estimated from air temperature and sunshine. Marked **Forecast**. |
| **Qualifying segments** (forecast) | Q1/Q2/Q3 use the forecast at the usual times the segments end |
| **~1–3 hours after the session** | The forecast is replaced by the **measured** conditions from the official timing weather station, plus Q1/Q2/Q3 snapshots and the real best laps. Marked **Timing**. These values are final. |
| **Every game start** | The app downloads the latest database. If the session you are using changed (new forecast, or real data now available), the new conditions go to Pure Planner straight away. |

- A **new circuit** on the calendar (Sepang in 2026, for example) works without an app update. The
  database includes its name and the words used to recognise the AC track.
- **Offline?** The app uses the last downloaded copy, or the copy bundled with the release.
- You can turn downloads off in the main window (**Download updates at start**).

### Overrides (haze and sky)

The timing feed has no data for haze or visibility. To make the sky match reality, the maintainer
adds manual corrections in [`data/f1_weather_overrides.csv`](data/f1_weather_overrides.csv). For example,
2026 Sepang uses scattered clouds with 35 % mist because of the haze across Malaysia. These corrections reach
everyone at their next game start. They only change the sky and mist. Temperatures, wind and rain
always come from the real data. A dry-weather override never changes a rainy session.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| No panel in the pits | Check that CSP is up to date and the app is in `apps\lua\F1TrueConditions\`. Enable *Show weather panel in the pits* in the main window. |
| Weather doesn't change | Weather FX must be set to **Pure** and the weather controller to **Pure Planner / Load last used plan**. Watch the panel footer: it turns green when Pure confirms. |
| "No F1 circuit for this track" | The track's folder name isn't recognised. Use the main window to pick the circuit by hand, or report the track folder name in an issue. |
| Two weather apps / red warning | Delete the old `apps\lua\F1RealWeather\` folder. |
| Not loading with my car | Auto-load is for VRC Formula Alpha by default. Turn on **Any car** in the main window. |

---

## Data sources

| Data | Source |
|---|---|
| Session calendar, measured air/track temperature, humidity, wind, rain, Q1/Q2/Q3 timing and best laps | [OpenF1](https://openf1.org) (official F1 timing data, community API) |
| Cloud cover, rain amount, forecasts, solar radiation | [Open-Meteo](https://open-meteo.com) (CC BY 4.0, *Weather data by Open-Meteo.com*) |
| Haze / sky corrections | Hand-made, in `data/f1_weather_overrides.csv` |

Seasons 2023 → today: qualifying (with Q1/Q2/Q3), sprint qualifying (SQ1/SQ2/SQ3), sprint and race.

OpenF1 is an unofficial project, and F1 True Conditions is not affiliated with Formula 1, CSP or Pure.

---

## Repository contents (for maintainers)

| Path | What it is |
|---|---|
| `app/F1TrueConditions/` | App source (the release zip contains it as `apps/lua/F1TrueConditions/`) |
| `data/f1_weather_db.csv` | One row per session, updated by the Action |
| `data/f1_weather_segments.csv` | Q1/Q2/Q3 and SQ1–SQ3 final-lap snapshots + real best laps |
| `data/f1_weather_overrides.csv` | Manual haze/sky corrections (`year, event, session, segment, when, pure_weather, mist_pct, note`) |
| `tools/update_db.py` | The updater (Python 3, no extra packages) |
| `.github/workflows/update-f1-weather.yml` | Runs the updater every 3 hours and commits changes |
| `SETUP.md` | Maintenance guide, column descriptions and the track temperature model |

## Credits

App and data pipeline by **Me**. Custom Shaders Patch by **x4fab**. Pure and Pure Planner
by **Peter Boese**. Weather data by OpenF1 and Open-Meteo.com.
