local shell = require("shell")
local term = require("term")
local text = require("text")
local fs = require("filesystem")
local component = require("component")
local computer = require("computer")
local event = require("event")
local process = require("process")
local sides = require("sides")
local unicode = require("unicode")

local ccpal = {0xF0F0F0,0xF2B233,0xE57FD8,0x99B2F2,0xDEDE6C,0x7FCC19,0xF2B2CC,0x4C4C4C,0x999999,0x4C99B2,0xB266E5,0x253192,0x7F664C,0x57A64E,0xCC4C4C,0x000000}
local ocpal = {0xFFFFFF,0xFFCC33,0xCC66CC,0x6699FF,0xFFFF33,0x33CC33,0xFF6699,0x333333,0xCCCCCC,0x336699,0x9933CC,0x333399,0x663300,0x336600,0xFF3333,0x000000}
local oldpal = {}

local args, opt = shell.parse(...)
local apipath
local addShell, debugMode = true, false

local usageStr = [[Usage: ccemu (options) (program) (arguments)
 --help          What you see here
 --apipath=path  Load certain apis in folder
 --ccpal         Load CC's palette
 --noshell       Disable built in shell api
 --unicode       Experimentally support unicode
 --debug         Enable debugging]]

for k,v in pairs(opt) do
	if k == "help" then
		print(usageStr)
		return
	elseif k == "apipath" then
		if type(v) ~= "string" then
			error("Invalid parameter for " .. k,0)
		end
		apipath = shell.resolve(v)
	elseif k == "noshell" then
		addShell = false
	elseif k == "debug" then
		debugMode = true
	elseif k == "ccpal" or k == "unicode" then
	else
		error("Unknown option " .. k,0)
	end
end

local dPrint
if debugMode then
	dPrint = print
else
	dPrint = function() end
end

if #args < 1 then
	print(usageStr)
	return
end

args[1] = shell.resolve(args[1],"lua")

if args[1] == nil or not fs.exists(args[1]) or fs.isDirectory(args[1]) then
	error("Invalid program to launch",0)
end

if apipath ~= nil and not fs.isDirectory(apipath) then
	error("Invalid apipath",0)
end

if component.gpu.maxDepth() > 1 then
	dPrint("Setting up palette ...")
	component.gpu.setBackground(15,true)
	component.gpu.setForeground(0,true)
	local pal = opt.ccpal and ccpal or ocpal
	for i = 1,16 do
		oldpal[i] = component.gpu.getPaletteColor(i-1)
		if oldpal[i] ~= pal[i] then
			component.gpu.setPaletteColor(i-1, pal[i])
		end
	end
end

local comp = {
	label = nil,
	eventStack = {},
	timerC = 0,
	timerTrans = {},
}

local env, _wrap

local function tablecopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in pairs(orig) do
			copy[orig_key] = orig_value
		end
	else
		copy = orig
	end
	return copy
end

local function recurse_spec(results, path, spec)
	if spec:sub(1,1) == "/" then spec = spec:sub(2) end
	if spec:sub(-1,-1) == "/" then spec = spec:sub(1,-2) end
	local segment = spec:match('([^/]*)'):gsub('/', '')
	local pattern = '^' .. segment:gsub("[%.%[%]%(%)%%%+%-%?%^%$]","%%%1"):gsub("%z","%%z"):gsub("%*",".+") .. '$'

	if fs.isDirectory(path) then
		for file in fs.list(path) do
			file = file:gsub("/","")
			if file:match(pattern) then
				local f = _wrap.combine(path, file)

				if fs.isDirectory(f) then
					table.insert(results, f)
					recurse_spec(results, f, spec:sub(#segment + 2))
				elseif spec == segment then
					table.insert(results, f)
				end
			end
		end
	end
end

local envs = {}
_wrap = {
	-- TODO: Can getfenv and setfenv be recreated?
	getfenv = function(level)
		level = level or 1
		if type(level) ~= "function" and type(level) ~= "number" then
			error("bad argument (number expected, got " .. type(level) .. ")",2)
		end
		if type(level) == "number" and level < 0 then
			error("bad argument #1 (level must be non-negative)",2)
		end
		if type(level) == "function" then
			return envs[level] or env
		end
		return env
	end,
	setfenv = function(level,tbl)
		level = level or 1
		checkArg(2,tbl,"table")
		checkArg(1,level,"number","function")
		if type(level) == "number" and level < 0 then
			error("bad argument #1 (level must be non-negative)",2)
		end
		if type(level) == "function" and envs[level] ~= nil then
			envs[level] = tbl
			return level
		else
			error("'setfenv' cannot change environment of given object",2) -- Not a lie, :P
		end
	end,
	loadstring = function(str, source)
		source = source or "string"
		if type(str) ~= "string" and type(str) ~= "number" then error("bad argument #1 (string expected, got " .. type(str) .. ")",2) end
		if type(source) ~= "string" and type(source) ~= "number" then error("bad argument #2 (string expected, got " .. type(str) .. ")",2) end
		local source2 = tostring(source)
		local sSS = source2:sub(1,1)
		if sSS == "@" or sSS == "=" then
			source2 = source2:sub(2)
		end
		local f, err
		local customenv = setmetatable({},{
			__index = function(_,k) return f ~= nil and envs[f][k] or env[k] end,
			__newindex = function(_,k,v) if f ~= nil then envs[f][k] = v else env[k] = v end end,
		})
		f, err = load(str, "@" .. source2, nil, customenv)
		if f == nil then
			-- Get the normal error message
			local _, err = load(str, source, nil, customenv)
			return f, err
		end
		envs[f] = env
		return f, err
	end,
	setTextColor = function(color)
		checkArg(1,color,"number")
		component.gpu.setForeground(math.floor(math.log(color)/math.log(2)),true)
	end,
	setBackgroundColor = function(color)
		checkArg(1,color,"number")
		component.gpu.setBackground(math.floor(math.log(color)/math.log(2)),true)
	end,
	scroll = function(pos)
		checkArg(1,pos,"number")
		local sW,sH = component.gpu.getResolution()
		component.gpu.copy(1,1,sW,sH,0,-pos)
		if pos < 0 then
			component.gpu.fill(1,1,sW,-pos," ")
		else
			component.gpu.fill(1,sH-pos+1,sW,pos," ")
		end
	end,
	getDir = function(path)
		checkArg(1,path,"string")
		return _wrap._combine(path,"..",true)
	end,
	find = function(spec)
		checkArg(1,spec,"string")
		local results = {}
		recurse_spec(results, '', spec)
		return results
	end,
	open = function(path,mode)
		checkArg(1,path,"string")
		checkArg(2,mode,"string")
		if mode == "r" then
			local _file = io.open(path,"rb")
			if _file == nil then return end
			local file = {
				close = function() return _file:close() end,
				readLine = function() return _file:read("*l") end,
				readAll = function() return _file:read("*a") end,
			}
			return file
		elseif mode == "rb" then
			local _file = io.open(path,"rb")
			if _file == nil then return end
			local file = {
				close = function() return _file:close() end,
				read = function() local chr = _file:read(1) if chr ~= nil then chr = chr:byte() end return chr end,
			}
			return file
		elseif mode == "w" or mode == "a" then
			local _file = io.open(path,mode .. "b")
			if _file == nil then return end
			local file = {
				close = function() return _file:close() end,
				writeLine = function(data) return _file:write(data .. "\n") end,
				write = function(data) return _file:write(data) end,
				flush = function() return _file:flush() end
			}
			return file
		elseif mode == "wb" or mode == "ab" then
			local _file = io.open(path,mode)
			if _file == nil then return end
			local file = {
				close = function() return _file:close() end,
				write = function(data) return _file:write(string.char(data)) end,
				flush = function() return _file:flush() end
			}
			return file
		else
			error("Unsupported mode",2)
		end
	end,
	list = function(path)
		checkArg(1,path,"string")
		local toret = {}
		for entry in fs.list(path) do
			toret[#toret + 1] = entry
		end
		return toret
	end,
	getDrive = function(path)
		checkArg(1,path,"string")
		if fs.exists(path) then
			return "hdd"
		end
	end,
	getFreeSpace = function(path)
		checkArg(1,path,"string")
		path = fs.canonical(path)
		local bp,bm = nil,""
		for proxy,mount in fs.mounts() do
			if (path:sub(1,#mount) == mount or path .. "/" == mount) and #mount > #bm then
				bp, bm = proxy, mount
			end
		end
		return bp.spaceTotal() - bp.spaceUsed()
	end,
	move = function()
	end,
	makeDir = function(path)
		checkArg(1,path,"string")
		if fs.exists(path) then
			if not fs.isDirectory(path) then
				error("file with that name already exists",2)
			end
		else
			local ret,err = fs.makeDirectory(path)
			if not ret then
				error(err,2)
			end
		end
	end,
	_combine = function(basePath, localPath, dummy)
		local path = ("/" .. basePath .. "/" .. localPath):gsub("\\", "/")

		local tPath = {}
		for part in path:gmatch("[^/]+") do
	   		if part ~= "" and part ~= "." then
	   			if part == ".." and #tPath > 0 and (dummy or tPath[1] ~= "..") then
	   				table.remove(tPath)
	   			else
	   				table.insert(tPath, part:sub(1,255))
	   			end
	   		end
		end
		return table.concat(tPath, "/")
	end,
	combine = function(basePath, localPath)
		checkArg(1,basePath,"string")
		checkArg(2,localPath,"string")
		return _wrap._combine(basePath, localPath)
	end,
	getComputerID = function()
		return tonumber(computer.address():sub(1,4),16)
	end,
	setComputerLabel = function(label)
		checkArg(1,label,"string")
		comp.label = label
	end,
	queueEvent = function(event, ...)
		checkArg(1,event,"string")
		table.insert(comp.eventStack,{event, ...})
	end,
	startTimer = function(timeout)
		checkArg(1,timeout,"number")
		local timerRet = comp.timerC
		comp.timerC = comp.timerC + 1
		local timer = event.timer(timeout, function()
			comp.timerTrans[timerRet] = nil
			table.insert(comp.eventStack,{"timer", timerRet})
		end)
		comp.timerTrans[timerRet] = timer
		return timerRet
	end,
	setAlarm = function()
		-- TODO: Alarm
	end,
	cancelTimer = function(id)
		checkArg(1,id,"number")
		event.cancel(comp.timerTrans[id])
		comp.timerTrans[id] = nil
	end,
	cancelAlarm = function()
		-- TODO: Alarm
	end,
	time = function()
		local ost = os.date()
		return ost.hour + ((ost.min * 60 + ost.sec)/3600)
	end,
	day = function()
		local ost = os.date()
		return ((ost.year - 1970) * 365) + (ost.month * 30) + ost.day
	end
}

env = {
	_VERSION = "Luaj-jse 2.0.3",
	tostring = tostring,
	tonumber = tonumber,
	unpack = table.unpack,
	getfenv = _wrap.getfenv,
	setfenv = _wrap.setfenv,
	rawequal = rawequal,
	rawset = rawset,
	rawget = rawget,
	setmetatable = setmetatable,
	getmetatable = getmetatable,
	next = next,
	type = type,
	select = select,
	assert = assert,
	error = error,
	ipairs = ipairs,
	pairs = pairs,
	pcall = pcall,
	xpcall = xpcall,
	loadstring = _wrap.loadstring,
	_realload = load,
	math = math,
	string = string,
	table = table,
	coroutine = coroutine,
	term = {
		clear = function() local x,y = term.getCursor() term.clear() term.setCursor(x,y) end,
		clearLine = function() local x,y = term.getCursor() term.clearLine() term.setCursor(x,y) end,
		getSize = function() return component.gpu.getResolution() end,
		getCursorPos = term.getCursor,
		setCursorPos = term.setCursor,
		setTextColor = _wrap.setTextColor,
		setTextColour = _wrap.setTextColor,
		setBackgroundColor = _wrap.setBackgroundColor,
		setBackgroundColour = _wrap.setBackgroundColor,
		setCursorBlink = term.setCursorBlink,
		scroll = _wrap.scroll,
		write = term.write,
		isColor = function() return component.gpu.maxDepth() > 1 end,
		isColour = function() return component.gpu.maxDepth() > 1 end,
	},
	fs = {
		getDir = _wrap.getDir,
		find = _wrap.find,
		open = _wrap.open,
		list = _wrap.list,
		exists = fs.exists,
		isDir = fs.isDirectory,
		isReadOnly = function() return false end,
		getName = function(path) local name = fs.name(path) return name == "" and "root" or name end,
		getDrive = _wrap.getDrive,
		getSize = function(path) if not fs.exists(path) then error("file not found",2) end return fs.size(path) end,
		getFreeSpace = _wrap.getFreeSpace,
		makeDir = _wrap.makeDir,
		move = _wrap.move,
		copy = fs.copy,
		delete = fs.remove,
		combine = _wrap.combine,
	},
	os = {
		clock = computer.uptime,
		getComputerID = _wrap.getComputerID,
		computerID = _wrap.getComputerID,
		setComputerLabel = _wrap.setComputerLabel,
		getComputerLabel = function() return comp.label end,
		computerLabel = function() return comp.label end,
		queueEvent = _wrap.queueEvent,
		startTimer = _wrap.startTimer,
		setAlarm = _wrap.setAlarm,
		cancelTimer = _wrap.cancelTimer,
		cancelAlarm = _wrap.cancelAlarm,
		time = _wrap.time,
		day = _wrap.day,
		shutdown = function() computer.shutdown(false) end,
		reboot = function() computer.shutdown(true) end,
	},
	-- TODO: Peripherals
	peripheral = {
		isPresent = function() end,
		getType = function() end,
		getMethods = function() end,
		call = function() end,
	},
	bit = {
		blshift = bit32.lshift,
		brshift = bit32.arshift,
		blogic_rshift = bit32.rshift,
		bxor = bit32.bxor,
		bor = bit32.bor,
		band = bit32.band,
		bnot = bit32.bnot,
	}
}

env._G = env
if opt.unicode then
	env.string = tablecopy(string)
	env.string.reverse = unicode.reverse
	env.string.char = unicode.char
	env.string.sub = unicode.sub
	env.string.len = unicode.len
	env.string.lower = unicode.lower
	env.string.upper = unicode.upper
end

if component.isAvailable("internet") and component.internet.isHttpEnabled() then
	-- TODO: Can this be written so http.request doesn't hog the execution?
	--env.http = {
	--}
end
if component.isAvailable("redstone") then
	env.redstone = {
		getSides = function() return {"top","bottom","left","right","front","back"} end,
		getInput = function(side) return component.redstone.getInput(sides[side]) ~= 0 end,
		getOutput = function(side) return component.redstone.getOutput(sides[side]) ~= 0 end,
		setOutput = function(side, val) return component.redstone.setOutput(sides[side],val and 15 or 0) end,
		getAnalogInput = function(side) return component.redstone.getInput(sides[side]) end,
		getAnalogOutput = function(side) return component.redstone.getOutput(sides[side]) end,
		setAnalogOutput = function(side, val) return component.redstone.setOutput(sides[side],val) end,
		getBundledInput = function(side)
			side = sides[side]
			local val
			for i = 0,15 do
				if component.redstone.getBundledInput(side,i) > 0 then
					val = val + (2^i)
				end
			end
			return val
		end,
		getBundledOutput = function(side)
			side = sides[side]
			local val
			for i = 0,15 do
				if component.redstone.getBundledOutput(side,i) > 0 then
					val = val + (2^i)
				end
			end
			return val
		end,
		setBundledOutput = function(side, val) end,
		testBundledInput = function() end,
	}
	env.redstone.getAnalogueInput = env.redstone.getAnalogInput
	env.redstone.getAnalogueOutput = env.redstone.getAnalogOutput
	env.redstone.setAnalogueOutput = env.redstone.setAnalogOutput
	env.rs = env.redstone
else
	dPrint("Using fake redstone api")
	local outputs = {top=0, bottom=0, left=0, right=0, front=0, back=0}
	local bundled = {top=0, bottom=0, left=0, right=0, front=0, back=0}
	env.redstone = {
		getSides = function() return {"top","bottom","left","right","front","back"} end,
		getInput = function(side)
			checkArg(1,side,"string")
			if outputs[side] == nil then error("bad argument #1 (invalid side)",2) end
			return false
		end,
		getOutput = function(side)
			checkArg(1,side,"string")
			if outputs[side] == nil then error("bad argument #1 (invalid side)",2) end
			return outputs[side] > 0
		end,
		setOutput = function(side,val)
			checkArg(1,side,"string")
			checkArg(2,val,"boolean")
			if outputs[side] == nil then error("bad argument #1 (invalid side)",2) end
			outputs[side] = val and 15 or 0
		end,
		getAnalogInput = function(side)
			checkArg(1,side,"string")
			if outputs[side] == nil then error("bad argument #1 (invalid side)",2) end
			return 0
		end,
		getAnalogOutput = function(side)
			checkArg(1,side,"string")
			if outputs[side] == nil then error("bad argument #1 (invalid side)",2) end
			return outputs[side]
		end,
		setAnalogOutput = function(side,val)
			checkArg(1,side,"string")
			checkArg(2,val,"number")
			if outputs[side] == nil then error("bad argument #1 (invalid side)",2) end
			if val < 0 or val >= 16 then error("bad argument #2 (number out of range)",2) end
			outputs[side] = math.floor(val)
		end,
		getBundledInput = function(side)
			checkArg(1,side,"string")
			if bundled[side] == nil then error("bad argument #1 (invalid side)",2) end
			return 0
		end,
		getBundledOutput = function(side)
			checkArg(1,side,"string")
			if bundled[side] == nil then error("bad argument #1 (invalid side)",2) end
			return bundled[side]
		end,
		setBundledOutput = function(side,val)
			checkArg(1,side,"string")
			checkArg(2,val,"number")
			if bundled[side] == nil then error("bad argument #1 (invalid side)",2) end
			bundled[side] = math.max(math.min(math.floor(val),2^31),0)
		end,
		testBundledInput = function(side,val)
			checkArg(1,side,"string")
			checkArg(2,val,"number")
			if bundled[side] == nil then error("bad argument #1 (invalid side)",2) end
			return val == 0
		end,
	}
end
env.redstone.getAnalogueInput = env.redstone.getAnalogInput
env.redstone.getAnalogueOutput = env.redstone.getAnalogOutput
env.redstone.setAnalogueOutput = env.redstone.setAnalogOutput
env.rs = env.redstone

-- Bios entries:
local eventTrans = {
	key = "key_down",
}

function env.os.version()
    return "CCEmu 1.0"
end
local oldinterrupt = event.shouldInterrupt
local newinterrupt = function() return false end
event.shouldInterrupt = newinterrupt
local function getEvent(filter)
	if #comp.eventStack > 0 then
		if filter ~= nil then
			for i = 1,#comp.eventStack do
				if comp.eventStack[i][1] == filter then
					local e = comp.eventStack[i]
					table.remove(comp.eventStack,i)
					return table.unpack(e)
				end
			end
		else
			local e = comp.eventStack[1]
			table.remove(comp.eventStack,1)
			return table.unpack(e)
		end
	end
	filter = eventTrans[filter] or filter
	event.shouldInterrupt = oldinterrupt
	local e = { pcall(event.pull,filter) }
	event.shouldInterrupt = newinterrupt
	if e[1] == false and e[2] == "interrupted" then
	    return "terminate"
	end
	table.remove(e,1)
	if e[1] == "key_down" then
		if e[3] >= 32 and e[3] <= 126 then
			table.insert(comp.eventStack,{"char", string.char(e[3])})
		end
		return "key", e[4]
	elseif e[1] == "touch" then
		return "mouse_click", e[5] + 1, e[3], e[4]
	elseif e[1] == "drag" then
		return "mouse_drag", e[5] + 1, e[3], e[4]
	elseif e[1] == "scroll" then
		return "mouse_scroll", e[5], e[3], e[4]
	end
end
function env.os.pullEventRaw(filter)
	while true do
		local e = { getEvent() }
		if e[1] ~= nil then return table.unpack(e) end
	end
end
function env.os.pullEvent(filter)
	while true do
		local e = { getEvent() }
		if e[1] == "terminate" then
		    error("Terminated", 0)
		end
		if e[1] ~= nil then return table.unpack(e) end
	end
end
env.sleep = os.sleep
env.write = function(data)
	local count = 0
	local otw = text.wrap
	function text.wrap(...)
		local a,b,c = otw(...)
		if c then count = count + 1 end
		return a,b,c
	end
	term.write(data,true)
	text.wrap = otw
	return count
end
env.print = function(...)
	local args = {...}
    for i = 1,#args do
        args[i] = tostring(args[i])
    end
    return env.write(table.concat(args,"\t") .. "\n")
end
env.printError = function(...) io.stderr:write(table.concat({...},"\t") .. "\n") end
env.read = function(pwchar, hist)
	local line = term.read(tablecopy(hist),nil,nil,pwchar)
	if line == nil then
		return ""
	end
	return line:gsub("\n","")
end
env.loadfile = loadfile
env.dofile = dofile
env.os.run = function(newenv, name, ...)
    local args = {...}
	setmetatable(newenv, {__index=env})
    local fn, err = loadfile(name, nil, newenv)
    if fn then
        local ok, err = pcall(function() fn(table.unpack(args)) end)
        if not ok then
            if err and err ~= "" then
                env.printError(err)
            end
            return false
        end
        return true
    end
    if err and err ~= "" then
        env.printError(err)
    end
    return false
end

local tAPIsLoading = {}
env.os.loadAPI = function(path)
    local sName = fs.name(path)
    if tAPIsLoading[sName] == true then
        env.printError("API " .. sName .. " is already being loaded")
        return false
    end
    tAPIsLoading[sName] = true

	local env2
	env2 = {
		getfenv = function() return env2 end
	}
    setmetatable(env2, {__index = env})
    local fn, err = loadfile(path, nil, env2)
    if fn then
        fn()
    else
        env.printError(err)
        tAPIsLoading[sName] = nil
        return false
    end

	local tmpcopy = {}
    for k,v in pairs(env2) do
        tmpcopy[k] =  v
    end
    
    env[sName] = tmpcopy
    tAPIsLoading[sName] = nil
    return true
end
env.os.unloadAPI = function(name)
    if _name ~= "_G" and type(env[name]) == "table" then
        env[name] = nil
    end
end
env.os.sleep = os.sleep
if env.http ~= nil then
	-- TODO: http.get
	-- TODO: http.post
end

if apipath ~= nil then
	for file in fs.list(apipath) do
		local path = apipath .. "/" .. file
		if not fs.isDirectory(path) and file ~= "colours" then
			dPrint("Loading " .. file)
			local stat,err = pcall(env.os.loadAPI,path)
			if stat == false then
				env.printError(err)
			end
		else
			dPrint("Ignoring " .. file)
		end
	end
end

if env.colors ~= nil then
	dPrint("Adding colours from colors")
	env.colours = {}
	for k,v in pairs(env.colors) do
		if k == "gray" then k = "grey" end
		if k == "lightGray" then k = "lightGrey" end
		env.colours[k] = v
	end
end

-- Shell api
if addShell then
	env.shell = {
		dir = shell.getWorkingDirectory,
		setDir = shell.setWorkingDirectory,
		path = shell.getPath,
		setPath = shell.setPath,
		resolve = shell.resolve,
		resolveProgram = function(path) return shell.resolve(path,"lua") end,
		aliases = function()
			local toret = {}
			for k,v in shell.aliases() do
				toret[k] = v
			end
			return toret
		end,
		setAlias = shell.setAlias,
		clearAlias = function(alias) shell.setAlias(alias,nil) end,
		programs = function(hidden)
			local firstlist = {}
			for part in string.gmatch(shell.getPath(), "[^:]+") do
				part = shell.resolve(part)
				if fs.isDirectory(part) then
					for entry in fs.list(part) do
						if not fs.isDirectory(env.fs.combine(part, entry)) and (hidden or string.sub(entry, 1, 1) ~= ".") then
							firstlist[entry] = true
						end
					end
				end
			end
			local list = {}
			for entry, _ in pairs(firstlist) do
				table.insert(list, entry)
			end
			table.sort(list)
			return list
		end,
		getRunningProgram = function() return process.running():sub(2) end,
		run = function(command, ...) return shell.execute(command, nil, ...) end,
		openTab = function() end,
		switchTab = function() end,
	}
end

if debugMode then
	io.stdout:write("Loading program ... ")
end

local fn,err = loadfile(args[1], nil, env)
if not fn then
	dPrint("Fail")
	error("Failed to load: " .. err, 0)
end
dPrint("Done")
local retval = {xpcall(function() return fn(table.unpack(args,2)) end, debug.traceback)}
event.shouldInterrupt = oldinterrupt
component.gpu.setBackground(0x000000)
component.gpu.setForeground(0xFFFFFF)
if retval[1] == false then
	io.stderr:write(retval[2] .. "\n")
else
	return table.unpack(retval,2)
end
if component.gpu.maxDepth() > 1 then
	dPrint("Restoring palette ...")
	for i = 1,16 do
		component.gpu.setPaletteColor(i-1, oldpal[i])
	end
end
