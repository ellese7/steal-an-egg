-- Delta only. Tier A/B save-freeze probe for psx-stayso.
-- Dual pulse: LastSaveTimestamp + SaveVersion must both stall for 3 cycles.
-- No trade, booth, mail, daycare. No new files; this is the stayso test script.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	LocalPlayer = Players.PlayerAdded:Wait()
end

-- Priority: Open Gift -> pet machines -> positions/orbs.
local COMMANDS = {
	{ name = "Open Gift", kind = "invoke", shape = "gift" },
	{ name = "Fuse Pets", kind = "invoke", shape = "uids" },
	{ name = "Use Golden Machine", kind = "invoke", shape = "uids" },
	{ name = "Use Rainbow Machine", kind = "invoke", shape = "uids" },
	{ name = "Enchant Pets", kind = "invoke", shape = "enchant" },
	{ name = "Delete Several Pets", kind = "invoke", shape = "delete" },
	{ name = "Pet Positions", kind = "fire", shape = "positions" },
	{ name = "Claim Orbs", kind = "fire", shape = "orbs" },
	{ name = "Collect Lootbag", kind = "fire", shape = "lootbag" },
}

local PAYLOAD_STEPS = { "valid_1_uid", "{0}", "{}", "{nil}", "string" }
local CHECKS = 3
local WATCH_SECONDS = 6
local SAMPLE_STEP = 1
local HOLD_STEP = 4
local LEARN_SECONDS = 20
local MAX_LINES = 600

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
local saveCache = nil

local function paintLogs()
	if not logBox then
		return
	end
	-- Never call IsFocused: Delta can throw "lacking capability Plugin".
	pcall(function()
		logBox.Text = table.concat(lines, "\n")
	end)
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
		pcall(function()
			statusLabel.Text = tostring(text)
			if color then
				statusLabel.TextColor3 = color
			end
		end)
	end
end

local function setStroke(color)
	if frameStroke then
		pcall(function()
			frameStroke.Color = color
		end)
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

local function classNameOf(inst)
	if typeof(inst) ~= "Instance" then
		return nil
	end
	local ok, name = pcall(function()
		return inst.ClassName
	end)
	if ok then
		return name
	end
	return nil
end

local function isRemote(inst)
	local className = classNameOf(inst)
	return className == "RemoteEvent" or className == "RemoteFunction"
end

local function debugId(inst)
	if type(getdebugid) == "function" then
		local ok, id = pcall(getdebugid, inst)
		if ok then
			return tostring(id)
		end
	end
	return classNameOf(inst) or "?"
end

local function remember(list, value)
	for _, item in ipairs(list) do
		if item == value then
			return
		end
	end
	list[#list + 1] = value
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
		pcall(function()
			logBox:CaptureFocus()
			logBox.CursorPosition = #logBox.Text + 1
			logBox.SelectionStart = 1
		end)
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
	if viaFramework and classNameOf(viaFramework) == "ModuleScript" then
		local ok, library = pcall(require, viaFramework)
		if ok and type(library) == "table" then
			local started = os.clock()
			while running and library.Loaded ~= true and os.clock() - started < 8 do
				task.wait(0.1)
			end
			if type(library.Network) == "table" then
				return library, "Framework.Library"
			end
		end
	end
	local moduleScript = ReplicatedStorage:FindFirstChild("Library")
	if moduleScript and classNameOf(moduleScript) == "ModuleScript" then
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

local function bindSave(library)
	saveCache = nil
	if type(library) == "table" and type(library.Save) == "table" and type(library.Save.Get) == "function" then
		local ok, save = pcall(library.Save.Get)
		if ok and type(save) == "table" then
			saveCache = save
			return true
		end
	end
	return false
end

local function currentSave(library)
	if type(saveCache) == "table" then
		return saveCache
	end
	if type(library) == "table" and type(library.Save) == "table" and type(library.Save.Get) == "function" then
		local ok, save = pcall(library.Save.Get)
		if ok and type(save) == "table" then
			saveCache = save
			return save
		end
	end
	return nil
end

local function readDual(library)
	local save = currentSave(library)
	if type(save) ~= "table" then
		return nil, nil
	end
	local a = save.LastSaveTimestamp
	local b = save.SaveVersion
	if realNumber(a) and realNumber(b) then
		return a, b
	end
	return nil, nil
end

local function pickOwnedUid(library)
	local save = currentSave(library)
	if type(save) ~= "table" or type(save.Pets) ~= "table" then
		return nil, nil
	end
	for _, pet in pairs(save.Pets) do
		if type(pet) == "table" and type(pet.uid) == "string" and #pet.uid > 0 then
			return pet.uid, tostring(pet.id)
		end
	end
	return nil, nil
end

local function buildPayload(shape, step, uid, petId)
	if step == "valid_1_uid" then
		if shape == "delete" then
			return nil, "skip_valid_delete"
		end
		if not uid then
			return nil, "no_uid"
		end
		if shape == "gift" then
			return { { uid }, petId or tostring(uid), false, false }, nil
		end
		if shape == "enchant" then
			return { { uid }, false }, nil
		end
		if shape == "positions" then
			return { { [uid] = Vector3.new(0, 0, 0) } }, nil
		end
		if shape == "orbs" then
			return { { "orb_probe_1" } }, nil
		end
		if shape == "lootbag" then
			return { "loot_probe_1", Vector3.new(0, 0, 0) }, nil
		end
		return { { uid } }, nil
	end
	if step == "{0}" then
		if shape == "lootbag" then
			return { 0, Vector3.new(0, 0, 0) }, nil
		end
		if shape == "gift" then
			return { { 0 }, "0", false, false }, nil
		end
		if shape == "enchant" then
			return { { 0 }, false }, nil
		end
		return { { 0 } }, nil
	end
	if step == "{}" then
		if shape == "lootbag" then
			return { {}, Vector3.new(0, 0, 0) }, nil
		end
		if shape == "gift" then
			return { {}, "0", false, false }, nil
		end
		if shape == "enchant" then
			return { {}, false }, nil
		end
		return { {} }, nil
	end
	if step == "{nil}" then
		if shape == "lootbag" then
			return { nil, Vector3.new(0, 0, 0) }, nil
		end
		if shape == "gift" then
			return { { nil }, "0", false, false }, nil
		end
		if shape == "enchant" then
			return { { nil }, false }, nil
		end
		return { { nil } }, nil
	end
	if step == "string" then
		if shape == "lootbag" then
			return { "invalid_type", Vector3.new(0, 0, 0) }, nil
		end
		if shape == "gift" then
			return { "invalid_type", "0", false, false }, nil
		end
		if shape == "enchant" then
			return { "invalid_type", false }, nil
		end
		return { "invalid_type" }, nil
	end
	return nil, "unknown_step"
end

local function observeDualBaseline(library)
	local firstA, firstB = readDual(library)
	if not (realNumber(firstA) and realNumber(firstB)) then
		return nil, "missing"
	end
	local lastA, lastB = firstA, firstB
	local ticksA, ticksB = 0, 0
	local deadline = os.clock() + WATCH_SECONDS
	while running and os.clock() < deadline do
		if not waitSeconds(SAMPLE_STEP) then
			return nil, "stop"
		end
		local nowA, nowB = readDual(library)
		if not (realNumber(nowA) and realNumber(nowB)) then
			return nil, "errore"
		end
		if nowA ~= lastA then
			ticksA += 1
			lastA = nowA
		end
		if nowB ~= lastB then
			ticksB += 1
			lastB = nowB
		end
	end
	return {
		firstA = firstA,
		firstB = firstB,
		lastA = lastA,
		lastB = lastB,
		ticksA = ticksA,
		ticksB = ticksB,
	}, nil
end

local function holdDual(library)
	local prevA, prevB = readDual(library)
	if not (realNumber(prevA) and realNumber(prevB)) then
		log("[INFO] Polso duale illeggibile. Skip check")
		return false
	end
	local holdCount = 0
	for index = 1, CHECKS do
		setStatus(string.format("Hold %d/%d", index, CHECKS))
		if not waitSeconds(HOLD_STEP) then
			return false
		end
		local nowA, nowB = readDual(library)
		if not (realNumber(nowA) and realNumber(nowB)) then
			log(string.format("[SYNC] Check %d: illeggibile | holdCount=%d", index, holdCount))
			holdCount = 0
		elseif nowA == prevA and nowB == prevB then
			holdCount += 1
			log(string.format(
				"[SYNC] Check %d: entrambi fermi | LastSaveTimestamp=%s SaveVersion=%s | holdCount=%d",
				index,
				tostring(nowA),
				tostring(nowB),
				holdCount
			))
		else
			holdCount = 0
			log(string.format(
				"[SYNC] Check %d: avanza | LastSaveTimestamp %s -> %s | SaveVersion %s -> %s",
				index,
				tostring(prevA),
				tostring(nowA),
				tostring(prevB),
				tostring(nowB)
			))
			prevA, prevB = nowA, nowB
		end
		if holdCount >= 3 then
			return true
		end
	end
	return false
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
		readers[#readers + 1] = getprotos
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

local function commandNames()
	local names = {}
	for _, command in ipairs(COMMANDS) do
		names[#names + 1] = command.name
	end
	return names
end

local function considerMap(tbl, maps, depth, names)
	if type(tbl) ~= "table" or depth > 4 or maps.seen[tbl] then
		return
	end
	maps.seen[tbl] = true
	local commandLike = 0
	local remoteLike = 0
	for key, value in pairs(tbl) do
		if type(key) == "string" then
			for _, name in ipairs(names) do
				if key == name then
					commandLike += 1
					if isRemote(value) then
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
		considerMap(tbl[1], maps, depth + 1, names)
	end
	if type(tbl[2]) == "table" then
		considerMap(tbl[2], maps, depth + 1, names)
	end
end

local function mapsFromFunction(fn, names)
	local maps = { seen = {}, commandMaps = {}, remoteMaps = {}, direct = {} }
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
					considerMap(value, maps, 0, names)
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

local function remotesFromMaps(maps, names, quiet)
	local found = {}
	local blocked = {}
	local function say(text)
		if not quiet then
			log(text)
		end
	end
	for _, name in ipairs(names) do
		local list = {}
		local direct = maps.direct[name]
		if direct then
			for _, inst in ipairs(direct) do
				remember(list, inst)
			end
		end
		for _, map in ipairs(maps.commandMaps) do
			local hash = nil
			pcall(function()
				hash = map[name]
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
			found[name] = list[1]
			say(string.format("[REMOTE] %s isolato id %s (%s)", name, debugId(list[1]), list[1].ClassName))
		elseif #list > 1 then
			blocked[name] = true
			say("[REMOTE] " .. name .. " ambiguo")
		end
	end
	return found, blocked
end

local function scanNetwork(library, quiet)
	local names = commandNames()
	local found = {}
	local blocked = {}
	local network = library and library.Network
	if type(network) ~= "table" then
		return found, blocked
	end
	local maps = { seen = {}, commandMaps = {}, remoteMaps = {}, direct = {} }
	for _, fnName in ipairs({ "Invoke", "Fire" }) do
		local fn = network[fnName]
		if type(fn) == "function" then
			local part = mapsFromFunction(fn, names)
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
	end
	found, blocked = remotesFromMaps(maps, names, quiet)
	return found, blocked
end

local function learnFromPlay(library, found, blocked)
	local names = commandNames()
	local pending = false
	for _, name in ipairs(names) do
		if not found[name] and not blocked[name] then
			pending = true
		end
	end
	if not pending then
		return
	end
	log("[REMOTE] Cache incompleta. Hai 20s: apri gift/macchine/orbs in gioco se puoi, altrimenti uso Network diretto.")
	local deadline = os.clock() + LEARN_SECONDS
	while running and pending and os.clock() < deadline do
		setStatus("Usa gift/macchina in gioco")
		task.wait(0.5)
		local seen, seenBlocked = scanNetwork(library, true)
		pending = false
		for _, name in ipairs(names) do
			if blocked[name] or seenBlocked[name] then
				if seenBlocked[name] and not blocked[name] then
					blocked[name] = true
					log("[REMOTE] " .. name .. " ambiguo")
				end
			elseif seen[name] and not found[name] then
				found[name] = seen[name]
				log(string.format("[REMOTE] %s imparato id %s (%s)", name, debugId(seen[name]), seen[name].ClassName))
			elseif not found[name] then
				pending = true
			end
		end
	end
end

local function argsEqual(expectArgs, ...)
	local n = select("#", ...)
	if n ~= #expectArgs then
		return false
	end
	for i = 1, n do
		local got = select(i, ...)
		local want = expectArgs[i]
		if type(want) == "table" then
			if got ~= want then
				return false
			end
		elseif got ~= want then
			return false
		end
	end
	return true
end

local function namecall(self, ...)
	local method = nil
	if type(getnamecallmethod) == "function" then
		method = getnamecallmethod()
	end
	local state = root.__DeltaSaveFreeze
	if state and state.armed and (method == "InvokeServer" or method == "FireServer") and type(state.expect) == "table" and argsEqual(state.expect, ...) then
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

local function sendArgs(remote, args)
	bucket.hits = 0
	bucket.foreign = 0
	bucket.expect = args
	bucket.remote = remote
	bucket.capture = nil
	bucket.loose = false
	bucket.method = nil
	bucket.armed = true
	local callOk, callErr = pcall(function()
		if classNameOf(remote) == "RemoteFunction" then
			remote:InvokeServer(table.unpack(args, 1, #args))
		else
			remote:FireServer(table.unpack(args, 1, #args))
		end
	end)
	bucket.armed = false
	bucket.remote = nil
	bucket.expect = nil
	return bucket.hits, bucket.foreign, callOk, callErr, bucket.method
end

local function sendLoose(library, command, args)
	bucket.hits = 0
	bucket.foreign = 0
	bucket.expect = args
	bucket.remote = nil
	bucket.capture = nil
	bucket.loose = true
	bucket.method = nil
	bucket.armed = true
	local callOk, callErr = pcall(function()
		if command.kind == "invoke" and type(library.Network.Invoke) == "function" then
			library.Network.Invoke(command.name, table.unpack(args, 1, #args))
		elseif type(library.Network.Fire) == "function" then
			library.Network.Fire(command.name, table.unpack(args, 1, #args))
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

local function run()
	setStroke(Color3.fromRGB(70, 110, 170))
	local library, source = resolveLibrary()
	log("[NET] " .. source)
	if type(library) ~= "table" then
		setStatus("Library assente", Color3.fromRGB(255, 160, 120))
		return
	end
	setStatus("Leggo il save")
	if not bindSave(library) then
		log("[INFO] Save assente. Test annullato")
		setStatus("Save assente", Color3.fromRGB(255, 160, 120))
		return
	end
	local uid, petId = pickOwnedUid(library)
	if uid then
		log(string.format("[SAVE] UID di prova: %s | petId %s", uid, tostring(petId)))
	else
		log("[SAVE] Nessun UID pet in inventario. I passi valid_1_uid saranno saltati.")
	end
	log("[CLOCK] Baseline 6s su LastSaveTimestamp + SaveVersion (FreeGiftsTime ignorato per il verdetto)")
	local baseline, why = observeDualBaseline(library)
	if not running or why == "stop" then
		return
	end
	if why == "missing" or why == "errore" or type(baseline) ~= "table" then
		log("[INFO] LastSaveTimestamp/SaveVersion non leggibili. Test annullato")
		setStatus("Polso assente", Color3.fromRGB(255, 160, 120))
		return
	end
	log(string.format(
		"[CLOCK] LastSaveTimestamp %s -> %s | scatti %d",
		tostring(baseline.firstA),
		tostring(baseline.lastA),
		baseline.ticksA
	))
	log(string.format(
		"[CLOCK] SaveVersion %s -> %s | scatti %d",
		tostring(baseline.firstB),
		tostring(baseline.lastB),
		baseline.ticksB
	))
	if baseline.ticksA < 1 and baseline.ticksB < 1 then
		log("[INFO] Entrambi i clock erano gia fermi prima dei payload. Verdetto non emesso")
		setStatus("Polso gia fermo", Color3.fromRGB(255, 200, 120))
		return
	end
	if baseline.ticksA < 1 or baseline.ticksB < 1 then
		log("[CLOCK] Nota: un campo del polso duale non si e mosso in baseline. Serve che entrambi restino fermi dopo il payload.")
	end
	setStatus("Cerco i remote")
	local remotes, blocked = scanNetwork(library, false)
	learnFromPlay(library, remotes, blocked)
	if not running then
		return
	end
	if not installHook() then
		setStatus("Hook assente", Color3.fromRGB(255, 160, 120))
		return
	end
	for _, command in ipairs(COMMANDS) do
		if not running then
			return
		end
		if blocked[command.name] then
			log("[REMOTE] " .. command.name .. " ambiguo, salto")
			continue
		end
		log("[TEST] Comando: " .. command.name)
		for _, step in ipairs(PAYLOAD_STEPS) do
			if not running then
				return
			end
			local args, skip = buildPayload(command.shape, step, uid, petId)
			if skip == "skip_valid_delete" then
				log("[TEST] Delete Several Pets | valid_1_uid saltato (evito cancellazione reale)")
				continue
			end
			if skip == "no_uid" then
				log("[TEST] " .. command.name .. " | " .. step .. " saltato (nessun UID)")
				continue
			end
			if type(args) ~= "table" then
				log("[TEST] " .. command.name .. " | " .. step .. " non costruibile")
				continue
			end
			setStatus(command.name .. " " .. step)
			local remote = remotes[command.name]
			local hits = 0
			local foreign = 0
			local callOk = true
			local callErr = nil
			local method = nil
			if remote then
				hits, foreign, callOk, callErr, method = sendArgs(remote, args)
			else
				local capture
				hits, capture, callOk, callErr, method = sendLoose(library, command, args)
				foreign = 0
				if hits > 0 and typeof(capture) == "Instance" then
					remotes[command.name] = capture
					log(string.format("[REMOTE] %s visto id %s (%s)", command.name, debugId(capture), capture.ClassName))
				end
			end
			if not callOk then
				log("[NET] invio fallito: " .. tostring(callErr))
			end
			if hits >= 1 and foreign == 0 then
				log(string.format("[NET] %s | %s | confermato via %s", command.name, step, method or "Network"))
			else
				local detail = (hits == 0 and foreign == 0) and "nessun invio" or "non isolato"
				log(string.format("[NET] %s | %s | %s", command.name, step, detail))
			end
			if hits < 1 then
				log("[SYNC] Nessun pacchetto uscito, salto hold per questo payload")
				continue
			end
			log(string.format("[SYNC] Hold duale dopo %s | %s", command.name, step))
			local frozen = holdDual(library)
			if frozen then
				log(string.format(
					"[SAVE FROZEN] Trovato il comando che blocca il salvataggio: %s con payload %s",
					command.name,
					step
				))
				setStatus("SAVE FROZEN", Color3.fromRGB(255, 90, 90))
				setStroke(Color3.fromRGB(210, 50, 50))
				return
			end
			if not waitSeconds(0.2) then
				return
			end
		end
	end
	log("[SYNC] Nessun payload ha fermato LastSaveTimestamp e SaveVersion per 3 cicli.")
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
title.Text = "SAVE FREEZE TIER A/B"
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
	pcall(function()
		logBox.Text = table.concat(lines, "\n")
	end)
end)

log("[GUI] Pronto. Polso duale LastSaveTimestamp+SaveVersion. Tier A/B filtrata, no booth/mail/daycare.")
log("[NOTA] Ordine: Open Gift -> macchine -> Pet Positions/Orbs/Lootbag. COPIA LOG o tieni premuto il testo.")
