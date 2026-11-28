--[[
	Levian Hub - Final Swarm
]]

local HttpService = game:GetService("HttpService")
local LOBBY_ID, MATCH_ID = 99521272836282, 79787558257549
local IN_LOBBY = game.PlaceId == LOBBY_ID -- the Lobby tab only exists in the lobby, not in a match
local RS = game:GetService("ReplicatedStorage")

---------------------------------------------------------------- saved settings
local FOLDER = "Levian Hub"
local FILE = FOLDER .. "/" .. game:GetService("Players").LocalPlayer.Name .. "-finalswarm.json"
local cfg = {
	mode = "Solo",
	difficulty = "Normal",
	map = "Volcano",
	challenges = {},
	raid = "None",
	raidDifficulty = "Normal",
	raidMode = "Solo",
	dungeonFloor = "None",
	dungeonMode = "Solo",
	cardFallback = "Pick first card",
	cardMaxRerolls = 3,
	cardBanish = false,
	weaponsWanted = {},
	cardsWanted = {},
	banishList = {},
	bubbleMode = "Safe",
	bubbleName = "OxygenBubble",
	bubbleBelow = 80,
	bubbleSpeed = 20,
	riftMode = "Safe",
	riftSpeed = 20,
	riftStay = true,
	pressMethod = "",
	afterMatch = "Nothing",
	afterDelay = 3,
	autoExecute = false,
	autoMinimize = false,
	flyMode = "Walk Around",
	flyDistance = 30,
	flyHeight = 25,
	flySpeed = 30,
	dodgePatterns = "HitCircle,Telegraph,Indicator,AOE,DangerZone", -- part names that count as a hit circle (guess, edit in the menu)
	dodgeMode = "Tween",
	dodgeSpeed = 60,
	dodgeMargin = 6,
	bossName = "Boss",
	dodgeRed = true, -- also dodge flat red parts (lines), not only parts with a matching name
	raidSelect = "Colosseum",
	raidWait = 20, -- seconds to wait at a corner zone / statue
	raidZones = "Capture,Corner", -- 75%: corner zones (names, comma separated)
	raidStatues = "Statue", -- 50%: statues in the middle
	raidRocks = "Rock,Stone,Platform", -- 25%: rocks above the lava
	spyFilter = "World,Queue,Map,Difficulty,Challenge,Party,Raid,Dungeon", -- words a Remote Spy line must contain (empty = all)
}
pcall(function()
	if isfile then
		if isfile(FILE) then
			for k, v in pairs(HttpService:JSONDecode(readfile(FILE))) do
				cfg[k] = v
			end
		end
	end
end)

if type(cfg.challenges) ~= "table" then
	cfg.challenges = {}
end
-- Auto Farm modes were renamed
if cfg.flyMode == "Walking Circle" then
	cfg.flyMode = "Walk Circle"
end
if cfg.flyMode ~= "Fly(risk)" and cfg.flyMode ~= "Walk Circle" then
	cfg.flyMode = "Walk Around"
end

local function save()
	pcall(function()
		if makefolder and not isfolder(FOLDER) then
			makefolder(FOLDER)
		end
		writefile(FILE, HttpService:JSONEncode(cfg))
	end)
end

---------------------------------------------------------------- UI library
local function loadUI()
	local urls = {
		"https://levianstore.my.id/LevianUI.lua",
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
	task.wait(0.3)
	r.qsEvent:FireServer("Created")
	return true, ("Campaign: %s / %s / %s"):format(tostring(cfg.map), tostring(cfg.difficulty), tostring(cfg.mode))
end

-- the server may expect another spelling of the raid id: the ones below are tried in turn
local RAID_ID_VARIANTS = {
	SandWorm = { "SandWorm", "Sandworm", "Sand Worm", "sandworm", "Sand_Worm" },
}
local raidIdWorked = {}

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
	local variants = { raidIdWorked[id] or id }
	for _, v in ipairs(RAID_ID_VARIANTS[id] or {}) do
		if v ~= variants[1] then
			variants[#variants + 1] = v
		end
	end
	local notes = {}
	for _, rid in ipairs(variants) do
		r.rqEvent:FireServer("SelectRaid", rid)
		task.wait(0.4)
		r.wsEvent:FireServer("SetDifficulty", cfg.raidDifficulty)
		task.wait(0.4)
		local ok, res = pcall(function()
			return r.rqFunc:InvokeServer("EnterQueue")
		end)
		if ok and res == true then
			raidIdWorked[id] = rid
			task.wait(0.4)
			r.rqEvent:FireServer("PartySizeSelected", size)
			task.wait(0.3)
			r.rqEvent:FireServer("Created")
			return true, ("Raid: %s / %s / %s"):format(tostring(cfg.raid), tostring(cfg.raidDifficulty), tostring(cfg.raidMode))
		end
		notes[#notes + 1] = ('"%s" -> %s'):format(rid, ok and tostring(res) or ("error " .. tostring(res)))
	end
	return false, ("EnterQueue rejected (%s): %s"):format(tostring(cfg.raidDifficulty), table.concat(notes, "; "))
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
-- button signals first (no screen click); real clicks/touches only as a last resort and never for cards;
-- the method that worked last time is remembered between sessions
local PREF = { connections = 1, signal = 2, click = 3, touch = 4 }
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
local function isClickMethod(i)
	return METHODS[i][1] == "click" or METHODS[i][1] == "touch"
end
local function pressRaw(btn) -- never clicks the screen
	for i, m in ipairs(METHODS) do
		if not isClickMethod(i) then
			local ok, res = pcall(m[2], btn)
			if ok and res ~= false then
				return true
			end
		end
	end
	return false
end

-- press and check (up to ~1s per method) that something changed; falls through to the next method otherwise
local function pressVerified(btn, check, noClick)
	local order = {}
	if bestMethod and not (noClick and isClickMethod(bestMethod)) then
		order[1] = bestMethod
	end
	for i = 1, #METHODS do
		if i ~= bestMethod and not (noClick and isClickMethod(i)) then
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

-- pick the first offered weapon/card that is in the Weapons or Cards list
local function chooseCard(cards)
	for _, c in ipairs(cards) do
		if inList(cfg.weaponsWanted, c.name) or inList(cfg.cardsWanted, c.name) then
			return c
		end
	end
	return nil
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
		local ok = pressVerified(c.btn, changed, true)
		if ok then
			noti("Auto Card", label .. c.name, 3)
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
			local ok = pressVerified(rb, changed, true)
			if ok then
				rerolls += 1
				noti("Auto Card", "Reroll " .. rerolls .. "/" .. tostring(cfg.cardMaxRerolls), 2)
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
-- Order: attributes -> Value objects -> an "oxygen" bar in PlayerGui.
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
	-- 1) attributes and Value objects
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
	-- 2) an oxygen bar / label in the UI (cached)
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
local dodgeBusy = false -- true while Auto Dodge / Auto Raid has control of the character (other loops wait)
local dodgeHit, raidHold, raidLava = false, false, false -- dodgeBusy = dodgeHit or raidHold; raidLava = Auto Raid is moving over the lava rocks
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
		elseif dodgeBusy then
			task.wait(0.1)
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
				while bubbleAuto and bubbleToken == token and not dodgeBusy and os.clock() - started < 20 do
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
				if not dodgeBusy then
					bubbleVisited[target.inst] = os.clock()
				end
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
local RIFT_TARGETS = { "Rift", "Crystal", "Circle" } -- every rift object type is targeted

local function riftCandidates(hrp, char)
	if os.clock() - riftCacheAt > 1 then
		riftCacheAt = os.clock()
		riftCache = {}
		local map = workspace:FindFirstChild("Map")
		local root = map and map:FindFirstChild("RiftRuntime")
		if root then
			local want = {}
			for _, n in ipairs(RIFT_TARGETS) do
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
		elseif bubbleBusy or dodgeBusy then
			task.wait(0.3) -- oxygen first
		else
			local target = riftCandidates(hrp, char)[1]
			if not target then
				task.wait(0.5)
			else
				local started = os.clock()
				riftBusy = true
				while riftAuto and riftToken == token and not bubbleBusy and not dodgeBusy and os.clock() - started < 25 do
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
				if not dodgeBusy then
					riftVisited[target.inst] = os.clock()
				end
				riftBusy = false
			end
		end
	end
	riftBusy = false
end

---------------------------------------------------------------- auto farm modes: walking (in-match)
-- Auto Farm has three modes (the "Mode" dropdown, default Walk Around):
--   Fly(risk)      = flies in a circle in the air (next section)
--   Walk Around    = walks to random points around where it was switched on (Roblox walking, Humanoid:MoveTo)
--   Walk Circle    = walks around a circle on the ground (Humanoid:MoveTo)
-- "Distance" is the radius of all three. The walking modes pause while Auto Dodge, Auto Bubble or Auto Rift moves you.
local flyAuto, flyToken = false, nil
local function groundAt(pos, char)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { char }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position.Y or pos.Y
end

local function walkLoop(token)
	local center
	while flyAuto and flyToken == token do
		local char = game:GetService("Players").LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then
			center = nil
			task.wait(1)
		elseif bubbleBusy or riftBusy or dodgeBusy then
			center = nil -- take a new centre after the bubble/rift/dodge
			task.wait(0.3)
		else
			center = center or hrp.Position
			local r = math.max(tonumber(cfg.flyDistance) or 30, 5)
			local ang, dist = math.random() * math.pi * 2, 5 + math.random() * (r - 5)
			local flat = center + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist)
			local target = Vector3.new(flat.X, groundAt(flat, char) + 3, flat.Z)
			hum:MoveTo(target)
			local t0 = os.clock()
			while flyAuto and flyToken == token and not bubbleBusy and not riftBusy and not dodgeBusy and os.clock() - t0 < 6 do
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

local function walkCircleLoop(token)
	local center, ang, pointAt
	while flyAuto and flyToken == token do
		local char = game:GetService("Players").LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then
			center = nil
			task.wait(1)
		elseif bubbleBusy or riftBusy or dodgeBusy then
			task.wait(0.3)
		else
			if not center then
				center, ang, pointAt = hrp.Position, 0, os.clock()
			end
			local r = math.max(tonumber(cfg.flyDistance) or 30, 5)
			local flat = center + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
			local target = Vector3.new(flat.X, groundAt(flat, char) + 3, flat.Z)
			hum:MoveTo(target)
			local dx, dz = hrp.Position.X - target.X, hrp.Position.Z - target.Z
			if math.sqrt(dx * dx + dz * dz) < 4 or os.clock() - pointAt > 3 then
				ang += 0.4 -- next point along the circle
				pointAt = os.clock()
			end
			task.wait(0.1)
		end
	end
end

---------------------------------------------------------------- auto farm: fly in a circle (in-match)
-- Flies around a circle. Centre = where you were when it was switched on,
-- Distance = radius (studs), Height = height above the ground at the centre, Speed = studs per second.
-- Auto Bubble and Auto Rift have priority (they take over, then the circle continues).
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
		elseif bubbleBusy or riftBusy or dodgeBusy then
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

-- starts the loop of the selected Auto Farm mode (a new token stops the previous loop)
local function startFarm()
	local token = {}
	flyToken = token
	if cfg.flyMode == "Fly(risk)" then
		task.spawn(flyLoop, token)
	elseif cfg.flyMode == "Walk Circle" then
		task.spawn(walkCircleLoop, token)
	else
		task.spawn(walkLoop, token)
	end
end

---------------------------------------------------------------- auto dodge (hit circles)
-- Hit circles are found by NAME: every Part/Model in workspace whose name contains one of the words in
-- "Hit circle names" (comma separated) is treated as a circle on the ground. The circle radius is taken from the
-- part size (half of its second-largest side, so flat discs and balls both work). If you stand inside one,
-- you are moved straight out of it (Safe = Humanoid:MoveTo, Tween = fast CFrame steps at "Dodge speed").
-- The names are a guess: stand next to a circle and press "Show nearby flat parts" to see the real names.
-- Auto Dodge (always) / Boss Dodge (only while a boss is alive) / Auto Raid (while it is on). Circles AND lines are avoided.
local Players = game:GetService("Players")
local dodgeOn = { campaign = false, campaignBoss = false, raid = false }
local dodgeToken = nil
local dodgeSet, dodgePats, dodgeKey = {}, {}, nil

local function splitNames(text)
	local out = {}
	for part in tostring(text or ""):gmatch("[^,;|]+") do
		local n = norm(part)
		if n ~= "" then
			out[#out + 1] = n
		end
	end
	return out
end

local bossCache, bossAt = false, 0
local function bossExists()
	if os.clock() - bossAt > 2 then
		bossAt = os.clock()
		bossCache = false
		local pat = norm(cfg.bossName)
		if pat == "" then
			pat = "boss"
		end
		for _, h in ipairs(workspace:GetDescendants()) do
			if h:IsA("Humanoid") and h.Health > 0 then
				local m = h.Parent
				if m and not Players:GetPlayerFromCharacter(m) then
					if norm(m.Name):find(pat, 1, true) or norm(h.DisplayName):find(pat, 1, true) then
						bossCache = true
						break
					end
				end
			end
		end
	end
	return bossCache
end

-- hit circle names that are active right now (nil = nothing to dodge at the moment)
local function activePatterns()
	local set, any = {}, false
	local function add(list)
		any = true
		for _, p in ipairs(list) do
			set[p] = true
		end
	end
	local generic = splitNames(cfg.dodgePatterns)
	if dodgeOn.campaign then
		add(generic)
	end
	if dodgeOn.campaignBoss and bossExists() then
		add(generic)
	end
	if dodgeOn.raid then
		add(generic)
	end
	if not any then
		return nil
	end
	local out = {}
	for p in pairs(set) do
		out[#out + 1] = p
	end
	table.sort(out)
	return out
end

-- flat red parts (telegraph lines): thin, large, strongly red
local function isRedFlat(d)
	if not d:IsA("BasePart") or d:IsA("Terrain") or d.Transparency >= 0.95 then
		return false
	end
	local c = d.Color
	if not (c.R > 0.65 and c.G < 0.4 and c.B < 0.4) then
		return false
	end
	local sz = d.Size
	return math.min(sz.X, sz.Y, sz.Z) <= 3 and math.max(sz.X, sz.Y, sz.Z) >= 4
end

local function isHazard(d)
	if not (d:IsA("BasePart") or d:IsA("Model")) or d:IsA("Terrain") then
		return false
	end
	local n = norm(d.Name)
	local hit = false
	for _, p in ipairs(dodgePats) do
		if n:find(p, 1, true) then
			hit = true
			break
		end
	end
	if not hit and not (cfg.dodgeRed and isRedFlat(d)) then
		return false
	end
	local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
	return not (m and Players:GetPlayerFromCharacter(m))
end

-- Is `pos` inside the hazard d (grown by `grow` studs)? Returns the penetration depth (0 = outside) and the nearest
-- point outside (exitMargin studs past the edge, same height as pos).
-- A hazard is the flat plane of the part (its thinnest side is ignored): nearly square = circle, long = line/rectangle.
local function probe(d, pos, grow, exitMargin)
	local cf, size
	if d:IsA("Model") then
		cf, size = d:GetBoundingBox()
	else
		cf, size = d.CFrame, d.Size
	end
	local dims = { { size.X, "X" }, { size.Y, "Y" }, { size.Z, "Z" } }
	table.sort(dims, function(p, q)
		return p[1] < q[1]
	end)
	local tn, an, bn = dims[1][2], dims[2][2], dims[3][2]
	local ha, hb = dims[2][1] / 2, dims[3][1] / 2
	if hb < 2 or hb > 200 then
		return 0
	end
	local lp = cf:PointToObjectSpace(pos)
	if math.abs(lp[tn]) > 60 then
		return 0
	end
	local la, lb = lp[an], lp[bn]
	local round = (d:IsA("Part") and d.Shape == Enum.PartType.Ball) or hb / math.max(ha, 0.01) < 1.25
	local ra, rb, pen
	if round then
		local r = (ha + hb) / 2
		local dist = math.sqrt(la * la + lb * lb)
		pen = r + grow - dist
		if pen <= 0 then
			return 0
		end
		local ux, uz = la, lb
		if dist < 0.1 then
			ux, uz, dist = 1, 0, 1
		end
		ra, rb = ux / dist * (r + exitMargin), uz / dist * (r + exitMargin)
	else
		local ia, ib = ha + grow - math.abs(la), hb + grow - math.abs(lb)
		if ia <= 0 or ib <= 0 then
			return 0
		end
		pen = math.min(ia, ib)
		ra, rb = la, lb
		if ia <= ib then
			ra = (la >= 0 and 1 or -1) * (ha + exitMargin)
		else
			rb = (lb >= 0 and 1 or -1) * (hb + exitMargin)
		end
	end
	local v = { X = 0, Y = 0, Z = 0 }
	v[an], v[bn], v[tn] = ra, rb, lp[tn]
	local w = cf:PointToWorldSpace(Vector3.new(v.X, v.Y, v.Z))
	return pen, Vector3.new(w.X, pos.Y, w.Z)
end

local dodgeConns = {}
local function startIndex()
	dodgeConns[#dodgeConns + 1] = workspace.DescendantAdded:Connect(function(d)
		if dodgeKey and isHazard(d) then
			dodgeSet[d] = true
		end
	end)
	dodgeConns[#dodgeConns + 1] = workspace.DescendantRemoving:Connect(function(d)
		dodgeSet[d] = nil
	end)
end
local function stopIndex()
	for _, c in ipairs(dodgeConns) do
		c:Disconnect()
	end
	dodgeConns, dodgeSet, dodgeKey = {}, {}, nil
end
local function rescan()
	for _, d in ipairs(workspace:GetDescendants()) do
		if not dodgeSet[d] and isHazard(d) then
			dodgeSet[d] = true
		end
	end
end
local function refreshIndex(pats)
	local key = table.concat(pats, ",") .. "|" .. tostring(cfg.dodgeRed)
	if key == dodgeKey then
		return
	end
	dodgeKey, dodgePats, dodgeSet = key, pats, {}
	rescan()
end

-- deepest hazard overlap at a position (used by Auto Raid to find safe rocks)
local function hazardPen(pos, grow)
	local best = 0
	for d in pairs(dodgeSet) do
		if d.Parent and (not d:IsA("BasePart") or d.Transparency < 1) then
			local pen = probe(d, pos, grow, 0)
			if pen > best then
				best = pen
			end
		end
	end
	return best
end

local function dodgeLoop(token)
	startIndex()
	local lastDanger, lastScan = 0, 0
	while dodgeToken == token do
		local pats = activePatterns()
		local char = Players.LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not pats or not hrp or not hum or hum.Health <= 0 then
			dodgeHit, dodgeBusy = false, raidHold
			task.wait(0.25)
		else
			refreshIndex(pats)
			if cfg.dodgeRed and os.clock() - lastScan > 2 then
				lastScan = os.clock()
				rescan() -- picks up parts that turned red after they were created
			end
			if raidLava then
				dodgeHit, dodgeBusy = false, raidHold -- Auto Raid moves between rocks itself
				task.wait(0.1)
			else
				local margin = math.clamp(tonumber(cfg.dodgeMargin) or 6, 1, 40)
				local wpen, wtgt = 0, nil
				for d in pairs(dodgeSet) do
					if d.Parent and not d:IsDescendantOf(char) and (not d:IsA("BasePart") or d.Transparency < 1) then
						local pen, tgt = probe(d, hrp.Position, 1, margin)
						if pen > wpen then
							wpen, wtgt = pen, tgt
						end
					end
				end
				local dt = RunService.Heartbeat:Wait()
				if wtgt then
					dodgeHit, dodgeBusy, lastDanger = true, true, os.clock()
					if cfg.dodgeMode == "Safe" then
						hum:MoveTo(wtgt)
					else
						local to = wtgt - hrp.Position
						local step = math.min(math.max(tonumber(cfg.dodgeSpeed) or 60, 5) * dt, to.Magnitude)
						if to.Magnitude > 0.01 then
							hrp.CFrame = hrp.CFrame + to.Unit * step
						end
						hrp.AssemblyLinearVelocity = Vector3.zero
					end
				elseif dodgeHit and os.clock() - lastDanger > 0.4 then
					dodgeHit, dodgeBusy = false, raidHold
				end
			end
		end
	end
	dodgeHit, dodgeBusy = false, raidHold
	stopIndex()
end

local function setDodge(key, v)
	dodgeOn[key] = v and true or false
	local anyOn = false
	for _, x in pairs(dodgeOn) do
		anyOn = anyOn or x
	end
	if anyOn and not dodgeToken then
		local token = {}
		dodgeToken = token
		task.spawn(dodgeLoop, token)
	elseif not anyOn then
		dodgeToken = nil
	end
end

-- enemies (non-player Humanoids) near you: shows the real boss name
local function nearbyEnemies(radius)
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local best = {}
	for _, h in ipairs(workspace:GetDescendants()) do
		if h:IsA("Humanoid") and h.Health > 0 and h.Parent and not Players:GetPlayerFromCharacter(h.Parent) then
			local root = h.Parent:FindFirstChild("HumanoidRootPart") or h.Parent:FindFirstChildWhichIsA("BasePart")
			local dist = root and (root.Position - hrp.Position).Magnitude or math.huge
			if dist <= radius and (not best[h.Parent.Name] or dist < best[h.Parent.Name]) then
				best[h.Parent.Name] = dist
			end
		end
	end
	local list = {}
	for n, d in pairs(best) do
		list[#list + 1] = { n = n, d = d }
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local out = {}
	for i = 1, math.min(#list, 8) do
		out[i] = list[i].n
	end
	return out
end

-- flat parts near you with their names (to find the real hit circle name)
local function nearbyFlat(radius)
	local char = Players.LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local best = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and not d:IsA("Terrain") and d.Transparency < 1 and not d:IsDescendantOf(char) then
			local sz = d.Size
			local thin = math.min(sz.X, sz.Y, sz.Z) <= 3 and math.max(sz.X, sz.Y, sz.Z) >= 4
			local dist = (d.Position - hrp.Position).Magnitude
			if thin and dist <= radius then
				local m = d:FindFirstAncestorOfClass("Model")
				if not (m and Players:GetPlayerFromCharacter(m)) then
					if not best[d.Name] or dist < best[d.Name] then
						best[d.Name] = dist
					end
				end
			end
		end
	end
	local list = {}
	for n, dist in pairs(best) do
		list[#list + 1] = { n = n, d = dist }
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local out = {}
	for i = 1, math.min(#list, 12) do
		out[i] = list[i].n
	end
	return out
end

---------------------------------------------------------------- auto raid (Colosseum)
-- Plays the boss phases by the boss health (the boss = the non-player Humanoid matching "Boss name contains",
-- otherwise the one with the most max health):
--   75%  corner zones : visit each zone and stay until it is full (gone) or "Max wait" ran out, like Auto Rift
--   50%  statues      : stay next to each statue in the middle until it is destroyed (the weapons hit it)
--   25%  lava         : stand on the rocks; when a hit zone covers your rock (or you are off the rocks) hop to the
--                       nearest rock that is not covered. Auto Dodge's pushing is paused during this phase.
-- While Auto Raid is on, hit zone dodging is on too. The object names are guesses: use the Raid tab buttons.
local RAID = {}
do
	local running, token = false, nil
	local bossH, bossAt = nil, 0
	local visited = {}
	local cache = {}

	local function hold(v)
		raidHold = v
		dodgeBusy = dodgeHit or v
	end

	local function findBoss()
		if bossH and bossH.Parent and bossH.Health > 0 and os.clock() - bossAt < 3 then
			return bossH
		end
		bossAt, bossH = os.clock(), nil
		local pat, best = norm(cfg.bossName), 0
		for _, h in ipairs(workspace:GetDescendants()) do
			if h:IsA("Humanoid") and h.Health > 0 and h.Parent and not Players:GetPlayerFromCharacter(h.Parent) then
				local byName = pat ~= "" and (norm(h.Parent.Name):find(pat, 1, true) or norm(h.DisplayName):find(pat, 1, true))
				local score = h.MaxHealth + (byName and 1e12 or 0)
				if score > best then
					best, bossH = score, h
				end
			end
		end
		return bossH
	end

	-- objects (parts/models) whose name contains one of the words; cached for 1 second
	local function find(names)
		local c = cache[names]
		if not c or os.clock() - c.at > 1 then
			c = { at = os.clock(), list = {} }
			cache[names] = c
			local pats, found, set = splitNames(names), {}, {}
			if #pats > 0 then
				for _, d in ipairs(workspace:GetDescendants()) do
					if (d:IsA("BasePart") or d:IsA("Model")) and not d:IsA("Terrain") then
						local n = norm(d.Name)
						for _, p in ipairs(pats) do
							if n:find(p, 1, true) then
								local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
								if not (m and Players:GetPlayerFromCharacter(m)) then
									found[#found + 1] = d
									set[d] = true
								end
								break
							end
						end
					end
				end
				for _, d in ipairs(found) do
					local nested, p = false, d.Parent
					while p and p ~= workspace do
						if set[p] then
							nested = true
							break
						end
						p = p.Parent
					end
					if not nested then
						c.list[#c.list + 1] = d
					end
				end
			end
		end
		local out = {}
		for _, d in ipairs(c.list) do
			if d.Parent then
				out[#out + 1] = d
			end
		end
		return out
	end

	local function walkTo(hrp, hum, pos)
		if cfg.dodgeMode == "Safe" then
			hum:MoveTo(pos)
			task.wait(0.2)
		else
			local dir = pos - hrp.Position
			local dt = RunService.Heartbeat:Wait()
			local step = math.min(math.max(tonumber(cfg.dodgeSpeed) or 60, 5) * dt, dir.Magnitude)
			if dir.Magnitude > 0.01 then
				hrp.CFrame = hrp.CFrame + dir.Unit * step
			end
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
	end

	-- go to the nearest zone/statue that was not visited lately and stay there
	local function visit(list, hrp, hum, tok, stayDist)
		local best, bd
		for _, d in ipairs(list) do
			if not visited[d] or os.clock() - visited[d] > 30 then
				local dist = (objPos(d) - hrp.Position).Magnitude
				if not bd or dist < bd then
					best, bd = d, dist
				end
			end
		end
		if not best then
			visited = {} -- all done: start over while they still exist
			task.wait(0.3)
			return
		end
		local t0, arrivedAt = os.clock(), nil
		local maxWait = tonumber(cfg.raidWait) or 20
		while running and token == tok and best.Parent and hrp.Parent and hum.Health > 0 do
			if dodgeHit then
				task.wait(0.1)
				t0 = t0 + 0.1
				if arrivedAt then
					arrivedAt = arrivedAt + 0.1
				end
			else
				local pos = objPos(best)
				if (pos - hrp.Position).Magnitude < stayDist then
					arrivedAt = arrivedAt or os.clock()
					if os.clock() - arrivedAt > maxWait then
						break
					end
					task.wait(0.2) -- stay: the bar fills / the statue gets hit
				else
					if os.clock() - t0 > 25 then
						break
					end
					walkTo(hrp, hum, pos)
				end
			end
		end
		if not dodgeHit then
			visited[best] = os.clock()
		end
	end

	local function isRock(inst, rocks)
		for _, r in ipairs(rocks) do
			if inst == r or inst:IsDescendantOf(r) then
				return true
			end
		end
		return false
	end
	local function rockPoint(r)
		if r:IsA("Model") then
			local cf, size = r:GetBoundingBox()
			return cf.Position + Vector3.new(0, size.Y / 2 + 3, 0)
		end
		return r.Position + Vector3.new(0, r.Size.Y / 2 + 3, 0)
	end

	-- one lava step; false = no rocks (the lava phase is over / not started)
	local function lavaStep(hrp, hum, char)
		local rocks = find(cfg.raidRocks)
		if #rocks == 0 then
			return false
		end
		local here = hrp.Position
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { char }
		params.FilterType = Enum.RaycastFilterType.Exclude
		local hit = workspace:Raycast(here, Vector3.new(0, -10, 0), params)
		local onRock = hit ~= nil and isRock(hit.Instance, rocks)
		if onRock and hazardPen(here, 3) <= 0 then
			task.wait(0.05) -- safe on a rock: stay
			return true
		end
		local best, bs
		for _, r in ipairs(rocks) do
			local p = rockPoint(r)
			local dist = (p - here).Magnitude
			if dist > 4 and dist < 150 then
				local pen = hazardPen(p, 5)
				local score = (pen > 0 and 1000 + pen or 0) + dist
				if not bs or score < bs then
					best, bs = p, score
				end
			end
		end
		if best then
			hum.Jump = true -- hop
			local dir = best - here
			local dt = RunService.Heartbeat:Wait()
			local step = math.min(math.max(tonumber(cfg.dodgeSpeed) or 60, 60) * dt, dir.Magnitude)
			hrp.CFrame = hrp.CFrame + dir.Unit * step
			hrp.AssemblyLinearVelocity = Vector3.zero
		else
			task.wait(0.1)
		end
		return true
	end

	local function loop(tok)
		while running and token == tok do
			local char = Players.LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local bh = (hrp and hum and hum.Health > 0 and cfg.raidSelect == "Colosseum") and findBoss() or nil
			if not bh then
				raidLava = false
				hold(false)
				task.wait(0.6)
			else
				local pct = bh.MaxHealth > 0 and bh.Health / bh.MaxHealth * 100 or 100
				local zones, statues
				if pct <= 51 then
					statues = find(cfg.raidStatues)
				end
				if pct <= 76 then
					zones = find(cfg.raidZones)
				end
				if pct <= 26 and #find(cfg.raidRocks) > 0 then
					raidLava = true
					hold(true)
					lavaStep(hrp, hum, char)
				elseif statues and #statues > 0 then
					raidLava = false
					hold(true)
					visit(statues, hrp, hum, tok, 7)
				elseif zones and #zones > 0 then
					raidLava = false
					hold(true)
					visit(zones, hrp, hum, tok, 3)
				else
					raidLava = false
					hold(false)
					task.wait(0.4)
				end
			end
		end
		raidLava = false
		hold(false)
	end

	function RAID.set(on)
		if on then
			if running then
				return
			end
			running, token = true, {}
			setDodge("raid", true)
			task.spawn(loop, token)
		else
			running, token = false, nil
			setDodge("raid", false)
			raidLava = false
			hold(false)
		end
	end

	function RAID.status()
		local h = findBoss()
		if not h then
			return "Boss not found"
		end
		local pct = h.MaxHealth > 0 and math.floor(h.Health / h.MaxHealth * 100 + 0.5) or 0
		return ("%s %d%% | zones %d | statues %d | rocks %d"):format(
			h.Parent and h.Parent.Name or "?", pct, #find(cfg.raidZones), #find(cfg.raidStatues), #find(cfg.raidRocks)
		)
	end

	-- model/part names near you, nearest first (to find the real zone / statue / rock names)
	function RAID.nearby(radius)
		local char = Players.LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return nil
		end
		local best = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if (d:IsA("Model") or d:IsA("BasePart")) and not d:IsA("Terrain") and d.Name ~= "HumanoidRootPart" then
				local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
				if not (m and Players:GetPlayerFromCharacter(m)) and not d:IsA("Humanoid") then
					local dist = (objPos(d) - hrp.Position).Magnitude
					if dist <= radius and (not best[d.Name] or dist < best[d.Name]) then
						best[d.Name] = dist
					end
				end
			end
		end
		local list = {}
		for n, dist in pairs(best) do
			list[#list + 1] = { n = n, d = dist }
		end
		table.sort(list, function(a, b)
			return a.d < b.d
		end)
		local out = {}
		for i = 1, math.min(#list, 14) do
			out[i] = list[i].n
		end
		return out
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
local on = { autoJoin = false, autoCard = false, autoBubble = false, autoRift = false, autoFarm = false, autoDodge = false, bossDodge = false, autoRaid = false }
local SKIP = { pressMethod = true }
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

---------------------------------------------------------------- remote spy (map selection / queue)
-- Logs the remote calls sent by the game AND by this script, so you can pick a map by hand in the lobby and see
-- exactly what the game sends ("[game]"), then press Join Now and compare with what this script sends ("[script]").
-- Only lines that contain one of the "Filter words" are kept (empty filter = everything).
local SPY = {}
do
	local hooked, orig, running = false, nil, false
	local pending, log = {}, {}
	local LIMIT = 60

	local function pathOf(i)
		local parts, p = {}, i
		while p and p ~= game do
			table.insert(parts, 1, p.Name)
			p = p.Parent
		end
		return table.concat(parts, ".")
	end
	local function ser(v, depth)
		local t = typeof(v)
		if t == "string" then
			return string.format("%q", v)
		elseif t == "Instance" then
			return "<" .. v.ClassName .. " " .. pathOf(v) .. ">"
		elseif t == "table" then
			if (depth or 0) >= 2 then
				return "{...}"
			end
			local out, n = {}, 0
			for k, x in pairs(v) do
				n += 1
				if n > 8 then
					out[#out + 1] = "..."
					break
				end
				out[#out + 1] = (type(k) == "number" and "" or (tostring(k) .. "=")) .. ser(x, (depth or 0) + 1)
			end
			return "{" .. table.concat(out, ", ") .. "}"
		end
		return tostring(v)
	end
	local function line(c)
		local args = {}
		for i = 1, c.args.n do
			args[i] = ser(c.args[i])
		end
		return string.format("[%s] %s:%s(%s)", c.mine and "script" or "game", pathOf(c.remote), c.method, table.concat(args, ", "))
	end
	local function keep(text)
		local any, low = false, text:lower()
		for w in tostring(cfg.spyFilter or ""):gmatch("[^,;|]+") do
			w = (w:lower():gsub("^%s+", ""):gsub("%s+$", ""))
			if w ~= "" then
				any = true
				if low:find(w, 1, true) then
					return true
				end
			end
		end
		return not any
	end

	-- the hook only stores the raw call: no other work there, so the game's own call is never disturbed
	local function install()
		if hooked then
			return true
		end
		pcall(function()
			orig = hookmetamethod(game, "__namecall", (newcclosure or function(f) return f end)(function(self, ...)
				if running then
					local m = getnamecallmethod()
					if (m == "FireServer" or m == "InvokeServer") and typeof(self) == "Instance" then
						local cn = self.ClassName
						if cn == "RemoteEvent" or cn == "RemoteFunction" then
							pending[#pending + 1] = {
								remote = self,
								method = m,
								args = table.pack(...),
								mine = (checkcaller and checkcaller()) or false,
							}
						end
					end
				end
				return orig(self, ...)
			end))
		end)
		hooked = orig ~= nil
		return hooked
	end

	local function flush()
		while running do
			while #pending > 0 do
				local c = table.remove(pending, 1)
				local ok, text = pcall(line, c)
				if ok and keep(text) then
					log[#log + 1] = text
					if #log > LIMIT then
						table.remove(log, 1)
					end
					noti("Spy", text:sub(1, 160), 5)
				end
			end
			task.wait(0.25)
		end
	end

	function SPY.set(on)
		if on then
			if running then
				return true
			end
			if not (hookmetamethod and getnamecallmethod) or not install() then
				return false
			end
			running = true
			task.spawn(flush)
			return true
		end
		running = false
		if hooked then
			hooked = false
			pcall(hookmetamethod, game, "__namecall", orig) -- put the original back (the wrapper stays harmless if this fails)
		end
		pending = {}
		return true
	end
	function SPY.last(n)
		local out = {}
		for i = math.max(#log - n + 1, 1), #log do
			out[#out + 1] = log[i]
		end
		return out
	end
	function SPY.copy()
		local copy = setclipboard or toclipboard or (syn and syn.write_clipboard)
		return copy ~= nil and #log > 0 and pcall(copy, table.concat(log, "\n"))
	end
	function SPY.clear()
		log = {}
	end
end

---------------------------------------------------------------- UI
local Main = UI.CreateMain({ Title = "Levian Hub", Desc = " - Final Swarm" })
local PageA = Main.CreatePage({ Page_Name = "About Us", Page_Title = "About Us" })
local SAb = PageA.CreateSection("About Us")
SAb.CreateLabel({ Title = "Levian Hub" })
-- centre the label (the library labels are left-aligned by default)
pcall(function()
	for _, root in ipairs({ game:GetService("CoreGui"), (gethui and gethui()) or game:GetService("CoreGui") }) do
		local g = root:FindFirstChild("Levian Hub GUI")
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

-- Lobby tab: only in the lobby (99521272836282), not inside a match (79787558257549)
if IN_LOBBY then
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

local SSpy = Page.CreateSection("SPY")
local spyTog
spyTog = SSpy.CreateToggle({ Title = "Remote Spy", Desc = "Logs remote calls: pick a map by hand and see what it sends", Default = false }, function(v)
	if v and not SPY.set(true) then
		noti("Spy", "This executor cannot hook remotes (no hookmetamethod)", 5)
		if spyTog then
			pcall(spyTog.SetValue, false)
		end
		return
	end
	if not v then
		SPY.set(false)
	end
	UI.CreateNoti({ Title = "Remote Spy", Desc = v and "ON" or "OFF", ShowTime = 2 })
end)
SSpy.CreateBox({ Title = "Filter words", Default = cfg.spyFilter }, function(v)
	cfg.spyFilter = tostring(v or "")
	save()
end)
SSpy.CreateButton({ Title = "Show last calls" }, function()
	local last = SPY.last(4)
	noti("Spy", #last > 0 and table.concat(last, "\n"):sub(1, 400) or "No calls logged", 10)
end)
SSpy.CreateButton({ Title = "Copy log" }, function()
	noti("Spy", SPY.copy() and "Log copied" or "Nothing to copy", 3)
end)
SSpy.CreateButton({ Title = "Clear log" }, function()
	SPY.clear()
	noti("Spy", "Log cleared", 2)
end)
end

local PageF = Main.CreatePage({ Page_Name = "Farm Setting", Page_Title = "Farm Setting" })

local SFl = PageF.CreateSection("AUTO FARM")
tog.autoFarm = SFl.CreateToggle({ Title = "Auto Farm", Desc = "Fly / walk around where you switched it on", Default = false }, function(v)
	flyAuto = v and true or false
	on.autoFarm = flyAuto
	UI.CreateNoti({ Title = "Auto Farm", Desc = flyAuto and ("ON - " .. tostring(cfg.flyMode)) or "OFF", ShowTime = 2 })
	if flyAuto then
		startFarm()
	end
end)
reg.flyMode = SFl.CreateDropdown({ Title = "Mode", List = { "Walk Around", "Walk Circle", "Fly(risk)" }, Default = cfg.flyMode }, function(v)
	cfg.flyMode = v
	save()
	if flyAuto then
		startFarm() -- switch the running mode
	end
end)
reg.flyDistance = SFl.CreateSlider({ Title = "Distance (radius)", Min = 1, Max = 100, Default = tonumber(cfg.flyDistance) or 30 }, function(v)
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
-- DODGE
do
	local SDg = PageF.CreateSection("DODGE")
	tog.autoDodge = SDg.CreateToggle({ Title = "Auto Dodge", Desc = "Steps out of hit circles", Default = false }, function(v)
		on.autoDodge = v and true or false
		setDodge("campaign", v)
		UI.CreateNoti({ Title = "Auto Dodge", Desc = v and "ON" or "OFF", ShowTime = 2 })
	end)
	tog.bossDodge = SDg.CreateToggle({ Title = "Boss Dodge", Desc = "Dodges hit circles only while a boss is alive", Default = false }, function(v)
		on.bossDodge = v and true or false
		setDodge("campaignBoss", v)
		UI.CreateNoti({ Title = "Boss Dodge", Desc = v and "ON" or "OFF", ShowTime = 2 })
	end)
	reg.dodgeRed = SDg.CreateToggle({ Title = "Dodge red zones / lines", Desc = "Also avoids flat red parts, not only parts with a matching name", Default = cfg.dodgeRed }, function(v)
		cfg.dodgeRed = v and true or false
		save()
	end)
	reg.bossName = SDg.CreateBox({ Title = "Boss name contains", Default = cfg.bossName }, function(v)
		cfg.bossName = tostring(v or "")
		save()
	end)
	reg.dodgePatterns = SDg.CreateBox({ Title = "Hit zone names", Default = cfg.dodgePatterns }, function(v)
		cfg.dodgePatterns = tostring(v or "")
		save()
	end)
	reg.dodgeMode = SDg.CreateDropdown({ Title = "Dodge mode", List = { "Safe", "Tween" }, Default = cfg.dodgeMode }, function(v)
		cfg.dodgeMode = v
		save()
	end)
	reg.dodgeSpeed = SDg.CreateSlider({ Title = "Dodge speed (Tween)", Min = 10, Max = 150, Default = tonumber(cfg.dodgeSpeed) or 60 }, function(v)
		cfg.dodgeSpeed = v
		save()
	end)
	reg.dodgeMargin = SDg.CreateSlider({ Title = "Safe distance outside circle", Min = 1, Max = 30, Default = tonumber(cfg.dodgeMargin) or 6 }, function(v)
		cfg.dodgeMargin = v
		save()
	end)
	SDg.CreateButton({ Title = "Show nearby flat parts" }, function()
		local names = nearbyFlat(80)
		if not names then
			noti("Dodge", "Character not found", 3)
		elseif #names == 0 then
			noti("Dodge", "No flat parts within 80 studs", 4)
		else
			noti("Dodge", table.concat(names, " | "), 8)
		end
	end)
	SDg.CreateButton({ Title = "Show nearby enemies" }, function()
		local names = nearbyEnemies(300)
		if not names then
			noti("Dodge", "Character not found", 3)
		elseif #names == 0 then
			noti("Dodge", "No enemies within 300 studs", 4)
		else
			noti("Dodge", table.concat(names, " | ") .. (bossExists() and "  (boss found)" or "  (no boss matched)"), 8)
		end
	end)
	SDg.CreateLabel({ Title = "Stand next to a hit circle, press 'Show nearby flat parts', then put its name in Hit zone names." })
	SDg.CreateLabel({ Title = "Names are comma separated, e.g. Telegraph,AOE." })
end

local PageC = Main.CreatePage({ Page_Name = "Campaign", Page_Title = "Campaign" })

local SB = PageC.CreateSection("AUTO BUBBLE")
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
SB.CreateLabel({ Title = "Goes to a bubble when oxygen is below the slider value." })

local SR = PageC.CreateSection("AUTO RIFT")
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
SR.CreateLabel({ Title = "Auto Bubble has priority when oxygen is low." })

local SA = PageC.CreateSection("AFTER MATCH")
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


do
	local PageR = Main.CreatePage({ Page_Name = "Raid", Page_Title = "Raid" })
	local SRa = PageR.CreateSection("AUTO RAID")
	tog.autoRaid = SRa.CreateToggle({ Title = "Auto Raid", Desc = "Plays the boss phases of the selected raid", Default = false }, function(v)
		on.autoRaid = v and true or false
		RAID.set(v)
		UI.CreateNoti({ Title = "Auto Raid", Desc = v and ("ON - " .. tostring(cfg.raidSelect)) or "OFF", ShowTime = 2 })
	end)
	reg.raidSelect = SRa.CreateDropdown({ Title = "Raid", List = { "Colosseum" }, Default = cfg.raidSelect }, function(v)
		cfg.raidSelect = v
		save()
	end)
	reg.raidWait = SRa.CreateSlider({ Title = "Max wait per zone / statue (s)", Min = 5, Max = 60, Default = tonumber(cfg.raidWait) or 20 }, function(v)
		cfg.raidWait = v
		save()
	end)
	reg.raidZones = SRa.CreateBox({ Title = "75% corner zone names", Default = cfg.raidZones }, function(v)
		cfg.raidZones = tostring(v or "")
		save()
	end)
	reg.raidStatues = SRa.CreateBox({ Title = "50% statue names", Default = cfg.raidStatues }, function(v)
		cfg.raidStatues = tostring(v or "")
		save()
	end)
	reg.raidRocks = SRa.CreateBox({ Title = "25% lava rock names", Default = cfg.raidRocks }, function(v)
		cfg.raidRocks = tostring(v or "")
		save()
	end)
	SRa.CreateButton({ Title = "Show raid status" }, function()
		noti("Raid", RAID.status(), 6)
	end)
	SRa.CreateButton({ Title = "Show nearby objects" }, function()
		local names = RAID.nearby(120)
		if not names then
			noti("Raid", "Character not found", 3)
		else
			noti("Raid", table.concat(names, " | "), 10)
		end
	end)
	SRa.CreateLabel({ Title = "Boss name: Farm Setting > Boss name contains (empty = the boss with the most health)." })
end

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

-- open the first working tab (Lobby in the lobby, Campaign in a match)
local firstTab = IN_LOBBY and "Lobby" or "Campaign"
pcall(function()
	for _, root in ipairs({ game:GetService("CoreGui"), (gethui and gethui()) or game:GetService("CoreGui") }) do
		local g = root:FindFirstChild("Levian Hub GUI")
		if g then
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("TextButton") and d.Text == firstTab then
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

UI.CreateNoti({ Title = "Final Swarm v26", Desc = "Menu ready. Pick a mode, then Join Now.", ShowTime = 5 })

-- Auto Minimize: hide the window like the "-" button does (the X logo stays and reopens it)
if cfg.autoMinimize then
	task.delay(2, function()
		pcall(Main.SetVisible, false)
	end)
end
