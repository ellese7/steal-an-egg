-- DIAGNOSTICA SALVATAGGIO PSX - SOLO PER DELTA
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- CREAZIONE GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SaveDiagnostic"
screenGui.ResetOnSpawn = false
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 450, 0, 300)
frame.Position = UDim2.new(0.5, -225, 0.5, -150)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "Diagnostica Salvataggio"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.Parent = frame

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -80)
scroll.Position = UDim2.new(0, 10, 0, 35)
scroll.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
scroll.BorderSizePixel = 0
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = frame
local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 6)
scrollCorner.Parent = scroll

local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 4)
logLayout.Parent = scroll

local function addLog(text, color)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -10, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color or Color3.fromRGB(200, 200, 200)
    label.Font = Enum.Font.Code
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Parent = scroll
end

-- PULSANTI
local scanBtn = Instance.new("TextButton")
scanBtn.Size = UDim2.new(0.48, -15, 0, 35)
scanBtn.Position = UDim2.new(0, 10, 1, -45)
scanBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 200)
scanBtn.Text = "1. SCANSIONA REMOTE"
scanBtn.TextColor3 = Color3.new(1,1,1)
scanBtn.Font = Enum.Font.GothamBold
scanBtn.Parent = frame
local sCorner = Instance.new("UICorner") sCorner.CornerRadius = UDim.new(0, 6) sCorner.Parent = scanBtn

local netBtn = Instance.new("TextButton")
netBtn.Size = UDim2.new(0.48, -15, 0, 35)
netBtn.Position = UDim2.new(0.52, 5, 1, -45)
netBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 40)
netBtn.Text = "2. ISPEZIONA NETWORK"
netBtn.TextColor3 = Color3.new(1,1,1)
netBtn.Font = Enum.Font.GothamBold
netBtn.Parent = frame
local nCorner = Instance.new("UICorner") nCorner.CornerRadius = UDim.new(0, 6) nCorner.Parent = netBtn

-- LOGICA 1: SCANSIONE REMOTE
scanBtn.MouseButton1Click:Connect(function()
    scroll:ClearAllChildren()
    local layout = Instance.new("UIListLayout") layout.Parent = scroll
    addLog("[SCAN] Cerco RemoteEvent legati al salvataggio...", Color3.fromRGB(100, 200, 255))
    
    local keywords = {"save", "request", "sync", "profile", "commit", "update"}
    local found = 0
    
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local name = string.lower(obj.Name)
            for _, kw in ipairs(keywords) do
                if string.find(name, kw) then
                    addLog("[TROVATO] " .. obj:GetFullName(), Color3.fromRGB(100, 255, 100))
                    found = found + 1
                    break
                end
            end
        end
    end
    
    if found == 0 then
        addLog("[!] Nessun remote di salvataggio ovvio trovato.", Color3.fromRGB(255, 200, 100))
    else
        addLog("[!] Trovati " .. found .. " possibili remote. Prova a invocarli manualmente se sei sicuro.", Color3.fromRGB(255, 200, 100))
    end
end)

-- LOGICA 2: ISPEZIONA MODULO NETWORK
netBtn.MouseButton1Click:Connect(function()
    scroll:ClearAllChildren()
    local layout = Instance.new("UIListLayout") layout.Parent = scroll
    addLog("[NET] Tento di leggere Library.Network...", Color3.fromRGB(255, 150, 50))
    
    local ok, net = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Network"))
    end)
    
    if ok and net then
        addLog("[OK] Modulo Network caricato!", Color3.fromRGB(100, 255, 100))
        
        -- Cerca funzioni alternative
        local foundFuncs = {}
        for k, v in pairs(net) do
            if type(v) == "function" then
                table.insert(foundFuncs, k)
            end
        end
        
        -- Aggiunge metatable
        local mt = getrawmetatable(net)
        if mt and mt.__index then
            for k, v in pairs(mt.__index) do
                if type(v) == "function" and not table.find(foundFuncs, k) then
                    table.insert(foundFuncs, k)
                end
            end
        end
        
        addLog("[NET] Funzioni trovate:", Color3.fromRGB(200, 200, 200))
        for _, fName in ipairs(foundFuncs) do
            addLog(" - " .. tostring(fName), Color3.fromRGB(150, 200, 255))
        end
        
        addLog("[!] Cerca una funzione tipo 'RequestSave' o 'Save'. Se c'è, possiamo provarla.", Color3.fromRGB(255, 200, 100))
    else
        addLog("[ERRORE] Network bloccato o in crash (come su Xeno).", Color3.fromRGB(255, 100, 100))
    end
end)

addLog("In attesa di comandi. Premi 1 o 2.", Color3.fromRGB(200, 200, 200))
