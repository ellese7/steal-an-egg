-- Delta: trova la funzione di movimento dei pet e alza Upgrades["Pet Walkspeed"].
-- getconnections, getgc, debug.getupvalue, debug.setupvalue.
-- v113 non viene sostituito. Si fissa la tabella Upgrades che la funzione legge.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local env = _G
pcall(function()
	if typeof(getgenv) == "function" then
		env = getgenv()
	end
end)
if typeof(env.__DeltaPetSpeed) == "table" and typeof(env.__DeltaPetSpeed.stop) == "function" then
	pcall(env.__DeltaPetSpeed.stop)
end

local alive = true
local scanning = false
local logs = {}
local logBox
local targets = {}
local holdConn
local holding = false
local gui

local function api(name)
	if typeof(debug) == "table" and typeof(debug[name]) == "function" then
		return debug[name]
	end
	local spots = { _G }
	pcall(function()
		if typeof(getgenv) == "function" then
			spots[#spots + 1] = getgenv()
		end
	end)
	for i = 1, #spots do
		local ok, fn = pcall(function()
			return spots[i][name]
		end)
		if ok and typeof(fn) == "function" then
			return fn
		end
	end
	return nil
end

local getconnections = api("getconnections")
local getscriptclosure = api("getscriptclosure")
local getgc = api("getgc")
local getupvalue = api("getupvalue")
local setupvalue = api("setupvalue")
local getconstants = api("getconstants")
local getproto = api("getproto")
local getprotos = api("getprotos")
local setclip = api("setclipboard") or api("toclipboard") or api("setrbxclipboard")

local function cut(text, n)
	text = tostring(text or "")
	if #text > n then
		return string.sub(text, 1, n)
	end
	return text
end

local function pushLog(line)
	logs[#logs + 1] = line
	if #logs > 400 then
		table.remove(logs, 1)
	end
	print(line)
	if logBox then
		local from = math.max(1, #logs - 40)
		local shown = {}
		for i = from, #logs do
			shown[#shown + 1] = logs[i]
		end
		logBox.Text = table.concat(shown, "\n")
	end
end

local function log(msg)
	pushLog(string.format("[%s] %s", os.date("%H:%M:%S"), msg))
end

local function sourceOf(fn)
	if typeof(fn) ~= "function" then
		return ""
	end
	if typeof(debug) == "table" and typeof(debug.getinfo) == "function" then
		local ok, info = pcall(debug.getinfo, fn)
		if ok and typeof(info) == "table" then
			return tostring(info.source or info.short_src or "")
		end
	end
	if typeof(debug) == "table" and typeof(debug.info) == "function" then
		local ok, src = pcall(debug.info, fn, "s")
		if ok and typeof(src) == "string" then
			return src
		end
	end
	return ""
end

local function isFake(fn)
	local src = string.lower(sourceOf(fn))
	return string.find(src, "locales", 1, true) ~= nil or string.find(src, "coregui", 1, true) ~= nil
end

local function hasConst(fn, needle)
	if typeof(getconstants) ~= "function" or typeof(fn) ~= "function" then
		return false
	end
	local ok, list = pcall(getconstants, fn)
	if not ok or typeof(list) ~= "table" then
		return false
	end
	for _, c in pairs(list) do
		if c == needle then
			return true
		end
	end
	return false
end

local function childProtos(fn)
	local list = {}
	if typeof(getprotos) == "function" then
		local ok, bag = pcall(getprotos, fn)
		if ok and typeof(bag) == "table" then
			for _, p in pairs(bag) do
				if typeof(p) == "function" then
					list[#list + 1] = p
					if #list >= 40 then
						return list
					end
				end
			end
			if #list > 0 then
				return list
			end
		end
	end
	if typeof(getproto) ~= "function" then
		return list
	end
	local misses = 0
	for i = 1, 40 do
		local ok, p = pcall(getproto, fn, i, true)
		if not ok or typeof(p) ~= "function" then
			ok, p = pcall(getproto, fn, i)
		end
		if ok and typeof(p) == "function" then
			list[#list + 1] = p
			misses = 0
		else
			misses = misses + 1
			if misses >= 2 then
				break
			end
		end
	end
	return list
end

local function upvalueAt(fn, index)
	if typeof(getupvalue) ~= "function" then
		return nil, nil, false
	end
	local ok, a, b = pcall(getupvalue, fn, index)
	if not ok or (a == nil and b == nil) then
		return nil, nil, false
	end
	if typeof(a) == "string" then
		return a, b, true
	end
	return "#" .. tostring(index), a, true
end

local function upvalueCount(fn)
	local n = 0
	for i = 1, 80 do
		local _, _, alive = upvalueAt(fn, i)
		if not alive then
			break
		end
		n = i
	end
	return n
end

local function readField(tbl, key)
	if typeof(tbl) ~= "table" then
		return nil
	end
	local raw = rawget(tbl, key)
	if raw ~= nil then
		return raw
	end
	local ok, val = pcall(function()
		return tbl[key]
	end)
	if ok then
		return val
	end
	return nil
end

local function describe(value)
	if typeof(value) ~= "table" then
		return nil
	end
	local direct = readField(value, "Pet Walkspeed")
	if typeof(direct) == "number" then
		return "direct", value, direct
	end
	local up = readField(value, "Upgrades")
	if typeof(up) == "table" then
		local level = readField(up, "Pet Walkspeed")
		if typeof(level) == "number" then
			return "parent", value, level, up
		end
	end
	return nil
end

local PETS_SRC = "PlayerScripts.Scripts.Game.Pets"
local announced = false

local function isPetsSource(fn)
	return string.find(sourceOf(fn), PETS_SRC, 1, true) ~= nil
end

local function remember(fn, index, kind, parent, realUpgrades, before)
	for i = 1, #targets do
		if targets[i].originalUpgrades == realUpgrades then
			return false
		end
	end
	if not announced then
		announced = true
		log("[FUNC] Trovata funzione: " .. cut(sourceOf(fn), 180))
	end
	targets[#targets + 1] = {
		fn = fn,
		index = index,
		kind = kind,
		parent = parent,
		originalUpgrades = realUpgrades,
		realUpgrades = realUpgrades,
		before = before,
		mode = "none",
	}
	log("[UPVALUE] Pet Walkspeed = " .. tostring(before))
	return true
end

local function harvest(fn, seen, depth)
	if typeof(fn) ~= "function" or seen[fn] or depth > 6 or isFake(fn) then
		return false
	end
	seen[fn] = true
	for i = 1, 80 do
		local _, val, alive = upvalueAt(fn, i)
		if not alive then
			break
		end
		local kind, parent, level, up = describe(val)
		if kind == "parent" and remember(fn, i, "parent", parent, up, level) then
			return true
		end
		if kind == "direct" and remember(fn, i, "direct", nil, parent, level) then
			return true
		end
		if typeof(val) == "function" and harvest(val, seen, depth + 1) then
			return true
		end
	end
	local kids = childProtos(fn)
	for i = 1, #kids do
		if harvest(kids[i], seen, depth + 1) then
			return true
		end
	end
	return false
end

local function findPets(fn, seen, depth)
	if typeof(fn) ~= "function" or seen[fn] or depth > 4 or isFake(fn) then
		return nil
	end
	seen[fn] = true
	if isPetsSource(fn) then
		return fn
	end
	for i = 1, 40 do
		local _, val, alive = upvalueAt(fn, i)
		if not alive then
			break
		end
		if typeof(val) == "function" then
			local hit = findPets(val, seen, depth + 1)
			if hit then
				return hit
			end
		end
	end
	return nil
end

local function connFunction(conn)
	if typeof(conn) == "function" then
		return conn
	end
	if typeof(conn) ~= "table" then
		return nil
	end
	if typeof(conn.Function) == "function" then
		return conn.Function
	end
	if typeof(conn.func) == "function" then
		return conn.func
	end
	return nil
end

local function petsInstance()
	local ps = LocalPlayer:FindFirstChild("PlayerScripts")
	local folder = ps and ps:FindFirstChild("Scripts")
	folder = folder and folder:FindFirstChild("Game")
	return folder and folder:FindFirstChild("Pets")
end

local function copyMap(tbl)
	local out = {}
	if typeof(tbl) ~= "table" then
		return out
	end
	pcall(function()
		for k, v in pairs(tbl) do
			out[k] = v
		end
	end)
	return out
end

local restore

local function search()
	if #targets > 0 then
		restore()
	end
	targets = {}
	announced = false
	local seen = {}
	if typeof(getconnections) ~= "function" then
		log("[ERR] getconnections assente")
	else
		local ok, list = pcall(getconnections, RunService.Heartbeat)
		if not ok or typeof(list) ~= "table" then
			log("[ERR] getconnections Heartbeat " .. tostring(list))
		else
			for _, conn in pairs(list) do
				local fn = connFunction(conn)
				if fn and not isFake(fn) then
					local hit = fn
					if not isPetsSource(fn) then
						hit = findPets(fn, {}, 0)
					end
					if hit and harvest(hit, seen, 0) then
						return
					end
				end
			end
		end
	end
	local pets = petsInstance()
	if pets and typeof(getscriptclosure) == "function" then
		local ok, fn = pcall(getscriptclosure, pets)
		if ok and typeof(fn) == "function" and harvest(fn, seen, 0) then
			return
		end
	end
	if typeof(getgc) ~= "function" then
		log("[UPVALUE] nessuno")
		return
	end
	local okGc, bag = pcall(getgc, true)
	if not okGc or typeof(bag) ~= "table" then
		log("[ERR] getgc " .. tostring(bag))
		log("[UPVALUE] nessuno")
		return
	end
	local n = 0
	for _, obj in pairs(bag) do
		n = n + 1
		if typeof(obj) == "function" and not seen[obj] and isPetsSource(obj) and harvest(obj, seen, 0) then
			return
		end
		if n % 250 == 0 then
			task.wait()
		end
	end
	log("[UPVALUE] nessuno")
end

restore = function()
	for i = 1, #targets do
		local item = targets[i]
		if item.mode == "setup" and item.backup ~= nil and typeof(setupvalue) == "function" then
			pcall(setupvalue, item.fn, item.index, item.backup)
		end
		if typeof(item.originalUpgrades) == "table" then
			pcall(function()
				item.originalUpgrades["Pet Walkspeed"] = item.before
			end)
		end
		item.mode = "none"
	end
end

local function applyBoost()
	if not alive then
		return
	end
	if #targets == 0 then
		search()
	end
	if #targets == 0 then
		log("[BOOST] Errore: v113.Upgrades non trovato")
		return
	end
	local item = targets[1]
	local up = item.originalUpgrades
	local before = readField(up, "Pet Walkspeed")
	local wrote = pcall(function()
		up["Pet Walkspeed"] = 10000
	end)
	local after = readField(up, "Pet Walkspeed")
	if wrote and after == 10000 then
		item.mode = "direct"
		log(string.format("[BOOST] Pet Walkspeed %s -> 10000", tostring(before)))
		return
	end
	if typeof(setupvalue) ~= "function" then
		log("[BOOST] Errore: letto " .. tostring(after))
		return
	end
	local installed
	local err
	if item.kind == "parent" and typeof(item.parent) == "table" then
		local parentCopy = copyMap(item.parent)
		local upCopy = copyMap(up)
		upCopy["Pet Walkspeed"] = 10000
		parentCopy.Upgrades = upCopy
		local ok
		ok, err = pcall(setupvalue, item.fn, item.index, parentCopy)
		local _, now = upvalueAt(item.fn, item.index)
		local nowUp = typeof(now) == "table" and readField(now, "Upgrades")
		local nowLevel = typeof(nowUp) == "table" and readField(nowUp, "Pet Walkspeed")
		if ok and nowLevel == 10000 then
			item.mode = "setup"
			item.backup = item.parent
			item.realUpgrades = upCopy
			installed = true
		end
	else
		local upCopy = copyMap(up)
		upCopy["Pet Walkspeed"] = 10000
		local ok
		ok, err = pcall(setupvalue, item.fn, item.index, upCopy)
		local _, now = upvalueAt(item.fn, item.index)
		local nowLevel = typeof(now) == "table" and readField(now, "Pet Walkspeed")
		if ok and nowLevel == 10000 then
			item.mode = "setup"
			item.backup = up
			item.realUpgrades = upCopy
			installed = true
		end
	end
	if installed then
		log(string.format("[BOOST] Pet Walkspeed %s -> 10000", tostring(before)))
		return
	end
	log("[BOOST] Errore: " .. tostring(err or after))
end

local function shutdown()
	alive = false
	restore()
	pcall(function()
		gui:Destroy()
	end)
end

local pg = LocalPlayer:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("DeltaPetSpeed")
if old then
	pcall(function()
		old:Destroy()
	end)
end

gui = Instance.new("ScreenGui")
gui.Name = "DeltaPetSpeed"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(520, 280)
frame.Position = UDim2.fromOffset(12, 12)
frame.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
frame.BackgroundTransparency = 0.08
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local function button(text, x, w, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, 28)
	b.Position = UDim2.fromOffset(x, 8)
	b.BackgroundColor3 = color
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = 13
	b.Font = Enum.Font.GothamBold
	b.Parent = frame
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	return b
end

local startBtn = button("START", 8, 84, Color3.fromRGB(50, 80, 120))
local stopBtn = button("STOP", 98, 72, Color3.fromRGB(140, 50, 50))
local copyBtn = button("COPIA LOG", 176, 110, Color3.fromRGB(40, 120, 50))
local boostBtn = button("APPLICA BOOST", 292, 150, Color3.fromRGB(140, 90, 20))

logBox = Instance.new("TextBox")
logBox.Size = UDim2.new(1, -16, 1, -48)
logBox.Position = UDim2.fromOffset(8, 42)
logBox.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
logBox.TextColor3 = Color3.fromRGB(210, 216, 200)
logBox.TextSize = 13
logBox.Font = Enum.Font.Code
logBox.Text = "START cerca la funzione. APPLICA BOOST scrive 10000."
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.TextWrapped = true
logBox.ClearTextOnFocus = false
logBox.TextEditable = false
logBox.MultiLine = true
logBox.Parent = frame

startBtn.MouseButton1Click:Connect(function()
	if not alive or scanning then
		return
	end
	scanning = true
	task.spawn(function()
		local ok, err = pcall(search)
		scanning = false
		if not ok and alive then
			log("[ERR] " .. tostring(err))
		end
	end)
end)

stopBtn.MouseButton1Click:Connect(function()
	if not alive then
		return
	end
	local had = #targets
	restore()
	if had > 0 then
		log("[STOP] Pet Walkspeed ripristinato")
	else
		log("[STOP]")
	end
end)

copyBtn.MouseButton1Click:Connect(function()
	local text = table.concat(logs, "\n")
	if text == "" then
		log("[COPY] log vuoto")
		return
	end
	if typeof(setclip) ~= "function" then
		log("[ERR] setclipboard assente")
		return
	end
	local ok, err = pcall(setclip, text)
	if ok then
		log("[COPY] " .. tostring(#logs) .. " righe")
	else
		log("[ERR] setclipboard " .. tostring(err))
	end
end)

boostBtn.MouseButton1Click:Connect(function()
	if not alive then
		return
	end
	task.spawn(function()
		local ok, err = pcall(applyBoost)
		if not ok and alive then
			log("[BOOST] Errore: " .. tostring(err))
		end
	end)
end)

env.__DeltaPetSpeed = {
	stop = shutdown,
}

log("[READY] Delta pet speed")
