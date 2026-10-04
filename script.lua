-- ==================================================
--  Steal a Pet — AC Research Probe 2b (Delta)
--  Stationary WS ladder — any HRP move = real correction
-- ==================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local MAX_LINES = 180
local LOG_VIEW = 65

local LADDER = { 50, 100, 150, 200, 250, 300, 400, 500, 750, 1000 }
local HOLD_SEC = 2.0
local RESET_SEC = 1.0
local BASE_WS = 16
local MOVE_EPS = 1.0 -- stud: qualunque spostamento >=1 mentre "fermo" = sospetto

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
local results = {}
local remoteHits = {}
local stepActive = false
local stepWs = 0
local stepT0 = 0
local stepOrigin = nil
local stepMaxDist = 0
local stepFirstMoveAt = nil
local stepKick = false
local stepNotes = {}
local hooks = {}
local inputBlocked = false
local sinkConns = {}

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

local function freezeHumanoid(on)
	local h = getHum()
	if not h then
		return
	end
	if on then
		h:ChangeState(Enum.HumanoidStateType.Physics)
		h.WalkSpeed = 0
		h.JumpPower = 0
		pcall(function()
			h.JumpHeight = 0
		end)
		h.AutoRotate = false
	else
		h.AutoRotate = true
		h.WalkSpeed = BASE_WS
		pcall(function()
			h.JumpPower = 50
		end)
		h:ChangeState(Enum.HumanoidStateType.Running)
	end
end

local function anchorHrp(on)
	local hrp = getHrp()
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		-- NON ancoriamo permanentemente: maschererebbe pushback server.
		-- Solo azzera velocità; posizione libera per vedere correzioni.
	end
end

local function blockMovementInput(on)
	inputBlocked = on
	for i = 1, #sinkConns do
		pcall(function()
			sinkConns[i]:Disconnect()
		end)
	end
	sinkConns = {}
	if not on then
		return
	end
	-- sink WASD / stick (best-effort; user must still not touch keys)
	local keys = {
		Enum.KeyCode.W,
		Enum.KeyCode.A,
		Enum.KeyCode.S,
		Enum.KeyCode.D,
		Enum.KeyCode.Up,
		Enum.KeyCode.Down,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.Space,
	}
	for i = 1, #keys do
		sinkConns[#sinkConns + 1] = UserInputService.InputBegan:Connect(function(input, gp)
			if not inputBlocked then
				return
			end
			if input.KeyCode == keys[i] then
				-- cannot fully eat engine move; warn once
			end
		end)
	end
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
			return string.format("%q…", string.sub(a, 1, 40))
		end
		return string.format("%q", a)
	elseif t == "number" then
		return string.format("%.3g", a)
	elseif t == "Vector3" then
		return string.format("(%.1f,%.1f,%.1f)", a.X, a.Y, a.Z)
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
		"exploit",
		"flag",
		"check",
		"collision",
		"push",
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
		log(string.format("  REMOTE +%.2fs %s %s %s", hit.t, method, path, hit.args), true)
	end
end

local function installRemoteHook()
	if #hooks > 0 then
		return true
	end
	if not hookmm or not getnamecall then
		log("no hookmm/getnamecall — remotes not hooked", true)
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
	log("remote hook OK", true)
	return true
end

local function watchKickUi()
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then
		return nil
	end
	return pg.DescendantAdded:Connect(function(d)
		if not stepActive then
			return
		end
		if not (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) then
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
			or string.find(t, "violat", 1, true)
		then
			stepKick = true
			stepNotes[#stepNotes + 1] = "UI:" .. string.sub(d.Text, 1, 50)
			log("  UI: " .. string.sub(d.Text, 1, 70), true)
		end
	end)
end

local function beginStep(ws)
	stepActive = true
	stepWs = ws
	stepT0 = os.clock()
	stepMaxDist = 0
	stepFirstMoveAt = nil
	stepKick = false
	stepNotes = {}
	remoteHits = {}
	local hrp = getHrp()
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		stepOrigin = hrp.Position
	else
		stepOrigin = nil
	end
end

local function samplePos()
	if not stepActive or not stepOrigin then
		return
	end
	local hrp = getHrp()
	if not hrp then
		return
	end
	-- kill residual client velocity each frame while testing
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	local d = (hrp.Position - stepOrigin).Magnitude
	if d > stepMaxDist then
		stepMaxDist = d
	end
	if d >= MOVE_EPS and not stepFirstMoveAt then
		stepFirstMoveAt = os.clock() - stepT0
		local delta = hrp.Position - stepOrigin
		log(
			string.format(
				"  MOVE +%.2fs dist=%.2f delta=(%.2f,%.2f,%.2f)",
				stepFirstMoveAt,
				d,
				delta.X,
				delta.Y,
				delta.Z
			),
			true
		)
	end
end

local function endStep()
	stepActive = false
	local remLines = {}
	for i = 1, #remoteHits do
		local h = remoteHits[i]
		if h.interesting then
			remLines[#remLines + 1] = string.format("%s %s %s", h.method, h.path, h.args)
		end
	end

	local line
	if stepKick then
		line = string.format("WS=%-4d → KICK/WARN %s", stepWs, table.concat(stepNotes, "; "))
	elseif stepFirstMoveAt then
		line = string.format(
			"WS=%-4d → POSITION CHANGED +%.2fs maxDist=%.2f stud %s",
			stepWs,
			stepFirstMoveAt,
			stepMaxDist,
			#remLines > 0 and ("| REMOTE " .. table.concat(remLines, " || ")) or ""
		)
	elseif #remLines > 0 then
		line = string.format(
			"WS=%-4d → REMOTE (no move) maxDist=%.2f | %s",
			stepWs,
			stepMaxDist,
			table.concat(remLines, " || ")
		)
	elseif #remoteHits > 0 then
		line = string.format(
			"WS=%-4d → no move (maxDist=%.2f) | %d remotes non-AC",
			stepWs,
			stepMaxDist,
			#remoteHits
		)
	else
		line = string.format("WS=%-4d → no reaction (maxDist=%.2f)", stepWs, stepMaxDist)
	end

	results[#results + 1] = { ws = stepWs, line = line }
	log(line, true)
	stepOrigin = nil
end

local function waitSec(sec)
	local t0 = os.clock()
	while os.clock() - t0 < sec do
		if abortFlag then
			return false
		end
		samplePos()
		task.wait()
	end
	return true
end

local function printSummary()
	log("======== STATIONARY SUMMARY ========", true)
	for i = 1, #results do
		log(results[i].line, true)
	end
	log("======== END SUMMARY ========", true)
end

local function runLadder()
	results = {}
	abortFlag = false
	installRemoteHook()
	local kickConn = watchKickUi()

	if not getHum() or not getHrp() then
		log("NO CHARACTER — spawn first", true)
		setStatus("no character", COL.bad)
		return
	end

	log("STATIONARY mode — DO NOT move / jump / shiftlock walk", true)
	blockMovementInput(true)
	freezeHumanoid(true)
	anchorHrp(true)
	setWs(0)
	if not waitSec(0.6) then
		return
	end

	-- baseline drift check
	beginStep(0)
	setWs(0)
	waitSec(0.5)
	local baseline = stepMaxDist
	endStep()
	if results[#results] then
		results[#results].line = string.format("BASELINE WS=0 → maxDist=%.2f (expect <1)", baseline)
		log(results[#results].line, true)
	end
	if baseline >= MOVE_EPS then
		log("WARNING: already drifting while WS=0 — platform/physics noise", true)
	end

	for i = 1, #LADDER do
		if abortFlag then
			break
		end
		local ws = LADDER[i]
		setStatus(string.format("stationary WS=%d …", ws), COL.accent)
		log(string.format("--- step WS=%d hold=%.1fs (STAND STILL) ---", ws, HOLD_SEC))

		beginStep(ws)
		-- set WS but keep velocity zeroed every frame in samplePos
		if not setWs(ws) then
			log(string.format("WS=%-4d → FAIL no humanoid", ws), true)
			results[#results + 1] = { ws = ws, line = string.format("WS=%-4d → FAIL", ws) }
			stepActive = false
			break
		end
		local h = getHum()
		if h then
			h.JumpPower = 0
			pcall(function()
				h.JumpHeight = 0
			end)
		end

		if not waitSec(HOLD_SEC) then
			endStep()
			break
		end
		endStep()

		setWs(0)
		anchorHrp(true)
		setStatus("reset WS=0", COL.muted)
		if not waitSec(RESET_SEC) then
			break
		end
	end

	freezeHumanoid(false)
	blockMovementInput(false)
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
	freezeHumanoid(false)
	blockMovementInput(false)
	setWs(BASE_WS)
	paintRun()
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
		task.wait(0.4)
	end
	running = true
	paintRun()
	log("START Probe 2b — stand still the whole time", true)
	task.spawn(function()
		local ok, err = pcall(runLadder)
		if not ok then
			log("CRASH " .. tostring(err), true)
		end
		running = false
		freezeHumanoid(false)
		blockMovementInput(false)
		setWs(BASE_WS)
		paintRun()
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
	local old = pg:FindFirstChild("ACProbe2bUI")
	if old then
		old:Destroy()
	end

	local gui = mk("ScreenGui", {
		Name = "ACProbe2bUI",
		ResetOnSpawn = false,
		DisplayOrder = 122,
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
		Text = "AC Probe 2b — Stationary WS",
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
		Text = "STAND STILL — then START (~40s)",
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
		CanvasSize = UDim2.fromOffset(0, 1000),
	}, shell)

	logBox = mk("TextLabel", {
		Size = UDim2.new(1, -4, 0, 1000),
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
log("ready — Probe 2b stationary (Delta)", true)
