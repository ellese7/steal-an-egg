-- FORCE SAVE / NETWORK UNLOCK PER XENO
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- GUI
local pg = LocalPlayer:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("ForceSaveUI")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "ForceSaveUI"
gui.ResetOnSpawn = false
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(260, 120)
frame.Position = UDim2.new(0.5, -130, 0.5, -60)
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
title.Text = "Salvataggio d'Emergenza"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 30)
status.Position = UDim2.fromOffset(10, 35)
status.BackgroundTransparency = 1
status.Text = "Pronto per l'attacco."
status.TextColor3 = Color3.fromRGB(200, 200, 200)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextWrapped = true
status.Parent = frame

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(1, -20, 0, 35)
btn.Position = UDim2.fromOffset(10, 75)
btn.BackgroundColor3 = Color3.fromRGB(0, 150, 100)
btn.Text = "START"
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Font = Enum.Font.GothamBold
btn.Parent = frame
local btnCorner = Instance.new("UICorner") btnCorner.CornerRadius = UDim.new(0, 6) btnCorner.Parent = btn

-- Logica Aggressiva
local function updateStatus(txt, color)
    status.Text = txt
    status.TextColor3 = color or Color3.fromRGB(200, 200, 200)
    print("[FORCE_SAVE] " .. txt)
end

local function tryRequestSave()
    local paths = {
        {"LoadSaveRequests", "RequestSave"},
        {"Remotes", "RequestSave"},
        {"SaveRequests", "RequestSave"}
    }
    for _, p in ipairs(paths) do
        local parent = ReplicatedStorage:FindFirstChild(p[1])
        if parent then
            local remote = parent:FindFirstChild(p[2])
            if remote and (remote:IsA("RemoteFunction") or remote:IsA("RemoteEvent")) then
                updateStatus("Trovato remote di salvataggio: " .. remote:GetFullName(), Color3.fromRGB(100, 200, 255))
                pcall(function()
                    if remote:IsA("RemoteFunction") then
                        remote:InvokeServer()
                    else
                        remote:FireServer()
                    end
                end)
                return true
            end
        end
    end
    return false
end

local function tryUnlockNetwork()
    local ok, Network = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Library"):WaitForChild("Network"))
    end)
    if ok and Network then
        updateStatus("Modulo Network trovato. Invio comandi validi per resettare la coda...", Color3.fromRGB(255, 200, 100))
        pcall(function() Network.Invoke("Buy Egg", 1) end)
        task.wait(0.5)
        pcall(function() Network.Invoke("Join Coin", 1) end)
        return true
    end
    return false
end

local function forceKick()
    updateStatus("Tentativi falliti. Forzo la disconnessione per far scattare il salvataggio d'emergenza del server.", Color3.fromRGB(255, 100, 100))
    task.wait(2)
    LocalPlayer:Kick("Forzatura salvataggio d'emergenza.")
end

btn.MouseButton1Click:Connect(function()
    btn.Active = false
    btn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    
    updateStatus("Fase 1: Ricerca remote di salvataggio...", Color3.fromRGB(255, 200, 100))
    local foundRemote = tryRequestSave()
    
    if not foundRemote then
        updateStatus("Fase 2: Tentativo di sbloccare Library.Network...", Color3.fromRGB(255, 200, 100))
        local unlocked = tryUnlockNetwork()
        if not unlocked then
            updateStatus("Fase 3: Fallback finale.", Color3.fromRGB(255, 100, 100))
            forceKick()
        else
            updateStatus("Comandi inviati. Attendi 10 secondi e controlla se il gioco risponde.", Color3.fromRGB(100, 255, 100))
        end
    else
        updateStatus("Remote invocato. Attendi 10 secondi.", Color3.fromRGB(100, 255, 100))
    end
end)
