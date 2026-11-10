-- Delta recon only. Paste on the phone, press START, copy the log.
-- Does not call FireServer or InvokeServer and does not farm.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local LocalPlayer = Players.LocalPlayer

local COMMANDS = { "Join Coin", "Farm Coin", "Change Pet Target" }
local DUMP_COMMANDS = { ["Join Coin"] = true, ["Farm Coin"] = true }
local MAX_LINES = 500

local running = false
local statusLabel
local startBtn
local logScroll
local lines = {}

local function paintLogs()
	if not logScroll then
		return
	end
	for _, child in ipairs(logScroll:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local widest = 0
	for index, line in ipairs(lines) do
		local row = Instance.new("TextLabel")
		row.Name = "L" .. index
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromOffset(1400, 18)
		row.Font = Enum.Font.Code
		row.TextSize = 13
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Color3.fromRGB(210, 220, 200)
		row.Text = line
		row.Parent = logScroll
		if #line > widest then
			widest = #line
		end
	end
	logScroll.CanvasSize = UDim2.fromOffset(math.max(widest * 8, 400), #lines * 20 + 8)
	logScroll.CanvasPosition = Vector2.new(0, #lines * 20)
end

local function log(text)
	lines[#lines + 1] = os.date("%H:%M:%S ") .. text
	while #lines > MAX_LINES do
		table.remove(lines, 1)
	end
	paintLogs()
end

local function logError(where, err)
	log("[ERRORE] " .. where .. ": " .. tostring(err))
end

local function setStatus(text)
	if statusLabel then
		statusLabel.Text = text
	end
end

local function copyLogs()
	local blob = table.concat(lines, "\n")
	local writer = setclipboard or toclipboard
	if type(writer) ~= "function" then
		log("[ERRORE] setclipboard non esiste su questo executor")
		setStatus("Copia non disponibile")
		return
	end
	local ok, err = pcall(writer, blob)
	if ok then
		setStatus("Log copiati")
		log("[GUI] Log copiati (" .. tostring(#lines) .. " righe)")
	else
		logError("setclipboard", err)
		setStatus("Copia fallita")
	end
end

local function isHash(value)
	return type(value) == "string" and #value == 32 and string.match(value, "^%x+$") ~= nil
end

local function isRemote(value)
	return typeof(value) == "Instance" and (value:IsA("RemoteEvent") or value:IsA("RemoteFunction"))
end

local function wantedCommand(key)
	for _, name in ipairs(COMMANDS) do
		if key == name then
			return true
		end
	end
	return false
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

local function short(value)
	local text = tostring(value)
	if #text > 140 then
		return string.sub(text, 1, 140) .. "..."
	end
	return text
end

local function callApi(primaryName, debugName, ...)
	local fn = ({
		getupvalues = getupvalues,
		getupvalue = getupvalue,
		getconstants = getconstants,
		getprotos = getprotos,
		getproto = getproto,
	})[primaryName]
	if type(fn) ~= "function" then
		fn = debug and debug[debugName]
	end
	if type(fn) ~= "function" then
		return false, "assente"
	end
	return pcall(fn, ...)
end

local function listUpvalues(fn)
	local ok, bulk = callApi("getupvalues", "getupvalues", fn)
	if ok and type(bulk) == "table" then
		return bulk, "getupvalues"
	end
	local out = {}
	local any = false
	for index = 1, 25 do
		local readOk, a, b = callApi("getupvalue", "getupvalue", fn, index)
		if not readOk then
			if not any then
				return nil, tostring(a)
			end
			break
		end
		if a == nil and b == nil then
			break
		end
		any = true
		if type(a) == "string" and b ~= nil then
			out[index] = b
		else
			out[index] = a
		end
	end
	if not any then
		return out, "vuoti"
	end
	return out, "getupvalue"
end

local function listConstants(fn)
	local ok, bulk = callApi("getconstants", "getconstants", fn)
	if ok and type(bulk) == "table" then
		return bulk
	end
	return nil, ok and typeof(bulk) or tostring(bulk)
end

local function listProtos(fn)
	local ok, bulk = callApi("getprotos", "getprotos", fn)
	if ok and type(bulk) == "table" then
		return bulk
	end
	local out = {}
	for index = 1, 12 do
		local readOk, proto = callApi("getproto", "getproto", fn, index, true)
		if not readOk or type(proto) ~= "function" then
			local readOk2, proto2 = callApi("getproto", "getproto", fn, index)
			if readOk2 and type(proto2) == "function" then
				out[#out + 1] = proto2
			else
				break
			end
		else
			out[#out + 1] = proto
		end
	end
	return out
end

local function stringConstants(fn)
	local constants, err = listConstants(fn)
	if type(constants) ~= "table" then
		return nil, err or "nessuna"
	end
	local texts = {}
	local numbers = 0
	for _, value in pairs(constants) do
		if type(value) == "string" then
			texts[#texts + 1] = value
		elseif type(value) == "number" then
			numbers += 1
		end
	end
	table.sort(texts)
	return texts, numbers
end

local function looksLikeGuard(texts)
	if type(texts) ~= "table" then
		return false
	end
	for _, text in ipairs(texts) do
		if text == "getgenv" or text == "pcall(settings)" or string.find(text, "callerScriptName", 1, true) then
			return true
		end
	end
	return false
end

local function clientModule()
	local framework = ReplicatedStorage:FindFirstChild("Framework")
	local clientFolder = framework and framework:FindFirstChild("Client")
	if not clientFolder then
		log("[MOD] Framework.Client assente")
		return nil, nil
	end
	for _, child in ipairs(clientFolder:GetDescendants()) do
		if child:IsA("ModuleScript") and string.find(child.Name, "Network", 1, true) then
			local ok, result = pcall(require, child)
			if ok and type(result) == "table" and type(result.Fire) == "function" and type(result.Invoke) == "function" then
				log("[MOD] " .. child:GetFullName())
				return result, child
			end
			logError("require " .. child.Name, result)
		end
	end
	log("[MOD] Network client senza Fire/Invoke")
	return nil, nil
end

local function dumpGuard(fn, label)
	local texts, numbers = stringConstants(fn)
	if type(texts) ~= "table" then
		log(string.format("[U11] %s costanti non lette (%s)", label, tostring(numbers)))
		return false
	end
	local hit = looksLikeGuard(texts)
	if not hit and #texts == 0 then
		return false
	end
	if hit then
		log(string.format("[U11] %s numeri %s stringhe %d", label, tostring(numbers), #texts))
		for _, text in ipairs(texts) do
			log("[U11] costante \"" .. short(text) .. "\"")
		end
		local ups, how = listUpvalues(fn)
		if type(ups) ~= "table" then
			log("[U11] upvalue " .. tostring(how))
		else
			local count = 0
			for index, value in pairs(ups) do
				count += 1
				log(string.format("[U11] upvalue [%s] %s %s", tostring(index), typeof(value), short(value)))
			end
			if count == 0 then
				log("[U11] upvalue nessuno (" .. tostring(how) .. ")")
			end
		end
	end
	return hit
end

local function scanGuard(network)
	log("[U11] Costanti di Fire, Invoke e delle funzioni interne")
	if type(network) ~= "table" then
		log("[ESITO] u11: modulo non letto")
		return
	end
	local seen = {}
	local found = 0
	local function walk(fn, label, depth)
		if type(fn) ~= "function" or seen[fn] or depth > 3 then
			return
		end
		seen[fn] = true
		if dumpGuard(fn, label) then
			found += 1
		end
		local protos = listProtos(fn)
		if type(protos) == "table" then
			local index = 0
			for _, proto in pairs(protos) do
				if type(proto) == "function" then
					index += 1
					walk(proto, label .. ".proto" .. tostring(index), depth + 1)
				end
			end
		end
		local ups = listUpvalues(fn)
		if type(ups) == "table" then
			for index, value in pairs(ups) do
				if type(value) == "function" then
					walk(value, label .. ".up" .. tostring(index), depth + 1)
				end
			end
		end
	end
	walk(network.Fire, "Fire", 1)
	walk(network.Invoke, "Invoke", 1)
	if found == 0 then
		log("[U11] Nessuna costante getgenv / pcall(settings) / callerScriptName sulle closure lette")
	end
	log(string.format("[ESITO] u11: funzioni con quelle costanti %d", found))
end

local function scanModuleChildren(moduleInst)
	log("[BIND] Figli del ModuleScript Network")
	if typeof(moduleInst) ~= "Instance" then
		log("[ESITO] Bindable hash sotto il modulo: modulo assente")
		return
	end
	local ok, kids = pcall(function()
		return moduleInst:GetChildren()
	end)
	if not ok then
		logError("GetChildren modulo", kids)
		return
	end
	local hashed = 0
	for _, child in ipairs(kids) do
		local hashName = isHash(child.Name)
		if hashName then
			hashed += 1
		end
		log(string.format("[BIND] %s nome '%s' hash=%s", child.ClassName, child.Name, tostring(hashName)))
	end
	if #kids == 0 then
		log("[BIND] Nessun figlio")
	end
	log(string.format("[ESITO] Bindable con nome hash sotto il modulo: %d su %d figli", hashed, #kids))
end

local function dumpRemote(command, hash, inst, how)
	log(string.format("[REMOTE] %s via %s hash %s", command, how, hash or "nil"))
	log(string.format(
		"[REMOTE] %s ClassName=%s Name='%s' Parent=%s id=%s",
		command,
		inst.ClassName,
		inst.Name,
		typeof(inst.Parent) == "Instance" and inst.Parent:GetFullName() or tostring(inst.Parent),
		debugId(inst)
	))
	local fullOk, fullName = pcall(function()
		return inst:GetFullName()
	end)
	log("[REMOTE] FullName " .. (fullOk and fullName or tostring(fullName)))
	local attrOk, attrs = pcall(function()
		return inst:GetAttributes()
	end)
	if not attrOk or type(attrs) ~= "table" or next(attrs) == nil then
		log("[REMOTE] " .. command .. " attributi nessuno")
	else
		local parts = {}
		for key, value in pairs(attrs) do
			parts[#parts + 1] = tostring(key) .. "=" .. short(value)
		end
		table.sort(parts)
		log("[REMOTE] " .. command .. " attributi " .. table.concat(parts, ", "))
	end
	local tagOk, tags = pcall(function()
		return CollectionService:GetTags(inst)
	end)
	if tagOk and type(tags) == "table" and #tags > 0 then
		log("[REMOTE] " .. command .. " tag " .. table.concat(tags, ", "))
	else
		log("[REMOTE] " .. command .. " tag nessuno")
	end
	local childOk, kids = pcall(function()
		return inst:GetChildren()
	end)
	if not childOk then
		logError("GetChildren " .. command, kids)
		return
	end
	log(string.format("[REMOTE] %s figli %d", command, #kids))
	for index, child in ipairs(kids) do
		if index > 12 then
			log(string.format("[REMOTE] %s altri %d figli", command, #kids - 12))
			break
		end
		log(string.format("[REMOTE] figlio %s '%s'", child.ClassName, child.Name))
	end
end

local function scanGc()
	log("[GC] getgc(true)")
	if type(getgc) ~= "function" then
		log("[GC] API assente")
		log("[ESITO] getgc: non disponibile")
		return
	end
	local ok, list = pcall(getgc, true)
	if not ok then
		logError("getgc(true)", list)
		log("[ESITO] getgc: chiamata fallita")
		return
	end
	if type(list) ~= "table" then
		log("[GC] Risposta " .. typeof(list))
		log("[ESITO] getgc: risposta non tabella")
		return
	end
	local kinds = {}
	local total = 0
	for _, obj in pairs(list) do
		total += 1
		local kind = typeof(obj)
		kinds[kind] = (kinds[kind] or 0) + 1
	end
	local parts = {}
	for kind, count in pairs(kinds) do
		parts[#parts + 1] = kind .. ":" .. tostring(count)
	end
	table.sort(parts)
	log(string.format("[GC] Oggetti %d (%s)", total, table.concat(parts, ", ")))
	if (kinds.table or 0) == 0 then
		log("[ESITO] getgc(true): nessuna tabella")
		return
	end

	local commandHash = {}
	local hashRemote = {}
	local direct = {}
	local channelMaps = 0
	local commandMaps = 0
	local scanned = 0
	for _, obj in pairs(list) do
		if type(obj) == "table" then
			scanned += 1
			if scanned % 250 == 0 then
				setStatus("GC " .. tostring(scanned))
				task.wait()
			end
			local hashCount = 0
			local commandCount = 0
			local localHash = {}
			local localCommand = {}
			local localDirect = {}
			local readOk = pcall(function()
				for key, value in pairs(obj) do
					if isHash(key) and isRemote(value) then
						hashCount += 1
						localHash[key] = value
					elseif type(key) == "string" and wantedCommand(key) and isHash(value) then
						commandCount += 1
						localCommand[key] = value
					elseif type(key) == "string" and wantedCommand(key) and isRemote(value) then
						localDirect[key] = value
					end
				end
			end)
			if readOk and hashCount > 0 then
				channelMaps += 1
				for key, value in pairs(localHash) do
					hashRemote[key] = value
				end
				if channelMaps <= 4 then
					log(string.format("[GC] Mappa hash->remote #%d voci %d", channelMaps, hashCount))
				end
			end
			if readOk and commandCount > 0 then
				commandMaps += 1
				for key, value in pairs(localCommand) do
					commandHash[key] = value
					log(string.format("[GC] Comando '%s' -> hash %s", key, value))
				end
			end
			if readOk then
				for key, value in pairs(localDirect) do
					direct[key] = value
					log(string.format("[GC] Comando '%s' -> istanza diretta %s '%s'", key, value.ClassName, value.Name))
				end
			end
		end
	end

	log(string.format(
		"[GC] Tabelle viste %d, mappe hash->remote %d, mappe comando->hash %d, comandi diretti %d",
		scanned,
		channelMaps,
		commandMaps,
		(direct["Join Coin"] and 1 or 0) + (direct["Farm Coin"] and 1 or 0)
	))

	for _, command in ipairs(COMMANDS) do
		local hash = commandHash[command]
		local inst = direct[command]
		local how = "diretto"
		if not inst and hash then
			inst = hashRemote[hash]
			how = "hash"
		end
		if inst and DUMP_COMMANDS[command] then
			dumpRemote(command, hash, inst, how)
		elseif inst then
			log(string.format("[REMOTE] %s trovato via %s, Name='%s', senza dump completo", command, how, inst.Name))
		elseif hash then
			log(string.format("[REMOTE] %s hash %s ma nessuna istanza con quella chiave", command, hash))
		else
			log("[REMOTE] " .. command .. " non collegato")
		end
	end

	log(string.format("[ESITO] Cache comando->hash: %d comandi", commandMaps > 0 and (commandHash["Join Coin"] and 1 or 0) + (commandHash["Farm Coin"] and 1 or 0) + (commandHash["Change Pet Target"] and 1 or 0) or 0))
	log(string.format("[ESITO] Cache hash->remote: %d mappe, chiavi totali %d", channelMaps, (function()
		local n = 0
		for _ in pairs(hashRemote) do
			n += 1
		end
		return n
	end)()))
end

local function hunt()
	if running then
		return
	end
	running = true
	table.clear(lines)
	startBtn.Text = "..."
	setStatus("Lettura")
	local named = "executor"
	pcall(function()
		named = identifyexecutor()
	end)
	log("[GUI] Ricognizione avviata su " .. tostring(named) .. ". Nessuna FireServer / InvokeServer")
	local network, moduleInst = clientModule()
	local steps = {
		{ "u11", function()
			scanGuard(network)
		end },
		{ "Bind", function()
			scanModuleChildren(moduleInst)
		end },
		{ "GC", scanGc },
	}
	for _, step in ipairs(steps) do
		setStatus(step[1])
		local ok, err = pcall(step[2])
		if not ok then
			logError(step[1], err)
		end
		task.wait()
	end
	log("[GUI] Ricognizione finita. COPIA LOG")
	setStatus("Finito")
	running = false
	startBtn.Text = "START"
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local parentGui = playerGui
if type(gethui) == "function" then
	local ok, guiRoot = pcall(gethui)
	if ok and typeof(guiRoot) == "Instance" then
		parentGui = guiRoot
	end
end

local existing = parentGui:FindFirstChild("DeltaRemoteExtractor")
if existing then
	pcall(function()
		existing:Destroy()
	end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "DeltaRemoteExtractor"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1002
gui.Parent = parentGui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromScale(0.94, 0.62)
frame.Position = UDim2.fromScale(0.03, 0.06)
frame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.fromOffset(110, 40)
startBtn.Position = UDim2.fromOffset(10, 10)
startBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 70)
startBtn.Text = "START"
startBtn.TextColor3 = Color3.new(1, 1, 1)
startBtn.Font = Enum.Font.GothamBold
startBtn.TextSize = 16
startBtn.Parent = frame

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 8)
buttonCorner.Parent = startBtn

local copyBtn = Instance.new("TextButton")
copyBtn.Size = UDim2.fromOffset(130, 40)
copyBtn.Position = UDim2.fromOffset(128, 10)
copyBtn.BackgroundColor3 = Color3.fromRGB(40, 90, 140)
copyBtn.Text = "COPIA LOG"
copyBtn.TextColor3 = Color3.new(1, 1, 1)
copyBtn.Font = Enum.Font.GothamBold
copyBtn.TextSize = 16
copyBtn.Parent = frame

local copyCorner = Instance.new("UICorner")
copyCorner.CornerRadius = UDim.new(0, 8)
copyCorner.Parent = copyBtn

statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -270, 0, 40)
statusLabel.Position = UDim2.fromOffset(266, 10)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Pronto"
statusLabel.TextColor3 = Color3.fromRGB(210, 220, 200)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 14
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.Parent = frame

logScroll = Instance.new("ScrollingFrame")
logScroll.Name = "Logs"
logScroll.Position = UDim2.fromOffset(10, 58)
logScroll.Size = UDim2.new(1, -20, 1, -68)
logScroll.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 8
logScroll.ScrollingDirection = Enum.ScrollingDirection.XY
logScroll.CanvasSize = UDim2.fromOffset(0, 0)
logScroll.Parent = frame

local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 8)
scrollCorner.Parent = logScroll

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 4)
pad.PaddingLeft = UDim.new(0, 6)
pad.Parent = logScroll

startBtn.MouseButton1Click:Connect(function()
	task.spawn(hunt)
end)
copyBtn.MouseButton1Click:Connect(copyLogs)

log("[GUI] Pronto su Delta. START legge la cache, non farma")
