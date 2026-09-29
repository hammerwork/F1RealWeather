#!/usr/bin/env python3
"""F1 Real Weather — database updater.

Builds data/f1_weather_db.csv: one row per F1 Qualifying / Sprint Qualifying / Sprint / Race
from 2023 to the current season, with the conditions at the start of the session.

Sources (both free, no API key):
  * OpenF1  https://openf1.org        — session calendar + official timing weather feed
                                         (air/track temp, humidity, pressure, wind, rainfall)
  * Open-Meteo https://open-meteo.com — cloud cover + precipitation for the start hour
                                         (historical archive), and forecasts for sessions that
                                         haven't happened yet (next 16 days)

Rows are marked in the `source` column:
  timing   = measured by the official timing weather station (final)
  forecast = Open-Meteo forecast for an upcoming session; track temp is an estimate.
             Replaced by `timing` automatically on the first run after the session.

Incremental: rows already measured (`timing`) are kept and never re-downloaded, so a normal run
only fetches new sessions and refreshes forecasts. Use --full to rebuild everything.

Python 3.8+, standard library only.   Usage:  python tools/update_db.py [--full] [--out PATH]
"""
import argparse, csv, json, math, os, sys, time, urllib.parse, urllib.request
from datetime import datetime, timedelta, timezone

OPENF1 = 'https://api.openf1.org/v1'
ARCHIVE = 'https://archive-api.open-meteo.com/v1/archive'
FORECAST = 'https://api.open-meteo.com/v1/forecast'
GEOCODE = 'https://geocoding-api.open-meteo.com/v1/search'

FIRST_YEAR = 2023
SESSIONS = ['Sprint Qualifying', 'Sprint Shootout', 'Sprint', 'Qualifying', 'Race']
SESSION_ORDER = {'Sprint Shootout': 0, 'Sprint Qualifying': 0, 'Sprint': 1, 'Qualifying': 2, 'Race': 3}
FORECAST_DAYS = 16
TRACK_A, TRACK_B = 4.3, 0.0179      # dry track-temp estimate for forecasts (see forecast_row)
TRACK_WET = 3.5                     # wet track: water keeps it near air temp (median of 20 wet sessions: +4.9)
RAIN_PROB_MIN = 50                  # forecast rain only counts when the model gives it >= 50 %

# OpenF1 circuit_short_name -> (name shown in the app, lat, lon, AC track-folder keywords)
# A circuit missing here still works: it is geocoded by its location name and matched on its own name.
CIRCUITS = {
    'Sakhir':             ('Bahrain',       26.0325,   50.5106, 'bahrain;sakhir'),
    'Jeddah':             ('Jeddah',        21.6319,   39.1044, 'jeddah;saudi'),
    'Melbourne':          ('Melbourne',    -37.8497,  144.9680, 'melbourne;albert;albertpark'),
    'Shanghai':           ('Shanghai',      31.3389,  121.2200, 'shanghai;china'),
    'Suzuka':             ('Suzuka',        34.8431,  136.5410, 'suzuka'),
    'Miami':              ('Miami',         25.9581,  -80.2389, 'miami'),
    'Imola':              ('Imola',         44.3439,   11.7167, 'imola'),
    'Monte Carlo':        ('Monaco',        43.7347,    7.4206, 'monaco;monte'),
    'Catalunya':          ('Barcelona',     41.5700,    2.2611, 'barcelona;catalunya;montmelo'),
    'Montreal':           ('Montreal',      45.5000,  -73.5228, 'montreal;villeneuve;canada'),
    'Spielberg':          ('Red Bull Ring', 47.2197,   14.7647, 'spielberg;redbull;red_bull;rbr;austria'),
    'Silverstone':        ('Silverstone',   52.0786,   -1.0169, 'silverstone'),
    'Hungaroring':        ('Hungaroring',   47.5789,   19.2486, 'hungaroring;hungary'),
    'Spa-Francorchamps':  ('Spa',           50.4372,    5.9714, 'spa;francorchamps'),
    'Zandvoort':          ('Zandvoort',     52.3888,    4.5409, 'zandvoort'),
    'Monza':              ('Monza',         45.6156,    9.2811, 'monza'),
    'Baku':               ('Baku',          40.3725,   49.8533, 'baku;azerbaijan'),
    'Singapore':          ('Singapore',      1.2914,  103.8640, 'singapore;marina_bay;marinabay'),
    'Austin':             ('Austin (COTA)', 30.1328,  -97.6411, 'austin;cota;americas'),
    'Mexico City':        ('Mexico City',   19.4042,  -99.0907, 'mexico;hermanos'),
    'Interlagos':         ('Interlagos',   -23.7036,  -46.6997, 'interlagos;sao_paulo;saopaulo;brazil'),
    'Las Vegas':          ('Las Vegas',     36.1147, -115.1730, 'vegas'),
    'Lusail':             ('Lusail',        25.4900,   51.4542, 'lusail;losail;qatar'),
    'Yas Marina Circuit': ('Abu Dhabi',     24.4672,   54.6031, 'yas;abu_dhabi;abudhabi'),
    'Madring':            ('Madrid',        40.4650,   -3.6150, 'madring;madrid'),
    'Kuala Lumpur':       ('Sepang',         2.7608,  101.7382, 'sepang;malaysia;kuala'),
}

COLUMNS = ['year', 'round', 'meeting', 'circuit', 'country', 'session', 'local_start', 'utc_start',
           'gmt_offset', 'stamp_ts', 'air_c', 'track_c', 'humidity_pct', 'pressure_hpa', 'wind_kmh',
           'wind_dir_deg', 'rain', 'rain_frac', 'cloud_pct', 'precip_mm', 'pure_weather', 'air_min',
           'air_max', 'track_min', 'track_max', 'session_key', 'source', 'display', 'track_keywords']


# --------------------------------------------------------------------------------------------- http
def get_json(url, params=None, tries=6):
    if params:
        url = url + '?' + urllib.parse.urlencode(params)
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'F1RealWeather-updater/1.0'})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < tries - 1:
                time.sleep(3 * (attempt + 1))
                continue
            raise
        except (urllib.error.URLError, TimeoutError):
            if attempt < tries - 1:
                time.sleep(3 * (attempt + 1))
                continue
            raise


def openf1(path, **params):
    data = get_json(f'{OPENF1}/{path}', params)
    time.sleep(0.6)               # stay well under OpenF1's free rate limit
    return data


# --------------------------------------------------------------------------------------------- helpers
def median(values):
    v = sorted(x for x in values if x is not None)
    if not v:
        return None
    n = len(v)
    return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2


def r1(v):
    return None if v is None or (isinstance(v, float) and math.isnan(v)) else round(v, 1)


def parse_offset(s):
    neg = s.startswith('-')
    h, m, sec = [int(x) for x in s.lstrip('-').split(':')]
    d = timedelta(hours=h, minutes=m, seconds=sec)
    return -d if neg else d


def parse_time(s):
    return datetime.fromisoformat(s.replace('Z', '+00:00'))


def circular_mean(degrees):
    degrees = [d for d in degrees if d is not None]
    if not degrees:
        return None
    sx = sum(math.cos(math.radians(d)) for d in degrees)
    sy = sum(math.sin(math.radians(d)) for d in degrees)
    return round((math.degrees(math.atan2(sy, sx)) + 360) % 360)


def pure_weather(wet, rain_at_start, cloud, precip, humidity):
    """Pick the Pure weather preset id."""
    if wet:
        if not rain_at_start:
            return 6                      # rain only inferred from the hour total: keep it light
        if precip is None or precip < 0.3:
            return 6                      # light rain
        return 7 if precip < 2.5 else 8   # rain / heavy rain
    if cloud is None:
        return 16
    if cloud < 10:
        return 23 if (humidity or 0) > 85 else 15   # haze / clear
    if cloud < 30:
        return 16                         # few clouds
    if cloud < 60:
        return 17                         # scattered
    if cloud < 88:
        return 18                         # broken
    return 19                             # overcast


_geo_cache = {}


def circuit_info(short_name, location, country):
    if short_name in CIRCUITS:
        return CIRCUITS[short_name]
    key = (short_name, location)
    if key not in _geo_cache:
        lat = lon = None
        for q in (location, short_name):
            try:
                res = get_json(GEOCODE, {'name': q, 'count': 1}).get('results') or []
                if res:
                    lat, lon = res[0]['latitude'], res[0]['longitude']
                    break
            except Exception:
                pass
        kw = ';'.join(sorted({w for w in (short_name + ' ' + (location or '')).lower().replace('-', ' ').split() if len(w) > 2}))
        _geo_cache[key] = (short_name, lat, lon, kw)
        print(f'  new circuit {short_name!r} ({location}, {country}) -> {lat}, {lon}; keywords {kw}', file=sys.stderr)
    return _geo_cache[key]


def meteo_hour(lat, lon, when_utc, forecast):
    """Hourly Open-Meteo values for the hour containing when_utc + 30 min."""
    if lat is None:
        return {}
    t = (when_utc + timedelta(minutes=30)).replace(minute=0, second=0, microsecond=0)
    day = t.strftime('%Y-%m-%d')
    params = {'latitude': lat, 'longitude': lon, 'start_date': day, 'end_date': day, 'timezone': 'GMT',
              'hourly': 'temperature_2m,relative_humidity_2m,wind_speed_10m,wind_direction_10m,'
                        'cloud_cover,precipitation,shortwave_radiation,surface_pressure'
                        + (',precipitation_probability' if forecast else '')}
    bases = [FORECAST] if forecast else [ARCHIVE, FORECAST]   # archive lags ~5 days; forecast covers that gap
    for base in bases:
        try:
            j = get_json(base, params)
            h = j.get('hourly') or {}
            times = h.get('time') or []
            key = t.strftime('%Y-%m-%dT%H:00')
            if key in times:
                i = times.index(key)
                vals = {k: (h[k][i] if h.get(k) else None) for k in h if k != 'time'}
                if vals.get('cloud_cover') is not None:
                    return vals
        except Exception as e:
            print(f'  open-meteo {base} failed: {e}', file=sys.stderr)
        time.sleep(0.2)
    return {}


# --------------------------------------------------------------------------------------------- rows
def base_row(s, meeting, rnd):
    utc = parse_time(s['date_start'])
    off = parse_offset(s['gmt_offset'])
    local = (utc + off).replace(tzinfo=None)
    disp, lat, lon, kw = circuit_info(s['circuit_short_name'], s.get('location'), s.get('country_name'))
    sign = '-' if s['gmt_offset'].startswith('-') else '+'
    return {
        'year': s['year'], 'round': rnd, 'meeting': (meeting.get('meeting_name') or '').replace(',', ' '),
        'circuit': s['circuit_short_name'], 'country': (s.get('country_name') or '').replace(',', ' '),
        'session': s['session_name'], 'local_start': local.strftime('%Y-%m-%d %H:%M'),
        'utc_start': utc.strftime('%Y-%m-%dT%H:%M:%SZ'), 'gmt_offset': sign + s['gmt_offset'].lstrip('-')[:5],
        'stamp_ts': int((local - datetime(1970, 1, 1)).total_seconds()),
        'session_key': s['session_key'], 'display': disp, 'track_keywords': kw,
    }, (lat, lon), utc


def timing_row(s, meeting, rnd):
    """Measured row from the OpenF1 timing weather feed. None if the feed has no data yet."""
    row, (lat, lon), utc = base_row(s, meeting, rnd)
    w = openf1('weather', session_key=s['session_key'])
    if not w:
        return None
    t0 = utc.timestamp()
    start = [x for x in w if t0 - 300 <= parse_time(x['date']).timestamp() <= t0 + 600]
    use = start if len(start) >= 2 else w[:10]
    f = lambda k: [x.get(k) for x in use if x.get(k) is not None]
    a = lambda k: [x.get(k) for x in w if x.get(k) is not None]
    air, track = r1(median(f('air_temperature'))), r1(median(f('track_temperature')))
    if air is None or track is None:
        return None
    rain_start = any((x or 0) > 0 for x in f('rainfall'))
    rain_frac = r1(sum(1 for x in a('rainfall') if x > 0) / len(w)) if w else 0
    m = meteo_hour(lat, lon, utc, forecast=False)
    cloud, precip = m.get('cloud_cover'), m.get('precipitation')
    # wet start = timing-feed rain flag backed by rain later in the session or measured precipitation,
    # or a wet hour (>= 1 mm) in a session that saw rain; a lone flag is treated as a sensor blip
    wet = (rain_start and (rain_frac > 0 or (precip or 0) >= 0.5)) or ((precip or 0) >= 1.0 and rain_frac > 0)
    mins = lambda vals, med: (r1(min(vals)) if vals and min(vals) >= 0.5 * med else '')
    wind_ms = median(f('wind_speed'))
    row.update({
        'air_c': air, 'track_c': track, 'humidity_pct': r1(median(f('humidity'))),
        'pressure_hpa': r1(median(f('pressure'))),
        'wind_kmh': r1(wind_ms * 3.6) if wind_ms is not None else '',
        'wind_dir_deg': circular_mean(f('wind_direction')) if f('wind_direction') else '',
        'rain': 1 if wet else 0, 'rain_frac': rain_frac,
        'cloud_pct': cloud if cloud is not None else '', 'precip_mm': precip if precip is not None else '',
        'pure_weather': pure_weather(wet, rain_start, cloud, precip, median(f('humidity'))),
        'air_min': mins(a('air_temperature'), air), 'air_max': r1(max(a('air_temperature'))),
        'track_min': mins(a('track_temperature'), track), 'track_max': r1(max(a('track_temperature'))),
        'source': 'timing',
    })
    return row


def forecast_row(s, meeting, rnd):
    """Upcoming session: Open-Meteo forecast for the start hour. Track temperature is estimated
    from air temperature and solar radiation: track = air + 4.3 + 0.0179 * shortwave (W/m²),
    fitted on 95 dry 2023-2026 sessions (RMSE 4.2 °C; Open-Meteo air vs timing air RMSE 1.3 °C).
    In rain the sun term is dropped: a wet track stays a few degrees above air temperature
    (wet 2023-2026 timing sessions: median +4.9 °C, steady rain +1 to +4 °C).
    Rain intensity is capped one step lower than for measured sessions, because a forecast gives an
    hourly (often 3-hourly) total and a probability, not the rain actually falling at lights out."""
    row, (lat, lon), utc = base_row(s, meeting, rnd)
    m = meteo_hour(lat, lon, utc, forecast=True)
    if not m or m.get('temperature_2m') is None:
        return None
    air = m['temperature_2m']
    sw = m.get('shortwave_radiation') or 0
    precip, cloud, hum = m.get('precipitation') or 0, m.get('cloud_cover'), m.get('relative_humidity_2m')
    prob = m.get('precipitation_probability')
    wet = precip >= 0.3 and (prob is None or prob >= RAIN_PROB_MIN)
    track = air + (TRACK_WET if wet else TRACK_A + TRACK_B * sw)
    # forecast rain level: light rain up to 2.5 mm/h, rain up to 7.5, heavy above
    level = (6 if precip < 2.5 else 7 if precip < 7.5 else 8) if wet else None
    row.update({
        'air_c': r1(air), 'track_c': r1(track), 'humidity_pct': r1(hum),
        'pressure_hpa': r1(m.get('surface_pressure')), 'wind_kmh': r1(m.get('wind_speed_10m')),
        'wind_dir_deg': round(m['wind_direction_10m']) if m.get('wind_direction_10m') is not None else '',
        'rain': 1 if wet else 0, 'rain_frac': '', 'cloud_pct': cloud if cloud is not None else '',
        'precip_mm': precip, 'pure_weather': level if wet else pure_weather(False, False, cloud, precip, hum),
        'air_min': '', 'air_max': '', 'track_min': '', 'track_max': '', 'source': 'forecast',
    })
    return row


# --------------------------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'f1_weather_db.csv'))
    ap.add_argument('--full', action='store_true', help='re-download every session')
    ap.add_argument('--now', help='pretend current UTC time (ISO), for testing')
    args = ap.parse_args()
    out = os.path.abspath(args.out)

    kept = {}
    if os.path.exists(out) and not args.full:
        with open(out, newline='', encoding='utf-8') as f:
            for r in csv.DictReader(f):
                if r.get('source', 'timing') in ('timing', '') and r.get('session_key'):
                    kept[int(r['session_key'])] = r

    now = parse_time(args.now) if args.now else datetime.now(timezone.utc)
    rows, counts = [], {'kept': 0, 'timing': 0, 'forecast': 0, 'pending': 0}
    for year in range(FIRST_YEAR, now.year + 1):
        meetings = {m['meeting_key']: m for m in openf1('meetings', year=year)}
        sessions = [s for s in openf1('sessions', year=year)
                    if s['session_name'] in SESSIONS and not s.get('is_cancelled')
                    and 'testing' not in (meetings.get(s['meeting_key'], {}).get('meeting_name') or '').lower()]
        # round = order of (non-cancelled) Grand Prix weekends in the season
        order = sorted({s['meeting_key'] for s in sessions}, key=lambda k: min(x['date_start'] for x in sessions if x['meeting_key'] == k))
        rnd = {k: i + 1 for i, k in enumerate(order)}
        for s in sessions:
            key, m = s['session_key'], meetings.get(s['meeting_key'], {})
            start = parse_time(s['date_start'])
            end = parse_time(s['date_end']) if s.get('date_end') else start + timedelta(hours=2)
            if key in kept:
                r = kept[key]
                r['round'] = rnd[s['meeting_key']]                      # rounds shift if races are cancelled
                disp, _, _, kw = circuit_info(s['circuit_short_name'], s.get('location'), s.get('country_name'))
                r['display'], r['track_keywords'], r['source'] = r.get('display') or disp, r.get('track_keywords') or kw, 'timing'
                rows.append(r); counts['kept'] += 1
                continue
            row = None
            if start <= now:
                print(f'{year} {s["circuit_short_name"]} {s["session_name"]}: timing data', file=sys.stderr)
                row = timing_row(s, m, rnd[s['meeting_key']])
                if row: counts['timing'] += 1
            if row is None and start <= now + timedelta(days=FORECAST_DAYS) and end >= now - timedelta(days=2):
                # upcoming, or just finished and not in the timing feed yet
                print(f'{year} {s["circuit_short_name"]} {s["session_name"]}: forecast', file=sys.stderr)
                row = forecast_row(s, m, rnd[s['meeting_key']])
                if row: counts['forecast'] += 1
            if row:
                rows.append(row)
            elif start > now:
                counts['pending'] += 1

    rows.sort(key=lambda r: (int(r['year']), int(r['round']), SESSION_ORDER.get(r['session'], 9)))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + '.tmp'
    with open(tmp, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS, lineterminator='\n', extrasaction='ignore')
        w.writeheader()
        for r in rows:
            w.writerow({k: ('' if r.get(k) is None else r.get(k)) for k in COLUMNS})
    os.replace(tmp, out)
    print(f'wrote {len(rows)} sessions to {out}  ({counts})', file=sys.stderr)


if __name__ == '__main__':
    main()
