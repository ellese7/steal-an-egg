-- DELTA SMART NETWORK SNIFFER (ANTI-SPAM)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- GUI
local pg = LocalPlayer:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("SmartSniffer")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SmartSniffer"
gui.ResetOnSpawn = false
gui.Parent = pg

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(550, 400)
frame.Position = UDim2.new(0.5, -275, 0.5, -200)
frame.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

local btnHook = Instance.new("TextButton")
btnHook.Size = UDim2.new(1, -20, 0, 35)
btnHook.Position = UDim2.fromOffset(10, 35)
btnHook.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
btnHook.Text = "1. AVVIA SNIFFER INTELLIGENTE"
btnHook.TextColor3 = Color3.new(1,1,1)
btnHook.Font = Enum.Font.GothamBold
btnHook.Parent = frame
Instance.new("UICorner", btnHook).CornerRadius = UDim.new(0, 5)

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

local isHooked = false

btnHook.MouseButton1Click:Connect(function()
    if isHooked then return end
    isHooked = true
    btnHook.Text = "SNIFFER ATTIVO (Ignoro il Ping)"
    btnHook.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
    
    addLog("[SNIFFER] In ascolto. Ignoro il ping 'miseg03'.", Color3.fromRGB(100, 200, 255))
    addLog("[ISTRUZIONI] Ora compra un uovo o fai un'azione che salva.", Color3.fromRGB(255, 200, 100))
    
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        
        if method == "FireServer" or method == "InvokeServer" then
            if self:IsA("RemoteEvent") or self:IsA("RemoteFunction") then
                if string.match(self.Name, "^%x+$") and #self.Name >= 32 then
                    
                    -- FILTRO ANTI-SPAM: Ignora il remote del ping
                    if self.Name == "645cdb478042458ba422781d7bdd738b" then
                        return oldNamecall(self, ...)
                    end

                    local args = {...}
                    local argString = ""
                    local hasTable = false
                    
                    for i, v in ipairs(args) do
                        if type(v) == "table" then
                            argString = argString .. "{Tabella}, "
                            hasTable = true
                        elseif typeof(v) == "Instance" then
                            argString = argString .. v.Name .. ", "
                        else
                            argString = argString .. tostring(v) .. ", "
                        end
                    end
                    
                    -- LOGGA SOLO SE: C'è una tabella O se non è solo il nome utente
                    if hasTable or (#args > 0 and tostring(args[1]) ~= "miseg03") then
                        addLog("  [DIVERSO DAL PING] " .. self.Name, Color3.fromRGB(255, 150, 150))
                        addLog("      Args: " .. argString, Color3.fromRGB(200, 255, 200))
                    end
                end
            end
        end
        
        return oldNamecall(self, ...)
    end))
end)
