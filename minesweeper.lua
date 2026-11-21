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
	firedAt = {}, -- cell key -> time PlaceFlag was last fired on it
	firedCount = {}, -- cell key -> times PlaceFlag was fired on it this game (max 2)
}
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
local function passable(c)
	return revealed(c) or (F.PassFlags and c.state == "flag")
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

-- wait until the stepped block opens (checks every 0.02s) instead of a fixed delay
local function waitRevealed(cell)
	local t0 = os.clock()
	while F.Run and os.clock() - t0 < 0.6 do
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
	if not hum or not hrp or hum.Health <= 0 then
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
	while F.Run and os.clock() - t0 < 4 do
		hum:MoveTo(Vector3.new(tx, hrp.Position.Y, tz))
		local dx, dz = hrp.Position.X - tx, hrp.Position.Z - tz
		if math.sqrt(dx * dx + dz * dz) < thr then
			return true
		end
		task.wait(0.03)
	end
	return false
end

-- walk through opened cells (4 directions) to a neighbor matching pred, then step on it.
-- Always the nearest; route and ties are randomized in Human-like mode.
local function stepToward(B, cur, pred)
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
			if n and n.state == "unk" and pred(n) then
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
		if not F.Run then
			return false
		end
		local c0, p0 = path[i], path[i - 1]
		local nxt = path[i + 1] or pick.n
		local straight = (nxt.x - c0.x == c0.x - p0.x) and (nxt.z - c0.z == c0.z - p0.z)
		if not moveTo(c0, straight) then
			return false
		end
	end
	if not F.Run then
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
	if not remote or not flagTemplate then
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
	while os.clock() - t0 < t do
		if flagged(part) then
			return true
		end
		task.wait(0.05)
	end
	return false
end
local function flagCell(B, cell, src)
	if not fireFlag(cell.part) then
		F.failed[cell.key] = true
		return false
	end
	if waitFlag(cell.part, 0.8) then
		return true
	end
	-- the server may need proximity: walk to the source cell and try again
	local from = curCell(B)
	if from and passable(from) then
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

local function farmLoop()
	if F.Busy then
		return
	end
	F.Busy = true
	resetFlags()
	local notified, lastRevealed, tplSeen = false, 0, flagTemplate
	local quick = false -- true after stepping: continue without delay
	while F.Run do
		if quick then
			task.wait()
		else
			task.wait(F.Delay * (0.7 + math.random() * 0.6))
		end
		quick = false
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
		if not cur or not passable(cur) then
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
				if not F.Run then
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
				else
					fstatus("flag failed (outdated template? place 1 flag manually again)")
				end
			end
		end

		-- 2) walk to the nearest safe block
		cur = curCell(B)
		if F.Run and cur and passable(cur) and next(safeK) then
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
		if F.Run and not stepped and canFlag then
			while F.Run do
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

		if F.Run and not acted then
			cur = curCell(B)
			if F.Guess and cur and passable(cur) then
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
	for i = 1, 8 do
		if not btn.Parent or not shown(btn) then
			return true
		end
		local txt = promptText(btn)
		if txt:find("back out", 1, true) then
			return true
		end
		local cur, req = voteCount(txt)
		if cur and req and cur >= req then
			return true
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

---------------------------------------------------------------- UI
local Main = UI.CreateMain({ Title = "Levian Hub - Minesweeper" })

local DISCORD_LINK = "https://discord.gg/Mc2YpMT2cF"
local About = Main:CreatePage({ Page_Name = "About Us", Page_Title = "About Us" })
local AS = About.CreateSection("About Us")
AS.CreateLabel("Levian Hub")
AS.CreateButton("Copy Link", function()
	if setclipboard then
		setclipboard(DISCORD_LINK)
		UI.CreateNoti({ Title = "Copied", Desc = "Discord link copied to clipboard", ShowTime = 2 })
	else
		UI.CreateNoti({ Title = "Failed", Desc = "Executor has no setclipboard", ShowTime = 3 })
	end
end)

local Page = Main:CreatePage({ Page_Name = "Auto Farm", Page_Title = "Auto Farm" })

local FS = Page.CreateSection("Auto Minesweeper")
lblTpl = FS.CreateLabel("Flag template: none yet (found automatically, or place 1 flag manually)")
lblFarm = FS.CreateLabel("Status: off")
FS.CreateToggle({ Title = "Auto Farm", Desc = "Flag mines + walk to safe blocks", Default = false }, function(v)
	F.Run = v
	if v then
		task.spawn(farmLoop)
	end
end)
FS.CreateDropdown({ Title = "Walking style", List = { "Human-like", "Robot" }, Default = "Human-like" }, function(v)
	F.Human = (v == "Human-like")
end)
FS.CreateToggle({ Title = "Flag mines", Desc = "Place flags on certain mines", Default = true }, function(v)
	F.Flagging = v
end)
FS.CreateSlider({ Title = "Flag range (studs)", Min = 5, Max = 40, Default = 12 }, function(v)
	F.FlagRange = v
end)
FS.CreateToggle({ Title = "Auto find token", Desc = "Tries up to 3 candidates on 1 certain mine", Default = false }, function(v)
	F.AutoToken = v
end)
FS.CreateToggle({ Title = "Walk over flags", Desc = "Walk on flagged blocks for shorter routes", Default = true }, function(v)
	F.PassFlags = v
end)
FS.CreateToggle({ Title = "Guess when stuck", Desc = "Risk of stepping on a mine", Default = false }, function(v)
	F.Guess = v
end)
FS.CreateSlider({ Title = "Loop delay (seconds)", Min = 0.05, Max = 1, Default = 0.15, Precise = true }, function(v)
	F.Delay = v
end)

local EV = Page.CreateSection("Events")
lblEvent = EV.CreateLabel("Event: idle")
EV.CreateToggle({ Title = "Auto join event", Desc = 'Presses "Yes" on the event round vote', Default = false }, function(v)
	F.AutoEvent = v
	if v then
		task.spawn(eventLoop, "AutoEvent", "event", 0.05)
	end
end)
EV.CreateToggle({ Title = "Auto join secret event", Desc = 'Spams "Yes" until the secret event vote shows up', Default = false }, function(v)
	F.AutoSecret = v
	if v then
		task.spawn(eventLoop, "AutoSecret", "secret", 0.05)
	end
end)
EV.CreateBox({ Title = "Event vote text", Placeholder = "event round", Default = "event round" }, function(txt)
	F.EventKw = tostring(txt or "")
end)
EV.CreateBox({ Title = "Secret vote text", Placeholder = "secret", Default = "secret" }, function(txt)
	F.SecretKw = tostring(txt or "")
end)

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
Tools.CreateButton("Dump vote prompts", dumpVotes)
Tools.CreateButton("Copy log", function()
	if setclipboard then
		setclipboard(table.concat(logs, "\n"))
		UI.CreateNoti({ Title = "Log copied", Desc = #logs .. " lines", ShowTime = 2 })
	else
		UI.CreateNoti({ Title = "Failed", Desc = "Executor has no setclipboard", ShowTime = 3 })
	end
end)

UI.CreateNoti({ Title = "Minesweeper ready", Desc = "Stand on an opened block, then turn on Auto Farm.", ShowTime = 4 })
