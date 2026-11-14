-- ===================================================================
-- DIG-ONE: PSX-Stayso Dupe Injector (Final Fix by Me)
-- ===================================================================
local Game = game
local Players = Game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") -- FIX: PlayerGui corretto
local LIBRARY = Game:GetService("ReplicatedStorage"):WaitForChild("Framework"):WaitForChild("Library")

local MIN_FREEZE_CYCLES = 3
local MAX_TEST_CYCLES = 5

local InitialTimestamp = nil
local FreezeCount = 0
local LogHistory = {}

local function updateLog(message, isError)
    local formattedMessage = string.format("[%s] %s", isError and "CRITICAL" or "INFO", message)
    table.insert(LogHistory, formattedMessage)
    if #LogHistory > 50 then
        table.remove(LogHistory, 1)
    end
    if GUI and GUI.LogTextBox then
        GUI.LogTextBox.Text = table.concat(LogHistory, "\n")
    end
    print(formattedMessage)
end

local function getSaveTimestamp()
    local s = LIBRARY.Save.Get()
    if not s then
        local s_player = LIBRARY.Save.Get(LocalPlayer)
        if s_player then return s_player.LastSaveTimestamp or s_player.SaveTimestamp or s_player.SaveTime or s_player._saveClock end
        return nil
    end
    return s.LastSaveTimestamp or s.SaveTimestamp or s.SaveTime or s._saveClock
end

-- PAYLOADS
local function generateBadCFramePayload()
    -- Crea un vero NaN in Luau
    return CFrame.new(0/0, 0/0, 0/0)
end

local function generateComplexPetPayload()
    local fakeUID = 999999
    local nestedNil = nil
    return {{fakeUID, nestedNil}, true}
end

local function generateEmptyTablePayload()
    local fakeUID = 888888
    return {{fakeUID, {}}}
end

local function executeInjectionAttack()
    updateLog("AVVIO ATTACCO: Iniezione di payload corrotti...", false)

    -- FIX: Uso Fire per Report Migration Position e Invoke per gli altri
    local success1, result1 = pcall(function()
        LIBRARY.Network.Fire("Report Migration Position", generateBadCFramePayload())
    end)
    if not success1 then updateLog("FALLIMENTO [Report Migration Position]: " .. tostring(result1), true) else updateLog("SUCCESSO [Report Migration Position]", false) end
    task.wait(0.3)

    local success2, result2 = pcall(function()
        LIBRARY.Network.Invoke("Enchant Pets", generateComplexPetPayload())
    end)
    if not success2 then updateLog("FALLIMENTO [Enchant Pets]: " .. tostring(result2), true) else updateLog("SUCCESSO [Enchant Pets]", false) end
    task.wait(0.3)

    local success3, result3 = pcall(function()
        LIBRARY.Network.Invoke("Delete Several Pets", generateEmptyTablePayload())
    end)
    if not success3 then updateLog("FALLIMENTO [Delete Several Pets]: " .. tostring(result3), true) else updateLog("SUCCESSO [Delete Several Pets]", false) end
end

local function monitorPersistence()
    InitialTimestamp = getSaveTimestamp()
    if not InitialTimestamp then
        updateLog("CRITICO: Impossibile leggere il timestamp iniziale.", true)
        return
    end

    updateLog("T0 Acquisito: " .. tostring(InitialTimestamp) .. ". Inizio monitoraggio.", false)
    executeInjectionAttack()

    for i = 1, MAX_TEST_CYCLES do
        updateLog("--- Ciclo di monitoraggio " .. i .. " / " .. MAX_TEST_CYCLES .. " ---", false)
        task.wait(6) 

        local currentTimestamp = getSaveTimestamp()

        if currentTimestamp == nil then
            updateLog("Ciclo " .. i .. ": ERRORE di lettura timestamp.", true)
            FreezeCount = 0 
        elseif currentTimestamp == InitialTimestamp then
            FreezeCount = FreezeCount + 1
            updateLog("Ciclo " .. i .. ": STASIS DETECTED.", false)

            if FreezeCount >= MIN_FREEZE_CYCLES then
                updateLog("*****************************************************************", false)
                updateLog("!!! SAVE FREEZE CONFIRMED: IL SERVER È BLOCCATO SU T0 !!!", true)
                updateLog("=================================================================", false)
                return 
            end
        else
            FreezeCount = 0
            InitialTimestamp = currentTimestamp 
            updateLog("Ciclo " .. i .. ": PROGRESSION. Stato avanzato.", false)
        end
    end

    if FreezeCount < MIN_FREEZE_CYCLES then
        updateLog("Monitoraggio completato. Nessun freeze stabile confermato.", false)
    end
end

-- GUI
local GUI = {}
local StartButton = nil
local LogTextBox = nil

local function setupGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "DIG_HackerPanel"
    screenGui.Parent = PlayerGui -- Usa la variabile corretta

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0.35, 0, 0.6, 0)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 3
    frame.BorderColor3 = Color3.fromRGB(0, 255, 0)
    frame.Parent = screenGui

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, 0, 0.2, 0)
    titleLabel.Text = "DIG - PSX Dupe Injector"
    titleLabel.TextColor3 = Color3.new(0.2, 1, 0.2)
    titleLabel.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    titleLabel.Font = Enum.Font.Code
    titleLabel.TextSize = 18
    titleLabel.Parent = frame

    StartButton = Instance.new("TextButton")
    StartButton.Size = UDim2.new(0.9, 0, 0.2, 0)
    StartButton.Position = UDim2.new(0.05, 0, 0.25, 0)
    StartButton.Text = ">> INIZIA ATTACCO & MONITORAGGIO <<" -- FIX: Caratteri HTML rimossi
    StartButton.TextColor3 = Color3.new(1, 1, 1)
    StartButton.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
    StartButton.Font = Enum.Font.SourceSansBold
    StartButton.TextSize = 16
    StartButton.Parent = frame

    LogTextBox = Instance.new("TextBox")
    LogTextBox.Size = UDim2.new(0.9, 0, 0.6, 0)
    LogTextBox.Position = UDim2.new(0.05, 0, 0.45, 0)
    LogTextBox.Text = "Pronto. Clicca START per inizializzare il controllo." -- FIX: Rimossa la virgola
    LogTextBox.TextWrapped = true
    LogTextBox.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    LogTextBox.TextColor3 = Color3.new(1, 1, 1)
    LogTextBox.Font = Enum.Font.SourceSans
    LogTextBox.TextSize = 11
    LogTextBox.Parent = frame
end

setupGUI()

if StartButton then
    StartButton.MouseButton1Click:Connect(function()
        FreezeCount = 0
        LogHistory = {} 
        updateLog("=====================================================", false)
        updateLog("*** AVVIANDO CICLO DUPE HUNTING *** ", false)
        monitorPersistence()
    end)
end