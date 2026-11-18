-- Prime Dash / Delta — trova __SG056Control (o equivalente) e testa override.
-- Usa _G, getgenv, getgc. Niente hookmetamethod.

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- override.x/y = Q16 packati (bypass packInput). x=46341 + y=46341 = diagonale piena → void.
-- Default sicuro: fermo (0,0) + salto a impulso solo se grounded (evita dash aereo spam).
local LOOP_DT = 0.05
local LOG_POS_EVERY = 0.5
local JUMP_COOLDOWN = 0.55 -- secondi tra un edge di salto e il successivo
local mode = "jump" -- "jump" = fermo+salto | "move" = diagonale pericolosa (test moto)

local env = _G
pcall(function()
	if typeof(getgenv) == "function" then
		env = getgenv()
	end
end)

if typeof(env.__PrimeDashDeltaCtrl) == "table" and typeof(env.__PrimeDashDeltaCtrl.stop) == "function" then
	pcall(env.__PrimeDashDeltaCtrl.stop)
end

local running = false
local loopToken = 0
local lines = {}
local controlRef = nil -- tabella live trovata (puo' non essere _G.__SG056Control)

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
	local old = parent and parent:FindFirstChild("PrimeDashDeltaCtrl")
	if old then
		pcall(function()
			old:Destroy()
		end)
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "PrimeDashDeltaCtrl"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2147483647
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = host

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(460, 540)
frame.Position = UDim2.new(0.5, -230, 0.5, -270)
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
title.Text = "Prime Dash Delta Control"
title.Parent = frame

local function makeBtn(text, xScale, xOffset, y, color)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(xScale, -16, 0, 34)
	btn.Position = UDim2.new(xOffset, xOffset == 0 and 12 or 4, 0, y)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
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
local modeBtn = makeBtn("MODE: JUMP (safe)", 1, 0, 80, Color3.fromRGB(42, 48, 64))

local logFrame = Instance.new("ScrollingFrame")
logFrame.Position = UDim2.fromOffset(12, 124)
logFrame.Size = UDim2.new(1, -24, 1, -136)
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

local function log(text, color)
	logOrder = logOrder + 1
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

------------------------------------------------------------------- helpers
local NEEDLES = { "sg056", "control", "stumble", "actor" }

local function keyMatch(name)
	local low = string.lower(tostring(name))
	for i = 1, #NEEDLES do
		if string.find(low, NEEDLES[i], 1, true) then
			return true
		end
	end
	return false
end

local function tableKeys(t, limit)
	limit = limit or 24
	local keys = {}
	local ok, err = pcall(function()
		for k in pairs(t) do
			keys[#keys + 1] = tostring(k)
			if #keys >= limit then
				break
			end
		end
	end)
	if not ok then
		return {}, err
	end
	table.sort(keys)
	return keys, nil
end

local function looksLikeControl(t)
	if typeof(t) ~= "table" then
		return false
	end
	local ok, hasOverride, hasActor = pcall(function()
		return t.override ~= nil or rawget(t, "override") ~= nil, t.actor ~= nil or rawget(t, "actor") ~= nil
	end)
	if not ok then
		return false
	end
	-- Deve avere almeno uno dei due campi tipici; preferisci entrambi.
	local ok2, hasVisuals, hasSteps = pcall(function()
		return t.visuals ~= nil, typeof(t.steps) == "number" or typeof(t.snapshots) == "number"
	end)
	if hasOverride and hasActor then
		return true
	end
	if (hasOverride or hasActor) and ok2 and (hasVisuals or hasSteps) then
		return true
	end
	return false
end

local function scoreControl(t)
	local score = 0
	pcall(function()
		if rawget(t, "override") ~= nil or t.override ~= nil then
			score += 3
		end
		if rawget(t, "actor") ~= nil or t.actor ~= nil then
			score += 3
		end
		if t.visuals ~= nil then
			score += 2
		end
		if t.predictedActors ~= nil then
			score += 2
		end
		if typeof(t.steps) == "number" or typeof(t.snapshots) == "number" then
			score += 1
		end
	end)
	return score
end

local function readActorY(actor)
	if typeof(actor) ~= "table" then
		return nil
	end
	local y
	pcall(function()
		if typeof(actor.position) == "table" then
			y = actor.position.y or actor.position.Y
		elseif typeof(actor.y) == "number" then
			y = actor.y
		elseif typeof(actor.Y) == "number" then
			y = actor.Y
		end
	end)
	if typeof(y) ~= "number" then
		return nil
	end
	return y
end

local function addrOf(t)
	local s = tostring(t)
	return s
end

local function scanEnvTable(label, bag, hits, dumped)
	if typeof(bag) ~= "table" then
		log("[SCAN] " .. label .. " non-table (" .. typeof(bag) .. ")", C_WARN)
		return
	end
	local matched = 0
	local ok, err = pcall(function()
		for k, v in pairs(bag) do
			if keyMatch(k) then
				matched += 1
				local keys = {}
				if typeof(v) == "table" then
					keys = tableKeys(v, 18)
					if looksLikeControl(v) then
						hits[#hits + 1] = { source = label .. "." .. tostring(k), table = v, score = scoreControl(v) }
					end
				end
				if #dumped < 40 then
					dumped[#dumped + 1] = true
					log(string.format(
						"[DUMP] %s key=%s type=%s keys=%s",
						label,
						tostring(k),
						typeof(v),
						typeof(v) == "table" and (#keys > 0 and table.concat(keys, ",") or "?") or "-"
					), C_ACT)
				end
			end
			-- Hit diretta sul nome classico
			if tostring(k) == "__SG056Control" and typeof(v) == "table" then
				hits[#hits + 1] = { source = label .. ".__SG056Control", table = v, score = scoreControl(v) + 10 }
			end
		end
	end)
	if not ok then
		log("[SCAN] " .. label .. " errore: " .. tostring(err), C_ERR)
	else
		log(string.format("[SCAN] %s match chiavi=%d", label, matched), C_INFO)
	end
end

local function scanGetsenv(hits)
	local folder = LocalPlayer:FindFirstChild("PlayerScripts")
	local client = folder and folder:FindFirstChild("Stumble056Client")
	if not client then
		log("[SCAN] Stumble056Client LocalScript assente", C_WARN)
		return
	end
	if typeof(getsenv) ~= "function" then
		log("[SCAN] getsenv assente", C_WARN)
		return
	end
	local ok, senv = pcall(getsenv, client)
	if not ok or typeof(senv) ~= "table" then
		log("[SCAN] getsenv Stumble056Client fallito: " .. tostring(senv), C_WARN)
		return
	end
	log("[SCAN] getsenv Stumble056Client ok", C_OK)
	local dumped = {}
	scanEnvTable("getsenv", senv, hits, dumped)
	-- Alcuni executor espongono locali come campi; cerca tabelle control-like
	pcall(function()
		for k, v in pairs(senv) do
			if typeof(v) == "table" and looksLikeControl(v) then
				hits[#hits + 1] = {
					source = "getsenv." .. tostring(k),
					table = v,
					score = scoreControl(v) + 5,
				}
			end
		end
	end)
end

local function scanGetgc(hits)
	if typeof(getgc) ~= "function" then
		log("[GC] getgc assente", C_WARN)
		return
	end
	log("[GC] scansione getgc(true)...", C_ACT)
	local ok, list = pcall(getgc, true)
	if not ok or typeof(list) ~= "table" then
		-- alcuni executor: getgc() senza true
		ok, list = pcall(getgc)
	end
	if not ok or typeof(list) ~= "table" then
		log("[GC] getgc fallito: " .. tostring(list), C_ERR)
		return
	end

	local checked = 0
	local found = 0
	local limit = 120000
	for _, item in pairs(list) do
		checked += 1
		if checked > limit then
			break
		end
		if typeof(item) == "table" and looksLikeControl(item) then
			found += 1
			hits[#hits + 1] = {
				source = "getgc#" .. tostring(found),
				table = item,
				score = scoreControl(item),
				addr = addrOf(item),
			}
			if found >= 12 then
				break
			end
		end
	end
	log(string.format("[GC] controllate~%d tabelle, candidate=%d", checked, found), C_INFO)
end

local function pickBest(hits)
	if #hits == 0 then
		return nil
	end
	table.sort(hits, function(a, b)
		return (a.score or 0) > (b.score or 0)
	end)
	-- dedupe by table identity
	local best = hits[1]
	return best
end

local function discoverControl()
	local hits = {}
	local dumped = {}

	log("=== DISCOVER SG056 CONTROL ===", C_ACT)

	-- 1) ambienti globali
	scanEnvTable("_G", _G, hits, dumped)
	pcall(function()
		if typeof(getgenv) == "function" then
			scanEnvTable("getgenv", getgenv(), hits, dumped)
		end
	end)
	pcall(function()
		if typeof(getrenv) == "function" then
			local renv = getrenv()
			scanEnvTable("getrenv", renv, hits, dumped)
			if typeof(renv) == "table" and typeof(renv._G) == "table" then
				scanEnvTable("getrenv._G", renv._G, hits, dumped)
			end
		end
	end)
	pcall(function()
		if typeof(shared) == "table" then
			scanEnvTable("shared", shared, hits, dumped)
		end
	end)

	-- 2) env dello script client
	scanGetsenv(hits)

	local best = pickBest(hits)
	if best then
		local keys = tableKeys(best.table, 30)
		log("[FOUND] Tabella controllo trovata: " .. best.source .. " score=" .. tostring(best.score), C_OK)
		log("[FOUND] Tabella controllo trovata con chiavi: " .. (#keys > 0 and table.concat(keys, ", ") or "?"), C_OK)
		if best.addr then
			log("[FOUND] addr " .. best.addr, C_INFO)
		end
		return best.table, best.source
	end

	-- 3) fallback getgc
	log("[FALLBACK] _G/getgenv/getsenv senza hit utili → getgc", C_WARN)
	scanGetgc(hits)
	best = pickBest(hits)
	if best then
		local keys = tableKeys(best.table, 30)
		log("[FOUND] via getgc: " .. best.source .. " score=" .. tostring(best.score), C_OK)
		log("[FOUND] Tabella controllo trovata con chiavi: " .. (#keys > 0 and table.concat(keys, ", ") or "?"), C_OK)
		log("[FOUND] addr " .. tostring(best.addr or addrOf(best.table)), C_INFO)
		return best.table, best.source
	end

	log("[FAIL] Nessuna tabella con override/actor trovata", C_ERR)
	return nil, nil
end

local function clearOverride(reason)
	if typeof(controlRef) ~= "table" then
		log("[STOP] Nessun controlRef da pulire (" .. reason .. ")", C_WARN)
		return
	end
	local ok, err = pcall(function()
		controlRef.override = nil
		pcall(function()
			controlRef.overrideHeld = false
			controlRef.overridePunchHeld = false
		end)
	end)
	if ok then
		log("[STOP] Override rimosso (" .. reason .. ")", C_OK)
	else
		log("[STOP] Errore clear: " .. tostring(err), C_ERR)
	end
end

local function stopTest(reason)
	running = false
	loopToken += 1
	clearOverride(reason)
	startBtn.Text = "START"
	startBtn.BackgroundColor3 = Color3.fromRGB(42, 118, 78)
end

local function paintMode()
	if mode == "jump" then
		modeBtn.Text = "MODE: JUMP (safe)"
		modeBtn.BackgroundColor3 = Color3.fromRGB(42, 118, 78)
	else
		modeBtn.Text = "MODE: MOVE+JUMP (void!)"
		modeBtn.BackgroundColor3 = Color3.fromRGB(140, 80, 40)
	end
end

local function moveAxes()
	if mode == "move" then
		return 46341, 46341 -- diagonale Q16: ti butta via dalla piattaforma
	end
	return 0, 0
end

local function isGrounded(actor)
	local ok, grounded = pcall(function()
		local s = actor and actor.s
		if typeof(s) ~= "table" then
			return false
		end
		if s.Grounded == true then
			return true
		end
		local old = s.OldGrounded
		return typeof(old) == "number" and old > 0
	end)
	return ok and grounded == true
end

local function applyOverride(ctrl, wantJump)
	local mx, my = moveAxes()
	ctrl.override = {
		x = mx,
		y = my,
		jump = wantJump == true,
		punch = false,
	}
end

local function startTest()
	if running then
		log("[TEST] Gia' running", C_WARN)
		return
	end

	local ctrl, source = discoverControl()
	if typeof(ctrl) ~= "table" then
		log("[FAIL] Entra in un round con Stumble056Client attivo, poi START.", C_WARN)
		return
	end

	controlRef = ctrl
	running = true
	loopToken += 1
	local token = loopToken
	startBtn.Text = "RUNNING"
	startBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 50)

	local mx, my = moveAxes()
	log(string.format(
		"[TEST] source=%s mode=%s x=%d y=%d jump=edge@%.2fs se grounded",
		tostring(source),
		mode,
		mx,
		my,
		JUMP_COOLDOWN
	), C_ACT)
	log("[TEST] Override sostituisce WASD: con MOVE corri nel void (FallY).", C_WARN)
	log("[TEST] JUMP spam ogni 0.1s = salto+dash aereo. Ora solo impulsi a terra.", C_INFO)

	pcall(function()
		if typeof(getrenv) == "function" then
			local r = getrenv()
			if typeof(r) == "table" and typeof(r._G) == "table" then
				r._G.__SG056Control = ctrl
			end
		end
	end)

	task.spawn(function()
		local ticks = 0
		local lastPosLog = 0
		local lastJumpAt = -math.huge
		local y0 = nil
		local jumpCount = 0

		while running and token == loopToken do
			local okLoop, loopErr = pcall(function()
				if typeof(controlRef) ~= "table" then
					error("controlRef perso")
				end

				local actor = controlRef.actor
				if actor and actor.eliminated == true then
					log("[TEST] eliminated=true → stop automatico (void/laser)", C_ERR)
					stopTest("eliminated")
					return
				end

				local now = os.clock()
				local grounded = isGrounded(actor)
				local wantJump = false
				if grounded and (now - lastJumpAt) >= JUMP_COOLDOWN then
					wantJump = true
					lastJumpAt = now
					jumpCount += 1
					log(string.format("[JUMP] edge #%d (grounded)", jumpCount), C_ACT)
				end

				applyOverride(controlRef, wantJump)
				ticks += 1
				if ticks == 1 or ticks % 40 == 0 then
					local ax, ay = moveAxes()
					log(string.format(
						"[TEST] hold override (#%d) x=%d y=%d grounded=%s",
						ticks,
						ax,
						ay,
						tostring(grounded)
					), C_INFO)
				end

				local y = readActorY(actor)
				if y ~= nil then
					if y0 == nil then
						y0 = y
					end
					if now - lastPosLog >= LOG_POS_EVERY then
						lastPosLog = now
						log(string.format(
							"[ACTOR] y=%d (%.3f u) dy=%d grounded=%s elim=%s",
							y,
							y / 65536,
							y - y0,
							tostring(grounded),
							tostring(actor and actor.eliminated)
						), C_OK)
					end
				elseif ticks == 1 or ticks % 40 == 0 then
					log("[ACTOR] nil o senza position.y", C_WARN)
				end
			end)

			if not okLoop then
				log("[ERR] " .. tostring(loopErr), C_ERR)
				stopTest("errore loop")
				return
			end
			if not running or token ~= loopToken then
				return
			end
			task.wait(LOOP_DT)
		end
	end)
end

local function copyLog()
	if running then
		stopTest("copia log")
	else
		clearOverride("copia log")
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
		log("[MODE] Ferma il test prima di cambiare mode", C_WARN)
		return
	end
	mode = mode == "jump" and "move" or "jump"
	paintMode()
	log("[MODE] " .. mode, C_ACT)
end)

startBtn.MouseButton1Click:Connect(function()
	pcall(startTest)
end)
stopBtn.MouseButton1Click:Connect(function()
	pcall(function()
		stopTest("stop")
	end)
end)
copyBtn.MouseButton1Click:Connect(function()
	pcall(copyLog)
end)

env.__PrimeDashDeltaCtrl = {
	stop = function()
		pcall(function()
			stopTest("shutdown")
		end)
		pcall(function()
			gui:Destroy()
		end)
	end,
	getControl = function()
		return controlRef
	end,
}

log("Delta control ready. Default MODE=JUMP (x=0,y=0, salto grounded).", C_OK)
log("Il log precedente: move diagonale + jump spam → dash → void → FallY.", C_WARN)
log("Cerca in getrenv._G.__SG056Control (confermato dai tuoi log).", C_INFO)
