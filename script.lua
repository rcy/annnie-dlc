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

-- Shows today's World Cup scores and upcoming World Cup matches.
-- Uses the FIFA API to fetch match data.
-- Returns a single message with all output.
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
  
  -- Try today first
  local res = http.json("https://api.fifa.com/api/v3/calendar/matches?from=" .. today .. "&to=" .. today .. "&language=en")
  if res and res.Results then
    for _, m in ipairs(res.Results) do
      local comp = safe_get(m, "CompetitionName", 1, "Description")
      if string.find(comp, "World Cup", 1, true) then
        add_match(m)
      end
    end
  end
  
  -- Try this month
  local y, mth = today:match("(%d+)-(%d+)")
  local last_day = os.date("!%d", os.time({year=y, month=mth+1, day=0}))
  local month_end = string.format("%s-%s-%s", y, mth, last_day)
  
  res = http.json("https://api.fifa.com/api/v3/calendar/matches?from=" .. today .. "&to=" .. month_end .. "&language=en")
  if res and res.Results and #res.Results < 50 then
    for _, m in ipairs(res.Results) do
      local comp = safe_get(m, "CompetitionName", 1, "Description")
      if string.find(comp, "World Cup", 1, true) then
        add_match(m)
      end
    end
  else
    -- Fallback: check weekly chunks to get past API 50-result limit
    local ts = os.time()
    for off = 0, 60, 7 do
      local f = os.date("!%Y-%m-%d", ts + off * 86400)
      local t = os.date("!%Y-%m-%d", ts + (off + 6) * 86400)
      local r = http.json("https://api.fifa.com/api/v3/calendar/matches?from=" .. f .. "&to=" .. t .. "&language=en")
      if r and r.Results then
        for _, m in ipairs(r.Results) do
          local comp = safe_get(m, "CompetitionName", 1, "Description")
          if string.find(comp, "World Cup", 1, true) then
            add_match(m)
          end
        end
      end
      if #wc_matches >= 20 then break end
    end
  end
  
  if #wc_matches == 0 then
    return "No World Cup matches found today or in the near future."
  end
  
  table.sort(wc_matches, function(a, b) return (a.Date or "") < (b.Date or "") end)
  
  local today_list, upcoming = {}, {}
  for _, m in ipairs(wc_matches) do
    local d = (m.Date or ""):gsub("T", " "):gsub("Z", "")
    local donly = d:match("^(%S+)")
    if donly == today then
      table.insert(today_list, m)
    else
      table.insert(upcoming, m)
    end
  end
  
  local lines = {}
  
  if #today_list > 0 then
    table.insert(lines, "=== Today's World Cup Matches (" .. today .. ") ===")
    for _, m in ipairs(today_list) do
      local comp = safe_get(m, "CompetitionName", 1, "Description")
      local home = safe_get(m, "Home", "TeamName", 1, "Description")
      local away = safe_get(m, "Away", "TeamName", 1, "Description")
      local hs, as = m.HomeTeamScore, m.AwayTeamScore
      local stage = safe_get(m, "StageName", 1, "Description")
      if type(hs) == "number" and type(as) == "number" then
        table.insert(lines, comp .. ": " .. home .. " " .. hs .. "-" .. as .. " " .. away .. " (" .. stage .. ")")
      else
        table.insert(lines, comp .. ": " .. home .. " vs " .. away .. " (" .. stage .. ")")
      end
    end
  else
    table.insert(lines, "No World Cup matches today (" .. today .. ").")
  end
  
  if #upcoming > 0 then
    table.insert(lines, "")
    table.insert(lines, "=== Upcoming World Cup Matches ===")
    for _, m in ipairs(upcoming) do
      local comp = safe_get(m, "CompetitionName", 1, "Description")
      local home = safe_get(m, "Home", "TeamName", 1, "Description")
      local away = safe_get(m, "Away", "TeamName", 1, "Description")
      local stage = safe_get(m, "StageName", 1, "Description")
      local d = (m.Date or ""):gsub("T", " "):gsub("Z", "")
      local donly = d:match("^(%S+)")
      local hs, as = m.HomeTeamScore, m.AwayTeamScore
      if type(hs) == "number" and type(as) == "number" then
        table.insert(lines, donly .. " | " .. comp .. ": " .. home .. " " .. hs .. "-" .. as .. " " .. away .. " (" .. stage .. ")")
      else
        table.insert(lines, donly .. " | " .. comp .. ": " .. home .. " vs " .. away .. " (" .. stage .. ")")
      end
    end
  end
  
  return table.concat(lines, "\n")
end

-- Returns the number 69.
function the_number()
  return 69
end
