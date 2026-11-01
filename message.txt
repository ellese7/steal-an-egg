-- L7 Script — Steal-a-Pet

local Players = game:GetService("Players")
local Run = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local PPS = game:GetService("ProximityPromptService")
local LP = Players.LocalPlayer

local ENV = _G
pcall(function()
	if typeof(getgenv) == "function" then
		ENV = getgenv()
	end
end)
if typeof(ENV.__L7ScriptKill) == "function" then
	pcall(ENV.__L7ScriptKill)
end
if typeof(ENV.__EggRunKill) == "function" then
	pcall(ENV.__EggRunKill)
end
if typeof(ENV.__HwHuntKill) == "function" then
	pcall(ENV.__HwHuntKill)
end
local KB_F = 1.15
local STAND_SQ = 4
local MOVE_EPS = 0.0025
local ZERO = Vector3.zero
local TAPIS_OFF = Vector3.new(0, 3, 0)
local HEAVY = PhysicalProperties.new(100, 0.5, 0, 1, 1)
local BAT_EQUIP_CD = 0.25
local BAT_FIRE_GAP = 0.02 -- solo anti double-fire prima che CooldownActive salga

local S_Phys = Enum.HumanoidStateType.Physics
local S_Rag = Enum.HumanoidStateType.Ragdoll
local S_Fall = Enum.HumanoidStateType.FallingDown
local S_Up = Enum.HumanoidStateType.GettingUp
local S_Run = Enum.HumanoidStateType.Running

local COL = {
	panel = Color3.fromRGB(13, 15, 20),
	panelHi = Color3.fromRGB(20, 24, 32),
	btn = Color3.fromRGB(26, 30, 40),
	btnHot = Color3.fromRGB(36, 42, 56),
	row = Color3.fromRGB(30, 34, 44),
	rowHot = Color3.fromRGB(38, 44, 56),
	sel = Color3.fromRGB(34, 78, 64),
	modeOn = Color3.fromRGB(44, 112, 88),
	modeOff = Color3.fromRGB(30, 34, 44),
	autoOff = Color3.fromRGB(42, 38, 44),
	autoOn = Color3.fromRGB(168, 58, 58),
	accent = Color3.fromRGB(64, 168, 128),
	text = Color3.fromRGB(240, 242, 248),
	textDim = Color3.fromRGB(138, 146, 162),
	textMute = Color3.fromRGB(98, 106, 122),
	border = Color3.fromRGB(58, 68, 88),
	warn = Color3.fromRGB(255, 120, 120),
}

local hum, root, char
local conns = table.create(6)
local skipKnockUntil = 0
local resetting = false
local batOn = true
local nextBatEquip, lastBatFire = 0, 0
local reequipUntil = 0
local batEpoch = 0 -- invalida loop forceEquip quando BAT OFF
local cachedBat, cachedBelt, askWearStill, netFolder, backpack
local alive = true
local hbConn, charConn, bagConn
local extraConns = {}

local myName, myDisplay, myUidStr = LP.Name, LP.DisplayName, tostring(LP.UserId)
pcall(function()
	netFolder = RS.Packages.Networking
end)
backpack = LP:FindFirstChild("Backpack") or LP:WaitForChild("Backpack", 5)

local clock = os.clock

local function getHum()
	if hum and hum.Parent then
		return hum
	end
	local c = char or LP.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
	if root and root.Parent then
		return root
	end
	local c = char or LP.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function clearAttr() pcall(LP.SetAttribute, LP, "RagdollEndTime", 0) end
local function harden()
	local h = hum
	if not h or resetting then return end
	h:SetStateEnabled(S_Phys, false)
	h:SetStateEnabled(S_Rag, false)
	h:SetStateEnabled(S_Fall, false)
	h.PlatformStand = false
	h.AutoRotate = true
end
local function isUnderTool(inst) return inst:FindFirstAncestorOfClass("Tool") ~= nil end
local function breakCons()
	local c = char
	if not c then return end
	for _, d in c:GetDescendants() do
		if not isUnderTool(d) then
			local cls = d.ClassName
			if (cls == "BallSocketConstraint" or cls == "NoCollisionConstraint") and d.Enabled then
				d.Enabled = false
			elseif cls == "Motor6D" and not d.Enabled then
				d.Enabled = true
			end
		end
	end
end
local function recover()
	local h = hum
	if resetting or not h then return end
	clearAttr()
	harden()
	local st = h:GetState()
	if st == S_Phys or st == S_Rag or st == S_Fall then
		breakCons()
		h:ChangeState(S_Up)
		task.defer(function()
			if hum and not resetting then hum:ChangeState(S_Run) end
		end)
	end
end
local function burst()
	if resetting then return end
	recover()
	task.delay(0.08, recover)
end
local function isBatTool(t)
	return t and t.ClassName == "Tool" and (t:GetAttribute("IsBat") == true or t:GetAttribute("GearName") == "Bat")
end
local function resolveBat()
	local c = char
	if c then
		for _, t in c:GetChildren() do
			if isBatTool(t) then
				cachedBat = t
				return t, true
			end
		end
	end
	local bp = backpack or LP:FindFirstChild("Backpack")
	backpack = bp
	if bp then
		for _, t in bp:GetChildren() do
			if isBatTool(t) then
				cachedBat = t
				return t, false
			end
		end
	end
	cachedBat = nil
	return nil, false
end
local function unequipBat()
	batEpoch = batEpoch + 1
	reequipUntil, nextBatEquip, lastBatFire = 0, 1e9, 0
	local h, c = hum, char or LP.Character
	local bp = LP:FindFirstChild("Backpack")
	backpack = bp
	if c then
		for _, t in c:GetChildren() do
			if isBatTool(t) then pcall(function() t:Deactivate() end) end
		end
	end
	if h then pcall(h.UnequipTools, h) end
	c = char or LP.Character
	bp = LP:FindFirstChild("Backpack") or bp
	if c and bp then
		for _, t in c:GetChildren() do
			if isBatTool(t) then t.Parent, cachedBat = bp, t end
		end
	end
end
local function forceEquipBat(sec)
	if not batOn then
		return
	end
	sec = sec or 8
	batEpoch = batEpoch + 1
	local myEpoch = batEpoch
	nextBatEquip = 0
	reequipUntil = clock() + sec
	task.spawn(function()
		local deadline = clock() + sec
		while batOn and myEpoch == batEpoch and clock() < deadline do
			backpack = LP:FindFirstChild("Backpack") or backpack
			local h = hum
			local bat, inHand = resolveBat()
			if bat and h and h.Parent and h.Health > 0 then
				if inHand then
					return
				end
				if not batOn or myEpoch ~= batEpoch then
					return
				end
				pcall(h.EquipTool, h, bat)
				task.wait(0.08)
				if not batOn or myEpoch ~= batEpoch then
					return
				end
				if bat.Parent == char then
					return
				end
			end
			task.wait(0.08)
		end
	end)
end
local function wipeConns()
	for i = 1, 6 do
		local c = conns[i]
		if c then
			c:Disconnect()
			conns[i] = nil
		end
	end
	hum, root, char, cachedBat = nil, nil, nil, nil
end
local function bind(ch)
	wipeConns()
	resetting = false
	cachedBelt = nil
	char = ch
	backpack = LP:FindFirstChild("Backpack") or backpack
	if not ch then
		return
	end
	hum = ch:WaitForChild("Humanoid", 5)
	root = ch:WaitForChild("HumanoidRootPart", 5)
	if not hum or not root then
		hum, root, char = nil, nil, nil
		return
	end
	harden()
	clearAttr()
	root.CustomPhysicalProperties = HEAVY
	resolveBat()

	conns[1] = hum.StateChanged:Connect(function(_, n)
		if not resetting and (n == S_Phys or n == S_Rag or n == S_Fall) then
			recover()
		end
	end)
	conns[2] = hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
		if not resetting and hum and hum.PlatformStand then
			hum.PlatformStand = false
			recover()
		end
	end)
	conns[3] = ch.DescendantAdded:Connect(function(d)
		local cls = d.ClassName
		if cls == "Tool" then
			if isBatTool(d) then
				cachedBat = d
				if batOn then
					nextBatEquip = 0
					forceEquipBat(4)
				end
			end
			return
		end
		-- constraint/Motor sotto un Tool (uovo/pet/bat) = non toccare
		if isUnderTool(d) then
			return
		end
		if cls == "BallSocketConstraint" or cls == "NoCollisionConstraint" then
			d.Enabled = false
		end
	end)
	conns[4] = ch:GetAttributeChangedSignal("RagdollEndTime"):Connect(function()
		if not resetting then
			clearAttr()
			recover()
		end
	end)
	conns[5] = ch.ChildRemoved:Connect(function(d)
		if d == cachedBat then
			cachedBat = nil
			if batOn and alive then
				nextBatEquip = 0
				forceEquipBat(3)
			end
		end
	end)

	if batOn and alive then
		forceEquipBat(8)
	end
end

if netFolder then
	local guards = {
		"RE/GuardPatrol/Rouse",
		"RE/GuardPatrol/ForestStrike",
		"RE/GuardPatrol/SpeedTollOffer",
		"RE/GuardPatrol/SpeedTollWarning",
		"RE/GuardPatrol/ForestHandoff",
	}
	for i = 1, #guards do
		local r = netFolder:FindFirstChild(guards[i])
		if r then
			extraConns[#extraConns + 1] = r.OnClientEvent:Connect(burst)
		end
	end
	askWearStill = netFolder:FindFirstChild("RF/Treadmill/AskWearStill")
end

extraConns[#extraConns + 1] = LP:GetAttributeChangedSignal("RagdollEndTime"):Connect(function()
	if alive and not resetting then
		clearAttr()
		recover()
	end
end)

if backpack then
	bagConn = backpack.ChildAdded:Connect(function(d)
		if not alive then
			return
		end
		if isBatTool(d) then
			cachedBat = d
			if batOn then
				nextBatEquip = 0
				forceEquipBat(5)
			end
		end
	end)
end

charConn = LP.CharacterAdded:Connect(function(ch)
	if not alive then
		return
	end
	bind(ch)
	if batOn then
		task.delay(0.35, function()
			if alive and batOn and LP.Character == ch then
				forceEquipBat(8)
			end
		end)
	end
end)
if LP.Character then
	bind(LP.Character)
end

hbConn = Run.Heartbeat:Connect(function()
	if not alive then
		return
	end
	local now = clock()
	local h, r = hum, root

	if batOn and not resetting and h and hum == h then
		local bat = cachedBat
		local inHand = bat and bat.Parent == char
		if not bat or not bat.Parent then
			bat, inHand = resolveBat()
		elseif not inHand and bat.Parent ~= backpack then
			bat, inHand = resolveBat()
		end
		if bat then
			if not inHand then
				local equipCd = (now < reequipUntil) and 0.05 or BAT_EQUIP_CD
				if now >= nextBatEquip then
					nextBatEquip = now + equipCd
					pcall(h.EquipTool, h, bat)
				end
			elseif bat:GetAttribute("CooldownActive") ~= true and (now - lastBatFire) >= BAT_FIRE_GAP then
				lastBatFire = now
				pcall(bat.Activate, bat)
			end
		elseif now < reequipUntil then
			nextBatEquip = 0
		end
	end

	-- anti-knock
	if resetting or now < skipKnockUntil or not h or not r then
		return
	end
	local v = r.AssemblyLinearVelocity
	local hx, hz = v.X, v.Z
	local sq = hx * hx + hz * hz
	if sq < STAND_SQ then
		return
	end
	local mv = h.MoveDirection
	local mx, mz = mv.X, mv.Z
	local y = v.Y
	if mx * mx + mz * mz < MOVE_EPS then
		r.AssemblyLinearVelocity = Vector3.new(0, y, 0)
		r.AssemblyAngularVelocity = ZERO
		return
	end
	local maxs = h.WalkSpeed * KB_F
	if sq <= maxs * maxs then
		return
	end
	local inv = 1 / math.sqrt(mx * mx + mz * mz)
	local dx, dz = mx * inv, mz * inv
	local along = hx * dx + hz * dz
	if along < 0 then
		along = 0
	elseif along > maxs then
		along = maxs
	end
	r.AssemblyLinearVelocity = Vector3.new(dx * along, y, dz * along)
	r.AssemblyAngularVelocity = ZERO
end)

local function isMySign(text)
	return text == myDisplay or text == myName or text == myUidStr
end
local function findMyTreadmill()
	if cachedBelt and cachedBelt.Parent then
		return cachedBelt
	end
	cachedBelt = nil
	local plots = Workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		local sign = plot:FindFirstChild("PlotSign")
		local label = sign and sign:FindFirstChild("PlayerName", true)
		local text = label and label.Text
		if text and isMySign(text) then
			local bottom = plot:FindFirstChild("TreadmillBottom")
			if bottom and bottom:IsA("BasePart") then
				cachedBelt = bottom
				return bottom
			end
		end
	end
	return nil
end
local function tpToMyTapis()
	local r = getRoot()
	if not r then
		return false, "no char"
	end
	local part = findMyTreadmill()
	if not part then
		return false, "no plot"
	end
	r.AssemblyLinearVelocity = ZERO
	r.AssemblyAngularVelocity = ZERO
	r.CFrame = CFrame.new(part.Position + TAPIS_OFF)
	task.delay(0.15, function()
		local rf = askWearStill
		if not (rf and rf.Parent) and netFolder then
			askWearStill = netFolder:FindFirstChild("RF/Treadmill/AskWearStill")
			rf = askWearStill
		end
		if rf then
			pcall(rf.InvokeServer, rf)
		end
	end)
	return true
end
local function resetToSafe()
	local h = getHum()
	if not h then
		return false, "no char"
	end
	resetting = true
	skipKnockUntil = clock() + 2
	if batOn then
		nextBatEquip = 0
		reequipUntil = clock() + 10
	end
	h.Health = 0
	return true
end
local SAFE_X, ARRIVE_HOME, ARRIVE_NEST = 530, 12, 2.5
local TIMEOUT, BIND, WALK_BIND = 90, "EggRunHome", "EggWalkTo"
local PICK_TIMEOUT, BETWEEN_PICKS = 12, 0.6
local RECLAIM_RADIUS, NEST_NEAR = 45, 7
local REFRESH_EVERY = 5

local NESTS do
	local V = Vector3.new
	local function nest(...)
		local a, t = { ... }, {}
		for i = 1, #a, 3 do
			t[#t + 1] = V(a[i], a[i + 1], a[i + 2])
		end
		return t
	end
	NESTS = {
		["Lake"] = nest(735.90,67.46,-410.67, 740.70,67.49,-404.49, 743.71,67.49,-412.79, 747.92,67.49,-404.77, 750.29,67.46,-411.61),
		["Desert"] = nest(943.21,67.50,-321.41, 945.58,67.53,-328.26, 949.79,67.53,-320.23, 952.79,67.53,-328.53, 957.60,67.50,-322.35),
		["Jungle"] = nest(1181.19,67.46,-411.25, 1186.00,67.49,-405.07, 1189.00,67.49,-413.38, 1193.21,67.49,-405.35, 1195.58,67.46,-412.19),
		["Snow"] = nest(1485.80,67.83,-311.93, 1488.17,67.85,-318.77, 1492.38,67.85,-310.74, 1495.38,67.85,-319.05, 1500.19,67.83,-312.87),
		["Volcano"] = nest(1871.38,67.34,-399.67, 1876.19,67.36,-393.49, 1879.19,67.36,-401.79, 1883.41,67.36,-393.76, 1885.77,67.34,-400.61),
		["Abyss Ocean"] = nest(2274.98,67.32,-324.27, 2277.35,67.34,-331.11, 2281.56,67.34,-323.08, 2284.57,67.34,-331.39, 2289.37,67.32,-325.21),
		["Prehistoric"] = nest(2805.78,67.33,-400.06, 2810.58,67.35,-393.88, 2813.59,67.35,-402.19, 2817.80,67.35,-394.16, 2820.17,67.33,-401.00),
		["Cosmic"] = nest(3385.38,67.51,-322.11, 3387.74,67.53,-328.96, 3391.96,67.53,-320.93, 3394.96,67.53,-329.24, 3399.77,67.51,-323.06),
		["Cherry Blossom"] = nest(4020.34,67.61,-399.75, 4024.33,67.63,-393.01, 4028.36,67.63,-400.87, 4031.53,67.63,-392.38, 4034.74,67.61,-398.87),
		["Titan Temple"] = nest(4790.84,67.61,-326.72, 4794.06,67.63,-333.21, 4797.22,67.63,-324.72, 4801.25,67.63,-332.58, 4805.24,67.61,-325.84),
		["Light Dark"] = nest(5655.84,67.61,-326.72, 5659.06,67.63,-333.21, 5662.22,67.63,-324.72, 5666.25,67.63,-332.58, 5670.24,67.61,-325.84),
	}
end
local AREA_ORDER = {
	"Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean",
	"Prehistoric", "Cosmic", "Cherry Blossom", "Titan Temple", "Light Dark",
}
local SKIP_AREAS = { Forest = true }

local armed, running, carrying, picking = false, false, false, false
local uid, area, token, pickToken = nil, nil, 0, 0
local eggs, selectedUid, areaOn, searchText = {}, nil, {}, ""
local rareByUid, lastEgg = {}, nil
local reclaiming, homeActive, refreshBusy = false, false, false
local autoRunSafe = true
local instantE = false
local deliverMode = nil -- nil | "pick" | "manual" — who owns current auto-deliver
local autoRefreshTok = 0
local searchBox, listFrame, countLbl, gui
local carryC
local slotsClient
local rebuildList, reclaimEgg
local remoteCache = {}
local IE = {
	busy = false,
	lastFire = 0,
	snapAt = 0,
	snapRes = nil,
	cached = nil,
	shown = nil,
	shownPos = nil,
	lastPrefetch = 0,
	inputConn = nil,
	shownConn = nil,
	hiddenConn = nil,
	hbConn = nil,
}
local IE_RANGE, IE_CD, IE_SNAP_CACHE, IE_PREFETCH = 14, 0.2, 2.5, 0.4

local areaListed, pendingAreas, addAreaChip = {}, {}, nil
for _, a in ipairs(AREA_ORDER) do
	areaOn[a] = false
	areaListed[a] = true
end
local function noteDiscoveredAreas(list)
	local found = {}
	for _, e in ipairs(list) do
		local a = e.area
		if a and a ~= "" and a ~= "?" and not SKIP_AREAS[a] and not areaListed[a] then
			local f = found[a]
			if not f then
				f = { name = a, x = math.huge }
				found[a] = f
			end
			if e.pos and e.pos.X < f.x then
				f.x = e.pos.X
			end
		end
	end
	local extras = {}
	for _, f in pairs(found) do
		extras[#extras + 1] = f
	end
	table.sort(extras, function(a, b)
		if a.x ~= b.x then
			return a.x < b.x
		end
		return a.name < b.name
	end)
	for _, f in ipairs(extras) do
		areaListed[f.name] = true
		if areaOn[f.name] == nil then
			areaOn[f.name] = false
		end
		if addAreaChip then
			addAreaChip(f.name)
		else
			pendingAreas[#pendingAreas + 1] = f.name
		end
	end
end
local function setPickStatus(t, col)
	if countLbl then
		countLbl.Text = tostring(t)
		if col then countLbl.TextColor3 = col end
	end
end
local function rootPos()
	local r = getRoot()
	return r and r.Position
end
local function stopMove()
	local h = getHum()
	if h then pcall(h.Move, h, ZERO, false) end
end
local function xzDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end
local function cfPos(cf)
	if typeof(cf) == "CFrame" then
		return cf.Position
	end
	if typeof(cf) == "table" then
		local x = cf.X or cf.x or (cf[1] and cf[1].X)
		local y = cf.Y or cf.y or (cf[1] and cf[1].Y)
		local z = cf.Z or cf.z or (cf[1] and cf[1].Z)
		if typeof(x) == "number" and typeof(z) == "number" then
			return Vector3.new(x, y or 68, z)
		end
	end
end
local function nestSlotNum(nestId)
	local n = string.match(tostring(nestId or ""), "(%d+)$")
	return n and tonumber(n) or nil
end
local function uidMatch(a, b)
	if not a or not b then
		return false
	end
	a, b = tostring(a), tostring(b)
	if a == b then
		return true
	end
	local n = math.min(#a, #b)
	if n < 12 then
		return false
	end
	return string.sub(a, 1, n) == string.sub(b, 1, n) or string.find(a, b, 1, true) or string.find(b, a, 1, true)
end
local function compositeNestId(areaId, nestId)
	local nid = tostring(nestId or "Slot_001")
	if not string.find(nid, "Slot_", 1, true) then
		local n = nestSlotNum(nid) or 1
		nid = string.format("Slot_%03d", n)
	end
	return tostring(areaId) .. ":" .. nid
end
local function isSkippedEgg(recOrEgg)
	if not recOrEgg then
		return true
	end
	local a = tostring(recOrEgg.AreaId or recOrEgg.area or "")
	local u = tostring(recOrEgg.Uid or recOrEgg.uid or "")
	return SKIP_AREAS[a] == true or string.find(u, "FirstAreaEgg", 1, true) ~= nil
end
local function atSafe()
	local p = rootPos()
	return p and p.X <= SAFE_X + ARRIVE_HOME
end
local function findSlotsClient()
	if slotsClient and slotsClient.Parent then
		return slotsClient
	end
	local ok, found = pcall(function()
		return LP:FindFirstChild("PlayerScripts")
			and LP.PlayerScripts:FindFirstChild("AreaEggSlotsClient")
	end)
	if ok and found then
		slotsClient = found
		return found
	end
	for _, d in ipairs(LP:GetDescendants()) do
		if d.Name == "AreaEggSlotsClient" then
			slotsClient = d
			return d
		end
	end
end
local function findRemote(className, needle)
	local key = className .. "\0" .. needle
	local cached = remoteCache[key]
	if cached and cached.Parent then
		return cached
	end
	local ok, pack = pcall(function()
		return RS:FindFirstChild("Packages") and RS.Packages:FindFirstChild("Networking")
	end)
	local rootNet = ok and pack or RS
	for _, d in ipairs(rootNet:GetDescendants()) do
		if d.ClassName == className and string.find(d:GetFullName(), needle, 1, true) then
			remoteCache[key] = d
			return d
		end
	end
end
local function carryRemote()
	return findRemote("RemoteEvent", "RE/EggWorld/FieldEggCarry") or findRemote("RemoteEvent", "FieldEggCarry")
end
local function askCarryRF()
	return findRemote("RemoteFunction", "RF/EggWorld/AskFieldEggCarry") or findRemote("RemoteFunction", "AskFieldEggCarry")
end
local function snapshotRF()
	return findRemote("RemoteFunction", "RF/EggWorld/AskFieldEggSnapshot") or findRemote("RemoteFunction", "AskFieldEggSnapshot")
end
local function classifyRarity(s)
	s = string.lower(tostring(s or ""))
	if s == "" then return nil end
	if string.find(s, "secret", 1, true) then return "Secret" end
	if string.find(s, "legendary", 1, true) or string.find(s, "legend", 1, true) then return "Legendary" end
	if string.find(s, "epic", 1, true) then return "Epic" end
	if string.find(s, "rare", 1, true) then return "Rare" end
	return "Normal"
end
local function eggFromRecord(rec)
	local slotN = nestSlotNum(rec.NestId)
	local pos = cfPos(rec.BottomCFrame) or cfPos(rec.BoundsCFrame)
	local areaId = tostring(rec.AreaId or (lastEgg and lastEgg.area) or "?")
	if not pos and slotN and NESTS[rec.AreaId] then
		pos = NESTS[rec.AreaId][slotN]
	elseif not pos and slotN and NESTS[areaId] then
		pos = NESTS[areaId][slotN]
	end
	return {
		uid = tostring(rec.Uid),
		name = tostring(rec.AssetCategory or (lastEgg and lastEgg.name) or "?"),
		area = areaId,
		nestId = tostring(rec.NestId or "?"),
		slot = slotN or (lastEgg and lastEgg.slot) or 0,
		pos = pos,
		state = tostring(rec.State or "?"),
	}
end
local function nestPosOf(egg)
	if not egg then
		return nil
	end
	local slot = egg.slot or nestSlotNum(egg.nestId)
	local nest = slot and NESTS[egg.area]
	return (nest and nest[slot]) or egg.pos
end
local function stopWalk()
	pcall(Run.UnbindFromRenderStep, Run, WALK_BIND)
	stopMove()
end
local function stopRun()
	running = false
	pcall(Run.UnbindFromRenderStep, Run, BIND)
	if not picking then stopMove() end
end
local function stopPickTeardown()
	armed, picking, reclaiming, homeActive = false, false, false, false
	deliverMode = nil
	autoRefreshTok = autoRefreshTok + 1
	pickToken = pickToken + 1
	token = token + 1
	carrying = false
	stopRun()
	stopWalk()
	if carryC then
		carryC:Disconnect()
		carryC = nil
	end
end
ENV.__EggRunKill = stopPickTeardown

local function runHome(tok)
	stopRun()
	running = true
	local h, r = getHum(), getRoot()
	if not h or not r then
		running = false
		setPickStatus("no char", COL.warn)
		return
	end
	local t0 = os.clock()
	local lockZ = r.Position.Z
	local dirX = r.Position.X > SAFE_X and -1 or 1
	local dir = Vector3.new(dirX, 0, 0)
	h.Sit = false
	h.PlatformStand = false
	setPickStatus(string.format("run Z=%.0f", lockZ), Color3.fromRGB(120, 220, 255))

	Run:BindToRenderStep(BIND, Enum.RenderPriority.Character.Value + 5, function()
		if not (armed and carrying and running and tok == token) then
			return
		end
		h, r = getHum(), getRoot()
		if not h or not r or h.Health <= 0 then
			stopRun()
			setPickStatus("stop", COL.warn)
			return
		end
		h:Move(dir, false)
		local p = r.Position
		if math.abs(p.Z - lockZ) > 0.25 then
			r.CFrame = CFrame.new(p.X, p.Y, lockZ) * (r.CFrame - r.CFrame.Position)
		end
		local v = r.AssemblyLinearVelocity
		if math.abs(v.Z) > 0.05 then
			r.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, 0)
		end
		local x = p.X
		if (dirX < 0 and x <= SAFE_X + ARRIVE_HOME) or (dirX > 0 and x >= SAFE_X - ARRIVE_HOME) then
			stopRun()
			setPickStatus("safe", COL.accent)
			return
		end
		if os.clock() - t0 > TIMEOUT then
			stopRun()
			setPickStatus("timeout", Color3.fromRGB(255, 180, 80))
		end
	end)
end
local function wantsDeliver()
	return picking or deliverMode == "pick" or autoRunSafe
end
local function resumeDeliverHome()
	if carrying and not atSafe() then
		homeActive = true
		token = token + 1
		task.defer(runHome, token)
	end
end
local function onCarry(p)
	if carrying and running and p.Uid == uid then
		return
	end
	if reclaiming and lastEgg and lastEgg.uid and p.Uid and not uidMatch(p.Uid, lastEgg.uid) then
		carrying = true
		uid, area = p.Uid, p.AreaId
		token = token + 1
		stopRun()
		homeActive = false
		return
	end
	carrying = true
	uid, area = p.Uid, p.AreaId
	local u, a = tostring(p.Uid or ""), tostring(p.AreaId or "?")
	if not lastEgg or not uidMatch(lastEgg.uid, u) then
		lastEgg = { uid = u, name = tostring(p.AssetCategory or p.Name or "?"), area = a, nestId = tostring(p.NestId or "?"), slot = nestSlotNum(p.NestId) or 0, pos = rootPos() }
	else
		lastEgg.uid, lastEgg.area = u, a
		if p.NestId then
			lastEgg.nestId = tostring(p.NestId)
			lastEgg.slot = nestSlotNum(p.NestId) or lastEgg.slot or 0
		end
	end
	armed, token, reclaiming = true, token + 1, false
	local mode = (picking or deliverMode == "pick") and "pick" or (autoRunSafe and "manual" or nil)
	if mode then
		deliverMode, homeActive = mode, true
		task.defer(runHome, token)
	else
		deliverMode, homeActive = nil, false
		setPickStatus("holding (auto safe off)", Color3.fromRGB(255, 220, 120))
	end
end
local function onDrop()
	local dropUid, dropArea = uid, area
	local wasHome = homeActive
	local mode = deliverMode
	local dropPos = rootPos()
	carrying = false
	uid, area = nil, nil
	token = token + 1
	stopRun()
	homeActive = false
	local keep = not reclaiming
		and dropUid
		and not atSafe()
		and (wasHome or mode == "pick" or picking or (mode == "manual" and autoRunSafe))
	if keep then
		deliverMode = (mode == "pick" or picking) and "pick" or (autoRunSafe and "manual" or mode)
		task.spawn(reclaimEgg, dropUid, dropArea, dropPos, pickToken)
	else
		if mode ~= "pick" then
			deliverMode = nil
		end
		if armed and not picking then
			setPickStatus("wait", Color3.fromRGB(100, 180, 255))
		end
	end
end
local function armCarryListen()
	local rem = carryRemote()
	if not rem then return false end
	if carryC then carryC:Disconnect() end
	carryC = rem.OnClientEvent:Connect(function(p)
		if typeof(p) ~= "table" then return end
		if p.Uid then onCarry(p) else onDrop() end
	end)
	return true
end
local function startArm()
	if not armCarryListen() then
		setPickStatus("no remote", COL.warn)
		return false
	end
	armed = true
	setPickStatus("armed", Color3.fromRGB(100, 180, 255))
	return true
end
local function ensureAutoSafeArm()
	if not autoRunSafe then return false end
	return (armed and carryC) and true or startArm()
end
local function clearAutoSafeTransport()
	autoRunSafe = false
	if picking or deliverMode == "pick" then
		setPickStatus("auto safe off", COL.textDim)
		return
	end
	token, pickToken = token + 1, pickToken + 1
	reclaiming, homeActive, deliverMode, lastEgg = false, false, nil, nil
	stopRun(); stopWalk(); stopMove()
	setPickStatus("auto safe off", COL.textDim)
end
local function stopAll()
	pickToken = pickToken + 1
	token = token + 1
	picking, reclaiming, homeActive, armed, deliverMode, carrying =
		false, false, false, false, nil, false
	stopWalk()
	stopRun()
	if carryC then
		carryC:Disconnect()
		carryC = nil
	end
	setPickStatus("off", COL.textDim)
end
local function stopPick()
	pickToken = pickToken + 1
	local tok = pickToken
	picking = false
	stopWalk()
	stopMove()
	-- Stop cancels pick queue only; keep in-progress pick delivery/reclaim
	if carrying and not atSafe() then
		deliverMode = "pick"
		reclaiming = false
		homeActive = true
		token = token + 1
		task.defer(runHome, token)
		setPickStatus("pick stopped · delivering", Color3.fromRGB(255, 180, 80))
	elseif reclaiming and lastEgg and lastEgg.uid and not atSafe() then
		deliverMode = "pick"
		local u, a, pos = lastEgg.uid, lastEgg.area, rootPos()
		task.spawn(reclaimEgg, u, a, pos, tok)
		setPickStatus("pick stopped · reclaiming", Color3.fromRGB(255, 180, 80))
	else
		if deliverMode == "pick" then
			deliverMode = nil
		end
		setPickStatus("pick stopped", Color3.fromRGB(255, 180, 80))
	end
end
local function walkTo(target, arrive, timeout, tok, tickFn)
	stopWalk()
	local h, r = getHum(), getRoot()
	if not h or not r then
		return false
	end
	h.Sit = false
	h.PlatformStand = false
	local t0 = os.clock()
	local done, ok = false, false

	Run:BindToRenderStep(WALK_BIND, Enum.RenderPriority.Character.Value + 5, function()
		if done or tok ~= pickToken then
			done = true
			return
		end
		h, r = getHum(), getRoot()
		if not h or not r or h.Health <= 0 then
			done = true
			return
		end
		local p = r.Position
		local flat = Vector3.new(target.X - p.X, 0, target.Z - p.Z)
		local dist = flat.Magnitude
		if dist <= arrive then
			h:Move(ZERO, false)
			ok, done = true, true
			return
		end
		if dist > 0.05 then
			h:Move(flat.Unit, false)
		end
		if os.clock() - t0 > timeout then
			done = true
		end
	end)

	while not done do
		if tok ~= pickToken then
			break
		end
		if tickFn and (tickFn() or carrying) then
			ok = carrying or ok
			break
		end
		task.wait(0.05)
	end
	stopWalk()
	return ok and tok == pickToken
end
local function buildPayloads(egg, ground)
	local u = tostring(egg.uid)
	local a = tostring(egg.area)
	local nestId = tostring(egg.nestId)
	if nestId == "?" or nestId == "" then
		nestId = "Slot_001"
	end
	local slotN = egg.slot or nestSlotNum(nestId) or 1
	if not string.find(nestId, "Slot_", 1, true) then
		nestId = string.format("Slot_%03d", slotN)
	end
	local comp = compositeNestId(a, nestId)
	if ground then
		return {
			{ Uid = u, NestId = comp, AreaId = a },
			{ Uid = u, NestId = nestId, AreaId = a },
			{ Uid = u, NestId = nestId },
		}
	end
	return {
		{ Uid = u, NestId = comp, AreaId = a },
		{ Uid = u, NestId = nestId, AreaId = a },
	}
end
local function invokeRF(rf, payload)
	if carrying then return true end
	local ok, res = pcall(function() return rf:InvokeServer(payload) end)
	if carrying then return true end
	if ok and res == true then
		local t0 = os.clock()
		while not carrying and os.clock() - t0 < 0.35 do task.wait(0.05) end
		return true
	end
	return false
end

-- Instant E (Dist): indipendente da Auto Safe / Pick / deliver
local function iePromptWorldPos(p)
	local par = p and p.Parent
	if not par then return nil end
	if par:IsA("BasePart") then return par.Position end
	if par:IsA("Attachment") then return par.WorldPosition end
	if par:IsA("Model") then return par:GetPivot().Position end
	local bp = par:FindFirstChildWhichIsA("BasePart", true)
	return bp and bp.Position or nil
end
local function ieIsStealPrompt(p)
	if not p or not p:IsA("ProximityPrompt") then return false end
	if p.Name == "CarryAreaEgg" then return true end
	return string.lower(tostring(p.ActionText or "")) == "steal"
end
local function ieGetSnapshot(force)
	local now = clock()
	if not force and IE.snapRes and (now - IE.snapAt) < IE_SNAP_CACHE then
		return IE.snapRes
	end
	local rf = snapshotRF()
	if not rf then return nil end
	local ok, res = pcall(function() return rf:InvokeServer() end)
	if ok and typeof(res) == "table" then
		IE.snapAt, IE.snapRes = now, res
		return res
	end
	return nil
end
local function ieEggFromSnap(pos, snap)
	if not snap or typeof(snap.Records) ~= "table" then return nil end
	local best, bd = nil, IE_RANGE + 1
	for _, rec in pairs(snap.Records) do
		if typeof(rec) == "table" and rec.Uid then
			local st = tostring(rec.State or "")
			if st == "Slot" or st == "Dropped" or st == "GuardCarried" then
				local p = cfPos(rec.BottomCFrame) or cfPos(rec.BoundsCFrame)
				if not p then
					local er = eggFromRecord(rec)
					p = er and er.pos
				end
				if p then
					local d = xzDist(pos, p)
					if d < bd then
						bd = d
						best = {
							uid = tostring(rec.Uid),
							area = tostring(rec.AreaId or LP:GetAttribute("AreaId") or "?"),
							nestId = tostring(rec.NestId or "Slot_001"),
							pos = p,
							ground = st ~= "Slot",
							slot = nestSlotNum(rec.NestId) or 0,
						}
					end
				end
			end
		end
	end
	return best
end
local function ieFindEgg(selectPos)
	if IE.snapRes and (clock() - IE.snapAt) < IE_SNAP_CACHE then
		local egg = ieEggFromSnap(selectPos, IE.snapRes)
		if egg then
			IE.cached = egg
			return egg
		end
	end
	local snap = ieGetSnapshot(false) or ieGetSnapshot(true)
	IE.cached = ieEggFromSnap(selectPos, snap)
	return IE.cached
end
local function iePrefetch()
	if not instantE or IE.busy or carrying or picking then return end
	local r = getRoot()
	if not r then return end
	local snap = ieGetSnapshot(false)
	if snap then
		IE.cached = ieEggFromSnap(r.Position, snap)
	end
end
local function ieTryPickup()
	if not instantE or IE.busy or carrying or picking then return end
	if UIS:GetFocusedTextBox() then return end
	local now = clock()
	if now - IE.lastFire < IE_CD then return end
	local r = getRoot()
	if not r then return end
	local playerPos = r.Position
	if IE.shown and IE.shown.Parent then
		IE.shownPos = iePromptWorldPos(IE.shown) or IE.shownPos
	else
		IE.shown, IE.shownPos = nil, nil
	end
	local selectPos = IE.shownPos or playerPos
	local egg = ieFindEgg(selectPos)
	if not egg or xzDist(playerPos, egg.pos) > IE_RANGE then
		egg = ieEggFromSnap(selectPos, ieGetSnapshot(true))
	end
	if not egg then return end
	if xzDist(playerPos, egg.pos) > IE_RANGE then return end
	local rf = askCarryRF()
	if not rf then return end
	IE.busy, IE.lastFire = true, now
	for _, pl in ipairs(buildPayloads(egg, egg.ground)) do
		if invokeRF(rf, pl) or carrying then break end
	end
	IE.cached, IE.snapRes = nil, nil
	IE.busy = false
end
local function ieDisarm()
	if IE.inputConn then IE.inputConn:Disconnect() IE.inputConn = nil end
	if IE.shownConn then IE.shownConn:Disconnect() IE.shownConn = nil end
	if IE.hiddenConn then IE.hiddenConn:Disconnect() IE.hiddenConn = nil end
	if IE.hbConn then IE.hbConn:Disconnect() IE.hbConn = nil end
	IE.shown, IE.shownPos, IE.cached, IE.snapRes = nil, nil, nil, nil
	IE.busy = false
end
local function ieArm()
	ieDisarm()
	IE.shownConn = PPS.PromptShown:Connect(function(prompt)
		if not instantE or not ieIsStealPrompt(prompt) then return end
		IE.shown = prompt
		IE.shownPos = iePromptWorldPos(prompt)
	end)
	IE.hiddenConn = PPS.PromptHidden:Connect(function(prompt)
		if prompt == IE.shown then
			IE.shown, IE.shownPos = nil, nil
		end
	end)
	IE.inputConn = UIS.InputBegan:Connect(function(input)
		if not instantE then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode ~= Enum.KeyCode.E then return end
		ieTryPickup()
	end)
	IE.hbConn = Run.Heartbeat:Connect(function()
		if not instantE or IE.busy or carrying or picking then return end
		local now = clock()
		if now - IE.lastPrefetch < IE_PREFETCH then return end
		IE.lastPrefetch = now
		iePrefetch()
	end)
	task.defer(iePrefetch)
end
local function setInstantE(on)
	instantE = on and true or false
	if instantE then
		ieArm()
	else
		ieDisarm()
	end
end

local function waitCarrying(timeout, tok, wantUid, strictUid)
	local t0 = os.clock()
	while tok == pickToken and os.clock() - t0 < timeout do
		if carrying then
			if wantUid and uid and not uidMatch(uid, wantUid) then
				if strictUid then return false end
			else
				return true
			end
		end
		task.wait(0.06)
	end
	return false
end
local function findSlotModelNear(pos, wantUid, maxD)
	maxD = maxD or 12
	local client = findSlotsClient()
	if not client or not pos then
		return nil
	end
	local best, bd = nil, maxD + 1
	for _, ch in ipairs(client:GetChildren()) do
		if ch:IsA("Model") and not string.match(ch.Name, "^%d+_") then
			if not wantUid or uidMatch(ch.Name, wantUid) then
				local d = xzDist(ch:GetPivot().Position, pos)
				if d < bd then
					bd, best = d, ch
				end
			end
		end
	end
	return best, bd
end
local function resolveLiveEgg(egg)
	if not egg or not egg.pos or egg.ground then
		return egg
	end
	local slotM, sd = findSlotModelNear(egg.pos, egg.uid, 12)
	if not slotM then
		slotM, sd = findSlotModelNear(egg.pos, nil, 6)
		if slotM and egg.uid and not uidMatch(slotM.Name, egg.uid) then
			return egg
		end
	end
	if slotM then
		egg.slotModel = slotM.Name
		egg.pos = slotM:GetPivot().Position
		if uidMatch(slotM.Name, egg.uid) then
			egg.uid = slotM.Name
		end
	end
	return egg
end
local function snapWantUid(wantUid)
	local rf = snapshotRF()
	if not rf or not wantUid then
		return nil
	end
	local ok, res = pcall(function()
		return rf:InvokeServer()
	end)
	if not ok or typeof(res) ~= "table" or typeof(res.Records) ~= "table" then
		return nil
	end
	for _, rec in pairs(res.Records) do
		if typeof(rec) == "table" and rec.Uid and uidMatch(rec.Uid, wantUid) then
			local stt = tostring(rec.State or "")
			local egg = eggFromRecord(rec)
			if not egg.pos then
				return nil
			end
			if stt == "Dropped" or stt == "GuardCarried" then
				egg.ground = true
				egg.requireUid = true
				return egg
			end
			if stt == "Slot" then
				egg.fromNest = true
				egg.requireUid = true
				return egg
			end
			if stt == "Carried" then
				return nil
			end
			egg.ground = true
			egg.requireUid = true
			return egg
		end
	end
	return nil
end
local function findGroundLocal(dropPos, wantUid, nestPos)
	if not dropPos or not wantUid then
		return nil
	end
	local client = findSlotsClient()
	if not client then
		return nil
	end
	local best, bd = nil, RECLAIM_RADIUS + 1
	for _, ch in ipairs(client:GetChildren()) do
		if ch:IsA("Model") and uidMatch(ch.Name, wantUid) then
			local p = ch:GetPivot().Position
			local d = xzDist(p, dropPos)
			if d <= RECLAIM_RADIUS and d < bd then
				if not nestPos or xzDist(p, nestPos) > NEST_NEAR then
					bd, best = d, ch
				end
			end
		end
	end
	if not best then
		return nil
	end
	local p = best:GetPivot().Position
	return {
		uid = best.Name,
		name = lastEgg and lastEgg.name or "?",
		area = lastEgg and lastEgg.area or "?",
		nestId = lastEgg and lastEgg.nestId or "?",
		slot = lastEgg and lastEgg.slot or 0,
		pos = p,
		slotModel = best.Name,
		ground = true,
		requireUid = true,
	}
end
local function pollDropSteal(egg, tok, wantUid, budget)
	budget = budget or 5
	if not egg or not egg.pos or tok ~= pickToken then
		return false
	end
	egg.ground = true
	local rf = askCarryRF()
	if not rf then
		return false
	end
	local payloads = buildPayloads(egg, true)
	local primary = payloads[1]
	local t0 = os.clock()
	local lastFull, lastRf, lastSnap = 0, 0, 0
	local rfOk = false

	local function fire(full)
		if rfOk or carrying then
			return carrying or rfOk
		end
		if full then
			for i = 1, #payloads do
				if invokeRF(rf, payloads[i]) or carrying then
					rfOk = true
					return true
				end
			end
			return carrying
		end
		if invokeRF(rf, primary) then
			rfOk = true
			return true
		end
		return false
	end

	local here = rootPos()
	if here and xzDist(here, egg.pos) > ARRIVE_NEST + 1 then
		walkTo(egg.pos, ARRIVE_NEST, 25, tok, function()
			if tok ~= pickToken or carrying then
				return true
			end
			local r = getRoot()
			if not r or xzDist(r.Position, egg.pos) > 18 then
				return false
			end
			local now = os.clock()
			if now - lastRf < 0.12 then
				return false
			end
			lastRf = now
			fire(false)
			return carrying
		end)
	end

	if carrying and uidMatch(uid, wantUid) then
		return true
	end

	while tok == pickToken and not carrying and os.clock() - t0 < budget do
		local now = os.clock()
		if not rfOk then
			local full = lastFull == 0 or (now - lastFull >= 0.9)
			if full then
				lastFull = now
			end
			fire(full)
		end
		if carrying then
			break
		end
		if now - lastSnap >= 0.75 then
			lastSnap = now
			local snap = snapWantUid(wantUid)
			if snap and snap.ground and snap.pos then
				local r = getRoot()
				if r and xzDist(egg.pos, snap.pos) > 12 then
					egg.pos = snap.pos
					egg.uid = snap.uid
					rfOk = false
					if xzDist(r.Position, snap.pos) > 20 then
						walkTo(egg.pos, ARRIVE_NEST, 12, tok)
					end
				else
					egg.pos = snap.pos
				end
			end
		end
		task.wait(0.12)
	end
	return carrying and uidMatch(uid, wantUid)
end
local function stealNest(egg, tok, walkTimeout, wantUid, waitSec)
	if carrying or not egg or not egg.pos then return carrying end
	local here = rootPos()
	if here and xzDist(here, egg.pos) > ARRIVE_NEST then
		walkTo(egg.pos, ARRIVE_NEST, walkTimeout or 20, tok or pickToken)
	end
	if tok and tok ~= pickToken then return false end
	egg = resolveLiveEgg(egg)
	if wantUid and not uidMatch(egg.uid, wantUid) then return false end
	local rf = askCarryRF()
	if not rf then return false end
	for _, pl in ipairs(buildPayloads(egg, false)) do
		if invokeRF(rf, pl) or carrying then break end
	end
	if wantUid then return waitCarrying(waitSec or 1.2, tok, wantUid, false) end
	return carrying
end
reclaimEgg = function(dropUid, dropArea, dropPos, tok)
	if tok ~= pickToken or reclaiming then
		return
	end
	reclaiming = true
	homeActive = false
	setPickStatus("reclaiming…", Color3.fromRGB(255, 180, 100))
	local nestPos = nestPosOf(lastEgg)

	local function finishOk()
		reclaiming = false
		setPickStatus("reclaimed", Color3.fromRGB(120, 220, 255))
		if wantsDeliver() and carrying and not running and not atSafe() then
			resumeDeliverHome()
		end
	end

	local function tryEgg(egg)
		if not egg or not egg.pos or not uidMatch(egg.uid, dropUid) then return false end
		if egg.slotModel and uidMatch(egg.slotModel, dropUid) then egg.uid = egg.slotModel end
		egg.requireUid = true
		if egg.ground then return pollDropSteal(egg, tok, dropUid, 5.5) end
		return stealNest(egg, tok, 30, dropUid, 1.2)
	end

	local target = nil
	for _ = 1, 12 do
		if tok ~= pickToken or carrying then
			break
		end
		target = findGroundLocal(dropPos or rootPos(), dropUid, nestPos)
		if not target then
			local snap = snapWantUid(dropUid)
			if snap and (snap.ground or snap.fromNest) then
				target = snap
			end
		end
		if target then
			break
		end
		task.wait(0.15)
	end

	if target and tryEgg(target) then
		finishOk()
		return
	end

	if tok == pickToken and not carrying then
		local snap = snapWantUid(dropUid)
		if snap and tryEgg(snap) then
			finishOk()
			return
		end
	end

	reclaiming = false
	if carrying and uidMatch(uid, dropUid) then
		finishOk()
	else
		setPickStatus("reclaim fail", COL.warn)
		homeActive = false
		if deliverMode ~= "pick" and not picking then
			deliverMode = nil
		end
	end
end
local function trySteal(egg)
	return stealNest(egg, pickToken, 20, nil, nil)
end
local function waitDelivered(tok)
	local t0 = os.clock()
	while tok == pickToken and os.clock() - t0 < TIMEOUT + 30 do
		if tok ~= pickToken then
			return false
		end
		if atSafe() and not carrying then
			homeActive = false
			if not picking then
				deliverMode = nil
			end
			return true
		end
		local pending = reclaiming
			or homeActive
			or running
			or carrying
			or (wantsDeliver() and lastEgg and lastEgg.uid and not atSafe())
		if not pending then
			return false
		end
		task.wait(0.12)
	end
	return tok == pickToken and atSafe() and not carrying
end
local function sortEggsByAreaSlot(list)
	table.sort(list, function(a, b)
		if a.area == b.area then
			return (a.slot or 0) < (b.slot or 0)
		end
		return a.area < b.area
	end)
end
local function refreshEggs()
	if refreshBusy then
		return
	end
	refreshBusy = true
	pcall(function()
		local rf = snapshotRF()
		if not rf then
			setPickStatus("no snapshot RF", COL.warn)
			return
		end
		local ok, res = pcall(function()
			return rf:InvokeServer()
		end)
		if not ok or typeof(res) ~= "table" or typeof(res.Records) ~= "table" then
			setPickStatus("snapshot fail", COL.warn)
			return
		end
		local list = {}
		for _, rec in pairs(res.Records) do
			if typeof(rec) == "table" and rec.Uid and rec.AreaId and not isSkippedEgg(rec) then
				local egg = eggFromRecord(rec)
				egg.name = tostring(rec.AssetCategory or "?")
				egg.area = tostring(rec.AreaId)
				egg.rarity = rareByUid[egg.uid]
					or classifyRarity(rec.RarityId)
					or classifyRarity(rec.Rarity)
					or "Normal"
				list[#list + 1] = egg
			end
		end
		sortEggsByAreaSlot(list)
		eggs = list
		noteDiscoveredAreas(list)
		rebuildList()
	end)
	refreshBusy = false
end
local function startAutoRefresh()
	autoRefreshTok = autoRefreshTok + 1
	local tok = autoRefreshTok
	task.spawn(function()
		refreshEggs()
		while tok == autoRefreshTok and gui and gui.Parent do
			task.wait(REFRESH_EVERY)
			if tok ~= autoRefreshTok or not gui or not gui.Parent then
				break
			end
			refreshEggs()
		end
	end)
end
local function eggMatches(e)
	local q = string.lower(searchText or "")
	if q == "" then return true end
	return string.find(string.lower(e.name .. " " .. e.area .. " " .. (e.rarity or "") .. " " .. e.nestId), q, 1, true) ~= nil
end
rebuildList = function()
	if not listFrame then return end
	for _, ch in ipairs(listFrame:GetChildren()) do
		if ch:IsA("TextButton") then ch:Destroy() end
	end
	local filt = {}
	for _, e in ipairs(eggs) do
		if eggMatches(e) then filt[#filt + 1] = e end
	end
	if countLbl and not picking and not reclaiming then
		countLbl.Text = string.format("%d / %d eggs", #filt, #eggs)
		countLbl.TextColor3 = COL.textDim
	end
	for i, e in ipairs(filt) do
		local selected = selectedUid == e.uid
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -4, 0, 26)
		b.BackgroundColor3 = selected and COL.sel or COL.row
		b.BorderSizePixel = 0
		b.Text = "  " .. e.name .. "  ·  " .. e.area
		b.TextColor3 = COL.text
		b.Font = Enum.Font.Gotham
		b.TextSize = 12
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.AutoButtonColor = false
		b.LayoutOrder = i
		b.Parent = listFrame
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
		local ref = e
		b.MouseEnter:Connect(function()
			if selectedUid ~= ref.uid then b.BackgroundColor3 = COL.rowHot end
		end)
		b.MouseLeave:Connect(function()
			b.BackgroundColor3 = (selectedUid == ref.uid) and COL.sel or COL.row
		end)
		b.MouseButton1Click:Connect(function()
			selectedUid = (selectedUid == ref.uid) and nil or ref.uid
			rebuildList()
		end)
	end
	listFrame.CanvasSize = UDim2.fromOffset(0, #filt * 28)
end
local function findEggByUid(u)
	for _, e in ipairs(eggs) do
		if e.uid == u then return e end
	end
end
local function pickOne(egg, tok)
	if not egg or isSkippedEgg(egg) or not egg.pos then
		setPickStatus("skip", Color3.fromRGB(255, 150, 80))
		return false
	end
	if not armed then startArm() end
	lastEgg = { uid = egg.uid, name = egg.name, area = egg.area, nestId = egg.nestId, slot = egg.slot, pos = egg.pos }
	setPickStatus(string.format("→ %s", egg.name), Color3.fromRGB(255, 220, 120))
	if not walkTo(egg.pos, ARRIVE_NEST, 60, tok) then
		if tok == pickToken then setPickStatus("walk fail", COL.warn) end
		return false
	end
	setPickStatus("steal " .. egg.name, Color3.fromRGB(255, 200, 100))
	if not carrying then trySteal(egg) end
	if not waitCarrying(PICK_TIMEOUT, tok, egg.uid, true) then
		setPickStatus("steal fail", COL.warn)
		return false
	end
	deliverMode = "pick"
	setPickStatus("carrying → home", Color3.fromRGB(120, 220, 255))
	if not (homeActive or running) then resumeDeliverHome() end
	if not waitDelivered(tok) then
		setPickStatus("deliver fail", COL.warn)
		return false
	end
	setPickStatus("ok " .. egg.name, COL.accent)
	task.wait(BETWEEN_PICKS)
	return tok == pickToken
end
local function startPickQueue(list)
	if picking then return end
	if not list or #list == 0 then
		setPickStatus("Empty list", Color3.fromRGB(255, 180, 80))
		return
	end
	picking, deliverMode = true, "pick"
	pickToken = pickToken + 1
	local tok = pickToken
	if not armed then startArm() end
	task.spawn(function()
		local okN, failN = 0, 0
		for i, egg in ipairs(list) do
			if tok ~= pickToken then
				break
			end
			setPickStatus(string.format("Pick %d/%d", i, #list), Color3.fromRGB(255, 220, 120))
			if pickOne(egg, tok) then
				okN = okN + 1
			else
				failN = failN + 1
				if tok ~= pickToken then
					break
				end
			end
		end
		if tok == pickToken then
			picking = false
			if not carrying and not reclaiming and not homeActive and not running then
				deliverMode = nil
			end
			setPickStatus(string.format("Done ok=%d fail=%d", okN, failN), COL.accent)
			refreshEggs()
		end
	end)
end
local function pickSelected()
	if not selectedUid then
		setPickStatus("Select an egg", Color3.fromRGB(255, 180, 80))
		return
	end
	local e = findEggByUid(selectedUid)
	if not e then
		setPickStatus("Egg gone", Color3.fromRGB(255, 180, 80))
		return
	end
	startPickQueue({ e })
end
local function pickAreas()
	local out = {}
	for _, e in ipairs(eggs) do
		if areaOn[e.area] and e.pos then
			out[#out + 1] = e
		end
	end
	sortEggsByAreaSlot(out)
	if #out == 0 then
		setPickStatus("Enable 1+ areas", Color3.fromRGB(255, 180, 80))
		return
	end
	startPickQueue(out)
end

task.defer(function()
	local re = findRemote("RemoteEvent", "FieldEggRaritiesShown")
	if re then
		re.OnClientEvent:Connect(function(p)
			if typeof(p) ~= "table" or typeof(p.RareSpawns) ~= "table" then
				return
			end
			for _, rec in pairs(p.RareSpawns) do
				if typeof(rec) == "table" then
					local u = rec.EggUid or rec.Uid
					local rar = classifyRarity(rec.RarityId) or classifyRarity(rec.Message)
					if u and rar then
						rareByUid[tostring(u)] = rar
					end
				end
			end
			pcall(rebuildList)
		end)
	end
end)

-- ========== Halloween auto-kill ==========
local HW_POLL = 0.12
local hwOn = false
local hwByModel = {}
local hwList = table.create(64)
local hwN = 0
local hwTarget = nil
local hwConns = {}
local hwAcc = 0
local hwStatusLbl, hwKillBtn
local function setHwStatus(t, col)
	if hwStatusLbl then
		hwStatusLbl.Text = t
		hwStatusLbl.TextColor3 = col or COL.textDim
	end
end
local function paintHwBtn()
	if not hwKillBtn then
		return
	end
	local lab = hwOn and "AUTO-KILL ON" or "AUTO-KILL OFF"
	hwKillBtn.Name = lab
	hwKillBtn.Text = lab
	hwKillBtn.TextColor3 = hwOn and COL.accent or COL.text
end
local function hwClearConns()
	for i = 1, #hwConns do
		pcall(function()
			hwConns[i]:Disconnect()
		end)
	end
	table.clear(hwConns)
end
local function hwParts(m)
	local hb, r
	pcall(function()
		hb = m:FindFirstChild("Hitbox")
		r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or hb
	end)
	if hb and not hb:IsA("BasePart") then
		hb = nil
	end
	return hb, r
end
local function hwReadHp(hb)
	if not hb then
		return
	end
	local hp, maxHp
	pcall(function()
		hp = hb:GetAttribute("Health")
		maxHp = hb:GetAttribute("MaxHealth") or hb:GetAttribute("MaxHP")
	end)
	if typeof(hp) ~= "number" then
		return
	end
	if typeof(maxHp) ~= "number" then
		maxHp = hp
	end
	return hp, maxHp
end
local function hwDrop(m)
	local rec = hwByModel[m]
	if not rec then
		return
	end
	hwByModel[m] = nil
	local i = rec.i
	if i and i <= hwN and hwList[i] == rec then
		local last = hwList[hwN]
		hwList[i] = last
		hwList[hwN] = nil
		hwN -= 1
		if last and last ~= rec then
			last.i = i
		end
	end
	if hwTarget == rec then
		hwTarget = nil
	end
end
local function hwAdd(m)
	if not hwOn or hwByModel[m] or not m:IsA("Model") then
		return
	end
	local hb, r = hwParts(m)
	local hp, maxHp = hwReadHp(hb)
	if typeof(hp) == "number" and hp <= 0 then
		return
	end
	hwN += 1
	local rec = {
		m = m,
		name = m.Name,
		hp = hp or 0,
		maxHp = maxHp or hp or 0,
		hb = hb,
		root = r,
		i = hwN,
	}
	hwByModel[m] = rec
	hwList[hwN] = rec
	hwConns[#hwConns + 1] = m.AncestryChanged:Connect(function(_, p)
		if not p then
			hwDrop(m)
		end
	end)
end
local function hwRefresh(rec)
	local m = rec.m
	if not m.Parent then
		hwDrop(m)
		return false
	end
	if not rec.hb or not rec.hb.Parent then
		local hb, r = hwParts(m)
		rec.hb = hb
		if not rec.root or not rec.root.Parent then
			rec.root = r
		end
	elseif not rec.root or not rec.root.Parent then
		local _, r = hwParts(m)
		rec.root = r or rec.hb
	end
	local hp, maxHp = hwReadHp(rec.hb)
	if typeof(hp) == "number" then
		rec.hp = hp
		if hp <= 0 then
			hwDrop(m)
			return false
		end
	end
	if typeof(maxHp) == "number" then
		rec.maxHp = maxHp
	end
	return true
end
local function hwPickBest()
	local best
	local bestMax, bestHp = -1, -1
	for i = 1, hwN do
		local rec = hwList[i]
		if rec and hwRefresh(rec) then
			local maxHp = typeof(rec.maxHp) == "number" and rec.maxHp or 0
			local hp = typeof(rec.hp) == "number" and rec.hp or 0
			if maxHp > bestMax or (maxHp == bestMax and hp > bestHp) then
				best = rec
				bestMax = maxHp
				bestHp = hp
			end
		end
	end
	return best
end
local function hwTp(rec)
	local r = getRoot()
	if not r then
		return
	end
	local part = rec.root
	local pos
	if part and part.Parent then
		pos = part.Position
	else
		local ok, p = pcall(function()
			return rec.m:GetPivot().Position
		end)
		if ok then
			pos = p
		end
	end
	if not pos then
		return
	end
	r.AssemblyLinearVelocity = ZERO
	r.AssemblyAngularVelocity = ZERO
	r.CFrame = CFrame.new(pos)
end
local function hwBindFolder()
	local dim = Workspace:FindFirstChild("HalloweenDimension")
	if not dim then
		for _, ch in ipairs(Workspace:GetChildren()) do
			if string.find(string.lower(ch.Name), "halloween", 1, true) then
				dim = ch
				break
			end
		end
	end
	return dim and dim:FindFirstChild("Monsters")
end
local function stopHwKill()
	hwOn = false
	hwTarget = nil
	hwAcc = 0
	hwClearConns()
	table.clear(hwByModel)
	table.clear(hwList)
	hwN = 0
	paintHwBtn()
	setHwStatus("auto-kill off", COL.textDim)
end
local function startHwKill()
	if hwOn then
		return
	end
	local folder = hwBindFolder()
	if not folder then
		setHwStatus("Monsters non trovato", COL.warn)
		return
	end
	hwOn = true
	hwTarget = nil
	hwAcc = 0
	hwClearConns()
	table.clear(hwByModel)
	table.clear(hwList)
	hwN = 0
	paintHwBtn()
	setHwStatus("scan…", COL.accent)
	local kids = folder:GetChildren()
	for i = 1, #kids do
		if kids[i]:IsA("Model") then
			hwAdd(kids[i])
		end
	end
	hwConns[#hwConns + 1] = folder.ChildAdded:Connect(function(ch)
		if ch:IsA("Model") then
			hwAdd(ch)
		end
	end)
	hwConns[#hwConns + 1] = folder.ChildRemoved:Connect(function(ch)
		if hwByModel[ch] then
			hwDrop(ch)
		end
	end)
	setHwStatus("caccia…", COL.accent)
end
local function hwTick()
	if not hwOn then
		return
	end
	if hwTarget then
		if hwRefresh(hwTarget) then
			hwTp(hwTarget)
			setHwStatus(hwTarget.name .. "  " .. hwTarget.hp .. "/" .. hwTarget.maxHp, COL.accent)
			return
		end
		hwTarget = nil
	end
	hwTarget = hwPickBest()
	if not hwTarget then
		setHwStatus("nessun mostro", Color3.fromRGB(255, 180, 80))
		return
	end
	hwTp(hwTarget)
	setHwStatus(hwTarget.name .. "  " .. hwTarget.hp .. "/" .. hwTarget.maxHp, COL.accent)
end
extraConns[#extraConns + 1] = Run.Heartbeat:Connect(function(dt)
	if not alive or not hwOn then
		return
	end
	hwAcc += dt
	if hwAcc < HW_POLL then
		return
	end
	hwAcc = 0
	hwTick()
end)

-- ========== Halloween auto-fish (from fish_log v12c, no logger) ==========
-- Isolated in IIFE: main chunk was past Luau's 200 local-register limit.
local Fish = (function()
local FISH_CHARGE_RELEASE = 0.82
local FISH_HOLD_MIN = 0.95
local FISH_HOLD_MAX = 1.40
local FISH_CHARGE_ARMED = 0.35
local FISH_CHARGE_APPEAR = 1.6
local FISH_REEL_DT = 0.025
local FISH_REEL_BURST = 16
local FISH_BETWEEN = 0.8
local FISH_START_DELAY = 0.8
local FISH_BITE_TIMEOUT = 14
local FISH_REEL_TIMEOUT = 5
local FISH_REVEAL_WAIT = 6
local FISH_READY_TIMEOUT = 8
local FISH_TP = Vector3.new(-5204, -205, -6082)

local fishOn = false
local fishBusy = false
local fishBtn
local fishTpConn = nil
local fishConns = {}
local fishUiConns = {}
local fishPhase = "idle"
local fishRod = nil
local fishUi = nil
local fishHold = false
local fishHoldT0 = 0
local fishCastAt = 0
local fishNextCast = 0
local fishPerfect = false
local fishChargeArmed = false
local fishReleaseWhy = ""
local fishTipSeenOff = true
local fishTipFresh = false
local fishRefs = {
	Charge = nil,
	Perfect = nil,
	Pointer = nil,
	Track = nil,
	Reel = nil,
	Reveal = nil,
	Tooltip = nil,
}

local function setFishStatus(t, col)
	if hwOn then
		return
	end
	setHwStatus(t, col)
end

local function paintFishBtn()
	if not fishBtn then
		return
	end
	local lab = fishOn and "AUTO FISH ON" or "AUTO FISH OFF"
	fishBtn.Name = lab
	fishBtn.Text = lab
	fishBtn.TextColor3 = fishOn and COL.accent or COL.text
end

local function fishClearUiConns()
	for i = 1, #fishUiConns do
		pcall(function()
			fishUiConns[i]:Disconnect()
		end)
	end
	table.clear(fishUiConns)
end

local function fishClearConns()
	fishClearUiConns()
	for i = 1, #fishConns do
		pcall(function()
			fishConns[i]:Disconnect()
		end)
	end
	table.clear(fishConns)
end

local function fishStopTp()
	if fishTpConn then
		pcall(function()
			fishTpConn:Disconnect()
		end)
		fishTpConn = nil
	end
end

local function fishStartTp()
	fishStopTp()
	fishTpConn = Run.Heartbeat:Connect(function()
		if not alive or not fishOn then
			return
		end
		local r = getRoot()
		if not r then
			return
		end
		r.CFrame = CFrame.new(FISH_TP)
		r.AssemblyLinearVelocity = ZERO
		r.AssemblyAngularVelocity = ZERO
	end)
end

local function fishVis(obj)
	if not obj or not obj.Parent then
		return false
	end
	local ok, v = pcall(function()
		return obj.Visible
	end)
	return ok and v == true
end

local function fishChargePct()
	local track, ptr = fishRefs.Track, fishRefs.Pointer
	if not track or not ptr or not track.Parent or not ptr.Parent then
		return nil
	end
	local ok, pct = pcall(function()
		local top = track.AbsolutePosition.Y
		local h = track.AbsoluteSize.Y
		if h < 1 then
			return nil
		end
		local py = ptr.AbsolutePosition.Y + ptr.AbsoluteSize.Y * 0.5
		local p = 1 - (py - top) / h
		if p < 0 then
			p = 0
		elseif p > 1 then
			p = 1
		end
		return p
	end)
	return ok and pct or nil
end

local function fishNoteTip(on)
	if on then
		if fishTipSeenOff then
			fishTipFresh = true
			fishTipSeenOff = false
		end
	else
		fishTipSeenOff = true
		fishTipFresh = false
	end
end

local function fishSyncTip()
	if fishRefs.Tooltip and fishVis(fishRefs.Tooltip) then
		fishTipSeenOff = false
		fishTipFresh = false
	else
		fishTipSeenOff = true
		fishTipFresh = false
	end
end

local function fishReady()
	if fishHold or fishBusy then
		return false
	end
	if fishVis(fishRefs.Reveal) or fishVis(fishRefs.Reel) or fishVis(fishRefs.Charge) or fishVis(fishRefs.Perfect) then
		return false
	end
	if clock() < fishNextCast then
		return false
	end
	if not (fishRefs.Tooltip and fishVis(fishRefs.Tooltip)) then
		fishNoteTip(false)
		return false
	end
	fishNoteTip(true)
	return fishTipFresh
end

local function fishWaitReady(forceCycle)
	local t0 = clock()
	if forceCycle and fishRefs.Tooltip and fishVis(fishRefs.Tooltip) then
		fishTipFresh = false
		fishTipSeenOff = false
		setFishStatus("fish: tip clear…", COL.textDim)
		while alive and fishOn and fishVis(fishRefs.Tooltip) do
			if clock() - t0 > FISH_READY_TIMEOUT then
				break
			end
			task.wait(0.12)
		end
		fishNoteTip(false)
		t0 = clock()
	end
	while alive and fishOn do
		if fishRefs.Tooltip then
			fishNoteTip(fishVis(fishRefs.Tooltip))
		end
		if fishReady() then
			return true
		end
		if clock() - t0 > FISH_READY_TIMEOUT then
			return false
		end
		setFishStatus(fishTipSeenOff and "fish: wait tip…" or "fish: tip refresh…", COL.textDim)
		task.wait(0.12)
	end
	return false
end

local function fishIsRod(tool)
	if not tool or not tool:IsA("Tool") then
		return false
	end
	local n = string.lower(tool.Name)
	if string.find(n, "rod", 1, true) or string.find(n, "fish", 1, true) then
		return true
	end
	local ok, v = pcall(function()
		return tool:GetAttribute("GhostDogRod") or tool:GetAttribute("GearName")
	end)
	if ok and v then
		if v == true then
			return true
		end
		return string.find(string.lower(tostring(v)), "rod", 1, true) ~= nil
	end
	return false
end

local function fishFindRod()
	local c = char or LP.Character
	if c then
		for _, ch in ipairs(c:GetChildren()) do
			if fishIsRod(ch) then
				return ch
			end
		end
	end
	local bp = LP:FindFirstChildOfClass("Backpack")
	if bp then
		for _, ch in ipairs(bp:GetChildren()) do
			if fishIsRod(ch) then
				return ch
			end
		end
	end
end

local function fishEnsureRod()
	if fishRod and fishRod.Parent == (char or LP.Character) then
		return true
	end
	local tool = fishFindRod()
	if not tool then
		setFishStatus("fish: no rod", COL.warn)
		return false
	end
	local h = getHum()
	if not h then
		return false
	end
	pcall(function()
		h:EquipTool(tool)
	end)
	fishRod = tool
	fishPhase = "equipped"
	task.wait(0.3)
	return true
end

local function fishRemember(obj)
	local n = obj.Name
	if n == "Charge" and obj:IsA("Frame") then
		fishRefs.Charge = obj
	elseif n == "Perfect" then
		fishRefs.Perfect = obj
	elseif n == "Pointer" then
		local under = fishRefs.Charge and obj:IsDescendantOf(fishRefs.Charge)
		if under or not fishRefs.Pointer then
			fishRefs.Pointer = obj
		end
	elseif n == "Fill" and obj.Parent and obj.Parent.Name == "Track" then
		fishRefs.Track = obj.Parent
	elseif n == "Track" and obj.Parent and obj.Parent.Name == "Charge" then
		fishRefs.Track = obj
	elseif n == "Reel" then
		fishRefs.Reel = obj
	elseif n == "Reveal" then
		fishRefs.Reveal = obj
	elseif n == "Tooltip" then
		fishRefs.Tooltip = obj
	end
end

local function fishBindVis(obj)
	if not obj:IsA("GuiObject") then
		return
	end
	local n = obj.Name
	if n ~= "Charge" and n ~= "Perfect" and n ~= "Reel" and n ~= "Reveal" and n ~= "Tooltip" then
		return
	end
	fishUiConns[#fishUiConns + 1] = obj:GetPropertyChangedSignal("Visible"):Connect(function()
		if not fishOn then
			return
		end
		local v = obj.Visible
		local ln = string.lower(n)
		if ln == "tooltip" then
			fishNoteTip(v)
		end
		if v then
			if ln == "charge" then
				fishPerfect = false
				fishChargeArmed = false
				fishPhase = "holding"
			elseif ln == "perfect" then
				fishPerfect = true
			elseif ln == "reel" then
				fishPhase = "reel"
			elseif ln == "reveal" then
				fishCastAt = 0
			end
		else
			if ln == "reel" and fishPhase == "reel" then
				fishCastAt = 0
				fishPhase = fishRod and "equipped" or "idle"
				fishNextCast = clock() + FISH_BETWEEN
				fishTipFresh = false
				fishTipSeenOff = true
			elseif ln == "reveal" then
				fishNextCast = clock() + FISH_BETWEEN
				fishPhase = fishRod and "equipped" or "idle"
				fishTipFresh = false
				fishTipSeenOff = true
			end
		end
	end)
end

local function fishBindUi(root)
	if not root then
		return
	end
	fishClearUiConns()
	fishUi = root
	for k in pairs(fishRefs) do
		fishRefs[k] = nil
	end
	for _, d in ipairs(root:GetDescendants()) do
		fishRemember(d)
		fishBindVis(d)
	end
	fishSyncTip()
	fishUiConns[#fishUiConns + 1] = root.DescendantAdded:Connect(function(d)
		fishRemember(d)
		task.defer(fishBindVis, d)
	end)
end

local function fishFindUi()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	return pg and pg:FindFirstChild("FishingUI")
end

local function fishWatchChar(ch)
	if not ch then
		return
	end
	for _, c in ipairs(ch:GetChildren()) do
		if fishIsRod(c) then
			fishRod = c
			if fishPhase == "idle" then
				fishPhase = "equipped"
			end
		end
	end
	fishConns[#fishConns + 1] = ch.ChildAdded:Connect(function(c)
		if fishIsRod(c) then
			fishRod = c
			if fishPhase == "idle" then
				fishPhase = "equipped"
			end
		end
	end)
	fishConns[#fishConns + 1] = ch.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") and fishRod == c then
			fishRod = nil
		end
	end)
end

local function fishInpDown()
	if typeof(mouse1press) == "function" then
		pcall(mouse1press)
	elseif typeof(mouse1click) == "function" then
		pcall(mouse1click)
	end
end

local function fishInpUp()
	if typeof(mouse1release) == "function" then
		pcall(mouse1release)
	end
end

local function fishInpClick()
	if typeof(mouse1click) == "function" then
		pcall(mouse1click)
	elseif typeof(mouse1press) == "function" then
		pcall(mouse1press)
		task.wait(0.03)
		fishInpUp()
	end
end

local function fishEnsureInput()
	return typeof(mouse1press) == "function" or typeof(mouse1click) == "function"
end

local function fishShouldRelease()
	local held = fishHold and (clock() - fishHoldT0) or 0
	local pct = fishChargePct()
	if pct and pct < FISH_CHARGE_ARMED then
		fishChargeArmed = true
	end
	if fishVis(fishRefs.Perfect) then
		return true, "perfect"
	end
	if fishPerfect and held >= FISH_HOLD_MIN then
		return true, "perfectSeen"
	end
	if fishChargeArmed and fishVis(fishRefs.Charge) and pct and pct >= FISH_CHARGE_RELEASE and held >= FISH_HOLD_MIN then
		return true, "charge"
	end
	if held >= FISH_CHARGE_APPEAR and not fishVis(fishRefs.Charge) and not fishChargeArmed then
		return true, "noChargeUI"
	end
	if held >= FISH_HOLD_MAX then
		if fishChargeArmed or fishVis(fishRefs.Charge) or fishPerfect then
			return true, "holdMax"
		end
		return true, "noChargeUI"
	end
	return false, nil
end

local function fishCastHold()
	if fishHold or fishBusy or clock() < fishNextCast or not fishReady() then
		return
	end
	fishTipFresh = false
	fishBusy = true
	fishChargeArmed = false
	fishPerfect = false
	fishReleaseWhy = ""
	fishInpDown()

	local waitUis = clock() + 0.35
	while alive and fishOn and not fishHold and clock() < waitUis do
		task.wait(0.02)
	end
	fishHold = true
	fishHoldT0 = clock()
	if fishPhase == "equipped" or fishPhase == "idle" then
		fishPhase = "holding"
	end

	local armedDeadline = clock() + FISH_CHARGE_APPEAR
	while alive and fishOn and fishHold and not fishVis(fishRefs.Charge) and clock() < armedDeadline do
		task.wait(0.03)
	end
	if fishVis(fishRefs.Charge) then
		fishHoldT0 = clock()
		fishChargeArmed = false
	end

	local t0 = clock()
	while alive and fishOn and fishHold do
		local pct = fishChargePct()
		if pct and pct < FISH_CHARGE_ARMED then
			fishChargeArmed = true
		end
		local okRel, why = fishShouldRelease()
		if okRel then
			fishReleaseWhy = tostring(why)
			break
		end
		if clock() - t0 > FISH_HOLD_MAX + 0.5 then
			fishReleaseWhy = "stuck"
			break
		end
		task.wait(0.03)
	end

	fishInpUp()
	task.wait(0.05)
	fishHold = false

	local bad = fishReleaseWhy == "noChargeUI"
		or fishReleaseWhy == "stuck"
		or (not fishChargeArmed and not fishPerfect and not fishVis(fishRefs.Perfect))
	if bad then
		fishCastAt = 0
		fishPhase = fishRod and "equipped" or "idle"
		fishNextCast = clock() + 0.4
		fishBusy = false
		fishWaitReady(true)
		return
	end
	fishCastAt = clock()
	fishPhase = "cast_wait"
	fishBusy = false
end

local function fishReel()
	fishBusy = true
	setFishStatus("fish: reel", COL.accent)
	local t0 = clock()
	local n = 0
	while alive and fishOn and fishVis(fishRefs.Reel) and n < FISH_REEL_BURST do
		fishInpClick()
		n += 1
		task.wait(FISH_REEL_DT)
	end
	while alive and fishOn and fishVis(fishRefs.Reel) do
		fishInpClick()
		n += 1
		if clock() - t0 > FISH_REEL_TIMEOUT then
			break
		end
		task.wait(FISH_REEL_DT)
	end
	fishBusy = false
	fishCastAt = 0
	fishNextCast = clock() + FISH_BETWEEN
	fishTipFresh = false
	fishTipSeenOff = true
	fishWaitReady(false)
end

local function fishWaitReveal()
	if not fishVis(fishRefs.Reveal) then
		return
	end
	local t0 = clock()
	while alive and fishOn and fishVis(fishRefs.Reveal) do
		if clock() - t0 > FISH_REVEAL_WAIT then
			break
		end
		task.wait(0.15)
	end
	fishCastAt = 0
	fishPhase = fishRod and "equipped" or "idle"
	fishNextCast = clock() + FISH_BETWEEN
	fishTipFresh = false
	fishTipSeenOff = true
	fishWaitReady(false)
end

local function fishLoop()
	task.wait(FISH_START_DELAY)
	fishSyncTip()
	if fishRefs.Tooltip and fishVis(fishRefs.Tooltip) then
		task.wait(0.35)
		if alive and fishOn and fishVis(fishRefs.Tooltip) then
			fishTipFresh = true
			fishTipSeenOff = false
		end
	else
		fishWaitReady(false)
	end
	while alive and fishOn do
		local ok, err = pcall(function()
			if not fishUi or not fishUi.Parent then
				local ui = fishFindUi()
				if ui then
					fishBindUi(ui)
				else
					setFishStatus("fish: no FishingUI", COL.warn)
					task.wait(1)
					return
				end
			end
			if not fishEnsureRod() then
				task.wait(1.5)
				return
			end
			if fishVis(fishRefs.Reveal) then
				fishWaitReveal()
				return
			end
			if fishVis(fishRefs.Reel) then
				fishReel()
				task.wait(0.15)
				return
			end
			if fishPhase == "cast_wait" and fishCastAt > 0 then
				local waited = clock() - fishCastAt
				if waited > FISH_BITE_TIMEOUT then
					fishCastAt = 0
					fishPhase = fishRod and "equipped" or "idle"
					fishWaitReady(true)
					return
				end
				setFishStatus(string.format("fish: bite %.1fs", waited), COL.accent)
				task.wait(0.12)
				return
			end
			if fishHold or fishBusy then
				task.wait(0.03)
				return
			end
			if not fishReady() then
				fishWaitReady(fishVis(fishRefs.Tooltip) and not fishTipFresh)
				return
			end
			fishCastHold()
		end)
		if not ok then
			setFishStatus("fish err", COL.warn)
			task.wait(0.5)
		end
	end
	pcall(fishInpUp)
	fishBusy = false
end

local function stopFish()
	fishOn = false
	fishBusy = false
	fishHold = false
	fishStopTp()
	fishClearConns()
	pcall(fishInpUp)
	fishUi = nil
	fishRod = nil
	fishPhase = "idle"
	fishCastAt = 0
	fishTipFresh = false
	fishTipSeenOff = true
	for k in pairs(fishRefs) do
		fishRefs[k] = nil
	end
	paintFishBtn()
	if not hwOn then
		setHwStatus("auto-kill off", COL.textDim)
	end
end

local function startFish()
	if fishOn then
		return
	end
	if not fishEnsureInput() then
		setFishStatus("fish: no mouse1", COL.warn)
		return
	end
	fishOn = true
	fishBusy = false
	fishHold = false
	fishPhase = "idle"
	fishCastAt = 0
	fishNextCast = clock() + FISH_START_DELAY
	fishTipFresh = false
	fishTipSeenOff = true
	fishClearConns()
	paintFishBtn()
	fishStartTp()
	setFishStatus("auto fish…", COL.accent)

	local ui = fishFindUi()
	if ui then
		fishBindUi(ui)
	else
		local pg = LP:FindFirstChildOfClass("PlayerGui")
		if pg then
			fishConns[#fishConns + 1] = pg.ChildAdded:Connect(function(ch)
				if fishOn and ch.Name == "FishingUI" then
					fishBindUi(ch)
				end
			end)
		end
	end
	fishWatchChar(char or LP.Character)
	fishConns[#fishConns + 1] = LP.CharacterAdded:Connect(function(ch)
		task.defer(fishWatchChar, ch)
	end)
	fishConns[#fishConns + 1] = UIS.InputBegan:Connect(function(input, gp)
		if not fishOn or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if gp and not fishBusy then
			return
		end
		if fishBusy then
			if fishPhase ~= "reel" then
				fishHold = true
			end
			return
		end
	end)
	fishConns[#fishConns + 1] = UIS.InputEnded:Connect(function(input)
		if not fishOn or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if not fishHold then
			return
		end
		if fishBusy then
			fishHold = false
			return
		end
		fishHold = false
	end)
	task.spawn(fishLoop)
end

return {
	start = startFish,
	stop = stopFish,
	paint = paintFishBtn,
	setBtn = function(b)
		fishBtn = b
	end,
	isOn = function()
		return fishOn
	end,
	toggle = function()
		if fishOn then
			stopFish()
		else
			startFish()
		end
	end,
}
end)()

-- ========== Halloween Munnezz auto-sell (v51 stack: FetchProfile + SellSelection) ==========
local Munnezz = (function()
	local KEEP = { secret = true, eternal = true, divine = true }
	local SELL = {
		common = true, uncommon = true, rare = true, epic = true,
		legendary = true, mythic = true, cosmic = true,
	}
	local LOOP_WAIT, SELL_WAIT = 0.75, 0.12
	local str_lower, str_gsub, str_match, str_find, str_sub, str_format =
		string.lower, string.gsub, string.match, string.find, string.sub, string.format

	local FetchProfile = netFolder and netFolder:FindFirstChild("RF/ProfileMirror/FetchProfile")
	local SellSelection = netFolder and netFolder:FindFirstChild("RE/PetSatchel/SellSelection")
	pcall(function()
		local pkgs = RS:FindFirstChild("Packages")
		local net = pkgs and pkgs:FindFirstChild("Networking")
		if net then
			if not FetchProfile then
				FetchProfile = net:WaitForChild("RF/ProfileMirror/FetchProfile", 8)
			end
			if not SellSelection then
				SellSelection = net:WaitForChild("RE/PetSatchel/SellSelection", 8)
			end
		end
	end)

	local DataFolder = RS:FindFirstChild("Data") or RS:WaitForChild("Data", 8)
	local AssetsMod = DataFolder and DataFolder:FindFirstChild("Assets")
	local ConfigsFolder = AssetsMod and AssetsMod:FindFirstChild("Configs")
	local HalloweenPetsMod = DataFolder and DataFolder:FindFirstChild("HalloweenPets")

	local munOn = false
	local munBtn, munLbl
	local catalog, selling = {}, {}
	local halloweenMapCache, halloweenSrcCache = nil, nil
	local bpConn

	local function setMunLbl(t, col)
		if munLbl then
			munLbl.Text = t
			munLbl.TextColor3 = col or COL.textDim
		end
	end

	local function paintMunBtn()
		if not munBtn then
			return
		end
		local lab = munOn and "MUNNEZZ ON" or "MUNNEZZ OFF"
		munBtn.Name = lab
		munBtn.Text = lab
		munBtn.TextColor3 = munOn and COL.accent or COL.text
	end

	local function norm(s)
		return str_lower((str_gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")))
	end

	local function readSource(inst)
		if typeof(decompile) ~= "function" or typeof(inst) ~= "Instance" then
			return nil
		end
		local ok, src = pcall(decompile, inst)
		if ok and type(src) == "string" and not str_find(src, "Hello, world", 1, true) then
			return src
		end
		return nil
	end

	local function parseRarity(src)
		local rarity = str_match(src, "Rarity%.Rarities%.([%w_]+)")
			or str_match(src, "%.Rarities%.([%w_]+)")
			or str_match(src, 'Rarity%s*=%s*"([%w_]+)"')
			or str_match(src, "Rarity%s*=%s*'([%w_]+)'")
			or str_match(src, "Rarity%s*=%s*([%w_]+)%s*[,;\n]")
		local eggName = str_match(src, 'DisplayName%s*=%s*"([^"]*Egg[^"]*)"')
		local display = eggName or str_match(src, 'DisplayName%s*=%s*"([^"]+)"')
		if rarity == "Rarities" or rarity == "nil" or rarity == "true" or rarity == "false" then
			rarity = nil
		end
		return rarity, display
	end

	local function absorbSpec(map, key, window)
		if map[key] or type(window) ~= "string" then
			return
		end
		local rarity = str_match(window, 'Rarity%s*=%s*"([^"]+)"')
			or str_match(window, "Rarity%s*=%s*'([^']+)'")
			or str_match(window, "Rarity%s*=%s*([%w_]+)")
		if not rarity or rarity == "Rarities" or rarity == "nil" or rarity == "true" then
			return
		end
		local display = str_match(window, 'DisplayName%s*=%s*"([^"]+)"')
		map[key] = { rarity = rarity, name = display or key }
	end

	local function parseHalloweenSpecs(src, needed)
		local map = {}
		local pos = 1
		while true do
			local s, e, key = str_find(src, '%["([^"]+)"%]', pos)
			if not s then
				break
			end
			absorbSpec(map, key, str_sub(src, e + 1, e + 800))
			pos = e + 1
		end
		pos = 1
		while true do
			local s, e, key = str_find(src, "([%w_]+)%s*=%s*%{", pos)
			if not s then
				break
			end
			absorbSpec(map, key, str_sub(src, e, e + 800))
			pos = e + 1
		end
		for i = 1, #needed do
			local cat = needed[i]
			if not map[cat] then
				local found = str_find(src, cat, 1, true)
				if found then
					absorbSpec(map, cat, str_sub(src, found, found + 900))
				end
			end
		end
		return map
	end

	local function halloweenKeyFromWrapper(src)
		return str_match(src, 'HalloweenPetConfig%)%(%s*"([^"]+)"')
			or str_match(src, "HalloweenPetConfig%)%(%s*'([^']+)'")
	end

	local function fillHalloweenNeeded(map, src, needed)
		if type(src) ~= "string" or type(needed) ~= "table" then
			return
		end
		for i = 1, #needed do
			local cat = needed[i]
			if not map[cat] then
				local found = str_find(src, cat, 1, true)
				if found then
					absorbSpec(map, cat, str_sub(src, found, found + 900))
				end
			end
		end
	end

	local function getHalloweenMap(needed)
		if type(halloweenMapCache) == "table" then
			fillHalloweenNeeded(halloweenMapCache, halloweenSrcCache, needed)
			return halloweenMapCache
		end
		if not HalloweenPetsMod then
			return {}
		end
		local hsrc = readSource(HalloweenPetsMod)
		if not hsrc then
			return {}
		end
		halloweenSrcCache = hsrc
		halloweenMapCache = parseHalloweenSpecs(hsrc, needed)
		return halloweenMapCache
	end

	local function ensureCatalog(categories)
		local missing = {}
		for i = 1, #categories do
			local cat = categories[i]
			if type(catalog[cat]) ~= "table" then
				missing[#missing + 1] = cat
			end
		end
		if #missing == 0 then
			return
		end
		local halloweenMap = getHalloweenMap(missing)
		for i = 1, #missing do
			local cat = missing[i]
			local entry = halloweenMap[cat]
			if type(entry) == "table" then
				catalog[cat] = entry
			else
				local mod = ConfigsFolder and ConfigsFolder:FindFirstChild(cat)
				local src = mod and readSource(mod)
				if src then
					if str_find(src, "HalloweenPetConfig", 1, true) then
						local hk = halloweenKeyFromWrapper(src)
						local resolved = (hk and halloweenMap[hk]) or halloweenMap[cat]
						if type(resolved) == "table" then
							catalog[cat] = resolved
						end
					else
						local rarity, name = parseRarity(src)
						if rarity then
							catalog[cat] = { rarity = rarity, name = name or cat }
						end
					end
				end
			end
			if i % 6 == 0 then
				task.wait()
			end
		end
	end

	local function rarityOf(cat)
		local e = cat and catalog[cat]
		if type(e) ~= "table" then
			return "?", cat or "?"
		end
		return e.rarity or "?", e.name or cat
	end

	local function shouldSell(rarity)
		local key = norm(rarity)
		return rarity ~= "?" and SELL[key] == true and not KEEP[key]
	end

	local function getInventory()
		if not FetchProfile then
			return nil
		end
		for _ = 1, 3 do
			local ok, profile = pcall(FetchProfile.InvokeServer, FetchProfile, LP)
			if ok and type(profile) == "table" and type(profile.EggInventory) == "table" then
				return profile.EggInventory
			end
			task.wait(0.15)
		end
		return nil
	end

	local function fireSell(uid, name, rarity)
		if not uid or selling[uid] or not SellSelection then
			return false
		end
		selling[uid] = true
		local ok = pcall(SellSelection.FireServer, SellSelection, { Eggs = { uid }, Assets = {} })
		if ok then
			setMunLbl(str_format("%s | %s", tostring(name), tostring(rarity)), COL.accent)
		end
		task.delay(2.5, function()
			selling[uid] = nil
		end)
		return ok
	end

	local function sellPass()
		local inv = getInventory()
		if not inv then
			return 0
		end
		local cats, bag, sold, seen = {}, {}, 0, {}
		for uid, egg in pairs(inv) do
			if type(egg) ~= "table" or egg.Placement ~= nil then
				continue
			end
			local cat = egg.AssetCategory
			if cat and not seen[cat] then
				seen[cat] = true
				cats[#cats + 1] = cat
			end
			local inline = egg.Rarity or egg.rarity
			if type(inline) == "table" then
				inline = inline.Name or inline.Value or inline[1]
			end
			if type(inline) ~= "string" or inline == "" then
				inline = nil
			end
			bag[#bag + 1] = { uid = uid, cat = cat, inline = inline }
		end
		ensureCatalog(cats)
		for i = 1, #bag do
			if not munOn or not alive then
				break
			end
			local row = bag[i]
			local rarity, name = rarityOf(row.cat)
			if row.inline then
				rarity = row.inline
			end
			if shouldSell(rarity) then
				if fireSell(row.uid, name, rarity) then
					sold += 1
					task.wait(SELL_WAIT)
				end
			end
		end
		return sold
	end

	local function stopHotbarWatch()
		if bpConn then
			bpConn:Disconnect()
			bpConn = nil
		end
	end

	local function startHotbarWatch()
		stopHotbarWatch()
		local bp = LP:FindFirstChildOfClass("Backpack") or LP:WaitForChild("Backpack", 3)
		if not bp then
			return
		end
		bpConn = bp.ChildAdded:Connect(function(ch)
			if not munOn or not alive or not ch:IsA("Tool") then
				return
			end
			task.defer(function()
				if munOn and alive then
					pcall(sellPass)
				end
			end)
		end)
	end

	local function stopMun()
		munOn = false
		stopHotbarWatch()
		paintMunBtn()
		setMunLbl("Munnezz off", COL.textDim)
	end

	local function startMun()
		if munOn then
			return
		end
		if not FetchProfile or not SellSelection then
			setMunLbl("Remotes missing", COL.warn)
			return
		end
		munOn = true
		paintMunBtn()
		setMunLbl("Waiting…", COL.accent)
		startHotbarWatch()
		task.spawn(function()
			while munOn and alive do
				pcall(sellPass)
				local t = 0
				while munOn and alive and t < LOOP_WAIT do
					task.wait(0.1)
					t += 0.1
				end
			end
			stopHotbarWatch()
		end)
	end

	task.defer(function()
		if alive then
			pcall(getHalloweenMap, {})
		end
	end)

	return {
		start = startMun,
		stop = stopMun,
		paint = paintMunBtn,
		setBtn = function(b)
			munBtn = b
		end,
		setLbl = function(l)
			munLbl = l
		end,
		isOn = function()
			return munOn
		end,
		toggle = function()
			if munOn then
				stopMun()
			else
				startMun()
			end
		end,
	}
end)()

-- ========== Dist anti-AFK (from anti-afk/script.lua, no VU/VIM) ==========
local AntiAfk = (function()
	local PERIODIC_SEC = 150
	local PREEMPT_SEC = 840
	local POKE_GAP = 12
	local BOOT_DELAY = 2.5
	local VK_J = 0x4A

	local on = false
	local btn
	local lastPoke, lastPokeAt, lastActivity, nextPeriodic = 0, 0, clock(), 0
	local idledConn, inputConn

	local function jitter(base)
		return base + (math.random() * 40 - 10)
	end

	local function hasInputApi()
		return typeof(keypress) == "function"
			or typeof(mouse2click) == "function"
			or typeof(mouse1click) == "function"
			or typeof(mouse1press) == "function"
	end

	local function pokeOnce()
		if typeof(keypress) == "function" then
			local ok = pcall(function()
				keypress(VK_J)
				task.wait(0.05)
				if typeof(keyrelease) == "function" then
					keyrelease(VK_J)
				end
			end)
			if ok then
				return "key:J"
			end
		end
		if typeof(mouse2click) == "function" then
			local ok = pcall(mouse2click)
			if ok then
				return "mouse2click"
			end
		end
		if typeof(mouse1click) == "function" then
			local ok = pcall(mouse1click)
			if ok then
				return "mouse1click"
			end
		end
		if typeof(mouse1press) == "function" then
			local ok = pcall(function()
				mouse1press()
				task.wait(0.04)
				if typeof(mouse1release) == "function" then
					mouse1release()
				end
			end)
			if ok then
				return "mouse1press"
			end
		end
		return nil
	end

	local function poke(reason)
		if not alive or not on then
			return
		end
		local now = clock()
		if now - lastPoke < POKE_GAP then
			return
		end
		lastPoke = now
		lastPokeAt = now
		lastActivity = now
		nextPeriodic = now + jitter(PERIODIC_SEC)
		local method = pokeOnce()
		-- TEMP debug (F9): confirm input actually sent — remove later
		print("[Anti-AFK]", reason, method or "FAIL", "J?", method == "key:J")
	end

	local function stop()
		on = false
		if idledConn then
			pcall(function()
				idledConn:Disconnect()
			end)
			idledConn = nil
		end
		if inputConn then
			pcall(function()
				inputConn:Disconnect()
			end)
			inputConn = nil
		end
	end

	local function start()
		if on then
			return true
		end
		if not hasInputApi() then
			print("[Anti-AFK] ABORT — no keypress/mouse API")
			return false
		end
		on = true
		lastPoke, lastPokeAt = 0, 0
		lastActivity = clock()
		nextPeriodic = clock() + jitter(PERIODIC_SEC)
		idledConn = LP.Idled:Connect(function()
			poke("idled")
		end)
		inputConn = UIS.InputBegan:Connect(function(input)
			if not alive or not on then
				return
			end
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Focus then
				return
			end
			lastActivity = clock()
		end)
		task.delay(BOOT_DELAY, function()
			if alive and on then
				poke("boot")
			end
		end)
		return true
	end

	task.spawn(function()
		while alive do
			task.wait(1)
			if on then
				local now = clock()
				if now >= nextPeriodic and now - lastPoke >= POKE_GAP then
					poke("periodic")
				elseif now - lastActivity >= PREEMPT_SEC and now - lastPoke >= POKE_GAP then
					poke("preempt")
				end
			end
		end
	end)

	return {
		isOn = function()
			return on
		end,
		stop = stop,
		start = start,
		toggle = function()
			if on then
				stop()
			else
				start()
			end
		end,
		setBtn = function(b)
			btn = b
		end,
		paint = function()
			if not btn then
				return
			end
			local lab = on and "ANTI-AFK ON" or "ANTI-AFK OFF"
			btn.Name = lab
			btn.Text = lab
			btn.TextColor3 = on and COL.accent or COL.text
		end,
	}
end)()


-- ========== Discord egg board (from rare_egg_spawn_log) ==========
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
if typeof(ENV.__RareEggLogKill) == "function" then
	pcall(ENV.__RareEggLogKill)
end

local DiscordBoard = (function()
	local boardAlive = false
	local on = false
	local btn = nil

local BOT_TOKEN = "MTU2MjQxNzk2ODA0MDkwNjgzMw.Gp1V46.4_m1Cg7O7gty7sHx9I7HFfAY9fC4uZQXCLcs94"
local CHANNEL_ID = "1562406407146307704"
local API = "https://discord.com/api/v10"
local BOARD_TITLE = "Spawn Egg Notifier"
local MSG_BASE = "/channels/" .. CHANNEL_ID .. "/messages"
local JSON_NULL = "__DISCORD_JSON_NULL__"
local EGG_DOT = { Secret = "⚫", Eternal = "🟣", Divine = "🟡" }
local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local DOW_T = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }

local MAX_EGG_LINES = 40
local MAX_LOCAL_SEEN = 180
local MAX_SYNC_QUEUE = 40
local MAX_REQ_PER_MIN = 35
local MIN_WRITE_GAP = 1.2
local ERR_KEEP = 40

local conns, hooked, localSeen = {}, {}, {}
local boardMsgId = nil
local syncBusy = false
local syncQueue = {}
local lastClock = nil
local cachedEggs = {}
local cachedCycle = "DAY"
local cachedRev = 0
local cachedEpoch = 0
local cycleGen = 0
local lastAppliedGen = 0
local rateLimitUntil = 0
local reqWindowStart = 0
local reqWindowCount = 0
local lastDiscordWrite = 0
local errGui, errBox, errLines = nil, nil, {}

local function logErr(_msg)
	-- error GUI disabled for now
end

local function buildErrGui()
	-- disabled: destroy leftover logger if present
	local pg = LP:FindFirstChild("PlayerGui")
	local old = pg and pg:FindFirstChild("RareEggErrUI")
	if old then
		old:Destroy()
	end
	errGui, errBox = nil, nil
end

---------------------------------------------------------------- utils
local function track(c)
	conns[#conns + 1] = c
	return c
end

local function low(s)
	return string.lower(tostring(s or ""))
end

local function stripRich(s)
	s = tostring(s or ""):gsub("<[^>]+>", ""):gsub("%s+", " ")
	return (s:match("^%s*(.-)%s*$") or s)
end

local function classify(s)
	s = low(s)
	if string.find(s, "secret", 1, true) then
		return "Secret"
	end
	if string.find(s, "eternal", 1, true) then
		return "Eternal"
	end
	if string.find(s, "divine", 1, true) then
		return "Divine"
	end
	return nil
end

local function cleanTail(s)
	return (tostring(s or ""):gsub("[%!%.%,%;%:]+$", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseSpawnText(raw)
	local t = stripRich(raw)
	local rarity = classify(t)
	if not rarity then
		return nil
	end
	local tl = low(t)
	if not (string.find(tl, "spawn", 1, true) or string.find(tl, "appeared", 1, true)) then
		return nil
	end
	local egg = t:match("[Ss]ecret%s+([%w%s%'%-]+)")
		or t:match("[Ee]ternal%s+([%w%s%'%-]+)")
		or t:match("[Dd]ivine%s+([%w%s%'%-]+)")
	if egg then
		egg = cleanTail(egg:gsub("%s+[Ss]pawned.*$", ""):gsub("%s+[Hh]as%s+[Ss]pawned.*$", ""):gsub("%s+[Aa]ppeared.*$", ""))
	end
	local area = t:match("[Ii]n%s+the%s+([%w%s%'%-]+)")
		or t:match("[Ii]n%s+([%w%s%'%-]+)")
		or t:match("[Aa]t%s+the%s+([%w%s%'%-]+)")
		or t:match("[Aa]t%s+([%w%s%'%-]+)")
	if area then
		area = cleanTail(area:match("^([%w%s%'%-]+)") or area)
	end
	return {
		rarity = rarity,
		egg = (egg and egg ~= "") and egg or "?",
		area = (area and area ~= "") and area or "?",
	}
end

local function isLeap(y)
	return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

local function dayOfWeek(y, m, d)
	local yy = y
	if m < 3 then
		yy -= 1
	end
	return (yy + math.floor(yy / 4) - math.floor(yy / 100) + math.floor(yy / 400) + DOW_T[m] + d) % 7
end

local function lastSundayDay(y, m)
	local dim = MONTH_DAYS[m]
	if m == 2 and isLeap(y) then
		dim = 29
	end
	for d = dim, 1, -1 do
		if dayOfWeek(y, m, d) == 0 then
			return d
		end
	end
	return 1
end

local function daysSinceEpoch(y, m, d)
	local days = d - 1
	for yy = 1970, y - 1 do
		days += isLeap(yy) and 366 or 365
	end
	for mm = 1, m - 1 do
		days += MONTH_DAYS[mm]
		if mm == 2 and isLeap(y) then
			days += 1
		end
	end
	return days
end

local function italianNowString()
	local utc = os.time()
	local y = tonumber(os.date("!%Y", utc))
	local dstStart = daysSinceEpoch(y, 3, lastSundayDay(y, 3)) * 86400 + 3600
	local dstEnd = daysSinceEpoch(y, 10, lastSundayDay(y, 10)) * 86400 + 3600
	local offset = (utc >= dstStart and utc < dstEnd) and 2 or 1
	local t = os.date("!*t", utc + offset * 3600)
	return string.format(
		"%02d/%02d/%04d %02d:%02d:%02d %s",
		t.day,
		t.month,
		t.year,
		t.hour,
		t.min,
		t.sec,
		offset == 2 and "CEST" or "CET"
	)
end

local function httpRequest(opts)
	local fn = (typeof(syn) == "table" and syn.request)
		or (typeof(request) == "function" and request)
		or (typeof(http_request) == "function" and http_request)
		or (typeof(http) == "table" and http.request)
	if typeof(fn) ~= "function" then
		return nil, "no http"
	end
	local ok, res = pcall(fn, opts)
	if not ok then
		return nil, tostring(res)
	end
	return res
end

local function encodeBody(bodyTbl)
	if not bodyTbl then
		return nil
	end
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(bodyTbl):gsub('"' .. JSON_NULL .. '"', "null")
	end)
	if not ok then
		return nil, tostring(encoded)
	end
	return encoded
end

local function headerRetryAfter(res)
	local h = res and (res.Headers or res.headers)
	if typeof(h) ~= "table" then
		return nil
	end
	return tonumber(h["Retry-After"] or h["retry-after"] or h["RETRY-AFTER"])
end

local function botRequest(method, path, bodyTbl)
	local headers = {
		["Authorization"] = "Bot " .. BOT_TOKEN,
		["Content-Type"] = "application/json",
	}
	for attempt = 1, 6 do
		if not boardAlive then
			return nil, "killed"
		end
		local now = os.clock()
		if now - reqWindowStart >= 60 then
			reqWindowStart = now
			reqWindowCount = 0
		end
		if reqWindowCount >= MAX_REQ_PER_MIN then
			local cool = 60 - (now - reqWindowStart) + 0.2
			if cool > 0 then
				rateLimitUntil = math.max(rateLimitUntil, now + cool)
			end
		end
		local waitFor = rateLimitUntil - os.clock()
		if waitFor > 0 then
			task.wait(math.min(waitFor, 20))
		end
		if method == "POST" or method == "PATCH" then
			local gap = MIN_WRITE_GAP - (os.clock() - lastDiscordWrite)
			if gap > 0 then
				task.wait(gap)
			end
		end
		local body, encErr = encodeBody(bodyTbl)
		if bodyTbl and not body then
			return nil, "json encode: " .. tostring(encErr)
		end
		local res, err = httpRequest({
			Url = API .. path,
			Method = method,
			Headers = headers,
			Body = body,
		})
		reqWindowCount += 1
		if not res then
			task.wait(0.4 * attempt)
			if attempt == 6 then
				return nil, err or "request fail/timeout"
			end
		else
			local code = tonumber(res.StatusCode) or tonumber(tostring(res.StatusCode)) or 0
			local raw = tostring(res.Body or res.body or "")
			local data = nil
			if raw ~= "" then
				pcall(function()
					data = HttpService:JSONDecode(raw)
				end)
			end
			if code == 0 then
				task.wait(0.5 * attempt)
			elseif code == 429 then
				local retry = (data and tonumber(data.retry_after)) or headerRetryAfter(res) or (0.5 * attempt)
				if retry < 0.3 then
					retry = 0.3
				elseif retry > 30 then
					retry = 30
				end
				rateLimitUntil = os.clock() + retry
				logErr("Discord 429 — wait " .. string.format("%.1fs", retry))
				task.wait(retry)
			elseif code >= 500 then
				task.wait(0.6 * attempt)
			elseif code < 200 or code >= 300 then
				local msg = (data and data.message) or raw
				if typeof(msg) == "string" and #msg > 120 then
					msg = string.sub(msg, 1, 120) .. "…"
				end
				return nil, tostring(code) .. " " .. tostring(msg), code
			else
				if method == "POST" or method == "PATCH" then
					lastDiscordWrite = os.clock()
				end
				return data or true, nil, code
			end
		end
	end
	return nil, "http retries exhausted"
end

---------------------------------------------------------------- board state
local function emptyState()
	return { eggs = {}, cycle = "DAY", rev = 0, epoch = 0 }
end

local function eggKey(e)
	return low(e.rarity) .. "|" .. low(e.egg) .. "|" .. low(e.area)
end

local function copyEgg(e)
	return {
		rarity = e.rarity,
		egg = e.egg,
		area = e.area,
		uid = tostring(e.uid or "?"),
		time = e.time or "?",
		epoch = tonumber(e.epoch) or 0,
	}
end

local function eggIsCurrent(e, epoch)
	return (tonumber(e and e.epoch) or 0) >= (tonumber(epoch) or 0)
end

local function isNightEmpty(s)
	return s and s.cycle == "NIGHT" and #(s.eggs or {}) == 0
end

local function hasEgg(list, e)
	local k = eggKey(e)
	local uid = e.uid
	local checkUid = uid and uid ~= "?"
	for _, x in ipairs(list) do
		if eggKey(x) == k then
			return true
		end
		if checkUid and x.uid and x.uid ~= "?" and x.uid == uid then
			return true
		end
	end
	return false
end

local function mergeEggList(dst, src, minEpoch)
	if typeof(dst) ~= "table" then
		dst = {}
	end
	minEpoch = tonumber(minEpoch)
	local seenK, seenU = {}, {}
	for _, e in ipairs(dst) do
		seenK[eggKey(e)] = true
		if e.uid and e.uid ~= "?" then
			seenU[e.uid] = true
		end
	end
	if typeof(src) == "table" then
		for _, e in ipairs(src) do
			if typeof(e) == "table" and e.rarity and e.egg and e.area then
				if minEpoch == nil or eggIsCurrent(e, minEpoch) then
					local k = eggKey(e)
					local uid = tostring(e.uid or "?")
					if not seenK[k] and not (uid ~= "?" and seenU[uid]) then
						dst[#dst + 1] = copyEgg(e)
						seenK[k] = true
						if uid ~= "?" then
							seenU[uid] = true
						end
					end
				end
			end
		end
	end
	return dst
end

-- Copy + optional cap (maxn=false → copy only, no trim)
local function trimEggList(list, maxn)
	local out = mergeEggList({}, list)
	if maxn == false then
		return out
	end
	maxn = maxn or MAX_EGG_LINES
	if #out <= maxn then
		return out
	end
	local trimmed = {}
	for i = #out - maxn + 1, #out do
		trimmed[#trimmed + 1] = out[i]
	end
	return trimmed
end

local function pruneLocalSeen()
	local n = 0
	for _ in pairs(localSeen) do
		n += 1
	end
	if n <= MAX_LOCAL_SEEN then
		return
	end
	local drop = n - math.floor(MAX_LOCAL_SEEN * 0.6)
	for k in pairs(localSeen) do
		if drop <= 0 then
			break
		end
		localSeen[k] = nil
		drop -= 1
	end
end

local function rememberState(state)
	cachedEggs = trimEggList(state.eggs, MAX_EGG_LINES)
	cachedCycle = state.cycle or cachedCycle
	cachedRev = tonumber(state.rev) or cachedRev
	cachedEpoch = math.max(cachedEpoch or 0, tonumber(state.epoch) or 0)
end

local function wipeLocalForNight(ep, rev)
	cachedEggs = {}
	cachedCycle = "NIGHT"
	cachedEpoch = math.max(cachedEpoch or 0, tonumber(ep) or 0)
	if rev ~= nil then
		cachedRev = tonumber(rev) or cachedRev
	end
	table.clear(localSeen)
end

local function extractContentFromMessage(msg)
	if typeof(msg) ~= "table" then
		return ""
	end
	if typeof(msg.content) == "string" and msg.content ~= "" then
		return msg.content
	end
	local bits = {}
	local function walk(comps)
		if typeof(comps) ~= "table" then
			return
		end
		for _, c in ipairs(comps) do
			if typeof(c) == "table" then
				if c.type == 10 and typeof(c.content) == "string" then
					bits[#bits + 1] = c.content
				end
				if typeof(c.components) == "table" then
					walk(c.components)
				end
			end
		end
	end
	walk(msg.components)
	return table.concat(bits, "\n")
end

local function isBoardContent(content)
	return typeof(content) == "string" and string.find(content, BOARD_TITLE, 1, true) ~= nil
end

local function parseStateFromContent(content)
	if not isBoardContent(content) then
		return nil
	end
	local state = emptyState()
	local cycle = content:match("·%*%*(%w+)%*%*") or content:match("· %*%*(%w+)%*%*")
	if cycle == "DAY" or cycle == "NIGHT" then
		state.cycle = cycle
	end
	local rev = tonumber(content:match("`r(%d+)`")) or 0
	local epoch = tonumber(content:match("`e(%d+)`")) or 0
	state.rev = rev
	state.epoch = epoch
	for line in string.gmatch(content, "[^\r\n]+") do
		if not string.find(line, "waiting for spawns", 1, true) then
			local rarity, egg, area, time = line:match("%*%*(.-)%*%* — (.-) in (.-) %(`([^`]+)`%)")
			if rarity and egg and area and classify(rarity) then
				local rr, ee, aa = cleanTail(rarity), cleanTail(egg), cleanTail(area)
				if ee ~= "" and ee ~= "?" and aa ~= "" then
					state.eggs[#state.eggs + 1] = {
						rarity = rr,
						egg = ee,
						area = aa,
						time = time or "?",
						uid = "?",
						epoch = epoch,
					}
				end
			end
		end
	end
	state.eggs = trimEggList(state.eggs, false)
	return state
end

local function parseMsg(msg)
	return parseStateFromContent(extractContentFromMessage(msg))
end

local function buildPayload(state, pingEveryone)
	local eggLines = {}
	local seenEgg = {}
	local eggs = state.eggs or {}
	local startIdx = (#eggs > MAX_EGG_LINES) and (#eggs - MAX_EGG_LINES + 1) or 1
	for i = startIdx, #eggs do
		local e = eggs[i]
		if typeof(e) == "table" then
			local k = eggKey(e)
			if not seenEgg[k] then
				seenEgg[k] = true
				eggLines[#eggLines + 1] = string.format(
					"%s **%s** — %s in %s (`%s`)",
					EGG_DOT[e.rarity] or "⚪",
					tostring(e.rarity or "?"),
					tostring(e.egg or "?"),
					tostring(e.area or "?"),
					tostring(e.time or "?")
				)
			end
		end
	end
	if #eggLines == 0 then
		eggLines[1] = "_waiting for spawns…_"
	end

	local comps = {}
	if pingEveryone then
		comps[#comps + 1] = { type = 10, content = "@everyone" }
	end
	comps[#comps + 1] = {
		type = 17,
		accent_color = JSON_NULL,
		components = {
			{
				type = 10,
				content = string.format(
					"# %s · **%s** · `r%d` · `e%d`",
					BOARD_TITLE,
					(state.cycle == "NIGHT") and "NIGHT" or "DAY",
					tonumber(state.rev) or 0,
					tonumber(state.epoch) or 0
				),
			},
			{ type = 14, divider = true, spacing = 1 },
			{ type = 10, content = "## Eggs\n" .. table.concat(eggLines, "\n") },
		},
	}
	return {
		flags = 32768,
		allowed_mentions = pingEveryone and { parse = { "everyone" } } or { parse = {} },
		components = comps,
	}
end

-- NIGHT-empty wins only if its rev >= any board that still has eggs
local function collapseBoardMessages(matches)
	if #matches == 0 then
		return nil
	end
	local pool = emptyState()
	local maxRev, maxEpoch = 0, 0
	local nightClearRev, nightClearEpoch = -1, -1
	local eggsRev = -1
	local keep = matches[#matches]
	for _, msg in ipairs(matches) do
		local parsed = parseMsg(msg)
		if parsed then
			local r = tonumber(parsed.rev) or 0
			local ep = tonumber(parsed.epoch) or 0
			if r > maxRev then
				maxRev = r
			end
			if ep > maxEpoch then
				maxEpoch = ep
			end
			if isNightEmpty(parsed) then
				if r > nightClearRev then
					nightClearRev = r
				end
				if ep > nightClearEpoch then
					nightClearEpoch = ep
				end
			end
			if #(parsed.eggs) > 0 and r > eggsRev then
				eggsRev = r
			end
			mergeEggList(pool.eggs, parsed.eggs, ep)
			if parsed.cycle == "DAY" then
				pool.cycle = "DAY"
			elseif pool.cycle ~= "DAY" then
				pool.cycle = parsed.cycle or pool.cycle
			end
		end
	end
	if nightClearRev >= 0 and nightClearRev >= eggsRev then
		pool.eggs = {}
		pool.cycle = "NIGHT"
		pool.epoch = math.max(maxEpoch, nightClearEpoch, 1)
	elseif #(pool.eggs) > 0 then
		pool.cycle = "DAY"
		pool.epoch = maxEpoch
		pool.eggs = trimEggList(mergeEggList({}, pool.eggs, maxEpoch), MAX_EGG_LINES)
	else
		pool.epoch = maxEpoch
	end
	pool.rev = maxRev + 1
	local keepId = tostring(keep.id)
	for i = 1, #matches do
		if tostring(matches[i].id) ~= keepId then
			pcall(botRequest, "DELETE", MSG_BASE .. "/" .. tostring(matches[i].id))
		end
	end
	local patchOk = false
	pcall(function()
		local res, err = botRequest("PATCH", MSG_BASE .. "/" .. keepId .. "?with_components=true", buildPayload(pool, false))
		patchOk = res ~= nil and err == nil
	end)
	if patchOk then
		rememberState(pool)
	end
	return keep, pool
end

local function findBoardMessage()
	local data, err = botRequest("GET", MSG_BASE .. "?limit=50")
	if not data then
		return nil, nil, err
	end
	if typeof(data) ~= "table" then
		return nil, nil, "bad messages"
	end
	local matches = {}
	for _, msg in ipairs(data) do
		if isBoardContent(extractContentFromMessage(msg)) then
			matches[#matches + 1] = msg
		end
	end
	if #matches == 0 then
		return nil, nil, nil
	end
	if #matches == 1 then
		return matches[1], parseMsg(matches[1]), nil
	end
	local keep, pooled = collapseBoardMessages(matches)
	return keep, pooled, nil
end

local function collectAdds(mut)
	local toAdd = {}
	if mut.addEgg then
		toAdd[#toAdd + 1] = mut.addEgg
	end
	if typeof(mut.addEggs) == "table" then
		for _, e in ipairs(mut.addEggs) do
			toAdd[#toAdd + 1] = e
		end
	end
	return toAdd
end

local function unseeAdds(mut)
	for _, e in ipairs(collectAdds(mut or {})) do
		if typeof(e) == "table" then
			local uid = tostring(e.uid or "?")
			if uid ~= "?" then
				localSeen[uid] = nil
			end
			localSeen[eggKey(e)] = nil
		end
	end
end

local function applyMut(state, mut)
	mut = mut or {}
	state.eggs = state.eggs or {}
	local ping = false
	local adds = collectAdds(mut)
	local gen = tonumber(mut.gen)

	if not mut.clearEggs and #adds == 0 and gen ~= nil and gen < lastAppliedGen then
		return state, false
	end

	state.epoch = tonumber(state.epoch) or cachedEpoch or 0

	if mut.clearEggs then
		if not (gen ~= nil and gen < lastAppliedGen) then
			local boardEp = tonumber(state.epoch) or 0
			local nextEpoch = (isNightEmpty(state) and boardEp > 0) and boardEp
				or (math.max(boardEp, cachedEpoch or 0) + 1)
			state.eggs = {}
			state.cycle = "NIGHT"
			state.epoch = nextEpoch
			cachedEggs = {}
			cachedCycle = "NIGHT"
			cachedEpoch = nextEpoch
			table.clear(localSeen)
		end
	end

	if mut.cycle == "DAY" or mut.cycle == "NIGHT" then
		if mut.clearEggs and mut.cycle == "DAY" then
			state.cycle = "NIGHT"
		else
			state.cycle = mut.cycle
		end
	elseif mut.clearEggs then
		state.cycle = "NIGHT"
	end

	local ep = tonumber(state.epoch) or 0
	for _, e in ipairs(adds) do
		if typeof(e) == "table" and e.rarity and e.egg and e.egg ~= "?" and e.area then
			if eggIsCurrent(e, ep) then
				local before = #state.eggs
				mergeEggList(state.eggs, {
					{
						rarity = e.rarity,
						egg = e.egg,
						area = e.area,
						uid = e.uid or "?",
						time = e.time or italianNowString(),
						epoch = ep,
					},
				}, ep)
				if #state.eggs > before then
					ping = true
				end
				state.cycle = "DAY"
			end
		end
	end

	state.eggs = trimEggList(state.eggs, MAX_EGG_LINES)
	if gen ~= nil and gen >= lastAppliedGen then
		lastAppliedGen = gen
	end
	return state, ping
end

local function loadFreshState(mut)
	mut = mut or {}
	local msg, pooled, err = nil, nil, nil
	if boardMsgId then
		local got = botRequest("GET", MSG_BASE .. "/" .. boardMsgId)
		if got and typeof(got) == "table" and isBoardContent(extractContentFromMessage(got)) then
			msg = got
			pooled = parseMsg(got)
		else
			boardMsgId = nil
		end
	end
	if not msg then
		msg, pooled, err = findBoardMessage()
		if err and not msg then
			return nil, nil, 0, err
		end
	end

	local state = emptyState()
	if pooled then
		state.cycle = pooled.cycle or "DAY"
		state.eggs = trimEggList(pooled.eggs, false)
		state.rev = pooled.rev or 0
		state.epoch = pooled.epoch or 0
	elseif msg then
		local parsed = parseMsg(msg)
		if parsed then
			state = parsed
		end
	end
	if msg then
		boardMsgId = tostring(msg.id)
	end

	local boardRev = tonumber(state.rev) or 0
	local boardEp = tonumber(state.epoch) or 0
	if boardEp > (cachedEpoch or 0) then
		cachedEpoch = boardEp
	end

	if isNightEmpty(state) then
		wipeLocalForNight(boardEp, boardRev)
	elseif not mut.clearEggs and state.cycle == "DAY" then
		if #(state.eggs) == 0 and (boardRev > (cachedRev or 0) or boardEp > (cachedEpoch or 0)) then
			cachedEggs = {}
			cachedRev = boardRev
			cachedEpoch = math.max(cachedEpoch, boardEp)
			table.clear(localSeen)
		else
			state.eggs = trimEggList(mergeEggList(state.eggs, cachedEggs, boardEp), MAX_EGG_LINES)
		end
	end

	return state, msg, state.rev or 0, nil
end

local function patchBoard(state, ping)
	if not boardMsgId then
		return false, "no board id"
	end
	local _, err = botRequest(
		"PATCH",
		MSG_BASE .. "/" .. boardMsgId .. "?with_components=true",
		buildPayload(state, ping == true)
	)
	if err then
		if string.find(err, "10008", 1, true) or string.find(err, "404", 1, true) then
			boardMsgId = nil
		end
		return false, err
	end
	rememberState(state)
	return true
end

local function createBoard(state, ping)
	local created, err = botRequest(
		"POST",
		MSG_BASE .. "?with_components=true",
		buildPayload(state, ping == true)
	)
	if not created then
		return false, err
	end
	if typeof(created) == "table" and created.id then
		boardMsgId = tostring(created.id)
	end
	task.wait(0.35)
	local keep, pooled = findBoardMessage()
	if keep then
		boardMsgId = tostring(keep.id)
		if pooled then
			local pep = tonumber(pooled.epoch) or 0
			if isNightEmpty(pooled) then
				cachedEggs = {}
				cachedEpoch = math.max(cachedEpoch, pep)
			else
				local ep = math.max(pep, tonumber(state.epoch) or 0)
				pooled.eggs = mergeEggList(pooled.eggs, state.eggs, ep)
				pooled.epoch = ep
				if state.cycle == "DAY" then
					pooled.cycle = "DAY"
				end
			end
			pooled.rev = math.max(tonumber(pooled.rev) or 0, tonumber(state.rev) or 0)
			state = pooled
		end
		state.rev = tonumber(state.rev) or 0
		state.epoch = tonumber(state.epoch) or cachedEpoch or 0
		local ok, err2 = patchBoard(state, false)
		if not ok then
			return false, err2
		end
		return true
	end
	rememberState(state)
	return true
end

local function syncOnce(mut)
	mut = mut or {}
	local expectedAdd = collectAdds(mut)
	local isNoopCycle = (#expectedAdd == 0 and not mut.clearEggs and (mut.cycle == "DAY" or mut.cycle == "NIGHT"))

	for attempt = 1, 6 do
		local state, msg, baseRev, err = loadFreshState(mut)
		if not state then
			return false, err or "load fail"
		end

		if isNoopCycle and state.cycle == mut.cycle then
			cachedCycle = state.cycle
			cachedRev = tonumber(state.rev) or cachedRev
			cachedEpoch = math.max(cachedEpoch, tonumber(state.epoch) or 0)
			if mut.gen and mut.gen >= lastAppliedGen then
				lastAppliedGen = mut.gen
			end
			return true
		end

		local beforeCycle = state.cycle
		local beforeEp = tonumber(state.epoch) or 0
		local ping
		state, ping = applyMut(state, mut)
		if not mut.clearEggs and #expectedAdd > 0 and not ping and state.cycle == beforeCycle and (tonumber(state.epoch) or 0) == beforeEp then
			unseeAdds(mut)
			return true
		end
		state.rev = (tonumber(baseRev) or 0) + 1
		state.eggs = trimEggList(state.eggs, MAX_EGG_LINES)
		local ep = tonumber(state.epoch) or cachedEpoch or 0

		local conflict = false
		local latestBoardEggs = nil
		if msg and boardMsgId then
			local again = botRequest("GET", MSG_BASE .. "/" .. boardMsgId)
			if again and typeof(again) == "table" then
				local cur = parseMsg(again)
				if cur and (tonumber(cur.rev) or 0) ~= (tonumber(baseRev) or 0) then
					conflict = true
					local cep = tonumber(cur.epoch) or 0
					if isNightEmpty(cur) then
						cachedEggs = {}
						cachedCycle = "NIGHT"
						cachedEpoch = math.max(cachedEpoch, cep)
					else
						cachedEpoch = math.max(cachedEpoch, cep)
						cachedEggs = mergeEggList(trimEggList(cur.eggs, false), cachedEggs, cachedEpoch)
						cachedEggs = mergeEggList(cachedEggs, expectedAdd, cachedEpoch)
						cachedCycle = cur.cycle or cachedCycle
					end
					cachedRev = cur.rev or cachedRev
				elseif cur then
					latestBoardEggs = cur.eggs or {}
					if not isNightEmpty(cur) then
						local cep = tonumber(cur.epoch) or ep
						state.epoch = math.max(ep, cep)
						state.eggs = mergeEggList(state.eggs, cur.eggs, state.epoch)
					end
				end
			end
		end
		-- @everyone only if first writer: egg still absent on latest board re-read
		if ping and #expectedAdd > 0 and latestBoardEggs ~= nil then
			local firstWriter = false
			local pep = tonumber(state.epoch) or ep
			for _, e in ipairs(expectedAdd) do
				if typeof(e) == "table" and e.egg and e.egg ~= "?" and eggIsCurrent(e, pep) and not hasEgg(latestBoardEggs, e) then
					firstWriter = true
					break
				end
			end
			ping = firstWriter
		end
		if conflict then
			task.wait(0.2 + 0.15 * attempt)
		else
			local ok
			if boardMsgId then
				ok = patchBoard(state, ping)
			else
				ok = createBoard(state, ping)
			end
			if not ok then
				if #expectedAdd > 0 then
					cachedEggs = mergeEggList(cachedEggs, expectedAdd, cachedEpoch)
				end
				task.wait(0.25 * attempt)
			else
				task.wait(0.2)
				local vState = loadFreshState({ clearEggs = false })
				if not vState then
					if #expectedAdd > 0 then
						cachedEggs = mergeEggList(cachedEggs, expectedAdd, cachedEpoch)
					end
					task.wait(0.35 * attempt)
				elseif mut.clearEggs then
					if isNightEmpty(vState) or vState.cycle == "DAY" then
						if vState.cycle == "NIGHT" then
							cachedEggs = {}
							cachedCycle = "NIGHT"
							cachedEpoch = math.max(cachedEpoch, tonumber(vState.epoch) or 0)
						else
							rememberState(vState)
						end
						return true
					end
					task.wait(0.25 * attempt)
				else
					local vEp = tonumber(vState.epoch) or cachedEpoch or 0
					local missing = false
					for _, e in ipairs(expectedAdd) do
						if typeof(e) == "table" and e.egg and e.egg ~= "?" and eggIsCurrent(e, vEp) and not hasEgg(vState.eggs, e) then
							missing = true
							break
						end
					end
					if not missing and vState.cycle == "DAY" then
						local need = mergeEggList(trimEggList(vState.eggs, false), expectedAdd, vEp)
						need = mergeEggList(need, cachedEggs, vEp)
						if #need > #vState.eggs then
							cachedEggs = need
							missing = true
						else
							rememberState(vState)
							return true
						end
					elseif not missing then
						rememberState(vState)
						return true
					end
					if missing then
						cachedEggs = mergeEggList(trimEggList(vState.eggs, false), expectedAdd, vEp)
					end
					task.wait(0.25 * attempt)
				end
			end
		end
	end
	return false, "sync retries exhausted"
end

local function takeGen(m, n)
	if n.gen and (not m.gen or n.gen > m.gen) then
		m.gen = n.gen
	end
end

local function coalesceMut(m)
	while #syncQueue > 0 do
		local n = syncQueue[1]
		if typeof(n) ~= "table" then
			table.remove(syncQueue, 1)
		elseif m.clearEggs or n.clearEggs then
			if n.addEgg or n.addEggs then
				break
			end
			if m.clearEggs and n.cycle == "DAY" and not n.clearEggs then
				break
			end
			if n.clearEggs and not m.clearEggs then
				break
			end
			m.clearEggs = true
			m.addEgg = nil
			m.addEggs = nil
			m.cycle = "NIGHT"
			takeGen(m, n)
			table.remove(syncQueue, 1)
		elseif n.addEgg or n.addEggs then
			m.addEggs = m.addEggs or {}
			if m.addEgg then
				m.addEggs[#m.addEggs + 1] = m.addEgg
				m.addEgg = nil
			end
			if n.addEgg then
				m.addEggs[#m.addEggs + 1] = n.addEgg
			end
			if typeof(n.addEggs) == "table" then
				for _, e in ipairs(n.addEggs) do
					m.addEggs[#m.addEggs + 1] = e
				end
			end
			if n.cycle then
				m.cycle = n.cycle
			end
			takeGen(m, n)
			table.remove(syncQueue, 1)
		else
			if n.cycle then
				m.cycle = n.cycle
			end
			takeGen(m, n)
			table.remove(syncQueue, 1)
		end
	end
	return m
end

local function pumpSync()
	if syncBusy or not boardAlive or #syncQueue == 0 then
		return
	end
	syncBusy = true
	task.spawn(function()
		local okWorker, workerErr = pcall(function()
			while boardAlive and #syncQueue > 0 do
				local m = table.remove(syncQueue, 1)
				if typeof(m) ~= "table" then
					m = {}
				end
				m = coalesceMut(m)
				local ok, err = false, nil
				for attempt = 1, 4 do
					if not boardAlive then
						break
					end
					local sOk, a, b = pcall(syncOnce, m)
					if not sOk then
						err = tostring(a)
						logErr("sync crash: " .. err)
						task.wait(0.6 * attempt)
					else
						ok, err = a, b
						if ok then
							break
						end
						task.wait(0.6 * attempt)
					end
				end
				if not ok then
					logErr("Discord sync: " .. tostring(err))
					unseeAdds(m)
					local adds = collectAdds(m)
					if #adds > 0 then
						cachedEggs = mergeEggList(cachedEggs, adds, cachedEpoch)
					end
				end
				task.wait(0.4)
			end
		end)
		if not okWorker then
			logErr("sync worker: " .. tostring(workerErr))
		end
		syncBusy = false
		if boardAlive and #syncQueue > 0 then
			pumpSync()
		end
	end)
end

local function isClearMut(m)
	return typeof(m) == "table" and m.clearEggs == true
end

local function dropQueueSlot(preferNonClear)
	-- Drop cycle-only no-ops first
	for i = 1, #syncQueue do
		local q = syncQueue[i]
		if typeof(q) == "table" and not q.clearEggs and not q.addEgg and not q.addEggs then
			table.remove(syncQueue, i)
			return true
		end
	end
	if preferNonClear then
		for i = 1, #syncQueue do
			if not isClearMut(syncQueue[i]) then
				table.remove(syncQueue, i)
				return true
			end
		end
		return false -- only clearEggs remain — never drop them
	end
	return false
end

local function enqueueSync(mut)
	if typeof(mut) ~= "table" then
		return
	end
	while #syncQueue >= MAX_SYNC_QUEUE do
		if not dropQueueSlot(true) then
			-- Queue saturated with clearEggs only
			if isClearMut(mut) then
				break -- still enqueue wipe (priority); coalesce will merge
			end
			return -- refuse non-wipe mut rather than drop a wipe
		end
	end
	if isClearMut(mut) then
		-- Absolute priority: wipe runs before pending adds/cycles
		table.insert(syncQueue, 1, mut)
	else
		syncQueue[#syncQueue + 1] = mut
	end
	pumpSync()
end

---------------------------------------------------------------- spawn detect
local function field(rec, keys)
	for i = 1, #keys do
		local v = rec[keys[i]]
		if v ~= nil and tostring(v) ~= "" then
			return tostring(v)
		end
	end
end

local function emit(info)
	if typeof(info) ~= "table" or not info.rarity then
		return
	end
	local egg = tostring(info.egg or "")
	local area = tostring(info.area or "")
	if egg == "" or egg == "?" or area == "" then
		return
	end
	local uid = tostring(info.uid or "?")
	local key = eggKey({ rarity = info.rarity, egg = egg, area = area })
	if uid ~= "?" then
		if localSeen[uid] then
			return
		end
		localSeen[uid] = true
	else
		if localSeen[key] then
			return
		end
		localSeen[key] = true
	end
	pruneLocalSeen()
	enqueueSync({
		addEgg = {
			rarity = info.rarity,
			egg = egg,
			area = area,
			uid = uid,
			time = italianNowString(),
			epoch = cachedEpoch,
		},
		cycle = "DAY",
		gen = cycleGen,
	})
end

local function fromRecord(rec)
	if typeof(rec) ~= "table" then
		return
	end
	local msg = field(rec, { "Message", "Text", "Msg", "Description" }) or ""
	local parsed = parseSpawnText(msg)
	local rarity = classify(field(rec, { "RarityId", "Rarity", "RarityName" }) or "")
		or (parsed and parsed.rarity)
		or classify(msg)
	if not rarity then
		return
	end
	local egg = (parsed and parsed.egg ~= "?" and parsed.egg)
		or stripRich(field(rec, { "EggName", "Name", "DisplayName", "AssetCategory", "PetName" }) or "")
	if egg == "" then
		egg = "?"
	end
	local area = (parsed and parsed.area ~= "?" and parsed.area)
		or field(rec, { "AreaId", "Area", "AreaName", "Zone", "WorldArea", "Location" })
		or "?"
	emit({
		rarity = rarity,
		egg = egg,
		area = area,
		uid = tostring(rec.EggUid or rec.Uid or rec.Id or "?"),
	})
end

local function fromText(text)
	local p = parseSpawnText(text)
	if p then
		emit({ rarity = p.rarity, egg = p.egg, area = p.area, uid = "?" })
	end
end

local function onRarities(p)
	if typeof(p) ~= "table" then
		return
	end
	local rares = p.RareSpawns
	if typeof(rares) == "table" then
		for _, rec in pairs(rares) do
			fromRecord(rec)
		end
		return
	end
	if p.Message or p.RarityId or p.EggUid then
		fromRecord(p)
	end
end

local function hookRE(re)
	if not boardAlive or hooked[re] or not re:IsA("RemoteEvent") then
		return
	end
	local okPath, full = pcall(function()
		return re:GetFullName()
	end)
	local path = low(okPath and full or re.Name)
	if string.find(path, "trail", 1, true) or string.find(path, "shifted", 1, true) or string.find(path, "carry", 1, true) then
		return
	end
	local name = low(re.Name)
	local isRarity = name == "fieldeggraritiesshown" or string.find(name, "rarit", 1, true)
	local isAnnounce = isRarity
		or name == "post"
		or name == "raise"
		or string.find(path, "chatfeed", 1, true)
		or string.find(path, "alert", 1, true)
		or string.find(path, "announce", 1, true)
		or string.find(path, "toast", 1, true)
		or string.find(path, "banner", 1, true)
	if not isAnnounce then
		return
	end
	hooked[re] = true
	track(re.OnClientEvent:Connect(function(...)
		if not boardAlive then
			return
		end
		local args = { ... }
		pcall(function()
			local a1 = args[1]
			if isRarity then
				onRarities(a1)
				return
			end
			for i = 1, #args do
				local a = args[i]
				if typeof(a) == "string" and classify(a) and string.find(low(a), "spawn", 1, true) then
					fromText(a)
					return
				end
				if typeof(a) == "table" then
					local t = a.Text or a.Message or a.Msg
					if typeof(t) == "string" and classify(t) then
						if a.EggUid or a.RareSpawns or a.AreaId then
							fromRecord(a)
						else
							fromText(t)
						end
						return
					end
				end
			end
		end)
	end))
end

local function hookRoot(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("RemoteEvent") then
			pcall(hookRE, d)
		end
	end
	track(root.DescendantAdded:Connect(function(d)
		if d:IsA("RemoteEvent") then
			task.defer(hookRE, d)
		end
	end))
end

local function onCycleFlip(toNight)
	cycleGen += 1
	local gen = cycleGen
	if toNight then
		table.clear(localSeen)
		cachedEggs = {}
		cachedCycle = "NIGHT"
		enqueueSync({ clearEggs = true, cycle = "NIGHT", gen = gen })
	else
		enqueueSync({ cycle = "DAY", gen = gen })
	end
end

local function hookCycle()
	-- Prefer IsNight when the game exposes it; otherwise ClockTime only (never both)
	local useAttr = false
	pcall(function()
		local lastAttr = Workspace:GetAttribute("IsNight")
		if lastAttr == nil then
			return
		end
		useAttr = true
		track(Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
			if not boardAlive then
				return
			end
			local v = Workspace:GetAttribute("IsNight")
			if v == lastAttr then
				return
			end
			lastAttr = v
			onCycleFlip(v == true)
		end))
	end)
	if useAttr then
		return
	end
	pcall(function()
		lastClock = Lighting.ClockTime
		track(Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
			if not boardAlive then
				return
			end
			local c = Lighting.ClockTime
			local prev = lastClock
			lastClock = c
			if prev == nil then
				return
			end
			if prev > 6 and c <= 6 then
				onCycleFlip(true)
				return
			end
			if prev <= 6 and c > 6 then
				onCycleFlip(false)
				return
			end
			if prev < 18 and c >= 18 then
				onCycleFlip(true)
				return
			end
			if prev >= 18 and c < 18 and c > 6 then
				onCycleFlip(false)
			end
		end))
	end)
end

local function resetRuntime()
	boardMsgId = nil
	syncBusy = false
	table.clear(syncQueue)
	table.clear(hooked)
	table.clear(localSeen)
	table.clear(cachedEggs)
	table.clear(conns)
	lastClock = nil
	cachedCycle = "DAY"
	cachedRev = 0
	cachedEpoch = 0
	cycleGen = 0
	lastAppliedGen = 0
	rateLimitUntil = 0
	reqWindowStart = 0
	reqWindowCount = 0
	lastDiscordWrite = 0
	errLines = {}
	errBox = nil
end

local function stop()
	boardAlive = false
	on = false
	for i = 1, #conns do
		pcall(function()
			conns[i]:Disconnect()
		end)
	end
	table.clear(conns)
	table.clear(hooked)
	table.clear(localSeen)
	table.clear(syncQueue)
	table.clear(cachedEggs)
	if errGui then
		pcall(function()
			errGui:Destroy()
		end)
		errGui = nil
	end
	errBox = nil
	if btn then
		btn.Text = "DISCORD OFF"
		btn.Name = "DISCORD OFF"
		btn.TextColor3 = COL.text
	end
end

local function start()
	if on then
		return true
	end
	stop()
	resetRuntime()
	boardAlive = true
	on = true
	pcall(buildErrGui) -- no-op / cleanup only (logger UI off)
	pcall(hookRoot, RS)
	pcall(function()
		local net = RS:FindFirstChild("Packages")
		net = net and net:FindFirstChild("Networking")
		if net then
			hookRoot(net)
		end
	end)
	pcall(hookCycle)
	local bootNight = false
	pcall(function()
		local attr = Workspace:GetAttribute("IsNight")
		if attr ~= nil then
			bootNight = attr == true
			return
		end
		local ct = Lighting.ClockTime
		if ct < 6 or ct >= 18 then
			bootNight = true
		end
	end)
	cycleGen += 1
	if bootNight then
		table.clear(localSeen)
		cachedEggs = {}
		cachedCycle = "NIGHT"
		enqueueSync({ clearEggs = true, cycle = "NIGHT", gen = cycleGen })
	else
		enqueueSync({ cycle = "DAY", gen = cycleGen })
	end
	if btn then
		btn.Text = "DISCORD ON"
		btn.Name = "DISCORD ON"
		btn.TextColor3 = COL.accent
	end
	return true
end

task.spawn(function()
	while true do
		task.wait(300)
		if boardAlive then
			pcall(function()
				pruneLocalSeen()
				cachedEggs = trimEggList(cachedEggs, MAX_EGG_LINES)
				local target = math.floor(MAX_SYNC_QUEUE * 0.5)
				while #syncQueue > target do
					if not dropQueueSlot(true) then
						break
					end
				end
				if #errLines > ERR_KEEP then
					while #errLines > 20 do
						table.remove(errLines, 1)
					end
				end
			end)
		end
		if not alive then
			stop()
			break
		end
	end
end)

return {
	isOn = function()
		return on
	end,
	start = start,
	stop = stop,
	toggle = function()
		if on then
			stop()
		else
			start()
		end
	end,
	setBtn = function(b)
		btn = b
	end,
	paint = function()
		if not btn then
			return
		end
		local lab = on and "DISCORD ON" or "DISCORD OFF"
		btn.Name = lab
		btn.Text = lab
		btn.TextColor3 = on and COL.accent or COL.text
	end,
}
end)()
ENV.__RareEggLogKill = DiscordBoard.stop

-- ========== GUI ==========
local function buildGui()
	local ICON_SZ, ICON_URL, ICON_CACHE = 22, "https://i.imgur.com/T74OGZv.png", "L7Script/title_icon.png"
	local function loadTitleIcon()
		if typeof(getcustomasset) ~= "function" then return nil end
		local ok, asset = pcall(function()
			local dir = string.match(ICON_CACHE, "^(.+)/[^/]+$")
			if dir and typeof(isfolder) == "function" and typeof(makefolder) == "function" and not isfolder(dir) then
				makefolder(dir)
			end
			local has = typeof(isfile) == "function" and isfile(ICON_CACHE)
			if not has and typeof(writefile) == "function" then
				local body
				if typeof(request) == "function" then
					body = request({ Url = ICON_URL, Method = "GET" }).Body
				elseif typeof(http_request) == "function" then
					body = http_request({ Url = ICON_URL, Method = "GET" }).Body
				else
					body = game:HttpGet(ICON_URL)
				end
				if typeof(body) == "string" and body ~= "" then
					writefile(ICON_CACHE, body)
					has = true
				end
			end
			return has and getcustomasset(ICON_CACHE) or nil
		end)
		return (ok and typeof(asset) == "string" and asset ~= "") and asset or nil
	end

	local pg = LP:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("EggProtectUI")
	if old then old:Destroy() end

	local function corner(p, rad)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, rad or 8)
		c.Parent = p
	end
	local function stroke(p, color, th, tr)
		local s = Instance.new("UIStroke")
		s.Color = color or COL.border
		s.Thickness = th or 1
		s.Transparency = tr or 0.45
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = p
		return s
	end
	local function mk(class, props, parent)
		local o = Instance.new(class)
		for k, v in pairs(props) do o[k] = v end
		if parent then o.Parent = parent end
		return o
	end
	local function hPad(p, l, r)
		local sp = Instance.new("UIPadding")
		sp.PaddingLeft = UDim.new(0, l or 0)
		sp.PaddingRight = UDim.new(0, r or l or 0)
		sp.Parent = p
	end
	local function vList(p, pad)
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Vertical
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Padding = UDim.new(0, pad or 0)
		l.Parent = p
		return l
	end
	local function hList(p, pad)
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.Padding = UDim.new(0, pad or 0)
		l.Parent = p
		return l
	end
	local function makeRow(parent, order, h)
		local row = mk("Frame", {
			Size = UDim2.new(1, 0, 0, h),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, parent)
		hList(row, 8)
		return row
	end
	local function makeScrollShell(parent, h, order, clip)
		local shell = mk("Frame", {
			Size = UDim2.new(1, 0, 0, h),
			LayoutOrder = order,
			BackgroundColor3 = COL.panelHi,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			ClipsDescendants = clip == true,
		}, parent)
		corner(shell, 10)
		stroke(shell, COL.border, 1, 0.45)
		local sc = mk("ScrollingFrame", {
			Size = UDim2.new(1, -12, 1, -12),
			Position = UDim2.fromOffset(6, 6),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = COL.accent,
			CanvasSize = UDim2.fromOffset(0, 0),
		}, shell)
		return shell, sc
	end

	local PAD, PAD_BOT, GAP, TITLE_H, TAB_H = 12, 16, 8, 28, 34
	local FULL_W = 300
	local SEARCH_H, AREA_H, LIST_H, INFO_H, ACT_H = 32, 64, 168, 16, 34
	local DIST_BTN_H = 34
	local HW_STATUS_H, HW_BTN_H = 18, 34
	local activeTab = "dist"
	local function protectContentHeight()
		return DIST_BTN_H * 5 + GAP * 4
	end
	local function pickContentHeight()
		return SEARCH_H + GAP + AREA_H + GAP + LIST_H + GAP + INFO_H + GAP + ACT_H
	end
	local function halloweenContentHeight()
		-- status + kill + fish + munnezz btn + munnezz label
		return HW_STATUS_H + GAP + HW_BTN_H + GAP + HW_BTN_H + GAP + HW_BTN_H + GAP + HW_STATUS_H
	end
	local function contentHeight()
		if activeTab == "dist" then
			return protectContentHeight()
		end
		if activeTab == "pick" then
			return pickContentHeight()
		end
		return halloweenContentHeight()
	end
	local function fullHeight()
		return PAD + TITLE_H + GAP + TAB_H + GAP + contentHeight() + PAD_BOT
	end

	gui = mk("ScreenGui", {
		Name = "EggProtectUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, pg)

	local uiRoot = mk("Frame", {
		Size = UDim2.fromOffset(FULL_W, fullHeight()),
		Position = UDim2.fromOffset(16, 200),
		BackgroundColor3 = COL.panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
		Draggable = true,
	}, gui)
	corner(uiRoot, 16)
	local grad = mk("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COL.panelHi),
			ColorSequenceKeypoint.new(1, COL.panel),
		}),
		Rotation = 115,
	}, uiRoot)
	stroke(uiRoot, COL.border, 1, 0.5)
	local pad = mk("UIPadding", {}, uiRoot)
	pad.PaddingTop = UDim.new(0, PAD)
	pad.PaddingBottom = UDim.new(0, PAD_BOT)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	vList(uiRoot, GAP)

	local titleRow = mk("Frame", {
		Size = UDim2.new(1, 0, 0, TITLE_H),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, uiRoot)
	local brand = mk("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1,
	}, titleRow)
	local brandLay = hList(brand, 6)
	brandLay.VerticalAlignment = Enum.VerticalAlignment.Center
	brandLay.SortOrder = Enum.SortOrder.LayoutOrder
	local titleIcon = mk("ImageLabel", {
		Size = UDim2.fromOffset(ICON_SZ, ICON_SZ),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		LayoutOrder = 1,
	}, brand)
	mk("TextLabel", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "L7 Script",
		TextColor3 = COL.text,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
	}, brand)
	local rightCluster = mk("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 18),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		BackgroundTransparency = 1,
	}, titleRow)
	local rightLay = hList(rightCluster, 6)
	rightLay.VerticalAlignment = Enum.VerticalAlignment.Center
	rightLay.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local discordBtn = mk("TextButton", {
		Size = UDim2.fromOffset(88, 18),
		BackgroundColor3 = COL.btn,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Text = "DISCORD OFF",
		TextColor3 = COL.text,
		Font = Enum.Font.GothamMedium,
		TextSize = 10,
		AutoButtonColor = false,
		LayoutOrder = 1,
	}, rightCluster)
	corner(discordBtn, 6)
	local status = mk("TextLabel", {
		Size = UDim2.fromOffset(56, 18),
		BackgroundColor3 = COL.btn,
		BackgroundTransparency = 0.35,
		Text = "ACTIVE",
		TextColor3 = COL.accent,
		Font = Enum.Font.GothamMedium,
		TextSize = 10,
		LayoutOrder = 2,
	}, rightCluster)
	corner(status, 6)
	DiscordBoard.setBtn(discordBtn)
	discordBtn.MouseButton1Click:Connect(function()
		DiscordBoard.toggle()
		DiscordBoard.paint()
	end)
	DiscordBoard.start()
	DiscordBoard.paint()

	local tabRow = mk("Frame", {
		Size = UDim2.new(1, 0, 0, TAB_H),
		BackgroundColor3 = COL.btn,
		BackgroundTransparency = 0.35,
		LayoutOrder = 2,
	}, uiRoot)
	corner(tabRow, 10)
	stroke(tabRow, COL.border, 1, 0.6)
	do
		local tabPad = mk("UIPadding", {}, tabRow)
		tabPad.PaddingTop = UDim.new(0, 3)
		tabPad.PaddingBottom = UDim.new(0, 3)
		tabPad.PaddingLeft = UDim.new(0, 3)
		tabPad.PaddingRight = UDim.new(0, 3)
		hList(tabRow, 6)
	end
	local function makeTab(label, on)
		local b = mk("TextButton", {
			Size = UDim2.new(1 / 3, -4, 1, 0),
			BackgroundColor3 = on and COL.modeOn or COL.modeOff,
			BorderSizePixel = 0,
			Text = label,
			TextColor3 = COL.text,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			AutoButtonColor = false,
		}, tabRow)
		corner(b, 8)
		return b
	end
	local tabProtect = makeTab("Dist", true)
	local tabPick = makeTab("Pick", false)
	local tabHalloween = makeTab("Halloween", false)

	local contentArea = mk("Frame", {
		Size = UDim2.new(1, 0, 0, protectContentHeight()),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		ClipsDescendants = false,
	}, uiRoot)
	local protectPanel = mk("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = true,
	}, contentArea)
	local pickPanel = mk("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, contentArea)
	local halloweenPanel = mk("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, contentArea)

	local function makeActionBtn(parent, label, flex, cols, gapPx, bg)
		cols = cols or 2
		gapPx = gapPx or 8
		local b = mk("TextButton", {
			Name = label,
			Size = UDim2.new(flex, -math.ceil(gapPx * (cols - 1) / cols), 1, 0),
			BackgroundColor3 = bg or COL.btn,
			BorderSizePixel = 0,
			Text = label,
			TextColor3 = COL.text,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			AutoButtonColor = false,
		}, parent)
		corner(b, 10)
		stroke(b, COL.border, 1, 0.55)
		local base = bg or COL.btn
		local hot = (bg == COL.autoOff) and COL.autoOn or COL.btnHot
		b.MouseEnter:Connect(function()
			if alive then b.BackgroundColor3 = hot end
		end)
		b.MouseLeave:Connect(function()
			if alive then b.BackgroundColor3 = base end
		end)
		return b
	end
	local function flashBtn(b, okText, failText, ok)
		local restore = b.Name
		b.Text = ok and (okText or "OK") or (failText or "fail")
		b.TextColor3 = ok and COL.accent or COL.warn
		task.delay(1.2, function()
			if b.Parent then
				b.Text = restore
				b.TextColor3 = (restore == "BAT ON" or restore == "AUTO SAFE ON" or restore == "ISTANT E ON") and COL.accent or COL.text
			end
		end)
	end
	local function paintToggle(btn, on, onL, offL)
		local lab = on and onL or offL
		btn.Name = lab
		btn.Text = lab
		btn.TextColor3 = on and COL.accent or COL.text
	end

	do
		vList(protectPanel, GAP)
		local row1 = makeRow(protectPanel, 1, DIST_BTN_H)
		local row2 = makeRow(protectPanel, 2, DIST_BTN_H)
		local row3 = makeRow(protectPanel, 3, DIST_BTN_H)
		local row4 = makeRow(protectPanel, 4, DIST_BTN_H)
		local row5 = makeRow(protectPanel, 5, DIST_BTN_H)
		local safeBtn = makeActionBtn(row1, "SAFE", 0.5, 2, 8)
		local tapisBtn = makeActionBtn(row1, "TAPIS", 0.5, 2, 8)
		local batBtn = makeActionBtn(row2, "BAT ON", 1, 1, 8)
		batBtn.Name = "BAT ON"
		batBtn.TextColor3 = COL.accent
		local autoSafeBtn = makeActionBtn(row3, "AUTO SAFE ON", 1, 1, 8)
		autoSafeBtn.Name = "AUTO SAFE ON"
		autoSafeBtn.TextColor3 = COL.accent
		local instantEBtn = makeActionBtn(row4, "ISTANT E OFF", 1, 1, 8)
		instantEBtn.Name = "ISTANT E OFF"
		local afkBtn = makeActionBtn(row5, "ANTI-AFK OFF", 1, 1, 8)
		afkBtn.Name = "ANTI-AFK OFF"
		AntiAfk.setBtn(afkBtn)
		local function paintBat() paintToggle(batBtn, batOn, "BAT ON", "BAT OFF") end
		local function paintAutoSafe() paintToggle(autoSafeBtn, autoRunSafe, "AUTO SAFE ON", "AUTO SAFE OFF") end
		local function paintInstantE() paintToggle(instantEBtn, instantE, "ISTANT E ON", "ISTANT E OFF") end
		local function paintAfk() AntiAfk.paint() end
		tapisBtn.MouseButton1Click:Connect(function()
			local ok, info = tpToMyTapis()
			flashBtn(tapisBtn, "OK", tostring(info), ok)
		end)
		safeBtn.MouseButton1Click:Connect(function()
			local ok, info = resetToSafe()
			flashBtn(safeBtn, "…", tostring(info), ok)
		end)
		batBtn.MouseButton1Click:Connect(function()
			if batOn then
				batOn = false
				paintBat()
				unequipBat()
			else
				batOn = true
				paintBat()
				nextBatEquip = 0
				forceEquipBat(5)
			end
		end)
		autoSafeBtn.MouseButton1Click:Connect(function()
			if autoRunSafe then
				clearAutoSafeTransport()
				paintAutoSafe()
			else
				autoRunSafe = true
				paintAutoSafe()
				ensureAutoSafeArm()
				setPickStatus("auto safe on", COL.accent)
			end
		end)
		instantEBtn.MouseButton1Click:Connect(function()
			setInstantE(not instantE)
			paintInstantE()
		end)
		paintInstantE()
		afkBtn.MouseButton1Click:Connect(function()
			AntiAfk.toggle()
			paintAfk()
		end)
		paintAfk()
	end

	do
		vList(pickPanel, GAP)
		searchBox = mk("TextBox", {
			Size = UDim2.new(1, 0, 0, SEARCH_H),
			LayoutOrder = 1,
			BackgroundColor3 = COL.btn,
			BorderSizePixel = 0,
			PlaceholderText = "Search eggs...",
			PlaceholderColor3 = COL.textMute,
			Text = "",
			TextColor3 = COL.text,
			ClearTextOnFocus = false,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, pickPanel)
		corner(searchBox, 10)
		stroke(searchBox, COL.border, 1, 0.65)
		hPad(searchBox, 10, 10)
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			searchText = searchBox.Text
			rebuildList()
		end)

		local _, areaScroll = makeScrollShell(pickPanel, AREA_H, 2, false)
		do
			local ax, ay, chipH, chipGap = 0, 0, 24, 6
			local availW = FULL_W - 24 - 12
			local chipW = math.floor((availW - chipGap * 2) / 3)
			local function paintChip(b, on)
				b.BackgroundColor3 = on and COL.modeOn or COL.modeOff
				b.TextColor3 = on and COL.text or COL.textDim
			end
			addAreaChip = function(aName)
				local b = mk("TextButton", {
					Size = UDim2.fromOffset(chipW, chipH),
					Position = UDim2.fromOffset(ax, ay),
					BackgroundColor3 = COL.modeOff,
					BorderSizePixel = 0,
					Text = aName,
					TextColor3 = COL.textDim,
					Font = Enum.Font.GothamMedium,
					TextSize = 11,
					TextScaled = false,
					AutoButtonColor = false,
					ClipsDescendants = true,
				}, areaScroll)
				corner(b, 8)
				paintChip(b, areaOn[aName] == true)
				b.MouseButton1Click:Connect(function()
					areaOn[aName] = not areaOn[aName]
					paintChip(b, areaOn[aName])
				end)
				local bottom = ay + chipH
				ax = ax + chipW + chipGap
				if ax + chipW > availW then
					ax, ay = 0, ay + chipH + chipGap
				end
				areaScroll.CanvasSize = UDim2.fromOffset(0, bottom + 2)
			end
			for _, aName in ipairs(AREA_ORDER) do
				addAreaChip(aName)
			end
			for _, aName in ipairs(pendingAreas) do
				addAreaChip(aName)
			end
			table.clear(pendingAreas)
		end

		local _, listSc = makeScrollShell(pickPanel, LIST_H, 3, true)
		listFrame = listSc
		local listLay = Instance.new("UIListLayout")
		listLay.Padding = UDim.new(0, 2)
		listLay.SortOrder = Enum.SortOrder.LayoutOrder
		listLay.Parent = listFrame

		countLbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, INFO_H),
			LayoutOrder = 4,
			BackgroundTransparency = 1,
			Text = "0 / 0 eggs",
			TextColor3 = COL.textDim,
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, pickPanel)

		local btnRow = makeRow(pickPanel, 5, ACT_H)
		local pick1Btn = makeActionBtn(btnRow, "Pick 1", 1 / 3, 3, 8)
		local pickAreeBtn = makeActionBtn(btnRow, "Areas", 1 / 3, 3, 8)
		local stopBtn = makeActionBtn(btnRow, "Stop", 1 / 3, 3, 8, COL.autoOff)
		pick1Btn.MouseButton1Click:Connect(pickSelected)
		pickAreeBtn.MouseButton1Click:Connect(pickAreas)
		stopBtn.MouseButton1Click:Connect(stopPick)
	end

	do
		vList(halloweenPanel, GAP)
		hwStatusLbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, HW_STATUS_H),
			LayoutOrder = 1,
			BackgroundTransparency = 1,
			Text = "auto-kill off",
			TextColor3 = COL.textDim,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, halloweenPanel)
		local hwRow = makeRow(halloweenPanel, 2, HW_BTN_H)
		hwKillBtn = makeActionBtn(hwRow, "AUTO-KILL OFF", 1, 1, 8)
		hwKillBtn.Name = "AUTO-KILL OFF"
		hwKillBtn.MouseButton1Click:Connect(function()
			if hwOn then
				stopHwKill()
			else
				startHwKill()
			end
		end)
		paintHwBtn()
		local fishRow = makeRow(halloweenPanel, 3, HW_BTN_H)
		local fishBtn = makeActionBtn(fishRow, "AUTO FISH OFF", 1, 1, 8)
		fishBtn.Name = "AUTO FISH OFF"
		Fish.setBtn(fishBtn)
		fishBtn.MouseButton1Click:Connect(Fish.toggle)
		Fish.paint()
		local munRow = makeRow(halloweenPanel, 4, HW_BTN_H)
		local munBtn = makeActionBtn(munRow, "MUNNEZZ OFF", 1, 1, 8)
		munBtn.Name = "MUNNEZZ OFF"
		Munnezz.setBtn(munBtn)
		munBtn.MouseButton1Click:Connect(Munnezz.toggle)
		Munnezz.paint()
		local munLbl = mk("TextLabel", {
			Size = UDim2.new(1, 0, 0, HW_STATUS_H),
			LayoutOrder = 5,
			BackgroundTransparency = 1,
			Text = "Munnezz off",
			TextColor3 = COL.textDim,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, halloweenPanel)
		Munnezz.setLbl(munLbl)
	end

	local function refreshTabBtns()
		tabProtect.BackgroundColor3 = (activeTab == "dist") and COL.modeOn or COL.modeOff
		tabPick.BackgroundColor3 = (activeTab == "pick") and COL.modeOn or COL.modeOff
		tabHalloween.BackgroundColor3 = (activeTab == "halloween") and COL.modeOn or COL.modeOff
	end
	local function switchTab(tab)
		if activeTab == tab then return end
		activeTab = tab
		protectPanel.Visible = tab == "dist"
		pickPanel.Visible = tab == "pick"
		halloweenPanel.Visible = tab == "halloween"
		refreshTabBtns()
		contentArea.Size = UDim2.new(1, 0, 0, contentHeight())
		uiRoot.Size = UDim2.fromOffset(FULL_W, fullHeight())
	end
	tabProtect.MouseButton1Click:Connect(function() switchTab("dist") end)
	tabPick.MouseButton1Click:Connect(function() switchTab("pick") end)
	tabHalloween.MouseButton1Click:Connect(function() switchTab("halloween") end)
	task.defer(function()
		local asset = loadTitleIcon()
		if asset then titleIcon.Image = asset end
	end)
	startAutoRefresh()
	if autoRunSafe then task.defer(ensureAutoSafeArm) end
	uiRoot.BackgroundTransparency = 1
	TweenService:Create(uiRoot, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
end
buildGui()

ENV.__L7ScriptKill = function()
	alive, batOn = false, false
	batEpoch = batEpoch + 1
	reequipUntil, nextBatEquip = 0, 1e9
	setInstantE(false)
	stopPickTeardown()
	stopHwKill()
	Fish.stop()
	Munnezz.stop()
	AntiAfk.stop()
	pcall(DiscordBoard.stop)
	for _, conn in ipairs({ hbConn, charConn, bagConn }) do
		if conn then conn:Disconnect() end
	end
	hbConn, charConn, bagConn = nil, nil, nil
	for i = 1, #extraConns do
		local cc = extraConns[i]
		if cc then pcall(function() cc:Disconnect() end) end
		extraConns[i] = nil
	end
	wipeConns()
	local g = LP:FindFirstChild("PlayerGui")
	g = g and g:FindFirstChild("EggProtectUI")
	if g then g:Destroy() end
	gui = nil
end