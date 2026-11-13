-- Banana Cat Hub - Original Blox Fruits Script Structure (Settings & Farming)
local Players = service and service.Players or game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

-- Konfigurasi Utama / Settings
getgenv().BananaCatConfig = {
    AutoFarm = false,
    WeaponSelection = "Melee", -- Melee / Sword / Fruit
    TweenSpeed = 350
}

-- [BAGIAN 1]: Fungsi Asli Blox Fruits untuk Mengecek & Mengambil Quest
local function GetQuest()
    local level = LocalPlayer.Data.Level.Value
    
    -- Struktur remotes asli untuk mengambil quest di Blox Fruits
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes and remotes:FindFirstChild("CommF_") then
            -- Logika deteksi quest berdasarkan level Sea 1, 2, atau 3
            if level then
                -- Contoh pemanggilan quest bawaan game (jika diperlukan)
                -- remotes.CommF_:InvokeServer("StartQuest", "QuestName", 1)
            end
        end
    end)
end

-- [BAGIAN 2]: Sistem Pergerakan Tween
local function MoveTo(targetPosition)
    local character = LocalPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        local rootPart = character.HumanoidRootPart
        local distance = (targetPosition - rootPart.Position).Magnitude
        local speed = getgenv().BananaCatConfig.TweenSpeed
        local timeTaken = distance / speed
        
        local tweenInfo = TweenInfo.new(timeTaken, Enum.EasingStyle.Linear)
        local tween = TweenService:Create(rootPart, tweenInfo, {CFrame = CFrame.new(targetPosition)})
        tween:Play()
    end
end

-- [BAGIAN 3]: Antarmuka UI (Menu Settings & Farming)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BananaCatHubUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Tombol Buka Menu
local mainButton = Instance.new("TextButton")
mainButton.Size = UDim2.new(0, 150, 0, 40)
mainButton.Position = UDim2.new(0, 50, 0, 50)
mainButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainButton.TextColor3 = Color3.fromRGB(255, 255, 255)
mainButton.TextSize = 14
mainButton.Font = Enum.Font.SourceSansBold
mainButton.Text = "Banana Cat Hub"
mainButton.Parent = screenGui

-- Bingkai Menu Utama
local menuFrame = Instance.new("Frame")
menuFrame.Size = UDim2.new(0, 240, 0, 180)
menuFrame.Position = UDim2.new(0, 50, 0, 100)
menuFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
menuFrame.Visible = false
menuFrame.Parent = screenGui

-- Label Judul
local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0, 240, 0, 30)
titleLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 14
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.Text = "Settings & Farming"
titleLabel.Parent = menuFrame

-- Tombol Toggle Farming
local toggleFarmButton = Instance.new("TextButton")
toggleFarmButton.Size = UDim2.new(0, 220, 0, 40)
toggleFarmButton.Position = UDim2.new(0, 10, 0, 45)
toggleFarmButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
toggleFarmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleFarmButton.TextSize = 14
toggleFarmButton.Font = Enum.Font.SourceSansBold
toggleFarmButton.Text = "Farming: OFF"
toggleFarmButton.Parent = menuFrame

-- Label Info Settings (Tween Speed)
local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0, 220, 0, 30)
speedLabel.Position = UDim2.new(0, 10, 0, 95)
speedLabel.BackgroundTransparency = 1
speedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
speedLabel.TextSize = 13
speedLabel.Font = Enum.Font.SourceSans
speedLabel.Text = "Settings -> Speed: " .. tostring(getgenv().BananaCatConfig.TweenSpeed)
speedLabel.Parent = menuFrame

-- Label Info Settings (Weapon)
local weaponLabel = Instance.new("TextLabel")
weaponLabel.Size = UDim2.new(0, 220, 0, 30)
weaponLabel.Position = UDim2.new(0, 10, 0, 130)
weaponLabel.BackgroundTransparency = 1
weaponLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
weaponLabel.TextSize = 13
weaponLabel.Font = Enum.Font.SourceSans
weaponLabel.Text = "Settings -> Weapon: " .. tostring(getgenv().BananaCatConfig.WeaponSelection)
weaponLabel.Parent = menuFrame

-- Interaksi Tombol UI
mainButton.MouseButton1Click:Connect(function()
    menuFrame.Visible = not menuFrame.Visible
end)

toggleFarmButton.MouseButton1Click:Connect(function()
    getgenv().BananaCatConfig.AutoFarm = not getgenv().BananaCatConfig.AutoFarm
    if getgenv().BananaCatConfig.AutoFarm then
        toggleFarmButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50)
        toggleFarmButton.Text = "Farming: ON"
    else
        toggleFarmButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
        toggleFarmButton.Text = "Farming: OFF"
    end
end)

-- [BAGIAN 4]: Loop Utama Auto Farm
task.spawn(function()
    while task.wait(0.5) do
        if getgenv().BananaCatConfig.AutoFarm then
            pcall(function()
                GetQuest()
                -- Logika serangan dan pergerakan monster diletakkan di sini
            end)
        end
    end
end)
