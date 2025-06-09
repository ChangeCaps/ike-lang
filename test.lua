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

    for part in string.gmatch(str, pattern) do
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

  return {
    tag = "ok",
    value = contents
  }
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
    local l1
    local l2
    return (function() -- block
      l0 = {path = "test.ike", content = (M["body1"]())((M["body9"]())("test.ike"))};
      return (function() -- match
        local v = (M["body10"]())(l0)
        if v.tag == "ok" and true then
          l1 = v.value
          return (function() -- block
          end)()
        elseif v.tag == "err" and true then
          l2 = v.value
          return (function() -- block
            return (M["body3"]())((M["body27"]())(l2))
          end)()
        end
      end)()
    end)()
end

M["body1"] = function() -- body result::assert
  return function(p0)
    local l0 = p0
    local l1
    local l2
    l0 = p0
    return (function() -- block
      return (function() -- match
        local v = l0
        if v.tag == "ok" and true then
          l1 = v.value
          return l1
        elseif v.tag == "err" and true then
          l2 = v.value
          return (M["body2"]())((M["body8"]())(l2))
        end
      end)()
    end)()
  end
end

M["body2"] = function() -- body panic
  return function(p0)
    local l0 = p0
    l0 = p0
    return (function() -- block
      (M["body3"]())(l0);
      return (M["body7"]())(1)
    end)()
  end
end

M["body3"] = function() -- body io::println
  return function(p0)
    local l0 = p0
    l0 = p0
    return (M["body4"]())(((M["body5"]())("\n"))(l0))
  end
end

M["body4"] = function() -- extern io::print
    return E["io::print"]
end

M["body5"] = function() -- body string::append
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    l0 = p0
    l1 = p1
    return ((M["body6"]())(l1))(l0)
  end
  end
end

M["body6"] = function() -- extern string::prepend
    return E["string::prepend"]
end

M["body7"] = function() -- extern os::exit
    return E["os::exit"]
end

M["body8"] = function() -- extern debug::format
    return E["debug::format"]
end

M["body9"] = function() -- extern fs::read
    return E["fs::read"]
end

M["body10"] = function() -- body tokenize
  return function(p0)
    local l0 = p0
    local l1
    l0 = p0
    return (function() -- block
      l1 = {file = l0, graphs = (M["body11"]())(l0.content), offset = 0};
      return (M["body12"]())(l1)
    end)()
  end
end

M["body11"] = function() -- extern string::graphemes
    return E["string::graphemes"]
end

M["body12"] = function() -- body lexer::all
  return function(p0)
    local l0 = p0
    local l1
    l0 = p0
    return (function() -- block
      return (function() -- match
        local v = (M["body13"]())(l0)
        if v.tag == "none" then
          return (M["body16"]())({})
        elseif v.tag == "some" and true then
          l1 = v.value
          return (function() -- block
            (M["body17"]())(((M["body19"]())(l0))(l1));
            return ((M["body22"]())(l0))(l1)
          end)()
        end
      end)()
    end)()
  end
end

M["body13"] = function() -- body lexer::peek
  return function(p0)
    local l0 = p0
    local l1
    l0 = p0
    return (function() -- block
      return (function() -- match
        local v = l0.graphs
        if #v > 0 and true and true then
          l1 = v[1];
          return (M["body14"]())(l1)
        elseif #v == 0 then
          return M["body15"]()
        end
      end)()
    end)()
  end
end

M["body14"] = function() -- body some
  return function(p0)
    local l0 = p0
    l0 = p0
    return { tag = "some", value = l0 }
  end
end

M["body15"] = function() -- body none
    return { tag = "none" }
end

M["body16"] = function() -- body ok
  return function(p0)
    local l0 = p0
    l0 = p0
    return { tag = "ok", value = l0 }
  end
end

M["body17"] = function() -- body option::or
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    local l2
    l0 = p0
    l1 = p1
    return (function() -- block
      return (function() -- match
        local v = l0
        if v.tag == "some" and true then
          l2 = v.value
          return (M["body18"]())(l2)
        elseif v.tag == "none" then
          return l1
        end
      end)()
    end)()
  end
  end
end

M["body18"] = function() -- body some
  return function(p0)
    local l0 = p0
    l0 = p0
    return { tag = "some", value = l0 }
  end
end

M["body19"] = function() -- body lexer::whitespace
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    l0 = p0
    l1 = p1
    return (function() -- block
      return (function() -- match
        local v = (M["body20"]())(l1)
        if true == v then
          return M["body21"]()
        elseif false == v then
          return M["body21"]()
        end
      end)()
    end)()
  end
  end
end

M["body20"] = function() -- body lexer::is-whitespace
  return function(p0)
    local l0 = p0
    l0 = p0
    return ((l0 == " ") or ((l0 == "\t") or (l0 == "\r")))
  end
end

M["body21"] = function() -- body none
    return { tag = "none" }
end

M["body22"] = function() -- body lexer::unexpected-character
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    local l2
    local l3
    l0 = p0
    l1 = p1
    return (function() -- block
      l2 = {file = l0.file, lo = l0.offset, hi = (l0.offset + 1)};
      l3 = ((M["body5"]())("`"))(((M["body5"]())(l1))("unexpected character `"));
      return (M["body23"]())((((M["body24"]())(l2))("found here"))((M["body25"]())(l3)))
    end)()
  end
  end
end

M["body23"] = function() -- body err
  return function(p0)
    local l0 = p0
    l0 = p0
    return { tag = "err", value = l0 }
  end
end

M["body24"] = function() -- body diagnostic::with-label
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 = p0
    local l1 = p1
    local l2 = p2
    local l3
    l0 = p0
    l1 = p1
    l2 = p2
    return (function() -- block
      l3 = {message = (M["body14"]())(l1), span = l0};
      return {color = l2.color, level = l2.level, message = l2.message, labels = { __list = true, l3, l2.labels }}
    end)()
  end
  end
  end
end

M["body25"] = function() -- body diagnostic::error
  return function(p0)
    local l0 = p0
    l0 = p0
    return (function() -- block
      return {color = M["body26"](), level = "error", message = l0, labels = {}}
    end)()
  end
end

M["body26"] = function() -- body red
    return { tag = "red" }
end

M["body27"] = function() -- body diagnostic::format
  return function(p0)
    local l0 = p0
    local l1
    local l2
    l0 = p0
    return (function() -- block
      l1 = (M["body28"]())((M["body29"]())((((M["body30"]())(0))(M["body31"]()))(((M["body32"]())(M["body33"]()))(l0.labels))));
      l2 = (((M["body38"]())(l0.labels))(l0.color))(l1);
      return ((M["body5"]())(l2))(((M["body5"]())("\n"))((M["body52"]())(l0)))
    end)()
  end
end

M["body28"] = function() -- extern string::length
    return E["string::length"]
end

M["body29"] = function() -- extern debug::format
    return E["debug::format"]
end

M["body30"] = function() -- body list::foldl
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 = p0
    local l1 = p1
    local l2 = p2
    local l3
    local l4
    l0 = p0
    l1 = p1
    l2 = p2
    return (function() -- block
      return (function() -- match
        local v = l2
        if #v == 0 then
          return l0
        elseif #v > 0 and true and true then
          l4 = v[1];
          l3 = v[2]
          return (((M["body30"]())(((l1)(l0))(l4)))(l1))(l3)
        end
      end)()
    end)()
  end
  end
  end
end

M["body31"] = function() -- body math::max
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    l0 = p0
    l1 = p1
    return (function() -- block
      return (function() -- match
        local v = (l0 < l1)
        if true == v then
          return l1
        elseif false == v then
          return l0
        end
      end)()
    end)()
  end
  end
end

M["body32"] = function() -- body list::map
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    local l2
    local l3
    l0 = p0
    l1 = p1
    return (function() -- block
      return (function() -- match
        local v = l1
        if #v == 0 then
          return {}
        elseif #v > 0 and true and true then
          l3 = v[1];
          l2 = v[2]
          return { __list = true, (l0)(l3), ((M["body32"]())(l0))(l2) }
        end
      end)()
    end)()
  end
  end
end

M["body33"] = function() -- body diagnostic::format::{lambda}
  return function(p0)
    local l0 = p0
    l0 = p0
    return (M["body34"]())(l0.span)
  end
end

M["body34"] = function() -- body span::line
  return function(p0)
    local l0 = p0
    local l1
    l0 = p0
    return (function() -- block
      l1 = (((M["body35"]())(({ __tuple = true, 1, 0})))((M["body36"]())(l0)))(((M["body37"]())("\n"))(l0.file.content))[1];
      return l1
    end)()
  end
end

M["body35"] = function() -- body list::foldl
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 = p0
    local l1 = p1
    local l2 = p2
    local l3
    local l4
    l0 = p0
    l1 = p1
    l2 = p2
    return (function() -- block
      return (function() -- match
        local v = l2
        if #v == 0 then
          return l0
        elseif #v > 0 and true and true then
          l4 = v[1];
          l3 = v[2]
          return (((M["body35"]())(((l1)(l0))(l4)))(l1))(l3)
        end
      end)()
    end)()
  end
  end
  end
end

M["body36"] = function() -- body span::line::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 = p0
    local l1 = p1
    local l2 = p2
    local l3
    local l4
    l4 = p0
    l0 = p1[1];
l1 = p1[2]
    l2 = p2
    return (function() -- block
      l3 = ((l1 + (M["body28"]())(l2)) + 1);
      return (function() -- match
        local v = (l1 >= l4.lo)
        if true == v then
          return ({ __tuple = true, l0, l3})
        elseif false == v then
          return ({ __tuple = true, (l0 + 1), l3})
        end
      end)()
    end)()
  end
  end
  end
end

M["body37"] = function() -- extern string::split
    return E["string::split"]
end

M["body38"] = function() -- body diagnostic::format-labels
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 = p0
    local l1 = p1
    local l2 = p2
    local l3
    local l4
    l0 = p0
    l1 = p1
    l2 = p2
    return (function() -- block
      return (function() -- match
        local v = l0
        if #v == 0 then
          return ""
        elseif #v > 0 and true and true then
          l4 = v[1];
          l3 = v[2]
          return (function() -- block
            return ((M["body5"]())((((M["body38"]())(l3))(l1))(l2)))((((M["body39"]())(l4))(l1))(l2))
          end)()
        end
      end)()
    end)()
  end
  end
  end
end

M["body39"] = function() -- body diagnostic::format-label
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 = p0
    local l1 = p1
    local l2 = p2
    local l3
    local l4
    local l5
    local l6
    l0 = p0
    l1 = p1
    l2 = p2
    return (function() -- block
      l3 = (M["body34"]())(l0.span);
      l4 = (M["body40"]())((M["body43"]())(l0.span))[1];
      l5 = (M["body40"]())((M["body43"]())(l0.span))[2];
      l6 = (l0.span.lo - l4);
      return ((M["body5"]())("\n"))(((M["body5"]())(((M["body48"]())(l1))(((M["body49"]())(""))(l0.message))))(((M["body5"]())(" "))(((M["body5"]())(((M["body48"]())(l1))(((M["body50"]())((l0.span.hi - l0.span.lo)))("^"))))(((M["body5"]())(((M["body50"]())(l6))(" ")))(((M["body5"]())(((M["body48"]())(M["body51"]()))("|")))(((M["body5"]())(((M["body50"]())((l2 + 1)))(" ")))(((M["body5"]())("\n"))(((M["body5"]())(l5))(((M["body5"]())(" "))(((M["body5"]())(((M["body48"]())(M["body51"]()))("|")))(((M["body5"]())(" "))(((M["body5"]())(((M["body48"]())(M["body51"]()))((M["body29"]())(l3))))(((M["body5"]())(((M["body48"]())(M["body51"]()))("|\n")))(((M["body5"]())(((M["body50"]())((l2 + 1)))(" ")))(((M["body5"]())("\n"))(((M["body5"]())((M["body29"]())(l6)))(((M["body5"]())(":"))(((M["body5"]())((M["body29"]())(l3)))(((M["body5"]())(":"))(((M["body5"]())(l0.span.file.path))(((M["body5"]())(" "))(((M["body5"]())(((M["body48"]())(M["body51"]()))("-->")))(((M["body50"]())(l2))(" "))))))))))))))))))))))))
    end)()
  end
  end
  end
end

M["body40"] = function() -- body option::assert
  return function(p0)
    local l0 = p0
    local l1
    l0 = p0
    return (function() -- block
      return (function() -- match
        local v = l0
        if v.tag == "some" and true then
          l1 = v.value
          return l1
        elseif v.tag == "none" then
          return (M["body41"]())("option was none")
        end
      end)()
    end)()
  end
end

M["body41"] = function() -- body panic
  return function(p0)
    local l0 = p0
    l0 = p0
    return (function() -- block
      (M["body3"]())(l0);
      return (M["body42"]())(1)
    end)()
  end
end

M["body42"] = function() -- extern os::exit
    return E["os::exit"]
end

M["body43"] = function() -- body span::column
  return function(p0)
    local l0 = p0
    local l1
    l0 = p0
    return (function() -- block
      l1 = (((M["body44"]())(({ __tuple = true, M["body45"](), 0})))((M["body46"]())(l0)))(((M["body37"]())("\n"))(l0.file.content))[1];
      return l1
    end)()
  end
end

M["body44"] = function() -- body list::foldl
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 = p0
    local l1 = p1
    local l2 = p2
    local l3
    local l4
    l0 = p0
    l1 = p1
    l2 = p2
    return (function() -- block
      return (function() -- match
        local v = l2
        if #v == 0 then
          return l0
        elseif #v > 0 and true and true then
          l4 = v[1];
          l3 = v[2]
          return (((M["body44"]())(((l1)(l0))(l4)))(l1))(l3)
        end
      end)()
    end)()
  end
  end
  end
end

M["body45"] = function() -- body none
    return { tag = "none" }
end

M["body46"] = function() -- body span::column::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 = p0
    local l1 = p1
    local l2 = p2
    local l3
    local l4
    l4 = p0
    l0 = p1[1];
l1 = p1[2]
    l2 = p2
    return (function() -- block
      l3 = ((l1 + (M["body28"]())(l2)) + 1);
      return (function() -- match
        local v = ((l4.lo >= l1) and (l4.lo < l3))
        if true == v then
          return ({ __tuple = true, (M["body47"]())(({ __tuple = true, l1, l2})), l3})
        elseif false == v then
          return ({ __tuple = true, l0, l3})
        end
      end)()
    end)()
  end
  end
  end
end

M["body47"] = function() -- body some
  return function(p0)
    local l0 = p0
    l0 = p0
    return { tag = "some", value = l0 }
  end
end

M["body48"] = function() -- body colorize
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
      return ((M["body5"]())(l3))(((M["body6"]())(l2))(l1))
    end)()
  end
  end
end

M["body49"] = function() -- body option::some-or
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    local l2
    l0 = p0
    l1 = p1
    return (function() -- block
      return (function() -- match
        local v = l1
        if v.tag == "some" and true then
          l2 = v.value
          return l2
        elseif v.tag == "none" then
          return l0
        end
      end)()
    end)()
  end
  end
end

M["body50"] = function() -- body string::repeat
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    l0 = p0
    l1 = p1
    return (function() -- block
      return (function() -- match
        local v = (l0 <= 1)
        if true == v then
          return l1
        elseif false == v then
          return ((M["body5"]())(l1))(((M["body50"]())((l0 - 1)))(l1))
        end
      end)()
    end)()
  end
  end
end

M["body51"] = function() -- body blue
    return { tag = "blue" }
end

M["body52"] = function() -- body diagnostic::format-header
  return function(p0)
    local l0 = p0
    l0 = p0
    return (function() -- block
      return ((M["body5"]())((M["body53"]())(l0.message)))(((M["body5"]())(" "))(((M["body5"]())((M["body53"]())(":")))((M["body53"]())(((M["body48"]())(l0.color))(l0.level)))))
    end)()
  end
end

M["body53"] = function() -- body bold
  return function(p0)
    local l0 = p0
    local l1
    local l2
    l0 = p0
    return (function() -- block
      l1 = "\x1b[1m";
      l2 = "\x1b[0m";
      return ((M["body5"]())(l2))(((M["body6"]())(l1))(l0))
    end)()
  end
end

M["body0"]()