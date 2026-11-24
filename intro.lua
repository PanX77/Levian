-- Levian Hub Intro
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- Parent GUI (aman untuk executor)
local parent
pcall(function() parent = gethui and gethui() end)
if not parent then
	pcall(function() parent = game:GetService("CoreGui") end)
end
if not parent then parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

local gui = Instance.new("ScreenGui")
gui.Name = "LevianIntro"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.Parent = parent

-- 1. Layar hitam
local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.new(0, 0, 0)
bg.BackgroundTransparency = 1
bg.BorderSizePixel = 0
bg.Active = true
bg.Parent = gui
tween(bg, 0.8, {BackgroundTransparency = 0}).Completed:Wait()

-- 2. Tulisan "Levian Hub" (per huruf)
local TEXT = "Levian Hub"
local PURPLE = Color3.fromRGB(190, 140, 255)

local holder = Instance.new("Frame")
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.fromScale(0.5, 0.5)
holder.AutomaticSize = Enum.AutomaticSize.XY
holder.Parent = bg

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 2)
layout.Parent = holder

local letters = {}
for i = 1, #TEXT do
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = TEXT:sub(i, i)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 56
	l.TextColor3 = PURPLE
	l.TextTransparency = 1
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, 60)
	l.LayoutOrder = i
	l.Parent = holder
	letters[i] = l
end

RunService.RenderStepped:Wait()
RunService.RenderStepped:Wait()

-- Bekukan posisi tiap huruf supaya bisa digerakkan bebas
for _, l in ipairs(letters) do
	local pos, size = l.AbsolutePosition, l.AbsoluteSize
	l.AutomaticSize = Enum.AutomaticSize.None
	l.Size = UDim2.fromOffset(size.X, size.Y)
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Position = UDim2.fromOffset(pos.X + size.X / 2, pos.Y + size.Y / 2)
	l.Parent = bg
end
holder:Destroy()

for i, l in ipairs(letters) do
	task.delay(i * 0.08, function()
		tween(l, 0.4, {TextTransparency = 0})
	end)
end
task.wait(#letters * 0.08 + 1)

-- 3. Susun logo dari Frame
local S = 1.2 -- ukuran logo (ubah sesuka kamu)
local center = bg.AbsoluteSize / 2

local logo = Instance.new("Frame")
logo.BackgroundTransparency = 1
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromOffset(center.X, center.Y)
logo.Size = UDim2.fromOffset(204 * S, 275 * S)
logo.Parent = bg

local bars = {}
local function bar(cx, cy, w, h, rot, isDot)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(cx * S, cy * S)
	f.Size = UDim2.fromOffset(w * S, h * S)
	f.Rotation = rot or 0
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 1

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f

	local g = Instance.new("UIGradient")
	g.Rotation = 65
	g.Color = ColorSequence.new(Color3.fromRGB(205, 160, 255), Color3.fromRGB(135, 65, 245))
	g.Parent = f

	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(170, 100, 255)
	st.Thickness = 4
	st.Transparency = 1
	st.Parent = f

	f.Parent = logo
	table.insert(bars, {frame = f, stroke = st, dot = isDot})
	return f
end

bar(13, 92, 26, 185)            -- L: garis tegak kiri
bar(102, 166.5, 204, 26, -2.9)  -- garis horizontal
bar(96.5, 162.5, 26, 197)       -- H: tegak tengah
bar(179.5, 186, 26, 178)        -- H: tegak kanan
bar(96.5, 167, 17, 17, 0, true) -- titik tengah

-- Target huruf L dan H di posisi logo
local topLeft = Vector2.new(center.X - 102 * S, center.Y - 137.5 * S)
local Lidx, Hidx = 1, 8

for i, l in ipairs(letters) do
	if i ~= Lidx and i ~= Hidx then
		tween(l, 0.6, {TextTransparency = 1})
	end
end
task.wait(0.4)

local move = TweenInfo.new(1, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
TweenService:Create(letters[Lidx], move, {
	Position = UDim2.fromOffset(topLeft.X + 13 * S, topLeft.Y + 92 * S),
	TextSize = 90,
}):Play()
TweenService:Create(letters[Hidx], move, {
	Position = UDim2.fromOffset(topLeft.X + 138 * S, topLeft.Y + 175 * S),
	TextSize = 90,
}):Play()

task.wait(0.7)

-- Letter memudar, logo menyala
tween(letters[Lidx], 0.5, {TextTransparency = 1})
tween(letters[Hidx], 0.5, {TextTransparency = 1})
for _, b in ipairs(bars) do
	tween(b.frame, 0.6, {BackgroundTransparency = 0})
	tween(b.stroke, 0.6, {Transparency = 0.65})
end
task.wait(1.8)

-- 4. Keluar
for _, b in ipairs(bars) do
	tween(b.frame, 0.6, {BackgroundTransparency = 1})
	tween(b.stroke, 0.6, {Transparency = 1})
end
tween(bg, 0.8, {BackgroundTransparency = 1}).Completed:Wait()
gui:Destroy()
