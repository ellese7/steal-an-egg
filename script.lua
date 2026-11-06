-- Delta: analisi remoti e timestamp per portare dupe.lua su Xeno.
-- Hook __namecall con newcclosure. Original prima, log dopo.
-- Niente PivotTo. Non hardcodare hash.

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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local env = _G
pcall(function()
	if typeof(getgenv) == "function" then
		env = getgenv()
	end
end)
if typeof(env.__DeltaDupeAnalysis) == "table" and typeof(env.__DeltaDupeAnalysis.stop) == "function" then
	pcall(env.__DeltaDupeAnalysis.stop)
end

local alive = true
local running = false
local scanningVulns = false
local lines = {}
local logLabel
local logScroll
local gui
local saveConn
local box = env.__DeltaDupeSpy
if typeof(box) ~= "table" then
	box = { on = false, busy = false, copying = false }
	env.__DeltaDupeSpy = box
end

local FILTER = { "toggle", "auto", "hatch", "delete", "network", "save", "timestamp" }
local SUSPECT = { "enabled", "toggle", "auto", "state", "bool", "freeze", "lock", "save", "hatch", "delete" }

-- Remoti visti dall'hook con primo arg booleano (type confusion).
local boolArgRemotes = {}

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

local function clockText()
	local ok, text = pcall(os.date, "%H:%M:%S")
	if ok and typeof(text) == "string" then
		return text
	end
	return tostring(math.floor(os.clock()))
end

local function flushLog()
	if not logLabel then
		return
	end
	logLabel.Text = table.concat(lines, "\n")
	task.defer(function()
		if not alive or not logScroll or not logLabel then
			return
		end
		local height = logLabel.TextBounds.Y + 8
		logScroll.CanvasSize = UDim2.fromOffset(0, height)
		logScroll.CanvasPosition = Vector2.new(0, math.max(0, height - logScroll.AbsoluteSize.Y))
	end)
end

local flushScheduled = false
local function log(msg)
	local line = "[" .. clockText() .. "] " .. msg
	lines[#lines + 1] = line
	print(line)
	if #lines > 400 then
		table.remove(lines, 1)
	end
	if flushScheduled then
		return
	end
	flushScheduled = true
	task.defer(function()
		flushScheduled = false
		flushLog()
	end)
end

local function cut(text, n)
	text = tostring(text or "")
	if #text > n then
		return string.sub(text, 1, n) .. "..."
	end
	return text
end

local function isLuaFn(fn)
	if typeof(fn) ~= "function" then
		return false
	end
	local info = api("info")
	if typeof(info) ~= "function" then
		return false
	end
	local ok, src = pcall(info, fn, "s")
	return ok and typeof(src) == "string" and src ~= "=[C]" and src ~= "[C]"
end

local function hitWords(text, words)
	if typeof(text) ~= "string" or text == "" then
		return nil
	end
	local low = string.lower(text)
	for i = 1, #words do
		if string.find(low, words[i], 1, true) then
			return words[i]
		end
	end
	return nil
end

local function hitFilter(text)
	return hitWords(text, FILTER) ~= nil
end

local function hitSuspect(text)
	return hitWords(text, SUSPECT)
end

local function dumpValue(value, depth, seen)
	if depth > 3 then
		return "..."
	end
	local kind = typeof(value)
	if kind == "nil" then
		return "nil"
	end
	if kind == "boolean" or kind == "number" then
		return tostring(value)
	end
	if kind == "string" then
		return string.format("%q", cut(value, 120))
	end
	if kind == "Vector3" then
		return string.format("Vector3(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
	end
	if kind == "CFrame" then
		local p = value.Position
		return string.format("CFrame(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
	end
	if kind == "Instance" then
		local ok, full = pcall(function()
			return value:GetFullName()
		end)
		return ok and full or (value.ClassName .. " " .. tostring(value.Name))
	end
	if kind == "function" then
		return "function"
	end
	if kind ~= "table" then
		return kind
	end
	seen = seen or {}
	if seen[value] then
		return "<cycle>"
	end
	seen[value] = true
	local parts = {}
	local n = 0
	local okPairs = pcall(function()
		for k, v in pairs(value) do
			n = n + 1
			if n > 12 then
				parts[#parts + 1] = "..."
				return
			end
			parts[#parts + 1] = tostring(k) .. "=" .. dumpValue(v, depth + 1, seen)
		end
	end)
	if not okPairs then
		return "{?}"
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function argsWanted(path, argc, args)
	if hitFilter(path) then
		return true
	end
	for i = 1, argc do
		local v = args[i]
		if typeof(v) == "string" and hitFilter(v) then
			return true
		end
		if typeof(v) == "table" then
			local ok = pcall(function()
				for k, item in pairs(v) do
					if (typeof(k) == "string" and hitFilter(k)) or (typeof(item) == "string" and hitFilter(item)) then
						error("hit")
					end
				end
			end)
			if not ok then
				return true
			end
		end
	end
	return false
end

local function instPath(inst)
	if typeof(inst) ~= "Instance" then
		return "?"
	end
	local ok, full = pcall(function()
		return inst:GetFullName()
	end)
	return ok and full or tostring(inst.Name)
end

local function upvalueAt(fn, index)
	local getter = api("getupvalue")
	if typeof(getter) ~= "function" then
		return nil, false
	end
	local ok, a, b = pcall(getter, fn, index)
	if not ok or (a == nil and b == nil) then
		return nil, false
	end
	if typeof(a) == "string" then
		return b, true
	end
	return a, true
end

local function findTimestampInTable(tbl, depth, seen, out)
	if depth > 4 or typeof(tbl) ~= "table" or seen[tbl] then
		return
	end
	seen[tbl] = true
	pcall(function()
		for k, v in pairs(tbl) do
			local key = typeof(k) == "string" and k or nil
			if key then
				local low = string.lower(key)
				if string.find(low, "lastsavetimestamp", 1, true)
					or string.find(low, "savetimestamp", 1, true)
					or string.find(low, "savetime", 1, true)
					or low == "_saveclock"
					or string.find(low, "timestamp", 1, true) then
					out[#out + 1] = { key = key, value = v, table = tbl }
				end
			end
			if typeof(v) == "table" then
				findTimestampInTable(v, depth + 1, seen, out)
			end
		end
	end)
end

local function readSaveTimestamp(Library)
	if typeof(Library) ~= "table" or typeof(Library.Save) ~= "table" then
		return nil, nil
	end
	local getFn = Library.Save.Get
	if typeof(getFn) ~= "function" then
		return nil, nil
	end
	local ok, save = pcall(getFn)
	if not ok or typeof(save) ~= "table" then
		return nil, nil
	end
	local keys = { "LastSaveTimestamp", "SaveTimestamp", "SaveTime", "_saveClock" }
	for i = 1, #keys do
		local v = save[keys[i]]
		if v ~= nil then
			return keys[i], v
		end
	end
	local found = {}
	findTimestampInTable(save, 0, {}, found)
	if found[1] then
		return found[1].key, found[1].value
	end
	return "Save", save
end

local function loadFrameworkLibrary()
	local framework = ReplicatedStorage:FindFirstChild("Framework")
	local module = framework and framework:FindFirstChild("Library")
	if module then
		local ok, loaded = pcall(require, module)
		if ok and typeof(loaded) == "table" then
			return loaded, "Framework.Library"
		end
		log("[SAVE] require Framework.Library fallito: " .. tostring(loaded))
	end
	local library = ReplicatedStorage:FindFirstChild("Library")
	if library and library:IsA("ModuleScript") then
		local ok, loaded = pcall(require, library)
		if ok and typeof(loaded) == "table" then
			return loaded, "Library"
		end
	end
	return nil, nil
end

local function scanPlayerAttributes()
	local ok, attrs = pcall(function()
		return LocalPlayer:GetAttributes()
	end)
	if not ok or typeof(attrs) ~= "table" then
		log("[SAVE] GetAttributes non disponibile")
		return
	end
	local hit = 0
	for k, v in pairs(attrs) do
		local key = tostring(k)
		if hitFilter(key) or (typeof(v) == "number" and v > 1000000000) then
			log(string.format("[SAVE] attr %s = %s", key, tostring(v)))
			hit = hit + 1
		end
	end
	if hit == 0 then
		log("[SAVE] nessun attributo player simile a timestamp")
	end
end

local function scanHeartbeatUpvalues()
	local getconnections = api("getconnections")
	if typeof(getconnections) ~= "function" then
		log("[SAVE] getconnections assente")
		return
	end
	local ok, conns = pcall(getconnections, RunService.Heartbeat)
	if not ok or typeof(conns) ~= "table" then
		log("[SAVE] Heartbeat connections illeggibili")
		return
	end
	log("[SAVE] Heartbeat connessioni=" .. tostring(#conns))
	local hits = 0
	local seen = {}
	for i = 1, #conns do
		local conn = conns[i]
		local fn = typeof(conn) == "function" and conn
			or (typeof(conn) == "table" and (conn.Function or conn.func))
		if typeof(fn) == "function" and not seen[fn] then
			seen[fn] = true
			for u = 1, 30 do
				local up, aliveUp = upvalueAt(fn, u)
				if not aliveUp then
					break
				end
				if typeof(up) == "table" then
					local found = {}
					findTimestampInTable(up, 0, {}, found)
					for f = 1, #found do
						hits = hits + 1
						if hits <= 12 then
							log(string.format(
								"[SAVE] Heartbeat upvalue #%d key=%s value=%s",
								u,
								found[f].key,
								cut(dumpValue(found[f].value, 0), 80)
							))
						end
					end
				end
			end
		end
		if i % 20 == 0 then
			task.wait()
		end
	end
	if hits == 0 then
		log("[SAVE] nessun LastSaveTimestamp negli upvalue Heartbeat")
	end
end

local function inspectLibraryDeep(Library, source)
	if typeof(Library) ~= "table" then
		return
	end
	local keys = {}
	pcall(function()
		for k, v in pairs(Library) do
			keys[#keys + 1] = tostring(k) .. ":" .. typeof(v)
			if #keys >= 24 then
				return
			end
		end
	end)
	log("[LIB] " .. source .. " keys: " .. table.concat(keys, ", "))
	if typeof(Library.Network) == "table" then
		local netKeys = {}
		pcall(function()
			for k, v in pairs(Library.Network) do
				netKeys[#netKeys + 1] = tostring(k) .. ":" .. typeof(v)
				if #netKeys >= 16 then
					return
				end
			end
		end)
		log("[LIB] Network keys: " .. table.concat(netKeys, ", "))
	end
	if typeof(Library.Save) == "table" then
		local saveKeys = {}
		pcall(function()
			for k, v in pairs(Library.Save) do
				saveKeys[#saveKeys + 1] = tostring(k) .. ":" .. typeof(v)
				if #saveKeys >= 16 then
					return
				end
			end
		end)
		log("[LIB] Save keys: " .. table.concat(saveKeys, ", "))
	end
	log("[LIB] Loaded=" .. tostring(Library.Loaded))
end

local function scanGcForLibrary()
	local getgc = api("getgc")
	if typeof(getgc) ~= "function" then
		log("[LIB] getgc assente")
		return
	end
	local ok, objects = pcall(getgc, true)
	if not ok or typeof(objects) ~= "table" then
		ok, objects = pcall(getgc)
	end
	if not ok or typeof(objects) ~= "table" then
		log("[LIB] getgc fallito")
		return
	end
	log("[LIB] getgc oggetti=" .. tostring(#objects))
	local found = 0
	for i = 1, #objects do
		local obj = objects[i]
		if typeof(obj) == "table" then
			local hasNetwork = rawget(obj, "Network") ~= nil
			local hasSave = rawget(obj, "Save") ~= nil
			local hasLoaded = rawget(obj, "Loaded") ~= nil
			if hasNetwork and hasSave then
				found = found + 1
				if found <= 3 then
					log("[LIB] tabella Library-like via getgc #" .. tostring(found))
					inspectLibraryDeep(obj, "getgc#" .. tostring(found))
					local key, value = readSaveTimestamp(obj)
					if key then
						log(string.format("[SAVE] getgc TS key=%s value=%s", key, cut(dumpValue(value, 0), 80)))
					end
				end
			elseif hasLoaded and (hasNetwork or hasSave) then
				found = found + 1
				if found <= 3 then
					log("[LIB] tabella parziale via getgc #" .. tostring(found))
					inspectLibraryDeep(obj, "getgc-partial#" .. tostring(found))
				end
			end
		end
		if i % 800 == 0 then
			task.wait()
		end
	end
	if found == 0 then
		log("[LIB] nessuna tabella Library via getgc")
	end
end

local function startSaveMonitor(Library)
	if saveConn then
		pcall(function()
			saveConn:Disconnect()
		end)
		saveConn = nil
	end
	local lastKey, lastValue
	local nextAt = 0
	saveConn = RunService.Heartbeat:Connect(function()
		if not alive or not running or box.copying then
			return
		end
		local now = os.clock()
		if now < nextAt then
			return
		end
		nextAt = now + 2
		local ok, err = pcall(function()
			local key, value = readSaveTimestamp(Library)
			if key == nil then
				return
			end
			local shown = dumpValue(value, 0)
			if key ~= lastKey or shown ~= lastValue then
				lastKey, lastValue = key, shown
				log(string.format("[SAVE] TS %s: %s", key, cut(shown, 120)))
			else
				log(string.format("[SAVE] TS: %s", cut(shown, 120)))
			end
		end)
		if not ok then
			log("[SAVE] monitor err " .. tostring(err))
		end
	end)
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
		local val, aliveUp = upvalueAt(fn, i)
		if not aliveUp then
			break
		end
		if typeof(val) == "function" and not isLuaFn(val) then
			local n = 0
			for u = 1, 5 do
				local _, ok = upvalueAt(val, u)
				if not ok then
					break
				end
				n = n + 1
			end
			if n == 0 then
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

local function ensureEngine()
	if typeof(box.engine) == "function" and not isLuaFn(box.engine) then
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
	if typeof(recovered) == "function" then
		box.engine = recovered
		return recovered
	end
	if typeof(box.detour) == "function" and current == box.detour then
		return nil
	end
	box.engine = current
	return current
end

local function noteBoolArg(self, method, argc, args)
	if typeof(self) ~= "Instance" then
		return
	end
	if not self:IsA("RemoteEvent") and not self:IsA("RemoteFunction") and not self:IsA("UnreliableRemoteEvent") then
		return
	end
	if argc < 1 or typeof(args[1]) ~= "boolean" then
		return
	end
	local path = instPath(self)
	local row = boolArgRemotes[path]
	if not row then
		row = {
			path = path,
			remote = self,
			method = method,
			trueN = 0,
			falseN = 0,
			last = args[1],
		}
		boolArgRemotes[path] = row
	end
	row.method = method
	row.last = args[1]
	if args[1] then
		row.trueN = row.trueN + 1
	else
		row.falseN = row.falseN + 1
	end
end

local function logNet(self, method, argc, args)
	noteBoolArg(self, method, argc, args)
	local path = instPath(self)
	if not argsWanted(path, argc, args) then
		return
	end
	local shown = {}
	for i = 1, argc do
		shown[i] = dumpValue(args[i], 0)
	end
	log(string.format(
		"[NET] %s | Metodo: %s | Args: %s",
		path,
		method,
		table.concat(shown, ", ")
	))
end

local function connFunction(conn)
	if typeof(conn) == "function" then
		return conn
	end
	if typeof(conn) ~= "table" then
		return nil
	end
	return conn.Function or conn.func or conn.Fn or conn.Callback
end

local function functionHints(fn)
	local hints = {}
	local seen = {}
	local function add(text, source)
		if typeof(text) ~= "string" or text == "" or seen[text] then
			return
		end
		local word = hitSuspect(text)
		if not word then
			return
		end
		seen[text] = true
		hints[#hints + 1] = { name = text, word = word, source = source }
	end
	local infoFn = api("info") or api("getinfo")
	if typeof(infoFn) == "function" then
		pcall(function()
			local a, b, c, d = infoFn(fn, "n")
			add(typeof(a) == "string" and a or nil, "debug.info:n")
			add(typeof(b) == "string" and b or nil, "debug.info:n")
		end)
		pcall(function()
			local nparams = infoFn(fn, "a")
			if typeof(nparams) == "number" and nparams > 0 then
				add("param_count_" .. tostring(nparams), "debug.info:a")
			end
		end)
		pcall(function()
			local info = infoFn(fn)
			if typeof(info) == "table" then
				add(info.name, "getinfo.name")
				add(info.namewhat, "getinfo.namewhat")
				if typeof(info.parameters) == "table" then
					for _, p in pairs(info.parameters) do
						add(tostring(p), "getinfo.parameters")
					end
				end
			end
		end)
	end
	local getconstants = api("getconstants")
	if typeof(getconstants) == "function" then
		local ok, consts = pcall(getconstants, fn)
		if ok and typeof(consts) == "table" then
			for _, c in pairs(consts) do
				if typeof(c) == "string" then
					add(c, "constant")
				end
			end
		end
	end
	for i = 1, 40 do
		local getter = api("getupvalue")
		if typeof(getter) ~= "function" then
			break
		end
		local ok, a, b = pcall(getter, fn, i)
		if not ok or (a == nil and b == nil) then
			break
		end
		if typeof(a) == "string" then
			add(a, "upvalue-name")
			if typeof(b) == "string" then
				add(b, "upvalue")
			elseif typeof(b) == "boolean" then
				add(a .. "=bool", "upvalue-bool")
			end
		elseif typeof(a) == "boolean" then
			add("bool_upvalue_" .. tostring(i), "upvalue-bool")
		end
	end
	local cleaned = {}
	for i = 1, #hints do
		if not string.match(hints[i].name, "^param_count_") then
			cleaned[#cleaned + 1] = hints[i]
		end
	end
	return cleaned
end

local function listRemotes(root)
	local list = {}
	local ok, descendants = pcall(function()
		return root:GetDescendants()
	end)
	if not ok then
		return list
	end
	for i = 1, #descendants do
		local inst = descendants[i]
		if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
			list[#list + 1] = inst
		end
	end
	local kids = root:GetChildren()
	for i = 1, #kids do
		local inst = kids[i]
		if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent") then
			local already = false
			for j = 1, #list do
				if list[j] == inst then
					already = true
					break
				end
			end
			if not already then
				list[#list + 1] = inst
			end
		end
	end
	return list
end

local function signalOf(remote)
	if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
		return remote.OnClientEvent, "OnClientEvent"
	end
	if remote:IsA("RemoteFunction") then
		local ok, signal = pcall(function()
			return remote.OnClientInvoke
		end)
		if ok then
			return signal, "OnClientInvoke"
		end
	end
	return nil, nil
end

local function runVulnScan()
	if scanningVulns then
		log("[SCAN] gia' in corso")
		return
	end
	scanningVulns = true
	local okRun, err = pcall(function()
		log("[SCAN] scansione passiva avviata (read-only)")
		local getconnections = api("getconnections")
		if typeof(getconnections) ~= "function" then
			log("[SCAN] getconnections assente")
		end
		local remotes = listRemotes(ReplicatedStorage)
		log("[SCAN] Remote in ReplicatedStorage: " .. tostring(#remotes))
		local candidates = {}
		local function addCandidate(path, param, source, remote)
			local key = path .. "|" .. tostring(param) .. "|" .. tostring(source)
			if candidates[key] then
				return
			end
			candidates[key] = {
				path = path,
				param = param,
				source = source,
				remote = remote,
			}
			log(string.format(
				"[CANDIDATE] %s | Parametro sospetto: %s | Fonte: %s",
				path,
				tostring(param),
				tostring(source)
			))
		end
		for i = 1, #remotes do
			if not alive then
				break
			end
			local remote = remotes[i]
			local path = instPath(remote)
			local pathHit = hitSuspect(path) or hitSuspect(remote.Name)
			if pathHit then
				addCandidate(path, pathHit, "NomeRemote", remote)
			end
			local signal, signalName = signalOf(remote)
			if typeof(getconnections) == "function" and signal ~= nil then
				local okConn, conns = pcall(getconnections, signal)
				if okConn and typeof(conns) == "table" then
					for _, conn in pairs(conns) do
						local fn = connFunction(conn)
						if typeof(fn) == "function" then
							local hints = functionHints(fn)
							for h = 1, #hints do
								addCandidate(
									path,
									hints[h].name,
									signalName .. "/" .. hints[h].source,
									remote
								)
							end
						end
					end
				end
			end
			if i % 25 == 0 then
				task.wait()
			end
		end
		local boolPaths = {}
		for path, row in pairs(boolArgRemotes) do
			boolPaths[#boolPaths + 1] = path
			addCandidate(
				path,
				"boolean first-arg last=" .. tostring(row.last),
				"Argomento/" .. tostring(row.method) .. " t=" .. tostring(row.trueN) .. " f=" .. tostring(row.falseN),
				row.remote
			)
		end
		table.sort(boolPaths)
		local unique = {}
		local names = {}
		for _, row in pairs(candidates) do
			if not unique[row.path] then
				unique[row.path] = true
				names[#names + 1] = row.path
			end
		end
		table.sort(names)
		log(string.format(
			"[SCAN] Trovati %d remote che accettano booleani. Candidati: %s",
			#boolPaths,
			#boolPaths > 0 and table.concat(boolPaths, " | ") or "(nessuno ancora dall'hook)"
		))
		log(string.format(
			"[SCAN] Candidati totali unici: %d | %s",
			#names,
			#names > 0 and table.concat(names, " | ") or "(nessuno)"
		))
		log("[SCAN] fine. Nessun remote e' stato invocato.")
	end)
	scanningVulns = false
	if not okRun then
		log("[SCAN] errore " .. tostring(err))
	end
end

local function installHook()
	local getnamecallmethod = api("getnamecallmethod")
	local newcclosure = api("newcclosure")
	local setreadonly = api("setreadonly")
	local hookmetamethod = api("hookmetamethod")
	if typeof(getnamecallmethod) ~= "function" then
		log("[ERR] getnamecallmethod assente")
		return false
	end
	if typeof(newcclosure) ~= "function" then
		log("[ERR] newcclosure assente")
		return false
	end
	local current, mt = namecallNow()
	if typeof(current) ~= "function" or typeof(mt) ~= "table" then
		log("[ERR] namecall originale assente. Rientra.")
		return false
	end
	if isLuaFn(current) then
		log("[ERR] namecall gia' Lua. Chiudi il gioco, rientra, riesegui.")
		return false
	end
	local original = ensureEngine()
	if typeof(original) ~= "function" then
		log("[ERR] namecall impilato. Chiudi il gioco, rientra, riesegui.")
		return false
	end
	local token = {}
	local probe = newcclosure(function()
		return token
	end)
	local probeOk, probeGot = pcall(probe)
	if not probeOk or probeGot ~= token then
		log("[ERR] newcclosure perde gli upvalue")
		return false
	end
	local detour = newcclosure(function(self, ...)
		if box.copying or not box.on then
			return original(self, ...)
		end
		local method = getnamecallmethod()
		if method ~= "FireServer" and method ~= "InvokeServer" then
			return original(self, ...)
		end
		local argc = select("#", ...)
		local args = { ... }
		local pack = table.pack(original(self, ...))
		if not box.busy then
			box.busy = true
			local ok, err = pcall(logNet, self, method, argc, args)
			box.busy = false
			if not ok then
				log("[ERR] log " .. tostring(err))
			end
		end
		return unpack(pack, 1, pack.n)
	end)
	if typeof(detour) ~= "function" then
		log("[ERR] detour assente")
		return false
	end
	local installed = false
	if typeof(hookmetamethod) == "function" then
		local ok, previous = pcall(hookmetamethod, game, "__namecall", detour)
		if ok and typeof(previous) == "function" then
			original = previous
			box.engine = previous
			installed = true
			log("[HOOK] installato via hookmetamethod")
		else
			log("[HOOK] hookmetamethod rifiutato " .. tostring(previous))
		end
	end
	if not installed then
		if typeof(setreadonly) == "function" then
			pcall(setreadonly, mt, false)
		end
		local wrote, writeErr = pcall(function()
			mt.__namecall = detour
		end)
		if typeof(setreadonly) == "function" then
			pcall(setreadonly, mt, true)
		end
		if not wrote then
			log("[ERR] scrittura namecall " .. tostring(writeErr))
			return false
		end
		if namecallNow() == original then
			log("[ERR] namecall non sostituito")
			return false
		end
		installed = true
		log("[HOOK] installato via metatable")
	end
	box.mt = mt
	box.engine = original
	box.detour = detour
	box.on = true
	return true
end

local function restoreHook()
	box.on = false
	local mt = box.mt
	local original = box.engine
	local detour = box.detour
	if typeof(mt) ~= "table" or typeof(original) ~= "function" then
		return
	end
	local setreadonly = api("setreadonly")
	pcall(function()
		if typeof(setreadonly) == "function" then
			setreadonly(mt, false)
		end
		if rawget(mt, "__namecall") == detour then
			rawset(mt, "__namecall", original)
		end
		if typeof(setreadonly) == "function" then
			setreadonly(mt, true)
		end
	end)
	log("[HOOK] ripristinato")
end

local function stopAnalysis()
	running = false
	box.on = false
	if saveConn then
		pcall(function()
			saveConn:Disconnect()
		end)
		saveConn = nil
	end
	restoreHook()
	log("[STOP]")
end

local function startAnalysis()
	if running then
		return
	end
	running = true
	log("[START] analisi dupe")
	local Library, source = loadFrameworkLibrary()
	if Library then
		log("[SAVE] Library caricata! via " .. source)
		inspectLibraryDeep(Library, source)
		local key, value = readSaveTimestamp(Library)
		if key then
			log(string.format("[SAVE] TS iniziale %s: %s", key, cut(dumpValue(value, 0), 120)))
		else
			log("[SAVE] timestamp non trovato in Library.Save.Get()")
		end
		startSaveMonitor(Library)
	else
		log("[SAVE] require fallito, metodi alternativi")
		scanPlayerAttributes()
		task.spawn(function()
			scanHeartbeatUpvalues()
		end)
	end
	task.spawn(function()
		scanGcForLibrary()
	end)
	if not installHook() then
		running = false
		return
	end
	log("[START] spy attivo. Attendi Toggle Auto Hatch / Auto Delete.")
end

local function copyLogs()
	box.copying = true
	local text = table.concat(lines, "\n")
	local clip = api("setclipboard")
	if typeof(clip) ~= "function" then
		pcall(function()
			if typeof(setclipboard) == "function" then
				clip = setclipboard
			elseif typeof(toclipboard) == "function" then
				clip = toclipboard
			end
		end)
	end
	if typeof(clip) == "function" then
		local ok, err = pcall(clip, text)
		if ok then
			log("[COPY] " .. tostring(#lines) .. " righe inviate a setclipboard")
		else
			log("[COPY] " .. tostring(err))
		end
	else
		log("[COPY] setclipboard assente")
	end
	box.copying = false
end

local function shutdown()
	alive = false
	stopAnalysis()
	local pg = LocalPlayer:FindFirstChild("PlayerGui")
	local old = pg and pg:FindFirstChild("DeltaDupeAnalysis")
	if old then
		pcall(function()
			old:Destroy()
		end)
	end
end

local pg = LocalPlayer:WaitForChild("PlayerGui")
local oldGui = pg:FindFirstChild("DeltaDupeAnalysis")
if oldGui then
	pcall(function()
		oldGui:Destroy()
	end)
end

gui = Instance.new("ScreenGui")
gui.Name = "DeltaDupeAnalysis"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(520, 240)
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
	b.TextSize = 12
	b.Font = Enum.Font.GothamBold
	b.Parent = frame
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	return b
end

local startBtn = button("START", 8, 70, Color3.fromRGB(50, 80, 120))
local stopBtn = button("STOP", 84, 62, Color3.fromRGB(140, 50, 50))
local copyBtn = button("COPIA LOG", 152, 96, Color3.fromRGB(40, 120, 50))
local scanBtn = button("SCAN VULNS", 254, 110, Color3.fromRGB(90, 60, 130))

logScroll = Instance.new("ScrollingFrame")
logScroll.Size = UDim2.new(1, -16, 1, -48)
logScroll.Position = UDim2.fromOffset(8, 40)
logScroll.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 6
logScroll.CanvasSize = UDim2.fromOffset(0, 0)
logScroll.Parent = frame

local logCorner = Instance.new("UICorner")
logCorner.CornerRadius = UDim.new(0, 6)
logCorner.Parent = logScroll

logLabel = Instance.new("TextLabel")
logLabel.BackgroundTransparency = 1
logLabel.Size = UDim2.new(1, -10, 0, 0)
logLabel.Position = UDim2.fromOffset(4, 4)
logLabel.AutomaticSize = Enum.AutomaticSize.Y
logLabel.Font = Enum.Font.Code
logLabel.TextSize = 12
logLabel.TextXAlignment = Enum.TextXAlignment.Left
logLabel.TextYAlignment = Enum.TextYAlignment.Top
logLabel.TextColor3 = Color3.fromRGB(220, 226, 232)
logLabel.TextWrapped = true
logLabel.Text = ""
logLabel.Parent = logScroll

startBtn.MouseButton1Click:Connect(function()
	if not alive then
		return
	end
	task.spawn(function()
		local ok, err = pcall(startAnalysis)
		if not ok then
			log("[ERR] " .. tostring(err))
			running = false
		end
	end)
end)

stopBtn.MouseButton1Click:Connect(function()
	if not alive then
		return
	end
	pcall(stopAnalysis)
end)

copyBtn.MouseButton1Click:Connect(function()
	if not alive then
		return
	end
	pcall(copyLogs)
end)

scanBtn.MouseButton1Click:Connect(function()
	if not alive or scanningVulns then
		return
	end
	task.spawn(function()
		local ok, err = pcall(runVulnScan)
		if not ok then
			scanningVulns = false
			log("[SCAN] " .. tostring(err))
		end
	end)
end)

env.__DeltaDupeAnalysis = { stop = shutdown }
log("[READY] Delta dupe analysis")
