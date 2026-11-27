--[[
	Rivals.lua - Levian Hub (versi visual / utilitas, tanpa fitur tempur)

	CREDIT / NOTE:
	Sebagian ide dan potongan logika (kamera, viewmodel, crosshair, lighting,
	config manager) diadaptasi dari open source "zerohub.cc rivals.lua"
	(https://zerohub.cc/rivals.lua). Hak cipta kode asli tetap milik
	para pembuat ZeroHub. Fitur tempur (aimbot, silent aim, ragebot,
	hitbox expander, triggerbot, ESP, dll) sengaja TIDAK disertakan.
	UI: LevianUI.
]]

if game.GameId ~= 6035872082 then
	return
end
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local base = "https://levianstore.my.id/"
local UI = loadstring(game:HttpGet(base .. "LevianUI.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

local CONFIG_DIR = "Levian Hub/Rivals"
local hasFS = type(isfolder) == "function" and type(makefolder) == "function"
	and type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"

---------------------------------------------------------------- state
local State = {
	CustomFOV = 90,
	LockFOV = false,
	ThirdPerson = false,
	ThirdPersonDist = 12,
	ViewmodelOffset = false,
	VMOffsetX = 0,
	VMOffsetY = 0,
	VMOffsetZ = 0,
	Crosshair = false,
	Fullbright = false,
	CustomTime = false,
	TimeOfDay = 12,
	SelectedWrap = "Galaxy",
	AutoWrap = false,
	RainbowVM = false,
}
local Controls = {}
local Connections = {}
local configName = "default"

local function getCam()
	return Workspace.CurrentCamera
end

---------------------------------------------------------------- overlay (crosshair)
local function guiParent()
	return (type(gethui) == "function" and gethui()) or game:GetService("CoreGui")
end

local Overlay = Instance.new("ScreenGui")
Overlay.Name = "LevianRivals_Overlay"
Overlay.IgnoreGuiInset = true
Overlay.ResetOnSpawn = false
Overlay.DisplayOrder = 997
Overlay.Parent = guiParent()

local Cross = Instance.new("Frame")
Cross.BackgroundTransparency = 1
Cross.AnchorPoint = Vector2.new(0.5, 0.5)
Cross.Position = UDim2.fromScale(0.5, 0.5)
Cross.Size = UDim2.fromOffset(18, 18)
Cross.Visible = false
Cross.Parent = Overlay
for _, sz in ipairs({ UDim2.fromOffset(14, 2), UDim2.fromOffset(2, 14) }) do
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(255, 204, 0)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = sz
	f.Parent = Cross
end

---------------------------------------------------------------- helpers
local origAmbient, origBrightness, origFogEnd, origClock =
	Lighting.Ambient, Lighting.Brightness, Lighting.FogEnd, Lighting.ClockTime

local WRAPS = {
	["Galaxy"] = { Color3.fromRGB(115, 65, 255), Enum.Material.ForceField },
	["Neon Emerald"] = { Color3.fromRGB(0, 255, 160), Enum.Material.Neon },
	["Crimson Gold"] = { Color3.fromRGB(255, 55, 85), Enum.Material.Glass },
	["Cyber Ice"] = { Color3.fromRGB(60, 210, 255), Enum.Material.Neon },
	["Obsidian Chrome"] = { Color3.fromRGB(35, 35, 45), Enum.Material.SmoothPlastic },
	["Solar Flare"] = { Color3.fromRGB(255, 165, 20), Enum.Material.ForceField },
}
local wrapNames = {}
for n in pairs(WRAPS) do
	wrapNames[#wrapNames + 1] = n
end
table.sort(wrapNames)

local function styleModel(model, col, mat)
	if not model then
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = d.Name:lower()
			if not (n:find("arm") or n:find("hand") or n:find("glove") or n:find("hum")) then
				d.Color, d.Material = col, mat
			end
		end
	end
end

local function applyWrap(name)
	local w = WRAPS[name]
	if not w then
		return
	end
	pcall(function()
		local vm = Workspace:FindFirstChild("ViewModels")
		if vm then
			for _, m in ipairs(vm:GetChildren()) do
				styleModel(m, w[1], w[2])
			end
		end
	end)
end

local function setThirdPerson(on)
	pcall(function()
		if on then
			LocalPlayer.CameraMode = Enum.CameraMode.Classic
			LocalPlayer.CameraMinZoomDistance = State.ThirdPersonDist
			LocalPlayer.CameraMaxZoomDistance = State.ThirdPersonDist
		else
			LocalPlayer.CameraMaxZoomDistance = 0.5
			LocalPlayer.CameraMinZoomDistance = 0.5
			LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		end
	end)
end

local function setFullbright(on)
	if on then
		Lighting.Ambient = Color3.fromRGB(210, 210, 210)
		Lighting.Brightness = 2.2
		Lighting.FogEnd = 100000
	else
		Lighting.Ambient, Lighting.Brightness, Lighting.FogEnd = origAmbient, origBrightness, origFogEnd
	end
end

---------------------------------------------------------------- UI
local Main = UI.CreateMain({ Title = "Levian Hub", Desc = " | Rivals" })

local function notify(t, d)
	UI.CreateNoti({ Title = t, Desc = d, ShowTime = 3 })
end

local function toggle(section, key, spec, onChange)
	spec.Default = State[key]
	local c = section.CreateToggle(spec, function(v)
		State[key] = v
		if onChange then
			onChange(v)
		end
	end)
	Controls[key] = c
	return c
end

local function slider(section, key, spec, onChange)
	spec.Default = State[key]
	local c = section.CreateSlider(spec, function(v)
		State[key] = v
		if onChange then
			onChange(v)
		end
	end)
	Controls[key] = c
	return c
end

-- Page: Info
local info = Main.CreatePage({ Page_Title = "Info" })
do
	local s = info.CreateSection({ Title = "Server" })
	s.CreateButton({ Title = "Rejoin Server" }, function()
		pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
		end)
	end)
	s.CreateButton({ Title = "Server Hop" }, function()
		task.spawn(function()
			local ok, res = pcall(function()
				return HttpService:JSONDecode(game:HttpGet(
					"https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
				))
			end)
			if ok and res and res.data then
				for _, sv in ipairs(res.data) do
					if sv.playing < sv.maxPlayers and sv.id ~= game.JobId then
						TeleportService:TeleportToPlaceInstance(game.PlaceId, sv.id, LocalPlayer)
						return
					end
				end
			end
			notify("Server Hop", "Tidak ada server lain")
		end)
	end)
	local stat = s.CreateLabel({ Title = "Players: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers })
	s.CreateButton({ Title = "Refresh Info" }, function()
		stat.SetText("Players: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers .. "  |  FPS: " .. math.floor(Workspace:GetRealPhysicsFPS()))
	end)
end

-- Page: View
local view = Main.CreatePage({ Page_Title = "View" })
do
	local cam = view.CreateSection({ Title = "Kamera" })
	slider(cam, "CustomFOV", { Title = "Field of View", Min = 60, Max = 120 }, function(v)
		local c = getCam()
		if c then
			c.FieldOfView = v
		end
	end)
	toggle(cam, "LockFOV", { Title = "Lock FOV", Desc = "Cegah game mereset FOV" })
	toggle(cam, "ThirdPerson", { Title = "Third Person", Desc = "Buka zoom kamera" }, setThirdPerson)
	slider(cam, "ThirdPersonDist", { Title = "Jarak Third Person", Min = 5, Max = 30 }, function()
		if State.ThirdPerson then
			setThirdPerson(true)
		end
	end)

	local vm = view.CreateSection({ Title = "Viewmodel" })
	toggle(vm, "ViewmodelOffset", { Title = "Viewmodel Offset", Desc = "Geser posisi senjata FPS" })
	slider(vm, "VMOffsetX", { Title = "Offset X (x10)", Min = -30, Max = 30 })
	slider(vm, "VMOffsetY", { Title = "Offset Y (x10)", Min = -30, Max = 30 })
	slider(vm, "VMOffsetZ", { Title = "Offset Z (x10)", Min = -30, Max = 30 })

	local env = view.CreateSection({ Title = "Lingkungan & HUD" })
	toggle(env, "Crosshair", { Title = "Custom Crosshair" }, function(v)
		Cross.Visible = v
	end)
	toggle(env, "Fullbright", { Title = "Fullbright", Desc = "Hilangkan bayangan & kabut" }, setFullbright)
	toggle(env, "CustomTime", { Title = "Override Waktu" }, function(v)
		Lighting.ClockTime = v and State.TimeOfDay or origClock
	end)
	slider(env, "TimeOfDay", { Title = "Jam", Min = 0, Max = 24 }, function(v)
		if State.CustomTime then
			Lighting.ClockTime = v
		end
	end)
end

-- Page: Cosmetics
local cos = Main.CreatePage({ Page_Title = "Cosmetics" })
do
	local s = cos.CreateSection({ Title = "Weapon Wrap (client-side)" })
	local dd = s.CreateDropdown({ Title = "Pilih Wrap", List = wrapNames, Default = State.SelectedWrap }, function(v)
		State.SelectedWrap = v
	end)
	Controls.SelectedWrap = dd
	s.CreateButton({ Title = "Apply ke Weapon" }, function()
		applyWrap(State.SelectedWrap)
		notify("Cosmetics", "Wrap " .. State.SelectedWrap .. " diterapkan")
	end)
	toggle(s, "AutoWrap", { Title = "Auto Apply", Desc = "Terapkan terus saat ganti senjata" })
	toggle(s, "RainbowVM", { Title = "Rainbow Viewmodel" })
end

-- Page: Config
local cfg = Main.CreatePage({ Page_Title = "Config" })
do
	local s = cfg.CreateSection({ Title = "Config Manager" })

	local function path()
		return CONFIG_DIR .. "/" .. configName .. ".json"
	end

	s.CreateBox({ Title = "Nama Config", Default = "default", Placeholder = "default" }, function(v)
		v = tostring(v or ""):gsub("[^%w_%-]", "")
		if v ~= "" then
			configName = v
		end
	end)

	s.CreateButton({ Title = "Save Config" }, function()
		if not hasFS then
			notify("Config", "Executor tidak mendukung file")
			return
		end
		pcall(function()
			if not isfolder("Levian Hub") then
				makefolder("Levian Hub")
			end
			if not isfolder(CONFIG_DIR) then
				makefolder(CONFIG_DIR)
			end
			writefile(path(), HttpService:JSONEncode(State))
		end)
		notify("Config", "Tersimpan: " .. configName)
	end)

	s.CreateButton({ Title = "Load Config" }, function()
		if not (hasFS and isfile(path())) then
			notify("Config", "File tidak ditemukan: " .. configName)
			return
		end
		local ok, data = pcall(function()
			return HttpService:JSONDecode(readfile(path()))
		end)
		if not ok or type(data) ~= "table" then
			notify("Config", "File config rusak")
			return
		end
		for k, v in pairs(data) do
			if State[k] ~= nil and type(State[k]) == type(v) and Controls[k] then
				Controls[k].SetValue(v)
			end
		end
		notify("Config", "Dimuat: " .. configName)
	end)

	local sess = cfg.CreateSection({ Title = "Session" })
	sess.CreateBind({ Title = "Toggle UI", Key = Enum.KeyCode.RightControl }, function()
		Main.SetVisible(not getgenv().UIToggled)
	end)
	sess.CreateButton({ Title = "Unload Script" }, function()
		for _, c in pairs(Connections) do
			pcall(function()
				c:Disconnect()
			end)
		end
		setFullbright(false)
		Lighting.ClockTime = origClock
		setThirdPerson(false)
		pcall(function()
			Overlay:Destroy()
		end)
		Main.Destroy()
	end)
end

---------------------------------------------------------------- loops
local hue, lastSlow = 0, 0

Connections.Render = RunService.RenderStepped:Connect(function(dt)
	local cam = getCam()
	if not cam then
		return
	end

	if State.Crosshair then
		local m = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter and cam.ViewportSize / 2
			or UserInputService:GetMouseLocation()
		Cross.Position = UDim2.fromOffset(m.X, m.Y)
	end

	if State.LockFOV then
		cam.FieldOfView = State.CustomFOV
	end

	if State.ViewmodelOffset then
		local vm = Workspace:FindFirstChild("ViewModels")
		if vm then
			local off = CFrame.new(State.VMOffsetX / 10, State.VMOffsetY / 10, State.VMOffsetZ / 10)
			for _, m in ipairs(vm:GetChildren()) do
				if m:IsA("Model") and m.PrimaryPart then
					m:SetPrimaryPartCFrame(m.PrimaryPart.CFrame * off)
				end
			end
		end
	end

	if State.RainbowVM then
		hue = (hue + dt * 0.35) % 1
		local col = Color3.fromHSV(hue, 1, 1)
		local vm = Workspace:FindFirstChild("ViewModels")
		if vm then
			for _, m in ipairs(vm:GetChildren()) do
				styleModel(m, col, Enum.Material.Neon)
			end
		end
	elseif State.AutoWrap and tick() - lastSlow > 0.5 then
		lastSlow = tick()
		applyWrap(State.SelectedWrap)
	end
end)

notify("Levian Hub", "Rivals dimuat (Right Ctrl = buka/tutup UI)")
