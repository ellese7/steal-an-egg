-- ==================================================
--  Steal a Pet — AC Research Probe Decompile (Delta)
--  AntiCollisionHighSeedPushBack / Kernel / ContentCatalog
-- ==================================================

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local MAX_LINES = 400
local LOG_VIEW = 80
local CHUNK = 900 -- chars per log block

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

local TARGETS = {
	{ name = "AntiCollisionHighSeedPushBack", find = "char" },
	{ name = "Kernel", find = "playerscripts" },
	{ name = "ContentCatalog", find = "any" },
	{ name = "ActiveAssetsController", find = "any" },
}

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
local decompileFn = findApi("decompile")
local getsbFn = findApi("getscriptbytecode", "dumpstring")
local getgcFn = findApi("getgc")

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

local function dumpBlocks(label, text)
	if typeof(text) ~= "string" or #text == 0 then
		log(label .. " EMPTY", true)
		return
	end
	log(string.format("%s len=%d", label, #text), true)
	local n = math.ceil(#text / CHUNK)
	-- max 12 blocks per script to avoid spam
	local maxB = math.min(n, 12)
	for i = 1, maxB do
		local a = (i - 1) * CHUNK + 1
		local b = math.min(#text, i * CHUNK)
		log(string.format("--- %s [%d/%d] ---", label, i, maxB))
		log(string.sub(text, a, b))
		if abortFlag then
			return
		end
		task.wait()
	end
	if n > maxB then
		log(string.format("%s TRUNCATED (+%d blocks not shown)", label, n - maxB), true)
	end
end

local function extractHints(src)
	if typeof(src) ~= "string" then
		return
	end
	local hints = {}
	-- remotes / strings of interest
	for w in string.gmatch(src, "[%w_]*[Rr]emote[%w_]*") do
		hints[w] = true
	end
	for w in string.gmatch(src, "FireServer") do
		hints[w] = true
	end
	for w in string.gmatch(src, "InvokeServer") do
		hints[w] = true
	end
	for w in string.gmatch(src, "WalkSpeed") do
		hints[w] = true
	end
	for w in string.gmatch(src, "AssemblyLinearVelocity") do
		hints[w] = true
	end
	for w in string.gmatch(src, "CFrame") do
		hints[w] = true
	end
	for w in string.gmatch(src, "[%w_/]*[Aa]nti[%w_]*") do
		hints[w] = true
	end
	for w in string.gmatch(src, "[%w_]*[Ss]peed[%w_]*") do
		hints[w] = true
	end
	for w in string.gmatch(src, "[%w_]*[Kk]ick[%w_]*") do
		hints[w] = true
	end
	for w in string.gmatch(src, "[%w_]*[Pp]ush[%w_]*") do
		hints[w] = true
	end
	-- quoted strings (short)
	local nStr = 0
	for s in string.gmatch(src, '"([^"][%w%s%._%-/][^"]-)"') do
		if #s >= 3 and #s <= 64 then
			hints['"' .. s .. '"'] = true
			nStr += 1
			if nStr > 25 then
				break
			end
		end
	end
	local list = {}
	for k in pairs(hints) do
		list[#list + 1] = k
	end
	table.sort(list)
	if #list > 0 then
		log("HINTS: " .. table.concat(list, ", "), true)
	else
		log("HINTS: (none extracted)", true)
	end
end

local function tryDecompile(inst)
	if not decompileFn then
		return nil, "decompile API missing"
	end
	local ok, res = pcall(decompileFn, inst)
	if ok and typeof(res) == "string" and #res > 0 then
		return res, nil
	end
	return nil, tostring(res)
end

local function tryBytecode(inst)
	if not getsbFn then
		return nil, "getscriptbytecode missing"
	end
	local ok, res = pcall(getsbFn, inst)
	if ok and typeof(res) == "string" then
		return res, nil
	end
	return nil, tostring(res)
end

local function findByName(name, mode)
	local hits = {}
	local function consider(inst)
		if inst.Name ~= name then
			return
		end
		if not (inst:IsA("LocalScript") or inst:IsA("ModuleScript") or inst:IsA("Script")) then
			-- sometimes the LocalScript is a child with same name, or folder
			return
		end
		hits[#hits + 1] = inst
	end

	if mode == "char" then
		local char = LP.Character
		if char then
			for _, d in ipairs(char:GetDescendants()) do
				consider(d)
				if d.Name == name then
					-- also collect parent scripts
					for _, c in ipairs(d:GetDescendants()) do
						consider(c)
					end
					if d:IsA("LocalScript") or d:IsA("ModuleScript") then
						hits[#hits + 1] = d
					end
				end
			end
			-- name match even if not script class (clone of LocalScript sometimes)
			local node = char:FindFirstChild(name, true)
			if node then
				if node:IsA("LocalScript") or node:IsA("ModuleScript") or node:IsA("Script") then
					hits[#hits + 1] = node
				end
				for _, c in ipairs(node:GetChildren()) do
					consider(c)
				end
				log("FOUND node " .. node:GetFullName() .. " class=" .. node.ClassName, true)
			end
		end
	elseif mode == "playerscripts" then
		local ps = LP:FindFirstChild("PlayerScripts")
		if ps then
			local n = ps:FindFirstChild(name, true)
			if n then
				log("FOUND " .. n:GetFullName() .. " class=" .. n.ClassName, true)
				if n:IsA("LocalScript") or n:IsA("ModuleScript") or n:IsA("Script") then
					hits[#hits + 1] = n
				end
				for _, c in ipairs(n:GetDescendants()) do
					consider(c)
				end
			end
		end
	end

	-- global scan fallback
	local roots = {
		game:GetService("ReplicatedStorage"),
		game:GetService("StarterPlayer"),
		LP:FindFirstChild("PlayerScripts"),
		LP:FindFirstChild("PlayerGui"),
		LP.Character,
	}
	for _, root in ipairs(roots) do
		if root then
			local ok, list = pcall(function()
				return root:GetDescendants()
			end)
			if ok then
				for _, d in ipairs(list) do
					if d.Name == name and (d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Script")) then
						hits[#hits + 1] = d
					end
				end
			end
		end
	end

	-- dedupe
	local seen = {}
	local uniq = {}
	for i = 1, #hits do
		local h = hits[i]
		if not seen[h] then
			seen[h] = true
			uniq[#uniq + 1] = h
		end
	end
	return uniq
end

local function scanGcForName(name)
	if not getgcFn then
		return {}
	end
	local out = {}
	local ok, gc = pcall(getgcFn, true)
	if not ok or typeof(gc) ~= "table" then
		return out
	end
	local n = 0
	for i = 1, #gc do
		local v = gc[i]
		if typeof(v) == "Instance" and (v:IsA("LocalScript") or v:IsA("ModuleScript")) then
			local okn, nm = pcall(function()
				return v.Name
			end)
			if okn and nm == name then
				out[#out + 1] = v
				n += 1
				if n >= 5 then
					break
				end
			end
		end
	end
	return out
end

local function processScript(inst)
	local path = "?"
	pcall(function()
		path = inst:GetFullName()
	end)
	log("======== TARGET " .. path .. " (" .. inst.ClassName .. ") ========", true)

	-- parent context
	if inst.Parent then
		log("parent=" .. inst.Parent:GetFullName() .. " (" .. inst.Parent.ClassName .. ")")
		for _, sib in ipairs(inst.Parent:GetChildren()) do
			if sib:IsA("LocalScript") or sib:IsA("ModuleScript") or sib:IsA("Script") then
				log("  sibling script: " .. sib.Name .. " (" .. sib.ClassName .. ")")
			end
		end
	end

	local src, err = tryDecompile(inst)
	if src then
		extractHints(src)
		dumpBlocks("DECOMPILE " .. inst.Name, src)
	else
		log("DECOMPILE FAIL: " .. tostring(err), true)
		local bc, berr = tryBytecode(inst)
		if bc then
			log(string.format("BYTECODE ok len=%d (hex head)", #bc), true)
			local head = {}
			for i = 1, math.min(32, #bc) do
				head[#head + 1] = string.format("%02X", string.byte(bc, i))
			end
			log("BC: " .. table.concat(head, " "))
		else
			log("BYTECODE FAIL: " .. tostring(berr), true)
		end
	end
end

local function runAll()
	abortFlag = false
	if not decompileFn then
		log("CRITICAL: decompile() not found in Delta env", true)
		setStatus("no decompile", COL.bad)
		return
	end
	log("decompile=OK getscriptbytecode=" .. tostring(getsbFn ~= nil) .. " getgc=" .. tostring(getgcFn ~= nil), true)

	if not LP.Character then
		log("waiting Character…", true)
		LP.CharacterAdded:Wait()
		task.wait(0.5)
	end

	for t = 1, #TARGETS do
		if abortFlag then
			break
		end
		local spec = TARGETS[t]
		setStatus("decompile " .. spec.name .. "…", COL.accent)
		log("---- search " .. spec.name .. " ----", true)
		local hits = findByName(spec.name, spec.find)
		if #hits == 0 then
			local gcHits = scanGcForName(spec.name)
			for i = 1, #gcHits do
				hits[#hits + 1] = gcHits[i]
			end
		end
		if #hits == 0 then
			log("NOT FOUND: " .. spec.name, true)
		else
			log(string.format("found %d instance(s) for %s", #hits, spec.name), true)
			for i = 1, math.min(#hits, 3) do
				processScript(hits[i])
				task.wait(0.05)
			end
		end
	end

	log("======== DECOMPILE DONE ========", true)
	log("Paste Copy log here for analysis", true)
end

local function stop()
	abortFlag = true
	running = false
	paintRun()
	setStatus("stopped", COL.muted)
	log("STOP", true)
end

local function start()
	if running then
		stop()
		return
	end
	running = true
	paintRun()
	log("START decompile pass", true)
	task.spawn(function()
		local ok, err = pcall(runAll)
		if not ok then
			log("CRASH " .. tostring(err), true)
		end
		running = false
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
	local old = pg:FindFirstChild("ACDecompileUI")
	if old then
		old:Destroy()
	end

	local gui = mk("ScreenGui", {
		Name = "ACDecompileUI",
		ResetOnSpawn = false,
		DisplayOrder = 123,
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
		Text = "AC Probe — Decompile",
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
		Text = "Delta — spawn in, then START",
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
		CanvasSize = UDim2.fromOffset(0, 2400),
	}, shell)

	logBox = mk("TextLabel", {
		Size = UDim2.new(1, -4, 0, 2400),
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
log("ready — decompile probe (Delta)", true)
if not decompileFn then
	log("WARNING: decompile missing", true)
	setStatus("decompile missing", COL.bad)
end
