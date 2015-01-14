local args = {...}
if #args ~= 1 then
	print("Usage: optipal.lua file")
	return
end

print("Hello! [optipal]")

os.execute("convert " .. args[1] .. " tmp/blarg.ppm")
os.execute("convert palette685.png tmp/palette685.ppm")
local pal685 = {}

print("Reading 685 palette")

local data
local file = io.open("tmp/palette685.ppm","rb")
data = file:read("*a"):sub(-720,-1)
file:close()
local a = data:gmatch(".")
for y = 1,240 do
	pal685[y] = { a():byte(), a():byte(), a():byte() }
end

print("Reading image")

local tile = {}
local data
local file = io.open("tmp/blarg.ppm","rb")
file:read("*l")
local w,h = file:read("*l"):match("(.-) (.+)")
w,h = tonumber(w),tonumber(h)
file:read("*l")
data = file:read("*a")
file:close()
local a = data:gmatch(".")
for y = 1,h do
	tile[y] = {}
	for x = 1,w do
		tile[y][x] = { a():byte(), a():byte(), a():byte() }
	end
end

local function getColorDistance(a, b)
	local ar = a[1]
	local ag = a[2]
	local ab = a[3]
	local br = b[1]
	local bg = b[2]
	local bb = b[3]
	return math.sqrt(0.2126*(ar-br)*(ar-br) + 0.7152*(ag-bg)*(ag-bg) + 0.0722*(ab-bb)*(ab-bb))
end

local function compare(blah)
	local score = math.huge
	for i = 1,240 do
		local fscore = getColorDistance(blah,pal685[i])
		if fscore < score then
			score = fscore
		end
	end
	if score < 12 then
		return { 255, 255, 255 }
	else
		return blah
	end
end

print("Comparing image")

for y = 1,h do
	for x = 1,w do
		tile[y][x] = compare(tile[y][x])
	end
end

print("Writing new image")

file = io.open("tmp/blarg.ppm","wb")
file:write("P6\n" .. w .. " " .. h .. "\n255\n")
local left = {}
for y = 1,h do
	for x = 1,w do
		if tile[y][x][1] ~= 255 or tile[y][x][2] ~= 255 or tile[y][x][3] ~= 255 then
			left[#left+1] = tile[y][x]
		end
		file:write(string.char(tile[y][x][1]))
		file:write(string.char(tile[y][x][2]))
		file:write(string.char(tile[y][x][3]))
	end
end
file:close()

local size = math.ceil(math.sqrt(#left))
local max = size*size

print("Writing palette [" .. size .. "x" .. size .. "]")

file = io.open("tmp/blargpal.ppm","wb")
file:write("P6\n" .. size .. " " .. size .. "\n255\n")
for j = 1,max do
	local tile = left[math.ceil(j/max*#left)]
	file:write(string.char(tile[1]))
	file:write(string.char(tile[2]))
	file:write(string.char(tile[3]))
end
file:close()

print("Goodbye [optipal]")
