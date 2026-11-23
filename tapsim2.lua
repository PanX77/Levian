--[[
	tapsim2.lua - Tap Simulator Reborn WORLD 2 (Levian Hub)
	Memakai script utama (tapsim.lua) dengan daftar egg world 2.
	Pastikan tapsim.lua ada di server yang sama.
]]

local BASE = "https://levianstore.my.id/"

local env = getgenv()
env.TapSimTitle = " - Tap Simulator Reborn (World 2)"
env.TapSimEggs = {
	"Dead Man's Hand",
	"Deadeye",
	"Dustbone Wendigo",
	"Glacier Egg",
	"Grove Egg",
	"High Noon",
	"Jurassic Egg",
	"Medieval Egg",
	"Permafrost Egg",
	"Rift Egg",
	"Royal Egg",
	"Wild West Egg",
}

local ok, src = pcall(function()
	return game:HttpGet(BASE .. "tapsim.lua")
end)
if not ok then
	ok, src = pcall(readfile, "tapsim.lua")
end
if ok and type(src) == "string" then
	loadstring(src)()
else
	warn("[TapSim2] Gagal memuat tapsim.lua")
end
