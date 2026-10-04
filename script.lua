-- ==================================================
--  Steal a Pet — AC Research Probe 2 (Delta)
--  WalkSpeed threshold ladder → reaction / remotes / pushback
-- ==================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local MAX_LINES = 200
local LOG_VIEW = 70

local LADDER = { 50, 100, 150, 200, 250, 300, 400, 500, 750, 1000 }
local HOLD_SEC = 2.0
local RESET_SEC = 1.0
local BASE_WS = 16
local PUSH_STUD = 2.5 -- soglia spostamento "correzione"

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

local running = false
local abortFlag = false
local lines = {}
local statusLbl, runBtn, logBox
local results = {} -- {ws=, line=}
local remoteHits = {} -- during active step
local stepActive = false
local stepWs = 0
local stepT0 = 0
local stepOrigin = nil
local stepMaxDist = 0
local stepPushAt = nil
local stepKick = false
local stepNotes = {}
local hooks = {}
local charConn

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

local function getHum()
	local c = LP.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function getHrp()
	local c = LP.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function setWs(v)
	local h = getHum()
	if h then
		h.WalkSpeed = v
		return true
	end
	return false
end

local function shortArg(a)
	local t = typeof(a)
	if t == "Instance" then
		local ok, n = pcall(function()
			return a:GetFullName()
		end)
		return ok and n or a.ClassName
	elseif t == "string" then
		if #a > 48 then
			return string.format("%q…", string.sub(a, 1, 48))
		end
		return string.format("%q", a)
	elseif t == "number" then
		return string.format("%.3g", a)
	elseif t == "Vector3" then
		return string.format("(%.1f,%.1f,%.1f)", a.X, a.Y, a.Z)
	elseif t == "CFrame" then
		local p = a.Position
		return string.format("CF(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z)
	elseif t == "table" then
		return "table"
	elseif t == "boolean" then
		return tostring(a)
	end
	return t
end

local function fmtArgs(args)
	local parts = table.create(#args)
	for i = 1, #args do
		parts[i] = shortArg(args[i])
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function interestingRemote(path)
	local low = string.lower(path)
	local keys = {
		"speed",
		"cheat",
		"anti",
		"move",
		"viol",
		"report",
		"kick",
		"ban",
		"dist",
		"tele",
		"pos",
		"valid",
		"secure",
		"moderat",
		"exploit",
		"flag",
		"check",
	}
	for i = 1, #keys do
		if string.find(low, keys[i], 1, true) then
			return true
		end
	end
	return false
end

local function onRemoteOut(path, method, args)
	if not stepActive then
		return
	end
	local hit = {
		path = path,
		method = method,
		args = fmtArgs(args),
		t = os.clock() - stepT0,
		interesting = interestingRemote(path),
	}
	remoteHits[#remoteHits + 1] = hit
	if hit.interesting then
		log(string.format("  REMOTE %.2fs %s:%s %s", hit.t, method, path, hit.args), true)
	end
end

local function installRemoteHook()
	if #hooks > 0 then
		return true
	end
	if not hookmm or not getnamecall then
		log("hookmetamethod/getnamecallmethod missing — remotes not hooked", true)
		return false
	end
	local ok, err = pcall(function()
		local old
		old = hookmm(game, "__namecall", newcclosure(function(self, ...)
			local method = getnamecall()
			if stepActive and typeof(self) == "Instance" then
				if method == "FireServer" or method == "InvokeServer" then
					if self:IsA("RemoteEvent") or self:IsA("RemoteFunction") or self:IsA("UnreliableRemoteEvent") then
						local args = { ... }
						local okp, path = pcall(function()
							return self:GetFullName()
						end)
						onRemoteOut(okp and path or self.Name, method, args)
					end
				end
			end
			return old(self, ...)
		end))
		hooks[#hooks + 1] = true
	end)
	if not ok then
		log("remote hook FAIL " .. tostring(err), true)
		return false
	end
	log("remote FireServer/InvokeServer hook OK", true)
	return true
end

local function watchKickSignals()
	-- Text labels / notifications often appear in PlayerGui
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then
		return
	end
	local conn
	conn = pg.DescendantAdded:Connect(function(d)
		if not stepActive then
			return
		end
		if not d:IsA("TextLabel") and not d:IsA("TextButton") and not d:IsA("TextBox") then
			return
		end
		local t = string.lower(d.Text or "")
		if t == "" then
			return
		end
		if string.find(t, "kick", 1, true)
			or string.find(t, "ban", 1, true)
			or string.find(t, "exploit", 1, true)
			or string.find(t, "cheat", 1, true)
			or string.find(t, "speed", 1, true)
			or string.find(t, "teleport", 1, true)
			or string.find(t, "violat", 1, true)
		then
			stepKick = true
			stepNotes[#stepNotes + 1] = "UI:" .. string.sub(d.Text, 1, 60)
			log("  UI warn: " .. string.sub(d.Text, 1, 80), true)
		end
	end)
	return conn
end

local function beginStep(ws)
	stepActive = true
	stepWs = ws
	stepT0 = os.clock()
	stepMaxDist = 0
	stepPushAt = nil
	stepKick = false
	stepNotes = {}
	remoteHits = {}
	local hrp = getHrp()
	stepOrigin = hrp and hrp.Position or nil
end

local function trackPushback()
	if not stepActive or not stepOrigin then
		return
	end
	local hrp = getHrp()
	if not hrp then
		return
	end
	local d = (hrp.Position - stepOrigin).Magnitude
	if d > stepMaxDist then
		stepMaxDist = d
	end
	-- pushback = ritorno improvviso verso origin dopo essersi allontanati
	-- oppure snap indietro: distanza cala di colpo > PUSH_STUD da un picco
	-- qui loggiamo se durante HOLD la velocità reale è bassa ma WS alto → possibile force
	-- e se Position viene teletrasportata indietro rispetto al frame precedente
end

local lastPos = nil
local function trackSnap()
	if not stepActive then
		return
	end
	local hrp = getHrp()
	if not hrp then
		return
	end
	local p = hrp.Position
	if lastPos then
		local jump = (p - lastPos).Magnitude
		-- snap enorme in 1 frame (~teleport correction)
		if jump >= 8 then
			local age = os.clock() - stepT0
			if not stepPushAt then
				stepPushAt = age
			end
			stepNotes[#stepNotes + 1] = string.format("snap=%.1fstud@%.2fs", jump, age)
			log(string.format("  SNAP %.1f stud at +%.2fs", jump, age), true)
		end
	end
	lastPos = p
	if stepOrigin then
		local d = (p - stepOrigin).Magnitude
		if d > stepMaxDist then
			stepMaxDist = d
		end
	end
end

local function endStep()
	stepActive = false
	local parts = {}
	-- remotes interesting
	local remLines = {}
	for i = 1, #remoteHits do
		local h = remoteHits[i]
		if h.interesting then
			remLines[#remLines + 1] = string.format("%s %s %s", h.method, h.path, h.args)
		end
	end
	-- also keep up to 2 non-interesting if nothing interesting (optional sparse)
	if #remLines == 0 and #remoteHits > 0 then
		-- non loggare tutti — solo count
		parts[#parts + 1] = string.format("%d remotes (none AC-named)", #remoteHits)
	end

	local line
	if stepKick then
		line = string.format("WS=%-4d → KICK/WARN %s", stepWs, table.concat(stepNotes, "; "))
	elseif stepPushAt or (#stepNotes > 0 and string.find(table.concat(stepNotes), "snap", 1, true)) then
		line = string.format(
			"WS=%-4d → PUSHBACK/SNAP react=%.2fs maxDist=%.1f %s",
			stepWs,
			stepPushAt or -1,
			stepMaxDist,
			table.concat(stepNotes, "; ")
		)
	elseif #remLines > 0 then
		line = string.format(
			"WS=%-4d → REMOTE %s | maxDist=%.1f",
			stepWs,
			table.concat(remLines, " || "),
			stepMaxDist
		)
	else
		line = string.format("WS=%-4d → no reaction (maxDist=%.1f)", stepWs, stepMaxDist)
	end

	if #remLines > 0 and not string.find(line, "REMOTE", 1, true) then
		line = line .. " | REMOTE " .. table.concat(remLines, " || ")
	end

	results[#results + 1] = { ws = stepWs, line = line }
	log(line, true)
	lastPos = nil
	stepOrigin = nil
end

local function waitSec(sec)
	local t0 = os.clock()
	while os.clock() - t0 < sec do
		if abortFlag then
			return false
		end
		trackSnap()
		task.wait()
	end
	return true
end

local function printSummary()
	log("======== THRESHOLD SUMMARY ========", true)
	for i = 1, #results do
		log(results[i].line, true)
	end
	log("======== END SUMMARY ========", true)
end

local function runLadder()
	results = {}
	abortFlag = false
	installRemoteHook()
	local kickConn = watchKickSignals()

	local hum = getHum()
	if not hum then
		log("NO HUMANOID — spawn first", true)
		setStatus("no character", COL.bad)
		return
	end

	log("LADDER start — reset WS=" .. BASE_WS, true)
	setWs(BASE_WS)
	if not waitSec(0.5) then
		return
	end

	for i = 1, #LADDER do
		if abortFlag then
			break
		end
		local ws = LADDER[i]
		setStatus(string.format("testing WS=%d …", ws), COL.accent)
		log(string.format("--- step WS=%d hold=%.1fs ---", ws, HOLD_SEC))

		beginStep(ws)
		if not setWs(ws) then
			log(string.format("WS=%-4d → FAIL no humanoid", ws), true)
			results[#results + 1] = { ws = ws, line = string.format("WS=%-4d → FAIL no humanoid", ws) }
			stepActive = false
			break
		end

		if not waitSec(HOLD_SEC) then
			endStep()
			break
		end
		endStep()

		-- reset clean
		setWs(BASE_WS)
		setStatus(string.format("reset WS=%d", BASE_WS), COL.muted)
		if not waitSec(RESET_SEC) then
			break
		end
	end

	setWs(BASE_WS)
	if kickConn then
		kickConn:Disconnect()
	end
	printSummary()
end

local function stop()
	abortFlag = true
	running = false
	stepActive = false
	paintRun()
	setWs(BASE_WS)
	setStatus("stopped", COL.muted)
	log("STOP", true)
end

local function start()
	if running then
		stop()
		return
	end
	if not LP.Character or not getHum() then
		log("Wait for character…", true)
		LP.CharacterAdded:Wait()
		task.wait(0.3)
	end
	running = true
	paintRun()
	log("START Probe 2 — do not teleport; walk OK", true)
	task.spawn(function()
		local ok, err = pcall(runLadder)
		if not ok then
			log("CRASH " .. tostring(err), true)
		end
		running = false
		paintRun()
		setWs(BASE_WS)
		setStatus("done — Copy log", COL.ok)
	end)
end

local function copyLog()
	local text = table.concat(lines, "\n")
	if setclipFn then
		local ok, err = pcall(setclipFn, text)
		if ok then
			setStatus("copied " .. #lines, COL.ok)
			log("COPY ok", true)
		else
			setStatus("copy fail", COL.bad)
			log("COPY err " .. tostring(err), true)
		end
	else
		setStatus("no setclipboard — select text", COL.warn)
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
	local old = pg:FindFirstChild("ACProbe2UI")
	if old then
		old:Destroy()
	end

	local gui = mk("ScreenGui", {
		Name = "ACProbe2UI",
		ResetOnSpawn = false,
		DisplayOrder = 121,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, pg)

	local root = mk("Frame", {
		Size = UDim2.fromOffset(340, 300),
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
		Text = "AC Probe 2 — WS Threshold",
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
		Text = "Delta — open area, then START (~40s)",
		LayoutOrder = 3,
	}, root)

	local shell = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 160),
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
		CanvasSize = UDim2.fromOffset(0, 1100),
	}, shell)

	logBox = mk("TextLabel", {
		Size = UDim2.new(1, -4, 0, 1100),
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
log("ready — Probe 2 WS ladder (Delta)", true)
if not hookmm then
	log("WARNING: no hookmetamethod — remotes limited", true)
end
