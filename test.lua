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
    local l3 -- local 'ast'
    local block_result0 -- block result
    do -- block
      l0 = (M["body1"]())("ike/parse/tokenize.ike") -- pattern binding assign
      block_result0 = nil
      local t1 = ((M["body2"]())(l0))((M["body105"]())((M["body111"]())(l0))) -- tuple pattern assign
      l1 = t1[1] -- pattern binding assign
      l2 = t1[2] -- pattern binding assign
      block_result0 = nil
      block_result0 = (M["body107"]())((((M["body113"]())(""))(M["body21"]()))(((M["body114"]())(M["body115"]()))(l2)))
      l3 = (M["body136"]())((M["body146"]())((M["body348"]())(l1))) -- pattern binding assign
      block_result0 = nil
      block_result0 = (M["body109"]())((M["body350"]())(l3))
      block_result0 = (M["body107"]())((((M["body113"]())(""))(M["body21"]()))(((M["body114"]())(M["body115"]()))((M["body356"]())(l3))))
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
      block_result0 = { __tuple = true, (M["body103"]())(l3), l4["diagnostics"] }
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
                match_result58 = (M["body101"]())(l3)
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
    local l4 -- local 'token'
    local l5 -- local 'span'
    local l6 -- local 'ts'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = ((M["body38"]())(M["body89"]()))(l1) -- tuple pattern assign
      l2 = t1[1] -- pattern binding assign
      l3 = t1[2] -- pattern binding assign
      block_result0 = nil
      local v = l2 -- match target
      local match_result2 -- match result
      if ("and" == v) then -- match arm
        match_result2 = M["body90"]()
      elseif ("bool" == v) then -- match arm
        match_result2 = M["body91"]()
      elseif ("false" == v) then -- match arm
        match_result2 = M["body92"]()
      elseif ("let" == v) then -- match arm
        match_result2 = M["body93"]()
      elseif ("true" == v) then -- match arm
        match_result2 = M["body94"]()
      elseif ("try" == v) then -- match arm
        match_result2 = M["body95"]()
      elseif ("int" == v) then -- match arm
        match_result2 = M["body96"]()
      elseif ("or" == v) then -- match arm
        match_result2 = M["body97"]()
      elseif ("str" == v) then -- match arm
        match_result2 = M["body98"]()
      elseif ("match" == v) then -- match arm
        match_result2 = M["body99"]()
      elseif true then -- match arm
        match_result2 = (M["body100"]())(l2)
      end
      l4 = match_result2 -- pattern binding assign
      block_result0 = nil
      l5 = ((M["body10"]())((M["body13"]())(l2)))(l1) -- pattern binding assign
      block_result0 = nil
      l6 = { __list = true, { __tuple = true, l4, l5 }, l0 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body4"]())(l6))(l3)
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

M["body90"] = function() -- body token::and_
    return { tag = "token::and_" }
end

M["body91"] = function() -- body token::bool_
    return { tag = "token::bool_" }
end

M["body92"] = function() -- body token::false_
    return { tag = "token::false_" }
end

M["body93"] = function() -- body token::let_
    return { tag = "token::let_" }
end

M["body94"] = function() -- body token::true_
    return { tag = "token::true_" }
end

M["body95"] = function() -- body token::try_
    return { tag = "token::try_" }
end

M["body96"] = function() -- body token::int_
    return { tag = "token::int_" }
end

M["body97"] = function() -- body token::or_
    return { tag = "token::or_" }
end

M["body98"] = function() -- body token::str_
    return { tag = "token::str_" }
end

M["body99"] = function() -- body token::match_
    return { tag = "token::match_" }
end

M["body100"] = function() -- body token::ident
  return function(p0)
    local l0 -- local 'ident'
    l0 = p0 -- pattern binding assign
    return { tag = "token::ident", value = l0 }
  end
end

M["body101"] = function() -- body ike::parse::lexer::unexpected-character
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
      l5 = { __list = true, { __tuple = true, (M["body102"]())(l0), l3 }, l1 } -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body4"]())(l5))((M["body12"]())(((M["body29"]())(l4))(l2)))
    end
    return block_result0
  end
  end
  end
end

M["body102"] = function() -- body token::unknown
  return function(p0)
    local l0 -- local 'unknown'
    l0 = p0 -- pattern binding assign
    return { tag = "token::unknown", value = l0 }
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

M["body105"] = function() -- body std::result::assert
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
        match_result1 = (M["body106"]())((M["body108"]())(l2))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body106"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body107"]())("thread main panic: `")
      block_result0 = (M["body107"]())((M["body108"]())(l0))
      block_result0 = (M["body109"]())("`")
      block_result0 = (M["body110"]())(1)
    end
    return block_result0
  end
end

M["body107"] = function() -- extern std::io::print
    return E["std::io::print"]()
end

M["body108"] = function() -- extern std::debug::format
    return E["std::debug::format"]()
end

M["body109"] = function() -- body std::io::println
  return function(p0)
    local l0 -- local 's'
    l0 = p0 -- pattern binding assign
    return (M["body107"]())(((M["body21"]())("\n"))(l0))
  end
end

M["body110"] = function() -- extern std::os::exit
    return E["std::os::exit"]()
end

M["body111"] = function() -- body ike::file::read
  return function(p0)
    local l0 -- local 'file'
    l0 = p0 -- pattern binding assign
    return (M["body112"]())(l0["path"])
  end
end

M["body112"] = function() -- extern std::fs::read
    return E["std::fs::read"]()
end

M["body113"] = function() -- body std::list::foldl
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
        match_result1 = (((M["body113"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body114"] = function() -- body std::list::map
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
        match_result1 = { __list = true, (l0)(l3), ((M["body114"]())(l0))(l2) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body115"] = function() -- body ike::diagnostic::format
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
        match_result1 = { __tuple = true, M["body116"](), "error" }
      elseif v.tag == "level::warning" then -- match arm
        match_result1 = { __tuple = true, M["body117"](), "warning" }
      elseif v.tag == "level::help" then -- match arm
        match_result1 = { __tuple = true, M["body118"](), "note" }
      end
      local t2 = match_result1 -- tuple pattern assign
      l1 = t2[1] -- pattern binding assign
      l2 = t2[2] -- pattern binding assign
      block_result0 = nil
      l3 = (M["body119"]())(l0) -- pattern binding assign
      block_result0 = nil
      local t3 = (((M["body127"]())({ __tuple = true, "", M["body7"]() }))(((M["body128"]())(l1))(l3)))(l0["labels"]) -- tuple pattern assign
      l4 = t3[1] -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body21"]())(l4))(toString("", true)..toString(l1, true)..toString("", true)..toString(l2, true)..toString("", true)..toString(M["body132"](), true)..toString(": ", true)..toString(M["body131"](), true)..toString("", true)..toString(l0["message"], true)..toString("", true)..toString(M["body132"](), true)..toString("\n", true))
    end
    return block_result0
  end
end

M["body116"] = function() -- body ike::ansi::red
    return "\x1b[31m"
end

M["body117"] = function() -- body ike::ansi::yellow
    return "\x1b[33m"
end

M["body118"] = function() -- body ike::ansi::blue
    return "\x1b[34m"
end

M["body119"] = function() -- body ike::diagnostic::indent
  return function(p0)
    local l0 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((M["body120"]())(0))(M["body121"]()))(((M["body122"]())(M["body123"]()))(l0["labels"]))
    end
    return block_result0
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
    local block_result0 -- block result
    do -- block
      local v = l2 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = l0
      elseif #v > 0 and true and true then -- match arm
        l4 = (v)[1] -- pattern binding assign
        l3 = (v)[2] -- pattern binding assign
        match_result1 = (((M["body120"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body121"] = function() -- body std::math::max
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

M["body122"] = function() -- body std::list::map
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
        match_result1 = { __list = true, (l0)(l3), ((M["body122"]())(l0))(l2) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body123"] = function() -- body ike::diagnostic::indent::{lambda}
  return function(p0)
    local l0 -- local 'label'
    local l1 -- local 'info'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = ((M["body124"]())(l0["span"]))((M["body105"]())((M["body112"]())(l0["span"]["file"]["path"]))) -- pattern binding assign
      block_result0 = nil
      block_result0 = (M["body13"]())(toString("", true)..toString(l1["line"], true)..toString("", true))
    end
    return block_result0
  end
end

M["body124"] = function() -- body ike::span::info
  return function(p0)
  return function(p1)
    local l0 -- local 'span'
    local l1 -- local 'contents'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((((M["body125"]())(0))(1))(l0))(((M["body126"]())("\n"))(l1))
    end
    return block_result0
  end
  end
end

M["body125"] = function() -- body ike::span::info'
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
            match_result3 = ((((M["body125"]())(l6))((l1 + 1)))(l2))(l4)
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

M["body126"] = function() -- extern std::string::split
    return E["std::string::split"]()
end

M["body127"] = function() -- body std::list::foldl
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
        match_result1 = (((M["body127"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body128"] = function() -- body ike::diagnostic::format::{lambda}
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
      l5 = ((((M["body129"]())(l1))(l4))(l3))(l2) -- pattern binding assign
      block_result1 = nil
      block_result1 = { __tuple = true, ((M["body21"]())(l5))(l0), (M["body8"]())(l2["span"]["file"]["path"]) }
    end
    return block_result1
  end
  end
  end
  end
end

M["body129"] = function() -- body ike::diagnostic::label::format
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
      l4 = ((M["body130"]())(l1))(" ") -- pattern binding assign
      block_result0 = nil
      l5 = (M["body105"]())((M["body112"]())(l3["span"]["file"]["path"])) -- pattern binding assign
      block_result0 = nil
      l6 = ((M["body124"]())(l3["span"]))(l5) -- pattern binding assign
      block_result0 = nil
      local v = equal(l0, (M["body8"]())(l3["span"]["file"]["path"])) -- match target
      local match_result1 -- match result
      if (true == v) then -- match arm
        match_result1 = toString("", true)..toString(l4, true)..toString("", true)..toString(M["body118"](), true)..toString("", true)..toString(M["body131"](), true)..toString("...", true)..toString(M["body132"](), true)..toString("", true)
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
          block_result2 = toString("", true)..toString(l4, true)..toString("", true)..toString(M["body118"](), true)..toString("", true)..toString(M["body131"](), true)..toString("", true)..toString(l7, true)..toString("", true)..toString(M["body132"](), true)..toString(" ", true)..toString(l8, true)..toString("", true)
        end
        match_result1 = block_result2
      end
      l9 = match_result1 -- pattern binding assign
      block_result0 = nil
      l10 = ((M["body133"]())(""))(((M["body134"]())((l6["line"] - 1)))(((M["body126"]())("\n"))(l5))) -- pattern binding assign
      block_result0 = nil
      l11 = toString("", true)..toString(l4, true)..toString(" ", true)..toString(M["body118"](), true)..toString("", true)..toString(M["body131"](), true)..toString("|", true)..toString(M["body132"](), true)..toString("", true) -- pattern binding assign
      block_result0 = nil
      l12 = ((M["body130"]())((l1 - (M["body13"]())(toString("", true)..toString(l6["line"], true)..toString("", true)))))(" ") -- pattern binding assign
      block_result0 = nil
      l13 = toString("", true)..toString(M["body118"](), true)..toString("", true)..toString(M["body131"](), true)..toString("", true)..toString(l6["line"], true)..toString("", true)..toString(l12, true)..toString(" |", true) -- pattern binding assign
      block_result0 = nil
      l14 = toString("", true)..toString(l13, true)..toString("", true)..toString(M["body132"](), true)..toString(" ", true)..toString(l10, true)..toString("", true) -- pattern binding assign
      block_result0 = nil
      l15 = ((M["body130"]())((l6["column"] - 1)))(" ") -- pattern binding assign
      block_result0 = nil
      l16 = ((M["body121"]())(1))(((M["body135"]())((((M["body13"]())(l10) + 1) - l6["column"])))((l3["span"]["end"] - l3["span"]["start"]))) -- pattern binding assign
      block_result0 = nil
      l17 = ((M["body130"]())(l16))("^") -- pattern binding assign
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
      l20 = toString("", true)..toString(l11, true)..toString(" ", true)..toString(l15, true)..toString("", true)..toString(l2, true)..toString("", true)..toString(l17, true)..toString(" ", true)..toString(l19, true)..toString("", true)..toString(M["body132"](), true)..toString("", true) -- pattern binding assign
      block_result0 = nil
      block_result0 = toString("", true)..toString(l9, true)..toString("\n", true)..toString(l11, true)..toString("\n", true)..toString(l14, true)..toString("\n", true)..toString(l20, true)..toString("\n", true)..toString(l11, true)..toString("\n", true)
    end
    return block_result0
  end
  end
  end
  end
end

M["body130"] = function() -- body std::string::repeat
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
        match_result1 = ((M["body21"]())(l1))(((M["body130"]())((l0 - 1)))(l1))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body131"] = function() -- body ike::ansi::bold
    return "\x1b[1m"
end

M["body132"] = function() -- body ike::ansi::reset
    return "\x1b[0m"
end

M["body133"] = function() -- body std::option::some-or
  return function(p0)
  return function(p1)
    local l0 -- local 'a'
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
        match_result1 = l2
      elseif v.tag == "none" then -- match arm
        match_result1 = l0
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body134"] = function() -- body std::list::nth
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
            match_result3 = ((M["body134"]())((l0 - 1)))(l2)
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

M["body135"] = function() -- body std::math::min
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

M["body136"] = function() -- body ike::parse::finish
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'tree'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = (M["body137"]())(l0) -- tuple pattern assign
      l1 = t1[1] -- pattern binding assign
      block_result0 = nil
      block_result0 = { ["kind"] = l1["kind"], ["children"] = (M["body144"]())(l1["children"]) }
    end
    return block_result0
  end
end

M["body137"] = function() -- body ike::parse::parser::pop-stack
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'tree'
    local l2 -- local 'stack'
    local l3 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = ((M["body138"]())("parser::pop-stack stack empty"))((M["body141"]())(l0["stack"])) -- tuple pattern assign
      l1 = t1[1] -- pattern binding assign
      l2 = t1[2] -- pattern binding assign
      block_result0 = nil
      l3 = { ["tokens"] = l0["tokens"], ["stack"] = l2 } -- pattern binding assign
      block_result0 = nil
      block_result0 = { __tuple = true, l1, l3 }
    end
    return block_result0
  end
end

M["body138"] = function() -- body std::option::expect
  return function(p0)
  return function(p1)
    local l0 -- local 'msg'
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
        match_result1 = l2
      elseif v.tag == "none" then -- match arm
        match_result1 = (M["body139"]())(l0)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body139"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body107"]())("thread main panic: `")
      block_result0 = (M["body107"]())((M["body108"]())(l0))
      block_result0 = (M["body109"]())("`")
      block_result0 = (M["body140"]())(1)
    end
    return block_result0
  end
end

M["body140"] = function() -- extern std::os::exit
    return E["std::os::exit"]()
end

M["body141"] = function() -- body std::list::pop
  return function(p0)
    local l0 -- local 'xs'
    local l1 -- local 'xs'
    local l2 -- local 'x'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = M["body142"]()
      elseif #v > 0 and true and true then -- match arm
        l2 = (v)[1] -- pattern binding assign
        l1 = (v)[2] -- pattern binding assign
        match_result1 = (M["body143"]())({ __tuple = true, l2, l1 })
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body142"] = function() -- body none
    return { tag = "none" }
end

M["body143"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body144"] = function() -- body std::list::reverse
  return function(p0)
    local l0 -- local 'xs'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body145"]())(l0))({ __list = true })
    end
    return block_result0
  end
end

M["body145"] = function() -- body std::list::reverse'
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
        match_result1 = ((M["body145"]())(l2))({ __list = true, l3, l1 })
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body146"] = function() -- body ike::parse::file
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::end-of-file" then -- match arm
        match_result1 = l0
      elseif true then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body146"]())((M["body162"]())((M["body176"]())((M["body162"]())(l0))))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body147"] = function() -- body ike::parse::peek
    return (M["body148"]())(0)
end

M["body148"] = function() -- body ike::parse::nth
  return function(p0)
  return function(p1)
    local l0 -- local 'n'
    local l1 -- local 'parser'
    local l2 -- local 'pair'
    local l3 -- local 'token'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = ((M["body149"]())(l0))(((M["body153"]())(M["body158"]()))((M["body160"]())(l1["tokens"]))) -- pattern binding assign
      block_result0 = nil
      local v = l2 -- match target
      local match_result1 -- match result
      if v.tag == "some" and true and true then -- match arm
        local t2 = v.value -- tuple pattern assign
        l3 = t2[1] -- pattern binding assign
        match_result1 = l3
      elseif v.tag == "none" then -- match arm
        match_result1 = M["body11"]()
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body149"] = function() -- body std::iter::nth
  return function(p0)
  return function(p1)
    local l0 -- local 'n'
    local l1 -- local 'it'
    local l2 -- local 'x'
    local l3 -- local 'it'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body150"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "none" then -- match arm
        match_result1 = M["body151"]()
      elseif v.tag == "some" and true and true then -- match arm
        local t2 = v.value -- tuple pattern assign
        l2 = t2[1] -- pattern binding assign
        l3 = t2[2] -- pattern binding assign
        local block_result3 -- block result
        do -- block
          local v = l0 -- match target
          local match_result4 -- match result
          if (0 == v) then -- match arm
            match_result4 = (M["body152"]())(l2)
          elseif true then -- match arm
            match_result4 = ((M["body149"]())((l0 - 1)))(l3)
          end
          block_result3 = match_result4
        end
        match_result1 = block_result3
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body150"] = function() -- body std::iter::next
  return function(p0)
    local l0 -- local 'it'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local block_result1 -- block result
      do -- block
      end
      block_result0 = (l0["next"])(block_result1)
    end
    return block_result0
  end
end

M["body151"] = function() -- body none
    return { tag = "none" }
end

M["body152"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body153"] = function() -- body std::iter::filter
  return function(p0)
  return function(p1)
    local l0 -- local 'f'
    local l1 -- local 'it'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body154"]())(((M["body155"]())(l0))(l1))
    end
    return block_result0
  end
  end
end

M["body154"] = function() -- body std::iter::new
  return function(p0)
    local l0 -- local 'next'
    l0 = p0 -- pattern binding assign
    return { ["next"] = l0 }
  end
end

M["body155"] = function() -- body std::iter::filter::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
    local l0 -- local 'it'
    local l1 -- local 'x'
    local l2 -- local 'it'
    local l3 -- local 'f'
    l3 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body150"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "some" and true and true then -- match arm
        local t2 = v.value -- tuple pattern assign
        l1 = t2[1] -- pattern binding assign
        l2 = t2[2] -- pattern binding assign
        local block_result3 -- block result
        do -- block
          local v = (l3)(l1) -- match target
          local match_result4 -- match result
          if (true == v) then -- match arm
            match_result4 = (M["body156"]())({ __tuple = true, l1, ((M["body153"]())(l3))(l2) })
          elseif (false == v) then -- match arm
            match_result4 = (M["body150"]())(((M["body153"]())(l3))(l2))
          end
          block_result3 = match_result4
        end
        match_result1 = block_result3
      elseif v.tag == "none" then -- match arm
        match_result1 = M["body157"]()
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body156"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body157"] = function() -- body none
    return { tag = "none" }
end

M["body158"] = function() -- body ike::parse::nth::{lambda}
  return function(p0)
    local l0 -- local 't'
    local t0 = p0 -- tuple pattern assign
    l0 = t0[1] -- pattern binding assign
    return equal((M["body159"]())(l0), false)
  end
end

M["body159"] = function() -- body ike::parse::parser::should-skip
  return function(p0)
    local l0 -- local 'token'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "token::comment" then -- match arm
        match_result1 = true
      elseif v.tag == "token::whitespace" then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body160"] = function() -- body std::list::iter
  return function(p0)
    local l0 -- local 'xs'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body154"]())((M["body161"]())(l0))
    end
    return block_result0
  end
end

M["body161"] = function() -- body std::list::iter::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 'xs'
    local l1 -- local 'xs'
    local l2 -- local 'x'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = M["body157"]()
      elseif #v > 0 and true and true then -- match arm
        l2 = (v)[1] -- pattern binding assign
        l1 = (v)[2] -- pattern binding assign
        match_result1 = (M["body156"]())({ __tuple = true, l2, (M["body160"]())(l1) })
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body162"] = function() -- body ike::parse::eat-newlines
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = ((M["body163"]())(M["body83"]()))(l0) -- match target
      local match_result1 -- match result
      if v.tag == "some" and true then -- match arm
        l1 = v.value -- pattern binding assign
        match_result1 = (M["body162"]())(l1)
      elseif v.tag == "none" then -- match arm
        match_result1 = l0
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body163"] = function() -- body ike::parse::eat
  return function(p0)
  return function(p1)
    local l0 -- local 'token'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = equal(l0, (M["body147"]())(l1)) -- match target
      local match_result1 -- match result
      if (true == v) then -- match arm
        match_result1 = (M["body164"]())((M["body165"]())(l1))
      elseif (false == v) then -- match arm
        match_result1 = M["body175"]()
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body164"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body165"] = function() -- body ike::parse::advance
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'token'
    local l2 -- local 'span'
    local l3 -- local 'tokens'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = ((M["body166"]())("missing eof token"))((M["body169"]())(l0["tokens"])) -- tuple pattern assign
      local t2 = t1[1] -- tuple pattern assign
      l1 = t2[1] -- pattern binding assign
      l2 = t2[2] -- pattern binding assign
      l3 = t1[2] -- pattern binding assign
      block_result0 = nil
      local v = (M["body159"]())(l1) -- match target
      local match_result3 -- match result
      if (true == v) then -- match arm
        match_result3 = (M["body165"]())((M["body172"]())(l0))
      elseif (false == v) then -- match arm
        match_result3 = (M["body172"]())(l0)
      end
      block_result0 = match_result3
    end
    return block_result0
  end
end

M["body166"] = function() -- body std::option::expect
  return function(p0)
  return function(p1)
    local l0 -- local 'msg'
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
        match_result1 = l2
      elseif v.tag == "none" then -- match arm
        match_result1 = (M["body167"]())(l0)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body167"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body107"]())("thread main panic: `")
      block_result0 = (M["body107"]())((M["body108"]())(l0))
      block_result0 = (M["body109"]())("`")
      block_result0 = (M["body168"]())(1)
    end
    return block_result0
  end
end

M["body168"] = function() -- extern std::os::exit
    return E["std::os::exit"]()
end

M["body169"] = function() -- body std::list::pop
  return function(p0)
    local l0 -- local 'xs'
    local l1 -- local 'xs'
    local l2 -- local 'x'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = M["body170"]()
      elseif #v > 0 and true and true then -- match arm
        l2 = (v)[1] -- pattern binding assign
        l1 = (v)[2] -- pattern binding assign
        match_result1 = (M["body171"]())({ __tuple = true, l2, l1 })
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body170"] = function() -- body none
    return { tag = "none" }
end

M["body171"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body172"] = function() -- body ike::parse::advance-one
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'token'
    local l2 -- local 'span'
    local l3 -- local 'tokens'
    local l4 -- local 'child'
    local l5 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = ((M["body166"]())("missing eof token"))((M["body169"]())(l0["tokens"])) -- tuple pattern assign
      local t2 = t1[1] -- tuple pattern assign
      l1 = t2[1] -- pattern binding assign
      l2 = t2[2] -- pattern binding assign
      l3 = t1[2] -- pattern binding assign
      block_result0 = nil
      l4 = (M["body173"]())({ __tuple = true, l1, l2 }) -- pattern binding assign
      block_result0 = nil
      l5 = ((M["body174"]())(l4))(l0) -- pattern binding assign
      block_result0 = nil
      local v = l1 -- match target
      local match_result3 -- match result
      if v.tag == "token::end-of-file" then -- match arm
        match_result3 = l5
      elseif true then -- match arm
        local block_result4 -- block result
        do -- block
          block_result4 = { ["tokens"] = l3, ["stack"] = l5["stack"] }
        end
        match_result3 = block_result4
      end
      block_result0 = match_result3
    end
    return block_result0
  end
end

M["body173"] = function() -- body token
  return function(p0)
    local l0 -- local 'token'
    l0 = p0 -- pattern binding assign
    return { tag = "token", value = l0 }
  end
end

M["body174"] = function() -- body ike::parse::parser::push-child
  return function(p0)
  return function(p1)
    local l0 -- local 'child'
    local l1 -- local 'parser'
    local l2 -- local 'tree'
    local l3 -- local 'stack'
    local l4 -- local 'tree'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = ((M["body138"]())("parser::push-child stack empty"))((M["body141"]())(l1["stack"])) -- tuple pattern assign
      l2 = t1[1] -- pattern binding assign
      l3 = t1[2] -- pattern binding assign
      block_result0 = nil
      l4 = { ["kind"] = l2["kind"], ["children"] = { __list = true, l0, l2["children"] } } -- pattern binding assign
      block_result0 = nil
      block_result0 = { ["tokens"] = l1["tokens"], ["stack"] = { __list = true, l4, l3 } }
    end
    return block_result0
  end
  end
end

M["body175"] = function() -- body none
    return { tag = "none" }
end

M["body176"] = function() -- body ike::parse::item
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::ident" and ("import" == v.value) then -- match arm
        match_result1 = (M["body177"]())(l0)
      elseif v.tag == "token::ident" and ("type" == v.value) then -- match arm
        match_result1 = (M["body195"]())(l0)
      elseif v.tag == "token::ident" and ("alias" == v.value) then -- match arm
        match_result1 = (M["body248"]())(l0)
      elseif v.tag == "token::ident" and ("fn" == v.value) then -- match arm
        match_result1 = (M["body250"]())(l0)
      elseif v.tag == "token::ident" and ("extern" == v.value) then -- match arm
        match_result1 = (M["body346"]())(l0)
      elseif true then -- match arm
        local block_result2 -- block result
        do -- block
          l1 = (((M["body25"]())((M["body183"]())(l0)))("here"))((M["body26"]())("expected item")) -- pattern binding assign
          block_result2 = nil
          block_result2 = (M["body178"]())((M["body165"]())(((M["body189"]())((M["body191"]())(l1)))(l0)))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body177"] = function() -- body ike::parse::item::import
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body180"]())(((M["body192"]())((M["body100"]())("import")))(((M["body189"]())(M["body194"]()))(l0))))
    end
    return block_result0
  end
end

M["body178"] = function() -- body ike::parse::close
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'tree'
    local l2 -- local 'parser'
    local l3 -- local 'child'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = (M["body137"]())(l0) -- tuple pattern assign
      l1 = t1[1] -- pattern binding assign
      l2 = t1[2] -- pattern binding assign
      block_result0 = nil
      l3 = (M["body179"]())({ ["kind"] = l1["kind"], ["children"] = (M["body144"]())(l1["children"]) }) -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body174"]())(l3))(l2)
    end
    return block_result0
  end
end

M["body179"] = function() -- body tree
  return function(p0)
    local l0 -- local 'tree'
    l0 = p0 -- pattern binding assign
    return { tag = "tree", value = l0 }
  end
end

M["body180"] = function() -- body ike::parse::item::path
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body181"]())((M["body182"]())(((M["body189"]())(M["body193"]()))(l0))))
    end
    return block_result0
  end
end

M["body181"] = function() -- body ike::parse::item::path-rec
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::coloncolon" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body181"]())((M["body182"]())(((M["body192"]())(M["body48"]()))(l0)))
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = l0
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body182"] = function() -- body ike::parse::expect-ident
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::ident" then -- match arm
        match_result1 = (M["body165"]())(l0)
      elseif true then -- match arm
        local block_result2 -- block result
        do -- block
          l1 = (((M["body25"]())((M["body183"]())(l0)))("here"))((M["body26"]())("expected `identifier`")) -- pattern binding assign
          block_result2 = nil
          block_result2 = (M["body178"]())(((M["body189"]())((M["body191"]())(l1)))(l0))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body183"] = function() -- body ike::parse::span
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'pair'
    local l2 -- local 'pair'
    local l3 -- local 'span'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = (M["body150"]())(((M["body153"]())(M["body184"]()))((M["body160"]())(l0["tokens"]))) -- pattern binding assign
      block_result0 = nil
      local v = l1 -- match target
      local match_result1 -- match result
      if v.tag == "some" and true and true then -- match arm
        local t2 = v.value -- tuple pattern assign
        l2 = t2[1] -- pattern binding assign
        match_result1 = l2
      elseif v.tag == "none" then -- match arm
        local block_result3 -- block result
        do -- block
          block_result3 = ((M["body185"]())("missing eof"))((M["body188"]())(l0["tokens"]))
        end
        match_result1 = block_result3
      end
      local t4 = match_result1 -- tuple pattern assign
      l3 = t4[2] -- pattern binding assign
      block_result0 = nil
      block_result0 = l3
    end
    return block_result0
  end
end

M["body184"] = function() -- body ike::parse::span::{lambda}
  return function(p0)
    local l0 -- local 't'
    local t0 = p0 -- tuple pattern assign
    l0 = t0[1] -- pattern binding assign
    return equal((M["body159"]())(l0), false)
  end
end

M["body185"] = function() -- body std::option::expect
  return function(p0)
  return function(p1)
    local l0 -- local 'msg'
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
        match_result1 = l2
      elseif v.tag == "none" then -- match arm
        match_result1 = (M["body186"]())(l0)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body186"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body107"]())("thread main panic: `")
      block_result0 = (M["body107"]())((M["body108"]())(l0))
      block_result0 = (M["body109"]())("`")
      block_result0 = (M["body187"]())(1)
    end
    return block_result0
  end
end

M["body187"] = function() -- extern std::os::exit
    return E["std::os::exit"]()
end

M["body188"] = function() -- body std::list::last
  return function(p0)
    local l0 -- local 'xs'
    local l1 -- local 'x'
    local l2 -- local 'xs'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = M["body151"]()
      elseif #v > 0 and true and #(v)[2] == 0 then -- match arm
        l1 = (v)[1] -- pattern binding assign
        match_result1 = (M["body152"]())(l1)
      elseif #v > 0 and true and true then -- match arm
        l2 = (v)[2] -- pattern binding assign
        match_result1 = (M["body188"]())(l2)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body189"] = function() -- body ike::parse::open
  return function(p0)
  return function(p1)
    local l0 -- local 'kind'
    local l1 -- local 'parser'
    local l2 -- local 'token'
    local l3 -- local 'tree'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = ((M["body185"]())("missing eof"))((M["body190"]())(l1["tokens"])) -- tuple pattern assign
      l2 = t1[1] -- pattern binding assign
      block_result0 = nil
      local v = (M["body159"]())(l2) -- match target
      local match_result2 -- match result
      if (true == v) then -- match arm
        match_result2 = ((M["body189"]())(l0))((M["body172"]())(l1))
      elseif (false == v) then -- match arm
        local block_result3 -- block result
        do -- block
          l3 = { ["kind"] = l0, ["children"] = { __list = true } } -- pattern binding assign
          block_result3 = nil
          block_result3 = { ["tokens"] = l1["tokens"], ["stack"] = { __list = true, l3, l1["stack"] } }
        end
        match_result2 = block_result3
      end
      block_result0 = match_result2
    end
    return block_result0
  end
  end
end

M["body190"] = function() -- body std::list::first
  return function(p0)
    local l0 -- local 'xs'
    local l1 -- local 'x'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = M["body151"]()
      elseif #v > 0 and true and true then -- match arm
        l1 = (v)[1] -- pattern binding assign
        match_result1 = (M["body152"]())(l1)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body191"] = function() -- body error
  return function(p0)
    local l0 -- local 'error'
    l0 = p0 -- pattern binding assign
    return { tag = "error", value = l0 }
  end
end

M["body192"] = function() -- body ike::parse::expect
  return function(p0)
  return function(p1)
    local l0 -- local 'token'
    local l1 -- local 'parser'
    local l2 -- local 'parser'
    local l3 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = ((M["body163"]())(l0))(l1) -- match target
      local match_result1 -- match result
      if v.tag == "some" and true then -- match arm
        l2 = v.value -- pattern binding assign
        match_result1 = l2
      elseif v.tag == "none" then -- match arm
        local block_result2 -- block result
        do -- block
          l3 = (((M["body25"]())((M["body183"]())(l1)))("here"))((M["body26"]())(toString("expected `", true)..toString(l0, true)..toString("`", true))) -- pattern binding assign
          block_result2 = nil
          block_result2 = (M["body178"]())(((M["body189"]())((M["body191"]())(l3)))(l1))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body193"] = function() -- body path
    return { tag = "path" }
end

M["body194"] = function() -- body item::import
    return { tag = "item::import" }
end

M["body195"] = function() -- body ike::parse::item::type
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body196"]())(((M["body192"]())(M["body75"]()))((M["body243"]())((M["body180"]())(((M["body192"]())((M["body100"]())("type")))(((M["body189"]())(M["body247"]()))(l0)))))))
    end
    return block_result0
  end
end

M["body196"] = function() -- body ike::parse::item::type::body
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::ident" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body178"]())((M["body197"]())(((M["body189"]())(M["body238"]()))(l0)))
        end
        match_result1 = block_result2
      elseif v.tag == "token::open-brace" then -- match arm
        local block_result3 -- block result
        do -- block
          block_result3 = (M["body178"]())((M["body239"]())(((M["body189"]())(M["body242"]()))(l0)))
        end
        match_result1 = block_result3
      elseif true then -- match arm
        local block_result4 -- block result
        do -- block
          l1 = (((M["body25"]())((M["body183"]())(l0)))("here"))((M["body26"]())("expected union or record")) -- pattern binding assign
          block_result4 = nil
          block_result4 = (M["body178"]())(((M["body189"]())((M["body191"]())(l1)))(l0))
        end
        match_result1 = block_result4
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body197"] = function() -- body ike::parse::item::type::union
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = (M["body178"]())((M["body198"]())((M["body180"]())(((M["body189"]())(M["body236"]()))(l0)))) -- pattern binding assign
      block_result0 = nil
      local v = (M["body237"]())(l1) -- match target
      local match_result1 -- match result
      if (false == v) then -- match arm
        match_result1 = l1
      elseif (true == v) then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body197"]())(((M["body192"]())(M["body72"]()))((M["body162"]())(l1)))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body198"] = function() -- body ike::parse::item::type::union::body
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::newline" then -- match arm
        match_result1 = l0
      elseif v.tag == "token::pipe" then -- match arm
        match_result1 = l0
      elseif true then -- match arm
        match_result1 = (M["body199"]())(l0)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body199"] = function() -- body ike::parse::type
    return M["body200"]()
end

M["body200"] = function() -- body ike::parse::type::function
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = (M["body201"]())(l0) -- pattern binding assign
      block_result0 = nil
      local v = (M["body147"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "token::rarrow" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body178"]())((M["body200"]())(((M["body192"]())(M["body46"]()))(((M["body225"]())(M["body235"]()))(l1))))
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = l1
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body201"] = function() -- body ike::parse::type::tuple
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = (M["body202"]())(l0) -- pattern binding assign
      block_result0 = nil
      local v = (M["body147"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "token::comma" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body178"]())((M["body224"]())(((M["body225"]())(M["body234"]()))(l1)))
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = l1
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body202"] = function() -- body ike::parse::type::application
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::ident" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body178"]())((M["body203"]())((M["body180"]())(((M["body189"]())(M["body217"]()))(l0))))
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = (M["body205"]())(l0)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body203"] = function() -- body ike::parse::type::application-rec
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body204"]())((M["body147"]())(l0)) -- match target
      local match_result1 -- match result
      if (false == v) then -- match arm
        match_result1 = l0
      elseif (true == v) then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body203"]())((M["body205"]())(l0))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body204"] = function() -- body ike::parse::type::first
  return function(p0)
    local l0 -- local 'token'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "token::int_" then -- match arm
        match_result1 = true
      elseif v.tag == "token::str_" then -- match arm
        match_result1 = true
      elseif v.tag == "token::bool_" then -- match arm
        match_result1 = true
      elseif v.tag == "token::under" then -- match arm
        match_result1 = true
      elseif v.tag == "token::quote" then -- match arm
        match_result1 = true
      elseif v.tag == "token::ident" then -- match arm
        match_result1 = true
      elseif v.tag == "token::open-paren" then -- match arm
        match_result1 = true
      elseif v.tag == "token::open-brace" then -- match arm
        match_result1 = true
      elseif v.tag == "token::open-bracket" then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body205"] = function() -- body ike::parse::type::term
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'token'
    local l2 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::int_" then -- match arm
        match_result1 = (M["body206"]())(l0)
      elseif v.tag == "token::str_" then -- match arm
        match_result1 = (M["body208"]())(l0)
      elseif v.tag == "token::bool_" then -- match arm
        match_result1 = (M["body210"]())(l0)
      elseif v.tag == "token::under" then -- match arm
        match_result1 = (M["body212"]())(l0)
      elseif v.tag == "token::quote" then -- match arm
        match_result1 = (M["body214"]())(l0)
      elseif v.tag == "token::ident" then -- match arm
        match_result1 = (M["body216"]())(l0)
      elseif v.tag == "token::open-paren" then -- match arm
        match_result1 = (M["body218"]())(l0)
      elseif v.tag == "token::open-brace" then -- match arm
        match_result1 = (M["body220"]())(l0)
      elseif v.tag == "token::open-bracket" then -- match arm
        match_result1 = (M["body222"]())(l0)
      elseif true then -- match arm
        l1 = v -- pattern binding assign
        local block_result2 -- block result
        do -- block
          l2 = (((M["body25"]())((M["body183"]())(l0)))("here"))((M["body26"]())("expected type")) -- pattern binding assign
          block_result2 = nil
          block_result2 = (M["body178"]())(((M["body189"]())((M["body191"]())(l2)))(l0))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body206"] = function() -- body ike::parse::type::integer
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body96"]()))(((M["body189"]())(M["body207"]()))(l0)))
    end
    return block_result0
  end
end

M["body207"] = function() -- body type::integer
    return { tag = "type::integer" }
end

M["body208"] = function() -- body ike::parse::type::string
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body98"]()))(((M["body189"]())(M["body209"]()))(l0)))
    end
    return block_result0
  end
end

M["body209"] = function() -- body type::string
    return { tag = "type::string" }
end

M["body210"] = function() -- body ike::parse::type::boolean
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body91"]()))(((M["body189"]())(M["body211"]()))(l0)))
    end
    return block_result0
  end
end

M["body211"] = function() -- body type::boolean
    return { tag = "type::boolean" }
end

M["body212"] = function() -- body ike::parse::type::inferred
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body64"]()))(((M["body189"]())(M["body213"]()))(l0)))
    end
    return block_result0
  end
end

M["body213"] = function() -- body type::inferred
    return { tag = "type::inferred" }
end

M["body214"] = function() -- body ike::parse::type::generic
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body182"]())(((M["body192"]())(M["body74"]()))(((M["body189"]())(M["body215"]()))(l0))))
    end
    return block_result0
  end
end

M["body215"] = function() -- body type::generic
    return { tag = "type::generic" }
end

M["body216"] = function() -- body ike::parse::type::path
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body180"]())(((M["body189"]())(M["body217"]()))(l0)))
    end
    return block_result0
  end
end

M["body217"] = function() -- body type::path
    return { tag = "type::path" }
end

M["body218"] = function() -- body ike::parse::type::paren
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body56"]()))((M["body199"]())(((M["body192"]())(M["body55"]()))(((M["body189"]())(M["body219"]()))(l0)))))
    end
    return block_result0
  end
end

M["body219"] = function() -- body type::paren
    return { tag = "type::paren" }
end

M["body220"] = function() -- body ike::parse::type::unit
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body36"]()))(((M["body192"]())(M["body33"]()))(((M["body189"]())(M["body221"]()))(l0))))
    end
    return block_result0
  end
end

M["body221"] = function() -- body type::unit
    return { tag = "type::unit" }
end

M["body222"] = function() -- body ike::parse::type::list
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body58"]()))((M["body199"]())(((M["body192"]())(M["body57"]()))(((M["body189"]())(M["body223"]()))(l0)))))
    end
    return block_result0
  end
end

M["body223"] = function() -- body type::list
    return { tag = "type::list" }
end

M["body224"] = function() -- body ike::parse::type::tuple-rec
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::comma" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body224"]())((M["body202"]())(((M["body192"]())(M["body61"]()))(l0)))
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = l0
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body225"] = function() -- body ike::parse::open-before
  return function(p0)
  return function(p1)
    local l0 -- local 'kind'
    local l1 -- local 'parser'
    local l2 -- local 'child'
    local l3 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = (M["body226"]())(l1) -- tuple pattern assign
      l2 = t1[1] -- pattern binding assign
      l3 = t1[2] -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body174"]())(l2))(((M["body189"]())(l0))(l3))
    end
    return block_result0
  end
  end
end

M["body226"] = function() -- body ike::parse::parser::pop-child
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'tree'
    local l2 -- local 'parser'
    local l3 -- local 'child'
    local l4 -- local 'children'
    local l5 -- local 'tree'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = (M["body137"]())(l0) -- tuple pattern assign
      l1 = t1[1] -- pattern binding assign
      l2 = t1[2] -- pattern binding assign
      block_result0 = nil
      local t2 = ((M["body227"]())("parser::pop-stack children empty"))((M["body230"]())(l1["children"])) -- tuple pattern assign
      l3 = t2[1] -- pattern binding assign
      l4 = t2[2] -- pattern binding assign
      block_result0 = nil
      l5 = { ["kind"] = l1["kind"], ["children"] = l4 } -- pattern binding assign
      block_result0 = nil
      block_result0 = { __tuple = true, l3, ((M["body233"]())(l5))(l2) }
    end
    return block_result0
  end
end

M["body227"] = function() -- body std::option::expect
  return function(p0)
  return function(p1)
    local l0 -- local 'msg'
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
        match_result1 = l2
      elseif v.tag == "none" then -- match arm
        match_result1 = (M["body228"]())(l0)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body228"] = function() -- body std::panic
  return function(p0)
    local l0 -- local 'message'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body107"]())("thread main panic: `")
      block_result0 = (M["body107"]())((M["body108"]())(l0))
      block_result0 = (M["body109"]())("`")
      block_result0 = (M["body229"]())(1)
    end
    return block_result0
  end
end

M["body229"] = function() -- extern std::os::exit
    return E["std::os::exit"]()
end

M["body230"] = function() -- body std::list::pop
  return function(p0)
    local l0 -- local 'xs'
    local l1 -- local 'xs'
    local l2 -- local 'x'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if #v == 0 then -- match arm
        match_result1 = M["body231"]()
      elseif #v > 0 and true and true then -- match arm
        l2 = (v)[1] -- pattern binding assign
        l1 = (v)[2] -- pattern binding assign
        match_result1 = (M["body232"]())({ __tuple = true, l2, l1 })
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body231"] = function() -- body none
    return { tag = "none" }
end

M["body232"] = function() -- body some
  return function(p0)
    local l0 -- local 'some'
    l0 = p0 -- pattern binding assign
    return { tag = "some", value = l0 }
  end
end

M["body233"] = function() -- body ike::parse::parser::push-stack
  return function(p0)
  return function(p1)
    local l0 -- local 'tree'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = { ["tokens"] = l1["tokens"], ["stack"] = { __list = true, l0, l1["stack"] } }
    end
    return block_result0
  end
  end
end

M["body234"] = function() -- body type::tuple
    return { tag = "type::tuple" }
end

M["body235"] = function() -- body type::function
    return { tag = "type::function" }
end

M["body236"] = function() -- body item::type::union::variant
    return { tag = "item::type::union::variant" }
end

M["body237"] = function() -- body ike::parse::item::type::is-union
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())((M["body162"]())(l0)) -- match target
      local match_result1 -- match result
      if v.tag == "token::pipe" then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body238"] = function() -- body item::type::union
    return { tag = "item::type::union" }
end

M["body239"] = function() -- body ike::parse::item::type::record
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body192"]())(M["body36"]()))((M["body240"]())((M["body162"]())(((M["body192"]())(M["body33"]()))(l0))))
    end
    return block_result0
  end
end

M["body240"] = function() -- body ike::parse::item::type::record::fields
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::ident" then -- match arm
        local block_result2 -- block result
        do -- block
          l1 = (M["body178"]())((M["body199"]())(((M["body192"]())(M["body60"]()))((M["body182"]())(((M["body189"]())(M["body241"]()))(l0))))) -- pattern binding assign
          block_result2 = nil
          local v = (M["body147"]())(l1) -- match target
          local match_result3 -- match result
          if v.tag == "token::semi" then -- match arm
            local block_result4 -- block result
            do -- block
              block_result4 = (M["body240"]())((M["body162"]())(((M["body192"]())(M["body59"]()))(l1)))
            end
            match_result3 = block_result4
          elseif v.tag == "token::newline" then -- match arm
            local block_result5 -- block result
            do -- block
              block_result5 = (M["body240"]())((M["body162"]())(l1))
            end
            match_result3 = block_result5
          elseif true then -- match arm
            match_result3 = l1
          end
          block_result2 = match_result3
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = l0
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body241"] = function() -- body item::type::record::field
    return { tag = "item::type::record::field" }
end

M["body242"] = function() -- body item::type::record
    return { tag = "item::type::record" }
end

M["body243"] = function() -- body ike::parse::item::generics
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body244"]())(((M["body189"]())(M["body246"]()))(l0)))
    end
    return block_result0
  end
end

M["body244"] = function() -- body ike::parse::item::generics-rec
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::quote" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body244"]())((M["body178"]())((M["body182"]())(((M["body192"]())(M["body74"]()))(((M["body189"]())(M["body245"]()))(l0)))))
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = l0
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body245"] = function() -- body item::generic
    return { tag = "item::generic" }
end

M["body246"] = function() -- body item::generics
    return { tag = "item::generics" }
end

M["body247"] = function() -- body item::type
    return { tag = "item::type" }
end

M["body248"] = function() -- body ike::parse::item::alias
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body199"]())(((M["body192"]())(M["body75"]()))((M["body243"]())((M["body180"]())(((M["body192"]())((M["body100"]())("alias")))(((M["body189"]())(M["body249"]()))(l0)))))))
    end
    return block_result0
  end
end

M["body249"] = function() -- body item::alias
    return { tag = "item::alias" }
end

M["body250"] = function() -- body ike::parse::item::function
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'parser'
    local l2 -- local 'parser'
    local l3 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = (M["body180"]())(((M["body192"]())((M["body100"]())("fn")))(((M["body189"]())(M["body251"]()))(l0))) -- pattern binding assign
      block_result0 = nil
      local v = (M["body147"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "token::colon" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((M["body252"]())(M["body253"]()))((M["body199"]())(((M["body192"]())(M["body60"]()))(l1)))
        end
        match_result1 = block_result2
      elseif true then -- match arm
        local block_result3 -- block result
        do -- block
          l2 = (M["body178"]())((M["body254"]())(((M["body189"]())(M["body277"]()))(l1))) -- pattern binding assign
          block_result3 = nil
          local v = (M["body147"]())(l2) -- match target
          local match_result4 -- match result
          if v.tag == "token::open-brace" then -- match arm
            local block_result5 -- block result
            do -- block
              block_result5 = (M["body178"]())(((M["body278"]())(true))(l2))
            end
            match_result4 = block_result5
          elseif v.tag == "token::rarrow" then -- match arm
            local block_result6 -- block result
            do -- block
              block_result6 = (M["body178"]())(((M["body278"]())(false))(((M["body192"]())(M["body46"]()))(l2)))
            end
            match_result4 = block_result6
          elseif true then -- match arm
            local block_result7 -- block result
            do -- block
              l3 = (((M["body25"]())((M["body183"]())(l2)))("here"))((M["body26"]())("expected function body")) -- pattern binding assign
              block_result7 = nil
              block_result7 = (M["body178"]())(((M["body189"]())((M["body191"]())(l3)))(l2))
            end
            match_result4 = block_result7
          end
          block_result3 = match_result4
        end
        match_result1 = block_result3
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body251"] = function() -- body item::function
    return { tag = "item::function" }
end

M["body252"] = function() -- body ike::parse::close-with
  return function(p0)
  return function(p1)
    local l0 -- local 'kind'
    local l1 -- local 'parser'
    local l2 -- local 'tree'
    local l3 -- local 'parser'
    local l4 -- local 'child'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local t1 = (M["body137"]())(l1) -- tuple pattern assign
      l2 = t1[1] -- pattern binding assign
      l3 = t1[2] -- pattern binding assign
      block_result0 = nil
      l4 = (M["body179"]())({ ["kind"] = l0, ["children"] = (M["body144"]())(l2["children"]) }) -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body174"]())(l4))(l3)
    end
    return block_result0
  end
  end
end

M["body253"] = function() -- body item::ascription
    return { tag = "item::ascription" }
end

M["body254"] = function() -- body ike::parse::item::function::params
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::rarrow" then -- match arm
        match_result1 = l0
      elseif v.tag == "token::open-brace" then -- match arm
        match_result1 = l0
      elseif true then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body254"]())(((M["body255"]())(false))(l0))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body255"] = function() -- body ike::parse::pattern
    return M["body256"]()
end

M["body256"] = function() -- body ike::parse::pattern::tuple
  return function(p0)
  return function(p1)
    local l0 -- local 'refutable'
    local l1 -- local 'parser'
    local l2 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = ((M["body257"]())(l0))(l1) -- pattern binding assign
      block_result0 = nil
      local v = (M["body147"]())(l2) -- match target
      local match_result1 -- match result
      if v.tag == "token::comma" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body178"]())(((M["body275"]())(l0))(((M["body225"]())(M["body276"]()))(l2)))
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = l2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body257"] = function() -- body ike::parse::pattern::term
  return function(p0)
  return function(p1)
    local l0 -- local 'refutable'
    local l1 -- local 'parser'
    local l2 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "token::under" then -- match arm
        match_result1 = (M["body258"]())(l1)
      elseif v.tag == "token::ident" then -- match arm
        match_result1 = ((M["body260"]())(l0))(l1)
      elseif v.tag == "token::true_" then -- match arm
        match_result1 = (M["body264"]())(l1)
      elseif v.tag == "token::false_" then -- match arm
        match_result1 = (M["body264"]())(l1)
      elseif v.tag == "token::integer" then -- match arm
        match_result1 = (M["body266"]())(l1)
      elseif v.tag == "token::string" then -- match arm
        match_result1 = (M["body268"]())(l1)
      elseif v.tag == "token::open-paren" then -- match arm
        match_result1 = ((M["body270"]())(l0))(l1)
      elseif v.tag == "token::open-bracket" then -- match arm
        match_result1 = ((M["body272"]())(l0))(l1)
      elseif true then -- match arm
        local block_result2 -- block result
        do -- block
          l2 = (((M["body25"]())((M["body183"]())(l1)))("here"))((M["body26"]())("expected pattern")) -- pattern binding assign
          block_result2 = nil
          block_result2 = (M["body178"]())((M["body165"]())(((M["body189"]())((M["body191"]())(l2)))(l1)))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body258"] = function() -- body ike::parse::pattern::wildcard
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body64"]()))(((M["body189"]())(M["body259"]()))(l0)))
    end
    return block_result0
  end
end

M["body259"] = function() -- body pattern::wildcard
    return { tag = "pattern::wildcard" }
end

M["body260"] = function() -- body ike::parse::pattern::path
  return function(p0)
  return function(p1)
    local l0 -- local 'refutable'
    local l1 -- local 'parser'
    local l2 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = (M["body180"]())(((M["body189"]())(M["body261"]()))(l1)) -- pattern binding assign
      block_result0 = nil
      local v = ((M["body262"]())((M["body147"]())(l2)) and l0) -- match target
      local match_result1 -- match result
      if (false == v) then -- match arm
        match_result1 = (M["body178"]())(l2)
      elseif (true == v) then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((M["body252"]())(M["body263"]()))(((M["body255"]())(l0))(l2))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body261"] = function() -- body pattern::path
    return { tag = "pattern::path" }
end

M["body262"] = function() -- body ike::parse::pattern::first
  return function(p0)
    local l0 -- local 'token'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "token::under" then -- match arm
        match_result1 = true
      elseif v.tag == "token::ident" then -- match arm
        match_result1 = true
      elseif v.tag == "token::true_" then -- match arm
        match_result1 = true
      elseif v.tag == "token::false_" then -- match arm
        match_result1 = true
      elseif v.tag == "token::integer" then -- match arm
        match_result1 = true
      elseif v.tag == "token::string" then -- match arm
        match_result1 = true
      elseif v.tag == "token::open-paren" then -- match arm
        match_result1 = true
      elseif v.tag == "token::open-bracket" then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body263"] = function() -- body pattern::variant
    return { tag = "pattern::variant" }
end

M["body264"] = function() -- body ike::parse::pattern::boolean
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body165"]())(((M["body189"]())(M["body265"]()))(l0)))
    end
    return block_result0
  end
end

M["body265"] = function() -- body pattern::boolean
    return { tag = "pattern::boolean" }
end

M["body266"] = function() -- body ike::parse::pattern::integer
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body165"]())(((M["body189"]())(M["body267"]()))(l0)))
    end
    return block_result0
  end
end

M["body267"] = function() -- body pattern::integer
    return { tag = "pattern::integer" }
end

M["body268"] = function() -- body ike::parse::pattern::string
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body165"]())(((M["body189"]())(M["body269"]()))(l0)))
    end
    return block_result0
  end
end

M["body269"] = function() -- body pattern::string
    return { tag = "pattern::string" }
end

M["body270"] = function() -- body ike::parse::pattern::paren
  return function(p0)
  return function(p1)
    local l0 -- local 'refutable'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body56"]()))(((M["body255"]())(l0))(((M["body192"]())(M["body55"]()))(((M["body189"]())(M["body271"]()))(l1)))))
    end
    return block_result0
  end
  end
end

M["body271"] = function() -- body pattern::paren
    return { tag = "pattern::paren" }
end

M["body272"] = function() -- body ike::parse::pattern::list
  return function(p0)
  return function(p1)
    local l0 -- local 'refutable'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body273"]())(l0))(((M["body192"]())(M["body57"]()))(((M["body189"]())(M["body274"]()))(l1))))
    end
    return block_result0
  end
  end
end

M["body273"] = function() -- body ike::parse::pattern::list-rec
  return function(p0)
  return function(p1)
    local l0 -- local 'refutable'
    local l1 -- local 'parser'
    local l2 -- local 'parser'
    local l3 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "token::close-bracket" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((M["body192"]())(M["body58"]()))(l1)
        end
        match_result1 = block_result2
      elseif v.tag == "token::dotdot" then -- match arm
        local block_result3 -- block result
        do -- block
          l2 = ((M["body192"]())(M["body45"]()))(l1) -- pattern binding assign
          block_result3 = nil
          local v = (M["body147"]())(l2) -- match target
          local match_result4 -- match result
          if v.tag == "token::close-bracket" then -- match arm
            local block_result5 -- block result
            do -- block
              block_result5 = ((M["body192"]())(M["body58"]()))(l2)
            end
            match_result4 = block_result5
          elseif true then -- match arm
            local block_result6 -- block result
            do -- block
              block_result6 = ((M["body192"]())(M["body58"]()))(((M["body255"]())(l0))(l2))
            end
            match_result4 = block_result6
          end
          block_result3 = match_result4
        end
        match_result1 = block_result3
      elseif true then -- match arm
        local block_result7 -- block result
        do -- block
          l3 = ((M["body255"]())(l0))(l1) -- pattern binding assign
          block_result7 = nil
          local v = (M["body147"]())(l3) -- match target
          local match_result8 -- match result
          if v.tag == "token::semi" then -- match arm
            local block_result9 -- block result
            do -- block
              block_result9 = ((M["body273"]())(l0))(((M["body192"]())(M["body59"]()))(l3))
            end
            match_result8 = block_result9
          elseif true then -- match arm
            local block_result10 -- block result
            do -- block
              block_result10 = ((M["body192"]())(M["body58"]()))(l3)
            end
            match_result8 = block_result10
          end
          block_result7 = match_result8
        end
        match_result1 = block_result7
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body274"] = function() -- body pattern::list
    return { tag = "pattern::list" }
end

M["body275"] = function() -- body ike::parse::pattern::tuple-rec
  return function(p0)
  return function(p1)
    local l0 -- local 'refutable'
    local l1 -- local 'parser'
    local l2 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = ((M["body257"]())(l0))(((M["body192"]())(M["body61"]()))(l1)) -- pattern binding assign
      block_result0 = nil
      local v = (M["body147"]())(l2) -- match target
      local match_result1 -- match result
      if v.tag == "token::comma" then -- match arm
        match_result1 = ((M["body275"]())(l0))(l2)
      elseif true then -- match arm
        match_result1 = l2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body276"] = function() -- body pattern::tuple
    return { tag = "pattern::tuple" }
end

M["body277"] = function() -- body item::function::params
    return { tag = "item::function::params" }
end

M["body278"] = function() -- body ike::parse::expr
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "token::let_" then -- match arm
        match_result1 = ((M["body279"]())(l0))(l1)
      elseif v.tag == "token::match_" then -- match arm
        match_result1 = (M["body281"]())(l1)
      elseif true then -- match arm
        match_result1 = ((M["body285"]())(l0))(l1)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body279"] = function() -- body ike::parse::expr::let_
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body278"]())(l0))(((M["body192"]())(M["body75"]()))(((M["body255"]())(false))(((M["body192"]())(M["body93"]()))(((M["body189"]())(M["body280"]()))(l1))))))
    end
    return block_result0
  end
  end
end

M["body280"] = function() -- body expr::let_
    return { tag = "expr::let_" }
end

M["body281"] = function() -- body ike::parse::expr::match_
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body36"]()))((M["body282"]())((M["body162"]())(((M["body192"]())(M["body33"]()))(((M["body278"]())(false))(((M["body192"]())(M["body99"]()))(((M["body189"]())(M["body284"]()))(l0))))))))
    end
    return block_result0
  end
end

M["body282"] = function() -- body ike::parse::expr::match_::arms
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::close-brace" then -- match arm
        match_result1 = l0
      elseif true then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body282"]())((M["body178"]())((M["body162"]())(((M["body278"]())(true))(((M["body192"]())(M["body46"]()))(((M["body255"]())(true))(((M["body189"]())(M["body283"]()))(l0)))))))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body283"] = function() -- body expr::match_::arm
    return { tag = "expr::match_::arm" }
end

M["body284"] = function() -- body expr::match_
    return { tag = "expr::match_" }
end

M["body285"] = function() -- body ike::parse::expr::pipe-right
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body286"]())(l0))(((M["body288"]())(l0))(l1))
    end
    return block_result0
  end
  end
end

M["body286"] = function() -- body ike::parse::expr::pipe-right-rec
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body287"]())(l1) -- match target
      local match_result1 -- match result
      if (false == v) then -- match arm
        match_result1 = l1
      elseif (true == v) then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((M["body286"]())(l0))((M["body178"]())(((M["body288"]())(l0))(((M["body192"]())(M["body54"]()))((M["body162"]())(((M["body225"]())(M["body345"]()))(l1))))))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body287"] = function() -- body ike::parse::expr::is-pipe-right
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())((M["body162"]())(l0)) -- match target
      local match_result1 -- match result
      if v.tag == "token::pipegt" then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body288"] = function() -- body ike::parse::expr::pipe-left
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body289"]())(l0))(((M["body291"]())(l0))(l1))
    end
    return block_result0
  end
  end
end

M["body289"] = function() -- body ike::parse::expr::pipe-left-rec
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body290"]())(l1) -- match target
      local match_result1 -- match result
      if (false == v) then -- match arm
        match_result1 = l1
      elseif (true == v) then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((M["body289"]())(l0))((M["body178"]())(((M["body291"]())(l0))(((M["body192"]())(M["body53"]()))((M["body162"]())(((M["body225"]())(M["body345"]()))(l1))))))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body290"] = function() -- body ike::parse::expr::is-pipe-left
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())((M["body162"]())(l0)) -- match target
      local match_result1 -- match result
      if v.tag == "token::ltpipe" then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body291"] = function() -- body ike::parse::expr::tuple
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    local l2 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = ((M["body292"]())(l0))(l1) -- pattern binding assign
      block_result0 = nil
      local v = (M["body147"]())(l2) -- match target
      local match_result1 -- match result
      if v.tag == "token::comma" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body178"]())(((M["body343"]())(l0))(((M["body225"]())(M["body344"]()))(l2)))
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = l2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body292"] = function() -- body ike::parse::expr::or_
  return function(p0)
    local l0 -- local 'allow-block'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((M["body293"]())({ __list = true, M["body97"](), { __list = true } }))(M["body298"]()))(l0)
    end
    return block_result0
  end
end

M["body293"] = function() -- body ike::parse::expr::binary
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'ops'
    local l1 -- local 'prev'
    local l2 -- local 'allow-block'
    local l3 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((((M["body294"]())(l0))(l1))(l2))(((l1)(l2))(l3))
    end
    return block_result0
  end
  end
  end
  end
end

M["body294"] = function() -- body ike::parse::expr::binary-rec
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'ops'
    local l1 -- local 'prev'
    local l2 -- local 'allow-block'
    local l3 -- local 'parser'
    local l4 -- local 'op'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    l2 = p2 -- pattern binding assign
    l3 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l4 = (M["body147"]())(l3) -- pattern binding assign
      block_result0 = nil
      local v = ((M["body295"]())((M["body296"]())(l4)))(l0) -- match target
      local match_result1 -- match result
      if (false == v) then -- match arm
        match_result1 = l3
      elseif (true == v) then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((((M["body294"]())(l0))(l1))(l2))((M["body178"]())(((l1)(l2))(((M["body192"]())(l4))(((M["body225"]())(M["body297"]()))(l3)))))
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

M["body295"] = function() -- body std::list::any
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
        match_result1 = ((l0)(l3) or ((M["body295"]())(l0))(l2))
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body296"] = function() -- body ike::parse::expr::binary-rec::{lambda}
  return function(p0)
  return function(p1)
    local l0 -- local 't'
    local l1 -- local 'op'
    l1 = p0 -- pattern binding assign
    l0 = p1 -- pattern binding assign
    return equal(l0, l1)
  end
  end
end

M["body297"] = function() -- body expr::binary
    return { tag = "expr::binary" }
end

M["body298"] = function() -- body ike::parse::expr::and_
  return function(p0)
    local l0 -- local 'allow-block'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((M["body293"]())({ __list = true, M["body90"](), { __list = true } }))(M["body299"]()))(l0)
    end
    return block_result0
  end
end

M["body299"] = function() -- body ike::parse::expr::eq-ne
  return function(p0)
    local l0 -- local 'allow-block'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((M["body293"]())({ __list = true, M["body49"](), { __list = true, M["body50"](), { __list = true } } }))(M["body300"]()))(l0)
    end
    return block_result0
  end
end

M["body300"] = function() -- body ike::parse::expr::cmp
  return function(p0)
    local l0 -- local 'allow-block'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((M["body293"]())({ __list = true, M["body78"](), { __list = true, M["body77"](), { __list = true, M["body52"](), { __list = true, M["body51"](), { __list = true } } } } }))(M["body301"]()))(l0)
    end
    return block_result0
  end
end

M["body301"] = function() -- body ike::parse::expr::add-sub
  return function(p0)
    local l0 -- local 'allow-block'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((M["body293"]())({ __list = true, M["body65"](), { __list = true, M["body66"](), { __list = true } } }))(M["body302"]()))(l0)
    end
    return block_result0
  end
end

M["body302"] = function() -- body ike::parse::expr::mul-div-mod
  return function(p0)
    local l0 -- local 'allow-block'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (((M["body293"]())({ __list = true, M["body67"](), { __list = true, M["body68"](), { __list = true, M["body70"](), { __list = true } } } }))(M["body303"]()))(l0)
    end
    return block_result0
  end
end

M["body303"] = function() -- body ike::parse::expr::try_
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "token::try_" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body178"]())(((M["body303"]())(l0))(((M["body192"]())(M["body95"]()))(((M["body189"]())(M["body304"]()))(l1))))
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = ((M["body305"]())(l0))(l1)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body304"] = function() -- body expr::unary
    return { tag = "expr::unary" }
end

M["body305"] = function() -- body ike::parse::expr::call
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body306"]())(l0))(((M["body308"]())(l0))(l1))
    end
    return block_result0
  end
  end
end

M["body306"] = function() -- body ike::parse::expr::call-rec
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = ((M["body307"]())(l0))((M["body147"]())(l1)) -- match target
      local match_result1 -- match result
      if (false == v) then -- match arm
        match_result1 = l1
      elseif (true == v) then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((M["body306"]())(l0))((M["body178"]())(((M["body308"]())(l0))(((M["body225"]())(M["body342"]()))(l1))))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body307"] = function() -- body ike::parse::expr::first
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'token'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l1 -- match target
      local match_result1 -- match result
      if v.tag == "token::ident" then -- match arm
        match_result1 = true
      elseif v.tag == "token::string" then -- match arm
        match_result1 = true
      elseif v.tag == "token::format-start" then -- match arm
        match_result1 = true
      elseif v.tag == "token::integer" then -- match arm
        match_result1 = true
      elseif v.tag == "token::true_" then -- match arm
        match_result1 = true
      elseif v.tag == "token::false_" then -- match arm
        match_result1 = true
      elseif v.tag == "token::let_" then -- match arm
        match_result1 = true
      elseif v.tag == "token::match_" then -- match arm
        match_result1 = true
      elseif v.tag == "token::try_" then -- match arm
        match_result1 = true
      elseif v.tag == "token::pipe" then -- match arm
        match_result1 = true
      elseif v.tag == "token::open-paren" then -- match arm
        match_result1 = true
      elseif v.tag == "token::open-brace" then -- match arm
        match_result1 = (true and l0)
      elseif v.tag == "token::open-bracket" then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body308"] = function() -- body ike::parse::expr::field
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body309"]())(((M["body311"]())(l0))(l1))
    end
    return block_result0
  end
  end
end

M["body309"] = function() -- body ike::parse::expr::field-rec
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::dot" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body309"]())((M["body178"]())((M["body182"]())(((M["body192"]())(M["body62"]()))(((M["body225"]())(M["body310"]()))(l0)))))
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = l0
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body310"] = function() -- body expr::field
    return { tag = "expr::field" }
end

M["body311"] = function() -- body ike::parse::expr::term
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    local l2 -- local 'diagnostic'
    local l3 -- local 'token'
    local l4 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "token::ident" then -- match arm
        match_result1 = (M["body312"]())(l1)
      elseif v.tag == "token::string" then -- match arm
        match_result1 = (M["body318"]())(l1)
      elseif v.tag == "token::format-start" then -- match arm
        match_result1 = ((M["body320"]())(l0))(l1)
      elseif v.tag == "token::integer" then -- match arm
        match_result1 = (M["body323"]())(l1)
      elseif v.tag == "token::true_" then -- match arm
        match_result1 = (M["body325"]())(l1)
      elseif v.tag == "token::false_" then -- match arm
        match_result1 = (M["body325"]())(l1)
      elseif v.tag == "token::pipe" then -- match arm
        match_result1 = ((M["body327"]())(l0))(l1)
      elseif v.tag == "token::open-paren" then -- match arm
        match_result1 = ((M["body332"]())(l0))(l1)
      elseif v.tag == "token::open-bracket" then -- match arm
        match_result1 = ((M["body334"]())(l0))(l1)
      elseif v.tag == "token::open-brace" then -- match arm
        local block_result2 -- block result
        do -- block
          local v = l0 -- match target
          local match_result3 -- match result
          if (true == v) then -- match arm
            match_result3 = (M["body337"]())(l1)
          elseif (false == v) then -- match arm
            local block_result4 -- block result
            do -- block
              l2 = (((M["body25"]())((M["body183"]())(l1)))("here"))((M["body26"]())("block expression not allowed here")) -- pattern binding assign
              block_result4 = nil
              block_result4 = (M["body178"]())(((M["body189"]())((M["body191"]())(l2)))(l1))
            end
            match_result3 = block_result4
          end
          block_result2 = match_result3
        end
        match_result1 = block_result2
      elseif true then -- match arm
        l3 = v -- pattern binding assign
        local block_result5 -- block result
        do -- block
          l4 = (((M["body25"]())((M["body183"]())(l1)))("here"))((M["body26"]())("expected expression")) -- pattern binding assign
          block_result5 = nil
          block_result5 = (M["body178"]())(((M["body189"]())((M["body191"]())(l4)))(l1))
        end
        match_result1 = block_result5
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body312"] = function() -- body ike::parse::expr::path
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = (M["body180"]())(((M["body189"]())(M["body313"]()))(l0)) -- pattern binding assign
      block_result0 = nil
      local v = (M["body314"]())(l1) -- match target
      local match_result1 -- match result
      if (false == v) then -- match arm
        match_result1 = (M["body178"]())(l1)
      elseif (true == v) then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((M["body252"]())(M["body315"]()))(((M["body192"]())(M["body36"]()))((M["body316"]())((M["body162"]())(((M["body192"]())(M["body33"]()))(l1)))))
        end
        match_result1 = block_result2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body313"] = function() -- body expr::path
    return { tag = "expr::path" }
end

M["body314"] = function() -- body ike::parse::expr::is-record
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'is-brace'
    local l2 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = equal((M["body147"]())(l0), M["body33"]()) -- pattern binding assign
      block_result0 = nil
      l2 = (M["body162"]())((M["body165"]())(l0)) -- pattern binding assign
      block_result0 = nil
      local v = (M["body147"]())(l2) -- match target
      local match_result1 -- match result
      if v.tag == "token::ident" then -- match arm
        match_result1 = (l1 and equal(((M["body148"]())(1))(l2), M["body60"]()))
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body315"] = function() -- body expr::record
    return { tag = "expr::record" }
end

M["body316"] = function() -- body ike::parse::expr::record::fields
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::ident" then -- match arm
        local block_result2 -- block result
        do -- block
          l1 = (M["body178"]())(((M["body278"]())(true))(((M["body192"]())(M["body60"]()))((M["body182"]())(((M["body189"]())(M["body317"]()))(l0))))) -- pattern binding assign
          block_result2 = nil
          local v = (M["body147"]())(l1) -- match target
          local match_result3 -- match result
          if v.tag == "token::newline" then -- match arm
            local block_result4 -- block result
            do -- block
              block_result4 = (M["body316"]())((M["body162"]())(l1))
            end
            match_result3 = block_result4
          elseif v.tag == "token::semi" then -- match arm
            local block_result5 -- block result
            do -- block
              block_result5 = (M["body316"]())((M["body162"]())(((M["body192"]())(M["body59"]()))(l1)))
            end
            match_result3 = block_result5
          elseif true then -- match arm
            match_result3 = l1
          end
          block_result2 = match_result3
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = l0
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body317"] = function() -- body expr::record::field
    return { tag = "expr::record::field" }
end

M["body318"] = function() -- body ike::parse::expr::string
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body165"]())(((M["body189"]())(M["body319"]()))(l0)))
    end
    return block_result0
  end
end

M["body319"] = function() -- body expr::string
    return { tag = "expr::string" }
end

M["body320"] = function() -- body ike::parse::expr::format
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body321"]())(l0))(((M["body189"]())(M["body322"]()))(l1)))
    end
    return block_result0
  end
  end
end

M["body321"] = function() -- body ike::parse::expr::format-rec
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    local l2 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "token::format-start" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((M["body321"]())(l0))(((M["body278"]())(l0))((M["body178"]())((M["body165"]())(((M["body189"]())(M["body319"]()))(l1)))))
        end
        match_result1 = block_result2
      elseif v.tag == "token::format-continue" then -- match arm
        local block_result3 -- block result
        do -- block
          block_result3 = ((M["body321"]())(l0))(((M["body278"]())(l0))((M["body178"]())((M["body165"]())(((M["body189"]())(M["body319"]()))(l1)))))
        end
        match_result1 = block_result3
      elseif v.tag == "token::format-end" then -- match arm
        local block_result4 -- block result
        do -- block
          block_result4 = (M["body178"]())((M["body165"]())(((M["body189"]())(M["body319"]()))(l1)))
        end
        match_result1 = block_result4
      elseif true then -- match arm
        local block_result5 -- block result
        do -- block
          l2 = (((M["body25"]())((M["body183"]())(l1)))("here"))((M["body26"]())("expected format string")) -- pattern binding assign
          block_result5 = nil
          block_result5 = (M["body178"]())(((M["body189"]())((M["body191"]())(l2)))(l1))
        end
        match_result1 = block_result5
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body322"] = function() -- body expr::format
    return { tag = "expr::format" }
end

M["body323"] = function() -- body ike::parse::expr::integer
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body165"]())(((M["body189"]())(M["body324"]()))(l0)))
    end
    return block_result0
  end
end

M["body324"] = function() -- body expr::integer
    return { tag = "expr::integer" }
end

M["body325"] = function() -- body ike::parse::expr::boolean
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body165"]())(((M["body189"]())(M["body326"]()))(l0)))
    end
    return block_result0
  end
end

M["body326"] = function() -- body expr::boolean
    return { tag = "expr::boolean" }
end

M["body327"] = function() -- body ike::parse::expr::lambda
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body291"]())(l0))((M["body328"]())(((M["body189"]())(M["body331"]()))(l1))))
    end
    return block_result0
  end
  end
end

M["body328"] = function() -- body ike::parse::expr::lambda::params
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body329"]())(((M["body192"]())(M["body72"]()))(((M["body189"]())(M["body330"]()))(l0))))
    end
    return block_result0
  end
end

M["body329"] = function() -- body ike::parse::expr::lambda::params-rec
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l0) -- match target
      local match_result1 -- match result
      if v.tag == "token::pipe" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((M["body192"]())(M["body72"]()))(l0)
        end
        match_result1 = block_result2
      elseif true then -- match arm
        local block_result3 -- block result
        do -- block
          block_result3 = (M["body329"]())(((M["body255"]())(false))(l0))
        end
        match_result1 = block_result3
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body330"] = function() -- body expr::lambda::params
    return { tag = "expr::lambda::params" }
end

M["body331"] = function() -- body expr::lambda
    return { tag = "expr::lambda" }
end

M["body332"] = function() -- body ike::parse::expr::paren
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body56"]()))(((M["body278"]())(l0))(((M["body192"]())(M["body55"]()))(((M["body189"]())(M["body333"]()))(l1)))))
    end
    return block_result0
  end
  end
end

M["body333"] = function() -- body expr::paren
    return { tag = "expr::paren" }
end

M["body334"] = function() -- body ike::parse::expr::list
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())(((M["body192"]())(M["body58"]()))(((M["body335"]())(l0))((M["body162"]())(((M["body192"]())(M["body57"]()))(((M["body189"]())(M["body336"]()))(l1))))))
    end
    return block_result0
  end
  end
end

M["body335"] = function() -- body ike::parse::expr::list-rec
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    local l2 -- local 'parser'
    local l3 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = (M["body147"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "token::close-bracket" then -- match arm
        match_result1 = l1
      elseif v.tag == "token::dotdot" then -- match arm
        local block_result2 -- block result
        do -- block
          l2 = ((M["body192"]())(M["body45"]()))(l1) -- pattern binding assign
          block_result2 = nil
          local v = (M["body147"]())(l2) -- match target
          local match_result3 -- match result
          if v.tag == "token::close-bracket" then -- match arm
            match_result3 = l2
          elseif true then -- match arm
            match_result3 = ((M["body278"]())(l0))(l2)
          end
          block_result2 = match_result3
        end
        match_result1 = block_result2
      elseif true then -- match arm
        local block_result4 -- block result
        do -- block
          l3 = ((M["body278"]())(l0))(l1) -- pattern binding assign
          block_result4 = nil
          local v = (M["body147"]())(l3) -- match target
          local match_result5 -- match result
          if v.tag == "token::newline" then -- match arm
            local block_result6 -- block result
            do -- block
              block_result6 = ((M["body335"]())(l0))((M["body162"]())(l3))
            end
            match_result5 = block_result6
          elseif v.tag == "token::semi" then -- match arm
            local block_result7 -- block result
            do -- block
              block_result7 = ((M["body335"]())(l0))((M["body162"]())(((M["body192"]())(M["body59"]()))(l3)))
            end
            match_result5 = block_result7
          elseif true then -- match arm
            match_result5 = l3
          end
          block_result4 = match_result5
        end
        match_result1 = block_result4
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body336"] = function() -- body expr::list
    return { tag = "expr::list" }
end

M["body337"] = function() -- body ike::parse::expr::block
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = ((M["body192"]())(M["body33"]()))(((M["body189"]())(M["body338"]()))(l0)) -- pattern binding assign
      block_result0 = nil
      local v = (M["body147"]())(l1) -- match target
      local match_result1 -- match result
      if v.tag == "token::newline" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = (M["body178"]())(((M["body192"]())(M["body36"]()))((M["body339"]())(l1)))
        end
        match_result1 = block_result2
      elseif v.tag == "token::close-brace" then -- match arm
        local block_result3 -- block result
        do -- block
          block_result3 = (M["body178"]())(((M["body192"]())(M["body36"]()))(l1))
        end
        match_result1 = block_result3
      elseif true then -- match arm
        local block_result4 -- block result
        do -- block
          block_result4 = (M["body178"]())(((M["body192"]())(M["body36"]()))(((M["body278"]())(true))(l1)))
        end
        match_result1 = block_result4
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body338"] = function() -- body expr::block
    return { tag = "expr::block" }
end

M["body339"] = function() -- body ike::parse::expr::block-rec
  return function(p0)
    local l0 -- local 'parser'
    local l1 -- local 'parser'
    local l2 -- local 'next'
    local l3 -- local 'diagnostic'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = (M["body162"]())(((M["body192"]())(M["body83"]()))(l0)) -- pattern binding assign
      block_result0 = nil
      l2 = (M["body147"]())(l1) -- pattern binding assign
      block_result0 = nil
      local v = l2 -- match target
      local match_result1 -- match result
      if v.tag == "token::close-brace" then -- match arm
        match_result1 = l1
      elseif true then -- match arm
        local block_result2 -- block result
        do -- block
          local v = ((M["body307"]())(true))(l2) -- match target
          local match_result3 -- match result
          if (true == v) then -- match arm
            local block_result4 -- block result
            do -- block
              block_result4 = (M["body339"]())(((M["body278"]())(true))(l1))
            end
            match_result3 = block_result4
          elseif (false == v) then -- match arm
            local block_result5 -- block result
            do -- block
              local v = (M["body340"]())(l2) -- match target
              local match_result6 -- match result
              if (true == v) then -- match arm
                match_result6 = l1
              elseif (false == v) then -- match arm
                local block_result7 -- block result
                do -- block
                  l3 = (((M["body25"]())((M["body183"]())(l1)))("here"))((M["body26"]())("expected expression")) -- pattern binding assign
                  block_result7 = nil
                  block_result7 = (M["body339"]())((M["body178"]())((M["body165"]())(((M["body189"]())((M["body191"]())(l3)))(l1))))
                end
                match_result6 = block_result7
              end
              block_result5 = match_result6
            end
            match_result3 = block_result5
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

M["body340"] = function() -- body ike::parse::expr::block-recovery
  return function(p0)
    local l0 -- local 'token'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "token::end-of-file" then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = (M["body341"]())(l0)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body341"] = function() -- body ike::parse::item::first
  return function(p0)
    local l0 -- local 'token'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "token::ident" and ("import" == v.value) then -- match arm
        match_result1 = true
      elseif v.tag == "token::ident" and ("type" == v.value) then -- match arm
        match_result1 = true
      elseif v.tag == "token::ident" and ("alias" == v.value) then -- match arm
        match_result1 = true
      elseif v.tag == "token::ident" and ("fn" == v.value) then -- match arm
        match_result1 = true
      elseif v.tag == "token::ident" and ("extern" == v.value) then -- match arm
        match_result1 = true
      elseif true then -- match arm
        match_result1 = false
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body342"] = function() -- body expr::call
    return { tag = "expr::call" }
end

M["body343"] = function() -- body ike::parse::expr::tuple-rec
  return function(p0)
  return function(p1)
    local l0 -- local 'allow-block'
    local l1 -- local 'parser'
    local l2 -- local 'parser'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = ((M["body292"]())(l0))(((M["body192"]())(M["body61"]()))(l1)) -- pattern binding assign
      block_result0 = nil
      local v = (M["body147"]())(l2) -- match target
      local match_result1 -- match result
      if v.tag == "token::comma" then -- match arm
        local block_result2 -- block result
        do -- block
          block_result2 = ((M["body343"]())(l0))(l2)
        end
        match_result1 = block_result2
      elseif true then -- match arm
        match_result1 = l2
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body344"] = function() -- body expr::tuple
    return { tag = "expr::tuple" }
end

M["body345"] = function() -- body expr::pipe-left
    return { tag = "expr::pipe-left" }
end

M["body346"] = function() -- body ike::parse::item::extern
  return function(p0)
    local l0 -- local 'parser'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = (M["body178"]())((M["body199"]())(((M["body192"]())(M["body60"]()))((M["body180"]())(((M["body192"]())((M["body100"]())("extern")))(((M["body189"]())(M["body347"]()))(l0))))))
    end
    return block_result0
  end
end

M["body347"] = function() -- body item::extern
    return { tag = "item::extern" }
end

M["body348"] = function() -- body ike::parse::parser::new
  return function(p0)
    local l0 -- local 'tokens'
    local l1 -- local 'tree'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l1 = { ["kind"] = M["body349"](), ["children"] = { __list = true } } -- pattern binding assign
      block_result0 = nil
      block_result0 = { ["tokens"] = l0, ["stack"] = { __list = true, l1, { __list = true } } }
    end
    return block_result0
  end
end

M["body349"] = function() -- body file
    return { tag = "file" }
end

M["body350"] = function() -- body ike::ast::format
  return function(p0)
    local l0 -- local 'ast'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      block_result0 = ((M["body351"]())(l0))(0)
    end
    return block_result0
  end
end

M["body351"] = function() -- body ike::ast::format-rec
  return function(p0)
  return function(p1)
    local l0 -- local 'ast'
    local l1 -- local 'indent'
    local l2 -- local 'indent''
    local l3 -- local 'e'
    local l4 -- local 'kind'
    local l5 -- local 'kind'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      l2 = ((M["body130"]())(l1))(" ") -- pattern binding assign
      block_result0 = nil
      local v = l0["kind"] -- match target
      local match_result1 -- match result
      if v.tag == "error" and true then -- match arm
        l3 = v.value -- pattern binding assign
        match_result1 = toString("", true)..toString(l2, true)..toString("error \"", true)..toString(l3["message"], true)..toString("\"", true)
      elseif true then -- match arm
        l4 = v -- pattern binding assign
        match_result1 = toString("", true)..toString(l2, true)..toString("", true)..toString(l0["kind"], true)..toString("", true)
      end
      l5 = match_result1 -- pattern binding assign
      block_result0 = nil
      block_result0 = (((M["body352"]())(l5))(((M["body353"]())(l1))(l2)))(((M["body354"]())(M["body355"]()))(l0["children"]))
    end
    return block_result0
  end
  end
end

M["body352"] = function() -- body std::list::foldl
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
        match_result1 = (((M["body352"]())(((l1)(l0))(l4)))(l1))(l3)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
  end
end

M["body353"] = function() -- body ike::ast::format-rec::{lambda}
  return function(p0)
  return function(p1)
  return function(p2)
  return function(p3)
    local l0 -- local 'acc'
    local l1 -- local 'child'
    local l2 -- local 't'
    local l3 -- local 'indent''
    local l4 -- local 'ast'
    local l5 -- local 'indent'
    local l6 -- local 'child'
    l5 = p0 -- pattern binding assign
    l3 = p1 -- pattern binding assign
    l0 = p2 -- pattern binding assign
    l1 = p3 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l1 -- match target
      local match_result1 -- match result
      if v.tag == "token" and true and true then -- match arm
        local t2 = v.value -- tuple pattern assign
        l2 = t2[1] -- pattern binding assign
        match_result1 = toString("", true)..toString(l3, true)..toString("  ", true)..toString(l2, true)..toString("", true)
      elseif v.tag == "tree" and true then -- match arm
        l4 = v.value -- pattern binding assign
        match_result1 = ((M["body351"]())(l4))((l5 + 2))
      end
      l6 = match_result1 -- pattern binding assign
      block_result0 = nil
      block_result0 = toString("", true)..toString(l0, true)..toString("\n", true)..toString(l6, true)..toString("", true)
    end
    return block_result0
  end
  end
  end
  end
end

M["body354"] = function() -- body std::list::filter
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
        local block_result2 -- block result
        do -- block
          local v = (l0)(l3) -- match target
          local match_result3 -- match result
          if (true == v) then -- match arm
            match_result3 = { __list = true, l3, ((M["body354"]())(l0))(l2) }
          elseif (false == v) then -- match arm
            match_result3 = ((M["body354"]())(l0))(l2)
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

M["body355"] = function() -- body ike::ast::format-rec::{lambda}
  return function(p0)
    local l0 -- local 'child'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "token" and v.value[1].tag == "token::whitespace" and true then -- match arm
        local t2 = v.value -- tuple pattern assign
        match_result1 = false
      elseif v.tag == "token" and v.value[1].tag == "token::comment" and true then -- match arm
        local t3 = v.value -- tuple pattern assign
        match_result1 = false
      elseif true then -- match arm
        match_result1 = true
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body356"] = function() -- body ike::ast::errors
  return function(p0)
    local l0 -- local 'ast'
    local l1 -- local 'e'
    local l2 -- local 'kind'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0["kind"] -- match target
      local match_result1 -- match result
      if v.tag == "error" and true then -- match arm
        l1 = v.value -- pattern binding assign
        match_result1 = { __list = true, l1, { __list = true } }
      elseif true then -- match arm
        match_result1 = { __list = true }
      end
      l2 = match_result1 -- pattern binding assign
      block_result0 = nil
      block_result0 = ((M["body357"]())(l2))((M["body359"]())(((M["body360"]())(M["body361"]()))(l0["children"])))
    end
    return block_result0
  end
end

M["body357"] = function() -- body std::list::prepend
  return function(p0)
  return function(p1)
    local l0 -- local 'xs'
    local l1 -- local 'ys'
    l0 = p0 -- pattern binding assign
    l1 = p1 -- pattern binding assign
    return ((M["body358"]())(l1))(l0)
  end
  end
end

M["body358"] = function() -- body std::list::append
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
        match_result1 = { __list = true, l3, ((M["body358"]())(l2))(l1) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body359"] = function() -- body std::list::flatten
  return function(p0)
    local l0 -- local 'xss'
    local l1 -- local 'xss'
    local l2 -- local 'xs'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if #v > 0 and true and true then -- match arm
        l2 = (v)[1] -- pattern binding assign
        l1 = (v)[2] -- pattern binding assign
        match_result1 = ((M["body358"]())((M["body359"]())(l1)))(l2)
      elseif #v == 0 then -- match arm
        match_result1 = { __list = true }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

M["body360"] = function() -- body std::list::map
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
        match_result1 = { __list = true, (l0)(l3), ((M["body360"]())(l0))(l2) }
      end
      block_result0 = match_result1
    end
    return block_result0
  end
  end
end

M["body361"] = function() -- body ike::ast::errors::{lambda}
  return function(p0)
    local l0 -- local 'child'
    local l1 -- local 'ast'
    l0 = p0 -- pattern binding assign
    local block_result0 -- block result
    do -- block
      local v = l0 -- match target
      local match_result1 -- match result
      if v.tag == "token" and true then -- match arm
        match_result1 = { __list = true }
      elseif v.tag == "tree" and true then -- match arm
        l1 = v.value -- pattern binding assign
        match_result1 = (M["body356"]())(l1)
      end
      block_result0 = match_result1
    end
    return block_result0
  end
end

coroutine.resume(coroutine.create(M["body0"]))
