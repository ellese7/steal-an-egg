-- Delta only. Claim/Redeem spam + Delete/Equip desync probe for psx-stayso.
-- No trade, no save-freeze. No booth/mail/daycare.
-- Verdict: same redeem payload returns true more than once = reward dupe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	LocalPlayer = Players.PlayerAdded:Wait()
end

local SPAM_COUNT = 5
local MAX_LINES = 600

local COMMANDS = {
	{ name = "Redeem Free Gift", kind = "invoke" },
	{ name = "Redeem Rank Rewards", kind = "invoke" },
	{ name = "Redeem VIP Rewards", kind = "invoke" },
	{ name = "Claim Season Reward", kind = "invoke" },
	{ name = "ClaimLeaveBonus", kind = "invoke" },
	{ name = "Quests: Redeem Reward", kind = "invoke" },
	{ name = "Redeem Pet Collection", kind = "invoke" },
	{ name = "Delete Several Pets", kind = "invoke" },
	{ name = "Equip Pet", kind = "invoke" },
}

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
	expectAny = false,
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
local logScroll
local frameStroke
local lines = {}
local saveCache = nil

local function scrollLogsToBottom()
	if not logScroll then
		return
	end
	task.defer(function()
		pcall(function()
			local canvasY = logScroll.AbsoluteCanvasSize.Y
			local viewY = logScroll.AbsoluteSize.Y
			logScroll.CanvasPosition = Vector2.new(0, math.max(0, canvasY - viewY))
		end)
	end)
end

local function paintLogs()
	if not logBox then
		return
	end
	-- Never call IsFocused: Delta can throw "lacking capability Plugin".
	pcall(function()
		logBox.Text = table.concat(lines, "\n")
	end)
	scrollLogsToBottom()
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

local function collectPets(library)
	local pets = {}
	local save = currentSave(library)
	if type(save) ~= "table" or type(save.Pets) ~= "table" then
		return pets
	end
	for _, pet in pairs(save.Pets) do
		if type(pet) == "table" and type(pet.uid) == "string" and #pet.uid > 0 and type(pet.id) == "string" then
			pets[#pets + 1] = {
				uid = pet.uid,
				id = pet.id,
				hc = pet.hc == true,
				g = pet.g == true,
				r = pet.r == true,
				dm = pet.dm == true,
				e = pet.e == true,
			}
		end
	end
	return pets
end

local function groupKey(pet)
	return string.format("%s|%s", tostring(pet.id), pet.hc and "hc" or "n")
end

local function takeUids(list, count, startIndex)
	local out = {}
	local from = startIndex or 1
	for i = from, math.min(#list, from + count - 1) do
		out[#out + 1] = list[i].uid
	end
	return out
end

local function buildMachinePlans(pets)
	local normalGroups = {}
	local goldGroups = {}
	for _, pet in ipairs(pets) do
		if pet.dm or pet.r then
			continue
		end
		local key = groupKey(pet)
		if pet.g then
			local group = goldGroups[key]
			if not group then
				group = {}
				goldGroups[key] = group
			end
			group[#group + 1] = pet
		else
			local group = normalGroups[key]
			if not group then
				group = {}
				normalGroups[key] = group
			end
			group[#group + 1] = pet
		end
	end

	local plans = {}
	local bestNormalKey, bestNormal = nil, nil
	for key, group in pairs(normalGroups) do
		if not bestNormal or #group > #bestNormal then
			bestNormalKey = key
			bestNormal = group
		end
	end
	local bestGoldKey, bestGold = nil, nil
	for key, group in pairs(goldGroups) do
		if not bestGold or #group > #bestGold then
			bestGoldKey = key
			bestGold = group
		end
	end

	if bestNormal and #bestNormal >= FUSE_MIN * 2 then
		plans[#plans + 1] = {
			name = "Fuse Pets",
			kind = "invoke",
			mode = "same_id_dual_fuse",
			setA = takeUids(bestNormal, FUSE_TAKE, 1),
			setB = takeUids(bestNormal, FUSE_TAKE, 1 + FUSE_TAKE),
			note = bestNormalKey .. " x" .. tostring(#bestNormal),
		}
	elseif bestNormal and #bestNormal >= FUSE_MIN then
		local setA = takeUids(bestNormal, FUSE_TAKE, 1)
		plans[#plans + 1] = {
			name = "Fuse Pets",
			kind = "invoke",
			mode = "fuse_vs_self",
			setA = setA,
			setB = { setA[1], setA[2], setA[3] },
			note = bestNormalKey .. " x" .. tostring(#bestNormal),
		}
	end

	if bestNormal and #bestNormal >= 2 then
		local setA = takeUids(bestNormal, math.min(3, #bestNormal), 1)
		local setB = takeUids(bestNormal, math.min(3, #bestNormal), math.max(1, #bestNormal - 2))
		if setB[1] == setA[1] and #bestNormal >= 4 then
			setB = takeUids(bestNormal, math.min(3, #bestNormal - 3), 4)
		end
		plans[#plans + 1] = {
			name = "Use Golden Machine",
			kind = "invoke",
			mode = "same_id_golden",
			setA = setA,
			setB = setB,
			note = bestNormalKey .. " x" .. tostring(#bestNormal),
		}
	end

	if bestGold and #bestGold >= 2 then
		local setA = takeUids(bestGold, math.min(3, #bestGold), 1)
		local setB = takeUids(bestGold, math.min(3, #bestGold), math.max(1, #bestGold - 2))
		plans[#plans + 1] = {
			name = "Use Rainbow Machine",
			kind = "invoke",
			mode = "same_id_rainbow",
			setA = setA,
			setB = setB,
			note = bestGoldKey .. " x" .. tostring(#bestGold),
		}
	end

	local equipUid, unequipUid = nil, nil
	for _, pet in ipairs(pets) do
		if pet.e and not unequipUid then
			unequipUid = pet.uid
		elseif (not pet.e) and not equipUid then
			equipUid = pet.uid
		end
		if equipUid and unequipUid then
			break
		end
	end
	if equipUid or unequipUid then
		plans[#plans + 1] = {
			name = "Equip/Unequip cross",
			kind = "cross",
			mode = "equip_unequip",
			equipUid = equipUid,
			unequipUid = unequipUid,
			note = string.format("equip=%s unequip=%s", tostring(equipUid), tostring(unequipUid)),
		}
	end

	return plans, bestNormal and #bestNormal or 0, bestGold and #bestGold or 0
end

local function waitNearSaveTick(library)
	local firstA, firstB = readDual(library)
	if not (realNumber(firstA) and realNumber(firstB)) then
		return false, "missing"
	end
	log("[CLOCK] Allineo allo scatto save (~4s)...")
	local deadline = os.clock() + 6
	local lastA, lastB = firstA, firstB
	while running and os.clock() < deadline do
		if not waitSeconds(0.05) then
			return false, "stop"
		end
		local nowA, nowB = readDual(library)
		if not (realNumber(nowA) and realNumber(nowB)) then
			return false, "errore"
		end
		if nowA ~= lastA or nowB ~= lastB then
			log(string.format(
				"[CLOCK] Scatto visto | LastSaveTimestamp %s -> %s | SaveVersion %s -> %s | attendo %.1fs verso write",
				tostring(lastA),
				tostring(nowA),
				tostring(lastB),
				tostring(nowB),
				TICK_ALIGN_WAIT
			))
			if not waitSeconds(TICK_ALIGN_WAIT) then
				return false, "stop"
			end
			return true, nil
		end
	end
	log("[CLOCK] Nessuno scatto in 6s, lancio comunque")
	return true, "no_tick"
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
		if not running then
			return false
		end
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
			if holdCount >= 3 then
				return true
			end
		else
			log(string.format(
				"[SYNC] Check %d: avanza | LastSaveTimestamp %s -> %s | SaveVersion %s -> %s | vivo, next payload",
				index,
				tostring(prevA),
				tostring(nowA),
				tostring(prevB),
				tostring(nowB)
			))
			-- Save still writing: no need to wait the remaining checks.
			return false
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
	if state and state.armed and (method == "InvokeServer" or method == "FireServer") then
		local matched = false
		if state.expectAny then
			matched = true
		elseif type(state.expect) == "table" then
			matched = argsEqual(state.expect, ...)
		end
		if matched then
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
	bucket.expectAny = false
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
	bucket.expectAny = false
	return bucket.hits, bucket.foreign, callOk, callErr, bucket.method
end

local function sendLoose(library, command, args)
	bucket.hits = 0
	bucket.foreign = 0
	bucket.expect = args
	bucket.expectAny = false
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
	bucket.expectAny = false
	local capture = bucket.capture
	local method = bucket.method
	bucket.capture = nil
	return bucket.hits, capture, callOk, callErr, method
end

local function invokeNamedArgs(library, remotes, name, ...)
	local n = select("#", ...)
	local remote = remotes[name]
	if remote then
		if classNameOf(remote) == "RemoteFunction" then
			if n == 0 then
				return remote:InvokeServer()
			end
			return remote:InvokeServer(...)
		end
		if n == 0 then
			remote:FireServer()
		else
			remote:FireServer(...)
		end
		return true, "fired"
	end
	if type(library.Network.Invoke) == "function" then
		if n == 0 then
			return library.Network.Invoke(name)
		end
		return library.Network.Invoke(name, ...)
	end
	if n == 0 then
		library.Network.Fire(name)
	else
		library.Network.Fire(name, ...)
	end
	return true, "fired"
end

local function alreadyRedeemed(redeemed, index)
	if type(redeemed) ~= "table" then
		return false
	end
	for _, value in pairs(redeemed) do
		if value == index then
			return true
		end
	end
	return false
end

local function resolveFreeGiftsDir(library)
	if type(library) == "table" and type(library.Directory) == "table" and type(library.Directory.FreeGifts) == "table" then
		return library.Directory.FreeGifts
	end
	local ok, dir = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Directory"):WaitForChild("FreeGifts"))
	end)
	if ok and type(dir) == "table" then
		return dir
	end
	return nil
end

local function pickFreeGiftIndex(library)
	local save = currentSave(library)
	local redeemed = save and save.FreeGiftsRedeemed or {}
	local giftTime = save and tonumber(save.FreeGiftsTime) or 0
	local dir = resolveFreeGiftsDir(library)
	if type(dir) == "table" then
		for i, gift in ipairs(dir) do
			if not alreadyRedeemed(redeemed, i) and giftTime >= (tonumber(gift.waitTime) or 0) then
				return i, "ready", giftTime, redeemed
			end
		end
		for i, _ in ipairs(dir) do
			if not alreadyRedeemed(redeemed, i) then
				return i, "not_ready", giftTime, redeemed
			end
		end
		if #dir > 0 then
			return 1, "all_redeemed", giftTime, redeemed
		end
	end
	return 1, "fallback", giftTime, redeemed
end

local function petStillInSave(library, uid)
	local save = currentSave(library)
	if type(save) ~= "table" or type(save.Pets) ~= "table" then
		return false
	end
	for _, pet in pairs(save.Pets) do
		if type(pet) == "table" and pet.uid == uid then
			return true, pet.e == true
		end
	end
	-- Force refresh once if Save.Get available.
	if type(library.Save) == "table" and type(library.Save.Get) == "function" then
		local ok, fresh = pcall(library.Save.Get)
		if ok and type(fresh) == "table" then
			saveCache = fresh
			if type(fresh.Pets) == "table" then
				for _, pet in pairs(fresh.Pets) do
					if type(pet) == "table" and pet.uid == uid then
						return true, pet.e == true
					end
				end
			end
		end
	end
	return false, false
end

local function pickDeleteTarget(library)
	local pets = collectPets(library)
	for _, pet in ipairs(pets) do
		if (not pet.e) and (not pet.dm) and (not pet.r) and (not pet.g) then
			return pet.uid, pet.id
		end
	end
	for _, pet in ipairs(pets) do
		if not pet.e then
			return pet.uid, pet.id
		end
	end
	if pets[1] then
		return pets[1].uid, pets[1].id
	end
	return nil, nil
end

local function spamSamePayload(library, remotes, name, args, count)
	local remote = remotes[name]
	bucket.hits = 0
	bucket.foreign = 0
	bucket.expect = nil
	bucket.expectAny = true
	bucket.remote = remote
	bucket.capture = nil
	bucket.loose = remote == nil
	bucket.method = nil
	bucket.armed = true
	local rows = table.create(count)
	local pending = count
	for i = 1, count do
		task.spawn(function()
			local packed = args or {}
			local ok, a, b = pcall(function()
				return invokeNamedArgs(library, remotes, name, table.unpack(packed, 1, #packed))
			end)
			if ok then
				rows[i] = { ok = true, a = a, b = b }
			else
				rows[i] = { ok = false, err = a }
			end
			pending -= 1
		end)
	end
	local deadline = os.clock() + 4
	while running and pending > 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	task.wait(0.05)
	if bucket.loose and typeof(bucket.capture) == "Instance" then
		remotes[name] = bucket.capture
		log(string.format("[REMOTE] %s visto id %s (%s)", name, debugId(bucket.capture), bucket.capture.ClassName))
	end
	local hits = bucket.hits
	local method = bucket.method
	bucket.armed = false
	bucket.loose = false
	bucket.expectAny = false
	bucket.remote = nil
	bucket.capture = nil
	local trueCount = 0
	for i = 1, count do
		local row = rows[i]
		if not row then
			log(string.format("[RET] %s #%d -> (timeout)", name, i))
		elseif not row.ok then
			log(string.format("[RET] %s #%d ERR %s", name, i, tostring(row.err)))
		else
			log(string.format("[RET] %s #%d -> %s | %s", name, i, tostring(row.a), tostring(row.b)))
			if row.a == true then
				trueCount += 1
			end
		end
	end
	return hits, method, trueCount
end

local function runDeleteEquipDesync(library, remotes)
	local uid, petId = pickDeleteTarget(library)
	if not uid then
		log("[INFO] Delete/Equip: nessun pet disponibile")
		return false
	end
	log(string.format("[TEST] Delete+Equip stesso frame | uid=%s id=%s", uid, tostring(petId)))
	local before = petStillInSave(library, uid)
	log(string.format("[SAVE] pre: pet in save=%s", tostring(before)))
	bucket.hits = 0
	bucket.foreign = 0
	bucket.expect = nil
	bucket.expectAny = true
	bucket.remote = nil
	bucket.capture = nil
	bucket.loose = true
	bucket.method = nil
	bucket.armed = true
	local delRet, eqRet = nil, nil
	local pending = 2
	task.spawn(function()
		local ok, a, b = pcall(invokeNamedArgs, library, remotes, "Delete Several Pets", { uid })
		delRet = ok and { a, b } or { false, a }
		pending -= 1
	end)
	task.spawn(function()
		local ok, a, b = pcall(invokeNamedArgs, library, remotes, "Equip Pet", uid)
		eqRet = ok and { a, b } or { false, a }
		pending -= 1
	end)
	local deadline = os.clock() + 3
	while running and pending > 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	task.wait(0.2)
	bucket.armed = false
	bucket.loose = false
	bucket.expectAny = false
	if delRet then
		log(string.format("[RET] Delete Several Pets -> %s | %s", tostring(delRet[1]), tostring(delRet[2])))
	else
		log("[RET] Delete Several Pets -> (timeout)")
	end
	if eqRet then
		log(string.format("[RET] Equip Pet -> %s | %s", tostring(eqRet[1]), tostring(eqRet[2])))
	else
		log("[RET] Equip Pet -> (timeout)")
	end
	task.wait(0.5)
	local after, equipped = petStillInSave(library, uid)
	log(string.format(
		"[SAVE] post: pet in save=%s equipped=%s | deleteOk=%s equipOk=%s",
		tostring(after),
		tostring(equipped),
		tostring(delRet and delRet[1]),
		tostring(eqRet and eqRet[1])
	))
	-- Desync signal: delete true but pet still present, or equip true after delete true.
	if delRet and delRet[1] == true and after then
		log("[DESYNC] Delete true ma pet ancora in save")
		return true
	end
	if delRet and delRet[1] == true and eqRet and eqRet[1] == true then
		log("[DESYNC] Delete e Equip entrambi true sullo stesso uid")
		return true
	end
	if delRet and delRet[1] == true and not after and eqRet and eqRet[1] == true then
		log("[DESYNC?] Equip true dopo delete (pet assente in save locale)")
		return true
	end
	return false
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
	local pets = collectPets(library)
	log(string.format("[SAVE] pet=%d | test=Claim spam x%d + Delete/Equip", #pets, SPAM_COUNT))
	setStatus("Cerco i remote")
	local remotes, blocked = scanNetwork(library, true)
	log("[REMOTE] Claim/Redeem + Delete. No trade/save.")
	if not running then
		return
	end
	if not installHook() then
		setStatus("Hook assente", Color3.fromRGB(255, 160, 120))
		return
	end

	local giftIndex, giftWhy, giftTime, redeemed = pickFreeGiftIndex(library)
	log(string.format(
		"[PLAN] Redeem Free Gift index=%d why=%s FreeGiftsTime=%s redeemed=%d | NO client nonce/token",
		giftIndex,
		tostring(giftWhy),
		tostring(giftTime),
		type(redeemed) == "table" and #redeemed or 0
	))

	local dupeHits = {}

	local redeemTargets = {
		{ name = "Redeem Free Gift", args = { giftIndex }, note = "solo indice gift, zero token" },
		{ name = "Redeem Rank Rewards", args = {}, note = "zero args, zero token" },
		{ name = "Redeem VIP Rewards", args = {}, note = "zero args, zero token" },
		{ name = "Claim Season Reward", args = {}, note = "zero args, zero token" },
		{ name = "ClaimLeaveBonus", args = {}, note = "zero args, zero token" },
		{ name = "Redeem Pet Collection", args = {}, note = "zero args, zero token" },
	}

	for _, target in ipairs(redeemTargets) do
		if not running then
			return
		end
		if blocked[target.name] then
			log("[REMOTE] " .. target.name .. " ambiguo, salto")
			continue
		end
		log(string.format("[TEST] Spam x%d | %s | %s | args=%s", SPAM_COUNT, target.name, target.note, #target.args == 0 and "(none)" or tostring(target.args[1])))
		setStatus("Spam " .. target.name)
		local hits, method, trueCount = spamSamePayload(library, remotes, target.name, target.args, SPAM_COUNT)
		log(string.format(
			"[NET] %s | hits=%d via %s | trueCount=%d/%d",
			target.name,
			hits,
			method or "Network",
			trueCount,
			SPAM_COUNT
		))
		if trueCount >= 2 then
			log(string.format("[DUPE?] %s ha risposto true %d volte sullo stesso payload", target.name, trueCount))
			dupeHits[#dupeHits + 1] = target.name
		end
		task.wait(0.15)
	end

	if not running then
		return
	end
	setStatus("Delete+Equip")
	local desync = runDeleteEquipDesync(library, remotes)
	if desync then
		dupeHits[#dupeHits + 1] = "Delete+Equip"
	end

	if #dupeHits > 0 then
		log("[RESULT] Possibile falla: " .. table.concat(dupeHits, ", "))
		setStatus("DUPE?", Color3.fromRGB(255, 90, 90))
		setStroke(Color3.fromRGB(210, 50, 50))
	else
		log("[RESULT] Nessun redeem ha dato true>1; Delete/Equip senza desync evidente.")
		setStatus("Nessun dupe", Color3.fromRGB(120, 220, 140))
		setStroke(Color3.fromRGB(40, 150, 80))
	end
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

local UserInputService = game:GetService("UserInputService")

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
frame.Size = UDim2.fromOffset(300, 260)
frame.Position = UDim2.new(1, -312, 0, 12)
frame.BackgroundColor3 = Color3.fromRGB(12, 14, 20)
frame.Active = true
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

frameStroke = Instance.new("UIStroke")
frameStroke.Thickness = 1.5
frameStroke.Color = Color3.fromRGB(70, 110, 170)
frameStroke.Parent = frame

local title = Instance.new("TextButton")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(8, 2)
title.Size = UDim2.new(1, -16, 0, 20)
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(236, 240, 248)
title.Text = "SAVE FREEZE  (trascina)"
title.AutoButtonColor = false
title.Parent = frame

startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.fromOffset(64, 26)
startBtn.Position = UDim2.fromOffset(8, 24)
startBtn.BackgroundColor3 = Color3.fromRGB(32, 130, 78)
startBtn.Text = "START"
startBtn.TextColor3 = Color3.new(1, 1, 1)
startBtn.Font = Enum.Font.GothamBold
startBtn.TextSize = 12
startBtn.AutoButtonColor = true
startBtn.Parent = frame

local startCorner = Instance.new("UICorner")
startCorner.CornerRadius = UDim.new(0, 6)
startCorner.Parent = startBtn

copyBtn = Instance.new("TextButton")
copyBtn.Size = UDim2.fromOffset(78, 26)
copyBtn.Position = UDim2.fromOffset(78, 24)
copyBtn.BackgroundColor3 = Color3.fromRGB(36, 92, 158)
copyBtn.Text = "COPIA"
copyBtn.TextColor3 = Color3.new(1, 1, 1)
copyBtn.Font = Enum.Font.GothamBold
copyBtn.TextSize = 11
copyBtn.AutoButtonColor = true
copyBtn.Parent = frame

local copyCorner = Instance.new("UICorner")
copyCorner.CornerRadius = UDim.new(0, 6)
copyCorner.Parent = copyBtn

statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -168, 0, 26)
statusLabel.Position = UDim2.fromOffset(162, 24)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Pronto"
statusLabel.TextColor3 = Color3.fromRGB(220, 228, 240)
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 11
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.Parent = frame

logScroll = Instance.new("ScrollingFrame")
logScroll.Name = "LogScroll"
logScroll.Position = UDim2.fromOffset(8, 56)
logScroll.Size = UDim2.new(1, -16, 1, -64)
logScroll.BackgroundColor3 = Color3.fromRGB(7, 9, 14)
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 8
logScroll.ScrollBarImageColor3 = Color3.fromRGB(120, 140, 170)
logScroll.ScrollingDirection = Enum.ScrollingDirection.Y
logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
logScroll.Active = true
logScroll.Parent = frame

local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 6)
scrollCorner.Parent = logScroll

logBox = Instance.new("TextBox")
logBox.Name = "LogText"
logBox.Position = UDim2.fromOffset(4, 0)
logBox.Size = UDim2.new(1, -14, 0, 0)
logBox.AutomaticSize = Enum.AutomaticSize.Y
logBox.BackgroundTransparency = 1
logBox.TextColor3 = Color3.fromRGB(226, 232, 240)
logBox.Font = Enum.Font.Code
logBox.TextSize = 11
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.TextWrapped = true
logBox.ClearTextOnFocus = false
logBox.TextEditable = true
logBox.MultiLine = true
logBox.Active = true
logBox.Selectable = true
logBox.Text = ""
logBox.Parent = logScroll

local dragging = false
local dragStart = nil
local startPos = nil

title.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

startBtn.MouseButton1Click:Connect(function()
	setRunning(not running)
end)
copyBtn.MouseButton1Click:Connect(copyLogs)
logBox.Focused:Connect(function()
	pcall(function()
		logBox.Text = table.concat(lines, "\n")
		logBox.CursorPosition = #logBox.Text + 1
		logBox.SelectionStart = 1
	end)
end)
logBox.FocusLost:Connect(function()
	pcall(function()
		logBox.Text = table.concat(lines, "\n")
	end)
	scrollLogsToBottom()
end)

log("[GUI] Solo START. Claim/Redeem spam x5 + Delete/Equip. Guarda [RET].")
log("[GUI] trueCount>=2 = possibile dupe. Trade/save non toccati.")
