-- F1 Real Weather v1.1 — real F1 session conditions as Pure Planner presets
--
-- Auto mode (default on for VRC Formula Alpha cars):
--   * At session load the app writes the matching plan to Pure Planner's Plans\last_used.json
--     BEFORE Pure Planner starts (apps load alphabetically: F1RealWeather < PurePlanner). With the
--     Pure controller set to "Load last used plan" (Content Manager default) Pure Planner then
--     starts on it natively.
--   * Hotlap / practice / qualifying → the real Qualifying session. Race → the real Race.
--   * When the AC session changes (practice → qualifying → race weekend) the new plan is pushed to
--     Pure Planner through its controller state and confirmed by reading back Pure's live air temp.
-- Pit window ("F1 Weather — Pits"): shown in the setup screen while in the pits.

local APP_DIR     = ac.dirname()
local DB_BUNDLED  = APP_DIR .. '\\data\\f1_weather_db.csv'
local DB_CACHE    = APP_DIR .. '\\data\\f1_weather_db_online.csv'
-- URL of the shared database everyone downloads (one line; set by the mod author in data\\db_url.txt)
local OFFICIAL_URL = ((io.load(APP_DIR .. '\\data\\db_url.txt', '') or ''):match('^%s*(%S+)') or '')
if OFFICIAL_URL:find('YOUR_', 1, true) then OFFICIAL_URL = '' end   -- placeholder not filled in yet
local PLANS_DIR   = ac.getFolder(ac.FolderID.ExtRoot) .. '\\config-ext\\PurePlanner\\Plans\\'
local LAST_USED   = PLANS_DIR .. 'last_used.json'
local SUBFOLDER   = 'F1 Real Weather'

local settings = ac.storage({
  dbUrl       = '',            -- personal override; empty = use data\\db_url.txt
  autoUpdate  = true,          -- download the shared database at every start
  realTime    = true,          -- Stamp plan at the real local start time (else Daycycle, keeps sim time)
  autoDetect  = true,          -- select circuit from the loaded AC track
  autoTrigger = true,          -- manual Apply also pushes the plan into Pure Planner
  autoApply   = true,          -- apply automatically at load / session change
  autoAnyCar  = false,         -- false: only for cars whose id contains carFilter
  carFilter   = 'vrc_formula_alpha',
  autoYear    = 0,             -- 0 = latest season available for the circuit
  pitPanel    = true,          -- show the weather panel in the pit / setup screen
  pitX        = 40,
  pitY        = 160,
  pitSize     = 1.0,           -- personal size multiplier on top of screen-resolution scaling
})

---------------------------------------------------------------------------------------------------
-- Circuits: OpenF1 circuit name → display name + keywords to match AC track folder names
---------------------------------------------------------------------------------------------------
local CIRCUITS = {
  ['Sakhir']             = { 'Bahrain',        { 'bahrain', 'sakhir' } },
  ['Jeddah']             = { 'Jeddah',         { 'jeddah', 'saudi' } },
  ['Melbourne']          = { 'Melbourne',      { 'melbourne', 'albert', 'albertpark' } },
  ['Shanghai']           = { 'Shanghai',       { 'shanghai', 'china' } },
  ['Suzuka']             = { 'Suzuka',         { 'suzuka' } },
  ['Miami']              = { 'Miami',          { 'miami' } },
  ['Imola']              = { 'Imola',          { 'imola' } },
  ['Monte Carlo']        = { 'Monaco',         { 'monaco', 'monte' } },
  ['Catalunya']          = { 'Barcelona',      { 'barcelona', 'catalunya', 'montmelo' } },
  ['Montreal']           = { 'Montreal',       { 'montreal', 'villeneuve', 'canada' } },
  ['Spielberg']          = { 'Red Bull Ring',  { 'spielberg', 'redbull', 'red_bull', 'rbr', 'austria' } },
  ['Silverstone']        = { 'Silverstone',    { 'silverstone' } },
  ['Hungaroring']        = { 'Hungaroring',    { 'hungaroring', 'hungary' } },
  ['Spa-Francorchamps']  = { 'Spa',            { 'spa', 'francorchamps' } },
  ['Zandvoort']          = { 'Zandvoort',      { 'zandvoort' } },
  ['Monza']              = { 'Monza',          { 'monza' } },
  ['Baku']               = { 'Baku',           { 'baku', 'azerbaijan' } },
  ['Singapore']          = { 'Singapore',      { 'singapore', 'marina_bay', 'marinabay' } },
  ['Austin']             = { 'Austin (COTA)',  { 'austin', 'cota', 'americas' } },
  ['Mexico City']        = { 'Mexico City',    { 'mexico', 'hermanos' } },
  ['Interlagos']         = { 'Interlagos',     { 'interlagos', 'sao_paulo', 'saopaulo', 'brazil' } },
  ['Las Vegas']          = { 'Las Vegas',      { 'vegas' } },
  ['Lusail']             = { 'Lusail',         { 'lusail', 'losail', 'qatar' } },
  ['Yas Marina Circuit'] = { 'Abu Dhabi',      { 'yas', 'abu_dhabi', 'abudhabi' } },
  ['Madring']            = { 'Madrid',         { 'madring', 'madrid' } },
  ['Kuala Lumpur']       = { 'Sepang',         { 'sepang', 'malaysia', 'kuala' } },
}

local function displayName(circuit)
  local c = CIRCUITS[circuit]
  return c and c[1] or circuit
end

---------------------------------------------------------------------------------------------------
-- Pure weather presets used here (ids + rain parameters from Pure Planner's default table)
---------------------------------------------------------------------------------------------------
local WEATHER_NAMES = {
  [15] = 'Clear', [16] = 'Few clouds', [17] = 'Scattered clouds', [18] = 'Broken clouds',
  [19] = 'Overcast', [21] = 'Mist', [23] = 'Haze', [3] = 'Light drizzle', [4] = 'Drizzle',
  [6] = 'Light rain', [7] = 'Rain', [8] = 'Heavy rain', [0] = 'Light thunderstorm', [1] = 'Thunderstorm',
}
--                 rain_amount, probability, variance, wetness, water
local RAIN_PRESET = {
  [3] = { 0.001, 0.6, 0.6, 0.005, 0.1 },
  [4] = { 0.02,  0.8, 0.5, 0.04,  0.5 },
  [6] = { 0.05,  0.6, 0.8, 0.05,  0.3 },
  [7] = { 0.125, 0.8, 0.6, 0.125, 0.6 },
  [8] = { 0.6,   0.9, 0.4, 0.6,   1.0 },
  [0] = { 0.1,   0.5, 0.7, 0.1,   0.2 },
  [1] = { 0.2,   0.7, 0.5, 0.15,  0.4 },
}

---------------------------------------------------------------------------------------------------
-- CSV database
---------------------------------------------------------------------------------------------------
local function parseCsvLine(line)
  local out, i, n = {}, 1, #line
  while i <= n + 1 do
    if line:sub(i, i) == '"' then
      local buf, j = {}, i + 1
      while j <= n do
        local ch = line:sub(j, j)
        if ch == '"' then
          if line:sub(j + 1, j + 1) == '"' then buf[#buf + 1] = '"'; j = j + 2
          else j = j + 1; break end
        else buf[#buf + 1] = ch; j = j + 1 end
      end
      out[#out + 1] = table.concat(buf)
      i = j + 1
    else
      local j = line:find(',', i, true) or (n + 1)
      out[#out + 1] = line:sub(i, j - 1)
      i = j + 1
    end
  end
  return out
end

local NUMERIC = {
  year = true, stamp_ts = true, air_c = true, track_c = true, humidity_pct = true, pressure_hpa = true,
  wind_kmh = true, wind_dir_deg = true, rain = true, rain_frac = true, cloud_pct = true, precip_mm = true,
  pure_weather = true, air_min = true, air_max = true, track_min = true, track_max = true, round = true,
}

local function parseCsv(text)
  local rows, header = {}, nil
  for line in (text .. '\n'):gmatch('([^\r\n]*)\r?\n') do
    if line ~= '' then
      local f = parseCsvLine(line)
      if not header then
        header = f
      else
        local r = {}
        for k = 1, #header do
          local key, v = header[k], f[k]
          if NUMERIC[key] then v = tonumber(v) end
          r[key] = v
        end
        if r.circuit and r.circuit ~= '' and r.year and r.session then rows[#rows + 1] = r end
      end
    end
  end
  return rows
end

local db = { rows = {}, circuits = {}, byName = {}, source = '' }

local function indexDb(rows, source)
  local byCircuit = {}
  for _, r in ipairs(rows) do
    local c = byCircuit[r.circuit]
    if not c then
      c = { name = r.circuit, display = (r.display ~= nil and r.display ~= '') and r.display or displayName(r.circuit),
            years = {}, byYear = {}, keywords = {} }
      local seen = {}
      local function addKw(k) k = k:lower():gsub('^%s+', ''):gsub('%s+$', ''); if k ~= '' and not seen[k] then seen[k] = true; c.keywords[#c.keywords + 1] = k end end
      for k in ((r.track_keywords or '') .. ';'):gmatch('([^;]*);') do addKw(k) end
      for _, k in ipairs(CIRCUITS[r.circuit] and CIRCUITS[r.circuit][2] or {}) do addKw(k) end
      if #c.keywords == 0 then addKw(r.circuit:gsub('[%s%-]+', '_')) end
      byCircuit[r.circuit] = c
    end
    if not c.byYear[r.year] then c.byYear[r.year] = {}; c.years[#c.years + 1] = r.year end
    table.insert(c.byYear[r.year], r)
  end
  local list = {}
  for _, c in pairs(byCircuit) do
    table.sort(c.years, function(a, b) return a > b end)
    for _, s in pairs(c.byYear) do table.sort(s, function(a, b) return (a.stamp_ts or 0) < (b.stamp_ts or 0) end) end
    list[#list + 1] = c
  end
  table.sort(list, function(a, b) return a.display < b.display end)
  db.rows, db.circuits, db.byName, db.source = rows, list, byCircuit, source
end

-- use the downloaded copy unless the bundled file (e.g. a newer app release) has more sessions
local function loadDb()
  local cached = parseCsv(io.load(DB_CACHE, '') or '')
  local bundled = parseCsv(io.load(DB_BUNDLED, '') or '')
  if #cached >= 5 and #cached >= #bundled then indexDb(cached, 'online copy') else indexDb(bundled, 'bundled') end
end
loadDb()

---------------------------------------------------------------------------------------------------
-- Minimal JSON encoder (Pure Planner plan files are JSON)
---------------------------------------------------------------------------------------------------
local function jsonEncode(v)
  local t = type(v)
  if t == 'nil' then return 'null'
  elseif t == 'boolean' then return v and 'true' or 'false'
  elseif t == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then return '0' end
    if math.floor(v) == v and math.abs(v) < 1e15 then return string.format('%d', v) end
    return string.format('%.6g', v)
  elseif t == 'string' then
    return '"' .. v:gsub('[%c"\\]', function(c)
      local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
      return map[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
  elseif t == 'table' then
    if #v > 0 or next(v) == nil then
      local parts = {}
      for i = 1, #v do parts[i] = jsonEncode(v[i]) end
      return '[' .. table.concat(parts, ',') .. ']'
    end
    local keys, parts = {}, {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do parts[#parts + 1] = jsonEncode(k) .. ':' .. jsonEncode(v[k]) end
    return '{' .. table.concat(parts, ',') .. '}'
  end
  return 'null'
end

---------------------------------------------------------------------------------------------------
-- Plan building
---------------------------------------------------------------------------------------------------
local PLAN_TYPE = { day = 1, timed = 2, stamp = 3 }
local PLAN_FOLDER = { [1] = 'Daycycle', [2] = 'Timed', [3] = 'Stamp' }

local function clamp(v, a, b) v = tonumber(v) or a; return math.max(a, math.min(b, v)) end

local function buildWeather(r)
  local id = r.pure_weather or 16
  local rp = RAIN_PRESET[id]
  local wet = rp ~= nil
  local hum = clamp((r.humidity_pct or 50) / 100, 0, 1)
  local w = {
    index            = id,
    rain_amount      = wet and rp[1] or 0,
    rain_probability = wet and rp[2] or 0,
    rain_variance    = wet and rp[3] or 0,
    rain_wetness     = wet and rp[4] or 0,
    rain_water       = wet and rp[5] or 0,
    wind_direction   = clamp(r.wind_dir_deg or 0, 0, 360),
    wind_strength    = clamp(r.wind_kmh or 0, 0, 150),
    humidity         = hum,
    mist             = hum > 0.93 and clamp((hum - 0.93) / 0.07 * 0.3, 0, 0.3) or 0,
    temp_air         = clamp(r.air_c, 0, 45),
    temp_road        = clamp(r.track_c, 0, 80),
    trans_auto = true, trans_look_A = 0.5, trans_look_B = 1, trans_data_A = 0.5, trans_data_B = 1,
    temp_air_dyn = false, temp_road_dyn = false, humidity_dyn = false, mist_dyn = false,
    rain_amount_dyn = false,
    rain_wetness_dyn = wet, rain_water_dyn = wet,
  }
  for _, k in ipairs({ 'rain_amount', 'rain_probability', 'rain_variance', 'rain_wetness', 'rain_water', 'humidity',
                       'mist', 'temp_air', 'temp_road', 'wind_direction', 'wind_strength' }) do
    w[k .. '_range'] = 0
  end
  return w
end

-- realTime → Stamp plan at the real local start (sim clock jumps there);
-- otherwise a Daycycle plan: same conditions all day, sim time untouched.
local function buildPlan(r, realTime)
  local typ, ts, dur
  if realTime then
    typ, ts, dur = PLAN_TYPE.stamp, r.stamp_ts, 4 * 3600
  else
    typ, ts, dur = PLAN_TYPE.day, math.floor((ac.getSim().timestamp or 0) / 86400) * 86400, 86400
  end
  return {
    control = { type = typ, loop = not realTime, timemulti = 1 },
    container = { { data = { timestamp = ts, duration = dur, weather = buildWeather(r) } } },
  }
end

local function safeName(s)
  return (tostring(s or ''):gsub('[\\/:%*%?"<>|]', ''):gsub('%s+', '_'))
end

-- plan path relative to the Pure Planner Plans folder, without .json (what PURE.initPlan expects)
local function planRelPath(r, realTime)
  return string.format('%s\\%s\\%d\\%02d_%s_%s', realTime and 'Stamp' or 'Daycycle', SUBFOLDER, r.year, r.round or 0,
    safeName(displayName(r.circuit)), safeName(r.session))
end

local function writePlan(r, realTime, alsoLastUsed)
  local rel = planRelPath(r, realTime)
  local file = PLANS_DIR .. rel .. '.json'
  local json = jsonEncode(buildPlan(r, realTime))
  io.createDir(file:match('^(.*)\\[^\\]+$'))
  local ok = io.save(file, json) ~= false
  if alsoLastUsed then io.save(LAST_USED, json) end
  return ok, rel, file
end

---------------------------------------------------------------------------------------------------
-- Link to Pure Planner's shared controller state (the struct Pure Planner registers itself)
---------------------------------------------------------------------------------------------------
local link = { conn = nil, sync = nil, msg = {}, val = {}, nameMSG = 'PurePlanner_ControllerStateMSG',
               nameVAL = 'PurePlanner_ControllerStateVAL' }

local function linkConnect()
  local struct = ac.load('PurePlanner_ControllerStateSTRUCT')
  if type(struct) ~= 'string' or #struct < 10 then link.conn = nil; return false end
  local sync = ac.load('PurePlanner_ControllerStateSYNC')
  if link.conn and sync == link.sync then return true end
  local ok, c = pcall(ac.connect, struct, true, ac.SharedNamespace.Shared)
  if not ok or not c then link.conn = nil; return false end
  local nMsg = tonumber(struct:match('StateMSG%[(%d+)%]')) or 0
  local nVal = tonumber(struct:match('StateVAL%[(%d+)%]')) or 0
  link.msg, link.val = {}, {}
  local okScan = pcall(function()
    for i = 0, nMsg - 1 do
      local e = c[link.nameMSG][i]; if not e then break end
      local n = ffi.string(e.name)
      if n == '' then break end
      link.msg[n] = i
    end
    for i = 0, nVal - 1 do
      local e = c[link.nameVAL][i]; if not e then break end
      local n = ffi.string(e.name)
      if n == '' then break end
      link.val[n] = i
    end
  end)
  if not okScan then link.conn = nil; return false end
  link.conn, link.sync = c, sync
  return link.msg['PURE.initPlan'] ~= nil and link.val['PureCtrl.restarted'] ~= nil
end

local function linkGetString(name)
  local i = link.msg[name]; if not i or not link.conn then return nil end
  return ffi.string(link.conn[link.nameMSG][i].strValue)
end
local function linkSetString(name, s)
  local i = link.msg[name]; if i and link.conn then link.conn[link.nameMSG][i].strValue = s end
end
local function linkGetValue(name)
  local i = link.val[name]; if not i or not link.conn then return nil end
  return link.conn[link.nameVAL][i].dValue
end
local function linkSetValue(name, v)
  local i = link.val[name]; if i and link.conn then link.conn[link.nameVAL][i].dValue = v end
end

---------------------------------------------------------------------------------------------------
-- Sync engine: write plan, then make sure Pure Planner is actually running it
---------------------------------------------------------------------------------------------------
-- phases: idle → waiting (for Pure's own start-up load) → pushing (initPlan+restart) → confirmed | failed
local sync = { row = nil, rel = nil, phase = 'idle', t = 0, tries = 0, restore = nil, pureAir = nil, msg = '' }

-- Pure Planner publishes the temperatures it is currently driving; both must match the plan
local function isApplied(r)
  if not linkConnect() then return false end
  local air, road = linkGetValue('weather.temp.ambient'), linkGetValue('weather.temp.road')
  sync.pureAir = air
  return air ~= nil and road ~= nil
    and math.abs(air - clamp(r.air_c, 0, 45)) < 0.2 and math.abs(road - clamp(r.track_c, 0, 80)) < 0.2
end

-- viaStartup: true at session load (Pure Planner will read last_used.json by itself first)
local function applyRow(r, viaStartup)
  local ok, rel, file = writePlan(r, settings.realTime, true)
  if not ok then sync.phase, sync.msg = 'failed', 'Could not write ' .. file; return end
  sync.row, sync.rel, sync.t, sync.tries = r, rel, 0, 0
  sync.phase = viaStartup and 'waiting' or 'pushing'
  sync.msg = viaStartup and 'Waiting for Pure Planner to start…' or 'Sending to Pure Planner…'
end

local function pushNow()
  if not linkConnect() then return false end
  if (linkGetValue('ctrl.type') or 0) > 0 then
    sync.phase, sync.msg = 'failed', 'Pure runs its static controller. Pick "Pure Planner" as weather controller in CM.'
    return false
  end
  if sync.restore == nil then sync.restore = linkGetString('PURE.initPlan') or '' end
  linkSetString('PURE.initPlan', sync.rel)
  linkSetValue('PureCtrl.restarted', 1)
  sync.tries = sync.tries + 1
  return true
end

local function finishPush()
  if sync.restore ~= nil and link.conn then linkSetString('PURE.initPlan', sync.restore) end
  sync.restore = nil
end

local function syncUpdate(dt)
  if sync.phase == 'idle' or sync.phase == 'confirmed' or sync.phase == 'failed' or sync.phase == 'off' then return end
  sync.t = sync.t + dt
  if isApplied(sync.row) then
    finishPush()
    sync.phase, sync.msg = 'confirmed', string.format('Pure Planner is running it (air %.1f °C)', sync.pureAir)
    return
  end
  if sync.phase == 'checking' then
    if sync.t > 60 then
      sync.phase = 'failed'
      sync.msg = 'Pure Planner did not switch. Saved as Plans\\' .. sync.rel .. '.json — load it in Pure Planner.'
    end
    return
  end
  if sync.phase == 'waiting' then
    -- give Pure Planner up to 12 s to start on last_used.json by itself, then push
    if sync.t > 12 then sync.phase, sync.t = 'pushing', 0 end
    return
  end
  -- pushing
  if not link.conn and not linkConnect() then
    if sync.t > 20 then sync.phase, sync.msg = 'failed', 'Pure Planner not found. Is Pure the active weather in CM?' end
    return
  end
  if sync.tries == 0 then
    if pushNow() then sync.pushT = 0 end
    return
  end
  sync.pushT = (sync.pushT or 0) + dt
  if sync.pushT < 1.0 then
    linkSetString('PURE.initPlan', sync.rel)      -- hold the name while Pure Planner picks it up
  elseif sync.pushT > 6 then
    if sync.tries < 3 then
      if pushNow() then sync.pushT = 0 end
    else
      finishPush()
      sync.phase, sync.t = 'checking', 0
      sync.msg = 'Sent to Pure Planner, waiting for it to take effect…'
    end
  end
end

---------------------------------------------------------------------------------------------------
-- Selection helpers
---------------------------------------------------------------------------------------------------
local sel = { circuit = nil, year = nil, idx = 1 }
local pit = { lastWindowDraw = -10, overlay = false, tried = false, menuT = 0 }   -- pit-screen panel state
local detectedTrack, carId = '', ''
pcall(function() carId = (ac.getCarID(0) or ''):lower() end)

local function detectTrack()
  local id, full = '', ''
  pcall(function() id = (ac.getTrackID() or '') end)
  pcall(function() full = (ac.getTrackFullID('_') or '') end)
  detectedTrack = id
  local hay = (id .. ' ' .. full):lower()
  for _, c in ipairs(db.circuits) do
    for _, kw in ipairs(c.keywords or {}) do
      if hay:find(kw, 1, true) then return c end
    end
  end
  return nil
end

local function findIdx(list, sessionName)
  for i, r in ipairs(list) do if r.session == sessionName then return i end end
  return nil
end

local function selectCircuit(c, year, sessionName)
  sel.circuit = c
  sel.year = c and (year and c.byYear[year] and year or c.years[1]) or nil
  sel.idx = 1
  if c and sel.year then
    local list = c.byYear[sel.year]
    sel.idx = findIdx(list, sessionName or 'Race') or findIdx(list, 'Qualifying') or 1
  end
end

local function currentRow()
  if not sel.circuit or not sel.year then return nil end
  local list = sel.circuit.byYear[sel.year]
  return list and list[sel.idx]
end

-- AC session → real F1 session: race → Race, everything else (hotlap, practice, qualify) → Qualifying
local function acSessionType()
  local t = 0
  pcall(function() t = ac.getSim().raceSessionType or 0 end)
  return t
end
local function wantedSession(t) return t == ac.SessionType.Race and 'Race' or 'Qualifying' end
local SESSION_LABEL = { [0] = 'Session', [1] = 'Practice', [2] = 'Qualifying', [3] = 'Race', [4] = 'Hotlap',
                        [5] = 'Time attack', [6] = 'Drift', [7] = 'Drag' }

local function carMatches()
  if settings.autoAnyCar then return true end
  local f = (settings.carFilter or ''):lower()
  return f ~= '' and carId:find(f, 1, true) ~= nil
end

local autoState = { active = false, circuit = nil, reason = '' }

local function autoApply(viaStartup)
  if not settings.autoApply then
    autoState.active, autoState.reason = false, 'F1 Real Weather is off'
    sync.phase, sync.msg = 'off', 'F1 Real Weather is off — Pure Planner keeps its current plan'
    return
  end
  if not carMatches() then autoState.active, autoState.reason = false, 'Car ' .. carId .. ' is not a match'; return end
  local c = detectTrack()
  if not c then autoState.active, autoState.reason = false, 'No F1 circuit matches track "' .. detectedTrack .. '"'; return end
  local year = settings.autoYear ~= 0 and settings.autoYear or nil
  selectCircuit(c, year, wantedSession(acSessionType()))
  local r = currentRow()
  if not r then return end
  autoState.active, autoState.circuit, autoState.reason = true, c, ''
  applyRow(r, viaStartup)
end

---------------------------------------------------------------------------------------------------
-- Start-up + session tracking
---------------------------------------------------------------------------------------------------
if settings.autoDetect then selectCircuit(detectTrack()) end
if not sel.circuit then selectCircuit(db.circuits[1]) end
autoApply(true)
-- (automatic database download is started at the end of the file, once refreshDb exists)

local lastSessionIndex, lastSessionType = nil, nil
pcall(function() lastSessionIndex = ac.getSim().currentSessionIndex end)
lastSessionType = acSessionType()

function script.update(dt)
  local idx
  pcall(function() idx = ac.getSim().currentSessionIndex end)
  local t = acSessionType()
  if (idx ~= nil and idx ~= lastSessionIndex) or t ~= lastSessionType then
    local changed = wantedSession(t) ~= wantedSession(lastSessionType or 0)
    lastSessionIndex, lastSessionType = idx, t
    if changed and autoState.active then autoApply(false) end
  end
  syncUpdate(dt)

  -- pit / setup screen: open our setup window; if CSP doesn't show it, draw it as an overlay
  local inMenu = false
  pcall(function() inMenu = ac.getSim().isInMainMenu end)
  if inMenu and settings.pitPanel then
    pit.menuT = pit.menuT + dt
    if not pit.tried then pit.tried = true; pcall(ac.setWindowOpen, 'pit', true) end
    -- only fall back to the overlay while CSP isn't drawing our setup window itself
    pit.overlay = pit.menuT > 1.5 and os.clock() - (pit.lastWindowDraw or -10) > 0.5
  else
    pit.menuT, pit.overlay = 0, false
  end
end

---------------------------------------------------------------------------------------------------
-- Manual actions
---------------------------------------------------------------------------------------------------
local function applyManual(r)
  if settings.autoTrigger then
    applyRow(r, false)
  else
    local ok, rel = writePlan(r, settings.realTime, false)
    sync.row, sync.rel = r, rel
    sync.phase, sync.msg = ok and 'confirmed' or 'failed', ok and ('Saved Plans\\' .. rel .. '.json') or 'Could not save plan'
  end
end

local function exportAll()
  local n = 0
  for _, r in ipairs(db.rows) do if writePlan(r, true, false) then n = n + 1 end end
  sync.phase, sync.msg = 'confirmed', string.format('Exported %d Stamp presets to Plans\\Stamp\\%s', n, SUBFOLDER)
end

local refreshing, lastUpdate = false, nil
local function dbUrl() return (settings.dbUrl ~= '' and settings.dbUrl) or OFFICIAL_URL end

local function rowChanged(a, b)
  if not a or not b then return a ~= b end
  for _, k in ipairs({ 'air_c', 'track_c', 'humidity_pct', 'wind_kmh', 'wind_dir_deg', 'pure_weather', 'rain', 'source' }) do
    if a[k] ~= b[k] then return true end
  end
  return false
end

-- silent = automatic start-up update (no status message unless something changes)
local function refreshDb(silent)
  local url = dbUrl()
  if url == '' then if not silent then sync.phase, sync.msg = 'failed', 'No shared database URL set.' end; return end
  refreshing = true
  web.get(url, function(err, response)
    refreshing = false
    if err or not response or not response.body or (response.status and response.status >= 400) then
      if not silent then sync.phase, sync.msg = 'failed', 'Download failed: ' .. tostring(err or response and response.status) end
      return
    end
    local rows = parseCsv(response.body)
    if #rows < 5 then if not silent then sync.phase, sync.msg = 'failed', 'Download is not a valid F1 weather CSV.' end; return end
    io.save(DB_CACHE, response.body)
    lastUpdate = os.date('%H:%M')
    local keepC, keepY, cur = sel.circuit and sel.circuit.name, sel.year, currentRow()
    local keepS = cur and cur.session
    indexDb(rows, 'online copy')
    selectCircuit(db.byName[keepC] or detectTrack() or db.circuits[1], keepY, keepS)
    -- a new circuit (first race there) may only be recognisable with the new data
    if autoState.active or (settings.autoApply and not autoState.active and carMatches()) then
      local wasWaiting = sync.phase == 'waiting'
      local before = sync.row
      if autoState.active then
        local r = currentRow()
        if r and rowChanged(before, r) then applyRow(r, wasWaiting) end
      else
        autoApply(false)
      end
    elseif not silent then
      sync.phase, sync.msg = 'confirmed', string.format('Database updated: %d sessions.', #rows)
    end
  end)
end

local function resetToBundled()
  io.save(DB_CACHE, '')
  loadDb()
  selectCircuit(detectTrack() or db.circuits[1])
  sync.phase, sync.msg = 'confirmed', 'Using bundled database.'
end

---------------------------------------------------------------------------------------------------
-- Shared drawing helpers
---------------------------------------------------------------------------------------------------
local C = {
  panel   = rgbm(0.07, 0.08, 0.10, 0.92),
  panel2  = rgbm(0.12, 0.13, 0.16, 1),
  line    = rgbm(1, 1, 1, 0.08),
  text    = rgbm(0.92, 0.93, 0.95, 1),
  muted   = rgbm(0.60, 0.63, 0.68, 1),
  accent  = rgbm(0.96, 0.62, 0.04, 1),     -- amber
  good    = rgbm(0.45, 0.85, 0.55, 1),
  warn    = rgbm(1.00, 0.55, 0.35, 1),
  wet     = rgbm(0.45, 0.70, 1.00, 1),
  cool    = rgbm(0.50, 0.72, 1.00, 1),
  mild    = rgbm(0.50, 0.85, 0.60, 1),
  warm    = rgbm(0.98, 0.75, 0.30, 1),
  hot     = rgbm(1.00, 0.48, 0.28, 1),
}

local function tempColor(v, track)
  local x = track and v / 1.5 or v
  return x < 15 and C.cool or x < 24 and C.mild or x < 30 and C.warm or C.hot
end

local DIRS = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' }
local function compass(d) return DIRS[(math.floor(((d or 0) + 22.5) / 45) % 8) + 1] end
local function fmt(v, f) return v and string.format(f, v) or '–' end

local function statusColor()
  return sync.phase == 'confirmed' and C.good or sync.phase == 'failed' and C.warn or C.muted
end

local function pill(label, active, width, color)
  ui.pushStyleColor(ui.StyleColor.Button, active and (color or C.accent) or C.panel2)
  ui.pushStyleColor(ui.StyleColor.ButtonHovered, active and (color or C.accent) or rgbm(0.2, 0.21, 0.25, 1))
  ui.pushStyleColor(ui.StyleColor.ButtonActive, color or C.accent)
  ui.pushStyleColor(ui.StyleColor.Text, active and rgbm(0.05, 0.05, 0.06, 1) or C.text)
  local clicked = ui.button(label, vec2(width, 30))
  ui.popStyleColor(4)
  return clicked
end

---------------------------------------------------------------------------------------------------
-- Pit window (setup screen) — styled after the CSP / VRC setup panels:
-- glass background, white semibold text, dim labels, thin separators, one column per session.
---------------------------------------------------------------------------------------------------
local V = {
  bg      = rgbm(0.09, 0.09, 0.11, 0.85),   -- only used when drawn as overlay (no SETUP glass behind)
  text    = rgbm(1, 1, 1, 1),
  dim     = rgbm(0.72, 0.72, 0.74, 1),
  faint   = rgbm(0.44, 0.44, 0.44, 1),
  line    = rgbm(1, 1, 1, 0.10),
  colSel  = rgbm(1, 1, 1, 0.07),
  good    = rgbm(0.35, 0.85, 0.45, 1),
  warn    = rgbm(1.00, 0.45, 0.35, 1),
  wet     = rgbm(0.45, 0.72, 1.00, 1),
  red     = rgbm(0.92, 0.08, 0.12, 1),     -- VRC secondary #EB141F
  redFill = rgbm(0.92, 0.08, 0.12, 0.10),
}
local F = {}
pcall(function()
  F.regular = ui.DWriteFont('Default'):weight(ui.DWriteFont.Weight.SemiBold)
  F.bold    = ui.DWriteFont('Default'):weight(ui.DWriteFont.Weight.Bold)
end)
local function pushF(f) if f then ui.pushDWriteFont(f) end end
local function popF(f) if f then ui.popDWriteFont() end end
local function txt(text, size, p1, p2, align, color)
  ui.dwriteDrawTextClipped(text, size, p1, p2, align or ui.Alignment.Center, ui.Alignment.Center, false, color or V.text)
end

local SHORT = { ['Sprint Qualifying'] = 'Sprint Q', ['Sprint'] = 'Sprint', ['Qualifying'] = 'Qualifying', ['Race'] = 'Race' }
local ROWS = {
  { 'Air (°C)',       function(r) return fmt(r.air_c, '%.1f') end },
  { 'Track (°C)',     function(r) return fmt(r.track_c, '%.1f') end },
  false,
  { 'Humidity (%)',   function(r) return fmt(r.humidity_pct, '%.0f') end },
  { 'Wind (km/h)',    function(r) return fmt(r.wind_kmh, '%.1f') .. ' ' .. compass(r.wind_dir_deg) end },
  false,
  { 'Sky',            function(r) return WEATHER_NAMES[r.pure_weather] or tostring(r.pure_weather) end },
  { 'Rain',           function(r)
      if r.source == 'forecast' then return r.rain == 1 and 'Likely' or 'Unlikely' end
      return r.rain == 1 and 'Wet start' or ((r.rain_frac or 0) > 0 and 'Later' or 'Dry') end },
  { 'Local start',    function(r) return r.local_start and r.local_start:sub(12, 16) or '–' end },
  { 'Data',           function(r) return r.source == 'forecast' and 'Forecast' or 'Timing' end },
}
-- Base layout is designed at 1440p; everything is multiplied by pitScale() so the panel keeps
-- the same proportions at 1080p (x0.75) and 4K (x1.5). settings.pitSize adds a personal tweak.
local BASE = { W = 460, ROW = 26, HEAD = 44, COLHEAD = 30, FOOT = 34, M = 14, GAP = 9, LABEL = 130 }

local function pitScale()
  local h = 1440
  pcall(function() h = ac.getUI().windowSize.y end)
  return math.max(0.5, math.min(2.5, (h / 1440) * (settings.pitSize or 1)))
end

local function pitSize(S)
  local n = 0
  for _, rr in ipairs(ROWS) do n = n + (rr and BASE.ROW or BASE.GAP) end
  local h = BASE.M + BASE.HEAD + BASE.COLHEAD + n + 8 + BASE.FOOT + BASE.M
  return vec2(math.floor(BASE.W * S), math.floor(h * S))
end
local function pitHeight() return pitSize(pitScale()).y end

-- small iOS-style switch; returns true when clicked
local function drawSwitch(id, pos, S, on)
  local w, h = 38 * S, 20 * S
  ui.setCursor(pos)
  local clicked = ui.invisibleButton(id, vec2(w, h))
  local hov = ui.itemHovered()
  ui.drawRectFilled(pos, vec2(pos.x + w, pos.y + h), on and V.red or rgbm(1, 1, 1, hov and 0.28 or 0.18), h / 2)
  local r = h / 2 - 3 * S
  local cx = on and (pos.x + w - h / 2) or (pos.x + h / 2)
  ui.drawCircleFilled(vec2(cx, pos.y + h / 2), r, V.text, 20)
  return clicked
end

local function setEnabled(on)
  settings.autoApply = on
  if on then
    autoApply(false)
    if not autoState.active then local r = currentRow(); if r then applyManual(r) end end
  else
    finishPush()
    sync.phase, sync.msg = 'off', 'F1 Real Weather is off — Pure Planner keeps its current plan'
  end
end

local function drawPit(size, isOverlay)
  local S = pitScale()
  local M, ROW, HEAD, COLHEAD, FOOT, GAP = BASE.M * S, BASE.ROW * S, BASE.HEAD * S, BASE.COLHEAD * S, BASE.FOOT * S, BASE.GAP * S
  local fs = function(v) return math.floor(v * S + 0.5) end
  if isOverlay then ui.drawRectFilled(vec2(0, 0), size, V.bg, 12 * S) end
  pushF(F.regular)

  -- header: title + on/off switch
  local c = sel.circuit
  local r = currentRow()
  local on = settings.autoApply
  local title = c and (c.display .. (r and ('  ·  ' .. (r.meeting or '') .. ' ' .. r.year) or '')) or 'F1 Real Weather'
  local swW, swH = 38 * S, 20 * S
  if isOverlay then
    ui.setCursor(vec2(0, 0))
    ui.invisibleButton('##f1rwdrag', vec2(size.x - swW - M * 2, M + HEAD - 6 * S))
    if ui.itemActive() then
      local d = ui.mouseDelta()
      settings.pitX, settings.pitY = settings.pitX + d.x, settings.pitY + d.y
    end
  end
  txt(title, fs(18), vec2(M, M), vec2(size.x - swW - M * 2, M + 28 * S), ui.Alignment.Start, on and V.text or V.dim)
  if drawSwitch('##f1rwOnOff', vec2(size.x - M - swW, M + (28 * S - swH) / 2), S, on) then setEnabled(not on) end
  if ui.itemHovered() then ui.setTooltip(on and 'F1 Real Weather on — click to turn off' or 'F1 Real Weather off — click to turn on') end

  if not c then
    txt(autoState.reason ~= '' and autoState.reason or 'No F1 circuit for this track', fs(14),
      vec2(M, M + HEAD), vec2(size.x - M, M + HEAD + 30 * S), ui.Alignment.Start, V.dim)
    popF(F.regular); return
  end

  local list = c.byYear[sel.year] or {}
  local labelW = BASE.LABEL * S
  local colW = (size.x - M * 2 - labelW) / math.max(#list, 1)
  local top = M + HEAD
  local bottomOfTable = top + COLHEAD
  for _, rr in ipairs(ROWS) do bottomOfTable = bottomOfTable + (rr and ROW or GAP) end

  -- clickable column headers; the chosen session gets a red box
  for i, s in ipairs(list) do
    local x0 = M + labelW + (i - 1) * colW
    local chosen = on and i == sel.idx
    ui.setCursor(vec2(x0, top))
    if ui.invisibleButton('##col' .. i, vec2(colW, COLHEAD)) then
      sel.idx = i
      if on then applyManual(s) end
    end
    local hovered = ui.itemHovered()
    if chosen then
      ui.drawRectFilled(vec2(x0 + 3 * S, top), vec2(x0 + colW - 3 * S, bottomOfTable), V.redFill, 6 * S)
      ui.drawRect(vec2(x0 + 3 * S, top), vec2(x0 + colW - 3 * S, bottomOfTable), V.red, 6 * S, nil, 2 * S)
    elseif hovered then
      ui.drawRect(vec2(x0 + 3 * S, top), vec2(x0 + colW - 3 * S, bottomOfTable), V.line, 6 * S, nil, 1 * S)
    end
    pushF(F.bold)
    txt(SHORT[s.session] or s.session, fs(14), vec2(x0, top), vec2(x0 + colW, top + COLHEAD), ui.Alignment.Center,
      (chosen or hovered) and V.text or V.dim)
    popF(F.bold)
  end
  ui.drawLine(vec2(M, top + COLHEAD), vec2(size.x - M, top + COLHEAD), V.line, 1)

  -- rows
  local y = top + COLHEAD
  for _, rr in ipairs(ROWS) do
    if not rr then
      ui.drawLine(vec2(M, y + GAP / 2), vec2(size.x - M, y + GAP / 2), V.line, 1)
      y = y + GAP
    else
      txt(rr[1], fs(14), vec2(M + 4 * S, y), vec2(M + labelW, y + ROW), ui.Alignment.Start, V.dim)
      for i, s in ipairs(list) do
        local x0 = M + labelW + (i - 1) * colW
        local col = (rr[1] == 'Rain' and s.rain == 1) and V.wet or ((on and i == sel.idx) and V.text or V.dim)
        txt(rr[2](s), fs(14), vec2(x0, y), vec2(x0 + colW, y + ROW), ui.Alignment.Center, col)
      end
      y = y + ROW
    end
  end

  -- footer: Pure Planner status (green when Pure confirms it)
  y = y + 8 * S
  ui.drawLine(vec2(M, y), vec2(size.x - M, y), V.line, 1)
  local sc = sync.phase == 'confirmed' and V.good or sync.phase == 'failed' and V.warn or V.dim
  ui.drawCircleFilled(vec2(M + 6 * S, y + FOOT / 2), 4 * S, sc)
  txt(sync.msg ~= '' and sync.msg or 'Not applied yet', fs(13), vec2(M + 18 * S, y), vec2(size.x - M, y + FOOT),
    ui.Alignment.Start, sc)
  popF(F.regular)
end

-- CSP setup window (manifest ID "pit"); resized live to the current scale
local lastPitSize = nil
function windowPit(dt)
  pit.lastWindowDraw = os.clock()
  local want = pitSize(pitScale())
  if not lastPitSize or lastPitSize.x ~= want.x or lastPitSize.y ~= want.y then
    pcall(ac.setWindowSizeConstraints, 'pit', want, want)
    lastPitSize = want
  end
  drawPit(ui.windowSize(), false)
end

---------------------------------------------------------------------------------------------------
-- Main window: full browser + settings
---------------------------------------------------------------------------------------------------
local function row(label, value)
  ui.textColored(label, C.muted)
  ui.sameLine(110)
  ui.text(value)
end

function windowMain(dt)
  ui.textColored(string.format('%d sessions · %d circuits · %s DB', #db.rows, #db.circuits, db.source), C.muted)
  ui.textColored('Car: ' .. carId .. (carMatches() and '  (auto)' or ''), C.muted)
  if detectedTrack ~= '' then ui.textColored('Track: ' .. detectedTrack, C.muted) end
  ui.separator()

  ui.setNextItemWidth(ui.availableSpaceX())
  ui.combo('##circuit', sel.circuit and sel.circuit.display or 'Circuit', ui.ComboFlags.HeightLarge, function()
    for _, c in ipairs(db.circuits) do
      if ui.selectable(c.display .. '  (' .. c.name .. ')', sel.circuit == c) then selectCircuit(c) end
    end
  end)

  if sel.circuit then
    ui.setNextItemWidth(90)
    ui.combo('##year', tostring(sel.year or ''), ui.ComboFlags.None, function()
      for _, y in ipairs(sel.circuit.years) do
        if ui.selectable(tostring(y), sel.year == y) then
          local cur = currentRow()
          selectCircuit(sel.circuit, y, cur and cur.session)
        end
      end
    end)
    ui.sameLine()
    local list = sel.circuit.byYear[sel.year] or {}
    local cur = list[sel.idx]
    ui.setNextItemWidth(ui.availableSpaceX())
    ui.combo('##session', cur and cur.session or 'Session', ui.ComboFlags.None, function()
      for i, r in ipairs(list) do
        if ui.selectable(r.session, sel.idx == i) then sel.idx = i end
      end
    end)
  end

  local r = currentRow()
  ui.separator()
  if r then
    ui.textColored(r.meeting or '', C.accent)
    row('Local start', (r.local_start or '') .. '  (UTC' .. (r.gmt_offset or '') .. ')')
    row('Air', fmt(r.air_c, '%.1f °C') .. '   range ' .. fmt(r.air_min, '%.1f') .. '–' .. fmt(r.air_max, '%.1f'))
    row('Track', fmt(r.track_c, '%.1f °C') .. '   range ' .. fmt(r.track_min, '%.1f') .. '–' .. fmt(r.track_max, '%.1f'))
    row('Humidity', fmt(r.humidity_pct, '%.0f %%'))
    row('Wind', fmt(r.wind_kmh, '%.1f km/h') .. ' from ' .. compass(r.wind_dir_deg))
    row('Sky', (WEATHER_NAMES[r.pure_weather] or tostring(r.pure_weather)) ..
      (r.cloud_pct and string.format('  (%d%% cloud)', r.cloud_pct) or ''))
    row('Rain', (r.rain == 1 and 'at start' or 'dry at start') ..
      ((r.rain_frac or 0) > 0 and string.format(', wet %d%% of session', math.floor(r.rain_frac * 100 + 0.5)) or ''))
    row('Data', r.source == 'forecast' and 'Forecast (updates until the session, track temp estimated)' or 'Official timing weather station')
    if ui.button('Apply to Pure Planner', vec2(ui.availableSpaceX(), 32)) then applyManual(r) end
  end

  if sync.msg ~= '' then
    ui.pushStyleColor(ui.StyleColor.Text, statusColor())
    ui.textWrapped(sync.msg)
    ui.popStyleColor()
  end

  ui.separator()
  ui.textColored('Automatic', C.accent)
  if ui.checkbox('F1 Real Weather on (auto-load at session start / change)', settings.autoApply) then
    setEnabled(not settings.autoApply)
  end
  if ui.checkbox('Any car (off: only ' .. settings.carFilter .. '*)', settings.autoAnyCar) then settings.autoAnyCar = not settings.autoAnyCar end
  ui.setNextItemWidth(120)
  ui.combo('Season##auto', settings.autoYear == 0 and 'Latest' or tostring(settings.autoYear), ui.ComboFlags.None, function()
    if ui.selectable('Latest', settings.autoYear == 0) then settings.autoYear = 0 end
    for _, y in ipairs({ 2026, 2025, 2024, 2023 }) do
      if ui.selectable(tostring(y), settings.autoYear == y) then settings.autoYear = y end
    end
  end)
  if autoState.reason ~= '' then ui.textColored(autoState.reason, C.muted) end
  if ui.checkbox('Show weather panel in the pits', settings.pitPanel) then settings.pitPanel = not settings.pitPanel end
  ui.setNextItemWidth(160)
  local ps, psChanged = ui.slider('Pit panel size##pitsize', settings.pitSize * 100, 60, 160, '%.0f%%')
  if psChanged then settings.pitSize = ps / 100 end

  ui.separator()
  if ui.checkbox('Use real session date & time (Stamp)', settings.realTime) then settings.realTime = not settings.realTime end
  if ui.itemHovered() then
    ui.setTooltip('On: Stamp plan at the real local start time (sim clock jumps there).\nOff: Daycycle plan, keeps your sim time — conditions only.')
  end
  if ui.checkbox('Push manual Apply into Pure Planner', settings.autoTrigger) then settings.autoTrigger = not settings.autoTrigger end
  if ui.button('Detect track') then
    local c = detectTrack()
    if c then selectCircuit(c, nil, wantedSession(acSessionType())) end
  end
  ui.sameLine()
  if ui.button('Export all as presets') then exportAll() end

  ui.separator()
  ui.textColored('Shared database', C.accent)
  ui.textColored(dbUrl() ~= '' and dbUrl() or 'No URL (data\\db_url.txt is empty)', C.muted)
  ui.textColored(string.format('%d sessions (%s)%s', #db.rows, db.source, lastUpdate and ('  ·  updated ' .. lastUpdate) or ''), C.muted)
  if ui.checkbox('Download updates at start', settings.autoUpdate) then settings.autoUpdate = not settings.autoUpdate end
  if ui.button(refreshing and 'Downloading…' or 'Update now') and not refreshing then refreshDb(false) end
  ui.sameLine()
  if ui.button('Use bundled') then resetToBundled() end
  ui.text('Own URL (optional, overrides the shared one)')
  ui.setNextItemWidth(ui.availableSpaceX())
  local txt, changed = ui.inputText('##dburl', settings.dbUrl, ui.InputTextFlags.None)
  if changed then settings.dbUrl = txt end
end

-- pit overlay fallback (registered last so it sees drawPit / pitHeight)
pcall(function()
  ui.onExclusiveHUD(function(mode)
    if mode == 'menu' and pit.overlay and settings.pitPanel then
      local sz = pitSize(pitScale())
      ui.transparentWindow('f1rwPitOverlay', vec2(settings.pitX, settings.pitY), sz, true, true, function()
        drawPit(sz, true)
      end)
    end
  end)
end)

-- download the shared database once per start (after everything above exists)
if settings.autoUpdate then refreshDb(true) end
