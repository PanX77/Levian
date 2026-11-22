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
	AutoToken = false, -- off by default: a wrong token is sent to the server
	PassFlags = true, -- allow walking over flagged blocks (shorter routes)
	FlagRange = 12, -- stud
	Delay = 0.15,
	CellSize = 5, -- size of 1 cell (studs)
	failed = {},
	autoTried = false,
	AutoEvent = false, -- press "Yes" on the event round vote
	AutoSecret = false, -- spam "Yes" until the secret event vote shows up
	EventKw = "event round", -- text that identifies the event vote
	SecretKw = "secret", -- text that identifies the secret event vote
	pressing = false,
	abort = false, -- set by the watchdog when the game ends/restarts: all walking and flagging stops
	WatchBusy = false,
	firedAt = {}, -- cell key -> time PlaceFlag was last fired on it
	firedCount = {}, -- cell key -> times PlaceFlag was fired on it this game (max 2)
	-- dodge spike
	Dodge = false, -- master switch
	DodgeMove = true, -- step off hazardous cells
	DodgeJump = true, -- jump when the area is crowded
	SpikeRadius = 12, -- studs: the "area" around the player
	SpikeCount = 4, -- hazardous cells in the area that count as crowded
	SpikeCue = "Slash", -- which sound is the jump cue: "Slash" or "Warn"
	SpikeCueRange = 7, -- studs: only cues from cells this close count
	SpikeJumpDelay = 0, -- seconds after the cue
	SpikeFallback = 0, -- seconds crowded without a cue before jumping anyway (0 = off)
	SpikeName = "Warn", -- name of the warning sound inside a cell
	SpikeSound = "Slash", -- name of the spike sound inside a cell
	dodging = false,
	DodgeBusy = false,
	dangerKeys = {}, -- cell keys that are hazardous right now
	lastCue = 0,
	lastJump = 0,
	settingsReady = false,
}

---------------------------------------------------------------- settings (JSON)
-- saved to: Levian Hub/<PlayerName>-minesweeper.json
local SETTINGS_KEYS = {
	"Guess", "Human", "Flagging", "AutoToken", "PassFlags", "FlagRange", "Delay",
	"AutoEvent", "AutoSecret", "EventKw", "SecretKw",
	"Dodge", "DodgeMove", "DodgeJump", "SpikeRadius", "SpikeCount", "SpikeCue", "SpikeCueRange", "SpikeJumpDelay", "SpikeFallback", "SpikeName", "SpikeSound",
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
local seenTokens = {} -- token-like strings from incoming remotes

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
local function isTokenLike(v)
	return type(v) == "string" and #v >= 20 and #v <= 40 and v:match("^%d+$") ~= nil
end

-- collect long digit strings from: incoming remotes, Values/attributes, and client script memory
local function collectTokens()
	local out, seen = {}, {}
	local function add(v, where)
		if isTokenLike(v) and not seen[v] then
			seen[v] = true
			out[#out + 1] = { v = v, where = where }
		end
	end
	for v in pairs(seenTokens) do
		add(v, "incoming remote")
	end
	local n = 0
	for _, root in ipairs({ LP, ReplicatedStorage, workspace }) do
		pcall(function()
			for _, v in pairs(root:GetAttributes()) do
				add(v, "attribute " .. path(root))
			end
			for _, d in ipairs(root:GetDescendants()) do
				n += 1
				if n % 3000 == 0 then
					task.wait()
				end
				if d:IsA("ValueBase") then
					local okv, val = pcall(function()
						return d.Value
					end)
					if okv then
						add(val, "Value " .. path(d))
					end
				end
				for _, v in pairs(d:GetAttributes()) do
					add(v, "attribute " .. path(d))
				end
			end
		end)
	end
	if getgc then
		pcall(function()
			for i, o in ipairs(getgc(true)) do
				if i % 2000 == 0 then
					task.wait()
				end
				local t = type(o)
				if t == "table" then
					pcall(function()
						for _, v in next, o do
							add(v, "memory (table)")
						end
					end)
				elseif t == "function" and debug and debug.getupvalues then
					pcall(function()
						if islclosure and not islclosure(o) then
							return
						end
						for _, uv in pairs(debug.getupvalues(o)) do
							add(uv, "memory (upvalue)")
						end
						if debug.getconstants then
							for _, c in pairs(debug.getconstants(o)) do
								add(c, "memory (constant)")
							end
						end
					end)
				end
			end
		end)
	end
	return out
end

-- catch token-like strings sent by the server
local watched = {}
local function scanArgs(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if isTokenLike(v) then
			seenTokens[v] = true
		end
	end
end
local function watch(inst)
	if watched[inst] then
		return
	end
	local okC, isEvent = pcall(function()
		return inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")
	end)
	if okC and isEvent then
		watched[inst] = true
		inst.OnClientEvent:Connect(scanArgs)
	end
end
task.spawn(function()
	for _, d in ipairs(game:GetDescendants()) do
		watch(d)
	end
end)
game.DescendantAdded:Connect(watch)

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
local GREEN = Color3.new(0, 0.988235, 0) -- flagged cell color
local BROWN = { Color3.new(0.803922, 0.556863, 0.392157), Color3.new(0.705882, 0.490196, 0.345098) }

local function fstatus(t)
	setLabel(lblFarm, "Status: " .. t)
end
local function ckey(x, z)
	return x .. "," .. z
end
local function near(a, b)
	return math.abs(a.R - b.R) < 0.02 and math.abs(a.G - b.G) < 0.02 and math.abs(a.B - b.B) < 0.02
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
	return part:FindFirstChildOfClass("Model") ~= nil or near(part.Color, GREEN)
end

local function readNumber(gui)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
			local n = tonumber((d.Text or ""):match("%d+"))
			if n then
				return n
			end
		end
	end
	return nil
end

-- state: flag (has a flag Model) | num (has a NumberGui) | unk (brown color) | zero (opened, no number)
local function buildBoard()
	local f = workspace:FindFirstChild("Flag")
	local parts = f and f:FindFirstChild("Parts")
	if not parts then
		return nil
	end
	local B = { cells = {}, list = {} }
	for _, p in ipairs(parts:GetChildren()) do
		if p:IsA("BasePart") then
			local x = math.floor(p.Position.X / F.CellSize + 0.5)
			local z = math.floor(p.Position.Z / F.CellSize + 0.5)
			local c = { part = p, x = x, z = z, key = ckey(x, z) }
			local gui = p:FindFirstChild("NumberGui")
			if flagged(p) then
				c.state = "flag"
			elseif gui then
				c.state = "num"
				c.n = readNumber(gui)
			elseif near(p.Color, BROWN[1]) or near(p.Color, BROWN[2]) then
				c.state = "unk"
			else
				c.state = "zero"
			end
			if c.state == "unk" then
				local t = F.firedAt[c.key]
				if t and os.clock() - t < 6 then
					c.state = "pending" -- flag fired, not visible yet: counts as a mine, never walkable
				end
			end
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
		if p:FindFirstChild("NumberGui") or not (near(p.Color, BROWN[1]) or near(p.Color, BROWN[2])) then
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
	-- the server may need proximity: walk to the source cell and try again
	local from = curCell(B)
	if from and standable(from) then
		local path = bfs(B, from, function(c)
			return c == src
		end)
		if path then
			for i = 2, #path do
				if not F.Run or not moveTo(path[i]) then
					break
				end
			end
		end
	end
	if F.abort then
		return false
	end
	if flagged(cell.part) then
		return true -- it appeared while walking: do NOT fire again (would replace/remove it)
	end
	fireFlag(cell.part)
	if waitFlag(cell.part, 0.8) then
		return true
	end
	push(("FLAG not visible on %s after 2 tries"):format(cell.key))
	F.failed[cell.key] = true
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

-- try automatic tokens on one certain mine; valid only if the flag actually appears
local function tryAutoToken(B, mineK)
	local remote = getFlagRemote()
	if not remote then
		return false
	end
	local target
	for _, m in pairs(mineK) do
		if not flagged(m.cell.part) then
			target = m
			break
		end
	end
	if not target then
		return false
	end
	local cands = collectTokens()
	push(("AUTO TOKEN: %d candidates"):format(#cands))
	for i = 1, math.min(#cands, 3) do
		local tk = cands[i].v
		push(("  trying #%d (...%s) from %s"):format(i, tk:sub(-6), cands[i].where))
		remote:FireServer(target.cell.part, tk, true)
		if waitFlag(target.cell.part, 1) then
			flagTemplate = { n = 3, [2] = tk, [3] = true }
			setLabel(lblTpl, "Flag template: automatic (token ..." .. tk:sub(-4) .. ")")
			push("  token valid")
			return true
		end
	end
	return false
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
		if F.Flagging and F.AutoToken and not flagTemplate and not F.autoTried and next(mineK) then
			F.autoTried = true
			fstatus("searching for the flag token automatically")
			if not tryAutoToken(B, mineK) then
				UI.CreateNoti({ Title = "Token", Desc = "Not found automatically. Place 1 flag manually.", ShowTime = 4 })
			end
		end
		local canFlag = F.Flagging and flagTemplate ~= nil
		local acted, stepped = false, false

		-- 1) first finish all mines around the avatar (within range), nearest first
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

		-- 3) no safe blocks left: flag the remaining mines (walk closer if needed)
		if F.Run and not F.abort and not stepped and canFlag then
			while F.Run and not F.abort do
				local r = char:FindFirstChild("HumanoidRootPart")
				local m = r and pickMine(mineK, r.Position, math.huge)
				if not m then
					break
				end
				fstatus("flagging remaining mine " .. m.cell.key)
				if flagCell(B, m.cell, m.src) then
					acted = true
				end
				task.wait(F.Delay)
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
					ch = c.n and tostring(c.n) or "?"
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
local function yesTarget(d)
	if d:IsA("TextButton") and trim(d.Text):lower() == "yes" then
		return d
	end
	if d:IsA("TextLabel") and trim(d.Text):lower() == "yes" then
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

local function promptMatches(kind, txt)
	if txt == "" or txt:find("kick", 1, true) then
		return false -- never vote on a votekick prompt
	end
	local sk, ek = F.SecretKw:lower(), F.EventKw:lower()
	local hasSecret = sk ~= "" and txt:find(sk, 1, true) ~= nil
	if kind == "secret" then
		return hasSecret
	end
	return ek ~= "" and txt:find(ek, 1, true) ~= nil and not hasSecret
end

local seenAt = {} -- btn -> time the matching prompt was first seen
local done = {} -- btn -> true once the vote went through (reset when the prompt hides or restarts at 0)
local function eventLoop(flag, kind, interval)
	while F[flag] do
		for btn in pairs(yesBtns) do
			if not btn.Parent then
				yesBtns[btn], seenAt[btn], done[btn] = nil, nil, nil
			elseif shown(btn) then
				local txt = promptText(btn)
				if done[btn] and voteCount(txt) == 0 then
					done[btn] = nil -- a new vote started on the same prompt
				end
				if promptMatches(kind, txt) and not txt:find("back out", 1, true) and not done[btn] then
					if not seenAt[btn] then
						seenAt[btn] = os.clock()
						push(("[%s] VOTE %s prompt seen: %q"):format(os.date("%H:%M:%S"), kind, txt:sub(1, 100)))
					end
					if not F.pressing then
						F.pressing = true
						local ok = pressYes(btn, kind)
						F.pressing = false
						if ok then
							done[btn] = true
						end
						push(("[%s] VOTE %s %s after %.2fs"):format(os.date("%H:%M:%S"), kind, ok and "sent" or "still trying", os.clock() - seenAt[btn]))
						setLabel(lblEvent, "Event: " .. kind .. (ok and " vote sent" or " still trying"))
					end
				end
			else
				seenAt[btn], done[btn] = nil, nil
			end
		end
		task.wait(interval)
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
-- Spikes live on the board cells: every cell part has "Warn" and "Slash" sounds (seen in the log dump).
-- A cell is hazardous while its Warn/Slash sound is playing (or it turns red). The bot steps off a hazardous
-- cell and, when many cells around you are hazardous, jumps on the Slash (or Warn) cue.
local lblSpike = nil
local cellIndex, cellIndexAt = {}, -math.huge
local wasSlash, wasWarn = {}, {}

local function refreshIndex()
	if os.clock() - cellIndexAt < 2 then
		return
	end
	cellIndexAt = os.clock()
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

local function isRedColor(c)
	return c.R > 0.75 and c.G < 0.3 and c.B < 0.3
end

-- hazardous cells near pos: set of cell keys, how many are inside the area radius, and a fresh sound cue (cell key)
local function scanHazards(pos)
	local warnName = F.SpikeName ~= "" and F.SpikeName or "Warn"
	local slashName = F.SpikeSound ~= "" and F.SpikeSound or "Slash"
	local reach2, area2, cue2 = (F.SpikeRadius + 4) ^ 2, F.SpikeRadius ^ 2, F.SpikeCueRange ^ 2
	local danger, count, cue = {}, 0, nil
	for _, e in ipairs(cellIndex) do
		local dx, dz = e.x - pos.X, e.z - pos.Z
		local d2 = dx * dx + dz * dz
		if d2 <= reach2 then
			local p = e.part
			local w, sl = p:FindFirstChild(warnName), p:FindFirstChild(slashName)
			local warning = (w and w:IsA("Sound") and w.IsPlaying) or false
			local slashing = (sl and sl:IsA("Sound") and sl.IsPlaying) or false
			if warning or slashing or isRedColor(p.Color) then
				danger[e.key] = true
				if d2 <= area2 then
					count += 1
				end
			end
			local fresh = (F.SpikeCue == "Warn" and warning and not wasWarn[e.key])
				or (F.SpikeCue ~= "Warn" and slashing and not wasSlash[e.key])
			if fresh and d2 <= cue2 then
				cue = cue or e.key
			end
			wasSlash[e.key], wasWarn[e.key] = slashing, warning
		end
	end
	return danger, count, cue
end

local function jump(reason)
	if os.clock() - F.lastJump < 0.6 then
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

local function dodgeWalk(cell)
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then
		return false
	end
	local tx, tz = cell.part.Position.X, cell.part.Position.Z
	local t0 = os.clock()
	while F.Dodge and os.clock() - t0 < 1.5 do
		hum:MoveTo(Vector3.new(tx, hrp.Position.Y, tz))
		local dx, dz = hrp.Position.X - tx, hrp.Position.Z - tz
		if math.sqrt(dx * dx + dz * dz) < 1.2 then
			return true
		end
		task.wait(0.03)
	end
	return false
end

local function dodgeLoop()
	if F.DodgeBusy then
		return
	end
	F.DodgeBusy = true
	local denseSince, lastLog, lastText = nil, 0, ""
	while F.Dodge do
		task.wait(0.05)
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp or hum.Health <= 0 then
			F.dangerKeys, denseSince = {}, nil
			continue
		end
		refreshIndex()
		local pos = hrp.Position
		local danger, count, cue = scanHazards(pos)
		F.dangerKeys = danger -- buildBoard marks these cells as danger (routes avoid them)
		local ownKey = ckey(math.floor(pos.X / F.CellSize + 0.5), math.floor(pos.Z / F.CellSize + 0.5))
		local underMe = danger[ownKey] == true
		local text = ("Spikes: %d cells in area%s"):format(count, underMe and " (your cell!)" or "")
		if text ~= lastText then
			lastText = text
			setLabel(lblSpike, text)
		end

		-- crowded area: jump on the sound cue (or after the fallback time if no cue came)
		if F.DodgeJump and count >= F.SpikeCount then
			denseSince = denseSince or os.clock()
			if os.clock() - lastLog > 1 then
				lastLog = os.clock()
				push(("[%s] SPIKE crowded: %d hazardous cells within %.0f studs"):format(os.date("%H:%M:%S"), count, F.SpikeRadius))
			end
			if cue then
				F.lastCue = os.clock()
				push(("[%s] SPIKE cue (%s) at %s -> jump in %.2fs"):format(os.date("%H:%M:%S"), F.SpikeCue, cue, F.SpikeJumpDelay))
				task.delay(F.SpikeJumpDelay, function()
					jump("cue")
				end)
			elseif F.SpikeFallback > 0 and os.clock() - denseSince >= F.SpikeFallback and F.lastCue < denseSince then
				jump("fallback")
				denseSince = os.clock()
			end
		else
			denseSince = nil
		end

		-- your cell is hazardous: step to the nearest safe opened/flagged cell
		if F.DodgeMove and underMe and not F.dodging then
			local B = buildBoard()
			local cur = B and curCell(B)
			if cur and standable(cur) then
				local path2 = escapePath(B, cur)
				if path2 and #path2 >= 2 then
					F.dodging, F.abort = true, true -- pause the farm loop while we move
					push(("[%s] SPIKE dodge: %s -> %s"):format(os.date("%H:%M:%S"), cur.key, path2[#path2].key))
					for i = 2, #path2 do
						if not dodgeWalk(path2[i]) then
							break
						end
					end
					stopWalking()
					F.dodging = false
				elseif F.DodgeJump then
					jump("no safe cell to step to")
				end
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
	local danger, count = scanHazards(pos)
	local ownKey = ckey(math.floor(pos.X / F.CellSize + 0.5), math.floor(pos.Z / F.CellSize + 0.5))
	local n = 0
	for _ in pairs(danger) do
		n += 1
	end
	push(("[%s] SPIKES: %d hazardous cells near (%d in area radius), your cell %s%s"):format(
		os.date("%H:%M:%S"), n, count, ownKey, danger[ownKey] and " IS HAZARDOUS" or ""
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
FS.CreateToggle({ Title = "Flag mines", Desc = "Place flags on certain mines", Default = F.Flagging }, setting("Flagging"))
FS.CreateSlider({ Title = "Flag range (studs)", Min = 5, Max = 40, Default = F.FlagRange }, setting("FlagRange"))
FS.CreateToggle({ Title = "Auto find token", Desc = "Tries up to 3 candidates on 1 certain mine", Default = F.AutoToken }, setting("AutoToken"))
FS.CreateToggle({ Title = "Walk over flags", Desc = "Walk on flagged blocks for shorter routes", Default = F.PassFlags }, setting("PassFlags"))
FS.CreateToggle({ Title = "Guess when stuck", Desc = "Risk of stepping on a mine", Default = F.Guess }, setting("Guess"))
FS.CreateSlider({ Title = "Loop delay (seconds)", Min = 0.05, Max = 1, Default = F.Delay, Precise = true }, setting("Delay"))

local Tools = Page.CreateSection("Tools")
Tools.CreateButton("Find token now", function()
	task.spawn(function()
		local B = buildBoard()
		local mineK = B and solve(B)
		if not mineK or not next(mineK) then
			UI.CreateNoti({ Title = "Token", Desc = "No certain mine to test with yet", ShowTime = 3 })
			return
		end
		local ok = tryAutoToken(B, mineK)
		UI.CreateNoti({
			Title = "Token",
			Desc = ok and "Token valid" or "Not found, place 1 flag manually",
			ShowTime = 3,
		})
	end)
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
		task.spawn(eventLoop, "AutoEvent", "event", 0.05)
	end
end)
EV.CreateToggle({ Title = "Auto join secret event", Desc = 'Spams "Yes" until the secret event vote shows up', Default = F.AutoSecret }, function(v)
	F.AutoSecret = v
	saveSettings()
	if v then
		task.spawn(eventLoop, "AutoSecret", "secret", 0.05)
	end
end)
EV.CreateBox({ Title = "Event vote text", Placeholder = "event round", Default = F.EventKw }, function(txt)
	F.EventKw = tostring(txt or "")
	saveSettings()
end)
EV.CreateBox({ Title = "Secret vote text", Placeholder = "secret", Default = F.SecretKw }, function(txt)
	F.SecretKw = tostring(txt or "")
	saveSettings()
end)

local DS = EventPage.CreateSection("Dodge Spike")
lblSpike = DS.CreateLabel("Spikes: idle")
DS.CreateToggle({ Title = "Dodge spike", Desc = "Step off hazardous cells, jump when crowded", Default = F.Dodge }, function(v)
	F.Dodge = v
	saveSettings()
	if v then
		task.spawn(dodgeLoop)
	end
end)
DS.CreateToggle({ Title = "Move off hazardous cells", Desc = "Step to the nearest safe opened cell", Default = F.DodgeMove }, setting("DodgeMove"))
DS.CreateToggle({ Title = "Jump when crowded", Desc = "Jump on the sound cue when many cells are hazardous", Default = F.DodgeJump }, setting("DodgeJump"))
DS.CreateDropdown({ Title = "Jump cue sound", List = { "Slash", "Warn" }, Default = F.SpikeCue }, function(v)
	F.SpikeCue = v
	saveSettings()
end)
DS.CreateSlider({ Title = "Area radius (studs)", Min = 4, Max = 30, Default = F.SpikeRadius }, setting("SpikeRadius"))
DS.CreateSlider({ Title = "Crowded at (cells)", Min = 1, Max = 30, Default = F.SpikeCount }, setting("SpikeCount"))
DS.CreateSlider({ Title = "Cue range (studs)", Min = 2, Max = 20, Default = F.SpikeCueRange }, setting("SpikeCueRange"))
DS.CreateSlider({ Title = "Jump delay after cue (s)", Min = 0, Max = 1, Default = F.SpikeJumpDelay, Precise = true }, setting("SpikeJumpDelay"))
DS.CreateSlider({ Title = "Fallback jump, no cue (s, 0 = off)", Min = 0, Max = 3, Default = F.SpikeFallback, Precise = true }, setting("SpikeFallback"))
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

-- all controls exist now: from here on changes are written to Levian Hub/<name>-minesweeper.json
F.settingsReady = true
saveSettings()

UI.CreateNoti({ Title = "Minesweeper ready", Desc = "Stand on an opened block, then turn on Auto Farm.", ShowTime = 4 })
