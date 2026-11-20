-- tapsim.lua | Tap Simulator Reborn | satu file (UI + Remote Spy + Auto Click)
local BASE = "https://levianstore.my.id/"

local VIM = game:GetService("VirtualInputManager")

---------------------------------------------------------------- helper muat file
local function fetch(name)
    local ok, res = pcall(function()
        return game:HttpGet(BASE .. name .. "?v=" .. os.time())
    end)
    if not ok then return nil, "HttpGet gagal: " .. tostring(res) end
    if type(res) ~= "string" or #res < 10 then return nil, "file kosong" end
    if res:sub(1, 1) == "<" then return nil, "server mengirim HTML (file tidak ada / 404): " .. name end
    return res
end

local function loadModule(name)
    local src, err = fetch(name)
    if not src then return nil, err end
    local fn, cerr = loadstring(src)
    if not fn then return nil, "syntax error " .. name .. ": " .. tostring(cerr) end
    local ok, mod = pcall(fn)
    if not ok then return nil, "runtime error " .. name .. ": " .. tostring(mod) end
    return mod
end

local UI, uiErr = loadModule("LevianUI.lua")
if type(UI) ~= "table" or not UI.CreateMain then
    warn("[Tap Sim] Gagal memuat LevianUI.lua -> " .. tostring(uiErr or "tidak mengembalikan library"))
    return
end

local function noti(title, desc, t)
    pcall(UI.CreateNoti, { Title = title, Desc = desc, ShowTime = t or 3 })
end

---------------------------------------------------------------- remote spy (internal)
local Spy = {
    hooked = false,
    live = false,       -- log live aktif
    capturing = nil,    -- tabel hitungan saat deteksi
    last = {},          -- [path] = {remote, method, args}
    onLog = nil,
}
local IGNORE = { "ping", "heartbeat", "keepalive", "analytics", "log" }

local function ignored(name)
    name = name:lower()
    for _, w in ipairs(IGNORE) do
        if name:find(w, 1, true) then return true end
    end
    return false
end

local function argsToString(a)
    local out = {}
    for i = 1, a.n or #a do
        local v, t = a[i], typeof(a[i])
        out[i] = (t == "string") and ('"' .. v .. '"') or (t == "Instance" and v.Name or tostring(v))
    end
    return table.concat(out, ", ")
end

local function record(remote, method, args)
    local ok, isRemote = pcall(function()
        return typeof(remote) == "Instance" and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction"))
    end)
    if not (ok and isRemote) or ignored(remote.Name) then return end
    local key = remote:GetFullName()
    Spy.last[key] = { remote = remote, method = method, args = args }
    if Spy.capturing then Spy.capturing[key] = (Spy.capturing[key] or 0) + 1 end
    if Spy.live and Spy.onLog then pcall(Spy.onLog, key, args) end
end

function Spy.install()
    if Spy.hooked then return true end
    if not (hookmetamethod and getnamecallmethod) then
        return false, "Executor tidak mendukung hookmetamethod"
    end
    local wrap = newcclosure or function(f) return f end
    local old
    local ok, err = pcall(function()
        old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local m = getnamecallmethod()
            if (Spy.live or Spy.capturing) and (m == "FireServer" or m == "InvokeServer")
                and not (checkcaller and checkcaller()) then
                local a = table.pack(...)
                task.defer(record, self, m, a)
            end
            return old(self, ...)
        end))
    end)
    if not ok then return false, tostring(err) end
    Spy.hooked = true
    return true
end

function Spy.detect(seconds)
    local ok, err = Spy.install()
    if not ok then return nil, err end
    Spy.capturing = {}
    task.wait(seconds or 3)
    local res = Spy.capturing
    Spy.capturing = nil
    local bestKey, bestN = nil, 0
    for k, n in pairs(res) do
        if n > bestN then bestKey, bestN = k, n end
    end
    if not bestKey then return nil, "Tidak ada remote terdeteksi, klik lebih banyak" end
    return Spy.last[bestKey], bestKey, bestN
end

---------------------------------------------------------------- auto click
local S = { autoClick = false, delay = 0.05, clickRemote = nil }

local function viaRemote()
    local r = S.clickRemote
    if not r or not r.remote or not r.remote.Parent then return false end
    if r.method == "InvokeServer" then
        r.remote:InvokeServer(table.unpack(r.args, 1, r.args.n))
    else
        r.remote:FireServer(table.unpack(r.args, 1, r.args.n))
    end
    return true
end

local function viaScreen()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local s = cam.ViewportSize
    VIM:SendMouseButtonEvent(s.X / 2, s.Y / 2, 0, true, game, 0)
    VIM:SendMouseButtonEvent(s.X / 2, s.Y / 2, 0, false, game, 0)
end

task.spawn(function()
    while true do
        task.wait(S.delay)
        if S.autoClick then
            local ok, used = pcall(viaRemote)
            if not (ok and used) then pcall(viaScreen) end
        end
    end
end)

---------------------------------------------------------------- UI
local okUI, uiBuildErr = pcall(function()
    local Main = UI.CreateMain({ Title = "Levian Hub", Desc = " - Tap Simulator Reborn" })

    -- Page Auto Click
    local P1 = Main:CreatePage({ Page_Name = "Auto Click", Page_Title = "Auto Click" })
    local Sec1 = P1.CreateSection("Auto Click")

    Sec1.CreateToggle({
        Title = "Auto Click",
        Desc = "Pakai remote jika sudah dideteksi, jika belum klik layar",
        Default = false,
    }, function(v) S.autoClick = v end)

    Sec1.CreateSlider({
        Title = "Delay (detik)", Min = 0.01, Max = 1, Default = 0.05, Precise = true,
    }, function(v) S.delay = v end)

    local modeLabel = Sec1.CreateLabel("Mode: klik layar")

    -- Page Remote Spy
    local P2 = Main:CreatePage({ Page_Name = "Remote Spy", Page_Title = "Remote Spy" })
    local Sec2 = P2.CreateSection("Deteksi Remote Klik")
    local statusLabel = Sec2.CreateLabel("Remote klik: belum dideteksi")
    local argsLabel = Sec2.CreateLabel("Args: -")

    Sec2.CreateButton({ Title = "Deteksi Remote Klik (3 detik)" }, function()
        noti("Remote Spy", "Klik layar berkali-kali sekarang!", 3)
        statusLabel.SetText("Mendengarkan... klik layar terus")
        local info, key, count = Spy.detect(3)
        if info then
            S.clickRemote = info
            statusLabel.SetText("Remote: " .. info.remote.Name .. " (" .. count .. "x)")
            argsLabel.SetText("Args: " .. argsToString(info.args))
            modeLabel.SetText("Mode: remote " .. info.remote.Name)
            noti("Berhasil", key, 4)
        else
            statusLabel.SetText("Gagal: " .. tostring(key))
            noti("Gagal", tostring(key), 4)
        end
    end)

    Sec2.CreateButton({ Title = "Tes Kirim Remote 1x" }, function()
        local ok, used = pcall(viaRemote)
        noti("Tes Remote", (ok and used) and "Remote terkirim" or "Gagal / remote belum dipilih", 2)
    end)

    Sec2.CreateButton({ Title = "Reset ke Klik Layar" }, function()
        S.clickRemote = nil
        statusLabel.SetText("Remote klik: belum dideteksi")
        argsLabel.SetText("Args: -")
        modeLabel.SetText("Mode: klik layar")
    end)

    local Sec3 = P2.CreateSection("Log Live")
    local liveLabel = Sec3.CreateLabel("Terakhir: -")
    Spy.onLog = function(key, args)
        liveLabel.SetText(key:match("[^%.]+$") .. " (" .. argsToString(args) .. ")")
    end

    Sec3.CreateToggle({
        Title = "Remote Spy (log live)",
        Desc = "Tampilkan remote terakhir yang dikirim game",
        Default = false,
    }, function(v)
        if v then
            local ok, err = Spy.install()
            if not ok then noti("Error", tostring(err), 4) return end
        end
        Spy.live = v
    end)

    Sec3.CreateButton({ Title = "Copy Path Remote Klik" }, function()
        if S.clickRemote and setclipboard then
            local p = S.clickRemote.remote:GetFullName()
            setclipboard(p)
            noti("Disalin", p, 3)
        else
            noti("Gagal", "Remote belum dipilih / setclipboard tidak ada", 3)
        end
    end)
end)

if not okUI then
    warn("[Tap Sim] Error saat membuat UI: " .. tostring(uiBuildErr))
    return
end

noti("Levian Hub", "Tap Simulator Reborn siap", 3)
