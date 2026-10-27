--!optimize 2
--[[
  delta_logger.lua — Delta Executor
  Non vende e non chiama nessun remote.
  START aggancia __namecall e logga ogni FireServer/InvokeServer.
  I doppioni si saltano. Le chiamate sell/vend/selection/egg restano in cima.
  ProbeSatchel non basta a riconoscere una vendita.
  COPIA copia il testo del logger negli appunti.
  Rieseguire lo script sostituisce il precedente.
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer

-- Cattura i globali PRIMA di dichiarare local con lo stesso nome.
local gHook = hookmetamethod
local gNamecall = getnamecallmethod
local gClosure = newcclosure
local gCaller = checkcaller
local gClip = setclipboard
local gClip2 = toclipboard
local gHui = gethui

local function bare(name)
	local ok, fn = pcall(function()
		local loader = loadstring or load
		if typeof(loader) ~= "function" then
			return nil
		end
		local chunk = loader("return " .. name)
		if typeof(chunk) ~= "function" then
			return nil
		end
		return chunk()
	end)
	if ok and typeof(fn) == "function" then
		return fn
	end
	return nil
end

local hookmetamethod = (typeof(gHook) == "function" and gHook) or bare("hookmetamethod")
local getnamecallmethod = (typeof(gNamecall) == "function" and gNamecall) or bare("getnamecallmethod")
local newcclosure = (typeof(gClosure) == "function" and gClosure) or bare("newcclosure") or function(f)
	return f
end
local checkcaller = (typeof(gCaller) == "function" and gCaller) or bare("checkcaller")
local setclipboard = (typeof(gClip) == "function" and gClip) or (typeof(gClip2) == "function" and gClip2) or bare("setclipboard")
local gethui = (typeof(gHui) == "function" and gHui) or bare("gethui")

local ENV = (typeof(getgenv) == "function" and getgenv()) or _G
if typeof(ENV.__DeltaLoggerKill) == "function" then
	pcall(ENV.__DeltaLoggerKill)
end

local WORDS = { "sell", "vend", "selection", "egg" }
local NOISE = { "probesatchel", "rigsync" }
local METHODS = {
	FireServer = true,
	InvokeServer = true,
	fireServer = true,
	invokeServer = true,
}
local MAX_CHARS = 10000

local COL = {
	panel = Color3.fromRGB(14, 16, 22),
	bar = Color3.fromRGB(22, 26, 34),
	text = Color3.fromRGB(236, 240, 248),
	muted = Color3.fromRGB(150, 160, 176),
	idle = Color3.fromRGB(55, 62, 74),
	on = Color3.fromRGB(36, 140, 88),
	copy = Color3.fromRGB(40, 75, 130),
}

local alive = true
local running = false
local oldNamecall
local hooked = false
local queue = {}
local anyHits = 0
local fireHits = 0
local methodSeen = {}
local methodList = {}
local lines = {}
local pinned = {}
local seen = {}
local shown = 0
local skipped = 0
local logLabel
local statusLbl
local startBtn

local function low(s)
	return string.lower(tostring(s or ""))
end

local function matches(name)
	name = low(name)
	for i = 1, #WORDS do
		if string.find(name, WORDS[i], 1, true) then
			return true
		end
	end
	return false
end

local function fmt(v, depth, seen)
	depth = depth or 0
	if depth > 3 then
		return "…"
	end
	local tv = typeof(v)
	if tv == "string" then
		if #v > 160 then
			return string.format("%q…", string.sub(v, 1, 160))
		end
		return string.format("%q", v)
	end
	if tv == "number" or tv == "boolean" or tv == "nil" then
		return tostring(v)
	end
	if tv == "Instance" then
		local ok, path = pcall(function()
			return v:GetFullName()
		end)
		if ok and path then
			return v.ClassName .. "<" .. path .. ">"
		end
		return v.ClassName .. "<" .. v.Name .. ">"
	end
	if tv ~= "table" then
		local ok, text = pcall(tostring, v)
		return tv .. "(" .. (ok and text or "?") .. ")"
	end
	seen = seen or {}
	if seen[v] then
		return "{cycle}"
	end
	seen[v] = true
	local parts = {}
	local n = 0
	for k, val in pairs(v) do
		n = n + 1
		if n > 12 then
			parts[#parts + 1] = "…"
			break
		end
		local ok, piece = pcall(fmt, val, depth + 1, seen)
		parts[#parts + 1] = tostring(k) .. "=" .. (ok and piece or "?")
	end
	if n == 0 then
		return "{}"
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function argsText(...)
	local n = select("#", ...)
	if n == 0 then
		return "(nessun argomento)"
	end
	local parts = {}
	for i = 1, n do
		local ok, piece = pcall(fmt, select(i, ...), 0, nil)
		parts[i] = "[" .. i .. "] " .. (ok and piece or "?")
	end
	return table.concat(parts, "\n")
end

local function fullText()
	local chunks = {}
	if #pinned > 0 then
		chunks[#chunks + 1] = table.concat(pinned, "\n")
	end
	if #lines > 0 then
		chunks[#chunks + 1] = table.concat(lines, "\n")
	end
	return table.concat(chunks, "\n")
end

local function render()
	if not logLabel then
		return
	end
	while #fullText() > MAX_CHARS and #lines > 1 do
		table.remove(lines, 1)
	end
	local text = fullText()
	if #text > MAX_CHARS then
		text = string.sub(text, #text - MAX_CHARS + 1)
	end
	logLabel.Text = text
end

local function push(line)
	lines[#lines + 1] = tostring(line)
	render()
end

local function pushPin(line)
	pinned[#pinned + 1] = tostring(line)
	while #pinned > 24 do
		table.remove(pinned, 1)
	end
	render()
end

local function setStatus(s)
	if statusLbl then
		statusLbl.Text = s
	end
end

local function isNoise(path)
	path = low(path)
	for i = 1, #NOISE do
		if string.find(path, NOISE[i], 1, true) then
			return true
		end
	end
	return false
end

local function note(method, self, ...)
	local name = "?"
	local path = "?"
	if typeof(self) == "Instance" then
		name = tostring(self.Name)
		path = name
		local class = self.ClassName
		if class == "RemoteEvent" or class == "RemoteFunction" then
			local ok, full = pcall(function()
				return self:GetFullName()
			end)
			if ok and type(full) == "string" then
				path = full
			end
		end
	end
	local args = argsText(...)
	local key = method .. "\0" .. path .. "\0" .. args
	local now = os.clock()
	if seen[key] and (now - seen[key]) < 2 then
		skipped = skipped + 1
		return
	end
	seen[key] = now
	shown = shown + 1
	local stamp = os.date("%H:%M:%S")
	local interesting = (matches(name) or matches(path)) and not isNoise(path)
	local tag = interesting and "VENDITA" or (isNoise(path) and "RUMORE" or "REMOTE")
	local block = string.format("[%s] %s %s  %s\n%s", stamp, tag, method, path, args)
	if interesting then
		pushPin(block)
	else
		push(block)
	end
	if running then
		setStatus(string.format("in ascolto — %d nuovi, %d ripetuti", shown, skipped))
	end
end

local function rememberMethod(method)
	local label
	if typeof(method) == "string" then
		label = method
	else
		label = typeof(method) .. ":" .. tostring(method)
	end
	if methodSeen[label] or #methodList >= 18 then
		return
	end
	methodSeen[label] = true
	methodList[#methodList + 1] = label
end

local function enqueue(method, self, ...)
	fireHits = fireHits + 1
	if #queue >= 80 then
		table.remove(queue, 1)
	end
	local packed = table.pack(...)
	packed.method = method
	packed.inst = self
	queue[#queue + 1] = packed
end

local function installHook()
	if hooked then
		return true
	end
	if typeof(hookmetamethod) ~= "function" or typeof(gNamecall) ~= "function" then
		push("[ERR] Delta: hookmetamethod o getnamecallmethod assente")
		return false
	end
	-- Solo coda: niente GUI e niente GetFullName dentro __namecall.
	local function hook(self, ...)
		if running then
			anyHits = anyHits + 1
			local method = gNamecall()
			rememberMethod(method)
			if typeof(method) == "string" then
				local lowm = string.lower(method)
				if lowm == "fireserver" or lowm == "invokeserver" then
					enqueue(method, self, ...)
				end
			end
		end
		return oldNamecall(self, ...)
	end
	local ok, orig = pcall(hookmetamethod, game, "__namecall", newcclosure(hook))
	if not ok or typeof(orig) ~= "function" then
		push("[ERR] hookmetamethod: " .. tostring(orig))
		return false
	end
	oldNamecall = orig
	hooked = true
	push("[OK] __namecall attivo")
	return true
end

local function removeHook()
	running = false
	if hooked and typeof(oldNamecall) == "function" and typeof(hookmetamethod) == "function" then
		pcall(hookmetamethod, game, "__namecall", oldNamecall)
	end
	hooked = false
	oldNamecall = nil
end

local guiParent = LP:WaitForChild("PlayerGui")
pcall(function()
	if gethui then
		local h = gethui()
		if typeof(h) == "Instance" then
			guiParent = h
		end
	end
end)

local screen = Instance.new("ScreenGui")
screen.Name = "DeltaLogger"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 900
screen.Parent = guiParent

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.Size = UDim2.fromOffset(340, 320)
frame.Position = UDim2.fromOffset(12, 12)
frame.BackgroundColor3 = COL.panel
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = screen
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, 0, 0, 32)
title.BackgroundColor3 = COL.bar
title.BorderSizePixel = 0
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = COL.text
title.Text = "   Logger vendita"
title.Parent = frame
local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = title

local function makeBtn(text, color, x)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(148, 32)
	b.Position = UDim2.fromOffset(x, 42)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = COL.text
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = frame
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	return b
end

startBtn = makeBtn("START", COL.idle, 14)
local copyBtn = makeBtn("COPIA", COL.copy, 176)

statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -24, 0, 18)
statusLbl.Position = UDim2.fromOffset(14, 78)
statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 12
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextColor3 = COL.muted
statusLbl.Text = "fermo — START, vendi, COPIA"
statusLbl.Parent = frame

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Log"
scroll.Size = UDim2.new(1, -20, 1, -112)
scroll.Position = UDim2.fromOffset(10, 102)
scroll.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = frame
local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 8)
scrollCorner.Parent = scroll

logLabel = Instance.new("TextLabel")
logLabel.Size = UDim2.new(1, -12, 0, 0)
logLabel.Position = UDim2.fromOffset(6, 6)
logLabel.BackgroundTransparency = 1
logLabel.Font = Enum.Font.Code
logLabel.TextSize = 12
logLabel.TextXAlignment = Enum.TextXAlignment.Left
logLabel.TextYAlignment = Enum.TextYAlignment.Top
logLabel.TextColor3 = COL.text
logLabel.TextWrapped = true
logLabel.Text = ""
logLabel.AutomaticSize = Enum.AutomaticSize.Y
logLabel.Parent = scroll

local dragging = false
local dragStart
local startPos

title.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
	end
end)

title.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

UIS.InputChanged:Connect(function(input)
	if not dragging then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local delta = input.Position - dragStart
	frame.Position = UDim2.new(
		startPos.X.Scale,
		startPos.X.Offset + delta.X,
		startPos.Y.Scale,
		startPos.Y.Offset + delta.Y
	)
end)

local function setRunning(on)
	running = on
	if on then
		startBtn.Text = "STOP"
		startBtn.BackgroundColor3 = COL.on
		setStatus("in ascolto — vendi un uovo")
	else
		startBtn.Text = "START"
		startBtn.BackgroundColor3 = COL.idle
		setStatus("fermo — COPIA")
	end
end

startBtn.MouseButton1Click:Connect(function()
	if not alive then
		return
	end
	if running then
		setRunning(false)
		push("[STOP]")
		return
	end
	if not installHook() then
		setRunning(false)
		setStatus("hook non partito")
		return
	end
	lines = {}
	pinned = {}
	seen = {}
	queue = {}
	methodSeen = {}
	methodList = {}
	shown = 0
	skipped = 0
	anyHits = 0
	fireHits = 0
	setRunning(true)
	push("[OK] ascolto ogni FireServer/InvokeServer")
	push("se namecall resta 0, l'hook non vede le chiamate")
end)

RunService.Heartbeat:Connect(function()
	if not alive then
		return
	end
	if running then
		setStatus(string.format("namecall %d — fire %d — in log %d", anyHits, fireHits, shown))
	end
	local budget = 6
	while budget > 0 and #queue > 0 do
		budget = budget - 1
		local item = table.remove(queue, 1)
		local ok, err = pcall(function()
			note(item.method, item.inst, table.unpack(item, 1, item.n))
		end)
		if not ok then
			push("[ERR] " .. tostring(err))
		end
	end
	if running and #methodList > 0 and anyHits >= 30 and not methodSeen.__dumped then
		methodSeen.__dumped = true
		push("metodi visti: " .. table.concat(methodList, ", "))
	end
end)

copyBtn.MouseButton1Click:Connect(function()
	local text = fullText()
	if text == "" and logLabel then
		text = logLabel.Text
	end
	if text == "" then
		setStatus("niente da copiare")
		return
	end
	if typeof(setclipboard) ~= "function" then
		setStatus("setclipboard assente")
		push("[ERR] setclipboard assente")
		return
	end
	local ok, err = pcall(setclipboard, text)
	if ok then
		setStatus("copiato (" .. #lines .. " righe)")
	else
		setStatus("copia fallita")
		push("[ERR] setclipboard: " .. tostring(err))
	end
end)

ENV.__DeltaLoggerKill = function()
	alive = false
	running = false
	removeHook()
	pcall(function()
		screen:Destroy()
	end)
end

push("Pronto. START, vendi un uovo, COPIA.")
push("ProbeSatchel e' rumore: cerca la riga VENDITA.")
