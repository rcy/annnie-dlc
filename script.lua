
-- Returns a random headline from lite.cnn.com
function random_cnn_headline()
  local page = http.get("https://lite.cnn.com")
  local headlines = {}
  for a_tag, text in page:gmatch('<a href="/([^"]-)"[^>]->(.-)</a>') do
    local trimmed = text:match("^%s*(.-)%s*$")
    if #trimmed > 10 then
      table.insert(headlines, trimmed)
    end
  end
  if #headlines == 0 then
    return "No headlines found."
  end
  math.randomseed(os.time())
  return headlines[math.random(#headlines)]
end

-- Returns the 5 most recent recalls from the Canada recalls website on one line.
-- Format: Title, Type, Date; Title, Type, Date; ... (no links)
function recent_recalls()
  local page = http.get("https://recalls-rappels.canada.ca/en")
  local results = {}
  
  for item in page:gmatch('<div class="homepage%-recent%-row">(.-)</div></div>') do
    local href, title = item:match('<a href="(/en/alert%-recall/[^"]-)"[^>]->(.-)</a>')
    if href then
      title = title:match("^%s*(.-)%s*$")
      title = title:gsub('​', '')
      
      local label = item:match('<span class="label label[^"]-">(.-)</span>')
      local cat_date = item:match('<span class="ar%-type">(.-)</span>')
      local category, date
      if cat_date then
        local parts = {}
        for part in cat_date:gmatch('[^|]+') do
          table.insert(parts, part:match("^%s*(.-)%s*$"))
        end
        category = parts[1]
        date = parts[2]
      end
      
      table.insert(results, {
        title = title,
        recall_type = label or "N/A",
        date = date or "N/A"
      })
    end
  end
  
  local parts = {}
  for i = 1, math.min(5, #results) do
    local r = results[i]
    table.insert(parts, r.title .. ", " .. r.recall_type .. ", " .. r.date)
  end
  
  return table.concat(parts, "; ")
end

-- Announces the single most recent product recall from the Canada government
-- recalls website. Returns title and date only.
function recall()
  local page = http.get("https://recalls-rappels.canada.ca/en")
  
  local best_title, best_date
  
  for item in page:gmatch('<div class="homepage%-recent%-row">(.-)</div></div>') do
    local href, title = item:match('<a href="(/en/alert%-recall/[^"]-)"[^>]->(.-)</a>')
    if href then
      title = title:match("^%s*(.-)%s*$")
      title = title:gsub('​', '')
      title = title:gsub('&#039;', "'")
      title = title:gsub('&amp;', '&')
      
      local cat_date = item:match('<span class="ar%-type">(.-)</span>')
      local date
      if cat_date then
        local parts = {}
        for part in cat_date:gmatch('[^|]+') do
          table.insert(parts, part:match("^%s*(.-)%s*$"))
        end
        date = parts[2]
      end
      
      if not best_title then
        best_title = title
        best_date = date or "N/A"
      end
    end
  end
  
  if not best_title then
    return "No recent recalls found."
  end
  
  return best_title .. ", " .. best_date
end

-- Returns the #1 trending GitHub repository today as one long message.
function trending_today()
  local page = http.get("https://github.com/trending")
  local result = ""
  
  for article in page:gmatch('<article class="Box%-row">(.-)</article>') do
    local h2 = article:match('<h2 class="h3 lh%-condensed">(.-)</h2>')
    if h2 then
      local href = h2:match('href="/([^"]+)"')
      if href and not href:match("^login") then
        local owner, repo_name = href:match("([^/]+)/(.+)")
        if owner and repo_name then
          -- Description
          local desc = article:match('<p class="col%-9 color%-fg%-muted my%-1[^"]*">(.-)</p>')
          if desc then desc = desc:match("^%s*(.-)%s*$") end
          
          -- Language
          local lang = article:match('<span itemprop="programmingLanguage">(.-)</span>')
          
          -- Total stars
          local total_stars = article:match('octicon%-star[^>]-</svg>%s*([%d,]+)%s*</a>')
          
          -- Today's stars
          local today_stars = article:match('([%d,]+) stars today')
          
          -- Build output as one long message (no emoji)
          result = "Top Trending GitHub Repo Today"
          result = result .. " | Repo: " .. owner .. "/" .. repo_name
          if desc and #desc > 0 then
            result = result .. " | Description: " .. desc
          end
          if lang then
            result = result .. " | Language: " .. lang
          end
          if total_stars then
            result = result .. " | Stars: " .. total_stars .. " total"
          end
          if today_stars then
            result = result .. " | Stars Today: " .. today_stars
          end
          
          break
        end
      end
    end
  end
  
  return result
end

-- Shows today's World Cup scores only (live/finished matches with scores).
-- Uses the FIFA API to fetch match data. Returns only matches from today
-- where HomeTeamScore and AwayTeamScore are both numbers.
function worldcup_scores()
  local today = os.date("!%Y-%m-%d")
  
  local function safe_get(t, ...)
    local args = {...}
    local current = t
    for _, key in ipairs(args) do
      if current == nil then return "TBD" end
      if type(current) ~= "table" then return "TBD" end
      current = current[key]
    end
    if current == nil then return "TBD" end
    return tostring(current)
  end
  
  local seen_ids = {}
  local wc_matches = {}
  
  local function add_match(m)
    local id = m.IdMatch or ""
    if not seen_ids[id] then
      seen_ids[id] = true
      table.insert(wc_matches, m)
    end
  end
  
  -- Fetch a broader range to capture today's matches (timezone offsets can cause mismatches)
  local y, mth = today:match("(%d+)-(%d+)")
  local last_day = os.date("!%d", os.time({year=y, month=mth+1, day=0}))
  local month_end = string.format("%s-%s-%s", y, mth, last_day)
  
  local res = http.json("https://api.fifa.com/api/v3/calendar/matches?from=" .. today .. "&to=" .. month_end .. "&language=en")
  if res and res.Results then
    for _, m in ipairs(res.Results) do
      local comp = safe_get(m, "CompetitionName", 1, "Description")
      if string.find(comp, "World Cup", 1, true) then
        add_match(m)
      end
    end
  end
  
  -- Filter to only today's matches that have live/final scores
  local matches = {}
  for _, m in ipairs(wc_matches) do
    local hs = m.HomeTeamScore
    local as = m.AwayTeamScore
    local d = (m.Date or ""):gsub("T", " "):gsub("Z", "")
    local donly = d:match("^(%S+)")
    if donly == today and type(hs) == "number" and type(as) == "number" then
      table.insert(matches, m)
    end
  end
  
  if #matches == 0 then
    return "No live World Cup scores today (" .. today .. ")."
  end
  
  table.sort(matches, function(a, b) return (a.Date or "") < (b.Date or "") end)
  
  local lines = {}
  for _, m in ipairs(matches) do
    local comp = safe_get(m, "CompetitionName", 1, "Description")
    local home = safe_get(m, "Home", "TeamName", 1, "Description")
    local away = safe_get(m, "Away", "TeamName", 1, "Description")
    local hs = m.HomeTeamScore
    local as = m.AwayTeamScore
    local stage = safe_get(m, "StageName", 1, "Description")
    lines[#lines + 1] = comp .. ": " .. home .. " " .. hs .. "-" .. as .. " " .. away .. " (" .. stage .. ")"
  end
  
  return table.concat(lines, "\n")
end

-- Returns the number 99999.
function the_number()
  return 99999
end

-- Returns the number 66.
function foo()
  return 66
end

-- Compacts worldcup_scores() output into a single line suitable for IRC.
-- Joins match descriptions with " | " separators.
-- Strips "FIFA World Cup (tm)" text from the output.
function print_worldcup_scores()
  local raw = worldcup_scores()
  local matches = {}
  for line in raw:gmatch("[^\n]+") do
    if #line > 0 then
      -- Remove "FIFA World Cup™" text from each line
      local cleaned = line:gsub("FIFA World Cup%s*", "")
      -- If removal left a leading colon, clean that up too
      cleaned = cleaned:gsub("^%s*:%s+", "")
      table.insert(matches, cleaned)
    end
  end
  if #matches == 0 then
    return raw
  end
  return table.concat(matches, " | ")
end

-- Returns the training data cutoff date for DeepSeek-V4-Flash.
-- Based on official DeepSeek API docs and model release info.
function deepseek_v4_flash_cutoff_date()
  -- DeepSeek-V4 was released on 2026-04-24. Based on benchmarks listed
  -- in the official docs (e.g., HMMT 2026 Feb) and the model's release date,
  -- the training data cutoff is approximately early 2026.
  return "Early 2026 (approximately February 2026)"
end

-- Searches the MusicBrainz API with a free text query and returns the MBID
-- of the first matching resource.
-- resource_type: e.g. "artist", "release", "recording", "label", "work", "area"
-- query: free text search string
-- Returns the MusicBrainz ID (UUID) of the first match, or nil if not found.
function musicbrainz_search(resource_type, query)
  local encoded = query
  encoded = encoded:gsub(" ", "+")
  encoded = encoded:gsub("([^%w%.%-%_%~%+])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)

  local url = "https://beta.musicbrainz.org/ws/2/" .. resource_type .. "/?query=" .. encoded .. "&fmt=json&limit=1"
  local result = http.json(url)

  if not result then
    return nil
  end

  local key = resource_type .. "s"
  local list = result[key]

  if list and #list > 0 and list[1].id then
    return list[1].id
  end

  return nil
end

-- Checks a Lichess username for pending moves in their current game.
-- Uses the public Lichess API (no authentication required).
-- Returns whether it's the user's turn, if they're waiting, or if their game is over.
-- Note: only reports the current game (users can have multiple correspondence games).
function lichess_pending(username)
  local body = http.get("https://lichess.org/api/user/" .. username .. "/current-game")
  
  if not body or body == "No ongoing game" or #body < 30 then
    return "No ongoing games for " .. username .. "."
  end
  
  -- Parse PGN headers
  local white = body:match('%[White "([^"]-)"%]')
  local black = body:match('%[Black "([^"]-)"%]')
  local result = body:match('%[Result "([^"]-)"%]')
  
  if not white or not black then
    return "Could not parse game data for " .. username .. "."
  end
  
  -- Determine user's color
  local color
  if white:lower() == username:lower() then
    color = "white"
  elseif black:lower() == username:lower() then
    color = "black"
  else
    return username .. " is not playing in that game (watching " .. white .. " vs " .. black .. "?)."
  end
  
  local opponent = (color == "white") and black or white
  
  -- If game is finished
  if result and result ~= "*" then
    if result == "1-0" then
      local winner = (color == "white") and "You won!" or (opponent .. " won.")
      return "Game over: " .. winner .. " (" .. white .. " vs " .. black .. ": " .. result .. ")"
    elseif result == "0-1" then
      local winner = (color == "black") and "You won!" or (opponent .. " won.")
      return "Game over: " .. winner .. " (" .. white .. " vs " .. black .. ": " .. result .. ")"
    else
      return "Game over: Draw (" .. white .. " vs " .. black .. ": " .. result .. ")"
    end
  end
  
  -- Game in progress: determine whose turn from movetext
  local movetext = body:match("%]%s*\n%s*\n(.+)")
  if not movetext then
    movetext = ""
  end
  
  -- Strip comments (braces) and normalize whitespace
  local clean = movetext:gsub("%b{}", "")
  clean = clean:gsub("%s+", " ")
  clean = clean:match("^%s*(.-)%s*$") or ""
  
  -- Also strip result at end if embedded in movetext
  clean = clean:gsub("%s*[01]/[01]%-[01]/[01]%s*$", "")
  clean = clean:gsub("%s*[01]%-[01]%s*$", "")
  
  -- Find the position of the last move number (e.g. "12.")
  local last_num_pos = nil
  for pos in clean:gmatch("()%d+%.") do
    last_num_pos = pos
  end
  
  local is_white_turn
  if last_num_pos then
    local after = clean:sub(last_num_pos)
    -- If there's a "..." after the last move number, black moved → white's turn
    if after:find("%.%.%.") then
      is_white_turn = true
    else
      is_white_turn = false
    end
  else
    -- No moves yet: white's turn
    is_white_turn = true
  end
  
  local my_turn = (color == "white" and is_white_turn) or (color == "black" and not is_white_turn)
  
  if my_turn then
    return "Your turn! You are playing as " .. color .. " vs " .. opponent .. "."
  else
    return "Waiting for " .. opponent .. " to move. You are playing as " .. color .. "."
  end
end

-- Reports estimated ISS urine tank status based on live crew count + known UPA specs.
-- Uses the open-notify.org API for real-time ISS crew count, then calculates
-- estimated urine production, UPA processing capacity, and tank fill level.
-- Tank level is deterministic per day (seeded from UTC date).
function iss_piss_tank()
  local astros = http.json("http://api.open-notify.org/astros.json")
  if not astros or not astros.people then
    return "Unable to contact ISS. The piss tank's secrets remain classified."
  end
  
  local iss_crew = 0
  for _, p in ipairs(astros.people) do
    if p.craft and p.craft:lower():match("iss") then
      iss_crew = iss_crew + 1
    end
  end
  
  if iss_crew == 0 then
    iss_crew = astros.number or 0
  end
  
  -- Deterministic daily seed so tank level stays consistent all day
  math.randomseed(tonumber(os.date("!%Y%m%d")))
  
  -- ISS Urine Processor Assembly (UPA) known specs:
  -- Each astronaut: ~1.7 L urine/day | UPA: ~9 kg/day max | Tank: ~43 kg
  -- Water recovery rate: ~85% (distillate fed to WPA for further processing)
  local daily_urine_per_person = 1.7
  local total_daily_urine = iss_crew * daily_urine_per_person
  local upa_capacity = 9.0
  local tank_capacity = 43.0
  local water_recovery = 0.85
  local recovered_water = total_daily_urine * water_recovery
  
  local tank_level = math.random(20, 80)
  local tank_kg = (tank_level / 100) * tank_capacity
  
  local status
  if tank_level > 75 then
    status = "URGENT: nearly full, fire up the UPA!"
  elseif tank_level > 50 then
    status = "moderate, comfortably half-full"
  elseif tank_level > 25 then
    status = "low, plenty of headroom"
  else
    status = "very low, crew must be dehydrated"
  end
  
  return string.format(
    "ISS Urine Tank: %d%% full (%.1f/%.0f kg) — %s | Crew: %d, producing ~%.1f L/day | UPA capacity: %.0f kg/day max, ~%.0f%% recovery (~%.1f L water/day reclaimed)",
    tank_level, tank_kg, tank_capacity, status,
    iss_crew, total_daily_urine, upa_capacity, water_recovery * 100, recovered_water
  )
end

-- Returns the top definition of a term from Urban Dictionary.
-- Uses the unofficial Urban Dictionary API.
-- term: the word or phrase to look up (e.g. "yeet", "skibidi toilet")
function urban_dictionary(term)
  if not term or #term == 0 then
    return "Please provide a term to look up."
  end
  
  local encoded = term
  encoded = encoded:gsub(" ", "+")
  encoded = encoded:gsub("([^%w%.%-%_%~%+])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  
  local url = "https://api.urbandictionary.com/v0/define?term=" .. encoded
  local result = http.json(url)
  
  if not result or not result.list or #result.list == 0 then
    return "No definitions found for \"" .. term .. "\"."
  end
  
  local d = result.list[1]
  
  -- Strip [bracket] markup from definition and example
  local def = d.definition:gsub("%[([^%]]-)%]", "%1")
  def = def:gsub("%s+", " ")
  def = def:match("^%s*(.-)%s*$")
  
  local ex = d.example:gsub("%[([^%]]-)%]", "%1")
  ex = ex:gsub("%s+", " ")
  ex = ex:match("^%s*(.-)%s*$")
  
  local lines = {
    d.word .. ": " .. def,
    "Example: " .. ex,
    string.format("👍 %d | 👎 %d — by %s", d.thumbs_up or 0, d.thumbs_down or 0, d.author or "unknown")
  }
  
  return table.concat(lines, "\n")
end

-- Returns live air quality data for a given city.
-- Uses the free Open-Meteo Geocoding API to resolve the city name to coordinates,
-- then the free Open-Meteo Air Quality API for current readings.
-- Returns a formatted one-line summary with European AQI label, US AQI, PM2.5, PM10, NO₂, O₃.
function air_quality(city)
  if not city or #city == 0 then
    return "Please provide a city name."
  end

  local function url_encode(s)
    s = s:gsub(" ", "+")
    s = s:gsub("([^%w%.%-%_%~%+])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
    return s
  end

  -- Step 1: Geocode the city
  local geo = http.json("https://geocoding-api.open-meteo.com/v1/search?name=" .. url_encode(city) .. "&count=1&language=en&format=json")
  if not geo or not geo.results or #geo.results == 0 then
    return "City \"" .. city .. "\" not found."
  end

  local result = geo.results[1]
  local display_name = result.name .. ", " .. (result.country or result.country_code or "Unknown")
  local lat, lon = result.latitude, result.longitude

  -- Step 2: Fetch air quality
  local aq_url = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=" .. lat .. "&longitude=" .. lon .. "&current=european_aqi,us_aqi,pm2_5,pm10,nitrogen_dioxide,ozone"
  local aq = http.json(aq_url)
  if not aq or not aq.current then
    return "Could not fetch air quality data for " .. display_name .. "."
  end

  local cur = aq.current

  -- European AQI labels
  local eaqi = cur.european_aqi
  local e_label
  if not eaqi then
    e_label = "N/A"
  elseif eaqi <= 20 then
    e_label = "Good"
  elseif eaqi <= 40 then
    e_label = "Fair"
  elseif eaqi <= 60 then
    e_label = "Moderate"
  elseif eaqi <= 80 then
    e_label = "Poor"
  elseif eaqi <= 100 then
    e_label = "Very Poor"
  else
    e_label = "Extremely Poor"
  end

  local us_aqi = cur.us_aqi

  local function v(val, unit)
    if val == nil then return "N/A" end
    return val .. " " .. unit
  end

  return string.format(
    "%s | European AQI: %s (%s) | US AQI: %s | PM2.5: %s | PM10: %s | NO₂: %s | O₃: %s",
    display_name,
    tostring(eaqi or "N/A"), e_label,
    tostring(us_aqi or "N/A"),
    v(cur.pm2_5, "µg/m³"),
    v(cur.pm10, "µg/m³"),
    v(cur.nitrogen_dioxide, "µg/m³"),
    v(cur.ozone, "µg/m³")
  )
end
