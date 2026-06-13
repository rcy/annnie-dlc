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
      -- Remove "FIFA World Cup (tm)" text from each line
      local cleaned = line:gsub("FIFA World Cup %(tm%)%s*", "")
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
