local shell = require("shell")

local PROMPT = "$mtelnet> "
local escapeOn

local colors = {
  ["0"] = 30, r = 31, g = 32, y = 33, b = 34, m = 35, c = 36, w = 37
}

local function printfc(fmt, ...)
  io.write(({fmt:format(...):gsub("$(.)(b?)", function(color, bg)
    return color == "$" and "$" or (colors[color] and "\27[" .. (bg == "b" and colors[color] + 10 or colors[color]) .. "m" or "$" .. color .. bg)
  end)})[1] .. "\27[0m")
end

local function printHelp()
  print([=[Usage: telnet [OPTION]... [HOST [PORT]]
  HOST            specify a host to contact over the network
  PORT            specify a port number to contact (default: 23)
  -E              disable the escape key functionality
  --escape=key    WIP: set the escape key (default: C-])
  -h, --help      display this help and exit]=])
end

local function main(...)
  local args, opts = shell.parse(...)
  if opts.h or opts.help then
    printHelp()
    return
  end

  escapeOn = opts.E ~= null and opts.E or true
  printfc("%s", PROMPT)
end

main(...)

