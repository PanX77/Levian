-- Banana Cat Hub - Auto Farm dengan Simple UI
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local TweenService = game:GetService("TweenService")

-- Status Konfigurasi
getgenv().BananaCatConfig = {
    AutoFarm = false,
    TweenSpeed = 350
}

-- MEMBUAT UI SEDERHANA DI LAYAR GAME
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BananaCatUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Membuat Tombol Utama (Floating Button) untuk membuka/tutup menu
local mainButton = Instance.new("TextButton")
mainButton.Name = "ToggleMenu"
mainButton.Size = UDim2.new(0, 140, 0, 40)
mainButton.Position = UDim2.new(0, 50, 0, 50)
mainButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
mainButton.TextColor3 = Color3.fromRGB(255, 255, 255)
mainButton.TextSize = 14
mainButton.Font = Enum.Font.SourceSansBold
mainButton.Text = "Banana Cat Hub"
mainButton.Parent = screenGui

-- Membuat Panel Menu Utama
local menuFrame = Instance.new("Frame")
menuFrame.Name = "MenuFrame"
menuFrame.Size = UDim2.new(0, 220, 0, 150)
menuFrame.Position = UDim2.new(0, 50, 0, 100)
menuFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
menuFrame.Visible = false -- Awalnya disembunyikan
menuFrame.Parent = screenGui

-- Tombol Saklar (Toggle) Auto Farm di dalam UI
local toggleFarmButton = Instance.new("TextButton")
toggleFarmButton.Name = "ToggleFarm"
toggleFarmButton.Size = UDim2.new(0, 200, 0, 40)
toggleFarmButton.Position = UDim2.new(0, 10, 0, 20)
toggleFarmButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50) -- Merah (Mati)
toggleFarmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleFarmButton.TextSize = 14
toggleFarmButton.Font = Enum.Font.SourceSansBold
toggleFarmButton.Text = "Auto Farm: OFF"
toggleFarmButton.Parent = menuFrame

-- Fungsi Klik Tombol Utama untuk Menampilkan/Menyembunyikan Menu
mainButton.MouseButton1Click:Connect(function()
    menuFrame.Visible = not menuFrame.Visible
end)

-- Fungsi Klik Saklar Auto Farm
toggleFarmButton.MouseButton1Click:Connect(function()
    getgenv().BananaCatConfig.AutoFarm = not getgenv().BananaCatConfig.AutoFarm
    if getgenv().BananaCatConfig.AutoFarm then
        toggleFarmButton.BackgroundColor3 = Color3.fromRGB(50, 180, 50) -- Hijau (Nyala)
        toggleFarmButton.Text = "Auto Farm: ON"
    else
        toggleFarmButton.BackgroundColor3 = Color3.fromRGB(180, 50, 50) -- Merah (Mati)
        toggleFarmButton.Text = "Auto Farm: OFF"
    end
end)

-- LOGIKA UTAMA AUTO FARM
task.spawn(function()
    while task.wait(0.5) do
        if getgenv().BananaCatConfig.AutoFarm then
            pcall(function()
                print("[Banana Cat Hub]: Menjalankan Auto Farm...")
                -- Logika pergerakan / farm level di sini
            end)
        end
    end
end)
