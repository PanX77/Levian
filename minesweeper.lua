--[[
	Minesweeper | Levian Hub
	Fitur 1: Remote Spy (log remote saat avatar berjalan ke block)

	Cara kerja:
	  1. Setiap frame, script menembak raycast ke bawah dari HumanoidRootPart.
	     Kalau part di bawah kaki berganti => dianggap "melangkah ke block" (STEP).
	  2. Hook __namecall mencatat FireServer / InvokeServer (OUT).
	     Opsional: catat juga OnClientEvent dari server (IN).
	  3. Mode "Hanya dekat step": remote hanya dicatat dalam X detik setelah STEP,
	     jadi log tidak penuh remote lain. Angka "+0.05s" = jarak waktu dari step.
	  4. Kalau tidak ada remote OUT sama sekali saat melangkah, berarti server
	     mendeteksi sendiri lewat Touched / posisi. Lihat info block di log
	     (atribut, child, ClickDetector, TouchTransmitter).
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
		UI = loadstring(readfile("LevianUI.lua"))() -- cadangan: file lokal
	end
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

---------------------------------------------------------------- state
local S = {
	Spy = true,
	OnlyStep = false, -- default mati: catat semua remote dulu sampai step terdeteksi benar
	CellMode = true, -- deteksi step berdasarkan posisi grid (untuk lantai satu part)
	CellSize = 5, -- ukuran 1 kotak (stud); di game ini 5
	Touch = false, -- catat part yang disentuh avatar
	Window = 1.5, -- detik setelah STEP yang masih dicatat
	Incoming = false,
	BlockFilter = "", -- kosong = semua part dianggap block
	Ignore = { patukka = true, afkevent = true }, -- [namaremote lowercase] = true
	Max = 500,
}
local logs = {}
local lastStep = -math.huge
local lastBlock
local stepCount, remoteCount = 0, 0
local lblStep, lblRemote, lblCount, lblTpl, lblFarm
local flagTemplate -- argumen PlaceFlag terakhir dari pemain (dipakai ulang oleh auto farm)

---------------------------------------------------------------- util
-- game ini memberi nama instance dengan banyak newline; ganti jadi "¶" agar log rapi
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
	if #logs > S.Max then
		table.remove(logs, 1)
	end
	print("[MS-Spy] " .. line)
end

---------------------------------------------------------------- remote logging
local function addLog(kind, remote, method, a)
	local name = remote.Name
	if S.Ignore[name:lower()] then
		return
	end
	if S.OnlyStep and (os.clock() - lastStep) > S.Window then
		return
	end
	local parts = {}
	for i = 1, a.n do
		parts[i] = ser(a[i])
	end
	remoteCount += 1
	local line = ("[%s] +%.2fs %s %s (%s) args: %s"):format(
		os.date("%H:%M:%S"),
		os.clock() - lastStep,
		kind,
		path(remote),
		method,
		#parts > 0 and table.concat(parts, ", ") or "(kosong)"
	)
	push(line)
	setLabel(lblRemote, kind .. " " .. name)
	setLabel(lblCount, ("Step: %d | Remote tercatat: %d"):format(stepCount, remoteCount))
end

-- hook FireServer / InvokeServer
local hooked = false
if hookmetamethod and getnamecallmethod and newcclosure then
	local old
	old = hookmetamethod(
		game,
		"__namecall",
		newcclosure(function(self, ...)
			local m = getnamecallmethod()
			if
				S.Spy
				and (m == "FireServer" or m == "InvokeServer" or m == "fireServer" or m == "invokeServer")
				and not checkcaller()
				and typeof(self) == "Instance"
			then
				local a = table.pack(...)
				local remote = self
				if remote.Name == "PlaceFlag" then
					flagTemplate = a
					task.defer(setLabel, lblTpl, "Template flag: siap")
				end
				task.defer(function()
					local okC, isRemote = pcall(function()
						return remote:IsA("RemoteEvent")
							or remote:IsA("RemoteFunction")
							or remote:IsA("UnreliableRemoteEvent")
					end)
					if okC and isRemote then
						addLog("OUT", remote, m, a)
					end
				end)
			end
			return old(self, ...)
		end)
	)
	hooked = true
else
	warn("[MS-Spy] Executor tidak mendukung hookmetamethod, remote OUT tidak bisa dicatat")
end

-- OnClientEvent (server -> client)
local watched = {}
local function watch(inst)
	if watched[inst] then
		return
	end
	local okC, isEvent = pcall(function()
		return inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")
	end)
	if not okC or not isEvent then
		return
	end
	watched[inst] = true
	inst.OnClientEvent:Connect(function(...)
		if S.Spy and S.Incoming then
			addLog("IN ", inst, "OnClientEvent", table.pack(...))
		end
	end)
end
task.spawn(function()
	for _, d in ipairs(game:GetDescendants()) do
		watch(d)
	end
end)
game.DescendantAdded:Connect(watch)

---------------------------------------------------------------- deteksi step
local function describe(part)
	local t = {}
	t[#t + 1] = ("%s [%s]"):format(path(part), part.ClassName)
	local p, s = part.Position, part.Size
	t[#t + 1] = ("pos=%.1f,%.1f,%.1f size=%.1f,%.1f,%.1f color=%s material=%s"):format(
		p.X, p.Y, p.Z, s.X, s.Y, s.Z, tostring(part.Color), part.Material.Name
	)
	local attrs = {}
	for k, v in pairs(part:GetAttributes()) do
		attrs[#attrs + 1] = k .. "=" .. ser(v)
	end
	if #attrs > 0 then
		t[#t + 1] = "attr: " .. table.concat(attrs, ", ")
	end
	local kids = {}
	for _, c in ipairs(part:GetChildren()) do
		local extra = ""
		if c:IsA("ValueBase") then
			extra = "=" .. tostring(c.Value)
		end
		kids[#kids + 1] = c.Name .. "<" .. c.ClassName .. ">" .. extra
	end
	if #kids > 0 then
		t[#t + 1] = "child: " .. table.concat(kids, ", ")
	end
	return table.concat(t, " | ")
end

local function isBlock(part)
	if not part or part:IsA("Terrain") then
		return false
	end
	local f = S.BlockFilter
	if f == "" then
		return true
	end
	f = f:lower()
	return part.Name:lower():find(f, 1, true) ~= nil or part:GetFullName():lower():find(f, 1, true) ~= nil
end

local function onStep(part, text)
	lastStep = os.clock()
	stepCount += 1
	push(("[%s] STEP #%d %s"):format(os.date("%H:%M:%S"), stepCount, part and describe(part) or text))
	setLabel(lblStep, part and ("Block: " .. part.Name) or text)
	setLabel(lblCount, ("Step: %d | Remote tercatat: %d"):format(stepCount, remoteCount))
end

local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Exclude
local lastChar, lastCell
RunService.Heartbeat:Connect(function()
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	if char ~= lastChar then
		lastChar = char
		rp.FilterDescendantsInstances = { char }
	end
	local r = workspace:Raycast(hrp.Position, Vector3.new(0, -8, 0), rp)
	local part = r and r.Instance
	if part ~= lastBlock then
		lastBlock = part
		if part and isBlock(part) then
			onStep(part)
		end
	end
	if S.CellMode then
		local p = hrp.Position
		local key = math.floor(p.X / S.CellSize + 0.5) .. "," .. math.floor(p.Z / S.CellSize + 0.5)
		if key ~= lastCell then
			lastCell = key
			onStep(nil, ("CELL %s (lantai: %s)"):format(key, part and part.Name or "-"))
		end
	end
end)

---------------------------------------------------------------- touch, scan, dump
local touchSeen = {}
local function hookChar(char)
	for _, p in ipairs(char:GetChildren()) do
		if p:IsA("BasePart") then
			p.Touched:Connect(function(o)
				if not S.Touch or o:IsDescendantOf(char) then
					return
				end
				if touchSeen[o] and os.clock() - touchSeen[o] < 1 then
					return
				end
				touchSeen[o] = os.clock()
				push(("[%s] TOUCH %s [%s] CanQuery=%s"):format(os.date("%H:%M:%S"), path(o), o.ClassName, tostring(o.CanQuery)))
			end)
		end
	end
end
if LP.Character then
	hookChar(LP.Character)
end
LP.CharacterAdded:Connect(function(c)
	task.wait(1)
	hookChar(c)
end)

local function scan()
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local list = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and not d:IsDescendantOf(char) then
			local dist = (d.Position - hrp.Position).Magnitude
			if dist <= 30 then
				list[#list + 1] = { d, dist }
			end
		end
	end
	table.sort(list, function(a, b)
		return a[2] < b[2]
	end)
	push(("[%s] SCAN %d part dalam radius 30 stud (posisi avatar %.1f, %.1f, %.1f)"):format(
		os.date("%H:%M:%S"), #list, hrp.Position.X, hrp.Position.Y, hrp.Position.Z
	))
	for i = 1, math.min(#list, 40) do
		local d = list[i][1]
		push(("  %.1f stud | %s | CanQuery=%s CanTouch=%s CanCollide=%s Transp=%.2f"):format(
			list[i][2], describe(d), tostring(d.CanQuery), tostring(d.CanTouch), tostring(d.CanCollide), d.Transparency
		))
	end
end

local function dumpRemotes()
	push(("[%s] DUMP REMOTE:"):format(os.date("%H:%M:%S")))
	local n = 0
	for _, d in ipairs(game:GetDescendants()) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
			n += 1
			push(("  [%s] %s"):format(d.ClassName, path(d)))
		end
	end
	push(("  total: %d"):format(n))
end

---------------------------------------------------------------- AUTO FARM (solver minesweeper)
local F = { Run = false, Busy = false, Guess = false, Delay = 0.15, failed = {} }
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
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
local function flagged(part)
	return part:FindFirstChildOfClass("Model") ~= nil
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

-- state: flag (ada Model bendera) | num (ada NumberGui) | unk (warna cokelat) | zero (terbuka tanpa angka)
local function buildBoard()
	local f = workspace:FindFirstChild("Flag")
	local parts = f and f:FindFirstChild("Parts")
	if not parts then
		return nil
	end
	local B = { cells = {}, list = {} }
	for _, p in ipairs(parts:GetChildren()) do
		if p:IsA("BasePart") then
			local x = math.floor(p.Position.X / S.CellSize + 0.5)
			local z = math.floor(p.Position.Z / S.CellSize + 0.5)
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

-- solver: aturan dasar + aturan subset. Hanya menandai yang PASTI.
local function solve(B)
	local cons = {}
	for _, c in ipairs(B.list) do
		if c.state == "num" and c.n then
			local U, fl = {}, 0
			for _, n in ipairs(nbrs(B, c)) do
				if n.state == "flag" then
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

-- cell di bawah avatar
local function curCell(B)
	local char = LP.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	return B.cells[ckey(math.floor(hrp.Position.X / S.CellSize + 0.5), math.floor(hrp.Position.Z / S.CellSize + 0.5))]
end

-- BFS 4 arah, hanya lewat cell yang sudah terbuka (agar tidak menginjak yang belum terbuka)
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
			if n and prev[n.key] == nil and revealed(n) then
				prev[n.key] = c
				q[#q + 1] = n
			end
		end
	end
	return nil
end

local function moveTo(cell)
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp or hum.Health <= 0 then
		return false
	end
	local tx, tz = cell.part.Position.X, cell.part.Position.Z
	local t0 = os.clock()
	while F.Run and os.clock() - t0 < 4 do
		hum:MoveTo(Vector3.new(tx, hrp.Position.Y, tz))
		local dx, dz = hrp.Position.X - tx, hrp.Position.Z - tz
		if math.sqrt(dx * dx + dz * dz) < 1.2 then
			return true
		end
		task.wait(0.08)
	end
	return false
end

-- jalan lewat cell terbuka sampai ada tetangga (4 arah) yang memenuhi pred, lalu injak tetangga itu
local function stepToward(B, cur, pred)
	local target
	local path = bfs(B, cur, function(c)
		for _, d in ipairs(DIRS) do
			local n = B.cells[ckey(c.x + d[1], c.z + d[2])]
			if n and n.state == "unk" and pred(n) then
				target = n
				return true
			end
		end
		return false
	end)
	if not path then
		return false
	end
	for i = 2, #path do
		if not F.Run or not moveTo(path[i]) then
			return false
		end
	end
	if not F.Run then
		return false
	end
	moveTo(target)
	return true
end

-- bendera: pakai argumen yang dipelajari dari PlaceFlag manual terakhir, ganti part-nya saja
local function getFlagRemote()
	local ok, r = pcall(function()
		return game:GetService("ReplicatedStorage").Events.FlagEvents.PlaceFlag
	end)
	return ok and r or nil
end
local function fireFlag(part)
	local remote = getFlagRemote()
	if not remote or not flagTemplate then
		return false
	end
	local a = table.pack(table.unpack(flagTemplate, 1, flagTemplate.n))
	a[1] = part
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
	fireFlag(cell.part)
	if waitFlag(cell.part, 0.5) then
		return true
	end
	-- mungkin server butuh jarak dekat: jalan ke cell sumber lalu coba lagi
	local from = curCell(B)
	if from and revealed(from) then
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
	fireFlag(cell.part)
	if waitFlag(cell.part, 0.7) then
		return true
	end
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

local function farmLoop()
	if F.Busy then
		return
	end
	F.Busy, F.failed = true, {}
	local notified = false
	while F.Run do
		task.wait(F.Delay)
		local char = LP.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			fstatus("menunggu respawn")
			task.wait(1)
			continue
		end
		local B = buildBoard()
		if not B or #B.list == 0 then
			fstatus("board tidak ditemukan (workspace.Flag.Parts)")
			task.wait(1)
			continue
		end
		local cur = curCell(B)
		if not cur or not revealed(cur) then
			fstatus("berdiri di block yang sudah terbuka dulu")
			task.wait(1)
			continue
		end
		local mineK, safeK, cons, reduce = solve(B)
		local did = false

		if flagTemplate then
			for key, m in pairs(mineK) do
				if not F.Run then
					break
				end
				if not F.failed[key] and not flagged(m.cell.part) then
					fstatus("menandai bom " .. key)
					if flagCell(B, m.cell, m.src) then
						did = true
					end
				end
			end
		end

		cur = curCell(B)
		if F.Run and cur and revealed(cur) and next(safeK) then
			fstatus("jalan ke block aman")
			if
				stepToward(B, cur, function(n)
					return safeK[n.key] ~= nil
				end)
			then
				did = true
				task.wait(0.25)
			end
		end

		if F.Run and not did then
			cur = curCell(B)
			if F.Guess and cur and revealed(cur) then
				local g, p = guessTarget(B, cons, reduce, mineK)
				if g then
					fstatus(("menebak %s (risiko ~%d%%)"):format(g.key, math.floor(p * 100)))
					stepToward(B, cur, function(n)
						return n == g
					end)
					task.wait(0.4)
					did = true
				end
			end
			if not did then
				fstatus(flagTemplate and "buntu / selesai: tidak ada langkah pasti" or "buntu (dan belum ada template flag)")
				if not notified then
					notified = true
					UI.CreateNoti({ Title = "Auto Farm", Desc = "Tidak ada langkah pasti. Cek board atau aktifkan tebak.", ShowTime = 4 })
				end
				task.wait(1)
			end
		else
			notified = false
		end
	end
	F.Busy = false
	fstatus("mati")
end

-- tampilkan board seperti terbaca script: # belum buka, F bendera, . kosong, angka
local function dumpBoard()
	local B = buildBoard()
	if not B or #B.list == 0 then
		push("BOARD tidak ditemukan (workspace.Flag.Parts)")
		return
	end
	local minx, maxx, minz, maxz = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs(B.list) do
		minx, maxx = math.min(minx, c.x), math.max(maxx, c.x)
		minz, maxz = math.min(minz, c.z), math.max(maxz, c.z)
	end
	push(("[%s] BOARD %d cell | x %d..%d | z %d..%d | legenda: # belum buka, F bendera, . kosong, angka, ? angka tak terbaca"):format(
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
		local k = ("%s warna %.3f,%.3f,%.3f"):format(c.state, col.R, col.G, col.B)
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
	push("  template flag: " .. (flagTemplate and ser(flagTemplate[1]) .. " ... (siap)" or "belum ada"))
end

---------------------------------------------------------------- UI
local Main = UI.CreateMain({ Title = "Minesweeper", Desc = " - Minesweeper" })
local Page = Main:CreatePage({ Page_Name = "Remote Spy", Page_Title = "Remote Spy" })

local Sec = Page.CreateSection("Remote Spy")
Sec.CreateToggle({ Title = "Aktifkan Spy", Desc = "Catat FireServer / InvokeServer", Default = true }, function(v)
	S.Spy = v
end)
Sec.CreateToggle({ Title = "Hanya dekat step", Desc = "Catat remote hanya setelah melangkah ke block", Default = false }, function(v)
	S.OnlyStep = v
end)
Sec.CreateToggle({ Title = "Deteksi step per kotak", Desc = "Step = pindah kotak grid (untuk lantai 1 part)", Default = true }, function(v)
	S.CellMode = v
end)
Sec.CreateSlider({ Title = "Ukuran kotak (stud)", Min = 1, Max = 20, Default = 5 }, function(v)
	S.CellSize = v
	lastCell = nil
end)
Sec.CreateToggle({ Title = "Catat sentuhan (TOUCH)", Desc = "Part yang disentuh avatar", Default = false }, function(v)
	S.Touch = v
end)
Sec.CreateSlider({ Title = "Jendela waktu (detik)", Min = 0.1, Max = 5, Default = 1.5, Precise = true }, function(v)
	S.Window = v
end)
Sec.CreateToggle({ Title = "Catat remote masuk (IN)", Desc = "OnClientEvent dari server", Default = false }, function(v)
	S.Incoming = v
end)

local Filter = Page.CreateSection("Filter")
Filter.CreateBox({ Title = "Nama block", Placeholder = "mis. Tile (kosong = semua)" }, function(txt)
	S.BlockFilter = tostring(txt or "")
end)
Filter.CreateBox({ Title = "Abaikan remote", Placeholder = "nama1, nama2", Default = "Patukka, AFKEvent" }, function(txt)
	S.Ignore = {}
	for n in tostring(txt or ""):gmatch("[^,]+") do
		n = n:match("^%s*(.-)%s*$"):lower()
		if n ~= "" then
			S.Ignore[n] = true
		end
	end
end)

local Info = Page.CreateSection("Status")
lblStep = Info.CreateLabel("Block: -")
lblRemote = Info.CreateLabel("Remote terakhir: -")
lblCount = Info.CreateLabel("Step: 0 | Remote tercatat: 0")

local Tools = Page.CreateSection("Alat")
Tools.CreateButton("Scan sekitar avatar", scan)
Tools.CreateButton("Daftar semua remote", dumpRemotes)

local Log = Page.CreateSection("Log")
Log.CreateButton("Copy log", function()
	if setclipboard then
		setclipboard(table.concat(logs, "\n"))
		UI.CreateNoti({ Title = "Log disalin", Desc = #logs .. " baris", ShowTime = 2 })
	else
		UI.CreateNoti({ Title = "Gagal", Desc = "Executor tidak punya setclipboard", ShowTime = 3 })
	end
end)
Log.CreateButton("Simpan log ke file", function()
	local ok = pcall(function()
		if makefolder and isfolder and not isfolder("Levian Hub") then
			makefolder("Levian Hub")
		end
		writefile("Levian Hub/minesweeper_spy.txt", table.concat(logs, "\n"))
	end)
	UI.CreateNoti({
		Title = ok and "Tersimpan" or "Gagal",
		Desc = ok and "Levian Hub/minesweeper_spy.txt" or "writefile tidak tersedia",
		ShowTime = 3,
	})
end)
Log.CreateButton("Hapus log", function()
	logs, stepCount, remoteCount = {}, 0, 0
	setLabel(lblCount, "Step: 0 | Remote tercatat: 0")
	UI.CreateNoti({ Title = "Log dihapus", ShowTime = 2 })
end)

local FarmPage = Main:CreatePage({ Page_Name = "Auto Farm", Page_Title = "Auto Farm" })
local FS = FarmPage.CreateSection("Auto Minesweeper")
lblTpl = FS.CreateLabel("Template flag: belum (taruh 1 bendera manual)")
lblFarm = FS.CreateLabel("Status: mati")
FS.CreateToggle({ Title = "Auto Farm", Desc = "Tandai bom + jalan ke block aman", Default = false }, function(v)
	F.Run = v
	if v then
		task.spawn(farmLoop)
	end
end)
FS.CreateToggle({ Title = "Tebak kalau buntu", Desc = "Risiko menginjak bom", Default = false }, function(v)
	F.Guess = v
end)
FS.CreateSlider({ Title = "Jeda loop (detik)", Min = 0.05, Max = 1, Default = 0.15, Precise = true }, function(v)
	F.Delay = v
end)
local FT = FarmPage.CreateSection("Cek")
FT.CreateButton("Dump board (cek pembacaan)", dumpBoard)

UI.CreateNoti({
	Title = "Minesweeper siap",
	Desc = hooked and "Remote Spy aktif. Jalan ke block untuk mulai." or "Hook tidak didukung executor ini.",
	ShowTime = 4,
})
