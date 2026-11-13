-- Banana Cat Hub - Clean & Simple Auto Farm UI
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

-- Konfigurasi Utama / Settings
getgenv().BananaCatConfig = {
    AutoFarm = false,
    WeaponSelection = "Melee",
    TweenSpeed = 350
}

-- Fungsi Asli Blox Fruits untuk Mengecek & Mengambil Quest
local function GetQuest()
    local level = LocalPlayer.Data.Level.Value
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes and remotes:FindFirstChild("CommF_") then
            if level then
                -- Logika pemanggilan quest otomatis berdasarkan level
                -- remotes.CommF_:InvokeServer("StartQuest", "QuestName", 1)
            end
        end
    end)
end

-- Fungsi Pergerakan Tween
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

-- UI SEDERHANA: Hanya Tombol Saklar Auto Farm
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BananaCatSimpleUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Tombol Saklar Utama di Layar
local toggleFarmButton = Instance.new("TextButton")
toggleFarmButton.Size = UDim2.new(0, 180, 0, 45)
toggleFarmButton.Position = UDim2.new(0, 40, 0, 40)
toggleFarmButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50) -- Merah (OFF)
toggleFarmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleFarmButton.TextSize = 14
toggleFarmButton.Font = Enum.Font.SourceSansBold
toggleFarmButton.Text = "Auto Farm: OFF"
toggleFarmButton.Parent = screenGui

-- Interaksi Klik Saklar
toggleFarmButton.MouseButton1Click:Connect(function()
    getgenv().BananaCatConfig.AutoFarm = not getgenv().BananaCatConfig.AutoFarm
    if getgenv().BananaCatConfig.AutoFarm then
        toggleFarmButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50) -- Hijau (ON)
        toggleFarmButton.Text = "Auto Farm: ON"
    else
        toggleFarmButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50) -- Merah (OFF)
        toggleFarmButton.Text = "Auto Farm: OFF"
    end
end)

-- Loop Utama Eksekusi Auto Farm
task.spawn(function()
    while task.wait(0.5) do
        if getgenv().BananaCatConfig.AutoFarm then
            pcall(function()
                GetQuest()
                -- Logika penyerangan dan pergerakan target dijalankan di sini
            end)
        end
    end
end)
