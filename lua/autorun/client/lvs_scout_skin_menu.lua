-- Меню оператора в стиле интерфейса Crysis 1 (нанокостюм): расцветка, щит, ночь, автомодуль

local frame
local colorBtn, shieldBtn, nightBtn, autoBtn, autoAllBtn
local night = false

surface.CreateFont("LvsCrysisTitle", { font = "Roboto", size = 20, weight = 700, extended = true })
surface.CreateFont("LvsCrysisText", { font = "Roboto", size = 15, weight = 500, extended = true })
surface.CreateFont("LvsCrysisSmall", { font = "Roboto", size = 12, weight = 500, extended = true })

local ACCENT = Color(175, 228, 255)
local ACCENT_DIM = Color(80, 130, 165)
local CUT = 18

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

			surface.SetDrawColor(18, hover and 46 or 28, 26, 210)
			surface.DrawRect(0, 0, w, h)

			local isPlayer = entry:sub(1, 1) == "@"

			draw.SimpleText(label(entry), "LvsCrysisText", 8, h / 2,
				isPlayer and Color(170, 255, 90) or Color(120, 255, 150),
				TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

			draw.SimpleText("×", "LvsCrysisText", w - 10, h / 2,
				hover and Color(255, 120, 120) or ACCENT_DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
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

		surface.SetDrawColor(hover and 26 or 16, hover and 40 or 28, hover and 50 or 36, 220)
		surface.DrawRect(0, 0, w, h)

		-- верхняя тонкая линия
		surface.SetDrawColor(175, 228, 255, hover and 120 or 45)
		surface.DrawRect(0, 0, w, 1)

		-- нижняя линия: у включённого состояния ярче
		surface.SetDrawColor(175, 228, 255, on and 220 or (hover and 120 or 40))
		surface.DrawRect(0, h - (on and 2 or 1), w, on and 2 or 1)

		-- индикатор состояния
		if on then
			surface.SetDrawColor(175, 228, 255, 230)
			surface.DrawRect(12, h / 2 - 3, 6, 6)
		else
			surface.SetDrawColor(80, 130, 165, 180)
			surface.DrawOutlinedRect(12, h / 2 - 3, 6, 6, 1)
		end

		local col = hover and Color(230, 245, 255) or (on and ACCENT or Color(150, 190, 215))
		draw.SimpleText(self.LvsText or "", "LvsCrysisText", 28, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		-- шеврон при наведении
		if hover then
			draw.SimpleText(">", "LvsCrysisText", w - 14, h / 2, ACCENT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end

	return b
end

hook.Add("PlayerBindPress", "lvs_scout_skin_menu", function(ply, bind, pressed)
	if not pressed or bind ~= "gm_showspare1" then return end
	if not pilotDrone() then return end

	if frame and frame:IsValid() then
		frame:Remove()
		frame = nil
		return true
	end

	frame = vgui.Create("DFrame")
	frame:SetSize(400, 620)
	frame:Center()
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:MakePopup()

	frame.Paint = function(self, w, h)
		-- корпус со срезанным правым верхним углом
		surface.SetDrawColor(12, 20, 26, 238)
		surface.DrawPoly({
			{ x = 0, y = 0 },
			{ x = w - CUT, y = 0 },
			{ x = w, y = CUT },
			{ x = w, y = h },
			{ x = 0, y = h },
		})

		-- верхняя полоса-градиент (имитация подсветки панели)
		surface.SetDrawColor(40, 70, 90, 90)
		surface.DrawRect(0, 0, w - CUT, 54)

		-- контур: сверху, по срезу, справа, снизу, слева
		surface.SetDrawColor(175, 228, 255, 150)
		surface.DrawLine(0, 0, w - CUT, 0)
		surface.DrawLine(w - CUT, 0, w, CUT)
		surface.DrawLine(w - 1, CUT, w - 1, h - 1)
		surface.DrawLine(0, h - 1, w - 1, h - 1)
		surface.DrawLine(0, 0, 0, h - 1)

		-- мелкие засечки по углам
		surface.SetDrawColor(175, 228, 255, 200)
		surface.DrawRect(0, 0, 2, 14)
		surface.DrawRect(0, h - 14, 2, 13)
		surface.DrawRect(w - 14, h - 2, 14, 2)

		draw.SimpleText("SCOUT // CEPH", "LvsCrysisTitle", 18, 12, Color(235, 247, 255))
		draw.SimpleText("ОПЕРАТОР: " .. (IsValid(LocalPlayer()) and LocalPlayer():Nick() or "-"),
			"LvsCrysisSmall", 18, 36, ACCENT_DIM)

		draw.SimpleText("ДРУЖЕСТВЕННЫЕ NPC — ВПИШИТЕ КЛАСС ВРУЧНУЮ", "LvsCrysisSmall", 18, 344, ACCENT_DIM)

		surface.SetDrawColor(175, 228, 255, 70)
		surface.DrawRect(18, 58, w - 36, 1)

		draw.SimpleText("F3 — ЗАКРЫТЬ", "LvsCrysisSmall", w - 18, h - 16,
			Color(80, 130, 165), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	end

	local closeBtn = vgui.Create("DButton", frame)
	closeBtn:SetSize(30, 30)
	closeBtn:SetPos(400 - 38, 6)
	closeBtn:SetText("")
	closeBtn.DoClick = function()
		frame:Remove()
		frame = nil
	end

	closeBtn.Paint = function(self, w, h)
		local hover = self:IsHovered()

		if hover then
			surface.SetDrawColor(175, 228, 255, 30)
			surface.DrawRect(0, 0, w, h)
		end

		draw.SimpleText("×", "LvsCrysisText", w / 2, h / 2 - 1,
			hover and Color(255, 120, 120) or ACCENT_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	colorBtn = crysisButton(frame, 76, function()
		local drone = pilotDrone()
		if not drone then return end
		sendSkin(drone:GetNWInt("LvsSkin", 0) == 1 and 0 or 1)
	end)

	shieldBtn = crysisButton(frame, 128, function()
		local drone = pilotDrone()
		if not drone then return end
		sendShield(not drone:GetNWBool("hasModuleShield"))
	end)

	nightBtn = crysisButton(frame, 180, function() sendNight(true) end)

	autoBtn = crysisButton(frame, 232, function()
		local drone = pilotDrone()
		if not drone then return end
		sendAuto(not drone:GetNWBool("LvsAuto"))
	end)

	-- включает автономность всем своим дронам, где она ещё выключена
	autoAllBtn = crysisButton(frame, 284, function()
		local ok = pcall(net.Start, "lvs_scout_auto_all")

		if not ok then
			chat.AddText(Color(255, 120, 120), "[LVS Scout] Сервер не знает команду — перезапусти GMod")
			return
		end

		net.SendToServer()
	end)

	autoAllBtn.LvsText = "АВТОНОМНОСТЬ: ВКЛЮЧИТЬ ВСЕМ"

	friendEntry = vgui.Create("DTextEntry", frame)
	friendEntry:SetPos(18, 364)
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

		surface.SetDrawColor(175, 228, 255, self:IsEditing() and 200 or 80)
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
	addBtn:SetPos(272, 364)
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

		surface.SetDrawColor(175, 228, 255, hover and 220 or 90)
		surface.DrawOutlinedRect(0, 0, w, h, 1)

		draw.SimpleText("ДОБАВИТЬ", "LvsCrysisSmall", w / 2, h / 2,
			hover and Color(230, 245, 255) or ACCENT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	friendScroll = vgui.Create("DScrollPanel", frame)
	friendScroll:SetPos(18, 404)
	friendScroll:SetSize(364, 150)

	sendNight(false)
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
timer.Simple(3, requestFriends)
