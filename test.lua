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

E["std::string::len"] = function()
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
    local l0 -- local 'file'
    local l1 -- local 'input'
    local l2 -- local 'ts'
    local l3 -- local 'diagnostics'
    local block_result0 -- block result
    do -- block
      l0 = { ["path"] = "test/parse/expr.ike" } -- pattern binding assign
      block_result0 = nil
      l1 = (M["body1"]())((M["body9"]())("test/parse/expr.ike")) -- pattern binding assign
      block_result0 = nil
      local t1 = ((M["body10"]())(l0))(l1) -- tuple pattern assign
      l2 = t1[1] -- pattern binding assign
      l3 = t1[2] -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body105"]())(M["body106"]()))(l2)
      block_result0 = (M["body115"]())(toString("size ", true)..toString((M["body25"]())(l1), true)..toString("", true))
      block_result0 = ((M["body116"]())(M["body117"]()))(l3)
    end
    return block_result0
end

M["body1"] = function() -- body std::result::assert
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
        match_result1 = (M["body2"]())((M["body4"]())(l2))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body2"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body3"]())("thread main panic: `")
      block_result0 = (M["body3"]())((M["body4"]())(l0))
      block_result0 = (M["body5"]())("`")
      block_result0 = (M["body8"]())(1)
    end
    return block_result0
  end
end

M["body3"] = function() -- extern std::io::print
    return E["std::io::print"]()
end

M["body4"] = function() -- extern std::debug::format
    return E["std::debug::format"]()
end

M["body5"] = function() -- body std::io::println
  return function(p0)
    local l0 -- local 's'
    l0 = p0 -- pattern binding assign
    return (M["body3"]())(((M["body6"]())("\n"))(l0))
  end
end

M["body6"] = function() -- body std::string::append
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
    local l1 -- local 'b'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    return ((M["body7"]())(l1))(l0)
  end
  end
end

M["body7"] = function() -- extern std::string::prepend
    return E["std::string::prepend"]()
end

M["body8"] = function() -- extern std::os::exit
    return E["std::os::exit"]()
end

M["body9"] = function() -- extern std::fs::read
    return E["std::fs::read"]()
end

M["body10"] = function() -- body ike::lex::tokenize
  return function(p0)
  return function(p1)
    local l0 -- local 'file'
    local l1 -- local 'input'
    local l2 -- local 'lexer'
    local l3 -- local 'ts'
    local l4 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = { ["diagnostics"] = { __list = true }, ["graphs"] = (M["body11"]())(l1), ["file"] = l0, ["offset"] = 0, ["delim"] = M["body12"]() } -- pattern binding assign
      block_result0 = nil
      local t1 = ((M["body13"]())({ __list = true }))(l2) -- tuple pattern assign
      l3 = t1[1] -- pattern binding assign
      l4 = t1[2] -- pattern binding assign
      block_result0 = nil
      block_result0 = { __tuple = true, (M["body86"]())(l3), (M["body103"]())(l4["diagnostics"]) }
    end
    return block_result0
  end
  end
end

M["body11"] = function() -- extern std::string::graphemes
    return E["std::string::graphemes"]()
end

M["body12"] = function() -- body none
    return { tag = "none" }
end

M["body13"] = function() -- body ike::lex::lexer::lex
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'lexer'
    local l2 -- local 'delim'
    local l3 -- local 'span'
    local l4 -- local 'diagnostic'
    local l5 -- local 'lexer'
    local l6 -- local 'gs'
    local l7 -- local 'g'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l1["graphs"] -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        local block_result2 -- block result
        do -- block
          local v = l1["delim"] -- match target
          local match_result3 -- match result
          if v.tag == "none" then -- match arm
            match_result3 = { __tuple = true, l0, l1 }
          elseif v.tag == "some" and true and true then -- match arm
            local t4 = v.value -- tuple pattern assign
            l2 = t4[1] -- pattern binding assign
            l3 = t4[2] -- pattern binding assign
            local block_result5 -- block result
            do -- block
              l4 = (((M["body14"]())(l3))("here"))((M["body16"]())(toString("expected closing ", true)..toString(l2, true)..toString("", true))) -- pattern binding assign
              block_result5 = nil
              l5 = ((M["body19"]())(l4))(l1) -- pattern binding assign
              block_result5 = nil
              block_result5 = { __tuple = true, l0, l5 }
            end
            match_result3 = block_result5
          end
          block_result2 = match_result3
        end
        match_result1 = block_result2
      elseif #v > 0 and true and true then -- match arm
        l7 = (v)[1] -- pattern binding assign
        l6 = (v)[2] -- pattern binding assign
        local block_result6 -- block result
        do -- block
          block_result6 = (((M["body20"]())(l0))(l7))(((M["body36"]())(l6))(l1))
        end
        match_result1 = block_result6
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body14"] = function() -- body ike::diagnostic::with-label
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
      l3 = { ["span"] = l0, ["message"] = (M["body15"]())(l1) } -- pattern binding assign
      block_result0 = nil
      block_result0 = { ["level"] = l2["level"], ["message"] = l2["message"], ["labels"] = { __list = true, l3, l2["labels"] } }
    end
    return block_result0
  end
  end
  end
end

M["body15"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body16"] = function() -- body ike::diagnostic::error
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body17"]())(M["body18"]()))(l0)
    end
    return block_result0
  end
end

M["body17"] = function() -- body ike::diagnostic
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

M["body18"] = function() -- body level::error
    return { tag = "level::error" }
end

M["body19"] = function() -- body ike::lex::lexer::with-diagnostic
  return function(p0)
  return function(p1)
    local l0 -- local 'diagnostic'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["diagnostics"] = { __list = true, l0, l1["diagnostics"] }, ["graphs"] = l1["graphs"], ["file"] = l1["file"], ["offset"] = l1["offset"], ["delim"] = l1["delim"] }
    end
    return block_result0
  end
  end
end

M["body20"] = function() -- body ike::lex::lexer::graph
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'ts'
    local l1 -- local 'g'
    local l2 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l1 -- match target
      local match_result1 -- match result
      if ("\n" == v) then -- match arm
        match_result1 = ((M["body21"]())(l0))(l1)
      elseif (" " == v) then -- match arm
        match_result1 = ((M["body26"]())(l0))(l1)
      elseif ("\"" == v) then -- match arm
        match_result1 = ((((M["body28"]())(l0))({ __list = true }))(""))((M["body25"]())(l1))
      elseif (";" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body58"]())
      elseif (":" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body59"]())
      elseif ("," == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body60"]())
      elseif ("." == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body61"]())
      elseif ("#" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body62"]())
      elseif ("_" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body63"]())
      elseif ("+" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body64"]())
      elseif ("-" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body65"]())
      elseif ("*" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body66"]())
      elseif ("/" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body67"]())
      elseif ("\\" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body68"]())
      elseif ("%" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body69"]())
      elseif ("&" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body70"]())
      elseif ("|" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body71"]())
      elseif ("^" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body72"]())
      elseif ("!" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body73"]())
      elseif ("?" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body74"]())
      elseif ("'" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body75"]())
      elseif ("=" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body76"]())
      elseif ("~" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body77"]())
      elseif ("<" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body78"]())
      elseif (">" == v) then -- match arm
        match_result1 = (((M["body44"]())(l0))(l1))(M["body79"]())
      elseif ("0" == v) then -- match arm
        match_result1 = ((M["body80"]())(l0))(l1)
      elseif ("1" == v) then -- match arm
        match_result1 = ((M["body80"]())(l0))(l1)
      elseif ("2" == v) then -- match arm
        match_result1 = ((M["body80"]())(l0))(l1)
      elseif ("3" == v) then -- match arm
        match_result1 = ((M["body80"]())(l0))(l1)
      elseif ("4" == v) then -- match arm
        match_result1 = ((M["body80"]())(l0))(l1)
      elseif ("5" == v) then -- match arm
        match_result1 = ((M["body80"]())(l0))(l1)
      elseif ("6" == v) then -- match arm
        match_result1 = ((M["body80"]())(l0))(l1)
      elseif ("7" == v) then -- match arm
        match_result1 = ((M["body80"]())(l0))(l1)
      elseif ("8" == v) then -- match arm
        match_result1 = ((M["body80"]())(l0))(l1)
      elseif ("9" == v) then -- match arm
        match_result1 = ((M["body80"]())(l0))(l1)
      elseif ("(" == v) then -- match arm
        match_result1 = (((M["body85"]())(l0))(l1))(M["body89"]())
      elseif ("[" == v) then -- match arm
        match_result1 = (((M["body85"]())(l0))(l1))(M["body90"]())
      elseif ("{" == v) then -- match arm
        match_result1 = (((M["body85"]())(l0))(l1))(M["body40"]())
      elseif (")" == v) then -- match arm
        match_result1 = (((M["body91"]())(l0))(l1))(M["body89"]())
      elseif ("]" == v) then -- match arm
        match_result1 = (((M["body91"]())(l0))(l1))(M["body90"]())
      elseif ("}" == v) then -- match arm
        match_result1 = (((M["body91"]())(l0))(l1))(M["body40"]())
      elseif true then -- match arm
        local block_result2 -- block result
        do -- block
          local v = (M["body95"]())(l1) -- match target
          local match_result3 -- match result
          if (true == v) then -- match arm
            match_result3 = ((M["body99"]())(l0))(l1)
          elseif (false == v) then -- match arm
            match_result3 = ((M["body102"]())(l0))(l1)
          end
          block_result2 = match_result3
        end
        match_result1 = block_result2
      end
      block_result0 = (match_result1)(l2)
    end
    return block_result0
  end
  end
  end
end

M["body21"] = function() -- body ike::lex::lexer::newline
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'g'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((M["body22"]())(l0))(M["body24"]()))((M["body25"]())(l1))
    end
    return block_result0
  end
  end
end

M["body22"] = function() -- body ike::lex::lexer::lex-with
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'ts'
    local l1 -- local 'tok'
    local l2 -- local 'len'
    local l3 -- local 'lexer'
    local l4 -- local 'span'
    local l5 -- local 'lexer'
    local l6 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l4 = { ["file"] = l3["file"], ["start"] = l3["offset"], ["end"] = (l3["offset"] + l2) } -- pattern binding assign
      block_result0 = nil
      l5 = ((M["body23"]())(l2))(l3) -- pattern binding assign
      block_result0 = nil
      l6 = { __list = true, { __tuple = true, l1, l4 }, l0 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body13"]())(l6))(l5)
    end
    return block_result0
  end
  end
  end
  end
end

M["body23"] = function() -- body ike::lex::lexer::with-offset
  return function(p0)
  return function(p1)
    local l0 -- local 'offset'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["diagnostics"] = l1["diagnostics"], ["graphs"] = l1["graphs"], ["file"] = l1["file"], ["offset"] = (l1["offset"] + l0), ["delim"] = l1["delim"] }
    end
    return block_result0
  end
  end
end

M["body24"] = function() -- body newline
    return { tag = "newline" }
end

M["body25"] = function() -- extern std::string::len
    return E["std::string::len"]()
end

M["body26"] = function() -- body ike::lex::lexer::whitespace
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'g'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((M["body22"]())(l0))(M["body27"]()))((M["body25"]())(l1))
    end
    return block_result0
  end
  end
end

M["body27"] = function() -- body whitespace
    return { tag = "whitespace" }
end

M["body28"] = function() -- body ike::lex::lexer::string
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
  return function(p4)
    local l0 -- local 'ts'
    local l1 -- local 'parts'
    local l2 -- local 's'
    local l3 -- local 'len'
    local l4 -- local 'lexer'
    local l5 -- local 'lexer'
    local l6 -- local 'escape'
    local l7 -- local 'g'
    local l8 -- local 'span'
    local l9 -- local 'diagnostic'
    local l10 -- local 'lexer'
    local l11 -- local 'ts'
    local l12 -- local 'span'
    local l13 -- local 'diagnostic'
    local l14 -- local 'lexer'
    local l15 -- local 'ts'
    local l16 -- local 'lexer'
    local l17 -- local 'delim-span'
    local l18 -- local 'lexer''
    local l19 -- local 'ts''
    local l20 -- local 'lexer''
    local l21 -- local 'lexer'
    local l22 -- local 'g'
    local l23 -- local 'span'
    local l24 -- local 'diagnostic'
    local l25 -- local 'lexer'
    local l26 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    l4 = p4 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body29"]())(l4) -- match target
      local match_result1 -- match result
      if v.tag == "some" and ("\"" == v.value) then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((((M["body22"]())(l0))((M["body31"]())((M["body32"]())({ __list = true, (M["body34"]())(l2), l1 }))))((l3 + (M["body25"]())("\""))))((M["body35"]())(l4))
        end
        match_result1 = block_result2
      elseif v.tag == "some" and ("\\" == v.value) then -- match arm
        local block_result3 -- block result
        do -- block
          l5 = (M["body35"]())(l4) -- pattern binding assign
          block_result3 = nil
          l6 = (((((M["body37"]())(l0))(l1))(l2))(l3))(l5) -- pattern binding assign
          block_result3 = nil
          local v = (M["body29"]())(l5) -- match target
          local match_result4 -- match result
          if v.tag == "some" and ("\\" == v.value) then -- match arm
            match_result4 = (l6)("\\")
          elseif v.tag == "some" and ("\"" == v.value) then -- match arm
            match_result4 = (l6)("\"")
          elseif v.tag == "some" and ("n" == v.value) then -- match arm
            match_result4 = (l6)("\n")
          elseif v.tag == "some" and ("t" == v.value) then -- match arm
            match_result4 = (l6)("\t")
          elseif v.tag == "some" and ("r" == v.value) then -- match arm
            match_result4 = (l6)("\r")
          elseif v.tag == "some" and true then -- match arm
            l7 = v.value -- pattern binding assign
            local block_result5 -- block result
            do -- block
              l8 = { ["file"] = l5["file"], ["start"] = (l5["offset"] + l3), ["end"] = (((l5["offset"] + l3) + (M["body25"]())("\\")) + (M["body25"]())(l7)) } -- pattern binding assign
              block_result5 = nil
              l9 = (((M["body14"]())(l8))("found here"))((M["body16"]())(toString("invalid escape character `", true)..toString(l7, true)..toString("`", true))) -- pattern binding assign
              block_result5 = nil
              l10 = ((M["body23"]())(((l3 + (M["body25"]())("\\")) + (M["body25"]())(l7))))(((M["body19"]())(l9))(l5)) -- pattern binding assign
              block_result5 = nil
              l11 = { __list = true, { __tuple = true, (M["body31"]())({ __list = true, (M["body34"]())(l2), { __list = true } }), l8 }, l0 } -- pattern binding assign
              block_result5 = nil
              block_result5 = { __tuple = true, l11, l10 }
            end
            match_result4 = block_result5
          elseif v.tag == "none" then -- match arm
            local block_result6 -- block result
            do -- block
              l12 = { ["file"] = l5["file"], ["start"] = l5["offset"], ["end"] = (l5["offset"] + l3) } -- pattern binding assign
              block_result6 = nil
              l13 = (((M["body14"]())(l12))("found here"))((M["body16"]())("expected escape character")) -- pattern binding assign
              block_result6 = nil
              l14 = ((M["body23"]())((l3 + (M["body25"]())("\\"))))(((M["body19"]())(l13))(l5)) -- pattern binding assign
              block_result6 = nil
              l15 = { __list = true, { __tuple = true, (M["body31"]())({ __list = true, (M["body34"]())(l2), { __list = true } }), l12 }, l0 } -- pattern binding assign
              block_result6 = nil
              block_result6 = { __tuple = true, l15, l14 }
            end
            match_result4 = block_result6
          end
          block_result3 = match_result4
        end
        match_result1 = block_result3
      elseif v.tag == "some" and ("{" == v.value) then -- match arm
        local block_result7 -- block result
        do -- block
          l16 = (M["body35"]())(l4) -- pattern binding assign
          block_result7 = nil
          local v = equal((M["body29"]())(l16), (M["body15"]())("{")) -- match target
          local match_result8 -- match result
          if (true == v) then -- match arm
            local block_result9 -- block result
            do -- block
              block_result9 = (((((M["body28"]())(l0))(l1))(((M["body6"]())("{"))(l2)))((l3 + ((M["body25"]())("{") * 2))))((M["body35"]())(l16))
            end
            match_result8 = block_result9
          elseif (false == v) then -- match arm
            local block_result10 -- block result
            do -- block
              l17 = { ["file"] = l16["file"], ["start"] = (l16["offset"] + l3), ["end"] = ((l16["offset"] + l3) + (M["body25"]())("{")) } -- pattern binding assign
              block_result10 = nil
              l18 = ((M["body23"]())((l3 + (M["body25"]())("{"))))(((M["body38"]())((M["body39"]())({ __tuple = true, M["body40"](), l17 })))(l16)) -- pattern binding assign
              block_result10 = nil
              local t11 = ((M["body13"]())({ __list = true }))(l18) -- tuple pattern assign
              l19 = t11[1] -- pattern binding assign
              l20 = t11[2] -- pattern binding assign
              block_result10 = nil
              l21 = ((M["body41"]())(l20["diagnostics"]))(((M["body36"]())(l20["graphs"]))(l16)) -- pattern binding assign
              block_result10 = nil
              block_result10 = (((((M["body28"]())(l0))({ __list = true, (M["body43"]())(l19), { __list = true, (M["body34"]())(l2), l1 } }))(""))((l20["offset"] - l21["offset"])))(l21)
            end
            match_result8 = block_result10
          end
          block_result7 = match_result8
        end
        match_result1 = block_result7
      elseif v.tag == "some" and true then -- match arm
        l22 = v.value -- pattern binding assign
        local block_result12 -- block result
        do -- block
          block_result12 = (((((M["body28"]())(l0))(l1))(((M["body6"]())(l22))(l2)))((l3 + (M["body25"]())(l22))))((M["body35"]())(l4))
        end
        match_result1 = block_result12
      elseif v.tag == "none" then -- match arm
        local block_result13 -- block result
        do -- block
          l23 = { ["file"] = l4["file"], ["start"] = l4["offset"], ["end"] = (l4["offset"] + l3) } -- pattern binding assign
          block_result13 = nil
          l24 = (((M["body14"]())(l23))("found here"))((M["body16"]())("expected end of string")) -- pattern binding assign
          block_result13 = nil
          l25 = ((M["body23"]())(l3))(((M["body19"]())(l24))(l4)) -- pattern binding assign
          block_result13 = nil
          l26 = { __list = true, { __tuple = true, (M["body31"]())({ __list = true, (M["body34"]())(l2), { __list = true } }), l23 }, l0 } -- pattern binding assign
          block_result13 = nil
          block_result13 = { __tuple = true, l26, l25 }
        end
        match_result1 = block_result13
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
  end
  end
end

M["body29"] = function() -- body ike::lex::lexer::peek
  return function(p0)
    local l0 -- local 'lexer'
    local l1 -- local 'g'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0["graphs"] -- match target
      local match_result1 -- match result
      if #v > 0 and true and true then -- match arm
        l1 = (v)[1] -- pattern binding assign
        match_result1 = (M["body15"]())(l1)
      elseif #v == 0 then -- match arm
        match_result1 = M["body30"]()
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body30"] = function() -- body none
    return { tag = "none" }
end

M["body31"] = function() -- body format
  return function(p0)
    local l0 -- local 'format'
    l0 = p0 -- pattern binding assign
    return { tag = "format", value = l0 }
  end
end

M["body32"] = function() -- body std::list::reverse
  return function(p0)
    local l0 -- local 'xs'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body33"]())(l0))({ __list = true })
    end
    return block_result0
  end
end

M["body33"] = function() -- body std::list::reverse'
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
        match_result1 = ((M["body33"]())(l2))({ __list = true, l3, l1 })
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body34"] = function() -- body string
  return function(p0)
    local l0 -- local 'string'
    l0 = p0 -- pattern binding assign
    return { tag = "string", value = l0 }
  end
end

M["body35"] = function() -- body ike::lex::lexer::skip
  return function(p0)
    local l0 -- local 'lexer'
    local l1 -- local 'gs'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0["graphs"] -- match target
      local match_result1 -- match result
      if #v > 0 and true and true then -- match arm
        l1 = (v)[2] -- pattern binding assign
        match_result1 = ((M["body36"]())(l1))(l0)
      elseif #v == 0 then -- match arm
        match_result1 = l0
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body36"] = function() -- body ike::lex::lexer::with-graphs
  return function(p0)
  return function(p1)
    local l0 -- local 'graphs'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["diagnostics"] = l1["diagnostics"], ["graphs"] = l0, ["file"] = l1["file"], ["offset"] = l1["offset"], ["delim"] = l1["delim"] }
    end
    return block_result0
  end
  end
end

M["body37"] = function() -- body ike::lex::lexer::string::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
  return function(p4)
  return function(p5)
    local l0 -- local 'esc'
    local l1 -- local 'lexer'
    local l2 -- local 'len'
    local l3 -- local 's'
    local l4 -- local 'parts'
    local l5 -- local 'ts'
    l5 = p0 -- pattern binding assign
    l4 = p1 -- pattern binding assign
    l3 = p2 -- pattern binding assign
    l2 = p3 -- pattern binding assign
    l1 = p4 -- pattern binding assign
    l0 = p5 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((((M["body28"]())(l5))(l4))(((M["body6"]())(l0))(l3)))(((l2 + (M["body25"]())("\\")) + (M["body25"]())(l0))))((M["body35"]())(l1))
    end
    return block_result0
  end
  end
  end
  end
  end
  end
end

M["body38"] = function() -- body ike::lex::lexer::with-delim
  return function(p0)
  return function(p1)
    local l0 -- local 'delim'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["diagnostics"] = l1["diagnostics"], ["graphs"] = l1["graphs"], ["file"] = l1["file"], ["offset"] = l1["offset"], ["delim"] = l0 }
    end
    return block_result0
  end
  end
end

M["body39"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body40"] = function() -- body brace
    return { tag = "brace" }
end

M["body41"] = function() -- body ike::lex::lexer::with-diagnostics
  return function(p0)
  return function(p1)
    local l0 -- local 'diagnostics'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["diagnostics"] = ((M["body42"]())(l0))(l1["diagnostics"]), ["graphs"] = l1["graphs"], ["file"] = l1["file"], ["offset"] = l1["offset"], ["delim"] = l1["delim"] }
    end
    return block_result0
  end
  end
end

M["body42"] = function() -- body std::list::append
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
        match_result1 = { __list = true, l3, ((M["body42"]())(l2))(l1) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body43"] = function() -- body tokens
  return function(p0)
    local l0 -- local 'tokens'
    l0 = p0 -- pattern binding assign
    return { tag = "tokens", value = l0 }
  end
end

M["body44"] = function() -- body ike::lex::lexer::symbol
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'ts'
    local l1 -- local 'g'
    local l2 -- local 'symbol'
    local l3 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = { __tuple = true, l2, (M["body29"]())(l3) } -- match target
      local match_result1 -- match result
      if v[1].tag == "dot" and v[2].tag == "some" and ("." == v[2].value) then -- match arm
        local t2 = v -- tuple pattern assign
        match_result1 = ((((M["body45"]())(l0))(l1))("."))(M["body47"]())
      elseif v[1].tag == "minus" and v[2].tag == "some" and (">" == v[2].value) then -- match arm
        local t3 = v -- tuple pattern assign
        match_result1 = ((((M["body45"]())(l0))(l1))(">"))(M["body48"]())
      elseif v[1].tag == "lt" and v[2].tag == "some" and ("<" == v[2].value) then -- match arm
        local t4 = v -- tuple pattern assign
        match_result1 = ((((M["body45"]())(l0))(l1))("<"))(M["body49"]())
      elseif v[1].tag == "colon" and v[2].tag == "some" and (":" == v[2].value) then -- match arm
        local t5 = v -- tuple pattern assign
        match_result1 = ((((M["body45"]())(l0))(l1))(":"))(M["body50"]())
      elseif v[1].tag == "eq" and v[2].tag == "some" and ("=" == v[2].value) then -- match arm
        local t6 = v -- tuple pattern assign
        match_result1 = ((((M["body45"]())(l0))(l1))("="))(M["body51"]())
      elseif v[1].tag == "bang" and v[2].tag == "some" and ("=" == v[2].value) then -- match arm
        local t7 = v -- tuple pattern assign
        match_result1 = ((((M["body45"]())(l0))(l1))("="))(M["body52"]())
      elseif v[1].tag == "lt" and v[2].tag == "some" and ("=" == v[2].value) then -- match arm
        local t8 = v -- tuple pattern assign
        match_result1 = ((((M["body45"]())(l0))(l1))("="))(M["body53"]())
      elseif v[1].tag == "gt" and v[2].tag == "some" and ("=" == v[2].value) then -- match arm
        local t9 = v -- tuple pattern assign
        match_result1 = ((((M["body45"]())(l0))(l1))("="))(M["body54"]())
      elseif v[1].tag == "lt" and v[2].tag == "some" and ("|" == v[2].value) then -- match arm
        local t10 = v -- tuple pattern assign
        match_result1 = ((((M["body45"]())(l0))(l1))("|"))(M["body55"]())
      elseif v[1].tag == "pipe" and v[2].tag == "some" and (">" == v[2].value) then -- match arm
        local t11 = v -- tuple pattern assign
        match_result1 = ((((M["body45"]())(l0))(l1))(">"))(M["body56"]())
      elseif true then -- match arm
        match_result1 = (((M["body57"]())(l0))(l1))(l2)
      end
      block_result0 = (match_result1)(l3)
    end
    return block_result0
  end
  end
  end
  end
end

M["body45"] = function() -- body ike::lex::lexer::two-graph-symbol
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
  return function(p4)
    local l0 -- local 'ts'
    local l1 -- local 'g1'
    local l2 -- local 'g2'
    local l3 -- local 'symbol'
    local l4 -- local 'lexer'
    local l5 -- local 'span'
    local l6 -- local 'lexer'
    local l7 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    l4 = p4 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l5 = { ["file"] = l4["file"], ["start"] = l4["offset"], ["end"] = ((l4["offset"] + (M["body25"]())(l1)) + (M["body25"]())(l2)) } -- pattern binding assign
      block_result0 = nil
      l6 = ((M["body23"]())(((M["body25"]())(l1) + (M["body25"]())(l2))))((M["body35"]())(l4)) -- pattern binding assign
      block_result0 = nil
      l7 = { __list = true, { __tuple = true, (M["body46"]())(l3), l5 }, l0 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body13"]())(l7))(l6)
    end
    return block_result0
  end
  end
  end
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

M["body47"] = function() -- body dotdot
    return { tag = "dotdot" }
end

M["body48"] = function() -- body rarrow
    return { tag = "rarrow" }
end

M["body49"] = function() -- body larrow
    return { tag = "larrow" }
end

M["body50"] = function() -- body coloncolon
    return { tag = "coloncolon" }
end

M["body51"] = function() -- body eqeq
    return { tag = "eqeq" }
end

M["body52"] = function() -- body noteq
    return { tag = "noteq" }
end

M["body53"] = function() -- body lteq
    return { tag = "lteq" }
end

M["body54"] = function() -- body gteq
    return { tag = "gteq" }
end

M["body55"] = function() -- body ltpipe
    return { tag = "ltpipe" }
end

M["body56"] = function() -- body pipegt
    return { tag = "pipegt" }
end

M["body57"] = function() -- body ike::lex::lexer::one-graph-symbol
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'ts'
    local l1 -- local 'g'
    local l2 -- local 'symbol'
    local l3 -- local 'lexer'
    local l4 -- local 'span'
    local l5 -- local 'lexer'
    local l6 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l4 = { ["file"] = l3["file"], ["start"] = l3["offset"], ["end"] = (l3["offset"] + (M["body25"]())(l1)) } -- pattern binding assign
      block_result0 = nil
      l5 = ((M["body23"]())((M["body25"]())(l1)))(l3) -- pattern binding assign
      block_result0 = nil
      l6 = { __list = true, { __tuple = true, (M["body46"]())(l2), l4 }, l0 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body13"]())(l6))(l5)
    end
    return block_result0
  end
  end
  end
  end
end

M["body58"] = function() -- body semi
    return { tag = "semi" }
end

M["body59"] = function() -- body colon
    return { tag = "colon" }
end

M["body60"] = function() -- body comma
    return { tag = "comma" }
end

M["body61"] = function() -- body dot
    return { tag = "dot" }
end

M["body62"] = function() -- body pound
    return { tag = "pound" }
end

M["body63"] = function() -- body under
    return { tag = "under" }
end

M["body64"] = function() -- body plus
    return { tag = "plus" }
end

M["body65"] = function() -- body minus
    return { tag = "minus" }
end

M["body66"] = function() -- body star
    return { tag = "star" }
end

M["body67"] = function() -- body slash
    return { tag = "slash" }
end

M["body68"] = function() -- body backslash
    return { tag = "backslash" }
end

M["body69"] = function() -- body percent
    return { tag = "percent" }
end

M["body70"] = function() -- body amp
    return { tag = "amp" }
end

M["body71"] = function() -- body pipe
    return { tag = "pipe" }
end

M["body72"] = function() -- body caret
    return { tag = "caret" }
end

M["body73"] = function() -- body bang
    return { tag = "bang" }
end

M["body74"] = function() -- body question
    return { tag = "question" }
end

M["body75"] = function() -- body quote
    return { tag = "quote" }
end

M["body76"] = function() -- body eq
    return { tag = "eq" }
end

M["body77"] = function() -- body tilde
    return { tag = "tilde" }
end

M["body78"] = function() -- body lt
    return { tag = "lt" }
end

M["body79"] = function() -- body gt
    return { tag = "gt" }
end

M["body80"] = function() -- body ike::lex::lexer::integer
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'ts'
    local l1 -- local 's'
    local l2 -- local 'lexer'
    local l3 -- local 'is-digit'
    local l4 -- local 'g'
    local l5 -- local 's'
    local l6 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l3 = ((M["body81"]())(M["body82"]()))((M["body29"]())(l2)) -- pattern binding assign
      block_result0 = nil
      local v = l3 -- match target
      local match_result1 -- match result
      if (true == v) then -- match arm
        local block_result2 -- block result
        do -- block
          l4 = (M["body83"]())((M["body29"]())(l2)) -- pattern binding assign
          block_result2 = nil
          l5 = ((M["body6"]())(l4))(l1) -- pattern binding assign
          block_result2 = nil
          l6 = (M["body35"]())(l2) -- pattern binding assign
          block_result2 = nil
          block_result2 = (((M["body80"]())(l0))(l5))(l6)
        end
        match_result1 = block_result2
      elseif (false == v) then -- match arm
        local block_result3 -- block result
        do -- block
          block_result3 = ((((M["body22"]())(l0))((M["body84"]())(l1)))((M["body25"]())(l1)))(l2)
        end
        match_result1 = block_result3
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body81"] = function() -- body std::option::is-some-and
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'opt'
    local l2 -- local 'a'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l1 -- match target
      local match_result1 -- match result
      if v.tag == "some" and true then -- match arm
        l2 = v.value -- pattern binding assign
        match_result1 = (l0)(l2)
      elseif v.tag == "none" then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body82"] = function() -- body ike::lex::lexer::is-digit
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

M["body83"] = function() -- body std::option::assert
  return function(p0)
    local l0 -- local 'opt'
    local l1 -- local 'a'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "some" and true then -- match arm
        l1 = v.value -- pattern binding assign
        match_result1 = l1
      elseif v.tag == "none" then -- match arm
        match_result1 = (M["body2"]())("option was none")
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body84"] = function() -- body integer
  return function(p0)
    local l0 -- local 'integer'
    l0 = p0 -- pattern binding assign
    return { tag = "integer", value = l0 }
  end
end

M["body85"] = function() -- body ike::lex::lexer::start-group
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'ts'
    local l1 -- local 'g'
    local l2 -- local 'delim'
    local l3 -- local 'lexer'
    local l4 -- local 'delim-span'
    local l5 -- local 'ts''
    local l6 -- local 'lexer''
    local l7 -- local 'span'
    local l8 -- local 'group'
    local l9 -- local 'ts'
    local l10 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l4 = { ["file"] = l3["file"], ["start"] = l3["offset"], ["end"] = (l3["offset"] + (M["body25"]())(l1)) } -- pattern binding assign
      block_result0 = nil
      local t1 = ((M["body13"]())({ __list = true }))(((M["body38"]())((M["body39"]())({ __tuple = true, l2, l4 })))(((M["body23"]())((M["body25"]())(l1)))(l3))) -- tuple pattern assign
      l5 = t1[1] -- pattern binding assign
      l6 = t1[2] -- pattern binding assign
      block_result0 = nil
      l7 = { ["file"] = l3["file"], ["start"] = l3["offset"], ["end"] = l6["offset"] } -- pattern binding assign
      block_result0 = nil
      l8 = { ["delimiter"] = l2, ["contents"] = (M["body86"]())(l5) } -- pattern binding assign
      block_result0 = nil
      l9 = { __list = true, { __tuple = true, (M["body88"]())(l8), l7 }, l0 } -- pattern binding assign
      block_result0 = nil
      l10 = ((M["body41"]())(l3["diagnostics"]))(((M["body38"]())(l3["delim"]))(l6)) -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body13"]())(l9))(l10)
    end
    return block_result0
  end
  end
  end
  end
end

M["body86"] = function() -- body std::list::reverse
  return function(p0)
    local l0 -- local 'xs'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body87"]())(l0))({ __list = true })
    end
    return block_result0
  end
end

M["body87"] = function() -- body std::list::reverse'
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
        match_result1 = ((M["body87"]())(l2))({ __list = true, l3, l1 })
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body88"] = function() -- body group
  return function(p0)
    local l0 -- local 'group'
    l0 = p0 -- pattern binding assign
    return { tag = "group", value = l0 }
  end
end

M["body89"] = function() -- body parentheses
    return { tag = "parentheses" }
end

M["body90"] = function() -- body bracket
    return { tag = "bracket" }
end

M["body91"] = function() -- body ike::lex::lexer::end-group
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'ts'
    local l1 -- local 'g'
    local l2 -- local 'delim'
    local l3 -- local 'lexer'
    local l4 -- local 'span'
    local l5 -- local 'diagnostic'
    local l6 -- local 'lexer'
    local l7 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = ((M["body92"]())((M["body93"]())(l2)))(l3["delim"]) -- match target
      local match_result1 -- match result
      if (true == v) then -- match arm
        match_result1 = { __tuple = true, l0, ((M["body23"]())((M["body25"]())(l1)))(l3) }
      elseif (false == v) then -- match arm
        local block_result2 -- block result
        do -- block
          l4 = { ["file"] = l3["file"], ["start"] = l3["offset"], ["end"] = (l3["offset"] + (M["body25"]())(l1)) } -- pattern binding assign
          block_result2 = nil
          l5 = (((M["body14"]())(l4))("found here"))((M["body16"]())(toString("unexpected closing ", true)..toString(l2, true)..toString("", true))) -- pattern binding assign
          block_result2 = nil
          l6 = ((M["body19"]())(l5))(((M["body23"]())((M["body25"]())(l1)))(l3)) -- pattern binding assign
          block_result2 = nil
          l7 = { __list = true, { __tuple = true, M["body94"](), l4 }, l0 } -- pattern binding assign
          block_result2 = nil
          block_result2 = ((M["body13"]())(l7))(l6)
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
  end
end

M["body92"] = function() -- body std::option::is-some-and
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'opt'
    local l2 -- local 'a'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l1 -- match target
      local match_result1 -- match result
      if v.tag == "some" and true then -- match arm
        l2 = v.value -- pattern binding assign
        match_result1 = (l0)(l2)
      elseif v.tag == "none" then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body93"] = function() -- body ike::lex::lexer::end-group::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 'd'
    local l1 -- local 'delim'
    l1 = p0 -- pattern binding assign
    local t0 = p1 -- tuple pattern assign
    l0 = t0[1] -- pattern binding assign
    return equal(l0, l1)
  end
  end
end

M["body94"] = function() -- body error
    return { tag = "error" }
end

M["body95"] = function() -- body ike::lex::lexer::is-ident-start
  return function(p0)
    local l0 -- local 'c'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body96"]())(l0))((M["body11"]())("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"))
    end
    return block_result0
  end
end

M["body96"] = function() -- body std::list::contains
  return function(p0)
    local l0 -- local 'x'
    l0 = p0 -- pattern binding assign
    return (M["body97"]())((M["body98"]())(l0))
  end
end

M["body97"] = function() -- body std::list::any
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
        match_result1 = ((l0)(l3) or ((M["body97"]())(l0))(l2))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body98"] = function() -- body std::list::contains::{lambda}
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

M["body99"] = function() -- body ike::lex::lexer::ident
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'ts'
    local l1 -- local 's'
    local l2 -- local 'lexer'
    local l3 -- local 'is-continue'
    local l4 -- local 'g'
    local l5 -- local 's'
    local l6 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l3 = ((M["body81"]())(M["body100"]()))((M["body29"]())(l2)) -- pattern binding assign
      block_result0 = nil
      local v = l3 -- match target
      local match_result1 -- match result
      if (true == v) then -- match arm
        local block_result2 -- block result
        do -- block
          l4 = (M["body83"]())((M["body29"]())(l2)) -- pattern binding assign
          block_result2 = nil
          l5 = ((M["body6"]())(l4))(l1) -- pattern binding assign
          block_result2 = nil
          l6 = (M["body35"]())(l2) -- pattern binding assign
          block_result2 = nil
          block_result2 = (((M["body99"]())(l0))(l5))(l6)
        end
        match_result1 = block_result2
      elseif (false == v) then -- match arm
        local block_result3 -- block result
        do -- block
          block_result3 = ((((M["body22"]())(l0))((M["body101"]())(l1)))((M["body25"]())(l1)))(l2)
        end
        match_result1 = block_result3
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body100"] = function() -- body ike::lex::lexer::is-ident-continue
  return function(p0)
    local l0 -- local 'c'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body95"]())(l0) or ((M["body82"]())(l0) or (equal(l0, "_") or (equal(l0, "-") or equal(l0, "'")))))
    end
    return block_result0
  end
end

M["body101"] = function() -- body ident
  return function(p0)
    local l0 -- local 'ident'
    l0 = p0 -- pattern binding assign
    return { tag = "ident", value = l0 }
  end
end

M["body102"] = function() -- body ike::lex::lexer::unexpected-graph
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'ts'
    local l1 -- local 'g'
    local l2 -- local 'lexer'
    local l3 -- local 'span'
    local l4 -- local 'diagnostic'
    local l5 -- local 'lexer'
    local l6 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l3 = { ["file"] = l2["file"], ["start"] = l2["offset"], ["end"] = (l2["offset"] + (M["body25"]())(l1)) } -- pattern binding assign
      block_result0 = nil
      l4 = (((M["body14"]())(l3))("found here"))((M["body16"]())(toString("unexpected character `", true)..toString(l1, true)..toString("`", true))) -- pattern binding assign
      block_result0 = nil
      l5 = ((M["body23"]())((M["body25"]())(l1)))(((M["body19"]())(l4))(l2)) -- pattern binding assign
      block_result0 = nil
      l6 = { __list = true, { __tuple = true, M["body94"](), l3 }, l0 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body13"]())(l6))(l5)
    end
    return block_result0
  end
  end
  end
end

M["body103"] = function() -- body std::list::reverse
  return function(p0)
    local l0 -- local 'xs'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body104"]())(l0))({ __list = true })
    end
    return block_result0
  end
end

M["body104"] = function() -- body std::list::reverse'
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
        match_result1 = ((M["body104"]())(l2))({ __list = true, l3, l1 })
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body105"] = function() -- body std::list::map
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
        match_result1 = { __list = true, (l0)(l3), ((M["body105"]())(l0))(l2) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body106"] = function() -- body ike::main::{lambda}
  return function(p0)
    local l0 -- local 't'
    local l1 -- local 's'
    local t0 = p0 -- tuple pattern assign
    l0 = t0[1] -- pattern binding assign
    l1 = t0[2] -- pattern binding assign
    return (((M["body107"]())(l0))(l1))(0)
  end
end

M["body107"] = function() -- body ike::debug-token
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'token'
    local l1 -- local 'span'
    local l2 -- local 'indent'
    local l3 -- local 'group'
    local l4 -- local 'parts'
    local l5 -- local 'symbol'
    local l6 -- local 'ident'
    local l7 -- local 's'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body3"]())(((M["body108"]())(l2))(" "))
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "group" and true then -- match arm
        l3 = v.value -- pattern binding assign
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body5"]())(toString("group `", true)..toString(l3["delimiter"], true)..toString("` ", true)..toString(l1, true)..toString("", true))
          block_result2 = ((M["body109"]())((M["body110"]())(l2)))(l3["contents"])
          local block_result3 -- block result
          do -- block
          end
          block_result2 = block_result3
        end
        match_result1 = block_result2
      elseif v.tag == "format" and true then -- match arm
        l4 = v.value -- pattern binding assign
        local block_result4 -- block result
        do -- block
          block_result4 = (M["body5"]())(toString("format ", true)..toString(l1, true)..toString("", true))
          block_result4 = ((M["body112"]())((M["body113"]())(l2)))(l4)
          local block_result5 -- block result
          do -- block
          end
          block_result4 = block_result5
        end
        match_result1 = block_result4
      elseif v.tag == "symbol" and true then -- match arm
        l5 = v.value -- pattern binding assign
        match_result1 = (M["body5"]())(toString("symbol `", true)..toString(l5, true)..toString("` ", true)..toString(l1, true)..toString("", true))
      elseif v.tag == "ident" and true then -- match arm
        l6 = v.value -- pattern binding assign
        match_result1 = (M["body5"]())(toString("ident `", true)..toString(l6, true)..toString("` ", true)..toString(l1, true)..toString("", true))
      elseif v.tag == "integer" and true then -- match arm
        l7 = v.value -- pattern binding assign
        match_result1 = (M["body5"]())(toString("integer `", true)..toString(l7, true)..toString("` ", true)..toString(l1, true)..toString("", true))
      elseif v.tag == "whitespace" then -- match arm
        match_result1 = (M["body5"]())(toString("whitespace ", true)..toString(l1, true)..toString("", true))
      elseif v.tag == "newline" then -- match arm
        match_result1 = (M["body5"]())(toString("newline ", true)..toString(l1, true)..toString("", true))
      elseif v.tag == "error" then -- match arm
        match_result1 = (M["body5"]())(toString("error ", true)..toString(l1, true)..toString("", true))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body108"] = function() -- body std::string::repeat
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
        match_result1 = ((M["body6"]())(l1))(((M["body108"]())((l0 - 1)))(l1))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body109"] = function() -- body std::list::map
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
        match_result1 = { __list = true, (l0)(l3), ((M["body109"]())(l0))(l2) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body110"] = function() -- body ike::debug-token::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 't'
    local l1 -- local 's'
    local l2 -- local 'indent'
    l2 = p0 -- pattern binding assign
    local t0 = p1 -- tuple pattern assign
    l0 = t0[1] -- pattern binding assign
    l1 = t0[2] -- pattern binding assign
    return (((M["body111"]())(l0))(l1))((l2 + 2))
  end
  end
end

M["body111"] = function() -- body ike::debug-token
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'token'
    local l1 -- local 'span'
    local l2 -- local 'indent'
    local l3 -- local 'group'
    local l4 -- local 'parts'
    local l5 -- local 'symbol'
    local l6 -- local 'ident'
    local l7 -- local 's'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body3"]())(((M["body108"]())(l2))(" "))
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "group" and true then -- match arm
        l3 = v.value -- pattern binding assign
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body5"]())(toString("group `", true)..toString(l3["delimiter"], true)..toString("` ", true)..toString(l1, true)..toString("", true))
          block_result2 = ((M["body109"]())((M["body110"]())(l2)))(l3["contents"])
          local block_result3 -- block result
          do -- block
          end
          block_result2 = block_result3
        end
        match_result1 = block_result2
      elseif v.tag == "format" and true then -- match arm
        l4 = v.value -- pattern binding assign
        local block_result4 -- block result
        do -- block
          block_result4 = (M["body5"]())(toString("format ", true)..toString(l1, true)..toString("", true))
          block_result4 = ((M["body112"]())((M["body113"]())(l2)))(l4)
          local block_result5 -- block result
          do -- block
          end
          block_result4 = block_result5
        end
        match_result1 = block_result4
      elseif v.tag == "symbol" and true then -- match arm
        l5 = v.value -- pattern binding assign
        match_result1 = (M["body5"]())(toString("symbol `", true)..toString(l5, true)..toString("` ", true)..toString(l1, true)..toString("", true))
      elseif v.tag == "ident" and true then -- match arm
        l6 = v.value -- pattern binding assign
        match_result1 = (M["body5"]())(toString("ident `", true)..toString(l6, true)..toString("` ", true)..toString(l1, true)..toString("", true))
      elseif v.tag == "integer" and true then -- match arm
        l7 = v.value -- pattern binding assign
        match_result1 = (M["body5"]())(toString("integer `", true)..toString(l7, true)..toString("` ", true)..toString(l1, true)..toString("", true))
      elseif v.tag == "whitespace" then -- match arm
        match_result1 = (M["body5"]())(toString("whitespace ", true)..toString(l1, true)..toString("", true))
      elseif v.tag == "newline" then -- match arm
        match_result1 = (M["body5"]())(toString("newline ", true)..toString(l1, true)..toString("", true))
      elseif v.tag == "error" then -- match arm
        match_result1 = (M["body5"]())(toString("error ", true)..toString(l1, true)..toString("", true))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body112"] = function() -- body std::list::map
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
        match_result1 = { __list = true, (l0)(l3), ((M["body112"]())(l0))(l2) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body113"] = function() -- body ike::debug-token::{lambda}
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
          block_result2 = (M["body3"]())(((M["body108"]())((l2 + 2)))(" "))
          block_result2 = (M["body5"]())(toString("format-string '", true)..toString(l1, true)..toString("'", true))
        end
        match_result1 = block_result2
      elseif v.tag == "tokens" and true then -- match arm
        l3 = v.value -- pattern binding assign
        local block_result3 -- block result
        do -- block
          block_result3 = (M["body3"]())(((M["body108"]())((l2 + 2)))(" "))
          block_result3 = (M["body5"]())("format-tokens")
          block_result3 = ((M["body109"]())((M["body114"]())(l2)))(l3)
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

M["body114"] = function() -- body ike::debug-token::{lambda}::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 't'
    local l1 -- local 's'
    local l2 -- local 'indent'
    l2 = p0 -- pattern binding assign
    local t0 = p1 -- tuple pattern assign
    l0 = t0[1] -- pattern binding assign
    l1 = t0[2] -- pattern binding assign
    return (((M["body111"]())(l0))(l1))((l2 + 4))
  end
  end
end

M["body115"] = function() -- body std::debug::print
  return function(p0)
    local l0 -- local 'value'
    l0 = p0 -- pattern binding assign
    return (M["body5"]())((M["body4"]())(l0))
  end
end

M["body116"] = function() -- body std::list::map
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
        match_result1 = { __list = true, (l0)(l3), ((M["body116"]())(l0))(l2) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body117"] = function() -- body std::debug::print
  return function(p0)
    local l0 -- local 'value'
    l0 = p0 -- pattern binding assign
    return (M["body5"]())((M["body118"]())(l0))
  end
end

M["body118"] = function() -- extern std::debug::format
    return E["std::debug::format"]()
end

coroutine.resume(coroutine.create(M["body0"]))
