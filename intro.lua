-- Levian Hub Intro (responsive: PC & HP)
-- Alur: layar hitam -> "Levian Hub" (gradient) -> L & H menyatu jadi logo
--       -> logo mengecil & terbang ke tombol bulat LevianUI
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local GuiService = game:GetService("GuiService")
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
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)
gui.Parent = parent

-- Warna gradient (sama dengan logo)
local C_LIGHT = Color3.fromRGB(205, 160, 255)
local C_DARK = Color3.fromRGB(135, 65, 245)
local function colorAt(t)
	return C_LIGHT:Lerp(C_DARK, math.clamp(t, 0, 1))
end

-- 1. Layar hitam
local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.new(0, 0, 0)
bg.BackgroundTransparency = 1
bg.BorderSizePixel = 0
bg.Active = true
bg.Parent = gui

-- Glow biru tipis di pinggir layar (4 sisi, memudar ke tengah)
local edgeVp = bg.AbsoluteSize
if edgeVp.X < 100 or edgeVp.Y < 100 then
	local cam = workspace.CurrentCamera
	edgeVp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
end
local EDGE = math.floor(math.min(edgeVp.X, edgeVp.Y) * 0.1) -- tebal glow
local EDGE_COLOR = Color3.fromRGB(70, 130, 255)
local edges = {}
local function edge(pos, size, rot)
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = size
	f.BorderSizePixel = 0
	f.BackgroundColor3 = EDGE_COLOR
	f.BackgroundTransparency = 1
	f.ZIndex = 2
	f.Active = false
	f.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6), -- tepi layar: samar
		NumberSequenceKeypoint.new(1, 1),   -- ke tengah: hilang
	})
	g.Parent = f
	table.insert(edges, f)
end
edge(UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, EDGE), 90)                       -- atas
edge(UDim2.new(0, 0, 1, -EDGE), UDim2.new(1, 0, 0, EDGE), -90)                   -- bawah
edge(UDim2.fromOffset(0, 0), UDim2.new(0, EDGE, 1, 0), 0)                        -- kiri
edge(UDim2.new(1, -EDGE, 0, 0), UDim2.new(0, EDGE, 1, 0), 180)                   -- kanan

for _, e in ipairs(edges) do
	tween(e, 0.8, {BackgroundTransparency = 0}, Enum.EasingStyle.Sine)
end
tween(bg, 0.8, {BackgroundTransparency = 0}).Completed:Wait()

-- Ukuran layar (otomatis PC / HP)
local vp = bg.AbsoluteSize
if vp.X < 100 or vp.Y < 100 then
	local cam = workspace.CurrentCamera
	vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
end
local center = vp / 2

-- 2. Tulisan "Levian Hub" (posisi dihitung manual, warna gradient menyambung)
local TEXT = "Levian Hub"
local FONT = Enum.Font.GothamBold
local GAP = 2

local U = math.clamp(math.min(vp.X, vp.Y) / 720, 0.5, 1.5)
local textSize = math.floor(56 * U)

local function measure(size)
	local widths, total = {}, 0
	for i = 1, #TEXT do
		local w = TextService:GetTextSize(TEXT:sub(i, i), size, FONT, Vector2.new(1000, 1000)).X
		widths[i] = w
		total = total + w
	end
	total = total + GAP * (#TEXT - 1)
	return widths, total
end

local widths, totalW = measure(textSize)
local maxW = vp.X * 0.88
if totalW > maxW then
	textSize = math.max(14, math.floor(textSize * maxW / totalW))
	widths, totalW = measure(textSize)
end

local labelH = math.floor(textSize * 1.25)
local letters, baseSizes = {}, {}
local startX = center.X - totalW / 2
local x = startX
for i = 1, #TEXT do
	local w = widths[i]
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = TEXT:sub(i, i)
	l.Font = FONT
	l.TextSize = textSize
	l.TextColor3 = Color3.new(1, 1, 1) -- putih supaya warna gradient tampil asli
	l.TextTransparency = 1
	l.TextWrapped = false
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = UDim2.fromOffset(w, labelH)
	l.Position = UDim2.fromOffset(x + w / 2, center.Y)
	l.ZIndex = 3
	l.Parent = bg

	-- gradient menyambung dari huruf pertama sampai terakhir
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(
		colorAt((x - startX) / totalW),
		colorAt((x + w - startX) / totalW)
	)
	g.Parent = l

	letters[i] = l
	baseSizes[i] = Vector2.new(w, labelH)
	x = x + w + GAP
end

for i, l in ipairs(letters) do
	task.delay(i * 0.08, function()
		tween(l, 0.45, {TextTransparency = 0}, Enum.EasingStyle.Sine)
	end)
end
task.wait(#letters * 0.08 + 0.9)

-- 3. Siapkan logo (di dalam group supaya bisa mengecil + terbang sekaligus)
local S = math.clamp(math.min(vp.X * 0.5 / 204, vp.Y * 0.5 / 275), 0.4, 1.6)
local GSIZE = 640 * S -- ukuran group (logo = ~43% dari lingkaran, sama seperti ikon bulat)

local group = Instance.new("Frame")
group.BackgroundTransparency = 1
group.AnchorPoint = Vector2.new(0.5, 0.5)
group.Position = UDim2.fromOffset(center.X, center.Y)
group.Size = UDim2.fromOffset(GSIZE, GSIZE)
group.ZIndex = 1
group.Parent = bg

local gscale = Instance.new("UIScale")
gscale.Scale = 1
gscale.Parent = group

-- Lingkaran gelap (muncul saat logo menuju tombol bulat)
local circle = Instance.new("Frame")
circle.AnchorPoint = Vector2.new(0.5, 0.5)
circle.Position = UDim2.fromOffset(GSIZE / 2 - 5 * S, GSIZE / 2 - 10 * S)
circle.Size = UDim2.fromOffset(560 * S, 560 * S)
circle.BackgroundColor3 = Color3.fromRGB(16, 10, 27)
circle.BackgroundTransparency = 1
circle.BorderSizePixel = 0
circle.Parent = group
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = circle
end

local logo = Instance.new("Frame")
logo.BackgroundTransparency = 1
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromOffset(GSIZE / 2, GSIZE / 2)
logo.Size = UDim2.fromOffset(204 * S, 275 * S)
logo.Parent = group

local glowHolder = Instance.new("Frame")
glowHolder.BackgroundTransparency = 1
glowHolder.Size = UDim2.fromScale(1, 1)
glowHolder.Parent = logo

local barHolder = Instance.new("Frame")
barHolder.BackgroundTransparency = 1
barHolder.Size = UDim2.fromScale(1, 1)
barHolder.Parent = logo

local bars, glows = {}, {}
local function bar(cx, cy, w, h, rot)
	-- lapisan glow (lembut, di belakang)
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromOffset(cx * S, cy * S)
	glow.Size = UDim2.fromOffset((w + 18) * S, (h + 18) * S)
	glow.Rotation = rot or 0
	glow.BorderSizePixel = 0
	glow.BackgroundColor3 = Color3.fromRGB(160, 90, 255)
	glow.BackgroundTransparency = 1
	glow.Parent = glowHolder
	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(0.5, 0)
	gc.Parent = glow
	table.insert(glows, glow)

	-- batang logo
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
	g.Color = ColorSequence.new(C_LIGHT, C_DARK)
	g.Parent = f

	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(170, 100, 255)
	st.Thickness = math.max(2, 4 * S)
	st.Transparency = 1
	st.Parent = f

	f.Parent = barHolder
	table.insert(bars, {frame = f, stroke = st})
end

bar(13, 92, 26, 185)           -- L: garis tegak kiri
bar(102, 166.5, 204, 26, -2.9) -- garis horizontal
bar(96.5, 162.5, 26, 197)      -- H: tegak tengah
bar(179.5, 186, 26, 178)       -- H: tegak kanan
bar(96.5, 167, 17, 17, 0)      -- titik tengah

-- 4. L & H bergeser menyatu ke posisi logo (halus), huruf lain memudar
local topLeft = Vector2.new(center.X - 102 * S, center.Y - 137.5 * S)
local Lidx, Hidx = 1, 8

for i, l in ipairs(letters) do
	if i ~= Lidx and i ~= Hidx then
		tween(l, 0.7, {TextTransparency = 1}, Enum.EasingStyle.Sine)
	end
end
task.wait(0.25)

local targetTextSize = math.floor(75 * S)
local ratio = targetTextSize / textSize
local MOVE_T = 1.5
local move = TweenInfo.new(MOVE_T, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut)

TweenService:Create(letters[Lidx], move, {
	Position = UDim2.fromOffset(topLeft.X + 13 * S, topLeft.Y + 92 * S),
	TextSize = targetTextSize,
	Size = UDim2.fromOffset(baseSizes[Lidx].X * ratio, baseSizes[Lidx].Y * ratio),
}):Play()
TweenService:Create(letters[Hidx], move, {
	Position = UDim2.fromOffset(topLeft.X + 138 * S, topLeft.Y + 175 * S),
	TextSize = targetTextSize,
	Size = UDim2.fromOffset(baseSizes[Hidx].X * ratio, baseSizes[Hidx].Y * ratio),
}):Play()

-- Crossfade: logo menyala pelan selagi huruf L & H hampir sampai
task.wait(MOVE_T * 0.55)
local SOFT = Enum.EasingStyle.Sine
tween(letters[Lidx], 0.9, {TextTransparency = 1}, SOFT, Enum.EasingDirection.InOut)
tween(letters[Hidx], 0.9, {TextTransparency = 1}, SOFT, Enum.EasingDirection.InOut)
for _, b in ipairs(bars) do
	tween(b.frame, 0.9, {BackgroundTransparency = 0}, SOFT, Enum.EasingDirection.InOut)
	tween(b.stroke, 0.9, {Transparency = 0.7}, SOFT, Enum.EasingDirection.InOut)
end
for _, g in ipairs(glows) do
	tween(g, 1.1, {BackgroundTransparency = 0.88}, SOFT, Enum.EasingDirection.InOut)
end
task.wait(MOVE_T * 0.45 + 0.5)

-- Denyut glow sekali (nafas)
for _, g in ipairs(glows) do
	TweenService:Create(g, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true), {
		BackgroundTransparency = 0.78,
	}):Play()
end
task.wait(1.5)

-- 5. Logo mengecil & terbang ke tombol bulat LevianUI (kiri layar)
local inset = Vector2.new(0, 36)
pcall(function()
	local tl = GuiService:GetGuiInset()
	inset = tl
end)
-- Tombol bulat: ukuran 40x40, Position (0,10, 0.4,0) di ScreenGui yang menghormati inset
local fabCenter = Vector2.new(10 + 20, inset.Y + 0.4 * (vp.Y - inset.Y) + 20)
local endScale = 40 / GSIZE

local fly = TweenInfo.new(1.4, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut)
TweenService:Create(group, fly, {Position = UDim2.fromOffset(fabCenter.X, fabCenter.Y)}):Play()
TweenService:Create(gscale, fly, {Scale = endScale}):Play()

tween(circle, 0.9, {BackgroundTransparency = 0}, SOFT, Enum.EasingDirection.InOut)
for _, g in ipairs(glows) do
	tween(g, 0.6, {BackgroundTransparency = 1}, SOFT)
end
for _, b in ipairs(bars) do
	tween(b.stroke, 0.6, {Transparency = 1}, SOFT)
end
-- layar tetap hitam selama logo terbang; tunggu sampai logo mendarat
task.wait(1.45)

-- 6. Logo sudah di posisi: tunggu tombol bulat asli muncul (maks 4 detik)
local function fabExists()
	local getters = {
		function() return gethui() end,
		function() return game:GetService("CoreGui") end,
		function() return Players.LocalPlayer:FindFirstChild("PlayerGui") end,
	}
	for _, get in ipairs(getters) do
		local ok, root = pcall(get)
		if ok and root and root:FindFirstChild("LevianUI Toggle") then
			return true
		end
	end
	return false
end

local t0 = os.clock()
while not fabExists() and os.clock() - t0 < 4 do
	task.wait(0.1)
end
task.wait(0.15)

-- 7. Logo dan layar hitam (plus glow pinggir) hilang BERSAMAAN
local FADE_T = 1.1
local FADE = Enum.EasingDirection.InOut
tween(bg, FADE_T, {BackgroundTransparency = 1}, SOFT, FADE)
for _, e in ipairs(edges) do
	tween(e, FADE_T, {BackgroundTransparency = 1}, SOFT, FADE)
end
tween(circle, FADE_T, {BackgroundTransparency = 1}, SOFT, FADE)
for _, b in ipairs(bars) do
	tween(b.frame, FADE_T, {BackgroundTransparency = 1}, SOFT, FADE)
end
task.wait(FADE_T + 0.1)
gui:Destroy()
