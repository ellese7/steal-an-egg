-- Delta type check. Finds a live save clock, then runs the hold-count test.
-- A 6s pause is not a freeze if the clock only ticks every 30-60s.
-- The verdict needs three missed periods of the clock that was already moving.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	LocalPlayer = Players.PlayerAdded:Wait()
end

local COMMANDS = { "Toggle Setting", "Update Hoverboard State" }
local PAYLOADS = { "0", "{}" }
local CHECKS = 3
local SAMPLE_STEP = 1
local WATCH_SECONDS = 6
local HOLD_STEP = 4
local MAX_LINES = 500
local NAME_HINTS = { "time", "tick", "save", "sync", "version" }
local EXACT_KEYS = {
	LastSaveTimestamp = true,
	SaveTimestamp = true,
	SaveTime = true,
	_saveClock = true,
}

local root = _G
pcall(function()
	if type(getgenv) == "function" then
		root = getgenv()
	end
end)
local previous = root.__DeltaTypeCheck
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
	useCaller = false,
	old = nil,
}
root.__DeltaTypeCheck = bucket

local running = false
local generation = 0
local copyToken = 0
local statusLabel
local startBtn
local copyBtn
local logBox
local frameStroke
local lines = {}
local saveSlot = nil
local saveHeld = nil
local decoded = {}

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
	if not statusLabel then
		return
	end
	statusLabel.Text = text
	if color then
		statusLabel.TextColor3 = color
	end
end

local function setStroke(color)
	if frameStroke then
		frameStroke.Color = color
	end
end

local function flashCopy(text, color)
	if not copyBtn then
		return
	end
	copyToken += 1
	local token = copyToken
	copyBtn.Text = text
	copyBtn.BackgroundColor3 = color
	task.delay(1.2, function()
		if token ~= copyToken or not copyBtn then
			return
		end
		copyBtn.Text = "COPIA LOG"
		copyBtn.BackgroundColor3 = Color3.fromRGB(36, 92, 158)
	end)
end

local function callClipboard(name, blob)
	local spots = { _G }
	if type(getgenv) == "function" then
		local ok, genv = pcall(getgenv)
		if ok and type(genv) == "table" then
			spots[#spots + 1] = genv
		end
	end
	for _, spot in ipairs(spots) do
		local okRead, writer = pcall(function()
			return spot[name]
		end)
		if okRead and type(writer) == "function" and pcall(writer, blob) then
			return true
		end
	end
	return false
end

local function selectLogs()
	if not logBox then
		return
	end
	logBox.Text = table.concat(lines, "\n")
	task.defer(function()
		if not logBox then
			return
		end
		logBox:CaptureFocus()
		logBox.SelectionStart = 1
		logBox.CursorPosition = #logBox.Text + 1
	end)
end

local function copyLogs()
	local blob = table.concat(lines, "\n")
	local copied = callClipboard("setclipboard", blob) or callClipboard("toclipboard", blob)
	if copied then
		flashCopy("Copiato!", Color3.fromRGB(40, 140, 80))
		return
	end
	flashCopy("Seleziona", Color3.fromRGB(140, 90, 40))
	selectLogs()
end

local function remember(list, value)
	for _, existing in ipairs(list) do
		if existing == value then
			return
		end
	end
	list[#list + 1] = value
end

local function isHash(value)
	return type(value) == "string" and #value == 32 and string.match(value, "^%x+$") ~= nil
end

local function isRemoteEvent(value)
	if typeof(value) ~= "Instance" then
		return false
	end
	local ok, className = pcall(function()
		return value.ClassName
	end)
	return ok and className == "RemoteEvent"
end

local function debugId(inst)
	local ok, id = pcall(function()
		return inst:GetDebugId(0)
	end)
	if ok and type(id) == "string" and id ~= "" then
		return id
	end
	return "?"
end

local function listUpvalues(fn)
	if type(fn) ~= "function" then
		return nil
	end
	local readers = {}
	if type(getupvalues) == "function" then
		readers[#readers + 1] = getupvalues
	end
	if type(debug) == "table" and type(debug.getupvalues) == "function" then
		readers[#readers + 1] = debug.getupvalues
	end
	for _, reader in ipairs(readers) do
		local ok, bulk = pcall(reader, fn)
		if ok and type(bulk) == "table" then
			return bulk
		end
	end
	local one = getupvalue
	if type(one) ~= "function" and type(debug) == "table" then
		one = debug.getupvalue
	end
	if type(one) ~= "function" then
		return nil
	end
	local out = {}
	for index = 1, 60 do
		local ok, a, b = pcall(one, fn, index)
		if not ok or (a == nil and b == nil) then
			break
		end
		if type(a) == "string" and b ~= nil then
			out[index] = b
		else
			out[index] = a
		end
	end
	return out
end

local function listProtos(fn)
	if type(fn) ~= "function" then
		return nil
	end
	local readers = {}
	if type(getprotos) == "function" then
		readers[#readers + 1] = getprotos
	end
	if type(debug) == "table" and type(debug.getprotos) == "function" then
		readers[#readers + 1] = debug.getprotos
	end
	for _, reader in ipairs(readers) do
		local ok, bulk = pcall(reader, fn)
		if ok and type(bulk) == "table" then
			return bulk
		end
	end
	local one = getproto
	if type(one) ~= "function" and type(debug) == "table" then
		one = debug.getproto
	end
	if type(one) ~= "function" then
		return nil
	end
	local out = {}
	for index = 1, 60 do
		local ok, proto = pcall(one, fn, index, true)
		if not ok or type(proto) ~= "function" then
			ok, proto = pcall(one, fn, index)
		end
		if not ok or type(proto) ~= "function" then
			break
		end
		out[index] = proto
	end
	return out
end

local function slotFor(cache, extraPlayer)
	if type(cache) ~= "table" then
		return nil
	end
	local function accept(slot)
		return type(slot) == "table" and type(slot.save) == "table" and type(slot.loaded) == "boolean"
	end
	local targets = {}
	if typeof(LocalPlayer) == "Instance" then
		targets[#targets + 1] = LocalPlayer
	end
	if typeof(extraPlayer) == "Instance" then
		targets[#targets + 1] = extraPlayer
	end
	for _, player in ipairs(targets) do
		local ok, slot = pcall(function()
			return cache[player]
		end)
		if ok and accept(slot) then
			return slot
		end
	end
	return nil
end

local function cacheFromFunction(fn, extraPlayer)
	local found = nil
	local seen = {}
	local function visit(func, depth)
		if found or type(func) ~= "function" or depth > 6 or seen[func] then
			return
		end
		seen[func] = true
		local ups = listUpvalues(func)
		if type(ups) == "table" then
			for _, value in pairs(ups) do
				if slotFor(value, extraPlayer) then
					found = value
					return
				end
			end
			for _, value in pairs(ups) do
				if type(value) == "function" then
					visit(value, depth + 1)
				end
			end
		end
		local protos = listProtos(func)
		if type(protos) == "table" then
			for _, proto in pairs(protos) do
				visit(proto, depth + 1)
			end
		end
	end
	visit(fn, 0)
	return found
end

local function cachesFromGc(extraPlayer)
	local list = {}
	if type(getgc) ~= "function" then
		return list
	end
	local ok, objects = pcall(getgc, true)
	if not ok or type(objects) ~= "table" then
		return list
	end
	local seen = 0
	for _, object in pairs(objects) do
		if not running then
			return list
		end
		seen += 1
		if seen % 400 == 0 then
			setStatus("Save " .. tostring(seen))
			task.wait()
		end
		if slotFor(object, extraPlayer) then
			remember(list, object)
		end
	end
	return list
end

local function fetchSaveOnce(library)
	if type(library) ~= "table" or type(library.Save) ~= "table" or type(library.Save.Get) ~= "function" then
		return nil
	end
	local finished = false
	local save = nil
	task.spawn(function()
		local ok, result = pcall(library.Save.Get)
		if ok and type(result) == "table" then
			save = result
		end
		finished = true
	end)
	local started = os.clock()
	while not finished and os.clock() - started < 2 do
		if not running then
			return nil
		end
		task.wait(0.05)
	end
	return save
end

local function bindSave(library)
	saveSlot = nil
	saveHeld = nil
	local extra = type(library) == "table" and library.LocalPlayer or nil
	if type(library) == "table" and type(library.Save) == "table" then
		for _, fn in pairs(library.Save) do
			if not running then
				return nil
			end
			if type(fn) == "function" then
				local cache = cacheFromFunction(fn, extra)
				local slot = cache and slotFor(cache, extra)
				if slot then
					saveSlot = slot
					return "cache upvalue"
				end
			end
		end
	end
	setStatus("Cerco la cache")
	local caches = cachesFromGc(extra)
	if not running then
		return nil
	end
	local loaded = {}
	for _, cache in ipairs(caches) do
		local slot = slotFor(cache, extra)
		if slot and slot.loaded then
			loaded[#loaded + 1] = slot
		end
	end
	if #loaded == 1 then
		saveSlot = loaded[1]
		return "cache getgc"
	end
	if #caches == 1 then
		local slot = slotFor(caches[1], extra)
		if slot then
			saveSlot = slot
			return "cache getgc"
		end
	end
	local got = fetchSaveOnce(library)
	if type(got) == "table" then
		for _, cache in ipairs(caches) do
			local slot = slotFor(cache, extra)
			if slot and slot.save == got then
				saveSlot = slot
				return "cache getgc"
			end
		end
		saveHeld = got
		return "Get una volta"
	end
	return nil
end

local function currentSave()
	if type(saveSlot) == "table" and type(saveSlot.save) == "table" then
		return saveSlot.save
	end
	if type(saveHeld) == "table" then
		return saveHeld
	end
	return nil
end

local function appendPath(prefix, key)
	local kind = type(key)
	if kind ~= "string" and kind ~= "number" then
		return nil
	end
	local body = kind .. ":" .. tostring(key)
	if #body > 9999 then
		return nil
	end
	return prefix .. string.format("%04d", #body) .. body
end

local function walkPath(path, visit)
	local index = 1
	while index <= #path do
		local size = tonumber(string.sub(path, index, index + 3))
		if not size or size < 1 then
			return false
		end
		local body = string.sub(path, index + 4, index + 3 + size)
		if #body ~= size then
			return false
		end
		local kind, raw = string.match(body, "^(%a+):(.*)$")
		if kind ~= "string" and kind ~= "number" then
			return false
		end
		local key = raw
		if kind == "number" then
			key = tonumber(raw)
			if key == nil then
				return false
			end
		end
		if visit(key) == false then
			return false
		end
		index += 4 + size
	end
	return true
end

local function showPath(path)
	local parts = {}
	local ok = walkPath(path, function(key)
		parts[#parts + 1] = tostring(key)
	end)
	if not ok then
		return tostring(path)
	end
	return table.concat(parts, ".")
end

local function realNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function nameHint(key)
	local text = string.lower(tostring(key))
	for _, hint in ipairs(NAME_HINTS) do
		if string.find(text, hint, 1, true) then
			return true
		end
	end
	return false
end

local function looksLikeStamp(value)
	if not realNumber(value) then
		return false
	end
	local whole = math.abs(value)
	return (whole >= 1000000000 and whole < 10000000000) or (whole >= 1000000000000 and whole < 10000000000000)
end

local function keysOf(path)
	local cached = decoded[path]
	if cached then
		return cached
	end
	local keys = {}
	local ok = walkPath(path, function(key)
		keys[#keys + 1] = key
	end)
	if not ok then
		return nil
	end
	decoded[path] = keys
	return keys
end

local function readKeys(save, keys)
	local node = save
	for _, key in ipairs(keys) do
		if type(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	if realNumber(node) then
		return node
	end
	return nil
end

local function readSaved(path)
	local save = currentSave()
	local keys = keysOf(path)
	if type(save) ~= "table" or not keys then
		return nil
	end
	return readKeys(save, keys)
end

local function waitSeconds(seconds)
	local deadline = os.clock() + seconds
	while running and os.clock() < deadline do
		task.wait(0.1)
	end
	return running
end

local function collectClocks()
	decoded = {}
	local found = {}
	local hidden = 0
	local save = currentSave()
	if type(save) ~= "table" then
		return found, hidden, false
	end
	local seen = {}
	local steps = 0
	local function collect(node, prefix, depth)
		if not running or type(node) ~= "table" or seen[node] then
			return
		end
		seen[node] = true
		steps += 1
		if steps % 200 == 0 then
			setStatus("Clock " .. tostring(#found))
			task.wait()
		end
		for key, value in pairs(node) do
			if not running then
				return
			end
			local path = appendPath(prefix, key)
			if path and realNumber(value) then
				local named = nameHint(key)
				local exact = type(key) == "string" and EXACT_KEYS[key] == true
				if exact or named or (looksLikeStamp(value) and depth <= 3) then
					found[#found + 1] = {
						path = path,
						named = named,
						exact = exact,
						value = value,
					}
				elseif looksLikeStamp(value) then
					hidden += 1
				end
			elseif path and type(value) == "table" then
				collect(value, path, depth + 1)
			end
		end
	end
	local ok = pcall(collect, save, "", 0)
	if not ok then
		return {}, hidden, false
	end
	return found, hidden, true
end

local function readGroup(list)
	local save = currentSave()
	if type(save) ~= "table" then
		return nil
	end
	local out = {}
	for index, item in ipairs(list) do
		if not running then
			return nil
		end
		if index % 400 == 0 then
			task.wait()
			save = currentSave() or save
		end
		local keys = keysOf(item.path)
		if keys then
			local value = readKeys(save, keys)
			if value ~= nil then
				out[item.path] = value
			end
		end
	end
	return out
end

local function observeClocks(list)
	local first = readGroup(list)
	if not first then
		return nil, running and "errore" or "stop"
	end
	local changes = {}
	local prev = first
	local deadline = os.clock() + WATCH_SECONDS
	while running and os.clock() < deadline do
		local left = math.max(0, math.ceil(deadline - os.clock()))
		setStatus("Misuro " .. tostring(left) .. "s")
		if not waitSeconds(SAMPLE_STEP) then
			return nil, "stop"
		end
		local now = readGroup(list)
		if not now then
			return nil, running and "errore" or "stop"
		end
		for _, item in ipairs(list) do
			local before = prev[item.path]
			local value = now[item.path]
			if realNumber(before) and realNumber(value) and before ~= value then
				changes[item.path] = (changes[item.path] or 0) + 1
			end
		end
		prev = now
	end
	if not running then
		return nil, "stop"
	end
	return {
		first = first,
		last = prev,
		changes = changes,
	}, nil
end

local function pickClock(list)
	local order = { "LastSaveTimestamp", "SaveTimestamp", "SaveTime", "_saveClock" }
	for _, name in ipairs(order) do
		for _, item in ipairs(list) do
			if item.exact then
				local leaf = nil
				walkPath(item.path, function(key)
					leaf = tostring(key)
				end)
				if leaf == name then
					return item
				end
			end
		end
	end
	for _, item in ipairs(list) do
		if item.exact then
			return item
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
	local channelLike = 0
	local function wanted(key)
		for _, name in ipairs(COMMANDS) do
			if key == name then
				return true
			end
		end
		return false
	end
	local ok = pcall(function()
		for key, value in pairs(tbl) do
			if type(key) == "string" and isHash(value) then
				commandLike += 1
			elseif isHash(key) and isRemoteEvent(value) then
				remoteLike += 1
			elseif (key == 1 or key == 2) and type(value) == "table" then
				channelLike += 1
			elseif wanted(key) and isRemoteEvent(value) then
				local direct = maps.direct[key]
				if not direct then
					direct = {}
					maps.direct[key] = direct
				end
				remember(direct, value)
			end
		end
	end)
	if not ok then
		return
	end
	if commandLike > 0 then
		remember(maps.commandMaps, tbl)
	end
	if remoteLike > 0 then
		remember(maps.remoteMaps, tbl)
	end
	if channelLike > 0 then
		if type(tbl[1]) == "table" then
			considerMap(tbl[1], maps, depth + 1)
		end
		if type(tbl[2]) == "table" then
			considerMap(tbl[2], maps, depth + 1)
		end
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
				visit(proto, depth + 1)
			end
		end
	end
	visit(fn, 0)
	return maps
end

local function remotesFromMaps(maps)
	local found = {}
	local blocked = {}
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
					if isRemoteEvent(inst) then
						remember(list, inst)
					end
				end
			end
		end
		if #list == 1 then
			found[command] = list[1]
			log(string.format("[REMOTE] %s isolato da upvalue id %s", command, debugId(list[1])))
		elseif #list > 1 then
			blocked[command] = true
			log("[REMOTE] " .. command .. " ambiguo negli upvalue, payload non inviato")
		else
			local keySeen = false
			local hashCount = 0
			for _, map in ipairs(maps.commandMaps) do
				local hash = nil
				pcall(function()
					hash = map[command]
				end)
				if hash ~= nil then
					keySeen = true
					if isHash(hash) then
						hashCount += 1
					end
				end
			end
			local reason = "chiave assente nella cache: il comando non e stato usato in questa sessione"
			if #maps.commandMaps == 0 then
				reason = "nessuna mappa comando negli upvalue di Fire"
			elseif keySeen and hashCount == 0 then
				reason = "chiave presente ma il valore non e un hash"
			elseif hashCount > 0 then
				reason = "hash trovato ma nessuna istanza RemoteEvent"
			end
			log(string.format(
				"[REMOTE] %s upvalue: %s | mappe comando %d | mappe remote %d",
				command,
				reason,
				#maps.commandMaps,
				#maps.remoteMaps
			))
		end
	end
	return found, blocked
end

local function remotesFromGc(found, blocked)
	if type(getgc) ~= "function" then
		return
	end
	local missing = false
	for _, command in ipairs(COMMANDS) do
		if not found[command] and not blocked[command] then
			missing = true
		end
	end
	if not missing then
		return
	end
	local ok, objects = pcall(getgc, true)
	if not ok or type(objects) ~= "table" then
		return
	end
	local commandHashes = {}
	local hashRemote = {}
	local direct = {}
	local seen = 0
	local function wanted(key)
		if found[key] or blocked[key] then
			return false
		end
		for _, name in ipairs(COMMANDS) do
			if key == name then
				return true
			end
		end
		return false
	end
	for _, object in pairs(objects) do
		if not running then
			return
		end
		seen += 1
		if seen % 400 == 0 then
			setStatus("Remote " .. tostring(seen))
			task.wait()
		end
		if type(object) == "table" then
			pcall(function()
				for key, value in pairs(object) do
					if wanted(key) and isHash(value) then
						local hashes = commandHashes[key]
						if not hashes then
							hashes = {}
							commandHashes[key] = hashes
						end
						remember(hashes, value)
					elseif isHash(key) and isRemoteEvent(value) then
						hashRemote[key] = value
					elseif wanted(key) and isRemoteEvent(value) then
						local list = direct[key]
						if not list then
							list = {}
							direct[key] = list
						end
						remember(list, value)
					end
				end
			end)
		end
	end
	for _, command in ipairs(COMMANDS) do
		if not found[command] and not blocked[command] then
			local list = direct[command] or {}
			local hashes = commandHashes[command]
			if hashes then
				for _, hash in ipairs(hashes) do
					if hashRemote[hash] then
						remember(list, hashRemote[hash])
					end
				end
			end
			if #list == 1 then
				found[command] = list[1]
				log(string.format("[REMOTE] %s isolato da getgc id %s", command, debugId(list[1])))
			elseif #list > 1 then
				blocked[command] = true
				log("[REMOTE] " .. command .. " ambiguo in getgc, payload non inviato")
			else
				local hashCount = hashes and #hashes or 0
				log(string.format("[REMOTE] %s getgc: chiave assente o senza istanza | hash trovati %d", command, hashCount))
			end
		end
	end
end

local function findRemotes(library)
	local found = {}
	local blocked = {}
	if type(library) == "table" and type(library.Network) == "table" and type(library.Network.Fire) == "function" then
		local maps = mapsFromFunction(library.Network.Fire)
		found, blocked = remotesFromMaps(maps)
	end
	remotesFromGc(found, blocked)
	return found, blocked
end

local function ours()
	if not bucket.useCaller then
		return true
	end
	if type(checkcaller) ~= "function" then
		return true
	end
	local ok, yes = pcall(checkcaller)
	return ok and yes == true
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
	local state = root.__DeltaTypeCheck
	if state and state.armed and method == "FireServer" and argsMatch(state.expect, ...) then
		local owned = false
		if state.remote then
			owned = self == state.remote
		elseif state.loose then
			owned = true
		end
		if owned then
			pcall(function()
				if state.remote and not ours() then
					state.foreign = (state.foreign or 0) + 1
					return
				end
				state.hits = (state.hits or 0) + 1
				if state.loose and state.capture == nil then
					state.capture = self
				end
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
		log("[NET] hookmetamethod assente, il pacchetto non e verificabile")
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

local function readConstants(fn)
	local readers = {}
	if type(getconstants) == "function" then
		readers[#readers + 1] = getconstants
	end
	if type(debug) == "table" and type(debug.getconstants) == "function" then
		readers[#readers + 1] = debug.getconstants
	end
	for _, reader in ipairs(readers) do
		local ok, constants = pcall(reader, fn)
		if ok and type(constants) == "table" then
			return constants
		end
	end
	return nil
end

local function networkKind(network)
	if type(network) ~= "table" or type(network.Fire) ~= "function" then
		return "assente"
	end
	local constants = readConstants(network.Fire)
	if not constants then
		return "sconosciuto"
	end
	for _, value in pairs(constants) do
		if value == "Unimplemented" then
			return "stub"
		end
	end
	return "live"
end

local function fromRequire()
	local framework = ReplicatedStorage:FindFirstChild("Framework")
	local moduleScript = framework and framework:FindFirstChild("Library")
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		return nil
	end
	local ok, library = pcall(require, moduleScript)
	if not ok or type(library) ~= "table" then
		return nil
	end
	local started = os.clock()
	while running and type(library.Network) ~= "table" and os.clock() - started < 3 do
		task.wait(0.1)
	end
	if type(library.Network) ~= "table" or type(library.Network.Fire) ~= "function" then
		return nil
	end
	return library
end

local function fromGc()
	if type(getgc) ~= "function" then
		return nil
	end
	local ok, objects = pcall(getgc, true)
	if not ok or type(objects) ~= "table" then
		return nil
	end
	local seen = 0
	for _, object in pairs(objects) do
		if not running then
			return nil
		end
		seen += 1
		if seen % 400 == 0 then
			task.wait()
		end
		if type(object) == "table" and type(object.Network) == "table" and type(object.Network.Fire) == "function" then
			if networkKind(object.Network) == "live" then
				return object
			end
		end
	end
	return nil
end

local function resolveLibrary()
	local required = fromRequire()
	local requiredKind = "assente"
	if type(required) == "table" then
		requiredKind = networkKind(required.Network)
	end
	if requiredKind == "live" then
		return required, "require (live)"
	end
	local scanned = fromGc()
	if type(scanned) == "table" then
		return scanned, "getgc (live)"
	end
	if requiredKind == "sconosciuto" then
		return required, "require (costanti illeggibili)"
	end
	if requiredKind == "stub" then
		return nil, "solo stub Unimplemented"
	end
	return nil, "Library assente"
end

local function sendPayload(remote, value)
	bucket.hits = 0
	bucket.foreign = 0
	bucket.expect = value
	bucket.remote = remote
	bucket.armed = true
	local callOk, callErr = pcall(function()
		remote:FireServer(value)
	end)
	bucket.armed = false
	bucket.remote = nil
	bucket.expect = nil
	return bucket.hits, bucket.foreign, callOk, callErr
end

local function payloadValue(label)
	if label == "0" then
		return 0
	end
	return {}
end

local function sendLoose(library, command, value)
	bucket.hits = 0
	bucket.foreign = 0
	bucket.expect = value
	bucket.remote = nil
	bucket.capture = nil
	bucket.loose = true
	bucket.armed = true
	local callOk, callErr = pcall(function()
		library.Network.Fire(command, value)
	end)
	local deadline = os.clock() + 1
	while running and bucket.hits == 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	bucket.armed = false
	bucket.loose = false
	bucket.expect = nil
	local capture = bucket.capture
	bucket.capture = nil
	return bucket.hits, capture, callOk, callErr
end

local function run()
	bucket.useCaller = false
	if type(checkcaller) == "function" then
		local ok, yes = pcall(checkcaller)
		bucket.useCaller = ok and yes == true
	end
	setStroke(Color3.fromRGB(70, 110, 170))
	local library, source = resolveLibrary()
	log("[NET] " .. source)
	local nowTime = nil
	pcall(function()
		nowTime = os.time()
	end)
	if type(nowTime) == "number" then
		log("[CLOCK] os.time locale: " .. tostring(nowTime))
	end
	if type(library) ~= "table" or type(library.Network) ~= "table" or type(library.Network.Fire) ~= "function" then
		setStatus("Fire assente", Color3.fromRGB(255, 160, 120))
		return
	end
	if not running then
		return
	end
	setStatus("Leggo il save")
	local saveSource = bindSave(library)
	if not running then
		return
	end
	if not saveSource then
		log("[INFO] Cache del save assente. Test annullato")
		setStatus("Save assente", Color3.fromRGB(255, 160, 120))
		return
	end
	local clocks, hidden, indexed = collectClocks()
	if not running then
		return
	end
	if not indexed then
		log("[INFO] Lettura del save interrotta. Test annullato")
		setStatus("Save illeggibile", Color3.fromRGB(255, 160, 120))
		return
	end
	log(string.format("[SAVE] %s | candidati %d", saveSource, #clocks))
	if hidden > 0 then
		log("[CLOCK] Timestamp anonimi oltre il livello 3 non elencati: " .. tostring(hidden))
	end
	if #clocks < 1 then
		log("[INFO] Nessun timestamp nel save. Test annullato")
		setStatus("Nessun clock", Color3.fromRGB(255, 200, 120))
		return
	end
	log("[CLOCK] Confronto di 6 secondi, un campione ogni secondo")
	local report, why = observeClocks(clocks)
	if not running or why == "stop" then
		return
	end
	if why == "errore" or type(report) ~= "table" then
		log("[INFO] Lettura del clock interrotta. Test annullato")
		setStatus("Clock illeggibile", Color3.fromRGB(255, 160, 120))
		return
	end
	for _, item in ipairs(clocks) do
		local startValue = report.first[item.path]
		local endValue = report.last[item.path]
		local ticks = report.changes[item.path] or 0
		local note = "fermo in questi 6s"
		if item.exact then
			note = "chiave esatta del save"
		elseif ticks > 0 then
			note = "si muove, non e il timestamp di salvataggio"
		elseif looksLikeStamp(item.value) and type(nowTime) == "number" and realNumber(startValue) then
			note = string.format("unix fermo, scarto da os.time %d", math.floor(startValue - nowTime))
		end
		log(string.format(
			"[CLOCK] %s | %s -> %s | scatti %d | %s",
			showPath(item.path),
			tostring(startValue),
			tostring(endValue),
			ticks,
			note
		))
	end
	local chosen = pickClock(clocks)
	if not chosen then
		log("[INFO] LastSaveTimestamp non e nel save. Gli altri campi non sono il clock di salvataggio. Test annullato")
		setStatus("Clock assente", Color3.fromRGB(255, 200, 120))
		return
	end
	local baselineTicks = report.changes[chosen.path] or 0
	local alreadyStill = baselineTicks < 1
	log(string.format(
		"[CLOCK] Scelto: %s | valore %s | scatti prima del payload %d",
		showPath(chosen.path),
		tostring(report.last[chosen.path]),
		baselineTicks
	))
	if alreadyStill then
		log("[CLOCK] Non si e mosso nei 6 secondi prima del payload. Era gia fermo.")
	end
	setStatus("Cerco i remote")
	local remotes, blocked = findRemotes(library)
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
			if remote then
				hits, foreign, callOk, callErr = sendPayload(remote, value)
			else
				local capture
				hits, capture, callOk, callErr = sendLoose(library, command, value)
				foreign = 0
				if hits > 0 and typeof(capture) == "Instance" then
					remotes[command] = capture
					log(string.format("[REMOTE] %s visto durante Network.Fire id %s", command, debugId(capture)))
				end
			end
			if not callOk then
				log("[NET] invio fallito: " .. tostring(callErr))
			end
			if hits == 1 and foreign == 0 then
				confirmed += 1
				local how = remote and "FireServer" or "Network.Fire"
				log(string.format("[NET] %s | Payload: %s | confermato via %s", command, label, how))
			else
				local detail = (hits == 0 and foreign == 0) and "nessun FireServer" or "non isolato"
				log(string.format("[NET] %s | Payload: %s | %s", command, label, detail))
			end
		end
	end
	if confirmed < 1 then
		log("[INFO] Nessun FireServer confermato. Il client ha scartato la chiamata prima dell'invio. Verdetto non emesso")
		setStatus("Pacchetto non uscito", Color3.fromRGB(255, 180, 90))
		return
	end
	local previous = readSaved(chosen.path)
	if not realNumber(previous) then
		log("[INFO] Il clock scelto non e piu un numero. Verdetto non emesso")
		setStatus("Clock illeggibile", Color3.fromRGB(255, 160, 120))
		return
	end
	local holdCount = 0
	local sawMove = false
	for index = 1, CHECKS do
		setStatus(string.format("Check %d/%d", index, CHECKS))
		if not waitSeconds(HOLD_STEP) then
			return
		end
		local now = readSaved(chosen.path)
		if not realNumber(now) then
			log(string.format("[SYNC] Check %d: illeggibile, holdCount=%d", index, holdCount))
		elseif now == previous then
			holdCount += 1
			log(string.format("[SYNC] Check %d: fermo %s | holdCount=%d", index, tostring(now), holdCount))
		else
			sawMove = true
			holdCount = 0
			log(string.format("[SYNC] Check %d: avanza %s -> %s", index, tostring(previous), tostring(now)))
			previous = now
		end
		if holdCount >= 3 and not alreadyStill then
			log("[SAVE FROZEN] Il server ha smesso di aggiornare il timestamp di salvataggio!")
			setStatus("SAVE FROZEN", Color3.fromRGB(255, 90, 90))
			setStroke(Color3.fromRGB(210, 50, 50))
			return
		end
	end
	if alreadyStill then
		log("[SYNC] Resta fermo, ma lo era gia prima del payload. Verdetto non emesso.")
	elseif sawMove then
		log("[SYNC] Il timestamp si e aggiornato. Nessun blocco misurato.")
	else
		log("[SYNC] Non ci sono tre fermate di fila. Nessun blocco misurato.")
	end
	setStatus("Clock vivo", Color3.fromRGB(120, 220, 140))
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

local existing = parentGui:FindFirstChild("DeltaTypeCheck")
if existing then
	pcall(function()
		existing:Destroy()
	end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "DeltaTypeCheck"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1005
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
title.Text = "SAVE CLOCK"
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

log("[GUI] Pronto. Legge LastSaveTimestamp per 6 secondi, poi manda 0 e {}")
log("[NOTA] Tieni premuto il log per selezionarlo. COPIA LOG usa setclipboard")
