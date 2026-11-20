-- I making script for fun, Respect me Dont steal it😄
-- discord.gg/Mc2YpMT2cF

local base = "https://levianstore.my.id/"
local games = {
	[2753915549] = "bf.lua", -- Blox Fruits Sea 1
	[4442272183] = "bf.lua", -- Sea 2
	[7449423635] = "bf.lua", -- Sea 3
	[99521272836282] = "fs.lua", -- final swarm
	[79787558257549] = "fs.lua" -- final swarm
	[72858262610964] = "tabsim.lua" -- Tab Simulator 
  
	-- [ID_GAME_BARU] = "namagame.lua",
}
local file = games[game.PlaceId]
if file then
	loadstring(game:HttpGet(base .. file))()
else
	warn("Game not supported yet: " .. tostring(game.PlaceId))
end
