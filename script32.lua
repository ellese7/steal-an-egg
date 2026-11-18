-- Prime Dash / Delta — fly probe su actor.position / body.Velocity
-- Handle: getrenv()._G.__SG056Control
-- Niente hookmetamethod. Solo tabelle + Heartbeat/task.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local UNIT_SCALE = 25 / 7
local Q16 = 65536
local LOG_DT = 0.1
local FLY_STUDS_PER_SEC = 18 -- target salita (studs/s) → convertita in Q16 sim
local POS_BUMP_STUDS = 0.35 -- bump position.y per tick in mode POSITION/BOTH

local MODE = "VELOCITY" -- VELOCITY | POSITION | BOTH | HOLD (solo log)

local env = _G
pcall(function()
	if typeof(getgenv) == "function" then
		env = getgenv()
	end
end)

if typeof(env.__PrimeDashFlyProbe) == "table" and typeof(env.__PrimeDashFlyProbe.stop) == "function" then
	pcall(env.__PrimeDashFlyProbe.stop)
end

local running = false
local token = 0
local lines = {}
local controlRef = nil
local conns = {}

local function track(conn)
	conns[#conns + 1] = conn
	return conn
end

local function clearConns()
	for i = 1, #conns do
		pcall(function()
			conns[i]:Disconnect()
		end)
	end
	table.clear(conns)
end

------------------------------------------------------------------- math Q16 / world
local function studsToSimQ16(studs)
	return math.floor((studs / UNIT_SCALE) * Q16 + (studs < 0 and -0.5 or 0.5))
end

local function simQ16ToStuds(raw)
	if typeof(raw) ~= "number" then
		return 0
	end
	return (raw / Q16) * UNIT_SCALE
end

local function flyVelocityY()
	return studsToSimQ16(FLY_STUDS_PER_SEC)
end

local function posBumpY()
	return studsToSimQ16(POS_BUMP_STUDS)
end

------------------------------------------------------------------- GUI
local function guiParent()
	if typeof(gethui) == "function" then
		local ok, host = pcall(gethui)
		if ok and typeof(host) == "Instance" then
			return host
		end
	end
	local ok, core = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and core then
		return core
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local host = guiParent()
for _, parent in ipairs({ host, LocalPlayer:FindFirstChild("PlayerGui") }) do
	local old = parent and parent:FindFirstChild("PrimeDashFlyProbe")
	if old then
		pcall(function()
			old:Destroy()
		end)
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "PrimeDashFlyProbe"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2147483647
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = host

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(480, 560)
frame.Position = UDim2.new(0.5, -240, 0.5, -280)
frame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
frame.BackgroundTransparency = 0.05
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.ZIndex = 1000
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(90, 140, 210)
stroke.Thickness = 1.2
stroke.Transparency = 0.35
stroke.Parent = frame

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -24, 0, 22)
title.Position = UDim2.fromOffset(12, 10)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(235, 240, 248)
title.Text = "Prime Dash Fly Probe (Delta)"
title.Parent = frame

local function makeBtn(text, xScale, xOffset, y, color)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(xScale, -16, 0, 32)
	btn.Position = UDim2.new(xOffset, xOffset == 0 and 12 or 4, 0, y)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Text = text
	btn.Parent = frame
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = btn
	return btn
end

local startBtn = makeBtn("START", 1 / 3, 0, 40, Color3.fromRGB(42, 118, 78))
local stopBtn = makeBtn("STOP", 1 / 3, 1 / 3, 40, Color3.fromRGB(140, 60, 60))
local copyBtn = makeBtn("COPIA LOG", 1 / 3, 2 / 3, 40, Color3.fromRGB(45, 95, 170))
local modeBtn = makeBtn("MODE: VELOCITY", 1, 0, 78, Color3.fromRGB(42, 48, 64))

local logFrame = Instance.new("ScrollingFrame")
logFrame.Position = UDim2.fromOffset(12, 118)
logFrame.Size = UDim2.new(1, -24, 1, -130)
logFrame.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
logFrame.BackgroundTransparency = 0.2
logFrame.BorderSizePixel = 0
logFrame.ScrollBarThickness = 5
logFrame.ScrollBarImageColor3 = Color3.fromRGB(90, 140, 210)
logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
logFrame.Parent = frame

local logCorner = Instance.new("UICorner")
logCorner.CornerRadius = UDim.new(0, 8)
logCorner.Parent = logFrame

local logPad = Instance.new("UIPadding")
logPad.PaddingLeft = UDim.new(0, 8)
logPad.PaddingRight = UDim.new(0, 8)
logPad.PaddingTop = UDim.new(0, 6)
logPad.PaddingBottom = UDim.new(0, 6)
logPad.Parent = logFrame

local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 2)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Parent = logFrame

local logOrder = 0
local C_INFO = Color3.fromRGB(205, 212, 222)
local C_OK = Color3.fromRGB(70, 200, 120)
local C_WARN = Color3.fromRGB(230, 170, 60)
local C_ACT = Color3.fromRGB(110, 175, 240)
local C_ERR = Color3.fromRGB(230, 90, 90)
local C_WIN = Color3.fromRGB(80, 230, 180)

local function log(text, color)
	logOrder += 1
	lines[#lines + 1] = text
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = Enum.Font.Code
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.LayoutOrder = logOrder
	label.TextColor3 = color or C_INFO
	label.Text = text
	label.Parent = logFrame
	task.defer(function()
		logFrame.CanvasPosition = Vector2.new(0, logFrame.AbsoluteCanvasSize.Y)
	end)
end

------------------------------------------------------------------- control / actor
local function getGameG()
	local ok, renv = pcall(function()
		return getrenv()
	end)
	if ok and typeof(renv) == "table" and typeof(renv._G) == "table" then
		return renv._G
	end
	if typeof(_G) == "table" then
		return _G
	end
	return nil
end

local function getControl()
	local g = getGameG()
	if typeof(g) == "table" and typeof(g.__SG056Control) == "table" then
		return g.__SG056Control, "getrenv._G.__SG056Control"
	end
	local ok, genv = pcall(function()
		return getgenv()
	end)
	if ok and typeof(genv) == "table" and typeof(genv.__SG056Control) == "table" then
		return genv.__SG056Control, "getgenv.__SG056Control"
	end
	return nil, nil
end

local function getActor(ctrl)
	if typeof(ctrl) ~= "table" then
		return nil
	end
	local actor = ctrl.actor
	if typeof(actor) == "table" then
		return actor
	end
	return nil
end

local function readXYZ(t)
	if typeof(t) ~= "table" then
		return nil, nil, nil
	end
	local x = t.x
	if x == nil then
		x = t.X
	end
	local y = t.y
	if y == nil then
		y = t.Y
	end
	local z = t.z
	if z == nil then
		z = t.Z
	end
	if typeof(x) ~= "number" or typeof(y) ~= "number" or typeof(z) ~= "number" then
		return nil, nil, nil
	end
	return x, y, z
end

local function readPos(actor)
	if typeof(actor) ~= "table" then
		return nil, nil, nil
	end
	return readXYZ(actor.position)
end

local function readVel(actor)
	if typeof(actor) ~= "table" or typeof(actor.body) ~= "table" then
		return nil, nil, nil
	end
	local body = actor.body
	local vel = body.Velocity or body.velocity
	return readXYZ(vel)
end

local function writeVelY(actor, yRaw)
	local body = actor.body
	if typeof(body) ~= "table" then
		return false, "no body"
	end
	local vel = body.Velocity or body.velocity
	if typeof(vel) ~= "table" then
		return false, "no Velocity"
	end
	if vel.y ~= nil then
		vel.y = yRaw
		return true
	end
	if vel.Y ~= nil then
		vel.Y = yRaw
		return true
	end
	return false, "no y field"
end

local function writePosY(actor, yRaw)
	local pos = actor.position
	if typeof(pos) ~= "table" then
		return false, "no position"
	end
	if pos.y ~= nil then
		pos.y = yRaw
		return true
	end
	if pos.Y ~= nil then
		pos.Y = yRaw
		return true
	end
	return false, "no y field"
end

local function holdOverride(ctrl)
	-- fermo: niente diagonale void; jump off
	ctrl.override = {
		x = 0,
		y = 0,
		jump = false,
		punch = false,
	}
	pcall(function()
		ctrl.overrideHeld = false
		ctrl.overridePunchHeld = false
	end)
end

local function clearOverride(ctrl, reason)
	if typeof(ctrl) ~= "table" then
		log("[STOP] no control (" .. reason .. ")", C_WARN)
		return
	end
	local ok, err = pcall(function()
		ctrl.override = nil
		ctrl.overrideHeld = false
		ctrl.overridePunchHeld = false
	end)
	if ok then
		log("[STOP] override=nil (" .. reason .. ")", C_OK)
	else
		log("[STOP] clear fail: " .. tostring(err), C_ERR)
	end
end

------------------------------------------------------------------- modes UI
local MODES = { "VELOCITY", "POSITION", "BOTH", "HOLD" }

local function paintMode()
	modeBtn.Text = "MODE: " .. MODE
	if MODE == "VELOCITY" then
		modeBtn.BackgroundColor3 = Color3.fromRGB(42, 118, 78)
	elseif MODE == "POSITION" then
		modeBtn.BackgroundColor3 = Color3.fromRGB(45, 95, 170)
	elseif MODE == "BOTH" then
		modeBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 40)
	else
		modeBtn.BackgroundColor3 = Color3.fromRGB(42, 48, 64)
	end
end

------------------------------------------------------------------- run
local function stopProbe(reason)
	running = false
	token += 1
	clearConns()
	clearOverride(controlRef, reason)
	startBtn.Text = "START"
	startBtn.BackgroundColor3 = Color3.fromRGB(42, 118, 78)
end

local function applyFly(actor)
	if MODE == "HOLD" then
		return "hold", nil, nil
	end
	local vy = flyVelocityY()
	local bump = posBumpY()
	local vOk, vErr, pOk, pErr

	if MODE == "VELOCITY" or MODE == "BOTH" then
		vOk, vErr = writeVelY(actor, vy)
		-- azzera anche force Y se presente (riduce push gravità locale)
		pcall(function()
			local f = actor.body.Force
			if typeof(f) == "table" and typeof(f.y) == "number" then
				f.y = 0
			end
		end)
	end

	if MODE == "POSITION" or MODE == "BOTH" then
		local _, y = readPos(actor)
		if y ~= nil then
			pOk, pErr = writePosY(actor, y + bump)
		else
			pOk, pErr = false, "no y"
		end
	end

	return MODE, vOk, vErr, pOk, pErr
end

local function startProbe()
	if running then
		log("[TEST] already running", C_WARN)
		return
	end

	local ctrl, source = getControl()
	if typeof(ctrl) ~= "table" then
		log("[FAIL] __SG056Control assente. Entra in round su Delta.", C_ERR)
		return
	end

	local actor = getActor(ctrl)
	if typeof(actor) ~= "table" then
		log("[FAIL] control.actor nil — aspetta attach gameplay", C_ERR)
		return
	end

	controlRef = ctrl
	running = true
	token += 1
	local my = token
	startBtn.Text = "FLYING"
	startBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 50)

	local px, py, pz = readPos(actor)
	local vx, vy, vz = readVel(actor)
	local targetVy = flyVelocityY()

	log("=== FLY PROBE ===", C_ACT)
	log("source=" .. tostring(source) .. " mode=" .. MODE, C_INFO)
	log(string.format(
		"UnitScale=%.6f Q16=%d flyVyQ16=%d (%.1f studs/s) bump=%.2f studs",
		UNIT_SCALE,
		Q16,
		targetVy,
		FLY_STUDS_PER_SEC,
		POS_BUMP_STUDS
	), C_INFO)
	log(string.format(
		"[BASE] pos=%s,%s,%s vel=%s,%s,%s",
		tostring(px),
		tostring(py),
		tostring(pz),
		tostring(vx),
		tostring(vy),
		tostring(vz)
	), C_OK)
	log("[TEST] override x=0 y=0 jump=false mentre forziamo fisica", C_INFO)
	log("[WARN] prediction locale: snap server / FallY / laser ancora validi", C_WARN)

	local yStart = py
	local yPeak = py or 0
	local successArmed = false
	local snapCount = 0
	local lastY = py
	local lastLog = 0
	local writes = 0
	local writeFails = 0

	-- write ogni frame (sim ~30Hz, Heartbeat tipicamente più fitto)
	track(RunService.Heartbeat:Connect(function()
		if not running or my ~= token then
			return
		end
		local ok, err = pcall(function()
			holdOverride(controlRef)
			local a = getActor(controlRef)
			if typeof(a) ~= "table" then
				return
			end
			if a.eliminated == true then
				log("[FAIL] eliminated=true durante fly (void/laser/server)", C_ERR)
				stopProbe("eliminated")
				return
			end
			local _, vOk, vErr, pOk, pErr = applyFly(a)
			writes += 1
			if MODE ~= "HOLD" then
				if (MODE == "VELOCITY" or MODE == "BOTH") and vOk == false then
					writeFails += 1
					if writeFails <= 3 then
						log("[ERR] velocity write: " .. tostring(vErr), C_ERR)
					end
				end
				if (MODE == "POSITION" or MODE == "BOTH") and pOk == false then
					writeFails += 1
					if writeFails <= 3 then
						log("[ERR] position write: " .. tostring(pErr), C_ERR)
					end
				end
			end
		end)
		if not ok then
			log("[ERR] heartbeat: " .. tostring(err), C_ERR)
		end
	end))

	-- log / success detection a 0.1s
	task.spawn(function()
		while running and my == token do
			local ok, err = pcall(function()
				local a = getActor(controlRef)
				if typeof(a) ~= "table" then
					log("[WARN] actor nil", C_WARN)
					return
				end
				local x, y, z = readPos(a)
				local vx2, vy2, vz2 = readVel(a)
				local now = os.clock()
				if now - lastLog >= LOG_DT then
					lastLog = now
					log(string.format(
						"[MON] pos.x=%s pos.y=%s (%.2f st) pos.z=%s | vel=%s,%s,%s | w=%d",
						tostring(x),
						tostring(y),
						simQ16ToStuds(y or 0),
						tostring(z),
						tostring(vx2),
						tostring(vy2),
						tostring(vz2),
						writes
					), C_ACT)

					if typeof(y) == "number" then
						if y > yPeak then
							yPeak = y
						end
						if typeof(yStart) == "number" then
							local riseStuds = simQ16ToStuds(y - yStart)
							if riseStuds >= 2.5 and not successArmed then
								successArmed = true
								log(string.format(
									"[SUCCESS] Stiamo volando! dy=%.2f studs (y %d -> %d) mode=%s",
									riseStuds,
									yStart,
									y,
									MODE
								), C_WIN)
							end
						end
						-- snap detection: crollo improvviso verso il basso mentre forziamo su
						if typeof(lastY) == "number" and MODE ~= "HOLD" then
							local drop = lastY - y
							if drop > studsToSimQ16(3) then
								snapCount += 1
								log(string.format(
									"[SNAP?] y drop Q16 %d (~%.2f studs) count=%d — possibile reconcile server",
									drop,
									simQ16ToStuds(drop),
									snapCount
								), C_WARN)
								if snapCount >= 4 then
									log("[FAIL] snap ripetuti: server/sim ributta giu la prediction", C_ERR)
								end
							end
						end
						lastY = y
					end
				end
			end)
			if not ok then
				log("[ERR] mon: " .. tostring(err), C_ERR)
			end
			task.wait(LOG_DT)
		end
	end)
end

local function copyLog()
	if running then
		stopProbe("copia log")
	else
		clearOverride(controlRef, "copia log")
	end
	local text = table.concat(lines, "\n")
	local copied = false
	if typeof(setclipboard) == "function" then
		copied = pcall(setclipboard, text)
	end
	if not copied and typeof(toclipboard) == "function" then
		copied = pcall(toclipboard, text)
	end
	copyBtn.Text = copied and "COPIATO" or "NO CLIPBOARD"
	task.delay(1.2, function()
		if copyBtn and copyBtn.Parent then
			copyBtn.Text = "COPIA LOG"
		end
	end)
end

paintMode()

modeBtn.MouseButton1Click:Connect(function()
	if running then
		log("[MODE] STOP prima di cambiare mode", C_WARN)
		return
	end
	local idx = 1
	for i = 1, #MODES do
		if MODES[i] == MODE then
			idx = i
			break
		end
	end
	MODE = MODES[(idx % #MODES) + 1]
	paintMode()
	log("[MODE] " .. MODE, C_ACT)
end)

startBtn.MouseButton1Click:Connect(function()
	pcall(startProbe)
end)
stopBtn.MouseButton1Click:Connect(function()
	pcall(function()
		stopProbe("stop")
	end)
end)
copyBtn.MouseButton1Click:Connect(function()
	pcall(copyLog)
end)

env.__PrimeDashFlyProbe = {
	stop = function()
		pcall(function()
			stopProbe("shutdown")
		end)
		pcall(function()
			gui:Destroy()
		end)
	end,
}

log("Fly probe ready. getrenv()._G.__SG056Control.actor + Velocity/position.", C_OK)
log("MODE: VELOCITY (default) | POSITION | BOTH | HOLD. Override fermo in aria.", C_INFO)
log(string.format("Target +%.0f studs/s → vel.y Q16=%d", FLY_STUDS_PER_SEC, flyVelocityY()), C_INFO)
