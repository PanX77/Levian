-- I making script for fun, Respect me Dont steal it😄
-- discord.gg/Mc2YpMT2cF

local base = "https://levianstore.my.id/"
local games = {
	[123974602339071] = "tes.lua", -- Just for test
	[2753915549] = "bf.lua", -- Blox Fruits Sea 1
	[4442272183] = "bf.lua", -- Sea 2
	[7449423635] = "bf.lua", -- Sea 3
	[99521272836282] = "fs.lua", -- final swarm lobby
	[79787558257549] = "fs.lua", -- final swarm
	[72858262610964] = "tapsim.lua", -- Tap Simulator reborn
	[7871169780] = "minesweeper.lua", -- bLockerman's Minesweeper

	-- [ID_GAME_BARU] = "namagame.lua",
}
local file = games[game.PlaceId]
if file then
	-- Intro animasi Levian Hub (kalau gagal, script game tetap jalan)
	pcall(function()
		loadstring(game:HttpGet(base .. "intro.lua"))()
	end)
	loadstring(game:HttpGet(base .. file))()
else
	warn("Game not supported yet: " .. tostring(game.PlaceId))
end
