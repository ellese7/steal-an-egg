-- DELTA FORENSIC SCANNER (SAVE & NETWORK)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- GUI
local pg = LocalPlayer:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("ForensicScanner")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ForensicScanner"
gui.ResetOnSpawn = false
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(520, 400)
frame.Position = UDim2.new(0.5, -260, 0.5, -200)
frame.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "Forensic Scanner: Save & Network"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = frame

local btnScan = Instance.new("TextButton")
btnScan.Size = UDim2.new(1, -20, 0, 35)
btnScan.Position = UDim2.fromOffset(10, 35)
btnScan.BackgroundColor3 = Color3.fromRGB(180, 80, 30)
btnScan.Text = "AVVIA SCANSIONE FORENSE"
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
    addLog("[FORENSIC] Avvio analisi approfondita...", Color3.fromRGB(100, 200, 255))

    -- 1. Ispeziona modulo Save
    addLog("[1] Ispezione Library.Client.Save...", Color3.fromRGB(255, 200, 100))
    local saveModule
    pcall(function()
        saveModule = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("Save"))
    end)
    if saveModule then
        for k, v in pairs(saveModule) do
            if type(v) == "function" then
                addLog("  Funzione: " .. tostring(k), Color3.fromRGB(100, 255, 100))
                local consts = debug.getconstants(v)
                local interesting = {}
                for _, c in ipairs(consts) do
                    if type(c) == "string" and (string.find(c, "Save") or string.find(c, "Request") or string.find(c, "Buffer") or string.find(c, "Sync")) then
                        table.insert(interesting, c)
                    end
                end
                if #interesting > 0 then
                    addLog("    [COSTANTI INTERESSANTI] " .. table.concat(interesting, ", "), Color3.fromRGB(255, 150, 150))
                end
            end
        end
    else
        addLog("  Impossibile caricare il modulo Save.", Color3.fromRGB(255, 100, 100))
    end
    task.wait(0.5)

    -- 2. Ispeziona modulo Network (Library.Network)
    addLog("[2] Ispezione Library.Network...", Color3.fromRGB(255, 200, 100))
    local networkModule
    pcall(function()
        networkModule = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Network"))
    end)
    if networkModule then
        -- Cerchiamo funzioni nascoste nella metatable
        local mt = getrawmetatable(networkModule)
        if mt and mt.__index then
            for k, v in pairs(mt.__index) do
                if type(v) == "function" then
                    addLog("  Funzione Network: " .. tostring(k), Color3.fromRGB(100, 255, 100))
                    local consts = debug.getconstants(v)
                    for _, c in ipairs(consts) do
                        if type(c) == "string" and (string.find(c, "Save") or string.find(c, "Request") or string.find(c, "Buffer")) then
                            addLog("    [COSTANTE] " .. c, Color3.fromRGB(255, 150, 150))
                        end
                    end
                end
            end
        end
    else
        addLog("  Impossibile caricare il modulo Network.", Color3.fromRGB(255, 100, 100))
    end
    task.wait(0.5)

    -- 3. Scansione remote con nomi sospetti (non solo "save")
    addLog("[3] Scansione RemoteEvent/RemoteFunction...", Color3.fromRGB(255, 200, 100))
    local remoteKeywords = {"save", "request", "buffer", "sync", "data", "profile", "commit"}
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local name = string.lower(obj.Name)
            for _, kw in ipairs(remoteKeywords) do
                if string.find(name, kw) then
                    addLog("  [REMOTE] " .. obj:GetFullName(), Color3.fromRGB(100, 255, 100))
                    -- Prova a vedere se ha connessioni
                    local cons = getconnections(obj.OnClientEvent or obj.OnClientInvoke)
                    if cons and #cons > 0 then
                        addLog("    -> Connessioni attive: " .. #cons, Color3.fromRGB(200, 200, 255))
                    end
                    break
                end
            end
        end
    end

    -- 4. Ispeziona tabelle con chiavi sospette
    addLog("[4] Ispezione tabelle di stato...", Color3.fromRGB(255, 200, 100))
    local gc = getgc(true)
    if gc then
        for _, obj in ipairs(gc) do
            if typeof(obj) == "table" then
                for k, v in pairs(obj) do
                    if type(k) == "string" and (string.find(k, "desync") or string.find(k, "synchronize") or string.find(k, "LastSave")) then
                        addLog("  [TAB] " .. k .. " = " .. typeof(v), Color3.fromRGB(200, 255, 200))
                        if type(v) == "function" then
                            local consts = debug.getconstants(v)
                            for _, c in ipairs(consts) do
                                if type(c) == "string" then
                                    addLog("    [COSTANTE] " .. c, Color3.fromRGB(255, 150, 150))
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    addLog("=== SCANSIONE COMPLETATA ===", Color3.fromRGB(255, 255, 255))
    addLog("Cerca le righe [COSTANTI INTERESSANTI] o [COSTANTE]. Quelle stringhe sono i comandi da usare su Xeno.", Color3.fromRGB(100, 200, 255))
end)
