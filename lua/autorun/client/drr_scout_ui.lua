-- Модуль собран из отдельных файлов: правки вносить сюда.

-- ===== Меню F3 и друзья (drr_scout_skin_menu.lua) =====
-- Меню оператора в стиле интерфейса Crysis 1 (нанокостюм): расцветка, щит, ночь, автомодуль

local frame
local colorBtn, shieldBtn, nightBtn, autoBtn, autoAllBtn
local night = false

surface.CreateFont("DrrCrysisTitle", { font = "Roboto", size = 20, weight = 700, extended = true })
surface.CreateFont("DrrCrysisText", { font = "Roboto", size = 15, weight = 500, extended = true })
surface.CreateFont("DrrCrysisSmall", { font = "Roboto", size = 12, weight = 500, extended = true })

-- Эмодзи-шестерёнка: рисуется системным символом, а не вектором
surface.CreateFont("DrrGear", {
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
	-- сплошная заливка: срез углов и дема-подложка не должны просвечивать карту
	surface.SetDrawColor(4, 8, 10, 255)
	surface.DrawRect(0, 0, w, h)

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

-- Дроны владельца: сервер присылает точный список (на клиенте .Owner часто пуст)
local squadCache = { }

net.Receive("drr_scout_squad_list", function()
	local n = net.ReadUInt(8)
	local list = {}

	for i = 1, n do
		list[i] = {
			ent     = Entity(net.ReadUInt(16)),
			hp      = net.ReadUInt(16),
			max     = net.ReadUInt(16),
			auto    = net.ReadBool(),
			cmd     = net.ReadBool(),
			piloted = net.ReadBool(),
		}
	end

	squadCache = list
end)

-- Общий набор классов-друзей: им же пользуются сканер и подсветка
DrrFriendSet = DrrFriendSet or { }

function DrrIsFriendClass(cls)
	if not cls then return false end
	return DrrFriendSet[string.lower(cls)] == true
end
local rebuildFriends

local function requestFriends()
	net.Start("drr_scout_friends_get")
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

	net.Start("drr_scout_friends_set")
	net.WriteBool(true)
	net.WriteString(entry)
	net.SendToServer()

	timer.Simple(0.15, requestFriends)
end

local function removeFriend(cls)
	net.Start("drr_scout_friends_set")
	net.WriteBool(false)
	net.WriteString(cls)
	net.SendToServer()

	timer.Simple(0.15, requestFriends)
end

local function sendSkin(index)
	net.Start("drr_scout_set_skin")
	net.WriteUInt(index, 8)
	net.SendToServer()
end

local function sendShield(on)
	net.Start("drr_scout_set_shield")
	net.WriteBool(on)
	net.SendToServer()
end

local function sendAuto(on)
	net.Start("drr_scout_auto")
	net.WriteBool(on)
	net.SendToServer()
end

local function sendNight(toggle)
	net.Start("drr_scout_gw_night")
	net.WriteBool(toggle)
	net.SendToServer()
end

local function pilotDrone()
	local drone = LocalPlayer():GetNWEntity("DronesRewriteDrone")
	if IsValid(drone) and drone:GetClass() == "drr_scout_drr" then return drone end
end

local function setState(btn, text, on)
	if not (btn and btn:IsValid()) then return end

	btn.DrrText = text
	btn.DrrOn = on
end

local function refresh()
	if not (frame and frame:IsValid()) then return end

	local drone = pilotDrone()
	local skin = drone and drone:GetNWInt("DrrSkin", 0) == 1

	setState(colorBtn, skin and DrrT("РАСЦВЕТКА: КРАСНАЯ", "COLOR: RED") or DrrT("РАСЦВЕТКА: ОБЫЧНАЯ", "COLOR: NORMAL"), skin)

	local shield = drone and drone:GetNWBool("hasModuleShield")
	local left = drone and (drone:GetNWFloat("DrrShieldRestoreAt", 0) - CurTime()) or 0

	if left > 0 and not shield then
		setState(shieldBtn, string.format(DrrT("ЩИТ: ПЕРЕЗАГРУЗКА %d с", "SHIELD: RELOAD %d s"), math.ceil(left)), false)
	else
		setState(shieldBtn, shield and DrrT("ЩИТ: ВКЛЮЧЁН", "SHIELD: ON") or DrrT("ЩИТ: ВЫКЛЮЧЕН", "SHIELD: OFF"), shield)
	end

	setState(nightBtn, night and DrrT("НОЧЬ: ВКЛЮЧЕНА", "NIGHT: ON") or DrrT("НОЧЬ: ВЫКЛЮЧЕНА", "NIGHT: OFF"), night)

	local auto = drone and drone:GetNWBool("DrrAuto")
	setState(autoBtn, auto and DrrT("АВТОНОМНЫЙ МОДУЛЬ: ВКЛ", "AUTONOMOUS: ON") or DrrT("АВТОНОМНЫЙ МОДУЛЬ: ВЫКЛ", "AUTONOMOUS: OFF"), auto)

	-- счётчик «включено у N/M» спрашиваем у сервера не чаще раза в секунду
	if CurTime() > (DrrAutoStatsAt or 0) then
		DrrAutoStatsAt = CurTime() + 1

		if pcall(net.Start, "drr_scout_auto_stats") then
			net.SendToServer()
		end
	end
end

	net.Receive("drr_scout_gw_night", function()
		night = net.ReadBool()
		refresh()
	end)

	-- состояние ночи общее для всех дронов: кнопка всегда показывает факт
	net.Receive("drr_scout_gw_state", function()
		night = net.ReadBool()

		if refresh then refresh() end
	end)

-- сколько своих дронов уже в автономном режиме
net.Receive("drr_scout_auto_stats_res", function()
	local on = net.ReadUInt(8)
	local total = net.ReadUInt(8)

	if not (autoAllBtn and autoAllBtn:IsValid()) then return end

	autoAllBtn.DrrText = string.format(DrrT("АВТОНОМНОСТЬ: ВКЛЮЧЕНО %d/%d", "AUTONOMY: ENABLED %d/%d"), on, total)
	autoAllBtn.DrrOn = total > 0 and on == total
end)

net.Receive("drr_scout_friends_list", function()
	local n = net.ReadUInt(8)
	local list = { }

	for i = 1, n do list[i] = net.ReadString() end

	friendsCache = list

	local set = { }
	for _, cls in ipairs(list) do set[string.lower(cls)] = true end
	DrrFriendSet = set

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
			if IsValid(p) and p:SteamID() == sid then return p:Nick() .. DrrT(" (игрок)", " (player)") end
		end

		return DrrT("игрок ", "player ") .. sid
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

			draw.SimpleText(label(entry), "DrrCrysisText", 8, h / 2,
				isPlayer and Color(170, 255, 90) or Color(120, 255, 150),
				TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

			draw.SimpleText("×", "DrrCrysisText", w - 10, h / 2,
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
		local on = self.DrrOn
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
		draw.SimpleText(self.DrrText or "", "DrrCrysisText", 28, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		if hover then
			draw.SimpleText("◈", "DrrCrysisSmall", w - 16, h / 2, ACCENT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end

	return b
end
-- ===== Настройки производительности (шестерёнка внизу справа) =====
local settingsFrame

local function sendSetting(key, value)
	net.Start("drr_scout_setting")
	net.WriteString(key)
	net.WriteString(tostring(value))
	net.SendToServer()
end

local function mkBtn(parent, x, y, w, text, group, value, onClick)
	local b = vgui.Create("DButton", parent)
	b:SetPos(x, y)
	b:SetSize(w, 34)
	b:SetText("")

	b.DrrGroup = group
	b.DrrValue = value

	b.DoClick = function()
		surface.PlaySound("ui/buttonclick.wav")
		onClick()

		parent.DrrState = parent.DrrState or {}
		parent.DrrGroups = parent.DrrGroups or {}

		-- текущее выбранное значение: подсветка живёт на состоянии, а не на кнопке
		if group and value ~= nil then
			parent.DrrState[group] = value
		end

		if group == "preset" then
			for _, v in pairs(parent.DrrGroups) do
				if IsValid(v) then v.DrrActive = false end
			end

			parent.DrrGroups = {}
		else
			local p = parent.DrrGroups.preset

			if IsValid(p) then p.DrrActive = false end
		end

		local old = parent.DrrGroups[group or text]

		if IsValid(old) and old ~= b then old.DrrActive = false end

		parent.DrrGroups[group or text] = b
		b.DrrActive = true
		parent.DrrAppliedAt = CurTime()
	end

	b.Paint = function(self, ww, hh)
		local hover = self:IsHovered()
		local parent = self:GetParent()
		local on = self.DrrActive

		if self.DrrGroup and self.DrrValue ~= nil and parent.DrrState then
			on = parent.DrrState[self.DrrGroup] == self.DrrValue
		end

		surface.SetDrawColor(on and 10 or (hover and 12 or 5), on and 34 or (hover and 28 or 14), on and 36 or (hover and 30 or 16), 255)
		surface.DrawRect(0, 0, ww, hh)

		surface.SetDrawColor(110, 235, 215, on and 200 or (hover and 110 or 40))
		surface.DrawOutlinedRect(0, 0, ww, hh)

		if on then
			surface.SetDrawColor(110, 235, 215, 230)
			surface.DrawRect(0, hh - 2, ww, 2)
		end

		draw.SimpleText(self.DrrText or "", "DrrCrysisSmall", ww / 2, hh / 2,
			on and Color(225, 255, 248) or (hover and Color(200, 245, 240) or Color(128, 178, 180)),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	b.DrrText = text

	return b
end

-- окна встают в ряд от F3-меню: ИИ слева, производительность справа
local function sidePos(offset, width)
	local fx, fy = ScrW() * 0.5 - 200, ScrH() * 0.5 - 370

	if IsValid(frame) then fx, fy = frame:GetPos() end

	return math.Clamp(fx + offset, 8, math.max(8, ScrW() - width - 8)),
		math.Clamp(fy, 8, math.max(8, ScrH() - 220))
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
	settingsFrame:SetPos(sidePos(412, 400))
	settingsFrame:SetTitle("")
	settingsFrame:ShowCloseButton(true)
	settingsFrame:MakePopup()
settingsFrame.PaintBackground = function() end

	local f = settingsFrame

	-- реальные значения подтянем с сервера, чтобы кнопки светились по факту
	f.DrrState = {}

	net.Start("drr_scout_getsetting")
	net.SendToServer()

	f.Paint = function(self, w, h)
		cephBackdrop(w, h, 16)

		surface.SetDrawColor(CE_HEAD)
		surface.DrawRect(16, 0, w - 16, 68)
		surface.SetDrawColor(110, 235, 215, 26)
		surface.DrawRect(16, 67, w - 16, 1)

		surface.SetDrawColor(110, 235, 215, 220)
		surface.DrawRect(0, 20, 3, 44)

		draw.SimpleText(DrrT("ПРОИЗВОДИТЕЛЬНОСТЬ", "PERFORMANCE"), "DrrCrysisTitle", 18, 8, Color(220, 255, 248))
		draw.SimpleText(DrrT("ПРЕСЕТ ПОД ВАШ ПК", "PRESET FOR YOUR PC"), "DrrCrysisSmall", 18, 34, ACCENT_DIM)

		local function section(y, text)
			draw.SimpleText(text, "DrrCrysisSmall", 18, y, Color(80, 160, 158))
			local tw = surface.GetTextSize(text)
			surface.SetDrawColor(110, 235, 215, 150)
			surface.DrawRect(0, y + 6, 12, 2)
			surface.SetDrawColor(110, 235, 215, 30)
			surface.DrawRect(18 + tw + 10, y + 7, math.max(w - 46 - tw, 0), 1)
		end

		section(80, DrrT("01 · ПРЕСЕТ", "01 · PRESET"))
		section(222, DrrT("02 · ТОЧЕЧНО", "02 · FINE TUNE"))

		local st = self.DrrState or { }
		local perfTxt = st.perf == 0 and DrrT("ПОЛНЫЙ", "FULL") or DrrT("ЭКОНОМНЫЙ", "ECONOMY")
		local rangeTxt = (st.range or 0) == 0 and DrrT("ВСЯ КАРТА", "WHOLE MAP") or tostring(st.range)
		local navTxt = st.nav == 0 and DrrT("ВЫКЛ", "OFF") or "NAVMESH"

		draw.SimpleText(string.format(DrrT("СЕЙЧАС: %s · %s · %s", "NOW: %s · %s · %s"), perfTxt, rangeTxt, navTxt),
			"DrrCrysisSmall", 18, 372, Color(120, 200, 196))

		draw.SimpleText(DrrT("ПЕРФ-РЕЖИМ СНИЖАЕТ ЧАСТОТУ ПРОВЕРОК И ТРАСС", "PERF MODE LOWERS CHECK AND TRACE RATE"),
			"DrrCrysisSmall", 18, 394, Color(96, 156, 158))

		if self.DrrAppliedAt and CurTime() - self.DrrAppliedAt < 1.5 then
			draw.SimpleText(DrrT("◈ ПРИМЕНЕНО", "◈ APPLIED"), "DrrCrysisSmall", w - 18, 372,
				Color(150, 255, 220), TEXT_ALIGN_RIGHT)
		end
	end
	mkBtn(f, 18, 96, 364, DrrT("СЛАБЫЙ ПК  (всё экономно)", "LOW PC  (economy)"), "preset", nil, function()
		sendSetting("drr_scout_perf", 1)
		sendSetting("drr_scout_ai_range", 6000)
		sendSetting("drr_scout_nav_mode", 1)
	end)

	mkBtn(f, 18, 136, 364, DrrT("СРЕДНИЙ ПК  (баланс)", "MID PC  (balanced)"), "preset", nil, function()
		sendSetting("drr_scout_perf", 1)
		sendSetting("drr_scout_ai_range", 12000)
		sendSetting("drr_scout_nav_mode", 1)
	end)

	mkBtn(f, 18, 176, 364, DrrT("МОЩНЫЙ ПК  (полные возможности)", "HIGH PC  (full features)"), "preset", nil, function()
		sendSetting("drr_scout_perf", 0)
		sendSetting("drr_scout_ai_range", 16000)
		sendSetting("drr_scout_nav_mode", 2)
	end)


	mkBtn(f, 18, 238, 174, DrrT("ПЕРФ-РЕЖИМ: ВКЛ/ВЫКЛ", "PERF MODE: TOGGLE"), "perf", 1, function() sendSetting("drr_scout_perf", 1) end)
	mkBtn(f, 208, 238, 174, DrrT("ПОЛНЫЕ ВОЗМОЖНОСТИ", "FULL FEATURES"), "perf", 0, function() sendSetting("drr_scout_perf", 0) end)

	mkBtn(f, 18, 278, 114, DrrT("РАДИУС 6000", "RADIUS 6000"), "range", 6000, function() sendSetting("drr_scout_ai_range", 6000) end)
	mkBtn(f, 140, 278, 114, DrrT("РАДИУС 12000", "RADIUS 12000"), "range", 12000, function() sendSetting("drr_scout_ai_range", 12000) end)
	mkBtn(f, 262, 278, 114, DrrT("ВСЯ КАРТА", "WHOLE MAP"), "range", 0, function() sendSetting("drr_scout_ai_range", 0) end)

	mkBtn(f, 18, 318, 174, DrrT("НАВИГАЦИЯ: NAVMESH", "NAVIGATION: NAVMESH"), "nav", 1, function() sendSetting("drr_scout_nav_mode", 1) end)
	mkBtn(f, 208, 318, 174, DrrT("НАВИГАЦИЯ: ВЫКЛ", "NAVIGATION: OFF"), "nav", 0, function() sendSetting("drr_scout_nav_mode", 0) end)
end

-- Панель настроек закрывается и сама, и вместе с F3-меню
local tuneFrame

local function closeSettings()
	if IsValid(settingsFrame) then
		settingsFrame:Remove()
	end

	settingsFrame = nil

	if IsValid(tuneFrame) then tuneFrame:Remove() end
	tuneFrame = nil
end

-- ===== Стая: сводка по дронам (HP и статус) =====
local squadFrame

local function buildSquad()
	if IsValid(squadFrame) then
		squadFrame:Remove()
		squadFrame = nil
		return
	end

	squadFrame = vgui.Create("DFrame")
	squadFrame:SetSize(300, 380)
	squadFrame:SetPos(ScrW() / 2 + 210, ScrH() / 2 - 190)
	squadFrame:SetTitle("")
	squadFrame:ShowCloseButton(false)
	squadFrame:MakePopup()
	squadFrame.PaintBackground = function() end

	squadFrame.Paint = function(self, w, h)
		cephBackdrop(w, h, CUT)

		surface.SetDrawColor(CE_HEAD)
		surface.DrawRect(CUT, 0, w - CUT, 36)

		draw.SimpleText(DrrT("СТАЯ", "SQUAD"), "DrrCrysisTitle", 14, 8, Color(220, 255, 248))
	end

	local close = vgui.Create("DButton", squadFrame)
	close:SetSize(28, 28)
	close:SetPos(300 - 36, 4)
	close:SetText("")
	close.DoClick = function() squadFrame:Remove() end
	close.Paint = function(self, w, h)
		draw.SimpleText("×", "DrrCrysisTitle", w / 2, h / 2,
			self:IsHovered() and Color(255, 150, 130) or ACCENT_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	local scroll = vgui.Create("DScrollPanel", squadFrame)
	scroll:SetPos(12, 44)
	scroll:SetSize(276, 324)

	local function fill()
		if not IsValid(scroll) then return end

		scroll:Clear()

		local list = {}

		for _, d in ipairs(ents.FindByClass("drr_scout_drr")) do
			if IsValid(d) and d.Owner == LocalPlayer() then list[#list + 1] = d end
		end

		table.sort(list, function(a, b) return a:EntIndex() < b:EntIndex() end)

		if #list == 0 then
			local lbl = vgui.Create("DLabel", scroll)
			lbl:SetPos(6, 6)
			lbl:SetSize(240, 20)
			lbl:SetText(DrrT("ДРОНОВ НЕТ", "NO DRONES"))
			lbl:SetTextColor(Color(90, 150, 148))
			lbl:SetFont("DrrCrysisSmall")
			return
		end

		for i, d in ipairs(list) do
			local hp  = math.max(d:GetHealth() or 0, 0)
			local max = math.max(d:GetDefaultHealth() or hp, 1)

			local status =
				hp <= 0 and DrrT("УНИЧТОЖЕН", "DESTROYED")
				or (IsValid(d:GetDriver()) and DrrT("ПИЛОТ", "PILOTED"))
				or (d:GetNWBool("DrrCommander") and DrrT("КОМАНДИР", "COMMANDER"))
				or (d:GetNWBool("DrrAuto") and DrrT("АВТОНОМ", "AUTONOMOUS"))
				or DrrT("ОЖИДАНИЕ", "IDLE")

			local row = vgui.Create("DPanel", scroll)
			row:SetPos(0, (i - 1) * 46)
			row:SetSize(262, 42)
			row.PaintBackground = function() end
			row.Paint = function(self, w, h)
				local dead = hp <= 0

				surface.SetDrawColor(9, 21, 23, 235)
				surface.DrawRect(0, 0, w, h)

				surface.SetDrawColor(dead and 220 or 110, dead and 80 or 235, dead and 80 or 215, 120)
				surface.DrawOutlinedRect(0, 0, w, h)

				draw.SimpleText("#" .. d:EntIndex() .. "   " .. math.floor(hp) .. "/" .. math.floor(max),
					"DrrCrysisSmall", 8, 8, dead and Color(255, 130, 120) or Color(205, 255, 245))

				draw.SimpleText(status, "DrrCrysisSmall", w - 8, 8, ACCENT_DIM, TEXT_ALIGN_RIGHT)

				surface.SetDrawColor(14, 30, 32)
				surface.DrawRect(8, 28, w - 16, 6)

				surface.SetDrawColor(dead and 220 or 110, dead and 70 or 235, dead and 70 or 215, 230)
				surface.DrawRect(8, 28, (w - 16) * math.Clamp(hp / max, 0, 1), 6)
			end
		end
	end

	fill()

	timer.Create("DrrSquadRefresh", 0.5, 0, function()
		if IsValid(squadFrame) and IsValid(scroll) then fill() end
	end)

	squadFrame.OnRemove = function()
		squadFrame = nil
		timer.Remove("DrrSquadRefresh")
	end
end


net.Receive("drr_scout_state", function()
	local st = {
		perf = net.ReadInt(8),
		range = net.ReadInt(32),
		nav = net.ReadInt(8),
		engage = net.ReadInt(32),
		swarm = net.ReadInt(8),
		heat = net.ReadFloat(),
		cool = net.ReadFloat(),
		follow = net.ReadInt(8),
		formation = net.ReadInt(8),
		formDist = net.ReadInt(32),
		patrol = net.ReadInt(8),
		leader = net.ReadInt(8),
	}

	DrrTuneState = st

	if IsValid(settingsFrame) then settingsFrame.DrrState = st end
	if IsValid(tuneFrame) and tuneFrame.DrrSync then tuneFrame:DrrSync() end
	if DrrMenuSyncPages then DrrMenuSyncPages() end
end)


hook.Add("PlayerBindPress", "drr_scout_skin_menu", function(ply, bind, pressed)
	if not pressed or bind ~= "gm_showspare1" then return end
	if not pilotDrone() then return end

	if frame and frame:IsValid() then
		frame:Remove()
		frame = nil
		closeSettings()
		if IsValid(squadFrame) then squadFrame:Remove() end
		return true
	end

	-- ===== стили меню =====
	if not ConVarExists("drr_scout_menu_style") then
		CreateClientConVar("drr_scout_menu_style", "ceph", true, false, "Стиль меню DRR Scout")
	end

	local function mkStyle(id, ru, en, ar, ag, ab, pr, pg, pb, cr, cg, cb)
		return {
			id = id, ru = ru, en = en,
			a     = Color(ar, ag, ab),
			txt   = Color(math.min(255, ar + 105), math.min(255, ag + 20), math.min(255, ab + 33)),
			dim   = Color(math.floor(ar * 0.45), math.floor(ag * 0.45), math.floor(ab * 0.45)),
			panel = Color(pr, pg, pb, 252),
			card  = Color(cr, cg, cb, 240),
			cardH = Color(math.min(255, cr + 8), math.min(255, cg + 12), math.min(255, cb + 12), 244),
		}
	end

	local STYLES = {
		mkStyle("ceph",    "CEPH · БИРЮЗА",   "CEPH · CYAN",   110, 235, 215, 4, 8, 10, 10, 20, 22),
		mkStyle("crimson", "CRIMSON · АЛЫЙ",  "CRIMSON",       235, 90, 80,   10, 4, 5, 26, 12, 12),
		mkStyle("amber",   "AMBER · ЯНТАРЬ",  "AMBER",         255, 180, 72,  10, 7, 3, 28, 20, 9),
		mkStyle("steel",   "STEEL · СТАЛЬ",   "STEEL",         150, 190, 235, 5, 8, 12, 13, 19, 27),
		mkStyle("void",    "VOID · ФИОЛЕТ",   "VOID",          175, 130, 255, 8, 5, 12, 19, 14, 29),
		mkStyle("matrix",  "MATRIX · ИЗУМРУД", "MATRIX",       90, 255, 120,  4, 10, 5, 10, 22, 13),
		mkStyle("toxic",   "TOXIC · КИСЛОТА", "TOXIC",         190, 255, 60,  8, 10, 3, 20, 24, 9),
		mkStyle("ice",     "ICE · ЛЁД",       "ICE",           170, 225, 255, 4, 7, 11, 12, 18, 25),
		mkStyle("magma",   "MAGMA · ЛАВА",    "MAGMA",         255, 110, 60,  10, 4, 3, 26, 12, 8),
		mkStyle("gold",    "GOLD · ЗОЛОТО",   "GOLD",          255, 210, 110, 10, 8, 3, 26, 21, 10),
		mkStyle("rose",    "ROSE · РОЗА",     "ROSE",          255, 140, 190, 10, 5, 8, 26, 12, 20),
		mkStyle("mono",    "MONO · МОНОХРОМ", "MONOCHROME",    225, 235, 240, 6, 7, 8, 16, 18, 20),
	}

	local function curStyle()
		local cv = GetConVar("drr_scout_menu_style")
		local id = cv and cv:GetString() or "ceph"

		for _, s in ipairs(STYLES) do
			if s.id == id then return s end
		end

		return STYLES[1]
	end

	frame = vgui.Create("DFrame")
	frame:SetSize(720, 470)
	frame:Center()
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:MakePopup()
	frame.PaintBackground = function() end

	-- закрытие меню гасит боковые панели, иначе они остаются висеть
	frame.OnClose = function()
		closeSettings()
		if IsValid(squadFrame) then squadFrame:Remove() end
	end

	-- ночь общая для всех дронов: при открытии берём фактическое состояние
	net.Start("drr_scout_gw_get")
	net.SendToServer()

	-- настройки ИИ/профили живут в этом же меню: забираем фактические значения
	net.Start("drr_scout_getsetting")
	net.SendToServer()

	frame.Paint = function(self, w, h)
		local S = curStyle()

		surface.SetDrawColor(S.panel)
		surface.DrawRect(0, 0, w, h)

		surface.SetDrawColor(S.a.r, S.a.g, S.a.b, 8)
		for x = -h, w, 18 do surface.DrawLine(x, h, x + h, 0) end

		surface.SetDrawColor(S.a.r, S.a.g, S.a.b, 180)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

	-- ===== шапка =====
	local header = vgui.Create("DPanel", frame)
	header:Dock(TOP)
	header:SetTall(54)
	header.Paint = function(self, w, h)
		local S = curStyle()

		surface.SetDrawColor(S.card)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(S.a.r, S.a.g, S.a.b, 40)
		surface.DrawRect(0, h - 1, w, 1)

		draw.SimpleText("DRR // SCOUT", "DrrCrysisTitle", 16, 8, S.txt)
		draw.SimpleText(DrrT("ОПЕРАТОРСКИЙ ИНТЕРФЕЙС · F3 — ЗАКРЫТЬ", "OPERATOR INTERFACE · F3 — CLOSE"),
			"DrrCrysisSmall", 16, 32, S.dim)

		local drone = pilotDrone()
		local shield = drone and drone:GetNWBool("hasModuleShield")
		local auto = drone and drone:GetNWBool("DrrAuto")
		local fire = drone and drone:GetNWBool("DrrCryoActive")

		local function chip(cx, label, on)
			draw.SimpleText(label, "DrrCrysisSmall", cx - 10, h / 2,
				on and S.txt or S.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

			surface.SetDrawColor(on and S.a.r or S.dim.r, on and S.a.g or S.dim.g,
				on and S.a.b or S.dim.b, on and 240 or 150)
			surface.DrawPoly({
				{ x = cx - 2, y = h / 2 - 4 }, { x = cx + 2, y = h / 2 },
				{ x = cx - 2, y = h / 2 + 4 }, { x = cx - 6, y = h / 2 },
			})
		end

		chip(w - 246, DrrT("ЩИТ", "SHIELD"), shield)
		chip(w - 192, DrrT("АВТО", "AUTO"), auto)
		chip(w - 132, DrrT("ОГОНЬ", "FIRE"), fire)
	end

	local closeBtn = vgui.Create("DButton", header)
	closeBtn:Dock(RIGHT)
	closeBtn:DockMargin(6, 12, 10, 12)
	closeBtn:SetWide(30)
	closeBtn:SetText("×")
	closeBtn:SetFont("DrrCrysisText")
	closeBtn:SetTextColor(ACCENT_DIM)
	closeBtn.Paint = function(self, w, h)
		if self:IsHovered() then
			surface.SetDrawColor(110, 235, 215, 26)
			surface.DrawRect(0, 0, w, h)
		end
	end
	closeBtn.DoClick = function() frame:Close() end

	-- ===== тело: слева разделы, справа страница =====
	local body = vgui.Create("DPanel", frame)
	body:Dock(FILL)
	body.Paint = function() end

	local nav = vgui.Create("DPanel", body)
	nav:Dock(LEFT)
	nav:SetWide(190)
	nav.Paint = function(self, w, h)
		local S = curStyle()

		surface.SetDrawColor(S.card.r, S.card.g, S.card.b, 235)
		surface.DrawRect(0, 0, w, h)

		surface.SetDrawColor(S.a.r, S.a.g, S.a.b, 60)
		surface.DrawRect(w - 1, 0, 1, h)
	end

	local navTitle = vgui.Create("DLabel", nav)
	navTitle:Dock(TOP)
	navTitle:DockMargin(14, 10, 0, 4)
	navTitle:SetTall(18)
	navTitle:SetFont("DrrCrysisSmall")
	navTitle:SetTextColor(Color(80, 160, 158))
	navTitle:SetText(DrrT("РАЗДЕЛЫ", "SECTIONS"))

	local content = vgui.Create("DPanel", body)
	content:Dock(FILL)
	content:DockMargin(10, 8, 10, 8)
	content.Paint = function() end

	local function cardPaint(self, w, h)
		local S = curStyle()
		local hover = self:IsHovered()

		surface.SetDrawColor(hover and S.cardH or S.card)
		surface.DrawRect(0, 0, w, h)

		surface.SetDrawColor(S.a.r, S.a.g, S.a.b, hover and 150 or 60)
		surface.DrawOutlinedRect(0, 0, w, h, 1)

		surface.SetDrawColor(S.a.r, S.a.g, S.a.b, hover and 220 or 120)
		surface.DrawRect(0, 0, 2, h)
	end

	local function rowButton(parent, label, height)
		local b = vgui.Create("DButton", parent)
		b:Dock(TOP)
		b:DockMargin(0, 0, 0, 6)
		b:SetTall(height or 40)
		b:SetText("")
		b:SetCursor("hand")
		b.DrrLabel = label

		b.Paint = function(self, w, h)
			cardPaint(self, w, h)

			local S = curStyle()

			draw.SimpleText(self.DrrText or self.DrrLabel or "", "DrrCrysisText", 12, h / 2,
				self.DrrOn and S.txt or Color(172, 190, 192), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

			if self.DrrSwatch then
				surface.SetDrawColor(self.DrrSwatch)
				surface.DrawRect(w - 36, h / 2 - 7, 14, 14)
				surface.SetDrawColor(0, 0, 0, 130)
				surface.DrawOutlinedRect(w - 36, h / 2 - 7, 14, 14, 1)
			end

			draw.SimpleText("◈", "DrrCrysisSmall", w - 14, h / 2,
				self.DrrOn and S.a or S.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end

		return b
	end

	local function sectionLabel(parent, text)
		local l = vgui.Create("DLabel", parent)
		l:Dock(TOP)
		l:DockMargin(2, 8, 0, 4)
		l:SetTall(18)
		l:SetFont("DrrCrysisSmall")
		l:SetTextColor(Color(128, 158, 160))
		l:SetText(text)
		return l
	end

	local function pageScroll(host)
		local scroll = vgui.Create("DScrollPanel", host)
		scroll:Dock(FILL)
		scroll.Paint = function() end
		scroll:GetCanvas():DockPadding(0, 0, 8, 0)
		return scroll
	end

	-- после правки настроек просим сервер прислать фактическое состояние:
	-- без этого строки остаются со старыми подписями и кажется, что клик не сработал
	local function requestState()
		net.Start("drr_scout_getsetting")
		net.SendToServer()
	end

	local pages = {}
	local currentPage = "info"

	local INFO_ROWS = {
		{ ru = "ПРОЧНОСТЬ", en = "HULL", get = function(d)
			return math.floor(d:GetHealth() or 0) .. " / " .. math.floor(d:GetDefaultHealth() or 0)
		end },
		{ ru = "ЩИТ", en = "SHIELD", get = function(d)
			return d:GetNWBool("hasModuleShield") and DrrT("ВКЛ", "ON") or DrrT("ВЫКЛ", "OFF")
		end },
		{ ru = "АВТОНОМ", en = "AUTONOMY", get = function(d)
			return d:GetNWBool("DrrAuto") and DrrT("ВКЛ", "ON") or DrrT("ВЫКЛ", "OFF")
		end },
		{ ru = "КОМАНДНЫЙ", en = "COMMANDER", get = function(d)
			return d:GetNWBool("DrrCommander") and DrrT("ДА", "YES") or DrrT("НЕТ", "NO")
		end },
		{ ru = "ПИЛОТ", en = "PILOT", get = function(d)
			local p = d:GetDriver()
			return IsValid(p) and p:Nick() or DrrT("НЕТ", "NONE")
		end },
		{ ru = "СЛЕДОВАНИЕ", en = "FOLLOW", get = function()
			return ((DrrTuneState or {}).follow == 1) and DrrT("ЗА КОМАНДНЫМ", "BEHIND LEADER") or DrrT("ВЫКЛ", "OFF")
		end },
		{ ru = "СТРОЙ", en = "FORMATION", get = function()
			local ru = { "КЛИН", "КОЛОННА", "КРУГ", "ЛИНИЯ", "СВОБОДНЫЙ" }
			local en = { "WEDGE", "COLUMN", "CIRCLE", "LINE", "FREE" }
			local i = math.Clamp(((DrrTuneState or {}).formation or 0) + 1, 1, 5)

			return DrrT(ru[i], en[i])
		end },
		{ ru = "ДИСТАНЦИЯ СТРОЯ", en = "FORM DISTANCE", get = function()
			return tostring((DrrTuneState or {}).formDist or "—")
		end },
	}

	local SECTION_INFO = {
		{ ru = "СТАЯ", en = "SQUAD", dru = "Ваши дроны: прочность, статус, автоном.", den = "Your drones: hull, status, autonomy." },
		{ ru = "ДРУЗЬЯ", en = "FRIENDS", dru = "Классы NPC, по которым дрон не стреляет.", den = "NPC classes the drone never attacks." },
		{ ru = "ИИ", en = "AI", dru = "Дальность, огонь, перегрев луча, патруль, строй.", den = "Range, fire distance, beam heat, patrol, formation." },
		{ ru = "СОХРАНЕНИЯ", en = "SAVED", dru = "Три профиля настроек: ЛКМ загрузить, ПКМ сохранить.", den = "Three presets: LMB load, RMB save." },
		{ ru = "ПРОИЗВОДИТЕЛЬНОСТЬ", en = "PERFORMANCE", dru = "Пресеты под ПК, радиус поиска, навигация.", den = "PC presets, search radius, navigation." },
		{ ru = "СТИЛИ", en = "STYLES", dru = "Цветовые схемы меню.", den = "Menu color schemes." },
	}

	pages.info = function(host)
		local c = pageScroll(host):GetCanvas()
		local drone = pilotDrone()

		local model = vgui.Create("DModelPanel", c)
		model:Dock(TOP)
		model:DockMargin(0, 0, 0, 8)
		model:SetTall(190)
		model:SetMouseInputEnabled(false)

		if IsValid(drone) and util.IsValidModel(drone:GetModel()) then
			model:SetModel(drone:GetModel())
			model:SetAnimated(false)

			-- габариты модели, а не костей: щупальца иначе уводят центр кадра
			local ent = model:GetEntity()
			local mn, mx

			if IsValid(ent) then
				local ok, a, b = pcall(ent.GetModelBounds, ent)

				if ok then mn, mx = a, b end
			end

			if (not mn or not mx) and IsValid(drone) then
				local ok, a, b = pcall(drone.GetModelBounds, drone)

				if ok then mn, mx = a, b end
			end

			if mn and mx then
				local size = math.Clamp((mx - mn):Length(), 200, 1500)

				model:SetLookAt(Vector(0, 0, (mn.z + mx.z) * 0.5))
				model:SetCamPos(Vector(-size * 1.15, 0, size * 0.22))
				model:SetFOV(40)
			else
				model:SetLookAt(Vector(0, 0, 20))
				model:SetCamPos(Vector(-900, 0, 160))
				model:SetFOV(40)
			end

			model.LayoutEntity = function(self, ent2)
				ent2:SetAngles(Angle(0, RealTime() * 22, 0))
			end
		end

		-- обрезка по панели: DModelPanel сам не ограничивает область отрисовки
		local basePaint = model.Paint

		model.Paint = function(self, w, h)
			local x, y = self:LocalToScreen(0, 0)

			render.SetScissorRect(x, y, x + w, y + h, true)
			basePaint(self, w, h)
			render.SetScissorRect(0, 0, 0, 0, false)
		end

		model.PaintOver = function(self, w, h)
			local S = curStyle()

			surface.SetDrawColor(S.a.r, S.a.g, S.a.b, 90)
			surface.DrawOutlinedRect(0, 0, w, h, 1)

			draw.SimpleText(DrrT("МОДЕЛЬ ДРОНА", "DRONE MODEL"), "DrrCrysisSmall", 8, h - 16, S.dim)
		end

		local stats = vgui.Create("DPanel", c)
		stats:Dock(TOP)
		stats:DockMargin(0, 0, 0, 8)
		stats:SetTall(#INFO_ROWS * 22 + 10)
		stats.Paint = function(self, w, h)
			local S = curStyle()
			local d = pilotDrone()
			local y = 4

			cardPaint(self, w, h)

			for _, row in ipairs(INFO_ROWS) do
				draw.SimpleText(DrrT(row.ru, row.en), "DrrCrysisSmall", 12, y + 3, Color(132, 164, 166))

				local val = (IsValid(d) and row.get(d)) or "—"

				draw.SimpleText(tostring(val), "DrrCrysisText", w - 14, y, S.txt, TEXT_ALIGN_RIGHT)

				y = y + 22
			end
		end

		sectionLabel(c, DrrT("РАЗДЕЛЫ МЕНЮ", "MENU SECTIONS"))

		for _, s in ipairs(SECTION_INFO) do
			local r = vgui.Create("DPanel", c)
			r:Dock(TOP)
			r:DockMargin(0, 0, 0, 6)
			r:SetTall(48)
			r.Paint = function(self, w, h)
				local S = curStyle()

				cardPaint(self, w, h)

				draw.SimpleText(DrrT(s.ru, s.en), "DrrCrysisText", 12, 7, S.txt)
				draw.SimpleText(DrrT(s.dru, s.den), "DrrCrysisSmall", 12, 26, Color(132, 164, 166))
			end
		end
	end

	pages.systems = function(host)
		local c = pageScroll(host):GetCanvas()

		sectionLabel(c, DrrT("01 · ДРОН", "01 · DRONE"))

		colorBtn = rowButton(c, DrrT("РАСЦВЕТКА", "COLOR"))
		colorBtn.DoClick = function()
			local drone = pilotDrone()
			if not drone then return end
			sendSkin(drone:GetNWInt("DrrSkin", 0) == 1 and 0 or 1)
		end

		shieldBtn = rowButton(c, DrrT("ЩИТ", "SHIELD"))
		shieldBtn.DoClick = function()
			local drone = pilotDrone()
			if not drone then return end
			sendShield(not drone:GetNWBool("hasModuleShield"))
		end

		nightBtn = rowButton(c, DrrT("НОЧЬ", "NIGHT"))
		nightBtn.DoClick = function() sendNight(not night) end

		autoBtn = rowButton(c, DrrT("АВТОНОМНЫЙ МОДУЛЬ", "AUTONOMOUS MODULE"))
		autoBtn.DoClick = function()
			local drone = pilotDrone()
			if not drone then return end
			sendAuto(not drone:GetNWBool("DrrAuto"))
		end

		sectionLabel(c, DrrT("02 · СТАЯ И ВИД", "02 · SQUAD AND VIEW"))

		autoAllBtn = rowButton(c, DrrT("АВТОНОМНОСТЬ: ВКЛЮЧИТЬ ВСЕМ", "AUTONOMY: ENABLE FOR ALL"))
		autoAllBtn.DoClick = function()
			if pcall(net.Start, "drr_scout_auto_all") then net.SendToServer() end
		end

		local ovl = rowButton(c, DrrT("ОВЕРЛЕЙ", "OVERLAY"))
		ovl.Paint = function(self, w, h)
			cardPaint(self, w, h)

			local cv = GetConVar("dronesrewrite_curoverlay")
			local red = cv and cv:GetString() == "DRR Red"

			draw.SimpleText(DrrT("ОВЕРЛЕЙ: ", "OVERLAY: ") .. (red and "RED" or "CEPH"),
				"DrrCrysisText", 12, h / 2, red and Color(255, 190, 170) or Color(165, 215, 212),
				TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

			draw.SimpleText("◈", "DrrCrysisSmall", w - 14, h / 2,
				red and Color(255, 120, 90) or ACCENT_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
		ovl.DoClick = function()
			local cv = GetConVar("dronesrewrite_curoverlay")
			local nextOvl = (cv and cv:GetString() == "DRR Red") and "DRR Ceph" or "DRR Red"

			RunConsoleCommand("dronesrewrite_overlay_usedefault", "0")
			RunConsoleCommand("dronesrewrite_curoverlay", nextOvl)
			surface.PlaySound("ui/buttonclickrelease.wav")
		end
	end

	pages.squad = function(host)
		local c = pageScroll(host):GetCanvas()

		-- владельца знает только сервер: локально .Owner часто пуст
		net.Start("drr_scout_squad_list")
		net.SendToServer()

		local rows = {}

		for _, it in ipairs(squadCache) do rows[#rows + 1] = it end

		-- сервер ещё не ответил или старый аддон: локальный список как запасной
		if #rows == 0 then
			for _, d in ipairs(ents.FindByClass("drr_scout_drr")) do
				if IsValid(d) and (d.Owner == LocalPlayer() or d:GetOwner() == LocalPlayer()
					or d:GetDriver() == LocalPlayer()) then
					rows[#rows + 1] = {
						ent = d,
						hp = math.max(d:GetHealth() or 0, 0),
						max = math.max(d:GetDefaultHealth() or 0, 0),
						auto = d:GetNWBool("DrrAuto") == true,
						cmd = d:GetNWBool("DrrCommander") == true,
						piloted = IsValid(d:GetDriver()),
					}
				end
			end
		end

		if #rows == 0 then
			local lbl = vgui.Create("DLabel", c)
			lbl:Dock(TOP)
			lbl:DockMargin(2, 8, 0, 0)
			lbl:SetTall(20)
			lbl:SetFont("DrrCrysisText")
			lbl:SetTextColor(Color(90, 150, 148))
			lbl:SetText(DrrT("ДРОНОВ НЕТ", "NO DRONES"))
			return
		end

		for _, it in ipairs(rows) do
			local d   = it.ent
			local hp  = it.hp or 0
			local max = math.max(it.max or hp, 1)
			local dead = hp <= 0
			local id  = IsValid(d) and d:EntIndex() or 0

			local status =
				dead and DrrT("УНИЧТОЖЕН", "DESTROYED")
				or (it.piloted and DrrT("ПИЛОТ", "PILOTED"))
				or (it.cmd and DrrT("КОМАНДИР", "COMMANDER"))
				or (it.auto and DrrT("АВТОНОМ", "AUTONOMOUS"))
				or DrrT("ОЖИДАНИЕ", "IDLE")

			local row = vgui.Create("DPanel", c)
			row:Dock(TOP)
			row:DockMargin(0, 0, 0, 6)
			row:SetTall(46)
			row.Paint = function(self, w, h)
				cardPaint(self, w, h)

				draw.SimpleText("#" .. id .. "   " .. hp .. "/" .. max,
					"DrrCrysisText", 12, 10, dead and Color(255, 130, 120) or Color(205, 255, 245))

				draw.SimpleText(status, "DrrCrysisSmall", 12, 30,
					dead and Color(255, 130, 120) or ACCENT_DIM)

				local frac = math.Clamp(hp / max, 0, 1)

				surface.SetDrawColor(14, 30, 32)
				surface.DrawRect(w - 140, 20, 128, 6)

				surface.SetDrawColor(dead and 220 or 110, dead and 70 or 235, dead and 70 or 215, 230)
				surface.DrawRect(w - 140, 20, 128 * frac, 6)
			end
		end
	end

	pages.friends = function(host)
		friendEntry = vgui.Create("DTextEntry", host)
		friendEntry:Dock(TOP)
		friendEntry:SetTall(30)
		friendEntry:SetFont("DrrCrysisText")
		friendEntry:SetTextColor(Color(230, 245, 255))
		friendEntry:SetUpdateOnType(true)
		friendEntry:SetKeyboardInputEnabled(true)
		friendEntry:SetCursorColor(ACCENT)
		friendEntry.DrrPlaceholder = DrrT("classname, напр. npc_combine_s", "classname, e.g. npc_combine_s")

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
				draw.SimpleText(self.DrrPlaceholder, "DrrCrysisSmall", 8, h / 2,
					Color(90, 130, 160), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			else
				self:DrawTextEntryText(Color(230, 245, 255), ACCENT, ACCENT)
			end
		end

		local addBtn = rowButton(host, DrrT("ДОБАВИТЬ КЛАСС", "ADD CLASS"), 30)
		addBtn:DockMargin(0, 8, 0, 8)
		addBtn.DoClick = function()
			addFriend(friendEntry:GetValue())
			friendEntry:SetText("")
		end

		local scroll = vgui.Create("DScrollPanel", host)
		scroll:Dock(FILL)
		scroll.Paint = function(self, w, h)
			surface.SetDrawColor(4, 10, 12, 250)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(110, 235, 215, 45)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end

		friendScroll = scroll

		requestFriends()
		rebuildFriends()
	end

	pages.ai = function(host)
		local c = pageScroll(host):GetCanvas()

		if DrrBuildAiPage then
			DrrBuildAiPage(c, rowButton, sectionLabel)
		else
			local lbl = vgui.Create("DLabel", c)
			lbl:Dock(TOP)
			lbl:SetTall(20)
			lbl:SetFont("DrrCrysisText")
			lbl:SetTextColor(Color(90, 150, 148))
			lbl:SetText(DrrT("НАСТРОЙКИ ЕЩЁ НЕ ЗАГРУЖЕНЫ", "SETTINGS NOT LOADED YET"))
		end
	end

	pages.profiles = function(host)
		local c = pageScroll(host):GetCanvas()

		if DrrBuildProfilesPage then
			DrrBuildProfilesPage(c, rowButton, sectionLabel)
		else
			local lbl = vgui.Create("DLabel", c)
			lbl:Dock(TOP)
			lbl:SetTall(20)
			lbl:SetFont("DrrCrysisText")
			lbl:SetTextColor(Color(90, 150, 148))
			lbl:SetText(DrrT("ПРОФИЛИ ЕЩЁ НЕ ЗАГРУЖЕНЫ", "PROFILES NOT LOADED YET"))
		end
	end

	pages.perf = function(host)
		local c = pageScroll(host):GetCanvas()
		local st = DrrTuneState or {}

		sectionLabel(c, DrrT("01 · ПРЕСЕТ ПОД ПК", "01 · PRESET FOR YOUR PC"))

		local function preset(label, perf, range, nav)
			local b = rowButton(c, label)

			b.DoClick = function()
				sendSetting("drr_scout_perf", perf)
				sendSetting("drr_scout_ai_range", range)
				sendSetting("drr_scout_nav_mode", nav)

				DrrTuneState = DrrTuneState or {}
				DrrTuneState.perf, DrrTuneState.range, DrrTuneState.nav = perf, range, nav

				requestState()
				timer.Simple(0, function()
					if DrrMenuRebuild then DrrMenuRebuild() end
				end)
			end

			return b
		end

		preset(DrrT("СЛАБЫЙ ПК · ВСЁ ЭКОНОМНО", "LOW PC · ECONOMY"), 1, 6000, 1)
		preset(DrrT("СРЕДНИЙ ПК · БАЛАНС", "MID PC · BALANCED"), 1, 12000, 1)
		preset(DrrT("МОЩНЫЙ ПК · ВСЁ ВКЛЮЧЕНО", "HIGH PC · FULL"), 0, 16000, 2)

		sectionLabel(c, DrrT("02 · ТОЧЕЧНО", "02 · FINE TUNE"))

		local perf = rowButton(c, "")
		perf.DrrText = DrrT("ПЕРФ-РЕЖИМ: ", "PERF MODE: ")
			.. ((st.perf == 0) and DrrT("ВЫКЛ", "OFF") or DrrT("ВКЛ", "ON"))
		perf.DrrOn = st.perf ~= 0
		perf.DoClick = function()
			local nextV = ((DrrTuneState or {}).perf == 0) and 1 or 0

			DrrTuneState = DrrTuneState or {}
			DrrTuneState.perf = nextV

			sendSetting("drr_scout_perf", nextV)
			requestState()

			perf.DrrText = DrrT("ПЕРФ-РЕЖИМ: ", "PERF MODE: ")
				.. ((nextV == 0) and DrrT("ВЫКЛ", "OFF") or DrrT("ВКЛ", "ON"))
			perf.DrrOn = nextV ~= 0
		end

		local range = rowButton(c, "")
		range.DrrText = DrrT("РАДИУС ПОИСКА: ", "SEARCH RADIUS: ")
			.. (((st.range or 0) == 0) and DrrT("ВСЯ КАРТА", "WHOLE MAP") or tostring(st.range))
		range.DoClick = function()
			local cur = (DrrTuneState or {}).range or 0
			local nextV = (cur == 0) and 6000 or ((cur == 6000) and 12000 or ((cur == 12000) and 16000 or 0))

			DrrTuneState = DrrTuneState or {}
			DrrTuneState.range = nextV

			sendSetting("drr_scout_ai_range", nextV)
			requestState()

			range.DrrText = DrrT("РАДИУС ПОИСКА: ", "SEARCH RADIUS: ")
				.. ((nextV == 0) and DrrT("ВСЯ КАРТА", "WHOLE MAP") or tostring(nextV))
		end

		local nav = rowButton(c, "")
		nav.DrrText = DrrT("НАВИГАЦИЯ: ", "NAVIGATION: ")
			.. (((st.nav or 0) == 0) and DrrT("ВЫКЛ", "OFF") or (((st.nav or 0) == 1) and "NAVMESH" or DrrT("ПОЛНАЯ", "FULL")))
		nav.DrrOn = (st.nav or 0) ~= 0
		nav.DoClick = function()
			local cur = (DrrTuneState or {}).nav or 0
			local nextV = (cur == 0) and 1 or ((cur == 1) and 2 or 0)

			DrrTuneState = DrrTuneState or {}
			DrrTuneState.nav = nextV

			sendSetting("drr_scout_nav_mode", nextV)
			requestState()

			nav.DrrText = DrrT("НАВИГАЦИЯ: ", "NAVIGATION: ")
				.. ((nextV == 0) and DrrT("ВЫКЛ", "OFF") or ((nextV == 1) and "NAVMESH" or DrrT("ПОЛНАЯ", "FULL")))
			nav.DrrOn = nextV ~= 0
		end
	end

	pages.styles = function(host)
		local c = pageScroll(host):GetCanvas()
		local cur = curStyle()

		sectionLabel(c, DrrT("ЦВЕТОВАЯ СХЕМА", "COLOR SCHEME"))

		for _, s in ipairs(STYLES) do
			local b = rowButton(c, DrrT(s.ru, s.en))

			b.DrrSwatch = s.a
			b.DrrOn = (s.id == cur.id)
			b.DoClick = function()
				RunConsoleCommand("drr_scout_menu_style", s.id)

				if DrrMenuRebuild then DrrMenuRebuild() end
			end
		end
	end

	local navButtons = {}

	local function buildPage(id)
		currentPage = id
		content:Clear()

		local builder = pages[id] or pages.systems
		builder(content)

		refresh()
	end

	-- сервер прислал фактические значения: перерисовываем страницы настроек
	function DrrMenuSyncPages()
		if not (frame and frame:IsValid()) then return end
		if currentPage == "ai" or currentPage == "perf" or currentPage == "profiles" then
			buildPage(currentPage)
		end
	end

	-- сменили стиль: перерисовываем текущий раздел, чтобы обновить отметки
	function DrrMenuRebuild()
		if frame and frame:IsValid() then buildPage(currentPage) end
	end

	for _, def in ipairs({
		{ id = "info", ru = "ИНФОРМАЦИЯ", en = "INFO" },
		{ id = "systems", ru = "СИСТЕМЫ", en = "SYSTEMS" },
		{ id = "squad", ru = "СТАЯ", en = "SQUAD" },
		{ id = "friends", ru = "ДРУЗЬЯ", en = "FRIENDS" },
		{ id = "ai", ru = "ИИ", en = "AI" },
		{ id = "profiles", ru = "СОХРАНЕНИЯ", en = "SAVED" },
		{ id = "perf", ru = "ПРОИЗВОДИТЕЛЬНОСТЬ", en = "PERFORMANCE" },
		{ id = "styles", ru = "СТИЛИ", en = "STYLES" },
	}) do
		local b = vgui.Create("DButton", nav)
		b:Dock(TOP)
		b:DockMargin(6, 0, 6, 2)
		b:SetTall(40)
		b:SetText("")
		b.DrrId = def.id
		b.DoClick = function()
			for _, o in ipairs(navButtons) do o.DrrActive = (o == b) end
			buildPage(def.id)
		end
		b.Paint = function(self, w, h)
			local S = curStyle()
			local active = self.DrrActive
			local hover = self:IsHovered()

			if active then
				surface.SetDrawColor(S.a.r, S.a.g, S.a.b, 40)
				surface.DrawRect(0, 0, w, h)
				surface.SetDrawColor(S.a.r, S.a.g, S.a.b, 220)
				surface.DrawRect(0, 0, 3, h)
			elseif hover then
				surface.SetDrawColor(S.a.r, S.a.g, S.a.b, 18)
				surface.DrawRect(0, 0, w, h)
			end

			draw.SimpleText(DrrT(def.ru, def.en), "DrrCrysisText", 14, h / 2,
				active and S.txt or Color(148, 178, 180), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end

		navButtons[#navButtons + 1] = b
	end

	navButtons[1].DrrActive = true
	buildPage("info")

	-- список стаи перерисовывается, пока открыт его раздел
	timer.Create("drr_scout_menu_squad", 0.6, 0, function()
		if not (frame and frame:IsValid()) then
			timer.Remove("drr_scout_menu_squad")
			return
		end

		if currentPage == "squad" then buildPage("squad") end
	end)

	timer.Create("drr_scout_skin_menu_refresh", 0.25, 0, function()
		if not (frame and frame:IsValid()) then timer.Remove("drr_scout_skin_menu_refresh") return end
		refresh()
	end)

	return true
end)

hook.Add("OnScreenSizeChanged", "drr_scout_skin_menu_resize", function()
	if frame and frame:IsValid() then frame:Center() end
end)

-- без открытия меню список друзей тоже нужен (сканер/подсветка)
hook.Add("InitPostEntity", "drr_scout_friends_sync", requestFriends)

-- ===== Оверлей кабины (drr_scout_overlay.lua) =====
-- Оверлей дрона DRR Scout: «Ceph» из Crysis 1.
-- Холодная бирюзово-синяя тональность, прозрачные тени, лёгкий иней в светах,
-- тонкая плёнка оптики (виньетка + скан-линия) по краям кадра.
-- Появляется в списке Overlay панели DRR и выбран по умолчанию
-- (ENT.OverlayName = "DRR Ceph" в shared.lua).
-- При включённой оптике (DrrNightVision) не накладывается.

local registered = false

hook.Remove("HUDPaint", "drr_scout_ceph_film")

local function lightGain(pos)
	local l = render.GetLightColor(pos)
	local lum = (l.r + l.g + l.b) / 3

	if lum > 1 then lum = lum / 255 end

	return math.Clamp(1 - (lum - 0.15) / 0.40, 0, 1)
end

-- Плёнка оптики: мягкая виньетка и медленная скан-линия.
-- Рисуется только когда реально применён наш оверлей и оптика выключена.
hook.Add("HUDPaint", "drr_scout_ceph_film", function()

	local ply = LocalPlayer()

	if not IsValid(ply) then return end

	local drone = ply:GetNWEntity("DronesRewriteDrone")

	if not IsValid(drone) or drone:GetClass() ~= "drr_scout_drr" then return end
	if DrrNightVision then return end

	-- камера стороннего мода (Enhanced ThirdPerson): не наш кадр
	if not (DrrDroneCameraOn and DrrDroneCameraOn(drone)) then return end
	local ov = drone.GetOverlayName and drone:GetOverlayName()
	if ov ~= "DRR Ceph" and ov ~= "DRR Red" then return end

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

	DRONES_REWRITE.Overlay["DRR Ceph"] = function(drone)
		if not IsValid(drone) then return end
		if not (DrrDroneCameraOn and DrrDroneCameraOn(drone)) then return end
		if DrrNightVision then return end

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
	DRONES_REWRITE.Overlay["DRR Red"] = function(drone)
		if not IsValid(drone) then return end
		if not (DrrDroneCameraOn and DrrDroneCameraOn(drone)) then return end
		if DrrNightVision then return end

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

hook.Add("Think", "drr_scout_overlay_register", function()
	register()

	if registered then hook.Remove("Think", "drr_scout_overlay_register") end
end)

-- ===== Переопределение методов класса (drr_scout_class.lua) =====
-- Позднее переопределение методов класса: при регистрации GMod копирует
-- поля базового класса поверх наших, поэтому методы из cl_init затирались
-- базовыми DRR (оверлей и HUD оставались чужими).
-- Ставим их прямо в зарегистрированную таблицу класса.

hook.Remove("Think", "drr_scout_class_override")

local function entTable()
	local stored = scripted_ents.GetStored("drr_scout_drr")

	if stored and stored.t then return stored.t end

	return scripted_ents.Get("drr_scout_drr")
end

hook.Add("Think", "drr_scout_class_override", function()
	local ENT = entTable()

	if not ENT then return end

	-- регистрация могла затереть поле базовым «Default»
	ENT.OverlayName = "DRR Ceph"

	-- «Use Default Overlay»: галка — наш DRR Ceph, снята — выбранный в списке.
	-- Оптика живёт только на нашем оверлее и сама гаснет при выборе другого.
	ENT.GetOverlayName = function(self)
		local cvs = DRONES_REWRITE and DRONES_REWRITE.ClientCVars

		if cvs and cvs.OverlayDef and not cvs.OverlayDef:GetBool() then
			local picked = cvs.CustomOverlay and cvs.CustomOverlay:GetString()

			if picked and picked ~= "" then return picked end
		end

		return self.OverlayName or "DRR Ceph"
	end

	-- Пресет HUD DRR для нашего дрона не рисует: HUD зовётся напрямую.
	ENT.GetHUDName = function()
		return "DRR Internal"
	end

	hook.Remove("Think", "drr_scout_class_override")
end)

-- ===== Камера автопилота (drr_scout_auto_cam.lua) =====
-- Автономный режим: ИИ перехватывает обзор, чтобы можно было спокойно наблюдать.
-- Камера DRR считается клиентом от EyeAngles пилота, поэтому наводим её здесь.

local AUTO_CAM_HOOK = "drr_scout_auto_cam"
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

	if not IsValid(drone) or drone:GetClass() ~= "drr_scout_drr" then return end
	if not drone:GetNWBool("DrrAuto") then return end

	local dir = drone:GetNWVector("DrrAutoDir", vector_origin)

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

-- ===== Скрытие модели пилота (drr_scout_pilot_model.lua) =====
-- Игроки, пилотирующие дрон DRR, для всех невидимы (без моделей-заглушек),
-- и HUD-пресеты DRR не помечают их как цели.

local hidden = {}

local function piloting(ply)
	return IsValid(ply:GetNWEntity("DronesRewriteDrone"))
end

hook.Add("Think", "drr_scout_pilot_hide", function()
	if CurTime() < (DrrPilotHideNext or 0) then return end
	DrrPilotHideNext = CurTime() + 0.1

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

	if not ok then ErrorNoHalt("[DRR Scout] HUD: " .. tostring(err) .. "\n") end
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
	hook.Remove("Think", "drr_scout_hud_wrap")
end

hook.Add("Think", "drr_scout_hud_wrap", wrapHud)

-- ===== Подсветка целей (drr_scout_vision.lua) =====
hook.Remove("PlayerBindPress", "drr_scout_vision")
hook.Remove("PostDrawTranslucentRenderables", "drr_scout_vision_glow")
-- F в режиме пилотирования: подсветка игроков и NPC обводкой.
-- Цвет обводки берётся из текущего overlay дрона DRR (Red → красная).

local enabled = false
local MAX_DIST = 6000

local function pilotDrone()
	local drone = LocalPlayer():GetNWEntity("DronesRewriteDrone")
	if IsValid(drone) and drone:GetClass() == "drr_scout_drr" then return drone end
end

local function toggleVision()
	if not pilotDrone() then return end

	enabled = not enabled
	DRRScoutVision = enabled


	print("[DRR Scout] vision =", enabled, "drone =", tostring(pilotDrone()))
end

concommand.Add("drr_scout_vision", toggleVision)

-- Диагностика: что видит подсветка и в каком состоянии каждая цель
concommand.Add("drr_scout_vision_dump", function()
	local drone = pilotDrone()
	if not drone then print("[DRR] дрон не найден") return end

	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) and e ~= drone and (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) then
			local bone = e:LookupBone("ValveBiped.Bip01_Head1")
			local bp = bone and e:GetBonePosition(bone)

			print(string.format("[DRR] %s | dormant=%s | bone=%s | bp=%s | dist=%d",
				e:GetClass(), tostring(e:IsDormant()), tostring(bone), type(bp),
				math.floor(drone:GetPos():Distance(e:GetPos()))))
		end
	end
end)

-- Цвет метки: друг — зелёный, враг — красный, нейтрал — жёлтый,
-- свой дрон — фиолетовый, чужой дрон — жёлтый
function DrrBlipColor(ent)
	if not IsValid(ent) then return Color(255, 220, 90) end

	-- дружественные игроки — салатовый
	if ent:IsPlayer() and DrrFriendSet and DrrFriendSet["@" .. ent:SteamID()] then
		return Color(170, 255, 90)
	end

	local cls = ent:GetClass()
	local owner = ent.GetNWEntity and ent:GetNWEntity("DrrOwner")
	local ownerID = ent.GetNWString and ent:GetNWString("DrrOwnerID")
	local me = LocalPlayer()

	if ent.IS_DRONE or cls == "drr_scout_drr" then
		local mine = (IsValid(owner) and owner == me)
			or (IsValid(me) and ownerID ~= "" and ownerID == me:SteamID())

		if mine then return Color(190, 120, 255) end

		return Color(255, 220, 90)
	end

	if DrrIsFriendClass and DrrIsFriendClass(cls) then
		return Color(120, 255, 150)
	end

	if IsEnemyEntityName and IsEnemyEntityName(cls) then
		return Color(255, 70, 70)
	end

	return Color(255, 220, 90)
end

hook.Add("PreDrawHalos", "drr_scout_vision_halos", function()
	if not enabled then return end

	local drone = pilotDrone()
	if not drone then return end

	local origin = drone:GetPos()
	local maxSqr = MAX_DIST * MAX_DIST
	local ply = LocalPlayer()
	local friends, enemies, neutrals, own, players = {}, {}, {}, {}, {}

	-- ночная оптика рисует свои контуры: иначе обводки складываются
	if DrrNightVision then return end

	-- список сущностей кешируем: ents.GetAll каждый кадр — дорого
	if not DrrVisionCache or CurTime() > (DrrVisionCacheAt or 0) then
		DrrVisionCache = ents.GetAll()
		DrrVisionCacheAt = CurTime() + 0.25
	end

	for _, e in ipairs(DrrVisionCache) do
		if e ~= drone and IsValid(e) and not e:IsDormant() then
			-- свой игрок обводится всегда, независимо от дистанции до дрона
			local inRange = e == ply or e:GetPos():DistToSqr(origin) <= maxSqr

			if (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) and inRange then
				local cls = e:GetClass()
				local owner = e.GetNWEntity and e:GetNWEntity("DrrOwner")

				if (e.IS_DRONE or cls == "drr_scout_drr") and IsValid(owner) and owner == ply then
					own[#own + 1] = e
				elseif e:IsPlayer() and DrrFriendSet and DrrFriendSet["@" .. e:SteamID()] then
					players[#players + 1] = e
				elseif DrrIsFriendClass and DrrIsFriendClass(cls) then
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

hook.Add("Think", "drr_scout_vision_key", function()
	if not pilotDrone() then
		fWasDown = false
		return
	end

	local down = input.IsKeyDown(KEY_F)

	if down and not fWasDown then toggleVision() end

	fWasDown = down
end)

-- ===== Настройки ИИ: значение переключается нажатием =====
DrrTuneState = DrrTuneState or {}

local DrrEN = CreateClientConVar("drr_scout_en", "0", true, false, "English interface")

local function DrrT(ru, en)
	return DrrEN:GetBool() and en or ru
end

local TUNE_TITLES_EN = {
	range = "SEARCH RANGE",
	engage = "FIRE RANGE",
	swarm = "ATTACKERS PER TARGET",
	heat = "BEAM OVERHEAT",
	cool = "BEAM COOLING",
	follow = "FOLLOW COMMANDER",
	formation = "FORMATION",
	formDist = "FORMATION SPACING",
	patrol = "PATROL AROUND POINT",
	leader = "COMMAND DRONE",
}

-- подписи нулевого значения: у каждого поля своё
local TUNE_ZERO = {
	swarm  = { "ВСЯ СТАЯ", "WHOLE SWARM" },
	range  = { "ВСЯ КАРТА", "WHOLE MAP" },
	engage = { "БЕЗ ЛИМИТА", "UNLIMITED" },
	heat   = { "ВЫКЛ", "OFF" },
}

-- у времени есть единицы, у остальных значений нет
local TUNE_UNIT = {
	heat = { " с", " s" },
	cool = { " с", " s" },
}

local TUNE_ROWS = {
	{ header = { "ДАЛЬНОСТЬ И БОЙ", "RANGE AND COMBAT" } },
	{ key = "drr_scout_ai_range",     field = "range",  title = "ДАЛЬНОСТЬ ПОИСКА",  steps = { 3000, 6000, 10000, 16000, 25000, 0 } },
	{ key = "drr_scout_engage_range", field = "engage", title = "ДИСТАНЦИЯ ОГНЯ",    steps = { 0, 1500, 2500, 4000, 6000 } },
	{ key = "drr_scout_swarm",        field = "swarm",  title = "АТАКУЮЩИХ НА ЦЕЛЬ", steps = { 0, 1, 2, 3, 5 } },

	{ header = { "ПЕРЕГРЕВ КРИОЛУЧА", "CRYO BEAM HEAT" } },
	{ key = "drr_scout_cryo_heat",    field = "heat",   title = "ПЕРЕГРЕВ ЛУЧА",     steps = { 4, 6, 10, 15, 20, 0 } },
	{ key = "drr_scout_cryo_cool",    field = "cool",   title = "ОСТЫВАНИЕ ЛУЧА",   steps = { 1, 1.5, 2.5, 4, 6, 10 } },

	{ header = { "ПАТРУЛЬ", "PATROL" } },
	{ key = "drr_scout_patrol",       field = "patrol", title = "ПАТРУЛЬ",           steps = { 0, 1 }, names = { { "СВОБОДНЫЙ ПОЛЁТ", "FREE FLIGHT" }, { "ВОКРУГ ТОЧКИ", "AROUND POINT" } } },

	{ header = { "СТАЯ И СТРОЙ", "SWARM AND FORMATION" } },
	{ key = "drr_scout_follow",       field = "follow", title = "СЛЕДОВАНИЕ",        steps = { 0, 1 }, names = { { "ВЫКЛ", "OFF" }, { "ЗА КОМАНДНЫМ", "BEHIND LEADER" } } },
	{ key = "drr_scout_formation",    field = "formation", title = "СТРОЙ",          steps = { 0, 1, 2, 3, 4 }, names = { { "КЛИН", "WEDGE" }, { "КОЛОННА", "COLUMN" }, { "КРУГ", "CIRCLE" }, { "ЛИНИЯ", "LINE" }, { "СВОБОДНЫЙ", "FREE" } } },
	{ key = "drr_scout_form_dist",    field = "formDist",  title = "ДИСТАНЦИЯ СТРОЯ", steps = { 620, 820, 1100, 1500 }, unit = { "", "" } },
	{ key = "leader",                 field = "leader", title = "КОМАНДНЫЙ ДРОН",    steps = { 0, 1 }, names = { { "ВЫКЛ", "OFF" }, { "ЭТОТ ДРОН", "THIS DRONE" } } },
}

local function tuneValue(row)
	local v = DrrTuneState[row.field]

	if v == nil then return row.steps[1] end

	-- старые сборки оставляли дистанцию строя вроде 50: приводим к рабочему диапазону
	if row.field == "formDist" then return math.Clamp(v, 620, 1600) end

	return v
end

local function tuneNext(row, value)
	for i, v in ipairs(row.steps) do
		if v == value then return row.steps[i % #row.steps + 1] end
	end

	return row.steps[1]
end

local function tuneLabel(row, value)
	local title = DrrEN:GetBool() and (TUNE_TITLES_EN[row.field] or row.title) or row.title

	-- строки-переключатели: вместо числа показываем название режима
	if row.names then
		for i, v in ipairs(row.steps) do
			if v == value and row.names[i] then
				return title .. ": " .. DrrT(row.names[i][1], row.names[i][2])
			end
		end
	end

	local zero = TUNE_ZERO[row.field]

	if zero and value == 0 then
		return title .. ": " .. DrrT(zero[1], zero[2])
	end

	local unit = TUNE_UNIT[row.field]
	local suffix = unit and DrrT(unit[1], unit[2]) or ""
	local text = (value ~= math.floor(value)) and string.format("%.1f", value) or tostring(value)

	return title .. ": " .. text .. suffix
end

-- ===== Профили настроек: 3 слота, файл data/drr_scout_drr/<id>_profiles.txt =====
local profileCache, profileCacheAt

local function profilePath()
	return "drr_scout_drr/" .. (LocalPlayer():SteamID64() or "local") .. "_profiles.txt"
end

local function profileSlots(force)
	if not force and profileCache and CurTime() < (profileCacheAt or 0) then
		return profileCache
	end

	local raw = file.Read(profilePath(), "DATA")
	local data = (raw and util.JSONToTable(raw)) or {}

	-- JSONToTable отдаёт ключи то числом, то строкой: приводим к числу,
	-- иначе сохранение добавляло второй слот "1" рядом с существующим 1
	local norm = {}

	for k, v in pairs(data) do
		local n = tonumber(k)

		if n and n >= 1 and n <= 3 and type(v) == "table" then
			norm[n] = v
		end
	end

	profileCache = norm
	profileCacheAt = CurTime() + 1

	return profileCache
end

local function DrrSaveProfile(slot)
	local data = profileSlots(true)
	local st = DrrTuneState or {}
	local set = {}

	for _, row in ipairs(TUNE_ROWS) do
		if row.key and row.key ~= "leader" then
			set[row.key] = st[row.field] or row.steps[1]
		end
	end

	data[slot] = set

	file.CreateDir("drr_scout_drr")
	file.Write(profilePath(), util.TableToJSON(data))

	profileSlots(true)

	chat.AddText(Color(110, 235, 215), "[DRR Scout] ", Color(220, 255, 248),
		DrrT("Профиль ", "Profile ") .. slot .. DrrT(" сохранён", " saved"))

	if DrrMenuSyncPages then DrrMenuSyncPages() end
end

local function DrrLoadProfile(slot)
	local set = profileSlots()[slot]

	if not set then
		chat.AddText(Color(110, 235, 215), "[DRR Scout] ", Color(255, 178, 84),
			DrrT("Профиль пуст", "Profile is empty"))
		return
	end

	DrrTuneState = DrrTuneState or {}

	for _, row in ipairs(TUNE_ROWS) do
		local v = row.key and row.key ~= "leader" and set[row.key]

		if v ~= nil then
			DrrTuneState[row.field] = v
			sendSetting(row.key, v)
		end
	end

	if IsValid(tuneFrame) and tuneFrame.DrrSync then tuneFrame:DrrSync() end
	if DrrMenuSyncPages then DrrMenuSyncPages() end

	-- сервер подтверждает фактическое состояние
	timer.Simple(0.25, function()
		net.Start("drr_scout_getsetting")
		net.SendToServer()
	end)

	chat.AddText(Color(110, 235, 215), "[DRR Scout] ", Color(220, 255, 248),
		DrrT("Профиль ", "Profile ") .. slot .. DrrT(" загружен", " loaded"))
end

-- Страница «СОХРАНЕНИЯ»: только слоты профилей
function DrrBuildProfilesPage(canvas, makeRow, makeSection)
	local slots = profileSlots()

	makeSection(canvas, DrrT("СЛОТЫ · ЛКМ ЗАГРУЗИТЬ / ПКМ СОХРАНИТЬ", "SLOTS · LMB LOAD / RMB SAVE"))

	for i = 1, 3 do
		local b = makeRow(canvas, DrrT("ПРОФИЛЬ ", "PROFILE ") .. i, 34)

		b.DrrOn = slots[i] ~= nil
		b.DoClick = function() DrrLoadProfile(i) end
		b.DoRightClick = function() DrrSaveProfile(i) end
	end

	local hint = vgui.Create("DLabel", canvas)
	hint:Dock(TOP)
	hint:DockMargin(2, 6, 0, 0)
	hint:SetTall(44)
	hint:SetWrap(true)
	hint:SetFont("DrrCrysisSmall")
	hint:SetTextColor(Color(90, 150, 148))
	hint:SetText(DrrT("ЛКМ — применить профиль, ПКМ — записать текущие настройки ИИ в слот.",
		"LMB applies a profile, RMB writes the current AI settings into the slot."))
end

-- Страница «ИИ»: строки настроек
function DrrBuildAiPage(canvas, makeRow, makeSection)
	for _, row in ipairs(TUNE_ROWS) do
		if row.header then
			makeSection(canvas, DrrT(row.header[1], row.header[2]))
		else
			local b = makeRow(canvas, tuneLabel(row, tuneValue(row)))

			b.DoClick = function()
				DrrTuneState = DrrTuneState or {}

				-- командный дрон назначается на сервере, а не конваром
				if row.key == "leader" then
					DrrTuneState[row.field] = (tuneValue(row) ~= 0) and 0 or 1

					net.Start("drr_scout_leader")
					net.SendToServer()

					b.DrrText = tuneLabel(row, tuneValue(row))
					return
				end

				local v = tuneNext(row, tuneValue(row))

				DrrTuneState[row.field] = v
				sendSetting(row.key, v)

				b.DrrText = tuneLabel(row, v)
			end
		end
	end
end

function DrrOpenTune()
	if IsValid(tuneFrame) then tuneFrame:Remove() end

	tuneFrame = vgui.Create("DFrame")
	tuneFrame:SetSize(420, 760)
	tuneFrame:SetPos(sidePos(-432, 420))
	tuneFrame:SetTitle("")
	tuneFrame:MakePopup()
tuneFrame.PaintBackground = function() end

	-- подтягиваем фактические значения, иначе строки показывают первые из списка
	net.Start("drr_scout_getsetting")
	net.SendToServer()

	local f = tuneFrame
	local rows = {}

	f.Paint = function(self, w, h)
		cephBackdrop(w, h, 16)
		draw.SimpleText(DrrT("НАСТРОЙКИ ИИ", "AI SETTINGS"), "DrrCrysisTitle", 18, 14, Color(220, 255, 248))
		draw.SimpleText(DrrT("НАЖМИ НА СТРОКУ, ЧТОБЫ ПЕРЕКЛЮЧИТЬ", "CLICK A ROW TO CYCLE"), "DrrCrysisSmall", 18, 42, ACCENT_DIM)
	end

	local y = 72

	for _, row in ipairs(TUNE_ROWS) do
		-- секция-заголовок: разделяет группы настроек
		if row.header then
			local lbl = vgui.Create("DLabel", f)
			lbl:SetPos(18, y + 6)
			lbl:SetSize(384, 18)
			lbl:SetFont("DrrCrysisSmall")
			lbl:SetTextColor(Color(80, 160, 158))
			lbl:SetText(DrrT(row.header[1], row.header[2]))

			y = y + 24
			continue
		end

		local btn = vgui.Create("DButton", f)
		btn:SetSize(384, 44)
		btn:SetPos(18, y)
		btn:SetText("")

		local function refresh()
			btn.DrrText = tuneLabel(row, tuneValue(row))
		end

	btn.DoClick = function()
		-- командный дрон назначается на сервере, а не конваром
		if row.key == "leader" then
			DrrTuneState[row.field] = (tuneValue(row) ~= 0) and 0 or 1

			net.Start("drr_scout_leader")
			net.SendToServer()

			refresh()

			-- сервер подтверждает фактическое состояние
			timer.Simple(0.25, function()
				if IsValid(tuneFrame) then
					net.Start("drr_scout_getsetting")
					net.SendToServer()
				end
			end)

			return
		end

		local v = tuneNext(row, tuneValue(row))

			DrrTuneState[row.field] = v

			net.Start("drr_scout_setting")
			net.WriteString(row.key)
			net.WriteString(tostring(v))
			net.SendToServer()

			refresh()
		end

		btn.Paint = function(self, w, h)
			local hover = self:IsHovered()

			surface.SetDrawColor(hover and 12 or 6, hover and 30 or 16, hover and 30 or 18, 235)
			surface.DrawRect(0, 0, w, h)

			surface.SetDrawColor(hover and ACCENT or ACCENT_DIM)
			surface.DrawOutlinedRect(0, 0, w, h, 1)

			-- Ceph-акцент: полоса слева и ромб-маркер
			surface.SetDrawColor(110, 235, 215, hover and 230 or 140)
			surface.DrawRect(0, 0, 2, h)

			local cy = h / 2
			surface.SetDrawColor(110, 235, 215, hover and 240 or 170)
			surface.DrawLine(w - 16, cy - 4, w - 12, cy)
			surface.DrawLine(w - 12, cy, w - 16, cy + 4)
			surface.DrawLine(w - 16, cy + 4, w - 20, cy)
			surface.DrawLine(w - 20, cy, w - 16, cy - 4)

			draw.SimpleText(self.DrrText or "", "DrrCrysisText", 14, h / 2,
				hover and Color(200, 245, 240) or Color(170, 225, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end

		refresh()

		rows[#rows + 1] = refresh
		y = y + 50
	end

	-- профили: ЛКМ — загрузить, ПКМ — сохранить
	local profLbl = vgui.Create("DLabel", f)
	profLbl:SetPos(18, y + 4)
	profLbl:SetSize(384, 18)
	profLbl:SetFont("DrrCrysisSmall")
	profLbl:SetTextColor(Color(80, 160, 158))
	profLbl:SetText(DrrT("ПРОФИЛИ · ЛКМ ЗАГРУЗИТЬ / ПКМ СОХРАНИТЬ", "PROFILES · LMB LOAD / RMB SAVE"))

	y = y + 26

	for i = 1, 3 do
		local b = vgui.Create("DButton", f)
		b:SetPos(18 + (i - 1) * 130, y)
		b:SetSize(120, 34)
		b:SetText("")

		b.DoClick = function() DrrLoadProfile(i) end
		b.DoRightClick = function() DrrSaveProfile(i) end

		b.Paint = function(self, w, h)
			local hover = self:IsHovered()
			local used = profileSlots()[i] ~= nil

			surface.SetDrawColor(hover and 12 or 6, hover and 30 or 16, hover and 30 or 18, 235)
			surface.DrawRect(0, 0, w, h)

			surface.SetDrawColor(hover and ACCENT or ACCENT_DIM)
			surface.DrawOutlinedRect(0, 0, w, h, 1)

			draw.SimpleText(DrrT("ПРОФИЛЬ ", "PROFILE ") .. i, "DrrCrysisSmall", 10, h / 2,
				used and Color(205, 255, 245) or Color(120, 170, 168), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

			draw.SimpleText(used and "◈" or "·", "DrrCrysisSmall", w - 12, h / 2,
				used and ACCENT or ACCENT_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end

	f.DrrSync = function()
		for _, refresh in ipairs(rows) do refresh() end
	end
end
