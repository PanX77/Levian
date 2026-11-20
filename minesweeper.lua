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
	CellSize = 4, -- ukuran 1 kotak (stud), sesuaikan dengan game
	Touch = false, -- catat part yang disentuh avatar
	Window = 1.5, -- detik setelah STEP yang masih dicatat
	Incoming = false,
	BlockFilter = "", -- kosong = semua part dianggap block
	Ignore = {}, -- [namaremote lowercase] = true
	Max = 500,
}
local logs = {}
local lastStep = -math.huge
local lastBlock
local stepCount, remoteCount = 0, 0
local lblStep, lblRemote, lblCount

---------------------------------------------------------------- util
local function ser(v, depth, seen)
	depth = depth or 0
	local t = typeof(v)
	if t == "string" then
		return string.format("%q", v)
	elseif t == "Instance" then
		return "<" .. v.ClassName .. ">" .. v:GetFullName()
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
		remote:GetFullName(),
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
	t[#t + 1] = ("%s [%s]"):format(part:GetFullName(), part.ClassName)
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
		local key = math.floor(p.X / S.CellSize) .. "," .. math.floor(p.Z / S.CellSize)
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
				push(("[%s] TOUCH %s [%s] CanQuery=%s"):format(os.date("%H:%M:%S"), o:GetFullName(), o.ClassName, tostring(o.CanQuery)))
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
			push(("  [%s] %s"):format(d.ClassName, d:GetFullName()))
		end
	end
	push(("  total: %d"):format(n))
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
Sec.CreateSlider({ Title = "Ukuran kotak (stud)", Min = 1, Max = 20, Default = 4 }, function(v)
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
Filter.CreateBox({ Title = "Abaikan remote", Placeholder = "nama1, nama2" }, function(txt)
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

UI.CreateNoti({
	Title = "Minesweeper siap",
	Desc = hooked and "Remote Spy aktif. Jalan ke block untuk mulai." or "Hook tidak didukung executor ini.",
	ShowTime = 4,
})
