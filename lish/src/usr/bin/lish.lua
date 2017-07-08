local parserState = {} do
  parserState.__index = parserState

  function parserState:__tostring()
    return ("%q %d:%d"):format(self.input:sub(1, 50), self.line, self.col)
  end

  function parserState:advance(n)
    self.col = self.col + n
    self.input = self.input:sub(n + 1)
    self.pos = self.pos + 1
  end

  setmetatable(parserState, {
    __call = function(_, input)
      local self = setmetatable({}, parserState)
      self.original = input
      self.input = input
      self.col = 1
      self.line = 1
      self.pos = 1
      return self
    end
  })
end

local function parseError(state, message)
  coroutine.yield(nil, ("%d:%d: %s"):format(state.line, state.col, message))
end

local function createParser(f)
  return function(state)
    return coroutine.wrap(f)(state)
  end
end

local function parseIdent(state)
  local s, e, ident = state.input:find("^([%l%u_][%w_]*)")
  if not s then
    parseError(state, "incorrect identifier")
  end

  state:advance(e - s + 1)
  return ident
end

local function isIFS(char)  -- TODO: Read IFS env variable
  return char == " " or char == "\t" or char == "\n"
end

local function parseBraces(input)
  local s, e, rangeStart, rangeEnd = input:find("^{(%d+)%.%.(%d+)}")
  if not s then
    local words = {}
    local i = 1
    local pos = 2
    local escape

    while true do
      local char = input:sub(pos, pos)
      if char == "" then return end

      pos = pos + 1

      if char == "\\" then
        escape = true
      elseif not escape and char == "}" then
        return pos - 2, "words", words
      elseif not escape and char == "," then
        i = i + 1
      else
        words[i] = (words[i] or "") .. char
      end
    end
  else
    return e - s, "range", rangeStart, rangeEnd
  end
end

local function expandBraces(word, idx, expansions)
  local pos = 1
  local pre, post = "", ""
  local parsedBraces = false
  local braces = {}
  while true do
    local char = word:sub(pos, pos)
    pos = pos + 1

    if char == "" or (not escape and char == "{") then
      if braces[1] then
        if braces[2] == "range" then
          local variants = {}
          for i = braces[3], braces[4] do
            variants[i] = pre .. tostring(math.tointeger(i)) .. post
          end
          table.insert(expansions, {idx, variants})
        else
          local variants = {}
          for i, w in ipairs(braces[3]) do
            variants[i] = pre .. w .. post
          end
          table.insert(expansions, {idx, variants})
        end

        pre, post = "", ""
        parsedBraces = false
      end
    end

    if char == "" then
      if pre ~= "" then
        table.insert(expansions, {idx, {pre}})
      end

      return
    end

    if char == "\\" then
      escape = true
    elseif not escape and char == "{" then
      braces = {parseBraces(word:sub(pos - 1))}
      if braces[1] then
        pos = pos + braces[1]
        parsedBraces = true
      else
        pre = pre .. "{"
      end
    elseif parsedBraces then
      post = post .. char
    else
      pre = pre .. char
    end

    if escape and char ~= "\\" then escape = false end
  end
end

local function getHome()
  return os.getenv("HOME")
end

local function getPWD()
  return os.getenv("PWD")
end

local function getOLDPWD()
  return os.getenv("OLDPWD")
end

local function expandTilde(word)
  if word == "~" then
    return getHome() or "~"
  elseif word == "~+" then
    return getPWD() or "~+"
  elseif word == "~-" then
    return getOLDPWD() or "~-"
  elseif word:match("^~/") then
    return word:gsub("^~", getHome() or "~")
  elseif word:match("^~%+/") then
    return word:gsub("^~%+", getPWD() or "~+")
  elseif word:match("^~-/") then
    return word:gsub("^~-", getOLDPWD() or "~-")
  else
    return word
  end
end

local function map(f, t)
  local r = {}
  for i, v in ipairs(t) do
    r[i] = f(v)
  end
  return r
end

local function copyStrings(strings)
  local out = {}
  for i, string in ipairs(strings) do
    out[i] = string
  end
  return out
end

local function parseWord(state)
  local word = {}
  local braceExpansions = {}
  local s, e = state.pos, state.pos - 1
  local quote = ""
  local escape

  while #state.input > 0 do
    local char = state.input:sub(1, 1)

    if not escape and quote == "" and isIFS(char) then break end

    e = e + 1

    if not escape and char == quote then
      table.insert(word, ({state.original:sub(s, e - 1):gsub("\\(.)","%1")})[1])
      s = e + 1
      e = s - 1
      quote = ""
    elseif char == "\\" then
      escape = true
    elseif not escape and quote == "" and char == '"' or char == "'" then
      expandBraces(state.original:sub(s, e - 1):gsub("\\(.)","%1"), #word + 1, braceExpansions)
      quote = char
      s = e + 1
      e = s - 1
    end

    state:advance(1)

    if escape and char ~= "\\" then escape = false end
  end

  if quote ~= "" then
    state:advance(-1)
    parseError(state, "unclosed quote")
  end

  expandBraces(state.original:sub(s, e):gsub("\\(.)","%1"), #word + 1, braceExpansions)


  local words = {word}

  for i = #braceExpansions, 1, -1 do
    braceExpansions[i][2] = map(expandTilde, braceExpansions[i][2])

    local wordIndex, variants = braceExpansions[i][1], braceExpansions[i][2]
    local len = #words
    for j = 1, len do
      for k = 1, #variants - 1 do
        table.insert(words[j], wordIndex, "")
        words[k * len + j] = copyStrings(words[j])
      end
    end
    local chs = #words / #variants
    for j, variant in ipairs(variants) do
      for k = chs * (j - 1) + 1, chs * j do
        words[k][wordIndex] = variant
      end
    end
  end

  for i, word in ipairs(words) do
    words[i] = table.concat(word)
  end

  return words
end

local state = parserState([[{~,\ }/test]])
local parser = createParser(parseWord)
print(state)
local words, reason = parser(state)
if reason then print(reason) return end
for _, word in ipairs(words) do
  io.write(("%s"):format(word), " ")
end
io.write("\n")
print(state)

