-- DELTA DEEP ANALYSIS: CACCIA ALLA FUNZIONE FORCE SAVE
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- GUI
local pg = LocalPlayer:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("ForceSaveHunter")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ForceSaveHunter"
gui.ResetOnSpawn = false
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(500, 350)
frame.Position = UDim2.new(0.5, -250, 0.5, -175)
frame.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "Caccia al ForceSave (Solo Analisi)"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = frame

local btnScan = Instance.new("TextButton")
btnScan.Size = UDim2.new(1, -20, 0, 35)
btnScan.Position = UDim2.fromOffset(10, 35)
btnScan.BackgroundColor3 = Color3.fromRGB(200, 100, 40)
btnScan.Text = "AVVIA SCANSIONE PROFONDA"
btnScan.TextColor3 = Color3.new(1,1,1)
btnScan.Font = Enum.Font.GothamBold
btnScan.Parent = frame
Instance.new("UICorner", btnScan).CornerRadius = UDim.new(0, 5)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -85)
scroll.Position = UDim2.fromOffset(10, 75)
scroll.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
scroll.BorderSizePixel = 0
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = frame
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 6)

local logLayout = Instance.new("UIListLayout") logLayout.Padding = UDim.new(0, 3) logLayout.Parent = scroll

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
    task.defer(function() scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y) end)
end

btnScan.MouseButton1Click:Connect(function()
    scroll:ClearAllChildren()
    local layout = Instance.new("UIListLayout") layout.Parent = scroll
    addLog("[ANALISI] Avvio caccia alle funzioni di salvataggio...", Color3.fromRGB(100, 200, 255))
    
    -- 1. Scansione getgc per tabelle sospette
    addLog("[1] Scansione tabelle (getgc)...", Color3.fromRGB(255, 200, 100))
    local gc = getgc(true)
    local foundUI = false
    for _, obj in ipairs(gc) do
        if typeof(obj) == "table" then
            for k, v in pairs(obj) do
                if type(k) == "string" and (string.find(k, "ForceSave") or string.find(k, "SaveRecovery") or string.find(k, "SaveDiagnostic")) then
                    addLog("[TABELLA TROVATA] " .. k, Color3.fromRGB(100, 255, 100))
                    if typeof(v) == "table" then
                        for subK, subV in pairs(v) do
                            addLog("   -> " .. tostring(subK) .. " : " .. typeof(subV), Color3.fromRGB(200, 255, 200))
                        end
                    end
                    foundUI = true
                end
            end
        end
    end
    if not foundUI then addLog("Nessuna tabella ForceSave trovata in getgc.", Color3.fromRGB(255, 100, 100)) end
    task.wait(0.5)

    -- 2. Ispezione modulo Network (Library.Network e Library.Client.Network)
    addLog("[2] Ispezione moduli Network...", Color3.fromRGB(255, 200, 100))
    local netPaths = {
        ReplicatedStorage:FindFirstChild("Library") and ReplicatedStorage.Library:FindFirstChild("Network"),
        ReplicatedStorage:FindFirstChild("Library") and ReplicatedStorage.Library:FindFirstChild("Client") and ReplicatedStorage.Library.Client:FindFirstChild("Network")
    }
    for _, path in ipairs(netPaths) do
        if path then
            addLog("[MODULO] Trovato: " .. path:GetFullName(), Color3.fromRGB(100, 255, 100))
            local ok, mod = pcall(require, path)
            if ok and mod then
                -- Cerchiamo funzioni nascoste (metatable)
                local mt = getrawmetatable(mod)
                if mt and mt.__index then
                    for k, v in pairs(mt.__index) do
                        if type(v) == "function" and (string.find(string.lower(k), "save") or string.find(string.lower(k), "request")) then
                            addLog("   -> Funzione: " .. tostring(k), Color3.fromRGB(255, 200, 100))
                            local consts = debug.getconstants(v)
                            for _, c in ipairs(consts) do
                                if type(c) == "string" and (string.find(c, "Save") or string.find(c, "Request")) then
                                    addLog("      [COSTANTE SEGRETA] " .. tostring(c), Color3.fromRGB(255, 150, 150))
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    task.wait(0.5)

    -- 3. Scansione Remote per nomi "Save"
    addLog("[3] Scansione Remote nel Workspace/ReplicatedStorage...", Color3.fromRGB(255, 200, 100))
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            if string.find(string.lower(obj.Name), "save") then
                addLog("[REMOTE] " .. obj:GetFullName(), Color3.fromRGB(100, 255, 100))
            end
        end
    end

    addLog("=== SCANSIONE COMPLETATA ===", Color3.fromRGB(255, 255, 255))
    addLog("Cerca i log con [COSTANTE SEGRETA] o [REMOTE]. Quelli sono i comandi da mandare su Xeno.", Color3.fromRGB(100, 200, 255))
end)
