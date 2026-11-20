local Players = game:GetService("Players")
local VIM = game:GetService("VirtualInputManager")
local UIS = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Camera = workspace.CurrentCamera

local player = Players.LocalPlayer

-- Hapus GUI lama jika di-execute ulang
pcall(function()
    local old = CoreGui:FindFirstChild("TapSimGui")
    if old then old:Destroy() end
end)

local state = {
    enabled = false,
    delay = 0.05, -- jeda antar klik (detik)
}

-- Fungsi klik di tengah layar
local function clickScreen()
    local size = Camera.ViewportSize
    local x, y = size.X / 2, size.Y / 2
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
end

-- Loop auto click
task.spawn(function()
    while task.wait(state.delay) do
        if state.enabled then
            pcall(clickScreen)
        end
    end
end)

-- GUI sederhana
local gui = Instance.new("ScreenGui")
gui.Name = "TapSimGui"
gui.ResetOnSpawn = false
gui.Parent = (gethui and gethui()) or CoreGui

local frame = Instance.new("Frame", gui)
frame.Size = UDim2.new(0, 180, 0, 90)
frame.Position = UDim2.new(0, 20, 0.4, 0)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
frame.Active = true
frame.Draggable = true
Instance.new("UICorner", frame)

local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(1, 0, 0, 25)
title.BackgroundTransparency = 1
title.Text = "Tap Simulator Reborn"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 13

local toggle = Instance.new("TextButton", frame)
toggle.Size = UDim2.new(1, -20, 0, 30)
toggle.Position = UDim2.new(0, 10, 0, 30)
toggle.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
toggle.Text = "Auto Click: OFF"
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Font = Enum.Font.Gotham
toggle.TextSize = 13
Instance.new("UICorner", toggle)

local hint = Instance.new("TextLabel", frame)
hint.Size = UDim2.new(1, 0, 0, 20)
hint.Position = UDim2.new(0, 0, 0, 65)
hint.BackgroundTransparency = 1
hint.Text = "Hotkey: tekan F"
hint.TextColor3 = Color3.fromRGB(170, 170, 170)
hint.Font = Enum.Font.Gotham
hint.TextSize = 11

local function refresh()
    toggle.Text = "Auto Click: " .. (state.enabled and "ON" or "OFF")
    toggle.BackgroundColor3 = state.enabled
        and Color3.fromRGB(50, 170, 80)
        or Color3.fromRGB(180, 50, 50)
end

toggle.MouseButton1Click:Connect(function()
    state.enabled = not state.enabled
    refresh()
end)

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F then
        state.enabled = not state.enabled
        refresh()
    end
end)
