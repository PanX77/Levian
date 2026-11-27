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
	[17625359962] = "Rivals.lua", -- Rivals
	[18126510175] = "Rivals.lua", -- Rivals (mobile)
	[117398147513099] = "Rivals.lua", -- Rivals (Match)
}


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
		writeSettings(cfg)
	end

	local sid = getSessionId()
	local function markSession()
		env.LevianIntroPlayed = true
		if sid then
			cfg.LastSession = sid
			writeSettings(cfg)
		end
	end

	local t = (time and time()) or 999
	if not game:IsLoaded() or t < 5 then
		markSession() 
		return false
	end

	if not cfg.Intro then
		return false
	end

	if env.LevianIntroPlayed or (sid and cfg.LastSession == sid) then
		return false
	end

	markSession()
	return true
end

local file = games[game.PlaceId]
if file then
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
	pcall(function()
		loadstring(game:HttpGet(base .. "unsupported.lua"))()
	end)
end
