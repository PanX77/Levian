--[[
	LevianUI - library UI sederhana untuk Roblox (tanpa akses web)
	Isi: Window, Page(tab), Section, Toggle(saklar), Button, Label, Slider,
	     Dropdown(+search/multi), Box(input), Bind(keybind), Notifikasi.

	Contoh pakai:
		local UI   = loadstring(readfile("LevianUI.lua"))()
		local Main = UI.CreateMain({ Title = "Blox Fruit", Desc = " - Blox Fruit" })
		local Page = Main:CreatePage({ Page_Name = "Farming", Page_Title = "Farming" })
		local Sec  = Page.CreateSection("Auto Farm")
		Sec.CreateToggle({ Title = "Auto Farm", Desc = "Farm otomatis", Default = false }, function(v) print(v) end)
		Sec.CreateSlider({ Title = "Delay", Min = 0, Max = 5, Default = 1, Precise = true }, function(v) print(v) end)
		Sec.CreateDropdown({ Title = "Metode", List = {"A","B"}, Search = true }, function(v) print(v) end)
		UI.CreateNoti({ Title = "Halo", Desc = "UI siap", ShowTime = 3 })

	Semua method boleh dipanggil dengan titik (obj.CreateX(...)) atau titik dua (obj:CreateX(...)).
]]

local Library = {}

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Theme = {
	Bg = Color3.fromRGB(22, 22, 27),
	Panel = Color3.fromRGB(30, 30, 37),
	Element = Color3.fromRGB(40, 40, 49),
	Accent = Color3.fromRGB(255, 204, 0),
	Text = Color3.fromRGB(235, 235, 235),
	SubText = Color3.fromRGB(150, 150, 162),
	Off = Color3.fromRGB(72, 72, 84),
}

Library.GuiName = "Levian Hub GUI" -- nama ScreenGui utama (dipakai script untuk Toggle GUI)

---------------------------------------------------------------- helper
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function corner(o, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o)
end

local function tween(o, props, t)
	TweenService:Create(o, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

-- buang argumen pertama jika dipanggil dengan gaya titik dua (obj:Method(...))
local function args(self, ...)
	local first = ...
	if first == self then
		return select(2, ...)
	end
	return ...
end

local function fire(cb, ...)
	if type(cb) ~= "function" then
		return
	end
	local n, a = select("#", ...), { ... }
	task.spawn(function()
		local ok, err = pcall(cb, table.unpack(a, 1, n))
		if not ok then
			warn("[LevianUI] callback error:", err)
		end
	end)
end

local function norm(spec)
	if type(spec) == "string" then
		return { Title = spec }
	end
	return spec or {}
end

local function label(parent, text, size, color, bold)
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Text = tostring(text or ""),
		TextSize = size or 14,
		Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		TextColor3 = color or Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, parent)
end

local function makeDraggable(handle, target)
	local dragging, dragStart, startPos = false, nil, nil
	handle.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, i.Position, target.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if
			dragging
			and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch)
		then
			local d = i.Position - dragStart
			target.Position =
				UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

local function parentGui(gui)
	local ok = pcall(function()
		gui.Parent = game:GetService("CoreGui")
	end)
	if ok and gui.Parent then
		return
	end
	ok = pcall(function()
		gui.Parent = gethui()
	end)
	if ok and gui.Parent then
		return
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- objek yang tidak error kalau dipanggil method yang tidak ada
local function safeObj(t)
	return setmetatable(t, {
		__index = function()
			return function() end
		end,
	})
end

---------------------------------------------------------------- notifikasi
local notiHolder
local function ensureNotiHolder()
	if notiHolder and notiHolder.Parent then
		return notiHolder
	end
	local gui = new("ScreenGui", { Name = "LevianUI Noti", ResetOnSpawn = false, DisplayOrder = 999 })
	parentGui(gui)
	notiHolder = new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.new(0, 270, 1, -24),
	}, gui)
	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, notiHolder)
	return notiHolder
end

function Library.CreateNoti(...)
	local spec = norm(args(Library, ...))
	local holder = ensureNotiHolder()
	local f = new("Frame", {
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 260, 0, 66),
	}, holder)
	corner(f, 8)
	local bar = new("Frame", { BackgroundColor3 = Theme.Accent, Size = UDim2.new(0, 3, 1, -14), Position = UDim2.new(0, 6, 0, 7), BackgroundTransparency = 1 }, f)
	corner(bar, 2)
	local t = label(f, spec.Title or "Notifikasi", 14, Theme.Text, true)
	t.Position, t.Size, t.TextTransparency = UDim2.new(0, 18, 0, 8), UDim2.new(1, -26, 0, 18), 1
	local d = label(f, spec.Desc or spec.Content or "", 12, Theme.SubText)
	d.Position, d.Size, d.TextTransparency = UDim2.new(0, 18, 0, 28), UDim2.new(1, -26, 0, 34), 1
	d.TextWrapped, d.TextTruncate = true, Enum.TextTruncate.None

	tween(f, { BackgroundTransparency = 0.05 }, 0.25)
	tween(bar, { BackgroundTransparency = 0 }, 0.25)
	tween(t, { TextTransparency = 0 }, 0.25)
	tween(d, { TextTransparency = 0 }, 0.25)

	task.delay(tonumber(spec.ShowTime) or 4, function()
		if not f.Parent then
			return
		end
		tween(f, { BackgroundTransparency = 1 }, 0.3)
		tween(bar, { BackgroundTransparency = 1 }, 0.3)
		tween(t, { TextTransparency = 1 }, 0.3)
		tween(d, { TextTransparency = 1 }, 0.3)
		task.wait(0.35)
		f:Destroy()
	end)
end
Library.CreateNotification = Library.CreateNoti

---------------------------------------------------------------- keybind global
local function addBind(spec, cb)
	spec = norm(spec)
	local key = spec.Key or spec.Default or Enum.KeyCode.RightControl
	local listening = false
	local obj
	obj = safeObj({
		SetKey = function(...)
			local k = args(obj, ...)
			if k then
				key = k
			end
		end,
		GetKey = function()
			return key
		end,
	})
	UserInputService.InputBegan:Connect(function(i, processed)
		if listening then
			return
		end
		if not processed and i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == key then
			fire(cb, key)
		end
	end)
	obj._startListen = function(onDone)
		listening = true
		local c
		c = UserInputService.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Keyboard then
				key = i.KeyCode
				listening = false
				c:Disconnect()
				if onDone then
					onDone(key)
				end
			end
		end)
	end
	return obj
end

function Library.CreateBind(...)
	return addBind(args(Library, ...))
end

---------------------------------------------------------------- window
function Library.CreateMain(...)
	local spec = norm(args(Library, ...))

	-- hapus UI lama kalau ada
	pcall(function()
		for _, n in ipairs({ Library.GuiName, "LevianUI Toggle", "Nousigi Hub GUI", "BananaUI Toggle" }) do -- nama lama ikut dibersihkan
			local old = game:GetService("CoreGui"):FindFirstChild(n)
			if old then
				old:Destroy()
			end
		end
	end)

	local gui = new("ScreenGui", { Name = Library.GuiName, ResetOnSpawn = false, DisplayOrder = 998 })
	parentGui(gui)
	getgenv().UIToggled = true

	local win = new("Frame", {
		BackgroundColor3 = Theme.Bg,
		Size = UDim2.new(0, 500, 0, 320),
		Position = UDim2.new(0.5, -250, 0.5, -160),
		ClipsDescendants = true,
	}, gui)
	corner(win, 10)
	new("UIStroke", { Color = Theme.Accent, Transparency = 0.6, Thickness = 1 }, win)

	-- title bar
	local bar = new("Frame", { BackgroundColor3 = Theme.Panel, Size = UDim2.new(1, 0, 0, 36) }, win)
	corner(bar, 10)
	new("Frame", { BackgroundColor3 = Theme.Panel, Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10), BorderSizePixel = 0 }, bar)
	local title = label(bar, (spec.Title or "LevianUI") .. (spec.Desc or ""), 15, Theme.Accent, true)
	title.Position, title.Size = UDim2.new(0, 12, 0, 0), UDim2.new(1, -90, 1, 0)

	local function barBtn(txt, x)
		local b = new("TextButton", {
			BackgroundColor3 = Theme.Element,
			Text = txt,
			TextColor3 = Theme.Text,
			Font = Enum.Font.GothamBold,
			TextSize = 16,
			Size = UDim2.new(0, 26, 0, 22),
			Position = UDim2.new(1, x, 0.5, -11),
			AutoButtonColor = true,
		}, bar)
		corner(b, 6)
		return b
	end
	local minBtn = barBtn("-", -34) -- tombol close dihapus: di Android menutup seluruh UI termasuk logo
	makeDraggable(bar, win)

	-- sidebar + isi
	local side = new("ScrollingFrame", {
		BackgroundColor3 = Theme.Panel,
		Position = UDim2.new(0, 8, 0, 44),
		Size = UDim2.new(0, 130, 1, -52),
		ScrollBarThickness = 2,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
	}, win)
	corner(side, 8)
	new("UIListLayout", { Padding = UDim.new(0, 4) }, side)
	new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, side)

	local content = new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 146, 0, 44),
		Size = UDim2.new(1, -154, 1, -52),
	}, win)

	-- tombol melayang untuk buka/tutup (cocok untuk HP)
	local tgui = new("ScreenGui", { Name = "LevianUI Toggle", ResetOnSpawn = false, DisplayOrder = 999 })
	parentGui(tgui)
	local fab = new("TextButton", {
		BackgroundColor3 = Theme.Accent,
		Text = "X",
		TextColor3 = Color3.new(0, 0, 0),
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		Size = UDim2.new(0, 40, 0, 40),
		Position = UDim2.new(0, 10, 0.4, 0),
	}, tgui)
	corner(fab, 20)
	makeDraggable(fab, fab)
	local function setVisible(v)
		getgenv().UIToggled = v
		win.Visible = v
	end
	fab.MouseButton1Click:Connect(function()
		setVisible(not win.Visible)
	end)
	minBtn.MouseButton1Click:Connect(function()
		setVisible(false)
	end)

	local Main = {}
	local pages, activePage = {}, nil

	local function selectPage(p)
		for _, q in ipairs(pages) do
			q.frame.Visible = (q == p)
			tween(q.btn, { BackgroundColor3 = (q == p) and Theme.Accent or Theme.Element }, 0.12)
			q.btn.TextColor3 = (q == p) and Color3.new(0, 0, 0) or Theme.Text
		end
		activePage = p
	end

	---------------------------------------------------------------- page
	function Main.CreatePage(...)
		local ps = norm(args(Main, ...))
		local name = ps.Page_Title or ps.Page_Name or ps.Title or ps.Name or ("Page " .. (#pages + 1))

		local btn = new("TextButton", {
			BackgroundColor3 = Theme.Element,
			Size = UDim2.new(1, 0, 0, 30),
			Text = tostring(name),
			TextColor3 = Theme.Text,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = #pages + 1,
		}, side)
		corner(btn, 6)

		local frame = new("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 3,
			BorderSizePixel = 0,
			Visible = false,
		}, content)
		new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
		new("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }, frame)

		local Page = { frame = frame, btn = btn }
		pages[#pages + 1] = Page
		btn.MouseButton1Click:Connect(function()
			selectPage(Page)
		end)
		if not activePage then
			selectPage(Page)
		end

		local sectionCount = 0

		------------------------------------------------------------ section
		function Page.CreateSection(...)
			local ss = norm(args(Page, ...))
			sectionCount += 1
			local box = new("Frame", {
				BackgroundColor3 = Theme.Panel,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = sectionCount,
			}, frame)
			corner(box, 8)
			new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, box)
			new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)

			local head = label(box, ss.Title or ss.Name or "Section", 14, Theme.Accent, true)
			head.Size, head.LayoutOrder = UDim2.new(1, 0, 0, 20), 0

			local order = 0
			local Section = {}

			local function element(h)
				order += 1
				local r = new("Frame", {
					BackgroundColor3 = Theme.Element,
					Size = UDim2.new(1, 0, 0, h),
					LayoutOrder = order,
				}, box)
				corner(r, 6)
				return r
			end

			---------------------------------------------------- toggle (saklar)
			function Section.CreateToggle(...)
				local sp, cb = args(Section, ...)
				sp = norm(sp)
				local hasDesc = sp.Desc ~= nil and sp.Desc ~= ""
				local row = element(hasDesc and 48 or 36)
				local t = label(row, sp.Title or "Toggle", 14)
				t.Position, t.Size = UDim2.new(0, 10, 0, hasDesc and 5 or 0), UDim2.new(1, -64, 0, hasDesc and 20 or 36)
				if hasDesc then
					local d = label(row, sp.Desc, 11, Theme.SubText)
					d.Position, d.Size = UDim2.new(0, 10, 0, 25), UDim2.new(1, -64, 0, 16)
				end
				local track = new("Frame", {
					BackgroundColor3 = Theme.Off,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.new(0, 40, 0, 20),
				}, row)
				corner(track, 10)
				local knob = new("Frame", {
					BackgroundColor3 = Color3.new(1, 1, 1),
					Size = UDim2.new(0, 16, 0, 16),
					Position = UDim2.new(0, 2, 0.5, -8),
				}, track)
				corner(knob, 8)
				local hit = new("TextButton", { BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 1, 0) }, row)

				local value = false
				local obj
				local function render(v)
					tween(track, { BackgroundColor3 = v and Theme.Accent or Theme.Off })
					tween(knob, { Position = v and UDim2.new(0, 22, 0.5, -8) or UDim2.new(0, 2, 0.5, -8) })
				end
				obj = safeObj({
					SetValue = function(...)
						local v = args(obj, ...)
						v = v and true or false
						if v == value then
							return
						end
						value = v
						render(v)
						fire(cb, v)
					end,
					GetValue = function()
						return value
					end,
				})
				obj.Set, obj.Toggle = obj.SetValue, function()
					obj.SetValue(not value)
				end
				hit.MouseButton1Click:Connect(function()
					obj.SetValue(not value)
				end)
				if sp.Default == true then
					value = true
					render(true)
					fire(cb, true)
				end
				return obj
			end

			---------------------------------------------------- button
			function Section.CreateButton(...)
				local sp, cb = args(Section, ...)
				sp = norm(sp)
				local row = element(34)
				local b = new("TextButton", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					Text = tostring(sp.Title or "Button"),
					TextColor3 = Theme.Text,
					Font = Enum.Font.GothamMedium,
					TextSize = 14,
				}, row)
				b.MouseButton1Click:Connect(function()
					tween(row, { BackgroundColor3 = Theme.Accent }, 0.08)
					b.TextColor3 = Color3.new(0, 0, 0)
					task.delay(0.12, function()
						tween(row, { BackgroundColor3 = Theme.Element }, 0.15)
						b.TextColor3 = Theme.Text
					end)
					fire(cb)
				end)
				local obj
				obj = safeObj({
					SetTitle = function(...)
						b.Text = tostring((args(obj, ...)))
					end,
				})
				return obj
			end

			---------------------------------------------------- label
			function Section.CreateLabel(...)
				local sp = norm((args(Section, ...)))
				local row = element(30)
				local l = label(row, sp.Title or sp.Text or "", 13, Theme.SubText)
				l.Position, l.Size = UDim2.new(0, 10, 0, 0), UDim2.new(1, -20, 1, 0)
				local obj
				local function set(...)
					local v = args(obj, ...)
					if type(v) == "table" then
						v = v.Title or v.Text or ""
					end
					l.Text = tostring(v or "")
				end
				obj = safeObj({
					GetText = function()
						return l.Text
					end,
				})
				obj.SetText, obj.Set, obj.SetTitle, obj.SetValue, obj.SetDesc = set, set, set, set, set
				return obj
			end

			---------------------------------------------------- slider
			function Section.CreateSlider(...)
				local sp, cb = args(Section, ...)
				sp = norm(sp)
				local min, max = tonumber(sp.Min) or 0, tonumber(sp.Max) or 100
				if max <= min then
					max = min + 1
				end
				local row = element(50)
				local t = label(row, sp.Title or "Slider", 14)
				t.Position, t.Size = UDim2.new(0, 10, 0, 4), UDim2.new(1, -90, 0, 20)
				local vl = label(row, "", 13, Theme.Accent, true)
				vl.Position, vl.Size, vl.TextXAlignment = UDim2.new(1, -80, 0, 4), UDim2.new(0, 70, 0, 20), Enum.TextXAlignment.Right
				local rail = new("Frame", { BackgroundColor3 = Theme.Off, Position = UDim2.new(0, 10, 0, 34), Size = UDim2.new(1, -20, 0, 6) }, row)
				corner(rail, 3)
				local fill = new("Frame", { BackgroundColor3 = Theme.Accent, Size = UDim2.new(0, 0, 1, 0) }, rail)
				corner(fill, 3)

				local value = min
				local obj
				local function clampRound(v)
					v = math.clamp(tonumber(v) or min, min, max)
					if sp.Precise then
						return math.floor(v * 100 + 0.5) / 100
					end
					return math.floor(v + 0.5)
				end
				local function render()
					fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
					vl.Text = tostring(value)
				end
				local function set(v, silent)
					v = clampRound(v)
					if v == value and silent == nil then
						return
					end
					value = v
					render()
					if not silent then
						fire(cb, value)
					end
				end
				obj = safeObj({
					SetValue = function(...)
						set((args(obj, ...)))
					end,
					GetValue = function()
						return value
					end,
				})
				obj.Set = obj.SetValue

				local dragging = false
				local function fromX(x)
					local a = (x - rail.AbsolutePosition.X) / math.max(rail.AbsoluteSize.X, 1)
					set(min + math.clamp(a, 0, 1) * (max - min))
				end
				rail.InputBegan:Connect(function(i)
					if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
						dragging = true
						fromX(i.Position.X)
					end
				end)
				UserInputService.InputEnded:Connect(function(i)
					if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
						dragging = false
					end
				end)
				UserInputService.InputChanged:Connect(function(i)
					if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
						fromX(i.Position.X)
					end
				end)

				value = clampRound(sp.Default or min)
				render()
				if sp.Default ~= nil then
					fire(cb, value)
				end
				return obj
			end

			---------------------------------------------------- dropdown
			function Section.CreateDropdown(...)
				local sp, cb = args(Section, ...)
				sp = norm(sp)
				local list = {}
				for _, v in ipairs(sp.List or sp.Options or {}) do
					list[#list + 1] = v
				end
				local multi = sp.Multi == true
				local selected = multi and {} or nil
				local single = nil
				local open = false

				order += 1
				local wrap = new("Frame", {
					BackgroundColor3 = Theme.Element,
					Size = UDim2.new(1, 0, 0, 36),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = order,
				}, box)
				corner(wrap, 6)
				new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, wrap)

				local head = new("TextButton", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 36),
					Text = "",
					LayoutOrder = 1,
				}, wrap)
				local t = label(head, sp.Title or "Dropdown", 14)
				t.Position, t.Size = UDim2.new(0, 10, 0, 0), UDim2.new(0.5, -10, 1, 0)
				local vl = label(head, "-", 13, Theme.Accent)
				vl.Position, vl.Size, vl.TextXAlignment = UDim2.new(0.5, 0, 0, 0), UDim2.new(0.5, -28, 1, 0), Enum.TextXAlignment.Right
				local arrow = label(head, "v", 12, Theme.SubText, true)
				arrow.Position, arrow.Size, arrow.TextXAlignment = UDim2.new(1, -22, 0, 0), UDim2.new(0, 16, 1, 0), Enum.TextXAlignment.Center

				local panel = new("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Visible = false,
					LayoutOrder = 2,
				}, wrap)
				new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, panel)
				new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, panel)

				local search
				if sp.Search then
					search = new("TextBox", {
						BackgroundColor3 = Theme.Panel,
						Size = UDim2.new(1, 0, 0, 26),
						PlaceholderText = "Cari...",
						Text = "",
						TextColor3 = Theme.Text,
						PlaceholderColor3 = Theme.SubText,
						Font = Enum.Font.Gotham,
						TextSize = 13,
						ClearTextOnFocus = false,
						LayoutOrder = 1,
					}, panel)
					corner(search, 5)
				end
				local items = new("ScrollingFrame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 120),
					CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollBarThickness = 3,
					BorderSizePixel = 0,
					LayoutOrder = 2,
				}, panel)
				new("UIListLayout", { Padding = UDim.new(0, 3) }, items)

				local obj
				local function summary()
					if multi then
						local n = {}
						for k, v in pairs(selected) do
							if v then
								n[#n + 1] = tostring(k)
							end
						end
						table.sort(n)
						return #n > 0 and table.concat(n, ", ") or "-"
					end
					return single ~= nil and tostring(single) or "-"
				end

				local function rebuild()
					for _, c in ipairs(items:GetChildren()) do
						if c:IsA("TextButton") then
							c:Destroy()
						end
					end
					local q = search and search.Text:lower() or ""
					for _, v in ipairs(list) do
						local s = tostring(v)
						if q == "" or s:lower():find(q, 1, true) then
							local on = multi and selected[s] or (not multi and single == v)
							local b = new("TextButton", {
								BackgroundColor3 = on and Theme.Accent or Theme.Panel,
								Size = UDim2.new(1, -4, 0, 26),
								Text = s,
								TextColor3 = on and Color3.new(0, 0, 0) or Theme.Text,
								Font = Enum.Font.Gotham,
								TextSize = 13,
							}, items)
							corner(b, 5)
							b.MouseButton1Click:Connect(function()
								if multi then
									selected[s] = not selected[s] or nil
									vl.Text = summary()
									fire(cb, selected)
									rebuild()
								else
									single = v
									vl.Text = summary()
									fire(cb, v)
									open = false
									panel.Visible = false
									arrow.Text = "v"
									rebuild()
								end
							end)
						end
					end
				end
				if search then
					search:GetPropertyChangedSignal("Text"):Connect(rebuild)
				end
				head.MouseButton1Click:Connect(function()
					open = not open
					panel.Visible = open
					arrow.Text = open and "^" or "v"
					if open then
						rebuild()
					end
				end)

				obj = safeObj({
					SetValue = function(...)
						local v = args(obj, ...)
						if multi then
							selected = {}
							for k, x in pairs(type(v) == "table" and v or {}) do
								if type(k) == "number" then
									selected[tostring(x)] = true
								elseif x then
									selected[tostring(k)] = true
								end
							end
							fire(cb, selected)
						else
							single = v
							if v ~= nil then
								fire(cb, v)
							end
						end
						vl.Text = summary()
					end,
					GetValue = function()
						return multi and selected or single
					end,
					Refresh = function(...)
						local l = args(obj, ...)
						list = {}
						for _, v in ipairs(l or {}) do
							list[#list + 1] = v
						end
						if open then
							rebuild()
						end
					end,
				})
				obj.Set, obj.SetList, obj.SetOptions = obj.SetValue, obj.Refresh, obj.Refresh

				if sp.Default ~= nil then
					obj.SetValue(sp.Default)
				end
				return obj
			end

			---------------------------------------------------- box (input)
			function Section.CreateBox(...)
				local sp, cb = args(Section, ...)
				sp = norm(sp)
				local row = element(36)
				local t = label(row, sp.Title or "Input", 14)
				t.Position, t.Size = UDim2.new(0, 10, 0, 0), UDim2.new(0.5, -14, 1, 0)
				local tb = new("TextBox", {
					BackgroundColor3 = Theme.Panel,
					Position = UDim2.new(0.5, 0, 0.5, -13),
					Size = UDim2.new(0.5, -8, 0, 26),
					Text = sp.Default ~= nil and tostring(sp.Default) or "",
					PlaceholderText = tostring(sp.Placeholder or ""),
					PlaceholderColor3 = Theme.SubText,
					TextColor3 = Theme.Text,
					Font = Enum.Font.Gotham,
					TextSize = 13,
					ClearTextOnFocus = false,
				}, row)
				corner(tb, 5)
				local function out()
					if sp.Number then
						return tonumber(tb.Text)
					end
					return tb.Text
				end
				tb.FocusLost:Connect(function()
					fire(cb, out())
				end)
				local obj
				obj = safeObj({
					SetValue = function(...)
						tb.Text = tostring((args(obj, ...)) or "")
						fire(cb, out())
					end,
					GetValue = out,
				})
				obj.Set = obj.SetValue
				if sp.Default ~= nil and sp.Default ~= "" then
					fire(cb, out())
				end
				return obj
			end

			---------------------------------------------------- bind
			function Section.CreateBind(...)
				local sp, cb = args(Section, ...)
				sp = norm(sp)
				local row = element(36)
				local t = label(row, sp.Title or "Keybind", 14)
				t.Position, t.Size = UDim2.new(0, 10, 0, 0), UDim2.new(1, -110, 1, 0)
				local b = new("TextButton", {
					BackgroundColor3 = Theme.Panel,
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.new(0, 90, 0, 26),
					TextColor3 = Theme.Accent,
					Font = Enum.Font.GothamMedium,
					TextSize = 12,
					Text = "",
				}, row)
				corner(b, 5)
				local o = addBind(sp, cb)
				b.Text = tostring(o.GetKey().Name)
				b.MouseButton1Click:Connect(function()
					b.Text = "..."
					o._startListen(function(k)
						b.Text = k.Name
					end)
				end)
				return o
			end

			return safeObj(Section)
		end

		-- elemen yang dibuat langsung di Page masuk ke section default
		local default
		local function ds()
			default = default or Page.CreateSection("")
			return default
		end
		for _, name in ipairs({ "CreateToggle", "CreateButton", "CreateLabel", "CreateSlider", "CreateDropdown", "CreateBox", "CreateBind" }) do
			Page[name] = function(...)
				local a = ...
				local rest = (a == Page) and { select(2, ...) } or { ... }
				return ds()[name](table.unpack(rest, 1, 2))
			end
		end

		return safeObj(Page)
	end

	Main.CreateBind = function(...)
		return addBind(args(Main, ...))
	end
	Main.CreateNoti = Library.CreateNoti
	Main.CreateNotification = Library.CreateNoti
	Main.SetVisible = function(...)
		setVisible(args(Main, ...) and true or false)
	end
	Main.Destroy = function()
		gui:Destroy()
		tgui:Destroy()
	end

	return safeObj(Main)
end

return Library
