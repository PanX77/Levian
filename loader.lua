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
-- Pengaturan intro
-- true  = intro hanya muncul SEKALI saja (pertama kali execute, disimpan di file executor)
-- false = intro muncul sekali per sesi (hilang kalau game/executor ditutup)
local INTRO_ONCE_EVER = true
local INTRO_FLAG_FILE = "LevianHub/intro_seen.txt"

local function shouldPlayIntro()
	local env = (getgenv and getgenv()) or _G
	if env.LevianIntroPlayed then
		return false -- sudah pernah diputar di sesi ini
	end
	env.LevianIntroPlayed = true

	if INTRO_ONCE_EVER and isfile and writefile then
		local ok, seen = pcall(isfile, INTRO_FLAG_FILE)
		if ok and seen then
			return false -- sudah pernah diputar sebelumnya
		end
		pcall(function()
			if makefolder and isfolder and not isfolder("LevianHub") then
				makefolder("LevianHub")
			end
			writefile(INTRO_FLAG_FILE, "1")
		end)
	end
	return true
end

local file = games[game.PlaceId]
if file then
	-- Intro hanya di execute pertama. Jalan bersamaan dengan script game,
	-- supaya logo bisa mendarat tepat di tombol bulat (kalau gagal, game tetap jalan)
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
