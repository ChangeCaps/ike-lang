local function isList(value)
  return type(value) == "table" and value.__list
end

local function isTuple(value)
  return type(value) == "table" and value.__tuple
end

local function isUnion(value)
  return type(value) == "table" and value.tag ~= nil
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

local function toString(value)
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
    local result = ""

    for i, v in ipairs(value) do
      result = result .. toString(v)

      if i < #value then
        result = result .. ", "
      end
    end

    result = result

    return result
  elseif isUnion(value) then
    local result = value.tag

    if value.value ~= nil then
      result = result .. " " .. toString(value.value)
    end

    return result
  elseif type(value) == "table" then
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
    return string.format("%q", value)
  else
    return tostring(value)
  end
end

local E = {}

E["debug::format"] = function(value)
  return toString(value)
end

E["io::print"] = function(str)
  io.write(str)
end

E["string::prepend"] = function(a)
  return function(b)
    return a..b
  end
end

E["string::split"] = function(sep)
  return function(str)
    local parts = {}
    local pattern = "([^" .. sep .. "]+)"

    for part in str:gmatch(pattern) do
      table.insert(parts, part)
    end

    return toList(parts)
  end
end

E["string::graphemes"] = function(str)
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

E["string::length"] = function(str)
  return string.len(str)
end

E["string::sub"] = function(start)
  return function(end_)
    return function(str)
      if start < 1 or end_ < start or end_ > #str then
        return ""
      end

      return str:sub(start, end_)
    end
  end
end

E["fs::read"] = function(path)
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

  return contents
end

E["os::execute"] = function(cmd)
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

E["env::args"] = (function()
  local args = {}

  for i = 1, #arg do
    args[i] = arg[i]
  end

  return toList(args)
end)()

E["os::exit"] = function(code)
  os.exit(code)
end

local M = {}

M["body0"] = function() -- body main
    local l0
    return (function() -- block
      l0 = {file = {path = "ike/main.ike", content = "This is the main file content."}, lo = 0, hi = 0};
      return (M["body1"]())((M["body5"]())(((M["body9"]())(l0))((M["body11"]())("an error occurred"))))
    end)()
end

M["body1"] = function() -- body io::println
  return function(p0)
    local l0 = p0
    l0 = p0
    return (M["body2"]())(((M["body3"]())("\n"))(l0))
  end
end

M["body2"] = function() -- extern io::print
    return E["io::print"]
end

M["body3"] = function() -- body string::append
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    l0 = p0
    l1 = p1
    return ((M["body4"]())(l1))(l0)
  end
  end
end

M["body4"] = function() -- extern string::prepend
    return E["string::prepend"]
end

M["body5"] = function() -- body diagnostic::format
  return function(p0)
    local l0 = p0
    l0 = p0
    return (function() -- block
      return (M["body6"]())(l0)
    end)()
  end
end

M["body6"] = function() -- body diagnostic::format-header
  return function(p0)
    local l0 = p0
    l0 = p0
    return (function() -- block
      return ((M["body3"]())((M["body7"]())(l0.message)))(((M["body3"]())(" "))(((M["body3"]())((M["body7"]())(":")))((M["body7"]())(((M["body8"]())(l0.color))(l0.level)))))
    end)()
  end
end

M["body7"] = function() -- body bold
  return function(p0)
    local l0 = p0
    local l1
    local l2
    l0 = p0
    return (function() -- block
      l1 = "\x1b[1m";
      l2 = "\x1b[0m";
      return ((M["body3"]())(l2))(((M["body4"]())(l1))(l0))
    end)()
  end
end

M["body8"] = function() -- body colorize
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    local l2
    local l3
    l0 = p0
    l1 = p1
    return (function() -- block
      l2 = (function() -- match
        local v = l0
        if v.tag == "red" then
          return "\x1b[31m"
        elseif v.tag == "green" then
          return "\x1b[32m"
        elseif v.tag == "yellow" then
          return "\x1b[33m"
        elseif v.tag == "blue" then
          return "\x1b[34m"
        elseif v.tag == "magenta" then
          return "\x1b[35m"
        elseif v.tag == "cyan" then
          return "\x1b[36m"
        elseif v.tag == "white" then
          return "\x1b[37m"
        end
      end)();
      l3 = "\x1b[0m";
      return ((M["body3"]())(l3))(((M["body4"]())(l2))(l1))
    end)()
  end
  end
end

M["body9"] = function() -- body diagnostic::with-span
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    local l2
    l0 = p0
    l1 = p1
    return (function() -- block
      l2 = {message = M["body10"](), span = l0};
      return {color = l1.color, level = l1.level, message = l1.message, labels = { __list = true, l2, l1.labels }}
    end)()
  end
  end
end

M["body10"] = function() -- body none
    return { tag = "none" }
end

M["body11"] = function() -- body diagnostic::error
  return function(p0)
    local l0 = p0
    l0 = p0
    return (function() -- block
      return {color = M["body12"](), level = "error", message = l0, labels = {}}
    end)()
  end
end

M["body12"] = function() -- body red
    return { tag = "red" }
end

M["body0"]()