if (runx.api_version or 0) < 1 then
  error("Runx plugin API v1 or newer is required")
end

local function trim(value)
  return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function data_path()
  return runx.plugin_dir .. "/emoji.json"
end

local function load_emojis()
  local entries = {}
  local data = runx.json_decode(runx.read_text(data_path()))

  for emoji, keywords in pairs(data) do
    if emoji ~= "" and #keywords > 0 then
      table.insert(entries, {
        char = emoji,
        aliases = keywords,
        primary = keywords[1]:gsub("_", " "),
      })
    end
  end

  return entries
end

local function alias_score(alias, query)
  local lowered = alias:lower()

  if lowered == query then
    return 100000
  end

  if lowered:find(query, 1, true) then
    return 50000 + #query * 100 - #lowered
  end

  return runx.fuzzy_score(lowered, query)
end

local function emoji_score(entry, query)
  if entry.char == query then
    return 120000
  end

  local best = 0

  for _, keyword in ipairs(entry.aliases) do
    local score = alias_score(keyword, query)
    if score > best then
      best = score
    end
  end

  return best
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

  for _, entry in ipairs(load_emojis()) do
    local score = emoji_score(entry, query)
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
