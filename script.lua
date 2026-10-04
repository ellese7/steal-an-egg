-- ==================================================
--  Steal a Pet — AC Research Probe 1 (Delta)
--  Who reads WalkSpeed / Velocity / CFrame on Hum + HRP?
-- ==================================================

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local MAX_LINES = 120
local LOG_VIEW = 55
local MAX_UNIQUE_LOGS = 40 -- log dettagliato solo per i primi N reader unici
local SUMMARY_EVERY = 8 -- secondi

local COL = {
	panel = Color3.fromRGB(13, 15, 20),
	btn = Color3.fromRGB(26, 30, 40),
	ok = Color3.fromRGB(44, 112, 88),
	off = Color3.fromRGB(55, 60, 78),
	copy = Color3.fromRGB(40, 70, 120),
	clear = Color3.fromRGB(70, 55, 40),
	text = Color3.fromRGB(240, 242, 248),
	muted = Color3.fromRGB(138, 146, 162),
	accent = Color3.fromRGB(120, 220, 255),
	warn = Color3.fromRGB(255, 180, 80),
	bad = Color3.fromRGB(220, 80, 80),
}

local WATCH_KEYS = {
	WalkSpeed = true,
	JumpPower = true,
	JumpHeight = true,
	HipHeight = true,
	Health = false, -- rumore; lascia false
	MaxHealth = false,
	Velocity = true,
	AssemblyLinearVelocity = true,
	AssemblyAngularVelocity = true,
	CFrame = true,
	Position = true,
}

local running = false
local lines = {}
local statusLbl, runBtn, logBox, gui
local hooks = {}
local stats = {} -- key = prop|caller -> count
local uniqueLogged = 0
local totalHits = 0
local lastSummary = 0
local humRef, hrpRef
local charConns = {}

local function findApi(...)
	local names = { ... }
	local spots = { _G }
	pcall(function()
		if typeof(getgenv) == "function" then
			spots[#spots + 1] = getgenv()
		end
	end)
	for s = 1, #spots do
		for n = 1, #names do
			local ok, val = pcall(function()
				return spots[s][names[n]]
			end)
			if ok and typeof(val) == "function" then
				return val
			end
		end
	end
end

local setclipFn = findApi("setclipboard", "toclipboard", "setrbxclipboard")
local hookmm = findApi("hookmetamethod")
local getnamecall = findApi("getnamecallmethod")
local getcallingscript = findApi("getcallingscript")
local checkcaller = findApi("checkcaller")
local newcclosure = findApi("newcclosure") or function(f)
	return f
end

local function refreshLogBox()
	if not logBox then
		return
	end
	local n = #lines
	local from = math.max(1, n - LOG_VIEW)
	local chunk = table.create(n - from + 1)
	for i = from, n do
		chunk[#chunk + 1] = lines[i]
	end
	logBox.Text = table.concat(chunk, "\n")
end

local function log(msg, hi)
	lines[#lines + 1] = (hi and ">>> " or "") .. "[" .. os.date("%H:%M:%S") .. "] " .. tostring(msg)
	if #lines > MAX_LINES then
		table.remove(lines, 1)
	end
	refreshLogBox()
end

local function setStatus(t, col)
	if statusLbl then
		statusLbl.Text = tostring(t)
		if col then
			statusLbl.TextColor3 = col
		end
	end
end

local function paintRun()
	if not runBtn then
		return
	end
	if running then
		runBtn.Text = "STOP"
		runBtn.BackgroundColor3 = COL.ok
	else
		runBtn.Text = "START"
		runBtn.BackgroundColor3 = COL.off
	end
end

local function callerTag()
	local parts = {}
	if checkcaller and checkcaller() then
		parts[#parts + 1] = "executor"
	end
	if getcallingscript then
		local ok, scr = pcall(getcallingscript)
		if ok and scr then
			local ok2, path = pcall(function()
				return scr:GetFullName()
			end)
			parts[#parts + 1] = ok2 and path or tostring(scr)
		else
			parts[#parts + 1] = "no-script"
		end
	else
		local ok, src = pcall(function()
			return debug.info(3, "s")
		end)
		local ok2, line = pcall(function()
			return debug.info(3, "l")
		end)
		local ok3, name = pcall(function()
			return debug.info(3, "n")
		end)
		parts[#parts + 1] = string.format(
			"%s:%s:%s",
			ok and tostring(src) or "?",
			ok2 and tostring(line) or "?",
			ok3 and tostring(name) or "?"
		)
	end
	return table.concat(parts, " | ")
end

local function shortVal(v)
	local t = typeof(v)
	if t == "number" then
		return string.format("%.3f", v)
	elseif t == "Vector3" then
		return string.format("(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
	elseif t == "CFrame" then
		local p = v.Position
		return string.format("CF(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z)
	end
	return t
end

local function onRead(instKind, key, value)
	if not running then
		return
	end
	if not WATCH_KEYS[key] then
		return
	end
	totalHits += 1
	local who = callerTag()
	local id = instKind .. "." .. key .. " <- " .. who
	stats[id] = (stats[id] or 0) + 1
	local n = stats[id]
	-- primo hit di questo reader: log dettagliato
	if n == 1 then
		if uniqueLogged < MAX_UNIQUE_LOGS then
			uniqueLogged += 1
			log(string.format("READ %s.%s = %s | %s", instKind, key, shortVal(value), who), true)
		end
	elseif n == 10 or n == 50 or n == 200 then
		log(string.format("COUNT %s = %d hits", id, n))
	end
end

local function maybeSummary()
	local now = os.clock()
	if now - lastSummary < SUMMARY_EVERY then
		return
	end
	lastSummary = now
	local top = {}
	for k, c in pairs(stats) do
		top[#top + 1] = { k = k, c = c }
	end
	table.sort(top, function(a, b)
		return a.c > b.c
	end)
	log(string.format("SUMMARY hits=%d unique=%d", totalHits, #top), true)
	for i = 1, math.min(8, #top) do
		log(string.format("  #%d %dx  %s", i, top[i].c, top[i].k))
	end
end

local function clearCharConns()
	for i = 1, #charConns do
		pcall(function()
			charConns[i]:Disconnect()
		end)
	end
	charConns = {}
end

local function bindCharacter(char)
	clearCharConns()
	humRef = char and char:FindFirstChildOfClass("Humanoid")
	hrpRef = char and char:FindFirstChild("HumanoidRootPart")
	if not humRef then
		charConns[#charConns + 1] = char.ChildAdded:Connect(function(ch)
			if ch:IsA("Humanoid") then
				humRef = ch
				log("Humanoid bound", true)
			elseif ch.Name == "HumanoidRootPart" then
				hrpRef = ch
				log("HRP bound", true)
			end
		end)
	end
	if humRef then
		log("track Humanoid=" .. humRef:GetFullName(), true)
	end
	if hrpRef then
		log("track HRP=" .. hrpRef:GetFullName(), true)
	else
		log("HRP not ready yet", true)
	end
end

local function installHooks()
	if not hookmm then
		log("hookmetamethod MISSING — Delta required", true)
		setStatus("no hookmetamethod", COL.bad)
		return false
	end

	-- __index: letture proprietà
	local okIdx, errIdx = pcall(function()
		local old
		old = hookmm(game, "__index", newcclosure(function(self, key)
			if running then
				if typeof(key) == "string" and WATCH_KEYS[key] then
					if self == humRef then
						local v = old(self, key)
						onRead("Humanoid", key, v)
						maybeSummary()
						return v
					elseif self == hrpRef then
						local v = old(self, key)
						onRead("HRP", key, v)
						maybeSummary()
						return v
					end
				end
			end
			return old(self, key)
		end))
		hooks[#hooks + 1] = { kind = "__index", old = old }
	end)
	if not okIdx then
		log("__index hook FAIL " .. tostring(errIdx), true)
		return false
	end
	log("__index hook OK (Hum/HRP reads)", true)

	-- __namecall: GetPropertyChangedSignal / GetAttribute raramente; log Invoke/Fire non qui
	-- opzionale: GetPropertyChangedSignal su WalkSpeed
	local okNc, errNc = pcall(function()
		if not getnamecall then
			log("getnamecallmethod absent — skip namecall watch", true)
			return
		end
		local old
		old = hookmm(game, "__namecall", newcclosure(function(self, ...)
			if running and (self == humRef or self == hrpRef) then
				local method = getnamecall()
				if method == "GetPropertyChangedSignal" then
					local args = { ... }
					local prop = args[1]
					if typeof(prop) == "string" and WATCH_KEYS[prop] then
						log(
							string.format(
								"SIGNAL %s:GetPropertyChangedSignal(%s) | %s",
								self == humRef and "Humanoid" or "HRP",
								prop,
								callerTag()
							),
							true
						)
					end
				end
			end
			return old(self, ...)
		end))
		hooks[#hooks + 1] = { kind = "__namecall", old = old }
		log("__namecall hook OK (GetPropertyChangedSignal)", true)
	end)
	if not okNc then
		log("namecall hook FAIL " .. tostring(errNc), true)
	end

	return true
end

local function uninstallNote()
	-- Delta: hookmetamethod di solito non si "unhooka" facilmente; stop = flag running=false
	log("hooks left in place; reads ignored while STOPPED", true)
end

local function stop()
	if not running then
		return
	end
	running = false
	paintRun()
	clearCharConns()
	maybeSummary()
	log("STOP", true)
	setStatus("stopped — Copy log", COL.muted)
	uninstallNote()
end

local function start()
	if running then
		stop()
		return
	end

	stats = {}
	uniqueLogged = 0
	totalHits = 0
	lastSummary = os.clock()

	if #hooks == 0 then
		if not installHooks() then
			paintRun()
			return
		end
	end

	local char = LP.Character or LP.CharacterAdded:Wait()
	bindCharacter(char)
	charConns[#charConns + 1] = LP.CharacterAdded:Connect(function(c)
		task.defer(function()
			bindCharacter(c)
		end)
	end)

	running = true
	paintRun()
	log("START — walk normally 20–40s, then Copy log", true)
	log(
		string.format(
			"apis hookmm=%s getcallingscript=%s checkcaller=%s",
			tostring(hookmm ~= nil),
			tostring(getcallingscript ~= nil),
			tostring(checkcaller ~= nil)
		),
		true
	)
	setStatus("listening property reads…", COL.accent)
end

local function copyLog()
	local text = table.concat(lines, "\n")
	if setclipFn then
		local ok, err = pcall(setclipFn, text)
		if ok then
			setStatus("copied " .. #lines .. " lines", COL.ok)
			log("COPY ok", true)
		else
			setStatus("copy fail", COL.bad)
			log("COPY err " .. tostring(err), true)
		end
	else
		setStatus("no setclipboard — select log text", COL.warn)
		log("COPY no setclipboard", true)
	end
end

local function clearLog()
	lines = {}
	refreshLogBox()
	setStatus("log cleared", COL.muted)
end

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function buildGui()
	local pg = LP:FindFirstChild("PlayerGui") or LP:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("ACProbe1UI")
	if old then
		old:Destroy()
	end

	gui = mk("ScreenGui", {
		Name = "ACProbe1UI",
		ResetOnSpawn = false,
		DisplayOrder = 120,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, pg)

	local root = mk("Frame", {
		Size = UDim2.fromOffset(320, 280),
		Position = UDim2.fromOffset(16, 100),
		BackgroundColor3 = COL.panel,
		BorderSizePixel = 0,
		Active = true,
		Draggable = true,
	}, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 12) }, root)
	local pad = mk("UIPadding", {}, root)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, root)

	mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.text,
		Text = "AC Probe 1 — Property Reads",
		LayoutOrder = 1,
	}, root)

	runBtn = mk("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = COL.text,
		AutoButtonColor = true,
		LayoutOrder = 2,
	}, root)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, runBtn)

	statusLbl = mk("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COL.muted,
		Text = "Delta — walk around after START",
		LayoutOrder = 3,
	}, root)

	local shell = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 140),
		BackgroundColor3 = COL.btn,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = 4,
	}, root)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, shell)

	local scroll = mk("ScrollingFrame", {
		Size = UDim2.new(1, -6, 1, -6),
		Position = UDim2.fromOffset(3, 3),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = COL.accent,
		CanvasSize = UDim2.fromOffset(0, 900),
	}, shell)

	logBox = mk("TextLabel", {
		Size = UDim2.new(1, -4, 0, 900),
		Position = UDim2.fromOffset(2, 2),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Color3.fromRGB(200, 220, 200),
		TextSize = 11,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	}, scroll)

	local row = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
	}, root)
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
	}, row)

	local copyBtn = mk("TextButton", {
		Size = UDim2.new(0.55, -3, 1, 0),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = COL.text,
		BackgroundColor3 = COL.copy,
		Text = "Copy log",
		AutoButtonColor = true,
	}, row)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, copyBtn)

	local clearBtn = mk("TextButton", {
		Size = UDim2.new(0.45, -3, 1, 0),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = COL.text,
		BackgroundColor3 = COL.clear,
		Text = "Clear",
		AutoButtonColor = true,
	}, row)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, clearBtn)

	paintRun()
	runBtn.MouseButton1Click:Connect(function()
		if running then
			stop()
		else
			start()
		end
	end)
	copyBtn.MouseButton1Click:Connect(copyLog)
	clearBtn.MouseButton1Click:Connect(clearLog)
end

buildGui()
log("ready — Probe 1 (Delta)", true)
if not hookmm then
	log("WARNING: hookmetamethod not found", true)
	setStatus("hookmetamethod missing", COL.bad)
end
