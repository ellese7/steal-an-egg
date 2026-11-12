-- Delta only. Pulse the live save clock, isolate toggle remotes, send dirty
-- payloads, then verdict: three missed pulse cycles = save interruption.
-- No trade. No farm.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	LocalPlayer = Players.PlayerAdded:Wait()
end

local COMMANDS = {
	"Toggle Setting",
	"Toggle Auto Hatch Setting",
	"Toggle Auto Delete",
}
local PAYLOADS = { "0", "{}" }
local WATCH_SECONDS = 6
local SAMPLE_STEP = 1
local CHECKS = 3
local LEARN_SECONDS = 25
local MAX_LINES = 500

local root = _G
pcall(function()
	if type(getgenv) == "function" then
		root = getgenv()
	end
end)

local previous = root.__DeltaSaveFreeze
if type(previous) == "table" then
	previous.running = false
	previous.armed = false
	if previous.old and type(hookmetamethod) == "function" then
		pcall(hookmetamethod, game, "__namecall", previous.old)
	end
end

local bucket = {
	running = false,
	armed = false,
	hits = 0,
	foreign = 0,
	expect = nil,
	remote = nil,
	loose = false,
	capture = nil,
	method = nil,
	old = nil,
}
root.__DeltaSaveFreeze = bucket

local running = false
local generation = 0
local statusLabel
local startBtn
local copyBtn
local logBox
local frameStroke
local lines = {}

local function paintLogs()
	if not logBox or logBox:IsFocused() then
		return
	end
	logBox.Text = table.concat(lines, "\n")
end

local function log(text)
	lines[#lines + 1] = os.date("%H:%M:%S ") .. tostring(text)
	while #lines > MAX_LINES do
		table.remove(lines, 1)
	end
	paintLogs()
end

local function setStatus(text, color)
	if statusLabel then
		statusLabel.Text = tostring(text)
		if color then
			statusLabel.TextColor3 = color
		end
	end
end

local function setStroke(color)
	if frameStroke then
		frameStroke.Color = color
	end
end

local function waitSeconds(seconds)
	local deadline = os.clock() + seconds
	while running and os.clock() < deadline do
		task.wait(0.05)
	end
	return running
end

local function realNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isHash(value)
	return type(value) == "string" and #value == 32 and string.match(value, "^%x+$") ~= nil
end

local function isRemote(inst)
	return typeof(inst) == "Instance" and (inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction"))
end

local function debugId(inst)
	if type(getdebugid) == "function" then
		local ok, id = pcall(getdebugid, inst)
		if ok then
			return tostring(id)
		end
	end
	if typeof(inst) == "Instance" then
		local ok, id = pcall(function()
			return inst:GetDebugId()
		end)
		if ok then
			return tostring(id)
		end
		return inst.ClassName
	end
	return "?"
end

local function remember(list, value)
	for _, item in ipairs(list) do
		if item == value then
			return
		end
	end
	list[#list + 1] = value
end

local function payloadValue(label)
	if label == "0" then
		return 0
	end
	return {}
end

local function copyLogs()
	local text = table.concat(lines, "\n")
	local writers = {}
	if type(setclipboard) == "function" then
		writers[#writers + 1] = setclipboard
	end
	if type(toclipboard) == "function" then
		writers[#writers + 1] = toclipboard
	end
	pcall(function()
		if type(getgenv) == "function" and type(getgenv().setclipboard) == "function" then
			writers[#writers + 1] = getgenv().setclipboard
		end
	end)
	for _, writer in ipairs(writers) do
		local ok = pcall(writer, text)
		if ok then
			if copyBtn then
				local old = copyBtn.Text
				copyBtn.Text = "Copiato!"
				task.delay(1.2, function()
					if copyBtn then
						copyBtn.Text = old
					end
				end)
			end
			return
		end
	end
	if logBox then
		logBox:CaptureFocus()
		logBox.CursorPosition = #logBox.Text + 1
		logBox.SelectionStart = 1
	end
	if copyBtn then
		local old = copyBtn.Text
		copyBtn.Text = "Seleziona"
		task.delay(1.2, function()
			if copyBtn then
				copyBtn.Text = old
			end
		end)
	end
end

local function resolveLibrary()
	local framework = ReplicatedStorage:FindFirstChild("Framework")
	local viaFramework = framework and framework:FindFirstChild("Library")
	if viaFramework and viaFramework:IsA("ModuleScript") then
		local ok, library = pcall(require, viaFramework)
		if ok and type(library) == "table" then
			local started = os.clock()
			while running and library.Loaded ~= true and os.clock() - started < 8 do
				task.wait(0.1)
			end
			if type(library.Network) == "table" and (type(library.Network.Invoke) == "function" or type(library.Network.Fire) == "function") then
				return library, "Framework.Library"
			end
		end
	end
	local moduleScript = ReplicatedStorage:FindFirstChild("Library")
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, library = pcall(require, moduleScript)
		if ok and type(library) == "table" then
			local started = os.clock()
			while running and library.Loaded ~= true and os.clock() - started < 8 do
				task.wait(0.1)
			end
			if type(library.Network) == "table" then
				return library, "ReplicatedStorage.Library"
			end
		end
	end
	return nil, "Library assente"
end

local function currentSave(library)
	if type(library) == "table" and type(library.Save) == "table" and type(library.Save.Get) == "function" then
		local ok, save = pcall(library.Save.Get)
		if ok and type(save) == "table" then
			return save
		end
	end
	return nil
end

local function collectClocks(save)
	local list = {}
	if type(save) ~= "table" then
		return list
	end
	for key, value in pairs(save) do
		if type(key) == "string" and realNumber(value) then
			local lower = string.lower(key)
			local interesting = key == "FreeGiftsTime"
				or key == "FreeGiftsResetTime"
				or key == "LastSaveTimestamp"
				or string.find(lower, "time", 1, true)
				or string.find(lower, "tick", 1, true)
				or string.find(lower, "save", 1, true)
				or string.find(lower, "age", 1, true)
			if interesting then
				list[#list + 1] = {
					key = key,
					value = value,
					prefer = key == "FreeGiftsTime",
				}
			end
		end
	end
	table.sort(list, function(a, b)
		if a.prefer ~= b.prefer then
			return a.prefer
		end
		return a.key < b.key
	end)
	return list
end

local function observeClocks(library, clocks)
	local first = {}
	local last = {}
	local changes = {}
	local stamps = {}
	for _, item in ipairs(clocks) do
		first[item.key] = item.value
		last[item.key] = item.value
		changes[item.key] = 0
		stamps[item.key] = { os.clock() }
	end
	local deadline = os.clock() + WATCH_SECONDS
	while running and os.clock() < deadline do
		if not waitSeconds(SAMPLE_STEP) then
			return nil, "stop"
		end
		local save = currentSave(library)
		if type(save) ~= "table" then
			return nil, "errore"
		end
		for _, item in ipairs(clocks) do
			local now = save[item.key]
			if realNumber(now) then
				if realNumber(last[item.key]) and now ~= last[item.key] then
					changes[item.key] = (changes[item.key] or 0) + 1
					stamps[item.key][#stamps[item.key] + 1] = os.clock()
				end
				last[item.key] = now
			end
		end
	end
	return { first = first, last = last, changes = changes, stamps = stamps }, nil
end

local function estimatePeriod(stamps)
	if type(stamps) ~= "table" or #stamps < 2 then
		return nil
	end
	local gaps = {}
	for i = 2, #stamps do
		gaps[#gaps + 1] = stamps[i] - stamps[i - 1]
	end
	table.sort(gaps)
	return gaps[math.ceil(#gaps / 2)]
end

local function pickPulse(clocks, report)
	local preferred = nil
	local preferredTicks = 0
	local best = nil
	local bestTicks = 0
	for _, item in ipairs(clocks) do
		local ticks = report.changes[item.key] or 0
		if item.key == "FreeGiftsTime" and ticks > preferredTicks then
			preferred = item
			preferredTicks = ticks
		end
		if ticks > bestTicks then
			best = item
			bestTicks = ticks
		end
	end
	if preferred and preferredTicks > 0 then
		return preferred, preferredTicks
	end
	if best and bestTicks > 0 then
		return best, bestTicks
	end
	return nil, 0
end

local function listUpvalues(fn)
	local readers = {}
	if type(getupvalues) == "function" then
		readers[#readers + 1] = getupvalues
	end
	if type(debug) == "table" and type(debug.getupvalues) == "function" then
		readers[#readers + 1] = debug.getupvalues
	end
	if type(getupvalue) == "function" then
		readers[#readers + 1] = function(f)
			local out = {}
			for i = 1, 64 do
				local ok, name, value = pcall(getupvalue, f, i)
				if not ok or name == nil then
					break
				end
				out[name] = value
				out[i] = value
			end
			return out
		end
	end
	for _, reader in ipairs(readers) do
		local ok, ups = pcall(reader, fn)
		if ok and type(ups) == "table" then
			return ups
		end
	end
	return nil
end

local function listProtos(fn)
	local readers = {}
	if type(getprotos) == "function" then
		readers[#readers + 1] = function(f)
			return getprotos(f)
		end
	end
	if type(getproto) == "function" then
		readers[#readers + 1] = function(f)
			local out = {}
			for i = 1, 64 do
				local ok, proto = pcall(getproto, f, i, true)
				if not ok or proto == nil then
					ok, proto = pcall(getproto, f, i)
				end
				if not ok or proto == nil then
					break
				end
				out[#out + 1] = proto
			end
			return out
		end
	end
	for _, reader in ipairs(readers) do
		local ok, protos = pcall(reader, fn)
		if ok and type(protos) == "table" then
			return protos
		end
	end
	return nil
end

local function considerMap(tbl, maps, depth)
	if type(tbl) ~= "table" or depth > 4 or maps.seen[tbl] then
		return
	end
	maps.seen[tbl] = true
	local commandLike = 0
	local remoteLike = 0
	local hashLike = 0
	for key, value in pairs(tbl) do
		if type(key) == "string" then
			for _, command in ipairs(COMMANDS) do
				if key == command then
					commandLike += 1
					if isHash(value) then
						hashLike += 1
					elseif isRemote(value) then
						local list = maps.direct[key]
						if not list then
							list = {}
							maps.direct[key] = list
						end
						remember(list, value)
					end
				end
			end
		end
		if isHash(key) and isRemote(value) then
			remoteLike += 1
		end
	end
	if commandLike > 0 then
		remember(maps.commandMaps, tbl)
	end
	if remoteLike > 0 then
		remember(maps.remoteMaps, tbl)
	end
	if type(tbl[1]) == "table" then
		considerMap(tbl[1], maps, depth + 1)
	end
	if type(tbl[2]) == "table" then
		considerMap(tbl[2], maps, depth + 1)
	end
end

local function mapsFromFunction(fn)
	local maps = {
		seen = {},
		commandMaps = {},
		remoteMaps = {},
		direct = {},
	}
	local seenFn = {}
	local function visit(func, depth)
		if type(func) ~= "function" or depth > 6 or seenFn[func] then
			return
		end
		seenFn[func] = true
		local ups = listUpvalues(func)
		if type(ups) == "table" then
			for _, value in pairs(ups) do
				if type(value) == "table" then
					considerMap(value, maps, 0)
				elseif type(value) == "function" then
					visit(value, depth + 1)
				end
			end
		end
		local protos = listProtos(func)
		if type(protos) == "table" then
			for _, proto in pairs(protos) do
				if type(proto) == "function" then
					visit(proto, depth + 1)
				elseif type(proto) == "table" then
					for _, child in pairs(proto) do
						if type(child) == "function" then
							visit(child, depth + 1)
						end
					end
				end
			end
		end
	end
	visit(fn, 0)
	return maps
end

local function remotesFromMaps(maps, quiet)
	local found = {}
	local blocked = {}
	local function say(text)
		if not quiet then
			log(text)
		end
	end
	for _, command in ipairs(COMMANDS) do
		local list = {}
		local direct = maps.direct[command]
		if direct then
			for _, inst in ipairs(direct) do
				remember(list, inst)
			end
		end
		for _, map in ipairs(maps.commandMaps) do
			local hash = nil
			pcall(function()
				hash = map[command]
			end)
			if isHash(hash) then
				for _, remotes in ipairs(maps.remoteMaps) do
					local inst = nil
					pcall(function()
						inst = remotes[hash]
					end)
					if isRemote(inst) then
						remember(list, inst)
					end
				end
				for _, child in ipairs(ReplicatedStorage:GetChildren()) do
					if child.Name == hash and isRemote(child) then
						remember(list, child)
					end
				end
			end
		end
		if #list == 1 then
			found[command] = list[1]
			say(string.format("[REMOTE] %s isolato id %s (%s)", command, debugId(list[1]), list[1].ClassName))
		elseif #list > 1 then
			blocked[command] = true
			say("[REMOTE] " .. command .. " ambiguo, non inviato")
		else
			say("[REMOTE] " .. command .. " assente dalla cache")
		end
	end
	return found, blocked
end

local function scanNetwork(library)
	local found = {}
	local blocked = {}
	local network = library and library.Network
	if type(network) ~= "table" then
		return found, blocked
	end
	local maps = { seen = {}, commandMaps = {}, remoteMaps = {}, direct = {} }
	if type(network.Invoke) == "function" then
		local part = mapsFromFunction(network.Invoke)
		for _, map in ipairs(part.commandMaps) do
			remember(maps.commandMaps, map)
		end
		for _, map in ipairs(part.remoteMaps) do
			remember(maps.remoteMaps, map)
		end
		for key, list in pairs(part.direct) do
			maps.direct[key] = list
		end
	end
	if type(network.Fire) == "function" then
		local part = mapsFromFunction(network.Fire)
		for _, map in ipairs(part.commandMaps) do
			remember(maps.commandMaps, map)
		end
		for _, map in ipairs(part.remoteMaps) do
			remember(maps.remoteMaps, map)
		end
		for key, list in pairs(part.direct) do
			local dest = maps.direct[key]
			if not dest then
				maps.direct[key] = list
			else
				for _, inst in ipairs(list) do
					remember(dest, inst)
				end
			end
		end
	end
	found, blocked = remotesFromMaps(maps, false)
	return found, blocked
end

local function learnFromPlay(library, found, blocked)
	local pending = false
	for _, command in ipairs(COMMANDS) do
		if not found[command] and not blocked[command] then
			pending = true
		end
	end
	if not pending then
		return
	end
	log("[REMOTE] Cache vuota. Hai 25s: cambia un'impostazione e un toggle Auto Hatch/Delete.")
	local deadline = os.clock() + LEARN_SECONDS
	while running and pending and os.clock() < deadline do
		setStatus("Toggle impostazione / auto hatch")
		task.wait(0.4)
		local seen, seenBlocked = scanNetwork(library)
		pending = false
		for _, command in ipairs(COMMANDS) do
			if blocked[command] or seenBlocked[command] then
				if seenBlocked[command] and not blocked[command] then
					blocked[command] = true
					log("[REMOTE] " .. command .. " ambiguo dopo il toggle")
				end
			elseif seen[command] and not found[command] then
				found[command] = seen[command]
				log(string.format("[REMOTE] %s imparato id %s (%s)", command, debugId(seen[command]), seen[command].ClassName))
			elseif not found[command] then
				pending = true
			end
		end
	end
	for _, command in ipairs(COMMANDS) do
		if not found[command] and not blocked[command] then
			log("[REMOTE] " .. command .. " mai chiamato dal gioco")
		end
	end
end

local function argsMatch(expect, ...)
	if select("#", ...) ~= 1 then
		return false
	end
	local first = ...
	if type(expect) == "table" then
		return first == expect
	end
	return type(first) == "number" and first == 0 and expect == 0
end

local function namecall(self, ...)
	local method = nil
	if type(getnamecallmethod) == "function" then
		method = getnamecallmethod()
	end
	local state = root.__DeltaSaveFreeze
	if state and state.armed and (method == "InvokeServer" or method == "FireServer") and argsMatch(state.expect, ...) then
		local owned = false
		if state.remote then
			owned = self == state.remote
		elseif state.loose then
			owned = true
		end
		if owned then
			pcall(function()
				state.hits = (state.hits or 0) + 1
				state.method = method
				if state.loose and state.capture == nil then
					state.capture = self
				end
			end)
		elseif state.remote then
			pcall(function()
				state.foreign = (state.foreign or 0) + 1
			end)
		end
	end
	local fwd = state and state.old
	if fwd then
		return fwd(self, ...)
	end
end

local function installHook()
	if bucket.old then
		return true
	end
	if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
		log("[NET] hookmetamethod assente")
		return false
	end
	local callback = namecall
	if type(newcclosure) == "function" then
		local okWrap, wrapped = pcall(newcclosure, namecall)
		if okWrap and type(wrapped) == "function" then
			callback = wrapped
		end
	end
	local okHook, old = pcall(hookmetamethod, game, "__namecall", callback)
	if not okHook or type(old) ~= "function" then
		log("[NET] hook non installato")
		return false
	end
	bucket.old = old
	return true
end

local function sendOnRemote(remote, value)
	bucket.hits = 0
	bucket.foreign = 0
	bucket.expect = value
	bucket.remote = remote
	bucket.capture = nil
	bucket.loose = false
	bucket.method = nil
	bucket.armed = true
	local callOk, callErr = pcall(function()
		if remote:IsA("RemoteFunction") then
			remote:InvokeServer(value)
		else
			remote:FireServer(value)
		end
	end)
	bucket.armed = false
	bucket.remote = nil
	bucket.expect = nil
	return bucket.hits, bucket.foreign, callOk, callErr, bucket.method
end

local function sendLoose(library, command, value)
	bucket.hits = 0
	bucket.foreign = 0
	bucket.expect = value
	bucket.remote = nil
	bucket.capture = nil
	bucket.loose = true
	bucket.method = nil
	bucket.armed = true
	local callOk, callErr = pcall(function()
		if type(library.Network.Invoke) == "function" then
			library.Network.Invoke(command, value)
		elseif type(library.Network.Fire) == "function" then
			library.Network.Fire(command, value)
		else
			error("Network Invoke/Fire assenti")
		end
	end)
	local deadline = os.clock() + 1.2
	while running and bucket.hits == 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	bucket.armed = false
	bucket.loose = false
	bucket.expect = nil
	local capture = bucket.capture
	local method = bucket.method
	bucket.capture = nil
	return bucket.hits, capture, callOk, callErr, method
end

local function readPulse(library, key)
	local save = currentSave(library)
	if type(save) ~= "table" then
		return nil
	end
	local value = save[key]
	if realNumber(value) then
		return value
	end
	return nil
end

local function run()
	setStroke(Color3.fromRGB(70, 110, 170))
	local library, source = resolveLibrary()
	log("[NET] " .. source)
	if type(library) ~= "table" then
		setStatus("Library assente", Color3.fromRGB(255, 160, 120))
		return
	end
	setStatus("Leggo il save")
	local save = currentSave(library)
	if type(save) ~= "table" then
		log("[INFO] Save assente. Test annullato")
		setStatus("Save assente", Color3.fromRGB(255, 160, 120))
		return
	end
	local clocks = collectClocks(save)
	log(string.format("[SAVE] candidati clock %d", #clocks))
	if #clocks < 1 then
		log("[INFO] Nessun campo tempo nel save. Test annullato")
		setStatus("Nessun clock", Color3.fromRGB(255, 200, 120))
		return
	end
	log("[CLOCK] Confronto di 6 secondi, un campione ogni secondo")
	local report, why = observeClocks(library, clocks)
	if not running or why == "stop" then
		return
	end
	if why == "errore" or type(report) ~= "table" then
		log("[INFO] Lettura clock interrotta")
		setStatus("Clock illeggibile", Color3.fromRGB(255, 160, 120))
		return
	end
	for _, item in ipairs(clocks) do
		local ticks = report.changes[item.key] or 0
		local note = "fermo"
		if item.key == "FreeGiftsTime" and ticks > 0 then
			note = "polso preferito"
		elseif ticks > 0 then
			note = "si muove"
		elseif item.key == "LastSaveTimestamp" then
			note = "chiave save, non usata come polso se ferma"
		end
		log(string.format(
			"[CLOCK] %s | %s -> %s | scatti %d | %s",
			item.key,
			tostring(report.first[item.key]),
			tostring(report.last[item.key]),
			ticks,
			note
		))
	end
	local pulse, pulseTicks = pickPulse(clocks, report)
	if not pulse then
		log("[INFO] Nessun campo si muove. Senza polso non posso misurare un blocco. Verdetto non emesso")
		setStatus("Nessun polso", Color3.fromRGB(255, 200, 120))
		return
	end
	local period = estimatePeriod(report.stamps[pulse.key]) or (WATCH_SECONDS / math.max(pulseTicks, 1))
	period = math.max(1, math.min(period, 20))
	local holdStep = math.max(2, math.ceil(period + 1))
	log(string.format(
		"[CLOCK] Polso: %s | valore %s | scatti %d | periodo ~%.1fs | check ogni %ds",
		pulse.key,
		tostring(report.last[pulse.key]),
		pulseTicks,
		period,
		holdStep
	))
	setStatus("Cerco i remote")
	local remotes, blocked = scanNetwork(library)
	learnFromPlay(library, remotes, blocked)
	if not running then
		return
	end
	if not installHook() then
		setStatus("Hook assente", Color3.fromRGB(255, 160, 120))
		return
	end
	local confirmed = 0
	for _, command in ipairs(COMMANDS) do
		if blocked[command] then
			continue
		end
		for _, label in ipairs(PAYLOADS) do
			if not running then
				return
			end
			setStatus(command .. " " .. label)
			local value = payloadValue(label)
			local remote = remotes[command]
			local hits = 0
			local foreign = 0
			local callOk = true
			local callErr = nil
			local method = nil
			if remote then
				hits, foreign, callOk, callErr, method = sendOnRemote(remote, value)
			else
				local capture
				hits, capture, callOk, callErr, method = sendLoose(library, command, value)
				foreign = 0
				if hits > 0 and typeof(capture) == "Instance" then
					remotes[command] = capture
					log(string.format("[REMOTE] %s visto in Network id %s (%s)", command, debugId(capture), capture.ClassName))
				end
			end
			if not callOk then
				log("[NET] invio fallito: " .. tostring(callErr))
			end
			if hits >= 1 and foreign == 0 then
				confirmed += 1
				log(string.format(
					"[NET] %s | Payload: %s | confermato via %s",
					command,
					label,
					method or (remote and remote.ClassName) or "Network"
				))
			else
				local detail = (hits == 0 and foreign == 0) and "nessun invio" or "non isolato"
				log(string.format("[NET] %s | Payload: %s | %s", command, label, detail))
			end
			if not waitSeconds(0.25) then
				return
			end
		end
	end
	if confirmed < 1 then
		log("[INFO] Nessun payload uscito. Senza pacchetto non posso giudicare il save. Verdetto non emesso")
		setStatus("Pacchetto non uscito", Color3.fromRGB(255, 180, 90))
		return
	end
	local previousValue = readPulse(library, pulse.key)
	if not realNumber(previousValue) then
		log("[INFO] Polso illeggibile dopo i payload. Verdetto non emesso")
		setStatus("Polso illeggibile", Color3.fromRGB(255, 160, 120))
		return
	end
	local holdCount = 0
	local sawMove = false
	for index = 1, CHECKS do
		setStatus(string.format("Check %d/%d", index, CHECKS))
		if not waitSeconds(holdStep) then
			return
		end
		local now = readPulse(library, pulse.key)
		if not realNumber(now) then
			log(string.format("[SYNC] Check %d: illeggibile | holdCount=%d", index, holdCount))
		elseif now == previousValue then
			holdCount += 1
			log(string.format("[SYNC] Check %d: fermo %s | holdCount=%d", index, tostring(now), holdCount))
		else
			sawMove = true
			holdCount = 0
			log(string.format("[SYNC] Check %d: avanza %s -> %s", index, tostring(previousValue), tostring(now)))
			previousValue = now
		end
		if holdCount >= 3 then
			log("[SAVE FROZEN] Il polso del server si e fermato per 3 cicli dopo il payload. Salvataggio interrotto.")
			setStatus("SAVE FROZEN", Color3.fromRGB(255, 90, 90))
			setStroke(Color3.fromRGB(210, 50, 50))
			return
		end
	end
	if sawMove then
		log("[SYNC] Il polso continua. Nessuna interruzione del salvataggio misurata.")
	else
		log("[SYNC] Non ci sono tre fermate di fila. Nessuna interruzione del salvataggio misurata.")
	end
	setStatus("Save vivo", Color3.fromRGB(120, 220, 140))
	setStroke(Color3.fromRGB(40, 150, 80))
end

local function setRunning(state)
	if state == running then
		return
	end
	generation += 1
	local token = generation
	running = state
	bucket.running = state
	if startBtn then
		startBtn.Text = running and "STOP" or "START"
		startBtn.BackgroundColor3 = running and Color3.fromRGB(150, 48, 48) or Color3.fromRGB(32, 130, 78)
	end
	if running then
		setStatus("Test", Color3.fromRGB(220, 228, 240))
		setStroke(Color3.fromRGB(70, 110, 170))
		task.spawn(function()
			local ok, err = pcall(run)
			if token ~= generation then
				return
			end
			if not ok then
				log("[ERRORE] " .. tostring(err))
				setStatus("Errore", Color3.fromRGB(255, 120, 120))
			end
			running = false
			bucket.running = false
			bucket.armed = false
			bucket.remote = nil
			if startBtn then
				startBtn.Text = "START"
				startBtn.BackgroundColor3 = Color3.fromRGB(32, 130, 78)
			end
		end)
	else
		bucket.armed = false
		setStatus("Stop", Color3.fromRGB(220, 228, 240))
		setStroke(Color3.fromRGB(90, 98, 120))
		log("[GUI] STOP")
	end
end

local parentGui = LocalPlayer:WaitForChild("PlayerGui")
if type(gethui) == "function" then
	local ok, guiRoot = pcall(gethui)
	if ok and typeof(guiRoot) == "Instance" then
		parentGui = guiRoot
	end
end

local existing = parentGui:FindFirstChild("DeltaSaveFreeze")
if existing then
	pcall(function()
		existing:Destroy()
	end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "DeltaSaveFreeze"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1006
gui.Parent = parentGui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromScale(0.94, 0.7)
frame.Position = UDim2.fromScale(0.03, 0.03)
frame.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
frame.Active = true
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

frameStroke = Instance.new("UIStroke")
frameStroke.Thickness = 2
frameStroke.Color = Color3.fromRGB(70, 110, 170)
frameStroke.Parent = frame

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 8)
title.Size = UDim2.new(1, -24, 0, 22)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(236, 240, 248)
title.Text = "SAVE FREEZE"
title.Parent = frame

startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.fromOffset(96, 34)
startBtn.Position = UDim2.fromOffset(12, 36)
startBtn.BackgroundColor3 = Color3.fromRGB(32, 130, 78)
startBtn.Text = "START"
startBtn.TextColor3 = Color3.new(1, 1, 1)
startBtn.Font = Enum.Font.GothamBold
startBtn.TextSize = 14
startBtn.AutoButtonColor = true
startBtn.Parent = frame

local startCorner = Instance.new("UICorner")
startCorner.CornerRadius = UDim.new(0, 7)
startCorner.Parent = startBtn

copyBtn = Instance.new("TextButton")
copyBtn.Size = UDim2.fromOffset(118, 34)
copyBtn.Position = UDim2.fromOffset(116, 36)
copyBtn.BackgroundColor3 = Color3.fromRGB(36, 92, 158)
copyBtn.Text = "COPIA LOG"
copyBtn.TextColor3 = Color3.new(1, 1, 1)
copyBtn.Font = Enum.Font.GothamBold
copyBtn.TextSize = 13
copyBtn.AutoButtonColor = true
copyBtn.Parent = frame

local copyCorner = Instance.new("UICorner")
copyCorner.CornerRadius = UDim.new(0, 7)
copyCorner.Parent = copyBtn

statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -250, 0, 34)
statusLabel.Position = UDim2.fromOffset(244, 36)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Pronto"
statusLabel.TextColor3 = Color3.fromRGB(220, 228, 240)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 14
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.Parent = frame

logBox = Instance.new("TextBox")
logBox.Name = "LogText"
logBox.Position = UDim2.fromOffset(12, 80)
logBox.Size = UDim2.new(1, -24, 1, -92)
logBox.BackgroundColor3 = Color3.fromRGB(7, 9, 14)
logBox.TextColor3 = Color3.fromRGB(226, 232, 240)
logBox.Font = Enum.Font.Code
logBox.TextSize = 14
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.TextWrapped = true
logBox.ClearTextOnFocus = false
logBox.TextEditable = false
logBox.MultiLine = true
logBox.Active = true
logBox.Text = ""
logBox.Parent = frame

local logCorner = Instance.new("UICorner")
logCorner.CornerRadius = UDim.new(0, 8)
logCorner.Parent = logBox

startBtn.MouseButton1Click:Connect(function()
	setRunning(not running)
end)
copyBtn.MouseButton1Click:Connect(copyLogs)
logBox.FocusLost:Connect(function()
	logBox.Text = table.concat(lines, "\n")
end)

log("[GUI] Pronto. 6s di polso, toggle UI se serve, poi 0 e {} sui toggle. Solo verdetto save.")
log("[NOTA] Nessuno scambio pet in questo test.")
