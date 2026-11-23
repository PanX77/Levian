--[[
	Levian Hub - Minesweeper
	Auto Farm: minesweeper solver + flag mines + walk to safe blocks.

	- Mines can't be read from the client. The bot deduces them from the revealed numbers
	  and only acts on what is CERTAIN.
	- The avatar only walks over opened blocks, then steps on blocks that are certainly safe.
	- Flags: PlaceFlag needs a token that changes every session. The script tries to find it
	  automatically; if that fails, place 1 flag manually and the script will learn it.
]]

---------------------------------------------------------------- load UI
local UI
do
	local ok, res = pcall(function()
		return loadstring(game:HttpGet("https://levianstore.my.id/LevianUI.lua"))()
	end)
	if ok and res then
		UI = res
	else
		UI = loadstring(readfile("LevianUI.lua"))() -- fallback: local file
	end
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer

---------------------------------------------------------------- state
local F = {
	Run = false,
	Busy = false,
	Guess = false, -- guess when stuck (risky)
	Human = true, -- walking style: randomized route and target
	Flagging = true,
	PassFlags = true, -- allow walking over flagged blocks (shorter routes)
	FlagRange = 12, -- stud
	Delay = 0.15,
	CellSize = 5, -- size of 1 cell (studs)
	failed = {},
	AutoEvent = false, -- press "Yes" on the event round vote
	AutoSecret = false, -- spam "Yes" until the secret event vote shows up
	EventKw = "event round", -- text that identifies the event vote
	pressing = false,
	abort = false, -- set by the watchdog when the game ends/restarts: all walking and flagging stops
	WatchBusy = false,
	firedAt = {}, -- cell key -> time PlaceFlag was last fired on it
	firedCount = {}, -- cell key -> times PlaceFlag was fired on it this game (max 2)
	-- dodge spike
	Dodge = false, -- master switch
	DodgeMove = true, -- step off hazardous cells
	DodgeJump = true, -- jump when stepping off is not possible / the area is crowded
	SpikeRadius = 12, -- studs: the "area" around the player
	SpikeCount = 10, -- hazardous cells in the area that count as crowded (jump instead of walking)
	SpikeEta = 1.15, -- seconds from the warning to the spikes (measured from videos)
	SpikeLead = 0.2, -- jump this many seconds before the spikes come out
	SpikeMaxSteps = 2, -- only walk away if a safe cell is at most this many cells away
	SpikeName = "Warn", -- name of the warning sound inside a cell
	SpikeSound = "Slash", -- name of the spike sound inside a cell
	dodging = false,
	DodgeBusy = false,
	dangerKeys = {}, -- cell keys that are hazardous right now
	lastJump = 0,
	-- manual solver (ESP + auto-flag)
	ManualSafe = true,
	ManualBomb = true,
	ManualHalf = true,
	ManualSuggest = true,
	ManualAuto = false,
	ManualRadius = 20,
	ManualDelay = 100,
	settingsReady = false,
}

---------------------------------------------------------------- settings (JSON)
-- saved to: Levian Hub/<PlayerName>-minesweeper.json
local SETTINGS_KEYS = {
	"Guess", "Human", "Flagging", "PassFlags", "FlagRange", "Delay",
	"AutoEvent", "AutoSecret", "EventKw",
	"Dodge", "DodgeMove", "DodgeJump", "SpikeRadius", "SpikeCount", "SpikeEta", "SpikeLead", "SpikeMaxSteps", "SpikeName", "SpikeSound",
	"ManualSafe", "ManualBomb", "ManualHalf", "ManualSuggest", "ManualRadius", "ManualDelay",
}
local SETTINGS_FILE = "Levian Hub/" .. LP.Name .. "-minesweeper.json"
local saveGen = 0

local function loadSettings()
	local ok, data = pcall(function()
		if isfile and readfile and isfile(SETTINGS_FILE) then
			return HttpService:JSONDecode(readfile(SETTINGS_FILE))
		end
	end)
	if ok and type(data) == "table" then
		for _, k in ipairs(SETTINGS_KEYS) do
			if data[k] ~= nil and type(data[k]) == type(F[k]) then
				F[k] = data[k]
			end
		end
	end
end

-- debounced: sliders fire many times while dragging, the file is written once
local function saveSettings()
	if not F.settingsReady then
		return
	end
	saveGen += 1
	local mine = saveGen
	task.delay(0.5, function()
		if mine ~= saveGen then
			return
		end
		pcall(function()
			if makefolder and isfolder and not isfolder("Levian Hub") then
				makefolder("Levian Hub")
			end
			local t = {}
			for _, k in ipairs(SETTINGS_KEYS) do
				t[k] = F[k]
			end
			writefile(SETTINGS_FILE, HttpService:JSONEncode(t))
		end)
	end)
end

loadSettings()
local logs = {}
local flagTemplate -- PlaceFlag arguments (the part is swapped when used)
local lblTpl, lblFarm

---------------------------------------------------------------- util
-- this game names instances with many newlines; replace them with "¶" to keep logs tidy
local function path(i)
	local ok, n = pcall(function()
		return i:GetFullName()
	end)
	n = ok and n or tostring(i)
	return (n:gsub("%c+", "¶"))
end

local function ser(v, depth, seen)
	depth = depth or 0
	local t = typeof(v)
	if t == "string" then
		return string.format("%q", v)
	elseif t == "Instance" then
		return "<" .. v.ClassName .. ">" .. path(v)
	elseif t == "Vector3" then
		return ("Vector3(%.2f, %.2f, %.2f)"):format(v.X, v.Y, v.Z)
	elseif t == "Vector2" then
		return ("Vector2(%.2f, %.2f)"):format(v.X, v.Y)
	elseif t == "CFrame" then
		local p = v.Position
		return ("CFrame(%.2f, %.2f, %.2f)"):format(p.X, p.Y, p.Z)
	elseif t == "table" then
		if depth >= 3 then
			return "{...}"
		end
		seen = seen or {}
		if seen[v] then
			return "{<cycle>}"
		end
		seen[v] = true
		local parts, n = {}, 0
		for k, x in pairs(v) do
			n += 1
			if n > 25 then
				parts[#parts + 1] = "..."
				break
			end
			parts[#parts + 1] = "[" .. ser(k, depth + 1, seen) .. "]=" .. ser(x, depth + 1, seen)
		end
		seen[v] = nil
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

local function setLabel(l, text)
	if l and l.SetText then
		l.SetText(text)
	end
end

local function push(line)
	logs[#logs + 1] = line
	if #logs > 500 then
		table.remove(logs, 1)
	end
	print("[MS] " .. line)
end

---------------------------------------------------------------- token
-- the real flag token: an upvalue of the game's own ReplicatedFirst.MouseControl closure that references "PlaceFlag"
-- (needs filtergc; same technique as the open-source solver)
local function findFlagToken()
	if not filtergc then
		return nil
	end
	local ok, closures = pcall(filtergc, "function", { Constants = { "PlaceFlag" }, IgnoreExecutor = true }, false)
	if not ok or type(closures) ~= "table" then
		return nil
	end
	for _, closure in ipairs(closures) do
		local okS, src = pcall(debug.info, closure, "s")
		if okS and type(src) == "string" and src:find("ReplicatedFirst.MouseControl", 1, true) then
			local okU, ups = pcall(debug.getupvalues, closure)
			if okU and type(ups) == "table" then
				for _, v in pairs(ups) do
					if type(v) == "string" and v:match("^%d+$") then
						return v
					end
				end
			end
		end
	end
	return nil
end

-- make sure Auto Farm has the flag arguments: read the game's own token (retried every 2s until the game's
-- code is loaded; no test shots, no guessing). A manual flag still works as a fallback.
local nextTokenTry = 0
local function ensureTemplate()
	if flagTemplate or os.clock() < nextTokenTry then
		return
	end
	nextTokenTry = os.clock() + 2
	local tk = findFlagToken()
	if tk then
		flagTemplate = { n = 3, [2] = tk, [3] = true }
		setLabel(lblTpl, "Flag template: automatic (token ..." .. tk:sub(-4) .. ")")
		push("TOKEN read from the game (MouseControl)")
	else
		setLabel(lblTpl, "Flag template: waiting for the game's token (or place 1 flag manually)")
	end
end

-- learn the template from a manual flag (fallback if the automatic token is not found)
local function setTemplate(a)
	flagTemplate = a
	setLabel(lblTpl, "Flag template: ready (token ..." .. tostring(a[2]):sub(-4) .. ")")
end
if hookmetamethod and getnamecallmethod and newcclosure then
	local old
	old = hookmetamethod(
		game,
		"__namecall",
		newcclosure(function(self, ...)
			local m = getnamecallmethod()
			if
				(m == "FireServer" or m == "fireServer")
				and typeof(self) == "Instance"
				and not checkcaller()
				and self.Name == "PlaceFlag"
			then
				task.defer(setTemplate, table.pack(...))
			end
			return old(self, ...)
		end)
	)
else
	warn("[MS] Executor does not support hookmetamethod: cannot learn the template from a manual flag")
end

---------------------------------------------------------------- AUTO FARM (minesweeper solver)
local proveMines -- set by the Manual module: mines proven by the stronger solver (key -> part)
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local function dirs()
	if not F.Human then
		return DIRS
	end
	local d = { DIRS[1], DIRS[2], DIRS[3], DIRS[4] }
	for i = 4, 2, -1 do
		local j = math.random(1, i)
		d[i], d[j] = d[j], d[i]
	end
	return d
end

local function fstatus(t)
	setLabel(lblFarm, "Status: " .. t)
end
local function ckey(x, z)
	return x .. "," .. z
end
local function revealed(c)
	return c.state == "num" or c.state == "zero"
end
-- walkable: opened blocks, or (optionally) flagged blocks
local function standable(c)
	return revealed(c) or (F.PassFlags and c.state == "flag")
end
-- walkable for routes: standable and not covered by a spike warning
local function passable(c)
	return standable(c) and not c.danger
end
local function flagged(part)
	return part:FindFirstChildWhichIsA("Model") ~= nil
end

-- the cell size follows the board (some themes/modes use other tile sizes)
local function syncCellSize()
	local f = workspace:FindFirstChild("Flag")
	local parts = f and f:FindFirstChild("Parts")
	local first = parts and parts:FindFirstChildWhichIsA("BasePart")
	if first and first.Size.X > 0.5 then
		F.CellSize = first.Size.X
	end
end

-- Reads a tile exactly like the Manual solver does, with NO colors, so it works on every board theme:
--   no NumberGui      -> unopened ("flag" if it carries a flag Model)
--   NumberGui text    -> "" = 0, "1".."8" = clue; "X" or anything else = treated like a flag (never walked on)
-- state: flag | num | unk | pending (flag fired, not visible yet)
local function makeCell(p)
	local x = math.floor(p.Position.X / F.CellSize + 0.5)
	local z = math.floor(p.Position.Z / F.CellSize + 0.5)
	local c = { part = p, x = x, z = z, key = ckey(x, z) }
	local gui = p:FindFirstChild("NumberGui")
	if not gui then
		c.state = flagged(p) and "flag" or "unk"
	else
		local label = gui:FindFirstChild("TextLabel")
		local text = label and label:IsA("TextLabel") and label.Text or nil
		local clue = text ~= nil and (text == "" and 0 or tonumber(text)) or nil
		if clue and clue >= 0 and clue <= 8 and clue % 1 == 0 then
			c.state, c.n = "num", clue
		else
			c.state = "flag"
		end
	end
	if c.state == "unk" then
		local t = F.firedAt[c.key]
		if t and os.clock() - t < 6 then
			c.state = "pending" -- flag fired, not visible yet: counts as a mine, never walkable
		end
	end
	return c
end

local function buildBoard()
	local f = workspace:FindFirstChild("Flag")
	local parts = f and f:FindFirstChild("Parts")
	if not parts then
		return nil
	end
	syncCellSize()
	local B = { cells = {}, list = {} }
	for _, p in ipairs(parts:GetChildren()) do
		if p:IsA("BasePart") then
			local c = makeCell(p)
			B.cells[c.key] = c
			B.list[#B.list + 1] = c
		end
	end
	if F.Dodge then
		for key in pairs(F.dangerKeys) do
			local c = B.cells[key]
			if c then
				c.danger = true
			end
		end
	end
	return B
end

local function nbrs(B, c)
	local out = {}
	for dx = -1, 1 do
		for dz = -1, 1 do
			if dx ~= 0 or dz ~= 0 then
				local n = B.cells[ckey(c.x + dx, c.z + dz)]
				if n then
					out[#out + 1] = n
				end
			end
		end
	end
	return out
end

-- solver: basic rule + subset rule. Only marks what is CERTAIN.
local function solve(B)
	local cons = {}
	for _, c in ipairs(B.list) do
		if c.state == "num" and c.n then
			local U, fl = {}, 0
			for _, n in ipairs(nbrs(B, c)) do
				if n.state == "flag" or n.state == "pending" then
					fl += 1
				elseif n.state == "unk" then
					U[#U + 1] = n
				end
			end
			if #U > 0 then
				cons[#cons + 1] = { src = c, U = U, rem = c.n - fl }
			end
		end
	end
	local mineK, safeK = {}, {}
	local function reduce(k)
		local U, rem = {}, k.rem
		for _, u in ipairs(k.U) do
			if mineK[u.key] then
				rem -= 1
			elseif not safeK[u.key] then
				U[#U + 1] = u
			end
		end
		return U, rem
	end
	local function markAll(list, tbl, src)
		local new = false
		for _, u in ipairs(list) do
			if not tbl[u.key] then
				tbl[u.key] = { cell = u, src = src }
				new = true
			end
		end
		return new
	end
	local progress, rounds = true, 0
	while progress and rounds < 30 do
		progress, rounds = false, rounds + 1
		local red = {}
		for i, k in ipairs(cons) do
			local U, rem = reduce(k)
			red[i] = { U = U, rem = rem, src = k.src }
			if #U > 0 then
				if rem == 0 then
					progress = markAll(U, safeK, k.src) or progress
				elseif rem == #U then
					progress = markAll(U, mineK, k.src) or progress
				end
			end
		end
		if not progress then
			for i = 1, #red do
				for j = 1, #red do
					local a, b = red[i], red[j]
					if i ~= j and #a.U > 0 and #a.U < #b.U then
						local inB, sub = {}, true
						for _, u in ipairs(b.U) do
							inB[u.key] = true
						end
						for _, u in ipairs(a.U) do
							if not inB[u.key] then
								sub = false
								break
							end
						end
						if sub then
							local inA, diff = {}, {}
							for _, u in ipairs(a.U) do
								inA[u.key] = true
							end
							for _, u in ipairs(b.U) do
								if not inA[u.key] then
									diff[#diff + 1] = u
								end
							end
							local drem = b.rem - a.rem
							if drem == 0 then
								progress = markAll(diff, safeK, b.src) or progress
							elseif drem == #diff then
								progress = markAll(diff, mineK, b.src) or progress
							end
						end
					end
				end
			end
		end
	end
	return mineK, safeK, cons, reduce
end

-- cell under the avatar
local function curCell(B)
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	return B.cells[ckey(math.floor(hrp.Position.X / F.CellSize + 0.5), math.floor(hrp.Position.Z / F.CellSize + 0.5))]
end

-- 4-direction BFS, only through opened cells (never steps on unopened ones)
local function bfs(B, from, goalFn)
	local q, head, prev = { from }, 1, { [from.key] = false }
	while head <= #q do
		local c = q[head]
		head += 1
		if goalFn(c) then
			local path, cur = {}, c
			while cur do
				table.insert(path, 1, cur)
				cur = prev[cur.key]
			end
			return path
		end
		for _, d in ipairs(DIRS) do
			local n = B.cells[ckey(c.x + d[1], c.z + d[2])]
			if n and prev[n.key] == nil and passable(n) then
				prev[n.key] = c
				q[#q + 1] = n
			end
		end
	end
	return nil
end

-- cancel the current walk immediately
local function stopWalking()
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hrp then
		pcall(function()
			hum:MoveTo(hrp.Position)
		end)
	end
end

-- wait until the stepped block opens (checks every 0.02s) instead of a fixed delay
local function waitRevealed(cell)
	local t0 = os.clock()
	while F.Run and not F.abort and os.clock() - t0 < 0.6 do
		local p = cell.part
		if p:FindFirstChild("NumberGui") then
			return true
		end
		task.wait(0.02)
	end
	return false
end

local function moveTo(cell, straight)
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if F.abort or not hum or not hrp or hum.Health <= 0 then
		return false
	end
	local tx, tz = cell.part.Position.X, cell.part.Position.Z
	local thr = 1.2
	if F.Human then
		-- slightly off-center (max 0.3 stud), still far from the cell edge
		tx += (math.random() - 0.5) * 0.6
		tz += (math.random() - 0.5) * 0.6
		if straight then
			thr = 2.2 -- straight path: continue to the next cell without stopping at the center
		end
	end
	local t0 = os.clock()
	while F.Run and not F.abort and os.clock() - t0 < 4 do
		hum:MoveTo(Vector3.new(tx, hrp.Position.Y, tz))
		local dx, dz = hrp.Position.X - tx, hrp.Position.Z - tz
		if math.sqrt(dx * dx + dz * dz) < thr then
			return true
		end
		task.wait(0.03)
	end
	if F.abort then
		stopWalking()
	end
	return false
end

-- walk through opened cells (4 directions) to a neighbor matching pred, then step on it.
-- Always the nearest; route and ties are randomized in Human-like mode.
local function stepToward(B, cur, pred)
	if F.abort then
		return false
	end
	local prev, dist, order = { [cur.key] = false }, { [cur.key] = 0 }, { cur }
	local head = 1
	while head <= #order do
		local c = order[head]
		head += 1
		for _, d in ipairs(dirs()) do
			local n = B.cells[ckey(c.x + d[1], c.z + d[2])]
			if n and prev[n.key] == nil and passable(n) then
				prev[n.key] = c
				dist[n.key] = dist[c.key] + 1
				order[#order + 1] = n
			end
		end
	end
	local cands = {}
	for _, c in ipairs(order) do
		for _, d in ipairs(DIRS) do
			local n = B.cells[ckey(c.x + d[1], c.z + d[2])]
			if n and n.state == "unk" and not n.danger and pred(n) then
				cands[#cands + 1] = { c = c, n = n }
				break
			end
		end
	end
	if #cands == 0 then
		return false
	end
	-- always the nearest route; if several are equally near, pick randomly (human-like mode)
	local best, ties = dist[cands[1].c.key], {}
	for _, cd in ipairs(cands) do
		if dist[cd.c.key] == best then
			ties[#ties + 1] = cd
		end
	end
	local pick = F.Human and ties[math.random(1, #ties)] or ties[1]
	local path, w = {}, pick.c
	while w do
		table.insert(path, 1, w)
		w = prev[w.key]
	end
	for i = 2, #path do
		if not F.Run or F.abort then
			return false
		end
		local c0, p0 = path[i], path[i - 1]
		local nxt = path[i + 1] or pick.n
		local straight = (nxt.x - c0.x == c0.x - p0.x) and (nxt.z - c0.z == c0.z - p0.z)
		if not moveTo(c0, straight) then
			return false
		end
	end
	if not F.Run or F.abort then
		return false
	end
	moveTo(pick.n)
	return true, pick.n
end

-- flag: reuse the arguments learned from the last manual PlaceFlag, only swapping the part
local function getFlagRemote()
	local ok, r = pcall(function()
		return game:GetService("ReplicatedStorage").Events.FlagEvents.PlaceFlag
	end)
	return ok and r or nil
end
local function resetFlags()
	F.failed, F.firedAt, F.firedCount = {}, {}, {}
end
local function cellKeyOf(part)
	return ckey(math.floor(part.Position.X / F.CellSize + 0.5), math.floor(part.Position.Z / F.CellSize + 0.5))
end
-- PlaceFlag toggles/replaces on an already flagged cell, so each cell gets at most 2 fires per game
local function fireFlag(part)
	local remote = getFlagRemote()
	if F.abort or not remote or not flagTemplate then
		return false
	end
	local key = cellKeyOf(part)
	local n = (F.firedCount[key] or 0) + 1
	if n > 2 then
		push(("FLAG skip %s: already fired %d times"):format(key, n - 1))
		return false
	end
	F.firedCount[key], F.firedAt[key] = n, os.clock()
	local a = table.pack(table.unpack(flagTemplate, 1, flagTemplate.n))
	a[1] = part
	push(("[%s] FLAG fire %s (#%d)"):format(os.date("%H:%M:%S"), key, n))
	remote:FireServer(table.unpack(a, 1, a.n))
	return true
end
local function waitFlag(part, t)
	local t0 = os.clock()
	while os.clock() - t0 < t and not F.abort do
		if flagged(part) then
			return true
		end
		task.wait(0.05)
	end
	return false
end
-- like the Manual auto-flag: fire PlaceFlag straight at the tile (no walking, no second shot);
-- a tile that does not show a flag is not tried again until the next game
local function flagCell(B, cell, src)
	if F.abort then
		return false
	end
	if not fireFlag(cell.part) then
		F.failed[cell.key] = true
		return false
	end
	if waitFlag(cell.part, 0.8) then
		return true
	end
	if F.abort then
		return false
	end
	-- maybe the token changed: read it again and, if it differs, shoot once more
	local tk = findFlagToken()
	if tk and tostring(flagTemplate[2]) ~= tk then
		flagTemplate = { n = 3, [2] = tk, [3] = true }
		setLabel(lblTpl, "Flag template: automatic (token ..." .. tk:sub(-4) .. ")")
		push("FLAG token refreshed")
		if fireFlag(cell.part) and waitFlag(cell.part, 0.8) then
			return true
		end
	end
	if not F.abort then
		push(("FLAG not visible on %s, not retried"):format(cell.key))
		F.failed[cell.key] = true
	end
	return false
end

local function guessTarget(B, cons, reduce, mineK)
	local prob, best, bestp = {}, nil, 2
	for _, k in ipairs(cons) do
		local U, rem = reduce(k)
		if #U > 0 and rem > 0 then
			for _, u in ipairs(U) do
				prob[u.key] = math.max(prob[u.key] or 0, rem / #U)
			end
		end
	end
	for key, p in pairs(prob) do
		if p < bestp and not mineK[key] and B.cells[key].state == "unk" then
			bestp, best = p, B.cells[key]
		end
	end
	return best, bestp
end

-- nearest unflagged mine (within range)
local function pickMine(mineK, pos, maxDist)
	local best, bd
	for key, m in pairs(mineK) do
		if not F.failed[key] and not flagged(m.cell.part) then
			local dx, dz = m.cell.part.Position.X - pos.X, m.cell.part.Position.Z - pos.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= maxDist and (not bd or d < bd) then
				best, bd = m, d
			end
		end
	end
	return best
end

-- watchdog: sets F.abort the moment the game ends or restarts (teleport, death, board reset),
-- so every walk/flag in progress stops instead of running on stale data
local function watchdog()
	local lastPos, lastRev, lastCheck
	while F.Run do
		task.wait(0.1)
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or hum.Health <= 0 then
			F.abort = true
			lastPos = nil
		else
			local pos = hrp.Position
			if lastPos and (pos - lastPos).Magnitude > 20 then
				F.abort = true -- teleported (walking is only ~2 studs per 0.1s)
			end
			lastPos = pos
		end
		if not lastCheck or os.clock() - lastCheck > 0.4 then
			lastCheck = os.clock()
			local B = buildBoard()
			if B then
				local n = 0
				for _, c in ipairs(B.list) do
					if revealed(c) then
						n += 1
					end
				end
				if lastRev and n < lastRev then
					F.abort = true -- opened cell count dropped: the board was reset
				end
				lastRev = n
			end
		end
	end
end
local function startWatchdog()
	if F.WatchBusy then
		return
	end
	F.WatchBusy = true
	task.spawn(function()
		watchdog()
		F.WatchBusy = false
	end)
end

local function farmLoop()
	if F.Busy then
		return
	end
	F.Busy = true
	resetFlags()
	local notified, lastRevealed, tplSeen = false, 0, flagTemplate
	local quick = false -- true after stepping: continue without delay
	while F.Run do
		if F.dodging then
			task.wait(0.05)
			continue
		end
		if quick then
			task.wait()
		else
			task.wait(F.Delay * (0.7 + math.random() * 0.6))
		end
		quick = false
		if F.abort then
			F.abort = false -- the watchdog saw the game end/restart: everything in progress already stopped
			stopWalking()
			fstatus("game ended / reset, rescanning")
		end
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or hum.Health <= 0 then
			fstatus("waiting for respawn")
			task.wait(1)
			continue
		end
		local B = buildBoard()
		if not B or #B.list == 0 then
			fstatus("board not found (workspace.Flag.Parts)")
			task.wait(1)
			continue
		end

		-- new game (opened cell count dropped) or new template: reset failed-flag records
		local nRev = 0
		for _, c in ipairs(B.list) do
			if revealed(c) then
				nRev += 1
			end
		end
		if nRev < lastRevealed then
			resetFlags()
			notified = false
		end
		lastRevealed = nRev
		if tplSeen ~= flagTemplate then
			tplSeen = flagTemplate
			resetFlags()
		end

		local cur = curCell(B)
		if not cur or not standable(cur) then
			fstatus("waiting for the game to start / not on an opened block")
			task.wait(1)
			continue
		end

		local mineK, safeK, cons, reduce = solve(B)
		local proven = proveMines and proveMines() or nil -- exhaustive solver: finds mines the basic rules miss
		if proven then
			for key in pairs(proven) do
				local c = B.cells[key]
				if c and c.state == "unk" and not mineK[key] then
					mineK[key] = { cell = c, src = c }
				end
			end
		end
		if F.Flagging and not flagTemplate then
			ensureTemplate()
		end
		local canFlag = F.Flagging and flagTemplate ~= nil
		local acted, stepped = false, false

		-- 1) flag every proven mine within range, nearest first (no walking, like the Manual auto-flag)
		if canFlag then
			for _ = 1, 8 do
				if not F.Run or F.abort then
					break
				end
				local r = char:FindFirstChild("HumanoidRootPart")
				local m = r and pickMine(mineK, r.Position, F.FlagRange)
				if not m then
					break
				end
				fstatus("flagging mine " .. m.cell.key)
				if flagCell(B, m.cell, m.src) then
					acted = true
				elseif not F.abort then
					fstatus("flag failed (outdated template? place 1 flag manually again)")
				end
			end
		end

		-- 2) walk to the nearest safe block
		cur = curCell(B)
		if F.Run and not F.abort and cur and standable(cur) and next(safeK) then
			fstatus("walking to a safe block")
			local okStep, tgt = stepToward(B, cur, function(n)
				return safeK[n.key] ~= nil
			end)
			if okStep then
				stepped, acted, quick = true, true, true
				waitRevealed(tgt)
			end
		end

		if F.abort then
			continue
		end

		if F.Run and not acted then
			cur = curCell(B)
			if F.Guess and cur and standable(cur) then
				local g, p = guessTarget(B, cons, reduce, mineK)
				if g then
					fstatus(("guessing %s (risk ~%d%%)"):format(g.key, math.floor(p * 100)))
					local okG, tg = stepToward(B, cur, function(n)
						return n == g
					end)
					if okG then
						waitRevealed(tg)
						quick = true
					end
					acted = true
				end
			end
			if not acted then
				fstatus(flagTemplate and "stuck / done: no certain move" or "stuck (no flag template yet)")
				if not notified then
					notified = true
					UI.CreateNoti({ Title = "Auto Farm", Desc = "No certain move. Waiting for the next game.", ShowTime = 4 })
				end
				task.wait(1)
			end
		else
			notified = false
		end
	end
	F.Busy = false
	fstatus("off")
end

-- print the board as the script reads it: # unopened, F flag, . empty, number
local function dumpBoard()
	local B = buildBoard()
	if not B or #B.list == 0 then
		push("BOARD not found (workspace.Flag.Parts)")
		return
	end
	local minx, maxx, minz, maxz = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs(B.list) do
		minx, maxx = math.min(minx, c.x), math.max(maxx, c.x)
		minz, maxz = math.min(minz, c.z), math.max(maxz, c.z)
	end
	push(("[%s] BOARD %d cell | x %d..%d | z %d..%d | legend: # unopened, F flag, P flag pending, . empty, number, ? unreadable number"):format(
		os.date("%H:%M:%S"), #B.list, minx, maxx, minz, maxz
	))
	for z = minz, maxz do
		local row = {}
		for x = minx, maxx do
			local c = B.cells[ckey(x, z)]
			local ch = " "
			if c then
				if c.state == "flag" then
					ch = "F"
				elseif c.state == "pending" then
					ch = "P"
				elseif c.state == "unk" then
					ch = "#"
				elseif c.state == "zero" then
					ch = "."
				else
					ch = c.n and (c.n == 0 and "." or tostring(c.n)) or "?"
				end
			end
			row[#row + 1] = ch
		end
		push(table.concat(row))
	end
	local stats = {}
	for _, c in ipairs(B.list) do
		local col = c.part.Color
		local k = ("%s color %.3f,%.3f,%.3f"):format(c.state, col.R, col.G, col.B)
		stats[k] = (stats[k] or 0) + 1
	end
	for k, v in pairs(stats) do
		push(("  %s x%d"):format(k, v))
	end
	local shown = 0
	for _, c in ipairs(B.list) do
		local gui = c.state == "num" and c.part:FindFirstChild("NumberGui")
		if gui and shown < 2 then
			shown += 1
			for _, d in ipairs(gui:GetDescendants()) do
				push(("  NumberGui %s: %s [%s] text=%s"):format(c.key, path(d), d.ClassName, d:IsA("TextLabel") and d.Text or "-"))
			end
		end
	end
	push("  flag template: " .. (flagTemplate and ser(flagTemplate[1]) .. " ... (ready)" or "none"))
end

---------------------------------------------------------------- EVENT VOTES (auto "Yes")
local okV, VIM = pcall(function()
	return game:GetService("VirtualInputManager")
end)
if not okV then
	VIM = nil
end
local GuiService = game:GetService("GuiService")
local PlayerGui = LP:WaitForChild("PlayerGui")
local lblEvent = nil

local function trim(t)
	return (tostring(t):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- cache of "Yes" buttons (TextButton, or a TextLabel inside a GuiButton), kept up to date by events
local yesBtns = {}
local YES_TEXT = { yes = true, join = true, accept = true }
local function yesTarget(d)
	if d:IsA("TextButton") and YES_TEXT[trim(d.Text):lower()] then
		return d
	end
	if d:IsA("TextLabel") and YES_TEXT[trim(d.Text):lower()] then
		local p = d.Parent
		if p and p:IsA("GuiButton") then
			return p
		end
	end
	return nil
end
local function consider(d)
	local b = yesTarget(d)
	if b then
		yesBtns[b] = true
	end
end
local function onGuiAdded(d)
	consider(d)
	if d:IsA("TextButton") or d:IsA("TextLabel") then
		d:GetPropertyChangedSignal("Text"):Connect(function()
			consider(d)
		end)
	end
end
for _, d in ipairs(PlayerGui:GetDescendants()) do
	onGuiAdded(d)
end
PlayerGui.DescendantAdded:Connect(function(d)
	task.defer(onGuiAdded, d)
end)

-- really visible on screen (every ancestor visible/enabled, non-zero size)
local function shown(g)
	local node = g
	while node and node ~= game do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") and not node.Enabled then
			return false
		end
		node = node.Parent
	end
	return g:IsDescendantOf(PlayerGui) and g.AbsoluteSize.X > 0 and g.AbsoluteSize.Y > 0
end

-- visible text of the prompt that holds this Yes button: the highest ancestor that contains only this Yes button
local function promptText(btn)
	local top, node = btn.Parent, btn.Parent
	while node and node:IsA("GuiObject") do
		local count = 0
		for _, d in ipairs(node:GetDescendants()) do
			if yesTarget(d) then
				count += 1
			end
		end
		if count > 1 then
			break
		end
		top, node = node, node.Parent
	end
	local t = {}
	if top then
		for _, d in ipairs(top:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and shown(d) then
				t[#t + 1] = d.Text
			end
		end
	end
	return table.concat(t, " "):lower()
end

local function signalClick(btn)
	if firesignal then
		pcall(firesignal, btn.MouseButton1Click)
		pcall(firesignal, btn.Activated)
	elseif getconnections then
		pcall(function()
			for _, c in ipairs(getconnections(btn.MouseButton1Click)) do
				c:Fire()
			end
		end)
		pcall(function()
			for _, c in ipairs(getconnections(btn.Activated)) do
				c:Fire()
			end
		end)
	end
end

local function realClick(btn)
	if not VIM then
		return
	end
	local p, s = btn.AbsolutePosition, btn.AbsoluteSize
	local x, y = p.X + s.X / 2, p.Y + s.Y / 2
	local sg = btn:FindFirstAncestorOfClass("ScreenGui")
	if sg and not sg.IgnoreGuiInset then
		y += GuiService:GetGuiInset().Y
	end
	pcall(function()
		VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
		task.wait(0.03)
		VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
	end)
end

-- "x/y votes required." -> x, y
local function voteCount(txt)
	local a, b = txt:match("(%d+)%s*/%s*(%d+)%s*votes")
	return tonumber(a), tonumber(b)
end

-- press Yes: signal and real click alternate every 0.05s until the prompt closes, the vote is full,
-- or "You can't back out now." shows up
local function pressYes(btn, kind)
	local hasSignal = (firesignal or getconnections) ~= nil
	local startCur
	for i = 1, 8 do
		if not btn.Parent or not shown(btn) then
			return true
		end
		local txt = promptText(btn)
		if txt:find("back out", 1, true) then
			return true
		end
		local cur, req = voteCount(txt)
		if i == 1 then
			startCur = cur
		end
		if cur and req and cur >= req then
			return true
		end
		if i >= 3 and cur and startCur and cur > startCur then
			return true -- the count went up after a signal and a real click: the vote is in
		end
		local viaSignal = hasSignal and i % 2 == 1
		local p, s = btn.AbsolutePosition, btn.AbsoluteSize
		push(("  %s attempt %d via %s | pos %.0f,%.0f size %.0f,%.0f | votes %s/%s"):format(
			kind, i, viaSignal and "signal" or "real click", p.X, p.Y, s.X, s.Y, tostring(cur), tostring(req)
		))
		if viaSignal then
			signalClick(btn)
		else
			realClick(btn)
		end
		task.wait(0.05)
	end
	return false
end

local function promptMatches(txt)
	if txt == "" or txt:find("kick", 1, true) then
		return false -- never vote on a votekick prompt
	end
	local ek = F.EventKw:lower()
	return ek ~= "" and txt:find(ek, 1, true) ~= nil
end

local seenAt = {} -- btn -> time the matching prompt was first seen
local done = {} -- btn -> true once the vote went through (reset when the prompt hides or restarts at 0)

-- Auto join event: presses "Yes" when the event round vote is on screen
local function eventLoop(interval)
	while F.AutoEvent do
		for btn in pairs(yesBtns) do
			if not btn.Parent then
				yesBtns[btn], seenAt[btn], done[btn] = nil, nil, nil
			elseif shown(btn) then
				local txt = promptText(btn)
				if done[btn] and voteCount(txt) == 0 then
					done[btn] = nil -- a new vote started on the same prompt
				end
				if promptMatches(txt) and not txt:find("back out", 1, true) and not done[btn] then
					if not seenAt[btn] then
						seenAt[btn] = os.clock()
						push(("[%s] VOTE event prompt seen: %q"):format(os.date("%H:%M:%S"), txt:sub(1, 100)))
					end
					if not F.pressing then
						F.pressing = true
						local ok = pressYes(btn, "event")
						F.pressing = false
						if ok then
							done[btn] = true
						end
						push(("[%s] VOTE event %s after %.2fs"):format(os.date("%H:%M:%S"), ok and "sent" or "still trying", os.clock() - seenAt[btn]))
						setLabel(lblEvent, "Event: " .. (ok and "vote sent" or "still trying"))
					end
				end
			else
				seenAt[btn], done[btn] = nil, nil
			end
		end
		task.wait(interval)
	end
end

-- Auto join secret event: spams the event vote's Yes button all the time, even while it is hidden,
-- so the vote is already pressed the moment it opens. Votekick buttons are never touched.
local function isVoteYes(btn)
	local ok, nm = pcall(path, btn)
	nm = ok and nm:lower() or ""
	return nm:find("vote", 1, true) ~= nil and nm:find("kick", 1, true) == nil
end
local function secretLoop()
	while F.AutoSecret do
		for btn in pairs(yesBtns) do
			if not btn.Parent then
				yesBtns[btn], seenAt[btn], done[btn] = nil, nil, nil
			elseif isVoteYes(btn) then
				if shown(btn) then
					local txt = promptText(btn)
					if not txt:find("kick", 1, true) and not txt:find("back out", 1, true) and not done[btn] and not F.pressing then
						if not seenAt[btn] then
							seenAt[btn] = os.clock()
							push(("[%s] VOTE secret: button visible, pressing"):format(os.date("%H:%M:%S")))
						end
						F.pressing = true
						local ok = pressYes(btn, "secret")
						F.pressing = false
						if ok then
							done[btn] = true
							push(("[%s] VOTE secret sent after %.2fs"):format(os.date("%H:%M:%S"), os.clock() - seenAt[btn]))
							setLabel(lblEvent, "Event: secret vote sent")
						end
					end
				else
					seenAt[btn], done[btn] = nil, nil
					signalClick(btn) -- hidden: spam only the click signal (no real click on the screen)
				end
			end
		end
		task.wait(0.03)
	end
end

local function connCount(sig)
	if not getconnections then
		return "n/a"
	end
	local ok, c = pcall(getconnections, sig)
	return ok and tostring(#c) or "err"
end

local function dumpVotes()
	local n = 0
	for btn in pairs(yesBtns) do
		n += 1
		local par = btn.Parent
		local parentClick = par and par:IsA("GuiButton") and connCount(par.MouseButton1Click) or "-"
		push(("VOTE yes-button %s | shown=%s | click=%s activated=%s parentClick=%s | prompt=%q"):format(
			path(btn), tostring(btn.Parent ~= nil and shown(btn)), connCount(btn.MouseButton1Click),
			connCount(btn.Activated), parentClick, promptText(btn):sub(1, 140)
		))
	end
	push(("VOTE total yes-buttons: %d"):format(n))
end

---------------------------------------------------------------- DODGE SPIKE
-- Timing measured from gameplay videos: red warning appears -> spikes come out ~1.15s later (the red is only
-- visible ~0.5s), and the spikes stay ~0.6s. Spikes sit on board cells: each cell part has "Warn" and "Slash"
-- sounds. A "wave" starts when a Warn sound starts. For each wave the bot, if YOUR cell is hazardous:
--   * steps to the nearest safe opened/flagged cell (if it is within "max steps" and the area is not crowded), or
--   * jumps so that it is already in the air when the spikes come out (and jumps again if it lands on them).
local lblSpike = nil
local cellIndex, cellIndexAt = {}, -math.huge

local function refreshIndex()
	if os.clock() - cellIndexAt < 2 then
		return
	end
	cellIndexAt = os.clock()
	syncCellSize()
	local f = workspace:FindFirstChild("Flag")
	local parts = f and f:FindFirstChild("Parts")
	local list = {}
	if parts then
		for _, p in ipairs(parts:GetChildren()) do
			if p:IsA("BasePart") then
				local pos = p.Position
				list[#list + 1] = {
					part = p,
					x = pos.X,
					z = pos.Z,
					key = ckey(math.floor(pos.X / F.CellSize + 0.5), math.floor(pos.Z / F.CellSize + 0.5)),
				}
			end
		end
	end
	cellIndex = list
end

-- hazardous cells near pos: set of cell keys, how many are inside the area radius,
-- when the freshest Warn sound started (os.clock time), and whether any cell is red
local function scanHazards(pos)
	local warnName = F.SpikeName ~= "" and F.SpikeName or "Warn"
	local slashName = F.SpikeSound ~= "" and F.SpikeSound or "Slash"
	local reach2, area2 = (F.SpikeRadius + 4) ^ 2, F.SpikeRadius ^ 2
	local danger, count, freshStart = {}, 0, nil
	local now = os.clock()
	for _, e in ipairs(cellIndex) do
		local dx, dz = e.x - pos.X, e.z - pos.Z
		local d2 = dx * dx + dz * dz
		if d2 <= reach2 then
			local p = e.part
			local w, sl = p:FindFirstChild(warnName), p:FindFirstChild(slashName)
			local warning = w ~= nil and w:IsA("Sound") and w.IsPlaying
			local slashing = sl ~= nil and sl:IsA("Sound") and sl.IsPlaying
			if warning or slashing then
				danger[e.key] = true
				if d2 <= area2 then
					count += 1
				end
			end
			if warning and w.TimePosition < 0.4 then
				local started = now - w.TimePosition
				if not freshStart or started < freshStart then
					freshStart = started
				end
			end
		end
	end
	return danger, count, freshStart
end

local function jump(reason)
	if os.clock() - F.lastJump < 0.45 then
		return
	end
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		F.lastJump = os.clock()
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end)
		hum.Jump = true
		push(("[%s] SPIKE jump (%s)"):format(os.date("%H:%M:%S"), reason))
	end
end

-- only the cells around the avatar, classified like the board (fast: no full board scan)
local function nearBoard(pos, radius, danger)
	local B = { cells = {}, list = {} }
	local r2 = radius * radius
	for _, e in ipairs(cellIndex) do
		local dx, dz = e.x - pos.X, e.z - pos.Z
		if dx * dx + dz * dz <= r2 then
			local c = makeCell(e.part)
			if danger[c.key] then
				c.danger = true
			end
			B.cells[c.key] = c
			B.list[#B.list + 1] = c
		end
	end
	return B
end

-- nearest cell (through opened/flagged cells) that is not hazardous
local function escapePath(B, from)
	local prev, order = { [from.key] = false }, { from }
	local head = 1
	while head <= #order do
		local c = order[head]
		head += 1
		if c ~= from and not c.danger then
			local p, w = {}, c
			while w do
				table.insert(p, 1, w)
				w = prev[w.key]
			end
			return p
		end
		for _, d in ipairs(DIRS) do
			local n = B.cells[ckey(c.x + d[1], c.z + d[2])]
			if n and prev[n.key] == nil and standable(n) then
				prev[n.key] = c
				order[#order + 1] = n
			end
		end
	end
	return nil
end

-- walk the escape path without stopping at every cell center (straight stretches switch waypoint early)
local function dodgeRun(path2)
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then
		return
	end
	for i = 2, #path2 do
		local c0, p0, nxt = path2[i], path2[i - 1], path2[i + 1]
		local straight = nxt ~= nil and (nxt.x - c0.x == c0.x - p0.x) and (nxt.z - c0.z == c0.z - p0.z)
		local thr = straight and 2.2 or 1.3
		local tx, tz = c0.part.Position.X, c0.part.Position.Z
		local t0 = os.clock()
		while F.Dodge and os.clock() - t0 < 1.0 do
			hum:MoveTo(Vector3.new(tx, hrp.Position.Y, tz))
			local dx, dz = hrp.Position.X - tx, hrp.Position.Z - tz
			if math.sqrt(dx * dx + dz * dz) < thr then
				break
			end
			task.wait()
		end
	end
end

local function dodgeLoop()
	if F.DodgeBusy then
		return
	end
	F.DodgeBusy = true
	local wave, lastText = nil, ""
	while F.Dodge do
		task.wait()
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or hum.Health <= 0 then
			F.dangerKeys, wave = {}, nil
			continue
		end
		refreshIndex()
		local pos = hrp.Position
		local now = os.clock()
		local danger, count, freshStart = scanHazards(pos)
		F.dangerKeys = danger -- buildBoard marks these cells as danger (farm routes avoid them)

		-- a new wave: a Warn sound just started (or, without sounds, red cells showed up)
		if freshStart then
			if not wave or freshStart - wave.start > 0.8 then
				wave = { start = freshStart, seen = now, handled = false, rejumps = 0 }
			end
		end

		local ownKey = ckey(math.floor(pos.X / F.CellSize + 0.5), math.floor(pos.Z / F.CellSize + 0.5))
		local underMe = danger[ownKey] == true
		local text = ("Spikes: %d cells in area%s"):format(count, underMe and " (your cell!)" or "")
		if text ~= lastText then
			lastText = text
			setLabel(lblSpike, text)
		end

		if wave and not wave.handled and now - wave.seen >= 0.06 then
			wave.handled = true
			wave.spikeAt = wave.start + F.SpikeEta
			if underMe then
				local B = nearBoard(pos, 22, danger)
				local cur = B.cells[ownKey]
				local crowded = count >= F.SpikeCount
				local path2 = (F.DodgeMove and not crowded and cur and standable(cur)) and escapePath(B, cur) or nil
				if path2 and #path2 - 1 <= F.SpikeMaxSteps then
					F.dodging, F.abort = true, true -- pause the farm loop while we move
					push(("[%s] SPIKE dodge: %s -> %s (%.2fs before spikes)"):format(
						os.date("%H:%M:%S"), cur.key, path2[#path2].key, wave.spikeAt - now
					))
					dodgeRun(path2)
					stopWalking()
					F.dodging = false
				elseif F.DodgeJump then
					wave.jumpAt = wave.spikeAt - F.SpikeLead
					push(("[%s] SPIKE %s: jump in %.2fs (spikes in %.2fs)"):format(
						os.date("%H:%M:%S"), crowded and "crowded" or "no safe cell close", math.max(0, wave.jumpAt - now), wave.spikeAt - now
					))
				end
			end
		end

		-- planned jump, and a second jump if we land while the spikes are still out
		if wave and wave.jumpAt then
			if now >= wave.jumpAt and not wave.jumped then
				wave.jumped = true
				jump("airborne when the spikes come out")
			elseif wave.jumped and underMe and wave.rejumps < 2 and now < wave.spikeAt + 0.7
				and hum.FloorMaterial ~= Enum.Material.Air then
				wave.rejumps += 1
				jump("landed on spikes, jump again")
			end
		end
	end
	F.dangerKeys = {}
	F.DodgeBusy = false
end

local function dumpSpikes()
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		push("SPIKES: no character")
		return
	end
	cellIndexAt = -math.huge
	refreshIndex()
	local pos = hrp.Position
	local danger, count, freshStart = scanHazards(pos)
	local ownKey = ckey(math.floor(pos.X / F.CellSize + 0.5), math.floor(pos.Z / F.CellSize + 0.5))
	local n = 0
	for _ in pairs(danger) do
		n += 1
	end
	push(("[%s] SPIKES: %d hazardous cells near (%d in area radius), your cell %s%s, fresh warn %s"):format(
		os.date("%H:%M:%S"), n, count, ownKey, danger[ownKey] and " IS HAZARDOUS" or "",
		freshStart and ("%.2fs ago"):format(os.clock() - freshStart) or "none"
	))
	local shown = 0
	for key in pairs(danger) do
		shown += 1
		if shown > 40 then
			break
		end
		push("  hazard cell " .. key)
	end
	for _, e in ipairs(cellIndex) do
		if e.key == ownKey then
			push("  children of your cell " .. path(e.part) .. ":")
			for _, c in ipairs(e.part:GetChildren()) do
				push(("    %s <%s>%s"):format(c.Name, c.ClassName, c:IsA("Sound") and (" playing=" .. tostring(c.IsPlaying)) or ""))
			end
			break
		end
	end
end

---------------------------------------------------------------- MANUAL (solver ESP + auto-flag)
-- Ported from the open-source bLockerman's Minesweeper solver (scriptblox) and adapted to this UI.
-- Exact deductions first, then exhaustive enumeration of every frontier group to get mine probabilities.
local Teams = game:GetService("Teams")
local startManual, stopManual, resetManualToken
local lblMBoard, lblMNext, lblMFlag

do
	local function solveClues(clues)
		local known = {}
		local changed = true
		while changed do
			changed = false
			local residuals, byTile = {}, {}
			for _, clue in ipairs(clues) do
				local need, remaining = clue.count, {}
				for _, id in ipairs(clue.ids) do
					if known[id] == nil then
						remaining[id] = true
					else
						need -= known[id]
					end
				end
				local count = 0
				for _ in pairs(remaining) do
					count += 1
				end
				if need < 0 or need > count then
					return {}, false
				end
				if count > 0 and (need == 0 or need == count) then
					local value = if need == 0 then 0 else 1
					for id in pairs(remaining) do
						known[id] = value
					end
					changed = true
				elseif count > 0 then
					local residual = { ids = remaining, count = count, need = need }
					table.insert(residuals, residual)
					for id in pairs(remaining) do
						byTile[id] = byTile[id] or {}
						table.insert(byTile[id], residual)
					end
				end
			end

			if not changed then
				for _, small in ipairs(residuals) do
					local first = next(small.ids)
					for _, large in ipairs(byTile[first]) do
						if small == large or small.count > large.count then
							continue
						end
						local subset = true
						for id in pairs(small.ids) do
							if not large.ids[id] then
								subset = false
								break
							end
						end
						if not subset then
							continue
						end
						local need = large.need - small.need
						local extra = large.count - small.count
						if need < 0 or need > extra then
							return {}, false
						end
						if extra > 0 and (need == 0 or need == extra) then
							for id in pairs(large.ids) do
								if not small.ids[id] then
									known[id] = if need == 0 then 0 else 1
								end
							end
							changed = true
							break
						end
					end
					if changed then
						break
					end
				end
			end
		end

		local frontier = {}
		for _, clue in ipairs(clues) do
			local edge = { ids = {}, need = clue.count, used = 0, left = 0 }
			for _, id in ipairs(clue.ids) do
				if known[id] == nil then
					table.insert(edge.ids, id)
					frontier[id] = frontier[id] or {}
					table.insert(frontier[id], edge)
				else
					edge.need -= known[id]
				end
			end
			edge.left = #edge.ids
		end

		local visited, budget = {}, 180000
		local stopAt = os.clock() + 0.035
		for first in pairs(frontier) do
			if visited[first] then
				continue
			end
			local ids, seenEdges = { first }, {}
			visited[first] = true
			local cursor = 1
			while cursor <= #ids do
				for _, edge in ipairs(frontier[ids[cursor]]) do
					if seenEdges[edge] then
						continue
					end
					seenEdges[edge] = true
					for _, id in ipairs(edge.ids) do
						if not visited[id] then
							visited[id] = true
							table.insert(ids, id)
						end
					end
				end
				cursor += 1
			end
			if #ids > 64 or budget <= 0 or os.clock() >= stopAt then
				continue
			end

			local linked, used = {}, {}
			local ordered = {}
			for _ = 1, #ids do
				local best, bestScore
				for _, id in ipairs(ids) do
					if used[id] then
						continue
					end
					local score = (linked[id] or 0) * 100 + #frontier[id]
					if not bestScore or score > bestScore then
						best, bestScore = id, score
					end
				end
				used[best] = true
				table.insert(ordered, best)
				for _, edge in ipairs(frontier[best]) do
					for _, id in ipairs(edge.ids) do
						if not used[id] then
							linked[id] = (linked[id] or 0) + 1
						end
					end
				end
			end
			ids = ordered
			local assignments, mineCounts, solutions = {}, {}, 0
			local componentBudget = math.min(70000, budget)
			local function enumerate(index)
				if componentBudget <= 0 or (componentBudget % 256 == 0 and os.clock() >= stopAt) then
					return false
				end
				budget -= 1
				componentBudget -= 1
				if index > #ids then
					solutions += 1
					for i, value in ipairs(assignments) do
						mineCounts[i] = (mineCounts[i] or 0) + value
					end
					return true
				end
				local adjacent = frontier[ids[index]]
				for value = 0, 1 do
					local valid = true
					for _, edge in ipairs(adjacent) do
						edge.left -= 1
						edge.used += value
						if edge.used > edge.need or edge.used + edge.left < edge.need then
							valid = false
						end
					end
					local complete = true
					if valid then
						assignments[index] = value
						complete = enumerate(index + 1)
					end
					for _, edge in ipairs(adjacent) do
						edge.left += 1
						edge.used -= value
					end
					if not complete then
						return false
					end
				end
				return true
			end
			if not enumerate(1) then
				continue
			end
			if solutions == 0 then
				return {}, false
			end
			for i, id in ipairs(ids) do
				known[id] = (mineCounts[i] or 0) / solutions
			end
		end
		return known, true
	end

	local M = { alive = false, flagsPlaced = 0, markers = {} }
	local colors = {
		safe = Color3.fromRGB(64, 236, 117),
		bomb = Color3.fromRGB(255, 70, 85),
		half = Color3.fromRGB(255, 208, 66),
		suggest = Color3.fromRGB(79, 180, 255),
	}
	local lastText = { "", "", "" }
	local function put(i, lbl, text)
		if lastText[i] ~= text then
			lastText[i] = text
			setLabel(lbl, text)
		end
	end

	-- one tile: its clue number (0..8) or nil when unopened/flagged, and whether it carries a flag
	local function readTile(part)
		local gui = part:FindFirstChild("NumberGui")
		if not gui then
			return nil, part:FindFirstChildWhichIsA("Model") ~= nil
		end
		local label = gui:FindFirstChild("TextLabel")
		if not label or not label:IsA("TextLabel") then
			return nil, true
		end
		local value = label.Text
		if value == "X" then
			return nil, true
		end
		if value == "" then
			return 0, false
		end
		local clue = tonumber(value)
		if clue and clue >= 0 and clue <= 8 and clue % 1 == 0 then
			return clue, false
		end
		return nil, true
	end

	local function tileId(x, z)
		return tostring(x) .. "," .. tostring(z)
	end

	local function readBoard(parts)
		local tiles, occupied = {}, 0
		for _, part in ipairs(parts:GetChildren()) do
			if not part:IsA("BasePart") then
				continue
			end
			local x = math.round(part.Position.X / part.Size.X)
			local z = math.round(part.Position.Z / part.Size.Z)
			local number, flagged2 = readTile(part)
			tiles[tileId(x, z)] = { part = part, x = x, z = z, number = number, flagged = flagged2 }
			occupied += 1
		end
		return tiles, occupied
	end

	local cachedTiles, cachedCount, cachedParts, cachedMarks, cachedValid, cachedClueCount

	local function solveBoard(parts, tiles, occupied)
		local unchanged = cachedParts == parts and cachedCount == occupied
		if unchanged then
			for id, tile in pairs(tiles) do
				local old = cachedTiles[id]
				if not old or old.part ~= tile.part or old.number ~= tile.number then
					unchanged = false
					break
				end
			end
		end
		if unchanged then
			return cachedMarks, cachedValid, cachedClueCount
		end
		local clues = {}
		for _, tile in pairs(tiles) do
			if tile.number == nil then
				continue
			end
			local ids = {}
			for dx = -1, 1 do
				for dz = -1, 1 do
					local id = tileId(tile.x + dx, tile.z + dz)
					local neighbor = tiles[id]
					if neighbor and neighbor.number == nil then
						table.insert(ids, id)
					end
				end
			end
			table.insert(clues, { ids = ids, count = tile.number })
		end
		local marks, valid = solveClues(clues)
		cachedParts, cachedTiles, cachedCount = parts, tiles, occupied
		cachedMarks, cachedValid, cachedClueCount = marks, valid, #clues
		return marks, valid, #clues
	end

	-- the flag token comes straight from the game (see findFlagToken)
	local requestArgument
	local nextLookup = 0
	local function getFlagArgument()
		if requestArgument then
			return requestArgument
		end
		if os.clock() < nextLookup then
			return nil
		end
		nextLookup = os.clock() + 5
		requestArgument = findFlagToken()
		return requestArgument
	end
	resetManualToken = function()
		requestArgument, nextLookup = nil, 0
	end

	-- used by Auto Farm: unopened, unflagged tiles the exhaustive solver proves to be mines
	proveMines = function()
		local board = workspace:FindFirstChild("Flag")
		local parts = board and board:FindFirstChild("Parts")
		if not parts then
			return nil
		end
		local tiles, count = readBoard(parts)
		local marks, valid = solveBoard(parts, tiles, count)
		if not valid then
			return nil
		end
		local out = {}
		for id, tile in pairs(tiles) do
			if tile.number == nil and not tile.flagged and marks[id] == 1 then
				out[id] = tile.part
			end
		end
		return out
	end

	local attempts = setmetatable({}, { __mode = "k" })
	local pending
	local lastFlagAt = -math.huge

	local function showMarker(tile, key, active)
		local part = tile.part
		local marker = M.markers[part]
		if not marker then
			marker = Instance.new("BoxHandleAdornment")
			marker.Adornee = part
			marker.Size = Vector3.new(part.Size.X * 0.92, 0.08, part.Size.Z * 0.92)
			marker.CFrame = CFrame.new(0, part.Size.Y / 2 + 0.08, 0)
			marker.ZIndex = 3
			marker.AlwaysOnTop = true
			marker.Parent = M.overlay
			M.markers[part] = marker
		end
		marker.Color3 = colors[key]
		marker.Transparency = if key == "safe" and tile.flagged then 0.18 else 0.38
		active[part] = true
	end

	local function update()
		local board = workspace:FindFirstChild("Flag")
		local parts = board and board:FindFirstChild("Parts")
		if not parts then
			for _, marker in pairs(M.markers) do
				marker:Destroy()
			end
			table.clear(M.markers)
			M.route.Enabled = false
			put(1, lblMBoard, "Waiting for the board")
			return
		end
		local tiles, count = readBoard(parts)
		local marks, valid, clueCount = solveBoard(parts, tiles, count)
		local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
		local info = ReplicatedStorage:FindFirstChild("Info")
		local flagless = info and info:FindFirstChild("Flagless")
		local playing = LP.Team ~= nil and LP.Team == Teams:FindFirstChild("Playing")
		local eligible = playing and root and not (flagless and flagless:IsA("BoolValue") and flagless.Value)
		local now = os.clock()
		local counts = { safe = 0, bomb = 0, half = 0 }
		local active = {}
		local candidate, bestDistance

		if pending then
			local _, isFlagged = readTile(pending.part)
			if pending.part.Parent == parts and isFlagged then
				M.flagsPlaced += 1
				pending = nil
			elseif pending.part.Parent ~= parts or now >= pending.deadline then
				pending = nil
			end
		end
		local openableSafe, flaggedSafe = 0, 0
		local guess, guessRisk, guessDistance
		local nearestSafe, safeDistance, nearestFlaggedSafe, flaggedSafeDistance
		local position = root and root.Position or (workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position)

		for id, tile in pairs(tiles) do
			if tile.number ~= nil then
				continue
			end
			local risk = marks[id]
			local key = if risk == 0 then "safe" elseif risk == 1 then "bomb" elseif risk == 0.5 then "half" else nil
			if key then
				counts[key] += 1
			end
			if key == "safe" then
				local distance = position and (position - tile.part.Position).Magnitude
				if tile.flagged then
					flaggedSafe += 1
					if distance and (not flaggedSafeDistance or distance < flaggedSafeDistance) then
						nearestFlaggedSafe, flaggedSafeDistance = tile, distance
					end
				else
					openableSafe += 1
					if distance and (not safeDistance or distance < safeDistance) then
						nearestSafe, safeDistance = tile, distance
					end
				end
			end
			local show = (key == "safe" and F.ManualSafe) or (key == "bomb" and F.ManualBomb) or (key == "half" and F.ManualHalf)
			if key and show and (not tile.flagged or key == "safe") then
				showMarker(tile, key, active)
			end
			if tile.flagged or not position then
				continue
			end

			local distance = (position - tile.part.Position).Magnitude
			if key == "bomb" and eligible and not attempts[tile.part] then
				if distance <= F.ManualRadius and (not bestDistance or distance < bestDistance) then
					candidate, bestDistance = tile.part, distance
				end
			elseif risk ~= 0 and risk ~= 1 and F.ManualSuggest and valid and clueCount > 0 then
				local score = risk or math.huge
				local bestScore = guessRisk or math.huge
				if not guess or score < bestScore or (score == bestScore and distance < guessDistance) then
					guess, guessRisk, guessDistance = tile, risk, distance
				end
			end
		end

		local nextMove = ""
		local routeTile, routeText, routeColor
		if valid and count == 0 then
			nextMove = "Waiting for tiles"
		elseif valid and clueCount == 0 then
			nextMove = "Open a tile to start solving"
		elseif valid and nearestSafe and F.ManualSafe then
			routeTile, routeText, routeColor = nearestSafe, "SAFE", colors.safe
			nextMove = ("Nearest safe tile: %.0f studs"):format(safeDistance)
		elseif valid and openableSafe == 0 then
			if flaggedSafe > 0 then
				if nearestFlaggedSafe and F.ManualSafe then
					routeTile, routeText, routeColor = nearestFlaggedSafe, "UNFLAG", colors.safe
				end
				nextMove = ("Unflag a green tile (%d flagged)"):format(flaggedSafe)
			elseif guess then
				showMarker(guess, "suggest", active)
				routeTile, routeText, routeColor = guess, "GUESS", colors.suggest
				nextMove = if guessRisk then ("Blue guess: %.0f%% mine risk"):format(guessRisk * 100) else "Blue guess: risk unknown"
			else
				nextMove = "No proven safe move"
			end
		end
		M.route.Enabled = routeTile ~= nil
		M.route.Adornee = routeTile and routeTile.part or nil
		if routeTile then
			M.routeLabel.Text = routeText
			M.routeLabel.TextColor3 = routeColor
		end
		for part, marker in pairs(M.markers) do
			if not active[part] then
				marker:Destroy()
				M.markers[part] = nil
			end
		end

		local flagStatus = "off"
		local placeFlag = ReplicatedStorage:FindFirstChild("Events")
		placeFlag = placeFlag and placeFlag:FindFirstChild("FlagEvents")
		placeFlag = placeFlag and placeFlag:FindFirstChild("PlaceFlag")
		if F.ManualAuto then
			if F.Run then
				flagStatus = "paused (Auto Farm is on, it flags by itself)"
			elseif not eligible then
				flagStatus = "waiting until you are playing"
			elseif not placeFlag or not placeFlag:IsA("RemoteEvent") or not getFlagArgument() then
				flagStatus = "flag control unavailable (needs filtergc)"
			else
				flagStatus = ("%d placed | %d studs | %d ms"):format(M.flagsPlaced, F.ManualRadius, F.ManualDelay)
				if candidate and not pending and now - lastFlagAt >= F.ManualDelay / 1000 then
					local number, isFlagged = readTile(candidate)
					if candidate.Parent == parts and number == nil and not isFlagged then
						attempts[candidate] = true
						lastFlagAt = now
						pending = { part = candidate, deadline = now + 1.5 }
						placeFlag:FireServer(candidate, requestArgument, true)
					end
				end
			end
		end
		put(1, lblMBoard, ("%d safe | %d mines | %d at 50/50"):format(counts.safe, counts.bomb, counts.half))
		put(2, lblMNext, valid and nextMove or "Waiting for consistent clues")
		put(3, lblMFlag, "Auto-flag: " .. flagStatus)
	end

	startManual = function()
		if M.alive then
			return
		end
		M.alive = true
		M.overlay = Instance.new("Folder")
		M.overlay.Name = "LevianMarkers"
		M.overlay.Parent = workspace
		M.route = Instance.new("BillboardGui")
		M.route.Name = "NextTile"
		M.route.Size = UDim2.fromOffset(100, 28)
		M.route.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
		M.route.AlwaysOnTop = true
		M.route.Enabled = false
		M.route.Parent = M.overlay
		M.routeLabel = Instance.new("TextLabel")
		M.routeLabel.Size = UDim2.fromScale(1, 1)
		M.routeLabel.BackgroundColor3 = Color3.fromRGB(16, 24, 29)
		M.routeLabel.BackgroundTransparency = 0.15
		M.routeLabel.Font = Enum.Font.GothamBold
		M.routeLabel.TextSize = 13
		M.routeLabel.Parent = M.route
		local overlayAtStart = M.overlay
		task.spawn(function()
			while M.alive and M.overlay == overlayAtStart do
				local ok, err = pcall(update)
				if not ok then
					push("MANUAL error: " .. tostring(err))
				end
				task.wait(F.ManualAuto and 0.05 or 0.4)
			end
		end)
	end

	stopManual = function()
		M.alive = false
		if M.overlay then
			M.overlay:Destroy()
			M.overlay = nil
		end
		M.markers = {}
		pending = nil
		put(1, lblMBoard, "Board: off")
		put(2, lblMNext, "Next: -")
		put(3, lblMFlag, "Auto-flag: off")
	end
end

---------------------------------------------------------------- UI
local Main = UI.CreateMain({ Title = "Levian Hub - Minesweeper" })

-- "About Us": big, centered heading (the library's label has no size option, so restyle it after creation)
local function styleHeading(text)
	pcall(function()
		local host = (gethui and gethui()) or game:GetService("CoreGui")
		local gui = host:FindFirstChild("Levian Hub GUI")
		if not gui then
			return
		end
		for _, d in ipairs(gui:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text == text then
				d.TextSize = 36
				d.Font = Enum.Font.GothamBold
				d.TextXAlignment = Enum.TextXAlignment.Center
				d.TextYAlignment = Enum.TextYAlignment.Center
				d.TextTruncate = Enum.TextTruncate.None
				if d.Parent and d.Parent:IsA("Frame") then
					d.Parent.Size = UDim2.new(1, 0, 0, 64)
				end
				return
			end
		end
	end)
end

local DISCORD_LINK = "https://discord.gg/Mc2YpMT2cF"
local About = Main:CreatePage({ Page_Name = "About Us", Page_Title = "About Us" })
local AS = About.CreateSection("About Us")
AS.CreateLabel("Levian Hub")
styleHeading("Levian Hub")
AS.CreateButton("Copy Link", function()
	if setclipboard then
		setclipboard(DISCORD_LINK)
		UI.CreateNoti({ Title = "Copied", Desc = "Discord link copied to clipboard", ShowTime = 2 })
	else
		UI.CreateNoti({ Title = "Failed", Desc = "Executor has no setclipboard", ShowTime = 3 })
	end
end)

local function copyLog()
	if setclipboard then
		setclipboard(table.concat(logs, "\n"))
		UI.CreateNoti({ Title = "Log copied", Desc = #logs .. " lines", ShowTime = 2 })
	else
		UI.CreateNoti({ Title = "Failed", Desc = "Executor has no setclipboard", ShowTime = 3 })
	end
end

-- every setting control: starts from the saved value and saves on change
local function setting(key)
	return function(v)
		F[key] = v
		saveSettings()
	end
end

---------------------------------------------------------------- page: Auto Farm
local Page = Main:CreatePage({ Page_Name = "Auto Farm", Page_Title = "Auto Farm" })

local FS = Page.CreateSection("Auto Minesweeper")
lblTpl = FS.CreateLabel("Flag template: none yet (found automatically, or place 1 flag manually)")
lblFarm = FS.CreateLabel("Status: off")
FS.CreateToggle({ Title = "Auto Farm", Desc = "Flag mines + walk to safe blocks", Default = false }, function(v)
	F.Run = v
	if v then
		F.abort = false
		startWatchdog()
		task.spawn(farmLoop)
	else
		stopWalking()
	end
end)
FS.CreateDropdown({ Title = "Walking style", List = { "Human-like", "Robot" }, Default = F.Human and "Human-like" or "Robot" }, function(v)
	F.Human = (v == "Human-like")
	saveSettings()
end)
FS.CreateToggle({ Title = "Flag mines", Desc = "Flags proven mines in range, like the Manual auto-flag", Default = F.Flagging }, setting("Flagging"))
FS.CreateSlider({ Title = "Flag range (studs)", Min = 5, Max = 40, Default = F.FlagRange }, setting("FlagRange"))
FS.CreateToggle({ Title = "Walk over flags", Desc = "Walk on flagged blocks for shorter routes", Default = F.PassFlags }, setting("PassFlags"))
FS.CreateToggle({ Title = "Guess when stuck", Desc = "Risk of stepping on a mine", Default = F.Guess }, setting("Guess"))
FS.CreateSlider({ Title = "Loop delay (seconds)", Min = 0.05, Max = 1, Default = F.Delay, Precise = true }, setting("Delay"))

local Tools = Page.CreateSection("Tools")
Tools.CreateButton("Refresh flag token", function()
	local tk = findFlagToken()
	if tk then
		flagTemplate = { n = 3, [2] = tk, [3] = true }
		setLabel(lblTpl, "Flag template: automatic (token ..." .. tk:sub(-4) .. ")")
		resetFlags()
		UI.CreateNoti({ Title = "Token", Desc = "Flag token read from the game", ShowTime = 3 })
	else
		UI.CreateNoti({ Title = "Token", Desc = "Not found (needs filtergc). Place 1 flag manually.", ShowTime = 4 })
	end
end)
Tools.CreateButton("Dump board (check reading)", dumpBoard)
Tools.CreateButton("Copy log", copyLog)

---------------------------------------------------------------- page: Events
local EventPage = Main:CreatePage({ Page_Name = "Events", Page_Title = "Events" })

local EV = EventPage.CreateSection("Event Votes")
lblEvent = EV.CreateLabel("Event: idle")
EV.CreateToggle({ Title = "Auto join event", Desc = 'Presses "Yes" on the event round vote', Default = F.AutoEvent }, function(v)
	F.AutoEvent = v
	saveSettings()
	if v then
		task.spawn(eventLoop, 0.05)
	end
end)
EV.CreateToggle({ Title = "Auto join secret event", Desc = 'Spams the vote "Yes" button, even while hidden, until it opens', Default = F.AutoSecret }, function(v)
	F.AutoSecret = v
	saveSettings()
	if v then
		task.spawn(secretLoop)
	end
end)
EV.CreateBox({ Title = "Event vote text", Placeholder = "event round", Default = F.EventKw }, function(txt)
	F.EventKw = tostring(txt or "")
	saveSettings()
end)

local DS = EventPage.CreateSection("Dodge Spike")
lblSpike = DS.CreateLabel("Spikes: idle")
DS.CreateToggle({ Title = "Dodge spike", Desc = "Step off or jump over spikes before they come out", Default = F.Dodge }, function(v)
	F.Dodge = v
	saveSettings()
	if v then
		task.spawn(dodgeLoop)
	end
end)
DS.CreateToggle({ Title = "Step off hazardous cells", Desc = "Walk to the nearest safe opened cell", Default = F.DodgeMove }, setting("DodgeMove"))
DS.CreateToggle({ Title = "Jump over spikes", Desc = "Used when walking away is not possible or the area is crowded", Default = F.DodgeJump }, setting("DodgeJump"))
DS.CreateSlider({ Title = "Max steps to walk away", Min = 1, Max = 4, Default = F.SpikeMaxSteps }, setting("SpikeMaxSteps"))
DS.CreateSlider({ Title = "Warning to spike time (s)", Min = 0.5, Max = 2, Default = F.SpikeEta, Precise = true }, setting("SpikeEta"))
DS.CreateSlider({ Title = "Jump lead before spike (s)", Min = 0, Max = 0.6, Default = F.SpikeLead, Precise = true }, setting("SpikeLead"))
DS.CreateSlider({ Title = "Area radius (studs)", Min = 4, Max = 30, Default = F.SpikeRadius }, setting("SpikeRadius"))
DS.CreateSlider({ Title = "Crowded at (cells)", Min = 1, Max = 40, Default = F.SpikeCount }, setting("SpikeCount"))
DS.CreateBox({ Title = "Warning sound name", Placeholder = "Warn", Default = F.SpikeName }, function(txt)
	F.SpikeName = tostring(txt or "")
	saveSettings()
end)
DS.CreateBox({ Title = "Spike sound name", Placeholder = "Slash", Default = F.SpikeSound }, function(txt)
	F.SpikeSound = tostring(txt or "")
	saveSettings()
end)

local ET = EventPage.CreateSection("Tools")
ET.CreateButton("Dump vote prompts", dumpVotes)
ET.CreateButton("Dump spikes", dumpSpikes)
ET.CreateButton("Copy log", copyLog)

---------------------------------------------------------------- page: Manual
local ManualPage = Main:CreatePage({ Page_Name = "Manual", Page_Title = "Manual" })

local MS = ManualPage.CreateSection("Solver ESP")
lblMBoard = MS.CreateLabel("Board: off")
lblMNext = MS.CreateLabel("Next: -")
MS.CreateToggle({ Title = "Enable solver ESP", Desc = "Marks safe tiles, mines and 50/50 tiles on the board", Default = false }, function(v)
	if v then
		startManual()
	else
		stopManual()
	end
end)
MS.CreateToggle({ Title = "Safe ESP", Desc = "Green: proven safe", Default = F.ManualSafe }, setting("ManualSafe"))
MS.CreateToggle({ Title = "Bomb ESP", Desc = "Red: proven mine", Default = F.ManualBomb }, setting("ManualBomb"))
MS.CreateToggle({ Title = "50/50 ESP", Desc = "Yellow: could be either", Default = F.ManualHalf }, setting("ManualHalf"))
MS.CreateToggle({ Title = "Show a guess when stuck", Desc = "Blue: lowest-risk tile", Default = F.ManualSuggest }, setting("ManualSuggest"))

local MA = ManualPage.CreateSection("Auto-flag")
lblMFlag = MA.CreateLabel("Auto-flag: off")
MA.CreateToggle({ Title = "Auto-flag", Desc = "Flags proven mines near you (turn off Auto Farm first)", Default = false }, function(v)
	F.ManualAuto = v
end)
MA.CreateSlider({ Title = "Auto-flag range (studs)", Min = 1, Max = 31, Default = F.ManualRadius }, setting("ManualRadius"))
MA.CreateSlider({ Title = "Auto-flag delay (ms)", Min = 50, Max = 1000, Default = F.ManualDelay }, setting("ManualDelay"))
MA.CreateButton("Refresh flag token", function()
	resetManualToken()
	UI.CreateNoti({ Title = "Manual", Desc = "The flag token will be read again", ShowTime = 2 })
end)

-- all controls exist now: from here on changes are written to Levian Hub/<name>-minesweeper.json
F.settingsReady = true
saveSettings()

UI.CreateNoti({ Title = "Minesweeper ready", Desc = "Stand on an opened block, then turn on Auto Farm.", ShowTime = 4 })
