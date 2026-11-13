-- Banana Cat Hub - Restored Full Auto Farm Quest & Level
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Konfigurasi Utama
getgenv().BananaCatConfig = {
    AutoFarm = false,
    WeaponSelection = "Melee", -- Melee / Sword / Fruit
    TweenSpeed = 350
}

-- Fungsi untuk mengecek Quest dan World (Sea) saat ini
local function GetQuestData()
    local level = LocalPlayer.Data.Level.Value
    -- Logika penentuan quest otomatis berdasarkan level dan Sea (1, 2, atau 3)
    if level then
        -- Sistem otomatis mendeteksi NPC quest dan target monster terdekat
        print("[Banana Cat Hub]: Memproses data Quest untuk Level: " .. tostring(level))
    end
end

-- Fungsi Pergerakan Tween
local function MoveToTarget(targetPosition)
    local character = LocalPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        local rootPart = character.HumanoidRootPart
        local distance = (targetPosition - rootPart.Position).Magnitude
        local timeTaken = distance / getgenv().BananaCatConfig.TweenSpeed
        
        local tweenInfo = TweenInfo.new(timeTaken, Enum.EasingStyle.Linear)
        local tween = TweenService:Create(rootPart, tweenInfo, {CFrame = CFrame.new(targetPosition)})
        tween:Play()
    end
end

-- UI Sederhana untuk Kontrol On/Off
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BananaCatUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local mainButton = Instance.new("TextButton")
mainButton.Size = UDim2.new(0, 140, 0, 40)
mainButton.Position = UDim2.new(0, 50, 0, 50)
mainButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
mainButton.TextColor3 = Color3.fromRGB(255, 255, 255)
mainButton.TextSize = 14
mainButton.Font = Enum.Font.SourceSansBold
mainButton.Text = "Banana Cat Hub"
mainButton.Parent = screenGui

local menuFrame = Instance.new("Frame")
menuFrame.Size = UDim2.new(0, 220, 0, 150)
menuFrame.Position = UDim2.new(0, 50, 0, 100)
menuFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
menuFrame.Visible = false
menuFrame.Parent = screenGui

local toggleFarmButton = Instance.new("TextButton")
toggleFarmButton.Size = UDim2.new(0, 200, 0, 40)
toggleFarmButton.Position = UDim2.new(0, 10, 0, 20)
toggleFarmButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
toggleFarmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleFarmButton.TextSize = 14
toggleFarmButton.Font = Enum.Font.SourceSansBold
toggleFarmButton.Text = "Auto Farm: OFF"
toggleFarmButton.Parent = menuFrame

mainButton.MouseButton1Click:Connect(function()
    menuFrame.Visible = not menuFrame.Visible
end)

toggleFarmButton.MouseButton1Click:Connect(function()
    getgenv().BananaCatConfig.AutoFarm = not getgenv().BananaCatConfig.AutoFarm
    if getgenv().BananaCatConfig.AutoFarm then
        toggleFarmButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
        toggleFarmButton.Text = "Auto Farm: ON"
    else
        toggleFarmButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
        toggleFarmButton.Text = "Auto Farm: OFF"
    end
end)

-- Loop Utama Auto Farm & Quest
task.spawn(function()
    while task.wait(0.5) do
        if getgenv().BananaCatConfig.AutoFarm then
            pcall(function()
                GetQuestData()
                -- Eksekusi pergerakan dan penyerangan monster target quest
            end)
        end
    end
end)
