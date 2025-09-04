LOVELY_INTEGRITY = '7455ed4254b2b7075263a2061657e0fe991fa36dde097f32190ae8c58ed9ec7f'

--- STEAMODDED CORE
--- MODULE STACKTRACE
-- NOTE: This is a modifed version of https://github.com/ignacio/StackTracePlus/blob/master/src/StackTracePlus.lua
-- Licensed under the MIT License. See https://github.com/ignacio/StackTracePlus/blob/master/LICENSE
-- The MIT License
-- Copyright (c) 2010 Ignacio Burgueño
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.
-- tables
function loadStackTracePlus()
    local _G = _G
    local string, io, debug, coroutine = string, io, debug, coroutine

    -- functions
    local tostring, print, require = tostring, print, require
    local next, assert = next, assert
    local pcall, type, pairs, ipairs = pcall, type, pairs, ipairs
    local error = error

    assert(debug, "debug table must be available at this point")

    local io_open = io.open
    local string_gmatch = string.gmatch
    local string_sub = string.sub
    local table_concat = table.concat

    local _M = {
        max_tb_output_len = 140 -- controls the maximum length of the 'stringified' table before cutting with ' (more...)'
    }

    -- this tables should be weak so the elements in them won't become uncollectable
    local m_known_tables = {
        [_G] = "_G (global table)"
    }
    local function add_known_module(name, desc)
        local ok, mod = pcall(require, name)
        if ok then
            m_known_tables[mod] = desc
        end
    end

    add_known_module("string", "string module")
    add_known_module("io", "io module")
    add_known_module("os", "os module")
    add_known_module("table", "table module")
    add_known_module("math", "math module")
    add_known_module("package", "package module")
    add_known_module("debug", "debug module")
    add_known_module("coroutine", "coroutine module")

    -- lua5.2
    add_known_module("bit32", "bit32 module")
    -- luajit
    add_known_module("bit", "bit module")
    add_known_module("jit", "jit module")
    -- lua5.3
    if _VERSION >= "Lua 5.3" then
        add_known_module("utf8", "utf8 module")
    end

    local m_user_known_tables = {}

    local m_known_functions = {}
    for _, name in ipairs { -- Lua 5.2, 5.1
    "assert", "collectgarbage", "dofile", "error", "getmetatable", "ipairs", "load", "loadfile", "next", "pairs",
    "pcall", "print", "rawequal", "rawget", "rawlen", "rawset", "require", "select", "setmetatable", "tonumber",
    "tostring", "type", "xpcall", -- Lua 5.1
    "gcinfo", "getfenv", "loadstring", "module", "newproxy", "setfenv", "unpack" -- TODO: add table.* etc functions
    } do
        if _G[name] then
            m_known_functions[_G[name]] = name
        end
    end

    local m_user_known_functions = {}

    local function safe_tostring(value)
        local ok, err = pcall(tostring, value)
        if ok then
            return err
        else
            return ("<failed to get printable value>: '%s'"):format(err)
        end
    end

    -- Private:
    -- Parses a line, looking for possible function definitions (in a very naïve way)
    -- Returns '(anonymous)' if no function name was found in the line
    local function ParseLine(line)
        assert(type(line) == "string")
        -- print(line)
        local match = line:match("^%s*function%s+(%w+)")
        if match then
            -- print("+++++++++++++function", match)
            return match
        end
        match = line:match("^%s*local%s+function%s+(%w+)")
        if match then
            -- print("++++++++++++local", match)
            return match
        end
        match = line:match("^%s*local%s+(%w+)%s+=%s+function")
        if match then
            -- print("++++++++++++local func", match)
            return match
        end
        match = line:match("%s*function%s*%(") -- this is an anonymous function
        if match then
            -- print("+++++++++++++function2", match)
            return "(anonymous)"
        end
        return "(anonymous)"
    end

    -- Private:
    -- Tries to guess a function's name when the debug info structure does not have it.
    -- It parses either the file or the string where the function is defined.
    -- Returns '?' if the line where the function is defined is not found
    local function GuessFunctionName(info)
        -- print("guessing function name")
        if type(info.source) == "string" and info.source:sub(1, 1) == "@" then
            local file, err = io_open(info.source:sub(2), "r")
            if not file then
                print("file not found: " .. tostring(err)) -- whoops!
                return "?"
            end
            local line
            for _ = 1, info.linedefined do
                line = file:read("*l")
            end
            if not line then
                print("line not found") -- whoops!
                return "?"
            end
            return ParseLine(line)
        elseif type(info.source) == "string" and info.source:sub(1, 6) == "=[love" then
            return "(LÖVE Function)"
        else
            local line
            local lineNumber = 0
            for l in string_gmatch(info.source, "([^\n]+)\n-") do
                lineNumber = lineNumber + 1
                if lineNumber == info.linedefined then
                    line = l
                    break
                end
            end
            if not line then
                print("line not found") -- whoops!
                return "?"
            end
            return ParseLine(line)
        end
    end

    ---
    -- Dumper instances are used to analyze stacks and collect its information.
    --
    local Dumper = {}

    Dumper.new = function(thread)
        local t = {
            lines = {}
        }
        for k, v in pairs(Dumper) do
            t[k] = v
        end

        t.dumping_same_thread = (thread == coroutine.running())

        -- if a thread was supplied, bind it to debug.info and debug.get
        -- we also need to skip this additional level we are introducing in the callstack (only if we are running
        -- in the same thread we're inspecting)
        if type(thread) == "thread" then
            t.getinfo = function(level, what)
                if t.dumping_same_thread and type(level) == "number" then
                    level = level + 1
                end
                return debug.getinfo(thread, level, what)
            end
            t.getlocal = function(level, loc)
                if t.dumping_same_thread then
                    level = level + 1
                end
                return debug.getlocal(thread, level, loc)
            end
        else
            t.getinfo = debug.getinfo
            t.getlocal = debug.getlocal
        end

        return t
    end

    -- helpers for collecting strings to be used when assembling the final trace
    function Dumper:add(text)
        self.lines[#self.lines + 1] = text
    end
    function Dumper:add_f(fmt, ...)
        self:add(fmt:format(...))
    end
    function Dumper:concat_lines()
        return table_concat(self.lines)
    end

    ---
    -- Private:
    -- Iterates over the local variables of a given function.
    --
    -- @param level The stack level where the function is.
    --
    function Dumper:DumpLocals(level)
        local prefix = "\t "
        local i = 1

        if self.dumping_same_thread then
            level = level + 1
        end

        local name, value = self.getlocal(level, i)
        if not name then
            return
        end
        self:add("\tLocal variables:\r\n")
        while name do
            if type(value) == "number" then
                self:add_f("%s%s = number: %g\r\n", prefix, name, value)
            elseif type(value) == "boolean" then
                self:add_f("%s%s = boolean: %s\r\n", prefix, name, tostring(value))
            elseif type(value) == "string" then
                self:add_f("%s%s = string: %q\r\n", prefix, name, value)
            elseif type(value) == "userdata" then
                self:add_f("%s%s = %s\r\n", prefix, name, safe_tostring(value))
            elseif type(value) == "nil" then
                self:add_f("%s%s = nil\r\n", prefix, name)
            elseif type(value) == "table" then
                if m_known_tables[value] then
                    self:add_f("%s%s = %s\r\n", prefix, name, m_known_tables[value])
                elseif m_user_known_tables[value] then
                    self:add_f("%s%s = %s\r\n", prefix, name, m_user_known_tables[value])
                else
                    local txt = "{"
                    for k, v in pairs(value) do
                        txt = txt .. safe_tostring(k) .. ":" .. safe_tostring(v)
                        if #txt > _M.max_tb_output_len then
                            txt = txt .. " (more...)"
                            break
                        end
                        if next(value, k) then
                            txt = txt .. ", "
                        end
                    end
                    self:add_f("%s%s = %s  %s\r\n", prefix, name, safe_tostring(value), txt .. "}")
                end
            elseif type(value) == "function" then
                local info = self.getinfo(value, "nS")
                local fun_name = info.name or m_known_functions[value] or m_user_known_functions[value]
                if info.what == "C" then
                    self:add_f("%s%s = C %s\r\n", prefix, name,
                        (fun_name and ("function: " .. fun_name) or tostring(value)))
                else
                    local source = info.short_src
                    if source:sub(2, 7) == "string" then
                        source = source:sub(9) -- uno más, por el espacio que viene (string "Baragent.Main", por ejemplo)
                    end
                    -- for k,v in pairs(info) do print(k,v) end
                    fun_name = fun_name or GuessFunctionName(info)
                    self:add_f("%s%s = Lua function '%s' (defined at line %d of chunk %s)\r\n", prefix, name, fun_name,
                        info.linedefined, source)
                end
            elseif type(value) == "thread" then
                self:add_f("%sthread %q = %s\r\n", prefix, name, tostring(value))
            end
            i = i + 1
            name, value = self.getlocal(level, i)
        end
    end

    ---
    -- Public:
    -- Collects a detailed stack trace, dumping locals, resolving function names when they're not available, etc.
    -- This function is suitable to be used as an error handler with pcall or xpcall
    --
    -- @param thread An optional thread whose stack is to be inspected (defaul is the current thread)
    -- @param message An optional error string or object.
    -- @param level An optional number telling at which level to start the traceback (default is 1)
    --
    -- Returns a string with the stack trace and a string with the original error.
    --
    function _M.stacktrace(thread, message, level)
        if type(thread) ~= "thread" then
            -- shift parameters left
            thread, message, level = nil, thread, message
        end

        thread = thread or coroutine.running()

        level = level or 1

        local dumper = Dumper.new(thread)

        local original_error

        if type(message) == "table" then
            dumper:add("an error object {\r\n")
            local first = true
            for k, v in pairs(message) do
                if first then
                    dumper:add("  ")
                    first = false
                else
                    dumper:add(",\r\n  ")
                end
                dumper:add(safe_tostring(k))
                dumper:add(": ")
                dumper:add(safe_tostring(v))
            end
            dumper:add("\r\n}")
            original_error = dumper:concat_lines()
        elseif type(message) == "string" then
            dumper:add(message)
            original_error = message
        end

        dumper:add("\r\n")
        dumper:add [[
Stack Traceback
===============
]]
        -- print(error_message)

        local level_to_show = level
        if dumper.dumping_same_thread then
            level = level + 1
        end

        local info = dumper.getinfo(level, "nSlf")
        while info do
            if info.what == "main" then
                if string_sub(info.source, 1, 1) == "@" then
                    dumper:add_f("(%d) main chunk of file '%s' at line %d\r\n", level_to_show,
                        string_sub(info.source, 2), info.currentline)
                elseif info.source and info.source:sub(1, 1) == "=" then
                    local str = info.source:sub(3, -2)
                    local props = {}
                    -- Split by space
                    for v in string.gmatch(str, "[^%s]+") do
                        table.insert(props, v)
                    end
                    local source = table.remove(props, 1)
                    if source == "love" then
                        dumper:add_f("(%d) main chunk of LÖVE file '%s' at line %d\r\n", level_to_show,
                            table.concat(props, " "):sub(2, -2), info.currentline)
                    elseif source == "SMODS" then
                        local modID = table.remove(props, 1)
                        local fileName = table.concat(props, " ")
                        if modID == '_' then
                            dumper:add_f("(%d) main chunk of Steamodded file '%s' at line %d\r\n", level_to_show,
                                fileName:sub(2, -2), info.currentline)
                        else
                            dumper:add_f("(%d) main chunk of file '%s' at line %d (from mod with id %s)\r\n",
                                level_to_show, fileName:sub(2, -2), info.currentline, modID)
                        end
                    elseif source == "lovely" then
                        local module = table.remove(props, 1)
                        local fileName = table.concat(props, " ")
                        dumper:add_f("(%d) main chunk of file '%s' at line %d (from lovely module %s)\r\n",
                            level_to_show, fileName:sub(2, -2), info.currentline, module)
                    else
                        dumper:add_f("(%d) main chunk of %s at line %d\r\n", level_to_show, info.source,
                            info.currentline)
                    end
                else
                    dumper:add_f("(%d) main chunk of %s at line %d\r\n", level_to_show, info.source, info.currentline)
                end
            elseif info.what == "C" then
                -- print(info.namewhat, info.name)
                -- for k,v in pairs(info) do print(k,v, type(v)) end
                local function_name = m_user_known_functions[info.func] or m_known_functions[info.func] or info.name or
                                          tostring(info.func)
                dumper:add_f("(%d) %s C function '%s'\r\n", level_to_show, info.namewhat, function_name)
                -- dumper:add_f("%s%s = C %s\r\n", prefix, name, (m_known_functions[value] and ("function: " .. m_known_functions[value]) or tostring(value)))
            elseif info.what == "tail" then
                -- print("tail")
                -- for k,v in pairs(info) do print(k,v, type(v)) end--print(info.namewhat, info.name)
                dumper:add_f("(%d) tail call\r\n", level_to_show)
                dumper:DumpLocals(level)
            elseif info.what == "Lua" then
                local source = info.short_src
                local function_name = m_user_known_functions[info.func] or m_known_functions[info.func] or info.name
                if source:sub(2, 7) == "string" then
                    source = source:sub(9)
                end
                local was_guessed = false
                if not function_name or function_name == "?" then
                    -- for k,v in pairs(info) do print(k,v, type(v)) end
                    function_name = GuessFunctionName(info)
                    was_guessed = true
                end
                -- test if we have a file name
                local function_type = (info.namewhat == "") and "function" or info.namewhat
                if info.source and info.source:sub(1, 1) == "@" then
                    dumper:add_f("(%d) Lua %s '%s' at file '%s:%d'%s\r\n", level_to_show, function_type, function_name,
                        info.source:sub(2), info.currentline, was_guessed and " (best guess)" or "")
                elseif info.source and info.source:sub(1, 1) == '#' then
                    dumper:add_f("(%d) Lua %s '%s' at template '%s:%d'%s\r\n", level_to_show, function_type,
                        function_name, info.source:sub(2), info.currentline, was_guessed and " (best guess)" or "")
                elseif info.source and info.source:sub(1, 1) == "=" then
                    local str = info.source:sub(3, -2)
                    local props = {}
                    -- Split by space
                    for v in string.gmatch(str, "[^%s]+") do
                        table.insert(props, v)
                    end
                    local source = table.remove(props, 1)
                    if source == "love" then
                        dumper:add_f("(%d) LÖVE %s at file '%s:%d'%s\r\n", level_to_show, function_type,
                            table.concat(props, " "):sub(2, -2), info.currentline, was_guessed and " (best guess)" or "")
                    elseif source == "SMODS" then
                        local modID = table.remove(props, 1)
                        local fileName = table.concat(props, " ")
                        if modID == '_' then
                            dumper:add_f("(%d) Lua %s '%s' at Steamodded file '%s:%d' %s\r\n", level_to_show,
                                function_type, function_name, fileName:sub(2, -2), info.currentline,
                                was_guessed and " (best guess)" or "")
                        else
                            dumper:add_f("(%d) Lua %s '%s' at file '%s:%d' (from mod with id %s)%s\r\n", level_to_show,
                                function_type, function_name, fileName:sub(2, -2), info.currentline, modID,
                                was_guessed and " (best guess)" or "")
                        end
                    elseif source == "lovely" then
                        local module = table.remove(props, 1)
                        local fileName = table.concat(props, " ")
                        dumper:add_f("(%d) Lua %s '%s' at file '%s:%d' (from lovely module %s)%s\r\n", level_to_show,
                            function_type, function_name, fileName:sub(2, -2), info.currentline, module,
                            was_guessed and " (best guess)" or "")
                    else
                        dumper:add_f("(%d) Lua %s '%s' at line %d of chunk '%s'\r\n", level_to_show, function_type,
                            function_name, info.currentline, source)
                    end
                else
                    dumper:add_f("(%d) Lua %s '%s' at line %d of chunk '%s'\r\n", level_to_show, function_type,
                        function_name, info.currentline, source)
                end
                dumper:DumpLocals(level)
            else
                dumper:add_f("(%d) unknown frame %s\r\n", level_to_show, info.what)
            end

            level = level + 1
            level_to_show = level_to_show + 1
            info = dumper.getinfo(level, "nSlf")
        end

        return dumper:concat_lines(), original_error
    end

    --
    -- Adds a table to the list of known tables
    function _M.add_known_table(tab, description)
        if m_known_tables[tab] then
            error("Cannot override an already known table")
        end
        m_user_known_tables[tab] = description
    end

    --
    -- Adds a function to the list of known functions
    function _M.add_known_function(fun, description)
        if m_known_functions[fun] then
            error("Cannot override an already known function")
        end
        m_user_known_functions[fun] = description
    end

    return _M
end

-- Note: The below code is not from the original StackTracePlus.lua
local stackTraceAlreadyInjected = false

function getDebugInfoForCrash()
    local version = VERSION
    if not version or type(version) ~= "string" then
        local versionFile = love.filesystem.read("version.jkr")
        if versionFile then
            version = versionFile:match("[^\n]*") .. " (best guess)"
        else
            version = "???"
        end
    end
    local modded_version = MODDED_VERSION
    if not modded_version or type(modded_version) ~= "string" then
        local moddedSuccess, reqVersion = pcall(require, "SMODS.version")
        if moddedSuccess and type(reqVersion) == "string" then
            modded_version = reqVersion
        else
            modded_version = "???"
        end
    end

    local info = "Additional Context:\nBalatro Version: " .. version .. "\nModded Version: " ..
                     (modded_version)
    local major, minor, revision, codename = love.getVersion()
    info = info .. string.format("\nLÖVE Version: %d.%d.%d", major, minor, revision)
    local lovely_success, lovely = pcall(require, "lovely")
    if lovely_success then
        info = info .. "\nLovely Version: " .. lovely.version
    end
	info = info .. "\nPlatform: " .. (love.system.getOS() or "???")
    if SMODS and SMODS.Mods then
        local mod_strings = ""
        local lovely_strings = ""
        local i = 1
        local lovely_i = 1
        for _, v in pairs(SMODS.Mods) do
            if (v.can_load and (not v.meta_mod or v.lovely_only)) or (v.lovely and not v.can_load and not v.disabled) then
                if v.lovely_only or (v.lovely and not v.can_load) then
                    lovely_strings = lovely_strings .. "\n    " .. lovely_i .. ": " .. v.name
                    lovely_i = lovely_i + 1
                    if not v.can_load then
                        lovely_strings = lovely_strings .. "\n        Has Steamodded mod that failed to load."
                        if #v.load_issues.dependencies > 0 then
                            lovely_strings = lovely_strings .. "\n        Missing Dependencies:"
                            for k, v in ipairs(v.load_issues.dependencies) do
                                lovely_strings = lovely_strings .. "\n            " .. k .. ". " .. v
                            end
                        end
                        if #v.load_issues.conflicts > 0 then
                            lovely_strings = lovely_strings .. "\n        Conflicts:"
                            for k, v in ipairs(v.load_issues.conflicts) do
                                lovely_strings = lovely_strings .. "\n            " .. k .. ". " .. v
                            end
                        end
                        if v.load_issues.outdated then
                            lovely_strings = lovely_strings .. "\n        Outdated Mod."
                        end
                        if v.load_issues.main_file_not_found then
                            lovely_strings = lovely_strings .. "\n        Main file not found. (" .. v.main_file ..")"
                        end
                    end
                else
                    mod_strings = mod_strings .. "\n    " .. i .. ": " .. v.name .. " by " ..
                                      table.concat(v.author, ", ") .. " [ID: " .. v.id ..
                                      (v.priority ~= 0 and (", Priority: " .. v.priority) or "") ..
                                      (v.version and v.version ~= '0.0.0' and (", Version: " .. v.version) or "") ..
                                      (v.lovely and (", Uses Lovely") or "") .. "]"
                    i = i + 1
                    local debugInfo = v.debug_info
                    if debugInfo then
                        if type(debugInfo) == "string" then
                            if #debugInfo ~= 0 then
                                mod_strings = mod_strings .. "\n        " .. debugInfo
                            end
                        elseif type(debugInfo) == "table" then
                            for kk, vv in pairs(debugInfo) do
                                if type(vv) ~= 'nil' then
                                    vv = tostring(vv)
                                end
                                if #vv ~= 0 then
                                    mod_strings = mod_strings .. "\n        " .. kk .. ": " .. vv
                                end
                            end
                        end
                    end
                end
            end
        end
        info = info .. "\nSteamodded Mods:" .. mod_strings .. "\nLovely Mods:" .. lovely_strings
    end
    return info
end

function injectStackTrace()
    if (stackTraceAlreadyInjected) then
        return
    end
    stackTraceAlreadyInjected = true
    local STP = loadStackTracePlus()
    local utf8 = require("utf8")

    -- Modifed from https://love2d.org/wiki/love.errorhandler
    function love.errorhandler(msg)
        msg = tostring(msg)

        if not sendErrorMessage then
            function sendErrorMessage(msg)
                print(msg)
            end
        end
        if not sendInfoMessage then
            function sendInfoMessage(msg)
                print(msg)
            end
        end

        sendErrorMessage("Oops! The game crashed\n" .. STP.stacktrace(msg), 'StackTrace')

        if not love.window or not love.graphics or not love.event then
            return
        end

        if not love.graphics.isCreated() or not love.window.isOpen() then
            local success, status = pcall(love.window.setMode, 800, 600)
            if not success or not status then
                return
            end
        end

        -- Reset state.
        if love.mouse then
            love.mouse.setVisible(true)
            love.mouse.setGrabbed(false)
            love.mouse.setRelativeMode(false)
            if love.mouse.isCursorSupported() then
                love.mouse.setCursor()
            end
        end
        if love.joystick then
            -- Stop all joystick vibrations.
            for i, v in ipairs(love.joystick.getJoysticks()) do
                v:setVibration()
            end
        end
        if love.audio then
            love.audio.stop()
        end

        love.graphics.reset()
        local font = love.graphics.setNewFont("resources/fonts/m6x11plus.ttf", 20)

        local background = {0, 0, 1}
        if G and G.C and G.C.BLACK then
            background = G.C.BLACK
        end
        love.graphics.clear(background)
        love.graphics.origin()

        local trace = STP.stacktrace("", 3)

        local sanitizedmsg = {}
        for char in msg:gmatch(utf8.charpattern) do
            table.insert(sanitizedmsg, char)
        end
        sanitizedmsg = table.concat(sanitizedmsg)

        local err = {}

        table.insert(err, "Oops! The game crashed:")
        if sanitizedmsg:find("Syntax error: game.lua:4: '=' expected near 'Game'") then
            table.insert(err,
                'Duplicate installation of Steamodded detected! Please clean your installation: Steam Library > Balatro > Properties > Installed Files > Verify integrity of game files.')
        elseif sanitizedmsg:find("Syntax error: game.lua:%d+: duplicate label 'continue'") then
            table.insert(err,
                'Duplicate installation of Steamodded detected! Please remove the duplicate steamodded/smods folder in your mods folder.')
        else
            table.insert(err, sanitizedmsg)
        end
        if #sanitizedmsg ~= #msg then
            table.insert(err, "Invalid UTF-8 string in error message.")
        end

        local success, msg = pcall(getDebugInfoForCrash)
        if success and msg then
            table.insert(err, '\n' .. msg)
            sendInfoMessage(msg, 'StackTrace')
        else
            table.insert(err, "\n" .. "Failed to get additional context :/")
            sendErrorMessage("Failed to get additional context :/\n" .. msg, 'StackTrace')
        end

        for l in trace:gmatch("(.-)\n") do
            table.insert(err, l)
        end

        local p = table.concat(err, "\n")

        p = p:gsub("\t", "")
        p = p:gsub("%[string \"(.-)\"%]", "%1")

        local scrollOffset = 0
        local endHeight = 0
        love.keyboard.setKeyRepeat(true)

        local function scrollDown(amt)
            if amt == nil then
                amt = 18
            end
            scrollOffset = scrollOffset + amt
            if scrollOffset > endHeight then
                scrollOffset = endHeight
            end
        end

        local function scrollUp(amt)
            if amt == nil then
                amt = 18
            end
            scrollOffset = scrollOffset - amt
            if scrollOffset < 0 then
                scrollOffset = 0
            end
        end

        local pos = 70
        local arrowSize = 20

        local function calcEndHeight()
            local font = love.graphics.getFont()
            local rw, lines = font:getWrap(p, love.graphics.getWidth() - pos * 2)
            local lineHeight = font:getHeight()
            local atBottom = scrollOffset == endHeight and scrollOffset ~= 0
            endHeight = #lines * lineHeight - love.graphics.getHeight() + pos * 2
            if (endHeight < 0) then
                endHeight = 0
            end
            if scrollOffset > endHeight or atBottom then
                scrollOffset = endHeight
            end
        end

        local function draw()
            if not love.graphics.isActive() then
                return
            end
            love.graphics.clear(background)
            calcEndHeight()
            love.graphics.printf(p, pos, pos - scrollOffset, love.graphics.getWidth() - pos * 2)
            if scrollOffset ~= endHeight then
                love.graphics.polygon("fill", love.graphics.getWidth() - (pos / 2),
                    love.graphics.getHeight() - arrowSize, love.graphics.getWidth() - (pos / 2) + arrowSize,
                    love.graphics.getHeight() - (arrowSize * 2), love.graphics.getWidth() - (pos / 2) - arrowSize,
                    love.graphics.getHeight() - (arrowSize * 2))
            end
            if scrollOffset ~= 0 then
                love.graphics.polygon("fill", love.graphics.getWidth() - (pos / 2), arrowSize,
                    love.graphics.getWidth() - (pos / 2) + arrowSize, arrowSize * 2,
                    love.graphics.getWidth() - (pos / 2) - arrowSize, arrowSize * 2)
            end
            love.graphics.present()
        end

        local fullErrorText = p
        local function copyToClipboard()
            if not love.system then
                return
            end
            love.system.setClipboardText(fullErrorText)
            p = p .. "\nCopied to clipboard!"
        end

        p = p .. "\n\nPress ESC to exit\nPress R to restart the game"
        if love.system then
            p = p .. "\nPress Ctrl+C or tap to copy this error"
        end

        if G then
            -- Kill threads (makes restarting possible)
            if G.SOUND_MANAGER and G.SOUND_MANAGER.channel then
                G.SOUND_MANAGER.channel:push({
                    type = 'kill'
                })
            end
            if G.SAVE_MANAGER and G.SAVE_MANAGER.channel then
                G.SAVE_MANAGER.channel:push({
                    type = 'kill'
                })
            end
            if G.HTTP_MANAGER and G.HTTP_MANAGER.channel then
                G.HTTP_MANAGER.channel:push({
                    type = 'kill'
                })
            end
        end

        return function()
            love.event.pump()

            for e, a, b, c in love.event.poll() do
                if e == "quit" then
                    return 1
                elseif e == "keypressed" and a == "escape" then
                    return 1
                elseif e == "keypressed" and a == "c" and love.keyboard.isDown("lctrl", "rctrl") then
                    copyToClipboard()
                elseif e == "keypressed" and a == "r" then
                    SMODS.restart_game()
                elseif e == "keypressed" and a == "down" then
                    scrollDown()
                elseif e == "keypressed" and a == "up" then
                    scrollUp()
                elseif e == "keypressed" and a == "pagedown" then
                    scrollDown(love.graphics.getHeight())
                elseif e == "keypressed" and a == "pageup" then
                    scrollUp(love.graphics.getHeight())
                elseif e == "keypressed" and a == "home" then
                    scrollOffset = 0
                elseif e == "keypressed" and a == "end" then
                    scrollOffset = endHeight
                elseif e == "wheelmoved" then
                    scrollUp(b * 20)
                elseif e == "gamepadpressed" and b == "dpdown" then
                    scrollDown()
                elseif e == "gamepadpressed" and b == "dpup" then
                    scrollUp()
                elseif e == "gamepadpressed" and b == "a" then
                    return "restart"
                elseif e == "gamepadpressed" and b == "x" then
                    copyToClipboard()
                elseif e == "gamepadpressed" and (b == "b" or b == "back" or b == "start") then
                    return 1
                elseif e == "touchpressed" then
                    local name = love.window.getTitle()
                    if #name == 0 or name == "Untitled" then
                        name = "Game"
                    end
                    local buttons = {"OK", "Cancel", "Restart"}
                    if love.system then
                        buttons[4] = "Copy to clipboard"
                    end
                    local pressed = love.window.showMessageBox("Quit " .. name .. "?", "", buttons)
                    if pressed == 1 then
                        return 1
                    elseif pressed == 3 then
                        return "restart"
                    elseif pressed == 4 then
                        copyToClipboard()
                    end
                end
            end

            draw()

            if love.timer then
                love.timer.sleep(0.1)
            end
        end

    end
end

injectStackTrace()

-- ----------------------------------------------
-- --------MOD CORE API STACKTRACE END-----------

if (love.system.getOS() == 'OS X' ) and (jit.arch == 'arm64' or jit.arch == 'arm') then jit.off() end
do
    local logger = require("debugplus.logger")
    logger.registerLogHandler()
end
require "engine/object"
require "bit"
require "engine/string_packer"
require "engine/controller"
require "back"
require "tag"
require "engine/event"
require "engine/node"
require "engine/moveable"
require "engine/sprite"
require "engine/animatedsprite"
require "functions/misc_functions"
require "game"
require "globals"
require "engine/ui"
require "functions/UI_definitions"
require "functions/state_events"
require "functions/common_events"
require "functions/button_callbacks"
require "functions/misc_functions"
require "functions/test_functions"
require "card"
require "cardarea"
require "blind"
require "card_character"
require "engine/particles"
require "engine/text"
require "challenges"

math.randomseed( G.SEED )

function love.run()
	if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

	-- We don't want the first frame's dt to include time taken by love.load.
	if love.timer then love.timer.step() end

	local dt = 0
	local dt_smooth = 1/100
	local run_time = 0

	-- Main loop time.
	return function()
		run_time = love.timer.getTime()
		-- Process events.
		if love.event and G and G.CONTROLLER then
			love.event.pump()
			local _n,_a,_b,_c,_d,_e,_f,touched
			for name, a,b,c,d,e,f in love.event.poll() do
				if name == "quit" then
					if not love.quit or not love.quit() then
						return a or 0
					end
				end
				if name == 'touchpressed' then
					touched = true
				elseif name == 'mousepressed' then 
					_n,_a,_b,_c,_d,_e,_f = name,a,b,c,d,e,f
				else
					love.handlers[name](a,b,c,d,e,f)
				end
			end
			if _n then 
				love.handlers['mousepressed'](_a,_b,_c,touched)
			end
		end

		-- Update dt, as we'll be passing it to update
		if love.timer then dt = love.timer.step() end
		dt_smooth = math.min(0.8*dt_smooth + 0.2*dt, 0.1)
		-- Call update and draw
		if love.update then love.update(dt_smooth) end -- will pass 0 if love.timer is disabled

		if love.graphics and love.graphics.isActive() then
			if love.draw then love.draw() end
			love.graphics.present()
		end

		run_time = math.min(love.timer.getTime() - run_time, 0.1)
		G.FPS_CAP = G.FPS_CAP or 500
		if run_time < 1./G.FPS_CAP then love.timer.sleep(1./G.FPS_CAP - run_time) end
	end
end

Cryptid = {}
Cryptid.aliases = {}
function cry_format(...)
	return ...
end

-- These ones are deprecated, they do not do anything and are just here to prevent crashes
Cryptid.memepack = {}
Cryptid.food = {}
Cryptid.M_jokers = {}
Cryptid.Megavouchers = {}
Jen = {}
function love.load() 
	G:start_up()
	--Steam integration
	local os = love.system.getOS()
	if os == 'OS X' or os == 'Windows' or os == 'Linux' then
		local st = nil
		--To control when steam communication happens, make sure to send updates to steam as little as possible
		local cwd = NFS.getWorkingDirectory()
		NFS.setWorkingDirectory(love.filesystem.getSourceBaseDirectory())
		if os == 'OS X' or os == 'Linux' then
			local dir = love.filesystem.getSourceBaseDirectory()
			local old_cpath = package.cpath
			package.cpath = package.cpath .. ';' .. dir .. '/?.so'
			local success, _st = pcall(require, 'luasteam')
			if success then st = _st else sendWarnMessage(_st, "LuaSteam"); st = {} end
			package.cpath = old_cpath
		else
			local success, _st = pcall(require, 'luasteam')
			if success then st = _st else sendWarnMessage(_st, "LuaSteam"); st = {} end
		end

		st.send_control = {
			last_sent_time = -200,
			last_sent_stage = -1,
			force = false,
		}
		if not (st.init and st:init()) then
			st = nil
		end
		NFS.setWorkingDirectory(cwd)
		--Set up the render window and the stage for the splash screen, then enter the gameloop with :update
		G.STEAM = st
	else
	end

	--Set the mouse to invisible immediately, this visibility is handled in the G.CONTROLLER
	love.mouse.setVisible(false)
end

function love.quit()
	--Steam integration
	if G.SOUND_MANAGER then G.SOUND_MANAGER.channel:push({type = 'stop'}) end
	if G.STEAM then G.STEAM:shutdown() end
end

function love.update( dt )
	--Perf monitoring checkpoint
    timer_checkpoint(nil, 'update', true)
    G:update(dt)
end

function love.draw()
	--Perf monitoring checkpoint
    timer_checkpoint(nil, 'draw', true)
	G:draw()
	do
	    local console = require("debugplus.console")
	    console.doConsoleRender()
	    timer_checkpoint('DebugPlus Console', 'draw')
	end
end

function love.keypressed(key)
if Handy.controller.process_key(key, false) then return end
local console = require("debugplus.console")
if not console.consoleHandleKey(key) then return end
	if not _RELEASE_MODE and G.keybind_mapping[key] then love.gamepadpressed(G.CONTROLLER.keyboard_controller, G.keybind_mapping[key])
	else
		G.CONTROLLER:set_HID_flags('mouse')
		G.CONTROLLER:key_press(key)
	end
end

function love.keyreleased(key)
if Handy.controller.process_key(key, true) then return end
	if not _RELEASE_MODE and G.keybind_mapping[key] then love.gamepadreleased(G.CONTROLLER.keyboard_controller, G.keybind_mapping[key])
	else
		G.CONTROLLER:set_HID_flags('mouse')
		G.CONTROLLER:key_release(key)
	end
end

function love.gamepadpressed(joystick, button)
	button = G.button_mapping[button] or button
	G.CONTROLLER:set_gamepad(joystick)
    G.CONTROLLER:set_HID_flags('button', button)
    G.CONTROLLER:button_press(button)
end

function love.gamepadreleased(joystick, button)
	button = G.button_mapping[button] or button
    G.CONTROLLER:set_gamepad(joystick)
    G.CONTROLLER:set_HID_flags('button', button)
    G.CONTROLLER:button_release(button)
end

function love.mousepressed(x, y, button, touch)
if not touch and Handy.controller.process_mouse(button, false) then return end
    G.CONTROLLER:set_HID_flags(touch and 'touch' or 'mouse')
    if button == 1 then 
		G.CONTROLLER:queue_L_cursor_press(x, y)
	end
	if button == 2 then
		G.CONTROLLER:queue_R_cursor_press(x, y)
	end
end


function love.mousereleased(x, y, button)
if Handy.controller.process_mouse(button, true) then return end
    if button == 1 then G.CONTROLLER:L_cursor_release(x, y) end
end

function love.mousemoved(x, y, dx, dy, istouch)
	G.CONTROLLER.last_touch_time = G.CONTROLLER.last_touch_time or -1
	if next(love.touch.getTouches()) ~= nil then
		G.CONTROLLER.last_touch_time = G.TIMERS.UPTIME
	end
    G.CONTROLLER:set_HID_flags(G.CONTROLLER.last_touch_time > G.TIMERS.UPTIME - 0.2 and 'touch' or 'mouse')
end

function love.joystickaxis( joystick, axis, value )
    if math.abs(value) > 0.2 and joystick:isGamepad() then
		G.CONTROLLER:set_gamepad(joystick)
        G.CONTROLLER:set_HID_flags('axis')
    end
end

if false then
	if G.F_NO_ERROR_HAND then return end
	msg = tostring(msg)

	if G.SETTINGS.crashreports and _RELEASE_MODE and G.F_CRASH_REPORTS then 
		local http_thread = love.thread.newThread([[
			local https = require('https')
			CHANNEL = love.thread.getChannel("http_channel")

			while true do
				--Monitor the channel for any new requests
				local request = CHANNEL:demand()
				if request then
					https.request(request)
				end
			end
		]])
		local http_channel = love.thread.getChannel('http_channel')
		http_thread:start()
		local httpencode = function(str)
			local char_to_hex = function(c)
				return string.format("%%%02X", string.byte(c))
			end
			str = str:gsub("\n", "\r\n"):gsub("([^%w _%%%-%.~])", char_to_hex):gsub(" ", "+")
			return str
		end
		

		local error = msg
		local file = string.sub(msg, 0,  string.find(msg, ':'))
		local function_line = string.sub(msg, string.len(file)+1)
		function_line = string.sub(function_line, 0, string.find(function_line, ':')-1)
		file = string.sub(file, 0, string.len(file)-1)
		local trace = debug.traceback()
		local boot_found, func_found = false, false
		for l in string.gmatch(trace, "(.-)\n") do
			if string.match(l, "boot.lua") then
				boot_found = true
			elseif boot_found and not func_found then
				func_found = true
				trace = ''
				function_line = string.sub(l, string.find(l, 'in function')+12)..' line:'..function_line
			end

			if boot_found and func_found then 
				trace = trace..l..'\n'
			end
		end

		http_channel:push('https://958ha8ong3.execute-api.us-east-2.amazonaws.com/?error='..httpencode(error)..'&file='..httpencode(file)..'&function_line='..httpencode(function_line)..'&trace='..httpencode(trace)..'&version='..(G.VERSION))
	end

	if not love.window or not love.graphics or not love.event then
		return
	end

	if not love.graphics.isCreated() or not love.window.isOpen() then
		local success, status = pcall(love.window.setMode, 800, 600)
		if not success or not status then
			return
		end
	end

	-- Reset state.
	if love.mouse then
		love.mouse.setVisible(true)
		love.mouse.setGrabbed(false)
		love.mouse.setRelativeMode(false)
	end
	if love.joystick then
		-- Stop all joystick vibrations.
		for i,v in ipairs(love.joystick.getJoysticks()) do
			v:setVibration()
		end
	end
	if love.audio then love.audio.stop() end
	love.graphics.reset()
	local font = love.graphics.setNewFont("resources/fonts/m6x11plus.ttf", 20)

	love.graphics.clear(G.C.BLACK)
	love.graphics.origin()


	local p = 'Oops! Something went wrong:\n'..msg..'\n\n'..(not _RELEASE_MODE and debug.traceback() or G.SETTINGS.crashreports and
		'Since you are opted in to sending crash reports, LocalThunk HQ was sent some useful info about what happened.\nDon\'t worry! There is no identifying or personal information. If you would like\nto opt out, change the \'Crash Report\' setting to Off' or
		'Crash Reports are set to Off. If you would like to send crash reports, please opt in in the Game settings.\nThese crash reports help us avoid issues like this in the future')

	local function draw()
		local pos = love.window.toPixels(70)
		love.graphics.push()
		love.graphics.clear(G.C.BLACK)
		love.graphics.setColor(1., 1., 1., 1.)
		love.graphics.printf(p, font, pos, pos, love.graphics.getWidth() - pos)
		love.graphics.pop()
		love.graphics.present()

	end

	while true do
		love.event.pump()

		for e, a, b, c in love.event.poll() do
			if e == "quit" then
				return
			elseif e == "keypressed" and a == "escape" then
				return
			elseif e == "touchpressed" then
				local name = love.window.getTitle()
				if #name == 0 or name == "Untitled" then name = "Game" end
				local buttons = {"OK", "Cancel"}
				local pressed = love.window.showMessageBox("Quit "..name.."?", "", buttons)
				if pressed == 1 then
					return
				end
			end
		end

		draw()

		if love.timer then
			love.timer.sleep(0.1)
		end
	end

end

function love.resize(w, h)
	if w/h < 1 then --Dont allow the screen to be too square, since pop in occurs above and below screen
		h = w/1
	end

	--When the window is resized, this code resizes the Canvas, then places the 'room' or gamearea into the middle without streching it
	if w/h < G.window_prev.orig_ratio then
		G.TILESCALE = G.window_prev.orig_scale*w/G.window_prev.w
	else
		G.TILESCALE = G.window_prev.orig_scale*h/G.window_prev.h
	end

	if G.ROOM then
		G.ROOM.T.w = G.TILE_W
		G.ROOM.T.h = G.TILE_H
		G.ROOM_ATTACH.T.w = G.TILE_W
		G.ROOM_ATTACH.T.h = G.TILE_H		

		if w/h < G.window_prev.orig_ratio then
			G.ROOM.T.x = G.ROOM_PADDING_W
			G.ROOM.T.y = (h/(G.TILESIZE*G.TILESCALE) - (G.ROOM.T.h+G.ROOM_PADDING_H))/2 + G.ROOM_PADDING_H/2
		else
			G.ROOM.T.y = G.ROOM_PADDING_H
			G.ROOM.T.x = (w/(G.TILESIZE*G.TILESCALE) - (G.ROOM.T.w+G.ROOM_PADDING_W))/2 + G.ROOM_PADDING_W/2
		end

		G.ROOM_ORIG = {
            x = G.ROOM.T.x,
            y = G.ROOM.T.y,
            r = G.ROOM.T.r
        }

		if G.buttons then G.buttons:recalculate() end
		if G.HUD then G.HUD:recalculate() end
	end

	G.WINDOWTRANS = {
		x = 0, y = 0,
		w = G.TILE_W+2*G.ROOM_PADDING_W, 
		h = G.TILE_H+2*G.ROOM_PADDING_H,
		real_window_w = w,
		real_window_h = h
	}

	G.CANV_SCALE = 1

	if love.system.getOS() == 'Windows' and false then --implement later if needed
		local render_w, render_h = love.window.getDesktopDimensions(G.SETTINGS.WINDOW.selcted_display)
		local unscaled_dims = love.window.getFullscreenModes(G.SETTINGS.WINDOW.selcted_display)[1]

		local DPI_scale = math.floor((0.5*unscaled_dims.width/render_w + 0.5*unscaled_dims.height/render_h)*500 + 0.5)/500

		if DPI_scale > 1.1 then
			G.CANV_SCALE = 1.5

			G.AA_CANVAS = love.graphics.newCanvas(G.WINDOWTRANS.real_window_w*G.CANV_SCALE, G.WINDOWTRANS.real_window_h*G.CANV_SCALE, {type = '2d', readable = true})
			G.AA_CANVAS:setFilter('linear', 'linear')
		else
			G.AA_CANVAS = nil
		end
	end

	G.CANVAS = love.graphics.newCanvas(w*G.CANV_SCALE, h*G.CANV_SCALE, {type = '2d', readable = true})
	G.CANVAS:setFilter('linear', 'linear')
end 

--- STEAMODDED CORE
--- MODULE CORE

SMODS = {}
MODDED_VERSION = require'SMODS.version'
SMODS.id = 'Steamodded'
SMODS.version = MODDED_VERSION:gsub('%-STEAMODDED', '')
SMODS.can_load = true
SMODS.meta_mod = true
SMODS.config_file = 'config.lua'

-- Include lovely and nativefs modules
local nativefs = require "nativefs"
local lovely = require "lovely"
local json = require "json"

local lovely_mod_dir = lovely.mod_dir:gsub("/$", "")
NFS = nativefs
-- make lovely_mod_dir an absolute path.
-- respects symlink/.. combos
NFS.setWorkingDirectory(lovely_mod_dir)
lovely_mod_dir = NFS.getWorkingDirectory()
-- make sure NFS behaves the same as love.filesystem
NFS.setWorkingDirectory(love.filesystem.getSaveDirectory())

JSON = json

local function set_mods_dir()
    local love_dirs = {
        love.filesystem.getSaveDirectory(),
        love.filesystem.getSourceBaseDirectory()
    }
    for _, love_dir in ipairs(love_dirs) do
        if lovely_mod_dir:sub(1, #love_dir) == love_dir then
            -- relative path from love_dir
            SMODS.MODS_DIR = lovely_mod_dir:sub(#love_dir+2)
            NFS.setWorkingDirectory(love_dir)
            return
        end
    end
    SMODS.MODS_DIR = lovely_mod_dir
end
set_mods_dir()

local function find_self(directory, target_filename, target_line, depth)
    depth = depth or 1
    if depth > 3 then return end
    for _, filename in ipairs(NFS.getDirectoryItems(directory)) do
        local file_path = directory .. "/" .. filename
        local file_type = NFS.getInfo(file_path).type
        if file_type == 'directory' or file_type == 'symlink' then
            local f = find_self(file_path, target_filename, target_line, depth+1)
            if f then return f end
        elseif filename == target_filename then
            local first_line = NFS.read(file_path):match('^(.-)\n')
            if first_line == target_line then
                -- use parent directory
                return directory:match('^(.+/)')
            end
        end
    end
end

SMODS.path = find_self(SMODS.MODS_DIR, 'core.lua', '--- STEAMODDED CORE')

for _, path in ipairs {
    "src/ui.lua",
    "src/index.lua",
    "src/utils.lua",
    "src/overrides.lua",
    "src/game_object.lua",
    "src/logging.lua",
    "src/compat_0_9_8.lua",
    "src/loader.lua",
} do
    assert(load(NFS.read(SMODS.path..path), ('=[SMODS _ "%s"]'):format(path)))()
end

sendInfoMessage("Steamodded v" .. SMODS.version, "SMODS")

Handy = setmetatable({
	version = "1.4.1a",

	last_clicked_area = nil,
	last_clicked_card = nil,

	last_hovered_area = nil,
	last_hovered_card = nil,

	utils = {},
}, {})

--- @generic T
--- @generic S
--- @param target T
--- @param source S
--- @param ... any
--- @return T | S
function Handy.utils.table_merge(target, source, ...)
	assert(type(target) == "table", "Target is not a table")
	local tables_to_merge = { source, ... }
	if #tables_to_merge == 0 then
		return target
	end

	for k, t in ipairs(tables_to_merge) do
		assert(type(t) == "table", string.format("Expected a table as parameter %d", k))
	end

	for i = 1, #tables_to_merge do
		local from = tables_to_merge[i]
		for k, v in pairs(from) do
			if type(k) == "number" then
				table.insert(target, v)
			elseif type(k) == "string" then
				if type(v) == "table" then
					target[k] = target[k] or {}
					target[k] = Handy.utils.table_merge(target[k], v)
				else
					target[k] = v
				end
			end
		end
	end

	return target
end

function Handy.utils.table_contains(t, value)
	for i = #t, 1, -1 do
		if t[i] and t[i] == value then
			return true
		end
	end
	return false
end

function Handy.utils.serialize_string(s)
	return string.format("%q", s)
end

function Handy.utils.serialize(t, indent)
	indent = indent or ""
	local str = "{\n"
	for k, v in ipairs(t) do
		str = str .. indent .. "\t"
		if type(v) == "number" then
			str = str .. v
		elseif type(v) == "boolean" then
			str = str .. (v and "true" or "false")
		elseif type(v) == "string" then
			str = str .. Handy.utils.serialize_string(v)
		elseif type(v) == "table" then
			str = str .. Handy.utils.serialize(v, indent .. "\t")
		else
			-- not serializable
			str = str .. "nil"
		end
		str = str .. ",\n"
	end
	for k, v in pairs(t) do
		if type(k) == "string" then
			str = str .. indent .. "\t" .. "[" .. Handy.utils.serialize_string(k) .. "] = "

			if type(v) == "number" then
				str = str .. v
			elseif type(v) == "boolean" then
				str = str .. (v and "true" or "false")
			elseif type(v) == "string" then
				str = str .. Handy.utils.serialize_string(v)
			elseif type(v) == "table" then
				str = str .. Handy.utils.serialize(v, indent .. "\t")
			else
				-- not serializable
				str = str .. "nil"
			end
			str = str .. ",\n"
		end
	end
	str = str .. indent .. "}"
	return str
end

--

Handy.config = {
	default = {
		handy = {
			enabled = true,
		},

		notifications_level = 3,
		keybinds_trigger_mode = 1,
		insta_actions_trigger_mode = 1,
		hide_in_menu = false,

		insta_highlight = {
			enabled = true,
		},
		insta_highlight_entire_f_hand = {
			enabled = true,
			key_1 = "None",
			key_2 = "None",
		},
		insta_buy_n_sell = {
			enabled = true,
			key_1 = "None",
			key_2 = "None",
		},
		insta_buy_or_sell = {
			enabled = true,
			key_1 = "Shift",
			key_2 = "None",
		},
		insta_use = {
			enabled = true,
			key_1 = "Ctrl",
			key_2 = "None",
		},
		move_highlight = {
			enabled = true,

			swap = {
				enabled = true,
				key_1 = "Shift",
				key_2 = "None",
			},
			to_end = {
				enabled = true,
				key_1 = "Ctrl",
				key_2 = "None",
			},

			dx = {
				one_left = {
					enabled = true,
					key_1 = "Left",
					key_2 = "None",
				},
				one_right = {
					enabled = true,
					key_1 = "Right",
					key_2 = "None",
				},
			},
		},

		insta_cash_out = {
			enabled = true,
			key_1 = "Enter",
			key_2 = "None",
		},
		insta_booster_skip = {
			enabled = true,
			key_1 = "Enter",
			key_2 = "None",
		},
		show_deck_preview = {
			enabled = true,
			key_1 = "None",
			key_2 = "None",
		},

		dangerous_actions = {
			enabled = false,

			-- Use it as basic modifier for all dangerous controls
			-- Maybe I should change this but idk, backwards compatibility
			immediate_buy_and_sell = {
				enabled = true,
				key_1 = "Middle Mouse",
				key_2 = "None",

				queue = {
					enabled = false,
				},
			},

			sell_all_same = {
				enabled = false,
				key_1 = "None",
				key_2 = "None",
			},

			sell_all = {
				enabled = false,
				key_1 = "None",
				key_2 = "None",
			},

			card_remove = {
				enabled = false,
				key_1 = "None",
				key_2 = "None",
			},

			nopeus_unsafe = {
				enabled = true,
			},
		},

		speed_multiplier = {
			enabled = true,

			key_1 = "Alt",
			key_2 = "None",
		},

		deselect_hand = {
			enabled = true,
			key_1 = "Right Mouse",
			key_2 = "None",
		},

		regular_keybinds = {
			enabled = true,

			play = {
				enabled = true,
				key_1 = "None",
				key_2 = "None",
			},
			discard = {
				enabled = true,
				key_1 = "None",
				key_2 = "None",
			},
			sort_by_rank = {
				enabled = true,
				key_1 = "None",
				key_2 = "None",
			},
			sort_by_suit = {
				enabled = true,
				key_1 = "None",
				key_2 = "None",
			},

			reroll_shop = {
				enabled = true,
				key_1 = "Q",
				key_2 = "None",
			},
			leave_shop = {
				enabled = true,
				key_1 = "None",
				key_2 = "None",
			},

			skip_blind = {
				enabled = true,
				key_1 = "None",
				key_2 = "None",
			},
			select_blind = {
				enabled = true,
				key_1 = "None",
				key_2 = "None",
			},

			run_info = {
				enabled = true,
				key_1 = "None",
				key_2 = "None",
			},
			run_info_blinds = {
				enabled = true,
				key_1 = "None",
				key_2 = "None",
			},

			view_deck = {
				enabled = true,
				key_1 = "None",
				key_2 = "None",
			},
		},

		nopeus_interaction = {
			enabled = true,

			key_1 = "]",
			key_2 = "None",
		},

		not_just_yet_interaction = {
			enabled = true,
			key_1 = "Enter",
			key_2 = "None",
		},

		cryptid_code_use_last_interaction = {
			enabled = true,
			key_1 = "None",
			key_2 = "None",
		},
	},
	current = {},

	get_module = function(module)
		if not module then
			return nil
		end
		local override = Handy.get_module_override(module)
		if override then
			return Handy.utils.table_merge({}, module, override)
		end
		return module
	end,
	save = function()
		if SMODS and SMODS.save_mod_config and Handy.current_mod then
			Handy.current_mod.config = Handy.config.current
			SMODS.save_mod_config(Handy.current_mod)
		else
			love.filesystem.createDirectory("config")
			local serialized = "return " .. Handy.utils.serialize(Handy.config.current)
			love.filesystem.write("config/Handy.jkr", serialized)
		end
	end,
	load = function()
		Handy.config.current = Handy.utils.table_merge({}, Handy.config.default)
		local lovely_mod_config = get_compressed("config/Handy.jkr")
		if lovely_mod_config then
			Handy.config.current = Handy.utils.table_merge(Handy.config.current, STR_UNPACK(lovely_mod_config))
		end
		Handy.cc = Handy.config.current
	end,
}

-- Shorthand for `Handy.config.current`
Handy.cc = Handy.config.current
Handy.config.load()

function Handy.is_mod_active()
	return Handy.cc.handy.enabled
end
function Handy.is_dangerous_actions_active()
	return Handy.cc.dangerous_actions.enabled
end
function Handy.get_module_override(module)
	return nil
end

-- Ha-ha, funny Cryptid reference

-- Resolve module with overrides
function Handy.m(module)
	return Handy.config.get_module(module)
end

--

Handy.fake_events = {
	check = function(arg)
		local fake_event = {
			UIBox = arg.UIBox,
			config = {
				ref_table = arg.card,
				button = arg.button,
				id = arg.id,
			},
		}
		arg.func(fake_event)
		return fake_event.config.button ~= nil, fake_event.config.button
	end,
	execute = function(arg)
		if type(arg.func) == "function" then
			arg.func({
				UIBox = arg.UIBox,
				config = {
					ref_table = arg.card,
					button = arg.button,
					id = arg.id,
				},
			})
		end
	end,
}
Handy.controller = {
	bind_module = nil,
	bind_key = nil,
	bind_button = nil,

	update_bind_button_text = function(text)
		local button_text = Handy.controller.bind_button.children[1].children[1]
		button_text.config.text_drawable = nil
		button_text.config.text = text
		button_text:update_text()
		button_text.UIBox:recalculate()
	end,
	init_bind = function(button)
		button.config.button = nil
		Handy.controller.bind_button = button
		Handy.controller.bind_module = button.config.ref_table.module
		Handy.controller.bind_key = button.config.ref_table.key

		Handy.controller.update_bind_button_text(
			"[" .. (Handy.controller.bind_module[Handy.controller.bind_key] or "None") .. "]"
		)
	end,
	complete_bind = function(key)
		Handy.controller.bind_module[Handy.controller.bind_key] = key
		Handy.controller.update_bind_button_text(key or "None")

		Handy.controller.bind_button.config.button = "handy_init_keybind_change"
		Handy.controller.bind_button = nil
		Handy.controller.bind_module = nil
		Handy.controller.bind_key = nil
	end,
	cancel_bind = function()
		Handy.controller.update_bind_button_text(Handy.controller.bind_module[Handy.controller.bind_key] or "None")

		Handy.controller.bind_button.config.button = "handy_init_keybind_change"
		Handy.controller.bind_button = nil
		Handy.controller.bind_module = nil
		Handy.controller.bind_key = nil
	end,

	process_bind = function(key)
		if not Handy.controller.bind_button then
			return false
		end
		local parsed_key = Handy.controller.parse(key)
		if parsed_key == "Escape" then
			parsed_key = "None"
		end
		Handy.controller.complete_bind(parsed_key)
		Handy.config.save()
		return true
	end,

	parse_table = {
		["mouse1"] = "Left Mouse",
		["mouse2"] = "Right Mouse",
		["mouse3"] = "Middle Mouse",
		["mouse4"] = "Mouse 4",
		["mouse5"] = "Mouse 5",
		["wheelup"] = "Wheel Up",
		["wheeldown"] = "Wheel Down",
		["lshift"] = "Shift",
		["rshift"] = "Shift",
		["lctrl"] = "Ctrl",
		["rctrl"] = "Ctrl",
		["lalt"] = "Alt",
		["ralt"] = "Alt",
		["lgui"] = "GUI",
		["rgui"] = "GUI",
		["return"] = "Enter",
		["kpenter"] = "Enter",
		["pageup"] = "Page Up",
		["pagedown"] = "Page Down",
		["numlock"] = "Num Lock",
		["capslock"] = "Caps Lock",
		["scrolllock"] = "Scroll Lock",
	},
	resolve_table = {
		["Left Mouse"] = { "mouse1" },
		["Right Mouse"] = { "mouse2" },
		["Middle Mouse"] = { "mouse3" },
		["Mouse 4"] = { "mouse4" },
		["Mouse 5"] = { "mouse5" },
		["Wheel Up"] = { "wheelup" },
		["Wheel Down"] = { "wheeldown" },
		["Shift"] = { "lshift", "rshift" },
		["Ctrl"] = { "lctrl", "rctrl" },
		["Alt"] = { "lalt", "ralt" },
		["GUI"] = { "lgui", "rgui" },
		["Enter"] = { "return", "kpenter" },
		["Page Up"] = { "pageup" },
		["Page Down"] = { "pagedown" },
		["Num Lock"] = { "numlock" },
		["Caps Lock"] = { "capslock" },
		["Scroll Lock"] = { "scrolllock" },
	},

	mouse_to_key_table = {
		[1] = "mouse1",
		[2] = "mouse2",
		[3] = "mouse3",
		[4] = "mouse4",
		[5] = "mouse5",
	},
	wheel_to_key_table = {
		[1] = "wheelup",
		[2] = "wheeldown",
	},

	mouse_buttons = {
		["Left Mouse"] = 1,
		["Right Mouse"] = 2,
		["Middle Mouse"] = 3,
		["Mouse 4"] = 4,
		["Mouse 5"] = 5,
	},
	wheel_buttons = {
		["Wheel Up"] = 1,
		["Wheel Down"] = 2,
	},

	parse = function(raw_key)
		if not raw_key then
			return nil
		end
		if Handy.controller.parse_table[raw_key] then
			return Handy.controller.parse_table[raw_key]
		elseif string.sub(raw_key, 1, 2) == "kp" then
			return "NUM " .. string.sub(raw_key, 3)
		else
			return string.upper(string.sub(raw_key, 1, 1)) .. string.sub(raw_key, 2)
		end
	end,
	resolve = function(parsed_key)
		if not parsed_key then
			return nil
		end
		if Handy.controller.resolve_table[parsed_key] then
			return unpack(Handy.controller.resolve_table[parsed_key])
		elseif string.sub(parsed_key, 1, 4) == "NUM " then
			return "kp" .. string.sub(parsed_key, 5)
		else
			local str = string.gsub(string.lower(parsed_key), "%s+", "")
			return str
		end
	end,
	is_down = function(...)
		local parsed_keys = { ... }
		for i = 1, #parsed_keys do
			local parsed_key = parsed_keys[i]
			if parsed_key and parsed_key ~= "Unknown" and parsed_key ~= "None" then
				if Handy.controller.wheel_buttons[parsed_key] then
					-- Well, skip
				elseif Handy.controller.mouse_buttons[parsed_key] then
					if love.mouse.isDown(Handy.controller.mouse_buttons[parsed_key]) then
						return true
					end
				else
					local success, is_down = pcall(function()
						return love.keyboard.isDown(Handy.controller.resolve(parsed_key))
					end)
					if success and is_down then
						return true
					end
				end
			end
		end
		return false
	end,
	is = function(raw_key, ...)
		if not raw_key then
			return false
		end
		local parsed_keys = { ... }
		for i = 1, #parsed_keys do
			local parsed_key = parsed_keys[i]
			if parsed_key then
				local resolved_key_1, resolved_key_2 = Handy.controller.resolve(parsed_key)
				if
					raw_key
					and raw_key ~= "Unknown"
					and raw_key ~= "None"
					and (raw_key == resolved_key_1 or raw_key == resolved_key_2)
				then
					return true
				end
			end
		end
		return false
	end,

	is_module_key_down = function(module, allow_disabled)
		module = Handy.m(module)
		return module and (allow_disabled or module.enabled) and Handy.controller.is_down(module.key_1, module.key_2)
	end,
	is_module_key = function(module, raw_key, allow_disabled)
		module = Handy.m(module)
		return module
			and (allow_disabled or module.enabled)
			and Handy.controller.is(raw_key, module.key_1, module.key_2)
	end,
	is_module_enabled = function(module)
		module = Handy.m(module)
		return module and module.enabled
	end,

	is_trigger_on_release = function()
		return Handy.cc.keybinds_trigger_mode == 2
	end,
	is_triggered = function(released)
		if Handy.controller.is_trigger_on_release() then
			return released
		end
		return not released
	end,

	process_key = function(key, released)
		if not Handy.is_mod_active() then
			return false
		end
		if G.CONTROLLER.text_input_hook then
			return false
		end
		if not released and Handy.controller.process_bind(key) then
			return true
		end

		if key == "escape" then
			return false
		end

		if not released then
			Handy.speed_multiplier.use(key)
		end

		if G.STAGE == G.STAGES.RUN and not G.SETTINGS.paused then
			if Handy.controller.is_triggered(released) then
				Handy.insta_actions.use_alt(key)
				Handy.move_highlight.use(key)
				Handy.regular_keybinds.use(key)
				Handy.insta_highlight_entire_f_hand.use(key)
				Handy.deselect_hand.use(key)
			end

			Handy.dangerous_actions.toggle_queue(key, released)
		end

		Handy.UI.state_panel.update(key, released)

		return false
	end,
	process_mouse = function(mouse, released)
		if not Handy.is_mod_active() then
			return false
		end
		if G.CONTROLLER.text_input_hook then
			return false
		end
		local key = Handy.controller.mouse_to_key_table[mouse]

		if not released and Handy.controller.process_bind(key) then
			return true
		end

		if not released then
			Handy.speed_multiplier.use(key)
		end

		if G.STAGE == G.STAGES.RUN and not G.SETTINGS.paused and not G.OVERLAY_MENU then
			if Handy.controller.is_triggered(released) then
				Handy.insta_actions.use_alt(key)
				Handy.move_highlight.use(key)
				Handy.regular_keybinds.use(key)
				Handy.insta_highlight_entire_f_hand.use(key)
				Handy.deselect_hand.use(key)
			end

			Handy.dangerous_actions.toggle_queue(key, released)
		end

		Handy.UI.state_panel.update(key, released)

		return false
	end,
	process_wheel = function(wheel)
		if not Handy.is_mod_active() then
			return false
		end
		if G.CONTROLLER.text_input_hook then
			return false
		end
		local key = Handy.controller.wheel_to_key_table[wheel]

		if Handy.controller.process_bind(key) then
			return true
		end

		Handy.speed_multiplier.use(key)
		Handy.nopeus_interaction.use(key)

		if G.STAGE == G.STAGES.RUN and not G.SETTINGS.paused and not G.OVERLAY_MENU then
			Handy.move_highlight.use(key)
			Handy.regular_keybinds.use(key)
			Handy.insta_highlight_entire_f_hand.use(key)
			Handy.deselect_hand.use(key)
		end

		Handy.UI.state_panel.update(key, false)

		return false
	end,
	process_card_click = function(card)
		if not Handy.is_mod_active() then
			return false
		end
		if G.STAGE == G.STAGES.RUN and not G.SETTINGS.paused and not G.OVERLAY_MENU then
			if Handy.insta_actions.use(card) then
				return true
			end
			if Handy.dangerous_actions.use_click(card) then
				return true
			end
			Handy.last_clicked_card = card
			Handy.last_clicked_area = card.area
		end
		return false
	end,
	process_card_hover = function(card)
		if not Handy.is_mod_active() then
			return false
		end
		if G.STAGE == G.STAGES.RUN and not G.SETTINGS.paused and not G.OVERLAY_MENU then
			if Handy.insta_highlight.use(card) then
				return true
			end
			if Handy.dangerous_actions.use_hover(card) then
				return true
			end
			Handy.last_hovered_card = card
			Handy.last_hovered_area = card.area
		end

		return false
	end,

	process_tag_click = function(tag)
		if not Handy.is_mod_active() then
			return false
		end
		if G.STAGE == G.STAGES.RUN and not G.SETTINGS.paused and not G.OVERLAY_MENU then
			if Handy.dangerous_actions.use_tag_click(tag) then
				return true
			end
		end
		return false
	end,

	process_update = function(dt)
		Handy.insta_booster_skip.update()
		Handy.insta_cash_out.update()
		Handy.show_deck_preview.update()
		Handy.not_just_yet_interaction.update()

		Handy.UI.update(dt)
	end,
}

--

Handy.insta_cash_out = {
	is_hold = false,

	can_skip = false,
	is_skipped = false,

	can_execute = function()
		return not not (
			Handy.insta_cash_out.is_hold
			and Handy.insta_cash_out.can_skip
			and not Handy.insta_cash_out.is_skipped
			and G.round_eval
		)
	end,
	execute = function()
		Handy.insta_cash_out.is_skipped = true

		G.E_MANAGER:add_event(Event({
			trigger = "immediate",
			func = function()
				Handy.fake_events.execute({
					func = G.FUNCS.cash_out,
					id = "cash_out_button",
				})
				return true
			end,
		}))
		return true
	end,

	update = function()
		Handy.insta_cash_out.is_hold = (
			G.STAGE == G.STAGES.RUN
			and Handy.is_mod_active()
			and Handy.controller.is_module_key_down(Handy.cc.insta_cash_out)
		)
		return Handy.insta_cash_out.can_execute() and Handy.insta_cash_out.execute() or false
	end,

	update_state_panel = function(state, key, released) end,
}

Handy.insta_booster_skip = {
	is_hold = false,
	is_skipped = false,

	can_execute = function(check)
		-- if check then
		-- 	return not not (
		-- 		Handy.insta_booster_skip.is_hold
		-- 		and not Handy.insta_booster_skip.is_skipped
		-- 		and G.booster_pack
		-- 	)
		-- end
		return not not (
			Handy.insta_booster_skip.is_hold
			and not Handy.insta_booster_skip.is_skipped
			and G.booster_pack
			and Handy.fake_events.check({
				func = G.FUNCS.can_skip_booster,
			})
		)
	end,
	execute = function()
		Handy.insta_booster_skip.is_skipped = true
		G.E_MANAGER:add_event(Event({
			func = function()
				Handy.fake_events.execute({
					func = G.FUNCS.skip_booster,
				})
				return true
			end,
		}))
		return true
	end,

	update = function()
		Handy.insta_booster_skip.is_hold = (
			G.STAGE == G.STAGES.RUN
			and Handy.is_mod_active()
			and Handy.controller.is_module_key_down(Handy.cc.insta_booster_skip)
		)
		return Handy.insta_booster_skip.can_execute() and Handy.insta_booster_skip.execute() or false
	end,

	update_state_panel = function(state, key, released)
		-- if G.STAGE ~= G.STAGES.RUN then
		-- 	return false
		-- end
		-- if Handy.cc.notifications_level < 4 then
		-- 	return false
		-- end
		-- if Handy.insta_booster_skip.can_execute(true) then
		-- 	state.items.insta_booster_skip = {
		-- 		text = "Skip Booster Packs",
		-- 		hold = Handy.insta_booster_skip.is_hold,
		-- 		order = 10,
		-- 	}
		-- 	return true
		-- end
		-- return false
	end,
}

Handy.show_deck_preview = {
	is_hold = false,

	update = function()
		Handy.show_deck_preview.is_hold = (
			G.STAGE == G.STAGES.RUN
			and Handy.is_mod_active()
			and Handy.controller.is_module_key_down(Handy.cc.show_deck_preview)
		)
	end,
}

--

Handy.deselect_hand = {
	should_prevent = function()
		return Handy.controller.is_module_enabled(Handy.cc.deselect_hand)
	end,

	can_execute = function(key)
		return not not (
			G.hand
			and G.hand.highlighted[1]
			-- Vanilla check
			and not ((G.play and #G.play.cards > 0) or G.CONTROLLER.locked or G.CONTROLLER.locks.frame or (G.GAME.STOP_USE and G.GAME.STOP_USE > 0))
			and Handy.controller.is_module_key(Handy.cc.deselect_hand, key)
		)
	end,
	execute = function()
		G.hand:unhighlight_all()
	end,

	use = function(key)
		return Handy.deselect_hand.can_execute(key) and Handy.deselect_hand.execute() or false
	end,
}

Handy.regular_keybinds = {
	shop_reroll_blocker = false,

	can_play = function(key)
		return not not (
			Handy.fake_events.check({
				func = G.FUNCS.can_play,
			}) and Handy.controller.is_module_key(Handy.cc.regular_keybinds.play, key)
		)
	end,
	play = function()
		Handy.fake_events.execute({
			func = G.FUNCS.play_cards_from_highlighted,
		})
	end,

	can_discard = function(key)
		return not not (
			Handy.fake_events.check({
				func = G.FUNCS.can_discard,
			}) and Handy.controller.is_module_key(Handy.cc.regular_keybinds.discard, key)
		)
	end,
	discard = function()
		Handy.fake_events.execute({
			func = G.FUNCS.discard_cards_from_highlighted,
		})
	end,

	can_change_sort = function(key)
		if Handy.controller.is_module_key(Handy.cc.regular_keybinds.sort_by_rank, key) then
			return true, "rank"
		elseif Handy.controller.is_module_key(Handy.cc.regular_keybinds.sort_by_suit, key) then
			return true, "suit"
		else
			return false, nil
		end
	end,
	change_sort = function(sorter)
		if sorter == "rank" then
			Handy.fake_events.execute({
				func = G.FUNCS.sort_hand_value,
			})
		elseif sorter == "suit" then
			Handy.fake_events.execute({
				func = G.FUNCS.sort_hand_suit,
			})
		end
	end,

	can_reroll_shop = function(key)
		return not not (
			not Handy.regular_keybinds.shop_reroll_blocker
			and Handy.fake_events.check({ func = G.FUNCS.can_reroll, button = "reroll_shop" })
			and Handy.controller.is_module_key(Handy.cc.regular_keybinds.reroll_shop, key)
		)
	end,
	reroll_shop = function()
		Handy.regular_keybinds.shop_reroll_blocker = true
		Handy.fake_events.execute({
			func = G.FUNCS.reroll_shop,
		})
		G.E_MANAGER:add_event(Event({
			no_delete = true,
			func = function()
				Handy.regular_keybinds.shop_reroll_blocker = false
				return true
			end,
		}))
	end,

	can_leave_shop = function(key)
		return not not (Handy.controller.is_module_key(Handy.cc.regular_keybinds.leave_shop, key))
	end,
	leave_shop = function()
		Handy.fake_events.execute({
			func = G.FUNCS.toggle_shop,
		})
	end,

	can_select_blind = function(key)
		return not not (
			Handy.controller.is_module_key(Handy.cc.regular_keybinds.select_blind, key)
			and G.GAME.blind_on_deck
			and G.GAME.round_resets.blind_choices[G.GAME.blind_on_deck]
		)
	end,
	select_blind = function()
		Handy.fake_events.execute({
			func = G.FUNCS.select_blind,
			card = G.P_BLINDS[G.GAME.round_resets.blind_choices[G.GAME.blind_on_deck]],
		})
	end,

	can_skip_blind = function(key)
		return not not (
			Handy.controller.is_module_key(Handy.cc.regular_keybinds.skip_blind, key)
			and G.GAME.blind_on_deck
			and G.blind_select_opts[string.lower(G.GAME.blind_on_deck)]
		)
	end,
	skip_blind = function()
		Handy.fake_events.execute({
			func = G.FUNCS.skip_blind,
			UIBox = G.blind_select_opts[string.lower(G.GAME.blind_on_deck)],
		})
	end,

	can_open_run_info = function(key)
		if Handy.controller.is_module_key(Handy.cc.regular_keybinds.run_info, key) then
			return true, 1
		elseif Handy.controller.is_module_key(Handy.cc.regular_keybinds.run_info_blinds, key) then
			return true, 2
		end
		return false, nil
	end,
	open_run_info = function(tab_index)
		if tab_index == 2 then
			Handy.override_create_tabs_chosen_by_label = localize("b_blinds")
		end
		Handy.fake_events.execute({
			func = G.FUNCS.run_info,
		})
		Handy.override_create_tabs_chosen_by_label = nil
	end,

	can_view_deck = function(key)
		return not not (Handy.controller.is_module_key(Handy.cc.regular_keybinds.view_deck, key))
	end,
	view_deck = function()
		Handy.fake_events.execute({
			func = G.FUNCS.deck_info,
		})
	end,

	use = function(key)
		if not Handy.controller.is_module_enabled(Handy.cc.regular_keybinds) then
			return false
		end
		if not G.SETTINGS.paused and G.STAGE == G.STAGES.RUN then
			local can_open_info, info_tab_index = Handy.regular_keybinds.can_open_run_info(key)
			if can_open_info then
				Handy.regular_keybinds.open_run_info(info_tab_index)
			elseif Handy.regular_keybinds.can_view_deck(key) then
				Handy.regular_keybinds.view_deck()
			elseif G.STATE == G.STATES.SELECTING_HAND then
				local need_sort, sorter = Handy.regular_keybinds.can_change_sort(key)
				if need_sort then
					Handy.regular_keybinds.change_sort(sorter)
				elseif Handy.regular_keybinds.can_discard(key) then
					Handy.regular_keybinds.discard()
				elseif Handy.regular_keybinds.can_play(key) then
					Handy.regular_keybinds.play()
				end
				return false
			elseif G.STATE == G.STATES.SHOP then
				if Handy.regular_keybinds.can_reroll_shop(key) then
					Handy.regular_keybinds.reroll_shop()
				elseif Handy.regular_keybinds.can_leave_shop(key) then
					Handy.regular_keybinds.leave_shop()
				end
				return false
			elseif G.STATE == G.STATES.BLIND_SELECT then
				if Handy.regular_keybinds.can_skip_blind(key) then
					Handy.regular_keybinds.skip_blind()
				elseif Handy.regular_keybinds.can_select_blind(key) then
					Handy.regular_keybinds.select_blind()
				end
				return false
			end
		end
		return false
	end,
}

--

Handy.insta_highlight = {
	can_execute = function(card)
		return Handy.controller.is_module_enabled(Handy.cc.insta_highlight)
			and G.STATE ~= G.STATES.HAND_PLAYED
			and card
			and card.area == G.hand
			-- TODO: fix it
			and not next(love.touch.getTouches())
			and love.mouse.isDown(1)
			and not card.highlighted
	end,
	execute = function(card)
		card.area:add_to_highlighted(card)
		return false
	end,

	use = function(card)
		return Handy.insta_highlight.can_execute(card) and Handy.insta_highlight.execute(card) or false
	end,

	update_state_panel = function(state, key, released) end,
}

Handy.insta_highlight_entire_f_hand = {
	can_execute = function(key)
		return G.hand and Handy.controller.is_module_key(Handy.cc.insta_highlight_entire_f_hand, key)
	end,
	execute = function(key)
		G.hand:unhighlight_all()
		local cards_count = math.min(G.hand.config.highlighted_limit, #G.hand.cards)
		for i = 1, cards_count do
			local card = G.hand.cards[i]
			G.hand.cards[i]:highlight(true)
			G.hand.highlighted[#G.hand.highlighted + 1] = card
		end
		if G.STATE == G.STATES.SELECTING_HAND then
			G.hand:parse_highlighted()
		end
		return false
	end,

	use = function(key)
		return Handy.insta_highlight_entire_f_hand.can_execute(key) and Handy.insta_highlight_entire_f_hand.execute(key)
			or false
	end,
}

Handy.insta_actions = {
	action_blocker = false,

	get_actions = function()
		return {
			buy_n_sell = Handy.controller.is_module_key_down(Handy.cc.insta_buy_n_sell),
			buy_or_sell = Handy.controller.is_module_key_down(Handy.cc.insta_buy_or_sell),
			use = Handy.controller.is_module_key_down(Handy.cc.insta_use),
			cryptid_code_use_last_interaction = Handy.controller.is_module_key_down(
				Handy.cc.cryptid_code_use_last_interaction
			),
		}
	end,
	get_alt_actions = function(key)
		return {
			buy_n_sell = Handy.controller.is_module_key(Handy.cc.insta_buy_n_sell, key),
			buy_or_sell = Handy.controller.is_module_key(Handy.cc.insta_buy_or_sell, key),
			use = Handy.controller.is_module_key(Handy.cc.insta_use, key),
			cryptid_code_use_last_interaction = Handy.controller.is_module_key(
				Handy.cc.cryptid_code_use_last_interaction,
				key
			),
		}
	end,

	can_execute = function(card, buy_or_sell, use)
		return not not (not Handy.insta_actions.action_blocker and (buy_or_sell or use) and card and card.area)
	end,
	execute = function(card, buy_or_sell, use, only_sell)
		if card.REMOVED then
			return false
		end

		local target_button = nil
		local is_shop_button = false
		local is_custom_button = false
		local is_playable_consumeable = false

		local base_background = G.UIDEF.card_focus_ui(card)
		local base_attach = base_background:get_UIE_by_ID("ATTACH_TO_ME").children
		local card_buttons = G.UIDEF.use_and_sell_buttons(card)
		local result_funcs = {}
		for _, node in ipairs(card_buttons.nodes) do
			if node.config and node.config.func then
				result_funcs[node.config.func] = node
			end
		end
		local is_booster_pack_card = (G.pack_cards and card.area == G.pack_cards) and not card.ability.consumeable

		if use then
			if type(card.ability.extra) == "table" and card.ability.extra.charges then
				local success, isaac_changeable_item = pcall(function()
					-- G.UIDEF.use_and_sell_buttons(G.jokers.highlighted[1]).nodes[1].nodes[3].nodes[1].nodes[1]
					return card_buttons.nodes[1].nodes[3].nodes[1].nodes[1]
				end)
				if success and isaac_changeable_item then
					target_button = isaac_changeable_item
					is_custom_button = true
				end
			elseif card.area == G.hand and card.ability.consumeable then
				local success, playale_consumeable_button = pcall(function()
					-- G.UIDEF.use_and_sell_buttons(G.hand.highlighted[1]).nodes[1].nodes[2].nodes[1].nodes[1]
					return card_buttons.nodes[1].nodes[2].nodes[1].nodes[1]
				end)
				if success and playale_consumeable_button then
					target_button = playale_consumeable_button
					is_custom_button = true
					is_playable_consumeable = true
				end
			elseif result_funcs.can_select_alchemical or result_funcs.can_select_crazy_card then
				-- Prevent cards to be selected when usage is required:
				-- Alchemical cards, Cines
			else
				target_button = base_attach.buy_and_use
					or (not is_booster_pack_card and base_attach.use)
					or card.children.buy_and_use_button
				is_shop_button = target_button == card.children.buy_and_use_button
			end
		elseif buy_or_sell then
			target_button = card.children.buy_button
				or result_funcs.can_select_crazy_card -- Cines
				or result_funcs.can_select_alchemical -- Alchemical cards
				or result_funcs.can_use_mupack -- Multipacks
				or result_funcs.can_reserve_card -- Code cards, for example
				or base_attach.buy
				or base_attach.redeem
				or base_attach.sell
				or (is_booster_pack_card and base_attach.use)

			if only_sell and target_button ~= base_attach.sell then
				target_button = nil
			end
			is_shop_button = target_button == card.children.buy_button
		end

		if target_button and not is_custom_button and not is_shop_button then
			for _, node in ipairs(card_buttons.nodes) do
				if target_button == node then
					is_custom_button = true
				end
			end
		end

		local target_button_UIBox
		local target_button_definition

		local cleanup = function()
			base_background:remove()
			if target_button_UIBox and is_custom_button then
				target_button_UIBox:remove()
			end
		end

		if target_button then
			if is_playable_consumeable then
				card.area:add_to_highlighted(card)
				if not card.highlighted then
					cleanup()
					return false
				end
			end

			target_button_UIBox = (is_custom_button and UIBox({
				definition = target_button,
				config = {},
			})) or target_button
			target_button_definition = (is_custom_button and target_button)
				or (is_shop_button and target_button.definition)
				or target_button.definition.nodes[1]

			local check, button = Handy.fake_events.check({
				func = G.FUNCS[target_button_definition.config.func],
				button = nil,
				id = target_button_definition.config.id,
				card = card,
				UIBox = target_button_UIBox,
			})
			if check then
				Handy.insta_actions.action_blocker = true
				if Handy.last_clicked_card == card then
					Handy.last_clicked_card = nil
					Handy.last_clicked_area = nil
				end
				if Handy.last_hovered_card == card then
					Handy.last_hovered_card = nil
					Handy.last_hovered_area = nil
				end
				Handy.fake_events.execute({
					func = G.FUNCS[button or target_button_definition.config.button],
					button = nil,
					id = target_button_definition.config.id,
					card = card,
					UIBox = target_button_UIBox,
				})
				G.E_MANAGER:add_event(Event({
					no_delete = true,
					func = function()
						Handy.insta_actions.action_blocker = false
						return true
					end,
				}))
				cleanup()
				return true
			end
		end

		cleanup()
		return false
	end,

	process_card = function(card, actions)
		if not card or card.REMOVED then
			return false
		end
		if card.ability and card.ability.handy_dangerous_actions_used then
			return true
		end

		if actions.cryptid_code_use_last_interaction then
			local cards_events_list = {
				c_cry_variable = "variable_apply_previous",
				c_cry_pointer = "pointer_apply_previous",
				c_cry_class = "class_apply_previous",
				c_cry_exploit = "exploit_apply_previous",
			}
			local success, card_center = pcall(function()
				return card.config.center.key
			end)
			if success and card_center and cards_events_list[card_center] then
				local is_code_card_used = Handy.insta_actions.can_execute(card, false, true)
						and Handy.insta_actions.execute(card, false, true)
					or false
				if is_code_card_used then
					Handy.fake_events.execute({
						func = G.FUNCS[cards_events_list[card_center]],
					})
					return true
				end
			end
			return false
		elseif actions.buy_n_sell then
			if
				Handy.utils.table_contains({
					G.pack_cards,
					G.shop_jokers,
					G.shop_booster,
					G.shop_vouchers,
				}, card.area)
				and card.ability
				and (card.ability.set == "Joker" or card.ability.consumeable)
			then
				local is_buyed = Handy.insta_actions.can_execute(card, true, false)
						and Handy.insta_actions.execute(card, true, false)
					or false
				if is_buyed then
					G.E_MANAGER:add_event(Event({
						func = function()
							G.E_MANAGER:add_event(Event({
								func = function()
									return (
										Handy.insta_actions.can_execute(card, true, false)
										and Handy.insta_actions.execute(card, true, false)
									) or true
								end,
							}))
							return true
						end,
					}))
				end
				return is_buyed
			end
			return false
		else
			return Handy.insta_actions.can_execute(card, actions.buy_or_sell, actions.use)
					and Handy.insta_actions.execute(card, actions.buy_or_sell, actions.use)
				or false
		end
	end,

	use = function(card)
		return Handy.cc.insta_actions_trigger_mode == 1
			and Handy.insta_actions.process_card(card, Handy.insta_actions.get_actions())
	end,
	use_alt = function(key)
		return Handy.cc.insta_actions_trigger_mode == 2
			and Handy.insta_actions.process_card(Handy.last_hovered_card, Handy.insta_actions.get_alt_actions(key))
	end,

	update_state_panel = function(state, key, released)
		if G.STAGE ~= G.STAGES.RUN or G.SETTINGS.paused then
			return false
		end
		if Handy.cc.notifications_level < 4 then
			return false
		end
		local result = false
		local is_alt_action = Handy.cc.insta_actions_trigger_mode == 2
		if is_alt_action and not Handy.controller.is_triggered(released) then
			return false
		end
		local actions = is_alt_action and Handy.insta_actions.get_alt_actions(key) or Handy.insta_actions.get_actions()
		if actions.use then
			state.items.insta_use = {
				text = "Quick use",
				hold = not is_alt_action,
				order = 10,
			}
			result = true
		end
		if actions.buy_or_sell then
			state.items.quick_buy_and_sell = {
				text = "Quick buy and sell",
				hold = not is_alt_action,
				order = 11,
			}
			result = true
		end
		if actions.buy_n_sell then
			state.items.quick_buy_n_sell = {
				text = "Quick buy and immediately sell",
				hold = not is_alt_action,
				order = 12,
			}
			result = true
		end
		return result
	end,
}

Handy.move_highlight = {
	dx = {
		one_left = -1,
		one_right = 1,
	},

	get_dx = function(key, area)
		for module_key, module in pairs(Handy.cc.move_highlight.dx) do
			if Handy.controller.is_module_key(module, key) then
				return Handy.move_highlight.dx[module_key]
			end
		end
		return nil
	end,
	get_actions = function(key, area)
		return {
			swap = Handy.controller.is_module_key_down(Handy.cc.move_highlight.swap),
			to_end = Handy.controller.is_module_key_down(Handy.cc.move_highlight.to_end),
		}
	end,

	can_swap = function(key, area)
		if not area then
			return false
		end
		return not Handy.utils.table_contains({
			G.pack_cards,
			G.shop_jokers,
			G.shop_booster,
			G.shop_vouchers,
		}, area)
	end,
	cen_execute = function(key, area)
		return not not (
			Handy.controller.is_module_enabled(Handy.cc.move_highlight)
			and area
			and area.highlighted
			and area.highlighted[1]
			and Handy.utils.table_contains({
				G.consumeables,
				G.jokers,
				G.cine_quests,
				G.pack_cards,
				G.shop_jokers,
				G.shop_booster,
				G.shop_vouchers,
			}, area)
		)
	end,
	execute = function(key, area)
		local dx = Handy.move_highlight.get_dx(key, area)
		if not dx then
			return false
		end

		local current_card = area.highlighted[1]
		for current_index = #area.cards, 1, -1 do
			if area.cards[current_index] == current_card then
				local actions = Handy.move_highlight.get_actions(key, area)
				local next_index = actions.to_end and (dx > 0 and #area.cards or 1)
					or ((#area.cards + current_index + dx - 1) % #area.cards) + 1
				if current_index == next_index then
					return
				end
				local next_card = area.cards[next_index]
				if not next_card then
					return
				end
				if actions.swap and Handy.move_highlight.can_swap(key, area) then
					if actions.to_end or next_index == 1 or next_index == #area.cards then
						table.remove(area.cards, current_index)
						table.insert(area.cards, next_index, current_card)
					else
						area.cards[next_index] = current_card
						area.cards[current_index] = next_card
					end
				else
					area:remove_from_highlighted(current_card)
					area:add_to_highlighted(next_card)
				end
				return
			end
		end
	end,

	use = function(key, area)
		area = area or Handy.last_clicked_area
		return Handy.move_highlight.cen_execute(key, area) and Handy.move_highlight.execute(key, area) or false
	end,

	update_state_panel = function(state, key, released) end,
}

Handy.dangerous_actions = {
	sell_queue = {},

	sell_next_card = function()
		local target = table.remove(Handy.dangerous_actions.sell_queue, 1)
		if not target then
			stop_use()
			return
		end

		local card = target.card
		if target.remove then
			card:stop_hover()
			card:remove()
		else
			G.GAME.STOP_USE = 0
			Handy.insta_actions.execute(card, true, false, true)

			G.E_MANAGER:add_event(Event({
				blocking = false,
				func = function()
					if card.ability then
						card.ability.handy_dangerous_actions_used = nil
					end
					return true
				end,
			}))
		end
		if Handy.last_clicked_card == card then
			Handy.last_clicked_card = nil
			Handy.last_clicked_area = nil
		end
		if Handy.last_hovered_card == card then
			Handy.last_hovered_card = nil
			Handy.last_hovered_area = nil
		end
		Handy.dangerous_actions.sell_next_card()
	end,

	get_options = function(card)
		return {
			use_queue = Handy.controller.is_module_enabled(Handy.cc.dangerous_actions.immediate_buy_and_sell.queue),
			remove = Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.card_remove)
				and (card.area == G.jokers or card.area == G.consumeables),
		}
	end,

	process_card = function(card, use_queue, remove)
		if use_queue then
			if not card.ability then
				card.ability = {}
			end
			card.ability.handy_dangerous_actions_used = true

			table.insert(Handy.dangerous_actions.sell_queue, { card = card, remove = remove })
			Handy.UI.state_panel.update(nil, nil)
			return false
		elseif remove then
			card:stop_hover()
			card:remove()
			return true
		else
			local result = Handy.insta_actions.execute(card, true, false)
			if result then
				if not card.ability then
					card.ability = {}
				end
				card.ability.handy_dangerous_actions_used = true

				G.CONTROLLER.locks.selling_card = nil
				G.CONTROLLER.locks.use = nil
				G.GAME.STOP_USE = 0

				G.E_MANAGER:add_event(Event({
					no_delete = true,
					func = function()
						if card.ability then
							card.ability.handy_dangerous_actions_used = nil
						end
						return true
					end,
				}))
			end
			return result
		end
	end,

	can_execute = function(card)
		return Handy.is_dangerous_actions_active()
			and card
			and not (card.ability and card.ability.handy_dangerous_actions_used)
	end,
	execute_click = function(card)
		if Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.immediate_buy_and_sell, true) then
			if Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.sell_all) then
				local options = Handy.dangerous_actions.get_options(card)
				for _, target_card in ipairs(card.area.cards) do
					Handy.dangerous_actions.process_card(target_card, true, options.remove)
				end
				Handy.dangerous_actions.sell_next_card()
				return true
			elseif Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.sell_all_same) then
				local target_cards = {}
				local success, card_center_key = pcall(function()
					return card.config.center.key
				end)
				if success and card_center_key then
					for _, area_card in ipairs(card.area.cards) do
						local _success, area_card_center_key = pcall(function()
							return area_card.config.center.key
						end)
						if _success and area_card_center_key == card_center_key then
							table.insert(target_cards, area_card)
						end
					end
				end

				local options = Handy.dangerous_actions.get_options(card)
				for _, target_card in ipairs(target_cards) do
					Handy.dangerous_actions.process_card(target_card, true, options.remove)
				end
				Handy.dangerous_actions.sell_next_card()
				return true
			end
		end
		return false
	end,
	execute_hover = function(card)
		if not Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.immediate_buy_and_sell) then
			return false
		end
		if not Handy.insta_actions.get_actions().buy_or_sell then
			return false
		end
		local options = Handy.dangerous_actions.get_options(card)
		return Handy.dangerous_actions.process_card(card, options.use_queue, options.remove)
	end,

	use_click = function(card)
		return Handy.dangerous_actions.can_execute(card) and Handy.dangerous_actions.execute_click(card) or false
	end,
	use_hover = function(card)
		return Handy.dangerous_actions.can_execute(card) and Handy.dangerous_actions.execute_hover(card) or false
	end,

	can_execute_tag = function(tag)
		return Handy.is_dangerous_actions_active() and tag
	end,
	execute_tag_click = function(tag)
		if Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.card_remove) then
			local target_tags = {}
			for _, target_tag in ipairs(G.GAME.tags) do
				table.insert(target_tags, target_tag)
			end
			if Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.sell_all) then
				for _, target_tag in ipairs(target_tags) do
					target_tag:remove()
				end
				return true
			elseif Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.sell_all_same) then
				local tag_key = tag.key
				for _, target_tag in ipairs(target_tags) do
					if target_tag.key == tag_key then
						target_tag:remove()
					end
				end
				return true
			end
		end
		return false
	end,
	use_tag_click = function(tag)
		return Handy.dangerous_actions.can_execute_tag(tag) and Handy.dangerous_actions.execute_tag_click(tag) or false
	end,

	toggle_queue = function(key, released)
		if Handy.controller.is_module_key(Handy.cc.dangerous_actions.immediate_buy_and_sell, key) then
			if released then
				Handy.dangerous_actions.sell_next_card()
			else
				Handy.dangerous_actions.sell_queue = {}
			end
		end
	end,

	update_state_panel = function(state, key, released)
		if G.STAGE ~= G.STAGES.RUN or G.SETTINGS.paused then
			return false
		end
		if Handy.cc.notifications_level < 2 then
			return false
		end

		local is_sell = Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.immediate_buy_and_sell, true)
		if not is_sell then
			return false
		end

		if not Handy.controller.is_module_enabled(Handy.cc.dangerous_actions) then
			state.items.prevented_dangerous_actions = {
				text = "Unsafe actions disabled in mod settings",
				hold = true,
				order = 99999999,
			}
			return true
		elseif not Handy.is_dangerous_actions_active() then
			state.items.prevented_dangerous_actions = {
				text = "Unsafe actions disabled by other mod",
				hold = true,
				order = 99999999,
			}
			return true
		end

		local is_insta_sell = Handy.insta_actions.get_actions().buy_or_sell
			and Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.immediate_buy_and_sell)
		local is_all = Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.sell_all)
		local is_all_same = Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.sell_all_same)
		local is_remove = Handy.controller.is_module_key_down(Handy.cc.dangerous_actions.card_remove)

		state.dangerous = true
		state.items.dangerous_hint = {
			text = "[Unsafe] Bugs can appear!",
			dangerous = true,
			hold = true,
			order = 99999999,
		}

		if is_insta_sell then
			local text = is_remove and "Instant REMOVE" or "Instant sell"
			if Handy.controller.is_module_enabled(Handy.cc.dangerous_actions.immediate_buy_and_sell.queue) then
				text = text .. " [" .. #Handy.dangerous_actions.sell_queue .. " in queue]"
			end
			state.items.quick_buy_and_sell = {
				text = text,
				hold = true,
				order = 11,
				dangerous = true,
			}
		elseif is_all then
			local text = is_remove and "REMOVE ALL cards/tags in clicked area" or "Sell ALL cards in clicked area"
			state.items.sell_all_same = {
				text = text,
				hold = true,
				order = 12,
				dangerous = true,
			}
		elseif is_all_same then
			local text = is_remove and "REMOVE all copies of clicked card/tag" or "Sell all copies of clicked card"
			state.items.sell_all_same = {
				text = text,
				hold = true,
				order = 12,
				dangerous = true,
			}
		end
		return true
	end,
}

Handy.speed_multiplier = {
	value = 1,

	get_value = function()
		if not Handy.is_mod_active() or not Handy.controller.is_module_enabled(Handy.cc.speed_multiplier) then
			return 1
		end
		return Handy.speed_multiplier.value
	end,

	get_actions = function(key)
		return {
			multiply = key == Handy.controller.wheel_to_key_table[1],
			divide = key == Handy.controller.wheel_to_key_table[2],
		}
	end,
	can_execute = function(key)
		return Handy.controller.is_module_key_down(Handy.cc.speed_multiplier)
	end,

	execute = function(key)
		local actions = Handy.speed_multiplier.get_actions(key)
		if actions.multiply then
			Handy.speed_multiplier.multiply()
		end
		if actions.divide then
			Handy.speed_multiplier.divide()
		end
		return false
	end,

	multiply = function()
		Handy.speed_multiplier.value = math.min(512, Handy.speed_multiplier.value * 2)
	end,
	divide = function()
		Handy.speed_multiplier.value = math.max(0.001953125, Handy.speed_multiplier.value / 2)
	end,

	use = function(key)
		return Handy.speed_multiplier.can_execute(key) and Handy.speed_multiplier.execute(key) or false
	end,

	update_state_panel = function(state, key, released)
		if not key or not Handy.speed_multiplier.can_execute(key) then
			return false
		end
		if Handy.cc.notifications_level < 3 then
			return false
		end

		local actions = Handy.speed_multiplier.get_actions(key)

		if actions.multiply or actions.divide then
			state.items.change_speed_multiplier = {
				text = "Game speed multiplier: "
					.. (
						Handy.speed_multiplier.value >= 1 and Handy.speed_multiplier.value
						or ("1/" .. (1 / Handy.speed_multiplier.value))
					),
				hold = false,
				order = 5,
			}
			return true
		end
		return false
	end,
}

--

Handy.nopeus_interaction = {
	is_present = function()
		return type(Nopeus) == "table"
	end,

	get_actions = function(key)
		return {
			increase = key == Handy.controller.wheel_to_key_table[1],
			decrease = key == Handy.controller.wheel_to_key_table[2],
		}
	end,

	can_dangerous = function()
		return not not (
			Handy.is_mod_active()
			and Handy.is_dangerous_actions_active()
			and Handy.controller.is_module_enabled(Handy.cc.dangerous_actions.nopeus_unsafe)
		)
	end,
	can_execute = function(key)
		return not not (
			Handy.nopeus_interaction.is_present()
			and Handy.controller.is_module_key_down(Handy.cc.nopeus_interaction)
		)
	end,
	execute = function(key)
		local actions = Handy.nopeus_interaction.get_actions(key)
		if actions.increase then
			Handy.nopeus_interaction.increase()
		end
		if actions.decrease then
			Handy.nopeus_interaction.decrease()
		end
	end,

	change = function(dx)
		if not Handy.nopeus_interaction.is_present() then
			G.SETTINGS.FASTFORWARD = 0
		elseif Nopeus.Optimised then
			G.SETTINGS.FASTFORWARD = math.min(
				Handy.nopeus_interaction.can_dangerous() and 4 or 3,
				math.max(0, (G.SETTINGS.FASTFORWARD or 0) + dx)
			)
		else
			G.SETTINGS.FASTFORWARD = math.min(
				Handy.nopeus_interaction.can_dangerous() and 3 or 2,
				math.max(0, (G.SETTINGS.FASTFORWARD or 0) + dx)
			)
		end
	end,
	increase = function()
		Handy.nopeus_interaction.change(1)
	end,
	decrease = function()
		Handy.nopeus_interaction.change(-1)
	end,

	use = function(key)
		return Handy.nopeus_interaction.can_execute(key) and Handy.nopeus_interaction.execute(key) or false
	end,

	update_state_panel = function(state, key, released)
		if not Handy.nopeus_interaction.is_present() then
			return false
		end
		if not key or not Handy.nopeus_interaction.can_execute(key) then
			return false
		end

		local actions = Handy.nopeus_interaction.get_actions(key)

		if actions.increase or actions.decrease then
			local states = {
				Nopeus.Off,
				Nopeus.Planets,
				Nopeus.On,
				Nopeus.Unsafe,
			}
			if Nopeus.Optimised then
				states = {
					Nopeus.Off,
					Nopeus.Planets,
					Nopeus.On,
					Nopeus.Optimised,
					Nopeus.Unsafe,
				}
			end

			local is_dangerous = G.SETTINGS.FASTFORWARD == (#states - 1)

			if is_dangerous then
				state.dangerous = true
				if Handy.cc.notifications_level < 2 then
					return false
				end
			else
				if Handy.cc.notifications_level < 3 then
					return false
				end
			end

			state.items.change_nopeus_fastforward = {
				text = "Nopeus fast-forward: " .. states[(G.SETTINGS.FASTFORWARD or 0) + 1],
				hold = false,
				order = 4,
				dangerous = is_dangerous,
			}
			if
				not Handy.nopeus_interaction.can_dangerous()
				and actions.increase
				and G.SETTINGS.FASTFORWARD == (#states - 2)
			then
				state.items.prevent_nopeus_unsafe = {
					text = "Unsafe option disabled in mod settings",
					hold = false,
					order = 4.05,
				}
			end
			return true
		end
		return false
	end,
}

Handy.not_just_yet_interaction = {
	is_present = function()
		return G and G.FUNCS and G.FUNCS.njy_endround ~= nil
	end,

	can_execute = function(check)
		return not not (
			Handy.not_just_yet_interaction.is_present()
			and GLOBAL_njy_vanilla_override
			and G.STATE_COMPLETE
			and G.buttons
			and G.buttons.states
			and G.buttons.states.visible
			and G.GAME
			and G.GAME.chips
			and G.GAME.blind
			and G.GAME.blind.chips
			and to_big(G.GAME.chips) >= to_big(G.GAME.blind.chips)
		)
	end,
	execute = function()
		stop_use()
		G.STATE = G.STATES.NEW_ROUND
		end_round()
	end,

	update = function()
		GLOBAL_njy_vanilla_override = (
			G.STAGE == G.STAGES.RUN
			and Handy.is_mod_active()
			and Handy.controller.is_module_key_down(Handy.cc.not_just_yet_interaction)
		)
		return Handy.not_just_yet_interaction.can_execute() and Handy.not_just_yet_interaction.execute() or false
	end,
}

--

--

Handy.UI = {
	show_options_button = true,
	counter = 1,
	C = {
		TEXT = HEX("FFFFFF"),
		BLACK = HEX("000000"),
		RED = HEX("FF0000"),

		DYN_BASE_APLHA = {
			CONTAINER = 0.6,

			TEXT = 1,
			TEXT_DANGEROUS = 1,
		},

		DYN = {
			CONTAINER = HEX("000000"),

			TEXT = HEX("FFFFFF"),
			TEXT_DANGEROUS = HEX("FFEEEE"),
		},
	},
	state_panel = {
		element = nil,

		title = nil,
		items = nil,

		previous_state = {
			dangerous = false,
			title = {},
			items = {},
			sub_items = {},
			hold = false,
		},
		current_state = {
			dangerous = false,
			title = {},
			items = {},
			sub_items = {},
			hold = false,
		},

		get_definition = function()
			local state_panel = Handy.UI.state_panel

			local items_raw = {}
			for _, item in pairs(state_panel.current_state.items) do
				table.insert(items_raw, item)
			end

			table.sort(items_raw, function(a, b)
				return a.order < b.order
			end)

			local items = {}
			for _, item in ipairs(items_raw) do
				table.insert(items, {
					n = G.UIT.R,
					config = {
						align = "cm",
						padding = 0.035,
					},
					nodes = {
						{
							n = G.UIT.T,
							config = {
								text = item.text,
								scale = 0.225,
								colour = item.dangerous and Handy.UI.C.DYN.TEXT_DANGEROUS or Handy.UI.C.DYN.TEXT,
								shadow = true,
							},
						},
					},
				})
			end

			return {
				n = G.UIT.ROOT,
				config = { align = "cm", padding = 0.1, r = 0.1, colour = G.C.CLEAR, id = "handy_state_panel" },
				nodes = {
					{
						n = G.UIT.C,
						config = {
							align = "cm",
							padding = 0.125,
							r = 0.1,
							colour = Handy.UI.C.DYN.CONTAINER,
						},
						nodes = {
							{
								n = G.UIT.R,
								config = {
									align = "cm",
								},
								nodes = {
									{
										n = G.UIT.T,
										config = {
											text = state_panel.current_state.title.text,
											scale = 0.3,
											colour = Handy.UI.C.DYN.TEXT,
											shadow = true,
											id = "handy_state_title",
										},
									},
								},
							},
							{
								n = G.UIT.R,
								config = {
									align = "cm",
								},
								nodes = {
									{
										n = G.UIT.C,
										config = {
											align = "cm",
											id = "handy_state_items",
										},
										nodes = items,
									},
								},
							},
						},
					},
				},
			}
		end,
		emplace = function()
			if Handy.UI.state_panel.element then
				Handy.UI.state_panel.element:remove()
			end
			local element = UIBox({
				definition = Handy.UI.state_panel.get_definition(),
				config = {
					instance_type = "ALERT",
					align = "cm",
					major = G.ROOM_ATTACH,
					can_collide = false,
					offset = {
						x = 0,
						y = 3.5,
					},
				},
			})
			Handy.UI.state_panel.element = element
			Handy.UI.state_panel.title = element:get_UIE_by_ID("handy_state_title")
			Handy.UI.state_panel.items = element:get_UIE_by_ID("handy_state_items")
		end,

		update = function(key, released)
			local state_panel = Handy.UI.state_panel

			local state = {
				dangerous = false,
				title = {},
				items = {},
				sub_items = {},
			}

			local is_changed = false

			for _, part in ipairs({
				Handy.speed_multiplier,
				Handy.insta_booster_skip,
				Handy.insta_cash_out,
				Handy.insta_actions,
				Handy.insta_highlight,
				Handy.move_highlight,
				Handy.nopeus_interaction,
				Handy.dangerous_actions,
			}) do
				local temp_result = part.update_state_panel(state, key, released)
				is_changed = is_changed or temp_result or false
			end

			if is_changed then
				if state.dangerous then
					state.title.text = "Dangerous actions"
				else
					state.title.text = "Quick actions"
				end

				for _, item in pairs(state.items) do
					if item.hold then
						state.hold = true
					end
				end

				local color = Handy.UI.C.DYN.CONTAINER
				local target_color = state.dangerous and Handy.UI.C.RED or Handy.UI.C.BLACK
				color[1] = target_color[1]
				color[2] = target_color[2]
				color[3] = target_color[3]

				Handy.UI.counter = 0
				state_panel.previous_state = state_panel.current_state
				state_panel.current_state = state

				state_panel.emplace()
			else
				state_panel.current_state.hold = false
			end
		end,
	},

	update = function(dt)
		if Handy.UI.state_panel.current_state.hold then
			Handy.UI.counter = 0
		elseif Handy.UI.counter < 1 then
			Handy.UI.counter = Handy.UI.counter + dt
		end
		local multiplier = math.min(1, math.max(0, (1 - Handy.UI.counter) * 2))
		for key, color in pairs(Handy.UI.C.DYN) do
			color[4] = (Handy.UI.C.DYN_BASE_APLHA[key] or 1) * multiplier
		end
	end,
}

function Handy.UI.init()
	Handy.UI.counter = 1
	Handy.UI.state_panel.emplace()
	Handy.UI.update(0)
end

--

local love_update_ref = love.update
function love.update(dt, ...)
	love_update_ref(dt, ...)
	Handy.controller.process_update(dt)
end

local wheel_moved_ref = love.wheelmoved or function() end
function love.wheelmoved(x, y)
	wheel_moved_ref(x, y)
	Handy.controller.process_wheel(y > 0 and 1 or 2)
end

--

function Handy.emplace_steamodded()
	Handy.current_mod = (Handy_Preload and Handy_Preload.current_mod) or SMODS.current_mod
	Handy.current_mod.config_tab = true
	Handy.UI.show_options_button = not Handy.cc.hide_in_menu

	Handy.current_mod.extra_tabs = function()
		return Handy.UI.get_options_tabs()
	end

	G.E_MANAGER:add_event(Event({
		func = function()
			G.njy_keybind = nil
			return true
		end,
	}))

	if Handy_Preload then
		Handy_Preload = nil
	end
end

function G.FUNCS.handy_toggle_module_enabled(arg, module)
	if not module then
		return
	end
	module.enabled = arg
	Handy.nopeus_interaction.change(0)
	Handy.config.save()
end

function G.FUNCS.handy_toggle_menu_button(arg)
	Handy.cc.hide_in_menu = arg
	Handy.config.save()
	if Handy.current_mod then
		Handy.UI.show_options_button = not Handy.cc.hide_in_menu
	end
end

function G.FUNCS.handy_change_notifications_level(arg)
	Handy.cc.notifications_level = arg.to_key
	Handy.config.save()
end

function G.FUNCS.handy_change_keybinds_trigger_mode(arg)
	Handy.cc.keybinds_trigger_mode = arg.to_key
	Handy.config.save()
end

function G.FUNCS.handy_change_insta_actions_trigger_mode(arg)
	Handy.cc.insta_actions_trigger_mode = arg.to_key
	Handy.config.save()
end

function G.FUNCS.handy_init_keybind_change(e)
	Handy.controller.init_bind(e)
end

if Handy_Preload then
	Handy.emplace_steamodded()
end

Handy.UI.PARTS = {
	format_module_keys = function(module, only_first)
		local result = "[" .. module.key_1 .. "]"
		if only_first or not module.key_2 or module.key_2 == "None" then
			return result
		end
		return result .. " or [" .. module.key_2 .. "]"
	end,
	create_module_checkbox = function(module, label, text_prefix, text_lines, skip_keybinds)
		local desc_lines = {
			{ n = G.UIT.R, config = { minw = 5 } },
		}

		if skip_keybinds then
			table.insert(desc_lines, {
				n = G.UIT.R,
				config = { padding = 0.025 },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = text_prefix .. " " .. text_lines[1],
							scale = 0.3,
							colour = G.C.TEXT_LIGHT,
						},
					},
				},
			})
		else
			table.insert(desc_lines, {
				n = G.UIT.R,
				config = { padding = 0.025 },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = text_prefix
								.. " "
								.. Handy.UI.PARTS.format_module_keys(module)
								.. " "
								.. text_lines[1],
							scale = 0.3,
							colour = G.C.TEXT_LIGHT,
						},
					},
				},
			})
		end

		for i = 2, #text_lines do
			table.insert(desc_lines, {
				n = G.UIT.R,
				config = { padding = 0.025 },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = text_lines[i],
							scale = 0.3,
							colour = G.C.TEXT_LIGHT,
						},
					},
				},
			})
		end

		local label_lines = {}
		if type(label) == "string" then
			label = { label }
		end
		for i = 1, #label do
			table.insert(label_lines, {
				n = G.UIT.R,
				config = { minw = 2.75 },
				nodes = {
					{
						n = G.UIT.T,
						config = {
							text = label[i],
							scale = 0.4,
							colour = G.C.WHITE,
						},
					},
				},
			})
		end

		return {
			n = G.UIT.R,
			config = { align = "cm" },
			nodes = {
				{
					n = G.UIT.C,
					config = { align = "cm" },
					nodes = label_lines,
				},
				{
					n = G.UIT.C,
					config = { align = "cm" },
					nodes = {
						create_toggle({
							callback = function(b)
								return G.FUNCS.handy_toggle_module_enabled(b, module)
							end,
							label_scale = 0.4,
							label = "",
							ref_table = module,
							ref_value = "enabled",
							w = 0,
						}),
					},
				},
				{
					n = G.UIT.C,
					config = { minw = 0.1 },
				},
				{
					n = G.UIT.C,
					config = { align = "cm" },
					nodes = desc_lines,
				},
			},
		}
	end,

	create_module_section = function(label)
		return {
			n = G.UIT.R,
			config = { align = "cm", padding = 0.075 },
			nodes = {
				{
					n = G.UIT.T,
					config = { text = label, colour = G.C.WHITE, scale = 0.35, align = "cm" },
				},
			},
		}
	end,
	create_module_keybind = function(module, label, dangerous)
		return {
			n = G.UIT.R,
			config = { align = "cm", padding = 0.01 },
			nodes = {
				{
					n = G.UIT.C,
					config = { align = "c", minw = 4 },
					nodes = {
						{
							n = G.UIT.T,
							config = { text = label, colour = G.C.WHITE, scale = 0.3 },
						},
					},
				},
				{
					n = G.UIT.C,
					config = { align = "cm", minw = 0.75 },
				},
				UIBox_button({
					label = { module.key_1 or "None" },
					col = true,
					colour = dangerous and G.C.MULT or G.C.CHIPS,
					scale = 0.3,
					minw = 2.75,
					minh = 0.4,
					ref_table = {
						module = module,
						key = "key_1",
					},
					button = "handy_init_keybind_change",
				}),
				{
					n = G.UIT.C,
					config = { align = "cm", minw = 0.6 },
					nodes = {
						{
							n = G.UIT.T,
							config = { text = "or", colour = G.C.WHITE, scale = 0.3 },
						},
					},
				},
				UIBox_button({
					label = { module.key_2 or "None" },
					col = true,
					colour = dangerous and G.C.MULT or G.C.CHIPS,
					scale = 0.3,
					minw = 2.75,
					minh = 0.4,
					ref_table = {
						module = module,
						key = "key_2",
					},
					button = "handy_init_keybind_change",
				}),
			},
		}
	end,
}

--

Handy.UI.get_config_tab_overall = function()
	return {
		{
			n = G.UIT.R,
			config = { padding = 0.05, align = "cm" },
			nodes = {
				Handy.current_mod and {
					n = G.UIT.C,
					config = {
						align = "cm",
						padding = 0.1,
					},
					nodes = {
						{
							n = G.UIT.R,
							config = {
								padding = 0.15,
							},
							nodes = {},
						},
						{
							n = G.UIT.R,
							config = { align = "cm" },
							nodes = {
								{
									n = G.UIT.C,
									config = { align = "cm" },
									nodes = {
										{
											n = G.UIT.R,
											config = { minw = 2.5 },
											nodes = {
												{
													n = G.UIT.T,
													config = {
														text = "Hide mod button",
														scale = 0.4,
														colour = G.C.WHITE,
													},
												},
											},
										},
										{
											n = G.UIT.R,
											config = { minw = 2.5 },
											nodes = {
												{
													n = G.UIT.T,
													config = {
														text = "in options menu",
														scale = 0.4,
														colour = G.C.WHITE,
													},
												},
											},
										},
									},
								},
								{
									n = G.UIT.C,
									config = { align = "cm" },
									nodes = {
										create_toggle({
											callback = function(b)
												return G.FUNCS.handy_toggle_menu_button(b)
											end,
											label_scale = 0.4,
											label = "",
											ref_table = Handy.cc,
											ref_value = "hide_in_menu",
											w = 0,
										}),
									},
								},
							},
						},
					},
				} or nil,
				{
					n = G.UIT.C,
					nodes = {
						create_option_cycle({
							w = 6,
							label = "Info popups level",
							scale = 0.8,
							options = {
								"None",
								"Dangerous only",
								"Features-related",
								"All",
							},
							opt_callback = "handy_change_notifications_level",
							current_option = Handy.cc.notifications_level,
						}),
					},
				},
				{
					n = G.UIT.C,
					nodes = {
						create_option_cycle({
							w = 6,
							label = "Keybinds trigger mode",
							scale = 0.8,
							options = {
								"On key press",
								"On key release",
							},
							opt_callback = "handy_change_keybinds_trigger_mode",
							current_option = Handy.cc.keybinds_trigger_mode,
						}),
					},
				},
			},
		},
		{ n = G.UIT.R, config = { padding = 0.05 }, nodes = {} },
		Handy.UI.PARTS.create_module_checkbox(
			Handy.cc.handy,
			{ "HandyBalatro v" .. Handy.version, "by SleepyG11" },
			"Uncheck",
			{
				"to disable ALL mod features",
				"(no restart required)",
			},
			true
		),
		{ n = G.UIT.R, config = { minh = 0.25 } },
		{
			n = G.UIT.R,
			nodes = {
				{
					n = G.UIT.C,
					nodes = {
						Handy.UI.PARTS.create_module_checkbox(Handy.cc.regular_keybinds, "Regular keybinds", "Use", {
							"keybinds for",
							"common game actions",
							"(Play, Discard, Reroll, Skip blind, etc.)",
						}, true),
						{ n = G.UIT.R, config = { minh = 0.25 } },
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.insta_highlight,
							"Quick Highlight",
							"Hold [Left Mouse]",
							{
								"and",
								"hover cards in hand to highlight",
							},
							true
						),
						{ n = G.UIT.R, config = { minh = 0.25 } },
						Handy.UI.PARTS.create_module_checkbox(Handy.cc.show_deck_preview, "Deck preview", "Hold", {
							"to",
							"show deck preview",
						}),
					},
				},
				{
					n = G.UIT.C,
					config = { minw = 4 },
					nodes = {
						Handy.UI.PARTS.create_module_checkbox(Handy.cc.deselect_hand, "Deselect hand", "Press", {
							"to",
							"deselect hand",
							"(disable to use vanilla)",
						}),
						{ n = G.UIT.R, config = { minh = 0.25 } },
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.insta_cash_out,
							"Quick Cash Out",
							"Press/hold",
							{
								"to",
								"skip Cash Out stage",
							}
						),
						{ n = G.UIT.R, config = { minh = 0.25 } },
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.insta_booster_skip,
							{ "Quick skip", "Booster Packs" },
							"Press/hold",
							{
								"to",
								"skip booster pack",
							}
						),
					},
				},
			},
		},
		{ n = G.UIT.R, config = { minh = 0.4 } },
		{
			n = G.UIT.R,
			config = { padding = 0.1, align = "cm" },
			nodes = {
				{
					n = G.UIT.T,
					config = {
						text = 'Each control can be assigned to mouse button, mouse wheel or keyboard key in "Keybinds" tabs',
						scale = 0.3,
						colour = { 1, 1, 1, 0.6 },
						align = "cm",
					},
				},
			},
		},
		-- { n = G.UIT.R, config = { minh = 0.25 } },
	}
end

Handy.UI.get_config_tab_quick = function()
	return {
		{
			n = G.UIT.R,
			config = { padding = 0.05, align = "cm" },
			nodes = {
				{
					n = G.UIT.C,
					nodes = {
						create_option_cycle({
							w = 6,
							label = "Buy/Sell/Use mode",
							scale = 0.8,
							options = {
								"Hold + Card click",
								"Card hover + Press",
							},
							opt_callback = "handy_change_insta_actions_trigger_mode",
							current_option = Handy.cc.insta_actions_trigger_mode,
						}),
					},
				},
			},
		},
		{ n = G.UIT.R, config = { padding = 0.05 }, nodes = {} },
		Handy.UI.PARTS.create_module_checkbox(Handy.cc.move_highlight, "Move highlight", "Press", {
			"[" .. tostring(Handy.cc.move_highlight.dx.one_left.key_1) .. "] or [" .. tostring(
				Handy.cc.move_highlight.dx.one_right.key_1
			) .. "]",
			"to move highlight in card area.",
			"Hold [" .. tostring(Handy.cc.move_highlight.swap.key_1) .. "] to move card instead.",
			"Hold [" .. tostring(Handy.cc.move_highlight.to_end.key_1) .. "] to move to first/last card",
		}, true),
		{ n = G.UIT.R, config = { minh = 0.25 } },
		{
			n = G.UIT.R,
			nodes = {
				{
					n = G.UIT.C,
					nodes = {
						Handy.UI.PARTS.create_module_checkbox(Handy.cc.insta_buy_or_sell, "Quick Buy/Sell", "Use", {
							"to",
							"buy or sell card",
						}),
						{ n = G.UIT.R, config = { minh = 0.25 } },
						Handy.UI.PARTS.create_module_checkbox(Handy.cc.insta_buy_n_sell, "Quick Buy'n'Sell", "Use", {
							"to",
							"buy card and sell",
							"immediately after",
						}),
						{ n = G.UIT.R, config = { minh = 0.25 } },
						Handy.UI.PARTS.create_module_checkbox(Handy.cc.insta_use, "Quick use", "Use", {
							"to",
							"use card if possible",
							"(overrides Quick Buy/Sell)",
						}),
						{ n = G.UIT.R, config = { minh = 0.3 } },
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.cryptid_code_use_last_interaction,
							{ "Cryptid: use", "previous input" },
							"Use",
							{
								"to",
								"use code card if possible with",
								"previously inputted value",
							}
						),
					},
				},
				{
					n = G.UIT.C,
					config = { minw = 4 },
					nodes = {
						Handy.UI.PARTS.create_module_checkbox(Handy.cc.speed_multiplier, "Speed Multiplier", "Hold", {
							"and",
							"[Wheel Up] to multiply or",
							"[Wheel Down] to divide game speed",
						}),
						{ n = G.UIT.R, config = { minh = 0.25 } },
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.insta_highlight_entire_f_hand,
							{ "Highlight", "entire hand" },
							"Press",
							{
								"to",
								"highlight entire hand",
							}
						),
						{ n = G.UIT.R, config = { minh = 0.25 } },
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.nopeus_interaction,
							{ "Nopeus:", "fast-forward" },
							"Hold",
							{
								"and",
								"[Wheel Up] to increase or",
								"[Wheel Down] to decrease",
								"fast-forward setting",
							}
						),
						{ n = G.UIT.R, config = { minh = 0.25 } },
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.not_just_yet_interaction,
							{ "NotJustYet:", "End round" },
							"Press",
							{
								"to",
								"end round",
							}
						),
					},
				},
			},
		},
		-- { n = G.UIT.R, config = { minh = 0.25 } },
	}
end

Handy.UI.get_config_tab_interactions = function()
	return {
		{
			n = G.UIT.R,
			nodes = {
				{
					n = G.UIT.C,
					nodes = {
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.nopeus_interaction,
							{ "Nopeus:", "fast-forward" },
							"Hold",
							{
								"and",
								"[Wheel Up] to increase or",
								"[Wheel Down] to decrease",
								"fast-forward setting",
							}
						),
						{
							n = G.UIT.R,
							config = { minh = 0.25 },
						},
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.not_just_yet_interaction,
							{ "NotJustYet:", "End round" },
							"Press",
							{
								"to",
								"end round",
							}
						),
					},
				},
			},
		},
	}
end

Handy.UI.get_config_tab_dangerous = function()
	return {
		-- {
		-- 	n = G.UIT.R,
		-- 	config = { padding = 0.05, align = "cm" },
		-- 	nodes = {

		-- 	},
		-- },
		-- { n = G.UIT.R, config = { padding = 0.05 }, nodes = {} },
		{
			n = G.UIT.R,
			config = { padding = 0.05, align = "cm" },
			nodes = {
				{
					n = G.UIT.C,
					nodes = {
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.dangerous_actions,
							{ "Dangerous", "actions" },
							"Enable",
							{
								"unsafe controls. They're",
								"designed to be speed-first,",
								"which can cause bugs or crashes",
							},
							true
						),
					},
				},
			},
		},
		{ n = G.UIT.R, config = { minh = 0.5 } },
		{
			n = G.UIT.R,
			nodes = {
				{
					n = G.UIT.C,
					nodes = {
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.dangerous_actions.immediate_buy_and_sell,
							"Instant Sell",
							"Hold",
							{
								Handy.UI.PARTS.format_module_keys(Handy.cc.dangerous_actions.immediate_buy_and_sell)
									.. ",",
								"hold " .. Handy.UI.PARTS.format_module_keys(Handy.cc.insta_buy_or_sell) .. "",
								"and hover card to sell it",
							},
							true
						),
						{ n = G.UIT.R, config = { minh = 0.275 } },
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.dangerous_actions.immediate_buy_and_sell.queue,
							"Sell Queue",
							"Start",
							{
								"selling cards only when",
								"keybind was released",
							},
							true
						),
						{ n = G.UIT.R, config = { minh = 0.275 } },
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.dangerous_actions.nopeus_unsafe,
							{ "Nopeus: Unsafe", "fast-forward" },
							"Allow",
							{
								"increase fast-forward",
								'setting to "Unsafe"',
							},
							true
						),
					},
				},
				{
					n = G.UIT.C,
					config = { minw = 4 },
					nodes = {
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.dangerous_actions.sell_all_same,
							{ "Sell all", "card copies" },
							"Hold",
							{
								Handy.UI.PARTS.format_module_keys(Handy.cc.dangerous_actions.immediate_buy_and_sell)
									.. ",",
								"hold "
									.. Handy.UI.PARTS.format_module_keys(Handy.cc.dangerous_actions.sell_all_same)
									.. ",",
								"and click on card to sell",
								"all of their copies",
							},
							true
						),
						{ n = G.UIT.R, config = { minh = 0.1 } },
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.dangerous_actions.sell_all,
							"Sell ALL",
							"Hold",
							{
								"to",
								"sell ALL cards in area instead",
							}
						),
						{ n = G.UIT.R, config = { minh = 0.1 } },
						Handy.UI.PARTS.create_module_checkbox(
							Handy.cc.dangerous_actions.card_remove,
							{ "REMOVE* cards", "or skip tags" },
							"Hold",
							{
								"to",
								"REMOVE cards instead",
								"of selling, works for skip tags",
							}
						),
					},
				},
			},
		},
		{ n = G.UIT.R, config = { minh = 0.4 } },
		{
			n = G.UIT.R,
			config = { padding = 0.1, align = "cm" },
			nodes = {
				{
					n = G.UIT.T,
					config = {
						text = "*REMOVE card/tag - delete without any checks, effects, triggers or money refunds",
						scale = 0.3,
						colour = { 1, 1, 1, 0.6 },
						align = "cm",
					},
				},
			},
		},
		-- { n = G.UIT.R, config = { minh = 0.25 } },
	}
end

Handy.UI.get_config_tab_regular_keybinds = function()
	return {
		Handy.UI.PARTS.create_module_section("Round"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.regular_keybinds.play, "Play hand"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.regular_keybinds.discard, "Discard"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.regular_keybinds.sort_by_rank, "Sort by rank"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.regular_keybinds.sort_by_suit, "Sort by suit"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.deselect_hand, "Deselect hand"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.insta_cash_out, "Cash Out"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.not_just_yet_interaction, "NotJustYet: End round"),
		Handy.UI.PARTS.create_module_section("Shop and Blinds"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.insta_booster_skip, "Skip Booster Pack"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.regular_keybinds.reroll_shop, "Shop reroll"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.regular_keybinds.leave_shop, "Leave shop"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.regular_keybinds.skip_blind, "Skip blind"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.regular_keybinds.select_blind, "Select blind"),
		Handy.UI.PARTS.create_module_section("Menus"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.regular_keybinds.run_info, "Run info: Poker hands"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.regular_keybinds.run_info_blinds, "Run info: Blinds"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.regular_keybinds.view_deck, "View deck"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.show_deck_preview, "Deck preview"),
	}
end

Handy.UI.get_config_tab_keybinds_2 = function()
	return {
		Handy.UI.PARTS.create_module_section("Quick actions"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.insta_buy_or_sell, "Quick Buy/Sell"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.insta_use, "Quick Use"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.insta_buy_n_sell, "Quick Buy'n'Sell"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.insta_highlight_entire_f_hand, "Highlight entire hand"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.cryptid_code_use_last_interaction, "Cryptid: use previous input"),
		Handy.UI.PARTS.create_module_section("Dangerous actions"),
		Handy.UI.PARTS.create_module_keybind(
			Handy.cc.dangerous_actions.immediate_buy_and_sell,
			"Dangerous modifier",
			true
		),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.dangerous_actions.sell_all_same, "Sell all copies of card", true),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.dangerous_actions.sell_all, "Sell ALL cards", true),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.dangerous_actions.card_remove, "REMOVE cards", true),
		Handy.UI.PARTS.create_module_section("Game speed and animations"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.speed_multiplier, "Speed Multiplier"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.nopeus_interaction, "Nopeus: fast-forward"),
		Handy.UI.PARTS.create_module_section("Highlight movement"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.move_highlight.dx.one_left, "Move one left"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.move_highlight.dx.one_right, "Move one right"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.move_highlight.swap, "Move card"),
		Handy.UI.PARTS.create_module_keybind(Handy.cc.move_highlight.to_end, "Move to end"),
	}
end

Handy.UI.get_config_tab = function(_tab)
	local result = {
		n = G.UIT.ROOT,
		config = { align = "cm", padding = 0.05, colour = G.C.CLEAR, minh = 5, minw = 5 },
		nodes = {},
	}
	if _tab == "Overall" then
		result.nodes = Handy.UI.get_config_tab_overall()
	elseif _tab == "Quick" then
		result.nodes = Handy.UI.get_config_tab_quick()
	elseif _tab == "Interactions" then
		result.nodes = Handy.UI.get_config_tab_interactions()
	elseif _tab == "Dangerous" then
		result.nodes = Handy.UI.get_config_tab_dangerous()
	elseif _tab == "Keybinds" then
		result.nodes = Handy.UI.get_config_tab_regular_keybinds()
	elseif _tab == "Keybinds 2" then
		result.nodes = Handy.UI.get_config_tab_keybinds_2()
	end
	return result
end

--

function Handy.UI.get_options_tabs()
	return {
		{
			label = "General & Vanilla",
			tab_definition_function = function()
				return Handy.UI.get_config_tab("Overall")
			end,
		},
		{
			label = "Quick actions",
			tab_definition_function = function()
				return Handy.UI.get_config_tab("Quick")
			end,
		},
		{
			label = "Danger zone",
			tab_definition_function = function()
				return Handy.UI.get_config_tab("Dangerous")
			end,
		},
		{
			label = "Regular keybinds",
			tab_definition_function = function()
				return Handy.UI.get_config_tab("Keybinds")
			end,
		},
		{
			label = "Other keybinds",
			tab_definition_function = function()
				return Handy.UI.get_config_tab("Keybinds 2")
			end,
		},
	}
end

--

function G.UIDEF.handy_options()
	local tabs = Handy.UI.get_options_tabs()
	tabs[1].chosen = true
	local t = create_UIBox_generic_options({
		back_func = "options",
		contents = {
			{
				n = G.UIT.R,
				config = { align = "cm", padding = 0 },
				nodes = {
					create_tabs({
						tabs = tabs,
						snap_to_nav = true,
						colour = G.C.BOOSTER,
					}),
				},
			},
		},
	})
	return t
end

function G.FUNCS.handy_open_options()
	G.SETTINGS.paused = true
	G.FUNCS.overlay_menu({
		definition = G.UIDEF.handy_options(),
	})
end

function Handy.UI.get_options_button()
	return UIBox_button({ label = { "Handy" }, button = "handy_open_options", minw = 5, colour = G.C.CHIPS })
end

-- Code taken from Anhk by MathIsFun
local create_uibox_options_ref = create_UIBox_options
function create_UIBox_options()
	local contents = create_uibox_options_ref()
	if Handy.UI.show_options_button then
		table.insert(contents.nodes[1].nodes[1].nodes[1].nodes, Handy.UI.get_options_button())
	end
	return contents
end

local lovely = require("lovely")
local nativefs = require("nativefs")

if not nativefs.getInfo(lovely.mod_dir .. "/Talisman") then
    error(
        'Could not find proper Talisman folder.\nPlease make sure the folder for Talisman is named exactly "Talisman" and not "Talisman-main" or anything else.')
end

Talisman = {config_file = {disable_anims = true, break_infinity = "omeganum", score_opt_id = 2}}
if nativefs.read(lovely.mod_dir.."/Talisman/config.lua") then
    Talisman.config_file = STR_UNPACK(nativefs.read(lovely.mod_dir.."/Talisman/config.lua"))

    if Talisman.config_file.break_infinity and type(Talisman.config_file.break_infinity) ~= 'string' then
      Talisman.config_file.break_infinity = "omeganum"
    end
end
if not SMODS or not JSON then
  local createOptionsRef = create_UIBox_options
  function create_UIBox_options()
  contents = createOptionsRef()
  local m = UIBox_button({
  minw = 5,
  button = "talismanMenu",
  label = {
  "Talisman"
  },
  colour = G.C.GOLD
  })
  table.insert(contents.nodes[1].nodes[1].nodes[1].nodes, #contents.nodes[1].nodes[1].nodes[1].nodes + 1, m)
  return contents
  end
end

Talisman.config_tab = function()
                tal_nodes = {{n=G.UIT.R, config={align = "cm"}, nodes={
                  {n=G.UIT.O, config={object = DynaText({string = "Select features to enable:", colours = {G.C.WHITE}, shadow = true, scale = 0.4})}},
                }},create_toggle({label = "Disable Scoring Animations", ref_table = Talisman.config_file, ref_value = "disable_anims",
                callback = function(_set_toggle)
	                nativefs.write(lovely.mod_dir .. "/Talisman/config.lua", STR_PACK(Talisman.config_file))
                end}),
                create_option_cycle({
                  label = "Score Limit (requires game restart)",
                  scale = 0.8,
                  w = 6,
                  options = {"Vanilla (e308)", "BigNum (ee308)", "OmegaNum (e10##1000)"},
                  opt_callback = 'talisman_upd_score_opt',
                  current_option = Talisman.config_file.score_opt_id,
                })}
                return {
                n = G.UIT.ROOT,
                config = {
                    emboss = 0.05,
                    minh = 6,
                    r = 0.1,
                    minw = 10,
                    align = "cm",
                    padding = 0.2,
                    colour = G.C.BLACK
                },
                nodes = tal_nodes
            }
              end
G.FUNCS.talismanMenu = function(e)
  local tabs = create_tabs({
      snap_to_nav = true,
      tabs = {
          {
              label = "Talisman",
              chosen = true,
              tab_definition_function = Talisman.config_tab
          },
      }})
  G.FUNCS.overlay_menu{
          definition = create_UIBox_generic_options({
              back_func = "options",
              contents = {tabs}
          }),
      config = {offset = {x=0,y=10}}
  }
end
G.FUNCS.talisman_upd_score_opt = function(e)
  Talisman.config_file.score_opt_id = e.to_key
  local score_opts = {"", "bignumber", "omeganum"}
  Talisman.config_file.break_infinity = score_opts[e.to_key]
  nativefs.write(lovely.mod_dir .. "/Talisman/config.lua", STR_PACK(Talisman.config_file))
end
if Talisman.config_file.break_infinity then
  Big, err = nativefs.load(lovely.mod_dir.."/Talisman/big-num/"..Talisman.config_file.break_infinity..".lua")
  if not err then Big = Big() else Big = nil end
  Notations = nativefs.load(lovely.mod_dir.."/Talisman/big-num/notations.lua")()
  -- We call this after init_game_object to leave room for mods that add more poker hands
  Talisman.igo = function(obj)
      for _, v in pairs(obj.hands) do
          v.chips = to_big(v.chips)
          v.mult = to_big(v.mult)
          v.s_chips = to_big(v.s_chips)
          v.s_mult = to_big(v.s_mult)
          v.l_chips = to_big(v.l_chips)
          v.l_mult = to_big(v.l_mult)
          v.level = to_big(v.level)
      end
      obj.starting_params.dollars = to_big(obj.starting_params.dollars)
      return obj
  end

  local nf = number_format
  function number_format(num, e_switch_point)
      if type(num) == 'table' then
          num = to_big(num)
          G.E_SWITCH_POINT = G.E_SWITCH_POINT or 100000000000
          if num < to_big(e_switch_point or G.E_SWITCH_POINT) then
              return nf(num:to_number(), e_switch_point)
          else
            return Notations.Balatro:format(num, 3)
          end
      else return nf(num, e_switch_point) end
  end

  local mf = math.floor
  function math.floor(x)
      if type(x) == 'table' then return x:floor() end
      return mf(x)
  end
  local mc = math.ceil
  function math.ceil(x)
      if type(x) == 'table' then return x:ceil() end
      return mc(x)
  end

function lenient_bignum(x)
    if type(x) == "number" then return x end
    if to_big(x) < to_big(1e300) and to_big(x) > to_big(-1e300) then
      return x:to_number()
    end
    return x
  end

  --prevent some log-related crashes
  local sns = score_number_scale
  function score_number_scale(scale, amt)
    local ret = sns(scale, amt)
    if type(ret) == "table" then
      if ret > to_big(1e300) then return 1e300 end
      return ret:to_number()
    end
    return ret
  end

  local gftsj = G.FUNCS.text_super_juice
  function G.FUNCS.text_super_juice(e, _amount)
    if type(_amount) == "table" then
      if _amount > to_big(1e300) then
        _amount = 1e300
      else
        _amount = _amount:to_number()
      end
    end
    return gftsj(e, _amount)
  end

  local l10 = math.log10
  function math.log10(x)
      if type(x) == 'table' then 
        if x.log10 then return lenient_bignum(x:log10()) end
        return lenient_bignum(l10(math.min(x:to_number(),1e300)))
      end
      return lenient_bignum(l10(x))
  end

  local lg = math.log
  function math.log(x, y)
      if not y then y = 2.718281828459045 end
      if type(x) == 'table' then 
        if x.log then return lenient_bignum(x:log(to_big(y))) end
        if x.logBase then return lenient_bignum(x:logBase(to_big(y))) end
        return lenient_bignum(lg(math.min(x:to_number(),1e300),y))
      end
      return lenient_bignum(lg(x,y))
  end

  function math.exp(x)
    local big_e = to_big(2.718281828459045)
    
    return lenient_bignum(big_e:pow(x))
  end 

  if SMODS then
    function SMODS.get_blind_amount(ante)
      local k = to_big(0.75)
      local scale = G.GAME.modifiers.scaling
      local amounts = {
          to_big(300),
          to_big(700 + 100*scale),
          to_big(1400 + 600*scale),
          to_big(2100 + 2900*scale),
          to_big(15000 + 5000*scale*math.log(scale)),
          to_big(12000 + 8000*(scale+1)*(0.4*scale)),
          to_big(10000 + 25000*(scale+1)*((scale/4)^2)),
          to_big(50000 * (scale+1)^2 * (scale/7)^2)
      }
      
      if ante < 1 then return to_big(100) end
      if ante <= 8 then 
        local amount = amounts[ante]
        if (amount:lt(R.E_MAX_SAFE_INTEGER)) then
          local exponent = to_big(10)^(math.floor(amount:log10() - to_big(1))):to_number()
          amount = math.floor(amount / exponent):to_number() * exponent
        end
        amount:normalize()
        return amount
       end
      local a, b, c, d = amounts[8], amounts[8]/amounts[7], ante-8, 1 + 0.2*(ante-8)
      local amount = math.floor(a*(b + (b*k*c)^d)^c)
      if (amount:lt(R.E_MAX_SAFE_INTEGER)) then
        local exponent = to_big(10)^(math.floor(amount:log10() - to_big(1))):to_number()
        amount = math.floor(amount / exponent):to_number() * exponent
      end
      amount:normalize()
      return amount
    end
  end
  -- There's too much to override here so we just fully replace this function
  -- Note that any ante scaling tweaks will need to manually changed...
  local gba = get_blind_amount
  function get_blind_amount(ante)
    if G.GAME.modifiers.scaling and G.GAME.modifiers.scaling > 3 then return SMODS.get_blind_amount(ante) end
    if type(to_big(1)) == 'number' then return gba(ante) end
      local k = to_big(0.75)
      if not G.GAME.modifiers.scaling or G.GAME.modifiers.scaling == 1 then 
        local amounts = {
          to_big(300),  to_big(800), to_big(2000),  to_big(5000),  to_big(11000),  to_big(20000),   to_big(35000),  to_big(50000)
        }
        if ante < 1 then return to_big(100) end
        if ante <= 8 then return amounts[ante] end
        local a, b, c, d = amounts[8],1.6,ante-8, 1 + 0.2*(ante-8)
        local amount = a*(b+(k*c)^d)^c
        if (amount:lt(R.E_MAX_SAFE_INTEGER)) then
          local exponent = to_big(10)^(math.floor(amount:log10() - to_big(1))):to_number()
          amount = math.floor(amount / exponent):to_number() * exponent
        end
        amount:normalize()
        return amount
      elseif G.GAME.modifiers.scaling == 2 then 
        local amounts = {
          to_big(300),  to_big(900), to_big(2600),  to_big(8000), to_big(20000),  to_big(36000),  to_big(60000),  to_big(100000)
          --300,  900, 2400,  7000,  18000,  32000,  56000,  90000
        }
        if ante < 1 then return to_big(100) end
        if ante <= 8 then return amounts[ante] end
        local a, b, c, d = amounts[8],1.6,ante-8, 1 + 0.2*(ante-8)
        local amount = a*(b+(k*c)^d)^c
        if (amount:lt(R.E_MAX_SAFE_INTEGER)) then
          local exponent = to_big(10)^(math.floor(amount:log10() - to_big(1))):to_number()
          amount = math.floor(amount / exponent):to_number() * exponent
        end
        amount:normalize()
        return amount
      elseif G.GAME.modifiers.scaling == 3 then 
        local amounts = {
          to_big(300),  to_big(1000), to_big(3200),  to_big(9000),  to_big(25000),  to_big(60000),  to_big(110000),  to_big(200000)
          --300,  1000, 3000,  8000,  22000,  50000,  90000,  180000
        }
        if ante < 1 then return to_big(100) end
        if ante <= 8 then return amounts[ante] end
        local a, b, c, d = amounts[8],1.6,ante-8, 1 + 0.2*(ante-8)
        local amount = a*(b+(k*c)^d)^c
        if (amount:lt(R.E_MAX_SAFE_INTEGER)) then
          local exponent = to_big(10)^(math.floor(amount:log10() - to_big(1))):to_number()
          amount = math.floor(amount / exponent):to_number() * exponent
        end
        amount:normalize()
        return amount
      end
    end

  function check_and_set_high_score(score, amt)
    if G.GAME.round_scores[score] and to_big(math.floor(amt)) > to_big(G.GAME.round_scores[score].amt) then
      G.GAME.round_scores[score].amt = to_big(math.floor(amt))
    end
    if  G.GAME.seeded  then return end
    --[[if G.PROFILES[G.SETTINGS.profile].high_scores[score] and math.floor(amt) > G.PROFILES[G.SETTINGS.profile].high_scores[score].amt then
      if G.GAME.round_scores[score] then G.GAME.round_scores[score].high_score = true end
      G.PROFILES[G.SETTINGS.profile].high_scores[score].amt = math.floor(amt)
      G:save_settings()
    end--]] --going to hold off on modifying this until proper save loading exists
  end

  local ics = inc_career_stat
  -- This is used often for unlocks, so we can't just prevent big money from being added
  -- Also, I'm completely overriding this, since I don't think any mods would want to change it
  function inc_career_stat(stat, mod)
    if G.GAME.seeded or G.GAME.challenge then return end
    if not G.PROFILES[G.SETTINGS.profile].career_stats[stat] then G.PROFILES[G.SETTINGS.profile].career_stats[stat] = 0 end
    G.PROFILES[G.SETTINGS.profile].career_stats[stat] = G.PROFILES[G.SETTINGS.profile].career_stats[stat] + (mod or 0)
    -- Make sure this isn't ever a talisman number
    if type(G.PROFILES[G.SETTINGS.profile].career_stats[stat]) == 'table' then
      if G.PROFILES[G.SETTINGS.profile].career_stats[stat] > to_big(1e300) then
        G.PROFILES[G.SETTINGS.profile].career_stats[stat] = to_big(1e300)
      elseif G.PROFILES[G.SETTINGS.profile].career_stats[stat] < to_big(-1e300) then
        G.PROFILES[G.SETTINGS.profile].career_stats[stat] = to_big(-1e300)
      end
      G.PROFILES[G.SETTINGS.profile].career_stats[stat] = G.PROFILES[G.SETTINGS.profile].career_stats[stat]:to_number()
    end
    G:save_settings()
  end

  local sn = scale_number
  function scale_number(number, scale, max, e_switch_point)
    if not Big then return sn(number, scale, max, e_switch_point) end
    scale = to_big(scale)
    G.E_SWITCH_POINT = G.E_SWITCH_POINT or 100000000000
    if not number or not is_number(number) then return scale end
    if not max then max = 10000 end
    if to_big(number).e and to_big(number).e == 10^1000 then
      scale = scale*math.floor(math.log(max*10, 10))/7
    end
    if to_big(number) >= to_big(e_switch_point or G.E_SWITCH_POINT) then
      if (to_big(to_big(number):log10()) <= to_big(999)) then
        scale = scale*math.floor(math.log(max*10, 10))/math.floor(math.log(1000000*10, 10))
      else
        scale = scale*math.floor(math.log(max*10, 10))/math.floor(math.max(7,string.len(number_format(number))-1))
      end
    elseif to_big(number) >= to_big(max) then
      scale = scale*math.floor(math.log(max*10, 10))/math.floor(math.log(number*10, 10))
    end
    return math.min(3, scale:to_number())
  end

  local tsj = G.FUNCS.text_super_juice
  function G.FUNCS.text_super_juice(e, _amount)
    if type(_amount) == 'table' then
      if _amount > to_big(2) then _amount = 2 end
    else
      if _amount > 2 then _amount = 2 end
    end
    return tsj(e, _amount)
  end

  local max = math.max
  --don't return a Big unless we have to - it causes nativefs to break
  function math.max(x, y)
    if type(x) == 'table' or type(y) == 'table' then
    x = to_big(x)
    y = to_big(y)
    if (x > y) then
      return x
    else
      return y
    end
    else return max(x,y) end
  end

  local min = math.min
  function math.min(x, y)
    if type(x) == 'table' or type(y) == 'table' then
    x = to_big(x)
    y = to_big(y)
    if (x < y) then
      return x
    else
      return y
    end
    else return min(x,y) end
  end

  local sqrt = math.sqrt
  function math.sqrt(x)
    if type(x) == 'table' then
      if getmetatable(x) == BigMeta then return x:sqrt() end
      if getmetatable(x) == OmegaMeta then return x:pow(0.5) end
    end
    return sqrt(x)
  end

 

  local old_abs = math.abs
  function math.abs(x)
    if type(x) == 'table' then
    x = to_big(x)
    if (x < to_big(0)) then
      return -1 * x
    else
      return x
    end
    else return old_abs(x) end
  end
end

function is_number(x)
  if type(x) == 'number' then return true end
  if type(x) == 'table' and ((x.e and x.m) or (x.array and x.sign)) then return true end
  return false
end

function to_big(x, y)
  if type(x) == 'string' and x == "0" then --hack for when 0 is asked to be a bignumber need to really figure out the fix
    return 0
  elseif Big and Big.m then
    return Big:new(x,y)
  elseif Big and Big.array then
    local result = Big:create(x)
    result.sign = y or result.sign or x.sign or 1
    return result
  elseif is_number(x) then
    return x * 10^(y or 0)

  elseif type(x) == "nil" then
    return 0
  else
    if ((#x>=2) and ((x[2]>=2) or (x[2]==1) and (x[1]>308))) then
      return 1e309
    end
    if (x[2]==1) then
      return math.pow(10,x[1])
    end
    return x[1]*(y or 1);
  end
end
function to_number(x)
  if type(x) == 'table' and (getmetatable(x) == BigMeta or getmetatable(x) == OmegaMeta) then
    return x:to_number()
  else
    return x
  end
end

--patch to remove animations
local cest = card_eval_status_text
function card_eval_status_text(a,b,c,d,e,f)
    if not Talisman.config_file.disable_anims then cest(a,b,c,d,e,f) end
end
local jc = juice_card
function juice_card(x)
    if not Talisman.config_file.disable_anims then jc(x) end
end
local cju = Card.juice_up
function Card:juice_up(...)
    if not Talisman.config_file.disable_anims then cju(self, ...) end
end
function tal_uht(config, vals)
    local col = G.C.GREEN
    if vals.chips and G.GAME.current_round.current_hand.chips ~= vals.chips then
        local delta = (is_number(vals.chips) and is_number(G.GAME.current_round.current_hand.chips)) and (vals.chips - G.GAME.current_round.current_hand.chips) or 0
        if to_big(delta) < to_big(0) then delta = number_format(delta); col = G.C.RED
        elseif to_big(delta) > to_big(0) then delta = '+'..number_format(delta)
        else delta = number_format(delta)
        end
        if type(vals.chips) == 'string' then delta = vals.chips end
        G.GAME.current_round.current_hand.chips = vals.chips
        if G.hand_text_area.chips.config.object then
          G.hand_text_area.chips:update(0)
        end
    end
    if vals.mult and G.GAME.current_round.current_hand.mult ~= vals.mult then
        local delta = (is_number(vals.mult) and is_number(G.GAME.current_round.current_hand.mult))and (vals.mult - G.GAME.current_round.current_hand.mult) or 0
        if to_big(delta) < to_big(0) then delta = number_format(delta); col = G.C.RED
        elseif to_big(delta) > to_big(0) then delta = '+'..number_format(delta)
        else delta = number_format(delta)
        end
        if type(vals.mult) == 'string' then delta = vals.mult end
        G.GAME.current_round.current_hand.mult = vals.mult
        if G.hand_text_area.mult.config.object then
          G.hand_text_area.mult:update(0)
        end
    end
    if vals.handname and G.GAME.current_round.current_hand.handname ~= vals.handname then
        G.GAME.current_round.current_hand.handname = vals.handname
    end
    if vals.chip_total then G.GAME.current_round.current_hand.chip_total = vals.chip_total;G.hand_text_area.chip_total.config.object:pulse(0.5) end
    if vals.level and G.GAME.current_round.current_hand.hand_level ~= ' '..localize('k_lvl')..tostring(vals.level) then
        if vals.level == '' then
            G.GAME.current_round.current_hand.hand_level = vals.level
        else
            G.GAME.current_round.current_hand.hand_level = ' '..localize('k_lvl')..tostring(vals.level)
            if is_number(vals.level) then
                G.hand_text_area.hand_level.config.colour = G.C.HAND_LEVELS[type(vals.level) == "number" and math.floor(math.min(vals.level, 7)) or math.floor(to_big(math.min(vals.level, 7))):to_number()]
            else
                G.hand_text_area.hand_level.config.colour = G.C.HAND_LEVELS[1]
            end
        end
    end
    return true
end
local uht = update_hand_text
function update_hand_text(config, vals)
    if Talisman.config_file.disable_anims then
        if G.latest_uht then
          local chips = G.latest_uht.vals.chips
          local mult = G.latest_uht.vals.mult
          if not vals.chips then vals.chips = chips end
          if not vals.mult then vals.mult = mult end
        end
        G.latest_uht = {config = config, vals = vals}
    else uht(config, vals)
    end
end


G.FUNCS.evaluate_play = function(e)
  Talisman.scoring_state = "intro"
  text, disp_text, poker_hands, scoring_hand, non_loc_disp_text, percent, percent_delta = evaluate_play_intro()
  if not G.GAME.blind:debuff_hand(G.play.cards, poker_hands, text) then
    Talisman.scoring_state = "main"
    text, disp_text, poker_hands, scoring_hand, non_loc_disp_text, percent, percent_delta = evaluate_play_main(text, disp_text, poker_hands, scoring_hand, non_loc_disp_text, percent, percent_delta)
  else
    Talisman.scoring_state = "debuff"
    text, disp_text, poker_hands, scoring_hand, non_loc_disp_text, percent, percent_delta = evaluate_play_debuff(text, disp_text, poker_hands, scoring_hand, non_loc_disp_text, percent, percent_delta)
  end
  Talisman.scoring_state = "final_scoring"
  text, disp_text, poker_hands, scoring_hand, non_loc_disp_text, percent, percent_delta = evaluate_play_final_scoring(text, disp_text, poker_hands, scoring_hand, non_loc_disp_text, percent, percent_delta)
  Talisman.scoring_state = "after"
  evaluate_play_after(text, disp_text, poker_hands, scoring_hand, non_loc_disp_text, percent, percent_delta)
  Talisman.scoring_state = nil
end

local upd = Game.update
function Game:update(dt)
    upd(self, dt)
    if G.latest_uht and G.latest_uht.config and G.latest_uht.vals then
        tal_uht(G.latest_uht.config, G.latest_uht.vals)
        G.latest_uht = nil
    end
    if Talisman.dollar_update then
      G.HUD:get_UIE_by_ID('dollar_text_UI').config.object:update()
      G.HUD:recalculate()
      Talisman.dollar_update = false
    end
end
Talisman.F_NO_COROUTINE = false --easy disabling for bugfixing, since the coroutine can make it hard to see where errors are
if not Talisman.F_NO_COROUTINE then
  --scoring coroutine
  local oldplay = G.FUNCS.evaluate_play

  function G.FUNCS.evaluate_play(...)
      G.SCORING_COROUTINE = coroutine.create(oldplay)
      G.LAST_SCORING_YIELD = love.timer.getTime()
      G.CARD_CALC_COUNTS = {} -- keys = cards, values = table containing numbers
      local success, err = coroutine.resume(G.SCORING_COROUTINE, ...)
      if not success then
        error(err)
      end
  end

  function G.FUNCS.tal_abort()
      tal_aborted = true
  end

  local oldupd = love.update

  function love.update(dt, ...)
      oldupd(dt, ...)
      if G.SCORING_COROUTINE then
        if collectgarbage("count") > 1024*1024 then
          collectgarbage("collect")
        end
          if coroutine.status(G.SCORING_COROUTINE) == "dead" or tal_aborted then
              G.SCORING_COROUTINE = nil
              G.FUNCS.exit_overlay_menu()
              local totalCalcs = 0
              for i, v in pairs(G.CARD_CALC_COUNTS) do
                totalCalcs = totalCalcs + v[1]
              end
              G.GAME.LAST_CALCS = totalCalcs
              G.GAME.LAST_CALC_TIME = G.CURRENT_CALC_TIME
              G.CURRENT_CALC_TIME = 0
              if tal_aborted and Talisman.scoring_state == "main" then
                evaluate_play_final_scoring(text, disp_text, poker_hands, scoring_hand, non_loc_disp_text, percent, percent_delta)
              end
              tal_aborted = nil
              Talisman.scoring_state = nil
          else
              G.SCORING_TEXT = nil
              if not G.OVERLAY_MENU then
                  G.scoring_text = {"Calculating...", "", "", ""}
                  G.SCORING_TEXT = { 
                    {n = G.UIT.C, nodes = {
                      {n = G.UIT.R, config = {padding = 0.1, align = "cm"}, nodes = {
                      {n=G.UIT.O, config={object = DynaText({string = {{ref_table = G.scoring_text, ref_value = 1}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, pop_in = 0, scale = 1, silent = true})}},
                      }},{n = G.UIT.R,  nodes = {
                      {n=G.UIT.O, config={object = DynaText({string = {{ref_table = G.scoring_text, ref_value = 2}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, pop_in = 0, scale = 0.4, silent = true})}},
                      }},{n = G.UIT.R,  nodes = {
                      {n=G.UIT.O, config={object = DynaText({string = {{ref_table = G.scoring_text, ref_value = 3}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, pop_in = 0, scale = 0.4, silent = true})}},
                      }},{n = G.UIT.R,  nodes = {
                      {n=G.UIT.O, config={object = DynaText({string = {{ref_table = G.scoring_text, ref_value = 4}}, colours = {G.C.UI.TEXT_LIGHT}, shadow = true, pop_in = 0, scale = 0.4, silent = true})}},
                      }},{n = G.UIT.R,  nodes = {
                      UIBox_button({
                        colour = G.C.BLUE,
                        button = "tal_abort",
                        label = { "Abort" },
                        minw = 4.5,
                        focus_args = { snap_to = true },
                      })}},
                    }}}
                  G.FUNCS.overlay_menu({
                      definition = 
                      {n=G.UIT.ROOT, minw = G.ROOM.T.w*5, minh = G.ROOM.T.h*5, config={align = "cm", padding = 9999, offset = {x = 0, y = -3}, r = 0.1, colour = {G.C.GREY[1], G.C.GREY[2], G.C.GREY[3],0.7}}, nodes= G.SCORING_TEXT}, 
                      config = {align="cm", offset = {x=0,y=0}, major = G.ROOM_ATTACH, bond = 'Weak'}
                  })
              else

                  if G.OVERLAY_MENU and G.scoring_text then
                    local totalCalcs = 0
                    for i, v in pairs(G.CARD_CALC_COUNTS) do
                      totalCalcs = totalCalcs + v[1]
                    end
                    local jokersYetToScore = #G.jokers.cards + #G.play.cards - #G.CARD_CALC_COUNTS
                    G.CURRENT_CALC_TIME = (G.CURRENT_CALC_TIME or 0) + dt
                    G.scoring_text[1] = "Calculating..."
                    G.scoring_text[2] = "Elapsed calculations: "..tostring(totalCalcs).." ("..tostring(number_format(G.CURRENT_CALC_TIME)).."s)"
                    G.scoring_text[3] = "Cards yet to score: "..tostring(jokersYetToScore)
                    G.scoring_text[4] = "Calculations last played hand: " .. tostring(G.GAME.LAST_CALCS or "Unknown") .." ("..tostring(G.GAME.LAST_CALC_TIME and number_format(G.GAME.LAST_CALC_TIME) or "???").."s)"
                  end

              end
        --this coroutine allows us to stagger GC cycles through
        --the main source of waste in terms of memory (especially w joker retriggers) is through local variables that become garbage
        --this practically eliminates the memory overhead of scoring
        --event queue overhead seems to not exist if Talismans Disable Scoring Animations is off.
        --event manager has to wait for scoring to finish until it can keep processing events anyways.

              
              G.LAST_SCORING_YIELD = love.timer.getTime()
              
              local success, msg = coroutine.resume(G.SCORING_COROUTINE)
              if not success then
                error(msg)
              end
          end
      end
  end



  TIME_BETWEEN_SCORING_FRAMES = 0.03 -- 30 fps during scoring
  -- we dont want overhead from updates making scoring much slower
  -- originally 10 fps, I think 30 fps is a good way to balance it while making it look smooth, too
  --wrap everything in calculating contexts so we can do more things with it
  Talisman.calculating_joker = false
  Talisman.calculating_score = false
  Talisman.calculating_card = false
  Talisman.dollar_update = false
  local ccj = Card.calculate_joker
  function Card:calculate_joker(context)
    --scoring coroutine
    G.CURRENT_SCORING_CARD = self
    G.CARD_CALC_COUNTS = G.CARD_CALC_COUNTS or {}
    if G.CARD_CALC_COUNTS[self] then
      G.CARD_CALC_COUNTS[self][1] = G.CARD_CALC_COUNTS[self][1] + 1
    else
      G.CARD_CALC_COUNTS[self] = {1, 1}
    end


    if G.LAST_SCORING_YIELD and ((love.timer.getTime() - G.LAST_SCORING_YIELD) > TIME_BETWEEN_SCORING_FRAMES) and coroutine.running() then
          coroutine.yield()
    end
    Talisman.calculating_joker = true
    local ret, trig = ccj(self, context)

    if ret and type(ret) == "table" and ret.repetitions then
      if not ret.card then
        G.CARD_CALC_COUNTS.other = G.CARD_CALC_COUNTS.other or {1,1}
        G.CARD_CALC_COUNTS.other[2] = G.CARD_CALC_COUNTS.other[2] + ret.repetitions
      else
        G.CARD_CALC_COUNTS[ret.card] = G.CARD_CALC_COUNTS[ret.card] or {1,1}
        G.CARD_CALC_COUNTS[ret.card][2] = G.CARD_CALC_COUNTS[ret.card][2] + ret.repetitions
      end
    end
    Talisman.calculating_joker = false
    return ret, trig
  end
  local cuc = Card.use_consumable
  function Card:use_consumable(x,y)
    Talisman.calculating_score = true
    local ret = cuc(self, x,y)
    Talisman.calculating_score = false
    return ret
  end
  local gfep = G.FUNCS.evaluate_play
  G.FUNCS.evaluate_play = function(e)
    Talisman.calculating_score = true
    local ret = gfep(e)
    Talisman.calculating_score = false
    return ret
  end
end
--[[local ec = eval_card
function eval_card()
  Talisman.calculating_card = true
  local ret = ec()
  Talisman.calculating_card = false
  return ret
end--]]
local sm = Card.start_materialize
function Card:start_materialize(a,b,c)
  if Talisman.config_file.disable_anims and (Talisman.calculating_joker or Talisman.calculating_score or Talisman.calculating_card) then return end
  return sm(self,a,b,c)
end
local sd = Card.start_dissolve
function Card:start_dissolve(a,b,c,d)
  if Talisman.config_file.disable_anims and (Talisman.calculating_joker or Talisman.calculating_score or Talisman.calculating_card) then self:remove() return end
  return sd(self,a,b,c,d)
end
local ss = Card.set_seal
function Card:set_seal(a,b,immediate)
  return ss(self,a,b,Talisman.config_file.disable_anims and (Talisman.calculating_joker or Talisman.calculating_score or Talisman.calculating_card) or immediate)
end

function Card:get_chip_x_bonus()
    if self.debuff then return 0 end
    if self.ability.set == 'Joker' then return 0 end
    if (self.ability.x_chips or 0) <= 1 then return 0 end
    return self.ability.x_chips
end

function Card:get_chip_e_bonus()
    if self.debuff then return 0 end
    if self.ability.set == 'Joker' then return 0 end
    if (self.ability.e_chips or 0) <= 1 then return 0 end
    return self.ability.e_chips
end

function Card:get_chip_ee_bonus()
    if self.debuff then return 0 end
    if self.ability.set == 'Joker' then return 0 end
    if (self.ability.ee_chips or 0) <= 1 then return 0 end
    return self.ability.ee_chips
end

function Card:get_chip_eee_bonus()
    if self.debuff then return 0 end
    if self.ability.set == 'Joker' then return 0 end
    if (self.ability.eee_chips or 0) <= 1 then return 0 end
    return self.ability.eee_chips
end

function Card:get_chip_hyper_bonus()
    if self.debuff then return {0,0} end
    if self.ability.set == 'Joker' then return {0,0} end
	if type(self.ability.hyper_chips) ~= 'table' then return {0,0} end
    if (self.ability.hyper_chips[1] <= 0 or self.ability.hyper_chips[2] <= 0) then return {0,0} end
    return self.ability.hyper_chips
end

function Card:get_chip_e_mult()
    if self.debuff then return 0 end
    if self.ability.set == 'Joker' then return 0 end
    if (self.ability.e_mult or 0) <= 1 then return 0 end
    return self.ability.e_mult
end

function Card:get_chip_ee_mult()
    if self.debuff then return 0 end
    if self.ability.set == 'Joker' then return 0 end
    if (self.ability.ee_mult or 0) <= 1 then return 0 end
    return self.ability.ee_mult
end

function Card:get_chip_eee_mult()
    if self.debuff then return 0 end
    if self.ability.set == 'Joker' then return 0 end
    if (self.ability.eee_mult or 0) <= 1 then return 0 end
    return self.ability.eee_mult
end

function Card:get_chip_hyper_mult()
    if self.debuff then return {0,0} end
    if self.ability.set == 'Joker' then return {0,0} end
	if type(self.ability.hyper_mult) ~= 'table' then return {0,0} end
    if (self.ability.hyper_mult[1] <= 0 or self.ability.hyper_mult[2] <= 0) then return {0,0} end
    return self.ability.hyper_mult
end

--Easing fixes
--Changed this to always work; it's less pretty but fine for held in hand things
local edo = ease_dollars
function ease_dollars(mod, instant)
  if Talisman.config_file.disable_anims then--and (Talisman.calculating_joker or Talisman.calculating_score or Talisman.calculating_card) then
    mod = mod or 0
    if to_big(mod) < to_big(0) then inc_career_stat('c_dollars_earned', mod) end
    G.GAME.dollars = G.GAME.dollars + mod
    Talisman.dollar_update = true
  else return edo(mod, instant) end
end

local su = G.start_up
function safe_str_unpack(str)
  local chunk, err = loadstring(str)
  if chunk then
    setfenv(chunk, {Big = Big, BigMeta = BigMeta, OmegaMeta = OmegaMeta, to_big = to_big, inf = 1.79769e308})  -- Use an empty environment to prevent access to potentially harmful functions
    local success, result = pcall(chunk)
    if success then
    return result
    else
    print("[Talisman] Error unpacking string: " .. result)
    print(tostring(str))
    return nil
    end
  else
    print("[Talisman] Error loading string: " .. err)
    print(tostring(str))
    return nil
  end
  end
function G:start_up()
  STR_UNPACK = safe_str_unpack
  su(self)
  STR_UNPACK = safe_str_unpack
end

--Skip round animation things
local gfer = G.FUNCS.evaluate_round
function G.FUNCS.evaluate_round()
    if Talisman.config_file.disable_anims then
      if to_big(G.GAME.chips) >= to_big(G.GAME.blind.chips) then
          add_round_eval_row({dollars = G.GAME.blind.dollars, name='blind1', pitch = 0.95})
      else
          add_round_eval_row({dollars = 0, name='blind1', pitch = 0.95, saved = true})
      end
      local arer = add_round_eval_row
      add_round_eval_row = function() return end
      local dollars = gfer()
      add_round_eval_row = arer
      add_round_eval_row({name = 'bottom', dollars = Talisman.dollars})
    else
        return gfer()
    end
end

local g_start_run = Game.start_run
function Game:start_run(args)
  local ret = g_start_run(self, args)
  self.GAME.round_resets.ante_disp = self.GAME.round_resets.ante_disp or number_format(self.GAME.round_resets.ante)
  return ret
end

-- Steamodded calculation API: add extra operations
if SMODS and SMODS.calculate_individual_effect then
  local smods_xchips = false
  for _, v in pairs(SMODS.calculation_keys) do
    if v == 'x_chips' then
      smods_xchips = true
      break
    end
  end
  local scie = SMODS.calculate_individual_effect
  function SMODS.calculate_individual_effect(effect, scored_card, key, amount, from_edition)
    -- For some reason, some keys' animations are completely removed
    -- I think this is caused by a lovely patch conflict
    --if key == 'chip_mod' then key = 'chips' end
    --if key == 'mult_mod' then key = 'mult' end
    --if key == 'Xmult_mod' then key = 'x_mult' end
    local ret = scie(effect, scored_card, key, amount, from_edition)
    if ret then
      return ret
    end
    if not smods_xchips and (key == 'x_chips' or key == 'xchips' or key == 'Xchip_mod') and amount ~= 1 then 
      if effect.card then juice_card(effect.card) end
      hand_chips = mod_chips(hand_chips * amount)
      update_hand_text({delay = 0}, {chips = hand_chips, mult = mult})
      if not effect.remove_default_message then
          if from_edition then
              card_eval_status_text(scored_card, 'jokers', nil, percent, nil, {message = "X"..amount, colour =  G.C.EDITION, edition = true})
          elseif key ~= 'Xchip_mod' then
              if effect.xchip_message then
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'extra', nil, percent, nil, effect.xchip_message)
              else
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'x_chips', amount, percent)
              end
          end
      end
      return true
    end

    if (key == 'e_chips' or key == 'echips' or key == 'Echip_mod') and amount ~= 1 then 
      if effect.card then juice_card(effect.card) end
      hand_chips = mod_chips(hand_chips ^ amount)
      update_hand_text({delay = 0}, {chips = hand_chips, mult = mult})
      if not effect.remove_default_message then
          if from_edition then
              card_eval_status_text(scored_card, 'jokers', nil, percent, nil, {message = "^"..amount, colour =  G.C.EDITION, edition = true})
          elseif key ~= 'Echip_mod' then
              if effect.echip_message then
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'extra', nil, percent, nil, effect.echip_message)
              else
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'e_chips', amount, percent)
              end
          end
      end
      return true
    end

    if (key == 'ee_chips' or key == 'eechips' or key == 'EEchip_mod') and amount ~= 1 then 
      if effect.card then juice_card(effect.card) end
      hand_chips = mod_chips(hand_chips:arrow(2, amount))
      update_hand_text({delay = 0}, {chips = hand_chips, mult = mult})
      if not effect.remove_default_message then
          if from_edition then
              card_eval_status_text(scored_card, 'jokers', nil, percent, nil, {message = "^^"..amount, colour =  G.C.EDITION, edition = true})
          elseif key ~= 'EEchip_mod' then
              if effect.eechip_message then
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'extra', nil, percent, nil, effect.eechip_message)
              else
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'ee_chips', amount, percent)
              end
          end
      end
      return true
    end

    if (key == 'eee_chips' or key == 'eeechips' or key == 'EEEchip_mod') and amount ~= 1 then 
      if effect.card then juice_card(effect.card) end
      hand_chips = mod_chips(hand_chips:arrow(3, amount))
      update_hand_text({delay = 0}, {chips = hand_chips, mult = mult})
      if not effect.remove_default_message then
          if from_edition then
              card_eval_status_text(scored_card, 'jokers', nil, percent, nil, {message = "^^^"..amount, colour =  G.C.EDITION, edition = true})
          elseif key ~= 'EEEchip_mod' then
              if effect.eeechip_message then
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'extra', nil, percent, nil, effect.eeechip_message)
              else
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'eee_chips', amount, percent)
              end
          end
      end
      return true
    end

    if (key == 'hyper_chips' or key == 'hyperchips' or key == 'hyperchip_mod') and type(amount) == 'table' then 
      if effect.card then juice_card(effect.card) end
      hand_chips = mod_chips(hand_chips:arrow(amount[1], amount[2]))
      update_hand_text({delay = 0}, {chips = hand_chips, mult = mult})
      if not effect.remove_default_message then
          if from_edition then
              card_eval_status_text(scored_card, 'jokers', nil, percent, nil, {message = (amount[1] > 5 and ('{' .. amount[1] .. '}') or string.rep('^', amount[1])) .. amount[2], colour =  G.C.EDITION, edition = true})
          elseif key ~= 'hyperchip_mod' then
              if effect.hyperchip_message then
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'extra', nil, percent, nil, effect.hyperchip_message)
              else
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'hyper_chips', amount, percent)
              end
          end
      end
      return true
    end

    if (key == 'e_mult' or key == 'emult' or key == 'Emult_mod') and amount ~= 1 then 
      if effect.card then juice_card(effect.card) end
      mult = mod_mult(mult ^ amount)
      update_hand_text({delay = 0}, {chips = hand_chips, mult = mult})
      if not effect.remove_default_message then
          if from_edition then
              card_eval_status_text(scored_card, 'jokers', nil, percent, nil, {message = "^"..amount.." Mult", colour =  G.C.EDITION, edition = true})
          elseif key ~= 'Emult_mod' then
              if effect.emult_message then
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'extra', nil, percent, nil, effect.emult_message)
              else
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'e_mult', amount, percent)
              end
          end
      end
      return true
    end

    if (key == 'ee_mult' or key == 'eemult' or key == 'EEmult_mod') and amount ~= 1 then 
      if effect.card then juice_card(effect.card) end
      mult = mod_mult(mult:arrow(2, amount))
      update_hand_text({delay = 0}, {chips = hand_chips, mult = mult})
      if not effect.remove_default_message then
          if from_edition then
              card_eval_status_text(scored_card, 'jokers', nil, percent, nil, {message = "^^"..amount.." Mult", colour =  G.C.EDITION, edition = true})
          elseif key ~= 'EEmult_mod' then
              if effect.eemult_message then
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'extra', nil, percent, nil, effect.eemult_message)
              else
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'ee_mult', amount, percent)
              end
          end
      end
      return true
    end

    if (key == 'eee_mult' or key == 'eeemult' or key == 'EEEmult_mod') and amount ~= 1 then 
      if effect.card then juice_card(effect.card) end
      mult = mod_mult(mult:arrow(3, amount))
      update_hand_text({delay = 0}, {chips = hand_chips, mult = mult})
      if not effect.remove_default_message then
          if from_edition then
              card_eval_status_text(scored_card, 'jokers', nil, percent, nil, {message = "^^^"..amount.." Mult", colour =  G.C.EDITION, edition = true})
          elseif key ~= 'EEEmult_mod' then
              if effect.eeemult_message then
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'extra', nil, percent, nil, effect.eeemult_message)
              else
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'eee_mult', amount, percent)
              end
          end
      end
      return true
    end

    if (key == 'hyper_mult' or key == 'hypermult' or key == 'hypermult_mod') and type(amount) == 'table' then 
      if effect.card then juice_card(effect.card) end
      mult = mod_mult(mult:arrow(amount[1], amount[2]))
      update_hand_text({delay = 0}, {chips = hand_chips, mult = mult})
      if not effect.remove_default_message then
          if from_edition then
              card_eval_status_text(scored_card, 'jokers', nil, percent, nil, {message = ((amount[1] > 5 and ('{' .. amount[1] .. '}') or string.rep('^', amount[1])) .. amount[2]).." Mult", colour =  G.C.EDITION, edition = true})
          elseif key ~= 'hypermult_mod' then
              if effect.hypermult_message then
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'extra', nil, percent, nil, effect.hypermult_message)
              else
                  card_eval_status_text(scored_card or effect.card or effect.focus, 'hyper_mult', amount, percent)
              end
          end
      end
      return true
    end
  end
  for _, v in ipairs({'e_mult', 'e_chips', 'ee_mult', 'ee_chips', 'eee_mult', 'eee_chips', 'hyper_mult', 'hyper_chips',
                      'emult', 'echips', 'eemult', 'eechips', 'eeemult', 'eeechips', 'hypermult', 'hyperchips',
                      'Emult_mod', 'Echip_mod', 'EEmult_mod', 'EEchip_mod', 'EEEmult_mod', 'EEEchip_mod', 'hypermult_mod', 'hyperchip_mod'}) do
    table.insert(SMODS.calculation_keys, v)
  end
  if not smods_xchips then
    for _, v in ipairs({'x_chips', 'xchips', 'Xchip_mod'}) do
    table.insert(SMODS.calculation_keys, v)
  end
  end

  -- prvent juice animations
  local smce = SMODS.calculate_effect
  function SMODS.calculate_effect(effect, ...)
    if Talisman.config_file.disable_anims then effect.juice_card = nil end
    return smce(effect, ...)
  end
end

--some debugging functions
--[[local callstep=0
function printCallerInfo()
  -- Get debug info for the caller of the function that called printCallerInfo
  local info = debug.getinfo(3, "Sl")
  callstep = callstep+1
  if info then
      print("["..callstep.."] "..(info.short_src or "???")..":"..(info.currentline or "unknown"))
  else
      print("Caller information not available")
  end
end
local emae = EventManager.add_event
function EventManager:add_event(x,y,z)
  printCallerInfo()
  return emae(self,x,y,z)
end--]]
function HEX(hex)
    if #hex <= 6 then hex = hex.."FF" end
    local _,_,r,g,b,a = hex:find('(%x%x)(%x%x)(%x%x)(%x%x)')
    local color = {tonumber(r,16)/255,tonumber(g,16)/255,tonumber(b,16)/255,tonumber(a,16)/255 or 255}
    return color
  end

local nativefs = require("nativefs")
local lovely = require("lovely")
Trance_config = {palette = "Base Game", font = "m6x11"}
baladir = lovely.mod_dir:sub(1, #lovely.mod_dir-5)
if nativefs.read(baladir .. "/config/Trance.lua") then
    Trance_config = load(nativefs.read(baladir .. "/config/Trance.lua"))()
end
function is_color(v)
    return type(v) == 'table' and #v == 4 and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number" and type(v[4]) == "number"
end
Trance = assert(load(nativefs.read(lovely.mod_dir .. "/Trance/colors/Base Game.lua")))()
Trance_theme = assert(load(nativefs.read(lovely.mod_dir .. "/Trance/colors/"..(Trance_config.palette or "Base Game")..".lua")))()
Trance_font = assert(load(nativefs.read(lovely.mod_dir .. "/Trance/fonts/"..(Trance_config.font or "m6x11")..".lua")))()
for k, v in pairs(Trance_theme) do
    if is_color(v) then 
        Trance[k] = v
    elseif type(v) == 'table' then
        for _k, _v in pairs(Trance_theme[k]) do
            if is_color(_v) then 
                Trance[k][_k] = _v
            end
        end
    end
end
local file = NFS.read(lovely.mod_dir .. "/Trance/fonts/"..(Trance_config.font or "m6x11")..".ttf")
local gsl = Game.set_language
function Game:set_language()
    gsl(self)
    local file = NFS.read(lovely.mod_dir .. "/Trance/fonts/"..(Trance_config.font or "m6x11")..".ttf")
    love.filesystem.write("temp-font.ttf", file)
    G.LANG.font.FONT = love.graphics.newFont("temp-font.ttf", G.TILESIZE * Trance_font.render_scale)
    for k, v in pairs(Trance_font) do
        G.LANG.font[k] = v
    end
    love.filesystem.remove("temp-font.ttf")
end


local files = nativefs.getDirectoryItems(lovely.mod_dir .. "/Trance/colors")
Trance_palettes = {}
for _, v in pairs(files) do
    if v:match("%.lua$") then
        Trance_palettes[#Trance_palettes+1] = v:gsub("%.lua$", "")
    end
end
files = nativefs.getDirectoryItems(lovely.mod_dir .. "/Trance/fonts")
Trance_fonts = {}
for _, v in pairs(files) do
    if v:match("%.lua$") then
        Trance_fonts[#Trance_fonts+1] = v:gsub("%.lua$", "")
    end
end

--color injection
function Trance_set_globals(G, dt)
    for k, v in pairs(Trance) do
        if is_color(v) then 
            if is_color(G.C[k]) then ease_colour(G.C[k],v,dt) else G.C[k] = v end
        elseif type(v) == 'table' then
            if not G.C[k] then G.C[k] = {} end
            for _k, _v in pairs(Trance[k]) do
                if is_color(_v) then 
                    if is_color(G.C[k][_k]) then ease_colour(G.C[k][_k],_v,dt) else G.C[k][_k] = _v end
                end
            end
        end
    end
    if Trance.MULT then ease_colour(G.C.UI_MULT,Trance.MULT,dt) end
    if Trance.CHIPS then ease_colour(G.C.UI_CHIPS,Trance.CHIPS,dt) end
    if G.P_BLINDS then
        for k, v in pairs(Trance.BOSSES) do
            if G.P_BLINDS[k] and G.P_BLINDS[k].boss_colour then G.P_BLINDS[k].boss_colour = v end
        end
    end
end

local iip = Game.init_item_prototypes
function Game:init_item_prototypes()
    iip(self)
    for k, v in pairs(Trance.BOSSES) do
        if G.P_BLINDS[k] and G.P_BLINDS[k].boss_colour then G.P_BLINDS[k].boss_colour = v end
    end
end

G_FUNCS_options_ref = G.FUNCS.options
G.FUNCS.options = function(e)
    G_FUNCS_options_ref(e)
    if love.filesystem.getInfo(baladir .. "/config", "directory") == nil then love.filesystem.createDirectory(baladir .. "/config") end
    nativefs.write(baladir .. "/config/Trance.lua", STR_PACK(Trance_config))
end
G.FUNCS.set_Trance_font = function(x)
    Trance_config.font = x.to_val
    
    Trance_font = assert(load(nativefs.read(lovely.mod_dir .. "/Trance/fonts/"..(Trance_config.font or "m6x11")..".lua")))()
    
    local file = NFS.read(lovely.mod_dir .. "/Trance/fonts/"..Trance_config.font..".ttf")
    love.filesystem.write("temp-font.ttf", file)
    G.LANG.font.FONT = love.graphics.newFont("temp-font.ttf", G.TILESIZE * Trance_font.render_scale)
    for k, v in pairs(Trance_font) do
        G.LANG.font[k] = v
    end
    for k, v in pairs(G.I.UIBOX) do
        if v.recalculate and type(v.recalculate) == "function" then
            v:recalculate()
        end
    end
    love.filesystem.remove("temp-font.ttf")
end
G.FUNCS.set_Trance_palette = function(x)
    Trance_config.palette = x.to_val
    
    Trance = assert(load(nativefs.read(lovely.mod_dir .. "/Trance/colors/Base Game.lua")))()
    Trance_theme = assert(load(nativefs.read(lovely.mod_dir .. "/Trance/colors/"..Trance_config.palette..".lua")))()
    for k, v in pairs(Trance_theme) do
        if is_color(v) then 
            Trance[k] = v
        elseif type(v) == 'table' then
            for _k, _v in pairs(Trance_theme[k]) do
                if is_color(_v) then 
                    Trance[k][_k] = _v
                end
            end
        end
    end
    Trance_set_globals(G, 1)
end
local createOptionsRef = create_UIBox_options
  function create_UIBox_options()
  contents = createOptionsRef()
  local m = UIBox_button({
  minw = 5,
  button = "tranceMenu",
  label = {
  "Trance"
  },
  colour = G.C.BLUE
  })
  table.insert(contents.nodes[1].nodes[1].nodes[1].nodes, #contents.nodes[1].nodes[1].nodes[1].nodes + 1, m)
  return contents
end
G.FUNCS.tranceMenu = function(e)
    local tabs = create_tabs({
        snap_to_nav = true,
        tabs = {
            {
                label = "Trance",
                chosen = true,
                tab_definition_function = function()
                    local palette_idx = 0
                    for i = 1, #Trance_palettes do
                        if Trance_palettes[i] == Trance_config.palette then
                            palette_idx = i
                            break
                        end
                    end
                    local font_idx = 0
                    for i = 1, #Trance_fonts do
                        if Trance_fonts[i] == Trance_config.font then
                            font_idx = i
                            break
                        end
                    end
                    return {
                        n = G.UIT.ROOT,
                        config = {
                            emboss = 0.05,
                            minh = 6,
                            r = 0.1,
                            minw = 10,
                            align = "cm",
                            padding = 0.2,
                            colour = G.C.BLACK
                        },
                        nodes = {
                            create_option_cycle({
                                label = "Selected Palette",
                                scale = 0.8,
                                w = 4,
                                options = Trance_palettes,
                                opt_callback = 'set_Trance_palette',
                                current_option = palette_idx,
                            }),
                            create_option_cycle({
                                label = "Selected Font",
                                scale = 0.8,
                                w = 4,
                                options = Trance_fonts,
                                opt_callback = 'set_Trance_font',
                                current_option = font_idx,
                            }),
                        },
                    }
                end
            },
        }})
    G.FUNCS.overlay_menu{
            definition = create_UIBox_generic_options({
                back_func = "options",
                contents = {tabs}
            }),
        config = {offset = {x=0,y=10}}
    }
end
require 'cartomancer.init'

Cartomancer.path = assert(
    Cartomancer.find_self('cartomancer.lua'),
    "Failed to find mod folder. Make sure that `Cartomancer` folder has `cartomancer.lua` file!"
)

Cartomancer.load_mod_file('internal/config.lua', 'internal.config')
Cartomancer.load_mod_file('internal/atlas.lua', 'internal.atlas')
Cartomancer.load_mod_file('internal/ui.lua', 'internal.ui')
Cartomancer.load_mod_file('internal/keybinds.lua', 'internal.keybinds')

Cartomancer.load_mod_file('core/view-deck.lua', 'core.view-deck')
Cartomancer.load_mod_file('core/flames.lua', 'core.flames')
Cartomancer.load_mod_file('core/optimizations.lua', 'core.optimizations')
Cartomancer.load_mod_file('core/jokers.lua', 'core.jokers')
Cartomancer.load_mod_file('core/hand.lua', 'core.hand')

Cartomancer.load_config()

Cartomancer.INTERNAL_jokers_menu = false

-- TODO dedicated keybinds file? keybinds need to load after config
Cartomancer.register_keybind {
    name = 'hide_joker',
    func = function (controller)
        Cartomancer.hide_hovered_joker(controller)
    end
}

Cartomancer.register_keybind {
    name = 'toggle_tags',
    func = function (controller)
        Cartomancer.SETTINGS.hide_tags = not Cartomancer.SETTINGS.hide_tags
        Cartomancer.update_tags_visibility()
    end
}

Cartomancer.register_keybind {
    name = 'toggle_consumables',
    func = function (controller)
        Cartomancer.SETTINGS.hide_consumables = not Cartomancer.SETTINGS.hide_consumables
    end
}

Cartomancer.register_keybind {
    name = 'toggle_deck',
    func = function (controller)
        Cartomancer.SETTINGS.hide_deck = not Cartomancer.SETTINGS.hide_deck
    end
}

Cartomancer.register_keybind {
    name = 'toggle_jokers',
    func = function (controller)
        if not (G and G.jokers) then
            return
        end
        G.jokers.cart_hide_all = not G.jokers.cart_hide_all

        if G.jokers.cart_hide_all then
            Cartomancer.hide_all_jokers()
        else
            Cartomancer.show_all_jokers()
        end
        Cartomancer.align_G_jokers()
    end
}

Cartomancer.register_keybind {
    name = 'toggle_jokers_buttons',
    func = function (controller)
        Cartomancer.SETTINGS.jokers_controls_buttons = not Cartomancer.SETTINGS.jokers_controls_buttons
    end
}

require 'blueprint.init'

Blueprint.load_mod_file('internal/config.lua', 'internal.config')

Blueprint.load_mod_file('core/settings.lua', 'core.settings')
Blueprint.load_mod_file('internal/assets.lua', 'internal.assets')

Blueprint.load_config()

Blueprint.load_mod_file('core/core.lua', 'core.main')

Blueprint.log "Finished loading core"
