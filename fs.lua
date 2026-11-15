--[[
	Final Swarm - Auto Join Lobby (v1)
	Urutan panggilan hasil rekaman (party 4 / Normal / Volcano):
	  WorldSelection.RemoteEvent   Fire("SetWorld", "Volcano")
	  WorldSelection.RemoteEvent   Fire("SetDifficulty", "Normal")
	  WorldSelection.RemoteEvent   Fire("SetChallenges", {})
	  WorldSelection.RemoteFunction Invoke("EnterQueue")  -> true
	  QueueService.RemoteEvent     Fire("PartySizeSelected", 4)
	  QueueService.RemoteEvent     Fire("Created")
	Solo = PartySizeSelected 1 (terkonfirmasi). Game mulai otomatis setelah antrean dibuat.
	Sebelum SetWorld, menu game juga mengirim: SetRunMode "Normal".
]]

local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")

---------------------------------------------------------------- pengaturan tersimpan
local FILE = "FinalSwarm/settings.json"
local cfg = {
	mode = "Solo", difficulty = "Normal", map = "Volcano", mapManual = "", runMode = "Normal", created = true,
	challenges = {}, challengeExtra = "",
}
pcall(function()
	if isfile and isfile(FILE) then
		for k, v in pairs(HttpService:JSONDecode(readfile(FILE))) do
			cfg[k] = v
		end
	end
end)
local function save()
	pcall(function()
		if makefolder and not isfolder("FinalSwarm") then
			makefolder("FinalSwarm")
		end
		writefile(FILE, HttpService:JSONEncode(cfg))
	end)
end

---------------------------------------------------------------- library UI (domain dulu, lalu GitHub)
local function loadUI()
	local urls = {
		"https://levianstore.my.id/BananaUI.lua",
		"https://raw.githubusercontent.com/PanX77/Bananaui/fe48e1c715ab1cf54a5c15b61d4f3c32070b5de3/BananaUI.lua",
	}
	for _, u in ipairs(urls) do
		local ok, lib = pcall(function()
			return loadstring(game:HttpGet(u))()
		end)
		if ok and type(lib) == "table" and lib.CreateMain then
			return lib
		end
	end
	return nil
end
local UI = loadUI()
if not UI then
	warn("[FS] library UI gagal dimuat")
	return
end

---------------------------------------------------------------- remote
local function getRemotes()
	local root
	for _, d in ipairs(RS:GetDescendants()) do
		if d.Name == "_remotes" and d:FindFirstChild("WorldSelection") and d:FindFirstChild("QueueService") then
			root = d
			break
		end
	end
	if not root then
		return nil
	end
	local ws, qs = root.WorldSelection, root.QueueService
	return {
		wsEvent = ws:FindFirstChildOfClass("RemoteEvent"),
		wsFunc = ws:FindFirstChildOfClass("RemoteFunction"),
		qsEvent = qs:FindFirstChildOfClass("RemoteEvent"),
	}
end

-- daftar challenge hasil rekaman (nama tampil -> ID yang dikirim). Kosong = default (tanpa challenge)
local CHALLENGES = {
	{ "Disable Rocks", "disable_rocks" },
	{ "First Person", "first_person" },
	{ "Inverted", "inverted" },
	{ "One Weapon", "one_weapon" },
	{ "Supdoggy Chase", "supdoggy_chase" },
	{ "Player Nerfs", "player_nerfs" },
	{ "Enemy Max", "enemy_max" },
	{ "1 HP", "1_hp" },
	{ "No Armor", "no_armor" },
}
local CH_NAMES = {}
for _, c in ipairs(CHALLENGES) do
	CH_NAMES[#CH_NAMES + 1] = c[1]
end

local function challengeList()
	local want, out, seen = {}, {}, {}
	for _, n in ipairs(cfg.challenges or {}) do
		want[n] = true
	end
	for _, c in ipairs(CHALLENGES) do
		if want[c[1]] then
			out[#out + 1] = c[2]
			seen[c[2]] = true
		end
	end
	-- ID tambahan (misalnya challenge ke-10) dipisah koma
	for token in tostring(cfg.challengeExtra or ""):gmatch("[^,]+") do
		local id = (token:gsub("^%s+", ""))
		id = (id:gsub("%s+$", ""))
		if id ~= "" and not seen[id] then
			out[#out + 1] = id
			seen[id] = true
		end
	end
	return out
end

local function worldName()
	local m = (tostring(cfg.mapManual or ""):gsub("^%s+", ""))
	m = (m:gsub("%s+$", ""))
	if m ~= "" then
		return m
	end
	return cfg.map
end

local function joinOnce()
	local r = getRemotes()
	if not r or not r.wsEvent or not r.wsFunc or not r.qsEvent then
		return false, "remote tidak ditemukan (pastikan kamu di lobby)"
	end
	local size = tonumber(tostring(cfg.mode):match("%d")) or 1 -- Solo = 1 (asumsi)
	local world = worldName()
	r.wsEvent:FireServer("SetRunMode", cfg.runMode)
	task.wait(0.3)
	r.wsEvent:FireServer("SetWorld", world)
	task.wait(0.4)
	r.wsEvent:FireServer("SetDifficulty", cfg.difficulty)
	task.wait(0.4)
	local chal = challengeList()
	r.wsEvent:FireServer("SetChallenges", chal)
	task.wait(0.4)
	local ok, res = pcall(function()
		return r.wsFunc:InvokeServer("EnterQueue")
	end)
	if not ok then
		return false, "EnterQueue error: " .. tostring(res)
	end
	if res ~= true then
		return false, "EnterQueue ditolak: " .. tostring(res)
	end
	task.wait(0.4)
	r.qsEvent:FireServer("PartySizeSelected", size)
	if cfg.created then
		task.wait(0.3)
		r.qsEvent:FireServer("Created")
	end
	return true, ("antrean dibuat: %s / %s / %d pemain, menunggu game mulai otomatis"):format(tostring(world), tostring(cfg.difficulty) .. "/" .. #chal .. " challenge", size)
end

local function leaveQueue()
	local r = getRemotes()
	if r and r.qsEvent then
		r.qsEvent:FireServer("Exited")
		return true
	end
	return false
end

---------------------------------------------------------------- UI
local Main = UI.CreateMain({ Title = "Final Swarm", Desc = " - Lobby" })
-- hapus tombol close (x) kalau library di server masih versi lama
pcall(function()
	for _, root in ipairs({ game:GetService("CoreGui"), (gethui and gethui()) or game:GetService("CoreGui") }) do
		local g = root:FindFirstChild("Nousigi Hub GUI")
		if g then
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("TextButton") and d.Text == "x" then
					d:Destroy()
				end
			end
			break
		end
	end
end)
local Page = Main.CreatePage({ Page_Name = "Lobby", Page_Title = "Auto Join" })

local S1 = Page.CreateSection("Pengaturan")
S1.CreateDropdown({ Title = "Mode", List = { "Solo", "2 Pemain", "3 Pemain", "4 Pemain" }, Default = cfg.mode }, function(v)
	cfg.mode = v
	save()
end)
S1.CreateDropdown({ Title = "Difficulty", List = { "Normal", "Hard", "Nightmare" }, Default = cfg.difficulty }, function(v)
	cfg.difficulty = v
	save()
end)
S1.CreateDropdown({
	Title = "Challenge (boleh lebih dari satu)",
	List = CH_NAMES,
	Multi = true,
	Default = cfg.challenges,
}, function(sel)
	local out = {}
	for _, c in ipairs(CHALLENGES) do
		if type(sel) == "table" and sel[c[1]] then
			out[#out + 1] = c[1]
		end
	end
	cfg.challenges = out
	save()
end)
S1.CreateBox({ Title = "Challenge tambahan (ID, pakai koma)", Default = cfg.challengeExtra }, function(v)
	cfg.challengeExtra = type(v) == "string" and v or ""
	save()
end)
S1.CreateLabel({ Title = "Challenge kosong = default (tanpa challenge)" })
S1.CreateDropdown({
	Title = "Map",
	List = { "Grasslands", "Desert", "Swamp", "Jungle", "Frost Forest", "Volcano", "Atlantis" },
	Default = cfg.map,
}, function(v)
	cfg.map = v
	save()
end)
S1.CreateBox({ Title = "Map manual (opsional)", Default = cfg.mapManual }, function(v)
	cfg.mapManual = type(v) == "string" and v or ""
	save()
end)
S1.CreateBox({ Title = "Run Mode", Default = cfg.runMode }, function(v)
	if type(v) == "string" and v ~= "" then
		cfg.runMode = v
		save()
	end
end)
S1.CreateToggle({ Title = "Kirim sinyal Created", Desc = "Seperti yang dikirim menu game", Default = cfg.created }, function(v)
	cfg.created = v and true or false
	save()
end)

local S2 = Page.CreateSection("Aksi")
local status = S2.CreateLabel({ Title = "Status: siap" })
local function setStatus(t)
	status.SetText("Status: " .. t)
end

S2.CreateButton({ Title = "Join Sekarang" }, function()
	local ok, msg = joinOnce()
	setStatus(msg)
	warn("[FS] " .. (ok and "OK " or "GAGAL ") .. msg)
end)
S2.CreateButton({ Title = "Keluar Antrean" }, function()
	setStatus(leaveQueue() and "keluar antrean" or "remote tidak ditemukan")
end)

local auto = false
S2.CreateToggle({ Title = "Auto Join", Desc = "Coba lagi tiap 20 detik; setelah berhasil tunggu 2 menit", Default = false }, function(v)
	auto = v and true or false
	if auto then
		task.spawn(function()
			while auto do
				local ok, msg = joinOnce()
				setStatus(msg)
				warn("[FS] " .. (ok and "OK " or "GAGAL ") .. msg)
				task.wait(ok and 120 or 20)
			end
		end)
	end
end)

UI.CreateNoti({ Title = "Final Swarm v3", Desc = "Challenge multi-pilih aktif. Pilih mode lalu Join.", ShowTime = 5 })
