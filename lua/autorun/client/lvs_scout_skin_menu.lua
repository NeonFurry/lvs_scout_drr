-- Меню оператора в стиле интерфейса Crysis 1 (нанокостюм): расцветка, щит, ночь, автомодуль

local frame
local colorBtn, shieldBtn, nightBtn, autoBtn, autoAllBtn
local night = false

surface.CreateFont("LvsCrysisTitle", { font = "Roboto", size = 20, weight = 700, extended = true })
surface.CreateFont("LvsCrysisText", { font = "Roboto", size = 15, weight = 500, extended = true })
surface.CreateFont("LvsCrysisSmall", { font = "Roboto", size = 12, weight = 500, extended = true })

-- Эмодзи-шестерёнка: рисуется системным символом, а не вектором
surface.CreateFont("LvsGear", {
	font = "Segoe UI Symbol",
	size = 26,
	weight = 500,
	antialias = true,
})

local ACCENT      = Color(110, 235, 215)
local ACCENT_DIM  = Color(52, 122, 118)
local WARN        = Color(255, 178, 84)
local CE_PANEL    = Color(7, 15, 17, 255)
local CE_HEAD     = Color(9, 21, 23, 255)
local CUT = 20

-- Общий фон Ceph: угловой срез, диагональная штриховка, ромбы, скан-линии
local function cephBackdrop(w, h, cut)
	surface.SetDrawColor(CE_PANEL)
	surface.DrawPoly({
		{ x = 0, y = cut }, { x = cut, y = 0 },
		{ x = w, y = 0 }, { x = w, y = h - cut },
		{ x = w - cut, y = h }, { x = 0, y = h },
	})

	surface.SetDrawColor(110, 235, 215, 10)
	for x = -h, w, 14 do surface.DrawLine(x, h, x + h, 0) end

	surface.SetDrawColor(110, 235, 215, 16)
	for y = 20, h - 10, 46 do
		for x = 20, w - 10, 46 do surface.DrawRect(x, y, 2, 2) end
	end

	surface.SetDrawColor(0, 0, 0, 26)
	for y = 0, h, 3 do surface.DrawRect(0, y, w, 1) end

	surface.SetDrawColor(110, 235, 215, 150)
	surface.DrawLine(0, cut, cut, 0)
	surface.DrawLine(cut, 0, w - 1, 0)
	surface.DrawLine(w - 1, 0, w - 1, h - cut)
	surface.DrawLine(w - 1, h - cut, w - cut, h - 1)
	surface.DrawLine(w - cut, h - 1, 0, h - 1)
	surface.DrawLine(0, h - 1, 0, cut)

	surface.SetDrawColor(110, 235, 215, 40)
	surface.DrawLine(6, cut + 2, 6, h - 7)
	surface.DrawLine(6, h - 7, w - 7, h - 7)
	surface.DrawLine(w - 7, cut, w - 7, h - 7)
	surface.DrawLine(cut, 6, w - 8, 6)
end
-- Дружественные NPC: список классов, которым дрон не стреляет
local friendsCache = { }
local friendScroll, friendEntry

-- Общий набор классов-друзей: им же пользуются сканер и подсветка
LvsFriendSet = LvsFriendSet or { }

function LvsIsFriendClass(cls)
	if not cls then return false end
	return LvsFriendSet[string.lower(cls)] == true
end
local rebuildFriends

local function requestFriends()
	net.Start("lvs_scout_friends_get")
	net.SendToServer()
end

-- Игрок по нику (если он на сервере) хранится как @STEAMID
local function findPlayer(name)
	name = string.lower(name)

	for _, p in ipairs(player.GetAll()) do
		if IsValid(p) and string.lower(p:Nick()) == name then return p end
	end

	for _, p in ipairs(player.GetAll()) do
		if IsValid(p) and string.find(string.lower(p:Nick()), name, 1, true) then return p end
	end
end

local function addFriend(cls)
	cls = string.Trim(cls or "")
	if cls == "" then return end

	local p = findPlayer(cls)
	local entry = IsValid(p) and ("@" .. p:SteamID()) or cls

	net.Start("lvs_scout_friends_set")
	net.WriteBool(true)
	net.WriteString(entry)
	net.SendToServer()

	timer.Simple(0.15, requestFriends)
end

local function removeFriend(cls)
	net.Start("lvs_scout_friends_set")
	net.WriteBool(false)
	net.WriteString(cls)
	net.SendToServer()

	timer.Simple(0.15, requestFriends)
end

local function sendSkin(index)
	net.Start("lvs_scout_set_skin")
	net.WriteUInt(index, 8)
	net.SendToServer()
end

local function sendShield(on)
	net.Start("lvs_scout_set_shield")
	net.WriteBool(on)
	net.SendToServer()
end

local function sendAuto(on)
	net.Start("lvs_scout_auto")
	net.WriteBool(on)
	net.SendToServer()
end

local function sendNight(toggle)
	net.Start("lvs_scout_gw_night")
	net.WriteBool(toggle)
	net.SendToServer()
end

local function pilotDrone()
	local drone = LocalPlayer():GetNWEntity("DronesRewriteDrone")
	if IsValid(drone) and drone:GetClass() == "lvs_scout_drr" then return drone end
end

local function setState(btn, text, on)
	if not (btn and btn:IsValid()) then return end

	btn.LvsText = text
	btn.LvsOn = on
end

local function refresh()
	if not (frame and frame:IsValid()) then return end

	local drone = pilotDrone()
	local skin = drone and drone:GetNWInt("LvsSkin", 0) == 1

	setState(colorBtn, skin and "РАСЦВЕТКА: КРАСНАЯ" or "РАСЦВЕТКА: ОБЫЧНАЯ", skin)

	local shield = drone and drone:GetNWBool("hasModuleShield")
	local left = drone and (drone:GetNWFloat("LvsShieldRestoreAt", 0) - CurTime()) or 0

	if left > 0 and not shield then
		setState(shieldBtn, string.format("ЩИТ: ПЕРЕЗАГРУЗКА %d с", math.ceil(left)), false)
	else
		setState(shieldBtn, shield and "ЩИТ: ВКЛЮЧЁН" or "ЩИТ: ВЫКЛЮЧЕН", shield)
	end

	setState(nightBtn, night and "НОЧЬ: ВКЛЮЧЕНА" or "НОЧЬ: ВЫКЛЮЧЕНА", night)

	local auto = drone and drone:GetNWBool("LvsAuto")
	setState(autoBtn, auto and "АВТОНОМНЫЙ МОДУЛЬ: ВКЛ" or "АВТОНОМНЫЙ МОДУЛЬ: ВЫКЛ", auto)

	-- счётчик «включено у N/M» спрашиваем у сервера не чаще раза в секунду
	if CurTime() > (LvsAutoStatsAt or 0) then
		LvsAutoStatsAt = CurTime() + 1

		if pcall(net.Start, "lvs_scout_auto_stats") then
			net.SendToServer()
		end
	end
end

net.Receive("lvs_scout_gw_night", function()
	night = net.ReadBool()
	refresh()
end)

-- сколько своих дронов уже в автономном режиме
net.Receive("lvs_scout_auto_stats_res", function()
	local on = net.ReadUInt(8)
	local total = net.ReadUInt(8)

	if not (autoAllBtn and autoAllBtn:IsValid()) then return end

	autoAllBtn.LvsText = string.format("АВТОНОМНОСТЬ: ВКЛЮЧЕНО %d/%d", on, total)
	autoAllBtn.LvsOn = total > 0 and on == total
end)

net.Receive("lvs_scout_friends_list", function()
	local n = net.ReadUInt(8)
	local list = { }

	for i = 1, n do list[i] = net.ReadString() end

	friendsCache = list

	local set = { }
	for _, cls in ipairs(list) do set[string.lower(cls)] = true end
	LvsFriendSet = set

	rebuildFriends()
end)

rebuildFriends = function()
	if not (friendScroll and friendScroll:IsValid()) then return end

	friendScroll:Clear()

	-- запись вида @STEAMID — дружественный игрок, показываем ник
	local function label(entry)
		if entry:sub(1, 1) ~= "@" then return entry end

		local sid = entry:sub(2)

		for _, p in ipairs(player.GetAll()) do
			if IsValid(p) and p:SteamID() == sid then return p:Nick() .. " (игрок)" end
		end

		return "игрок " .. sid
	end

	for _, cls in ipairs(friendsCache) do
		local entry = cls
		local row = vgui.Create("DButton", friendScroll)
		row:SetTall(24)
		row:Dock(TOP)
		row:DockMargin(0, 0, 0, 3)
		row:SetText("")
		row.DoClick = function() removeFriend(entry) end

		row.Paint = function(self, w, h)
			local hover = self:IsHovered()

			surface.SetDrawColor(5, hover and 30 or 16, hover and 32 or 18, 235)
			surface.DrawRect(0, 0, w, h)

			local isPlayer = entry:sub(1, 1) == "@"

			draw.SimpleText(label(entry), "LvsCrysisText", 8, h / 2,
				isPlayer and Color(170, 255, 90) or Color(120, 255, 150),
				TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

			draw.SimpleText("×", "LvsCrysisText", w - 10, h / 2,
				hover and Color(255, 140, 120) or ACCENT_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
end

-- Кнопка в стиле Crysis 1: плоская панель, тонкая линия, индикатор состояния
local function crysisButton(parent, y, onClick)
	local b = vgui.Create("DButton", parent)
	b:SetSize(364, 44)
	b:SetPos(18, y)
	b:SetText("")
	b.DoClick = onClick

	b.Paint = function(self, w, h)
		local hover = self:IsHovered()
		local on = self.LvsOn
		local t = CurTime()

		surface.SetDrawColor(hover and 12 or 6, hover and 30 or 16, hover and 30 or 18, 235)
		surface.DrawRect(0, 0, w, h)

		local mx, my = 14, h / 2
		local ds = on and 5 or 4

		surface.SetDrawColor(on and ACCENT or (hover and Color(150, 230, 220) or ACCENT_DIM))

		if on then
			surface.DrawPoly({
				{ x = mx, y = my - ds }, { x = mx + ds, y = my },
				{ x = mx, y = my + ds }, { x = mx - ds, y = my },
			})
		else
			surface.DrawOutlinedRect(mx - ds, my - ds, ds * 2, ds * 2, 1)
		end

		surface.SetDrawColor(110, 235, 215, on and 200 or (hover and 110 or 30))
		surface.DrawRect(28, h - 1, w - 28, 1)

		if on then
			local px = 28 + ((t * 120) % math.max(w - 60, 1))
			surface.SetDrawColor(200, 255, 245, 90)
			surface.DrawRect(px, h - 2, 26, 2)
		end

		surface.SetDrawColor(110, 235, 215, hover and 26 or 12)
		surface.DrawRect(0, 0, 3, h)

		local col = on and Color(215, 255, 245) or (hover and Color(200, 245, 240) or Color(140, 190, 190))
		draw.SimpleText(self.LvsText or "", "LvsCrysisText", 28, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		if hover then
			draw.SimpleText("◈", "LvsCrysisSmall", w - 16, h / 2, ACCENT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end

	return b
end
-- ===== Настройки производительности (шестерёнка внизу справа) =====
local settingsFrame

local function sendSetting(key, value)
	net.Start("lvs_scout_setting")
	net.WriteString(key)
	net.WriteString(tostring(value))
	net.SendToServer()
end

local function mkBtn(parent, x, y, w, text, group, value, onClick)
	local b = vgui.Create("DButton", parent)
	b:SetPos(x, y)
	b:SetSize(w, 34)
	b:SetText("")

	b.LvsGroup = group
	b.LvsValue = value

	b.DoClick = function()
		surface.PlaySound("ui/buttonclick.wav")
		onClick()

		parent.LvsState = parent.LvsState or {}
		parent.LvsGroups = parent.LvsGroups or {}

		-- текущее выбранное значение: подсветка живёт на состоянии, а не на кнопке
		if group and value ~= nil then
			parent.LvsState[group] = value
		end

		if group == "preset" then
			for _, v in pairs(parent.LvsGroups) do
				if IsValid(v) then v.LvsActive = false end
			end

			parent.LvsGroups = {}
		else
			local p = parent.LvsGroups.preset

			if IsValid(p) then p.LvsActive = false end
		end

		local old = parent.LvsGroups[group or text]

		if IsValid(old) and old ~= b then old.LvsActive = false end

		parent.LvsGroups[group or text] = b
		b.LvsActive = true
		parent.LvsAppliedAt = CurTime()
	end

	b.Paint = function(self, ww, hh)
		local hover = self:IsHovered()
		local parent = self:GetParent()
		local on = self.LvsActive

		if self.LvsGroup and self.LvsValue ~= nil and parent.LvsState then
			on = parent.LvsState[self.LvsGroup] == self.LvsValue
		end

		surface.SetDrawColor(on and 10 or (hover and 12 or 5), on and 34 or (hover and 28 or 14), on and 36 or (hover and 30 or 16), 255)
		surface.DrawRect(0, 0, ww, hh)

		surface.SetDrawColor(110, 235, 215, on and 200 or (hover and 110 or 40))
		surface.DrawOutlinedRect(0, 0, ww, hh)

		if on then
			surface.SetDrawColor(110, 235, 215, 230)
			surface.DrawRect(0, hh - 2, ww, 2)
		end

		draw.SimpleText(self.LvsText or "", "LvsCrysisSmall", ww / 2, hh / 2,
			on and Color(225, 255, 248) or (hover and Color(200, 245, 240) or Color(128, 178, 180)),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	b.LvsText = text

	return b
end

local function openSettings()
	if IsValid(settingsFrame) then
		settingsFrame:Remove()
		settingsFrame = nil
		return
	end

	settingsFrame = vgui.Create("DFrame")
	settingsFrame:SetSize(400, 430)
	-- справа от меню: F3-окно 400x620 всегда по центру экрана
	-- на узких экранах не вылезаем за правый край
	settingsFrame:SetPos(math.min(ScrW() * 0.5 + 212, ScrW() - 416), math.max(ScrH() * 0.5 - 268, 40))
	settingsFrame:SetTitle("")
	settingsFrame:ShowCloseButton(true)
	settingsFrame:MakePopup()

	local f = settingsFrame

	-- реальные значения подтянем с сервера, чтобы кнопки светились по факту
	f.LvsState = {}

	net.Start("lvs_scout_getsetting")
	net.SendToServer()

	f.Paint = function(self, w, h)
		cephBackdrop(w, h, 16)

		surface.SetDrawColor(CE_HEAD)
		surface.DrawRect(16, 0, w - 16, 68)
		surface.SetDrawColor(110, 235, 215, 26)
		surface.DrawRect(16, 67, w - 16, 1)

		surface.SetDrawColor(110, 235, 215, 220)
		surface.DrawRect(0, 20, 3, 44)

		draw.SimpleText("ПРОИЗВОДИТЕЛЬНОСТЬ", "LvsCrysisTitle", 18, 8, Color(220, 255, 248))
		draw.SimpleText("ПРЕСЕТ ПОД ВАШ ПК", "LvsCrysisSmall", 18, 34, ACCENT_DIM)

		local function section(y, text)
			draw.SimpleText(text, "LvsCrysisSmall", 18, y, Color(80, 160, 158))
			local tw = surface.GetTextSize(text)
			surface.SetDrawColor(110, 235, 215, 150)
			surface.DrawRect(0, y + 6, 12, 2)
			surface.SetDrawColor(110, 235, 215, 30)
			surface.DrawRect(18 + tw + 10, y + 7, math.max(w - 46 - tw, 0), 1)
		end

		section(80, "01 · ПРЕСЕТ")
		section(222, "02 · ТОЧЕЧНО")

		local st = self.LvsState or { }
		local perfTxt = st.perf == 0 and "ПОЛНЫЙ" or "ЭКОНОМНЫЙ"
		local rangeTxt = (st.range or 0) == 0 and "ВСЯ КАРТА" or tostring(st.range)
		local navTxt = st.nav == 0 and "ВЫКЛ" or "NAVMESH"

		draw.SimpleText(string.format("СЕЙЧАС: %s · %s · %s", perfTxt, rangeTxt, navTxt),
			"LvsCrysisSmall", 18, 372, Color(120, 200, 196))

		draw.SimpleText("ПЕРФ-РЕЖИМ СНИЖАЕТ ЧАСТОТУ ПРОВЕРОК И ТРАСС",
			"LvsCrysisSmall", 18, 394, Color(96, 156, 158))

		if self.LvsAppliedAt and CurTime() - self.LvsAppliedAt < 1.5 then
			draw.SimpleText("◈ ПРИМЕНЕНО", "LvsCrysisSmall", w - 18, 372,
				Color(150, 255, 220), TEXT_ALIGN_RIGHT)
		end
	end
	mkBtn(f, 18, 96, 364, "СЛАБЫЙ ПК  (всё экономно)", "preset", nil, function()
		sendSetting("lvs_scout_perf", 1)
		sendSetting("lvs_scout_ai_range", 6000)
		sendSetting("lvs_scout_nav_mode", 1)
	end)

	mkBtn(f, 18, 136, 364, "СРЕДНИЙ ПК  (баланс)", "preset", nil, function()
		sendSetting("lvs_scout_perf", 1)
		sendSetting("lvs_scout_ai_range", 12000)
		sendSetting("lvs_scout_nav_mode", 1)
	end)

	mkBtn(f, 18, 176, 364, "МОЩНЫЙ ПК  (полные возможности)", "preset", nil, function()
		sendSetting("lvs_scout_perf", 0)
		sendSetting("lvs_scout_ai_range", 16000)
		sendSetting("lvs_scout_nav_mode", 2)
	end)


	mkBtn(f, 18, 238, 174, "ПЕРФ-РЕЖИМ: ВКЛ/ВЫКЛ", "perf", 1, function() sendSetting("lvs_scout_perf", 1) end)
	mkBtn(f, 208, 238, 174, "ПОЛНЫЕ ВОЗМОЖНОСТИ", "perf", 0, function() sendSetting("lvs_scout_perf", 0) end)

	mkBtn(f, 18, 278, 114, "РАДИУС 6000", "range", 6000, function() sendSetting("lvs_scout_ai_range", 6000) end)
	mkBtn(f, 140, 278, 114, "РАДИУС 12000", "range", 12000, function() sendSetting("lvs_scout_ai_range", 12000) end)
	mkBtn(f, 262, 278, 114, "ВСЯ КАРТА", "range", 0, function() sendSetting("lvs_scout_ai_range", 0) end)

	mkBtn(f, 18, 318, 174, "НАВИГАЦИЯ: NAVMESH", "nav", 1, function() sendSetting("lvs_scout_nav_mode", 1) end)
	mkBtn(f, 208, 318, 174, "НАВИГАЦИЯ: ВЫКЛ", "nav", 0, function() sendSetting("lvs_scout_nav_mode", 0) end)
end

-- Панель настроек закрывается и сама, и вместе с F3-меню
local function closeSettings()
	if IsValid(settingsFrame) then
		settingsFrame:Remove()
	end

	settingsFrame = nil
end

net.Receive("lvs_scout_state", function()
	if not IsValid(settingsFrame) then return end

	settingsFrame.LvsState = {
		perf = net.ReadInt(8),
		range = net.ReadInt(32),
		nav = net.ReadInt(8),
	}
end)


hook.Add("PlayerBindPress", "lvs_scout_skin_menu", function(ply, bind, pressed)
	if not pressed or bind ~= "gm_showspare1" then return end
	if not pilotDrone() then return end

	if frame and frame:IsValid() then
		frame:Remove()
		frame = nil
		closeSettings()
		return true
	end

	frame = vgui.Create("DFrame")
	frame:SetSize(400, 620)
	frame:Center()
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:MakePopup()


	frame.Paint = function(self, w, h)
		cephBackdrop(w, h, CUT)

		-- шапка
		surface.SetDrawColor(CE_HEAD)
		surface.DrawRect(CUT, 0, w - CUT, 72)
		surface.SetDrawColor(110, 235, 215, 26)
		surface.DrawRect(CUT, 71, w - CUT, 1)

		-- бегущая скан-полоса
		local px = (CurTime() * 150) % (w + 180) - 180
		surface.SetDrawColor(110, 235, 215, 22)
		surface.DrawRect(px, 0, 180, 72)

		-- вертикальный акцент у среза
		surface.SetDrawColor(110, 235, 215, 220)
		surface.DrawRect(0, CUT + 4, 3, 50)

		draw.SimpleText("LVS // SCOUT", "LvsCrysisTitle", 18, 8, Color(220, 255, 248))
		draw.SimpleText("CEPH · ОПЕРАТОРСКИЙ ИНТЕРФЕЙС", "LvsCrysisSmall", 18, 34, ACCENT_DIM)

		-- статус: щит / автоном / огонь
		local drone = pilotDrone()
		local shield = drone and drone:GetNWBool("hasModuleShield")
		local auto = drone and drone:GetNWBool("LvsAuto")
		local fire = drone and drone:GetNWBool("LvsCryoActive")

		local function chip(cx, label, on)
			draw.SimpleText(label, "LvsCrysisSmall", cx - 12, 46,
				on and Color(200, 255, 245) or Color(70, 112, 114), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

			surface.SetDrawColor(on and 110 or 44, on and 235 or 74, on and 215 or 80, on and 240 or 170)
			surface.DrawPoly({
				{ x = cx - 4, y = 40 }, { x = cx, y = 44 },
				{ x = cx - 4, y = 48 }, { x = cx - 8, y = 44 },
			})
		end

		chip(w - 18, "ОГОНЬ", fire)
		chip(w - 88, "АВТО", auto)
		chip(w - 154, "ЩИТ", shield)

		-- секции
		local function section(y, text)
			draw.SimpleText(text, "LvsCrysisSmall", 18, y, Color(80, 160, 158))
			local tw = surface.GetTextSize(text)
			surface.SetDrawColor(110, 235, 215, 150)
			surface.DrawRect(0, y + 6, 12, 2)
			surface.SetDrawColor(110, 235, 215, 30)
			surface.DrawRect(18 + tw + 10, y + 7, math.max(w - 46 - tw, 0), 1)
		end

		section(84, "01 · СИСТЕМЫ ДРОНА")
		section(368, "02 · ДРУЖЕСТВЕННЫЕ NPC")

		draw.SimpleText("◈ F3 — ЗАКРЫТЬ     ◈ ⚙ — ПРОИЗВОДИТЕЛЬНОСТЬ", "LvsCrysisSmall", 18, h - 14,
			Color(58, 108, 108), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
	end
	local closeBtn = vgui.Create("DButton", frame)
	closeBtn:SetSize(30, 30)
	closeBtn:SetPos(400 - 38, 8)
	closeBtn:SetText("")
	closeBtn.DoClick = function()
		frame:Remove()
		frame = nil
		closeSettings()
	end

	closeBtn.Paint = function(self, w, h)
		local hover = self:IsHovered()

		if hover then
			surface.SetDrawColor(110, 235, 215, 26)
			surface.DrawRect(0, 0, w, h)
		end

		draw.SimpleText("×", "LvsCrysisText", w / 2, h / 2 - 1,
			hover and Color(255, 140, 120) or ACCENT_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- шестерёнка настроек: правый нижний угол
	local gearBtn = vgui.Create("DButton", frame)
	gearBtn:SetSize(40, 40)
	gearBtn:SetPos(400 - 52, 620 - 56)
	gearBtn:SetText("")
	gearBtn.DoClick = openSettings

	gearBtn.Paint = function(self, w, h)
		local hover = self:IsHovered()
		local cx, cy, r = w / 2, h / 2, 17

		local pts = { }

		for i = 0, 5 do
			local a = math.rad(60 * i - 30)
			pts[#pts + 1] = { x = cx + math.cos(a) * r, y = cy + math.sin(a) * r }
		end

		surface.SetDrawColor(hover and 12 or 5, hover and 34 or 18, hover and 34 or 18, 255)
		surface.DrawPoly(pts)

		surface.SetDrawColor(110, 235, 215, hover and 230 or 150)

		for i = 1, 6 do
			local p1, p2 = pts[i], pts[i % 6 + 1]
			surface.DrawLine(p1.x, p1.y, p2.x, p2.y)
		end

		local col = hover and Color(215, 255, 248) or Color(150, 225, 215)
		draw.SimpleText("⚙", "LvsGear", cx, cy + 1, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	-- оверлей: переключение LVS Ceph <-> LVS Red, на кнопке — текущий
	local ovlBtn = vgui.Create("DButton", frame)
	ovlBtn:SetSize(68, 40)
	ovlBtn:SetPos(400 - 134, 620 - 56)
	ovlBtn:SetText("")
	ovlBtn.DoClick = function()
		local cv = GetConVar("dronesrewrite_curoverlay")
		local cur = cv and cv:GetString() or "LVS Ceph"

		-- два наших пресета по кругу: LVS Ceph <-> LVS Red
		local nextOvl = cur == "LVS Ceph" and "LVS Red" or "LVS Ceph"

		RunConsoleCommand("dronesrewrite_overlay_usedefault", "0")
		RunConsoleCommand("dronesrewrite_curoverlay", nextOvl)
		surface.PlaySound("ui/buttonclickrelease.wav")
	end

	ovlBtn.Paint = function(self, w, h)
		local hover = self:IsHovered()
		local cv = GetConVar("dronesrewrite_curoverlay")
		local cur = cv and cv:GetString() or ""
		local red = cur == "LVS Red"

		surface.SetDrawColor(hover and 26 or 12, red and 52 or (hover and 44 or 30), red and 30 or (hover and 44 or 34), 255)
		surface.DrawRect(0, 0, w, h)

		surface.SetDrawColor(red and 255 or 110, red and 120 or 235, red and 90 or 215, hover and 235 or 165)
		surface.DrawOutlinedRect(0, 0, w, h)

		draw.SimpleText(red and "RED" or "CEPH", "LvsCrysisSmall", w / 2, h / 2,
			red and Color(255, 170, 140) or (hover and Color(220, 255, 248) or Color(160, 225, 215)),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	colorBtn = crysisButton(frame, 100, function()
		local drone = pilotDrone()
		if not drone then return end
		sendSkin(drone:GetNWInt("LvsSkin", 0) == 1 and 0 or 1)
	end)

	shieldBtn = crysisButton(frame, 152, function()
		local drone = pilotDrone()
		if not drone then return end
		sendShield(not drone:GetNWBool("hasModuleShield"))
	end)

	nightBtn = crysisButton(frame, 204, function() sendNight(not night) end)

	autoBtn = crysisButton(frame, 256, function()
		local drone = pilotDrone()
		if not drone then return end
		sendAuto(not drone:GetNWBool("LvsAuto"))
	end)

	-- включает автономность всем своим дронам, где она ещё выключена
	autoAllBtn = crysisButton(frame, 308, function()
		local ok = pcall(net.Start, "lvs_scout_auto_all")

		if not ok then
			return
		end

		net.SendToServer()
	end)

	autoAllBtn.LvsText = "АВТОНОМНОСТЬ: ВКЛЮЧИТЬ ВСЕМ"

	friendEntry = vgui.Create("DTextEntry", frame)
	friendEntry:SetPos(18, 392)
	friendEntry:SetSize(246, 30)
	friendEntry:SetFont("LvsCrysisText")
	friendEntry:SetTextColor(Color(230, 245, 255))
	friendEntry:SetUpdateOnType(true)
	friendEntry:SetKeyboardInputEnabled(true)
	friendEntry:SetCursorColor(ACCENT)
	friendEntry.LvsPlaceholder = "classname, напр. npc_combine_s"

	friendEntry.OnEnter = function(self)
		addFriend(self:GetValue())
		self:SetText("")
	end

	friendEntry.OnMousePressed = function(self)
		self:RequestFocus()
	end

	friendEntry.Paint = function(self, w, h)
		surface.SetDrawColor(14, 24, 30, 235)
		surface.DrawRect(0, 0, w, h)

		surface.SetDrawColor(110, 235, 215, self:IsEditing() and 210 or 70)
		surface.DrawOutlinedRect(0, 0, w, h, 1)

		if self:GetText() == "" and not self:IsEditing() then
			draw.SimpleText(self.LvsPlaceholder, "LvsCrysisSmall", 8, h / 2, Color(90, 130, 160), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		else
		if self:GetText() == "" and not self:IsEditing() then
			draw.SimpleText(self.LvsPlaceholder, "LvsCrysisSmall", 8, h / 2,
				Color(90, 130, 160), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		else
			self:DrawTextEntryText(Color(230, 245, 255), ACCENT, ACCENT)
		end
	end
	end

	local addBtn = vgui.Create("DButton", frame)
	addBtn:SetPos(272, 392)
	addBtn:SetSize(110, 30)
	addBtn:SetText("")
	addBtn.DoClick = function()
		addFriend(friendEntry:GetValue())
		friendEntry:SetText("")
	end

	addBtn.Paint = function(self, w, h)
		local hover = self:IsHovered()

		surface.SetDrawColor(hover and 30 or 18, hover and 44 or 28, hover and 52 or 36, 235)
		surface.DrawRect(0, 0, w, h)

		surface.SetDrawColor(110, 235, 215, hover and 220 or 80)
		surface.DrawOutlinedRect(0, 0, w, h, 1)

		draw.SimpleText("ДОБАВИТЬ", "LvsCrysisSmall", w / 2, h / 2,
			hover and Color(230, 245, 255) or ACCENT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	friendScroll = vgui.Create("DScrollPanel", frame)
	friendScroll:SetPos(18, 432)
	friendScroll:SetSize(364, 150)

	requestFriends()
	rebuildFriends()
	refresh()

	timer.Create("lvs_scout_skin_menu_refresh", 0.25, 0, function()
		if not (frame and frame:IsValid()) then timer.Remove("lvs_scout_skin_menu_refresh") return end
		refresh()
	end)

	return true
end)

hook.Add("OnScreenSizeChanged", "lvs_scout_skin_menu_resize", function()
	if frame and frame:IsValid() then frame:Center() end
end)

-- без открытия меню список друзей тоже нужен (сканер/подсветка)
hook.Add("InitPostEntity", "lvs_scout_friends_sync", requestFriends)