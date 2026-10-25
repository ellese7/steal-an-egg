-- ==========================================
-- SPEED HACK CON SPOOF (Delta / Xeno)
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local isEnabled = false
local targetSpeed = 60
local safeSpoofSpeed = 16 -- Velocità che il server crede che tu stia usando

-- ==========================================
-- 1. CREAZIONE GUI
-- ==========================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SpeedSpoofer"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = game.CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 280, 0, 350)
MainFrame.Position = UDim2.new(0.5, -140, 0.5, -175)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 40)
Title.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
Title.Text = "Speed Spoofer (Delta)"
Title.TextColor3 = Color3.fromRGB(0, 255, 150)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 8)
TitleCorner.Parent = Title

-- Toggle Button
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, -20, 0, 40)
ToggleBtn.Position = UDim2.new(0, 10, 0, 50)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
ToggleBtn.Text = "STATO: DISATTIVATO"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 14
ToggleBtn.Parent = MainFrame

-- Speed Input
local SpeedBox = Instance.new("TextBox")
SpeedBox.Size = UDim2.new(1, -20, 0, 35)
SpeedBox.Position = UDim2.new(0, 10, 0, 100)
SpeedBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
SpeedBox.TextColor3 = Color3.fromRGB(255, 255, 255)
SpeedBox.PlaceholderText = "Inserisci Velocità (es. 60)"
SpeedBox.Text = tostring(targetSpeed)
SpeedBox.Font = Enum.Font.Gotham
SpeedBox.TextSize = 14
SpeedBox.Parent = MainFrame

-- Logger Frame
local LoggerFrame = Instance.new("ScrollingFrame")
LoggerFrame.Size = UDim2.new(1, -20, 0, 140)
LoggerFrame.Position = UDim2.new(0, 10, 0, 145)
LoggerFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
LoggerFrame.BorderSizePixel = 0
LoggerFrame.ScrollBarThickness = 4
LoggerFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
LoggerFrame.Parent = MainFrame

local LoggerLayout = Instance.new("UIListLayout")
LoggerLayout.Padding = UDim.new(0, 4)
LoggerLayout.Parent = LoggerFrame

-- ==========================================
-- 2. SISTEMA DI LOGGING
-- ==========================================
local function AddLog(text, color)
    local timestamp = os.date("%H:%M:%S")
    local logLabel = Instance.new("TextLabel")
    logLabel.Size = UDim2.new(1, 0, 0, 20)
    logLabel.BackgroundTransparency = 1
    logLabel.Text = "[" .. timestamp .. "] " .. text
    logLabel.TextColor3 = color or Color3.fromRGB(200, 200, 200)
    logLabel.Font = Enum.Font.Code
    logLabel.TextSize = 12
    logLabel.TextXAlignment = Enum.TextXAlignment.Left
    logLabel.Parent = LoggerFrame
    
    -- Auto scroll
    task.wait()
    LoggerFrame.CanvasSize = UDim2.new(0, 0, 0, LoggerLayout.AbsoluteContentSize.Y)
    LoggerFrame.CanvasPosition = Vector2.new(0, LoggerLayout.AbsoluteContentSize.Y)
end

-- Hook dei print per vederli nel logger
local oldPrint = print
print = function(...)
    local args = {...}
    local str = ""
    for i, v in ipairs(args) do
        str = str .. tostring(v) .. (i < #args and " " or "")
    end
    AddLog(str, Color3.fromRGB(0, 200, 255))
    oldPrint(...)
end

-- ==========================================
-- 3. LOGICA DI SPOOF E MOVIMENTO
-- ==========================================
local CurrentBodyVelocity = nil

local function ApplySpeed()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not hrp or not hum then return end

    -- Rimuovi il BodyVelocity precedente se esiste
    if CurrentBodyVelocity then
        CurrentBodyVelocity:Destroy()
    end

    if isEnabled then
        -- Creiamo la spinta fisica
        local bv = Instance.new("BodyVelocity")
        bv.Name = "SpeedSpoofBV"
        bv.MaxForce = Vector3.new(math.huge, 0, math.huge) -- Solo orizzontale per non volare
        bv.Velocity = Vector3.new(0, 0, 0)
        bv.Parent = hrp
        CurrentBodyVelocity = bv
        AddLog("Spinta fisica attivata: " .. targetSpeed, Color3.fromRGB(0, 255, 0))
    else
        AddLog("Spinta fisica disattivata.", Color3.fromRGB(255, 100, 100))
    end
end

-- Hook per far credere al gioco che WalkSpeed sia sicuro
local oldIndex
oldIndex = hookmetamethod(game, "__index", function(self, key)
    if self:IsA("Humanoid") and key == "WalkSpeed" and isEnabled then
        return safeSpoofSpeed -- Il server vede questo valore
    end
    return oldIndex(self, key)
end)

-- Loop per muovere il personaggio
RunService.RenderStepped:Connect(function()
    if isEnabled and CurrentBodyVelocity then
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChild("Humanoid")
            if hum and hum.MoveDirection.Magnitude > 0 then
                -- Spingiamo il personaggio nella direzione in cui sta guardando
                CurrentBodyVelocity.Velocity = hum.MoveDirection * targetSpeed
            else
                CurrentBodyVelocity.Velocity = Vector3.new(0, 0, 0)
            end
        end
    end
end)

-- ==========================================
-- 4. GESTIONE EVENTI GUI
-- ==========================================
ToggleBtn.MouseButton1Click:Connect(function()
    isEnabled = not isEnabled
    if isEnabled then
        ToggleBtn.Text = "STATO: ATTIVATO"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
        targetSpeed = tonumber(SpeedBox.Text) or 60
        ApplySpeed()
    else
        ToggleBtn.Text = "STATO: DISATTIVATO"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        ApplySpeed()
    end
end)

SpeedBox.FocusLost:Connect(function()
    targetSpeed = tonumber(SpeedBox.Text) or 60
    if isEnabled then ApplySpeed() end
end)

-- Riapplica in caso di respawn
LocalPlayer.CharacterAdded:Connect(function()
    if isEnabled then
        task.wait(1)
        ApplySpeed()
    end
end)

AddLog("Script caricato con successo. Pronto.", Color3.fromRGB(255, 255, 0))
