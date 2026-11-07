-- DELTA DEEP INSPECTOR (SALVATAGGIO)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- GUI
local pg = LocalPlayer:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("DeltaDeepInspect")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DeltaDeepInspect"
gui.ResetOnSpawn = false
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(480, 380)
frame.Position = UDim2.new(0.5, -240, 0.5, -190)
frame.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "Delta Deep Inspector"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = frame

-- Pulsanti di scansione
local btnSave = Instance.new("TextButton")
btnSave.Size = UDim2.new(0.31, -5, 0, 30)
btnSave.Position = UDim2.fromOffset(10, 35)
btnSave.BackgroundColor3 = Color3.fromRGB(40, 100, 200)
btnSave.Text = "Ispeziona Save"
btnSave.TextColor3 = Color3.new(1,1,1)
btnSave.Font = Enum.Font.GothamBold
btnSave.TextSize = 11
btnSave.Parent = frame
Instance.new("UICorner", btnSave).CornerRadius = UDim.new(0, 5)

local btnNetwork = Instance.new("TextButton")
btnNetwork.Size = UDim2.new(0.31, -5, 0, 30)
btnNetwork.Position = UDim2.fromOffset(10 + 0.33*460, 35)
btnNetwork.BackgroundColor3 = Color3.fromRGB(200, 100, 40)
btnNetwork.Text = "Ispeziona Network"
btnNetwork.TextColor3 = Color3.new(1,1,1)
btnNetwork.Font = Enum.Font.GothamBold
btnNetwork.TextSize = 11
btnNetwork.Parent = frame
Instance.new("UICorner", btnNetwork).CornerRadius = UDim.new(0, 5)

local btnTables = Instance.new("TextButton")
btnTables.Size = UDim2.new(0.31, -5, 0, 30)
btnTables.Position = UDim2.fromOffset(10 + 0.66*460, 35)
btnTables.BackgroundColor3 = Color3.fromRGB(100, 180, 50)
btnTables.Text = "Cerca Tabelle Save"
btnTables.TextColor3 = Color3.new(1,1,1)
btnTables.Font = Enum.Font.GothamBold
btnTables.TextSize = 11
btnTables.Parent = frame
Instance.new("UICorner", btnTables).CornerRadius = UDim.new(0, 5)

-- Area Log
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -110)
scroll.Position = UDim2.fromOffset(10, 75)
scroll.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
scroll.BorderSizePixel = 0
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = frame
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)

local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 3)
logLayout.Parent = scroll

local function addLog(text, color)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -10, 0, 0)
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color or Color3.fromRGB(200, 200, 200)
    label.Font = Enum.Font.Code
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Parent = scroll
    task.defer(function()
        scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
    end)
end

-- Funzione per ispezionare un modulo
local function inspectModule(modulePath, moduleName)
    addLog("=== ISPEZIONE " .. moduleName .. " ===", Color3.fromRGB(100, 200, 255))
    local ok, mod = pcall(function()
        return require(modulePath)
    end)
    if not ok or not mod then
        addLog("Impossibile caricare " .. moduleName .. ": " .. tostring(mod), Color3.fromRGB(255, 100, 100))
        return
    end
    addLog("Modulo caricato. Chiavi trovate:", Color3.fromRGB(100, 255, 100))
    for k, v in pairs(mod) do
        local typeStr = typeof(v)
        addLog("  • " .. tostring(k) .. " (" .. typeStr .. ")", Color3.fromRGB(200, 200, 255))
        if type(v) == "function" then
            -- Legge costanti e upvalue (solo per Delta)
            local consts = debug.getconstants(v)
            if consts then
                local interesting = {}
                for _, c in ipairs(consts) do
                    if type(c) == "string" then
                        table.insert(interesting, '"' .. c .. '"')
                    elseif type(c) == "number" then
                        table.insert(interesting, tostring(c))
                    end
                end
                if #interesting > 0 then
                    addLog("     Costanti: " .. table.concat(interesting, ", "), Color3.fromRGB(255, 200, 100))
                end
            end
            local upvals = debug.getupvalue(v, 1)
            if upvals then
                addLog("     Upvalue[1]: " .. tostring(upvals), Color3.fromRGB(255, 200, 100))
            end
        end
    end
end

-- Ispeziona Save
btnSave.MouseButton1Click:Connect(function()
    scroll:ClearAllChildren()
    local layout = Instance.new("UIListLayout") layout.Parent = scroll
    local savePath = ReplicatedStorage:FindFirstChild("Library")
    if savePath then
        savePath = savePath:FindFirstChild("Client")
        if savePath then
            savePath = savePath:FindFirstChild("Save")
        end
    end
    if savePath then
        inspectModule(savePath, "Library.Client.Save")
    else
        addLog("Percorso Library.Client.Save non trovato.", Color3.fromRGB(255, 100, 100))
    end
end)

-- Ispeziona Network
btnNetwork.MouseButton1Click:Connect(function()
    scroll:ClearAllChildren()
    local layout = Instance.new("UIListLayout") layout.Parent = scroll
    local netPath = ReplicatedStorage:FindFirstChild("Library")
    if netPath then
        netPath = netPath:FindFirstChild("Client")
        if netPath then
            netPath = netPath:FindFirstChild("Network")
        end
    end
    if netPath then
        inspectModule(netPath, "Library.Client.Network")
    else
        addLog("Percorso Library.Client.Network non trovato.", Color3.fromRGB(255, 100, 100))
    end
end)

-- Cerca tabelle con LastSaveTimestamp
btnTables.MouseButton1Click:Connect(function()
    scroll:ClearAllChildren()
    local layout = Instance.new("UIListLayout") layout.Parent = scroll
    addLog("Scansione tabelle in memoria...", Color3.fromRGB(100, 200, 255))
    local gc = getgc(true)
    if not gc then
        addLog("getgc(true) non disponibile.", Color3.fromRGB(255, 100, 100))
        return
    end
    local found = 0
    for _, obj in ipairs(gc) do
        if typeof(obj) == "table" then
            for k, v in pairs(obj) do
                if type(k) == "string" and (string.find(k, "LastSaveTimestamp") or string.find(k, "LastSavedTimestamp")) then
                    addLog("[TAB] " .. k .. " = " .. tostring(v), Color3.fromRGB(255, 200, 100))
                    found = found + 1
                end
            end
        end
    end
    if found == 0 then
        addLog("Nessuna tabella con timestamp trovata.", Color3.fromRGB(255, 100, 100))
    else
        addLog("Trovate " .. found .. " tabelle con timestamp.", Color3.fromRGB(100, 255, 100))
    end
end)

addLog("Pronto. Seleziona un'ispezione.", Color3.fromRGB(200, 200, 200))
