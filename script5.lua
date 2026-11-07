-- DELTA SAVE RECOVERY TOOL
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- GUI
local pg = LocalPlayer:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("SaveRecoveryUI")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SaveRecoveryUI"
gui.ResetOnSpawn = false
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(320, 180)
frame.Position = UDim2.new(0.5, -160, 0.5, -90)
frame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
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
title.Text = "Delta Save Recovery"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 60)
status.Position = UDim2.fromOffset(10, 35)
status.BackgroundTransparency = 1
status.Text = "Pronto. Delta è connesso. Premi START per la scansione profonda."
status.TextColor3 = Color3.fromRGB(200, 200, 200)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.Parent = frame

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(1, -20, 0, 40)
btn.Position = UDim2.fromOffset(10, 115)
btn.BackgroundColor3 = Color3.fromRGB(200, 150, 0) -- Giallo/Ambra per Delta
btn.Text = "START"
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Font = Enum.Font.GothamBold
btn.Parent = frame
local btnCorner = Instance.new("UICorner") btnCorner.CornerRadius = UDim.new(0, 6) btnCorner.Parent = btn

-- Utility
local function updateStatus(txt, color)
    status.Text = txt
    status.TextColor3 = color or Color3.fromRGB(200, 200, 200)
    print("[DELTA_SAVE] " .. txt)
end

-- 1. Scansione Approfondita dei Remote di Salvataggio
local function deepScanForSaveRemotes()
    updateStatus("Fase 1: Scansione approfondita dei remote di salvataggio...", Color3.fromRGB(255, 200, 100))
    local keywords = {"save", "request", "sync", "profile", "commit", "update", "store", "data", "persist", "buffer"}
    local found = {}
    local descendants = ReplicatedStorage:GetDescendants()
    for _, obj in ipairs(descendants) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local name = string.lower(obj.Name)
            for _, kw in ipairs(keywords) do
                if string.find(name, kw) then
                    table.insert(found, obj)
                    break
                end
            end
        end
    end
    if #found > 0 then
        updateStatus("Trovati " .. #found .. " remote potenziali. Tento l'invio...", Color3.fromRGB(100, 200, 255))
        for _, remote in ipairs(found) do
            pcall(function()
                if remote:IsA("RemoteFunction") then
                    remote:InvokeServer()
                else
                    remote:FireServer()
                end
            end)
            task.wait(0.2)
        end
        return true
    end
    return false
end

-- 2. Ispezione di Library.Client.Save e Library.Network
local function inspectLibrary()
    updateStatus("Fase 2: Ispezione di Library.Client.Save...", Color3.fromRGB(255, 200, 100))
    local ok, saveModule = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Client"):WaitForChild("Save"))
    end)
    if ok and saveModule then
        updateStatus("Modulo Save caricato. Cerco funzioni di forzatura...", Color3.fromRGB(100, 200, 255))
        local funcs = {}
        for k, v in pairs(saveModule) do
            if type(v) == "function" then
                table.insert(funcs, k)
            end
        end
        -- Se c'è una funzione ForceSave o Save, proviamo a chiamarla
        for _, fName in ipairs(funcs) do
            if string.find(string.lower(fName), "save") or string.find(string.lower(fName), "force") then
                updateStatus("Trovata funzione: " .. fName .. ". Tento invocazione...", Color3.fromRGB(100, 255, 100))
                pcall(function() saveModule[fName]() end)
                return true
            end
        end
    end
    return false
end

-- 3. Ricerca con getgc di tabelle di salvataggio
local function tryFindSaveTable()
    updateStatus("Fase 3: Scansione getgc per tabelle di salvataggio...", Color3.fromRGB(255, 200, 100))
    local gc = getgc(true)
    if not gc then return false end
    local found = false
    for _, obj in ipairs(gc) do
        if typeof(obj) == "table" then
            local keys = {}
            for k, v in pairs(obj) do
                if type(k) == "string" then table.insert(keys, k) end
            end
            for _, k in ipairs(keys) do
                if string.find(string.lower(k), "save") or string.find(string.lower(k), "timestamp") then
                    updateStatus("Trovata tabella con chiave: " .. k, Color3.fromRGB(100, 255, 100))
                    found = true
                    pcall(function() print("[DELTA_SAVE] Valore di " .. k .. ": " .. tostring(obj[k])) end)
                end
            end
        end
    end
    return found
end

-- 4. Tentativo di forzare un salvataggio via Network
local function tryResetNetwork()
    updateStatus("Fase 4: Tentativo di reset Network...", Color3.fromRGB(255, 200, 100))
    local ok, Network = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Network"))
    end)
    if ok and Network and typeof(Network.Invoke) == "function" then
        updateStatus("Network caricato. Invio comandi validi per sbloccare...", Color3.fromRGB(255, 200, 100))
        pcall(function() Network.Invoke("Buy Egg", 1) end)
        task.wait(0.5)
        pcall(function() Network.Invoke("Join Coin", 1) end)
        return true
    end
    return false
end

-- Logica principale
btn.MouseButton1Click:Connect(function()
    btn.Active = false
    btn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    
    local success = deepScanForSaveRemotes()
    if not success then success = inspectLibrary() end
    if not success then success = tryFindSaveTable() end
    if not success then success = tryResetNetwork() end
    
    if success then
        updateStatus("Operazione completata. Attendi 10 secondi e controlla se il gioco risponde.", Color3.fromRGB(100, 255, 100))
    else
        updateStatus("Scansione completata senza risultati certi. Controlla la console di Delta (F9) per i dettagli.", Color3.fromRGB(255, 100, 100))
    end
end)
