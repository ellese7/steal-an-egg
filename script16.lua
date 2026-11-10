-- Delta black box. Paste, START, click the chest by hand, STOP, COPIA LOG.
-- The hook records calls and then forwards them. It does not farm.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local CHEST_NAME = "Giant Hacker Chest"
local CHEST_AREA = "Hacker Portal"
local NEAR = 200
local HIT_DIST = 40
local MAX_LINES = 700
local WORDS = { "coin", "chest", "farm", "join", "pet" }

local root = type(getgenv) == "function" and getgenv() or _G
local bucket = root.__DeltaCrude
if type(bucket) == "table" then
	bucket.running = false
	bucket.enabled = false
	if bucket.old and type(hookmetamethod) == "function" then
		pcall(hookmetamethod, game, "__namecall", bucket.old)
	end
end

bucket = {
	enabled = false,
	running = false,
	old = nil,
	chestId = nil,
	collapsed = 0,
	inspected = {},
	inspect = {},
	queue = {},
	seenNet = {},
}
root.__DeltaCrude = bucket

local statusLabel
local startBtn
local stopBtn
local logScroll
local logBox
local lines = {}

local function paintLogs()
	if not logBox then
		return
	end
	if logBox:IsFocused() then
		return
	end
	logBox.Text = table.concat(lines, "\n")
end

local function pushLine(text)
	lines[#lines + 1] = os.date("%H:%M:%S ") .. text
	while #lines > MAX_LINES do
		table.remove(lines, 1)
	end
end

local function queueLog(text)
	bucket.queue[#bucket.queue + 1] = text
end

local function flushQueue()
	if #bucket.queue == 0 then
		return
	end
	local batch = bucket.queue
	bucket.queue = {}
	for _, text in ipairs(batch) do
		pushLine(text)
	end
	paintLogs()
end

local function logNow(text)
	pushLine(text)
	paintLogs()
end

local function setStatus(text)
	if statusLabel then
		statusLabel.Text = text
	end
end

local function selectLogs()
	flushQueue()
	if logBox then
		logBox.Text = table.concat(lines, "\n")
		logBox:CaptureFocus()
		task.defer(function()
			if not logBox then
				return
			end
			logBox.SelectionStart = 1
			logBox.CursorPosition = #logBox.Text + 1
		end)
	end
	setStatus("Tieni premuto e scegli Copia")
end

local function copyLogs()
	flushQueue()
	local blob = table.concat(lines, "\n")
	local writer = setclipboard or toclipboard
	local copied = false
	if type(writer) == "function" then
		local ok = pcall(writer, blob)
		copied = ok
	end
	selectLogs()
	if copied then
		setStatus("Copiato, oppure tieni premuto il testo")
	end
end

local function short(value, limit)
	local text = tostring(value)
	limit = limit or 120
	if #text > limit then
		return string.sub(text, 1, limit) .. "..."
	end
	return text
end

local function textHits(text)
	local lower = string.lower(text)
	for _, word in ipairs(WORDS) do
		if string.find(lower, word, 1, true) then
			return true
		end
	end
	return false
end

local function preview(value, depth, seen)
	depth = depth or 0
	seen = seen or {}
	local kind = typeof(value)
	if kind == "string" then
		return string.format("%q", short(value, 80))
	end
	if kind == "Instance" then
		local ok, path = pcall(function()
			return value:GetFullName()
		end)
		return ok and path or value.ClassName
	end
	if kind ~= "table" then
		return tostring(value)
	end
	if seen[value] or depth >= 3 then
		return "{...}"
	end
	seen[value] = true
	local parts = {}
	local count = 0
	for key, item in pairs(value) do
		count += 1
		if count > 8 then
			parts[#parts + 1] = "..."
			break
		end
		parts[#parts + 1] = tostring(key) .. "=" .. preview(item, depth + 1, seen)
	end
	if count == 0 then
		return "{}"
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function argsText(packed)
	local parts = {}
	for index = 1, packed.n do
		local ok, text = pcall(preview, packed[index], 0, {})
		parts[index] = ok and text or ("<" .. short(text) .. ">")
	end
	if #parts == 0 then
		return "(nessuno)"
	end
	return table.concat(parts, ", ")
end

local function scanValue(value, chestId, depth, seen, found)
	if depth > 4 or value == nil then
		return
	end
	local kind = typeof(value)
	if kind == "string" then
		if textHits(value) then
			found.word = true
		end
		if chestId and value == chestId then
			found.id = true
		end
		return
	end
	if kind == "number" and chestId and tostring(value) == chestId then
		found.id = true
		return
	end
	if kind == "Instance" then
		local ok, path = pcall(function()
			return value:GetFullName()
		end)
		if ok and textHits(path) then
			found.word = true
		end
		if textHits(value.Name) then
			found.word = true
		end
		return
	end
	if kind == "table" and not seen[value] then
		seen[value] = true
		for key, item in pairs(value) do
			scanValue(key, chestId, depth + 1, seen, found)
			scanValue(item, chestId, depth + 1, seen, found)
		end
	end
end

local function callApi(name, ...)
	local fn = ({
		getconstants = getconstants,
		getupvalues = getupvalues,
		getupvalue = getupvalue,
	})[name]
	if type(fn) ~= "function" and type(debug) == "table" then
		fn = debug[name]
	end
	if type(fn) ~= "function" then
		return false, "assente"
	end
	return pcall(fn, ...)
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

local function callerInfo()
	local scriptPath = "?"
	if type(getcallingscript) == "function" then
		local ok, caller = pcall(getcallingscript)
		if ok and typeof(caller) == "Instance" then
			local pathOk, path = pcall(function()
				return caller:GetFullName()
			end)
			scriptPath = pathOk and path or caller.Name
		end
	end
	local stack = {}
	local callerFn
	if type(debug) == "table" and type(debug.info) == "function" then
		for level = 2, 12 do
			local ok, src, line, name = pcall(debug.info, level, "sln")
			if not ok or src == nil then
				break
			end
			stack[#stack + 1] = string.format("%s:%s %s", tostring(src), tostring(line), tostring(name))
			if not callerFn then
				local fnOk, fn = pcall(debug.info, level, "f")
				if fnOk and type(fn) == "function" then
					callerFn = fn
				end
			end
		end
	end
	local stackText = table.concat(stack, " <- ")
	if #stackText > 360 then
		stackText = string.sub(stackText, 1, 360) .. "..."
	end
	return scriptPath, stackText, callerFn
end

local function inspectFunction(fn, label)
	local texts = {}
	local numbers = 0
	local ok, constants = callApi("getconstants", fn)
	if ok and type(constants) == "table" then
		for _, value in pairs(constants) do
			if type(value) == "string" then
				if textHits(value) or string.find(value, "getgenv", 1, true) or string.find(value, "settings", 1, true) then
					texts[#texts + 1] = short(value, 100)
				end
			elseif type(value) == "number" then
				numbers += 1
			end
		end
	else
		queueLog("[CALL] " .. label .. " costanti non lette (" .. tostring(constants) .. ")")
	end
	table.sort(texts)
	if #texts == 0 then
		queueLog(string.format("[CALL] %s costanti interessanti 0, numeri %d", label, numbers))
	else
		queueLog(string.format("[CALL] %s costanti interessanti %d, numeri %d", label, #texts, numbers))
		for _, text in ipairs(texts) do
			queueLog("[CALL] costante \"" .. text .. "\"")
		end
	end
	local upOk, ups = callApi("getupvalues", fn)
	if not upOk or type(ups) ~= "table" then
		queueLog("[CALL] " .. label .. " upvalue non letti (" .. tostring(ups) .. ")")
		return
	end
	local count = 0
	for index, value in pairs(ups) do
		count += 1
		local kind = typeof(value)
		local extra = ""
		if kind == "table" then
			local keys, hashKeys, remoteValues = 0, 0, 0
			pcall(function()
				for key, item in pairs(value) do
					keys += 1
					if type(key) == "string" and #key == 32 and string.match(key, "^%x+$") and typeof(item) == "Instance" then
						hashKeys += 1
						if item:IsA("RemoteEvent") or item:IsA("RemoteFunction") then
							remoteValues += 1
						end
					end
					if keys > 40 then
						break
					end
				end
			end)
			extra = string.format(" chiavi~%d hash->remote %d", keys, remoteValues)
			if hashKeys == 0 then
				extra = extra .. " " .. short(preview(value, 0, {}), 80)
			end
		elseif kind == "function" then
			extra = " function"
		elseif kind == "Instance" then
			extra = " " .. value.ClassName .. " '" .. value.Name .. "'"
		else
			extra = " " .. short(value, 80)
		end
		queueLog(string.format("[CALL] %s upvalue[%s] %s%s", label, tostring(index), kind, extra))
		if count >= 12 then
			queueLog("[CALL] " .. label .. " altri upvalue non stampati")
			break
		end
	end
	if count == 0 then
		queueLog("[CALL] " .. label .. " upvalue nessuno")
	end
end

local function drainInspect()
	local job = table.remove(bucket.inspect, 1)
	if not job then
		return
	end
	queueLog("[CALL] stack " .. (job.stack ~= "" and job.stack or "(vuoto)"))
	if type(job.fn) == "function" then
		inspectFunction(job.fn, job.key)
	else
		queueLog("[CALL] " .. job.key .. " funzione chiamante non disponibile")
	end
end

local function capture(method, remote, packed, callerInst)
	if typeof(remote) ~= "Instance" then
		return
	end
	if not (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then
		return
	end
	local path = remote.Name
	pcall(function()
		path = remote:GetFullName()
	end)
	local found = { word = textHits(path), id = false }
	scanValue(packed, bucket.chestId, 0, {}, found)
	if not found.word and not found.id then
		return
	end
	local dumped = argsText(packed)
	local signature = method .. "|" .. path .. "|" .. dumped
	local now = os.clock()
	local prev = bucket.seenNet[signature]
	if prev and now - prev < 1 then
		bucket.collapsed += 1
		return
	end
	bucket.seenNet[signature] = now
	local who = "gioco"
	if type(checkcaller) == "function" then
		local ok, fromExec = pcall(checkcaller)
		if ok and fromExec then
			who = "executor"
		end
	end
	local reason = found.id and "id cassa" or "parola"
	local scriptPath, stackText, callerFn = callerInfo()
	if typeof(callerInst) == "Instance" then
		local pathOk, path = pcall(function()
			return callerInst:GetFullName()
		end)
		scriptPath = pathOk and path or callerInst.Name
	end
	queueLog(string.format(
		"[NET] %s | Metodo: %s | %s | motivo: %s | chiamante: %s | id=%s | Args: %s",
		path,
		method,
		who,
		reason,
		scriptPath,
		debugId(remote),
		dumped
	))
	local key = debugId(remote) .. ":" .. method
	if not bucket.inspected[key] then
		bucket.inspected[key] = true
		bucket.inspect[#bucket.inspect + 1] = {
			fn = callerFn,
			key = key,
			stack = stackText,
		}
	end
end

bucket.capture = capture

local function namecall(self, ...)
	local state = root.__DeltaCrude
	if state and state.enabled and type(getnamecallmethod) == "function" then
		local okMethod, method = pcall(getnamecallmethod)
		if okMethod and (method == "FireServer" or method == "InvokeServer") then
			local callerInst = nil
			if type(getcallingscript) == "function" then
				callerInst = getcallingscript()
			end
			pcall(state.capture, method, self, table.pack(...), callerInst)
		end
	end
	local fwd = state and state.old
	if fwd then
		return fwd(self, ...)
	end
end

local function installHook()
	if bucket.old then
		bucket.enabled = true
		logNow("[NET] hook gia presente, riattivato")
		return true
	end
	if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
		logNow("[NET] hookmetamethod o getnamecallmethod assente")
		return false
	end
	local callback = namecall
	if type(newcclosure) == "function" then
		local okWrap, wrapped = pcall(newcclosure, namecall)
		if okWrap and type(wrapped) == "function" then
			callback = wrapped
		end
	end
	bucket.enabled = false
	local ok, original = pcall(hookmetamethod, game, "__namecall", callback)
	if not ok or type(original) ~= "function" then
		logNow("[NET] hook non installato: " .. tostring(original))
		return false
	end
	bucket.old = original
	bucket.enabled = true
	logNow("[NET] hook __namecall attivo. Le chiamate originali passano")
	return true
end

local function removeHook()
	bucket.enabled = false
	local original = bucket.old
	if original and type(hookmetamethod) == "function" then
		local ok, err = pcall(hookmetamethod, game, "__namecall", original)
		if ok then
			bucket.old = nil
			logNow("[NET] hook rimosso")
		else
			logNow("[NET] hook disattivato, ripristino fallito: " .. tostring(err))
		end
	end
end

local function ownedPets()
	local folders = {}
	for _, name in ipairs({ "__ITEMS", "__THINGS" }) do
		local holder = Workspace:FindFirstChild(name)
		local pets = holder and holder:FindFirstChild("Pets")
		if pets then
			folders[#folders + 1] = pets
		end
	end
	local owner = string.lower(LocalPlayer.Name)
	local list = {}
	local source = "nessuna cartella Pets"
	for _, folder in ipairs(folders) do
		local foundHere = 0
		for _, pet in ipairs(folder:GetChildren()) do
			local who = pet:GetAttribute("Owner")
			if type(who) == "string" and string.lower(who) == owner then
				foundHere += 1
				local uid = pet:GetAttribute("ID")
				if type(uid) ~= "string" or uid == "" then
					uid = pet.Name
				end
				list[#list + 1] = pet
			end
		end
		if foundHere > 0 then
			source = folder:GetFullName() .. " owner=" .. LocalPlayer.Name .. " " .. tostring(foundHere)
			break
		end
		source = folder:GetFullName() .. " senza i tuoi pet"
	end
	return list, source
end

local function positionOf(inst)
	if typeof(inst) ~= "Instance" then
		return nil
	end
	if inst:IsA("BasePart") then
		return inst.Position
	end
	local pos = inst:FindFirstChild("POS")
	if pos and pos:IsA("BasePart") then
		return pos.Position
	end
	if inst:IsA("Model") then
		if inst.PrimaryPart then
			return inst.PrimaryPart.Position
		end
		local ok, pivot = pcall(function()
			return inst:GetPivot().Position
		end)
		if ok and typeof(pivot) == "Vector3" then
			return pivot
		end
	end
	local part = inst:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.Position
	end
	return nil
end

local function findChest()
	local holder = Workspace:FindFirstChild("__ITEMS")
	local coins = holder and holder:FindFirstChild("Coins")
	if not coins then
		return nil
	end
	local origin = positionOf(LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"))
	local best, bestDist
	for _, coin in ipairs(coins:GetChildren()) do
		local name = coin:GetAttribute("Name")
		local area = coin:GetAttribute("Area")
		local health = tonumber(coin:GetAttribute("Health"))
		if (name == CHEST_NAME or area == CHEST_AREA) and (health == nil or health > 0) then
			local pos = positionOf(coin)
			local dist = 0
			if origin and pos then
				dist = (pos - origin).Magnitude
			end
			if not best or dist < bestDist then
				best = coin
				bestDist = dist
			end
		end
	end
	return best
end

local function chestLabel(coin)
	local id = coin:GetAttribute("ID")
	if type(id) ~= "string" or id == "" then
		id = coin.Name
	end
	return tostring(id)
end

local function healthText(coin)
	local health = coin:GetAttribute("Health")
	if type(health) == "number" then
		return string.format("%.0f", health), health
	end
	if health ~= nil then
		return tostring(health), tonumber(health)
	end
	return "nil", nil
end

local function billboardText(coin)
	local parts = {}
	local ok, descendants = pcall(function()
		return coin:GetDescendants()
	end)
	if not ok then
		return ""
	end
	for _, child in ipairs(descendants) do
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			local text = child.Text
			if type(text) == "string" and text ~= "" then
				parts[#parts + 1] = short(text, 40)
				if #parts >= 3 then
					break
				end
			end
		end
	end
	return table.concat(parts, " | ")
end

local lastHealth
local lastBillboard
local lastChestId
local lastDist = {}
local announcedFolder = false

local function sample()
	local pets, source = ownedPets()
	if not announcedFolder then
		announcedFolder = true
		queueLog("[PETS] " .. source)
	end
	local coin = findChest()
	if not coin then
		bucket.chestId = nil
		if lastChestId ~= false then
			lastChestId = false
			queueLog("[TARGET] Nessuna Giant Hacker Chest viva")
		end
		return
	end
	local id = chestLabel(coin)
	bucket.chestId = id
	if id ~= lastChestId then
		lastChestId = id
		lastHealth = nil
		lastBillboard = nil
		queueLog(string.format(
			"[TARGET] Cassa %s name=%s area=%s pos=%s",
			id,
			tostring(coin:GetAttribute("Name")),
			tostring(coin:GetAttribute("Area")),
			tostring(positionOf(coin))
		))
	end
	local hpText, hp = healthText(coin)
	local chestPos = positionOf(coin)
	local pieces = {}
	local nearest, nearestDist, nearestPos
	for _, pet in ipairs(pets) do
		local uid = pet:GetAttribute("ID")
		if type(uid) ~= "string" or uid == "" then
			uid = pet.Name
		end
		local pos = positionOf(pet)
		local dist
		if pos and chestPos then
			dist = (pos - chestPos).Magnitude
		end
		local previous = lastDist[uid]
		local approaching = dist and previous and dist + 5 < previous
		if dist and (dist <= NEAR or approaching) then
			pieces[#pieces + 1] = string.format("%s %.1f %s", uid, dist, tostring(pos))
		end
		if dist and (not nearestDist or dist < nearestDist) then
			nearest = uid
			nearestDist = dist
			nearestPos = pos
		end
		if dist then
			lastDist[uid] = dist
		end
	end
	if hp and lastHealth and hp < lastHealth then
		queueLog(string.format("[HP] cassa %s %s -> %s", id, string.format("%.0f", lastHealth), hpText))
		if nearest and nearestDist and nearestDist <= HIT_DIST then
			queueLog(string.format(
				"[PET] %s ha colpito la cassa! dist %.1f pos %s",
				nearest,
				nearestDist,
				tostring(nearestPos)
			))
		elseif nearest then
			queueLog(string.format("[PET] vita scesa, pet piu vicino %s dist %.1f", nearest, nearestDist or -1))
		end
	end
	lastHealth = hp or lastHealth
	local board = billboardText(coin)
	if board ~= "" and board ~= lastBillboard then
		lastBillboard = board
		queueLog("[HP] billboard " .. board)
	end
	local petText = #pieces > 0 and table.concat(pieces, " | ") or "nessun pet entro " .. tostring(NEAR)
	queueLog(string.format("[TICK] cassa %s HP %s | %s", id, hpText, petText))
end

local function stopMonitor()
	bucket.running = false
	bucket.enabled = false
	removeHook()
	flushQueue()
	if bucket.collapsed > 0 then
		logNow("[NET] Chiamate identiche entro 1s non ristampate: " .. tostring(bucket.collapsed))
		bucket.collapsed = 0
	end
	logNow("[GUI] STOP")
	setStatus("Fermo")
	if startBtn then
		startBtn.Text = "START"
		startBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 70)
	end
end

local function startMonitor()
	if bucket.running then
		return
	end
	table.clear(lines)
	bucket.queue = {}
	bucket.inspect = {}
	bucket.inspected = {}
	bucket.seenNet = {}
	bucket.collapsed = 0
	bucket.chestId = nil
	lastHealth = nil
	lastBillboard = nil
	lastChestId = nil
	lastDist = {}
	announcedFolder = false
	bucket.running = true
	startBtn.Text = "ON"
	startBtn.BackgroundColor3 = Color3.fromRGB(30, 90, 50)
	setStatus("Registro")
	logNow("[GUI] START. Clicca la cassa a mano. Filtro: Coin Chest Farm Join Pet, oppure argomento uguale all'id della cassa")
	installHook()
	task.spawn(function()
		while bucket.running do
			local ok, err = pcall(sample)
			if not ok then
				queueLog("[ERRORE] monitor: " .. tostring(err))
			end
			task.wait(0.5)
		end
	end)
end

RunService.Heartbeat:Connect(function()
	if not bucket.running and #bucket.queue == 0 and #bucket.inspect == 0 then
		return
	end
	pcall(drainInspect)
	pcall(flushQueue)
end)

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
local parentGui = playerGui
if type(gethui) == "function" then
	local ok, guiRoot = pcall(gethui)
	if ok and typeof(guiRoot) == "Instance" then
		parentGui = guiRoot
	end
end

local existing = parentGui:FindFirstChild("DeltaCrudeLogger")
if existing then
	pcall(function()
		existing:Destroy()
	end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "DeltaCrudeLogger"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1003
gui.Parent = parentGui

local frame = Instance.new("Frame")
frame.Size = UDim2.fromScale(0.96, 0.7)
frame.Position = UDim2.fromScale(0.02, 0.04)
frame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.fromOffset(92, 40)
startBtn.Position = UDim2.fromOffset(8, 8)
startBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 70)
startBtn.Text = "START"
startBtn.TextColor3 = Color3.new(1, 1, 1)
startBtn.Font = Enum.Font.GothamBold
startBtn.TextSize = 15
startBtn.Parent = frame

stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.fromOffset(92, 40)
stopBtn.Position = UDim2.fromOffset(106, 8)
stopBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
stopBtn.Text = "STOP"
stopBtn.TextColor3 = Color3.new(1, 1, 1)
stopBtn.Font = Enum.Font.GothamBold
stopBtn.TextSize = 15
stopBtn.Parent = frame

local copyBtn = Instance.new("TextButton")
copyBtn.Size = UDim2.fromOffset(120, 40)
copyBtn.Position = UDim2.fromOffset(204, 8)
copyBtn.BackgroundColor3 = Color3.fromRGB(40, 90, 140)
copyBtn.Text = "COPIA LOG"
copyBtn.TextColor3 = Color3.new(1, 1, 1)
copyBtn.Font = Enum.Font.GothamBold
copyBtn.TextSize = 14
copyBtn.Parent = frame

for _, button in ipairs({ startBtn, stopBtn, copyBtn }) do
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 8)
	round.Parent = button
end

statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -336, 0, 40)
statusLabel.Position = UDim2.fromOffset(330, 8)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Pronto"
statusLabel.TextColor3 = Color3.fromRGB(210, 220, 200)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 14
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.Parent = frame

logScroll = Instance.new("ScrollingFrame")
logScroll.Position = UDim2.fromOffset(8, 56)
logScroll.Size = UDim2.new(1, -16, 1, -64)
logScroll.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 8
logScroll.ScrollingDirection = Enum.ScrollingDirection.Y
logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
logScroll.CanvasSize = UDim2.fromOffset(0, 0)
logScroll.Parent = frame

local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 8)
scrollCorner.Parent = logScroll

logBox = Instance.new("TextBox")
logBox.Name = "LogText"
logBox.BackgroundTransparency = 1
logBox.Size = UDim2.new(1, -12, 0, 0)
logBox.Position = UDim2.fromOffset(6, 4)
logBox.AutomaticSize = Enum.AutomaticSize.Y
logBox.ClearTextOnFocus = false
logBox.MultiLine = true
logBox.TextEditable = true
logBox.TextWrapped = true
logBox.Font = Enum.Font.Code
logBox.TextSize = 14
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.TextColor3 = Color3.fromRGB(210, 220, 200)
logBox.Text = ""
logBox.Parent = logScroll

local function fitLogBox()
	local width = math.max(logScroll.AbsoluteSize.X - 16, 80)
	logBox.Size = UDim2.fromOffset(width, 0)
end

logScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitLogBox)
fitLogBox()
task.defer(fitLogBox)

logBox.FocusLost:Connect(function()
	logBox.Text = table.concat(lines, "\n")
end)

startBtn.MouseButton1Click:Connect(function()
	task.spawn(startMonitor)
end)
stopBtn.MouseButton1Click:Connect(stopMonitor)
copyBtn.MouseButton1Click:Connect(copyLogs)
gui.Destroying:Connect(function()
	bucket.running = false
	pcall(removeHook)
end)

logNow("[GUI] Pronto. START, clicca la cassa, STOP. COPIA LOG seleziona il testo: tieni premuto e scegli Copia")
