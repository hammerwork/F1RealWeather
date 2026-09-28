# F1 Real Weather

A CSP Lua app for Assetto Corsa that loads the **real conditions of F1 qualifying, sprint and
race sessions (2023 → today)** into [Pure Planner](https://www.overtake.gg/threads/pure-planner.291023/).
Every user's app downloads the shared database from this repository at start-up, and a GitHub
Action keeps it up to date: forecasts before a Grand Prix, official timing data afterwards.

```
GitHub Action (every 3 h)                     this repo                        every user's app
  tools/update_db.py  ──► commits ──►  data/f1_weather_db.csv  ──► downloaded at game start ──► Pure Planner
  (OpenF1 + Open-Meteo)
```

## Contents

| Path | What it is |
|---|---|
| `app/F1RealWeather/` | The app. Copy to `assettocorsa\apps\lua\F1RealWeather\` |
| `app/F1RealWeather/data/db_url.txt` | The address every app downloads the database from (one line) |
| `data/f1_weather_db.csv` | The shared database (updated by the Action) |
| `tools/update_db.py` | Builds / updates the database. Python 3.8+, no extra packages |
| `.github/workflows/update-f1-weather.yml` | Runs the updater every 3 hours and commits changes |
| `SETUP.md` | Step-by-step setup and maintenance guide |

## Where the data comes from

| Data | Source | Notes |
|---|---|---|
| Session calendar, times, time zones | **OpenF1** — `api.openf1.org/v1/sessions`, `/meetings` | Official F1 timing, free, no key. Cancelled sessions are skipped. |
| Air temp, track temp, humidity, pressure, wind speed + direction, rainfall flag | **OpenF1** — `api.openf1.org/v1/weather` | The circuit's timing weather station, roughly one sample per minute. The database stores the median from 5 min before to 10 min after the session start; min/max cover the whole session. |
| Cloud cover and precipitation (sky type) | **Open-Meteo Historical Weather API** — `archive-api.open-meteo.com` | Hourly reanalysis at the circuit coordinates for the start hour. The timing feed has no cloud data. |
| Upcoming sessions (next 16 days) | **Open-Meteo Forecast API** — `api.open-meteo.com` | Air temp, humidity, wind, cloud, rain, solar radiation for the start hour. Marked `source = forecast`. |
| Track temperature for forecasts | Estimated | `track = air + 4.3 + 0.0179 × solar radiation (W/m²)`, fitted on 95 dry 2023–2026 sessions (typical error ±4 °C). Replaced by the measured value after the session. |
| New circuits (not in the built-in list) | **Open-Meteo Geocoding API** | Coordinates found from the location name; the circuit name becomes the track keyword. |

OpenF1 is an unofficial community project and not affiliated with Formula 1. Open-Meteo data is
CC BY 4.0 — credit "Weather data by Open-Meteo.com" if you publish it.

## Database columns

`year, round, meeting, circuit, country, session, local_start, utc_start, gmt_offset, stamp_ts,
air_c, track_c, humidity_pct, pressure_hpa, wind_kmh, wind_dir_deg, rain, rain_frac, cloud_pct,
precip_mm, pure_weather, air_min, air_max, track_min, track_max, session_key, source, display,
track_keywords`

- `source`: `timing` (measured, final) or `forecast` (upcoming session, refreshed every run).
- `display`: name shown in the app (e.g. `Sepang` for OpenF1's `Kuala Lumpur`).
- `track_keywords`: `;`-separated words matched against the AC track folder name (e.g. `chq_sepang`).
  Add your own if a track mod uses an unusual folder name.
- `pure_weather`: Pure weather preset id (15 clear, 16 few clouds, 17 scattered, 18 broken,
  19 overcast, 23 haze, 6 light rain, 7 rain, 8 heavy rain). You can override it by hand.
- `stamp_ts`: local start time as a Unix timestamp (AC / Pure convention: local wall clock).

## License

Tooling: CC0. Weather data: OpenF1 (community API) and Open-Meteo (CC BY 4.0).
