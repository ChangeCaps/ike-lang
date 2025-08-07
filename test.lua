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
    if no_quote_strings then
      return value
    end

    value = value:gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")

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
    local l1 -- local 'ts'
    local l2 -- local 'diagnostics'
    local block_result0 -- block result
    do -- block
      l0 = (M["body1"]())("ike/parse/tokenize.ike") -- pattern binding assign
      block_result0 = nil
      local t1 = ((M["body2"]())(l0))((M["body95"]())((M["body101"]())(l0))) -- tuple pattern assign
      l1 = t1[1] -- pattern binding assign
      l2 = t1[2] -- pattern binding assign
      block_result0 = nil
      block_result0 = (M["body97"]())((((M["body103"]())(""))(M["body21"]()))(((M["body104"]())(M["body105"]()))(l2)))
      block_result0 = (M["body126"]())(l1)
    end
    return block_result0
end

M["body1"] = function() -- body ike::file::new
  return function(p0)
    local l0 -- local 'path'
    l0 = p0 -- pattern binding assign
    return { ["path"] = l0 }
  end
end

M["body2"] = function() -- body ike::parse::tokenize
  return function(p0)
  return function(p1)
    local l0 -- local 'file'
    local l1 -- local 'contents'
    local l2 -- local 'lexer'
    local l3 -- local 'ts'
    local l4 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = { ["diagnostics"] = { __list = true }, ["graphs"] = (M["body3"]())(l1), ["file"] = l0, ["offset"] = 0, ["format"] = { __list = true } } -- pattern binding assign
      block_result0 = nil
      local t1 = ((M["body4"]())({ __list = true }))(l2) -- tuple pattern assign
      l3 = t1[1] -- pattern binding assign
      l4 = t1[2] -- pattern binding assign
      block_result0 = nil
      block_result0 = { __tuple = true, (M["body93"]())(l3), l4["diagnostics"] }
    end
    return block_result0
  end
  end
end

M["body3"] = function() -- extern std::string::graphemes
    return E["std::string::graphemes"]()
end

M["body4"] = function() -- body ike::parse::lexer::lex
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'lexer'
    local l2 -- local 'g'
    local l3 -- local 'g'
    local l4 -- local 'f'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body5"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "none" then -- match arm
        match_result1 = M["body9"]()
      elseif v.tag == "some" and true then -- match arm
        l2 = v.value -- pattern binding assign
        local block_result2 -- block result
        do -- block
          local v = { __tuple = true, l2, (M["body5"]())((M["body12"]())(l1)) } -- match target
          local match_result3 -- match result
          if ("\"" == v[1]) and true then -- match arm
            local t4 = v -- tuple pattern assign
            match_result3 = M["body14"]()
          elseif ("{" == v[1]) and true then -- match arm
            local t5 = v -- tuple pattern assign
            match_result3 = M["body31"]()
          elseif ("}" == v[1]) and true then -- match arm
            local t6 = v -- tuple pattern assign
            match_result3 = M["body35"]()
          elseif ("0" == v[1]) and true then -- match arm
            local t7 = v -- tuple pattern assign
            match_result3 = M["body37"]()
          elseif ("1" == v[1]) and true then -- match arm
            local t8 = v -- tuple pattern assign
            match_result3 = M["body37"]()
          elseif ("2" == v[1]) and true then -- match arm
            local t9 = v -- tuple pattern assign
            match_result3 = M["body37"]()
          elseif ("3" == v[1]) and true then -- match arm
            local t10 = v -- tuple pattern assign
            match_result3 = M["body37"]()
          elseif ("4" == v[1]) and true then -- match arm
            local t11 = v -- tuple pattern assign
            match_result3 = M["body37"]()
          elseif ("5" == v[1]) and true then -- match arm
            local t12 = v -- tuple pattern assign
            match_result3 = M["body37"]()
          elseif ("6" == v[1]) and true then -- match arm
            local t13 = v -- tuple pattern assign
            match_result3 = M["body37"]()
          elseif ("7" == v[1]) and true then -- match arm
            local t14 = v -- tuple pattern assign
            match_result3 = M["body37"]()
          elseif ("8" == v[1]) and true then -- match arm
            local t15 = v -- tuple pattern assign
            match_result3 = M["body37"]()
          elseif ("9" == v[1]) and true then -- match arm
            local t16 = v -- tuple pattern assign
            match_result3 = M["body37"]()
          elseif ("/" == v[1]) and v[2].tag == "some" and ("/" == v[2].value) then -- match arm
            local t17 = v -- tuple pattern assign
            match_result3 = M["body41"]()
          elseif ("." == v[1]) and v[2].tag == "some" and ("." == v[2].value) then -- match arm
            local t18 = v -- tuple pattern assign
            match_result3 = ((M["body44"]())(".."))(M["body45"]())
          elseif ("-" == v[1]) and v[2].tag == "some" and (">" == v[2].value) then -- match arm
            local t19 = v -- tuple pattern assign
            match_result3 = ((M["body44"]())("->"))(M["body46"]())
          elseif ("<" == v[1]) and v[2].tag == "some" and ("-" == v[2].value) then -- match arm
            local t20 = v -- tuple pattern assign
            match_result3 = ((M["body44"]())("<-"))(M["body47"]())
          elseif (":" == v[1]) and v[2].tag == "some" and (":" == v[2].value) then -- match arm
            local t21 = v -- tuple pattern assign
            match_result3 = ((M["body44"]())("::"))(M["body48"]())
          elseif ("=" == v[1]) and v[2].tag == "some" and ("=" == v[2].value) then -- match arm
            local t22 = v -- tuple pattern assign
            match_result3 = ((M["body44"]())("=="))(M["body49"]())
          elseif ("!" == v[1]) and v[2].tag == "some" and ("=" == v[2].value) then -- match arm
            local t23 = v -- tuple pattern assign
            match_result3 = ((M["body44"]())("!="))(M["body50"]())
          elseif ("<" == v[1]) and v[2].tag == "some" and ("=" == v[2].value) then -- match arm
            local t24 = v -- tuple pattern assign
            match_result3 = ((M["body44"]())("<="))(M["body51"]())
          elseif (">" == v[1]) and v[2].tag == "some" and ("=" == v[2].value) then -- match arm
            local t25 = v -- tuple pattern assign
            match_result3 = ((M["body44"]())(">="))(M["body52"]())
          elseif ("<" == v[1]) and v[2].tag == "some" and ("|" == v[2].value) then -- match arm
            local t26 = v -- tuple pattern assign
            match_result3 = ((M["body44"]())("<|"))(M["body53"]())
          elseif ("|" == v[1]) and v[2].tag == "some" and (">" == v[2].value) then -- match arm
            local t27 = v -- tuple pattern assign
            match_result3 = ((M["body44"]())("|>"))(M["body54"]())
          elseif ("(" == v[1]) and true then -- match arm
            local t28 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body55"]())
          elseif (")" == v[1]) and true then -- match arm
            local t29 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body56"]())
          elseif ("[" == v[1]) and true then -- match arm
            local t30 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body57"]())
          elseif ("]" == v[1]) and true then -- match arm
            local t31 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body58"]())
          elseif (";" == v[1]) and true then -- match arm
            local t32 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body59"]())
          elseif (":" == v[1]) and true then -- match arm
            local t33 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body60"]())
          elseif ("," == v[1]) and true then -- match arm
            local t34 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body61"]())
          elseif ("." == v[1]) and true then -- match arm
            local t35 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body62"]())
          elseif ("#" == v[1]) and true then -- match arm
            local t36 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body63"]())
          elseif ("_" == v[1]) and true then -- match arm
            local t37 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body64"]())
          elseif ("+" == v[1]) and true then -- match arm
            local t38 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body65"]())
          elseif ("-" == v[1]) and true then -- match arm
            local t39 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body66"]())
          elseif ("*" == v[1]) and true then -- match arm
            local t40 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body67"]())
          elseif ("/" == v[1]) and true then -- match arm
            local t41 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body68"]())
          elseif ("\\" == v[1]) and true then -- match arm
            local t42 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body69"]())
          elseif ("%" == v[1]) and true then -- match arm
            local t43 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body70"]())
          elseif ("&" == v[1]) and true then -- match arm
            local t44 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body71"]())
          elseif ("|" == v[1]) and true then -- match arm
            local t45 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body72"]())
          elseif ("?" == v[1]) and true then -- match arm
            local t46 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body73"]())
          elseif ("'" == v[1]) and true then -- match arm
            local t47 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body74"]())
          elseif ("=" == v[1]) and true then -- match arm
            local t48 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body75"]())
          elseif ("~" == v[1]) and true then -- match arm
            local t49 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body76"]())
          elseif ("<" == v[1]) and true then -- match arm
            local t50 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body77"]())
          elseif (">" == v[1]) and true then -- match arm
            local t51 = v -- tuple pattern assign
            match_result3 = ((M["body32"]())(l2))(M["body78"]())
          elseif (" " == v[1]) and true then -- match arm
            local t52 = v -- tuple pattern assign
            match_result3 = M["body79"]()
          elseif ("\t" == v[1]) and true then -- match arm
            local t53 = v -- tuple pattern assign
            match_result3 = M["body79"]()
          elseif ("\r" == v[1]) and true then -- match arm
            local t54 = v -- tuple pattern assign
            match_result3 = M["body79"]()
          elseif ("\n" == v[1]) and true then -- match arm
            local t55 = v -- tuple pattern assign
            match_result3 = M["body82"]()
          elseif true and true then -- match arm
            local t56 = v -- tuple pattern assign
            l3 = t56[1] -- pattern binding assign
            local block_result57 -- block result
            do -- block
              local v = (M["body84"]())(l3) -- match target
              local match_result58 -- match result
              if (true == v) then -- match arm
                match_result58 = M["body88"]()
              elseif (false == v) then -- match arm
                match_result58 = (M["body91"]())(l3)
              end
              block_result57 = match_result58
            end
            match_result3 = block_result57
          end
          block_result2 = match_result3
        end
        match_result1 = block_result2
      end
      l4 = match_result1 -- pattern binding assign
      block_result0 = nil
      block_result0 = ((l4)(l0))(l1)
    end
    return block_result0
  end
  end
end

M["body5"] = function() -- body ike::parse::lexer::peek
  return function(p0)
    local l0 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    return (M["body6"]())(l0["graphs"])
  end
end

M["body6"] = function() -- body std::list::first
  return function(p0)
    local l0 -- local 'xs'
    local l1 -- local 'x'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = M["body7"]()
      elseif #v > 0 and true and true then -- match arm
        l1 = (v)[1] -- pattern binding assign
        match_result1 = (M["body8"]())(l1)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body7"] = function() -- body none
    return { tag = "none" }
end

M["body8"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body9"] = function() -- body ike::parse::lexer::eof
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'lexer'
    local l2 -- local 'span'
    local l3 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = ((M["body10"]())(0))(l1) -- pattern binding assign
      block_result0 = nil
      l3 = { __list = true, { __tuple = true, M["body11"](), l2 }, l0 } -- pattern binding assign
      block_result0 = nil
      block_result0 = { __tuple = true, l3, l1 }
    end
    return block_result0
  end
  end
end

M["body10"] = function() -- body ike::parse::lexer::span
  return function(p0)
  return function(p1)
    local l0 -- local 'len'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["file"] = l1["file"], ["start"] = l1["offset"], ["end"] = (l1["offset"] + l0) }
    end
    return block_result0
  end
  end
end

M["body11"] = function() -- body token::end-of-file
    return { tag = "token::end-of-file" }
end

M["body12"] = function() -- body ike::parse::lexer::advance
  return function(p0)
    local l0 -- local 'lexer'
    local l1 -- local 'graphs'
    local l2 -- local 'g'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0["graphs"] -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = l0
      elseif #v > 0 and true and true then -- match arm
        l2 = (v)[1] -- pattern binding assign
        l1 = (v)[2] -- pattern binding assign
        local block_result2 -- block result
        do -- block
          block_result2 = { ["diagnostics"] = l0["diagnostics"], ["graphs"] = l1, ["file"] = l0["file"], ["offset"] = (l0["offset"] + (M["body13"]())(l2)), ["format"] = l0["format"] }
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body13"] = function() -- extern std::string::len
    return E["std::string::len"]()
end

M["body14"] = function() -- body ike::parse::lexer::lex::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((((M["body15"]())(l1["offset"]))(true))(""))(l0))((M["body12"]())(l1))
    end
    return block_result0
  end
  end
end

M["body15"] = function() -- body ike::parse::lexer::string
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
  return function(p4)
    local l0 -- local 'start'
    local l1 -- local 'is-quote'
    local l2 -- local 's'
    local l3 -- local 'ts'
    local l4 -- local 'lexer'
    local l5 -- local 'g'
    local l6 -- local 'span'
    local l7 -- local 'diagnostic'
    local l8 -- local 'g'
    local l9 -- local 's'
    local l10 -- local 'span'
    local l11 -- local 'diagnostic'
    local l12 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    l4 = p4 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body5"]())(l4) -- match target
      local match_result1 -- match result
      if v.tag == "some" and true then -- match arm
        l5 = v.value -- pattern binding assign
        local block_result2 -- block result
        do -- block
          local v = { __tuple = true, l5, (M["body5"]())((M["body12"]())(l4)) } -- match target
          local match_result3 -- match result
          if ("\"" == v[1]) and true then -- match arm
            local t4 = v -- tuple pattern assign
            local v = l1 -- match target
            local match_result5 -- match result
            if (true == v) then -- match arm
              match_result5 = ((((((M["body16"]())(false))(l0))(l2))(M["body18"]()))(l3))(l4)
            elseif (false == v) then -- match arm
              match_result5 = ((((((M["body16"]())(false))(l0))(l2))(M["body19"]()))(l3))(l4)
            end
            match_result3 = match_result5
          elseif ("{" == v[1]) and v[2].tag == "some" and ("{" == v[2].value) then -- match arm
            local t6 = v -- tuple pattern assign
            match_result3 = ((((((M["body20"]())(l0))(l1))(l2))("{"))(l3))(l4)
          elseif ("}" == v[1]) and v[2].tag == "some" and ("}" == v[2].value) then -- match arm
            local t7 = v -- tuple pattern assign
            match_result3 = ((((((M["body20"]())(l0))(l1))(l2))("}"))(l3))(l4)
          elseif ("\\" == v[1]) and v[2].tag == "some" and ("\"" == v[2].value) then -- match arm
            local t8 = v -- tuple pattern assign
            match_result3 = ((((((M["body20"]())(l0))(l1))(l2))("\""))(l3))(l4)
          elseif ("\\" == v[1]) and v[2].tag == "some" and ("\\" == v[2].value) then -- match arm
            local t9 = v -- tuple pattern assign
            match_result3 = ((((((M["body20"]())(l0))(l1))(l2))("\\"))(l3))(l4)
          elseif ("\\" == v[1]) and v[2].tag == "some" and ("n" == v[2].value) then -- match arm
            local t10 = v -- tuple pattern assign
            match_result3 = ((((((M["body20"]())(l0))(l1))(l2))("\n"))(l3))(l4)
          elseif ("\\" == v[1]) and v[2].tag == "some" and ("r" == v[2].value) then -- match arm
            local t11 = v -- tuple pattern assign
            match_result3 = ((((((M["body20"]())(l0))(l1))(l2))("\r"))(l3))(l4)
          elseif ("\\" == v[1]) and v[2].tag == "some" and ("t" == v[2].value) then -- match arm
            local t12 = v -- tuple pattern assign
            match_result3 = ((((((M["body20"]())(l0))(l1))(l2))("\t"))(l3))(l4)
          elseif ("{" == v[1]) and true then -- match arm
            local t13 = v -- tuple pattern assign
            local v = l1 -- match target
            local match_result14 -- match result
            if (true == v) then -- match arm
              match_result14 = ((((((M["body16"]())(true))(l0))(l2))(M["body23"]()))(l3))(l4)
            elseif (false == v) then -- match arm
              match_result14 = ((((((M["body16"]())(true))(l0))(l2))(M["body24"]()))(l3))(l4)
            end
            match_result3 = match_result14
          elseif ("}" == v[1]) and true then -- match arm
            local t15 = v -- tuple pattern assign
            local block_result16 -- block result
            do -- block
              l6 = { ["file"] = l4["file"], ["start"] = l4["offset"], ["end"] = (l4["offset"] + (M["body13"]())("}")) } -- pattern binding assign
              block_result16 = nil
              l7 = (((M["body25"]())(l6))("found here"))((M["body26"]())("unexpected closing brace")) -- pattern binding assign
              block_result16 = nil
              block_result16 = (((((M["body15"]())(l0))(l1))(l2))(l3))(((M["body29"]())(l7))((M["body12"]())(l4)))
            end
            match_result3 = block_result16
          elseif true and true then -- match arm
            local t17 = v -- tuple pattern assign
            l8 = t17[1] -- pattern binding assign
            local block_result18 -- block result
            do -- block
              l9 = ((M["body21"]())(l8))(l2) -- pattern binding assign
              block_result18 = nil
              block_result18 = (((((M["body15"]())(l0))(l1))(l9))(l3))((M["body12"]())(l4))
            end
            match_result3 = block_result18
          end
          block_result2 = match_result3
        end
        match_result1 = block_result2
      elseif v.tag == "none" then -- match arm
        local block_result19 -- block result
        do -- block
          l10 = { ["file"] = l4["file"], ["start"] = l0, ["end"] = (l0 + (M["body13"]())("\"")) } -- pattern binding assign
          block_result19 = nil
          l11 = (((M["body25"]())(l10))("starting here"))((M["body26"]())("expected end of string")) -- pattern binding assign
          block_result19 = nil
          l12 = { __list = true, { __tuple = true, M["body30"](), l10 }, l3 } -- pattern binding assign
          block_result19 = nil
          block_result19 = ((M["body4"]())(l12))(l4)
        end
        match_result1 = block_result19
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

M["body16"] = function() -- body ike::parse::lexer::end-string
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
  return function(p4)
  return function(p5)
    local l0 -- local 'is-format'
    local l1 -- local 'start'
    local l2 -- local 's'
    local l3 -- local 'f'
    local l4 -- local 'ts'
    local l5 -- local 'lexer'
    local l6 -- local 'lexer'
    local l7 -- local 'span'
    local l8 -- local 'lexer'
    local l9 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    l4 = p4 -- pattern binding assign
    l5 = p5 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l6 = (M["body12"]())(l5) -- pattern binding assign
      block_result0 = nil
      l7 = { ["file"] = l6["file"], ["start"] = l1, ["end"] = l6["offset"] } -- pattern binding assign
      block_result0 = nil
      local v = l0 -- match target
      local match_result1 -- match result
      if (true == v) then -- match arm
        match_result1 = ((M["body17"]())(l7))(l6)
      elseif (false == v) then -- match arm
        match_result1 = l6
      end
      l8 = match_result1 -- pattern binding assign
      block_result0 = nil
      l9 = { __list = true, { __tuple = true, (l3)(l2), l7 }, l4 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body4"]())(l9))(l8)
    end
    return block_result0
  end
  end
  end
  end
  end
  end
end

M["body17"] = function() -- body ike::parse::lexer::with-format
  return function(p0)
  return function(p1)
    local l0 -- local 'span'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["diagnostics"] = l1["diagnostics"], ["graphs"] = l1["graphs"], ["file"] = l1["file"], ["offset"] = l1["offset"], ["format"] = { __list = true, { __tuple = true, 0, l0 }, l1["format"] } }
    end
    return block_result0
  end
  end
end

M["body18"] = function() -- body token::string
  return function(p0)
    local l0 -- local 'string'
    l0 = p0 -- pattern binding assign
    return { tag = "token::string", value = l0 }
  end
end

M["body19"] = function() -- body token::format-end
  return function(p0)
    local l0 -- local 'format-end'
    l0 = p0 -- pattern binding assign
    return { tag = "token::format-end", value = l0 }
  end
end

M["body20"] = function() -- body ike::parse::lexer::string-escape
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
  return function(p4)
  return function(p5)
    local l0 -- local 'start'
    local l1 -- local 'is-quote'
    local l2 -- local 's'
    local l3 -- local 'g'
    local l4 -- local 'ts'
    local l5 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    l4 = p4 -- pattern binding assign
    l5 = p5 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((((M["body15"]())(l0))(l1))(((M["body21"]())(l3))(l2)))(l4))((M["body12"]())((M["body12"]())(l5)))
    end
    return block_result0
  end
  end
  end
  end
  end
  end
end

M["body21"] = function() -- body std::string::append
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
    local l1 -- local 'b'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    return ((M["body22"]())(l1))(l0)
  end
  end
end

M["body22"] = function() -- extern std::string::prepend
    return E["std::string::prepend"]()
end

M["body23"] = function() -- body token::format-start
  return function(p0)
    local l0 -- local 'format-start'
    l0 = p0 -- pattern binding assign
    return { tag = "token::format-start", value = l0 }
  end
end

M["body24"] = function() -- body token::format-continue
  return function(p0)
    local l0 -- local 'format-continue'
    l0 = p0 -- pattern binding assign
    return { tag = "token::format-continue", value = l0 }
  end
end

M["body25"] = function() -- body ike::diagnostic::with-label
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
      l3 = { ["span"] = l0, ["message"] = (M["body8"]())(l1) } -- pattern binding assign
      block_result0 = nil
      block_result0 = { ["level"] = l2["level"], ["message"] = l2["message"], ["labels"] = { __list = true, l3, l2["labels"] } }
    end
    return block_result0
  end
  end
  end
end

M["body26"] = function() -- body ike::diagnostic::error
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body27"]())(M["body28"]()))(l0)
    end
    return block_result0
  end
end

M["body27"] = function() -- body ike::diagnostic
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

M["body28"] = function() -- body level::error
    return { tag = "level::error" }
end

M["body29"] = function() -- body ike::parse::lexer::with-diagnostic
  return function(p0)
  return function(p1)
    local l0 -- local 'diagnostic'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["diagnostics"] = { __list = true, l0, l1["diagnostics"] }, ["graphs"] = l1["graphs"], ["file"] = l1["file"], ["offset"] = l1["offset"], ["format"] = l1["format"] }
    end
    return block_result0
  end
  end
end

M["body30"] = function() -- body token::error
    return { tag = "token::error" }
end

M["body31"] = function() -- body ike::parse::lexer::open-brace
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'lexer'
    local l2 -- local 'fs'
    local l3 -- local 'opens'
    local l4 -- local 'format-span'
    local l5 -- local 'span'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l1["format"] -- match target
      local match_result1 -- match result
      if #v > 0 and true and true and true then -- match arm
        local t2 = (v)[1] -- tuple pattern assign
        l3 = t2[1] -- pattern binding assign
        l4 = t2[2] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        local block_result3 -- block result
        do -- block
          l5 = ((M["body10"]())((M["body13"]())("{")))(l1) -- pattern binding assign
          block_result3 = nil
          block_result3 = ((((M["body32"]())("{"))(M["body33"]()))(l0))(((M["body34"]())({ __list = true, { __tuple = true, (l3 + 1), l4 }, l2 }))(l1))
        end
        match_result1 = block_result3
      elseif #v == 0 then -- match arm
        match_result1 = ((((M["body32"]())("{"))(M["body33"]()))(l0))(l1)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body32"] = function() -- body ike::parse::lexer::one-symbol
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 's'
    local l1 -- local 't'
    local l2 -- local 'ts'
    local l3 -- local 'lexer'
    local l4 -- local 'span'
    local l5 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l4 = ((M["body10"]())((M["body13"]())(l0)))(l3) -- pattern binding assign
      block_result0 = nil
      l5 = { __list = true, { __tuple = true, l1, l4 }, l2 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body4"]())(l5))((M["body12"]())(l3))
    end
    return block_result0
  end
  end
  end
  end
end

M["body33"] = function() -- body token::open-brace
    return { tag = "token::open-brace" }
end

M["body34"] = function() -- body ike::parse::lexer::with-formats
  return function(p0)
  return function(p1)
    local l0 -- local 'formats'
    local l1 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["diagnostics"] = l1["diagnostics"], ["graphs"] = l1["graphs"], ["file"] = l1["file"], ["offset"] = l1["offset"], ["format"] = l0 }
    end
    return block_result0
  end
  end
end

M["body35"] = function() -- body ike::parse::lexer::close-brace
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'lexer'
    local l2 -- local 'fs'
    local l3 -- local 'fs'
    local l4 -- local 'opens'
    local l5 -- local 'format-span'
    local l6 -- local 'span'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l1["format"] -- match target
      local match_result1 -- match result
      if #v > 0 and (0 == (v)[1][1]) and true and true then -- match arm
        local t2 = (v)[1] -- tuple pattern assign
        l2 = (v)[2] -- pattern binding assign
        local block_result3 -- block result
        do -- block
          block_result3 = (((((M["body15"]())(l1["offset"]))(false))(""))(l0))(((M["body34"]())(l2))((M["body12"]())(l1)))
        end
        match_result1 = block_result3
      elseif #v > 0 and true and true and true then -- match arm
        local t4 = (v)[1] -- tuple pattern assign
        l4 = t4[1] -- pattern binding assign
        l5 = t4[2] -- pattern binding assign
        l3 = (v)[2] -- pattern binding assign
        local block_result5 -- block result
        do -- block
          l6 = ((M["body10"]())((M["body13"]())("}")))(l1) -- pattern binding assign
          block_result5 = nil
          block_result5 = ((((M["body32"]())("}"))(M["body36"]()))(l0))(((M["body34"]())({ __list = true, { __tuple = true, (l4 - 1), l5 }, l3 }))(l1))
        end
        match_result1 = block_result5
      elseif #v == 0 then -- match arm
        match_result1 = ((((M["body32"]())("}"))(M["body36"]()))(l0))(l1)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body36"] = function() -- body token::close-brace
    return { tag = "token::close-brace" }
end

M["body37"] = function() -- body ike::parse::lexer::number
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'lexer'
    local l2 -- local 'num'
    local l3 -- local 'lexer''
    local l4 -- local 'span'
    local l5 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = ((M["body38"]())(M["body39"]()))(l1) -- tuple pattern assign
      l2 = t1[1] -- pattern binding assign
      l3 = t1[2] -- pattern binding assign
      block_result0 = nil
      l4 = ((M["body10"]())((M["body13"]())(l2)))(l1) -- pattern binding assign
      block_result0 = nil
      l5 = { __list = true, { __tuple = true, (M["body40"]())(l2), l4 }, l0 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body4"]())(l5))(l3)
    end
    return block_result0
  end
  end
end

M["body38"] = function() -- body ike::parse::lexer::take-while
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'lexer'
    local l2 -- local 'g'
    local l3 -- local 's'
    local l4 -- local 'lexer'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body5"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "none" then -- match arm
        match_result1 = { __tuple = true, "", l1 }
      elseif v.tag == "some" and true then -- match arm
        l2 = v.value -- pattern binding assign
        local block_result2 -- block result
        do -- block
          local v = (l0)(l2) -- match target
          local match_result3 -- match result
          if (false == v) then -- match arm
            match_result3 = { __tuple = true, "", l1 }
          elseif (true == v) then -- match arm
            local block_result4 -- block result
            do -- block
              local t5 = ((M["body38"]())(l0))((M["body12"]())(l1)) -- tuple pattern assign
              l3 = t5[1] -- pattern binding assign
              l4 = t5[2] -- pattern binding assign
              block_result4 = nil
              block_result4 = { __tuple = true, ((M["body22"]())(l2))(l3), l4 }
            end
            match_result3 = block_result4
          end
          block_result2 = match_result3
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body39"] = function() -- body ike::parse::lexer::is-digit
  return function(p0)
    local l0 -- local 'g'
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

M["body40"] = function() -- body token::integer
  return function(p0)
    local l0 -- local 'integer'
    l0 = p0 -- pattern binding assign
    return { tag = "token::integer", value = l0 }
  end
end

M["body41"] = function() -- body ike::parse::lexer::comment
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'lexer'
    local l2 -- local 'comment'
    local l3 -- local 'lexer''
    local l4 -- local 'span'
    local l5 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = ((M["body38"]())(M["body42"]()))(l1) -- tuple pattern assign
      l2 = t1[1] -- pattern binding assign
      l3 = t1[2] -- pattern binding assign
      block_result0 = nil
      l4 = ((M["body10"]())((M["body13"]())(l2)))(l1) -- pattern binding assign
      block_result0 = nil
      l5 = { __list = true, { __tuple = true, (M["body43"]())(l2), l4 }, l0 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body4"]())(l5))((M["body12"]())(l3))
    end
    return block_result0
  end
  end
end

M["body42"] = function() -- body ike::parse::lexer::comment::{lambda}
  return function(p0)
    local l0 -- local 'g'
    l0 = p0 -- pattern binding assign
    return (not equal(l0, "\n"))
  end
end

M["body43"] = function() -- body token::comment
  return function(p0)
    local l0 -- local 'comment'
    l0 = p0 -- pattern binding assign
    return { tag = "token::comment", value = l0 }
  end
end

M["body44"] = function() -- body ike::parse::lexer::two-symbol
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 's'
    local l1 -- local 't'
    local l2 -- local 'ts'
    local l3 -- local 'lexer'
    local l4 -- local 'span'
    local l5 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l4 = ((M["body10"]())((M["body13"]())(l0)))(l3) -- pattern binding assign
      block_result0 = nil
      l5 = { __list = true, { __tuple = true, l1, l4 }, l2 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body4"]())(l5))((M["body12"]())((M["body12"]())(l3)))
    end
    return block_result0
  end
  end
  end
  end
end

M["body45"] = function() -- body token::dotdot
    return { tag = "token::dotdot" }
end

M["body46"] = function() -- body token::rarrow
    return { tag = "token::rarrow" }
end

M["body47"] = function() -- body token::larrow
    return { tag = "token::larrow" }
end

M["body48"] = function() -- body token::coloncolon
    return { tag = "token::coloncolon" }
end

M["body49"] = function() -- body token::eqeq
    return { tag = "token::eqeq" }
end

M["body50"] = function() -- body token::noteq
    return { tag = "token::noteq" }
end

M["body51"] = function() -- body token::lteq
    return { tag = "token::lteq" }
end

M["body52"] = function() -- body token::gteq
    return { tag = "token::gteq" }
end

M["body53"] = function() -- body token::ltpipe
    return { tag = "token::ltpipe" }
end

M["body54"] = function() -- body token::pipegt
    return { tag = "token::pipegt" }
end

M["body55"] = function() -- body token::open-paren
    return { tag = "token::open-paren" }
end

M["body56"] = function() -- body token::close-paren
    return { tag = "token::close-paren" }
end

M["body57"] = function() -- body token::open-bracket
    return { tag = "token::open-bracket" }
end

M["body58"] = function() -- body token::close-bracket
    return { tag = "token::close-bracket" }
end

M["body59"] = function() -- body token::semi
    return { tag = "token::semi" }
end

M["body60"] = function() -- body token::colon
    return { tag = "token::colon" }
end

M["body61"] = function() -- body token::comma
    return { tag = "token::comma" }
end

M["body62"] = function() -- body token::dot
    return { tag = "token::dot" }
end

M["body63"] = function() -- body token::pound
    return { tag = "token::pound" }
end

M["body64"] = function() -- body token::under
    return { tag = "token::under" }
end

M["body65"] = function() -- body token::plus
    return { tag = "token::plus" }
end

M["body66"] = function() -- body token::minus
    return { tag = "token::minus" }
end

M["body67"] = function() -- body token::star
    return { tag = "token::star" }
end

M["body68"] = function() -- body token::slash
    return { tag = "token::slash" }
end

M["body69"] = function() -- body token::backslash
    return { tag = "token::backslash" }
end

M["body70"] = function() -- body token::percent
    return { tag = "token::percent" }
end

M["body71"] = function() -- body token::amp
    return { tag = "token::amp" }
end

M["body72"] = function() -- body token::pipe
    return { tag = "token::pipe" }
end

M["body73"] = function() -- body token::question
    return { tag = "token::question" }
end

M["body74"] = function() -- body token::quote
    return { tag = "token::quote" }
end

M["body75"] = function() -- body token::eq
    return { tag = "token::eq" }
end

M["body76"] = function() -- body token::tilde
    return { tag = "token::tilde" }
end

M["body77"] = function() -- body token::lt
    return { tag = "token::lt" }
end

M["body78"] = function() -- body token::gt
    return { tag = "token::gt" }
end

M["body79"] = function() -- body ike::parse::lexer::whitespace
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'lexer'
    local l2 -- local 'ws'
    local l3 -- local 'lexer''
    local l4 -- local 'span'
    local l5 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = ((M["body38"]())(M["body80"]()))(l1) -- tuple pattern assign
      l2 = t1[1] -- pattern binding assign
      l3 = t1[2] -- pattern binding assign
      block_result0 = nil
      l4 = ((M["body10"]())((M["body13"]())(l2)))(l1) -- pattern binding assign
      block_result0 = nil
      l5 = { __list = true, { __tuple = true, M["body81"](), l4 }, l0 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body4"]())(l5))(l3)
    end
    return block_result0
  end
  end
end

M["body80"] = function() -- body ike::parse::lexer::is-whitespace
  return function(p0)
    local l0 -- local 'g'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if (" " == v) then -- match arm
        match_result1 = true
      elseif ("\r" == v) then -- match arm
        match_result1 = true
      elseif ("\t" == v) then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body81"] = function() -- body token::whitespace
    return { tag = "token::whitespace" }
end

M["body82"] = function() -- body ike::parse::lexer::newline
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'lexer'
    local l2 -- local 'span'
    local l3 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = ((M["body10"]())((M["body13"]())("\n")))(l1) -- pattern binding assign
      block_result0 = nil
      l3 = { __list = true, { __tuple = true, M["body83"](), l2 }, l0 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body4"]())(l3))((M["body12"]())(l1))
    end
    return block_result0
  end
  end
end

M["body83"] = function() -- body token::newline
    return { tag = "token::newline" }
end

M["body84"] = function() -- body ike::parse::lexer::is-ident-start
  return function(p0)
    local l0 -- local 'g'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body85"]())(l0))((M["body3"]())("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"))
    end
    return block_result0
  end
end

M["body85"] = function() -- body std::list::contains
  return function(p0)
    local l0 -- local 'x'
    l0 = p0 -- pattern binding assign
    return (M["body86"]())((M["body87"]())(l0))
  end
end

M["body86"] = function() -- body std::list::any
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
        match_result1 = ((l0)(l3) or ((M["body86"]())(l0))(l2))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body87"] = function() -- body std::list::contains::{lambda}
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

M["body88"] = function() -- body ike::parse::lexer::ident
  return function(p0)
  return function(p1)
    local l0 -- local 'ts'
    local l1 -- local 'lexer'
    local l2 -- local 'ident'
    local l3 -- local 'lexer''
    local l4 -- local 'span'
    local l5 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = ((M["body38"]())(M["body89"]()))(l1) -- tuple pattern assign
      l2 = t1[1] -- pattern binding assign
      l3 = t1[2] -- pattern binding assign
      block_result0 = nil
      l4 = ((M["body10"]())((M["body13"]())(l2)))(l1) -- pattern binding assign
      block_result0 = nil
      l5 = { __list = true, { __tuple = true, (M["body90"]())(l2), l4 }, l0 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body4"]())(l5))(l3)
    end
    return block_result0
  end
  end
end

M["body89"] = function() -- body ike::parse::lexer::is-ident-continue
  return function(p0)
    local l0 -- local 'g'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body84"]())(l0) or ((M["body39"]())(l0) or (equal(l0, "_") or (equal(l0, "-") or equal(l0, "'")))))
    end
    return block_result0
  end
end

M["body90"] = function() -- body token::ident
  return function(p0)
    local l0 -- local 'ident'
    l0 = p0 -- pattern binding assign
    return { tag = "token::ident", value = l0 }
  end
end

M["body91"] = function() -- body ike::parse::lexer::unexpected-character
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'g'
    local l1 -- local 'ts'
    local l2 -- local 'lexer'
    local l3 -- local 'span'
    local l4 -- local 'diagnostic'
    local l5 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l3 = ((M["body10"]())((M["body13"]())(l0)))(l2) -- pattern binding assign
      block_result0 = nil
      l4 = (((M["body25"]())(l3))("found here"))((M["body26"]())(toString("unexpected character `", true)..toString(l0, true)..toString("`", true))) -- pattern binding assign
      block_result0 = nil
      l5 = { __list = true, { __tuple = true, (M["body92"]())(l0), l3 }, l1 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body4"]())(l5))((M["body12"]())(((M["body29"]())(l4))(l2)))
    end
    return block_result0
  end
  end
  end
end

M["body92"] = function() -- body token::unknown
  return function(p0)
    local l0 -- local 'unknown'
    l0 = p0 -- pattern binding assign
    return { tag = "token::unknown", value = l0 }
  end
end

M["body93"] = function() -- body std::list::reverse
  return function(p0)
    local l0 -- local 'xs'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body94"]())(l0))({ __list = true })
    end
    return block_result0
  end
end

M["body94"] = function() -- body std::list::reverse'
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
        match_result1 = ((M["body94"]())(l2))({ __list = true, l3, l1 })
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body95"] = function() -- body std::result::assert
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
        match_result1 = (M["body96"]())((M["body98"]())(l2))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body96"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body97"]())("thread main panic: `")
      block_result0 = (M["body97"]())((M["body98"]())(l0))
      block_result0 = (M["body99"]())("`")
      block_result0 = (M["body100"]())(1)
    end
    return block_result0
  end
end

M["body97"] = function() -- extern std::io::print
    return E["std::io::print"]()
end

M["body98"] = function() -- extern std::debug::format
    return E["std::debug::format"]()
end

M["body99"] = function() -- body std::io::println
  return function(p0)
    local l0 -- local 's'
    l0 = p0 -- pattern binding assign
    return (M["body97"]())(((M["body21"]())("\n"))(l0))
  end
end

M["body100"] = function() -- extern std::os::exit
    return E["std::os::exit"]()
end

M["body101"] = function() -- body ike::file::read
  return function(p0)
    local l0 -- local 'file'
    l0 = p0 -- pattern binding assign
    return (M["body102"]())(l0["path"])
  end
end

M["body102"] = function() -- extern std::fs::read
    return E["std::fs::read"]()
end

M["body103"] = function() -- body std::list::foldl
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
        match_result1 = (((M["body103"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body104"] = function() -- body std::list::map
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
        match_result1 = { __list = true, (l0)(l3), ((M["body104"]())(l0))(l2) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body105"] = function() -- body ike::diagnostic::format
  return function(p0)
    local l0 -- local 'diagnostic'
    local l1 -- local 'color'
    local l2 -- local 'level'
    local l3 -- local 'indent'
    local l4 -- local 'labels'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0["level"] -- match target
      local match_result1 -- match result
      if v.tag == "level::error" then -- match arm
        match_result1 = { __tuple = true, M["body106"](), "error" }
      elseif v.tag == "level::warning" then -- match arm
        match_result1 = { __tuple = true, M["body107"](), "warning" }
      elseif v.tag == "level::help" then -- match arm
        match_result1 = { __tuple = true, M["body108"](), "note" }
      end
      local t2 = match_result1 -- tuple pattern assign
      l1 = t2[1] -- pattern binding assign
      l2 = t2[2] -- pattern binding assign
      block_result0 = nil
      l3 = (M["body109"]())(l0) -- pattern binding assign
      block_result0 = nil
      local t3 = (((M["body117"]())({ __tuple = true, "", M["body7"]() }))(((M["body118"]())(l1))(l3)))(l0["labels"]) -- tuple pattern assign
      l4 = t3[1] -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body21"]())(l4))(toString("", true)..toString(l1, true)..toString("", true)..toString(l2, true)..toString("", true)..toString(M["body122"](), true)..toString(": ", true)..toString(M["body121"](), true)..toString("", true)..toString(l0["message"], true)..toString("", true)..toString(M["body122"](), true)..toString("\n", true))
    end
    return block_result0
  end
end

M["body106"] = function() -- body ike::ansi::red
    return "\x1b[31m"
end

M["body107"] = function() -- body ike::ansi::yellow
    return "\x1b[33m"
end

M["body108"] = function() -- body ike::ansi::blue
    return "\x1b[34m"
end

M["body109"] = function() -- body ike::diagnostic::indent
  return function(p0)
    local l0 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((M["body110"]())(0))(M["body111"]()))(((M["body112"]())(M["body113"]()))(l0["labels"]))
    end
    return block_result0
  end
end

M["body110"] = function() -- body std::list::foldl
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
        match_result1 = (((M["body110"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body111"] = function() -- body std::math::max
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
    local l1 -- local 'b'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (l0 < l1) -- match target
      local match_result1 -- match result
      if (true == v) then -- match arm
        match_result1 = l1
      elseif (false == v) then -- match arm
        match_result1 = l0
      end
      block_result0 = match_result1
    end
    return block_result0
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

M["body113"] = function() -- body ike::diagnostic::indent::{lambda}
  return function(p0)
    local l0 -- local 'label'
    local l1 -- local 'info'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = ((M["body114"]())(l0["span"]))((M["body95"]())((M["body102"]())(l0["span"]["file"]["path"]))) -- pattern binding assign
      block_result0 = nil
      block_result0 = (M["body13"]())(toString("", true)..toString(l1["line"], true)..toString("", true))
    end
    return block_result0
  end
end

M["body114"] = function() -- body ike::span::info
  return function(p0)
  return function(p1)
    local l0 -- local 'span'
    local l1 -- local 'contents'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((((M["body115"]())(0))(1))(l0))(((M["body116"]())("\n"))(l1))
    end
    return block_result0
  end
  end
end

M["body115"] = function() -- body ike::span::info'
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'start-offset'
    local l1 -- local 'line-count'
    local l2 -- local 'span'
    local l3 -- local 'lines'
    local l4 -- local 'lines'
    local l5 -- local 'line'
    local l6 -- local 'end-offset'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l3 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = { ["line"] = 0, ["column"] = 0 }
      elseif #v > 0 and true and true then -- match arm
        l5 = (v)[1] -- pattern binding assign
        l4 = (v)[2] -- pattern binding assign
        local block_result2 -- block result
        do -- block
          l6 = ((l0 + (M["body13"]())(l5)) + (M["body13"]())("\n")) -- pattern binding assign
          block_result2 = nil
          local v = ((l2["start"] >= l0) and (l2["start"] < l6)) -- match target
          local match_result3 -- match result
          if (true == v) then -- match arm
            match_result3 = { ["line"] = l1, ["column"] = ((l2["start"] - l0) + 1) }
          elseif (false == v) then -- match arm
            match_result3 = ((((M["body115"]())(l6))((l1 + 1)))(l2))(l4)
          end
          block_result2 = match_result3
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

M["body116"] = function() -- extern std::string::split
    return E["std::string::split"]()
end

M["body117"] = function() -- body std::list::foldl
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
        match_result1 = (((M["body117"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body118"] = function() -- body ike::diagnostic::format::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'acc'
    local l1 -- local 'prev'
    local l2 -- local 'label'
    local l3 -- local 'color'
    local l4 -- local 'indent'
    local l5 -- local 's'
    l3 = p0 -- pattern binding assign
    l4 = p1 -- pattern binding assign
    local t0 = p2 -- tuple pattern assign
    l0 = t0[1] -- pattern binding assign
    l1 = t0[2] -- pattern binding assign
    l2 = p3 -- pattern binding assign
    local block_result1 -- block result
    do -- block
      l5 = ((((M["body119"]())(l1))(l4))(l3))(l2) -- pattern binding assign
      block_result1 = nil
      block_result1 = { __tuple = true, ((M["body21"]())(l5))(l0), (M["body8"]())(l2["span"]["file"]["path"]) }
    end
    return block_result1
  end
  end
  end
  end
end

M["body119"] = function() -- body ike::diagnostic::label::format
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'prev'
    local l1 -- local 'indent'
    local l2 -- local 'color'
    local l3 -- local 'label'
    local l4 -- local 'header-indent'
    local l5 -- local 'contents'
    local l6 -- local 'info'
    local l7 -- local 'sep'
    local l8 -- local 'source'
    local l9 -- local 'header'
    local l10 -- local 'line'
    local l11 -- local 'bar'
    local l12 -- local 'number-indent'
    local l13 -- local 'line-number'
    local l14 -- local 'content'
    local l15 -- local 'highlight-offset'
    local l16 -- local 'highlight-len'
    local l17 -- local 'highlight'
    local l18 -- local 'message'
    local l19 -- local 'message'
    local l20 -- local 'label'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l4 = ((M["body120"]())(l1))(" ") -- pattern binding assign
      block_result0 = nil
      l5 = (M["body95"]())((M["body102"]())(l3["span"]["file"]["path"])) -- pattern binding assign
      block_result0 = nil
      l6 = ((M["body114"]())(l3["span"]))(l5) -- pattern binding assign
      block_result0 = nil
      local v = equal(l0, (M["body8"]())(l3["span"]["file"]["path"])) -- match target
      local match_result1 -- match result
      if (true == v) then -- match arm
        match_result1 = toString("", true)..toString(l4, true)..toString("", true)..toString(M["body108"](), true)..toString("", true)..toString(M["body121"](), true)..toString("...", true)..toString(M["body122"](), true)..toString("", true)
      elseif (false == v) then -- match arm
        local block_result2 -- block result
        do -- block
          local v = l0 -- match target
          local match_result3 -- match result
          if v.tag == "some" and true then -- match arm
            match_result3 = ":::"
          elseif v.tag == "none" then -- match arm
            match_result3 = "-->"
          end
          l7 = match_result3 -- pattern binding assign
          block_result2 = nil
          l8 = toString("", true)..toString(l3["span"]["file"]["path"], true)..toString(":", true)..toString(l6["line"], true)..toString(":", true)..toString(l6["column"], true)..toString("", true) -- pattern binding assign
          block_result2 = nil
          block_result2 = toString("", true)..toString(l4, true)..toString("", true)..toString(M["body108"](), true)..toString("", true)..toString(M["body121"](), true)..toString("", true)..toString(l7, true)..toString("", true)..toString(M["body122"](), true)..toString(" ", true)..toString(l8, true)..toString("", true)
        end
        match_result1 = block_result2
      end
      l9 = match_result1 -- pattern binding assign
      block_result0 = nil
      l10 = (M["body123"]())(((M["body124"]())((l6["line"] - 1)))(((M["body116"]())("\n"))(l5))) -- pattern binding assign
      block_result0 = nil
      l11 = toString("", true)..toString(l4, true)..toString(" ", true)..toString(M["body108"](), true)..toString("", true)..toString(M["body121"](), true)..toString("|", true)..toString(M["body122"](), true)..toString("", true) -- pattern binding assign
      block_result0 = nil
      l12 = ((M["body120"]())((l1 - (M["body13"]())(toString("", true)..toString(l6["line"], true)..toString("", true)))))(" ") -- pattern binding assign
      block_result0 = nil
      l13 = toString("", true)..toString(M["body108"](), true)..toString("", true)..toString(M["body121"](), true)..toString("", true)..toString(l6["line"], true)..toString("", true)..toString(l12, true)..toString(" |", true) -- pattern binding assign
      block_result0 = nil
      l14 = toString("", true)..toString(l13, true)..toString("", true)..toString(M["body122"](), true)..toString(" ", true)..toString(l10, true)..toString("", true) -- pattern binding assign
      block_result0 = nil
      l15 = ((M["body120"]())((l6["column"] - 1)))(" ") -- pattern binding assign
      block_result0 = nil
      l16 = ((M["body125"]())((((M["body13"]())(l10) + 1) - l6["column"])))((l3["span"]["end"] - l3["span"]["start"])) -- pattern binding assign
      block_result0 = nil
      l17 = ((M["body120"]())(l16))("^") -- pattern binding assign
      block_result0 = nil
      local v = l3["message"] -- match target
      local match_result4 -- match result
      if v.tag == "some" and true then -- match arm
        l18 = v.value -- pattern binding assign
        match_result4 = l18
      elseif v.tag == "none" then -- match arm
        match_result4 = ""
      end
      l19 = match_result4 -- pattern binding assign
      block_result0 = nil
      l20 = toString("", true)..toString(l11, true)..toString(" ", true)..toString(l15, true)..toString("", true)..toString(l2, true)..toString("", true)..toString(l17, true)..toString(" ", true)..toString(l19, true)..toString("", true)..toString(M["body122"](), true)..toString("", true) -- pattern binding assign
      block_result0 = nil
      block_result0 = toString("", true)..toString(l9, true)..toString("\n", true)..toString(l11, true)..toString("\n", true)..toString(l14, true)..toString("\n", true)..toString(l20, true)..toString("\n", true)..toString(l11, true)..toString("\n", true)
    end
    return block_result0
  end
  end
  end
  end
end

M["body120"] = function() -- body std::string::repeat
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
        match_result1 = ((M["body21"]())(l1))(((M["body120"]())((l0 - 1)))(l1))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body121"] = function() -- body ike::ansi::bold
    return "\x1b[1m"
end

M["body122"] = function() -- body ike::ansi::reset
    return "\x1b[0m"
end

M["body123"] = function() -- body std::option::assert
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
        match_result1 = (M["body96"]())("option was none")
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body124"] = function() -- body std::list::nth
  return function(p0)
  return function(p1)
    local l0 -- local 'n'
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
        match_result1 = M["body7"]()
      elseif #v > 0 and true and true then -- match arm
        l3 = (v)[1] -- pattern binding assign
        l2 = (v)[2] -- pattern binding assign
        local block_result2 -- block result
        do -- block
          local v = l0 -- match target
          local match_result3 -- match result
          if (0 == v) then -- match arm
            match_result3 = (M["body8"]())(l3)
          elseif true then -- match arm
            match_result3 = ((M["body124"]())((l0 - 1)))(l2)
          end
          block_result2 = match_result3
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body125"] = function() -- body std::math::min
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
    local l1 -- local 'b'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (l0 < l1) -- match target
      local match_result1 -- match result
      if (true == v) then -- match arm
        match_result1 = l0
      elseif (false == v) then -- match arm
        match_result1 = l1
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body126"] = function() -- body std::debug::print
  return function(p0)
    local l0 -- local 'value'
    l0 = p0 -- pattern binding assign
    return (M["body99"]())((M["body127"]())(l0))
  end
end

M["body127"] = function() -- extern std::debug::format
    return E["std::debug::format"]()
end

coroutine.resume(coroutine.create(M["body0"]))
