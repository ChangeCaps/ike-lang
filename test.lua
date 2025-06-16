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
    local pattern = "([^" .. sep .. "]+)"

    for part in string.gmatch(str, pattern) do
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
    local l1 -- local 'tokens'
    local l2 -- local 'tokens'
    local l3 -- local 'e'
    local block_result -- block result
    do -- block
      l0 = { path = "test.ike", content = (M["body1"]())((M["body9"]())("ike/parse/token.ike")) } -- pattern binding assign
      block_result = nil
      local v = (M["body10"]())(l0) -- match target
      local match_result -- match result
      if v.tag == "ok" and true then -- match
        l1 = v.value -- pattern binding assign
        local block_result -- block result
        do -- block
          local t = (M["body110"]())(l1) -- tuple pattern assign
          l2 = t[1] -- pattern binding assign
          block_result = nil
          block_result = (M["body111"]())(l2)
        end
        match_result = block_result
      elseif v.tag == "err" and true then -- match
        l3 = v.value -- pattern binding assign
        local block_result -- block result
        do -- block
          block_result = (M["body3"]())((M["body113"]())(l3))
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
      block_result = (M["body3"]())(l0)
      block_result = (M["body7"]())(1)
    end
    return block_result
  end
end

M["body3"] = function() -- body std::io::println
  return function(p0)
    local l0 -- local 's'
    l0 = p0 -- pattern binding assign
    return (M["body4"]())(((M["body5"]())("\n"))(l0))
  end
end

M["body4"] = function() -- extern std::io::print
    return E["std::io::print"]
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

M["body10"] = function() -- body ike::parse::tokenize
  return function(p0)
    local l0 -- local 'file'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      l1 = { file = l0, graphs = (M["body11"]())(l0.content), offset = 0 } -- pattern binding assign
      block_result = nil
      block_result = (M["body12"]())(l1)
    end
    return block_result
  end
end

M["body11"] = function() -- extern std::string::graphemes
    return E["std::string::graphemes"]
end

M["body12"] = function() -- body ike::parse::lexer::all
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
      local v = (M["body13"]())(l0) -- match target
      local match_result -- match result
      if v.tag == "none" then -- match
        match_result = (M["body16"]())({ __list = true })
      elseif v.tag == "some" and true then -- match
        l1 = v.value -- pattern binding assign
        local block_result -- block result
        do -- block
          l2 = ((M["body17"]())(((M["body19"]())(l0))(l1)))(((M["body17"]())(((M["body38"]())(l0))(l1)))(((M["body17"]())(((M["body43"]())(l0))(l1)))(((M["body17"]())(((M["body77"]())(l0))(l1)))(((M["body17"]())(((M["body93"]())(l0))(l1)))(((M["body17"]())(((M["body97"]())(l0))(l1)))(((M["body100"]())(l0))(l1))))))) -- pattern binding assign
          block_result = nil
          local v = l2 -- match target
          local match_result -- match result
          if v.tag == "some" and true and true and true then -- match
            local t = v.value -- tuple pattern assign
            l3 = t[1] -- pattern binding assign
            l4 = t[2] -- pattern binding assign
            l5 = t[3] -- pattern binding assign
            match_result = ((M["body103"]())((M["body105"]())({ __list = true, { __tuple = true, l3, l4 }, { __list = true } })))((M["body12"]())(l5))
          elseif v.tag == "none" then -- match
            match_result = ((M["body106"]())(l0))(l1)
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

M["body13"] = function() -- body ike::parse::lexer::peek
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
        match_result = (M["body14"]())(l1)
      elseif #v == 0 then -- match
        match_result = M["body15"]()
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body14"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body15"] = function() -- body none
    return { tag = "none" }
end

M["body16"] = function() -- body ok
  return function(p0)
    local l0 -- local 'ok'
    l0 = p0 -- pattern binding assign
    return { tag = "ok", value = l0 }
  end
end

M["body17"] = function() -- body std::option::or-else
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
        match_result = (M["body18"]())(l2)
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

M["body18"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body19"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body20"]())(l1))(l0)
  end
  end
  end
end

M["body20"] = function() -- body ike::parse::lexer::number
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
      local v = (M["body21"]())(l1) -- match target
      local match_result -- match result
      if false == v then -- match
        match_result = M["body25"]()
      elseif true == v then -- match
        local block_result -- block result
        do -- block
          local t = ((M["body26"]())((M["body32"]())(l0)))(M["body21"]()) -- tuple pattern assign
          l2 = t[1] -- pattern binding assign
          l3 = t[2] -- pattern binding assign
          block_result = nil
          l4 = { file = l2.file, lo = l0.offset, hi = l2.offset } -- pattern binding assign
          block_result = nil
          l5 = (M["body35"]())((M["body36"]())(l3)) -- pattern binding assign
          block_result = nil
          block_result = (M["body18"]())({ __tuple = true, l5, l4, l2 })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body21"] = function() -- body ike::parse::lexer::is-digit
  return function(p0)
    local l0 -- local 'g'
    local l1 -- local 'allowed'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      l1 = "0123456789" -- pattern binding assign
      block_result = nil
      block_result = ((M["body22"]())(l0))((M["body11"]())(l1))
    end
    return block_result
  end
end

M["body22"] = function() -- body std::list::contains
  return function(p0)
    local l0 -- local 'x'
    l0 = p0 -- pattern binding assign
    return (M["body23"]())((M["body24"]())(l0))
  end
end

M["body23"] = function() -- body std::list::any
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
        match_result = ((l0)(l3) or ((M["body23"]())(l0))(l2))
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body24"] = function() -- body std::list::contains::{lambda}
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

M["body25"] = function() -- body none
    return { tag = "none" }
end

M["body26"] = function() -- body ike::parse::lexer::advance-while
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'f'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = ((M["body27"]())({ __tuple = true, l0, { __list = true } }))(((M["body28"]())(((M["body31"]())(l0))(l1)))((M["body13"]())(l0)))
    end
    return block_result
  end
  end
end

M["body27"] = function() -- body std::option::some-or
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

M["body28"] = function() -- body std::option::map
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
        match_result = (M["body29"]())((l0)(l2))
      elseif v.tag == "none" then -- match
        match_result = M["body30"]()
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body29"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body30"] = function() -- body none
    return { tag = "none" }
end

M["body31"] = function() -- body ike::parse::lexer::advance-while::{lambda}
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
          local t = ((M["body26"]())((M["body32"]())(l2)))(l1) -- tuple pattern assign
          l3 = t[1] -- pattern binding assign
          l4 = t[2] -- pattern binding assign
          block_result = nil
          block_result = { __tuple = true, l3, ((M["body34"]())({ __list = true, l0, { __list = true } }))(l4) }
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

M["body32"] = function() -- body ike::parse::lexer::advance
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
          block_result = { file = l0.file, graphs = l1, offset = (l0.offset + (M["body33"]())(l2)) }
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body33"] = function() -- extern std::string::length
    return E["std::string::length"]
end

M["body34"] = function() -- body std::list::append
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
        match_result = { __list = true, l3, ((M["body34"]())(l2))(l1) }
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body35"] = function() -- body number
  return function(p0)
    local l0 -- local 'number'
    l0 = p0 -- pattern binding assign
    return { tag = "number", value = l0 }
  end
end

M["body36"] = function() -- body std::string::join
  return function(p0)
    local l0 -- local 'xs'
    l0 = p0 -- pattern binding assign
    return (((M["body37"]())(""))(M["body6"]()))(l0)
  end
end

M["body37"] = function() -- body std::list::foldl
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
        match_result = (((M["body37"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body38"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body39"]())(l1))(l0)
  end
  end
  end
end

M["body39"] = function() -- body ike::parse::lexer::ident
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
      local v = (M["body40"]())(l1) -- match target
      local match_result -- match result
      if false == v then -- match
        match_result = M["body25"]()
      elseif true == v then -- match
        local block_result -- block result
        do -- block
          local t = ((M["body26"]())(l0))(M["body41"]()) -- tuple pattern assign
          l2 = t[1] -- pattern binding assign
          l3 = t[2] -- pattern binding assign
          block_result = nil
          l4 = { file = l2.file, lo = l0.offset, hi = l2.offset } -- pattern binding assign
          block_result = nil
          l5 = (M["body42"]())((M["body36"]())(l3)) -- pattern binding assign
          block_result = nil
          block_result = (M["body18"]())({ __tuple = true, l5, l4, l2 })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body40"] = function() -- body ike::parse::lexer::is-ident-start
  return function(p0)
    local l0 -- local 'g'
    local l1 -- local 'allowed'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      l1 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_" -- pattern binding assign
      block_result = nil
      block_result = ((M["body22"]())(l0))((M["body11"]())(l1))
    end
    return block_result
  end
end

M["body41"] = function() -- body ike::parse::lexer::is-ident-continue
  return function(p0)
    local l0 -- local 'g'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = ((l0 == "-") or ((l0 == "'") or ((M["body21"]())(l0) or (M["body40"]())(l0))))
    end
    return block_result
  end
end

M["body42"] = function() -- body ident
  return function(p0)
    local l0 -- local 'ident'
    l0 = p0 -- pattern binding assign
    return { tag = "ident", value = l0 }
  end
end

M["body43"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body44"]())(l1))(l0)
  end
  end
  end
end

M["body44"] = function() -- body ike::parse::lexer::one-character-symbol
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
      l2 = ((M["body45"]())((M["body48"]())(l1)))(M["body49"]()) -- pattern binding assign
      block_result = nil
      local v = l2 -- match target
      local match_result -- match result
      if v.tag == "none" then -- match
        match_result = M["body25"]()
      elseif v.tag == "some" and true and true then -- match
        local t = v.value -- tuple pattern assign
        l3 = t[1] -- pattern binding assign
        l4 = t[2] -- pattern binding assign
        local block_result -- block result
        do -- block
          l5 = { file = l0.file, lo = l0.offset, hi = (l0.offset + 1) } -- pattern binding assign
          block_result = nil
          block_result = (M["body18"]())({ __tuple = true, l4, l5, (M["body32"]())(l0) })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body45"] = function() -- body std::list::find
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
        match_result = M["body46"]()
      elseif #v > 0 and true and true then -- match
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        local block_result -- block result
        do -- block
          local v = (l0)(l3) -- match target
          local match_result -- match result
          if true == v then -- match
            match_result = (M["body47"]())(l3)
          elseif false == v then -- match
            match_result = ((M["body45"]())(l0))(l2)
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

M["body46"] = function() -- body none
    return { tag = "none" }
end

M["body47"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body48"] = function() -- body ike::parse::lexer::one-character-symbol::{lambda}
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

M["body49"] = function() -- body ike::parse::lexer::one-character-symbols
    local block_result -- block result
    do -- block
      block_result = { __list = true, { __tuple = true, ";", M["body50"]() }, { __list = true, { __tuple = true, ":", M["body51"]() }, { __list = true, { __tuple = true, ",", M["body52"]() }, { __list = true, { __tuple = true, ".", M["body53"]() }, { __list = true, { __tuple = true, "_", M["body54"]() }, { __list = true, { __tuple = true, "+", M["body55"]() }, { __list = true, { __tuple = true, "-", M["body56"]() }, { __list = true, { __tuple = true, "*", M["body57"]() }, { __list = true, { __tuple = true, "/", M["body58"]() }, { __list = true, { __tuple = true, "\\", M["body59"]() }, { __list = true, { __tuple = true, "%", M["body60"]() }, { __list = true, { __tuple = true, "&", M["body61"]() }, { __list = true, { __tuple = true, "|", M["body62"]() }, { __list = true, { __tuple = true, "^", M["body63"]() }, { __list = true, { __tuple = true, "!", M["body64"]() }, { __list = true, { __tuple = true, "?", M["body65"]() }, { __list = true, { __tuple = true, "'", M["body66"]() }, { __list = true, { __tuple = true, "=", M["body67"]() }, { __list = true, { __tuple = true, "~", M["body68"]() }, { __list = true, { __tuple = true, "<", M["body69"]() }, { __list = true, { __tuple = true, ">", M["body70"]() }, { __list = true, { __tuple = true, "(", M["body71"]() }, { __list = true, { __tuple = true, ")", M["body72"]() }, { __list = true, { __tuple = true, "{", M["body73"]() }, { __list = true, { __tuple = true, "}", M["body74"]() }, { __list = true, { __tuple = true, "[", M["body75"]() }, { __list = true, { __tuple = true, "]", M["body76"]() }, { __list = true } } } } } } } } } } } } } } } } } } } } } } } } } } } }
    end
    return block_result
end

M["body50"] = function() -- body semi
    return { tag = "semi" }
end

M["body51"] = function() -- body colon
    return { tag = "colon" }
end

M["body52"] = function() -- body comma
    return { tag = "comma" }
end

M["body53"] = function() -- body dot
    return { tag = "dot" }
end

M["body54"] = function() -- body under
    return { tag = "under" }
end

M["body55"] = function() -- body plus
    return { tag = "plus" }
end

M["body56"] = function() -- body minus
    return { tag = "minus" }
end

M["body57"] = function() -- body star
    return { tag = "star" }
end

M["body58"] = function() -- body slash
    return { tag = "slash" }
end

M["body59"] = function() -- body backslash
    return { tag = "backslash" }
end

M["body60"] = function() -- body percent
    return { tag = "percent" }
end

M["body61"] = function() -- body amp
    return { tag = "amp" }
end

M["body62"] = function() -- body pipe
    return { tag = "pipe" }
end

M["body63"] = function() -- body caret
    return { tag = "caret" }
end

M["body64"] = function() -- body bang
    return { tag = "bang" }
end

M["body65"] = function() -- body question
    return { tag = "question" }
end

M["body66"] = function() -- body quote
    return { tag = "quote" }
end

M["body67"] = function() -- body eq
    return { tag = "eq" }
end

M["body68"] = function() -- body tilde
    return { tag = "tilde" }
end

M["body69"] = function() -- body lt
    return { tag = "lt" }
end

M["body70"] = function() -- body gt
    return { tag = "gt" }
end

M["body71"] = function() -- body lparen
    return { tag = "lparen" }
end

M["body72"] = function() -- body rparen
    return { tag = "rparen" }
end

M["body73"] = function() -- body lbrace
    return { tag = "lbrace" }
end

M["body74"] = function() -- body rbrace
    return { tag = "rbrace" }
end

M["body75"] = function() -- body lbracket
    return { tag = "lbracket" }
end

M["body76"] = function() -- body rbracket
    return { tag = "rbracket" }
end

M["body77"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body78"]())(l1))(l0)
  end
  end
  end
end

M["body78"] = function() -- body ike::parse::lexer::two-character-symbol
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
          l5 = ((M["body45"]())((M["body79"]())(l4)))(M["body80"]()) -- pattern binding assign
          block_result = nil
          local v = l5 -- match target
          local match_result -- match result
          if v.tag == "none" then -- match
            match_result = M["body25"]()
          elseif v.tag == "some" and true and true then -- match
            local t = v.value -- tuple pattern assign
            l6 = t[1] -- pattern binding assign
            l7 = t[2] -- pattern binding assign
            local block_result -- block result
            do -- block
              l8 = { file = l0.file, lo = l0.offset, hi = (l0.offset + 2) } -- pattern binding assign
              block_result = nil
              l9 = (M["body32"]())((M["body32"]())(l0)) -- pattern binding assign
              block_result = nil
              block_result = (M["body18"]())({ __tuple = true, l7, l8, l9 })
            end
            match_result = block_result
          end
          block_result = match_result
        end
        match_result = block_result
      elseif true then -- match
        match_result = M["body25"]()
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body79"] = function() -- body ike::parse::lexer::two-character-symbol::{lambda}
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

M["body80"] = function() -- body ike::parse::lexer::two-character-symbols
    local block_result -- block result
    do -- block
      block_result = { __list = true, { __tuple = true, "..", M["body81"]() }, { __list = true, { __tuple = true, "->", M["body82"]() }, { __list = true, { __tuple = true, "<-", M["body83"]() }, { __list = true, { __tuple = true, "::", M["body84"]() }, { __list = true, { __tuple = true, "&&", M["body85"]() }, { __list = true, { __tuple = true, "||", M["body86"]() }, { __list = true, { __tuple = true, "==", M["body87"]() }, { __list = true, { __tuple = true, "!=", M["body88"]() }, { __list = true, { __tuple = true, "<=", M["body89"]() }, { __list = true, { __tuple = true, ">=", M["body90"]() }, { __list = true, { __tuple = true, "<|", M["body91"]() }, { __list = true, { __tuple = true, "|>", M["body92"]() }, { __list = true } } } } } } } } } } } } }
    end
    return block_result
end

M["body81"] = function() -- body dotdot
    return { tag = "dotdot" }
end

M["body82"] = function() -- body rarrow
    return { tag = "rarrow" }
end

M["body83"] = function() -- body larrow
    return { tag = "larrow" }
end

M["body84"] = function() -- body coloncolon
    return { tag = "coloncolon" }
end

M["body85"] = function() -- body ampamp
    return { tag = "ampamp" }
end

M["body86"] = function() -- body pipepipe
    return { tag = "pipepipe" }
end

M["body87"] = function() -- body eqeq
    return { tag = "eqeq" }
end

M["body88"] = function() -- body noteq
    return { tag = "noteq" }
end

M["body89"] = function() -- body lteq
    return { tag = "lteq" }
end

M["body90"] = function() -- body gteq
    return { tag = "gteq" }
end

M["body91"] = function() -- body ltpipe
    return { tag = "ltpipe" }
end

M["body92"] = function() -- body pipegt
    return { tag = "pipegt" }
end

M["body93"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body94"]())(l1))(l0)
  end
  end
  end
end

M["body94"] = function() -- body ike::parse::lexer::string
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    local l2 -- local 'l'
    local l3 -- local 'gs'
    local l4 -- local 'l'
    local l5 -- local 'span'
    local l6 -- local 'token'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = (l1 == "\"") -- match target
      local match_result -- match result
      if false == v then -- match
        match_result = M["body25"]()
      elseif true == v then -- match
        local block_result -- block result
        do -- block
          local t = ((M["body26"]())((M["body32"]())(l0)))(M["body95"]()) -- tuple pattern assign
          l2 = t[1] -- pattern binding assign
          l3 = t[2] -- pattern binding assign
          block_result = nil
          l4 = (M["body32"]())(l2) -- pattern binding assign
          block_result = nil
          l5 = { file = l4.file, lo = l0.offset, hi = (l4.offset + 1) } -- pattern binding assign
          block_result = nil
          l6 = (M["body96"]())((M["body36"]())(l3)) -- pattern binding assign
          block_result = nil
          block_result = (M["body18"]())({ __tuple = true, l6, l5, l4 })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body95"] = function() -- body ike::parse::lexer::string::{lambda}
  return function(p0)
    local l0 -- local 'g'
    l0 = p0 -- pattern binding assign
    return (l0 ~= "\"")
  end
end

M["body96"] = function() -- body string
  return function(p0)
    local l0 -- local 'string'
    l0 = p0 -- pattern binding assign
    return { tag = "string", value = l0 }
  end
end

M["body97"] = function() -- body ike::parse::lexer::all::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'lexer'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return ((M["body98"]())(l1))(l0)
  end
  end
  end
end

M["body98"] = function() -- body ike::parse::lexer::newline
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
        match_result = M["body25"]()
      elseif true == v then -- match
        local block_result -- block result
        do -- block
          l2 = { file = l0.file, lo = l0.offset, hi = (l0.offset + 1) } -- pattern binding assign
          block_result = nil
          l3 = M["body99"]() -- pattern binding assign
          block_result = nil
          block_result = (M["body18"]())({ __tuple = true, l3, l2, (M["body32"]())(l0) })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body99"] = function() -- body newline
    return { tag = "newline" }
end

M["body100"] = function() -- body ike::parse::lexer::whitespace
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
      local v = (M["body101"]())(l1) -- match target
      local match_result -- match result
      if false == v then -- match
        match_result = M["body25"]()
      elseif true == v then -- match
        local block_result -- block result
        do -- block
          local t = ((M["body26"]())((M["body32"]())(l0)))(M["body101"]()) -- tuple pattern assign
          l2 = t[1] -- pattern binding assign
          l3 = t[2] -- pattern binding assign
          block_result = nil
          l4 = { file = l2.file, lo = l0.offset, hi = l2.offset } -- pattern binding assign
          block_result = nil
          l5 = M["body102"]() -- pattern binding assign
          block_result = nil
          block_result = (M["body18"]())({ __tuple = true, l5, l4, l2 })
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body101"] = function() -- body ike::parse::lexer::is-whitespace
  return function(p0)
    local l0 -- local 'g'
    l0 = p0 -- pattern binding assign
    return ((l0 == " ") or ((l0 == "\t") or (l0 == "\r")))
  end
end

M["body102"] = function() -- body whitespace
    return { tag = "whitespace" }
end

M["body103"] = function() -- body std::result::map
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
        match_result = (M["body16"]())((l0)(l2))
      elseif v.tag == "err" and true then -- match
        l3 = v.value -- pattern binding assign
        match_result = (M["body104"]())(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body104"] = function() -- body err
  return function(p0)
    local l0 -- local 'err'
    l0 = p0 -- pattern binding assign
    return { tag = "err", value = l0 }
  end
end

M["body105"] = function() -- body std::list::append
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
        match_result = { __list = true, l3, ((M["body105"]())(l2))(l1) }
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body106"] = function() -- body ike::parse::lexer::unexpected-character
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
      block_result = (M["body104"]())((((M["body107"]())(l2))("found here"))((M["body108"]())(l3)))
    end
    return block_result
  end
  end
end

M["body107"] = function() -- body ike::diagnostic::with-label
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
      l3 = { message = (M["body14"]())(l1), span = l0 } -- pattern binding assign
      block_result = nil
      block_result = { color = l2.color, level = l2.level, message = l2.message, labels = { __list = true, l3, l2.labels } }
    end
    return block_result
  end
  end
  end
end

M["body108"] = function() -- body ike::diagnostic::error
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = { color = M["body109"](), level = "error", message = l0, labels = { __list = true } }
    end
    return block_result
  end
end

M["body109"] = function() -- body red
    return { tag = "red" }
end

M["body110"] = function() -- body std::list::unzip
  return function(p0)
    local l0 -- local 'xs'
    local l1 -- local 'xs'
    local l2 -- local 'x'
    local l3 -- local 'y'
    local l4 -- local 'xs'
    local l5 -- local 'ys'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local v = l0 -- match target
      local match_result -- match result
      if #v == 0 then -- match
        match_result = { __tuple = true, { __list = true }, { __list = true } }
      elseif #v > 0 and true and true and true then -- match
        local t = (v)[1] -- tuple pattern assign
        l2 = t[1] -- pattern binding assign
        l3 = t[2] -- pattern binding assign
        l1 = (v)[2] -- pattern binding assign
        local block_result -- block result
        do -- block
          local t = (M["body110"]())(l1) -- tuple pattern assign
          l4 = t[1] -- pattern binding assign
          l5 = t[2] -- pattern binding assign
          block_result = nil
          block_result = { __tuple = true, { __list = true, l2, l4 }, { __list = true, l3, l5 } }
        end
        match_result = block_result
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body111"] = function() -- body std::debug::print
  return function(p0)
    local l0 -- local 'value'
    l0 = p0 -- pattern binding assign
    return (M["body3"]())((M["body112"]())(l0))
  end
end

M["body112"] = function() -- extern std::debug::format
    return E["std::debug::format"]
end

M["body113"] = function() -- body ike::diagnostic::format
  return function(p0)
    local l0 -- local 'diagnostic'
    local l1 -- local 'indent'
    local l2 -- local 'labels'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      l1 = (M["body33"]())((M["body114"]())((((M["body115"]())(0))(M["body116"]()))(((M["body117"]())(M["body118"]()))(l0.labels)))) -- pattern binding assign
      block_result = nil
      l2 = (((M["body123"]())(l0.labels))(l0.color))(l1) -- pattern binding assign
      block_result = nil
      block_result = ((M["body5"]())(l2))(((M["body5"]())("\n"))((M["body137"]())(l0)))
    end
    return block_result
  end
end

M["body114"] = function() -- extern std::debug::format
    return E["std::debug::format"]
end

M["body115"] = function() -- body std::list::foldl
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
        match_result = (((M["body115"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body116"] = function() -- body std::math::max
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

M["body117"] = function() -- body std::list::map
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
        match_result = { __list = true, (l0)(l3), ((M["body117"]())(l0))(l2) }
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body118"] = function() -- body ike::diagnostic::format::{lambda}
  return function(p0)
    local l0 -- local 'l'
    l0 = p0 -- pattern binding assign
    return (M["body119"]())(l0.span)
  end
end

M["body119"] = function() -- body ike::span::line
  return function(p0)
    local l0 -- local 's'
    local l1 -- local 'n'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local t = (((M["body120"]())({ __tuple = true, 1, 0 }))((M["body121"]())(l0)))(((M["body122"]())("\n"))(l0.file.content)) -- tuple pattern assign
      l1 = t[1] -- pattern binding assign
      block_result = nil
      block_result = l1
    end
    return block_result
  end
end

M["body120"] = function() -- body std::list::foldl
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
        match_result = (((M["body120"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body121"] = function() -- body ike::span::line::{lambda}
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
      l3 = ((l1 + (M["body33"]())(l2)) + 1) -- pattern binding assign
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

M["body122"] = function() -- extern std::string::split
    return E["std::string::split"]
end

M["body123"] = function() -- body ike::diagnostic::format-labels
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
          block_result = ((M["body5"]())((((M["body123"]())(l3))(l1))(l2)))((((M["body124"]())(l4))(l1))(l2))
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

M["body124"] = function() -- body ike::diagnostic::format-label
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
      l3 = (M["body119"]())(l0.span) -- pattern binding assign
      block_result = nil
      local t = (M["body125"]())((M["body128"]())(l0.span)) -- tuple pattern assign
      l4 = t[1] -- pattern binding assign
      l5 = t[2] -- pattern binding assign
      block_result = nil
      l6 = ((l0.span.lo - l4) + 1) -- pattern binding assign
      block_result = nil
      block_result = ((M["body5"]())("\n"))(((M["body5"]())(((M["body133"]())(l1))(((M["body134"]())(""))(l0.message))))(((M["body5"]())(" "))(((M["body5"]())(((M["body133"]())(l1))(((M["body135"]())((l0.span.hi - l0.span.lo)))("^"))))(((M["body5"]())(((M["body135"]())(l6))(" ")))(((M["body5"]())(((M["body133"]())(M["body136"]()))("|")))(((M["body5"]())(((M["body135"]())((l2 + 1)))(" ")))(((M["body5"]())("\n"))(((M["body5"]())(l5))(((M["body5"]())(" "))(((M["body5"]())(((M["body133"]())(M["body136"]()))("|")))(((M["body5"]())(" "))(((M["body5"]())(((M["body133"]())(M["body136"]()))((M["body114"]())(l3))))(((M["body5"]())(((M["body133"]())(M["body136"]()))("|\n")))(((M["body5"]())(((M["body135"]())((l2 + 1)))(" ")))(((M["body5"]())("\n"))(((M["body5"]())((M["body114"]())(l6)))(((M["body5"]())(":"))(((M["body5"]())((M["body114"]())(l3)))(((M["body5"]())(":"))(((M["body5"]())(l0.span.file.path))(((M["body5"]())(" "))(((M["body5"]())(((M["body133"]())(M["body136"]()))("-->")))(((M["body135"]())(l2))(" "))))))))))))))))))))))))
    end
    return block_result
  end
  end
  end
end

M["body125"] = function() -- body std::option::assert
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
        match_result = (M["body126"]())("option was none")
      end
      block_result = match_result
    end
    return block_result
  end
end

M["body126"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = (M["body3"]())(l0)
      block_result = (M["body127"]())(1)
    end
    return block_result
  end
end

M["body127"] = function() -- extern std::os::exit
    return E["std::os::exit"]
end

M["body128"] = function() -- body ike::span::column
  return function(p0)
    local l0 -- local 's'
    local l1 -- local 'n'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      local t = (((M["body129"]())({ __tuple = true, M["body130"](), 0 }))((M["body131"]())(l0)))(((M["body122"]())("\n"))(l0.file.content)) -- tuple pattern assign
      l1 = t[1] -- pattern binding assign
      block_result = nil
      block_result = l1
    end
    return block_result
  end
end

M["body129"] = function() -- body std::list::foldl
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
        match_result = (((M["body129"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result = match_result
    end
    return block_result
  end
  end
  end
end

M["body130"] = function() -- body none
    return { tag = "none" }
end

M["body131"] = function() -- body ike::span::column::{lambda}
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
      l3 = ((l1 + (M["body33"]())(l2)) + 1) -- pattern binding assign
      block_result = nil
      local v = ((l4.lo >= l1) and (l4.lo < l3)) -- match target
      local match_result -- match result
      if true == v then -- match
        match_result = { __tuple = true, (M["body132"]())({ __tuple = true, l1, l2 }), l3 }
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

M["body132"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body133"] = function() -- body ike::colorize
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

M["body134"] = function() -- body std::option::some-or
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

M["body135"] = function() -- body std::string::repeat
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
        match_result = ((M["body5"]())(l1))(((M["body135"]())((l0 - 1)))(l1))
      end
      block_result = match_result
    end
    return block_result
  end
  end
end

M["body136"] = function() -- body blue
    return { tag = "blue" }
end

M["body137"] = function() -- body ike::diagnostic::format-header
  return function(p0)
    local l0 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    local block_result -- block result
    do -- block
      block_result = ((M["body5"]())((M["body138"]())(l0.message)))(((M["body5"]())(" "))(((M["body5"]())((M["body138"]())(":")))((M["body138"]())(((M["body133"]())(l0.color))(l0.level)))))
    end
    return block_result
  end
end

M["body138"] = function() -- body ike::bold
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