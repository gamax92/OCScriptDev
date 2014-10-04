local args = {...}
if #args == 0 then
	print("FAIL")
	return
end
-- Convert image
os.execute("convert " .. args[1] .. " -resize 160x100! -colors 16 image.txt")
os.execute("convert image.txt image2.png")
os.execute("convert image.txt -filter point -resize 800x475! large.png")
-- Generate palette
palindex = 0
palette = {}
palrev = {}
img = {}
for line in io.lines("image.txt") do
	if line:sub(1,1) ~= "#" and line ~= "" then
		color = line:match("#(.-) ")
		posX,posY = line:match("(.-),(.-):")
		posX,posY = tonumber(posX) + 1, tonumber(posY) + 1
		if img[posY] == nil then img[posY] = {} end
		img[posY][posX] = color
		if palrev[color] == nil then
			palindex = palindex + 1
			palrev[color] = palindex
			palette[palindex] = color
		end
	end
end
print("Loaded " .. palindex .. " colors")
-- Write header
local newfile = io.open("ocimage.lua","wb")
newfile:write([[local computer = require("computer")
local z = computer.uptime()
local component = require("component")
local unicode = require("unicode")
local mid = unicode.char(0x2584)
local spc = " "
local a = component.gpu.setPaletteColor
local f = component.gpu.getPaletteColor
local b = component.gpu.setBackground
local c = component.gpu.setForeground
local d = component.gpu.fill
local e = component.gpu.set
local g = string.rep
]])
-- Set palette colors
for i = 1,palindex do
	newfile:write("if f(" .. i - 1 .. ") ~= 0x" .. palette[i] .. " then a(" .. i - 1 .. ", 0x" .. palette[i] .. ") end\n")
end
newfile:write("print(computer.uptime() - z)\n")
-- Gather palette usage stats
local stats = {}
for ti = 1,palindex do
	for bi = 1,palindex do
		local piececount = 0
		for y = 1,#img - 1, 2 do
			for x = 1,#img[1] do
				if palrev[img[y][x]] == ti and palrev[img[y+1][x]] == bi then
					piececount = piececount + 1
				end
			end
		end
		if piececount > 0 then
			stats[#stats + 1] = {ti,bi,piececount}
		end
	end
end
table.sort(stats,function(a,b) return a[3] > b[3] end)
local callsbg, callsfg, callsd = 1, 1, 1
-- Flood fill most used palette, kick off stack
print("Reducing " .. stats[1][3] - 1)
newfile:write('b(' .. stats[1][1] - 1 .. ',true)\n')
newfile:write('c(' .. stats[1][2] - 1 .. ',true)\n')
newfile:write('d(1,1,160,50,' .. ((stats[1][1] == stats[1][2]) and "spc" or "mid") .. ')\n')
local lastti, lastbi = stats[1][1], stats[1][2]
table.remove(stats,1)
-- Horiz and Vert check
local horiz = {}
local vertz = {}
local lineb = {}
for i = 1,#stats do
	local ti = stats[i][1]
	local bi = stats[i][2]
	local calls = 0
	for y = 1,#img - 1, 2 do
		local blockcount = 0
		for x = 1,#img[1] do
			if palrev[img[y][x]] == ti and palrev[img[y+1][x]] == bi then
				blockcount = blockcount + 1
			else
				if blockcount > 0 then
					local touse = (ti == bi) and "spc" or "mid"
					if blockcount > 1 then
						calls = calls + 2
					else
						calls = calls + 1
					end
				end
				blockcount = 0
			end
		end
		if blockcount > 0 then
			local touse = (ti == bi) and "spc" or "mid"
			if blockcount > 1 then
				calls = calls + 2
			else
				calls = calls + 1
			end
		end
	end
	horiz[i] = calls
end
for i = 1,#stats do
	local ti = stats[i][1]
	local bi = stats[i][2]
	local calls = 0
	for x = 1,#img[1] do
		local blockcount = 0
		for y = 1,#img - 1, 2 do
			if palrev[img[y][x]] == ti and palrev[img[y+1][x]] == bi then
				blockcount = blockcount + 1
			else
				if blockcount > 0 then
					local touse = (ti == bi) and "spc" or "mid"
					if blockcount > 1 then
						calls = calls + 2
					else
						calls = calls + 1
					end
				end
				blockcount = 0
			end
		end
		if blockcount > 0 then
			local touse = (ti == bi) and "spc" or "mid"
			if blockcount > 1 then
				calls = calls + 2
			else
				calls = calls + 1
			end
		end
	end
	vertz[i] = calls
end
for i = 1,#stats do
	local ti = stats[i][1]
	local bi = stats[i][2]
	local calls = 0
	local donttouch = {}
	for y = 1,#img - 1, 2 do
		donttouch[y] = {}
	end
	for y = 1,#img - 1, 2 do
		for x = 1,#img[1] do
			if palrev[img[y][x]] == ti and palrev[img[y+1][x]] == bi and donttouch[y][x] ~= true then
				local xlength = 0
				local ylength = 0
				for nx = x,#img[1] do
					if palrev[img[y][nx]] ~= ti or palrev[img[y+1][nx]] ~= bi then break end
					xlength = xlength + 1
				end
				for yx = y,#img - 1, 2 do
					if palrev[img[yx][x]] ~= ti or palrev[img[yx+1][x]] ~= bi then break end
					ylength = ylength + 1
				end
				local touse = (ti == bi) and "spc" or "mid"
				if xlength > ylength then
					if xlength > 1 then
						calls = calls + 2
					else
						calls = calls + 1
					end
					for brk = x,x+xlength-1 do
						donttouch[y][brk] = true
					end
				else
					if ylength > 1 then
						calls = calls + 2
					else
						calls = calls + 1
					end
					for brk = y,y+((ylength-1)*2),2 do
						donttouch[brk][x] = true
					end
				end
			end
		end
	end
	lineb[i] = calls
end
for i = 1,#stats do
	if vertz[i] < horiz[i] and vertz[i] < lineb[i] then
		print(i .. ": Vertz")
		print(i .. ": " .. horiz[i] .. " " .. vertz[i] .. " " .. lineb[i])
	elseif horiz[i] < vertz[i] and horiz[i] < lineb[i] then
		print(i .. ": Horiz")
		print(i .. ": " .. horiz[i] .. " " .. vertz[i] .. " " .. lineb[i])
	elseif lineb[i] < horiz[i] and lineb[i] < vertz[i] then
		print(i .. ": Lineb")
		print(i .. ": " .. horiz[i] .. " " .. vertz[i] .. " " .. lineb[i])
	else
		local tp = math.min(horiz[i],vertz[i],lineb[i])
		print(i .. ": " .. (tp == horiz[i] and "Horiz, " or "") .. (tp == vertz[i] and "Vertz, " or "") .. (tp == lineb[i] and "Lineb, " or ""))
		print(i .. ": " .. horiz[i] .. " " .. vertz[i] .. " " .. lineb[i])
	end
end
-- Go through stack
for i = 1,#stats do
	local ti = stats[i][1]
	local bi = stats[i][2]
	if lastti ~= ti then
		newfile:write('b(' .. ti - 1 .. ',true)\n')
		callsbg = callsbg + 1
		lastti = ti
	end
	if lastbi ~= bi and bi ~= ti then
		newfile:write('c(' .. bi - 1 .. ',true)\n')
		callsfg = callsfg + 1
		lastbi = bi
	end
	if horiz[i] < vertz[i] and horiz[i] < lineb[i] then
		for y = 1,#img - 1, 2 do
			local blockcount = 0
			local startx = 1
			for x = 1,#img[1] do
				if palrev[img[y][x]] == ti and palrev[img[y+1][x]] == bi then
					if blockcount == 0 then startx = x end
					blockcount = blockcount + 1
				else
					if blockcount > 0 then
						local touse = (ti == bi) and "spc" or "mid"
						if blockcount > 1 then
							newfile:write('d(' .. startx .. "," .. (y + 1) / 2 .. ',' .. blockcount .. ',1,' .. touse .. ')\n')
						else
							newfile:write('e(' .. startx .. "," .. (y + 1) / 2 .. ',' .. touse .. ')\n')
						end
						callsd = callsd + 1
					end
					blockcount = 0
				end
			end
			if blockcount > 0 then
				local touse = (ti == bi) and "spc" or "mid"
				if blockcount > 1 then
					newfile:write('d(' .. startx .. "," .. (y + 1) / 2 .. ',' .. blockcount .. ',1,' .. touse .. ')\n')
				else
					newfile:write('e(' .. startx .. "," .. (y + 1) / 2 .. ',' .. touse .. ')\n')
				end
				callsd = callsd + 1
			end
		end
	elseif vertz[i] < horiz[i] and vertz[i] < lineb[i] then
		for x = 1,#img[1] do
			local blockcount = 0
			local starty = 1
			for y = 1,#img - 1, 2 do
				if palrev[img[y][x]] == ti and palrev[img[y+1][x]] == bi then
					if blockcount == 0 then starty = (y + 1) / 2 end
					blockcount = blockcount + 1
				else
					if blockcount > 0 then
						local touse = (ti == bi) and "spc" or "mid"
						if blockcount > 1 then
							newfile:write('d(' .. x .. "," .. starty .. ',1,' .. blockcount .. ',' .. touse .. ')\n')
						else
							newfile:write('e(' .. x .. "," .. starty .. ',' .. touse .. ')\n')
						end
						callsd = callsd + 1
					end
					blockcount = 0
				end
			end
			if blockcount > 0 then
				local touse = (ti == bi) and "spc" or "mid"
				if blockcount > 1 then
					newfile:write('d(' .. x .. "," .. starty .. ',1,' .. blockcount .. ',' .. touse .. ')\n')
				else
					newfile:write('e(' .. x .. "," .. starty .. ',' .. touse .. ')\n')
				end
				callsd = callsd + 1
			end
		end
	else
		local donttouch = {}
		for y = 1,#img - 1, 2 do
			donttouch[y] = {}
		end
		for y = 1,#img - 1, 2 do
			for x = 1,#img[1] do
				if palrev[img[y][x]] == ti and palrev[img[y+1][x]] == bi and donttouch[y][x] ~= true then
					local xlength = 0
					local ylength = 0
					for nx = x,#img[1] do
						if palrev[img[y][nx]] ~= ti or palrev[img[y+1][nx]] ~= bi then break end
						xlength = xlength + 1
					end
					for yx = y,#img - 1, 2 do
						if palrev[img[yx][x]] ~= ti or palrev[img[yx+1][x]] ~= bi then break end
						ylength = ylength + 1
					end
					local touse = (ti == bi) and "spc" or "mid"
					if xlength > ylength then
						if xlength > 1 then
							newfile:write('d(' .. x .. "," .. (y + 1) / 2 .. ',' .. xlength .. ',1,' .. touse .. ')\n')
						else
							newfile:write('e(' .. x .. "," .. (y + 1) / 2 .. ',' .. touse .. ')\n')
						end
						callsd = callsd + 1
						for brk = x,x+xlength-1 do
							donttouch[y][brk] = true
						end
					else
						if ylength > 1 then
							newfile:write('d(' .. x .. "," .. (y + 1) / 2 .. ',1,' .. ylength .. ',' .. touse .. ')\n')
						else
							newfile:write('e(' .. x .. "," .. (y + 1) / 2 .. ',' .. touse .. ')\n')
						end
						callsd = callsd + 1
						for brk = y,y+((ylength-1)*2),2 do
							donttouch[brk][x] = true
						end
					end
				end
			end
		end
	end
end
newfile:write("b(0,true)\nprint(computer.uptime() - z)\n")
newfile:close()
print("Done")
print(callsbg,callsfg,callsd,callsbg+callsfg+callsd)
