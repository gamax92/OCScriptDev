local args = {...}
if #args == 0 then
	print("FAIL")
	return
end
-- Convert image
os.execute("convert " .. args[1] .. " -resize 160x50! -colors 16 -filter point -resize 160x100! image.txt")
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
-- Flood fill most used palette, kick off stack
newfile:write('b(' .. stats[1][1] - 1 .. ',true)\n')
newfile:write('c(' .. stats[1][2] - 1 .. ',true)\n')
newfile:write('d(1,1,160,50,' .. ((stats[1][1] == stats[1][2]) and "spc" or "mid") .. ')\n')
local lastti, lastbi = stats[1][1], stats[1][2]
table.remove(stats,1)
-- Go through stack
for i = 1,#stats do
	local ti = stats[i][1]
	local bi = stats[i][2]
	if lastti ~= ti then
		newfile:write('b(' .. ti - 1 .. ',true)\n')
		lastti = ti
	end
	if lastbi ~= bi then
		newfile:write('c(' .. bi - 1 .. ',true)\n')
		lastbi = bi
	end
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
					for brk = x,x+xlength-1 do
						donttouch[y][brk] = true
					end
				else
					if ylength > 1 then
						newfile:write('d(' .. x .. "," .. (y + 1) / 2 .. ',1,' .. ylength .. ',' .. touse .. ')\n')
					else
						newfile:write('e(' .. x .. "," .. (y + 1) / 2 .. ',' .. touse .. ')\n')
					end
					for brk = y,y+((ylength-1)*2),2 do
						donttouch[brk][x] = true
					end
				end
			end
		end
	end
end
newfile:write("b(0,true)\nprint(computer.uptime() - z)\n")
newfile:close()
print("Done")
