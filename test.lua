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
    local l3
    return (function() -- block
      l0 = {path = "test.ike", content = (M["body1"]())((M["body9"]())("test.ike"))};
      return (function() -- match
        local v = (M["body10"]())(l0)
        if v.tag == "ok" and true then
          l1 = v.value
          return (function() -- block
            local t = (M["body102"]())(l1)
            l2 = t[1]
            ;
            return (M["body103"]())(l2)
          end)()
        elseif v.tag == "err" and true then
          l3 = v.value
          return (function() -- block
            return (M["body3"]())((M["body105"]())(l3))
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
    local l2
    local l3
    local l4
    local l5
    l0 = p0
    return (function() -- block
      return (function() -- match
        local v = (M["body13"]())(l0)
        if v.tag == "none" then
          return (M["body16"]())({})
        elseif v.tag == "some" and true then
          l1 = v.value
          return (function() -- block
            l2 = ((M["body17"]())(((M["body19"]())(l0))(l1)))(((M["body17"]())(((M["body55"]())(l0))(l1)))(((M["body17"]())(((M["body70"]())(l0))(l1)))(((M["body17"]())(((M["body82"]())(l0))(l1)))(((M["body17"]())(((M["body90"]())(l0))(l1)))(((M["body92"]())(l0))(l1))))));
            return (function() -- match
              local v = l2
              if v.tag == "some" and true and true and true then
                local t = v.value
                l3 = t[1]
                l4 = t[2]
                l5 = t[3]
                return ((M["body95"]())((M["body97"]())({ __list = true, ({ __tuple = true, l3, l4}), {} })))((M["body12"]())(l5))
              elseif v.tag == "none" then
                return ((M["body98"]())(l0))(l1)
              end
            end)()
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

M["body19"] = function() -- body lexer::one-character-symbol
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    local l2
    local l3
    local l4
    local l5
    l0 = p0
    l1 = p1
    return (function() -- block
      l2 = ((M["body20"]())((M["body23"]())(l1)))(M["body24"]());
      return (function() -- match
        local v = l2
        if v.tag == "none" then
          return M["body52"]()
        elseif v.tag == "some" and true and true then
          local t = v.value
          l3 = t[1]
          l4 = t[2]
          return (function() -- block
            l5 = {file = l0.file, lo = l0.offset, hi = (l0.offset + 1)};
            return (M["body18"]())(({ __tuple = true, l4, l5, (M["body53"]())(l0)}))
          end)()
        end
      end)()
    end)()
  end
  end
end

M["body20"] = function() -- body list::find
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
          return M["body21"]()
        elseif #v > 0 and true and true then
          l3 = v[1];
          l2 = v[2]
          return (function() -- block
            return (function() -- match
              local v = (l0)(l3)
              if true == v then
                return (M["body22"]())(l3)
              elseif false == v then
                return ((M["body20"]())(l0))(l2)
              end
            end)()
          end)()
        end
      end)()
    end)()
  end
  end
end

M["body21"] = function() -- body none
    return { tag = "none" }
end

M["body22"] = function() -- body some
  return function(p0)
    local l0 = p0
    l0 = p0
    return { tag = "some", value = l0 }
  end
end

M["body23"] = function() -- body lexer::one-character-symbol::{lambda}
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    l1 = p0
    local t = p1
l0 = t[1]


    return (l0 == l1)
  end
  end
end

M["body24"] = function() -- body lexer::one-character-symbols
    return (function() -- block
      return { __list = true, ({ __tuple = true, ";", M["body25"]()}), { __list = true, ({ __tuple = true, ":", M["body26"]()}), { __list = true, ({ __tuple = true, ",", M["body27"]()}), { __list = true, ({ __tuple = true, ".", M["body28"]()}), { __list = true, ({ __tuple = true, "_", M["body29"]()}), { __list = true, ({ __tuple = true, "+", M["body30"]()}), { __list = true, ({ __tuple = true, "-", M["body31"]()}), { __list = true, ({ __tuple = true, "*", M["body32"]()}), { __list = true, ({ __tuple = true, "/", M["body33"]()}), { __list = true, ({ __tuple = true, "\\", M["body34"]()}), { __list = true, ({ __tuple = true, "%", M["body35"]()}), { __list = true, ({ __tuple = true, "&", M["body36"]()}), { __list = true, ({ __tuple = true, "|", M["body37"]()}), { __list = true, ({ __tuple = true, "^", M["body38"]()}), { __list = true, ({ __tuple = true, "!", M["body39"]()}), { __list = true, ({ __tuple = true, "?", M["body40"]()}), { __list = true, ({ __tuple = true, "'", M["body41"]()}), { __list = true, ({ __tuple = true, "=", M["body42"]()}), { __list = true, ({ __tuple = true, "~", M["body43"]()}), { __list = true, ({ __tuple = true, "<", M["body44"]()}), { __list = true, ({ __tuple = true, ">", M["body45"]()}), { __list = true, ({ __tuple = true, "(", M["body46"]()}), { __list = true, ({ __tuple = true, ")", M["body47"]()}), { __list = true, ({ __tuple = true, "{", M["body48"]()}), { __list = true, ({ __tuple = true, "}", M["body49"]()}), { __list = true, ({ __tuple = true, "[", M["body50"]()}), { __list = true, ({ __tuple = true, "]", M["body51"]()}), {} } } } } } } } } } } } } } } } } } } } } } } } } } } }
    end)()
end

M["body25"] = function() -- body semi
    return { tag = "semi" }
end

M["body26"] = function() -- body colon
    return { tag = "colon" }
end

M["body27"] = function() -- body comma
    return { tag = "comma" }
end

M["body28"] = function() -- body dot
    return { tag = "dot" }
end

M["body29"] = function() -- body under
    return { tag = "under" }
end

M["body30"] = function() -- body plus
    return { tag = "plus" }
end

M["body31"] = function() -- body minus
    return { tag = "minus" }
end

M["body32"] = function() -- body star
    return { tag = "star" }
end

M["body33"] = function() -- body slash
    return { tag = "slash" }
end

M["body34"] = function() -- body backslash
    return { tag = "backslash" }
end

M["body35"] = function() -- body percent
    return { tag = "percent" }
end

M["body36"] = function() -- body amp
    return { tag = "amp" }
end

M["body37"] = function() -- body pipe
    return { tag = "pipe" }
end

M["body38"] = function() -- body caret
    return { tag = "caret" }
end

M["body39"] = function() -- body bang
    return { tag = "bang" }
end

M["body40"] = function() -- body question
    return { tag = "question" }
end

M["body41"] = function() -- body quote
    return { tag = "quote" }
end

M["body42"] = function() -- body eq
    return { tag = "eq" }
end

M["body43"] = function() -- body tilde
    return { tag = "tilde" }
end

M["body44"] = function() -- body lt
    return { tag = "lt" }
end

M["body45"] = function() -- body gt
    return { tag = "gt" }
end

M["body46"] = function() -- body lparen
    return { tag = "lparen" }
end

M["body47"] = function() -- body rparen
    return { tag = "rparen" }
end

M["body48"] = function() -- body lbrace
    return { tag = "lbrace" }
end

M["body49"] = function() -- body rbrace
    return { tag = "rbrace" }
end

M["body50"] = function() -- body lbracket
    return { tag = "lbracket" }
end

M["body51"] = function() -- body rbracket
    return { tag = "rbracket" }
end

M["body52"] = function() -- body none
    return { tag = "none" }
end

M["body53"] = function() -- body lexer::advance
  return function(p0)
    local l0 = p0
    local l1
    local l2
    l0 = p0
    return (function() -- block
      return (function() -- match
        local v = l0.graphs
        if #v == 0 then
          return l0
        elseif #v > 0 and true and true then
          l2 = v[1];
          l1 = v[2]
          return (function() -- block
            return {file = l0.file, graphs = l1, offset = (l0.offset + (M["body54"]())(l2))}
          end)()
        end
      end)()
    end)()
  end
end

M["body54"] = function() -- extern string::length
    return E["string::length"]
end

M["body55"] = function() -- body lexer::two-character-symbol
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    local l2
    local l3
    local l4
    local l5
    local l6
    local l7
    local l8
    local l9
    l0 = p0
    l1 = p1
    return (function() -- block
      return (function() -- match
        local v = l0.graphs
        if #v > 0 and true and #(v)[2] > 0 and true and true then
          l3 = v[1];
          l2 = v[2][1];
          return (function() -- block
            l4 = ((M["body6"]())(l3))(l2);
            l5 = ((M["body20"]())((M["body56"]())(l4)))(M["body57"]());
            return (function() -- match
              local v = l5
              if v.tag == "none" then
                return M["body52"]()
              elseif v.tag == "some" and true and true then
                local t = v.value
                l6 = t[1]
                l7 = t[2]
                return (function() -- block
                  l8 = {file = l0.file, lo = l0.offset, hi = (l0.offset + 2)};
                  l9 = (M["body53"]())((M["body53"]())(l0));
                  return (M["body18"]())(({ __tuple = true, l7, l8, l9}))
                end)()
              end
            end)()
          end)()
        elseif true then
          return M["body52"]()
        end
      end)()
    end)()
  end
  end
end

M["body56"] = function() -- body lexer::two-character-symbol::{lambda}
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    l1 = p0
    local t = p1
l0 = t[1]


    return (l0 == l1)
  end
  end
end

M["body57"] = function() -- body lexer::two-character-symbols
    return (function() -- block
      return { __list = true, ({ __tuple = true, "..", M["body58"]()}), { __list = true, ({ __tuple = true, "->", M["body59"]()}), { __list = true, ({ __tuple = true, "<-", M["body60"]()}), { __list = true, ({ __tuple = true, "::", M["body61"]()}), { __list = true, ({ __tuple = true, "&&", M["body62"]()}), { __list = true, ({ __tuple = true, "||", M["body63"]()}), { __list = true, ({ __tuple = true, "==", M["body64"]()}), { __list = true, ({ __tuple = true, "!=", M["body65"]()}), { __list = true, ({ __tuple = true, "<=", M["body66"]()}), { __list = true, ({ __tuple = true, ">=", M["body67"]()}), { __list = true, ({ __tuple = true, "<|", M["body68"]()}), { __list = true, ({ __tuple = true, "|>", M["body69"]()}), {} } } } } } } } } } } } }
    end)()
end

M["body58"] = function() -- body dotdot
    return { tag = "dotdot" }
end

M["body59"] = function() -- body rarrow
    return { tag = "rarrow" }
end

M["body60"] = function() -- body larrow
    return { tag = "larrow" }
end

M["body61"] = function() -- body coloncolon
    return { tag = "coloncolon" }
end

M["body62"] = function() -- body ampamp
    return { tag = "ampamp" }
end

M["body63"] = function() -- body pipepipe
    return { tag = "pipepipe" }
end

M["body64"] = function() -- body eqeq
    return { tag = "eqeq" }
end

M["body65"] = function() -- body noteq
    return { tag = "noteq" }
end

M["body66"] = function() -- body lteq
    return { tag = "lteq" }
end

M["body67"] = function() -- body gteq
    return { tag = "gteq" }
end

M["body68"] = function() -- body ltpipe
    return { tag = "ltpipe" }
end

M["body69"] = function() -- body pipegt
    return { tag = "pipegt" }
end

M["body70"] = function() -- body lexer::string
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    local l2
    local l3
    local l4
    local l5
    local l6
    l0 = p0
    l1 = p1
    return (function() -- block
      return (function() -- match
        local v = (l1 == "\"")
        if false == v then
          return M["body52"]()
        elseif true == v then
          return (function() -- block
            local t = ((M["body71"]())((M["body53"]())(l0)))(M["body78"]())
            l2 = t[1]
            l3 = t[2];
            l4 = (M["body53"]())(l2);
            l5 = {file = l4.file, lo = l0.offset, hi = (l4.offset + 1)};
            l6 = (M["body79"]())((M["body80"]())(l3));
            return (M["body18"]())(({ __tuple = true, l6, l5, l4}))
          end)()
        end
      end)()
    end)()
  end
  end
end

M["body71"] = function() -- body lexer::advance-while
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    l0 = p0
    l1 = p1
    return (function() -- block
      return ((M["body72"]())(({ __tuple = true, l0, {}})))(((M["body73"]())(((M["body76"]())(l0))(l1)))((M["body13"]())(l0)))
    end)()
  end
  end
end

M["body72"] = function() -- body option::some-or
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

M["body73"] = function() -- body option::map
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
          return (M["body74"]())((l0)(l2))
        elseif v.tag == "none" then
          return M["body75"]()
        end
      end)()
    end)()
  end
  end
end

M["body74"] = function() -- body some
  return function(p0)
    local l0 = p0
    l0 = p0
    return { tag = "some", value = l0 }
  end
end

M["body75"] = function() -- body none
    return { tag = "none" }
end

M["body76"] = function() -- body lexer::advance-while::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 = p0
    local l1 = p1
    local l2 = p2
    local l3
    local l4
    l2 = p0
    l1 = p1
    l0 = p2
    return (function() -- block
      return (function() -- match
        local v = (l1)(l0)
        if false == v then
          return ({ __tuple = true, l2, {}})
        elseif true == v then
          return (function() -- block
            local t = ((M["body71"]())((M["body53"]())(l2)))(l1)
            l3 = t[1]
            l4 = t[2];
            return ({ __tuple = true, l3, ((M["body77"]())({ __list = true, l0, {} }))(l4)})
          end)()
        end
      end)()
    end)()
  end
  end
  end
end

M["body77"] = function() -- body list::append
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
        local v = l0
        if #v == 0 then
          return l1
        elseif #v > 0 and true and true then
          l3 = v[1];
          l2 = v[2]
          return { __list = true, l3, ((M["body77"]())(l2))(l1) }
        end
      end)()
    end)()
  end
  end
end

M["body78"] = function() -- body lexer::string::{lambda}
  return function(p0)
    local l0 = p0
    l0 = p0
    return (l0 ~= "\"")
  end
end

M["body79"] = function() -- body string
  return function(p0)
    local l0 = p0
    l0 = p0
    return { tag = "string", value = l0 }
  end
end

M["body80"] = function() -- body string::join
  return function(p0)
    local l0 = p0
    l0 = p0
    return (((M["body81"]())(""))(M["body6"]()))(l0)
  end
end

M["body81"] = function() -- body list::foldl
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
          return (((M["body81"]())(((l1)(l0))(l4)))(l1))(l3)
        end
      end)()
    end)()
  end
  end
  end
end

M["body82"] = function() -- body lexer::ident
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    local l2
    local l3
    local l4
    local l5
    l0 = p0
    l1 = p1
    return (function() -- block
      return (function() -- match
        local v = (M["body83"]())(l1)
        if false == v then
          return M["body52"]()
        elseif true == v then
          return (function() -- block
            local t = ((M["body71"]())(l0))(M["body87"]())
            l2 = t[1]
            l3 = t[2];
            l4 = {file = l2.file, lo = l0.offset, hi = l2.offset};
            l5 = (M["body89"]())((M["body80"]())(l3));
            return (M["body18"]())(({ __tuple = true, l5, l4, l2}))
          end)()
        end
      end)()
    end)()
  end
  end
end

M["body83"] = function() -- body lexer::is-ident-start
  return function(p0)
    local l0 = p0
    local l1
    l0 = p0
    return (function() -- block
      l1 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_";
      return ((M["body84"]())(l0))((M["body11"]())(l1))
    end)()
  end
end

M["body84"] = function() -- body list::contains
  return function(p0)
    local l0 = p0
    l0 = p0
    return (M["body85"]())((M["body86"]())(l0))
  end
end

M["body85"] = function() -- body list::any
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
          return false
        elseif #v > 0 and true and true then
          l3 = v[1];
          l2 = v[2]
          return ((l0)(l3) or ((M["body85"]())(l0))(l2))
        end
      end)()
    end)()
  end
  end
end

M["body86"] = function() -- body list::contains::{lambda}
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    l1 = p0
    l0 = p1
    return (l0 == l1)
  end
  end
end

M["body87"] = function() -- body lexer::is-ident-continue
  return function(p0)
    local l0 = p0
    l0 = p0
    return (function() -- block
      return ((l0 == "-") or ((l0 == "'") or ((M["body88"]())(l0) or (M["body83"]())(l0))))
    end)()
  end
end

M["body88"] = function() -- body lexer::is-digit
  return function(p0)
    local l0 = p0
    local l1
    l0 = p0
    return (function() -- block
      l1 = "0123456789";
      return ((M["body84"]())(l0))((M["body11"]())(l1))
    end)()
  end
end

M["body89"] = function() -- body ident
  return function(p0)
    local l0 = p0
    l0 = p0
    return { tag = "ident", value = l0 }
  end
end

M["body90"] = function() -- body lexer::newline
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
        local v = (l1 == "\n")
        if false == v then
          return M["body52"]()
        elseif true == v then
          return (function() -- block
            l2 = {file = l0.file, lo = l0.offset, hi = (l0.offset + 1)};
            l3 = M["body91"]();
            return (M["body18"]())(({ __tuple = true, l3, l2, (M["body53"]())(l0)}))
          end)()
        end
      end)()
    end)()
  end
  end
end

M["body91"] = function() -- body newline
    return { tag = "newline" }
end

M["body92"] = function() -- body lexer::whitespace
  return function(p0)
  return function(p1)
    local l0 = p0
    local l1 = p1
    local l2
    local l3
    local l4
    local l5
    l0 = p0
    l1 = p1
    return (function() -- block
      return (function() -- match
        local v = (M["body93"]())(l1)
        if false == v then
          return M["body52"]()
        elseif true == v then
          return (function() -- block
            local t = ((M["body71"]())((M["body53"]())(l0)))(M["body93"]())
            l2 = t[1]
            l3 = t[2];
            l4 = {file = l2.file, lo = l0.offset, hi = l2.offset};
            l5 = M["body94"]();
            return (M["body18"]())(({ __tuple = true, l5, l4, l2}))
          end)()
        end
      end)()
    end)()
  end
  end
end

M["body93"] = function() -- body lexer::is-whitespace
  return function(p0)
    local l0 = p0
    l0 = p0
    return ((l0 == " ") or ((l0 == "\t") or (l0 == "\r")))
  end
end

M["body94"] = function() -- body whitespace
    return { tag = "whitespace" }
end

M["body95"] = function() -- body result::map
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
        if v.tag == "ok" and true then
          l2 = v.value
          return (M["body16"]())((l0)(l2))
        elseif v.tag == "err" and true then
          l3 = v.value
          return (M["body96"]())(l3)
        end
      end)()
    end)()
  end
  end
end

M["body96"] = function() -- body err
  return function(p0)
    local l0 = p0
    l0 = p0
    return { tag = "err", value = l0 }
  end
end

M["body97"] = function() -- body list::append
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
        local v = l0
        if #v == 0 then
          return l1
        elseif #v > 0 and true and true then
          l3 = v[1];
          l2 = v[2]
          return { __list = true, l3, ((M["body97"]())(l2))(l1) }
        end
      end)()
    end)()
  end
  end
end

M["body98"] = function() -- body lexer::unexpected-character
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
      return (M["body96"]())((((M["body99"]())(l2))("found here"))((M["body100"]())(l3)))
    end)()
  end
  end
end

M["body99"] = function() -- body diagnostic::with-label
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

M["body100"] = function() -- body diagnostic::error
  return function(p0)
    local l0 = p0
    l0 = p0
    return (function() -- block
      return {color = M["body101"](), level = "error", message = l0, labels = {}}
    end)()
  end
end

M["body101"] = function() -- body red
    return { tag = "red" }
end

M["body102"] = function() -- body list::unzip
  return function(p0)
    local l0 = p0
    local l1
    local l2
    local l3
    local l4
    local l5
    l0 = p0
    return (function() -- block
      return (function() -- match
        local v = l0
        if #v == 0 then
          return ({ __tuple = true, {}, {}})
        elseif #v > 0 and true and true and true then
          local t = v[1]
          l2 = t[1]
          l3 = t[2]
          ;
          l1 = v[2]
          return (function() -- block
            local t = (M["body102"]())(l1)
            l4 = t[1]
            l5 = t[2];
            return ({ __tuple = true, { __list = true, l2, l4 }, { __list = true, l3, l5 }})
          end)()
        end
      end)()
    end)()
  end
end

M["body103"] = function() -- body debug::print
  return function(p0)
    local l0 = p0
    l0 = p0
    return (M["body3"]())((M["body104"]())(l0))
  end
end

M["body104"] = function() -- extern debug::format
    return E["debug::format"]
end

M["body105"] = function() -- body diagnostic::format
  return function(p0)
    local l0 = p0
    local l1
    local l2
    l0 = p0
    return (function() -- block
      l1 = (M["body54"]())((M["body106"]())((((M["body107"]())(0))(M["body108"]()))(((M["body109"]())(M["body110"]()))(l0.labels))));
      l2 = (((M["body115"]())(l0.labels))(l0.color))(l1);
      return ((M["body5"]())(l2))(((M["body5"]())("\n"))((M["body129"]())(l0)))
    end)()
  end
end

M["body106"] = function() -- extern debug::format
    return E["debug::format"]
end

M["body107"] = function() -- body list::foldl
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
          return (((M["body107"]())(((l1)(l0))(l4)))(l1))(l3)
        end
      end)()
    end)()
  end
  end
  end
end

M["body108"] = function() -- body math::max
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

M["body109"] = function() -- body list::map
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
          return { __list = true, (l0)(l3), ((M["body109"]())(l0))(l2) }
        end
      end)()
    end)()
  end
  end
end

M["body110"] = function() -- body diagnostic::format::{lambda}
  return function(p0)
    local l0 = p0
    l0 = p0
    return (M["body111"]())(l0.span)
  end
end

M["body111"] = function() -- body span::line
  return function(p0)
    local l0 = p0
    local l1
    l0 = p0
    return (function() -- block
      local t = (((M["body112"]())(({ __tuple = true, 1, 0})))((M["body113"]())(l0)))(((M["body114"]())("\n"))(l0.file.content))
      l1 = t[1]
      ;
      return l1
    end)()
  end
end

M["body112"] = function() -- body list::foldl
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
          return (((M["body112"]())(((l1)(l0))(l4)))(l1))(l3)
        end
      end)()
    end)()
  end
  end
  end
end

M["body113"] = function() -- body span::line::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 = p0
    local l1 = p1
    local l2 = p2
    local l3
    local l4
    l4 = p0
    local t = p1
l0 = t[1]
l1 = t[2]

    l2 = p2
    return (function() -- block
      l3 = ((l1 + (M["body54"]())(l2)) + 1);
      return (function() -- match
        local v = (l3 >= l4.lo)
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

M["body114"] = function() -- extern string::split
    return E["string::split"]
end

M["body115"] = function() -- body diagnostic::format-labels
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
            return ((M["body5"]())((((M["body115"]())(l3))(l1))(l2)))((((M["body116"]())(l4))(l1))(l2))
          end)()
        end
      end)()
    end)()
  end
  end
  end
end

M["body116"] = function() -- body diagnostic::format-label
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
      l3 = (M["body111"]())(l0.span);
      local t = (M["body117"]())((M["body120"]())(l0.span))
      l4 = t[1]
      l5 = t[2];
      l6 = ((l0.span.lo - l4) + 1);
      return ((M["body5"]())("\n"))(((M["body5"]())(((M["body125"]())(l1))(((M["body126"]())(""))(l0.message))))(((M["body5"]())(" "))(((M["body5"]())(((M["body125"]())(l1))(((M["body127"]())((l0.span.hi - l0.span.lo)))("^"))))(((M["body5"]())(((M["body127"]())(l6))(" ")))(((M["body5"]())(((M["body125"]())(M["body128"]()))("|")))(((M["body5"]())(((M["body127"]())((l2 + 1)))(" ")))(((M["body5"]())("\n"))(((M["body5"]())(l5))(((M["body5"]())(" "))(((M["body5"]())(((M["body125"]())(M["body128"]()))("|")))(((M["body5"]())(" "))(((M["body5"]())(((M["body125"]())(M["body128"]()))((M["body106"]())(l3))))(((M["body5"]())(((M["body125"]())(M["body128"]()))("|\n")))(((M["body5"]())(((M["body127"]())((l2 + 1)))(" ")))(((M["body5"]())("\n"))(((M["body5"]())((M["body106"]())(l6)))(((M["body5"]())(":"))(((M["body5"]())((M["body106"]())(l3)))(((M["body5"]())(":"))(((M["body5"]())(l0.span.file.path))(((M["body5"]())(" "))(((M["body5"]())(((M["body125"]())(M["body128"]()))("-->")))(((M["body127"]())(l2))(" "))))))))))))))))))))))))
    end)()
  end
  end
  end
end

M["body117"] = function() -- body option::assert
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
          return (M["body118"]())("option was none")
        end
      end)()
    end)()
  end
end

M["body118"] = function() -- body panic
  return function(p0)
    local l0 = p0
    l0 = p0
    return (function() -- block
      (M["body3"]())(l0);
      return (M["body119"]())(1)
    end)()
  end
end

M["body119"] = function() -- extern os::exit
    return E["os::exit"]
end

M["body120"] = function() -- body span::column
  return function(p0)
    local l0 = p0
    local l1
    l0 = p0
    return (function() -- block
      local t = (((M["body121"]())(({ __tuple = true, M["body122"](), 0})))((M["body123"]())(l0)))(((M["body114"]())("\n"))(l0.file.content))
      l1 = t[1]
      ;
      return l1
    end)()
  end
end

M["body121"] = function() -- body list::foldl
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
          return (((M["body121"]())(((l1)(l0))(l4)))(l1))(l3)
        end
      end)()
    end)()
  end
  end
  end
end

M["body122"] = function() -- body none
    return { tag = "none" }
end

M["body123"] = function() -- body span::column::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 = p0
    local l1 = p1
    local l2 = p2
    local l3
    local l4
    l4 = p0
    local t = p1
l0 = t[1]
l1 = t[2]

    l2 = p2
    return (function() -- block
      l3 = ((l1 + (M["body54"]())(l2)) + 1);
      return (function() -- match
        local v = ((l4.lo >= l1) and (l4.lo < l3))
        if true == v then
          return ({ __tuple = true, (M["body124"]())(({ __tuple = true, l1, l2})), l3})
        elseif false == v then
          return ({ __tuple = true, l0, l3})
        end
      end)()
    end)()
  end
  end
  end
end

M["body124"] = function() -- body some
  return function(p0)
    local l0 = p0
    l0 = p0
    return { tag = "some", value = l0 }
  end
end

M["body125"] = function() -- body colorize
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

M["body126"] = function() -- body option::some-or
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

M["body127"] = function() -- body string::repeat
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
          return ((M["body5"]())(l1))(((M["body127"]())((l0 - 1)))(l1))
        end
      end)()
    end)()
  end
  end
end

M["body128"] = function() -- body blue
    return { tag = "blue" }
end

M["body129"] = function() -- body diagnostic::format-header
  return function(p0)
    local l0 = p0
    l0 = p0
    return (function() -- block
      return ((M["body5"]())((M["body130"]())(l0.message)))(((M["body5"]())(" "))(((M["body5"]())((M["body130"]())(":")))((M["body130"]())(((M["body125"]())(l0.color))(l0.level)))))
    end)()
  end
end

M["body130"] = function() -- body bold
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