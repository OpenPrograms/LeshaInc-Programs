local shell = require("shell")

local PROMPT = "$(36)telnet> "
local escapeOn = true

local args, opts = shell.parse(...)

-- 30 black, 31 red, 32 green, 33 yellow, 34 blue, 35 magenta, 36 cyan, 37 white
local writefc

opts.color = opts.color or "auto"
if opts.color == "auto" then
  opts.color = io.stdout.tty and "always" or "never"
end

if opts.color == "always" then
  function writefc(fmt, ...)
    io.write(({fmt:format(...):gsub("$%(([^)]+)%)", function(c)
      return c == "$" and "$" or "\27[" .. c .. "m"
    end)})[1] .. "\27[0m")
  end
elseif opts.color == "never" then
  function writefc(fmt, ...)
    io.write(({fmt:format(...):gsub("$%(([^)]+)%)", function(c)
      return c == "$" and "$" or ""
    end)})[1])
  end
else
  io.stderr:write("Invalid value for --color=WHEN option; WHEN should be auto, always or never\n")
  return 2
end


if opts.help then
  writefc([=[Usage: telnet [OPTION]... [HOST [PORT]]$(0)
  HOST                  specify a host to contact over the network
  PORT                  specify a port number to contact (default: 23)
      --color=WHEN      WHEN can be
                        auto - colorize output only if writing to a tty,
                        always - always colorize output,
                        never - never colorize output; (default: auto)
  -E                    disable the escape key functionality
      --escape=key      [WIP] set the escape key (default: C-])
      --help            display this help and exit
]=])
  return 0
end

if opts.E then escapeOn = false end


local function main(...)

  escapeOn = opts.E ~= null and opts.E or true
  writefc("%s", PROMPT)
end

main(...)

