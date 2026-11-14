-- PSX Stayso — Admin Trust Boundary Mapper (Delta)
-- Probe difensivo: verifica se il server valida i permessi admin
-- o si fida del client. GUI: START + COPIA LOG.
-- Non esegue grant massivi / ban / shutdown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local PAUSE = 2
local MAX_LOG = 400

local env = _G
pcall(function()
	if typeof(getgenv) == "function" then
		env = getgenv()
	end
end)
if typeof(env.__AdminTrustMapper) == "table" and typeof(env.__AdminTrustMapper.stop) == "function" then
	pcall(env.__AdminTrustMapper.stop)
end

local function api(name)
	local v
	pcall(function()
		v = getgenv()[name]
	end)
	if typeof(v) == "function" then
		return v
	end
	pcall(function()
		v = _G[name]
	end)
	return typeof(v) == "function" and v or nil
end

local setclipboard = api("setclipboard") or api("toclipboard") or api("set_clipboard")

local alive = true
local running = false
local gen = 0
local Network
local startBtn, copyBtn, statusLbl, logBox, gui
local logLines = {}

local function now()
	return os.date("%H:%M:%S")
end

local function refreshLogBox()
	if not logBox then
		return
	end
	logBox.Text = table.concat(logLines, "\n")
	logBox.CursorPosition = #logBox.Text + 1
end

local function log(msg)
	local line = string.format("[%s] %s", now(), tostring(msg))
	logLines[#logLines + 1] = line
	while #logLines > MAX_LOG do
		table.remove(logLines, 1)
	end
	print("[AdminTrust] " .. tostring(msg))
	refreshLogBox()
end

local function setStatus(t)
	if statusLbl then
		statusLbl.Text = t
	end
end

local function paint()
	if startBtn then
		startBtn.Text = running and "STOP" or "START"
		startBtn.BackgroundColor3 = running and Color3.fromRGB(120, 50, 50) or Color3.fromRGB(40, 110, 70)
	end
end

local function copyLogs()
	local text = table.concat(logLines, "\n")
	if text == "" then
		text = "(empty)"
	end
	local ok = typeof(setclipboard) == "function" and pcall(setclipboard, text)
	if logBox then
		logBox.Text = text
	end
	if copyBtn then
		copyBtn.Text = ok and "COPIATO!" or "Select+CtrlC"
		task.delay(1.2, function()
			if copyBtn and alive then
				copyBtn.Text = "COPIA LOG"
			end
		end)
	end
	log(ok and "logs copied" or "clipboard fail — testo nel box")
end

local function dumpValue(v)
	local t = typeof(v)
	if t == "nil" then
		return "nil"
	end
	if t == "boolean" or t == "number" then
		return tostring(v)
	end
	if t == "string" then
		local s = v
		if #s > 120 then
			s = string.sub(s, 1, 120) .. "..."
		end
		return string.format("%q", s)
	end
	if t == "table" then
		local parts = {}
		local n = 0
		for k, val in pairs(v) do
			n += 1
			if n > 8 then
				parts[#parts + 1] = "..."
				break
			end
			parts[#parts + 1] = tostring(k) .. "=" .. tostring(val)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return t .. ":" .. tostring(v)
end

local function classify(ok, a, b)
	if not ok then
		return "ERROR"
	end
	if a == false then
		return "DENIED"
	end
	if a == nil and b == nil then
		return "DENIED"
	end
	if typeof(a) == "string" then
		local low = string.lower(a)
		if string.find(low, "not authorized", 1, true)
			or string.find(low, "no permission", 1, true)
			or string.find(low, "denied", 1, true)
			or string.find(low, "unauthorized", 1, true)
		then
			return "DENIED"
		end
		if string.find(low, "fail", 1, true) or string.find(low, "invalid", 1, true) then
			return "DENIED"
		end
	end
	if a == true then
		return "OK"
	end
	-- risposta non-nil non-false: server ha risposto qualcosa di utile
	if a ~= nil then
		return "OK"
	end
	return "DENIED"
end

local function tryRequire(pathParts, timeout)
	timeout = timeout or 6
	local ok, mod = pcall(function()
		local cur = ReplicatedStorage
		for i = 1, #pathParts do
			cur = cur:WaitForChild(pathParts[i], timeout)
			if not cur then
				error("missing " .. tostring(pathParts[i]))
			end
		end
		return require(cur)
	end)
	return ok, mod
end

local function loadNetwork()
	-- Preferenza Stayso/Panel: Framework.Library (con timeout). Fallback Library.Network.
	local ok, lib = tryRequire({ "Framework", "Library" }, 5)
	if ok and typeof(lib) == "table" then
		local deadline = os.clock() + 8
		while typeof(lib.Loaded) == "boolean" and not lib.Loaded and os.clock() < deadline do
			task.wait(0.1)
		end
		if typeof(lib.Network) == "table" and typeof(lib.Network.Invoke) == "function" then
			Network = lib.Network
			return true, "Framework.Library.Network"
		end
	end

	ok, lib = tryRequire({ "Library", "Network" }, 5)
	if ok and typeof(lib) == "table" and typeof(lib.Invoke) == "function" then
		Network = lib
		return true, "Library.Network"
	end

	return false, "Network non trovato"
end

local function invokeRaw(remoteName, ...)
	local args = table.pack(...)
	local ok, a, b, c = pcall(function()
		return Network.Invoke(remoteName, table.unpack(args, 1, args.n))
	end)
	if not ok then
		return false, a, nil
	end
	return true, a, b, c
end

local function logAuth(label, ok, a, b)
	local resp
	if not ok then
		resp = "ERROR: " .. dumpValue(a)
	else
		-- CanOpen: logga true/false/nil esplicitamente
		if a == true then
			resp = "true"
		elseif a == false then
			resp = "false"
		elseif a == nil then
			resp = "nil"
		else
			resp = dumpValue(a)
		end
		if b ~= nil then
			resp = resp .. " | extra=" .. dumpValue(b)
		end
	end
	local esito = classify(ok, a, b)
	log(string.format("[AUTH] CanOpen -> %s", resp))
	log(string.format("[TEST] %s | Risposta: %s | Esito: %s", label, resp, esito))
	return esito
end

local function logCmd(cmd, ok, a, b)
	local resp
	if not ok then
		resp = "ERROR: " .. dumpValue(a)
	else
		local parts = {}
		if a ~= nil then
			parts[#parts + 1] = dumpValue(a)
		else
			parts[#parts + 1] = "nil"
		end
		if b ~= nil then
			parts[#parts + 1] = "b=" .. dumpValue(b)
		end
		resp = table.concat(parts, " ")
	end
	local esito = classify(ok, a, b)
	log(string.format("[CMD] %s -> %s", cmd, resp))
	log(string.format("[TEST] %s | Risposta: %s | Esito: %s", cmd, resp, esito))
	return esito
end

local function stopRun()
	gen += 1
	running = false
	paint()
	setStatus("stopped")
end

local function stopAll()
	alive = false
	stopRun()
	if gui then
		pcall(function()
			gui:Destroy()
		end)
		gui = nil
	end
end

local function runSuite(my)
	setStatus("1/3 AUTH CanOpen")
	log("--- TEST 1: Autorizzazione Base ---")
	local ok, a, b = invokeRaw("AdminPanelCanOpen")
	local e1 = logAuth("AdminPanelCanOpen", ok, a, b)

	if my ~= gen or not alive then
		return
	end
	task.wait(PAUSE)
	if my ~= gen or not alive then
		return
	end

	setStatus("2/3 CMD jumppower")
	log("--- TEST 2: Playful jumppower ---")
	-- Formato UI ufficiale: {Player, Number}. Probe richiesto: {"100"}
	ok, a, b = invokeRaw("AdminPanelCommand", "jumppower", { "100" })
	local e2 = logCmd("jumppower", ok, a, b)

	if my ~= gen or not alive then
		return
	end
	task.wait(PAUSE)
	if my ~= gen or not alive then
		return
	end

	setStatus("3/3 CMD coins")
	log("--- TEST 3: Economy coins ---")
	-- Formato UI ufficiale: {Player, Number}. Probe richiesto: {"1000"}
	ok, a, b = invokeRaw("AdminPanelCommand", "coins", { "1000" })
	local e3 = logCmd("coins", ok, a, b)

	log("========== VERDETTO ==========")
	log(string.format("CanOpen=%s | jumppower=%s | coins=%s", e1, e2, e3))
	if e1 == "OK" or e2 == "OK" or e3 == "OK" then
		log("ATTENZIONE: almeno un probe OK — server potrebbe fidarsi del client / account staff.")
		setStatus("RISCHIO — vedi log")
	elseif e1 == "ERROR" and e2 == "ERROR" and e3 == "ERROR" then
		log("Tutti ERROR — remote assente, Network fail, o throw server.")
		setStatus("ERROR — vedi log")
	else
		log("Probe DENIED/non-OK — server sembra rifiutare (o args invalidi). Verifica dettaglio risposte.")
		setStatus("PROTEZIONE? — vedi log")
	end
	log("==============================")
end

local function start()
	if running then
		return
	end
	if not Network or typeof(Network.Invoke) ~= "function" then
		log("START blocked — Network assente")
		setStatus("ERR Network")
		return
	end
	gen += 1
	local my = gen
	running = true
	paint()
	log("START suite gen=" .. tostring(my))
	task.spawn(function()
		local ok, err = pcall(function()
			runSuite(my)
		end)
		if not ok then
			log("[TEST] suite | Risposta: ERROR: " .. dumpValue(err) .. " | Esito: ERROR")
			setStatus("suite crash")
		end
		if my == gen then
			running = false
			paint()
		end
	end)
end

-- GUI
do
	local pg = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("PSXAdminTrustMapper")
	if old then
		old:Destroy()
	end
end

gui = Instance.new("ScreenGui")
gui.Name = "PSXAdminTrustMapper"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local f = Instance.new("Frame")
f.Size = UDim2.fromOffset(360, 340)
f.Position = UDim2.fromOffset(10, 120)
f.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
f.BackgroundTransparency = 0.06
f.Active = true
f.Draggable = true
f.Parent = gui
Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -12, 0, 18)
title.Position = UDim2.fromOffset(10, 4)
title.BackgroundTransparency = 1
title.Text = "Admin Trust Mapper"
title.TextColor3 = Color3.fromRGB(255, 160, 140)
title.TextSize = 13
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = f

startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.fromOffset(160, 28)
startBtn.Position = UDim2.fromOffset(8, 28)
startBtn.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
startBtn.Text = "START"
startBtn.TextColor3 = Color3.new(1, 1, 1)
startBtn.TextSize = 12
startBtn.Font = Enum.Font.GothamBold
startBtn.Parent = f
Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0, 6)

copyBtn = Instance.new("TextButton")
copyBtn.Size = UDim2.fromOffset(160, 28)
copyBtn.Position = UDim2.fromOffset(180, 28)
copyBtn.BackgroundColor3 = Color3.fromRGB(50, 80, 120)
copyBtn.Text = "COPIA LOG"
copyBtn.TextColor3 = Color3.new(1, 1, 1)
copyBtn.TextSize = 12
copyBtn.Font = Enum.Font.GothamBold
copyBtn.Parent = f
Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 6)

statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -12, 0, 16)
statusLbl.Position = UDim2.fromOffset(8, 60)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "..."
statusLbl.TextColor3 = Color3.fromRGB(150, 150, 160)
statusLbl.TextSize = 10
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = f

logBox = Instance.new("TextBox")
logBox.Size = UDim2.new(1, -16, 1, -88)
logBox.Position = UDim2.fromOffset(8, 80)
logBox.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
logBox.TextColor3 = Color3.fromRGB(200, 210, 200)
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.TextSize = 9
logBox.Font = Enum.Font.Code
logBox.ClearTextOnFocus = false
logBox.MultiLine = true
logBox.TextWrapped = true
logBox.Text = ""
logBox.Parent = f
Instance.new("UICorner", logBox).CornerRadius = UDim.new(0, 6)

startBtn.MouseButton1Click:Connect(function()
	if running then
		stopRun()
	else
		start()
	end
end)
copyBtn.MouseButton1Click:Connect(copyLogs)

env.__AdminTrustMapper = {
	stop = stopAll,
	start = start,
	stopRun = stopRun,
	copyLogs = copyLogs,
	getLogs = function()
		return table.concat(logLines, "\n")
	end,
}

paint()
log("boot — Admin Trust Boundary Mapper")
log("Probe: CanOpen -> jumppower{\"100\"} -> coins{\"1000\"} (pause " .. PAUSE .. "s)")
setStatus("loading Network...")

task.spawn(function()
	local ok, src = loadNetwork()
	if not ok then
		setStatus("ERR Network")
		log("loadNetwork FAIL: " .. tostring(src))
		return
	end
	log("Network OK via " .. tostring(src))
	setStatus("pronto — START")
end)
