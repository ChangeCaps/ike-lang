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
  elseif type(value) == "table" then
    if value.file ~= nil and value.lo ~= nil and value.hi ~= nil then
      return string.format("%s:%d..%d", value.file.path, value.lo, value.hi)
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
    return "\"" .. value:gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t") .. "\""
  else
    return tostring(value)
  end
end

local E = {}

E["std::debug::format"] = function(value)
  return toString(value)
end

E["std::io::print"] = function(str)
  io.write(str)
end

E["std::string::prepend"] = function(a)
  return function(b)
    return a..b
  end
end

E["std::string::split"] = function(sep)
  return function(str)
    local parts = {}

    for part in string.gmatch(str, "(.-)" .. sep) do
      table.insert(parts, part)
    end

    return toList(parts)
  end
end

E["std::string::graphemes"] = function(str)
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

E["std::string::length"] = function(str)
  return string.len(str)
end

E["std::string::sub"] = function(start)
  return function(end_)
    return function(str)
      if start < 1 or end_ < start or end_ > #str then
        return ""
      end

      return str:sub(start, end_)
    end
  end
end

E["std::fs::read"] = function(path)
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

E["std::os::execute"] = function(cmd)
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

E["std::env::args"] = (function()
  local args = {}

  for i = 1, #arg do
    args[i] = arg[i]
  end

  return toList(args)
end)()

E["std::os::exit"] = function(code)
  os.exit(code)
end

local M = {}

M["body0"] = function() -- body ike::main
    local l0 -- local 'file'
    local l1 -- local 'expr'
    local l2 -- local 'expr'
    local l3 -- local 'e'
    local block_result -- block result
    do -- block
      l0 = { path = "test.ike", content = (M["body1"]())((M["body9"]())("test.ike")) } -- pattern binding assign
      block_result = nil
      l1 = ((M["body10"]())(M["body12"]()))((M["body56"]())(l0)) -- pattern binding assign
      block_result = nil
      local v = l1 -- match target
      local match_result -- match result
      if v.tag == "ok" and true and true then -- match
        local t = v.value -- tuple pattern assign
        l2 = t[1] -- pattern binding assign
        match_result = (M["body161"]())(l2)
      elseif v.tag == "err" and true then -- match
        l3 = v.value -- pattern binding assign
        local block_result -- block result
        do -- block
          block_result = (M["body4"]())((M["body163"]())(l3))
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
end

M["body1"] = function() -- body std::result::assert
  return function(p0)
    local l0 -- local 'r'
    local l1 -- local 'v'
    local l2 -- local 'e'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0 -- match target
      local match_result -- match result
      if v.tag == "ok" and true then -- match
        l1 = v.value -- pattern binding assign
        match_result = l1
      elseif v.tag == "err" and true then -- match
        l2 = v.value -- pattern binding assign
        match_result = (M["body2"]())((M["body8"]())(l2))
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body2"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = (M["body3"]())("thread main panic: `")
      block_result = (M["body3"]())(l0)
      block_result = (M["body4"]())("`")
      block_result = (M["body7"]())(1)
    end
    return block_result
  end
end

M["body3"] = function() -- extern std::io::print
    return E["std::io::print"]
end

M["body4"] = function() -- body std::io::println
  return function(p0)
    local l0 -- local 's'
    l0 = p0 -- pattern binding assign
    return (M["body3"]())(((M["body5"]())("\n"))(l0))
  end
end

M["body5"] = function() -- body std::string::append
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
    local l1 -- local 'b'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    return ((M["body6"]())(l1))(l0)
  end
  end
end

M["body6"] = function() -- extern std::string::prepend
    return E["std::string::prepend"]
end

M["body7"] = function() -- extern std::os::exit
    return E["std::os::exit"]
end

M["body8"] = function() -- extern std::debug::format
    return E["std::debug::format"]
end

M["body9"] = function() -- extern std::fs::read
    return E["std::fs::read"]
end

M["body10"] = function() -- body std::result::try
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'r'
    local l2 -- local 'v'
    local l3 -- local 'e'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if v.tag == "ok" and true then -- match
        l2 = v.value -- pattern binding assign
        match_result = (l0)(l2)
      elseif v.tag == "err" and true then -- match
        l3 = v.value -- pattern binding assign
        match_result = (M["body11"]())(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body11"] = function() -- body err
  return function(p0)
    local l0 -- local 'err'
    l0 = p0 -- pattern binding assign
    return { tag = "err", value = l0 }
  end
end

M["body12"] = function() -- body ike::main::{lambda}
  return function(p0)
    local l0 -- local 'tokens'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      l1 = (M["body13"]())(l0) -- pattern binding assign
      block_result = nil
      block_result = (M["body14"]())(l1)
    end
    return block_result
  end
end

M["body13"] = function() -- body ike::parse::parser::new
  return function(p0)
    local l0 -- local 'tokens'
    l0 = p0 -- pattern binding assign
    return { tokens = l0 }
  end
end

M["body14"] = function() -- body ike::parse::expr
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    return (M["body15"]())(l0)
  end
end

M["body15"] = function() -- body ike::parse::expr::binary
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = ((M["body16"]())(M["body18"]()))((M["body41"]())(l0))
    end
    return block_result
  end
end

M["body16"] = function() -- body std::result::try
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'r'
    local l2 -- local 'v'
    local l3 -- local 'e'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if v.tag == "ok" and true then -- match
        l2 = v.value -- pattern binding assign
        match_result = (l0)(l2)
      elseif v.tag == "err" and true then -- match
        l3 = v.value -- pattern binding assign
        match_result = (M["body17"]())(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body17"] = function() -- body err
  return function(p0)
    local l0 -- local 'err'
    l0 = p0 -- pattern binding assign
    return { tag = "err", value = l0 }
  end
end

M["body18"] = function() -- body ike::parse::expr::binary::{lambda}
  return function(p0)
    local l0 -- local 'lhs'
    local l1 -- local 'parser'
    local l2 -- local 'token'
    local l3 -- local 'span'
    local t = p0 -- tuple pattern assign
    l0 = t[1] -- pattern binding assign
    l1 = t[2] -- pattern binding assign
    local block_result -- block result
    do -- block
      local t = (M["body19"]())(l1) -- tuple pattern assign
      l2 = t[1] -- pattern binding assign
      l3 = t[2] -- pattern binding assign
      block_result = nil
      local v = l2 -- match target
      local match_result -- match result
      if v.tag == "plus" then -- match
        match_result = (((M["body22"]())(l0))(M["body36"]()))(l1)
      elseif v.tag == "minus" then -- match
        match_result = (((M["body22"]())(l0))(M["body37"]()))(l1)
      elseif v.tag == "star" then -- match
        match_result = (((M["body22"]())(l0))(M["body38"]()))(l1)
      elseif v.tag == "slash" then -- match
        match_result = (((M["body22"]())(l0))(M["body39"]()))(l1)
      elseif v.tag == "percent" then -- match
        match_result = (((M["body22"]())(l0))(M["body40"]()))(l1)
      elseif true then -- match
        match_result = (M["body32"]())({ __tuple = true, l0, l1 })
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body19"] = function() -- body ike::parse::parser::peek
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'tokens'
    local l2 -- local 't'
    local l3 -- local 's'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0.tokens -- match target
      local match_result -- match result
      if #v > 0 and (v)[1][1].tag == "whitespace" and true and true then -- match
        local t = (v)[1] -- tuple pattern assign
        l1 = (v)[2] -- pattern binding assign
        match_result = (M["body19"]())((M["body13"]())(l1))
      elseif #v > 0 and true and true and true then -- match
        local t = (v)[1] -- tuple pattern assign
        l2 = t[1] -- pattern binding assign
        l3 = t[2] -- pattern binding assign
        match_result = { __tuple = true, l2, l3 }
      elseif #v == 0 then -- match
        match_result = (M["body20"]())("unreachable")
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body20"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = (M["body3"]())("thread main panic: `")
      block_result = (M["body3"]())(l0)
      block_result = (M["body4"]())("`")
      block_result = (M["body21"]())(1)
    end
    return block_result
  end
end

M["body21"] = function() -- extern std::os::exit
    return E["std::os::exit"]
end

M["body22"] = function() -- body ike::parse::expr::binary'
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'lhs'
    local l1 -- local 'op'
    local l2 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = ((M["body16"]())(((M["body23"]())(l0))(l1)))((M["body15"]())((M["body33"]())(l2)))
    end
    return block_result
  end
  end
  end
end

M["body23"] = function() -- body ike::parse::expr::binary'::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'rhs'
    local l1 -- local 'parser'
    local l2 -- local 'op''
    local l3 -- local 'lhs''
    local l4 -- local 'rhs''
    local l5 -- local 'op'
    local l6 -- local 'lhs'
    local l7 -- local 'lhs'
    local l8 -- local 'expr'
    local l9 -- local 'expr'
    local l10 -- local 'expr'
    l6 = p0 -- pattern binding assign
    l5 = p1 -- pattern binding assign
    local t = p2 -- tuple pattern assign
    l0 = t[1] -- pattern binding assign
    l1 = t[2] -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0.kind -- match target
      local match_result -- match result
      if v.tag == "binary" and true and true and true then -- match
        local t = v.value -- tuple pattern assign
        l2 = t[1] -- pattern binding assign
        l3 = t[2] -- pattern binding assign
        l4 = t[3] -- pattern binding assign
        local block_result -- block result
        do -- block
          local v = ((M["body24"]())(l5) >= (M["body24"]())(l2)) -- match target
          local match_result -- match result
          if true == v then -- match
            local block_result -- block result
            do -- block
              l7 = { kind = (M["body25"]())({ __tuple = true, l5, l6, l3 }), span = ((M["body26"]())(l6.span))(l3.span) } -- pattern binding assign
              block_result = nil
              l8 = { kind = (M["body25"]())({ __tuple = true, l2, l7, l4 }), span = ((M["body26"]())(l7.span))(l4.span) } -- pattern binding assign
              block_result = nil
              block_result = (M["body32"]())({ __tuple = true, l8, l1 })
            end
            match_result = block_result
          elseif false == v then -- match
            local block_result -- block result
            do -- block
              l9 = { kind = (M["body25"]())({ __tuple = true, l5, l6, l0 }), span = ((M["body26"]())(l6.span))(l0.span) } -- pattern binding assign
              block_result = nil
              block_result = (M["body32"]())({ __tuple = true, l9, l1 })
            end
            match_result = block_result
          end
          block_result = match_result
        end
        match_result = block_result
      elseif true then -- match
        local block_result -- block result
        do -- block
          l10 = { kind = (M["body25"]())({ __tuple = true, l5, l6, l0 }), span = ((M["body26"]())(l6.span))(l0.span) } -- pattern binding assign
          block_result = nil
          block_result = (M["body32"]())({ __tuple = true, l10, l1 })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body24"] = function() -- body ike::parse::expr::binary-precedence
  return function(p0)
    local l0 -- local 'op'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0 -- match target
      local match_result -- match result
      if v.tag == "add" then -- match
        match_result = 1
      elseif v.tag == "sub" then -- match
        match_result = 1
      elseif v.tag == "mul" then -- match
        match_result = 2
      elseif v.tag == "div" then -- match
        match_result = 2
      elseif v.tag == "mod" then -- match
        match_result = 2
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body25"] = function() -- body binary
  return function(p0)
    local l0 -- local 'binary'
    l0 = p0 -- pattern binding assign
    return { tag = "binary", value = l0 }
  end
end

M["body26"] = function() -- body ike::span::join
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
    local l1 -- local 'b'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = ((M["body27"]())((l0.file == l1.file)))("Cannot join spans from different sources")
      block_result = { file = l0.file, lo = ((M["body30"]())(l0.lo))(l1.lo), hi = ((M["body31"]())(l0.hi))(l1.hi) }
    end
    return block_result
  end
  end
end

M["body27"] = function() -- body std::assert
  return function(p0)
  return function(p1)
    local l0 -- local 'condition'
    local l1 -- local 'message'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0 -- match target
      local match_result -- match result
      if true == v then -- match
        local block_result -- block result
        do -- block
        end
        match_result = block_result
      elseif false == v then -- match
        match_result = (M["body28"]())(l1)
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body28"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = (M["body3"]())("thread main panic: `")
      block_result = (M["body3"]())(l0)
      block_result = (M["body4"]())("`")
      block_result = (M["body29"]())(1)
    end
    return block_result
  end
end

M["body29"] = function() -- extern std::os::exit
    return E["std::os::exit"]
end

M["body30"] = function() -- body std::math::min
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
    local l1 -- local 'b'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (l0 < l1) -- match target
      local match_result -- match result
      if true == v then -- match
        match_result = l0
      elseif false == v then -- match
        match_result = l1
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body31"] = function() -- body std::math::max
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
    local l1 -- local 'b'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (l0 < l1) -- match target
      local match_result -- match result
      if true == v then -- match
        match_result = l1
      elseif false == v then -- match
        match_result = l0
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body32"] = function() -- body ok
  return function(p0)
    local l0 -- local 'ok'
    l0 = p0 -- pattern binding assign
    return { tag = "ok", value = l0 }
  end
end

M["body33"] = function() -- body ike::parse::parser::advance
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'tokens'
    local l2 -- local 'tokens'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0.tokens -- match target
      local match_result -- match result
      if #v > 0 and (v)[1][1].tag == "eof" and true and true then -- match
        local t = (v)[1] -- tuple pattern assign
        match_result = l0
      elseif #v > 0 and (v)[1][1].tag == "whitespace" and true and true then -- match
        local t = (v)[1] -- tuple pattern assign
        l1 = (v)[2] -- pattern binding assign
        match_result = (M["body33"]())((M["body13"]())(l1))
      elseif #v > 0 and true and true and true then -- match
        local t = (v)[1] -- tuple pattern assign
        l2 = (v)[2] -- pattern binding assign
        match_result = (M["body13"]())(l2)
      elseif #v == 0 then -- match
        match_result = (M["body34"]())("unreachable")
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body34"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = (M["body3"]())("thread main panic: `")
      block_result = (M["body3"]())(l0)
      block_result = (M["body4"]())("`")
      block_result = (M["body35"]())(1)
    end
    return block_result
  end
end

M["body35"] = function() -- extern std::os::exit
    return E["std::os::exit"]
end

M["body36"] = function() -- body add
    return { tag = "add" }
end

M["body37"] = function() -- body sub
    return { tag = "sub" }
end

M["body38"] = function() -- body mul
    return { tag = "mul" }
end

M["body39"] = function() -- body div
    return { tag = "div" }
end

M["body40"] = function() -- body mod
    return { tag = "mod" }
end

M["body41"] = function() -- body ike::parse::expr::term
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'token'
    local l2 -- local 'span'
    local l3 -- local 'n'
    local l4 -- local 'expr'
    local l5 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local t = (M["body19"]())(l0) -- tuple pattern assign
      l1 = t[1] -- pattern binding assign
      l2 = t[2] -- pattern binding assign
      block_result = nil
      local v = l1 -- match target
      local match_result -- match result
      if v.tag == "number" and true then -- match
        l3 = v.value -- pattern binding assign
        local block_result -- block result
        do -- block
          l4 = { kind = (M["body42"]())(l3), span = l2 } -- pattern binding assign
          block_result = nil
          block_result = (M["body32"]())({ __tuple = true, l4, (M["body33"]())(l0) })
        end
        match_result = block_result
      elseif v.tag == "lparen" then -- match
        local block_result -- block result
        do -- block
          block_result = ((M["body16"]())(M["body43"]()))((M["body14"]())((M["body33"]())(l0)))
        end
        match_result = block_result
      elseif true then -- match
        local block_result -- block result
        do -- block
          l5 = ((M["body5"]())("`"))(((M["body5"]())((M["body49"]())(l1)))("expected an expression, found `")) -- pattern binding assign
          block_result = nil
          block_result = (M["body17"]())((((M["body51"]())(l2))("found here"))((M["body53"]())(l5)))
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body42"] = function() -- body number
  return function(p0)
    local l0 -- local 'number'
    l0 = p0 -- pattern binding assign
    return { tag = "number", value = l0 }
  end
end

M["body43"] = function() -- body ike::parse::expr::term::{lambda}
  return function(p0)
    local l0 -- local 'expr'
    local l1 -- local 'parser'
    local t = p0 -- tuple pattern assign
    l0 = t[1] -- pattern binding assign
    l1 = t[2] -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = ((M["body44"]())((M["body45"]())(l0)))(((M["body47"]())(M["body55"]()))(l1))
    end
    return block_result
  end
end

M["body44"] = function() -- body std::result::try
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'r'
    local l2 -- local 'v'
    local l3 -- local 'e'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if v.tag == "ok" and true then -- match
        l2 = v.value -- pattern binding assign
        match_result = (l0)(l2)
      elseif v.tag == "err" and true then -- match
        l3 = v.value -- pattern binding assign
        match_result = (M["body17"]())(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body45"] = function() -- body ike::parse::expr::term::{lambda}::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 'span'
    local l1 -- local 'parser'
    local l2 -- local 'expr'
    local l3 -- local 'expr'
    l2 = p0 -- pattern binding assign
    local t = p1 -- tuple pattern assign
    l0 = t[1] -- pattern binding assign
    l1 = t[2] -- pattern binding assign
    local block_result -- block result
    do -- block
      l3 = { kind = (M["body46"]())(l2), span = ((M["body26"]())(l0))(l2.span) } -- pattern binding assign
      block_result = nil
      block_result = (M["body32"]())({ __tuple = true, l3, l1 })
    end
    return block_result
  end
  end
end

M["body46"] = function() -- body grouped
  return function(p0)
    local l0 -- local 'grouped'
    l0 = p0 -- pattern binding assign
    return { tag = "grouped", value = l0 }
  end
end

M["body47"] = function() -- body ike::parse::parser::expect
  return function(p0)
  return function(p1)
    local l0 -- local 'token'
    local l1 -- local 'parser'
    local l2 -- local 't'
    local l3 -- local 'span'
    local l4 -- local 'message'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local t = (M["body19"]())(l1) -- tuple pattern assign
      l2 = t[1] -- pattern binding assign
      l3 = t[2] -- pattern binding assign
      block_result = nil
      local v = (l2 == l0) -- match target
      local match_result -- match result
      if true == v then -- match
        match_result = (M["body48"]())({ __tuple = true, l3, (M["body33"]())(l1) })
      elseif false == v then -- match
        local block_result -- block result
        do -- block
          l4 = ((M["body5"]())("`"))(((M["body5"]())((M["body49"]())(l2)))(((M["body5"]())("`, found `"))(((M["body5"]())((M["body49"]())(l0)))("expected `")))) -- pattern binding assign
          block_result = nil
          block_result = (M["body50"]())((((M["body51"]())(l3))("found here"))((M["body53"]())(l4)))
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body48"] = function() -- body ok
  return function(p0)
    local l0 -- local 'ok'
    l0 = p0 -- pattern binding assign
    return { tag = "ok", value = l0 }
  end
end

M["body49"] = function() -- extern std::debug::format
    return E["std::debug::format"]
end

M["body50"] = function() -- body err
  return function(p0)
    local l0 -- local 'err'
    l0 = p0 -- pattern binding assign
    return { tag = "err", value = l0 }
  end
end

M["body51"] = function() -- body ike::diagnostic::with-label
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'span'
    local l1 -- local 'message'
    local l2 -- local 'diagnostic'
    local l3 -- local 'label'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result -- block result
    do -- block
      l3 = { message = (M["body52"]())(l1), span = l0 } -- pattern binding assign
      block_result = nil
      block_result = { color = l2.color, level = l2.level, message = l2.message, labels = { __list = true, l3, l2.labels } }
    end
    return block_result
  end
  end
  end
end

M["body52"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body53"] = function() -- body ike::diagnostic::error
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = { color = M["body54"](), level = "error", message = l0, labels = { __list = true } }
    end
    return block_result
  end
end

M["body54"] = function() -- body red
    return { tag = "red" }
end

M["body55"] = function() -- body rparen
    return { tag = "rparen" }
end

M["body56"] = function() -- body ike::parse::tokenize
  return function(p0)
    local l0 -- local 'file'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      l1 = { file = l0, graphs = (M["body57"]())(l0.content), offset = 0 } -- pattern binding assign
      block_result = nil
      block_result = (M["body58"]())(l1)
    end
    return block_result
  end
end

M["body57"] = function() -- extern std::string::graphemes
    return E["std::string::graphemes"]
end

M["body58"] = function() -- body ike::parse::lexer::all
  return function(p0)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    local l2 -- local 'result'
    local l3 -- local 'token'
    local l4 -- local 'span'
    local l5 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (M["body59"]())(l0) -- match target
      local match_result -- match result
      if v.tag == "none" then -- match
        match_result = (M["body61"]())({ __list = true, { __tuple = true, M["body62"](), { file = l0.file, lo = l0.offset, hi = l0.offset } }, { __list = true } })
      elseif v.tag == "some" and true then -- match
        l1 = v.value -- pattern binding assign
        local block_result -- block result
        do -- block
          l2 = ((M["body63"]())(((M["body65"]())(l0))(l1)))(((M["body63"]())(((M["body84"]())(l0))(l1)))(((M["body63"]())(((M["body89"]())(l0))(l1)))(((M["body63"]())(((M["body122"]())(l0))(l1)))(((M["body63"]())(((M["body138"]())(l0))(l1)))(((M["body63"]())(((M["body151"]())(l0))(l1)))(((M["body154"]())(l0))(l1))))))) -- pattern binding assign
          block_result = nil
          local v = l2 -- match target
          local match_result -- match result
          if v.tag == "some" and true and true and true then -- match
            local t = v.value -- tuple pattern assign
            l3 = t[1] -- pattern binding assign
            l4 = t[2] -- pattern binding assign
            l5 = t[3] -- pattern binding assign
            match_result = ((M["body157"]())((M["body159"]())({ __list = true, { __tuple = true, l3, l4 }, { __list = true } })))((M["body58"]())(l5))
          elseif v.tag == "none" then -- match
            match_result = ((M["body160"]())(l0))(l1)
          end
          block_result = match_result
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body59"] = function() -- body ike::parse::lexer::peek
  return function(p0)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0.graphs -- match target
      local match_result -- match result
      if #v > 0 and true and true then -- match
        l1 = (v)[1] -- pattern binding assign
        match_result = (M["body52"]())(l1)
      elseif #v == 0 then -- match
        match_result = M["body60"]()
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body60"] = function() -- body none
    return { tag = "none" }
end

M["body61"] = function() -- body ok
  return function(p0)
    local l0 -- local 'ok'
    l0 = p0 -- pattern binding assign
    return { tag = "ok", value = l0 }
  end
end

M["body62"] = function() -- body eof
    return { tag = "eof" }
end

M["body63"] = function() -- body std::option::or-else
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'opt'
    local l2 -- local 'a'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if v.tag == "some" and true then -- match
        l2 = v.value -- pattern binding assign
        match_result = (M["body64"]())(l2)
      elseif v.tag == "none" then -- match
        local block_result -- block result
        do -- block
        end
        match_result = (l0)(block_result)
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body64"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body65"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body66"]())(l1))(l0)
  end
  end
  end
end

M["body66"] = function() -- body ike::parse::lexer::number
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    local l2 -- local 'l'
    local l3 -- local 'gs'
    local l4 -- local 'span'
    local l5 -- local 'token'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (M["body67"]())(l1) -- match target
      local match_result -- match result
      if false == v then -- match
        match_result = M["body71"]()
      elseif true == v then -- match
        local block_result -- block result
        do -- block
          local t = ((M["body72"]())((M["body78"]())(l0)))(M["body67"]()) -- tuple pattern assign
          l2 = t[1] -- pattern binding assign
          l3 = t[2] -- pattern binding assign
          block_result = nil
          l4 = { file = l2.file, lo = l0.offset, hi = l2.offset } -- pattern binding assign
          block_result = nil
          l5 = (M["body81"]())((M["body82"]())({ __list = true, l1, l3 })) -- pattern binding assign
          block_result = nil
          block_result = (M["body64"]())({ __tuple = true, l5, l4, l2 })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body67"] = function() -- body ike::parse::lexer::is-digit
  return function(p0)
    local l0 -- local 'g'
    local l1 -- local 'allowed'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      l1 = "0123456789" -- pattern binding assign
      block_result = nil
      block_result = ((M["body68"]())(l0))((M["body57"]())(l1))
    end
    return block_result
  end
end

M["body68"] = function() -- body std::list::contains
  return function(p0)
    local l0 -- local 'x'
    l0 = p0 -- pattern binding assign
    return (M["body69"]())((M["body70"]())(l0))
  end
end

M["body69"] = function() -- body std::list::any
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'xs'
    local l2 -- local 'xs'
    local l3 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = false
      elseif #v > 0 and true and true then -- match
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        match_result = ((l0)(l3) or ((M["body69"]())(l0))(l2))
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body70"] = function() -- body std::list::contains::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 'y'
    local l1 -- local 'x'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return (l0 == l1)
  end
  end
end

M["body71"] = function() -- body none
    return { tag = "none" }
end

M["body72"] = function() -- body ike::parse::lexer::advance-while
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'f'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = ((M["body73"]())({ __tuple = true, l0, { __list = true } }))(((M["body74"]())(((M["body77"]())(l0))(l1)))((M["body59"]())(l0)))
    end
    return block_result
  end
  end
end

M["body73"] = function() -- body std::option::some-or
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
    local l1 -- local 'opt'
    local l2 -- local 'a'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if v.tag == "some" and true then -- match
        l2 = v.value -- pattern binding assign
        match_result = l2
      elseif v.tag == "none" then -- match
        match_result = l0
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body74"] = function() -- body std::option::map
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'opt'
    local l2 -- local 'a'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if v.tag == "some" and true then -- match
        l2 = v.value -- pattern binding assign
        match_result = (M["body75"]())((l0)(l2))
      elseif v.tag == "none" then -- match
        match_result = M["body76"]()
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body75"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body76"] = function() -- body none
    return { tag = "none" }
end

M["body77"] = function() -- body ike::parse::lexer::advance-while::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'f'
    local l2 -- local 'lexer'
    local l3 -- local 'l'
    local l4 -- local 'gs'
    l2 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l0 = p2 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (l1)(l0) -- match target
      local match_result -- match result
      if false == v then -- match
        match_result = { __tuple = true, l2, { __list = true } }
      elseif true == v then -- match
        local block_result -- block result
        do -- block
          local t = ((M["body72"]())((M["body78"]())(l2)))(l1) -- tuple pattern assign
          l3 = t[1] -- pattern binding assign
          l4 = t[2] -- pattern binding assign
          block_result = nil
          block_result = { __tuple = true, l3, ((M["body80"]())({ __list = true, l0, { __list = true } }))(l4) }
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body78"] = function() -- body ike::parse::lexer::advance
  return function(p0)
    local l0 -- local 'lexer'
    local l1 -- local 'gs'
    local l2 -- local 'g'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0.graphs -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = l0
      elseif #v > 0 and true and true then -- match
        l2 = (v)[1] -- pattern binding assign
        l1 = (v)[2] -- pattern binding assign
        local block_result -- block result
        do -- block
          block_result = { file = l0.file, graphs = l1, offset = (l0.offset + (M["body79"]())(l2)) }
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body79"] = function() -- extern std::string::length
    return E["std::string::length"]
end

M["body80"] = function() -- body std::list::append
  return function(p0)
  return function(p1)
    local l0 -- local 'xs'
    local l1 -- local 'ys'
    local l2 -- local 'xs'
    local l3 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = l1
      elseif #v > 0 and true and true then -- match
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        match_result = { __list = true, l3, ((M["body80"]())(l2))(l1) }
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body81"] = function() -- body number
  return function(p0)
    local l0 -- local 'number'
    l0 = p0 -- pattern binding assign
    return { tag = "number", value = l0 }
  end
end

M["body82"] = function() -- body std::string::join
  return function(p0)
    local l0 -- local 'xs'
    l0 = p0 -- pattern binding assign
    return (((M["body83"]())(""))(M["body6"]()))(l0)
  end
end

M["body83"] = function() -- body std::list::foldl
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'acc'
    local l1 -- local 'f'
    local l2 -- local 'xs'
    local l3 -- local 'xs'
    local l4 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l2 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = l0
      elseif #v > 0 and true and true then -- match
        l4 = (v)[1] -- pattern binding assign
        l3 = (v)[2] -- pattern binding assign
        match_result = (((M["body83"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body84"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body85"]())(l1))(l0)
  end
  end
  end
end

M["body85"] = function() -- body ike::parse::lexer::ident
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    local l2 -- local 'l'
    local l3 -- local 'gs'
    local l4 -- local 'span'
    local l5 -- local 'token'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (M["body86"]())(l1) -- match target
      local match_result -- match result
      if false == v then -- match
        match_result = M["body71"]()
      elseif true == v then -- match
        local block_result -- block result
        do -- block
          local t = ((M["body72"]())(l0))(M["body87"]()) -- tuple pattern assign
          l2 = t[1] -- pattern binding assign
          l3 = t[2] -- pattern binding assign
          block_result = nil
          l4 = { file = l2.file, lo = l0.offset, hi = l2.offset } -- pattern binding assign
          block_result = nil
          l5 = (M["body88"]())((M["body82"]())(l3)) -- pattern binding assign
          block_result = nil
          block_result = (M["body64"]())({ __tuple = true, l5, l4, l2 })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body86"] = function() -- body ike::parse::lexer::is-ident-start
  return function(p0)
    local l0 -- local 'g'
    local l1 -- local 'allowed'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      l1 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_" -- pattern binding assign
      block_result = nil
      block_result = ((M["body68"]())(l0))((M["body57"]())(l1))
    end
    return block_result
  end
end

M["body87"] = function() -- body ike::parse::lexer::is-ident-continue
  return function(p0)
    local l0 -- local 'g'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = ((l0 == "-") or ((l0 == "'") or ((M["body67"]())(l0) or (M["body86"]())(l0))))
    end
    return block_result
  end
end

M["body88"] = function() -- body ident
  return function(p0)
    local l0 -- local 'ident'
    l0 = p0 -- pattern binding assign
    return { tag = "ident", value = l0 }
  end
end

M["body89"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body90"]())(l1))(l0)
  end
  end
  end
end

M["body90"] = function() -- body ike::parse::lexer::one-character-symbol
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    local l2 -- local 'token'
    local l3 -- local 's'
    local l4 -- local 't'
    local l5 -- local 'span'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      l2 = ((M["body91"]())((M["body94"]())(l1)))(M["body95"]()) -- pattern binding assign
      block_result = nil
      local v = l2 -- match target
      local match_result -- match result
      if v.tag == "none" then -- match
        match_result = M["body71"]()
      elseif v.tag == "some" and true and true then -- match
        local t = v.value -- tuple pattern assign
        l3 = t[1] -- pattern binding assign
        l4 = t[2] -- pattern binding assign
        local block_result -- block result
        do -- block
          l5 = { file = l0.file, lo = l0.offset, hi = (l0.offset + 1) } -- pattern binding assign
          block_result = nil
          block_result = (M["body64"]())({ __tuple = true, l4, l5, (M["body78"]())(l0) })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body91"] = function() -- body std::list::find
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'xs'
    local l2 -- local 'xs'
    local l3 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = M["body92"]()
      elseif #v > 0 and true and true then -- match
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        local block_result -- block result
        do -- block
          local v = (l0)(l3) -- match target
          local match_result -- match result
          if true == v then -- match
            match_result = (M["body93"]())(l3)
          elseif false == v then -- match
            match_result = ((M["body91"]())(l0))(l2)
          end
          block_result = match_result
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body92"] = function() -- body none
    return { tag = "none" }
end

M["body93"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body94"] = function() -- body ike::parse::lexer::one-character-symbol::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 's'
    local l1 -- local 'g'
    l1 = p0 -- pattern binding assign
    local t = p1 -- tuple pattern assign
    l0 = t[1] -- pattern binding assign
    return (l0 == l1)
  end
  end
end

M["body95"] = function() -- body ike::parse::lexer::one-character-symbols
    local block_result -- block result
    do -- block
      block_result = { __list = true, { __tuple = true, ";", M["body96"]() }, { __list = true, { __tuple = true, ":", M["body97"]() }, { __list = true, { __tuple = true, ",", M["body98"]() }, { __list = true, { __tuple = true, ".", M["body99"]() }, { __list = true, { __tuple = true, "_", M["body100"]() }, { __list = true, { __tuple = true, "+", M["body101"]() }, { __list = true, { __tuple = true, "-", M["body102"]() }, { __list = true, { __tuple = true, "*", M["body103"]() }, { __list = true, { __tuple = true, "/", M["body104"]() }, { __list = true, { __tuple = true, "\\", M["body105"]() }, { __list = true, { __tuple = true, "%", M["body106"]() }, { __list = true, { __tuple = true, "&", M["body107"]() }, { __list = true, { __tuple = true, "|", M["body108"]() }, { __list = true, { __tuple = true, "^", M["body109"]() }, { __list = true, { __tuple = true, "!", M["body110"]() }, { __list = true, { __tuple = true, "?", M["body111"]() }, { __list = true, { __tuple = true, "'", M["body112"]() }, { __list = true, { __tuple = true, "=", M["body113"]() }, { __list = true, { __tuple = true, "~", M["body114"]() }, { __list = true, { __tuple = true, "<", M["body115"]() }, { __list = true, { __tuple = true, ">", M["body116"]() }, { __list = true, { __tuple = true, "(", M["body117"]() }, { __list = true, { __tuple = true, ")", M["body55"]() }, { __list = true, { __tuple = true, "{", M["body118"]() }, { __list = true, { __tuple = true, "}", M["body119"]() }, { __list = true, { __tuple = true, "[", M["body120"]() }, { __list = true, { __tuple = true, "]", M["body121"]() }, { __list = true } } } } } } } } } } } } } } } } } } } } } } } } } } } }
    end
    return block_result
end

M["body96"] = function() -- body semi
    return { tag = "semi" }
end

M["body97"] = function() -- body colon
    return { tag = "colon" }
end

M["body98"] = function() -- body comma
    return { tag = "comma" }
end

M["body99"] = function() -- body dot
    return { tag = "dot" }
end

M["body100"] = function() -- body under
    return { tag = "under" }
end

M["body101"] = function() -- body plus
    return { tag = "plus" }
end

M["body102"] = function() -- body minus
    return { tag = "minus" }
end

M["body103"] = function() -- body star
    return { tag = "star" }
end

M["body104"] = function() -- body slash
    return { tag = "slash" }
end

M["body105"] = function() -- body backslash
    return { tag = "backslash" }
end

M["body106"] = function() -- body percent
    return { tag = "percent" }
end

M["body107"] = function() -- body amp
    return { tag = "amp" }
end

M["body108"] = function() -- body pipe
    return { tag = "pipe" }
end

M["body109"] = function() -- body caret
    return { tag = "caret" }
end

M["body110"] = function() -- body bang
    return { tag = "bang" }
end

M["body111"] = function() -- body question
    return { tag = "question" }
end

M["body112"] = function() -- body quote
    return { tag = "quote" }
end

M["body113"] = function() -- body eq
    return { tag = "eq" }
end

M["body114"] = function() -- body tilde
    return { tag = "tilde" }
end

M["body115"] = function() -- body lt
    return { tag = "lt" }
end

M["body116"] = function() -- body gt
    return { tag = "gt" }
end

M["body117"] = function() -- body lparen
    return { tag = "lparen" }
end

M["body118"] = function() -- body lbrace
    return { tag = "lbrace" }
end

M["body119"] = function() -- body rbrace
    return { tag = "rbrace" }
end

M["body120"] = function() -- body lbracket
    return { tag = "lbracket" }
end

M["body121"] = function() -- body rbracket
    return { tag = "rbracket" }
end

M["body122"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body123"]())(l1))(l0)
  end
  end
  end
end

M["body123"] = function() -- body ike::parse::lexer::two-character-symbol
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    local l2 -- local 'g2'
    local l3 -- local 'g1'
    local l4 -- local 'symbol'
    local l5 -- local 'token'
    local l6 -- local 's'
    local l7 -- local 't'
    local l8 -- local 'span'
    local l9 -- local 'l'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0.graphs -- match target
      local match_result -- match result
      if #v > 0 and true and #(v)[2] > 0 and true and true then -- match
        l3 = (v)[1] -- pattern binding assign
        l2 = ((v)[2])[1] -- pattern binding assign
        local block_result -- block result
        do -- block
          l4 = ((M["body6"]())(l3))(l2) -- pattern binding assign
          block_result = nil
          l5 = ((M["body91"]())((M["body124"]())(l4)))(M["body125"]()) -- pattern binding assign
          block_result = nil
          local v = l5 -- match target
          local match_result -- match result
          if v.tag == "none" then -- match
            match_result = M["body71"]()
          elseif v.tag == "some" and true and true then -- match
            local t = v.value -- tuple pattern assign
            l6 = t[1] -- pattern binding assign
            l7 = t[2] -- pattern binding assign
            local block_result -- block result
            do -- block
              l8 = { file = l0.file, lo = l0.offset, hi = (l0.offset + 2) } -- pattern binding assign
              block_result = nil
              l9 = (M["body78"]())((M["body78"]())(l0)) -- pattern binding assign
              block_result = nil
              block_result = (M["body64"]())({ __tuple = true, l7, l8, l9 })
            end
            match_result = block_result
          end
          block_result = match_result
        end
        match_result = block_result
      elseif true then -- match
        match_result = M["body71"]()
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body124"] = function() -- body ike::parse::lexer::two-character-symbol::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 's'
    local l1 -- local 'symbol'
    l1 = p0 -- pattern binding assign
    local t = p1 -- tuple pattern assign
    l0 = t[1] -- pattern binding assign
    return (l0 == l1)
  end
  end
end

M["body125"] = function() -- body ike::parse::lexer::two-character-symbols
    local block_result -- block result
    do -- block
      block_result = { __list = true, { __tuple = true, "..", M["body126"]() }, { __list = true, { __tuple = true, "->", M["body127"]() }, { __list = true, { __tuple = true, "<-", M["body128"]() }, { __list = true, { __tuple = true, "::", M["body129"]() }, { __list = true, { __tuple = true, "&&", M["body130"]() }, { __list = true, { __tuple = true, "||", M["body131"]() }, { __list = true, { __tuple = true, "==", M["body132"]() }, { __list = true, { __tuple = true, "!=", M["body133"]() }, { __list = true, { __tuple = true, "<=", M["body134"]() }, { __list = true, { __tuple = true, ">=", M["body135"]() }, { __list = true, { __tuple = true, "<|", M["body136"]() }, { __list = true, { __tuple = true, "|>", M["body137"]() }, { __list = true } } } } } } } } } } } } }
    end
    return block_result
end

M["body126"] = function() -- body dotdot
    return { tag = "dotdot" }
end

M["body127"] = function() -- body rarrow
    return { tag = "rarrow" }
end

M["body128"] = function() -- body larrow
    return { tag = "larrow" }
end

M["body129"] = function() -- body coloncolon
    return { tag = "coloncolon" }
end

M["body130"] = function() -- body ampamp
    return { tag = "ampamp" }
end

M["body131"] = function() -- body pipepipe
    return { tag = "pipepipe" }
end

M["body132"] = function() -- body eqeq
    return { tag = "eqeq" }
end

M["body133"] = function() -- body noteq
    return { tag = "noteq" }
end

M["body134"] = function() -- body lteq
    return { tag = "lteq" }
end

M["body135"] = function() -- body gteq
    return { tag = "gteq" }
end

M["body136"] = function() -- body ltpipe
    return { tag = "ltpipe" }
end

M["body137"] = function() -- body pipegt
    return { tag = "pipegt" }
end

M["body138"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body139"]())(l1))(l0)
  end
  end
  end
end

M["body139"] = function() -- body ike::parse::lexer::string
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    local l2 -- local 'l'
    local l3 -- local 'rest'
    local l4 -- local 'span'
    local l5 -- local 'token'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (l1 == "\"") -- match target
      local match_result -- match result
      if false == v then -- match
        match_result = M["body71"]()
      elseif true == v then -- match
        local block_result -- block result
        do -- block
          local t = (M["body140"]())((M["body78"]())(l0)) -- tuple pattern assign
          l2 = t[1] -- pattern binding assign
          l3 = t[2] -- pattern binding assign
          block_result = nil
          l4 = { file = l2.file, lo = l0.offset, hi = (l2.offset + 1) } -- pattern binding assign
          block_result = nil
          l5 = (M["body150"]())(l3) -- pattern binding assign
          block_result = nil
          block_result = (M["body64"]())({ __tuple = true, l5, l4, l2 })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body140"] = function() -- body ike::parse::lexer::string-end
  return function(p0)
    local l0 -- local 'lexer'
    local l1 -- local 'escapes'
    local l2 -- local 'g'
    local l3 -- local 'lexer'
    local l4 -- local 'g'
    local l5 -- local 'lexer'
    local l6 -- local 'escape'
    local l7 -- local 'lexer'
    local l8 -- local 'rest'
    local l9 -- local 'lexer'
    local l10 -- local 'lexer'
    local l11 -- local 'rest'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      l1 = { __list = true, { __tuple = true, "\\", "\\" }, { __list = true, { __tuple = true, "n", "\n" }, { __list = true, { __tuple = true, "r", "\r" }, { __list = true, { __tuple = true, "t", "\t" }, { __list = true, { __tuple = true, "\"", "\"" }, { __list = true } } } } } } -- pattern binding assign
      block_result = nil
      local v = (M["body59"]())(l0) -- match target
      local match_result -- match result
      if v.tag == "none" then -- match
        match_result = { __tuple = true, l0, "" }
      elseif v.tag == "some" and true then -- match
        l2 = v.value -- pattern binding assign
        local block_result -- block result
        do -- block
          local v = ((M["body141"]())(l0))("\\") -- match target
          local match_result -- match result
          if true == v then -- match
            local block_result -- block result
            do -- block
              l3 = (M["body78"]())(l0) -- pattern binding assign
              block_result = nil
              l4 = (M["body142"]())((M["body59"]())(l3)) -- pattern binding assign
              block_result = nil
              l5 = (M["body78"]())(l3) -- pattern binding assign
              block_result = nil
              local t = (M["body143"]())(((M["body146"]())((M["body149"]())(l4)))(l1)) -- tuple pattern assign
              l6 = t[2] -- pattern binding assign
              block_result = nil
              local t = (M["body140"]())(l5) -- tuple pattern assign
              l7 = t[1] -- pattern binding assign
              l8 = t[2] -- pattern binding assign
              block_result = nil
              block_result = { __tuple = true, l7, ((M["body6"]())(l6))(l8) }
            end
            match_result = block_result
          elseif false == v then -- match
            local block_result -- block result
            do -- block
              l9 = (M["body78"]())(l0) -- pattern binding assign
              block_result = nil
              local v = (l2 == "\"") -- match target
              local match_result -- match result
              if true == v then -- match
                match_result = { __tuple = true, l9, "" }
              elseif false == v then -- match
                local block_result -- block result
                do -- block
                  local t = (M["body140"]())(l9) -- tuple pattern assign
                  l10 = t[1] -- pattern binding assign
                  l11 = t[2] -- pattern binding assign
                  block_result = nil
                  block_result = { __tuple = true, l10, ((M["body6"]())(l2))(l11) }
                end
                match_result = block_result
              end
              block_result = match_result
            end
            match_result = block_result
          end
          block_result = match_result
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body141"] = function() -- body ike::parse::lexer::is
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    local l2 -- local 'g''
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (M["body59"]())(l0) -- match target
      local match_result -- match result
      if v.tag == "none" then -- match
        match_result = false
      elseif v.tag == "some" and true then -- match
        l2 = v.value -- pattern binding assign
        match_result = (l1 == l2)
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body142"] = function() -- body std::option::assert
  return function(p0)
    local l0 -- local 'opt'
    local l1 -- local 'a'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0 -- match target
      local match_result -- match result
      if v.tag == "some" and true then -- match
        l1 = v.value -- pattern binding assign
        match_result = l1
      elseif v.tag == "none" then -- match
        match_result = (M["body2"]())("option was none")
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body143"] = function() -- body std::option::assert
  return function(p0)
    local l0 -- local 'opt'
    local l1 -- local 'a'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0 -- match target
      local match_result -- match result
      if v.tag == "some" and true then -- match
        l1 = v.value -- pattern binding assign
        match_result = l1
      elseif v.tag == "none" then -- match
        match_result = (M["body144"]())("option was none")
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body144"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = (M["body3"]())("thread main panic: `")
      block_result = (M["body3"]())(l0)
      block_result = (M["body4"]())("`")
      block_result = (M["body145"]())(1)
    end
    return block_result
  end
end

M["body145"] = function() -- extern std::os::exit
    return E["std::os::exit"]
end

M["body146"] = function() -- body std::list::find
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'xs'
    local l2 -- local 'xs'
    local l3 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = M["body147"]()
      elseif #v > 0 and true and true then -- match
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        local block_result -- block result
        do -- block
          local v = (l0)(l3) -- match target
          local match_result -- match result
          if true == v then -- match
            match_result = (M["body148"]())(l3)
          elseif false == v then -- match
            match_result = ((M["body146"]())(l0))(l2)
          end
          block_result = match_result
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body147"] = function() -- body none
    return { tag = "none" }
end

M["body148"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body149"] = function() -- body ike::parse::lexer::string-end::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 'e'
    local l1 -- local 'g'
    l1 = p0 -- pattern binding assign
    local t = p1 -- tuple pattern assign
    l0 = t[1] -- pattern binding assign
    return (l0 == l1)
  end
  end
end

M["body150"] = function() -- body string
  return function(p0)
    local l0 -- local 'string'
    l0 = p0 -- pattern binding assign
    return { tag = "string", value = l0 }
  end
end

M["body151"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body152"]())(l1))(l0)
  end
  end
  end
end

M["body152"] = function() -- body ike::parse::lexer::newline
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    local l2 -- local 'span'
    local l3 -- local 'token'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (l1 == "\n") -- match target
      local match_result -- match result
      if false == v then -- match
        match_result = M["body71"]()
      elseif true == v then -- match
        local block_result -- block result
        do -- block
          l2 = { file = l0.file, lo = l0.offset, hi = (l0.offset + 1) } -- pattern binding assign
          block_result = nil
          l3 = M["body153"]() -- pattern binding assign
          block_result = nil
          block_result = (M["body64"]())({ __tuple = true, l3, l2, (M["body78"]())(l0) })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body153"] = function() -- body newline
    return { tag = "newline" }
end

M["body154"] = function() -- body ike::parse::lexer::whitespace
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    local l2 -- local 'l'
    local l3 -- local 'gs'
    local l4 -- local 'span'
    local l5 -- local 'token'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (M["body155"]())(l1) -- match target
      local match_result -- match result
      if false == v then -- match
        match_result = M["body71"]()
      elseif true == v then -- match
        local block_result -- block result
        do -- block
          local t = ((M["body72"]())((M["body78"]())(l0)))(M["body155"]()) -- tuple pattern assign
          l2 = t[1] -- pattern binding assign
          l3 = t[2] -- pattern binding assign
          block_result = nil
          l4 = { file = l2.file, lo = l0.offset, hi = l2.offset } -- pattern binding assign
          block_result = nil
          l5 = M["body156"]() -- pattern binding assign
          block_result = nil
          block_result = (M["body64"]())({ __tuple = true, l5, l4, l2 })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body155"] = function() -- body ike::parse::lexer::is-whitespace
  return function(p0)
    local l0 -- local 'g'
    l0 = p0 -- pattern binding assign
    return ((l0 == " ") or ((l0 == "\t") or (l0 == "\r")))
  end
end

M["body156"] = function() -- body whitespace
    return { tag = "whitespace" }
end

M["body157"] = function() -- body std::result::map
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'r'
    local l2 -- local 'v'
    local l3 -- local 'e'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if v.tag == "ok" and true then -- match
        l2 = v.value -- pattern binding assign
        match_result = (M["body61"]())((l0)(l2))
      elseif v.tag == "err" and true then -- match
        l3 = v.value -- pattern binding assign
        match_result = (M["body158"]())(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body158"] = function() -- body err
  return function(p0)
    local l0 -- local 'err'
    l0 = p0 -- pattern binding assign
    return { tag = "err", value = l0 }
  end
end

M["body159"] = function() -- body std::list::append
  return function(p0)
  return function(p1)
    local l0 -- local 'xs'
    local l1 -- local 'ys'
    local l2 -- local 'xs'
    local l3 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = l1
      elseif #v > 0 and true and true then -- match
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        match_result = { __list = true, l3, ((M["body159"]())(l2))(l1) }
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body160"] = function() -- body ike::parse::lexer::unexpected-character
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    local l2 -- local 'span'
    local l3 -- local 'message'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      l2 = { file = l0.file, lo = l0.offset, hi = (l0.offset + 1) } -- pattern binding assign
      block_result = nil
      l3 = ((M["body5"]())("`"))(((M["body5"]())(l1))("unexpected character `")) -- pattern binding assign
      block_result = nil
      block_result = (M["body158"]())((((M["body51"]())(l2))("found here"))((M["body53"]())(l3)))
    end
    return block_result
  end
  end
end

M["body161"] = function() -- body std::debug::print
  return function(p0)
    local l0 -- local 'value'
    l0 = p0 -- pattern binding assign
    return (M["body4"]())((M["body162"]())(l0))
  end
end

M["body162"] = function() -- extern std::debug::format
    return E["std::debug::format"]
end

M["body163"] = function() -- body ike::diagnostic::format
  return function(p0)
    local l0 -- local 'diagnostic'
    local l1 -- local 'indent'
    local l2 -- local 'labels'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      l1 = (M["body79"]())((M["body164"]())((((M["body165"]())(0))(M["body31"]()))(((M["body166"]())(M["body167"]()))(l0.labels)))) -- pattern binding assign
      block_result = nil
      l2 = (((M["body172"]())(l0.labels))(l0.color))(l1) -- pattern binding assign
      block_result = nil
      block_result = ((M["body5"]())(l2))(((M["body5"]())("\n"))((M["body186"]())(l0)))
    end
    return block_result
  end
end

M["body164"] = function() -- extern std::debug::format
    return E["std::debug::format"]
end

M["body165"] = function() -- body std::list::foldl
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'acc'
    local l1 -- local 'f'
    local l2 -- local 'xs'
    local l3 -- local 'xs'
    local l4 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l2 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = l0
      elseif #v > 0 and true and true then -- match
        l4 = (v)[1] -- pattern binding assign
        l3 = (v)[2] -- pattern binding assign
        match_result = (((M["body165"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body166"] = function() -- body std::list::map
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'xs'
    local l2 -- local 'xs'
    local l3 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = { __list = true }
      elseif #v > 0 and true and true then -- match
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        match_result = { __list = true, (l0)(l3), ((M["body166"]())(l0))(l2) }
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body167"] = function() -- body ike::diagnostic::format::{lambda}
  return function(p0)
    local l0 -- local 'l'
    l0 = p0 -- pattern binding assign
    return (M["body168"]())(l0.span)
  end
end

M["body168"] = function() -- body ike::span::line
  return function(p0)
    local l0 -- local 's'
    local l1 -- local 'n'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local t = (((M["body169"]())({ __tuple = true, 1, 0 }))((M["body170"]())(l0)))(((M["body171"]())("\n"))(l0.file.content)) -- tuple pattern assign
      l1 = t[1] -- pattern binding assign
      block_result = nil
      block_result = l1
    end
    return block_result
  end
end

M["body169"] = function() -- body std::list::foldl
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'acc'
    local l1 -- local 'f'
    local l2 -- local 'xs'
    local l3 -- local 'xs'
    local l4 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l2 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = l0
      elseif #v > 0 and true and true then -- match
        l4 = (v)[1] -- pattern binding assign
        l3 = (v)[2] -- pattern binding assign
        match_result = (((M["body169"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body170"] = function() -- body ike::span::line::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'n'
    local l1 -- local 'start'
    local l2 -- local 'line'
    local l3 -- local 'end'
    local l4 -- local 's'
    l4 = p0 -- pattern binding assign
    local t = p1 -- tuple pattern assign
    l0 = t[1] -- pattern binding assign
    l1 = t[2] -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result -- block result
    do -- block
      l3 = ((l1 + (M["body79"]())(l2)) + 1) -- pattern binding assign
      block_result = nil
      local v = (l3 >= l4.lo) -- match target
      local match_result -- match result
      if true == v then -- match
        match_result = { __tuple = true, l0, l3 }
      elseif false == v then -- match
        match_result = { __tuple = true, (l0 + 1), l3 }
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body171"] = function() -- extern std::string::split
    return E["std::string::split"]
end

M["body172"] = function() -- body ike::diagnostic::format-labels
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'labels'
    local l1 -- local 'color'
    local l2 -- local 'indent'
    local l3 -- local 'labels'
    local l4 -- local 'label'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = ""
      elseif #v > 0 and true and true then -- match
        l4 = (v)[1] -- pattern binding assign
        l3 = (v)[2] -- pattern binding assign
        local block_result -- block result
        do -- block
          block_result = ((M["body5"]())((((M["body172"]())(l3))(l1))(l2)))((((M["body173"]())(l4))(l1))(l2))
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body173"] = function() -- body ike::diagnostic::format-label
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'label'
    local l1 -- local 'color'
    local l2 -- local 'indent'
    local l3 -- local 'line'
    local l4 -- local 'start'
    local l5 -- local 's'
    local l6 -- local 'column'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result -- block result
    do -- block
      l3 = (M["body168"]())(l0.span) -- pattern binding assign
      block_result = nil
      local t = (M["body174"]())((M["body177"]())(l0.span)) -- tuple pattern assign
      l4 = t[1] -- pattern binding assign
      l5 = t[2] -- pattern binding assign
      block_result = nil
      l6 = ((l0.span.lo - l4) + 1) -- pattern binding assign
      block_result = nil
      block_result = ((M["body5"]())("\n"))(((M["body5"]())(((M["body182"]())(l1))(((M["body183"]())(""))(l0.message))))(((M["body5"]())(" "))(((M["body5"]())(((M["body182"]())(l1))(((M["body184"]())((l0.span.hi - l0.span.lo)))("^"))))(((M["body5"]())(((M["body184"]())(l6))(" ")))(((M["body5"]())(((M["body182"]())(M["body185"]()))("|")))(((M["body5"]())(((M["body184"]())((l2 + 1)))(" ")))(((M["body5"]())("\n"))(((M["body5"]())(l5))(((M["body5"]())(" "))(((M["body5"]())(((M["body182"]())(M["body185"]()))("|")))(((M["body5"]())(" "))(((M["body5"]())(((M["body182"]())(M["body185"]()))((M["body164"]())(l3))))(((M["body5"]())(((M["body182"]())(M["body185"]()))("|\n")))(((M["body5"]())(((M["body184"]())((l2 + 1)))(" ")))(((M["body5"]())("\n"))(((M["body5"]())((M["body164"]())(l6)))(((M["body5"]())(":"))(((M["body5"]())((M["body164"]())(l3)))(((M["body5"]())(":"))(((M["body5"]())(l0.span.file.path))(((M["body5"]())(" "))(((M["body5"]())(((M["body182"]())(M["body185"]()))("-->")))(((M["body184"]())(l2))(" "))))))))))))))))))))))))
    end
    return block_result
  end
  end
  end
end

M["body174"] = function() -- body std::option::assert
  return function(p0)
    local l0 -- local 'opt'
    local l1 -- local 'a'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0 -- match target
      local match_result -- match result
      if v.tag == "some" and true then -- match
        l1 = v.value -- pattern binding assign
        match_result = l1
      elseif v.tag == "none" then -- match
        match_result = (M["body175"]())("option was none")
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body175"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = (M["body3"]())("thread main panic: `")
      block_result = (M["body3"]())(l0)
      block_result = (M["body4"]())("`")
      block_result = (M["body176"]())(1)
    end
    return block_result
  end
end

M["body176"] = function() -- extern std::os::exit
    return E["std::os::exit"]
end

M["body177"] = function() -- body ike::span::column
  return function(p0)
    local l0 -- local 's'
    local l1 -- local 'n'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local t = (((M["body178"]())({ __tuple = true, M["body179"](), 0 }))((M["body180"]())(l0)))(((M["body171"]())("\n"))(l0.file.content)) -- tuple pattern assign
      l1 = t[1] -- pattern binding assign
      block_result = nil
      block_result = l1
    end
    return block_result
  end
end

M["body178"] = function() -- body std::list::foldl
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'acc'
    local l1 -- local 'f'
    local l2 -- local 'xs'
    local l3 -- local 'xs'
    local l4 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l2 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = l0
      elseif #v > 0 and true and true then -- match
        l4 = (v)[1] -- pattern binding assign
        l3 = (v)[2] -- pattern binding assign
        match_result = (((M["body178"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body179"] = function() -- body none
    return { tag = "none" }
end

M["body180"] = function() -- body ike::span::column::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'n'
    local l1 -- local 'start'
    local l2 -- local 'line'
    local l3 -- local 'end'
    local l4 -- local 's'
    l4 = p0 -- pattern binding assign
    local t = p1 -- tuple pattern assign
    l0 = t[1] -- pattern binding assign
    l1 = t[2] -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result -- block result
    do -- block
      l3 = ((l1 + (M["body79"]())(l2)) + 1) -- pattern binding assign
      block_result = nil
      local v = ((l4.lo >= l1) and (l4.lo < l3)) -- match target
      local match_result -- match result
      if true == v then -- match
        match_result = { __tuple = true, (M["body181"]())({ __tuple = true, l1, l2 }), l3 }
      elseif false == v then -- match
        match_result = { __tuple = true, l0, l3 }
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body181"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body182"] = function() -- body ike::colorize
  return function(p0)
  return function(p1)
    local l0 -- local 'color'
    local l1 -- local 'message'
    local l2 -- local 'prefix'
    local l3 -- local 'reset'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0 -- match target
      local match_result -- match result
      if v.tag == "red" then -- match
        match_result = "\x1b[31m"
      elseif v.tag == "green" then -- match
        match_result = "\x1b[32m"
      elseif v.tag == "yellow" then -- match
        match_result = "\x1b[33m"
      elseif v.tag == "blue" then -- match
        match_result = "\x1b[34m"
      elseif v.tag == "magenta" then -- match
        match_result = "\x1b[35m"
      elseif v.tag == "cyan" then -- match
        match_result = "\x1b[36m"
      elseif v.tag == "white" then -- match
        match_result = "\x1b[37m"
      end
      l2 = match_result -- pattern binding assign
      block_result = nil
      l3 = "\x1b[0m" -- pattern binding assign
      block_result = nil
      block_result = ((M["body5"]())(l3))(((M["body6"]())(l2))(l1))
    end
    return block_result
  end
  end
end

M["body183"] = function() -- body std::option::some-or
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
    local l1 -- local 'opt'
    local l2 -- local 'a'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l1 -- match target
      local match_result -- match result
      if v.tag == "some" and true then -- match
        l2 = v.value -- pattern binding assign
        match_result = l2
      elseif v.tag == "none" then -- match
        match_result = l0
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body184"] = function() -- body std::string::repeat
  return function(p0)
  return function(p1)
    local l0 -- local 'n'
    local l1 -- local 's'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (l0 <= 1) -- match target
      local match_result -- match result
      if true == v then -- match
        match_result = l1
      elseif false == v then -- match
        match_result = ((M["body5"]())(l1))(((M["body184"]())((l0 - 1)))(l1))
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body185"] = function() -- body blue
    return { tag = "blue" }
end

M["body186"] = function() -- body ike::diagnostic::format-header
  return function(p0)
    local l0 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = ((M["body5"]())((M["body187"]())(l0.message)))(((M["body5"]())(" "))(((M["body5"]())((M["body187"]())(":")))((M["body187"]())(((M["body182"]())(l0.color))(l0.level)))))
    end
    return block_result
  end
end

M["body187"] = function() -- body ike::bold
  return function(p0)
    local l0 -- local 'message'
    local l1 -- local 'prefix'
    local l2 -- local 'reset'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      l1 = "\x1b[1m" -- pattern binding assign
      block_result = nil
      l2 = "\x1b[0m" -- pattern binding assign
      block_result = nil
      block_result = ((M["body5"]())(l2))(((M["body6"]())(l1))(l0))
    end
    return block_result
  end
end

M["body0"]()