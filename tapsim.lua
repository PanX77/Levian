--[[
	tapsim.lua - Tap Simulator Reborn (Levian Hub)
	Menu Farm: Auto Tap, Auto Rebirth (tertinggi), Auto Quest, Auto Claim Quest

	Catatan cara kerja:
	- Tap  : klik layar sungguhan (VirtualInputManager), sama seperti jari Anda.
	- GUI  : tombol ditekan dengan klik sungguhan kalau menu hub sedang disembunyikan,
	         kalau tidak memakai firesignal. Karena itu menu hub disembunyikan otomatis
	         saat fitur dinyalakan (buka lagi lewat tombol bulat; selama menu terbuka
	         klik layar berhenti sementara).
	- Tombol "Diagnostik" menampilkan info executor/tombol/remote langsung di layar.
]]

local BASE = "https://levianstore.my.id/"
local UI_FILE = "LevianUI.lua"

---------------------------------------------------------------- CONFIG
local CONFIG = {
	RebirthNames = { "rebirth" },
	RebirthSkip = { "close", "exit", "back", "tutorial" },
	RebirthOptions = { 1000, 500, 100, 50, 25, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 }, -- hanya untuk jalur remote
	QuestNames = { "quest", "mission" },
	AcceptWords = { "accept", "start", "begin", "take", "track" },
	ClaimWords = { "claim", "collect" },
	ConfirmTexts = { "yes", "confirm", "ok", "sure", "rebirth now" },
	TapButtonPath = "Game.Bottom.Tap.Button", -- relatif ke PlayerGui
	ClaimButtonPath = "RightHud.Main.RightUI.Quests.ClaimAll.Claim.Button",
	QuestListPath = "RightHud.Main.RightUI.Quests.List",
	RebirthOptionsPath = "RightHud.Main.RightUI.Rebirths.List.Options",
	Eggs = { "30M Egg", "Basic Egg", "Cactus Egg", "Crystal Egg", "Draconic Egg", "Geode Egg", "Heaven Egg", "Mushroom Egg", "Mycelium Egg", "Nimbus Egg", "Pumpkin Egg", "Sky Egg", "Spiked Egg", "Spotted Egg", "Void Egg", "Volcanic Egg" },
}

---------------------------------------------------------------- setup
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local LP = Players.LocalPlayer

local env = getgenv()
env.TapSimRun = (env.TapSimRun or 0) + 1
local RUN = env.TapSimRun
local function alive()
	return env.TapSimRun == RUN
end

local function loadUI()
	local ok, lib = pcall(function()
		return loadstring(game:HttpGet(BASE .. UI_FILE))()
	end)
	if ok and type(lib) == "table" then
		return lib
	end
	ok, lib = pcall(function()
		return loadstring(readfile(UI_FILE))()
	end)
	if ok and type(lib) == "table" then
		return lib
	end
	error("[TapSim] Gagal memuat " .. UI_FILE)
end

---------------------------------------------------------------- helper
local function lower(s)
	return string.lower(tostring(s or ""))
end

local function trim(s)
	s = tostring(s)
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

local function hasAny(s, words)
	s = lower(s)
	for _, w in ipairs(words) do
		if string.find(s, w, 1, true) then
			return true
		end
	end
	return false
end

local function textOf(o)
	local t = o:IsA("TextButton") and o.Text or ""
	for _, d in ipairs(o:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			t = t .. " " .. d.Text
		end
	end
	return t
end

local function underName(o, words)
	local p = o
	while p and not p:IsA("PlayerGui") do
		if hasAny(p.Name, words) then
			return true
		end
		p = p.Parent
	end
	return false
end

local function isOwnGui(o)
	local sg = o:FindFirstAncestorOfClass("ScreenGui")
	return sg ~= nil and string.find(sg.Name, "Levian", 1, true) ~= nil
end

local function buttons(filter)
	local out = {}
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return out
	end
	for _, o in ipairs(pg:GetDescendants()) do
		if (o:IsA("TextButton") or o:IsA("ImageButton")) and not isOwnGui(o) and filter(o) then
			out[#out + 1] = o
		end
	end
	return out
end

-- nama lengkap tanpa namecall (aman dipakai di dalam hook)
local function fname(o)
	local t = {}
	while o and o ~= game do
		table.insert(t, 1, o.Name)
		o = o.Parent
	end
	return table.concat(t, ".")
end

local function ser(v, d)
	d = d or 0
	local t = typeof(v)
	if t == "string" then
		return string.format("%q", v)
	elseif t == "Instance" then
		return "<" .. fname(v) .. ">"
	elseif t == "table" then
		if d >= 2 then
			return "{...}"
		end
		local parts, n = {}, 0
		for k, x in pairs(v) do
			n = n + 1
			if n > 8 then
				parts[#parts + 1] = "..."
				break
			end
			parts[#parts + 1] = "[" .. tostring(k) .. "]=" .. ser(x, d + 1)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

---------------------------------------------------------------- tampilan teks (log/diagnostik) + salin
local function parentGui(gui)
	if pcall(function()
		gui.Parent = game:GetService("CoreGui")
	end) and gui.Parent then
		return
	end
	if gethui and pcall(function()
		gui.Parent = gethui()
	end) and gui.Parent then
		return
	end
	gui.Parent = LP:WaitForChild("PlayerGui")
end

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function copyText(t)
	local ok = false
	if setclipboard then
		ok = pcall(setclipboard, t)
	elseif toclipboard then
		ok = pcall(toclipboard, t)
	end
	if writefile then
		pcall(writefile, "TapSim_log.txt", t)
	end
	return ok
end

local function showText(title, text)
	if env.TapSimViewer then
		pcall(function()
			env.TapSimViewer:Destroy()
		end)
	end
	if #text > 15000 then
		text = string.sub(text, 1, 15000) .. "\n...(dipotong)"
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Levian LogView"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	parentGui(gui)
	env.TapSimViewer = gui

	local f = mk("Frame", {
		BackgroundColor3 = Color3.fromRGB(22, 22, 27),
		Size = UDim2.new(0.92, 0, 0.8, 0),
		Position = UDim2.new(0.04, 0, 0.1, 0),
	}, gui)
	mk("UICorner", { CornerRadius = UDim.new(0, 8) }, f)
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = Color3.fromRGB(255, 204, 0),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, 10, 0, 0),
		Size = UDim2.new(1, -150, 0, 30),
	}, f)
	local close = mk("TextButton", {
		BackgroundColor3 = Color3.fromRGB(70, 40, 40),
		Text = "Tutup",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		Size = UDim2.new(0, 60, 0, 22),
		Position = UDim2.new(1, -68, 0, 4),
	}, f)
	local copy = mk("TextButton", {
		BackgroundColor3 = Color3.fromRGB(40, 70, 40),
		Text = "Salin",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		Size = UDim2.new(0, 60, 0, 22),
		Position = UDim2.new(1, -134, 0, 4),
	}, f)
	local sc = mk("ScrollingFrame", {
		BackgroundColor3 = Color3.fromRGB(30, 30, 37),
		Position = UDim2.new(0, 6, 0, 32),
		Size = UDim2.new(1, -12, 1, -38),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		BorderSizePixel = 0,
	}, f)
	mk("TextBox", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.fromRGB(230, 230, 230),
		Font = Enum.Font.Code,
		TextSize = 12,
		TextWrapped = true,
		MultiLine = true,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, sc)
	close.MouseButton1Click:Connect(function()
		gui:Destroy()
	end)
	copy.MouseButton1Click:Connect(function()
		copy.Text = copyText(text) and "Tersalin" or "Gagal"
	end)
end

---------------------------------------------------------------- remote
local remotes = {}
local function scanRemotes()
	remotes = {}
	for _, o in ipairs(RS:GetDescendants()) do
		if o:IsA("RemoteEvent") or o:IsA("RemoteFunction") then
			remotes[#remotes + 1] = o
		end
	end
end
scanRemotes()

local function fireRemote(r, ...)
	if r:IsA("RemoteEvent") then
		r:FireServer(...)
	else
		task.spawn(r.InvokeServer, r, ...)
	end
end

local function path(p)
	local o = RS
	for part in string.gmatch(p, "[^%.]+") do
		o = o and o:FindFirstChild(part)
	end
	return o
end

local R = {
	Tap = path("RemoteServices.TapService.RE.TapRequested"),
	Rebirth = path("RemoteServices.RebirthService.RE.RebirthRequested"),
	ClaimAll = path("RemoteServices.QuestService.RF.ClaimAllQuests"),
	Hatch = path("RemoteServices.EggService.RE.EggHatchRequested"),
}

local function guiPath(p)
	local o = LP:FindFirstChildOfClass("PlayerGui")
	for part in string.gmatch(p, "[^%.]+") do
		o = o and o:FindFirstChild(part)
	end
	return o
end

---------------------------------------------------------------- perekam remote (hook)
env.TapSimLearned = env.TapSimLearned or {}
env.TapSimWatch = {}
for _, r in pairs({ R.Tap, R.Rebirth, R.Hatch }) do
	env.TapSimWatch[r] = true
end
env.TapSimLog = env.TapSimLog or {}
env.TapSimSeen = env.TapSimSeen or 0
local Learned = env.TapSimLearned

local LOG_SKIP = { "CharacterPositions", "ServerClock", "TrackingService", "Telemetry", "Replica", "Cmdr", "ShiftLock" }
env.TapSimOnCall = function(self, method, ...)
	env.TapSimSeen = env.TapSimSeen + 1
	if env.TapSimWatch[self] then
		env.TapSimLearned[self] = table.pack(...)
	end
	if env.TapSimRecord and typeof(self) == "Instance" then
		local p = fname(self)
		for _, w in ipairs(LOG_SKIP) do
			if string.find(p, w, 1, true) then
				return
			end
		end
		local a = table.pack(...)
		local parts = {}
		for i = 1, a.n do
			parts[i] = ser(a[i])
		end
		local line = string.gsub(p, "^ReplicatedStorage%.", "") .. "(" .. table.concat(parts, ", ") .. ")"
		local log = env.TapSimLog
		local last = log[#log]
		if last and last.line == line then
			last.n = last.n + 1
		else
			log[#log + 1] = { line = line, n = 1 }
			if #log > 150 then
				table.remove(log, 1)
			end
		end
	end
end

if not env.TapSimHookVer then
	local function nc(f)
		return newcclosure and newcclosure(f) or f
	end
	if hookmetamethod and getnamecallmethod then
		env.TapSimHookVer = 3
		pcall(function()
			local old
			old = hookmetamethod(
				game,
				"__namecall",
				nc(function(self, ...)
					local m = getnamecallmethod()
					if (m == "FireServer" or m == "InvokeServer") and env.TapSimOnCall and not (checkcaller and checkcaller()) then
						pcall(env.TapSimOnCall, self, m, ...)
						if setnamecallmethod then
							setnamecallmethod(m)
						end
					end
					return old(self, ...)
				end)
			)
		end)
	elseif hookfunction then
		env.TapSimHookVer = 3
		pcall(function()
			local oF, oI
			oF = hookfunction(
				Instance.new("RemoteEvent").FireServer,
				nc(function(self, ...)
					if env.TapSimOnCall and not (checkcaller and checkcaller()) then
						pcall(env.TapSimOnCall, self, "FireServer", ...)
					end
					return oF(self, ...)
				end)
			)
			oI = hookfunction(
				Instance.new("RemoteFunction").InvokeServer,
				nc(function(self, ...)
					if env.TapSimOnCall and not (checkcaller and checkcaller()) then
						pcall(env.TapSimOnCall, self, "InvokeServer", ...)
					end
					return oI(self, ...)
				end)
			)
		end)
	end
end

local function fireLearned(r)
	local a = Learned[r]
	if a then
		fireRemote(r, table.unpack(a, 1, a.n))
	else
		fireRemote(r)
	end
end

---------------------------------------------------------------- state
local UI, Main
local State = {
	Tap = false,
	Rebirth = false,
	Quest = false,
	Claim = false,
	AutoHide = true,
	Method = "Klik Layar",
	ClickX = 50,
	ClickY = 50,
	TapDelay = 0.1,
	RebirthDelay = 3,
	RebirthMax = 9,
	Hatch = false,
	EggName = "",
	EggPick = "(dari hatch manual)",
	AutoTP = false,
	HatchCount = 3,
	HatchDelay = 1,
	QuestDelay = 2,
	ClaimDelay = 2,
}

local Status, LastStatus = {}, {}
local function setStatus(key, txt)
	LastStatus[key] = txt
	if Status[key] then
		pcall(function()
			Status[key].SetText(txt)
		end)
	end
end

local running, warned = {}, {}
local function loop(key, fn, delayKey)
	if running[key] then
		return
	end
	running[key] = true
	task.spawn(function()
		while alive() and State[key] do
			local ok, err = pcall(fn)
			if not ok and not warned[key] then
				warned[key] = true
				warn("[TapSim] " .. key .. ":", err)
				setStatus(key, key .. ": error " .. tostring(err))
			end
			task.wait(State[delayKey])
		end
		running[key] = false
	end)
end

local function hideMenu()
	if State.AutoHide and Main then
		task.delay(0.4, function()
			if alive() then
				Main.SetVisible(false)
				UI.CreateNoti({ Title = "Menu disembunyikan", Desc = "Buka lagi lewat tombol bulat", ShowTime = 3 })
			end
		end)
	end
end

---------------------------------------------------------------- klik sungguhan & tekan tombol GUI
local VIM
pcall(function()
	VIM = game:GetService("VirtualInputManager")
end)

local function menuHidden() -- klik sungguhan hanya dilakukan kalau menu hub tersembunyi
	return env.UIToggled == false
end

local function clickAt(x, y)
	if not VIM then
		return false
	end
	local ok = pcall(function()
		VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
		VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
	end)
	if not ok then
		ok = pcall(function()
			VIM:SendTouchEvent(1, 0, x, y)
			VIM:SendTouchEvent(1, 2, x, y)
		end)
	end
	return ok
end

local function onScreen(b)
	local o = b
	while o do
		if o:IsA("GuiObject") then
			if not o.Visible then
				return false
			end
		elseif o:IsA("ScreenGui") then
			if not o.Enabled then
				return false
			end
			break
		end
		o = o.Parent
	end
	if not o then
		return false
	end
	local sz = b.AbsoluteSize
	if sz.X < 2 or sz.Y < 2 then
		return false
	end
	local cam = workspace.CurrentCamera
	local vs = cam and cam.ViewportSize or Vector2.new(800, 400)
	local c = b.AbsolutePosition + sz / 2
	return c.X >= 0 and c.Y >= 0 and c.X <= vs.X and c.Y <= vs.Y
end

local function clickGui(b)
	local sg = b:FindFirstAncestorOfClass("ScreenGui")
	local inset = Vector2.new(0, 0)
	if sg and not sg.IgnoreGuiInset then
		inset = GuiService:GetGuiInset()
	end
	local c = b.AbsolutePosition + b.AbsoluteSize / 2 + inset
	return clickAt(c.X, c.Y)
end

local function fireSignals(btn)
	if firesignal then
		pcall(firesignal, btn.Activated)
		pcall(firesignal, btn.MouseButton1Click)
	elseif getconnections then
		for _, sig in ipairs({ btn.Activated, btn.MouseButton1Click }) do
			pcall(function()
				for _, c in ipairs(getconnections(sig)) do
					c:Fire()
				end
			end)
		end
	end
end

local function press(b)
	if menuHidden() and onScreen(b) and clickGui(b) then
		return true
	end
	fireSignals(b)
	return false
end

local function clickConfirm()
	for _, b in ipairs(buttons(function(o)
		if not onScreen(o) then
			return false
		end
		local t = lower(trim(textOf(o)))
		for _, w in ipairs(CONFIG.ConfirmTexts) do
			if t == w then
				return true
			end
		end
		return false
	end)) do
		press(b)
		task.wait(0.2)
	end
end

---------------------------------------------------------------- auto tap
local function clickScreen()
	if not menuHidden() then
		return false
	end
	local cam = workspace.CurrentCamera
	local vs = cam and cam.ViewportSize or Vector2.new(800, 400)
	return clickAt(vs.X * State.ClickX / 100, vs.Y * State.ClickY / 100)
end

local tapSeq = 0
local function tapOnce()
	if State.Method == "Remote" then
		local r = R.Tap
		if not r then
			return
		end
		local a = Learned[r]
		local t = a and type(a[1]) == "table" and a[1] or nil
		tapSeq = math.max(tapSeq, t and tonumber(t.ClientSequence) or 0) + 1
		fireRemote(r, { ClientSequence = tapSeq, Auto = false, Source = t and t.Source or "tap" })
	elseif State.Method == "Tombol Tap" then
		local b = guiPath(CONFIG.TapButtonPath)
		if b then
			press(b)
		end
	else
		clickScreen()
	end
end

local tapRunning = false
local function ensureTapLoop() -- jalan selama Auto Tap atau Auto Quest aktif
	if tapRunning then
		return
	end
	tapRunning = true
	task.spawn(function()
		local n = 0
		while alive() and (State.Tap or State.Quest) do
			pcall(tapOnce)
			n = n + 1
			if n % 25 == 0 then
				setStatus("Tap", "Tap: " .. n .. "x (" .. State.Method .. ((State.Method == "Klik Layar" and not menuHidden()) and ", menu terbuka = jeda" or "") .. ")")
			end
			task.wait(State.TapDelay)
		end
		tapRunning = false
	end)
end

---------------------------------------------------------------- auto rebirth (tertinggi)
local function parseNum(s)
	local n, suf = string.match(tostring(s), "(%d[%d%.,]*)%s*([KkMmBbTt]?)")
	n = n and tonumber((string.gsub(n, ",", "")))
	if not n then
		return nil
	end
	local mult = ({ k = 1e3, m = 1e6, b = 1e9, t = 1e12 })[lower(suf)] or 1
	return n * mult
end

local statObj, lastStatScan = nil, 0
local function rebirthCount()
	local ls = LP:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild("Rebirths")
	if v and (v:IsA("IntValue") or v:IsA("NumberValue")) then
		return v.Value
	end
	if not (statObj and statObj.Parent) then
		statObj = nil
		if os.clock() - lastStatScan < 5 then
			return nil
		end
		lastStatScan = os.clock()
		local pg = LP:FindFirstChildOfClass("PlayerGui")
		for _, o in ipairs(LP:GetDescendants()) do
			if
				(o:IsA("IntValue") or o:IsA("NumberValue"))
				and string.find(lower(o.Name), "rebirth", 1, true)
				and not (pg and o:IsDescendantOf(pg))
			then
				statObj = o
				break
			end
		end
	end
	return statObj and statObj.Value or nil
end

local function doRebirth()
	local r = R.Rebirth
	if not r then
		setStatus("Rebirth", "Rebirth: remote tidak ditemukan")
		return
	end
	local before = rebirthCount()
	local from, to = State.RebirthMax, 1
	if State.RebirthIndex then
		from, to = State.RebirthIndex, State.RebirthIndex
	end
	for i = from, to, -1 do -- tertinggi -> terendah
		fireRemote(r, { Index = i })
		task.wait(0.5)
		local now = rebirthCount()
		if before and now and now > before then
			setStatus("Rebirth", "Rebirth: berhasil Index " .. i .. " (total " .. tostring(now) .. ")")
			return
		end
	end
	setStatus("Rebirth", "Rebirth: belum cukup untuk Index " .. to .. "-" .. from)
end

---------------------------------------------------------------- auto quest & claim
local function doQuest()
	setStatus("Quest", "Quest: tap aktif (quest hatch/portal belum otomatis)")
end

local function doClaim()
	local btn = guiPath(CONFIG.ClaimButtonPath)
	if btn then
		press(btn)
	end
	local res
	if R.ClaimAll then
		local ok, r = pcall(function()
			return R.ClaimAll:InvokeServer()
		end)
		res = ok and ser(r) or ("error " .. tostring(r))
	else
		res = "remote tidak ada"
	end
	setStatus("Claim", "Claim: tombol " .. (btn and "ada" or "tidak ada") .. " | remote " .. res)
end

local function eggCount()
	local ls = LP:FindFirstChild("leaderstats")
	local v = ls and ls:FindFirstChild("Eggs")
	return v and v.Value or nil
end

local function eggArg()
	if State.EggName ~= "" then
		return State.EggName
	end
	local pick = State.EggPick
	if pick and string.sub(pick, 1, 1) ~= "(" then
		local n = string.gsub(pick, "%s*[Ee]gg$", "") -- "Mycelium Egg" -> "Mycelium"
		return n
	end
	local a = R.Hatch and Learned[R.Hatch]
	local t = a and type(a[1]) == "table" and a[1] or nil
	return t and t.Egg or nil
end

local eggPosCache = {}
local function findEggPos(arg)
	local key = lower(arg)
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local origin = hrp and hrp.Position or Vector3.new(0, 0, 0)
	local best, bestD
	for pass = 1, 2 do -- pass 1: nama mengandung "egg"; pass 2: cukup mengandung nama telur
		for _, o in ipairs(workspace:GetDescendants()) do
			if (o:IsA("Model") or o:IsA("BasePart")) and not (char and o:IsDescendantOf(char)) then
				local n = lower(o.Name)
				if string.find(n, key, 1, true) and (pass == 2 or string.find(n, "egg", 1, true)) then
					local pos = o:IsA("Model") and o:GetPivot().Position or o.Position
					local d = (pos - origin).Magnitude
					if not bestD or d < bestD then
						best, bestD = pos, d
					end
				end
			end
		end
		if best then
			break
		end
	end
	return best
end

local function tpToEgg(arg, onlyIfFar)
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false, "karakter tidak ada"
	end
	local key = lower(arg)
	local pos = eggPosCache[key]
	if not pos then
		pos = findEggPos(arg)
		eggPosCache[key] = pos
	end
	if not pos then
		return false, "egg '" .. arg .. "' tidak ditemukan di workspace"
	end
	if onlyIfFar and (hrp.Position - pos).Magnitude < 40 then
		return true, "sudah dekat"
	end
	hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 7))
	return true, "berhasil"
end

local hatchSeq = 0
local function doHatch()
	local r = R.Hatch
	if not r then
		setStatus("Hatch", "Hatch: remote tidak ditemukan")
		return
	end
	local egg = eggArg()
	if not egg then
		setStatus("Hatch", "Hatch: pilih telur atau hatch manual 1x")
		return
	end
	if State.AutoTP then
		local ok, msg = tpToEgg(egg, true)
		if not ok then
			setStatus("Hatch", "TP: " .. msg)
		end
	end
	local a = Learned[r]
	local t = a and type(a[1]) == "table" and a[1] or nil
	hatchSeq = math.max(hatchSeq, t and tonumber(t.Seq) or 0) + 1
	local before = eggCount()
	fireRemote(r, { Egg = egg, Count = State.HatchCount, Seq = hatchSeq, Auto = false })
	task.wait(0.5)
	local now = eggCount()
	setStatus("Hatch", "Hatch: " .. egg .. " x" .. State.HatchCount .. ((before and now) and (" | Eggs +" .. (now - before)) or ""))
end

---------------------------------------------------------------- diagnostik
local function diagnose()
	scanRemotes()
	local L = {}
	local function add(s)
		L[#L + 1] = s
	end

	add("== EXECUTOR ==")
	local okN, name = pcall(function()
		return identifyexecutor()
	end)
	add("nama: " .. (okN and tostring(name) or "?"))
	local caps = { "hookmetamethod", "hookfunction", "getnamecallmethod", "checkcaller", "newcclosure", "firesignal", "getconnections", "decompile", "getscripts", "setclipboard", "writefile" }
	local have = {}
	for _, n in ipairs(caps) do
		have[#have + 1] = n .. "=" .. (env[n] and "ya" or "tidak")
	end
	add(table.concat(have, ", "))
	add("VirtualInputManager=" .. tostring(VIM ~= nil) .. " | menuHidden=" .. tostring(menuHidden()))

	add("== HOOK ==")
	add("hookVer=" .. tostring(env.TapSimHookVer) .. " | panggilan remote terlihat=" .. tostring(env.TapSimSeen))
	add("R.Tap=" .. tostring(R.Tap ~= nil) .. " R.Rebirth=" .. tostring(R.Rebirth ~= nil) .. " R.ClaimAll=" .. tostring(R.ClaimAll ~= nil))
	for r, a in pairs(Learned) do
		local parts = {}
		for i = 1, a.n do
			parts[i] = ser(a[i])
		end
		add("argumen asli " .. fname(r) .. "(" .. table.concat(parts, ", ") .. ")")
	end

	add("== STATUS TERAKHIR ==")
	for k, v in pairs(LastStatus) do
		add(k .. ": " .. tostring(v))
	end

	add("== STAT (Int/Number di Player) ==")
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	local cnt = 0
	for _, o in ipairs(LP:GetDescendants()) do
		if (o:IsA("IntValue") or o:IsA("NumberValue")) and not (pg and o:IsDescendantOf(pg)) and cnt < 60 then
			cnt = cnt + 1
			add(fname(o) .. " = " .. tostring(o.Value))
		end
	end

	add("== REMOTE terkait ==")
	local kw = { "tap", "click", "rebirth", "quest", "mission", "claim" }
	for _, r in ipairs(remotes) do
		if hasAny(fname(r), kw) then
			add(r.ClassName .. " | " .. fname(r))
		end
	end

	add("== TOMBOL TERLIHAT DI LAYAR ==")
	cnt = 0
	for _, b in ipairs(buttons(onScreen)) do
		cnt = cnt + 1
		if cnt <= 80 then
			add(fname(b) .. " | \"" .. trim(string.gsub(textOf(b), "%s+", " ")) .. "\"")
		end
	end

	add("== TOMBOL rebirth/quest/claim (termasuk tersembunyi) ==")
	cnt = 0
	for _, b in ipairs(buttons(function(o)
		return hasAny(fname(o) .. " " .. textOf(o), { "rebirth", "quest", "mission", "claim" })
	end)) do
		cnt = cnt + 1
		if cnt <= 60 then
			add(fname(b) .. " | \"" .. trim(string.gsub(textOf(b), "%s+", " ")) .. "\" | tampil=" .. tostring(onScreen(b)))
		end
	end

	add("== TEKS QUEST ==")
	local ql = guiPath(CONFIG.QuestListPath)
	if ql then
		for _, c in ipairs(ql:GetChildren()) do
			local texts = {}
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text ~= "" then
					texts[#texts + 1] = d.Text
				end
			end
			add(c.Name .. ": " .. table.concat(texts, " | "))
		end
	else
		add("(daftar quest tidak ditemukan)")
	end

	add("== OPSI REBIRTH ==")
	local ro = guiPath(CONFIG.RebirthOptionsPath)
	if ro then
		for _, c in ipairs(ro:GetChildren()) do
			local texts = {}
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text ~= "" then
					texts[#texts + 1] = d.Text
				end
			end
			add(c.Name .. ": " .. table.concat(texts, " | "))
		end
	end

	add("== EGG DI WORKSPACE ==")
	cnt = 0
	for _, o in ipairs(workspace:GetDescendants()) do
		if cnt < 40 and (o:IsA("Model") or o:IsA("BasePart")) and string.find(lower(o.Name), "egg", 1, true) then
			cnt = cnt + 1
			local pos = o:IsA("Model") and o:GetPivot().Position or o.Position
			add(fname(o) .. " @ " .. math.floor(pos.X) .. "," .. math.floor(pos.Y) .. "," .. math.floor(pos.Z))
		end
	end

	add("== LOG REKAMAN ==")
	for _, e in ipairs(env.TapSimLog or {}) do
		add(e.line .. (e.n > 1 and (" x" .. e.n) or ""))
	end

	local txt = table.concat(L, "\n")
	print(txt)
	local copied = copyText(txt)
	showText("Diagnostik" .. (copied and " (tersalin ke clipboard)" or ""), txt)
end

---------------------------------------------------------------- UI
-- override dari tapsim2.lua (world 2); dibersihkan supaya tidak terbawa ke eksekusi berikutnya
local eggsOverride, titleOverride = env.TapSimEggs, env.TapSimTitle
env.TapSimEggs, env.TapSimTitle = nil, nil

UI = loadUI()
Main = UI.CreateMain({ Title = "Levian Hub", Desc = titleOverride or " - Tap Simulator Reborn" })
local Farm = Main:CreatePage({ Page_Name = "Farm", Page_Title = "Farm" })

local secTap = Farm.CreateSection("Auto Tap")
secTap.CreateToggle({ Title = "Auto Tap", Desc = "Klik layar otomatis", Default = false }, function(v)
	State.Tap = v
	if v then
		ensureTapLoop()
		hideMenu()
	end
end)
secTap.CreateDropdown({ Title = "Metode Tap", List = { "Klik Layar", "Tombol Tap", "Remote" }, Default = "Klik Layar" }, function(v)
	State.Method = v
end)
secTap.CreateSlider({ Title = "Delay Tap", Min = 0.01, Max = 1, Default = 0.1, Precise = true }, function(v)
	State.TapDelay = v
end)
secTap.CreateSlider({ Title = "Posisi Klik X (%)", Min = 5, Max = 95, Default = 50 }, function(v)
	State.ClickX = v
end)
secTap.CreateSlider({ Title = "Posisi Klik Y (%)", Min = 5, Max = 95, Default = 50 }, function(v)
	State.ClickY = v
end)
secTap.CreateToggle({ Title = "Sembunyikan Menu Otomatis", Desc = "Perlu agar klik layar tidak kena menu", Default = true }, function(v)
	State.AutoHide = v
end)

local secReb = Farm.CreateSection("Rebirth")
secReb.CreateToggle({ Title = "Auto Rebirth", Desc = "Pilih rebirth tertinggi", Default = false }, function(v)
	State.Rebirth = v
	if v then
		loop("Rebirth", doRebirth, "RebirthDelay")
		hideMenu()
	end
end)
secReb.CreateSlider({ Title = "Delay Rebirth (detik)", Min = 1, Max = 30, Default = 3 }, function(v)
	State.RebirthDelay = v
end)
secReb.CreateSlider({ Title = "Index Rebirth Maks", Min = 1, Max = 11, Default = 9 }, function(v)
	State.RebirthMax = v
end)
local rebList, rebIndex = { "Tertinggi (otomatis)" }, {}
for i = 1, 9 do
	local label = "Index " .. i
	local o = guiPath(CONFIG.RebirthOptionsPath .. "." .. i)
	if o then
		local texts = {}
		for _, d in ipairs(o:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text ~= "" then
				texts[#texts + 1] = trim(d.Text)
			end
		end
		if #texts > 0 then
			label = label .. " (" .. string.sub(table.concat(texts, " "), 1, 24) .. ")"
		end
	end
	rebList[#rebList + 1] = label
	rebIndex[label] = i
end
secReb.CreateDropdown({ Title = "Pilihan Rebirth", List = rebList, Default = rebList[1] }, function(v)
	State.RebirthIndex = rebIndex[v]
end)

local secQ = Farm.CreateSection("Quest")
secQ.CreateToggle({ Title = "Auto Quest", Desc = "Ambil quest & tap sampai selesai", Default = false }, function(v)
	State.Quest = v
	if v then
		loop("Quest", doQuest, "QuestDelay")
		ensureTapLoop()
		hideMenu()
	end
end)
secQ.CreateToggle({ Title = "Auto Claim Quest", Desc = "Claim quest yang sudah selesai", Default = false }, function(v)
	State.Claim = v
	if v then
		loop("Claim", doClaim, "ClaimDelay")
		hideMenu()
	end
end)
secQ.CreateSlider({ Title = "Delay Quest/Claim (detik)", Min = 1, Max = 30, Default = 2 }, function(v)
	State.QuestDelay, State.ClaimDelay = v, v
end)

local secEgg = Farm.CreateSection("Auto Egg")
secEgg.CreateToggle({ Title = "Auto Hatch Telur", Desc = "Hatch otomatis telur terpilih", Default = false }, function(v)
	State.Hatch = v
	if v then
		loop("Hatch", doHatch, "HatchDelay")
	end
end)
local eggList = { "(dari hatch manual)" }
for _, n in ipairs(eggsOverride or CONFIG.Eggs) do
	eggList[#eggList + 1] = n
end
secEgg.CreateDropdown({ Title = "Pilih Telur", List = eggList, Search = true, Default = eggList[1] }, function(v)
	State.EggPick = v
end)
secEgg.CreateBox({ Title = "Nama Manual (opsional)", Placeholder = "persis seperti di game" }, function(v)
	State.EggName = trim(tostring(v or ""))
end)
secEgg.CreateSlider({ Title = "Jumlah per Hatch", Min = 1, Max = 10, Default = 3 }, function(v)
	State.HatchCount = v
end)
secEgg.CreateSlider({ Title = "Delay Hatch (detik)", Min = 0.1, Max = 5, Default = 1, Precise = true }, function(v)
	State.HatchDelay = v
end)
secEgg.CreateToggle({ Title = "Auto TP ke Egg", Desc = "TP dekat egg sebelum hatch", Default = false }, function(v)
	State.AutoTP = v
end)
secEgg.CreateButton({ Title = "TP ke Egg Terpilih" }, function()
	local arg = eggArg()
	if not arg then
		UI.CreateNoti({ Title = "TP", Desc = "Pilih telur dulu", ShowTime = 3 })
		return
	end
	local ok, msg = tpToEgg(arg)
	setStatus("Hatch", "TP: " .. msg)
	UI.CreateNoti({ Title = "TP ke " .. arg, Desc = msg, ShowTime = 3 })
end)

local secSt = Farm.CreateSection("Status")
Status.Tap = secSt.CreateLabel({ Title = "Tap: -" })
Status.Rebirth = secSt.CreateLabel({ Title = "Rebirth: -" })
Status.Quest = secSt.CreateLabel({ Title = "Quest: -" })
Status.Claim = secSt.CreateLabel({ Title = "Claim: -" })
Status.Hatch = secSt.CreateLabel({ Title = "Hatch: -" })

local secUtil = Farm.CreateSection("Utilitas")
secUtil.CreateButton({ Title = "Diagnostik (tampil di layar)" }, function()
	diagnose()
end)
secUtil.CreateToggle({ Title = "Rekam Remote Game", Desc = "ON, lalu tap/rebirth/claim manual", Default = false }, function(v)
	env.TapSimRecord = v
	if v then
		env.TapSimLog = {}
		if not env.TapSimHookVer then
			UI.CreateNoti({ Title = "Rekam", Desc = "Executor tidak mendukung hook", ShowTime = 4 })
		end
	end
end)
secUtil.CreateButton({ Title = "Tampilkan Log Rekaman" }, function()
	local lines = {}
	for _, e in ipairs(env.TapSimLog or {}) do
		lines[#lines + 1] = e.line .. (e.n > 1 and (" x" .. e.n) or "")
	end
	local head = "hookVer=" .. tostring(env.TapSimHookVer) .. " | panggilan terlihat=" .. tostring(env.TapSimSeen) .. "\n"
	showText("Log Rekaman", head .. (#lines > 0 and table.concat(lines, "\n") or "(kosong)"))
end)

UI.CreateNoti({ Title = "Tap Simulator Reborn", Desc = "Menu Farm siap dipakai", ShowTime = 3 })
