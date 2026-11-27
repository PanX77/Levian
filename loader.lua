-- I making script for fun, Respect me Dont steal it😄
-- discord.gg/Mc2YpMT2cF

local base = "https://levianstore.my.id/"
local games = {
	[2753915549] = "bf.lua", -- Blox Fruits Sea 1
	[4442272183] = "bf.lua", -- Sea 2
	[7449423635] = "bf.lua", -- Sea 3
	[99521272836282] = "fs.lua", -- final swarm lobby
	[79787558257549] = "fs.lua", -- final swarm
	[72858262610964] = "tapsim.lua", -- Tap Simulator reborn
	[7871169780] = "minesweeper.lua", -- bLockerman's Minesweeper

	-- [ID_GAME_BARU] = "namagame.lua",
}

--------------------------------------------------------------------
-- Pengaturan intro
-- File: workspace/Levian Hub/Intro_LevianHub.txt
--   Intro=true   -> intro tampil (sekali setiap Roblox dibuka)
--   Intro=false  -> intro dimatikan
-- File ini tidak pernah dihapus dan nilai "Intro" tidak pernah diubah
-- oleh script, jadi pengguna bebas mengaktifkan/menonaktifkan manual.
--
-- Intro TIDAK muncul jika:
--   * auto execute aktif (script jalan saat game belum selesai dimuat)
--   * hanya pindah game / teleport (Roblox belum benar-benar ditutup)
--   * Intro=false di file
--------------------------------------------------------------------
local SETTINGS_DIR = "Levian Hub"
local SETTINGS_FILE = SETTINGS_DIR .. "/Intro_LevianHub.txt"

local function readSettings()
	local cfg = {Intro = true, LastSession = "", exists = false}
	if isfile and readfile then
		local ok, exists = pcall(isfile, SETTINGS_FILE)
		if ok and exists then
			cfg.exists = true
			local ok2, content = pcall(readfile, SETTINGS_FILE)
			if ok2 and type(content) == "string" then
				for line in content:gmatch("[^\r\n]+") do
					local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
					if k == "Intro" then
						local lv = v:lower()
						cfg.Intro = not (lv == "false" or lv == "off" or lv == "no" or lv == "0")
					elseif k == "LastSession" then
						cfg.LastSession = v
					end
				end
			end
		end
	end
	return cfg
end

local function writeSettings(cfg)
	if not writefile then return end
	pcall(function()
		if makefolder and isfolder and not isfolder(SETTINGS_DIR) then
			makefolder(SETTINGS_DIR)
		end
		writefile(SETTINGS_FILE, table.concat({
			"-- Levian Hub intro settings",
			"-- Intro=true  : intro tampil sekali setiap Roblox dibuka",
			"-- Intro=false : intro dimatikan",
			"-- (LastSession diisi otomatis oleh script, jangan diubah)",
			"Intro=" .. (cfg.Intro and "true" or "false"),
			"LastSession=" .. tostring(cfg.LastSession or ""),
		}, "\n"))
	end)
end

local function getSessionId()
	local ok, id = pcall(function()
		return game:GetService("RbxAnalyticsService"):GetSessionId()
	end)
	if ok and type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

local function shouldPlayIntro()
	local env = (getgenv and getgenv()) or _G
	local cfg = readSettings()
	if not cfg.exists then
		writeSettings(cfg) -- buat file default (Intro=true)
	end

	local sid = getSessionId()
	local function markSession()
		env.LevianIntroPlayed = true
		if sid then
			cfg.LastSession = sid
			writeSettings(cfg)
		end
	end

	-- 1. Auto execute: script jalan sebelum game selesai dimuat
	local t = (time and time()) or 999
	if not game:IsLoaded() or t < 5 then
		markSession() -- sesi ini dianggap sudah lewat, tidak ada intro walau execute manual nanti
		return false
	end

	-- 2. Dimatikan manual di file
	if not cfg.Intro then
		return false
	end

	-- 3. Masih sesi Roblox yang sama (pindah game / execute ulang)
	if env.LevianIntroPlayed or (sid and cfg.LastSession == sid) then
		return false
	end

	markSession()
	return true
end

local file = games[game.PlaceId]
if file then
	-- Intro jalan bersamaan dengan script game, supaya logo bisa mendarat
	-- tepat di tombol bulat (kalau gagal, game tetap jalan)
	if shouldPlayIntro() then
		task.spawn(function()
			pcall(function()
				loadstring(game:HttpGet(base .. "intro.lua"))()
			end)
		end)
	end
	loadstring(game:HttpGet(base .. file))()
else
	warn("Game not supported yet: " .. tostring(game.PlaceId))
	-- Tampilkan UI "Game not support yet" + tombol Request game script
	pcall(function()
		loadstring(game:HttpGet(base .. "unsupported.lua"))()
	end)
end
