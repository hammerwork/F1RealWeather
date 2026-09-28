# Setup and maintenance guide

About 15 minutes, once. After that the database updates itself.

## 1. Put the files in your GitHub repo

**New repo (simplest):** on GitHub → **New repository** → name it e.g. `f1-real-weather` →
**Public** (the app downloads the CSV without logging in, so the repo must be public) → Create.
Then **Add file → Upload files** and drag in everything from this folder, keeping the folders:

```
.github/workflows/update-f1-weather.yml
app/F1RealWeather/...
data/f1_weather_db.csv
tools/update_db.py
README.md
SETUP.md
```

> The `.github` folder is hidden on some systems. If the upload skips it, create the file by
> hand: **Add file → Create new file**, name `.github/workflows/update-f1-weather.yml`, paste
> the contents.

**Existing repo (e.g. your FA26 telemetry repo):** put everything except `.github` in a subfolder,
e.g. `f1-real-weather/`, and put the workflow at the repo root
(`.github/workflows/update-f1-weather.yml`). Then edit the workflow line
`WEATHER_DIR: .` → `WEATHER_DIR: f1-real-weather`.

## 2. Allow the Action to commit

Repo → **Settings → Actions → General → Workflow permissions** → select
**Read and write permissions** → Save.

## 3. Run it once

Repo → **Actions** tab → *Update F1 weather database* → **Run workflow**. It takes about a minute.
A green tick and a new commit "Update F1 weather database (…)" mean it works. From now on it runs
every 3 hours by itself (GitHub may delay scheduled runs by a few minutes; that's normal).

> GitHub pauses scheduled workflows in repos with no activity for 60 days. The Action's own
> commits during the season count as activity; if it ever pauses, press **Enable workflow**.

## 4. Point the app at your CSV

Open `data/f1_weather_db.csv` on GitHub → **Raw**. Copy the address from the browser, e.g.

```
https://raw.githubusercontent.com/<your-name>/f1-real-weather/main/data/f1_weather_db.csv
```

(for the subfolder layout: `…/main/f1-real-weather/data/f1_weather_db.csv`).

Paste it as the only line of `app/F1RealWeather/data/db_url.txt`, commit, and include that file
in the app you give to people. Every copy of the app downloads that address at game start, so you
never need to ship a new app just for new weather data.

## 5. Release the app

Zip the `app/F1RealWeather` folder (the zip should contain `F1RealWeather/manifest.ini` at the top)
and attach it to a GitHub release, or put it in your mod package. Users unzip it into
`assettocorsa\apps\lua\`.

## How updating works during a race weekend

Example: this weekend's round at Sepang (OpenF1 lists it as the *Bahrain Grand Prix* at
*Kuala Lumpur*, qualifying Sat 3 Oct 16:00, race Sun 4 Oct 15:00 local).

| When | What the database holds for Sepang | What drivers get |
|---|---|---|
| Up to 16 days before | `forecast` rows, refreshed every 3 h | Forecast conditions, track temp estimated |
| ~1–3 h after each session | `timing` row from the official weather station | The real conditions |
| During a game session | — | The app downloads at start-up and, if the row it's using changed, pushes the new values to Pure Planner straight away |

New circuits need no app update: the updater writes `display` and `track_keywords` into the CSV.
For Sepang the keywords are `sepang;malaysia;kuala`, which match AC folders like `chq_sepang`.

## Running the updater yourself (optional)

```
python tools/update_db.py            # incremental: new sessions + fresh forecasts
python tools/update_db.py --full     # rebuild everything (~15 min, OpenF1 rate limits)
```

Then commit `data/f1_weather_db.csv`. Handy if GitHub Actions are down or you want to edit rows.

## Fixing or overriding a row

Edit the CSV on GitHub (pencil icon) and commit. Rows with `source = timing` are never
re-downloaded, so hand edits stay. To force a row to be rebuilt, delete it and run the Action.

Common edits:
- **Wrong sky:** change `pure_weather` (15 clear … 19 overcast, 6/7/8 rain).
- **A track mod isn't recognised:** add its folder word to `track_keywords` of every row for that
  circuit, e.g. `sepang;malaysia;kuala;my_sepang_mod`.

## Checking it in game

Main app window → *Shared database*: shows the address, the number of sessions and
"updated HH:MM" after a successful download. The pit panel's **Data** row says `Timing` or
`Forecast` for each session.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Action fails at "git push" | Step 2 (write permissions) not set. |
| Action fails with HTTP 429 | OpenF1 rate limit; the next run retries. For `--full`, run it at a quiet time. |
| App shows "bundled" and no "updated" time | `db_url.txt` still has the placeholder, the repo is private, or the URL is wrong (open it in a browser: it must show plain CSV text). |
| New GP missing | OpenF1 publishes a weekend's schedule a few days before; forecasts appear once it's listed and within 16 days. |
