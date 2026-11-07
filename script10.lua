-- DELTA FORENSIC SCANNER V2 (NO CRASH)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- GUI
local pg = LocalPlayer:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("ForensicScannerV2")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ForensicScannerV2"
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
title.Text = "Forensic Scanner V2 (Save Focus)"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = frame

local btnScan = Instance.new("TextButton")
btnScan.Size = UDim2.new(1, -20, 0, 35)
btnScan.Position = UDim2.fromOffset(10, 35)
btnScan.BackgroundColor3 = Color3.fromRGB(40, 120, 80)
btnScan.Text = "AVVIA SCANSIONE MIRATA"
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
    addLog("[ANALISI] Avvio scansione mirata...", Color3.fromRGB(100, 200, 255))

    -- 1. Testiamo la funzione Get()
    addLog("[1] Test lettura dati tramite Save.Get()...", Color3.fromRGB(255, 200, 100))
    local saveModule
    pcall(function()
        saveModule = require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("Save"))
    end)
    
    if saveModule and saveModule.Get then
        local success, data = pcall(saveModule.Get)
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
            addLog("  -> Errore nella lettura: " .. tostring(data), Color3.fromRGB(255, 100, 100))
        end
    else
        addLog("  -> Modulo Save non caricato.", Color3.fromRGB(255, 100, 100))
    end
    task.wait(1)

    -- 2. Cerchiamo RemoteEvents con hash in ReplicatedStorage
    addLog("[2] Ricerca RemoteEvent legati al salvataggio (pattern hash)...", Color3.fromRGB(255, 200, 100))
    local count = 0
    for _, obj in ipairs(ReplicatedStorage:GetChildren()) do
        -- Cerchiamo oggetti con nome hash (32 caratteri esadecimali)
        if (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) and string.match(obj.Name, "^%x+$") and #obj.Name >= 32 then
            -- Ispezioniamo i suoi metodi (FireServer/InvokeServer) per vedere se ci sono costanti "Save"
            local isSaveRemote = false
            local fServer = obj.FireServer or obj.InvokeServer
            if fServer then
                local consts = debug.getconstants(fServer)
                for _, c in ipairs(consts) do
                    if type(c) == "string" and (string.find(c, "Save") or string.find(c, "Request")) then
                        isSaveRemote = true
                        addLog("  [TROVATO] Remote: " .. obj.Name .. " | Contiene costante: '" .. c .. "'", Color3.fromRGB(100, 255, 100))
                        break
                    end
                end
            end
            if not isSaveRemote and (string.find(string.lower(obj.Name), "save") or string.find(string.lower(obj.Name), "sync")) then
                addLog("  [SOSPETTO] Remote: " .. obj.Name, Color3.fromRGB(255, 200, 100))
            end
            count = count + 1
        end
    end
    addLog("  -> Controllati " .. count .. " remote con hash.", Color3.fromRGB(200, 200, 200))

    addLog("=== SCANSIONE COMPLETATA ===", Color3.fromRGB(255, 255, 255))
    addLog("Se la Fase 1 ha letto i pet, il gioco ha i dati in RAM. Dobbiamo solo forzare il trigger.", Color3.fromRGB(100, 200, 255))
end)
