-- DELTA DIAGNOSTIC SCANNER (SOLO RICERCA, NESSUN SALVATAGGIO FORZATO)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- GUI
local pg = LocalPlayer:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("DeltaDiagUI")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "DeltaDiagUI"
gui.ResetOnSpawn = false
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(500, 350)
frame.Position = UDim2.new(0.5, -250, 0.5, -175)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
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
title.Text = "Delta Diagnostic Scanner"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 24)
status.Position = UDim2.fromOffset(10, 32)
status.BackgroundTransparency = 1
status.Text = "Pronto. Premi START per avviare la scansione diagnostica."
status.TextColor3 = Color3.fromRGB(200, 200, 200)
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextWrapped = true
status.Parent = frame

-- Area Log
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -110)
scroll.Position = UDim2.fromOffset(10, 60)
scroll.BackgroundColor3 = Color3.fromRGB(10, 11, 14)
scroll.BorderSizePixel = 0
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = frame
local scrollCorner = Instance.new("UICorner")
scrollCorner.CornerRadius = UDim.new(0, 6)
scrollCorner.Parent = scroll

local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 3)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
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
    label.LayoutOrder = #scroll:GetChildren()
    label.Parent = scroll
    task.defer(function()
        scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
    end)
end

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(1, -20, 0, 35)
btn.Position = UDim2.new(0, 10, 1, -45)
btn.BackgroundColor3 = Color3.fromRGB(30, 80, 160)
btn.Text = "START SCANSIONE DIAGNOSTICA"
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Font = Enum.Font.GothamBold
btn.TextSize = 13
btn.Parent = frame
local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 6)
btnCorner.Parent = btn

-- FUNZIONI DI SCANSIONE
local function scanRemotes()
    addLog("[SCAN] Ricerca RemoteEvent/RemoteFunction con parole chiave...", Color3.fromRGB(100, 200, 255))
    local keywords = {"save", "request", "sync", "profile", "commit", "update", "data"}
    local count = 0
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local name = string.lower(obj.Name)
            for _, kw in ipairs(keywords) do
                if string.find(name, kw) then
                    addLog("[REMOTE] " .. obj:GetFullName() .. " | Tipo: " .. obj.ClassName, Color3.fromRGB(100, 255, 100))
                    count = count + 1
                    break
                end
            end
        end
    end
    addLog("[SCAN] Trovati " .. count .. " remote potenziali.", Color3.fromRGB(255, 200, 100))
end

local function scanModules()
    addLog("[SCAN] Ricerca moduli con 'Save' o 'Network'...", Color3.fromRGB(100, 200, 255))
    local folders = {ReplicatedStorage:FindFirstChild("Library"), ReplicatedStorage:FindFirstChild("Framework")}
    local count = 0
    for _, folder in ipairs(folders) do
        if folder then
            for _, obj in ipairs(folder:GetDescendants()) do
                if obj:IsA("ModuleScript") then
                    local name = string.lower(obj.Name)
                    if string.find(name, "save") or string.find(name, "network") then
                        addLog("[MODULE] " .. obj:GetFullName(), Color3.fromRGB(100, 255, 100))
                        count = count + 1
                    end
                end
            end
        end
    end
    addLog("[SCAN] Trovati " .. count .. " moduli potenziali.", Color3.fromRGB(255, 200, 100))
end

local function scanMemoryTables()
    addLog("[SCAN] Scansione getgc per tabelle con chiavi di salvataggio...", Color3.fromRGB(100, 200, 255))
    local gc = getgc(true)
    if not gc then
        addLog("[ERRORE] getgc non disponibile o fallito.", Color3.fromRGB(255, 100, 100))
        return
    end
    local count = 0
    for _, obj in ipairs(gc) do
        if typeof(obj) == "table" then
            local keys = {}
            for k, v in pairs(obj) do
                if type(k) == "string" then table.insert(keys, k) end
            end
            for _, k in ipairs(keys) do
                local lowK = string.lower(k)
                if string.find(lowK, "save") or string.find(lowK, "timestamp") or string.find(lowK, "sync") then
                    addLog("[TABLE] Trovata chiave: " .. k .. " | Valore: " .. tostring(obj[k]), Color3.fromRGB(255, 200, 100))
                    count = count + 1
                end
            end
        end
    end
    addLog("[SCAN] Trovate " .. count .. " chiavi di salvataggio in tabelle di memoria.", Color3.fromRGB(255, 200, 100))
end

local function scanHookedConnections()
    addLog("[SCAN] Analisi connessioni ai remote (getconnections)...", Color3.fromRGB(100, 200, 255))
    local count = 0
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            local cons = getconnections(obj.OnClientEvent or obj.OnClientInvoke)
            if cons and #cons > 0 then
                addLog("[CONN] " .. obj:GetFullName() .. " | Connessioni: " .. #cons, Color3.fromRGB(150, 200, 255))
                count = count + 1
            end
        end
    end
    addLog("[SCAN] Trovati " .. count .. " remote con connessioni attive.", Color3.fromRGB(255, 200, 100))
end

-- AVVIO
btn.MouseButton1Click:Connect(function()
    btn.Active = false
    btn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    scroll:ClearAllChildren()
    local layout = Instance.new("UIListLayout") layout.Parent = scroll

    addLog("=== AVVIO SCANSIONE DIAGNOSTICA ===", Color3.fromRGB(255, 255, 255))
    
    scanRemotes()
    task.wait(0.5)
    scanModules()
    task.wait(0.5)
    scanMemoryTables()
    task.wait(0.5)
    scanHookedConnections()
    
    addLog("=== SCANSIONE COMPLETATA ===", Color3.fromRGB(255, 255, 255))
    status.Text = "Scansione completata. Controlla i log sopra per capire come procedere."
    btn.Active = true
    btn.BackgroundColor3 = Color3.fromRGB(30, 80, 160)
end)
