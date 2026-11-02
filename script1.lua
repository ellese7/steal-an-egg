-- Delta: trova la funzione di movimento dei pet e alza Upgrades["Pet Walkspeed"].
-- getconnections, getgc, debug.getupvalue, debug.setupvalue.
-- v113 non viene sostituito. Si fissa la tabella Upgrades che la funzione legge.

local function namecallNow()
	local grm = getrawmetatable
	if type(grm) ~= "function" and type(getgenv) == "function" then
		grm = getgenv().getrawmetatable
	end
	if type(grm) ~= "function" then
		return nil
	end
	local ok, mt = pcall(grm, game)
	if not ok or type(mt) ~= "table" then
		return nil
	end
	return rawget(mt, "__namecall"), mt
end

do
	local nc = namecallNow()
	local info = debug and debug.info
	if type(nc) == "function" and type(info) == "function" then
		local ok, src = pcall(info, nc, "s")
		if ok and type(src) == "string" and src ~= "=[C]" and src ~= "[C]" then
			print("[ERR] namecall gia' rotto. Chiudi il gioco, rientra, poi riesegui.")
			return
		end
	end
end

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
local logScroll
local logRows = {}
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
	print(line)
end

local function flushLogs()
	if not alive or not logScroll or not logScroll.Parent then
		return
	end
	while #logs > 2000 do
		table.remove(logs, 1)
		local old = table.remove(logRows, 1)
		if old then
			old:Destroy()
		end
	end
	local added = false
	while #logRows < #logs do
		local row = Instance.new("TextLabel")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -10, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Font = Enum.Font.Code
		row.TextSize = 13
		row.TextColor3 = Color3.fromRGB(210, 216, 200)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextYAlignment = Enum.TextYAlignment.Top
		row.TextWrapped = true
		row.Text = logs[#logRows + 1]
		row.LayoutOrder = #logRows + 1
		row.Parent = logScroll
		logRows[#logRows + 1] = row
		added = true
	end
	if added then
		task.defer(function()
			if logScroll then
				logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y)
			end
		end)
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

local function makeProxy(real)
	return setmetatable({}, {
		__index = function(_, key)
			if key == "Pet Walkspeed" then
				return 10000
			end
			return real[key]
		end,
		__newindex = function(_, key, val)
			if key == "Pet Walkspeed" then
				return
			end
			real[key] = val
		end,
	})
end

local function remember(fn, index, kind, parent, realUpgrades, before)
	for i = 1, #targets do
		if targets[i].realUpgrades == realUpgrades then
			return false
		end
	end
	local proxy = makeProxy(realUpgrades)
	targets[#targets + 1] = {
		fn = fn,
		index = index,
		kind = kind,
		parent = parent,
		realUpgrades = realUpgrades,
		proxy = proxy,
		before = before,
	}
	log(string.format("[UPVALUE] Trovato v113 | Upgrades.Pet Walkspeed = %s", tostring(before)))
	return true
end

local function scanFunction(fn, how, seen, depth)
	if typeof(fn) ~= "function" or seen[fn] or depth > 5 or isFake(fn) then
		return
	end
	seen[fn] = true
	local src = sourceOf(fn)
	local interesting = hasConst(fn, "Pet Walkspeed") or string.find(src, "Game.Pets", 1, true) ~= nil
	if interesting then
		log(string.format("[FUNC] Trovata funzione: %s | upvalue: %d | via %s", cut(src, 140), upvalueCount(fn), how))
	end
	for i = 1, 80 do
		local _, val, alive = upvalueAt(fn, i)
		if not alive then
			break
		end
		local kind, parent, level, up = describe(val)
		if kind == "parent" then
			remember(fn, i, "parent", parent, up, level)
		elseif kind == "direct" then
			remember(fn, i, "direct", nil, parent, level)
		elseif typeof(val) == "function" then
			scanFunction(val, how .. " uv", seen, depth + 1)
		end
	end
	if interesting or depth == 0 then
		local kids = childProtos(fn)
		for i = 1, #kids do
			scanFunction(kids[i], how .. " proto", seen, depth + 1)
		end
	end
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

local function scanSignal(signal, label, seen)
	if typeof(getconnections) ~= "function" then
		log("[ERR] getconnections assente")
		return 0
	end
	local ok, list = pcall(getconnections, signal)
	if not ok or typeof(list) ~= "table" then
		log("[ERR] getconnections " .. label .. " " .. tostring(list))
		return 0
	end
	local n = 0
	for _, conn in pairs(list) do
		n = n + 1
		local fn = connFunction(conn)
		if fn then
			scanFunction(fn, label, seen, 0)
		end
	end
	log(string.format("[FUNC] %s connessioni=%d", label, n))
	return n
end

local function scanGc(seen)
	if typeof(getgc) ~= "function" then
		log("[ERR] getgc assente")
		return
	end
	local ok, bag = pcall(getgc, true)
	if not ok or typeof(bag) ~= "table" then
		log("[ERR] getgc " .. tostring(bag))
		return
	end
	local seenN, fnN, hitN = 0, 0, 0
	for _, obj in pairs(bag) do
		seenN = seenN + 1
		if typeof(obj) == "function" and not seen[obj] and hasConst(obj, "Pet Walkspeed") then
			fnN = fnN + 1
			local before = #targets
			scanFunction(obj, "gc", seen, 0)
			if #targets > before then
				hitN = hitN + 1
			end
		end
		if seenN % 200 == 0 then
			task.wait()
		end
	end
	log(string.format("[FUNC] gc oggetti=%d con costante=%d con upvalue=%d", seenN, fnN, hitN))
end

local restore

local function search()
	if holding or #targets > 0 then
		restore()
	end
	targets = {}
	local seen = {}
	scanSignal(RunService.Heartbeat, "Heartbeat", seen)
	if #targets == 0 then
		scanSignal(RunService.RenderStepped, "RenderStepped", seen)
	end
	if #targets == 0 then
		scanSignal(RunService.Stepped, "Stepped", seen)
	end
	if #targets == 0 then
		scanGc(seen)
	end
	if #targets == 0 then
		log("[UPVALUE] nessuno. Pet Walkspeed non e' in un upvalue raggiungibile")
	else
		log(string.format("[UPVALUE] tabelle=%d", #targets))
	end
end

local function forceOne(item)
	if item.kind == "parent" and typeof(item.parent) == "table" then
		rawset(item.parent, "Upgrades", item.proxy)
		return true, nil
	end
	if typeof(setupvalue) ~= "function" then
		return false, "setupvalue assente"
	end
	local _, now = upvalueAt(item.fn, item.index)
	if now == item.proxy then
		return true, nil
	end
	local ok, err = pcall(setupvalue, item.fn, item.index, item.proxy)
	if not ok then
		return false, err
	end
	return true, nil
end

local function forceAll()
	local okN, err
	for i = 1, #targets do
		local ok, why = forceOne(targets[i])
		if ok then
			okN = (okN or 0) + 1
		else
			err = why
		end
	end
	return okN or 0, err
end

local function stopHold()
	holding = false
	if holdConn then
		pcall(function()
			holdConn:Disconnect()
		end)
		holdConn = nil
	end
end

restore = function()
	stopHold()
	for i = 1, #targets do
		local item = targets[i]
		if item.kind == "parent" and typeof(item.parent) == "table" then
			rawset(item.parent, "Upgrades", item.realUpgrades)
		elseif typeof(setupvalue) == "function" then
			pcall(setupvalue, item.fn, item.index, item.realUpgrades)
		end
		pcall(function()
			item.realUpgrades["Pet Walkspeed"] = item.before
		end)
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
	local n, err = forceAll()
	if n == 0 then
		log("[BOOST] Errore: " .. tostring(err))
		return
	end
	log("[BOOST] Pet Walkspeed impostato a 10000")
	if holding then
		return
	end
	holding = true
	holdConn = RunService.Heartbeat:Connect(function()
		if not alive or not holding then
			return
		end
		forceAll()
	end)
end

local spyOn = false
local spyBusy = false
local namecallReady = false
local KEYS = { "pet", "coin", "chest", "breakable", "attack", "hit", "farm", "equip", "join" }

local function textHits(text)
	local low = string.lower(text)
	for i = 1, #KEYS do
		if string.find(low, KEYS[i], 1, true) then
			return true
		end
	end
	return false
end

local function dumpValue(value, depth)
	if depth > 2 then
		return "..."
	end
	local kind = typeof(value)
	if kind == "string" then
		local id = string.match(value, "^id[%x]+$")
			or string.match(value, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
		if id or (#value >= 24 and string.match(value, "^[%x%-]+$")) then
			return "[ID] " .. value
		end
		return string.format("%q", cut(value, 80))
	end
	if kind == "number" or kind == "boolean" then
		return tostring(value)
	end
	if kind == "Instance" then
		return value:GetFullName()
	end
	if kind == "table" then
		local parts = {}
		local n = 0
		for k, v in pairs(value) do
			n = n + 1
			if n > 8 then
				parts[#parts + 1] = "..."
				break
			end
			parts[#parts + 1] = tostring(k) .. "=" .. dumpValue(v, depth + 1)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return kind
end

local function isLuaFn(fn)
	if typeof(fn) ~= "function" or typeof(debug) ~= "table" or typeof(debug.info) ~= "function" then
		return false
	end
	local ok, src = pcall(debug.info, fn, "s")
	return ok and typeof(src) == "string" and src ~= "=[C]" and src ~= "[C]"
end

local function spyBox()
	local box = env.__DeltaNamecallSpy
	if typeof(box) ~= "table" then
		box = { on = false, busy = false, ready = false }
		env.__DeltaNamecallSpy = box
	end
	return box
end

local function setSpy(flag)
	spyOn = flag
	spyBox().on = flag
end

local function spyStart()
	local box = spyBox()
	if namecallReady or box.ready then
		namecallReady = true
		setSpy(true)
		log("[REMOTE] spy attivo")
		return
	end
	local getnamecallmethod = api("getnamecallmethod")
	local newcclosure = api("newcclosure")
	local setreadonly = api("setreadonly")
	if typeof(getnamecallmethod) ~= "function" or typeof(newcclosure) ~= "function" then
		log("[ERR] getnamecallmethod o newcclosure assente")
		return
	end
	local original, mt = namecallNow()
	if typeof(original) ~= "function" or typeof(mt) ~= "table" then
		log("[ERR] namecall originale assente. Rientra nel gioco.")
		return
	end
	if isLuaFn(original) then
		log("[ERR] namecall gia' rotto. Chiudi il gioco, rientra, poi riesegui.")
		return
	end
	local token = {}
	local probe = newcclosure(function()
		return token
	end)
	if typeof(probe) ~= "function" then
		log("[ERR] newcclosure non ha restituito una funzione")
		return
	end
	local probeOk, probeGot = pcall(probe)
	if not probeOk or probeGot ~= token then
		log("[ERR] newcclosure perde gli upvalue, hook non installato")
		return
	end
	local function logFire(self, ...)
		local path = self:GetFullName()
		local packed = { ... }
		local shown = {}
		for i = 1, #packed do
			shown[i] = dumpValue(packed[i], 0)
		end
		local args = table.concat(shown, ", ")
		if textHits(path .. " " .. args) then
			log("[REMOTE] " .. path .. " | Args: " .. args)
		end
	end
	local detour = newcclosure(function(self, ...)
		if box.on and not box.busy then
			local method = getnamecallmethod()
			if method == "FireServer" and typeof(self) == "Instance" then
				box.busy = true
				pcall(logFire, self, ...)
				box.busy = false
			end
		end
		return original(self, ...)
	end)
	if typeof(detour) ~= "function" then
		log("[ERR] detour assente, hook non installato")
		return
	end
	if typeof(setreadonly) == "function" then
		local unlocked = pcall(setreadonly, mt, false)
		if not unlocked then
			log("[ERR] metatable bloccata, hook non installato")
			return
		end
	end
	local wrote, writeErr = pcall(function()
		mt.__namecall = detour
	end)
	if typeof(setreadonly) == "function" then
		pcall(setreadonly, mt, true)
	end
	if not wrote then
		log("[ERR] hook " .. tostring(writeErr))
		return
	end
	if namecallNow() == original then
		log("[ERR] namecall non sostituito")
		return
	end
	box.ready = true
	namecallReady = true
	setSpy(true)
	log("[REMOTE] spy attivo")
end

local function spyStop()
	if not spyOn and not spyBox().on then
		return
	end
	setSpy(false)
	log("[REMOTE] spy spento")
end

local function scanRemotes()
	local rs = game:GetService("ReplicatedStorage")
	local list = rs:GetDescendants()
	local total, shown = 0, 0
	for i = 1, #list do
		local inst = list[i]
		if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
			total = total + 1
			local path = inst:GetFullName()
			if textHits(path) then
				shown = shown + 1
				local extra = ""
				if typeof(getconnections) == "function" and inst:IsA("RemoteEvent") then
					local ok, conns = pcall(getconnections, inst.OnClientEvent)
					if ok and typeof(conns) == "table" then
						local n = 0
						for _ in pairs(conns) do
							n = n + 1
						end
						extra = " | OnClientEvent=" .. tostring(n)
					end
				end
				log("[REMOTE] scan " .. path .. extra)
			end
		end
		if i % 400 == 0 then
			task.wait()
		end
	end
	log(string.format("[REMOTE] scan remoti=%d sospetti=%d", total, shown))
end

local function shutdown()
	alive = false
	setSpy(false)
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
frame.Size = UDim2.fromOffset(640, 460)
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
local scanBtn = button("SCAN REMOTES", 8, 150, Color3.fromRGB(70, 70, 110))
scanBtn.Position = UDim2.fromOffset(8, 40)

logScroll = Instance.new("ScrollingFrame")
logScroll.Size = UDim2.new(1, -16, 1, -82)
logScroll.Position = UDim2.fromOffset(8, 74)
logScroll.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 8
logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
logScroll.CanvasSize = UDim2.new()
logScroll.Parent = frame
local logLayout = Instance.new("UIListLayout")
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Padding = UDim.new(0, 2)
logLayout.Parent = logScroll
local logPad = Instance.new("UIPadding")
logPad.PaddingTop = UDim.new(0, 4)
logPad.PaddingLeft = UDim.new(0, 4)
logPad.PaddingRight = UDim.new(0, 4)
logPad.Parent = logScroll
RunService.Heartbeat:Connect(flushLogs)

startBtn.MouseButton1Click:Connect(function()
	if not alive then
		return
	end
	task.spawn(spyStart)
	if scanning then
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
	spyStop()
	restore()
	if had > 0 then
		log("[STOP] Pet Walkspeed ripristinato")
	else
		log("[STOP]")
	end
end)

local function clipBuckets()
	local buckets = {}
	pcall(function()
		if typeof(getgenv) == "function" then
			buckets[#buckets + 1] = getgenv()
		end
	end)
	buckets[#buckets + 1] = _G
	return buckets
end

local function clipFns()
	local out, seen = {}, {}
	local names = { "setclipboard", "toclipboard", "setrbxclipboard" }
	local buckets = clipBuckets()
	for i = 1, #buckets do
		for n = 1, #names do
			local ok, fn = pcall(function()
				return buckets[i][names[n]]
			end)
			if ok and typeof(fn) == "function" and not seen[fn] then
				seen[fn] = true
				out[#out + 1] = fn
			end
		end
	end
	return out
end

local function clipRead()
	local buckets = clipBuckets()
	for i = 1, #buckets do
		local ok, fn = pcall(function()
			return buckets[i].getclipboard
		end)
		if ok and typeof(fn) == "function" then
			local ok2, got = pcall(fn)
			if ok2 and typeof(got) == "string" then
				return got
			end
		end
	end
	return nil
end

local function clipMatches(got, text)
	if typeof(got) ~= "string" or got == "" then
		return false
	end
	if got == text then
		return true
	end
	return string.gsub(got, "\r\n", "\n") == text
end

copyBtn.MouseButton1Click:Connect(function()
	setSpy(false)
	local text = table.concat(logs, "\n")
	local rows = #logs
	if text == "" then
		log("[COPY] log vuoto")
		return
	end
	local function writeBackup()
		local ok = pcall(writefile, "psx_delta_log.txt", text)
		return ok
	end
	local fns = clipFns()
	local verified = false
	local called = false
	for i = 1, #fns do
		local ok = pcall(fns[i], text)
		if ok then
			called = true
			local got = clipRead()
			if got == nil or clipMatches(got, text) then
				if got ~= nil then
					verified = true
				end
				break
			end
		end
	end
	if verified then
		log("[COPY] " .. tostring(rows) .. " righe")
		return
	end
	task.spawn(function()
		task.wait(0.1)
		for i = 1, #fns do
			pcall(fns[i], text)
		end
		task.wait(0.1)
		local got = clipRead()
		if clipMatches(got, text) then
			log("[COPY] " .. tostring(rows) .. " righe")
			return
		end
		local wrote = writeBackup()
		if got == nil and called and wrote then
			log("[COPY] " .. tostring(rows) .. " righe | psx_delta_log.txt")
			return
		end
		if wrote then
			log("[ERR] clipboard vuota | file psx_delta_log.txt (" .. tostring(rows) .. " righe)")
		elseif called then
			log("[ERR] clipboard vuota")
		else
			log("[ERR] setclipboard assente")
		end
	end)
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

scanBtn.MouseButton1Click:Connect(function()
	if not alive then
		return
	end
	task.spawn(function()
		local ok, err = pcall(scanRemotes)
		if not ok and alive then
			log("[ERR] " .. tostring(err))
		end
	end)
end)

env.__DeltaPetSpeed = {
	stop = shutdown,
}

log("[READY] Delta pet speed")
