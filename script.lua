-- ==================================================
--  Steal a Pet — AC Research Probe 3 (Delta)
--  Teleport distance ladder → snapback / remotes / delay
-- ==================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local MAX_LINES = 320
local LOG_VIEW = 90

-- short → mid → long (studs, horizontal only, same Y)
local LADDER = { 5, 10, 25, 50, 100, 200, 300, 400, 600, 700 }
local WATCH_SEC = 2.5
local RESET_SEC = 1.2
local SNAP_STUD = 3.0 -- jump in 1 frame = correction
local BACK_FRAC = 0.35 -- moved back toward origin by this fraction of intended TP
local LOG_FILE = "sap_ac_probe3_log.txt"

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
local stepDist = 0
local stepT0 = 0
local stepOrigin = nil
local stepTarget = nil
local stepReactAt = nil
local stepMaxSnap = 0
local stepClosestToOrigin = nil -- min dist to origin after TP
local stepFarthestFromOrigin = 0
local stepDied = false
local stepKick = false
local stepNotes = {}
local hooks = {}
local lastPos = nil
local diedConn = nil

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

-- Same discovery as probe1/2 for hooks.
local hookmm = findApi("hookmetamethod")
local getnamecall = findApi("getnamecallmethod")
local newcclosure = findApi("newcclosure") or function(f)
	return f
end

--[[
  Clipboard su Delta/LDPlayer:
  setclipboard è spesso un GLOBAL LIBERO dell'executor, NON in _G/getgenv.
  findApi da solo fallisce → Copy "non fa niente".
  Pattern provato (egg_pos_map): typeof(setclipboard) + call diretto.
]]
local function pushClipboard(text)
	local ok, via = false, nil
	pcall(function()
		if typeof(setclipboard) == "function" then
			setclipboard(text)
			ok, via = true, "setclipboard"
		end
	end)
	if not ok then
		pcall(function()
			if typeof(toclipboard) == "function" then
				toclipboard(text)
				ok, via = true, "toclipboard"
			end
		end)
	end
	if not ok then
		pcall(function()
			if typeof(setrbxclipboard) == "function" then
				setrbxclipboard(text)
				ok, via = true, "setrbxclipboard"
			end
		end)
	end
	if not ok then
		local fn = findApi("setclipboard", "toclipboard", "setrbxclipboard")
		if fn then
			local ok2, err = pcall(fn, text)
			if ok2 then
				ok, via = true, "findApi"
			else
				return false, "findApi:" .. tostring(err)
			end
		end
	end
	return ok, via or "none"
end

local function pushFile(path, text)
	local ok = false
	pcall(function()
		if typeof(writefile) == "function" then
			writefile(path, text)
			ok = true
		end
	end)
	if not ok then
		local fn = findApi("writefile")
		if fn then
			ok = pcall(fn, path, text)
		end
	end
	return ok
end

local function stashLog(text)
	pcall(function()
		if typeof(getgenv) == "function" then
			getgenv().SAP_AC_PROBE3_LOG = text
		end
		_G.SAP_AC_PROBE3_LOG = text
	end)
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
		"physic",
		"replicat",
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
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then
		return
	end
	return pg.DescendantAdded:Connect(function(d)
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
			or string.find(t, "teleport", 1, true)
			or string.find(t, "violat", 1, true)
		then
			stepKick = true
			stepNotes[#stepNotes + 1] = "UI:" .. string.sub(d.Text, 1, 60)
			log("  UI warn: " .. string.sub(d.Text, 1, 80), true)
		end
	end)
end

local function bindDied()
	if diedConn then
		diedConn:Disconnect()
		diedConn = nil
	end
	local hum = getHum()
	if not hum then
		return
	end
	diedConn = hum.Died:Connect(function()
		if not stepActive then
			return
		end
		stepDied = true
		local age = os.clock() - stepT0
		stepNotes[#stepNotes + 1] = string.format("DIED@%.2fs", age)
		log(string.format("  DIED at +%.2fs", age), true)
	end)
end

local function doTeleport(studs)
	local hrp = getHrp()
	if not hrp then
		return nil, nil
	end
	local origin = hrp.Position
	-- horizontal only: prefer LookVector flattened, fallback +X
	local look = hrp.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(1, 0, 0)
	else
		flat = flat.Unit
	end
	local dest = origin + flat * studs
	-- keep Y
	dest = Vector3.new(dest.X, origin.Y, dest.Z)

	pcall(function()
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end)
	hrp.CFrame = CFrame.new(dest) * (hrp.CFrame - hrp.CFrame.Position)

	return origin, dest
end

local function beginStep(dist, origin, target)
	stepActive = true
	stepDist = dist
	stepT0 = os.clock()
	stepOrigin = origin
	stepTarget = target
	stepReactAt = nil
	stepMaxSnap = 0
	stepClosestToOrigin = nil
	stepFarthestFromOrigin = 0
	stepDied = false
	stepKick = false
	stepNotes = {}
	remoteHits = {}
	lastPos = target
end

local function trackCorrection()
	if not stepActive or not stepOrigin or not stepTarget then
		return
	end
	local hrp = getHrp()
	if not hrp then
		return
	end
	local p = hrp.Position
	local age = os.clock() - stepT0
	local dOrig = (p - stepOrigin).Magnitude
	local dTgt = (p - stepTarget).Magnitude

	if stepClosestToOrigin == nil or dOrig < stepClosestToOrigin then
		stepClosestToOrigin = dOrig
	end
	if dOrig > stepFarthestFromOrigin then
		stepFarthestFromOrigin = dOrig
	end

	-- frame snap (server rubberband)
	if lastPos then
		local jump = (p - lastPos).Magnitude
		if jump >= SNAP_STUD then
			if jump > stepMaxSnap then
				stepMaxSnap = jump
			end
			if not stepReactAt then
				stepReactAt = age
			end
			local towardOrig = (lastPos - stepOrigin).Magnitude - (p - stepOrigin).Magnitude
			local tag = towardOrig > 1 and "SNAPBACK" or "SNAP"
			stepNotes[#stepNotes + 1] = string.format("%s=%.1f@%.2fs", tag, jump, age)
			-- log only first snap per step (avoid clipboard-killing spam on LDPlayer)
			if #stepNotes <= 1 then
				log(string.format("  %s %.1f stud at +%.2fs (dOrig=%.1f dTgt=%.1f)", tag, jump, age, dOrig, dTgt), true)
			end
		end
	end

	-- gradual pull toward origin without huge frame jump
	local intended = stepDist
	if intended > 0 and dOrig < intended * (1 - BACK_FRAC) then
		if not stepReactAt and age > 0.02 then
			-- only if we actually left origin first
			if stepFarthestFromOrigin >= intended * 0.5 then
				stepReactAt = age
				stepNotes[#stepNotes + 1] = string.format("PULL_BACK dOrig=%.1f@%.2fs", dOrig, age)
				log(string.format("  PULL_BACK dOrig=%.1f at +%.2fs", dOrig, age), true)
			end
		end
	end

	lastPos = p
end

local function endStep()
	stepActive = false
	local hrp = getHrp()
	local final = hrp and hrp.Position or nil
	local dOrig = final and stepOrigin and (final - stepOrigin).Magnitude or -1
	local dTgt = final and stepTarget and (final - stepTarget).Magnitude or -1
	local held = (dTgt >= 0 and dTgt < 4) -- still near destination

	local remLines = {}
	for i = 1, #remoteHits do
		local h = remoteHits[i]
		if h.interesting then
			remLines[#remLines + 1] = string.format("%s %s %s", h.method, h.path, h.args)
		end
	end

	local line
	if stepDied then
		line = string.format(
			"TP=%-3d → DIED react=%.2fs dOrig=%.1f dTgt=%.1f %s",
			stepDist,
			stepReactAt or (os.clock() - stepT0),
			dOrig,
			dTgt,
			table.concat(stepNotes, "; ")
		)
	elseif stepKick then
		line = string.format("TP=%-3d → KICK/WARN %s", stepDist, table.concat(stepNotes, "; "))
	elseif stepReactAt then
		line = string.format(
			"TP=%-3d → CORRECTED react=%.2fs maxSnap=%.1f final dOrig=%.1f dTgt=%.1f %s",
			stepDist,
			stepReactAt,
			stepMaxSnap,
			dOrig,
			dTgt,
			table.concat(stepNotes, "; ")
		)
	elseif held then
		line = string.format(
			"TP=%-3d → HELD (no correction %.1fs) dOrig=%.1f dTgt=%.1f remotes=%d",
			stepDist,
			WATCH_SEC,
			dOrig,
			dTgt,
			#remoteHits
		)
	else
		line = string.format(
			"TP=%-3d → drifted dOrig=%.1f dTgt=%.1f remotes=%d %s",
			stepDist,
			dOrig,
			dTgt,
			#remoteHits,
			table.concat(stepNotes, "; ")
		)
	end

	if #remLines > 0 then
		line = line .. " | REMOTE " .. table.concat(remLines, " || ")
	elseif #remoteHits > 0 and not string.find(line, "remotes=", 1, true) then
		line = line .. string.format(" | %d remotes (none AC-named)", #remoteHits)
	end

	results[#results + 1] = { dist = stepDist, line = line }
	log(line, true)
	lastPos = nil
	stepOrigin = nil
	stepTarget = nil
end

local function waitSec(sec)
	local t0 = os.clock()
	while os.clock() - t0 < sec do
		if abortFlag then
			return false
		end
		trackCorrection()
		task.wait()
	end
	return true
end

local function printSummary()
	log("======== TELEPORT SUMMARY ========", true)
	for i = 1, #results do
		log(results[i].line, true)
	end
	local firstHit = nil
	for i = 1, #results do
		local L = results[i].line
		if string.find(L, "CORRECTED", 1, true)
			or string.find(L, "DIED", 1, true)
			or string.find(L, "KICK", 1, true)
		then
			firstHit = results[i].dist
			break
		end
	end
	if firstHit then
		log(string.format("first reaction at TP>=%d stud", firstHit), true)
	else
		log("no server correction observed in ladder", true)
	end
	log("======== END SUMMARY ========", true)
end

local function runLadder()
	results = {}
	abortFlag = false
	installRemoteHook()
	local kickConn = watchKickSignals()
	bindDied()

	if not getHum() or not getHrp() then
		log("NO CHARACTER — spawn first", true)
		setStatus("no character", COL.bad)
		return
	end

	log("LADDER start — stand still, open area", true)
	if not waitSec(0.4) then
		return
	end

	for i = 1, #LADDER do
		if abortFlag then
			break
		end
		if not getHrp() or not getHum() or getHum().Health <= 0 then
			log("character gone — abort", true)
			break
		end

		local dist = LADDER[i]
		setStatus(string.format("TP %d stud …", dist), COL.accent)
		log(string.format("--- TP %d stud watch=%.1fs ---", dist, WATCH_SEC))

		local origin, target = doTeleport(dist)
		if not origin then
			log(string.format("TP=%-3d → FAIL no HRP", dist), true)
			results[#results + 1] = { dist = dist, line = string.format("TP=%-3d → FAIL no HRP", dist) }
			break
		end

		beginStep(dist, origin, target)
		log(string.format("  warped +%d → (%.1f,%.1f,%.1f)", dist, target.X, target.Y, target.Z))

		if not waitSec(WATCH_SEC) then
			endStep()
			break
		end
		endStep()

		-- pause between hops (stay where we are — no forced return)
		setStatus(string.format("pause %.1fs", RESET_SEC), COL.muted)
		if not waitSec(RESET_SEC) then
			break
		end

		-- rebind died if respawned mid-run
		bindDied()
	end

	if kickConn then
		kickConn:Disconnect()
	end
	if diedConn then
		diedConn:Disconnect()
		diedConn = nil
	end
	printSummary()
end

local function stop()
	abortFlag = true
	running = false
	stepActive = false
	paintRun()
	setStatus("stopped", COL.muted)
	log("STOP", true)
end

-- forward decl: start() chiama copyLog a fine run
local copyLog

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
	log("START Probe 3 — teleport ladder (stay still between hops)", true)
	task.spawn(function()
		local ok, err = pcall(runLadder)
		if not ok then
			log("CRASH " .. tostring(err), true)
		end
		running = false
		paintRun()
		log("auto-copy…", true)
		copyLog()
	end)
end

copyLog = function()
	local text = table.concat(lines, "\n")
	if text == "" then
		setStatus("log empty", COL.warn)
		return
	end

	stashLog(text)

	local okClip, via = pushClipboard(text)
	local okFile = pushFile(LOG_FILE, text)

	if okClip and okFile then
		setStatus("COPIED " .. #lines .. " + file", COL.ok)
		log("COPY ok via " .. tostring(via) .. " + writefile " .. LOG_FILE, true)
	elseif okClip then
		setStatus("COPIED " .. #lines .. " (" .. tostring(via) .. ")", COL.ok)
		log("COPY ok via " .. tostring(via), true)
	elseif okFile then
		setStatus("SAVED " .. LOG_FILE .. " (clip fail)", COL.warn)
		log("COPY clipboard FAIL — writefile OK " .. LOG_FILE, true)
	else
		setStatus("COPY FAIL", COL.bad)
		log("COPY FAIL clip=" .. tostring(via) .. " file=false", true)
		log("Prova in console Delta: setclipboard(getgenv().SAP_AC_PROBE3_LOG)", true)
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
	local old = pg:FindFirstChild("ACProbe3UI")
	if old then
		old:Destroy()
	end

	-- Layout IDENTICO a probe_constants_dump (Copy funzionante li)
	local gui = mk("ScreenGui", {
		Name = "ACProbe3UI",
		ResetOnSpawn = false,
		DisplayOrder = 124,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, pg)

	local root = mk("Frame", {
		Size = UDim2.fromOffset(360, 320),
		Position = UDim2.fromOffset(16, 90),
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
		Text = "AC Probe 3 — Teleport",
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
		Text = "Delta — open area, stand still, START",
		LayoutOrder = 3,
	}, root)

	local shell = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 180),
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
		CanvasSize = UDim2.fromOffset(0, 2200),
	}, shell)

	logBox = mk("TextLabel", {
		Size = UDim2.new(1, -4, 0, 2200),
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
		AutoButtonColor = true,
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
		AutoButtonColor = true,
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

-- boot ping: verifica REALE clipboard subito
do
	local ok, via = pushClipboard("sap_probe3_clipboard_ping")
	if ok then
		log("ready — Probe 3 | clipboard=" .. tostring(via) .. " OK", true)
		setStatus("clipboard " .. tostring(via) .. " OK", COL.ok)
	else
		local okF = pushFile(LOG_FILE, "ping")
		log("ready — Probe 3 | clipboard=MISSING writefile=" .. tostring(okF), true)
		setStatus(okF and "no clip — usera file" or "COPY API MISSING", okF and COL.warn or COL.bad)
	end
end
if not hookmm then
	log("WARNING: no hookmetamethod — remotes limited", true)
end
