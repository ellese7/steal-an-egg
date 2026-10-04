-- ==================================================
--  Steal a Pet — AC Research Probe Constants/Connections (Delta)
--  AntiCollisionHighSeedPushBack / FixCollisions / Kernel
-- ==================================================

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local MAX_LINES = 350
local LOG_VIEW = 90
local MAX_PROTO_DEPTH = 2
local MAX_CONST_SHOW = 80
local MAX_PROTOS = 40

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

local TARGETS = {
	{ name = "AntiCollisionHighSeedPushBack", where = "char" },
	{ name = "FixCollisions", where = "char" },
	{ name = "Kernel", where = "ps" },
}

local running = false
local abortFlag = false
local lines = {}
local statusLbl, runBtn, logBox
local apiWarn = {}

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
local getsbFn = findApi("getscriptbytecode", "dumpstring")
local getconstantsFn = findApi("getconstants", "debug.getconstants")
local getprotosFn = findApi("getprotos", "debug.getprotos")
local getupvaluesFn = findApi("getupvalues", "debug.getupvalues")
local getinfoFn = findApi("getinfo", "debug.getinfo", "debug.info")
local getconnectionsFn = findApi("getconnections")
local getgcFn = findApi("getgc")
local islclosureFn = findApi("islclosure")
local iscclosureFn = findApi("iscclosure")

-- debug library fallbacks
pcall(function()
	if not getconstantsFn and debug and debug.getconstants then
		getconstantsFn = debug.getconstants
	end
	if not getprotosFn and debug and debug.getprotos then
		getprotosFn = debug.getprotos
	end
	if not getupvaluesFn and debug and debug.getupvalues then
		getupvaluesFn = debug.getupvalues
	end
end)

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

local function warnOnce(key, msg)
	if apiWarn[key] then
		return
	end
	apiWarn[key] = true
	log("API " .. msg, true)
end

local function keepConst(v)
	local t = typeof(v)
	if t == "string" then
		if #v < 3 then
			return false
		end
		local skip = {
			["true"] = true,
			["false"] = true,
			["nil"] = true,
			["and"] = true,
			["or"] = true,
		}
		if skip[v] then
			return false
		end
		return true
	elseif t == "number" then
		if v == 0 or v == 1 or v == -1 then
			return false
		end
		return true
	elseif t == "boolean" then
		return false
	elseif t == "vector" or t == "Vector3" then
		return true
	end
	return t ~= "nil"
end

local function fmtConst(v)
	local t = typeof(v)
	if t == "string" then
		local s = v
		if #s > 60 then
			s = string.sub(s, 1, 57) .. "…"
		end
		return string.format("%q", s)
	elseif t == "number" then
		return string.format("%.6g", v)
	elseif t == "Instance" then
		local ok, n = pcall(function()
			return v:GetFullName()
		end)
		return "Instance:" .. (ok and n or v.ClassName)
	elseif t == "function" then
		return "function"
	elseif t == "table" then
		return "table"
	elseif t == "Vector3" then
		return string.format("V3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
	end
	return t .. ":" .. tostring(v)
end

local function collectConstants(fn)
	if not getconstantsFn then
		warnOnce("getconstants", "getconstants missing — skip")
		return {}
	end
	local ok, consts = pcall(getconstantsFn, fn)
	if not ok or typeof(consts) ~= "table" then
		return { "__err:" .. tostring(consts) }
	end
	local out = {}
	for i = 1, #consts do
		local v = consts[i]
		if keepConst(v) then
			out[#out + 1] = fmtConst(v)
			if #out >= MAX_CONST_SHOW then
				out[#out + 1] = "…(+more)"
				break
			end
		end
	end
	-- also hash-style constants if present
	if #consts == 0 then
		for k, v in pairs(consts) do
			if keepConst(v) then
				out[#out + 1] = fmtConst(v)
				if #out >= MAX_CONST_SHOW then
					break
				end
			end
		end
	end
	return out
end

local function collectUpvalues(fn)
	if not getupvaluesFn then
		warnOnce("getupvalues", "getupvalues missing — skip")
		return {}
	end
	local ok, uvs = pcall(getupvaluesFn, fn)
	if not ok or typeof(uvs) ~= "table" then
		return { "__err:" .. tostring(uvs) }
	end
	local out = {}
	local n = 0
	for k, v in pairs(uvs) do
		n += 1
		local name = typeof(k) == "string" and k or ("[" .. tostring(k) .. "]")
		local t = typeof(v)
		local extra = ""
		if t == "Instance" then
			local ok2, path = pcall(function()
				return v.ClassName .. ":" .. v:GetFullName()
			end)
			extra = ok2 and path or v.ClassName
		elseif t == "function" then
			extra = "fn"
		elseif t == "table" then
			extra = "table"
		elseif t == "number" or t == "string" or t == "boolean" then
			extra = fmtConst(v)
		else
			extra = t
		end
		out[#out + 1] = name .. "=" .. extra
		if #out >= 40 then
			out[#out + 1] = "…(+more)"
			break
		end
	end
	return out
end

local function isLuaFn(fn)
	if typeof(fn) ~= "function" then
		return false
	end
	if islclosureFn then
		local ok, r = pcall(islclosureFn, fn)
		if ok then
			return r and true or false
		end
	end
	if iscclosureFn then
		local ok, r = pcall(iscclosureFn, fn)
		if ok and r then
			return false
		end
	end
	return true
end

local function getScriptClosure(inst)
	-- Delta often: getscriptclosure / getscriptfunction
	local gsc = findApi("getscriptclosure", "getscriptfunction", "getscriptfromname")
	if gsc then
		local ok, fn = pcall(gsc, inst)
		if ok and typeof(fn) == "function" then
			return fn
		end
	end
	-- fallback: scan getgc for functions with matching script
	if getgcFn then
		local ok, gc = pcall(getgcFn, false)
		if ok and typeof(gc) == "table" then
			for i = 1, #gc do
				local fn = gc[i]
				if typeof(fn) == "function" and isLuaFn(fn) then
					local ok2, info = pcall(function()
						if debug and debug.info then
							return debug.info(fn, "s")
						end
						return nil
					end)
					-- weak match: try debug.getinfo source
					local matched = false
					if getinfoFn then
						local ok3, inf = pcall(getinfoFn, fn)
						if ok3 and typeof(inf) == "table" then
							local src = inf.source or inf.short_src or ""
							if typeof(src) == "string" and string.find(src, inst.Name, 1, true) then
								matched = true
							end
						end
					end
					if matched then
						return fn
					end
				end
			end
		end
	end
	return nil
end

local function dumpProtoTree(fn, depth, prefix)
	if abortFlag or depth > MAX_PROTO_DEPTH then
		return
	end
	if not getprotosFn then
		warnOnce("getprotos", "getprotos missing — skip")
		return
	end
	local ok, protos = pcall(getprotosFn, fn)
	if not ok or typeof(protos) ~= "table" then
		log(prefix .. "protos: ERR " .. tostring(protos))
		return
	end
	local count = #protos
	if count == 0 then
		local c = 0
		for _ in pairs(protos) do
			c += 1
		end
		count = c
	end
	log(prefix .. "protos: " .. tostring(count))
	local i = 0
	for _, proto in pairs(protos) do
		i += 1
		if i > MAX_PROTOS then
			log(prefix .. "  …(+more protos)")
			break
		end
		if typeof(proto) == "function" then
			local consts = collectConstants(proto)
			local uvs = collectUpvalues(proto)
			log(prefix .. string.format("  proto[%d] constants: [%s]", i, table.concat(consts, ", ")))
			log(prefix .. string.format("  proto[%d] upvalues: [%s]", i, table.concat(uvs, ", ")))
			if depth < MAX_PROTO_DEPTH then
				dumpProtoTree(proto, depth + 1, prefix .. "  ")
			end
		end
		if abortFlag then
			return
		end
	end
end

local function dumpConnectionsOnScript(inst)
	-- Limit: try Actor/script.Destroyed etc is noise. Look for ModuleScript returned signals via upvalues later.
	-- If getconnections available, try Heartbeat connections whose Function belongs to this script — too heavy.
	-- Instead: only if script has known BindableEvent children
	if not getconnectionsFn then
		warnOnce("getconnections", "getconnections missing — skip")
		return
	end
	local interesting = {}
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BindableEvent") or d:IsA("BindableFunction") or d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
			interesting[#interesting + 1] = d
		end
	end
	if #interesting == 0 then
		log("connections: (no bindable/remote children under script)")
		return
	end
	for i = 1, #interesting do
		local obj = interesting[i]
		local signals = {}
		if obj:IsA("BindableEvent") or obj:IsA("RemoteEvent") or obj:IsA("UnreliableRemoteEvent") then
			signals = { "Event", "OnClientEvent", "OnServerEvent" }
		elseif obj:IsA("BindableFunction") or obj:IsA("RemoteFunction") then
			signals = { "OnInvoke", "OnClientInvoke", "OnServerInvoke" }
		end
		for s = 1, #signals do
			local ok, sig = pcall(function()
				return obj[signals[s]]
			end)
			if ok and sig ~= nil then
				local ok2, conns = pcall(getconnectionsFn, sig)
				if ok2 and typeof(conns) == "table" then
					log(string.format("connections %s.%s count=%d", obj:GetFullName(), signals[s], #conns))
				end
			end
		end
	end
end

local function findScript(name, where)
	local hits = {}
	local function add(inst)
		if inst and (inst:IsA("LocalScript") or inst:IsA("ModuleScript") or inst:IsA("Script")) then
			hits[#hits + 1] = inst
		end
	end
	if where == "char" then
		local char = LP.Character
		if char then
			add(char:FindFirstChild(name, true))
		end
		local scs = game:GetService("StarterPlayer"):FindFirstChild("StarterCharacterScripts")
		if scs then
			add(scs:FindFirstChild(name, true))
		end
	elseif where == "ps" then
		local ps = LP:FindFirstChild("PlayerScripts")
		if ps then
			add(ps:FindFirstChild(name, true))
		end
		local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
		if sps then
			add(sps:FindFirstChild(name, true))
		end
	end
	-- dedupe
	local seen, uniq = {}, {}
	for i = 1, #hits do
		if hits[i] and not seen[hits[i]] then
			seen[hits[i]] = true
			uniq[#uniq + 1] = hits[i]
		end
	end
	return uniq
end

local function processScript(inst)
	local path = inst:GetFullName()
	log("=== " .. inst.Name .. " ===", true)
	log("path=" .. path .. " class=" .. inst.ClassName)

	-- bytecode
	if getsbFn then
		local ok, bc = pcall(getsbFn, inst)
		if ok and typeof(bc) == "string" then
			log("bytecode len=" .. #bc)
		else
			log("bytecode FAIL: " .. tostring(bc))
		end
	else
		warnOnce("bytecode", "getscriptbytecode missing — skip")
		log("bytecode len=?")
	end

	local fn = getScriptClosure(inst)
	if not fn then
		log("closure: NOT FOUND (getscriptclosure/getgc failed)", true)
		dumpConnectionsOnScript(inst)
		return
	end
	log("closure: OK")

	local consts = collectConstants(fn)
	log("constants: [" .. table.concat(consts, ", ") .. "]")

	local uvs = collectUpvalues(fn)
	log("upvalues: [" .. table.concat(uvs, ", ") .. "]")

	dumpProtoTree(fn, 1, "")

	dumpConnectionsOnScript(inst)
end

local function runAll()
	abortFlag = false
	apiWarn = {}
	log(
		string.format(
			"apis: bytecode=%s const=%s protos=%s upvals=%s conn=%s gsc=%s",
			tostring(getsbFn ~= nil),
			tostring(getconstantsFn ~= nil),
			tostring(getprotosFn ~= nil),
			tostring(getupvaluesFn ~= nil),
			tostring(getconnectionsFn ~= nil),
			tostring(findApi("getscriptclosure", "getscriptfunction") ~= nil)
		),
		true
	)

	if not LP.Character then
		log("waiting Character…", true)
		LP.CharacterAdded:Wait()
		task.wait(0.4)
	end

	for i = 1, #TARGETS do
		if abortFlag then
			break
		end
		local t = TARGETS[i]
		setStatus("dump " .. t.name, COL.accent)
		local hits = findScript(t.name, t.where)
		if #hits == 0 then
			log("=== " .. t.name .. " === NOT FOUND", true)
		else
			processScript(hits[1])
		end
		task.wait()
	end
	log("======== DUMP DONE ========", true)
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
	log("START constants/connections dump", true)
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
	local old = pg:FindFirstChild("ACConstDumpUI")
	if old then
		old:Destroy()
	end

	local gui = mk("ScreenGui", {
		Name = "ACConstDumpUI",
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
		Text = "AC Probe — Constants Dump",
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
log("ready — constants/connections (Delta)", true)
