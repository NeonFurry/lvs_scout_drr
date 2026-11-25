-- Модуль собран из отдельных файлов: правки вносить сюда.

-- ===== Меню F3 и друзья (lvs_scout_skin_menu.lua) =====
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

-- ===== Оверлей кабины (lvs_scout_overlay.lua) =====
-- Оверлей дрона LVS Scout: «Ceph» из Crysis 1.
-- Холодная бирюзово-синяя тональность, прозрачные тени, лёгкий иней в светах,
-- тонкая плёнка оптики (виньетка + скан-линия) по краям кадра.
-- Появляется в списке Overlay панели DRR и выбран по умолчанию
-- (ENT.OverlayName = "LVS Ceph" в shared.lua).
-- При включённой оптике (LvsNightVision) не накладывается.

local registered = false

hook.Remove("HUDPaint", "lvs_scout_ceph_film")

local function lightGain(pos)
	local l = render.GetLightColor(pos)
	local lum = (l.r + l.g + l.b) / 3

	if lum > 1 then lum = lum / 255 end

	return math.Clamp(1 - (lum - 0.15) / 0.40, 0, 1)
end

-- Плёнка оптики: мягкая виньетка и медленная скан-линия.
-- Рисуется только когда реально применён наш оверлей и оптика выключена.
hook.Add("HUDPaint", "lvs_scout_ceph_film", function()

	local ply = LocalPlayer()

	if not IsValid(ply) then return end

	local drone = ply:GetNWEntity("DronesRewriteDrone")

	if not IsValid(drone) or drone:GetClass() ~= "lvs_scout_drr" then return end
	if LvsNightVision then return end

	-- камера стороннего мода (Enhanced ThirdPerson): не наш кадр
	if not (LvsDroneCameraOn and LvsDroneCameraOn(drone)) then return end
	local ov = drone.GetOverlayName and drone:GetOverlayName()
	if ov ~= "LVS Ceph" and ov ~= "LVS Red" then return end

	local sw, sh = ScrW(), ScrH()
	local g = lightGain(drone:GetPos())

	-- День: притемняем кадр, чтобы HUD читался. Потолок 55: на пустыне и снегу
	-- 80 съедало картинку, а ColorModify и так работает по всему кадру.
	local scrim = math.Round(math.Clamp(85 * (1 - g), 0, 55))

	if scrim > 0 then
		surface.SetDrawColor(4, 10, 14, scrim)
		surface.DrawRect(0, 0, sw, sh)
	end

	-- Верх и низ: там стоят показания HUD, им нужен более плотный фон
	local band = math.Round(70 * (1 - g))

	if band > 0 then
		for i = 1, 10 do
			surface.SetDrawColor(2, 8, 12, math.floor(band * (1 - i / 11)))
			surface.DrawRect(0, (i - 1) * sh * 0.012, sw, sh * 0.012)
			surface.DrawRect(0, sh - i * sh * 0.012, sw, sh * 0.012)
		end
	end

	-- виньетка: 6 шагов по краям
	for i = 1, 6 do
		local a = 20 - i * 3

		surface.SetDrawColor(2, 10, 16, a)
		surface.DrawRect(0, (i - 1) * sh * 0.018, sw, sh * 0.018)
		surface.DrawRect(0, sh - i * sh * 0.018, sw, sh * 0.018)
		surface.DrawRect((i - 1) * sw * 0.018, 0, sw * 0.018, sh)
		surface.DrawRect(sw - i * sw * 0.018, 0, sw * 0.018, sh)
	end

	-- тонкая бирюзовая кромка
	surface.SetDrawColor(90, 200, 235, 18)
	surface.DrawOutlinedRect(0, 0, sw, sh, 2)

	-- медленная скан-линия сверху вниз
	local y = (CurTime() * 90) % sh

	surface.SetDrawColor(130, 225, 255, 10)
	surface.DrawRect(0, y, sw, 2)
	surface.SetDrawColor(130, 225, 255, 4)
	surface.DrawRect(0, y + 2, sw, 10)

	-- помехи оптики: плотное зерно в два слоя (светлое + тёмное) и рваные полосы
	surface.SetDrawColor(160, 240, 240, 40)

	for i = 1, 380 do
		surface.DrawRect(math.Rand(0, sw), math.Rand(0, sh), math.Rand(1, 2), math.Rand(1, 2))
	end

	-- тёмные крупинки: зерно читается и на светлом, и на тёмном
	surface.SetDrawColor(0, 8, 10, 34)

	for i = 1, 220 do
		surface.DrawRect(math.Rand(0, sw), math.Rand(0, sh), math.Rand(1, 2), 1)
	end

	-- яркие искры поверх зерна
	surface.SetDrawColor(235, 255, 252, 85)

	for i = 1, 28 do
		surface.DrawRect(math.Rand(0, sw), math.Rand(0, sh), 1, 1)
	end

	-- срыв синхронизации раз в ~1.2 секунды
	local phase = (CurTime() % 1.2) / 1.2

	if phase < 0.09 then
		surface.SetDrawColor(170, 255, 245, 48)
		surface.DrawRect(0, math.Rand(0, sh), sw, math.Rand(1, 4))
		surface.SetDrawColor(60, 160, 160, 30)
		surface.DrawRect(math.Rand(0, sw * 0.4), math.Rand(0, sh), sw * math.Rand(0.2, 0.6), 2)
		surface.SetDrawColor(0, 0, 0, 40)
		surface.DrawRect(0, math.Rand(0, sh), sw, 1)
	end
end)

local function register()
	if registered then return end
	if not (DRONES_REWRITE and DRONES_REWRITE.Overlay) then return end

	DRONES_REWRITE.Overlay["LVS Ceph"] = function(drone)
		if not IsValid(drone) then return end
		if not (LvsDroneCameraOn and LvsDroneCameraOn(drone)) then return end
		if LvsNightVision then return end

		local g = lightGain(drone:GetPos())

		-- едва заметное «дыхание» оптики: картинка живая, но не мигает
		local breath = 0.006 * math.sin(CurTime() * 0.9)

		DrawColorModify({
			["$pp_colour_addr"] = 0,
			["$pp_colour_addg"] = 0.010,
			["$pp_colour_addb"] = 0.022 + 0.012 * g,
			-- день: притемняем сильнее (пересвет съедал HUD), ночь: поднимаем тени
			["$pp_colour_brightness"] = -0.16 + 0.28 * g + breath,
			["$pp_colour_contrast"] = 1.10 - 0.06 * g,
			-- ночью сильнее уходим в монохром: так читаются силуэты
			["$pp_colour_colour"] = 0.78 - 0.28 * g,
			["$pp_colour_mulr"] = 0.86 + 0.04 * g,
			["$pp_colour_mulg"] = 0.97 + 0.04 * g,
			["$pp_colour_mulb"] = 1.06 + 0.04 * g,
		})

		-- лёгкий морозный ореол, ночью чуть сильнее
		DrawBloom(0.02 + 0.05 * g, 0.22, 2, 2, 1, 0, 1, 1, 0.3)
		DrawSharpen(1.2 - 0.15 * g, 0.8)
	end

	-- Копия DRR-оверлея «Red», адаптированная: красный монохром без провала
	-- в чёрное, тени подняты, чтобы силуэты и HUD читались
	DRONES_REWRITE.Overlay["LVS Red"] = function(drone)
		if not IsValid(drone) then return end
		if not (LvsDroneCameraOn and LvsDroneCameraOn(drone)) then return end
		if LvsNightVision then return end

		local g = lightGain(drone:GetPos())

		DrawColorModify({
			["$pp_colour_addr"] = 0.42 + 0.06 * g,
			["$pp_colour_addg"] = 0.015,
			["$pp_colour_addb"] = 0.015,
			["$pp_colour_brightness"] = -0.34 + 0.26 * g,
			["$pp_colour_contrast"] = 1.08 - 0.04 * g,
			["$pp_colour_colour"] = 0.55,
			["$pp_colour_mulr"] = 0.72,
			["$pp_colour_mulg"] = 0.10,
			["$pp_colour_mulb"] = 0.10,
		})

		DrawBloom(0.03 + 0.03 * g, 0.25, 2, 2, 1, 0, 1, 1, 0.3)
		DrawSharpen(0.8, 2)
	end

	registered = true
end

register()

hook.Add("Think", "lvs_scout_overlay_register", function()
	register()

	if registered then hook.Remove("Think", "lvs_scout_overlay_register") end
end)

-- ===== Переопределение методов класса (lvs_scout_class.lua) =====
-- Позднее переопределение методов класса: при регистрации GMod копирует
-- поля базового класса поверх наших, поэтому методы из cl_init затирались
-- базовыми DRR (оверлей и HUD оставались чужими).
-- Ставим их прямо в зарегистрированную таблицу класса.

hook.Remove("Think", "lvs_scout_class_override")

local function entTable()
	local stored = scripted_ents.GetStored("lvs_scout_drr")

	if stored and stored.t then return stored.t end

	return scripted_ents.Get("lvs_scout_drr")
end

hook.Add("Think", "lvs_scout_class_override", function()
	local ENT = entTable()

	if not ENT then return end

	-- регистрация могла затереть поле базовым «Default»
	ENT.OverlayName = "LVS Ceph"

	-- «Use Default Overlay»: галка — наш LVS Ceph, снята — выбранный в списке.
	-- Оптика живёт только на нашем оверлее и сама гаснет при выборе другого.
	ENT.GetOverlayName = function(self)
		local cvs = DRONES_REWRITE and DRONES_REWRITE.ClientCVars

		if cvs and cvs.OverlayDef and not cvs.OverlayDef:GetBool() then
			local picked = cvs.CustomOverlay and cvs.CustomOverlay:GetString()

			if picked and picked ~= "" then return picked end
		end

		return self.OverlayName or "LVS Ceph"
	end

	-- Пресет HUD DRR для нашего дрона не рисует: HUD зовётся напрямую.
	ENT.GetHUDName = function()
		return "LVS Internal"
	end

	hook.Remove("Think", "lvs_scout_class_override")
end)

-- ===== Камера автопилота (lvs_scout_auto_cam.lua) =====
-- Автономный режим: ИИ перехватывает обзор, чтобы можно было спокойно наблюдать.
-- Камера DRR считается клиентом от EyeAngles пилота, поэтому наводим её здесь.

local AUTO_CAM_HOOK = "lvs_scout_auto_cam"
local LERP = 0.2

local function lerpView(f, cur, want)
	return Angle(
		Lerp(f, cur.p, want.p),
		cur.y + math.AngleDifference(want.y, cur.y) * f,
		0
	)
end

hook.Remove("CreateMove", AUTO_CAM_HOOK)

hook.Add("CreateMove", AUTO_CAM_HOOK, function(cmd)
	local ply = LocalPlayer()
	local drone = IsValid(ply) and ply:GetNWEntity("DronesRewriteDrone")

	if not IsValid(drone) or drone:GetClass() ~= "lvs_scout_drr" then return end
	if not drone:GetNWBool("LvsAuto") then return end

	local dir = drone:GetNWVector("LvsAutoDir", vector_origin)

	-- без цели камера не держит взгляд пилота, но только когда дрон не под
	-- управлением игрока: за штурвалом обзор не перехватываем
	if dir:IsZero() then
		local drv = drone.GetDriver and drone:GetDriver()
		if IsValid(drv) then return end

		dir = drone:GetForward()
	end

	local want = drone:WorldToLocalAngles(dir:Angle())
	cmd:SetViewAngles(lerpView(LERP, cmd:GetViewAngles(), want))
end)

-- ===== Скрытие модели пилота (lvs_scout_pilot_model.lua) =====
-- Игроки, пилотирующие дрон DRR, для всех невидимы (без моделей-заглушек),
-- и HUD-пресеты DRR не помечают их как цели.

local hidden = {}

local function piloting(ply)
	return IsValid(ply:GetNWEntity("DronesRewriteDrone"))
end

hook.Add("Think", "lvs_scout_pilot_hide", function()
	if CurTime() < (LvsPilotHideNext or 0) then return end
	LvsPilotHideNext = CurTime() + 0.1

	for _, ply in ipairs(player.GetAll()) do
		if piloting(ply) then
			hidden[ply] = true
			if not ply:GetNoDraw() then ply:SetNoDraw(true) end
		elseif hidden[ply] then
			hidden[ply] = nil
			ply:SetNoDraw(false)
		end
	end
end)

-- На время отрисовки HUD прячем пилотов из проверок IsPlayer,
-- чтобы DRR не рисовал на них маркеры целей.
local function withoutPilots(fn, drone)
	local patched = {}

	for _, ply in ipairs(player.GetAll()) do
		if piloting(ply) then
			patched[#patched + 1] = ply
			ply.IsPlayer = function() return false end
		end
	end

	local ok, err = pcall(fn, drone)

	for _, ply in ipairs(patched) do
		if IsValid(ply) then ply.IsPlayer = nil end
	end

	if not ok then ErrorNoHalt("[LVS Scout] HUD: " .. tostring(err) .. "\n") end
end

local wrapped = {}

local function wrapHud()
	if not (DRONES_REWRITE and DRONES_REWRITE.HUD) then return end
	if not next(DRONES_REWRITE.HUD) then return end

	for name, fn in pairs(DRONES_REWRITE.HUD) do
		if not wrapped[name] then
			wrapped[name] = true
			DRONES_REWRITE.HUD[name] = function(drone) withoutPilots(fn, drone) end
		end
	end

	-- таблица уже не пустая и всё обёрнуто — хук больше не нужен
	hook.Remove("Think", "lvs_scout_hud_wrap")
end

hook.Add("Think", "lvs_scout_hud_wrap", wrapHud)

-- ===== Подсветка целей (lvs_scout_vision.lua) =====
hook.Remove("PlayerBindPress", "lvs_scout_vision")
hook.Remove("PostDrawTranslucentRenderables", "lvs_scout_vision_glow")
-- F в режиме пилотирования: подсветка игроков и NPC обводкой.
-- Цвет обводки берётся из текущего overlay дрона DRR (Red → красная).

local enabled = false
local MAX_DIST = 6000

local function pilotDrone()
	local drone = LocalPlayer():GetNWEntity("DronesRewriteDrone")
	if IsValid(drone) and drone:GetClass() == "lvs_scout_drr" then return drone end
end

local function toggleVision()
	if not pilotDrone() then return end

	enabled = not enabled
	LVSScoutVision = enabled


	print("[LVS Scout] vision =", enabled, "drone =", tostring(pilotDrone()))
end

concommand.Add("lvs_scout_vision", toggleVision)

-- Диагностика: что видит подсветка и в каком состоянии каждая цель
concommand.Add("lvs_scout_vision_dump", function()
	local drone = pilotDrone()
	if not drone then print("[LVS] дрон не найден") return end

	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) and e ~= drone and (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) then
			local bone = e:LookupBone("ValveBiped.Bip01_Head1")
			local bp = bone and e:GetBonePosition(bone)

			print(string.format("[LVS] %s | dormant=%s | bone=%s | bp=%s | dist=%d",
				e:GetClass(), tostring(e:IsDormant()), tostring(bone), type(bp),
				math.floor(drone:GetPos():Distance(e:GetPos()))))
		end
	end
end)

-- Цвет метки: друг — зелёный, враг — красный, нейтрал — жёлтый,
-- свой дрон — фиолетовый, чужой дрон — жёлтый
function LvsBlipColor(ent)
	if not IsValid(ent) then return Color(255, 220, 90) end

	-- дружественные игроки — салатовый
	if ent:IsPlayer() and LvsFriendSet and LvsFriendSet["@" .. ent:SteamID()] then
		return Color(170, 255, 90)
	end

	local cls = ent:GetClass()
	local owner = ent.GetNWEntity and ent:GetNWEntity("LvsOwner")
	local ownerID = ent.GetNWString and ent:GetNWString("LvsOwnerID")
	local me = LocalPlayer()

	if ent.IS_DRONE or cls == "lvs_scout_drr" then
		local mine = (IsValid(owner) and owner == me)
			or (IsValid(me) and ownerID ~= "" and ownerID == me:SteamID())

		if mine then return Color(190, 120, 255) end

		return Color(255, 220, 90)
	end

	if LvsIsFriendClass and LvsIsFriendClass(cls) then
		return Color(120, 255, 150)
	end

	if IsEnemyEntityName and IsEnemyEntityName(cls) then
		return Color(255, 70, 70)
	end

	return Color(255, 220, 90)
end

hook.Add("PreDrawHalos", "lvs_scout_vision_halos", function()
	if not enabled then return end

	local drone = pilotDrone()
	if not drone then return end

	local origin = drone:GetPos()
	local maxSqr = MAX_DIST * MAX_DIST
	local ply = LocalPlayer()
	local friends, enemies, neutrals, own, players = {}, {}, {}, {}, {}

	-- ночная оптика рисует свои контуры: иначе обводки складываются
	if LvsNightVision then return end

	-- список сущностей кешируем: ents.GetAll каждый кадр — дорого
	if not LvsVisionCache or CurTime() > (LvsVisionCacheAt or 0) then
		LvsVisionCache = ents.GetAll()
		LvsVisionCacheAt = CurTime() + 0.25
	end

	for _, e in ipairs(LvsVisionCache) do
		if e ~= drone and IsValid(e) and not e:IsDormant() then
			-- свой игрок обводится всегда, независимо от дистанции до дрона
			local inRange = e == ply or e:GetPos():DistToSqr(origin) <= maxSqr

			if (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) and inRange then
				local cls = e:GetClass()
				local owner = e.GetNWEntity and e:GetNWEntity("LvsOwner")

				if (e.IS_DRONE or cls == "lvs_scout_drr") and IsValid(owner) and owner == ply then
					own[#own + 1] = e
				elseif e:IsPlayer() and LvsFriendSet and LvsFriendSet["@" .. e:SteamID()] then
					players[#players + 1] = e
				elseif LvsIsFriendClass and LvsIsFriendClass(cls) then
					friends[#friends + 1] = e
				elseif IsEnemyEntityName and IsEnemyEntityName(cls) then
					enemies[#enemies + 1] = e
				else
					neutrals[#neutrals + 1] = e
				end
			end
		end
	end

	local function add(list, col)
		if #list > 0 then halo.Add(list, col, 1, 1, 1, true, true) end
	end

	add(own, Color(190, 120, 255, 255))
	add(players, Color(170, 255, 90, 255))
	add(friends, Color(120, 255, 150, 255))
	add(enemies, Color(255, 70, 70, 255))
	add(neutrals, Color(255, 220, 90, 255))
end)
-- Дублирующий триггер: сама клавиша F, независимо от бинда
local fWasDown = false

hook.Add("Think", "lvs_scout_vision_key", function()
	if not pilotDrone() then
		fWasDown = false
		return
	end

	local down = input.IsKeyDown(KEY_F)

	if down and not fWasDown then toggleVision() end

	fWasDown = down
end)
