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
local loggedFunc = {}
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
		local key = src .. "|" .. tostring(upvalueCount(fn))
		if not loggedFunc[key] then
			loggedFunc[key] = true
			log(string.format("[FUNC] Trovata funzione: %s | upvalue: %d | via %s", cut(src, 140), upvalueCount(fn), how))
		end
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

local DROP_KEYS = { "orb", "loot", "bag", "collect", "pickup", "coin" }
local dropByName = {}
local dropScanAt = 0

local function keyHit(text)
	if typeof(text) ~= "string" or text == "" then
		return nil
	end
	local s = string.lower(text)
	for i = 1, #DROP_KEYS do
		if string.find(s, DROP_KEYS[i], 1, true) then
			return DROP_KEYS[i]
		end
	end
	return nil
end

local function indexDrops()
	local now = os.clock()
	if now - dropScanAt < 0.4 then
		return
	end
	dropScanAt = now
	local nextMap = {}
	local things = game:GetService("Workspace"):FindFirstChild("__THINGS")
	if not things then
		dropByName = nextMap
		return
	end
	local function take(folder, kind)
		if not folder then
			return
		end
		local kids = folder:GetChildren()
		for i = 1, #kids do
			local child = kids[i]
			nextMap[child.Name] = kind
			local ok, id = pcall(function()
				return child:GetAttribute("ID")
			end)
			if ok and typeof(id) == "string" and id ~= "" then
				nextMap[id] = kind
			end
		end
	end
	take(things:FindFirstChild("Orbs"), "Orb")
	take(things:FindFirstChild("Lootbags"), "Lootbag")
	dropByName = nextMap
end

local function dropKindFromInst(inst)
	local named = dropByName[inst.Name]
	local parent = inst.Parent
	if parent and (parent.Name == "Orbs" or parent.Name == "Lootbags") then
		return parent.Name == "Orbs" and "Orb" or "Lootbag"
	end
	local node = inst
	for _ = 1, 6 do
		if not node or not node.Parent then
			break
		end
		if node.Parent.Name == "__THINGS" then
			if node.Name == "Orbs" then
				return "Orb"
			end
			if node.Name == "Lootbags" then
				return "Lootbag"
			end
		end
		node = node.Parent
	end
	return named
end

local function instPath(inst)
	local ok, full = pcall(function()
		return inst:GetFullName()
	end)
	if ok and typeof(full) == "string" then
		return full
	end
	return tostring(inst.Name)
end

local function inspectDrop(value, hits, depth)
	if depth > 3 or value == nil then
		return
	end
	local kind = typeof(value)
	if kind == "string" then
		local key = keyHit(value)
		if key then
			hits.key = hits.key or key
		end
		local drop = dropByName[value]
		if drop then
			hits.drops[#hits.drops + 1] = drop .. " " .. value
		end
	elseif kind == "Instance" then
		local fullName = instPath(value)
		local key = keyHit(fullName) or keyHit(value.Name)
		if key then
			hits.key = hits.key or key
		end
		local drop = dropKindFromInst(value)
		if drop then
			hits.drops[#hits.drops + 1] = drop .. " " .. fullName
		end
	elseif kind == "table" then
		for k, v in pairs(value) do
			inspectDrop(k, hits, depth + 1)
			inspectDrop(v, hits, depth + 1)
		end
	end
end

local function collectWanted(hits, path)
	if #hits.drops > 0 then
		return true
	end
	if hits.key and hits.key ~= "coin" then
		return true
	end
	if hits.key == "coin" and keyHit(path) == "coin" then
		return true
	end
	return false
end

local function dumpValue(value, depth)
	if depth > 2 then
		return "..."
	end
	local kind = typeof(value)
	if kind == "string" then
		local drop = dropByName[value]
		if drop then
			return "[HIT " .. drop .. "] " .. value
		end
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
	if kind == "Vector3" then
		return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
	end
	if kind == "CFrame" then
		local pos = value.Position
		return string.format("CFrame(%.2f, %.2f, %.2f)", pos.X, pos.Y, pos.Z)
	end
	if kind == "Instance" then
		local path = instPath(value)
		local drop = dropKindFromInst(value)
		if drop then
			return "[HIT " .. drop .. "] " .. path
		end
		return path
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

local function recoverEngine(fn, guard)
	if typeof(fn) ~= "function" or isLuaFn(fn) then
		return nil
	end
	guard = guard or {}
	if guard[fn] then
		return nil
	end
	guard[fn] = true
	for i = 1, 40 do
		local name, val, aliveUp = upvalueAt(fn, i)
		if not aliveUp then
			break
		end
		if (name == "original" or name == "old") and typeof(val) == "function" and not isLuaFn(val) then
			if upvalueCount(val) == 0 then
				return val
			end
			local deeper = recoverEngine(val, guard)
			if typeof(deeper) == "function" then
				return deeper
			end
		end
	end
	return nil
end

local function spyBox()
	local box = env.__DeltaNamecallSpy
	if typeof(box) ~= "table" then
		box = { on = false, busy = false, ready = false }
		env.__DeltaNamecallSpy = box
	end
	return box
end

local seenClaim = {}

local function setSpy(flag)
	spyOn = flag
	spyBox().on = flag
end

local function ensureEngine()
	local box = spyBox()
	if typeof(box.engine) == "function" and (isLuaFn(box.engine) or upvalueCount(box.engine) > 0) then
		box.engine = nil
	end
	if typeof(box.engine) == "function" then
		return box.engine
	end
	local current, mt = namecallNow()
	if typeof(mt) == "table" then
		box.mt = mt
	end
	if typeof(current) ~= "function" or isLuaFn(current) then
		return nil
	end
	local recovered = recoverEngine(current)
	if typeof(recovered) == "function" and upvalueCount(recovered) == 0 then
		box.engine = recovered
		return recovered
	end
	if upvalueCount(current) > 0 then
		return nil
	end
	if typeof(box.detour) == "function" and current == box.detour then
		return nil
	end
	box.engine = current
	return current
end

local function spyStart()
	local box = spyBox()
	if box.drain then
		pcall(function()
			box.drain:Disconnect()
		end)
		box.drain = nil
	end
	local getnamecallmethod = api("getnamecallmethod")
	local newcclosure = api("newcclosure")
	local setreadonly = api("setreadonly")
	if typeof(getnamecallmethod) ~= "function" or typeof(newcclosure) ~= "function" then
		log("[ERR] getnamecallmethod o newcclosure assente")
		return
	end
	local current, mt = namecallNow()
	if typeof(current) ~= "function" or typeof(mt) ~= "table" then
		log("[ERR] namecall originale assente. Rientra nel gioco.")
		return
	end
	if isLuaFn(current) then
		log("[ERR] namecall gia' rotto. Chiudi il gioco, rientra, poi riesegui.")
		return
	end
	box.mt = mt
	local original = ensureEngine()
	if typeof(original) ~= "function" then
		log("[ERR] namecall impilato. Chiudi il gioco, rientra, poi riesegui.")
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
		indexDrops()
		local path = "?"
		if typeof(self) == "Instance" then
			path = instPath(self)
		end
		local hits = { drops = {} }
		local pathKey = keyHit(path)
		if pathKey then
			hits.key = pathKey
		end
		local packed = { ... }
		local n = select("#", ...)
		for i = 1, n do
			inspectDrop(packed[i], hits, 0)
		end
		if not collectWanted(hits, path) then
			return
		end
		local shown = {}
		for i = 1, n do
			shown[i] = dumpValue(packed[i], 0)
		end
		local mark = ""
		if #hits.drops > 0 then
			mark = " HIT " .. table.concat(hits.drops, " | ")
		end
		log("[COLLECT] " .. path .. mark .. " | Args: " .. table.concat(shown, ", "))
		if typeof(self) == "Instance" and self:IsA("RemoteEvent") then
			for i = 1, #hits.drops do
				local label = hits.drops[i]
				if string.sub(label, 1, 4) == "Orb " then
					seenClaim.Orb = self
				elseif string.sub(label, 1, 8) == "Lootbag " then
					seenClaim.Lootbag = self
				end
			end
		end
	end
	local counts = {}
	local detour = newcclosure(function(self, ...)
		if box.copying then
			return original(self, ...)
		end
		local method
		if box.on and not box.busy then
			method = getnamecallmethod()
			if method == nil then
				pcall(function()
					local g = getgenv()
					local alt = g and g.getnamecallmethod
					if typeof(alt) == "function" then
						method = alt()
					end
				end)
			end
			local key = tostring(method)
			counts[key] = (counts[key] or 0) + 1
		end
		if (method == "FireServer" or method == "InvokeServer") and not box.busy then
			local argc = select("#", ...)
			local args = { ... }
			local pack = table.pack(original(self, ...))
			box.busy = true
			local ok, err = pcall(logFire, self, unpack(args, 1, argc))
			box.busy = false
			if not ok then
				log("[ERRORE LOG] " .. tostring(err))
			end
			return unpack(pack, 1, pack.n)
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
	box.real = original
	box.mt = mt
	box.detour = detour
	box.ready = true
	namecallReady = true
	if box.drain then
		pcall(function()
			box.drain:Disconnect()
		end)
	end
	box.drain = RunService.Heartbeat:Connect(function()
		if not box.tick then
			box.tick = os.clock()
		end
		if os.clock() - box.tick < 1 then
			return
		end
		box.tick = os.clock()
		local parts = {}
		local extra = 0
		for key, value in pairs(counts) do
			if #parts < 8 then
				parts[#parts + 1] = key .. "=" .. tostring(value)
			else
				extra = extra + value
			end
			counts[key] = nil
		end
		if #parts == 0 then
			return
		end
		table.sort(parts)
		if extra > 0 then
			parts[#parts + 1] = "altri=" .. tostring(extra)
		end
		log("[HOOK] " .. table.concat(parts, " "))
	end)
	setSpy(true)
	log("[REMOTE] spy attivo")
end

local function setNamecall(fn)
	local box = spyBox()
	if typeof(box.mt) ~= "table" or typeof(fn) ~= "function" then
		return
	end
	local setreadonly = api("setreadonly")
	if typeof(setreadonly) == "function" then
		pcall(setreadonly, box.mt, false)
	end
	pcall(function()
		rawset(box.mt, "__namecall", fn)
	end)
	if typeof(setreadonly) == "function" then
		pcall(setreadonly, box.mt, true)
	end
	return namecallNow() == fn
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
			if inst.Parent == rs and string.match(inst.Name, "^%x+$") and #inst.Name >= 16 then
				shown = shown + 1
			end
		end
		if i % 400 == 0 then
			task.wait()
		end
	end
	log(string.format("[REMOTE] scan remoti=%d sospetti=%d", total, shown))
end

local ORB_HASH = "dd6b06ed6c49492a26678b848e3dd8c9"
local BAG_HASH = "aa4e3b0fdcd344e764c48257a73ebae4"
local testBusy = false

local function isHexHash(text)
	return typeof(text) == "string" and #text >= 16 and string.match(text, "^%x+$") ~= nil
end

local function noteMap(found, hash, name, remote)
	if not isHexHash(hash) then
		return
	end
	local row = found[hash]
	if not row then
		row = {}
		found[hash] = row
	end
	if typeof(name) == "string" and name ~= "" and not isHexHash(name) then
		row.name = name
	end
	if typeof(remote) == "Instance" and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") or remote:IsA("UnreliableRemoteEvent")) then
		row.remote = remote
		if isHexHash(remote.Name) then
			row.hash = remote.Name
		end
	end
end

local function walkMap(value, seen, depth, found)
	if depth > 5 or value == nil or seen[value] then
		return
	end
	local kind = typeof(value)
	if kind == "table" then
		seen[value] = true
		pcall(function()
			for key, item in pairs(value) do
				local keyText = typeof(key) == "string" and key or nil
				if typeof(item) == "Instance" then
					noteMap(found, item.Name, keyText, item)
					noteMap(found, keyText, nil, item)
				elseif isHexHash(item) and keyText then
					noteMap(found, item, keyText, nil)
				elseif isHexHash(keyText) and typeof(item) == "string" then
					noteMap(found, keyText, item, nil)
				end
				if typeof(item) == "table" or typeof(item) == "function" then
					walkMap(item, seen, depth + 1, found)
				end
			end
		end)
	elseif kind == "function" then
		seen[value] = true
		for i = 1, 25 do
			local _, up, aliveUp = upvalueAt(value, i)
			if not aliveUp then
				break
			end
			if typeof(up) == "table" or typeof(up) == "function" or typeof(up) == "Instance" then
				walkMap(up, seen, depth + 1, found)
			end
		end
	elseif kind == "Instance" then
		noteMap(found, value.Name, nil, value)
	end
end

local function mapCollectRemotes()
	local rs = game:GetService("ReplicatedStorage")
	local library = rs:FindFirstChild("Library")
	local module = library and library:FindFirstChild("Network")
	local network
	if module then
		local ok, loaded = pcall(require, module)
		if ok and typeof(loaded) == "table" then
			network = loaded
		end
	end
	local found = {}
	local seen = {}
	local getsenv = api("getsenv")
	if module and typeof(getsenv) == "function" then
		local ok, env = pcall(getsenv, module)
		if ok and typeof(env) == "table" then
			walkMap(env, seen, 0, found)
		else
			log("[MAP] getsenv senza ambiente")
		end
	else
		log("[MAP] getsenv assente")
	end
	if network then
		walkMap(network, seen, 0, found)
	end
	local function remoteOf(hash)
		local row = found[hash]
		if row and row.remote then
			return row.remote
		end
		local inst = rs:FindFirstChild(hash)
		if typeof(inst) == "Instance" and inst:IsA("RemoteEvent") then
			return inst
		end
		return nil
	end
	local function report(label, hash)
		local row = found[hash]
		local name = row and row.name or nil
		local remote = remoteOf(hash)
		if name then
			log("[MAP] " .. label .. " -> " .. name)
		elseif remote then
			log("[MAP] " .. label .. " -> hash " .. hash .. " senza nome")
		else
			log("[MAP] " .. label .. " -> hash assente in questa sessione")
		end
		return name, remote
	end
	local orbName, orbRemote = report("OrbRemote", ORB_HASH)
	local bagName, bagRemote = report("LootbagRemote", BAG_HASH)
	return network, orbName, orbRemote, bagName, bagRemote
end

local function dropPosition(inst)
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	local part = inst:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

local function playerRoot()
	local char = LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function runCollectTest()
	local network, orbName, orbRemote, bagName, bagRemote = mapCollectRemotes()
	local things = game:GetService("Workspace"):FindFirstChild("__THINGS")
	local orbs = things and things:FindFirstChild("Orbs")
	local bags = things and things:FindFirstChild("Lootbags")
	local function sendOrb(id)
		if orbName and network and typeof(network.Fire) == "function" then
			network.Fire(orbName, { id })
			return orbName
		end
		if orbRemote then
			orbRemote:FireServer({ id })
			return orbRemote.Name
		end
		return nil
	end
	local function sendBag(id, pos)
		if bagName and network and typeof(network.Fire) == "function" then
			network.Fire(bagName, id, pos)
			return bagName
		end
		if bagRemote then
			bagRemote:FireServer(id, pos)
			return bagRemote.Name
		end
		return nil
	end
	local function probe(kind, folder, send)
		local drop = folder and folder:GetChildren()[1]
		if not drop then
			log("[TEST] nessun " .. kind)
			return
		end
		local pos = dropPosition(drop)
		local root = playerRoot()
		if not pos or not root then
			log("[TEST] " .. kind .. " senza posizione")
			return
		end
		root.CFrame = CFrame.new(pos + Vector3.new(50, 5, 0))
		task.wait(0.3)
		root = playerRoot() or root
		local away = (root.Position - pos).Magnitude
		local label
		local okSend, sendErr = pcall(function()
			label = send(drop.Name, pos)
		end)
		if not okSend then
			log("[TEST] invio " .. kind .. " fallito " .. tostring(sendErr))
			return
		end
		if not label then
			log("[TEST] remote " .. kind .. " assente")
			return
		end
		task.wait(1)
		root = playerRoot() or root
		local still = drop.Parent ~= nil
		log(string.format("[TEST] Distanza attuale: %.1f stud | Remote: %s | Drop sparito: %s", away, label, tostring(not still)))
		log("[TEST] Drop ancora a terra: " .. tostring(still))
	end
	probe("Orb", orbs, function(id)
		return sendOrb(id)
	end)
	probe("Lootbag", bags, function(id, pos)
		return sendBag(id, pos)
	end)
end

local function sharedEnv()
	local genv = _G
	pcall(function()
		if typeof(getgenv) == "function" then
			genv = getgenv()
		end
	end)
	return genv
end

local function readableName(text)
	return typeof(text) == "string" and text ~= "" and not isHexHash(text) and string.match(text, "%a") ~= nil
end

local function mapHashName(hash)
	local rs = game:GetService("ReplicatedStorage")
	local library = rs:FindFirstChild("Library")
	local module = library and library:FindFirstChild("Network")
	local network
	local requireOk = false
	if module then
		local ok, loaded = pcall(require, module)
		if ok and typeof(loaded) == "table" then
			network = loaded
			requireOk = true
		end
	end
	local foundName
	local function consider(name)
		if not foundName and readableName(name) then
			foundName = name
		end
	end
	if requireOk then
		local seen = {}
		local function walk(value, depth)
			if foundName or depth > 6 or value == nil or seen[value] then
				return
			end
			local kind = typeof(value)
			if kind == "table" then
				seen[value] = true
				pcall(function()
					for key, item in pairs(value) do
						local keyText = typeof(key) == "string" and key or nil
						if isHexHash(item) and item == hash then
							consider(keyText)
						elseif isHexHash(keyText) and keyText == hash then
							consider(item)
						elseif typeof(item) == "Instance" and item.Name == hash then
							consider(keyText)
						end
						if typeof(item) == "table" or typeof(item) == "function" then
							walk(item, depth + 1)
						end
					end
				end)
			elseif kind == "function" then
				seen[value] = true
				if typeof(getconstants) == "function" then
					local okConst, consts = pcall(getconstants, value)
					if okConst and typeof(consts) == "table" then
						local hasHash = false
						local names = {}
						for _, c in pairs(consts) do
							if c == hash then
								hasHash = true
							elseif readableName(c) then
								names[#names + 1] = c
							end
						end
						if hasHash then
							consider(names[1])
						end
					end
				end
				for i = 1, 30 do
					local _, up, aliveUp = upvalueAt(value, i)
					if not aliveUp then
						break
					end
					walk(up, depth + 1)
				end
			end
		end
		walk(network, 0)
	end
	if not foundName then
		local remote = rs:FindFirstChild(hash)
		local getconns = api("getconnections")
		if typeof(remote) == "Instance" and remote:IsA("RemoteEvent") and typeof(getconns) == "function" then
			local okConn, conns = pcall(getconns, remote.OnClientEvent)
			if okConn and typeof(conns) == "table" then
				for _, conn in pairs(conns) do
					local fn = typeof(conn) == "function" and conn or (typeof(conn) == "table" and (conn.Function or conn.func))
					if typeof(fn) == "function" and typeof(getconstants) == "function" then
						local okConst, consts = pcall(getconstants, fn)
						if okConst and typeof(consts) == "table" then
							for _, c in pairs(consts) do
								if readableName(c) then
									local low = string.lower(c)
									if string.find(low, "orb", 1, true) or string.find(low, "loot", 1, true) or string.find(low, "bag", 1, true) or string.find(low, "collect", 1, true) then
										consider(c)
									end
								end
							end
						end
					end
					if foundName then
						break
					end
				end
			end
		end
	end
	local remote = rs:FindFirstChild(hash)
	if typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
		remote = nil
	end
	if foundName then
		log("[MAP] Hash " .. hash .. " -> " .. foundName)
	else
		log("[MAP] Mappatura non trovata")
	end
	return network, foundName, remote
end

local function pauseGameOrbs()
	local paused = {}
	local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
	if not scripts then
		return paused
	end
	local list = scripts:GetDescendants()
	for i = 1, #list do
		local inst = list[i]
		if inst:IsA("LocalScript") and inst.Name == "Orbs" and not inst.Disabled then
			inst.Disabled = true
			paused[#paused + 1] = inst
		end
	end
	return paused
end

local function resumeGameOrbs(paused)
	for i = 1, #paused do
		local inst = paused[i]
		if inst.Parent then
			inst.Disabled = false
		end
	end
end

local function runCleanCollectTest()
	local genv = sharedEnv()
	genv.DisableAutoCollect = true
	local paused = pauseGameOrbs()
	local function finish()
		genv.DisableAutoCollect = false
		resumeGameOrbs(paused)
	end
	local okRun, runErr = pcall(function()
		local network, orbName, orbRemote = mapHashName(ORB_HASH)
		local _, bagName, bagRemote = mapHashName(BAG_HASH)
		local things = game:GetService("Workspace"):FindFirstChild("__THINGS")
		local orbFolder = things and things:FindFirstChild("Orbs")
		local bagFolder = things and things:FindFirstChild("Lootbags")
		local function fireOrb(id)
			if orbName and network and typeof(network.Fire) == "function" then
				network.Fire(orbName, { id })
				return
			end
			if orbRemote then
				orbRemote:FireServer({ id })
			end
		end
		local function fireBag(id, pos)
			if bagName and network and typeof(network.Fire) == "function" then
				network.Fire(bagName, id, pos)
				return
			end
			if bagRemote then
				bagRemote:FireServer(id, pos)
			end
		end
		local function settle(drop, studs)
			local origin = dropPosition(drop)
			local root = playerRoot()
			if not origin or not root or drop.Parent == nil then
				return nil
			end
			root.CFrame = CFrame.new(origin + Vector3.new(studs, 0, 0))
			task.wait(3)
			if drop.Parent == nil then
				return nil
			end
			local now = dropPosition(drop)
			local rootNow = playerRoot() or root
			local moved = (now and origin) and (now - origin).Magnitude or 0
			local away = now and (rootNow.Position - now).Magnitude or 0
			return now, away, moved
		end
		for n = 1, 3 do
			local drop = orbFolder and orbFolder:GetChildren()[1]
			if not drop then
				log("[TEST_ORB] nessun Orb")
				break
			end
			local id = drop.Name
			local pos, away, moved = settle(drop, 100)
			if not pos then
				log("[TEST_ORB] Orb sparita prima della chiamata")
			else
				if moved > 2 then
					log(string.format("[TEST_ORB] Orb spostata di %.1f stud durante l'attesa, magnete ancora attivo", moved))
				end
				local okSend, sendErr = pcall(fireOrb, id)
				if not okSend then
					log("[TEST_ORB] invio fallito " .. tostring(sendErr))
				else
					task.wait(1)
					local gone = drop.Parent == nil
					log(string.format("[TEST_ORB] Distanza: %.0f stud | Orb sparita: %s", away, tostring(gone)))
				end
			end
		end
		for _, studs in ipairs({ 10, 20, 30, 50 }) do
			local drop = bagFolder and bagFolder:GetChildren()[1]
			if not drop then
				log("[TEST_LOOTBAG] nessun Lootbag")
				break
			end
			local id = drop.Name
			local pos, away, moved = settle(drop, studs)
			if not pos then
				log("[TEST_LOOTBAG] Lootbag sparito prima della chiamata")
			else
				if moved > 2 then
					log(string.format("[TEST_LOOTBAG] Bag spostato di %.1f stud durante l'attesa, magnete ancora attivo", moved))
				end
				local okSend, sendErr = pcall(fireBag, id, pos)
				if not okSend then
					log("[TEST_LOOTBAG] invio fallito " .. tostring(sendErr))
				else
					task.wait(1)
					local gone = drop.Parent == nil
					log(string.format("[TEST_LOOTBAG] Distanza: %.0f stud | Bag sparito: %s", away, tostring(gone)))
				end
			end
		end
	end)
	finish()
	if not okRun then
		error(runErr)
	end
end

local function loadNetwork()
	local rs = game:GetService("ReplicatedStorage")
	local library = rs:FindFirstChild("Library")
	local module = library and library:FindFirstChild("Network")
	if not module then
		return nil
	end
	local ok, loaded = pcall(require, module)
	if ok and typeof(loaded) == "table" then
		return loaded
	end
	return nil
end

local function harvestNamedRemotes(network)
	local rs = game:GetService("ReplicatedStorage")
	local named = {}
	local seen = {}
	local function add(name, remote)
		if not readableName(name) then
			return
		end
		if typeof(remote) == "Instance" and remote:IsA("RemoteEvent") then
			named[name] = remote
		end
	end
	local function resolveHash(hash)
		if not isHexHash(hash) then
			return nil
		end
		local inst = rs:FindFirstChild(hash)
		if typeof(inst) == "Instance" and inst:IsA("RemoteEvent") then
			return inst
		end
		return nil
	end
	local function walk(value, depth)
		if depth > 6 or value == nil or seen[value] then
			return
		end
		local kind = typeof(value)
		if kind == "table" then
			seen[value] = true
			pcall(function()
				for key, item in pairs(value) do
					local keyText = typeof(key) == "string" and key or nil
					if typeof(item) == "Instance" then
						add(keyText, item)
					elseif isHexHash(item) and keyText then
						add(keyText, resolveHash(item))
					elseif isHexHash(keyText) and typeof(item) == "string" then
						add(item, resolveHash(keyText))
					end
					if typeof(item) == "table" or typeof(item) == "function" then
						walk(item, depth + 1)
					end
				end
			end)
		elseif kind == "function" then
			seen[value] = true
			for i = 1, 30 do
				local _, up, aliveUp = upvalueAt(value, i)
				if not aliveUp then
					break
				end
				if typeof(up) == "table" or typeof(up) == "function" or typeof(up) == "Instance" then
					walk(up, depth + 1)
				end
			end
			if typeof(getconstants) == "function" then
				local okConst, consts = pcall(getconstants, value)
				if okConst and typeof(consts) == "table" then
					local hashes = {}
					local names = {}
					for _, c in pairs(consts) do
						if isHexHash(c) then
							hashes[#hashes + 1] = c
						elseif readableName(c) then
							names[#names + 1] = c
						end
					end
					if #hashes == 1 and #names == 1 then
						add(names[1], resolveHash(hashes[1]))
					end
				end
			end
		elseif kind == "Instance" then
			seen[value] = true
		end
	end
	if typeof(network) == "table" then
		walk(network, 0)
		if typeof(network.Fire) == "function" then
			walk(network.Fire, 0)
		end
	end
	return named
end

local function nameScore(name, words)
	local low = string.lower(name)
	if string.find(low, "coin", 1, true) or string.find(low, "pet", 1, true) or string.find(low, "egg", 1, true) then
		return -1
	end
	local score = 0
	for i = 1, #words do
		if string.find(low, words[i], 1, true) then
			score = score + 1
		end
	end
	return score
end

local function pickNamed(named, words)
	local bestName, bestRemote, bestScore
	for name, remote in pairs(named) do
		local score = nameScore(name, words)
		if score > 0 and (not bestScore or score > bestScore) then
			bestName, bestRemote, bestScore = name, remote, score
		end
	end
	return bestName, bestRemote
end

local function remotePath(remote)
	if typeof(remote) ~= "Instance" then
		return "?"
	end
	local ok, full = pcall(function()
		return remote:GetFullName()
	end)
	if ok and typeof(full) == "string" then
		return full
	end
	return tostring(remote.Name)
end

local function claimRejected(low)
	return string.find(low, "removed", 1, true)
		or string.find(low, "destroy", 1, true)
		or string.find(low, "delete", 1, true)
		or string.find(low, "spawn", 1, true)
		or string.find(low, "coin", 1, true)
		or string.find(low, "pet", 1, true)
		or string.find(low, "egg", 1, true)
end

local function claimRows(named)
	local rows = {}
	for name, remote in pairs(named) do
		local low = string.lower(name)
		if string.find(low, "orb", 1, true)
			or string.find(low, "loot", 1, true)
			or string.find(low, "bag", 1, true)
			or string.find(low, "gift", 1, true)
			or string.find(low, "collect", 1, true)
			or string.find(low, "claim", 1, true)
			or string.find(low, "redeem", 1, true)
			or string.find(low, "pickup", 1, true) then
			rows[#rows + 1] = { name = name, remote = remote, low = low }
		end
	end
	table.sort(rows, function(a, b)
		return a.name < b.name
	end)
	return rows
end

local function pickClaim(rows, words)
	local best, bestScore
	for i = 1, #rows do
		local row = rows[i]
		if not claimRejected(row.low) then
			local hit = false
			for w = 1, #words do
				if string.find(row.low, words[w], 1, true) then
					hit = true
					break
				end
			end
			if hit then
				local score = 1
				if string.find(row.low, "collect", 1, true) then
					score = score + 5
				end
				if string.find(row.low, "claim", 1, true) or string.find(row.low, "redeem", 1, true) then
					score = score + 4
				end
				if not bestScore or score > bestScore then
					best, bestScore = row, score
				end
			end
		end
	end
	return best
end

local function runClaim()
	local network = loadNetwork()
	local named = harvestNamedRemotes(network)
	local rows = claimRows(named)
	if #rows == 0 then
		log("[CLAIM] nessun nome orb/loot/gift nel Network")
	end
	for i = 1, #rows do
		local row = rows[i]
		local stato = claimRejected(row.low) and "scartato" or "candidato"
		log(string.format("[CLAIM] %s %q -> %s | hash %s", stato, row.name, remotePath(row.remote), tostring(row.remote and row.remote.Name)))
	end
	local bagRow = pickClaim(rows, { "lootbag", "loot" })
	local giftRow = pickClaim(rows, { "gift" })
	local orbRow = pickClaim(rows, { "orb" })
	local bagName = bagRow and bagRow.name or nil
	local bagRemote = (bagRow and bagRow.remote) or seenClaim.Lootbag
	local giftName = giftRow and giftRow.name or nil
	local giftRemote = giftRow and giftRow.remote or nil
	local orbName = orbRow and orbRow.name or nil
	local orbRemote = (orbRow and orbRow.remote) or nil
	if not orbRemote and seenClaim.Orb then
		local skip = false
		for i = 1, #rows do
			if rows[i].remote == seenClaim.Orb and claimRejected(rows[i].low) then
				skip = true
				break
			end
		end
		if not skip then
			orbRemote = seenClaim.Orb
			log("[CLAIM] Orb dal remote visto in gioco -> " .. remotePath(orbRemote) .. " | hash " .. tostring(orbRemote.Name))
		end
	end
	local things = game:GetService("Workspace"):FindFirstChild("__THINGS")
	if things then
		local folders = things:GetChildren()
		local shown = {}
		for i = 1, #folders do
			shown[i] = folders[i].Name .. ":" .. tostring(#folders[i]:GetChildren())
		end
		log("[CLAIM] __THINGS " .. table.concat(shown, ", "))
	else
		log("[CLAIM] __THINGS assente")
	end
	local function send(name, remote, ...)
		local preview = {}
		local n = select("#", ...)
		for i = 1, n do
			preview[i] = dumpValue(select(i, ...), 0)
		end
		local via = remotePath(remote)
		log(string.format("[CLAIM] Fire %q -> %s | hash %s | args %s", tostring(name), via, tostring(remote and remote.Name), table.concat(preview, ", ")))
		if name and network and typeof(network.Fire) == "function" then
			local ok, err = pcall(network.Fire, name, ...)
			if ok then
				return true
			end
			log("[CLAIM] Fire nome fallito " .. tostring(err))
		end
		if remote then
			local ok, err = pcall(function(...)
				remote:FireServer(...)
			end, ...)
			if ok then
				return true
			end
			log("[CLAIM] FireServer fallito " .. tostring(err))
		end
		return false
	end
	local function dropsOf(folder)
		local list = {}
		if not folder then
			return list
		end
		local kids = folder:GetChildren()
		for i = 1, #kids do
			if kids[i].Parent then
				list[#list + 1] = kids[i]
			end
		end
		return list
	end
	local function fireDrops(kind, name, remote, folder, withPos)
		local drops = dropsOf(folder)
		if not name and not remote then
			log("[CLAIM] " .. kind .. " remote assente")
			return
		end
		if #drops == 0 then
			log("[CLAIM] nessun " .. kind)
			return
		end
		local sent = 0
		for i = 1, #drops do
			local drop = drops[i]
			local pos = dropPosition(drop)
			if drop.Parent and (not withPos or pos) then
				local ok
				if withPos then
					ok = send(name, remote, drop.Name, pos)
				else
					ok = send(name, remote, { drop.Name })
				end
				if ok then
					sent = sent + 1
				end
			end
		end
		task.wait(2)
		local gone = 0
		for i = 1, #drops do
			if drops[i].Parent == nil then
				gone = gone + 1
			end
		end
		log(string.format("[CLAIM] %s inviati %d | spariti %d | ancora a terra %d", kind, sent, gone, #drops - gone))
	end
	local function fireOrbs()
		local folder = things and things:FindFirstChild("Orbs")
		local drops = dropsOf(folder)
		if not orbName and not orbRemote then
			log("[CLAIM] Orb collect assente. Orb Removed non viene usato: non raccoglie.")
			return
		end
		if #drops == 0 then
			log("[CLAIM] nessun Orb")
			return
		end
		local ids = {}
		for i = 1, #drops do
			ids[i] = drops[i].Name
		end
		local sent = 0
		local step = 30
		for i = 1, #ids, step do
			local batch = {}
			for j = i, math.min(i + step - 1, #ids) do
				batch[#batch + 1] = ids[j]
			end
			if send(orbName, orbRemote, batch) then
				sent = sent + #batch
			end
		end
		task.wait(1.5)
		local gone = 0
		for i = 1, #drops do
			if drops[i].Parent == nil then
				gone = gone + 1
			end
		end
		log(string.format("[CLAIM] Orb inviate %d | sparite %d | ancora a terra %d", sent, gone, #drops - gone))
	end
	fireDrops("Lootbag", bagName, bagRemote, things and things:FindFirstChild("Lootbags"), true)
	if giftName and giftRemote and giftRemote ~= bagRemote then
		local giftFolder = things and (things:FindFirstChild("Gifts") or things:FindFirstChild("Giftbags") or things:FindFirstChild("GiftBags"))
		fireDrops("Gift", giftName, giftRemote, giftFolder, true)
	end
	task.wait(1)
	fireOrbs()
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
frame.Size = UDim2.fromOffset(460, 200)
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
local boostBtn = button("BOOST SPEED", 292, 150, Color3.fromRGB(140, 90, 20))

local testBtn = Instance.new("TextButton")
testBtn.Name = "TestCollect"
testBtn.Size = UDim2.fromOffset(140, 28)
testBtn.Position = UDim2.fromOffset(480, 12)
testBtn.BackgroundColor3 = Color3.fromRGB(90, 50, 140)
testBtn.Text = "RISCATTA"
testBtn.TextColor3 = Color3.new(1, 1, 1)
testBtn.TextSize = 13
testBtn.Font = Enum.Font.GothamBold
testBtn.Parent = gui
local testCorner = Instance.new("UICorner")
testCorner.CornerRadius = UDim.new(0, 6)
testCorner.Parent = testBtn

local cleanBtn = Instance.new("TextButton")
cleanBtn.Name = "TestPulito"
cleanBtn.Size = UDim2.fromOffset(140, 28)
cleanBtn.Position = UDim2.fromOffset(480, 46)
cleanBtn.BackgroundColor3 = Color3.fromRGB(40, 90, 110)
cleanBtn.Visible = false
cleanBtn.Text = "RISCATTA"
cleanBtn.TextColor3 = Color3.new(1, 1, 1)
cleanBtn.TextSize = 13
cleanBtn.Font = Enum.Font.GothamBold
cleanBtn.Parent = gui
local cleanCorner = Instance.new("UICorner")
cleanCorner.CornerRadius = UDim.new(0, 6)
cleanCorner.Parent = cleanBtn

logScroll = Instance.new("ScrollingFrame")
logScroll.Size = UDim2.new(1, -16, 1, -48)
logScroll.Position = UDim2.fromOffset(8, 40)
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
	task.spawn(function()
		local ok, err = pcall(scanRemotes)
		if not ok and alive then
			log("[ERR] " .. tostring(err))
		end
	end)
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

copyBtn.MouseButton1Click:Connect(function()
	local box = spyBox()
	if box.copying then
		return
	end
	setSpy(false)
	local text = table.concat(logs, "\n")
	local rows = #logs
	if text == "" then
		log("[COPY] log vuoto")
		return
	end
	local engine = ensureEngine()
	if typeof(engine) ~= "function" then
		log("[ERR] namecall impilato. Chiudi il gioco, rientra, poi COPIA LOG.")
		return
	end
	if not setNamecall(engine) then
		log("[ERR] namecall non staccato")
		return
	end
	box.copying = true
	box.detour = nil
	if typeof(box.clipBox) == "Instance" then
		box.clipBox:Destroy()
		box.clipBox = nil
	end
	local g = env
	if typeof(getgenv) == "function" then
		g = getgenv()
	end
	local holder = Instance.new("TextBox")
	holder.Name = "DeltaLogCopy"
	holder.ClearTextOnFocus = false
	holder.TextEditable = true
	holder.MultiLine = true
	holder.Size = UDim2.fromOffset(360, 140)
	holder.Position = UDim2.fromOffset(12, 220)
	holder.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	holder.TextColor3 = Color3.fromRGB(210, 216, 200)
	holder.TextSize = 12
	holder.Font = Enum.Font.Code
	holder.TextXAlignment = Enum.TextXAlignment.Left
	holder.TextYAlignment = Enum.TextYAlignment.Top
	holder.ZIndex = 20
	holder.Parent = gui
	holder.Text = text
	box.clipBox = holder
	local held = #holder.Text
	if holder.Text ~= text then
		holder:Destroy()
		box.clipBox = nil
		box.copying = false
		local writeFn = g.writefile
		local readFn = g.readfile
		local fileOk = false
		if typeof(writeFn) == "function" and typeof(readFn) == "function" then
			local wrote = pcall(writeFn, "psx_delta_log.txt", text)
			if wrote then
				local okBack, back = pcall(readFn, "psx_delta_log.txt")
				fileOk = okBack and back == text
			end
		end
		if fileOk then
			log("[ERR] log di " .. tostring(#text) .. " caratteri, la casella ne tiene " .. tostring(held) .. ". Testo in psx_delta_log.txt")
		else
			log("[ERR] log di " .. tostring(#text) .. " caratteri, la casella ne tiene " .. tostring(held))
		end
		return
	end
	task.wait()
	holder:CaptureFocus()
	task.wait()
	holder.CursorPosition = #holder.Text + 1
	holder.SelectionStart = 1
	box.copying = false
	local selected = holder:IsFocused() and holder.SelectionStart == 1 and holder.Text == text
	if selected then
		log("[COPY] " .. tostring(rows) .. " righe selezionate. Premi Ctrl+C, poi incolla.")
	else
		log("[ERR] selezione non riuscita")
	end
	local clipFn = g.setclipboard or g.toclipboard
	if typeof(clipFn) == "function" then
		clipFn(text)
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

testBtn.MouseButton1Click:Connect(function()
	if not alive or testBusy then
		return
	end
	testBusy = true
	task.spawn(function()
		local ok, err = pcall(runClaim)
		testBusy = false
		if not ok and alive then
			log("[CLAIM] " .. tostring(err))
		end
	end)
end)

cleanBtn.MouseButton1Click:Connect(function()
	if not alive or testBusy then
		return
	end
	testBusy = true
	task.spawn(function()
		local ok, err = pcall(runClaim)
		testBusy = false
		if not ok and alive then
			log("[CLAIM] " .. tostring(err))
		end
	end)
end)

env.__DeltaPetSpeed = {
	stop = shutdown,
}

if typeof(spyBox().detour) == "function" and typeof(ensureEngine()) ~= "function" then
	log("[ERR] namecall impilato. Chiudi il gioco, rientra, poi riesegui.")
end
log("[READY] Delta pet speed")
