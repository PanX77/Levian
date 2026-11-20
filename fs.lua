--[[
	Levian Hub - Final Swarm (v22)
	Call order recorded from the game's own menu:
	  WorldSelection.RemoteEvent    Fire("SetRunMode", "Normal")
	  WorldSelection.RemoteEvent    Fire("SetWorld", <map>)
	  WorldSelection.RemoteEvent    Fire("SetDifficulty", <Normal|Hard|Nightmare>)
	  WorldSelection.RemoteEvent    Fire("SetChallenges", {<ids>})
	  WorldSelection.RemoteFunction Invoke("EnterQueue")  -> true
	  QueueService.RemoteEvent      Fire("PartySizeSelected", <1-4>)
	  QueueService.RemoteEvent      Fire("Created")
	Raid (recorded for Colosseum / SandWorm):
	  RaidQueueService.RemoteEvent    Fire("SelectRaid", <raid>)
	  WorldSelection.RemoteEvent      Fire("SetDifficulty", <difficulty>)
	  RaidQueueService.RemoteFunction Invoke("EnterQueue")  -> true
	  RaidQueueService.RemoteEvent    Fire("PartySizeSelected", <1-4>)
	  RaidQueueService.RemoteEvent    Fire("Created")
	Dungeon (recorded):
	  DungeonQueueService.RemoteFunction Invoke("GetFloorLimit")      -> highest unlocked floor
	  DungeonQueueService.RemoteFunction Invoke("EnterQueue", <floor>) -> true
	  DungeonQueueService.RemoteEvent    Fire("PartySizeSelected", <1-4>)
	  DungeonQueueService.RemoteEvent    Fire("Created")
	The game starts automatically after the queue is created.
]]

local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")

---------------------------------------------------------------- saved settings
local FOLDER = "Levian Hub"
local FILE = FOLDER .. "/" .. game:GetService("Players").LocalPlayer.Name .. "-finalswarm.json"
local OLD_FILE = "FinalSwarm/settings.json" -- location used by older versions
local cfg = {
	mode = "Solo",
	difficulty = "Normal",
	map = "Volcano",
	created = true,
	challenges = {},
	raid = "None",
	raidDifficulty = "Normal",
	raidMode = "Solo",
	dungeonFloor = "None",
	dungeonMode = "Solo",
	cardFallback = "Pick first card",
	cardMaxRerolls = 3,
	cardPrefer = "Weapons first",
	cardBanish = false,
	weaponsWanted = {},
	cardsWanted = {},
	banishList = {},
	bubbleMode = "Safe",
	bubbleName = "OxygenBubble",
	bubbleStay = 5,
	bubbleBelow = 80,
	bubbleSpeed = 20,
	walkRadius = 30,
	riftMode = "Safe",
	riftSpeed = 20,
	riftStay = true,
	riftName = "rift",
	riftTargets = { "Rift", "Crystal", "Circle" },
	pressMethod = "",
	afterMatch = "Nothing",
	afterDelay = 3,
	autoExecute = false,
	key = "",
	autoMinimize = false,
	flyMode = "Fly",
	flyDistance = 30,
	flyHeight = 25,
	flySpeed = 30,
	oxygenPath = "",
}
pcall(function()
	if isfile then
		local src = (isfile(FILE) and FILE) or (isfile(OLD_FILE) and OLD_FILE) or nil
		if src then
			for k, v in pairs(HttpService:JSONDecode(readfile(src))) do
				cfg[k] = v
			end
		end
	end
end)

cfg.created = true -- the "Created" signal is always sent (no UI toggle)

-- migrate values saved by older versions
local OLD_MODE = { ["2 Pemain"] = "Duo", ["3 Pemain"] = "Trio", ["4 Pemain"] = "Squad" }
cfg.mode = OLD_MODE[cfg.mode] or cfg.mode
local OLD_CHALLENGE = {
	["No Armor"] = "Barebones",
	["1 HP"] = "Made Of Glass",
	["Enemy Max"] = "Double Trouble",
	["Player Nerfs"] = "Half Strength",
	["Supdoggy Chase"] = "Supdoggy's Revenge",
	["One Weapon"] = "One Handed",
	["Inverted"] = "Dizzy Swarm",
	["First Person"] = "POV You",
}
if type(cfg.challenges) == "table" then
	for i, n in ipairs(cfg.challenges) do
		cfg.challenges[i] = OLD_CHALLENGE[n] or n
	end
else
	cfg.challenges = {}
end

local function save()
	pcall(function()
		if makefolder and not isfolder(FOLDER) then
			makefolder(FOLDER)
		end
		writefile(FILE, HttpService:JSONEncode(cfg))
	end)
end

---------------------------------------------------------------- UI library (own domain first, then GitHub)
local function loadUI()
	local urls = {
		"https://levianstore.my.id/LevianUI.lua",
		"https://levianstore.my.id/BananaUI.lua", -- old file name, fallback until LevianUI.lua is uploaded
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
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = "Final Swarm",
			Text = "Failed to load the UI library",
			Duration = 6,
		})
	end)
	return
end

-- logo of the floating button (also for older library versions that have no ApplyLogo)
local LOGO_URL = "https://levianstore.my.id/levian_logo.png"
local function applyLogoTo(b)
	if not b or b:FindFirstChild("LevianLogo") then
		return
	end
	if UI.ApplyLogo then
		if UI.ApplyLogo(b) then
			return
		end
	else
		local ok = pcall(function()
			local data = game:HttpGet(LOGO_URL)
			if makefolder and isfolder and not isfolder("Levian Hub") then
				makefolder("Levian Hub")
			end
			writefile("Levian Hub/logo.png", data)
			local img = Instance.new("ImageLabel")
			img.Name = "LevianLogo"
			img.BackgroundTransparency = 1
			img.Size = UDim2.new(1, 0, 1, 0)
			img.Image = (getcustomasset or getsynasset)("Levian Hub/logo.png")
			img.Parent = b
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 20)
			c.Parent = img
			b.Text = ""
			b.BackgroundTransparency = 1
		end)
		if ok then
			return
		end
	end
	if b.Text == "" or b.Text == "B" then
		b.Text = "X"
	end
end

---------------------------------------------------------------- key system (Panda Auth)
-- Nothing below this block runs until a valid key was entered (or the saved key is still valid).
local DISCORD = "https://discord.gg/Mc2YpMT2cF"
local PUSL
do
	local okLib, lib = pcall(function()
		return loadstring(game:HttpGet("https://secure.pandauth.com/pv4/lib"))()
	end)
	if okLib and type(lib) == "table" and type(lib.configure) == "function" then
		PUSL = lib
		pcall(PUSL.configure, { serviceId = "levianhub" })
	end
end

local function copyText(t)
	local f = setclipboard or toclipboard or (syn and syn.write_clipboard)
	return f and pcall(f, t) or false
end
local function keyNoti(title, desc, t)
	pcall(function()
		UI.CreateNoti({ Title = title, Desc = desc, ShowTime = t or 4 })
	end)
end

-- returns true + result table, or false + a short message
local function checkKey(key)
	if not PUSL then
		return false, "Key service unavailable"
	end
	key = tostring(key or ""):gsub("%s+", "")
	if key == "" then
		return false, "Enter your key first"
	end
	local ok, res = pcall(PUSL.validate, key)
	if not ok or type(res) ~= "table" then
		return false, "Could not reach the key service"
	end
	if res.success then
		return true, res
	end
	return false, tostring(res.message or res.error or "Invalid or expired key")
end

local authed = false
if tostring(cfg.key or "") ~= "" then
	local okSaved = checkKey(cfg.key)
	authed = okSaved and true or false
end

if not authed then
	local KeyMain = UI.CreateMain({ Title = "Levian Hub", Desc = " - Key System" })
	-- older library versions: remove the close (x) button and use an X logo
	pcall(function()
		for _, root in ipairs({ game:GetService("CoreGui"), (gethui and gethui()) or game:GetService("CoreGui") }) do
			local g = root:FindFirstChild("Levian Hub GUI") or root:FindFirstChild("Nousigi Hub GUI")
			if g then
				for _, d in ipairs(g:GetDescendants()) do
					if d:IsA("TextButton") and d.Text == "x" then
						d:Destroy()
					end
				end
			end
			local t = root:FindFirstChild("LevianUI Toggle") or root:FindFirstChild("BananaUI Toggle")
			local b = t and t:FindFirstChildWhichIsA("TextButton")
			if b then
				task.spawn(applyLogoTo, b)
			end
		end
	end)
	local KP = KeyMain.CreatePage({ Page_Name = "Key", Page_Title = "Key System" })
	local KS = KP.CreateSection("KEY")
	local typed = tostring(cfg.key or "")
	KS.CreateBox({ Title = "Key", Default = typed }, function(v)
		typed = tostring(v or "")
	end)
	KS.CreateButton({ Title = "Get Key" }, function()
		local okUrl, url = pcall(function()
			return PUSL.getKeyUrl()
		end)
		if not okUrl or type(url) ~= "string" or url == "" then
			keyNoti("Key", "Key service unavailable", 4)
			return
		end
		keyNoti("Get Key", copyText(url) and "Link copied - open it in your browser" or url, 6)
	end)
	KS.CreateButton({ Title = "Check Key" }, function()
		local ok, res = checkKey(typed)
		if ok then
			cfg.key = (typed:gsub("%s+", ""))
			save()
			keyNoti("Key", res.isPremium and "Authenticated (Premium)" or "Authenticated", 3)
			authed = true
		else
			keyNoti("Key", res, 4)
		end
	end)
	KS.CreateButton({ Title = "Discord" }, function()
		keyNoti("Discord", copyText(DISCORD) and "Link copied" or DISCORD, 5)
	end)
	KS.CreateLabel({ Title = "Get a key, paste it above, then press Check Key." })

	while not authed do
		task.wait(0.3)
	end
	pcall(KeyMain.Destroy)
	task.wait(0.2)
end


---------------------------------------------------------------- remotes
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
	local ws, qs, rq = root.WorldSelection, root.QueueService, root:FindFirstChild("RaidQueueService")
	local dq = root:FindFirstChild("DungeonQueueService")
	return {
		wsEvent = ws:FindFirstChildOfClass("RemoteEvent"),
		wsFunc = ws:FindFirstChildOfClass("RemoteFunction"),
		qsEvent = qs:FindFirstChildOfClass("RemoteEvent"),
		rqEvent = rq and rq:FindFirstChildOfClass("RemoteEvent"),
		rqFunc = rq and rq:FindFirstChildOfClass("RemoteFunction"),
		dqEvent = dq and dq:FindFirstChildOfClass("RemoteEvent"),
		dqFunc = dq and dq:FindFirstChildOfClass("RemoteFunction"),
	}
end

-- display name -> id sent to the server. No selection = default (no challenges)
local CHALLENGES = {
	{ "Disable Rocks", "disable_rocks" },
	{ "POV You", "first_person" },
	{ "Dizzy Swarm", "inverted" },
	{ "One Handed", "one_weapon" },
	{ "Supdoggy's Revenge", "supdoggy_chase" },
	{ "Half Strength", "player_nerfs" },
	{ "Double Trouble", "enemy_max" },
	{ "Made Of Glass", "1_hp" },
	{ "Barebones", "no_armor" },
}
local CH_NAMES = {}
for _, c in ipairs(CHALLENGES) do
	CH_NAMES[#CH_NAMES + 1] = c[1]
end

local function challengeList()
	local want, out = {}, {}
	for _, n in ipairs(cfg.challenges or {}) do
		want[n] = true
	end
	for _, c in ipairs(CHALLENGES) do
		if want[c[1]] then
			out[#out + 1] = c[2]
		end
	end
	return out
end

local PARTY_SIZE = { Solo = 1, Duo = 2, Trio = 3, Squad = 4 }

-- display name -> id sent to the server
local RAIDS = {
	{ "Colosseum", "Colosseum" },
	{ "Sand Worm", "SandWorm" },
}
local RAID_NAMES = { "None" }
for _, r in ipairs(RAIDS) do
	RAID_NAMES[#RAID_NAMES + 1] = r[1]
end
local function raidId()
	for _, r in ipairs(RAIDS) do
		if r[1] == cfg.raid then
			return r[2]
		end
	end
	return nil
end

local function joinOnce()
	if cfg.map == "None" then
		return false, "Campaign map is None"
	end
	local r = getRemotes()
	if not r or not r.wsEvent or not r.wsFunc or not r.qsEvent then
		return false, "Remotes not found - are you in the lobby?"
	end
	local size = PARTY_SIZE[cfg.mode] or 1
	local chal = challengeList()
	r.wsEvent:FireServer("SetRunMode", "Normal")
	task.wait(0.3)
	r.wsEvent:FireServer("SetWorld", cfg.map)
	task.wait(0.4)
	r.wsEvent:FireServer("SetDifficulty", cfg.difficulty)
	task.wait(0.4)
	r.wsEvent:FireServer("SetChallenges", chal)
	task.wait(0.4)
	local ok, res = pcall(function()
		return r.wsFunc:InvokeServer("EnterQueue")
	end)
	if not ok then
		return false, "EnterQueue error: " .. tostring(res)
	end
	if res ~= true then
		return false, "EnterQueue rejected: " .. tostring(res)
	end
	task.wait(0.4)
	r.qsEvent:FireServer("PartySizeSelected", size)
	if cfg.created then
		task.wait(0.3)
		r.qsEvent:FireServer("Created")
	end
	return true, ("Campaign: %s / %s / %s"):format(tostring(cfg.map), tostring(cfg.difficulty), tostring(cfg.mode))
end

local function joinRaidOnce()
	local id = raidId()
	if not id then
		return false, "Raid is None"
	end
	local r = getRemotes()
	if not r or not r.wsEvent or not r.rqEvent or not r.rqFunc then
		return false, "Raid remotes not found - in the lobby?"
	end
	local size = PARTY_SIZE[cfg.raidMode] or 1
	r.rqEvent:FireServer("SelectRaid", id)
	task.wait(0.4)
	r.wsEvent:FireServer("SetDifficulty", cfg.raidDifficulty)
	task.wait(0.4)
	local ok, res = pcall(function()
		return r.rqFunc:InvokeServer("EnterQueue")
	end)
	if not ok then
		return false, "EnterQueue error: " .. tostring(res)
	end
	if res ~= true then
		return false, "EnterQueue rejected: " .. tostring(res)
	end
	task.wait(0.4)
	r.rqEvent:FireServer("PartySizeSelected", size)
	if cfg.created then
		task.wait(0.3)
		r.rqEvent:FireServer("Created")
	end
	return true, ("Raid: %s / %s / %s"):format(
		tostring(cfg.raid), tostring(cfg.raidDifficulty), tostring(cfg.raidMode)
	)
end

local function joinDungeonOnce()
	local floor = tonumber(cfg.dungeonFloor)
	if not floor then
		return false, "Dungeon floor is None"
	end
	local r = getRemotes()
	if not r or not r.dqEvent or not r.dqFunc then
		return false, "Dungeon remotes not found - in the lobby?"
	end
	local size = PARTY_SIZE[cfg.dungeonMode] or 1
	local okL, limit = pcall(function()
		return r.dqFunc:InvokeServer("GetFloorLimit")
	end)
	limit = tonumber(limit)
	if okL and limit and floor > limit then
		floor = limit -- cannot enter a floor above the unlocked limit
	end
	task.wait(0.3)
	local ok, res = pcall(function()
		return r.dqFunc:InvokeServer("EnterQueue", floor)
	end)
	if not ok then
		return false, "EnterQueue error: " .. tostring(res)
	end
	if res ~= true then
		return false, "EnterQueue rejected: " .. tostring(res)
	end
	task.wait(0.4)
	r.dqEvent:FireServer("PartySizeSelected", size)
	task.wait(0.3)
	r.dqEvent:FireServer("Created")
	return true, ("Dungeon: Floor %d / %s"):format(floor, tostring(cfg.dungeonMode))
end

-- joins whichever of Campaign / Raid / Dungeon is not "None"
local function joinSelected()
	local active = {}
	if cfg.map ~= "None" then
		active[#active + 1] = joinOnce
	end
	if cfg.raid ~= "None" then
		active[#active + 1] = joinRaidOnce
	end
	if tonumber(cfg.dungeonFloor) then
		active[#active + 1] = joinDungeonOnce
	end
	if #active > 1 then
		return false, "Only one of Campaign / Raid / Dungeon can be active. Set the others to None."
	end
	if #active == 0 then
		return false, "Select a Map, a Raid or a Dungeon floor first."
	end
	return active[1]()
end

local function leaveQueue()
	local r = getRemotes()
	local done = false
	if r and r.qsEvent then
		r.qsEvent:FireServer("Exited")
		done = true
	end
	if r and r.rqEvent then
		r.rqEvent:FireServer("Exited")
		done = true
	end
	if r and r.dqEvent then
		r.dqEvent:FireServer("Exited")
		done = true
	end
	return done
end

---------------------------------------------------------------- auto card (in-match)
-- Card UI structure found with the scanner:
--   PlayerGui.Frames.Upgrades.Holder.Selection1..N      (ImageButton, 3-5 offers; name in .ItemTitle)
--   PlayerGui.Frames.Upgrades.RerollFrame.RerollButton  (re-roll the offers)
--   PlayerGui.Frames.Upgrades.RerollFrame.BanishButton  (press it, then press the card to remove)
-- Picking = pressing the card button, so the game itself sends the choice.
local WEAPONS = {
	"Daggers", "Bow", "Sword", "Shotgun", "Revolver", "Frost Walker", "Paintball Gun", "Poison Flask",
	"Ninja Star", "Spike Ball", "Flame Walker", "Lightning Staff", "Bananarang", "Sniper", "Axe", "Missile",
	"Firestaff", "Tornado", "Flamethrower", "Aura", "Pumpkin Staff", "Minigun", "Ban Hammer", "Trident",
	"Laserbeam", "Excalibur", "Cursed Diary", "Subspace Tripmine", "Mjolnir", "Aegis", "Void Scythe",
	"Jack-o'-Launcher", "Inferno Sword",
}
local CARDS = {
	"Armor", "Attack Speed", "Crit Chance", "Crit Damage", "Damage", "Health", "Knock Resistance", "Luck",
	"Movement Speed", "Projectile Speed", "Regen", "Blaze", "Boss Damage", "Demon Slayer", "Firestorm",
	"Freeze", "Frostwater", "Landslide", "Lifesteal", "Lightning Rod", "Nightshade", "Piercing", "Prismatic",
	"Purity", "Ricochet", "Size", "Stand Strong", "Thorns", "XP Gain", "Giant Strength", "Projectile Count",
	"Soul Swiftness", "Wind Blessing", "Extra Jump", "Multishot", "Power Trio", "Undying",
}
local BANISH_ALL = {}
for _, n in ipairs(WEAPONS) do
	BANISH_ALL[#BANISH_ALL + 1] = n
end
for _, n in ipairs(CARDS) do
	BANISH_ALL[#BANISH_ALL + 1] = n
end

local function norm(s)
	return (tostring(s or ""):lower():gsub("[^%w]", ""))
end
-- alternative spellings that may appear in the game
local ALIAS = { pumpkinstaff = { "pumkinstaff" }, mjolnir = { "mjolnier" }, critchance = { "critchange" } }
local function nameMatches(offered, listed)
	local a, b = norm(offered), norm(listed)
	if a == b then
		return true
	end
	for _, al in ipairs(ALIAS[b] or {}) do
		if a == al then
			return true
		end
	end
	return false
end
local function inList(list, name)
	for _, n in ipairs(list or {}) do
		if nameMatches(name, n) then
			return true
		end
	end
	return false
end
-- multi-select result (set) -> array in list order
local function toArray(order, sel)
	local out = {}
	for _, n in ipairs(order) do
		if type(sel) == "table" and sel[n] then
			out[#out + 1] = n
		end
	end
	return out
end

local function localPG()
	return game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
end

local function isShown(o)
	local pg = localPG()
	local p = o
	while p and p ~= pg do
		if p:IsA("GuiObject") and not p.Visible then
			return false
		end
		if p:IsA("ScreenGui") and not p.Enabled then
			return false
		end
		p = p.Parent
	end
	return true
end

local function cleanText(t)
	t = tostring(t or ""):gsub("<[^>]+>", "")
	t = t:gsub("%s+", " ")
	return (t:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function cardUI()
	local pg = localPG()
	local f = pg and pg:FindFirstChild("Frames")
	local up = f and f:FindFirstChild("Upgrades")
	return up, up and up:FindFirstChild("Holder"), up and up:FindFirstChild("RerollFrame")
end

local function getCards()
	local up, holder = cardUI()
	if not up or not holder or not isShown(up) then
		return nil
	end
	local cards = {}
	for _, c in ipairs(holder:GetChildren()) do
		if c:IsA("GuiButton") and c.Name:match("^Selection%d+$") and isShown(c) then
			local t = c:FindFirstChild("ItemTitle")
			cards[#cards + 1] = { btn = c, name = cleanText(t and t.Text), x = c.AbsolutePosition.X }
		end
	end
	table.sort(cards, function(a, b)
		return a.x < b.x
	end)
	return (#cards > 0) and cards or nil
end

-- Several ways to press a GUI button. The first one that visibly works is remembered (bestMethod).
local function centerOf(b)
	local gui = b:FindFirstAncestorOfClass("ScreenGui")
	local inset = Vector2.zero
	if not (gui and gui.IgnoreGuiInset) then
		inset = game:GetService("GuiService"):GetGuiInset()
	end
	local p = b.AbsolutePosition + b.AbsoluteSize / 2 + inset
	return p.X, p.Y
end

local METHODS = {
	{
		"signal",
		function(b)
			if not firesignal then
				return false
			end
			local ran = false
			for _, name in ipairs({ "MouseButton1Click", "Activated" }) do
				local ok = pcall(function()
					firesignal(b[name])
				end)
				ran = ran or ok
			end
			return ran
		end,
	},
	{
		"connections",
		function(b)
			if not getconnections then
				return false
			end
			local n = 0
			for _, name in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down", "MouseButton1Up" }) do
				local ok, list = pcall(getconnections, b[name])
				if ok and type(list) == "table" then
					for _, c in ipairs(list) do
						if type(c.Function) == "function" then
							pcall(c.Function)
						elseif c.Fire then
							pcall(function()
								c:Fire()
							end)
						end
						n += 1
					end
				end
			end
			return n > 0
		end,
	},
	{
		"click",
		function(b)
			local okS, vim = pcall(function()
				return game:GetService("VirtualInputManager")
			end)
			if not okS or not vim then
				return false
			end
			local x, y = centerOf(b)
			vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
			task.wait(0.06)
			vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
			return true
		end,
	},
	{
		"touch",
		function(b)
			local okS, vim = pcall(function()
				return game:GetService("VirtualInputManager")
			end)
			if not okS or not vim then
				return false
			end
			local x, y = centerOf(b)
			vim:SendTouchEvent(1, 0, x, y)
			task.wait(0.06)
			vim:SendTouchEvent(1, 2, x, y)
			return true
		end,
	},
}
-- real-input style first; the method that worked last time is remembered between sessions
local PREF = { click = 1, connections = 2, signal = 3, touch = 4 }
table.sort(METHODS, function(a, b)
	return PREF[a[1]] < PREF[b[1]]
end)
local bestMethod = nil
for i, m in ipairs(METHODS) do
	if m[1] == cfg.pressMethod then
		bestMethod = i
	end
end

-- press once with the best known method, no verification
local function pressRaw(btn)
	local m = METHODS[bestMethod or 1]
	local ok = pcall(m[2], btn)
	return ok
end

-- press and check (up to ~1s per method) that something changed; falls through to the next method otherwise
local function pressVerified(btn, check)
	local order = {}
	if bestMethod then
		order[1] = bestMethod
	end
	for i = 1, #METHODS do
		if i ~= bestMethod then
			order[#order + 1] = i
		end
	end
	for _, i in ipairs(order) do
		local ok, res = pcall(METHODS[i][2], btn)
		if ok and res ~= false then
			for _ = 1, 20 do
				task.wait(0.05)
				if check() then
					bestMethod = i
					if cfg.pressMethod ~= METHODS[i][1] then
						cfg.pressMethod = METHODS[i][1]
						save()
					end
					return true, METHODS[i][1]
				end
			end
		end
	end
	return false
end

-- manual players click anywhere to skip the card-reveal animation: click the (non-button) title area
-- wait until every card stopped moving (the reveal animation is over); returns false if the offer vanished
local function cardsLayout()
	local cards = getCards()
	if not cards then
		return nil
	end
	local parts = {}
	for _, c in ipairs(cards) do
		local p, sz = c.btn.AbsolutePosition, c.btn.AbsoluteSize
		parts[#parts + 1] = string.format("%d,%d,%d,%d", p.X, p.Y, sz.X, sz.Y)
	end
	return table.concat(parts, "|")
end
local function waitSettled(maxWait)
	local t0, last, stable = os.clock(), nil, 0
	while os.clock() - t0 < maxWait do
		local lay = cardsLayout()
		if not lay then
			return false
		end
		if lay == last then
			stable += 1
			if stable >= 3 then
				return true
			end
		else
			stable, last = 0, lay
		end
		task.wait(0.05)
	end
	return true
end

local function skipAnimation()
	local up = cardUI()
	local target = up and up:FindFirstChild("TitleFrame")
	if not target then
		return
	end
	local okS, vim = pcall(function()
		return game:GetService("VirtualInputManager")
	end)
	if not okS or not vim then
		return
	end
	for _ = 1, 2 do
		local x, y = centerOf(target)
		x, y = x + math.random(-15, 15), y + math.random(-4, 4)
		pcall(function()
			vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
			task.wait(0.03)
			vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
		end)
		task.wait(0.08)
	end
end

local function frameButton(word)
	local _, _, rf = cardUI()
	if not rf then
		return nil
	end
	for _, c in ipairs(rf:GetDescendants()) do
		if c:IsA("GuiButton") and c.Name:lower():find(word, 1, true) and isShown(c) then
			return c
		end
	end
	return nil
end

local function noti(title, desc, t)
	UI.CreateNoti({ Title = title, Desc = desc, ShowTime = t or 3 })
end

-- pick a wanted card: weapons and cards are separate lists, "Prefer" decides which wins
local function chooseCard(cards)
	local bestW, bestC
	for _, c in ipairs(cards) do
		if not bestW and inList(cfg.weaponsWanted, c.name) then
			bestW = c
		end
		if not bestC and inList(cfg.cardsWanted, c.name) then
			bestC = c
		end
	end
	if cfg.cardPrefer == "Cards first" then
		return bestC or bestW
	end
	return bestW or bestC
end

local function offerSig()
	local cards = getCards()
	if not cards then
		return nil
	end
	local names = {}
	for _, c in ipairs(cards) do
		names[#names + 1] = c.name
	end
	return table.concat(names, "|")
end

local cardAuto, cardToken = false, nil
local lastSig, lastAt, rerolls, banishes, failedSig = "", 0, 0, 0, nil
local function cardStep()
	local sig = offerSig()
	if not sig then
		lastSig, rerolls, banishes, failedSig = "", 0, 0, nil
		return
	end
	if sig == lastSig and os.clock() - lastAt < 4 then
		return -- this offer was already handled
	end
	lastSig, lastAt = sig, os.clock()
	skipAnimation()
	waitSettled(3)
	local cards = getCards()
	if not cards then
		return
	end
	sig = offerSig() or sig -- the offer may still have been filling in: use what is on screen now
	lastSig = sig
	local function changed()
		return offerSig() ~= sig
	end
	-- press a card and only report success if the offer really changed
	local function choose(c, label)
		local ok, how = pressVerified(c.btn, changed)
		if ok then
			noti("Auto Card", label .. c.name .. " (" .. how .. ")", 3)
			return true
		end
		if failedSig ~= sig then
			failedSig = sig
			noti("Auto Card", "Could not press: " .. c.name, 4)
		end
		return false
	end

	local pick = chooseCard(cards)
	if pick then
		choose(pick, "Picked: ")
		return
	end

	-- nothing wanted: banish an unwanted card (opt-in, only after a press method was verified once)
	if cfg.cardBanish and bestMethod and banishes < 3 then
		for _, c in ipairs(cards) do
			if inList(cfg.banishList, c.name) then
				local bb = frameButton("banish")
				if bb then
					pressRaw(bb)
					task.wait(0.5)
					if choose(c, "Banished: ") then
						banishes += 1
						return
					end
				end
				break
			end
		end
	end

	local mode = cfg.cardFallback
	if mode == "Do nothing" then
		return
	end
	if mode == "Reroll" and rerolls < (tonumber(cfg.cardMaxRerolls) or 0) then
		local rb = frameButton("reroll")
		if rb then
			local ok, how = pressVerified(rb, changed)
			if ok then
				rerolls += 1
				noti("Auto Card", "Reroll " .. rerolls .. "/" .. tostring(cfg.cardMaxRerolls) .. " (" .. how .. ")", 2)
				return
			end
		end
	end
	local fallback = cards[1]
	for _, c in ipairs(cards) do
		if not inList(cfg.banishList, c.name) then
			fallback = c
			break
		end
	end
	choose(fallback, "Picked: ")
end

---------------------------------------------------------------- auto bubble (in-match)
-- The scanner showed the bubbles are Models named "OxygenBubble" inside workspace.EnvironmentOxygenBubbles.
-- If that folder exists it is used directly; otherwise parts/models whose name contains the text in
-- "Bubble name contains" are searched in the whole workspace.
-- Safe  = Roblox's own walking (Humanoid:MoveTo)
-- Tween = moves the character toward the bubble at the speed set by "Tween speed"
---------------------------------------------------------------- oxygen reading
-- Returns oxygen as a percentage (0-100) and a short description of where it came from.
-- Order: optional PlayerGui path from the menu -> attributes -> Value objects -> an "oxygen" bar in PlayerGui.
local function percentFromGui(o)
	if o:IsA("TextLabel") or o:IsA("TextButton") then
		local txt = cleanText(o.Text)
		local a, b = txt:match("(%d+%.?%d*)%s*/%s*(%d+%.?%d*)")
		if a and b and tonumber(b) > 0 then
			return tonumber(a) / tonumber(b) * 100
		end
		local pct = txt:match("(%d+%.?%d*)%s*%%")
		if pct then
			return tonumber(pct)
		end
		return nil
	end
	if o:IsA("GuiObject") then
		local p = o.Parent
		if p and p:IsA("GuiObject") then
			local ps, os_ = p.AbsoluteSize, o.AbsoluteSize
			if ps.X >= ps.Y and ps.X > 0 then
				return math.clamp(os_.X / ps.X * 100, 0, 100)
			elseif ps.Y > 0 then
				return math.clamp(os_.Y / ps.Y * 100, 0, 100)
			end
		end
	end
	return nil
end

local function resolvePath(path)
	local cur = localPG()
	for part in tostring(path):gmatch("[^%.]+") do
		cur = cur and cur:FindFirstChild(part)
	end
	return cur
end

local function fromAttributes(inst)
	local cur, max
	for name, v in pairs(inst:GetAttributes()) do
		local n = name:lower()
		if type(v) == "number" and n:find("oxygen", 1, true) then
			if n:find("max", 1, true) then
				max = v
			else
				cur = cur or v
			end
		end
	end
	if cur then
		if max and max > 0 then
			return math.clamp(cur / max * 100, 0, 100)
		end
		if cur <= 1 then
			return cur * 100
		end
		return math.clamp(cur, 0, 100)
	end
	return nil
end

local function fromValues(root)
	local cur, max
	for _, v in ipairs(root:GetDescendants()) do
		if (v:IsA("NumberValue") or v:IsA("IntValue")) and v.Name:lower():find("oxygen", 1, true) then
			if v.Name:lower():find("max", 1, true) then
				max = v.Value
			else
				cur = cur or v.Value
			end
		end
	end
	if cur then
		if max and max > 0 then
			return math.clamp(cur / max * 100, 0, 100)
		end
		if cur <= 1 then
			return cur * 100
		end
		return math.clamp(cur, 0, 100)
	end
	return nil
end

local oxyGui, oxyGuiTry = nil, 0
local function findOxygenGui()
	local pg = localPG()
	if not pg then
		return nil
	end
	for _, d in ipairs(pg:GetDescendants()) do
		if d:IsA("GuiObject") then
			local n = d.Name:lower()
			if n:find("oxygen", 1, true) or n:find("breath", 1, true) then
				local cands = { d }
				for _, c in ipairs(d:GetDescendants()) do
					cands[#cands + 1] = c
				end
				for _, c in ipairs(cands) do
					if c:IsA("GuiObject") then
						local cn = c.Name:lower()
						if
							(c:IsA("TextLabel") or cn:find("fill", 1, true) or cn:find("bar", 1, true) or cn:find("progress", 1, true))
							and percentFromGui(c)
						then
							return c
						end
					end
				end
			end
		end
	end
	return nil
end

local function readOxygen()
	local lp = game:GetService("Players").LocalPlayer
	local char = lp.Character
	-- 1) path typed in the menu
	if cfg.oxygenPath and cfg.oxygenPath ~= "" then
		local o = resolvePath(cfg.oxygenPath)
		local p = o and percentFromGui(o)
		if p then
			return p, "path: " .. cfg.oxygenPath
		end
	end
	-- 2) attributes and Value objects
	for _, inst in ipairs({ lp, char, char and char:FindFirstChildOfClass("Humanoid") }) do
		local p = inst and fromAttributes(inst)
		if p then
			return p, "attribute on " .. inst.Name
		end
	end
	for _, root in ipairs({ char, lp:FindFirstChild("leaderstats"), lp:FindFirstChild("Data") }) do
		local p = root and fromValues(root)
		if p then
			return p, "value in " .. root.Name
		end
	end
	-- 3) an oxygen bar / label in the UI (cached)
	if not (oxyGui and oxyGui.Parent) and os.clock() - oxyGuiTry > 2 then
		oxyGuiTry = os.clock()
		oxyGui = findOxygenGui()
	end
	if oxyGui and oxyGui.Parent then
		local p = percentFromGui(oxyGui)
		if p then
			return p, "ui: " .. oxyGui.Name
		end
	end
	return nil, "not found"
end

local RunService = game:GetService("RunService")
local bubbleAuto, bubbleToken = false, nil
local bubbleBusy = false -- true while the bubble loop is moving the character
local bubbleCache, bubbleCacheAt, bubbleVisited = {}, 0, {}

local function objPos(o)
	if o:IsA("Model") then
		return o:GetPivot().Position
	end
	return o.Position
end

local function bubbleCandidates(hrp, char)
	if os.clock() - bubbleCacheAt > 1 then
		bubbleCacheAt = os.clock()
		bubbleCache = {}
		local pat = norm(cfg.bubbleName)
		if pat == "" then
			pat = "bubble"
		end
		local folder = workspace:FindFirstChild("EnvironmentOxygenBubbles")
		local pool = folder and folder:GetChildren() or workspace:GetDescendants()
		for _, d in ipairs(pool) do
			if
				(d:IsA("BasePart") or d:IsA("Model"))
				and not d:IsDescendantOf(char)
				and (folder ~= nil or norm(d.Name):find(pat, 1, true))
			then
				bubbleCache[#bubbleCache + 1] = d
			end
		end
	end
	local out = {}
	for _, d in ipairs(bubbleCache) do
		if d.Parent and (not bubbleVisited[d] or os.clock() - bubbleVisited[d] > 8) then
			local p = objPos(d)
			out[#out + 1] = { inst = d, pos = p, dist = (p - hrp.Position).Magnitude }
		end
	end
	table.sort(out, function(a, b)
		return a.dist < b.dist
	end)
	return out
end

local function bubbleLoop(token)
	local warnedOxy = false
	while bubbleAuto and bubbleToken == token do
		local char = game:GetService("Players").LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then
			task.wait(1)
		else
			local oxy = readOxygen()
			local thr = tonumber(cfg.bubbleBelow) or 80
			if oxy == nil and not warnedOxy then
				warnedOxy = true
				noti("Auto Bubble", "Oxygen not found - collecting bubbles without a limit", 5)
			end
			if oxy and oxy >= thr then
				task.wait(0.5) -- oxygen is above the limit: stay where you are
			else
			local target = bubbleCandidates(hrp, char)[1]
			if not target then
				task.wait(0.5)
			else
				local started = os.clock()
				bubbleBusy = true
				while bubbleAuto and bubbleToken == token and os.clock() - started < 20 do
					local inst = target.inst
					if not inst.Parent or not hrp.Parent or hum.Health <= 0 then
						break
					end
					local dir = objPos(inst) - hrp.Position
					if dir.Magnitude < 3 then
						break
					end
					if cfg.bubbleMode == "Tween" then
						local dt = RunService.Heartbeat:Wait()
						local step = math.min(math.max(tonumber(cfg.bubbleSpeed) or 20, 1) * dt, dir.Magnitude)
						hrp.CFrame = hrp.CFrame + dir.Unit * step
						hrp.AssemblyLinearVelocity = Vector3.zero
					else
						hum:MoveTo(objPos(inst))
						task.wait(0.25)
					end
				end
				bubbleVisited[target.inst] = os.clock()
				bubbleBusy = false
			end
			end
		end
	end
end

---------------------------------------------------------------- auto rift (in-match)
-- Rift objects live in workspace.Map.RiftRuntime (found with the scanner):
--   Rift (Model)  |  Shard.Crystal (MeshParts)  |  Checkpoint.Circle (MeshPart)
-- It goes to the nearest one of the target types chosen in the menu.
-- Safe = Roblox walking (Humanoid:MoveTo), Tween = moves at the "Tween speed" set in the menu.
-- With "Stay at rift" on it stays next to the rift while it exists. Auto Bubble has priority (oxygen).
local riftAuto, riftToken = false, nil
local riftBusy = false -- true while the rift loop is moving the character
local flyBusy = false -- true while Auto Farm (fly) is moving the character
local riftCache, riftCacheAt, riftVisited = {}, 0, {}

local function riftCandidates(hrp, char)
	if os.clock() - riftCacheAt > 1 then
		riftCacheAt = os.clock()
		riftCache = {}
		local map = workspace:FindFirstChild("Map")
		local root = map and map:FindFirstChild("RiftRuntime")
		if root then
			local want = {}
			for _, n in ipairs(cfg.riftTargets or {}) do
				want[norm(n)] = true
			end
			for _, d in ipairs(root:GetDescendants()) do
				if (d:IsA("BasePart") or d:IsA("Model")) and want[norm(d.Name)] then
					riftCache[#riftCache + 1] = d
				end
			end
		end
	end
	local set = {}
	for _, d in ipairs(riftCache) do
		set[d] = true
	end
	local out = {}
	for _, d in ipairs(riftCache) do
		if d.Parent and (not riftVisited[d] or os.clock() - riftVisited[d] > 8) then
			-- skip parts that belong to a model that is already a candidate
			local nested, p = false, d.Parent
			while p and p ~= workspace do
				if set[p] then
					nested = true
					break
				end
				p = p.Parent
			end
			if not nested then
				local pos = objPos(d)
				out[#out + 1] = { inst = d, pos = pos, dist = (pos - hrp.Position).Magnitude }
			end
		end
	end
	table.sort(out, function(a, b)
		return a.dist < b.dist
	end)
	return out
end

local function riftLoop(token)
	while riftAuto and riftToken == token do
		local char = game:GetService("Players").LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then
			task.wait(1)
		elseif bubbleBusy then
			task.wait(0.3) -- oxygen first
		else
			local target = riftCandidates(hrp, char)[1]
			if not target then
				task.wait(0.5)
			else
				local started = os.clock()
				riftBusy = true
				while riftAuto and riftToken == token and not bubbleBusy and os.clock() - started < 25 do
					local inst = target.inst
					if not inst.Parent or not hrp.Parent or hum.Health <= 0 then
						break
					end
					local pos = objPos(inst)
					local dir = pos - hrp.Position
					if dir.Magnitude < 4 then
						if not cfg.riftStay then
							break
						end
						task.wait(0.3) -- stay next to the rift
						started = os.clock()
					elseif cfg.riftMode == "Tween" then
						local dt = RunService.Heartbeat:Wait()
						local step = math.min(math.max(tonumber(cfg.riftSpeed) or 20, 1) * dt, dir.Magnitude)
						hrp.CFrame = hrp.CFrame + dir.Unit * step
						hrp.AssemblyLinearVelocity = Vector3.zero
					else
						hum:MoveTo(pos)
						task.wait(0.25)
					end
				end
				riftVisited[target.inst] = os.clock()
				riftBusy = false
			end
		end
	end
	riftBusy = false
end

---------------------------------------------------------------- walk around (in-match)
-- Walks to random points around where you were when it was switched on (Roblox walking, Humanoid:MoveTo).
-- It pauses while Auto Bubble, Auto Rift or Auto Farm is moving the character.
local walkAuto, walkToken = false, nil
local function groundAt(pos, char)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position.Y or pos.Y
end

local function walkLoop(token)
	local center
	while walkAuto and walkToken == token do
		local char = game:GetService("Players").LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then
			center = nil
			task.wait(1)
		elseif bubbleBusy or riftBusy or flyBusy then
			center = nil -- take a new centre after the bubble/rift/fly
			task.wait(0.3)
		else
			center = center or hrp.Position
			local r = math.max(tonumber(cfg.walkRadius) or 30, 5)
			local ang, dist = math.random() * math.pi * 2, 5 + math.random() * (r - 5)
			local flat = center + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
			local target = Vector3.new(flat.X, groundAt(flat, char) + 3, flat.Z)
			hum:MoveTo(target)
			local t0 = os.clock()
			while walkAuto and walkToken == token and not bubbleBusy and not riftBusy and not flyBusy and os.clock() - t0 < 6 do
				local dx, dz = hrp.Position.X - target.X, hrp.Position.Z - target.Z
				if math.sqrt(dx * dx + dz * dz) < 3 then
					break
				end
				task.wait(0.2)
			end
			task.wait(0.3 + math.random() * 1.2) -- short pause like a player
		end
	end
end

---------------------------------------------------------------- auto farm: fly in a circle (in-match)
-- Flies around a circle. Centre = where you were when it was switched on,
-- Distance = radius (studs), Height = height above the ground at the centre, Speed = studs per second.
-- Auto Bubble and Auto Rift have priority (they take over, then the circle continues).
local flyAuto, flyToken = false, nil
local function flyLoop(token)
	local center, ground, angle, cur
	while flyAuto and flyToken == token do
		local char = game:GetService("Players").LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then
			center, ground, cur = nil, nil, nil
			flyBusy = false
			task.wait(1)
		elseif bubbleBusy or riftBusy then
			flyBusy = false
			cur = nil -- take over from the real position after the trip
			hum.PlatformStand = false
			RunService.Heartbeat:Wait()
		else
			local r = math.clamp(tonumber(cfg.flyDistance) or 30, 1, 100)
			local h = math.clamp(tonumber(cfg.flyHeight) or 25, 1, 100)
			local sp = math.clamp(tonumber(cfg.flySpeed) or 30, 1, 100)
			if not center then
				center = hrp.Position
				ground = groundAt(center, char)
			end
			local dt = RunService.Heartbeat:Wait()
			flyBusy = true
			angle = (angle or 0) + math.min(sp / r, 6) * dt -- angular speed so the linear speed is ~Speed
			local target = Vector3.new(center.X + math.cos(angle) * r, ground + h, center.Z + math.sin(angle) * r)
			cur = cur or hrp.Position
			local delta = target - cur
			local dist = delta.Magnitude
			local step = math.max(sp * 2, 40) * dt -- catches up smoothly, never a teleport
			cur = (dist <= step) and target or (cur + delta.Unit * step)
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			hum.PlatformStand = true
			hrp.CFrame = CFrame.lookAt(cur, cur + tangent)
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end
	flyBusy = false
	local char = game:GetService("Players").LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
	end
end

---------------------------------------------------------------- after match (replay / lobby)
-- Flow described for the game:
--   win  : "VICTORY" -> "tap to continue..." -> items -> buttons Lobby / Again / Stats
--   lose : "Give Up" button -> "DEFEAT" + "tap to continue..." -> items -> buttons Lobby / Again / Stats
-- It never presses "Lobby" mid-match: the result buttons must be on screen together (Again + Lobby).
-- text of a label, or of a small labelled button (a big container button returns "")
local function buttonLabel(o)
	if o:IsA("TextButton") or o:IsA("TextLabel") then
		return cleanText(o.Text)
	end
	if o:IsA("GuiButton") then
		local parts, n = {}, 0
		for _, c in ipairs(o:GetDescendants()) do
			if (c:IsA("TextLabel") or c:IsA("TextButton")) and c.Text ~= "" then
				n += 1
				if n > 3 then
					return ""
				end
				parts[#parts + 1] = cleanText(c.Text)
			end
		end
		local joined = table.concat(parts, " ")
		return #joined <= 30 and joined or ""
	end
	return ""
end

local function preferButton(old, new)
	if not old then
		return new
	end
	if not old:IsA("GuiButton") and new:IsA("GuiButton") then
		return new
	end
	return old
end

-- returns kind ("result" | "defeat" | "continue") and the elements found, or nil.
-- Elements can be buttons OR plain text labels (the clickable part may be a separate transparent button).
local function scanEnd()
	local pg = localPG()
	if not pg then
		return nil
	end
	local defeatE, continueE
	for _, gui in ipairs(pg:GetChildren()) do
		if gui:IsA("ScreenGui") and gui.Enabled then
			local again, lobby, giveUp, deathText, cont
			for _, d in ipairs(gui:GetDescendants()) do
				if (d:IsA("GuiButton") or d:IsA("TextLabel")) and isShown(d) then
					local n = norm(buttonLabel(d))
					if n ~= "" then
						if n:find("again", 1, true) or n:find("replay", 1, true) or n:find("retry", 1, true) then
							again = preferButton(again, d)
						elseif n:find("lobby", 1, true) then
							lobby = preferButton(lobby, d)
						elseif n:find("giveup", 1, true) then
							giveUp = preferButton(giveUp, d)
						end
						if n:find("defeat", 1, true) or n:find("died", 1, true) or n:find("revive", 1, true) then
							deathText = true
						end
						if (n:find("tap", 1, true) or n:find("click", 1, true)) and n:find("continue", 1, true) then
							cont = cont or d
						end
					end
				end
			end
			if again and lobby then
				return "result", { again = again, lobby = lobby }
			end
			if deathText and giveUp and not defeatE then
				defeatE = { giveUp = giveUp }
			end
			if cont and not continueE then
				continueE = { cont = cont }
			end
		end
	end
	if defeatE then
		return "defeat", defeatE
	end
	if continueE then
		return "continue", continueE
	end
	return nil
end

-- real click on the element's position (works even when the clickable part is another, invisible object)
local function pressByPosition(el, check)
	local okS, vim = pcall(function()
		return game:GetService("VirtualInputManager")
	end)
	if not okS or not vim then
		return false
	end
	local x, y = centerOf(el)
	for _, kind in ipairs({ "mouse", "touch" }) do
		pcall(function()
			if kind == "mouse" then
				vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
				task.wait(0.05)
				vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
			else
				vim:SendTouchEvent(1, 0, x, y)
				task.wait(0.05)
				vim:SendTouchEvent(1, 2, x, y)
			end
		end)
		for _ = 1, 20 do
			task.wait(0.05)
			if check() then
				return true, "position " .. kind
			end
		end
	end
	return false
end

local function pressElement(el, check)
	local btn = el:IsA("GuiButton") and el or el:FindFirstAncestorWhichIsA("GuiButton")
	if btn then
		local ok, how = pressVerified(btn, check)
		if ok then
			return true, how
		end
	end
	return pressByPosition(el, check)
end

-- a plain click in the middle of the screen ("click screen to continue")
local function clickScreen()
	local okS, vim = pcall(function()
		return game:GetService("VirtualInputManager")
	end)
	if not okS or not vim then
		return false
	end
	local cam = workspace.CurrentCamera
	local size = cam and cam.ViewportSize or Vector2.new(800, 600)
	local x = size.X * (0.45 + math.random() * 0.1)
	local y = size.Y * (0.45 + math.random() * 0.1)
	pcall(function()
		vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
		task.wait(0.05)
		vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
	end)
	return true
end

local afterSeenAt, afterDoneAt, afterFailed, lastContinue, gaveUpAt, afterStage = nil, 0, false, 0, 0, nil
local function stage(name, msg)
	if afterStage ~= name then
		afterStage = name
		noti("After match", msg, 3)
	end
end
local function afterStep()
	if cfg.afterMatch == "Nothing" then
		afterSeenAt, afterStage = nil, nil
		return
	end
	if os.clock() - afterDoneAt < 20 then
		return
	end
	local kind, e = scanEnd()
	if kind == "result" then
		stage("result", "Result screen found")
		afterSeenAt = afterSeenAt or os.clock()
		if os.clock() - afterSeenAt < (tonumber(cfg.afterDelay) or 3) then
			return
		end
		local el = (cfg.afterMatch == "Replay") and e.again or e.lobby
		local label = buttonLabel(el)
		local ok, how = pressElement(el, function()
			return not el.Parent or not isShown(el)
		end)
		if ok then
			afterDoneAt = os.clock()
			noti("After match", cfg.afterMatch .. ": " .. label .. " (" .. how .. ")", 4)
		elseif not afterFailed then
			afterFailed = true
			noti("After match", "Could not press: " .. label, 4)
		end
	elseif kind == "defeat" then
		afterSeenAt = nil
		stage("defeat", "You died - giving up")
		if os.clock() - gaveUpAt > 5 then
			gaveUpAt = os.clock()
			local el = e.giveUp
			pressElement(el, function()
				return not el.Parent or not isShown(el)
			end)
		end
	elseif kind == "continue" then
		afterSeenAt = nil
		stage("continue", "Tap to continue")
		if os.clock() - lastContinue > 1.2 then
			lastContinue = os.clock()
			clickScreen()
		end
	else
		afterSeenAt, afterFailed, afterStage = nil, false, nil
	end
end

-- one background loop (a newer run of the script replaces the older one)
local afterToken = {}
getgenv().__LV_AFTER = afterToken
task.spawn(function()
	while getgenv().__LV_AFTER == afterToken do
		pcall(afterStep)
		task.wait(0.8)
	end
end)

---------------------------------------------------------------- auto execute (re-run after teleport)
local LOADER_URL = "https://levianstore.my.id/loader.lua"
local LINK = "https://discord.gg/Mc2YpMT2cF"

local function queueReload()
	if getgenv().__LV_QUEUED then
		return true -- already queued in this session
	end
	local q = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
	if not q then
		return false
	end
	local code = ([[
if not game:IsLoaded() then game.Loaded:Wait() end
local ok, saved = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile(%q)) end)
if ok and type(saved) == "table" and saved.autoExecute == false then return end
loadstring(game:HttpGet(%q))()
]]):format(FILE, LOADER_URL)
	local ok = pcall(q, code)
	if ok then
		getgenv().__LV_QUEUED = true
	end
	return ok
end

local tpConn
local function setAutoExecute(on)
	cfg.autoExecute = on and true or false
	save()
	if cfg.autoExecute then
		local ok = queueReload()
		if not ok then
			UI.CreateNoti({ Title = "Auto Execute", Desc = "queue_on_teleport is not supported by this executor", ShowTime = 5 })
		end
		if not tpConn then
			tpConn = game:GetService("Players").LocalPlayer.OnTeleport:Connect(function()
				if cfg.autoExecute then
					queueReload()
				end
			end)
		end
	end
end

---------------------------------------------------------------- configs (named snapshots of the menu)
local CFGFILE = FOLDER .. "/" .. game:GetService("Players").LocalPlayer.Name .. "-finalswarm-configs.json"
local store = { configs = {}, autoLoad = "" }
pcall(function()
	if isfile and isfile(CFGFILE) then
		local d = HttpService:JSONDecode(readfile(CFGFILE))
		if type(d) == "table" then
			store.configs = type(d.configs) == "table" and d.configs or {}
			store.autoLoad = type(d.autoLoad) == "string" and d.autoLoad or ""
		end
	end
end)
local function saveStore()
	pcall(function()
		if makefolder and not isfolder(FOLDER) then
			makefolder(FOLDER)
		end
		writefile(CFGFILE, HttpService:JSONEncode(store))
	end)
end
local function configNames()
	local n = {}
	for name in pairs(store.configs) do
		n[#n + 1] = name
	end
	table.sort(n)
	return n
end
local function cleanName(v)
	v = tostring(v or ""):gsub("[^%w _%-]", "")
	v = v:gsub("^%s+", ""):gsub("%s+$", "")
	return v:sub(1, 30)
end

-- reg: setting key -> menu control, tog: toggle name -> menu control, on: current state of the runtime toggles
local reg, tog = {}, {}
local on = { autoJoin = false, autoCard = false, autoBubble = false, autoRift = false, walk = false, autoFarm = false }
local SKIP = { pressMethod = true, key = true }
local function snapshot()
	local copy = {}
	for k, v in pairs(cfg) do
		if not SKIP[k] then
			copy[k] = v
		end
	end
	local snap = { cfg = copy, on = on }
	return HttpService:JSONDecode(HttpService:JSONEncode(snap)) -- deep copy
end
-- put a saved config into cfg AND into the menu controls (their callbacks apply it)
local function applyConfig(name)
	local snap = store.configs[name]
	if type(snap) ~= "table" then
		return false
	end
	for k, v in pairs(snap.cfg or {}) do
		cfg[k] = v
	end
	for k, v in pairs(snap.cfg or {}) do
		local c = reg[k]
		if c then
			pcall(c.SetValue, v)
		end
	end
	for k, v in pairs(snap.on or {}) do
		local c = tog[k]
		if c then
			pcall(c.SetValue, v and true or false)
		end
	end
	save()
	return true
end

---------------------------------------------------------------- UI
local Main = UI.CreateMain({ Title = "Levian Hub", Desc = " - Final Swarm" })
-- remove the close (x) button and use an X logo, in case the library on the server is an older version
pcall(function()
	for _, root in ipairs({ game:GetService("CoreGui"), (gethui and gethui()) or game:GetService("CoreGui") }) do
		local g = root:FindFirstChild("Levian Hub GUI") or root:FindFirstChild("Nousigi Hub GUI")
		if g then
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("TextButton") and d.Text == "x" then
					d:Destroy()
				end
			end
		end
		local t = root:FindFirstChild("LevianUI Toggle") or root:FindFirstChild("BananaUI Toggle")
		local b = t and t:FindFirstChildWhichIsA("TextButton")
		if b then
			task.spawn(applyLogoTo, b)
		end
	end
end)
local PageA = Main.CreatePage({ Page_Name = "About Us", Page_Title = "About Us" })
local SAb = PageA.CreateSection("About Us")
SAb.CreateLabel({ Title = "Levian Hub" })
-- centre the label (the library labels are left-aligned by default)
pcall(function()
	for _, root in ipairs({ game:GetService("CoreGui"), (gethui and gethui()) or game:GetService("CoreGui") }) do
		local g = root:FindFirstChild("Levian Hub GUI") or root:FindFirstChild("Nousigi Hub GUI")
		if g then
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("TextLabel") and d.Text == "Levian Hub" then
					d.TextXAlignment = Enum.TextXAlignment.Center
					d.TextSize = 22
					d.Font = Enum.Font.GothamBold
					d.TextColor3 = Color3.fromRGB(255, 204, 0)
				end
			end
		end
	end
end)
SAb.CreateButton({ Title = "Copy Link" }, function()
	local copy = setclipboard or toclipboard or (syn and syn.write_clipboard)
	local ok = copy and pcall(copy, LINK)
	UI.CreateNoti({ Title = "Levian Hub", Desc = ok and "Link copied" or LINK, ShowTime = 4 })
end)

local Page = Main.CreatePage({ Page_Name = "Lobby", Page_Title = "Lobby" })

local S1 = Page.CreateSection("CAMPAIGN")
reg.mode = S1.CreateDropdown({ Title = "Mode", List = { "Solo", "Duo", "Trio", "Squad" }, Default = cfg.mode }, function(v)
	cfg.mode = v
	save()
end)
reg.difficulty = S1.CreateDropdown({ Title = "Difficulty", List = { "Normal", "Hard", "Nightmare" }, Default = cfg.difficulty }, function(v)
	cfg.difficulty = v
	save()
end)
reg.challenges = S1.CreateDropdown({
	Title = "Challenge",
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
S1.CreateLabel({ Title = "Leave empty for default (no challenges)" })
reg.map = S1.CreateDropdown({
	Title = "Map",
	List = { "None", "Grasslands", "Desert", "Swamp", "Jungle", "Frost Forest", "Volcano", "Atlantis", "Crystal Cavern" },
	Default = cfg.map,
}, function(v)
	cfg.map = v
	save()
end)

local SR = Page.CreateSection("RAID")
reg.raid = SR.CreateDropdown({ Title = "Raid", List = RAID_NAMES, Default = cfg.raid }, function(v)
	cfg.raid = v
	save()
end)
reg.raidDifficulty = SR.CreateDropdown({ Title = "Difficulty", List = { "Normal", "Hard", "Nightmare" }, Default = cfg.raidDifficulty }, function(v)
	cfg.raidDifficulty = v
	save()
end)
reg.raidMode = SR.CreateDropdown({ Title = "Mode", List = { "Solo", "Duo", "Trio", "Squad" }, Default = cfg.raidMode }, function(v)
	cfg.raidMode = v
	save()
end)

local SD = Page.CreateSection("DUNGEON")
-- floors available to this account (GetFloorLimit = highest unlocked floor)
local floorNames = { "None", "1" }
pcall(function()
	local r = getRemotes()
	if r and r.dqFunc then
		local limit = tonumber(r.dqFunc:InvokeServer("GetFloorLimit"))
		if limit and limit >= 1 then
			floorNames = { "None" }
			for i = 1, math.min(math.floor(limit), 100) do
				floorNames[#floorNames + 1] = tostring(i)
			end
		end
	end
end)
reg.dungeonFloor = SD.CreateDropdown({ Title = "Floor", List = floorNames, Default = tostring(cfg.dungeonFloor) }, function(v)
	cfg.dungeonFloor = v
	save()
end)
reg.dungeonMode = SD.CreateDropdown({ Title = "Mode", List = { "Solo", "Duo", "Trio", "Squad" }, Default = cfg.dungeonMode }, function(v)
	cfg.dungeonMode = v
	save()
end)
SD.CreateLabel({ Title = "Only one of Campaign / Raid / Dungeon can be active. Set the others to None." })

local S2 = Page.CreateSection("Actions")
local status = S2.CreateLabel({ Title = "Status: ready" })
local function setStatus(t)
	status.SetText("Status: " .. t)
end
-- pop-up notification (replaces console output)
local function notify(ok, msg, okTitle)
	setStatus(msg)
	UI.CreateNoti({ Title = ok and (okTitle or "Queue created") or "Queue failed", Desc = msg, ShowTime = 4 })
end

S2.CreateButton({ Title = "Join Now" }, function()
	local ok, msg = joinSelected()
	notify(ok, msg)
end)
S2.CreateButton({ Title = "Leave Queue" }, function()
	local left = leaveQueue()
	notify(left, left and "Left the queue" or "Remotes not found", "Queue")
end)

local auto = false
tog.autoJoin = S2.CreateToggle({ Title = "Auto Join", Desc = "Retries every 20s; waits 2 minutes after a success", Default = false }, function(v)
	auto = v and true or false
	on.autoJoin = auto
	UI.CreateNoti({ Title = "Auto Join", Desc = auto and "ON" or "OFF", ShowTime = 2 })
	if auto then
		task.spawn(function()
			while auto do
				local ok, msg = joinSelected()
				notify(ok, msg)
				task.wait(ok and 120 or 20)
			end
		end)
	end
end)

local PageF = Main.CreatePage({ Page_Name = "Farming", Page_Title = "Farming" })

local SFl = PageF.CreateSection("AUTO FARM")
tog.autoFarm = SFl.CreateToggle({ Title = "Auto Farm", Desc = "Flies in a circle around the map", Default = false }, function(v)
	flyAuto = v and true or false
	on.autoFarm = flyAuto
	UI.CreateNoti({ Title = "Auto Farm", Desc = flyAuto and ("ON - " .. tostring(cfg.flyMode)) or "OFF", ShowTime = 2 })
	if flyAuto then
		local token = {}
		flyToken = token
		task.spawn(flyLoop, token)
	end
end)
reg.flyMode = SFl.CreateDropdown({ Title = "Mode", List = { "Fly" }, Default = cfg.flyMode }, function(v)
	cfg.flyMode = v
	save()
end)
reg.flyDistance = SFl.CreateSlider({ Title = "Distance", Min = 1, Max = 100, Default = tonumber(cfg.flyDistance) or 30 }, function(v)
	cfg.flyDistance = v
	save()
end)
reg.flyHeight = SFl.CreateSlider({ Title = "Height", Min = 1, Max = 100, Default = tonumber(cfg.flyHeight) or 25 }, function(v)
	cfg.flyHeight = v
	save()
end)
reg.flySpeed = SFl.CreateSlider({ Title = "Speed", Min = 1, Max = 100, Default = tonumber(cfg.flySpeed) or 30 }, function(v)
	cfg.flySpeed = v
	save()
end)
SFl.CreateLabel({ Title = "Circles around where you switched it on." })
SFl.CreateLabel({ Title = "Auto Bubble and Auto Rift take over when needed." })


local SF = PageF.CreateSection("AUTO CARD")
tog.autoCard = SF.CreateToggle({ Title = "Auto Card", Desc = "Picks a card when the offers appear", Default = false }, function(v)
	cardAuto = v and true or false
	on.autoCard = cardAuto
	UI.CreateNoti({ Title = "Auto Card", Desc = cardAuto and "ON" or "OFF", ShowTime = 2 })
	if cardAuto then
		local token = {}
		cardToken = token
		task.spawn(function()
			while cardAuto and cardToken == token do
				pcall(cardStep)
				task.wait(0.2)
			end
		end)
	end
end)
reg.cardPrefer = SF.CreateDropdown({ Title = "Prefer", List = { "Weapons first", "Cards first" }, Default = cfg.cardPrefer }, function(v)
	cfg.cardPrefer = v
	save()
end)
reg.weaponsWanted = SF.CreateDropdown({ Title = "Weapons", List = WEAPONS, Multi = true, Search = true, Default = cfg.weaponsWanted }, function(sel)
	cfg.weaponsWanted = toArray(WEAPONS, sel)
	save()
end)
reg.cardsWanted = SF.CreateDropdown({ Title = "Cards", List = CARDS, Multi = true, Search = true, Default = cfg.cardsWanted }, function(sel)
	cfg.cardsWanted = toArray(CARDS, sel)
	save()
end)
reg.cardFallback = SF.CreateDropdown({ Title = "If nothing matches", List = { "Pick first card", "Reroll", "Do nothing" }, Default = cfg.cardFallback }, function(v)
	cfg.cardFallback = v
	save()
end)
reg.cardMaxRerolls = SF.CreateSlider({ Title = "Max rerolls per offer", Min = 0, Max = 10, Default = tonumber(cfg.cardMaxRerolls) or 3 }, function(v)
	cfg.cardMaxRerolls = v
	save()
end)
reg.cardBanish = SF.CreateToggle({ Title = "Auto Banish", Desc = "Removes cards from the Banish list", Default = cfg.cardBanish }, function(v)
	cfg.cardBanish = v and true or false
	save()
end)
reg.banishList = SF.CreateDropdown({ Title = "Banish list", List = BANISH_ALL, Multi = true, Search = true, Default = cfg.banishList }, function(sel)
	cfg.banishList = toArray(BANISH_ALL, sel)
	save()
end)
SF.CreateButton({ Title = "Show cards on screen" }, function()
	local cards = getCards()
	if not cards then
		noti("Cards", "No card offer on screen", 3)
		return
	end
	local names = {}
	for _, c in ipairs(cards) do
		names[#names + 1] = c.name
	end
	noti("Cards (" .. #cards .. ")", table.concat(names, " | "), 6)
end)
SF.CreateLabel({ Title = "Weapons and cards are matched by their exact names." })
SF.CreateLabel({ Title = "Auto Banish: if no banish is left, the card may be picked instead." })

local SB = PageF.CreateSection("AUTO BUBBLE")
tog.autoBubble = SB.CreateToggle({ Title = "Auto Bubble", Desc = "Moves to the nearest bubble", Default = false }, function(v)
	bubbleAuto = v and true or false
	on.autoBubble = bubbleAuto
	if not bubbleAuto then
		bubbleBusy = false
	end
	UI.CreateNoti({ Title = "Auto Bubble", Desc = bubbleAuto and ("ON - " .. tostring(cfg.bubbleMode)) or "OFF", ShowTime = 2 })
	if bubbleAuto then
		local token = {}
		bubbleToken = token
		task.spawn(bubbleLoop, token)
	end
end)
reg.bubbleBelow = SB.CreateSlider({ Title = "Take bubble below (%)", Min = 0, Max = 100, Default = tonumber(cfg.bubbleBelow) or 80 }, function(v)
	cfg.bubbleBelow = v
	save()
end)
reg.bubbleMode = SB.CreateDropdown({ Title = "Mode", List = { "Safe", "Tween" }, Default = cfg.bubbleMode }, function(v)
	cfg.bubbleMode = v
	save()
end)
reg.bubbleSpeed = SB.CreateSlider({ Title = "Tween speed", Min = 0, Max = 100, Default = tonumber(cfg.bubbleSpeed) or 20 }, function(v)
	cfg.bubbleSpeed = v
	save()
end)
reg.oxygenPath = SB.CreateBox({ Title = "Oxygen UI path (optional)", Default = cfg.oxygenPath }, function(v)
	cfg.oxygenPath = type(v) == "string" and v or ""
	save()
end)
SB.CreateButton({ Title = "Show oxygen reading" }, function()
	local p, src = readOxygen()
	if p then
		noti("Oxygen", string.format("%d%% (%s)", math.floor(p + 0.5), src), 5)
	else
		noti("Oxygen", "Not found. Go underwater and try again, or set the UI path.", 5)
	end
end)
SB.CreateLabel({ Title = "Goes to a bubble when oxygen is below the slider value." })

local SR = PageF.CreateSection("AUTO RIFT")
tog.autoRift = SR.CreateToggle({ Title = "Auto Rift", Desc = "Moves to the nearest rift", Default = false }, function(v)
	riftAuto = v and true or false
	on.autoRift = riftAuto
	UI.CreateNoti({ Title = "Auto Rift", Desc = riftAuto and ("ON - " .. tostring(cfg.riftMode)) or "OFF", ShowTime = 2 })
	if riftAuto then
		local token = {}
		riftToken = token
		task.spawn(riftLoop, token)
	else
		riftBusy = false
	end
end)
reg.riftMode = SR.CreateDropdown({ Title = "Mode", List = { "Safe", "Tween" }, Default = cfg.riftMode }, function(v)
	cfg.riftMode = v
	save()
end)
reg.riftSpeed = SR.CreateSlider({ Title = "Tween speed", Min = 0, Max = 100, Default = tonumber(cfg.riftSpeed) or 20 }, function(v)
	cfg.riftSpeed = v
	save()
end)
reg.riftStay = SR.CreateToggle({ Title = "Stay at rift", Desc = "Stays next to the rift while it exists", Default = cfg.riftStay }, function(v)
	cfg.riftStay = v and true or false
	save()
end)
reg.riftTargets = SR.CreateDropdown({ Title = "Targets", List = { "Rift", "Crystal", "Circle" }, Multi = true, Default = cfg.riftTargets }, function(sel)
	cfg.riftTargets = toArray({ "Rift", "Crystal", "Circle" }, sel)
	save()
end)
SR.CreateLabel({ Title = "Auto Bubble has priority when oxygen is low." })

local SW = PageF.CreateSection("WALK AROUND")
tog.walk = SW.CreateToggle({ Title = "Walk Around", Desc = "Walks randomly around where you are", Default = false }, function(v)
	walkAuto = v and true or false
	on.walk = walkAuto
	UI.CreateNoti({ Title = "Walk Around", Desc = walkAuto and "ON" or "OFF", ShowTime = 2 })
	if walkAuto then
		local token = {}
		walkToken = token
		task.spawn(walkLoop, token)
	end
end)
reg.walkRadius = SW.CreateSlider({ Title = "Walk radius", Min = 5, Max = 100, Default = tonumber(cfg.walkRadius) or 30 }, function(v)
	cfg.walkRadius = v
	save()
end)
SW.CreateLabel({ Title = "Pauses while Auto Bubble or Auto Rift is moving." })

local SA = PageF.CreateSection("AFTER MATCH")
reg.afterMatch = SA.CreateDropdown({ Title = "When the match ends", List = { "Nothing", "Replay", "Lobby" }, Default = cfg.afterMatch }, function(v)
	cfg.afterMatch = v
	save()
end)
reg.afterDelay = SA.CreateSlider({ Title = "Delay (seconds)", Min = 0, Max = 30, Default = tonumber(cfg.afterDelay) or 3 }, function(v)
	cfg.afterDelay = v
	save()
end)
SA.CreateButton({ Title = "Show result buttons" }, function()
	local kind, e = scanEnd()
	if kind == "result" then
		noti("Result screen", "Again: " .. buttonLabel(e.again) .. " | Lobby: " .. buttonLabel(e.lobby), 6)
	elseif kind == "defeat" then
		noti("Result screen", "Death screen: " .. buttonLabel(e.giveUp), 4)
	elseif kind == "continue" then
		noti("Result screen", "Click-to-continue screen", 4)
	else
		noti("Result screen", "Not on screen", 3)
	end
end)
SA.CreateLabel({ Title = "Skips Victory/Defeat screens, then presses Again or Lobby." })
SA.CreateLabel({ Title = "Keep the menu hidden: it clicks the middle of the screen." })

local PageS = Main.CreatePage({ Page_Name = "Settings", Page_Title = "Settings" })
local SS = PageS.CreateSection("SETTINGS")
reg.autoExecute = SS.CreateToggle({ Title = "Auto Execute", Desc = "Reloads this script after changing map (lobby <-> match)", Default = cfg.autoExecute }, function(v)
	setAutoExecute(v)
	UI.CreateNoti({ Title = "Auto Execute", Desc = v and "ON" or "OFF", ShowTime = 2 })
end)
reg.autoMinimize = SS.CreateToggle({ Title = "Auto Minimize", Desc = "Hides the menu automatically when the script loads", Default = cfg.autoMinimize }, function(v)
	cfg.autoMinimize = v and true or false
	save()
	UI.CreateNoti({ Title = "Auto Minimize", Desc = v and "ON - the menu hides on load" or "OFF", ShowTime = 2 })
end)
SS.CreateLabel({ Title = "No need to enable auto execute in your executor." })

local SC = PageS.CreateSection("CONFIG")
local cfgNameInput, cfgSelected = "", ""
local cfgList, autoList
local function withNone(names)
	local l = { "None" }
	for _, n in ipairs(names) do
		l[#l + 1] = n
	end
	return l
end
local function refreshLists()
	local names = configNames()
	pcall(cfgList.Refresh, names)
	pcall(autoList.Refresh, withNone(names))
end
SC.CreateBox({ Title = "Config name", Default = "" }, function(v)
	cfgNameInput = cleanName(v)
end)
SC.CreateButton({ Title = "Save" }, function()
	if cfgNameInput == "" then
		noti("Config", "Type a config name first", 3)
		return
	end
	store.configs[cfgNameInput] = snapshot()
	saveStore()
	refreshLists()
	noti("Config", "Saved: " .. cfgNameInput, 3)
end)
cfgList = SC.CreateDropdown({ Title = "Config", List = configNames() }, function(v)
	cfgSelected = tostring(v or "")
end)
SC.CreateButton({ Title = "Load" }, function()
	if cfgSelected == "" or not store.configs[cfgSelected] then
		noti("Config", "Select a saved config first", 3)
		return
	end
	applyConfig(cfgSelected)
	noti("Config", "Loaded: " .. cfgSelected, 3)
end)
SC.CreateButton({ Title = "Delete" }, function()
	if cfgSelected == "" or not store.configs[cfgSelected] then
		noti("Config", "Select a saved config first", 3)
		return
	end
	local gone = cfgSelected
	store.configs[gone] = nil
	if store.autoLoad == gone then
		store.autoLoad = ""
		pcall(autoList.SetValue, "None")
	end
	saveStore()
	cfgSelected = ""
	pcall(cfgList.SetValue, nil)
	refreshLists()
	noti("Config", "Deleted: " .. gone, 3)
end)
autoList = SC.CreateDropdown({
	Title = "Auto Load",
	List = withNone(configNames()),
	Default = (store.configs[store.autoLoad] and store.autoLoad) or "None",
}, function(v)
	store.autoLoad = (v == "None") and "" or tostring(v)
	saveStore()
end)
SC.CreateLabel({ Title = "Save stores the whole menu, including the toggles that are on." })

-- open the Lobby tab first (About Us is the first tab in the list)
pcall(function()
	for _, root in ipairs({ game:GetService("CoreGui"), (gethui and gethui()) or game:GetService("CoreGui") }) do
		local g = root:FindFirstChild("Levian Hub GUI") or root:FindFirstChild("Nousigi Hub GUI")
		if g then
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("TextButton") and d.Text == "Lobby" then
					local ok = pcall(function()
						for _, c in ipairs(getconnections(d.MouseButton1Click)) do
							c:Fire()
						end
					end)
					if not ok and firesignal then
						pcall(firesignal, d.MouseButton1Click)
					end
					return
				end
			end
		end
	end
end)

-- auto load the chosen config once the menu is built
local autoName = store.autoLoad
if autoName ~= "" and store.configs[autoName] then
	task.delay(1.5, function()
		if applyConfig(autoName) then
			UI.CreateNoti({ Title = "Config", Desc = "Auto loaded: " .. autoName, ShowTime = 3 })
		end
	end)
end

UI.CreateNoti({ Title = "Final Swarm v22", Desc = "Menu ready. Pick a mode, then Join Now.", ShowTime = 5 })

-- Auto Minimize: hide the window like the "-" button does (the X logo stays and reopens it)
if cfg.autoMinimize then
	task.delay(2, function()
		pcall(Main.SetVisible, false)
	end)
end
