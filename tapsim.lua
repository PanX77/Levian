-- tapsim.lua | Tap Simulator Reborn | memakai LevianUI + Remote Spy
local BASE = "https://levianstore.my.id/"

local function load(name)
    return loadstring(game:HttpGet(BASE .. name))()
end

local VIM = game:GetService("VirtualInputManager")
local Camera = workspace.CurrentCamera

local UI  = load("LevianUI.lua")
local Spy = load("remotespy.lua")

local S = {
    autoClick = false,
    delay = 0.05,
    clickRemote = nil, -- {remote=, method=, args=}
}

---------------------------------------------------------------- fungsi klik
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
    local size = Camera.ViewportSize
    local x, y = size.X / 2, size.Y / 2
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
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
local Main = UI.CreateMain({ Title = "Levian Hub", Desc = " - Tap Simulator Reborn" })

-- Page 1: Auto Click
local PageClick = Main:CreatePage({ Page_Name = "Auto Click", Page_Title = "Auto Click" })
local SecClick = PageClick.CreateSection("Auto Click")

SecClick.CreateToggle({
    Title = "Auto Click",
    Desc = "Pakai remote bila sudah dideteksi, jika belum klik layar",
    Default = false,
}, function(v)
    S.autoClick = v
end)

SecClick.CreateSlider({
    Title = "Delay (detik)",
    Min = 0.01, Max = 1, Default = 0.05, Precise = true,
}, function(v)
    S.delay = v
end)

local modeLabel = SecClick.CreateLabel("Mode: klik layar (remote belum dipilih)")

-- Page 2: Remote Spy
local PageSpy = Main:CreatePage({ Page_Name = "Remote Spy", Page_Title = "Remote Spy" })
local SecDetect = PageSpy.CreateSection("Deteksi Remote Klik")

local statusLabel = SecDetect.CreateLabel("Remote klik: belum dideteksi")
local argsLabel = SecDetect.CreateLabel("Args: -")

SecDetect.CreateButton({ Title = "Deteksi Remote Klik (3 detik)" }, function()
    UI.CreateNoti({ Title = "Remote Spy", Desc = "Klik layar berkali-kali sekarang!", ShowTime = 3 })
    statusLabel.SetText("Mendengarkan... klik layar terus")
    local info, key, count = Spy:DetectClickRemote(3)
    if info then
        S.clickRemote = info
        statusLabel.SetText("Remote: " .. info.remote.Name .. " (" .. count .. "x)")
        argsLabel.SetText("Args: " .. Spy.ArgsToString(info.args))
        modeLabel.SetText("Mode: remote " .. info.remote.Name)
        UI.CreateNoti({ Title = "Berhasil", Desc = key, ShowTime = 4 })
    else
        statusLabel.SetText("Gagal: " .. tostring(key))
        UI.CreateNoti({ Title = "Gagal", Desc = tostring(key), ShowTime = 4 })
    end
end)

SecDetect.CreateButton({ Title = "Tes Kirim Remote 1x" }, function()
    local ok, used = pcall(viaRemote)
    UI.CreateNoti({
        Title = "Tes Remote",
        Desc = (ok and used) and "Remote terkirim" or "Gagal / remote belum dipilih",
        ShowTime = 2,
    })
end)

SecDetect.CreateButton({ Title = "Reset ke Klik Layar" }, function()
    S.clickRemote = nil
    statusLabel.SetText("Remote klik: belum dideteksi")
    argsLabel.SetText("Args: -")
    modeLabel.SetText("Mode: klik layar (remote belum dipilih)")
end)

local SecLive = PageSpy.CreateSection("Log Live")
local liveLabel = SecLive.CreateLabel("Terakhir: -")

SecLive.CreateToggle({
    Title = "Remote Spy (log live)",
    Desc = "Tampilkan remote terakhir yang dikirim game",
    Default = false,
}, function(v)
    if v then
        local ok, err = Spy:Start()
        if not ok then
            UI.CreateNoti({ Title = "Error", Desc = tostring(err), ShowTime = 4 })
        end
    else
        Spy:Stop()
    end
end)

SecLive.CreateButton({ Title = "Copy Path Remote Klik" }, function()
    if S.clickRemote and setclipboard then
        setclipboard(S.clickRemote.remote:GetFullName())
        UI.CreateNoti({ Title = "Disalin", Desc = S.clickRemote.remote:GetFullName(), ShowTime = 3 })
    else
        UI.CreateNoti({ Title = "Gagal", Desc = "Remote belum dipilih", ShowTime = 3 })
    end
end)

Spy:OnLog(function(key, method, args)
    liveLabel.SetText(key:match("[^%.]+$") .. " (" .. Spy.ArgsToString(args) .. ")")
end)

UI.CreateNoti({ Title = "Levian Hub", Desc = "Tap Simulator Reborn siap", ShowTime = 3 })
