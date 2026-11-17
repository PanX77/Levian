--[[
	Final Swarm - Lobby (v11)
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

-- press a button the way a click does (the button has one connection, either Click or Activated)
local function press(btn)
	local ok = false
	if firesignal then
		pcall(function()
			firesignal(btn.MouseButton1Click)
			ok = true
		end)
		pcall(function()
			firesignal(btn.Activated)
			ok = true
		end)
	end
	if not ok and getconnections then
		pcall(function()
			for _, c in ipairs(getconnections(btn.MouseButton1Click)) do
				c:Fire()
			end
			for _, c in ipairs(getconnections(btn.Activated)) do
				c:Fire()
			end
			ok = true
		end)
	end
	return ok
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

local cardAuto, cardToken = false, nil
local lastSig, lastAt, rerolls, banishes = "", 0, 0, 0
local function cardStep()
	local cards = getCards()
	if not cards then
		lastSig, rerolls, banishes = "", 0, 0
		return
	end
	local names = {}
	for _, c in ipairs(cards) do
		names[#names + 1] = c.name
	end
	local sig = table.concat(names, "|")
	if sig == lastSig and os.clock() - lastAt < 4 then
		return -- this offer was already handled
	end
	lastSig, lastAt = sig, os.clock()
	task.wait(0.5) -- let the offer settle

	local pick = chooseCard(cards)
	if pick then
		if press(pick.btn) then
			noti("Auto Card", "Picked: " .. pick.name, 3)
		end
		return
	end

	-- nothing wanted: banish an unwanted card (opt-in). Banish = press Banish, then press the card.
	if cfg.cardBanish and banishes < 3 then
		for _, c in ipairs(cards) do
			if inList(cfg.banishList, c.name) then
				local bb = frameButton("banish")
				if bb and press(bb) then
					task.wait(0.5)
					if press(c.btn) then
						banishes += 1
						noti("Auto Card", "Banished: " .. c.name, 3)
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
		if rb and press(rb) then
			rerolls += 1
			noti("Auto Card", "Reroll " .. rerolls .. "/" .. tostring(cfg.cardMaxRerolls), 2)
			return
		end
	end
	local fallback = cards[1]
	for _, c in ipairs(cards) do
		if not inList(cfg.banishList, c.name) then
			fallback = c
			break
		end
	end
	if press(fallback.btn) then
		noti("Auto Card", "Picked: " .. (fallback.name ~= "" and fallback.name or "?"), 3)
	end
end

---------------------------------------------------------------- auto bubble (in-match)
-- The scanner showed the bubbles are Models named "OxygenBubble" inside workspace.EnvironmentOxygenBubbles.
-- If that folder exists it is used directly; otherwise parts/models whose name contains the text in
-- "Bubble name contains" are searched in the whole workspace.
-- Safe  = Roblox's own walking (Humanoid:MoveTo)
-- Tween = moves the character toward the bubble at speed 20
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
local BUBBLE_SPEED = 20
local bubbleAuto, bubbleToken = false, nil
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
				local reached = false
				while bubbleAuto and bubbleToken == token and os.clock() - started < 20 do
					local inst = target.inst
					if not inst.Parent or not hrp.Parent or hum.Health <= 0 then
						break
					end
					local dir = objPos(inst) - hrp.Position
					if dir.Magnitude < 3 then
						reached = true
						break
					end
					if cfg.bubbleMode == "Tween" then
						local dt = RunService.Heartbeat:Wait()
						local step = math.min(BUBBLE_SPEED * dt, dir.Magnitude)
						hrp.CFrame = hrp.CFrame + dir.Unit * step
						hrp.AssemblyLinearVelocity = Vector3.zero
					else
						hum:MoveTo(objPos(inst))
						task.wait(0.25)
					end
				end
				-- stay inside the bubble for a while (oxygen refills while you are in it)
				local stay = tonumber(cfg.bubbleStay) or 0
				local t0 = os.clock()
				while
					reached
					and stay > 0
					and bubbleAuto
					and bubbleToken == token
					and os.clock() - t0 < stay
					and target.inst.Parent
					and hum.Health > 0
				do
					local o = readOxygen()
					if o and o >= 99 then
						break -- oxygen is full
					end
					task.wait(0.25)
				end
				bubbleVisited[target.inst] = os.clock()
			end
			end
		end
	end
end

---------------------------------------------------------------- UI
local Main = UI.CreateMain({ Title = "Final Swarm", Desc = " - Lobby" })
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
			b.Text = "X"
		end
	end
end)
local Page = Main.CreatePage({ Page_Name = "Lobby", Page_Title = "Lobby" })

local S1 = Page.CreateSection("CAMPAIGN")
S1.CreateDropdown({ Title = "Mode", List = { "Solo", "Duo", "Trio", "Squad" }, Default = cfg.mode }, function(v)
	cfg.mode = v
	save()
end)
S1.CreateDropdown({ Title = "Difficulty", List = { "Normal", "Hard", "Nightmare" }, Default = cfg.difficulty }, function(v)
	cfg.difficulty = v
	save()
end)
S1.CreateDropdown({
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
S1.CreateDropdown({
	Title = "Map",
	List = { "None", "Grasslands", "Desert", "Swamp", "Jungle", "Frost Forest", "Volcano", "Atlantis", "Crystal Cavern" },
	Default = cfg.map,
}, function(v)
	cfg.map = v
	save()
end)

local SR = Page.CreateSection("RAID")
SR.CreateDropdown({ Title = "Raid", List = RAID_NAMES, Default = cfg.raid }, function(v)
	cfg.raid = v
	save()
end)
SR.CreateDropdown({ Title = "Difficulty", List = { "Normal", "Hard", "Nightmare" }, Default = cfg.raidDifficulty }, function(v)
	cfg.raidDifficulty = v
	save()
end)
SR.CreateDropdown({ Title = "Mode", List = { "Solo", "Duo", "Trio", "Squad" }, Default = cfg.raidMode }, function(v)
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
SD.CreateDropdown({ Title = "Floor", List = floorNames, Default = tostring(cfg.dungeonFloor) }, function(v)
	cfg.dungeonFloor = v
	save()
end)
SD.CreateDropdown({ Title = "Mode", List = { "Solo", "Duo", "Trio", "Squad" }, Default = cfg.dungeonMode }, function(v)
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
S2.CreateToggle({ Title = "Auto Join", Desc = "Retries every 20s; waits 2 minutes after a success", Default = false }, function(v)
	auto = v and true or false
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

local SF = PageF.CreateSection("AUTO CARD")
SF.CreateToggle({ Title = "Auto Card", Desc = "Picks a card when the offers appear", Default = false }, function(v)
	cardAuto = v and true or false
	UI.CreateNoti({ Title = "Auto Card", Desc = cardAuto and "ON" or "OFF", ShowTime = 2 })
	if cardAuto then
		local token = {}
		cardToken = token
		task.spawn(function()
			while cardAuto and cardToken == token do
				pcall(cardStep)
				task.wait(0.5)
			end
		end)
	end
end)
SF.CreateDropdown({ Title = "Prefer", List = { "Weapons first", "Cards first" }, Default = cfg.cardPrefer }, function(v)
	cfg.cardPrefer = v
	save()
end)
SF.CreateDropdown({ Title = "Weapons", List = WEAPONS, Multi = true, Search = true, Default = cfg.weaponsWanted }, function(sel)
	cfg.weaponsWanted = toArray(WEAPONS, sel)
	save()
end)
SF.CreateDropdown({ Title = "Cards", List = CARDS, Multi = true, Search = true, Default = cfg.cardsWanted }, function(sel)
	cfg.cardsWanted = toArray(CARDS, sel)
	save()
end)
SF.CreateDropdown({ Title = "If nothing matches", List = { "Pick first card", "Reroll", "Do nothing" }, Default = cfg.cardFallback }, function(v)
	cfg.cardFallback = v
	save()
end)
SF.CreateSlider({ Title = "Max rerolls per offer", Min = 0, Max = 10, Default = tonumber(cfg.cardMaxRerolls) or 3 }, function(v)
	cfg.cardMaxRerolls = v
	save()
end)
SF.CreateToggle({ Title = "Auto Banish", Desc = "Removes cards from the Banish list", Default = cfg.cardBanish }, function(v)
	cfg.cardBanish = v and true or false
	save()
end)
SF.CreateDropdown({ Title = "Banish list", List = BANISH_ALL, Multi = true, Search = true, Default = cfg.banishList }, function(sel)
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
SB.CreateToggle({ Title = "Auto Bubble", Desc = "Moves to the nearest bubble", Default = false }, function(v)
	bubbleAuto = v and true or false
	UI.CreateNoti({ Title = "Auto Bubble", Desc = bubbleAuto and ("ON - " .. tostring(cfg.bubbleMode)) or "OFF", ShowTime = 2 })
	if bubbleAuto then
		local token = {}
		bubbleToken = token
		task.spawn(bubbleLoop, token)
	end
end)
SB.CreateSlider({ Title = "Take bubble below (%)", Min = 0, Max = 100, Default = tonumber(cfg.bubbleBelow) or 80 }, function(v)
	cfg.bubbleBelow = v
	save()
end)
SB.CreateDropdown({ Title = "Mode", List = { "Safe", "Tween" }, Default = cfg.bubbleMode }, function(v)
	cfg.bubbleMode = v
	save()
end)
SB.CreateBox({ Title = "Bubble name contains", Default = cfg.bubbleName }, function(v)
	cfg.bubbleName = (type(v) == "string" and v ~= "") and v or "bubble"
	save()
end)
SB.CreateSlider({ Title = "Stay in bubble (seconds)", Min = 0, Max = 30, Default = tonumber(cfg.bubbleStay) or 5 }, function(v)
	cfg.bubbleStay = v
	save()
end)
SB.CreateBox({ Title = "Oxygen UI path (optional)", Default = cfg.oxygenPath }, function(v)
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
SB.CreateLabel({ Title = "Safe: walks normally. Tween: moves at speed 20." })

UI.CreateNoti({ Title = "Final Swarm v11", Desc = "Menu ready. Pick a mode, then Join Now.", ShowTime = 5 })
