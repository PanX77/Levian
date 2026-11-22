--[[
	tapsim.lua - Tap Simulator Reborn (Levian Hub)
	Dipanggil oleh loader (PlaceId 72858262610964 -> "tapsim.lua").
	Menu: Farm -> Auto Tap, Auto Rebirth (tertinggi), Auto Quest, Auto Claim Quest

	Script mendeteksi tombol UI & remote berdasarkan NAMA, jadi kalau nama di game
	berbeda, cukup ubah tabel CONFIG di bawah (atau pakai tombol "Dump" di menu
	Utilitas untuk melihat nama asli remote & tombol di game).
]]

local BASE = "https://levianstore.my.id/"
local UI_FILE = "LevianUI.lua" -- nama file library UI di server / folder executor

---------------------------------------------------------------- CONFIG
local CONFIG = {
	TapNames = { "tap", "click" }, -- nama tombol / remote tap
	TapSkip = { "auto", "upgrade", "shop", "close", "rebirth", "quest", "claim", "gift" },

	RebirthNames = { "rebirth" },
	RebirthSkip = { "close", "exit", "back", "tutorial" },
	RebirthOptions = { 1000, 500, 100, 50, 25, 10, 5, 3, 2, 1 }, -- dipakai kalau pakai remote (urut tertinggi -> terendah)

	QuestNames = { "quest", "mission" },
	AcceptWords = { "accept", "start", "begin", "take", "track" },
	ClaimWords = { "claim", "collect" },
	QuestIds = {}, -- isi kalau remote claim butuh id, contoh: { 1, 2, 3 }
}

---------------------------------------------------------------- setup
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

-- hentikan loop dari eksekusi sebelumnya
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

local function hasAny(s, words)
	s = lower(s)
	for _, w in ipairs(words) do
		if s:find(w, 1, true) then
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
	return sg ~= nil and sg.Name:find("Levian", 1, true) ~= nil
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

-- klik tombol GUI tanpa perlu menggerakkan mouse
local function activate(btn)
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

local function findRemotes(words, skip)
	local out = {}
	for _, r in ipairs(remotes) do
		if hasAny(r.Name, words) and not (skip and hasAny(r.Name, skip)) then
			out[#out + 1] = r
		end
	end
	return out
end

local function fireRemote(r, ...)
	if r:IsA("RemoteEvent") then
		r:FireServer(...)
	else
		task.spawn(r.InvokeServer, r, ...)
	end
end

---------------------------------------------------------------- remote spesifik game + pembelajar argumen
local function path(p)
	local o = RS
	for part in p:gmatch("[^%.]+") do
		o = o and o:FindFirstChild(part)
	end
	return o
end

local R = {
	Tap = path("RemoteServices.TapService.RE.TapRequested"),
	Rebirth = path("RemoteServices.RebirthService.RE.RebirthRequested"),
	ClaimAll = path("RemoteServices.QuestService.RF.ClaimAllQuests"),
}

-- argumen asli yang dikirim game (saat Anda tap / rebirth manual) disimpan lalu dipakai ulang
env.TapSimLearned = env.TapSimLearned or {}
env.TapSimWatch = {}
for _, r in pairs({ R.Tap, R.Rebirth }) do
	env.TapSimWatch[r] = true
end
local Learned = env.TapSimLearned

if not env.TapSimHooked and hookmetamethod and getnamecallmethod then
	env.TapSimHooked = true
	pcall(function()
		local old
		local function hook(self, ...)
			local m = getnamecallmethod()
			if (m == "FireServer" or m == "InvokeServer") and env.TapSimWatch[self] and not (checkcaller and checkcaller()) then
				env.TapSimLearned[self] = table.pack(...)
			end
			return old(self, ...)
		end
		old = hookmetamethod(game, "__namecall", newcclosure and newcclosure(hook) or hook)
	end)
end

local function fireLearned(r)
	local a = Learned[r]
	if a then
		fireRemote(r, table.unpack(a, 1, a.n))
	else
		fireRemote(r)
	end
end

local function rebirthViaRemote(done)
	local r = R.Rebirth
	if not r then
		return
	end
	local a = Learned[r]
	if a and type(a[1]) == "number" then
		for _, opt in ipairs(CONFIG.RebirthOptions) do -- tertinggi -> terendah
			local args = table.pack(table.unpack(a, 1, a.n))
			args[1] = opt
			pcall(fireRemote, r, table.unpack(args, 1, args.n))
			task.wait(0.35)
			if done() then
				return
			end
		end
	else
		pcall(fireLearned, r)
	end
end

---------------------------------------------------------------- state & loop
local State = {
	Tap = false,
	Rebirth = false,
	Quest = false,
	Claim = false,
	Method = "Tombol Layar",
	TapDelay = 0.1,
	RebirthDelay = 3,
	QuestDelay = 2,
	ClaimDelay = 2,
}

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
			end
			task.wait(State[delayKey])
		end
		running[key] = false
	end)
end

---------------------------------------------------------------- auto tap
local tapBtn, tapRemote

local function findTapButton()
	if tapBtn and tapBtn.Parent then
		return tapBtn
	end
	local best, bestScore = nil, 0
	for _, b in ipairs(buttons(function()
		return true
	end)) do
		local n = lower(b.Name)
		local own = b:IsA("TextButton") and lower(b.Text) or ""
		local score = 0
		if n == "tap" or own == "tap" then
			score = 3
		elseif (hasAny(n, CONFIG.TapNames) or hasAny(textOf(b), CONFIG.TapNames)) and not hasAny(n .. " " .. own, CONFIG.TapSkip) then
			score = 1
		end
		if score > 0 and b.Visible then
			score += 0.5
		end
		if score > bestScore then
			best, bestScore = b, score
		end
	end
	tapBtn = best
	return best
end

local function findTapRemote()
	if R.Tap then
		return R.Tap
	end
	if tapRemote and tapRemote.Parent then
		return tapRemote
	end
	local list = findRemotes(CONFIG.TapNames, CONFIG.TapSkip)
	for _, r in ipairs(list) do
		if lower(r.Name) == "tap" or lower(r.Name) == "click" then
			tapRemote = r
			return r
		end
	end
	tapRemote = list[1]
	return tapRemote
end

local function tapOnce()
	local function viaButton()
		local b = findTapButton()
		if b then
			activate(b)
			return true
		end
	end
	local function viaRemote()
		local r = findTapRemote()
		if r then
			fireLearned(r)
			return true
		end
	end
	if State.Method == "Remote" then
		if not viaRemote() then
			viaButton()
		end
	else
		if not viaButton() then
			viaRemote()
		end
	end
end

local tapRunning = false
local function ensureTapLoop() -- jalan selama Auto Tap atau Auto Quest aktif
	if tapRunning then
		return
	end
	tapRunning = true
	task.spawn(function()
		while alive() and (State.Tap or State.Quest) do
			pcall(tapOnce)
			task.wait(State.TapDelay)
		end
		tapRunning = false
	end)
end

---------------------------------------------------------------- auto rebirth (tertinggi)
local function parseNum(s)
	local n, suf = tostring(s):match("(%d[%d%.,]*)%s*([KkMmBbTt]?)")
	n = n and tonumber((n:gsub(",", "")))
	if not n then
		return nil
	end
	local mult = ({ k = 1e3, m = 1e6, b = 1e9, t = 1e12 })[lower(suf)] or 1
	return n * mult
end

local statObj, lastStatScan = nil, 0
local function rebirthCount()
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
				and lower(o.Name):find("rebirth", 1, true)
				and not (pg and o:IsDescendantOf(pg))
			then
				statObj = o
				break
			end
		end
	end
	return statObj and statObj.Value or nil
end

local function rebirthButtons()
	local list = {}
	for _, b in ipairs(buttons(function(o)
		return underName(o, CONFIG.RebirthNames) or hasAny(textOf(o), CONFIG.RebirthNames)
	end)) do
		local txt = textOf(b)
		if not hasAny(b.Name .. " " .. txt, CONFIG.RebirthSkip) then
			list[#list + 1] = { btn = b, n = parseNum(txt) }
		end
	end
	table.sort(list, function(a, b)
		return (a.n or -1) > (b.n or -1)
	end)
	return list
end

local function doRebirth()
	local before = rebirthCount()
	local function done()
		local now = rebirthCount()
		return before ~= nil and now ~= nil and now > before
	end

	local cands = rebirthButtons()
	if #cands > 0 then
		for i = 1, math.min(#cands, 12) do -- tertinggi -> terendah
			activate(cands[i].btn)
			task.wait(0.35)
			if done() then
				return
			end
		end
		return
	end

	-- cadangan: lewat RebirthRequested
	rebirthViaRemote(done)
end

---------------------------------------------------------------- auto quest & claim
local function doQuest()
	-- klik tombol Accept/Start di UI quest
	for _, b in ipairs(buttons(function(o)
		return underName(o, CONFIG.QuestNames) and hasAny(o.Name .. " " .. textOf(o), CONFIG.AcceptWords)
	end)) do
		activate(b)
		task.wait(0.15)
	end
	-- remote accept/start quest (kalau ada)
	for _, r in ipairs(findRemotes(CONFIG.AcceptWords)) do
		if hasAny(r.Name, CONFIG.QuestNames) then
			if #CONFIG.QuestIds > 0 then
				for _, id in ipairs(CONFIG.QuestIds) do
					pcall(fireRemote, r, id)
				end
			else
				pcall(fireRemote, r)
			end
		end
	end
	-- progres quest datang dari tap, jadi ensureTapLoop ikut jalan saat Auto Quest aktif
end

local function doClaim()
	for _, b in ipairs(buttons(function(o)
		return underName(o, CONFIG.QuestNames) and hasAny(o.Name .. " " .. textOf(o), CONFIG.ClaimWords)
	end)) do
		activate(b)
		task.wait(0.1)
	end
	if R.ClaimAll then
		pcall(function()
			R.ClaimAll:InvokeServer()
		end)
	end
end

---------------------------------------------------------------- dump (untuk debug)
local function dump()
	scanRemotes()
	local lines = { "== REMOTE ==" }
	for _, r in ipairs(remotes) do
		lines[#lines + 1] = r.ClassName .. " | " .. r:GetFullName()
	end
	lines[#lines + 1] = "== TOMBOL GUI (tap/rebirth/quest/claim) =="
	local words = { "tap", "click", "rebirth", "quest", "mission", "claim", "accept", "start" }
	for _, b in ipairs(buttons(function(o)
		return hasAny(o.Name .. " " .. textOf(o), words)
	end)) do
		lines[#lines + 1] = b:GetFullName() .. " | \"" .. textOf(b):gsub("%s+", " ") .. "\""
	end
	local txt = table.concat(lines, "\n")
	print(txt)
	if setclipboard then
		pcall(setclipboard, txt)
	end
	return #remotes
end

---------------------------------------------------------------- UI
local UI = loadUI()
local Main = UI.CreateMain({ Title = "Levian Hub", Desc = " - Tap Simulator Reborn" })
local Farm = Main:CreatePage({ Page_Name = "Farm", Page_Title = "Farm" })

local secTap = Farm.CreateSection("Auto Tap")
secTap.CreateToggle({ Title = "Auto Tap", Desc = "Tap otomatis sesuai tombol Tap di layar", Default = false }, function(v)
	State.Tap = v
	if v then
		tapBtn, tapRemote = nil, nil
		ensureTapLoop()
	end
end)
secTap.CreateDropdown({ Title = "Metode Tap", List = { "Tombol Layar", "Remote" }, Default = "Tombol Layar" }, function(v)
	State.Method = v
end)
secTap.CreateSlider({ Title = "Delay Tap", Min = 0.01, Max = 1, Default = 0.1, Precise = true }, function(v)
	State.TapDelay = v
end)

local secReb = Farm.CreateSection("Rebirth")
secReb.CreateToggle({ Title = "Auto Rebirth", Desc = "Otomatis pilih rebirth tertinggi", Default = false }, function(v)
	State.Rebirth = v
	if v then
		loop("Rebirth", doRebirth, "RebirthDelay")
	end
end)
secReb.CreateSlider({ Title = "Delay Rebirth (detik)", Min = 1, Max = 30, Default = 3 }, function(v)
	State.RebirthDelay = v
end)

local secQ = Farm.CreateSection("Quest")
secQ.CreateToggle({ Title = "Auto Quest", Desc = "Ambil quest & tap otomatis sampai selesai", Default = false }, function(v)
	State.Quest = v
	if v then
		loop("Quest", doQuest, "QuestDelay")
		ensureTapLoop()
	end
end)
secQ.CreateToggle({ Title = "Auto Claim Quest", Desc = "Claim quest yang sudah selesai", Default = false }, function(v)
	State.Claim = v
	if v then
		loop("Claim", doClaim, "ClaimDelay")
	end
end)
secQ.CreateSlider({ Title = "Delay Quest/Claim (detik)", Min = 1, Max = 30, Default = 2 }, function(v)
	State.QuestDelay, State.ClaimDelay = v, v
end)

local secUtil = Farm.CreateSection("Utilitas")
secUtil.CreateButton({ Title = "Scan Ulang Remote" }, function()
	scanRemotes()
	tapBtn, tapRemote = nil, nil
	UI.CreateNoti({ Title = "Scan", Desc = #remotes .. " remote ditemukan", ShowTime = 3 })
end)
secUtil.CreateButton({ Title = "Dump Remote & Tombol (console)" }, function()
	local n = dump()
	UI.CreateNoti({ Title = "Dump", Desc = n .. " remote dicetak ke console" .. (setclipboard and " & disalin" or ""), ShowTime = 4 })
end)

UI.CreateNoti({ Title = "Tap Simulator Reborn", Desc = "Menu Farm siap dipakai", ShowTime = 3 })
