-- DELTA ULTIMATE SAVE LOGGER (ANTI-CRASH)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- GUI
local pg = LocalPlayer:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("UltimateSaveLogger")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "UltimateSaveLogger"
gui.ResetOnSpawn = false
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(520, 420)
frame.Position = UDim2.new(0.5, -260, 0.5, -210)
frame.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "Delta Ultimate Save Logger"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.Parent = frame

local btnScan = Instance.new("TextButton")
btnScan.Size = UDim2.new(1, -20, 0, 40)
btnScan.Position = UDim2.fromOffset(10, 40)
btnScan.BackgroundColor3 = Color3.fromRGB(40, 120, 80)
btnScan.Text = "AVVIA SCANSIONE TOTALE"
btnScan.TextColor3 = Color3.new(1,1,1)
btnScan.Font = Enum.Font.GothamBold
btnScan.Parent = frame
Instance.new("UICorner", btnScan).CornerRadius = UDim.new(0, 8)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -100)
scroll.Position = UDim2.fromOffset(10, 90)
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
    btnScan.Active = false
    btnScan.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    scroll:ClearAllChildren()
    local layout = Instance.new("UIListLayout") layout.Parent = scroll
    addLog("[SYSTEM] Avvio scansione profonda...", Color3.fromRGB(100, 200, 255))

    -- 1. Testiamo la funzione Get() con un timeout
    addLog("[1] Test lettura Save.Get()...", Color3.fromRGB(255, 200, 100))
    local success, data = pcall(function()
        local mod = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("Save"))
        return mod.Get()
    end)
    if success and data then
        addLog("  -> Dati letti con successo!", Color3.fromRGB(100, 255, 100))
        if data.Inventory then
            local petCount = 0
            for _ in pairs(data.Inventory.Pet or {}) do petCount = petCount + 1 end
            addLog("  -> Pet nell'inventario: " .. petCount, Color3.fromRGB(255, 200, 100))
        end
        if data.LastSaveTimestamp then
            addLog("  -> Timestamp attuale: " .. tostring(data.LastSaveTimestamp), Color3.fromRGB(200, 200, 255))
        end
    else
        addLog("  -> Errore: " .. tostring(data), Color3.fromRGB(255, 100, 100))
    end
    task.wait(0.5)

    -- 2. Analisi Remote (con Timeout per evitare blocchi)
    addLog("[2] Ispezione RemoteEvent/Function...", Color3.fromRGB(255, 200, 100))
    local keywords = {"save", "request", "sync", "profile", "commit", "data", "store", "desync"}
    local foundCount = 0
    
    -- Usiamo una lista pre-filtrata per non bloccare il thread
    local remotes = {}
    for _, obj in ipairs(ReplicatedStorage:GetChildren()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            table.insert(remotes, obj)
        end
    end
    
    for _, obj in ipairs(remotes) do
        local isSuspicious = false
        local matchedName = ""
        local nameLower = string.lower(obj.Name)
        
        -- Controllo nome hash o parole chiave
        for _, kw in ipairs(keywords) do
            if string.find(nameLower, kw) then
                isSuspicious = true
                matchedName = kw
                break
            end
        end
        
        if isSuspicious then
            addLog("  [REMOTE NAME] " .. obj:GetFullName() .. " (match: " .. matchedName .. ")", Color3.fromRGB(100, 255, 100))
            foundCount = foundCount + 1
            
            -- Prova a ispezionare le costanti in modo sicuro
            local function inspectFunc(fn)
                if type(fn) ~= "function" then return end
                local ok, consts = pcall(debug.getconstants, fn)
                if ok and consts then
                    for _, c in ipairs(consts) do
                        if type(c) == "string" then
                            for _, kw in ipairs(keywords) do
                                if string.find(string.lower(c), kw) then
                                    addLog("    -> Costante trovata: '" .. c .. "'", Color3.fromRGB(255, 150, 150))
                                    break
                                end
                            end
                        end
                    end
                end
            end
            
            if obj:IsA("RemoteEvent") then inspectFunc(obj.FireServer) end
            if obj:IsA("RemoteFunction") then inspectFunc(obj.InvokeServer) end
        end
    end
    
    if foundCount == 0 then
        addLog("  -> Nessun remote con nome sospetto trovato.", Color3.fromRGB(200, 200, 200))
    end
    task.wait(0.5)

    -- 3. Analisi connessioni client (OnClientEvent)
    addLog("[3] Analisi connessioni client (getconnections)...", Color3.fromRGB(255, 200, 100))
    local connCount = 0
    for _, obj in ipairs(remotes) do
        if obj:IsA("RemoteEvent") then
            local ok, conns = pcall(getconnections, obj.OnClientEvent)
            if ok and conns and #conns > 0 then
                addLog("  [CONN] " .. obj.Name .. " | Connessioni: " .. #conns, Color3.fromRGB(200, 255, 200))
                connCount = connCount + 1
            end
        end
    end
    addLog("  -> Trovate " .. connCount .. " connessioni attive.", Color3.fromRGB(255, 200, 100))

    addLog("=== SCANSIONE COMPLETATA ===", Color3.fromRGB(255, 255, 255))
    btnScan.Active = true
    btnScan.BackgroundColor3 = Color3.fromRGB(40, 120, 80)
end)
