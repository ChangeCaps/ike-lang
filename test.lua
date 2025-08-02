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

M["body0"] = function() -- body ike::main
    local l0 -- local 'in'
    local l1 -- local 'out'
    local l2 -- local 'file'
    local l3 -- local 'input'
    local l4 -- local 'result'
    local block_result0 -- block result
    do -- block
      local t1 = M["body1"]() -- tuple pattern assign
      l0 = t1[1] -- pattern binding assign
      l1 = t1[2] -- pattern binding assign
      block_result0 = nil
      block_result0 = (M["body2"]())((M["body3"]())(l1))
      l2 = { ["path"] = "test/parse/expr.ike" } -- pattern binding assign
      block_result0 = nil
      l3 = (M["body12"]())((M["body16"]())("test/parse/expr.ike")) -- pattern binding assign
      block_result0 = nil
      l4 = (((M["body17"]())(l0))(l2))(l3) -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body108"]())(M["body109"]()))(l4)
    end
    return block_result0
end

M["body1"] = function() -- extern std::channel
    return E["std::channel"]()
end

M["body2"] = function() -- extern std::spawn
    return E["std::spawn"]()
end

M["body3"] = function() -- body ike::main::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 'out'
    l0 = p0 -- pattern binding assign
    return (M["body4"]())(l0)
  end
  end
end

M["body4"] = function() -- body ike::emit
  return function(p0)
    local l0 -- local 'out'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body5"]())((M["body11"]())(l0))
      block_result0 = (M["body4"]())(l0)
    end
    return block_result0
  end
end

M["body5"] = function() -- body std::debug::print
  return function(p0)
    local l0 -- local 'value'
    l0 = p0 -- pattern binding assign
    return (M["body6"]())((M["body10"]())(l0))
  end
end

M["body6"] = function() -- body std::io::println
  return function(p0)
    local l0 -- local 's'
    l0 = p0 -- pattern binding assign
    return (M["body7"]())(((M["body8"]())("\n"))(l0))
  end
end

M["body7"] = function() -- extern std::io::print
    return E["std::io::print"]()
end

M["body8"] = function() -- body std::string::append
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
    local l1 -- local 'b'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    return ((M["body9"]())(l1))(l0)
  end
  end
end

M["body9"] = function() -- extern std::string::prepend
    return E["std::string::prepend"]()
end

M["body10"] = function() -- extern std::debug::format
    return E["std::debug::format"]()
end

M["body11"] = function() -- extern std::recv
    return E["std::recv"]()
end

M["body12"] = function() -- body std::result::assert
  return function(p0)
    local l0 -- local 'r'
    local l1 -- local 'v'
    local l2 -- local 'e'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "ok" and true then -- match arm
        l1 = v.value -- pattern binding assign
        match_result1 = l1
      elseif v.tag == "err" and true then -- match arm
        l2 = v.value -- pattern binding assign
        match_result1 = (M["body13"]())((M["body14"]())(l2))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body13"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body7"]())("thread main panic: `")
      block_result0 = (M["body7"]())((M["body14"]())(l0))
      block_result0 = (M["body6"]())("`")
      block_result0 = (M["body15"]())(1)
    end
    return block_result0
  end
end

M["body14"] = function() -- extern std::debug::format
    return E["std::debug::format"]()
end

M["body15"] = function() -- extern std::os::exit
    return E["std::os::exit"]()
end

M["body16"] = function() -- extern std::fs::read
    return E["std::fs::read"]()
end

M["body17"] = function() -- body ike::lex::tokenize
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'emitter'
    local l1 -- local 'file'
    local l2 -- local 'input'
    local l3 -- local 'lexer'
    local l4 -- local 'lexer''
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l3 = { ["emitter"] = l0, ["state"] = M["body18"](), ["tokens"] = { __list = true }, ["file"] = l1, ["offset"] = 0 } -- pattern binding assign
      block_result0 = nil
      l4 = (M["body19"]())((((M["body42"]())(l3))(M["body43"]()))((M["body81"]())(l2))) -- pattern binding assign
      block_result0 = nil
      block_result0 = (M["body29"]())(l4["tokens"])
    end
    return block_result0
  end
  end
  end
end

M["body18"] = function() -- body idle
    return { tag = "idle" }
end

M["body19"] = function() -- body ike::lex::lexer::end
  return function(p0)
    local l0 -- local 'lexer'
    local l1 -- local 's'
    local l2 -- local 's'
    local l3 -- local 's'
    local l4 -- local 'l'
    local l5 -- local 'd'
    local l6 -- local 'l'
    local l7 -- local 'p'
    local l8 -- local 's'
    local l9 -- local 'l'
    local l10 -- local 's'
    local l11 -- local 'span'
    local l12 -- local 'diagnostic'
    local l13 -- local 's'
    local l14 -- local 'lexer''
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0["state"] -- match target
      local match_result1 -- match result
      if v.tag == "idle" then -- match arm
        match_result1 = M["body20"]()
      elseif v.tag == "symbol" and true then -- match arm
        l1 = v.value -- pattern binding assign
        match_result1 = ((M["body21"]())(l1))(1)
      elseif v.tag == "integer" and true then -- match arm
        l2 = v.value -- pattern binding assign
        match_result1 = ((M["body22"]())((M["body24"]())(l2)))((M["body25"]())(l2))
      elseif v.tag == "ident" and true then -- match arm
        l3 = v.value -- pattern binding assign
        match_result1 = ((M["body22"]())((M["body26"]())(l3)))((M["body25"]())(l3))
      elseif v.tag == "whitespace" and true then -- match arm
        l4 = v.value -- pattern binding assign
        match_result1 = ((M["body22"]())(M["body27"]()))(l4)
      elseif v.tag == "group" and true and true then -- match arm
        local t2 = v.value -- tuple pattern assign
        l5 = t2[1] -- pattern binding assign
        l6 = t2[2] -- pattern binding assign
        match_result1 = ((M["body28"]())(l5))(l6)
      elseif v.tag == "string" and true and true and true then -- match arm
        local t3 = v.value -- tuple pattern assign
        l7 = t3[1] -- pattern binding assign
        l8 = t3[2] -- pattern binding assign
        l9 = t3[3] -- pattern binding assign
        local block_result4 -- block result
        do -- block
          local v = l8 -- match target
          local match_result5 -- match result
          if v.tag == "literal" and true then -- match arm
            l10 = v.value -- pattern binding assign
            local block_result6 -- block result
            do -- block
              l11 = { ["file"] = l0["file"], ["start"] = l0["offset"], ["end"] = (l0["offset"] + l9) } -- pattern binding assign
              block_result6 = nil
              l12 = (((M["body32"]())(l11))("found here"))((M["body34"]())("expected end of string")) -- pattern binding assign
              block_result6 = nil
              block_result6 = ((M["body37"]())(l12))(l0["emitter"])
              block_result6 = ((M["body22"]())(M["body38"]()))(((M["body25"]())(l10) + 1))
            end
            match_result5 = block_result6
          elseif v.tag == "escape" and true then -- match arm
            l13 = v.value -- pattern binding assign
            local block_result7 -- block result
            do -- block
              block_result7 = (M["body39"]())("escape")
            end
            match_result5 = block_result7
          elseif v.tag == "format" and true then -- match arm
            l14 = v.value -- pattern binding assign
            local block_result8 -- block result
            do -- block
              block_result8 = (M["body39"]())("format")
            end
            match_result5 = block_result8
          end
          block_result4 = match_result5
        end
        match_result1 = block_result4
      end
      block_result0 = (match_result1)(l0)
    end
    return block_result0
  end
end

M["body20"] = function() -- body ike::lex::lexer::identity
  return function(p0)
    local l0 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    return l0
  end
end

M["body21"] = function() -- body ike::lex::lexer::with-symbol
  return function(p0)
    local l0 -- local 's'
    l0 = p0 -- pattern binding assign
    return (M["body22"]())((M["body23"]())(l0))
  end
end

M["body22"] = function() -- body ike::lex::lexer::with-token
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'token'
    local l1 -- local 'l'
    local l2 -- local 'lexer'
    local l3 -- local 'span'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l3 = { ["file"] = l2["file"], ["start"] = l2["offset"], ["end"] = (l2["offset"] + l1) } -- pattern binding assign
      block_result0 = nil
      block_result0 = { ["emitter"] = l2["emitter"], ["state"] = M["body18"](), ["tokens"] = { __list = true, { __tuple = true, l0, l3 }, l2["tokens"] }, ["file"] = l2["file"], ["offset"] = (l2["offset"] + l1) }
    end
    return block_result0
  end
  end
  end
end

M["body23"] = function() -- body symbol
  return function(p0)
    local l0 -- local 'symbol'
    l0 = p0 -- pattern binding assign
    return { tag = "symbol", value = l0 }
  end
end

M["body24"] = function() -- body integer
  return function(p0)
    local l0 -- local 'integer'
    l0 = p0 -- pattern binding assign
    return { tag = "integer", value = l0 }
  end
end

M["body25"] = function() -- extern std::string::length
    return E["std::string::length"]()
end

M["body26"] = function() -- body ident
  return function(p0)
    local l0 -- local 'ident'
    l0 = p0 -- pattern binding assign
    return { tag = "ident", value = l0 }
  end
end

M["body27"] = function() -- body whitespace
    return { tag = "whitespace" }
end

M["body28"] = function() -- body ike::lex::lexer::end-group
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'delim'
    local l1 -- local 'lexer''
    local l2 -- local 'lexer'
    local l3 -- local 'lexer''
    local l4 -- local 'group'
    local l5 -- local 'len'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l3 = (M["body19"]())(l1) -- pattern binding assign
      block_result0 = nil
      l4 = { ["delimiter"] = l0, ["contents"] = (M["body29"]())(l3["tokens"]) } -- pattern binding assign
      block_result0 = nil
      l5 = (l3["offset"] - l2["offset"]) -- pattern binding assign
      block_result0 = nil
      block_result0 = (((M["body22"]())((M["body31"]())(l4)))(l5))(l2)
    end
    return block_result0
  end
  end
  end
end

M["body29"] = function() -- body std::list::reverse
  return function(p0)
    local l0 -- local 'xs'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body30"]())(l0))({ __list = true })
    end
    return block_result0
  end
end

M["body30"] = function() -- body std::list::reverse'
  return function(p0)
  return function(p1)
    local l0 -- local 'xs'
    local l1 -- local 'ys'
    local l2 -- local 'xs'
    local l3 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = l1
      elseif #v > 0 and true and true then -- match arm
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        match_result1 = ((M["body30"]())(l2))({ __list = true, l3, l1 })
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body31"] = function() -- body group
  return function(p0)
    local l0 -- local 'group'
    l0 = p0 -- pattern binding assign
    return { tag = "group", value = l0 }
  end
end

M["body32"] = function() -- body ike::diagnostic::with-label
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
    local block_result0 -- block result
    do -- block
      l3 = { ["span"] = l0, ["message"] = (M["body33"]())(l1) } -- pattern binding assign
      block_result0 = nil
      block_result0 = { ["level"] = l2["level"], ["message"] = l2["message"], ["labels"] = { __list = true, l3, l2["labels"] } }
    end
    return block_result0
  end
  end
  end
end

M["body33"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body34"] = function() -- body ike::diagnostic::error
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body35"]())(M["body36"]()))(l0)
    end
    return block_result0
  end
end

M["body35"] = function() -- body ike::diagnostic
  return function(p0)
  return function(p1)
    local l0 -- local 'level'
    local l1 -- local 'message'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["level"] = l0, ["message"] = l1, ["labels"] = { __list = true } }
    end
    return block_result0
  end
  end
end

M["body36"] = function() -- body level::error
    return { tag = "level::error" }
end

M["body37"] = function() -- extern std::send
    return E["std::send"]()
end

M["body38"] = function() -- body error
    return { tag = "error" }
end

M["body39"] = function() -- body std::todo
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    return (M["body40"]())(l0)
  end
end

M["body40"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body7"]())("thread main panic: `")
      block_result0 = (M["body7"]())((M["body14"]())(l0))
      block_result0 = (M["body6"]())("`")
      block_result0 = (M["body41"]())(1)
    end
    return block_result0
  end
end

M["body41"] = function() -- extern std::os::exit
    return E["std::os::exit"]()
end

M["body42"] = function() -- body std::list::foldl
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
    local block_result0 -- block result
    do -- block
      local v = l2 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = l0
      elseif #v > 0 and true and true then -- match arm
        l4 = (v)[1] -- pattern binding assign
        l3 = (v)[2] -- pattern binding assign
        match_result1 = (((M["body42"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body43"] = function() -- body ike::lex::lexer::next
  return function(p0)
  return function(p1)
    local l0 -- local 'lexer'
    local l1 -- local 'c'
    local l2 -- local 'span'
    local l3 -- local 'diagnostic'
    local l4 -- local 's'
    local l5 -- local 's'
    local l6 -- local 's'
    local l7 -- local 'l'
    local l8 -- local 'delim'
    local l9 -- local 'lexer''
    local l10 -- local 'lexer''
    local l11 -- local 'parts'
    local l12 -- local 'state'
    local l13 -- local 'len'
    local l14 -- local 's'
    local l15 -- local 'state'
    local l16 -- local 'lexer''
    local l17 -- local 'parts'
    local l18 -- local 'state'
    local l19 -- local 'state'
    local l20 -- local 's'
    local l21 -- local 'span'
    local l22 -- local 'diagnostic'
    local l23 -- local 'state'
    local l24 -- local 'lexer''
    local l25 -- local 'state'
    local l26 -- local 'lexer''
    local l27 -- local 'parts'
    local l28 -- local 'state'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0["state"] -- match target
      local match_result1 -- match result
      if v.tag == "idle" then -- match arm
        local block_result2 -- block result
        do -- block
          local v = l1 -- match target
          local match_result3 -- match result
          if (";" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body47"]())
          elseif (":" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body48"]())
          elseif ("," == v) then -- match arm
            match_result3 = (M["body44"]())(M["body49"]())
          elseif ("." == v) then -- match arm
            match_result3 = (M["body44"]())(M["body50"]())
          elseif ("#" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body51"]())
          elseif ("_" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body52"]())
          elseif ("+" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body53"]())
          elseif ("-" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body54"]())
          elseif ("*" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body55"]())
          elseif ("\\" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body56"]())
          elseif ("&" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body57"]())
          elseif ("|" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body58"]())
          elseif ("^" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body59"]())
          elseif ("!" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body60"]())
          elseif ("?" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body61"]())
          elseif ("'" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body62"]())
          elseif ("=" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body63"]())
          elseif ("~" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body64"]())
          elseif ("<" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body65"]())
          elseif (">" == v) then -- match arm
            match_result3 = (M["body44"]())(M["body66"]())
          elseif ("(" == v) then -- match arm
            match_result3 = (M["body67"]())(M["body69"]())
          elseif ("[" == v) then -- match arm
            match_result3 = (M["body67"]())(M["body70"]())
          elseif ("{" == v) then -- match arm
            match_result3 = (M["body67"]())(M["body71"]())
          elseif ("0" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body72"]())(l1))
          elseif ("1" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body72"]())(l1))
          elseif ("2" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body72"]())(l1))
          elseif ("3" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body72"]())(l1))
          elseif ("4" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body72"]())(l1))
          elseif ("5" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body72"]())(l1))
          elseif ("6" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body72"]())(l1))
          elseif ("7" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body72"]())(l1))
          elseif ("8" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body72"]())(l1))
          elseif ("9" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body72"]())(l1))
          elseif ("\"" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body73"]())({ __tuple = true, { __list = true }, (M["body74"]())(""), (M["body25"]())(l1) }))
          elseif (" " == v) then -- match arm
            match_result3 = (M["body45"]())((M["body75"]())(1))
          elseif ("\t" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body75"]())(1))
          elseif ("\r" == v) then -- match arm
            match_result3 = (M["body45"]())((M["body75"]())(1))
          elseif ("\n" == v) then -- match arm
            match_result3 = ((M["body22"]())(M["body76"]()))(1)
          elseif true then -- match arm
            local block_result4 -- block result
            do -- block
              local v = (M["body77"]())(l1) -- match target
              local match_result5 -- match result
              if (true == v) then -- match arm
                match_result5 = (M["body45"]())((M["body82"]())(l1))
              elseif (false == v) then -- match arm
                local block_result6 -- block result
                do -- block
                  l2 = { ["file"] = l0["file"], ["start"] = l0["offset"], ["end"] = (l0["offset"] + 1) } -- pattern binding assign
                  block_result6 = nil
                  l3 = (((M["body32"]())(l2))("found here"))((M["body34"]())(toString("unexpected character `", true)..toString(l1, true)..toString("`", true))) -- pattern binding assign
                  block_result6 = nil
                  block_result6 = ((M["body37"]())(l3))(l0["emitter"])
                  block_result6 = ((M["body22"]())(M["body38"]()))(1)
                end
                match_result5 = block_result6
              end
              block_result4 = match_result5
            end
            match_result3 = block_result4
          end
          block_result2 = (match_result3)(l0)
        end
        match_result1 = block_result2
      elseif v.tag == "symbol" and true then -- match arm
        l4 = v.value -- pattern binding assign
        local block_result7 -- block result
        do -- block
          local v = { __tuple = true, l4, l1 } -- match target
          local match_result8 -- match result
          if v[1].tag == "dot" and ("." == v[2]) then -- match arm
            local t9 = v -- tuple pattern assign
            match_result8 = ((M["body21"]())(M["body83"]()))(2)
          elseif v[1].tag == "minus" and (">" == v[2]) then -- match arm
            local t10 = v -- tuple pattern assign
            match_result8 = ((M["body21"]())(M["body84"]()))(2)
          elseif v[1].tag == "lt" and ("-" == v[2]) then -- match arm
            local t11 = v -- tuple pattern assign
            match_result8 = ((M["body21"]())(M["body85"]()))(2)
          elseif v[1].tag == "colon" and (":" == v[2]) then -- match arm
            local t12 = v -- tuple pattern assign
            match_result8 = ((M["body21"]())(M["body86"]()))(2)
          elseif v[1].tag == "eq" and ("=" == v[2]) then -- match arm
            local t13 = v -- tuple pattern assign
            match_result8 = ((M["body21"]())(M["body87"]()))(2)
          elseif v[1].tag == "bang" and ("=" == v[2]) then -- match arm
            local t14 = v -- tuple pattern assign
            match_result8 = ((M["body21"]())(M["body88"]()))(2)
          elseif v[1].tag == "lt" and ("=" == v[2]) then -- match arm
            local t15 = v -- tuple pattern assign
            match_result8 = ((M["body21"]())(M["body89"]()))(2)
          elseif v[1].tag == "gt" and ("=" == v[2]) then -- match arm
            local t16 = v -- tuple pattern assign
            match_result8 = ((M["body21"]())(M["body90"]()))(2)
          elseif v[1].tag == "lt" and ("|" == v[2]) then -- match arm
            local t17 = v -- tuple pattern assign
            match_result8 = ((M["body21"]())(M["body91"]()))(2)
          elseif v[1].tag == "pipe" and (">" == v[2]) then -- match arm
            local t18 = v -- tuple pattern assign
            match_result8 = ((M["body21"]())(M["body92"]()))(2)
          elseif true then -- match arm
            match_result8 = ((M["body93"]())(l1))(l4)
          end
          block_result7 = (match_result8)(l0)
        end
        match_result1 = block_result7
      elseif v.tag == "integer" and true then -- match arm
        l5 = v.value -- pattern binding assign
        local block_result19 -- block result
        do -- block
          local v = (M["body94"]())(l1) -- match target
          local match_result20 -- match result
          if (true == v) then -- match arm
            local block_result21 -- block result
            do -- block
              block_result21 = ((M["body45"]())((M["body72"]())(((M["body8"]())(l1))(l5))))(l0)
            end
            match_result20 = block_result21
          elseif (false == v) then -- match arm
            local block_result22 -- block result
            do -- block
              block_result22 = ((M["body95"]())(l1))((((M["body22"]())((M["body24"]())(l5)))((M["body25"]())(l5)))(l0))
            end
            match_result20 = block_result22
          end
          block_result19 = match_result20
        end
        match_result1 = block_result19
      elseif v.tag == "ident" and true then -- match arm
        l6 = v.value -- pattern binding assign
        local block_result23 -- block result
        do -- block
          local v = (M["body96"]())(l1) -- match target
          local match_result24 -- match result
          if (true == v) then -- match arm
            local block_result25 -- block result
            do -- block
              block_result25 = ((M["body45"]())((M["body82"]())(((M["body8"]())(l1))(l6))))(l0)
            end
            match_result24 = block_result25
          elseif (false == v) then -- match arm
            local block_result26 -- block result
            do -- block
              block_result26 = ((M["body95"]())(l1))((((M["body22"]())((M["body26"]())(l6)))((M["body25"]())(l6)))(l0))
            end
            match_result24 = block_result26
          end
          block_result23 = match_result24
        end
        match_result1 = block_result23
      elseif v.tag == "whitespace" and true then -- match arm
        l7 = v.value -- pattern binding assign
        local block_result27 -- block result
        do -- block
          local v = (M["body97"]())(l1) -- match target
          local match_result28 -- match result
          if (true == v) then -- match arm
            match_result28 = ((M["body45"]())((M["body75"]())((l7 + 1))))(l0)
          elseif (false == v) then -- match arm
            local block_result29 -- block result
            do -- block
              block_result29 = ((M["body95"]())(l1))((((M["body22"]())(M["body27"]()))(l7))(l0))
            end
            match_result28 = block_result29
          end
          block_result27 = match_result28
        end
        match_result1 = block_result27
      elseif v.tag == "group" and true and true then -- match arm
        local t30 = v.value -- tuple pattern assign
        l8 = t30[1] -- pattern binding assign
        l9 = t30[2] -- pattern binding assign
        local block_result31 -- block result
        do -- block
          local v = (equal(l1, (M["body98"]())(l8)) and (M["body99"]())(l9)) -- match target
          local match_result32 -- match result
          if (false == v) then -- match arm
            local block_result33 -- block result
            do -- block
              l10 = ((M["body43"]())(l9))(l1) -- pattern binding assign
              block_result33 = nil
              block_result33 = ((M["body45"]())((M["body68"]())({ __tuple = true, l8, l10 })))(l0)
            end
            match_result32 = block_result33
          elseif (true == v) then -- match arm
            match_result32 = (((M["body28"]())(l8))(l9))(l0)
          end
          block_result31 = match_result32
        end
        match_result1 = block_result31
      elseif v.tag == "string" and true and true and true then -- match arm
        local t34 = v.value -- tuple pattern assign
        l11 = t34[1] -- pattern binding assign
        l12 = t34[2] -- pattern binding assign
        l13 = t34[3] -- pattern binding assign
        local block_result35 -- block result
        do -- block
          local v = l12 -- match target
          local match_result36 -- match result
          if v.tag == "literal" and true then -- match arm
            l14 = v.value -- pattern binding assign
            local block_result37 -- block result
            do -- block
              local v = l1 -- match target
              local match_result38 -- match result
              if ("\"" == v) then -- match arm
                local block_result39 -- block result
                do -- block
                  block_result39 = ((M["body22"]())((M["body100"]())((M["body101"]())({ __list = true, (M["body103"]())(l14), l11 }))))((l13 + (M["body25"]())(l1)))
                end
                match_result38 = block_result39
              elseif ("\\" == v) then -- match arm
                local block_result40 -- block result
                do -- block
                  l15 = (M["body104"]())(l14) -- pattern binding assign
                  block_result40 = nil
                  block_result40 = (M["body45"]())((M["body73"]())({ __tuple = true, l11, l15, (l13 + (M["body25"]())(l1)) }))
                end
                match_result38 = block_result40
              elseif ("{" == v) then -- match arm
                local block_result41 -- block result
                do -- block
                  l16 = { ["emitter"] = l0["emitter"], ["state"] = M["body18"](), ["tokens"] = { __list = true }, ["file"] = l0["file"], ["offset"] = ((l0["offset"] + l13) + (M["body25"]())(l1)) } -- pattern binding assign
                  block_result41 = nil
                  l17 = { __list = true, (M["body103"]())(l14), l11 } -- pattern binding assign
                  block_result41 = nil
                  l18 = (M["body105"]())(l16) -- pattern binding assign
                  block_result41 = nil
                  block_result41 = (M["body45"]())((M["body73"]())({ __tuple = true, l17, l18, (l13 + (M["body25"]())(l1)) }))
                end
                match_result38 = block_result41
              elseif true then -- match arm
                local block_result42 -- block result
                do -- block
                  l19 = (M["body74"]())(((M["body8"]())(l1))(l14)) -- pattern binding assign
                  block_result42 = nil
                  block_result42 = (M["body45"]())((M["body73"]())({ __tuple = true, l11, l19, (l13 + (M["body25"]())(l1)) }))
                end
                match_result38 = block_result42
              end
              block_result37 = match_result38
            end
            match_result36 = block_result37
          elseif v.tag == "escape" and true then -- match arm
            l20 = v.value -- pattern binding assign
            local block_result43 -- block result
            do -- block
              local v = l1 -- match target
              local match_result44 -- match result
              if ("\"" == v) then -- match arm
                match_result44 = ((((M["body106"]())(l11))(l20))("\""))(l13)
              elseif ("\\" == v) then -- match arm
                match_result44 = ((((M["body106"]())(l11))(l20))("\\"))(l13)
              elseif ("n" == v) then -- match arm
                match_result44 = ((((M["body106"]())(l11))(l20))("\n"))(l13)
              elseif ("t" == v) then -- match arm
                match_result44 = ((((M["body106"]())(l11))(l20))("\t"))(l13)
              elseif ("r" == v) then -- match arm
                match_result44 = ((((M["body106"]())(l11))(l20))("\r"))(l13)
              elseif ("0" == v) then -- match arm
                match_result44 = ((((M["body106"]())(l11))(l20))("\0"))(l13)
              elseif true then -- match arm
                local block_result45 -- block result
                do -- block
                  l21 = { ["file"] = l0["file"], ["start"] = l0["offset"], ["end"] = ((l0["offset"] + l13) + (M["body25"]())(l1)) } -- pattern binding assign
                  block_result45 = nil
                  l22 = (((M["body32"]())(l21))("found in string here"))((M["body34"]())(toString("invalid escape character `", true)..toString(l1, true)..toString("`", true))) -- pattern binding assign
                  block_result45 = nil
                  block_result45 = ((M["body37"]())(l22))(l0["emitter"])
                  l23 = (M["body74"]())(((M["body8"]())(l1))(l20)) -- pattern binding assign
                  block_result45 = nil
                  block_result45 = (M["body45"]())((M["body73"]())({ __tuple = true, l11, l23, (l13 + (M["body25"]())(l1)) }))
                end
                match_result44 = block_result45
              end
              block_result43 = match_result44
            end
            match_result36 = block_result43
          elseif v.tag == "format" and true then -- match arm
            l24 = v.value -- pattern binding assign
            local block_result46 -- block result
            do -- block
              local v = (equal(l1, "}") and (M["body99"]())(l24)) -- match target
              local match_result47 -- match result
              if (false == v) then -- match arm
                local block_result48 -- block result
                do -- block
                  l25 = (M["body105"]())(((M["body95"]())(l1))(l24)) -- pattern binding assign
                  block_result48 = nil
                  block_result48 = (M["body45"]())((M["body73"]())({ __tuple = true, l11, l25, (l13 + (M["body25"]())(l1)) }))
                end
                match_result47 = block_result48
              elseif (true == v) then -- match arm
                local block_result49 -- block result
                do -- block
                  l26 = (M["body19"]())(l24) -- pattern binding assign
                  block_result49 = nil
                  l27 = { __list = true, (M["body107"]())(l26["tokens"]), l11 } -- pattern binding assign
                  block_result49 = nil
                  l28 = (M["body74"]())("") -- pattern binding assign
                  block_result49 = nil
                  block_result49 = (M["body45"]())((M["body73"]())({ __tuple = true, l27, l28, (l13 + (M["body25"]())(l1)) }))
                end
                match_result47 = block_result49
              end
              block_result46 = match_result47
            end
            match_result36 = block_result46
          end
          block_result35 = (match_result36)(l0)
        end
        match_result1 = block_result35
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body44"] = function() -- body ike::lex::lexer::start-symbol
  return function(p0)
    local l0 -- local 's'
    l0 = p0 -- pattern binding assign
    return (M["body45"]())((M["body46"]())(l0))
  end
end

M["body45"] = function() -- body ike::lex::lexer::with-state
  return function(p0)
  return function(p1)
    local l0 -- local 'state'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["emitter"] = l1["emitter"], ["state"] = l0, ["tokens"] = l1["tokens"], ["file"] = l1["file"], ["offset"] = l1["offset"] }
    end
    return block_result0
  end
  end
end

M["body46"] = function() -- body symbol
  return function(p0)
    local l0 -- local 'symbol'
    l0 = p0 -- pattern binding assign
    return { tag = "symbol", value = l0 }
  end
end

M["body47"] = function() -- body semi
    return { tag = "semi" }
end

M["body48"] = function() -- body colon
    return { tag = "colon" }
end

M["body49"] = function() -- body comma
    return { tag = "comma" }
end

M["body50"] = function() -- body dot
    return { tag = "dot" }
end

M["body51"] = function() -- body pound
    return { tag = "pound" }
end

M["body52"] = function() -- body under
    return { tag = "under" }
end

M["body53"] = function() -- body plus
    return { tag = "plus" }
end

M["body54"] = function() -- body minus
    return { tag = "minus" }
end

M["body55"] = function() -- body star
    return { tag = "star" }
end

M["body56"] = function() -- body backslash
    return { tag = "backslash" }
end

M["body57"] = function() -- body amp
    return { tag = "amp" }
end

M["body58"] = function() -- body pipe
    return { tag = "pipe" }
end

M["body59"] = function() -- body caret
    return { tag = "caret" }
end

M["body60"] = function() -- body bang
    return { tag = "bang" }
end

M["body61"] = function() -- body question
    return { tag = "question" }
end

M["body62"] = function() -- body quote
    return { tag = "quote" }
end

M["body63"] = function() -- body eq
    return { tag = "eq" }
end

M["body64"] = function() -- body tilde
    return { tag = "tilde" }
end

M["body65"] = function() -- body lt
    return { tag = "lt" }
end

M["body66"] = function() -- body gt
    return { tag = "gt" }
end

M["body67"] = function() -- body ike::lex::lexer::start-group
  return function(p0)
  return function(p1)
    local l0 -- local 'delimiter'
    local l1 -- local 'lexer'
    local l2 -- local 'lexer''
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = { ["emitter"] = l1["emitter"], ["state"] = M["body18"](), ["tokens"] = { __list = true }, ["file"] = l1["file"], ["offset"] = (l1["offset"] + 1) } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body45"]())((M["body68"]())({ __tuple = true, l0, l2 })))(l1)
    end
    return block_result0
  end
  end
end

M["body68"] = function() -- body group
  return function(p0)
    local l0 -- local 'group'
    l0 = p0 -- pattern binding assign
    return { tag = "group", value = l0 }
  end
end

M["body69"] = function() -- body parentheses
    return { tag = "parentheses" }
end

M["body70"] = function() -- body bracket
    return { tag = "bracket" }
end

M["body71"] = function() -- body brace
    return { tag = "brace" }
end

M["body72"] = function() -- body integer
  return function(p0)
    local l0 -- local 'integer'
    l0 = p0 -- pattern binding assign
    return { tag = "integer", value = l0 }
  end
end

M["body73"] = function() -- body string
  return function(p0)
    local l0 -- local 'string'
    l0 = p0 -- pattern binding assign
    return { tag = "string", value = l0 }
  end
end

M["body74"] = function() -- body literal
  return function(p0)
    local l0 -- local 'literal'
    l0 = p0 -- pattern binding assign
    return { tag = "literal", value = l0 }
  end
end

M["body75"] = function() -- body whitespace
  return function(p0)
    local l0 -- local 'whitespace'
    l0 = p0 -- pattern binding assign
    return { tag = "whitespace", value = l0 }
  end
end

M["body76"] = function() -- body newline
    return { tag = "newline" }
end

M["body77"] = function() -- body ike::lex::lexer::is-ident-start
  return function(p0)
    local l0 -- local 'c'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body78"]())(l0))((M["body81"]())("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"))
    end
    return block_result0
  end
end

M["body78"] = function() -- body std::list::contains
  return function(p0)
    local l0 -- local 'x'
    l0 = p0 -- pattern binding assign
    return (M["body79"]())((M["body80"]())(l0))
  end
end

M["body79"] = function() -- body std::list::any
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'xs'
    local l2 -- local 'xs'
    local l3 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l1 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = false
      elseif #v > 0 and true and true then -- match arm
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        match_result1 = ((l0)(l3) or ((M["body79"]())(l0))(l2))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body80"] = function() -- body std::list::contains::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 'y'
    local l1 -- local 'x'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return equal(l0, l1)
  end
  end
end

M["body81"] = function() -- extern std::string::graphemes
    return E["std::string::graphemes"]()
end

M["body82"] = function() -- body ident
  return function(p0)
    local l0 -- local 'ident'
    l0 = p0 -- pattern binding assign
    return { tag = "ident", value = l0 }
  end
end

M["body83"] = function() -- body dotdot
    return { tag = "dotdot" }
end

M["body84"] = function() -- body rarrow
    return { tag = "rarrow" }
end

M["body85"] = function() -- body larrow
    return { tag = "larrow" }
end

M["body86"] = function() -- body coloncolon
    return { tag = "coloncolon" }
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

M["body93"] = function() -- body ike::lex::lexer::next::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'lexer'
    local l1 -- local 's'
    local l2 -- local 'lexer''
    local l3 -- local 'c'
    l3 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l0 = p2 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = (((M["body21"]())(l1))(1))(l0) -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body43"]())(l2))(l3)
    end
    return block_result0
  end
  end
  end
end

M["body94"] = function() -- body ike::lex::lexer::is-digit
  return function(p0)
    local l0 -- local 'c'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if ("0" == v) then -- match arm
        match_result1 = true
      elseif ("1" == v) then -- match arm
        match_result1 = true
      elseif ("2" == v) then -- match arm
        match_result1 = true
      elseif ("3" == v) then -- match arm
        match_result1 = true
      elseif ("4" == v) then -- match arm
        match_result1 = true
      elseif ("5" == v) then -- match arm
        match_result1 = true
      elseif ("6" == v) then -- match arm
        match_result1 = true
      elseif ("7" == v) then -- match arm
        match_result1 = true
      elseif ("8" == v) then -- match arm
        match_result1 = true
      elseif ("9" == v) then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body95"] = function() -- body ike::lex::lexer::next'
  return function(p0)
  return function(p1)
    local l0 -- local 'c'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    return ((M["body43"]())(l1))(l0)
  end
  end
end

M["body96"] = function() -- body ike::lex::lexer::is-ident-continue
  return function(p0)
    local l0 -- local 'c'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body77"]())(l0) or ((M["body94"]())(l0) or (equal(l0, "_") or (equal(l0, "-") or equal(l0, "'")))))
    end
    return block_result0
  end
end

M["body97"] = function() -- body ike::lex::lexer::is-whitespace
  return function(p0)
    local l0 -- local 'c'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if (" " == v) then -- match arm
        match_result1 = true
      elseif ("\t" == v) then -- match arm
        match_result1 = true
      elseif ("\r" == v) then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body98"] = function() -- body ike::lex::lexer::delim-close-str
  return function(p0)
    local l0 -- local 'delim'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "parentheses" then -- match arm
        match_result1 = ")"
      elseif v.tag == "bracket" then -- match arm
        match_result1 = "]"
      elseif v.tag == "brace" then -- match arm
        match_result1 = "}"
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body99"] = function() -- body ike::lex::lexer::is-not-in-group
  return function(p0)
    local l0 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0["state"] -- match target
      local match_result1 -- match result
      if v.tag == "group" and true then -- match arm
        match_result1 = false
      elseif v.tag == "string" and true then -- match arm
        match_result1 = false
      elseif true then -- match arm
        match_result1 = true
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body100"] = function() -- body format
  return function(p0)
    local l0 -- local 'format'
    l0 = p0 -- pattern binding assign
    return { tag = "format", value = l0 }
  end
end

M["body101"] = function() -- body std::list::reverse
  return function(p0)
    local l0 -- local 'xs'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body102"]())(l0))({ __list = true })
    end
    return block_result0
  end
end

M["body102"] = function() -- body std::list::reverse'
  return function(p0)
  return function(p1)
    local l0 -- local 'xs'
    local l1 -- local 'ys'
    local l2 -- local 'xs'
    local l3 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = l1
      elseif #v > 0 and true and true then -- match arm
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        match_result1 = ((M["body102"]())(l2))({ __list = true, l3, l1 })
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body103"] = function() -- body string
  return function(p0)
    local l0 -- local 'string'
    l0 = p0 -- pattern binding assign
    return { tag = "string", value = l0 }
  end
end

M["body104"] = function() -- body escape
  return function(p0)
    local l0 -- local 'escape'
    l0 = p0 -- pattern binding assign
    return { tag = "escape", value = l0 }
  end
end

M["body105"] = function() -- body format
  return function(p0)
    local l0 -- local 'format'
    l0 = p0 -- pattern binding assign
    return { tag = "format", value = l0 }
  end
end

M["body106"] = function() -- body ike::lex::lexer::with-escape
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'parts'
    local l1 -- local 's'
    local l2 -- local 'c'
    local l3 -- local 'len'
    local l4 -- local 'state'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l4 = (M["body74"]())(((M["body8"]())("\0"))(l1)) -- pattern binding assign
      block_result0 = nil
      block_result0 = (M["body45"]())((M["body73"]())({ __tuple = true, l0, l4, (l3 + (M["body25"]())("\0")) }))
    end
    return block_result0
  end
  end
  end
  end
end

M["body107"] = function() -- body tokens
  return function(p0)
    local l0 -- local 'tokens'
    l0 = p0 -- pattern binding assign
    return { tag = "tokens", value = l0 }
  end
end

M["body108"] = function() -- body std::list::map
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'xs'
    local l2 -- local 'xs'
    local l3 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l1 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = { __list = true }
      elseif #v > 0 and true and true then -- match arm
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        match_result1 = { __list = true, (l0)(l3), ((M["body108"]())(l0))(l2) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body109"] = function() -- body ike::main::{lambda}
  return function(p0)
    local l0 -- local 't'
    local t0 = p0 -- tuple pattern assign
    l0 = t0[1] -- pattern binding assign
    return ((M["body110"]())(l0))(0)
  end
end

M["body110"] = function() -- body ike::debug-token
  return function(p0)
  return function(p1)
    local l0 -- local 'token'
    local l1 -- local 'indent'
    local l2 -- local 'group'
    local l3 -- local 'parts'
    local l4 -- local 'symbol'
    local l5 -- local 'ident'
    local l6 -- local 's'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body7"]())(((M["body111"]())(l1))(" "))
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "group" and true then -- match arm
        l2 = v.value -- pattern binding assign
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body6"]())(toString("group `", true)..toString(l2["delimiter"], true)..toString("`", true))
          block_result2 = ((M["body108"]())((M["body112"]())(l1)))(l2["contents"])
          local block_result3 -- block result
          do -- block
          end
          block_result2 = block_result3
        end
        match_result1 = block_result2
      elseif v.tag == "format" and true then -- match arm
        l3 = v.value -- pattern binding assign
        local block_result4 -- block result
        do -- block
          block_result4 = (M["body6"]())("format")
          block_result4 = ((M["body113"]())((M["body114"]())(l1)))(l3)
          local block_result5 -- block result
          do -- block
          end
          block_result4 = block_result5
        end
        match_result1 = block_result4
      elseif v.tag == "symbol" and true then -- match arm
        l4 = v.value -- pattern binding assign
        match_result1 = (M["body6"]())(toString("symbol `", true)..toString(l4, true)..toString("`", true))
      elseif v.tag == "ident" and true then -- match arm
        l5 = v.value -- pattern binding assign
        match_result1 = (M["body6"]())(toString("ident `", true)..toString(l5, true)..toString("`", true))
      elseif v.tag == "integer" and true then -- match arm
        l6 = v.value -- pattern binding assign
        match_result1 = (M["body6"]())(toString("integer `", true)..toString(l6, true)..toString("`", true))
      elseif v.tag == "whitespace" then -- match arm
        match_result1 = (M["body6"]())("whitespace")
      elseif v.tag == "newline" then -- match arm
        match_result1 = (M["body6"]())("newline")
      elseif v.tag == "error" then -- match arm
        match_result1 = (M["body6"]())("error")
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body111"] = function() -- body std::string::repeat
  return function(p0)
  return function(p1)
    local l0 -- local 'n'
    local l1 -- local 's'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (l0 <= 0) -- match target
      local match_result1 -- match result
      if (true == v) then -- match arm
        match_result1 = ""
      elseif (false == v) then -- match arm
        match_result1 = ((M["body8"]())(l1))(((M["body111"]())((l0 - 1)))(l1))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body112"] = function() -- body ike::debug-token::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 't'
    local l1 -- local 'indent'
    l1 = p0 -- pattern binding assign
    local t0 = p1 -- tuple pattern assign
    l0 = t0[1] -- pattern binding assign
    return ((M["body110"]())(l0))((l1 + 2))
  end
  end
end

M["body113"] = function() -- body std::list::map
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'xs'
    local l2 -- local 'xs'
    local l3 -- local 'x'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l1 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = { __list = true }
      elseif #v > 0 and true and true then -- match arm
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        match_result1 = { __list = true, (l0)(l3), ((M["body113"]())(l0))(l2) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body114"] = function() -- body ike::debug-token::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 'p'
    local l1 -- local 's'
    local l2 -- local 'indent'
    local l3 -- local 'ts'
    l2 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "string" and true then -- match arm
        l1 = v.value -- pattern binding assign
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body7"]())(((M["body111"]())((l2 + 2)))(" "))
          block_result2 = (M["body6"]())(toString("format-string '", true)..toString(l1, true)..toString("'", true))
        end
        match_result1 = block_result2
      elseif v.tag == "tokens" and true then -- match arm
        l3 = v.value -- pattern binding assign
        local block_result3 -- block result
        do -- block
          block_result3 = (M["body7"]())(((M["body111"]())((l2 + 2)))(" "))
          block_result3 = (M["body6"]())("format-tokens")
          block_result3 = ((M["body108"]())((M["body115"]())(l2)))(l3)
          local block_result4 -- block result
          do -- block
          end
          block_result3 = block_result4
        end
        match_result1 = block_result3
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body115"] = function() -- body ike::debug-token::{lambda}::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 't'
    local l1 -- local 'indent'
    l1 = p0 -- pattern binding assign
    local t0 = p1 -- tuple pattern assign
    l0 = t0[1] -- pattern binding assign
    return ((M["body110"]())(l0))((l1 + 4))
  end
  end
end

coroutine.resume(coroutine.create(M["body0"]))
