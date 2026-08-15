if (runx.api_version or 0) < 1 then
  error("Runx plugin API v1 or newer is required")
end

local function trim(value)
  return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function data_path()
  return runx.plugin_dir .. "/emoji-search.json"
end

local function exporter_path()
  return runx.plugin_dir .. "/tools/emoji-index-exporter"
end

local function file_exists(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  return true
end

local function ensure_data()
  local path = data_path()
  if file_exists(path) then
    return true
  end

  local ok, result = pcall(runx.exec_status, exporter_path(), { path })
  return ok and result == true and file_exists(path)
end

local cached_entries

local function load_emojis()
  if cached_entries then
    return cached_entries
  end

  if not ensure_data() then
    return nil
  end

  local entries = {}
  local data = runx.json_decode(runx.read_text(data_path()))

  for emoji, value in pairs(data.emoji) do
    if emoji ~= "" and value.name ~= "" then
      table.insert(entries, {
        char = emoji,
        primary = value.name,
        terms = value.terms,
      })
    end
  end

  cached_entries = entries
  return entries
end

local function query_terms(query)
  local terms = {}
  for term in query:gmatch("%S+") do
    table.insert(terms, term)
  end
  return terms
end

local function emoji_score(entry, query, terms)
  if entry.char == query then
    return 1000000000000000
  end

  local exact = entry.terms[query]
  if exact then
    return exact
  end

  if #terms > 1 then
    local total = 0
    for _, term in ipairs(terms) do
      local weight = entry.terms[term]
      if not weight then
        return 0
      end
      total = total + weight
    end
    return math.floor(total / #terms)
  end

  return 0
end

local function result_limit()
  local config = runx.plugin_config or {}
  return tonumber(config.result_limit) or 24
end

local function hint(title)
  return {
    {
      id = "emoji:hint:" .. title,
      title = title,
      score = 1,
      payload = {
        kind = "noop",
      },
    },
  }
end

local function search(raw, action_kind)
  local query = trim(raw):lower()
  if query == "" then
    return hint("emoji <query>")
  end

  local matches = {}
  local terms = query_terms(query)
  local entries = load_emojis()
  if not entries then
    return hint("Could not generate the local Apple emoji search index")
  end

  for _, entry in ipairs(entries) do
    local score = emoji_score(entry, query, terms)
    if score > 0 then
      table.insert(matches, {
        id = action_kind .. ":" .. entry.char,
        title = entry.char .. " " .. entry.primary,
        score = score,
        payload = {
          kind = action_kind,
          emoji = entry.char,
        },
      })
    end
  end

  table.sort(matches, function(left, right)
    if left.score == right.score then
      return left.title < right.title
    end

    return left.score > right.score
  end)

  local limit = result_limit()
  while #matches > limit do
    table.remove(matches)
  end

  return matches
end

return {
  id = "emoji",
  name = "emoji",

  commands = {
    emoji = "search_emoji",
    ["emoji-copy"] = "search_copy_emoji",
  },

  search_emoji = function(raw)
    return search(raw, "type_emoji")
  end,

  search_copy_emoji = function(raw)
    return search(raw, "copy_emoji")
  end,

  run = function(payload)
    if payload.kind == "noop" then
      return "Search for an emoji."
    end

    if payload.kind == "type_emoji" then
      return runx.type_text(payload.emoji)
    end

    if payload.kind == "copy_emoji" then
      return runx.copy_text(payload.emoji)
    end

    error("unknown emoji action: " .. tostring(payload.kind))
  end,
}
