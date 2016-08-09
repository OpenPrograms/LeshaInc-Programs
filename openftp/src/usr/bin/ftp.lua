local component = require("component")

if not component.isAvailable("internet") then
  io.stderr:write("OpenFTP requires an Internet Card to run!\n")
  return
end

local internet = require("internet")
local computer = require("computer")
local unicode = require("unicode")
local shell = require("shell")
local event = require("event")
local term = require("term")
local text = require("text")
local fs = require("filesystem")
local inetc = component.internet
local gpu = component.gpu

-- Variables -------------------------------------------------------------------

local isColored, isVerbose
local args, options

local sock, host, port, timer
local w = gpu.getResolution()

local history = {}
local commands = {}

local chsize = 102400
local isRunning = true

-- Functions -------------------------------------------------------------------

local function setFG(fg)
  if isColored then
    gpu.setForeground(fg)
  end
end

local function nop() end

local function help()
  print("Usage: ftp [--colors=<always|never|auto>] <host> [port]")
  print()
  print("Options: ")
  print("  --colors=<always|never|auto>  Specify whether to use color or not.")

  os.exit(0)
end

local function init(...)
  args, options = shell.parse(...)

  local oColors = options["colors"] or "auto"
  oColors = (oColors == "always" or oColors == "never") and oColors or "auto"

  if oColors == "always" then
    isColored = true
  elseif oColors == "never" then
    isColored = false
  elseif oColors == "auto" then
    isColored = gpu.getDepth() > 1
  end

  isVerbose = options["verbose"] == true
  host, port = args[1] or nil, args[2] or 21

  if #args < 1 then help() end
end

local function connect()
  local lSock, reason = internet.open(host .. ":" .. port)
  if not lSock then
    io.stderr:write(("ftp: %s: %s\n"):format(host .. ":" .. port,
                                             reason or "unknown error"))
    os.exit(1)
    return
  end

  sock = lSock
  sock:setTimeout(0.2)
end

local read

local function lost()
  read(trace, true)
  setFG(0xFF0000)
  print("Connection lost.")
  setFG(0xFFFFFF)
  sock:close()
  os.exit(0)
end

local function readLine()
  local ok, line = pcall(sock.read, sock)
  if ok and line == "" then lost() end

  return ok and line or false
end

function read(f, nwait)
  local was, lastRet, out = false, nil, computer.uptime() + 2

  repeat
    local line = readLine()

    if line then
      lastRet = f(line)
      was = true
      out = computer.uptime() + 2
    end

    if computer.uptime() >= out then
      lost()
    end
  until not line and (was or nwait)

  return was, lastRet
end

local function parseOutput(str)
  local match = {str:match("^(%d%d%d)([ -])(.*)$")}

  if #match < 1 then return false end

  local code = tonumber(match[1])
  local codeColor do
    if code >= 100 and code < 200 then
      codeColor = 0x0000FF
    elseif code >= 200 and code < 300 then
      codeColor = 0x00FF00
    elseif code >= 300 and code < 400 then
      codeColor = 0xFFFF00
    else
      codeColor = 0xFF0000
    end
  end
  local isLast = match[2] == " "
  local text = match[3]

  return {
    code = code,
    codeColor = codeColor,
    isLast = isLast,
    text = text
  }
end

local function traceLine(data)
  setFG(data.codeColor)
  io.write(data.code)
  setFG(0x666999)
  io.write(data.isLast and " " or "-")
  setFG(0xFFFFFF)
  io.write(data.text .. "\n")
end

local function trace(str)
  local data = parseOutput(str)
  if data then
    traceLine(data)
    return data
  else
    print(str)
  end
end

local function exit()
  if sock then
    sock:write("QUIT\r\n")
    sock:flush()
    read(trace, true)
    sock:close()
  end

  setFG(0xFFFFFF)

  os.exit(0)
end

local function auth()
  read(trace)

  local got = false
  while true do
    local user repeat
      io.write("Name: ")
      user = term.read()
      if not user then
        print()
      end
    until user and #user > 0
    sock:write("USER " .. user .. "\r\n")
    sock:flush()

    local got = false

    read(function (str)
      local data = trace(str)
      if not got then
        got = data and data.code == 331 and data.isLast
      end
    end)

    if got then break end
  end

  io.write("Password: ")
  pass = term.read(nil, nil, nil, "*"):sub(1, -2)
  if not pass then
    print()
  end
  sock:write("PASS " .. (pass or "") .. "\r\n")
  sock:flush()

  local logined = false

  while true do
    local was = read(function (str)
      local data = trace(str)
      logined = data and data.code == 230 and data.isLast
    end)
    if was then break end
  end

  if not logined then
    exit()
  end

  print("Using binary mode to transfer files.")
  sock:write("TYPE I\r\n")
  sock:flush()
  read(nop)
end

local function pasv()
  sock:write("PASV\r\n")
  local ip, port

  local was, ret = read(function (str)
    local data = trace(str)
    if data and data.code == 227 and data.isLast then
      local match = {data.text:match("(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)")}
      if match then
        ip = table.concat({match[1], match[2], match[3], match[4]}, ".")
        port = tonumber(match[5]) * 256 + tonumber(match[6])
      end
    end
  end)

  if not ip or not port then
    return false
  end

  return inetc.connect(ip, port)
end

local function readPasv(pasvSock, f)
  os.sleep(0.2)

  local buf = {}
  local bufLen = 0
  local written = false

  while true do
    local chunk = pasvSock.read(chsize)

    if bufLen >= chsize and written then
      buf = {}
      bufLen = 0
    end

    if chunk then
      table.insert(buf, chunk)
      bufLen = bufLen + #chunk
      written = false
    end

    if not written and (bufLen >= chsize or not chunk) then
      f(table.concat(buf), bufLen)
      written = true
    end

    if not chunk and written then break end
  end

  pasvSock.close()
end

local function writePasv(pasvSock, f)
  repeat
    local chunk, len = f()
    if chunk then
      len = len or 0
      local written = 0
      repeat
        written = written + pasvSock.write(chunk)
      until written >= len
    end
  until not chunk

  pasvSock.write("")
  pasvSock.close()

  os.sleep(0.2)
end

local function handleInput(str)
  str = text.trim(str)

  if str:sub(1, 1) == "!" then
    if str:sub(2, -1)  == "" then
      shell.execute("sh")
    else
      shell.execute(str:sub(2, -1))
    end

    return
  end

  local cmd, args do
    local tokens = text.tokenize(str)
    if #tokens < 1 then return end

    cmd = tokens[1]
    table.remove(tokens, 1)
    args = tokens
  end

  if commands[cmd] then
    commands[cmd](args)
  else
    setFG(0xFF0000)
    print("Invalid command.")
    setFG(0xFFFFFF)
  end
end

local function main()
  connect()
  auth()

  repeat
    setFG(0x999999)
    io.write("ftp> ")
    setFG(0xFFFFFF)
    local input = term.read(history)

    if input and text.trim(input) ~= "" then
      handleInput(input)

      if input:sub(1, 1) ~= " " then
        table.insert(history, input)
      end
    end
  until not input
  print()

  isRunning = false
end

local progress do
  local units = {"B", "k", "M", "G", "T"}
  local chars = {[0] = ""}
  for i = 0x258f, 0x2588, -1 do
    table.insert(chars, unicode.char(i))
  end

  local function formatFSize(fsize)
    local result = ""
    if fsize < 10e3 then
      result = ("%.4f"):format(fsize):sub(1,5)
      result = result .. (" "):rep(6 - #result) .. units[1]
    elseif fsize < 10e13 then
      local digits = #("%d"):format(fsize)
      local unit = units[math.floor((digits - 1) / 3) + 1]
      result = ("%.13f"):format(fsize / (10 ^ (math.floor((digits - 1) / 3) * 3))):sub(1, 5)
      result = result .. (" "):rep(6 - #result) .. unit
    else
      result = ("%.1e"):format(fsize)
    end
    return result
  end

  function progress(fgot, ftotal, tstart, width)
    local perc = 0
    if tonumber(tostring(fgot / ftotal)) then
      perc = fgot / ftotal * 100
      if perc > 100 then
        perc = 100
      end
    else
      error("The programmer has derped! fgot = 0, ftotal = 0, perc = -nan, undefined behaviour!")
    end
    local pstr = ("%.2f"):format(perc)

    local delta = computer.uptime() - tstart
    local perperc = delta / perc
    local t = (100 - perc) * perperc
    local time = "n/a"
    local cspeed = ""
    if tonumber(tostring(t)) then
      cspeed = tonumber(tostring(fgot / delta))
      cspeed = cspeed and (formatFSize(cspeed) .. "/s") or "n/a"
      local days = math.floor(t / 86400)
      t = t - days * 86400
      local hours = math.floor(t / 3600)
      t = t - hours * 3600
      local minutes = math.floor(t / 60)
      local seconds = t - minutes * 60
      time = ("%02d"):format(seconds)
      time = ("%02d"):format(minutes) .. ":" .. time
      if hours ~= 0 or days ~= 0 then
        time = ("%02d"):format(hours) .. ":" .. time
      end
      if days ~= 0 then
        time = tostring(days) .. "d, " .. time
      end
    end

    local lpart = formatFSize(fgot) .. " / " .. formatFSize(ftotal) .. "▕"
    local rpart = chars[1] .. (" "):rep(6 - #pstr) .. pstr .. "% " .. cspeed .. " -- " .. time
    local pwidth = width - unicode.len(lpart) - unicode.len(rpart)

    local cwidth = pwidth / 100
    local fr = tonumber(select(2, math.modf(perc * cwidth)))
    local lastblockindex = math.floor(fr * 8)
    if lastblockindex == 8 then
      lastblockindex = 7
    end
    local lastblock = chars[lastblockindex]
    local blocks = math.floor(perc * cwidth)

    local result = lpart .. chars[8]:rep(blocks) .. lastblock
    result = result .. (" "):rep(width - unicode.len(result) - unicode.len(rpart)) .. rpart
    return result
  end
end

-- Сommands --------------------------------------------------------------------

function commands.quit()
  exit()
end

function commands.pwd(args)
  local _, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h then
    print("pwd - print working directory.")
    print()
    print("Usage: pwd [-h|--help]")
    print()
    print("Options:")
    print("  -h|--help  Print this message")

    return
  end

  sock:write("PWD\r\n")
  sock:flush()
  read(trace)
end

function commands.system(args)
  local _, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h then
    print("system - print system running on server.")
    print()
    print("Usage: system [-h|--help]")
    print()
    print("Options:")
    print("  -h|--help  Print this message")

    return
  end

  sock:write("SYST\r\n")
  sock:flush()
  read(trace)
end

function commands.nop(args)
  local _, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h then
    print("nop - do nothing.")
    print()
    print("Usage: system [-h|--help]")
    print()
    print("Options:")
    print("  -h|--help  Print this message")

    return
  end

  sock:write("NOOP\r\n")
  sock:flush()
  read(trace)
end

commands[".."] = function (args)
  local _, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h then
    print(".. - go to the parent directory.")
    print()
    print("Usage: .. [-h|--help]")
    print("Options:")
    print("  -h|--help  Print this message")

    return
  end

  sock:write("CDUP\r\n")
  sock:flush()
  read(trace)
end

function commands.size(args)
  local _, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h then
    print("size - print file size.")
    print()
    print("Usage: size [-h|--help] <path>")
    print()
    print("Options:")
    print("  -h|--help  Print this message")
    print()
    print("Arguments:")
    print("  path  Path to file.")

    return
  end

  if #args < 1 then
    print("Usage: size <file>")
    return
  end

  sock:write("SIZE " .. args[1] .. "\r\n")
  sock:flush()
  read(trace)
end

function commands.shelp(args)
  local _, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h then
    print("shelp - print server help.")
    print()
    print("Usage: shelp [-h|--help]")
    print()
    print("Options:")
    print("  -h|--help  Print this message")

    return
  end

  sock:write("HELP\r\n")
  sock:flush()
  read(trace)
end

function commands.stat(args)
  local _, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h then
    print("stat - print server statistics.")
    print()
    print("Usage: stat [-h|--help]")
    print()
    print("Options:")
    print("  -h|--help  Print this message")

    return
  end

  sock:write("STAT\r\n")
  sock:flush()
  read(trace)
end

function commands.binary(args)
  local _, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h then
    print("binary - switch to binary mode.")
    print()
    print("Usage: binary [-h|--help]")
    print()
    print("Options:")
    print("  -h|--help  Print this message")

    return
  end

  sock:write("TYPE I\r\n")
  sock:flush()
  read(trace)
end

function commands.ascii()
  local _, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h then
    print("ascii - switch to ASCII mode.")
    print()
    print("Usage: ascii [-h|--help]")
    print()
    print("Options:")
    print("  -h|--help  Print this message")

    return
  end

  sock:write("TYPE A\r\n")
  sock:flush()
  read(trace)
end

function commands.cd(args)
  local cargs, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h or #cargs < 1 then
    print("ascii - change working directory.")
    print()
    print("Usage: ascii [-h|--help] <path>")
    print()
    print("Options:")
    print("  -h|--help  Print this message")
    print()
    print("Arguments:")
    print("  path  Path to new working directory")

    return
  end

  sock:write("CWD " .. cargs[1] .. "\r\n")
  sock:flush()
  read(trace)
end

function commands.ls(args)
  local cargs, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h then
    print("ls - print list files.")
    print()
    print("Usage: ls [-h|--help] [path]")
    print()
    print("Options:")
    print("  -h|--help  Print this message")
    print("  -s         Use short listing format")
    print()
    print("Arguments:")
    print("  path  Path to the directory (the current")
    print("        directory by default) to list its files")

    return
  end

  local pasvSock = pasv()
  if not pasvSock then
    return
  end

  sock:write((copts.s and "NLST" or "LIST")
             .. (cargs[1] and " " .. cargs[1] or "") .. "\r\n")
  sock:flush()
  read(function (str)
    local data = trace(str)
    if data and data.code == 150 and data.isLast then
      readPasv(pasvSock, function (str) print(str) end)
    end
  end)
end

function commands.rename(args)
  local cargs, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h or #cargs < 2 then
    print("rename - rename file or directory.")
    print()
    print("Usage: rename [-h|--help] <source> <dest>")
    print()
    print("Options:")
    print("  -h|--help  Print this message")
    print()
    print("Arguments:")
    print("  source  A path to file to rename")
    print("  dest    A name the source should be renamed to")
    print()
    print("Aliases: rn")

    return
  end

  sock:write("RNFR " .. cargs[1] .. "\r\n")
  sock:flush()
  read(function (str)
    local data = trace(str)
    if data and data.code == 350 and data.isLast then
      sock:write("RNTO " .. cargs[2] .. "\r\n")
      sock:flush()
      read(trace)
    end
  end)
end

commands.rn = commands.rename

function commands.rm(args)
  local cargs, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h or #cargs < 1 then
    print("rm - remove a file or directory.")
    print()
    print("Usage: rm [-h|--help] [-d] <path>")
    print()
    print("Options:")
    print("  -h|--help  Print this message")
    print("  -d         Remove a directory")
    print()
    print("Arguments:")
    print("  path  A path to the file or directory to remove")

    return
  end

  sock:write((copts.d and "RMD " or "DELE ") .. cargs[1] .. "\r\n")
  sock:flush()
  read(trace)
end

function commands.mkdir(args)
  local cargs, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h or #cargs < 1 then
    print("mkdir - create a directory.")
    print()
    print("Usage: mkdir [-h|--help] <path>")
    print()
    print("Options:")
    print("  -h|--help  Print this message")
    print()
    print("Arguments:")
    print("  path  A path to new directory")

    return
  end

  sock:write("MKD " .. cargs[1] .. "\r\n")
  sock:flush()
  read(trace)
end

function commands.raw(args)
  local cargs, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h or #cargs < 1 then
    print("raw - send a message to the server.")
    print("Sent message will end with CRLF (\\r\\n)")
    print()
    print("Usage: raw [-h|--help] <message>")
    print()
    print("Options:")
    print("  -h|--help  Print this message")
    print()
    print("Arguments:")
    print("  message  Message that should be sent to the server")

    return
  end

  sock:write(cargs[1] .. "\r\n")
  sock:flush()
  os.sleep(0.5)
  read(trace, true)
end

function commands.get(args)
  local cargs, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h or #cargs < 1 then
    print("get - get a file from the server.")
    print()
    print("Usage: get [-h|--help] <remote-path> [local-path]")
    print()
    print("Options:")
    print("  -h|--help  Print this message")
    print()
    print("Arguments:")
    print("  remote-path  A path to file that should be got from the server")
    print("  local-path   A path to local file (remote-path by default)")

    return
  end

  local file, reason = io.open(cargs[2] or cargs[1], "w")

  if not file then
    setFG(0xFF0000)
    print("Error opening file for writing: "
          .. tostring(reason or "unknown error"))
    setFG(0x000000)
    return
  end

  sock:write("SIZE " .. cargs[1] .. "\r\n")
  sock:flush()

  local size = 0
  read(function (str)
    local data = trace(str)
    if data and data.code == 213 and data.isLast then
      size = data.text:match("(%d+)")
    end
  end)
  size = tonumber(size)

  local pasvSock = pasv()
  if not pasvSock then
    return
  end

  sock:write("RETR " .. cargs[1] .. "\r\n")
  sock:flush()
  read(function (str)
    local data = trace(str)
    if data and data.code == 150 and data.isLast then
      local start = computer.uptime()
      local show = size and size > 0
      local now = 0

      io.write(progress(now, size, start, w))

      readPasv(pasvSock, function (chunk, len)
        file:write(chunk)
        if show then
          now = now + len
          term.clearLine()
          io.write(progress(now, size, start, w))
        end
      end)

      if show then
        print()
      end

      file:flush()
      file:close()
    end
  end)
end

function commands.put(args)
  local cargs, copts = shell.parse(table.unpack(args))
  if copts.help or copts.h or #cargs < 1 then
    print("put - put a file to the server.")
    print()
    print("Usage: put [-h|--help] <local-path> [remote-path]")
    print()
    print("Options:")
    print("  -h|--help  Print this message")
    print()
    print("Arguments:")
    print("  local-path   A path to local file.")
    print("  remote-path  A path to file that should be put to the server")
    print("               (local-path by default)")

    return
  end

  local file, reason = io.open(cargs[1], "rb")

  if not file then
    setFG(0xFF0000)
    print("Error opening file for reading: "
          .. tostring(reason or "unknown error"))
    setFG(0x000000)
    return
  end

  local pasvSock = pasv()
  if not pasvSock then
    return
  end

  sock:write("STOR " .. (cargs[2] or cargs[1]) .. "\r\n")
  sock:flush()
  read(function (str)
    local data = trace(str)
    if data and data.code == 150 and data.isLast then
      os.sleep(0.3)

      local start = computer.uptime()
      local size = fs.size(os.getenv("PWD") .. "/" .. cargs[1])
      local now = 0

      io.write(progress(now, size, start, w))

      writePasv(pasvSock, function ()
        local chunk = file:read(chsize)
        if not chunk then
          return
        end

        local len = #chunk

        now = now + len
        term.clearLine()
        io.write(progress(now, size, start, w))

        return chunk, len
      end)

      print()

      file:close()
    end
  end)
end


-- Main ------------------------------------------------------------------------

init(...)
main()
exit()
