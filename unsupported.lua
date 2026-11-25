-- Levian Hub: UI "Game not support yet" + tombol Request game script
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

local WEBHOOK = "https://discord.com/api/webhooks/1575117203991429192/ZK7TiZps6bdpN_umQ9s2TU4uzBhx86qbyKz8RUcOOPIw1Kcuoj32v18jaH-yh9DuSrzQ"
local DISCORD = "https://discord.gg/Mc2YpMT2cF"
local PLACE_ID = game.PlaceId

-- Simpan status "sudah request" selama sesi (anti spam)
local env = (getgenv and getgenv()) or _G
env.LevianRequested = env.LevianRequested or {}

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

local old = parent:FindFirstChild("LevianNotSupported")
if old then old:Destroy() end

local C_LIGHT = Color3.fromRGB(205, 160, 255)
local C_DARK = Color3.fromRGB(135, 65, 245)

local gui = Instance.new("ScreenGui")
gui.Name = "LevianNotSupported"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999998
gui.Parent = parent

-- Kotak lonjong
local box = Instance.new("Frame")
box.AnchorPoint = Vector2.new(0.5, 0)
box.Position = UDim2.new(0.5, 0, 0, -160)
box.Size = UDim2.fromOffset(320, 122)
box.BackgroundColor3 = Color3.fromRGB(16, 10, 27)
box.BorderSizePixel = 0
box.Parent = gui

local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 30)
boxCorner.Parent = box

local boxStroke = Instance.new("UIStroke")
boxStroke.Color = Color3.fromRGB(170, 100, 255)
boxStroke.Thickness = 1.5
boxStroke.Transparency = 0.35
boxStroke.Parent = box

-- Skala otomatis (PC / HP)
local cam = workspace.CurrentCamera
local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
local uiScale = Instance.new("UIScale")
uiScale.Scale = math.clamp(math.min(vp.X * 0.92 / 320, 1.15), 0.75, 1.15)
uiScale.Parent = box

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(0, 14)
title.Size = UDim2.new(1, 0, 0, 24)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Game not support yet"
title.Parent = box

local caption = Instance.new("TextLabel")
caption.BackgroundTransparency = 1
caption.Position = UDim2.fromOffset(0, 40)
caption.Size = UDim2.new(1, 0, 0, 16)
caption.Font = Enum.Font.GothamMedium
caption.TextSize = 12
caption.TextColor3 = Color3.fromRGB(165, 155, 190)
caption.Text = "Game ID: " .. tostring(PLACE_ID)
caption.Parent = box

-- Tombol close kecil
local close = Instance.new("TextButton")
close.BackgroundTransparency = 1
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -16, 0, 12)
close.Size = UDim2.fromOffset(22, 22)
close.Font = Enum.Font.GothamBold
close.TextSize = 14
close.TextColor3 = Color3.fromRGB(165, 155, 190)
close.Text = "X"
close.AutoButtonColor = false
close.Parent = box

-- Tombol "Request game script"
local btn = Instance.new("TextButton")
btn.AnchorPoint = Vector2.new(0.5, 0)
btn.Position = UDim2.new(0.5, 0, 0, 70)
btn.Size = UDim2.fromOffset(230, 38)
btn.BackgroundColor3 = Color3.new(1, 1, 1)
btn.BorderSizePixel = 0
btn.AutoButtonColor = false
btn.Font = Enum.Font.GothamBold
btn.TextSize = 14
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Text = "Request game script"
btn.Parent = box
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = btn
	local g = Instance.new("UIGradient")
	g.Rotation = 0
	g.Color = ColorSequence.new(C_LIGHT, C_DARK)
	g.Parent = btn
end

-- Label pengganti: "Already sent request"
local done = Instance.new("TextLabel")
done.AnchorPoint = Vector2.new(0.5, 0)
done.Position = UDim2.new(0.5, 0, 0, 70)
done.Size = UDim2.fromOffset(230, 38)
done.BackgroundColor3 = Color3.fromRGB(34, 24, 54)
done.BackgroundTransparency = 1
done.BorderSizePixel = 0
done.Font = Enum.Font.GothamBold
done.TextSize = 14
done.TextColor3 = Color3.fromRGB(205, 195, 230)
done.TextTransparency = 1
done.Text = "Already sent request"
done.Visible = false
done.Parent = box
do
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = done
end

local function showDone(animated)
	done.Visible = true
	if animated then
		tween(btn, 0.25, {BackgroundTransparency = 1, TextTransparency = 1}).Completed:Wait()
		btn.Visible = false
		tween(done, 0.3, {BackgroundTransparency = 0, TextTransparency = 0})
	else
		btn.Visible = false
		done.BackgroundTransparency = 0
		done.TextTransparency = 0
	end
end

-- Salin link Discord
local function copyDiscord()
	local copier = setclipboard or toclipboard or (Clipboard and Clipboard.set)
	if copier then
		local ok = pcall(copier, DISCORD)
		return ok
	end
	return false
end

-- Kirim webhook (id game)
local function sendWebhook()
	local req = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
	if not req then return false end

	local name = "Unknown"
	pcall(function()
		name = MarketplaceService:GetProductInfo(PLACE_ID).Name
	end)

	local payload = {
		username = "Levian Hub",
		embeds = {{
			title = "New game script request",
			color = 0x9B6BFF,
			fields = {
				{name = "Game ID (PlaceId)", value = tostring(PLACE_ID), inline = true},
				{name = "Game Name", value = tostring(name), inline = true},
				{name = "Link", value = "https://www.roblox.com/games/" .. tostring(PLACE_ID), inline = false},
			},
		}},
	}

	local ok, res = pcall(req, {
		Url = WEBHOOK,
		Method = "POST",
		Headers = {["Content-Type"] = "application/json"},
		Body = HttpService:JSONEncode(payload),
	})
	if not ok or not res then return false end
	local code = res.StatusCode or 0
	return res.Success == true or (code >= 200 and code < 300)
end

local busy = false
btn.MouseButton1Click:Connect(function()
	if busy then return end
	busy = true

	local copied = copyDiscord()
	if copied then caption.Text = "Discord link copied" end
	btn.Text = "Sending..."

	if sendWebhook() then
		env.LevianRequested[PLACE_ID] = true
		showDone(true)
	else
		btn.Text = "Failed, tap to retry"
		task.wait(1.5)
		btn.Text = "Request game script"
		busy = false
	end
end)

close.MouseButton1Click:Connect(function()
	tween(box, 0.35, {Position = UDim2.new(0.5, 0, 0, -160)}, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed:Wait()
	gui:Destroy()
end)

-- Kalau game ini sudah pernah di-request di sesi ini
if env.LevianRequested[PLACE_ID] then
	busy = true
	showDone(false)
end

-- Muncul dari atas
tween(box, 0.6, {Position = UDim2.new(0.5, 0, 0, 56)}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
