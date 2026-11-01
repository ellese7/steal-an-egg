-- Anti-AFK (Delta) — light toggle, no rejoin
-- NO VirtualUser / VIM (those = Kick 267). One short J tap via Delta input.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local LP = Players.LocalPlayer

local ENV = _G
pcall(function()
	if typeof(getgenv) == "function" then
		ENV = getgenv()
	end
end)
if typeof(ENV.__AntiAfkDeltaKill) == "function" then
	pcall(ENV.__AntiAfkDeltaKill)
end

local PERIODIC = 150
local PREEMPT = 840
local GAP = 12
local BOOT = 2.5
local VK_J = 0x4A

local COL_ON = Color3.fromRGB(44, 112, 88)
local COL_OFF = Color3.fromRGB(55, 60, 78)
local COL_BAD = Color3.fromRGB(140, 70, 50)

local alive = true
local enabled = false
local lastPoke = 0
local lastActivity = os.clock()
local nextAt = 0
local idledConn, inputConn
local btn

local function hasInput()
	return typeof(keyclick) == "function"
		or typeof(keypress) == "function"
		or typeof(mouse2click) == "function"
		or typeof(mouse1click) == "function"
		or typeof(mouse1press) == "function"
end

local function pokeOnce()
	if typeof(keyclick) == "function" then
		local ok = pcall(keyclick, VK_J)
		if ok then
			return true
		end
	end
	if typeof(keypress) == "function" then
		local ok = pcall(function()
			keypress(VK_J)
			task.wait(0.05)
			if typeof(keyrelease) == "function" then
				keyrelease(VK_J)
			end
		end)
		if ok then
			return true
		end
	end
	if typeof(mouse2click) == "function" then
		local ok = pcall(mouse2click)
		if ok then
			return true
		end
	end
	if typeof(mouse1click) == "function" then
		local ok = pcall(mouse1click)
		if ok then
			return true
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
			return true
		end
	end
	return false
end

local function paint()
	if not btn then
		return
	end
	if not hasInput() then
		btn.Text = "AFK NO API"
		btn.BackgroundColor3 = COL_BAD
		return
	end
	btn.Text = enabled and "AFK ON" or "AFK OFF"
	btn.BackgroundColor3 = enabled and COL_ON or COL_OFF
end

local function poke()
	if not alive or not enabled then
		return
	end
	local now = os.clock()
	if now - lastPoke < GAP then
		return
	end
	lastPoke = now
	lastActivity = now
	nextAt = now + PERIODIC + (math.random() * 40 - 10)
	if not pokeOnce() then
		enabled = false
		paint()
	end
end

local function stop()
	enabled = false
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
	paint()
end

local function start()
	if enabled or not hasInput() then
		paint()
		return
	end
	enabled = true
	lastPoke = 0
	lastActivity = os.clock()
	nextAt = os.clock() + BOOT + PERIODIC
	paint()

	idledConn = LP.Idled:Connect(function()
		poke()
	end)
	inputConn = UIS.InputBegan:Connect(function(input)
		if not alive or not enabled then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Focus then
			return
		end
		lastActivity = os.clock()
	end)

	task.delay(BOOT, function()
		if alive and enabled then
			poke()
		end
	end)
end

task.spawn(function()
	while alive do
		if not enabled then
			task.wait(1)
		else
			local now = os.clock()
			local waitFor = nextAt - now
			if now - lastActivity >= PREEMPT then
				waitFor = 0
			end
			if waitFor > 1 then
				task.wait(math.min(waitFor, 30))
			else
				task.wait(1)
				if alive and enabled then
					poke()
				end
			end
		end
	end
end)

local gui
do
	local pg = LP:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("AntiAfkDelta")
	if old then
		old:Destroy()
	end

	gui = Instance.new("ScreenGui")
	gui.Name = "AntiAfkDelta"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pg

	btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(92, 28)
	btn.Position = UDim2.fromOffset(16, 16)
	btn.BackgroundColor3 = COL_OFF
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(240, 242, 248)
	btn.Text = "AFK OFF"
	btn.AutoButtonColor = false
	btn.Active = true
	btn.Draggable = true
	btn.Parent = gui

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = btn

	btn.MouseButton1Click:Connect(function()
		if enabled then
			stop()
		else
			start()
		end
	end)
	paint()
end

start()

ENV.__AntiAfkDeltaKill = function()
	alive = false
	stop()
	if gui then
		pcall(function()
			gui:Destroy()
		end)
		gui = nil
	end
end
