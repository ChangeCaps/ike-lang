local function isList(value)
  return type(value) == "table" and value.__list
end

local function isTuple(value)
  return type(value) == "table" and value.__tuple
end

local function isUnion(value)
  return type(value) == "table" and value.tag ~= nil
end

local function isChannel(value)
  return type(value) == "table" and value.__channel
end

local function toList(value)
  local result = { __list = true }

  while #value > 0 do
    result = {
      __list = true,
      value[#value],
      result,
    }

    table.remove(value, #value)
  end

  return result
end

local function fromList(value)
  local result = {}
  local index = 1

  while #value > 0 do
    result[index] = value[1]
    value = value[2]
    index = index + 1
  end

  return result
end

local function equal(a, b)
  if type(a) == "table" then
    for k, v in pairs(a) do
      if not equal(v, b[k]) then
        return false
      end
    end

    return true
  else
    return a == b
  end
end

local function toString(value, no_quote_strings)
  if isList(value) then
    local result = "["

    while #value > 0 do
      result = result .. toString(value[1])
      value = value[2]

      if #value > 0 then
        result = result .. "; "
      end
    end

    result = result .. "]"

    return result
  elseif isTuple(value) then
    local result = "("

    for i, v in ipairs(value) do
      result = result .. toString(v)

      if i < #value then
        result = result .. ", "
      end
    end

    return result .. ")"
  elseif isUnion(value) then
    local result = value.tag

    if value.value ~= nil then
      result = result .. " " .. toString(value.value)
    end

    return result
  elseif isChannel(value) then
    return "channel"
  elseif type(value) == "table" then
    if value.file ~= nil and value.start ~= nil and value["end"] ~= nil then
      return string.format("%s:%d..%d", value.file.path, value.start, value["end"])
    end

    local result = "{ "

    for k, v in pairs(value) do
      result = result .. k .. ": " .. toString(v)

      if next(value, k) then
        result = result .. "; "
      end
    end

    result = result .. " }"

    return result
  elseif type(value) == "string" then
    value = value:gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")

    if no_quote_strings then
      return value
    end

    return "\"" .. value .. "\""
  else
    return tostring(value)
  end
end

local E = {}

E["std::debug::format"] = function()
  return function(value)
    return toString(value)
  end
end

E["std::io::print"] = function()
  return function(str)
    io.write(str)
  end
end

E["std::string::prepend"] = function()
  return function(a)
    return function(b)
      return a..b
    end
  end
end

E["std::string::split"] = function()
  return function(sep)
    return function(str)
      local parts = {}

      for part in string.gmatch(str, "(.-)" .. sep) do
        table.insert(parts, part)
      end

      return toList(parts)
    end
  end
end

E["std::string::graphemes"] = function()
  return function(str)
    local graphemes = {}

    for i = 1, #str do
      local byte = str:byte(i)

      if byte >= 0xD800 and byte <= 0xDBFF then
        -- High surrogate
        i = i + 1

        if i <= #str then
          local low = str:byte(i)

          if low >= 0xDC00 and low <= 0xDFFF then
            -- Low surrogate
            table.insert(graphemes, str:sub(i - 1, i))
          else
            table.insert(graphemes, str:sub(i - 1, i - 1))
          end
        else
          table.insert(graphemes, str:sub(i - 1, i - 1))
        end
      else
        table.insert(graphemes, str:sub(i, i))
      end
    end

    return toList(graphemes)
  end
end

E["std::string::length"] = function()
  return function(str)
    return string.len(str)
  end
end

E["std::string::sub"] = function()
  return function(start)
    return function(end_)
      return function(str)
        if start < 1 or end_ < start or end_ > #str then
          return ""
        end

        return str:sub(start, end_)
      end
    end
  end
end

E["std::fs::read"] = function()
  return function(path)
    local file = io.open(path, "r")

    if not file then
      return {
        tag = "err",
        value = "file not found",
      }
    end

    local contents = file:read("*a")

    if not contents then
      return {
        tag = "err",
        value = "failed to read file",
      }
    end

    file:close()

    return {
      tag = "ok",
      value = contents
    }
  end
end

E["std::os::execute"] = function()
  return function(cmd)
    cmd = fromList(cmd)

    local command = table.concat(cmd, " ")
    local file = io.popen(command, "r")

    if not file then
      return {
        tag = "err",
        value = "failed to execute command",
      }
    end

    local output = file:read("*a")

    local _, _, code = file:close()

    return {
      tag = "ok",
      value = {
        output = output,
        code = code,
      },
    }
  end
end

E["std::env::args"] = function()
  local args = {}

  for i = 1, #arg do
    args[i] = arg[i]
  end

  return toList(args)
end

E["std::os::exit"] = function()
  return function(code)
    os.exit(code)
  end
end

E["std::channel"] = function()
  local channel = { __channel = true }
  local queue = {}
  local waiting = {}

  function channel.send(value)
    if #waiting > 0 then
      coroutine.resume(table.remove(waiting, 1), value)
    else
      queue[#queue + 1] = value
    end
  end

  function channel.recv()
    if #queue > 0 then
      return table.remove(queue, 1)
    else
      waiting[#waiting + 1] = coroutine.running()
      return coroutine.yield()
    end
  end

  function channel.try_recv()
    if #queue > 0 then
      return {
        tag = "some",
        value = table.remove(queue, 1),
      }
    else
      return { tag = "none" }
    end
  end

  return { __tuple = true, channel, channel }
end

E["std::send"] = function()
  return function(input)
    return function(channel)
      channel.send(input)
    end
  end
end

E["std::recv"] = function()
  return function(channel)
    return channel.recv()
  end
end

E["std::try-recv"] = function()
  return function(channel)
    return channel.try_recv()
  end
end

E["std::spawn"] = function()
  return function(f)
    local task = coroutine.create(function()
      local result = f(nil)
      coroutine.yield()
      return result
    end)

    coroutine.resume(task)

    return task
  end
end

E["std::await"] = function()
  return function(task)
    local _, result = coroutine.resume(task)

    return result
  end
end

local M = {}
