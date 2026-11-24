-- Пресет HUD "Crysis Ceph" — по структуре DRR "Drones 2",
-- но в стиле нанокостюма Crysis 1 / биолюминесцентных Цефов.
-- Только визуал: данные берутся те же, что и у Drones 2.

-- регистрируем пресет, когда DRR уже загружен (иначе таблицы HUD ещё нет)

-- Заголовки: узкий полужирный, с разрядкой (стиль Crysis)
surface.CreateFont("LvsCephTitle", {
	font = "Bahnschrift SemiBold Condensed",
	size = 18,
	weight = 600,
	antialias = true,
	extended = true,
})

-- Значения: тонкий, крупнее
surface.CreateFont("LvsCephValue", {
	font = "Bahnschrift Light Condensed",
	size = 19,
	weight = 300,
	antialias = true,
	extended = true,
})

-- Мелкие подписи
surface.CreateFont("LvsCephSmall", {
	font = "Bahnschrift Light Condensed",
	size = 16,
	weight = 250,
	antialias = true,
	extended = true,
})

-- Крупный акцент (критическое состояние)
surface.CreateFont("LvsCeph", {
	font = "Bahnschrift SemiBold Condensed",
	size = 22,
	weight = 600,
	antialias = true,
	extended = true,
})

-- Состояние ночи приходит с сервера (см. lvs_scout_gweather.lua)
LvsGWNight = false

net.Receive("lvs_scout_gw_state", function()
	LvsGWNight = net.ReadBool()
end)

local CYAN = Color(120, 235, 255)
local CYAN_DIM = Color(60, 170, 200, 170)
local CEPH = Color(130, 255, 210)
local WARN = Color(255, 165, 60)
local DANGER = Color(255, 70, 70)
local FRIEND = Color(120, 255, 150)

local function anchor(drone)
	local cam = drone:GetCamera()
	local pos = IsValid(cam) and cam:GetPos() or drone:GetPos()
	local ang = drone.CamAngles or drone:GetAngles()

	return pos + ang:Forward() * 200
end

-- Угловые скобки (стиль Crysis)
local function brackets(x, y, w, h, size, col)
	surface.SetDrawColor(col)
	surface.DrawLine(x, y, x + size, y)
	surface.DrawLine(x, y, x, y + size)
	surface.DrawLine(x + w, y, x + w - size, y)
	surface.DrawLine(x + w, y, x + w, y + size)
	surface.DrawLine(x, y + h, x + size, y + h)
	surface.DrawLine(x, y + h, x, y + h - size)
	surface.DrawLine(x + w, y + h, x + w - size, y + h)
	surface.DrawLine(x + w, y + h, x + w, y + h - size)
end

-- Полоса в стиле Crysis: только контуры сегментов, без сплошной заливки
local function bar(x, y, w, h, frac, col)
	frac = math.Clamp(frac, 0, 1)

	local segs = 20
	local sw = (w - (segs - 1) * 2) / segs
	local on = frac * segs

	for i = 0, segs - 1 do
		local active = i < on

		if active then
			surface.SetDrawColor(Color(col.r, col.g, col.b, 230))
			surface.DrawOutlinedRect(x + i * (sw + 2), y, sw, h)
			surface.DrawOutlinedRect(x + i * (sw + 2) + 1, y + 1, sw - 2, h - 2)
		else
			surface.SetDrawColor(Color(col.r, col.g, col.b, 45))
			surface.DrawOutlinedRect(x + i * (sw + 2), y, sw, h)
		end
	end
end
-- «Полый» текст (только контур глифа): рисуем смещения, центр не закрашиваем
-- Разрядка между буквами (Crysis-стиль)
local function spaced(s)
	local up = string.upper(s)
	return (up:gsub("(.)", "%1 "):gsub("%s+$", ""))
end

-- Заголовок: мягкое свечение + чёткий тонкий глиф
local function titleText(text, x, y, col)
	local t = spaced(text)

	draw.SimpleText(t, "LvsCephTitle", x, y, Color(col.r, col.g, col.b, 40), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	draw.SimpleText(t, "LvsCephTitle", x, y, Color(col.r, col.g, col.b, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end

-- Значение: с тонкой тёмной обводкой, чтобы читалось на любом фоне
local function valueText(text, x, y, col, xalign)
	draw.SimpleTextOutlined(text, "LvsCephValue", x, y, col, xalign or TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 190))
end

-- Знак бесконечности: два жирных кольца, всегда яркие
local function infinityIcon(x, y, col)
	surface.SetDrawColor(col)
	surface.DrawCircle(x - 7, y, 9, col.r, col.g, col.b, 255)
	surface.DrawCircle(x + 7, y, 9, col.r, col.g, col.b, 255)

	surface.SetDrawColor(Color(col.r, col.g, col.b, 140))
	surface.DrawCircle(x - 7, y, 7, col.r, col.g, col.b, 140)
	surface.DrawCircle(x + 7, y, 7, col.r, col.g, col.b, 140)
end

-- Человекочитаемая подпись цели (для режима подсветки)
local function friendlyClass(class)
	local c = string.lower(class)

	if c == "lvs_scout_drr" then return "SCOUT" end

	if c:find("combine") or c == "npc_metropolice" then return "COMBINE" end
	if c:find("headcrab") then return "HEADCRAB" end
	if c:find("zombie") then return "ZOMBIE" end
	if c:find("antlion") then return "ANTLION" end
	if c:find("manhack") then return "MANHACK" end
	if c:find("turret") then return "TURRET" end
	if c:find("vortigaunt") then return "VORTIGAUNT" end
	if c:find("citizen") then return "CITIZEN" end
	if c:find("strider") or c:find("gunship") or c:find("helicopter") or c:find("dropship") then return "SYNTH" end
	if c:find("scanner") then return "SCANNER" end
	if c:find("player") then return "PLAYER" end

	return string.upper(c:gsub("^npc_", ""))
end

-- кеш списка сущностей для режима сканирования (чтобы не звать ents.GetAll каждый кадр)
local scanCache, scanAt = nil, 0

-- отдельный кеш для радара
local radarCache, radarAt = nil, 0
local RADAR_RANGE = 6000

local function enemyCol(class)
	if IsEnemyEntityName(class) then return DANGER end
	return CEPH
end

local function drawCrysis(drone)
	local shouldDrawCrosshair = drone.HUD_shouldDrawCrosshair and DRONES_REWRITE.ClientCVars.DrawCrosshair:GetBool()
	local shouldDrawHealth = drone.HUD_shouldDrawHealth and DRONES_REWRITE.ClientCVars.DrawHealth:GetBool()
	local shouldDrawTargets = drone.HUD_shouldDrawTargets and DRONES_REWRITE.ClientCVars.DrawTargets:GetBool()
	local shouldDrawFuel = drone.HUD_shouldDrawFuel and DRONES_REWRITE.ClientCVars.DrawFuel:GetBool()
	local shouldDrawWeps = drone.HUD_shouldDrawWeps and DRONES_REWRITE.ClientCVars.DrawWeps:GetBool()
	local shouldDetectDamage = drone.HUD_shouldDetectDamage and DRONES_REWRITE.ClientCVars.DetectDamage:GetBool()
	local shouldDrawCenter = drone.HUD_shouldDrawCenter and DRONES_REWRITE.ClientCVars.DrawCenter:GetBool()

	local sw, sh = ScrW(), ScrH()
	local center = anchor(drone):ToScreen()
	local cx, cy = center.x, center.y

	if not drone:HasFuel() then return end

	-- ===== Цели: биолюминесцентные скобки Цефов =====
	if shouldDrawTargets then
		local list

		if LVSScoutVision then
			-- режим сканирования (F): все цели в радиусе, даже за стенами
			if not scanCache or CurTime() > scanAt then
				scanCache = ents.GetAll()
				scanAt = CurTime() + 0.2
			end

			list = scanCache
		else
			local tr = drone:GetCameraTraceLine(nil, Vector(-32, -32, 0), Vector(32, 32, 0))
			list = ents.FindInSphere(tr.HitPos, 640)
		end

		for _, v in pairs(list) do
			if not IsValid(v) then continue end
			if v == drone then continue end
			if not v:IsPlayer() and not v:IsNPC() and not v:IsNextBot() and not v.IS_DRONE then continue end
			if v.IS_DRR and v:IsDroneDestroyed() then continue end

			-- пилотов не помечаем: их модели скрыты, метка висела бы в пустоте
			if v:IsPlayer() and IsValid(v:GetNWEntity("DronesRewriteDrone")) then continue end

			-- у части NPC (antlion и др.) кости головы может не быть — тогда берём центр модели
			local pos = v:WorldSpaceCenter()

			local bone = v:LookupBone("ValveBiped.Bip01_Head1")
			if bone then
				local bp = v:GetBonePosition(bone)
				if isvector(bp) then pos = bp end
			end

			if not isvector(pos) then continue end

			local distSqr = drone:GetPos():DistToSqr(pos)

			if LVSScoutVision then
				if distSqr > 6000 * 6000 then continue end
			else
				local los = util.TraceLine({ start = drone:GetPos(), endpos = pos, filter = drone })
				if los.Entity ~= v then continue end
			end

			local size = 78 - math.Clamp(drone:GetPos():Distance(pos) * 0.03, 18, 78)
			local scr = pos:ToScreen()
			local isFriend = LvsIsFriendClass and LvsIsFriendClass(v:GetClass())
			local col = isFriend and FRIEND or enemyCol(v:GetClass())

			local pulse = 0.55 + 0.45 * math.abs(math.sin(CurTime() * 2.5))
			col = Color(col.r, col.g, col.b, 90 + 120 * pulse)

			brackets(scr.x - size * 0.5, scr.y - size * 0.5, size, size, size * 0.35, col)

			surface.SetDrawColor(Color(col.r, col.g, col.b, 60))
			surface.DrawCircle(scr.x, scr.y, size * 0.18, col.r, col.g, col.b, 60)

			-- подпись всегда человекочитаемая: у игроков ник, у NPC — тип
			local label = v:IsPlayer() and v:Nick() or friendlyClass(v:GetClass())
			if isFriend then label = label .. " · FRIEND" end
			draw.SimpleText(label, "LvsCephSmall", scr.x + size * 0.5 + 6, scr.y - 8, Color(col.r, col.g, col.b, 170))
		end
	end

	-- ===== Левая колонка: единая сетка панелей =====
	local px = cx - 470
	local pw = 246

	local function panel(y, h)
		brackets(px, y, pw, h, 14, CYAN_DIM)
	end

	local function sectionValue(y, v) valueText(v, px + 10, y + 42, CYAN_DIM) end

	-- ENERGY
	if shouldDrawFuel then
		local y = cy - 200
		local frac = drone:GetFuel() / drone.MaxFuel

		panel(y, 74)
		titleText("ENERGY", px + 10, y + 8, CYAN)
		bar(px + 10, y + 30, pw - 20, 8, frac, CYAN)
		sectionValue(y, math.floor(frac * 100) .. "%  [" .. math.floor(drone:GetFuel()) .. "/" .. drone.MaxFuel .. "]")
	end

	-- INTEGRITY
	if shouldDrawHealth then
		local y = cy - 118
		local frac = drone:GetHealth() / drone:GetDefaultHealth()
		local col = frac < 0.34 and DANGER or CYAN

		panel(y, 74)
		titleText("INTEGRITY", px + 10, y + 8, CYAN)
		bar(px + 10, y + 30, pw - 20, 8, frac, col)
		sectionValue(y, math.floor(drone:GetHealth()) .. " / " .. math.floor(drone:GetDefaultHealth()))
	end

	-- SHIELD / COLOR / LIGHT
	do
		local y = cy - 36
		panel(y, drone:GetClass() == "lvs_scout_drr" and 166 or 132)

		local shield = drone:GetNWBool("hasModuleShield")
		titleText("SHIELD", px + 10, y + 8, CYAN)
		valueText(shield and "ON" or "OFF", px + pw - 14, y + 6, shield and CEPH or Color(150, 160, 170), TEXT_ALIGN_RIGHT)

		local charge = drone:GetNWInt("shield_health", 0)
		local maxCharge = math.max(math.floor(drone:GetDefaultHealth() / 2), 1)
		local frac = math.Clamp(charge / maxCharge, 0, 1)

		bar(px + 10, y + 30, pw - 76, 8, frac, shield and CEPH or Color(120, 130, 140))
		valueText(math.floor(frac * 100) .. "%", px + pw - 14, y + 24, shield and CEPH or Color(150, 160, 170), TEXT_ALIGN_RIGHT)

		surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 40))
		surface.DrawLine(px + 8, y + 56, px + pw - 8, y + 56)

		local red = drone:GetNWInt("LvsSkin", 0) == 1
		titleText("COLOR", px + 10, y + 64, CYAN)
		valueText(red and "RED" or "DEFAULT", px + pw - 14, y + 62, red and DANGER or CYAN, TEXT_ALIGN_RIGHT)

		surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 40))
		surface.DrawLine(px + 8, y + 92, px + pw - 8, y + 92)

		local night = LvsGWNight
		titleText("LIGHT", px + 10, y + 100, CYAN)
		valueText(night and "NIGHT" or "DAY", px + pw - 14, y + 98, night and Color(140, 170, 255) or WARN, TEXT_ALIGN_RIGHT)

		if drone:GetClass() == "lvs_scout_drr" then
			surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 40))
			surface.DrawLine(px + 8, y + 126, px + pw - 8, y + 126)

			local auto = drone:GetNWBool("LvsAuto")
			titleText("AUTO", px + 10, y + 134, CYAN)
			valueText(auto and "MODULE ON" or "OFF", px + pw - 14, y + 132, auto and CEPH or Color(150, 160, 170), TEXT_ALIGN_RIGHT)
		end
	end

	-- AMMO (у нашего дрона — бесконечность)
	if shouldDrawWeps then
		local inf = drone:GetClass() == "lvs_scout_drr"

		local y1 = cy + 142
		panel(y1, 74)
		titleText("PRIMARY", px + 10, y1 + 8, CYAN)

		local f1 = inf and 1 or drone:GetPrimaryAmmo() / math.max(drone:GetPrimaryMax(), 1)
		bar(px + 10, y1 + 30, pw - 20, 8, f1, WARN)

		if inf then
			infinityIcon(px + 22, y1 + 56, WARN)
		else
			valueText(drone:GetPrimaryAmmo() .. " / " .. drone:GetPrimaryMax(), px + 10, y1 + 44, CYAN_DIM)
		end

		local y2 = cy + 226
		panel(y2, 74)
		titleText("SECONDARY", px + 10, y2 + 8, CYAN)

		local f2 = inf and 1 or drone:GetSecondaryAmmo() / math.max(drone:GetSecondaryMax(), 1)
		bar(px + 10, y2 + 30, pw - 20, 8, f2, WARN)

		if inf then
			infinityIcon(px + 22, y2 + 56, WARN)
		else
			valueText(drone:GetSecondaryAmmo() .. " / " .. drone:GetSecondaryMax(), px + 10, y2 + 44, CYAN_DIM)
		end

		valueText("» " .. string.upper(drone:GetNWString("CurrentWeapon")), cx, cy + 312, CYAN, TEXT_ALIGN_CENTER)
	end
	-- ===== Подсказки управления (только наш дрон) =====
	if drone:GetClass() == "lvs_scout_drr" then
		local hints = {
			{ "LMB", "CRYOLASER" },
			{ "RMB", "MACHINE GUN" },
			{ "F3", "DRONE MENU" },
			{ "F", "TARGET VISION" },
		}

		surface.SetFont("LvsCephSmall")

		local gap, keyW, keyH, itemGap = 8, 34, 18, 22
		local total = 0

		for _, h in ipairs(hints) do
			total = total + keyW + gap + surface.GetTextSize(h[2]) + itemGap
		end

		total = total - itemGap

		local hy = sh - 62
		local hx = cx - total * 0.5

		for _, h in ipairs(hints) do
			surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 150))
			surface.DrawOutlinedRect(hx, hy - keyH * 0.5, keyW, keyH)

			draw.SimpleText(h[1], "LvsCephSmall", hx + keyW * 0.5, hy, CYAN, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText(h[2], "LvsCephSmall", hx + keyW + gap, hy, CYAN_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

			hx = hx + keyW + gap + surface.GetTextSize(h[2]) + itemGap
		end
	end
	-- ===== Режим сканирования (F): оверлей в стиле Crysis =====
	if LVSScoutVision then
		surface.SetDrawColor(60, 200, 230, 6)

		for sy = 0, sh, 4 do
			surface.DrawRect(0, sy, sw, 1)
		end

		surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 80))
		surface.DrawOutlinedRect(22, 22, sw - 44, sh - 44)

		titleText("SCAN MODE", 34, 30, CEPH)
	end
	-- ===== Центр: кольцо нанокостюма =====
	if shouldDrawCenter then
		local t = CurTime()
		local pulse = 0.6 + 0.4 * math.abs(math.sin(t * 2))

		surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 70 * pulse))
		surface.DrawCircle(cx, cy, 80, CYAN.r, CYAN.g, CYAN.b, 70 * pulse)
		surface.DrawCircle(cx, cy, 92, CYAN.r, CYAN.g, CYAN.b, 45 * pulse)

		-- сектора по кругу
		for i = 0, 7 do
			local a = t * 0.9 + i * math.pi / 4
			local x1, y1 = cx + math.cos(a) * 84, cy + math.sin(a) * 84
			local x2, y2 = cx + math.cos(a) * 96, cy + math.sin(a) * 96

			surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 130))
			surface.DrawLine(x1, y1, x2, y2)
		end

		-- короткие боковые штрихи, не доходя до блоков телеметрии
		surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 90))
		surface.DrawLine(cx - 190, cy - 26, cx - 120, cy - 38)
		surface.DrawLine(cx - 190, cy + 26, cx - 120, cy + 38)
		surface.DrawLine(cx + 190, cy - 26, cx + 120, cy - 38)
		surface.DrawLine(cx + 190, cy + 26, cx + 120, cy + 38)

		-- данные
		local p = drone:GetPos()
		valueText(string.format("X %d   Y %d   Z %d", math.floor(p.x), math.floor(p.y), math.floor(p.z)), cx + 120, cy - 14, CYAN_DIM)
		valueText(string.format("VEL %d", math.floor(drone:GetVelocity():Length())), cx - 210, cy - 30, CYAN_DIM)
		valueText("UNIT " .. drone:GetUnit(), cx - 210, cy + 2, CYAN_DIM)

		if drone:GetNWBool("NightVision") then
			valueText("NIGHTVISION // ACTIVE", cx - 210, cy + 30, CEPH)
		end
	end

	-- ===== Критическое состояние =====
	if shouldDetectDamage and drone:GetHealth() < drone.CriticalHealthPoint then
		local a = 120 + 135 * math.abs(math.sin(CurTime() * 5))
		draw.SimpleTextOutlined(spaced("SUIT INTEGRITY CRITICAL"), "LvsCeph", cx, cy + 60, Color(WARN.r, WARN.g, WARN.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
	end

	-- ===== Радар: враги, друзья, чужие дроны =====
	do
		local rs = math.min(170, math.min(sw, sh) * 0.18)
		local rcx, rcy = sw - rs - 34, sh - rs - 34

		local function ring(x, y, r, col, steps)
			steps = steps or 40

			surface.SetDrawColor(col)

			local prev

			for i = 0, steps do
				local a = math.rad(i * (360 / steps))
				local px, py = x + math.cos(a) * r, y + math.sin(a) * r

				if prev then surface.DrawLine(prev[1], prev[2], px, py) end

				prev = { px, py }
			end
		end

		-- заливка без текстуры: surface.DrawCircle тут не заливает (остаётся текстура)
		local function disc(x, y, r, col, steps)
			steps = steps or 48

			local pts = {}

			for i = 0, steps - 1 do
				local a = math.rad(i * (360 / steps))
				pts[#pts + 1] = { x = x + math.cos(a) * r, y = y + math.sin(a) * r }
			end

			draw.NoTexture()
			surface.SetDrawColor(col)
			surface.DrawPoly(pts)
		end

		-- тёмная подложка: на светлых местах карты радар иначе теряется
		disc(rcx, rcy, rs + 9, Color(2, 5, 8, 235))
		disc(rcx, rcy, rs, Color(6, 12, 16, 252))

		ring(rcx, rcy, rs, Color(CYAN.r, CYAN.g, CYAN.b, 140))
		ring(rcx, rcy, rs * 0.62, Color(CYAN.r, CYAN.g, CYAN.b, 55))
		ring(rcx, rcy, rs * 0.3, Color(CYAN.r, CYAN.g, CYAN.b, 35))

		surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 60))
		surface.DrawLine(rcx - rs, rcy, rcx + rs, rcy)
		surface.DrawLine(rcx, rcy - rs, rcx, rcy + rs)

		-- своя машина: треугольник «носом вверх» (радар повёрнут по курсу)
		local blipCol = Color(CYAN.r, CYAN.g, CYAN.b, 230)

		surface.SetDrawColor(blipCol)
		surface.DrawLine(rcx, rcy - 7, rcx - 5, rcy + 5)
		surface.DrawLine(rcx, rcy - 7, rcx + 5, rcy + 5)
		surface.DrawLine(rcx - 5, rcy + 5, rcx + 5, rcy + 5)

		if not radarCache or CurTime() > radarAt then
			radarCache = ents.GetAll()
			radarAt = CurTime() + 0.25
		end

		local heading = (drone.CamAngles or drone:GetAngles()).y
		local fwd = Angle(0, heading, 0):Forward()
		local rgt = Angle(0, heading, 0):Right()
		local origin = drone:GetPos()

		-- Индивидуальные иконки сверху: заливка + акценты (без 3D-рендера)
		local ICONS = {
			drone = {
				body = { { 1.5, 0 }, { -0.6, 0.9 }, { -1.0, 0 }, { -0.6, -0.9 } },
				lines = { { 0.9, 1.1, -0.4, 1.7 }, { 0.9, -1.1, -0.4, -1.7 } },
			},
			antlion = {
				body = { { 1.7, 0 }, { 0.6, 0.65 }, { -0.9, 0.55 }, { -1.5, 0 }, { -0.9, -0.55 }, { 0.6, -0.65 } },
				lines = {
					{ 0.9, 0.5, 1.4, 1.5 }, { 0.0, 0.55, 0.4, 1.7 }, { -0.8, 0.5, -1.1, 1.6 },
					{ 0.9, -0.5, 1.4, -1.5 }, { 0.0, -0.55, 0.4, -1.7 }, { -0.8, -0.5, -1.1, -1.6 },
				},
			},
			strider = {
				body = { { 2.1, 0.45 }, { -2.1, 0.45 }, { -2.1, -0.45 }, { 2.1, -0.45 } },
				lines = {
					{ 1.4, 0.45, 2.0, 1.4 }, { 0.3, 0.45, 0.6, 1.8 }, { -0.7, 0.45, -1.1, 1.8 },
					{ 1.4, -0.45, 2.0, -1.4 }, { 0.3, -0.45, 0.6, -1.8 }, { -0.7, -0.45, -1.1, -1.8 },
				},
			},
			helicopter = {
				body = { { 1.5, 0.5 }, { 0.6, 0.35 }, { -1.6, 0.25 }, { -2.2, 0 }, { -1.6, -0.25 }, { 0.6, -0.35 }, { 1.5, -0.5 } },
				lines = { { 0, 0, 0, 2.1 }, { 0, 0, 0, -2.1 }, { 0, 0, 1.8, 0 }, { 0, 0, -1.9, 0 } },
			},
			gunship = {
				body = { { 1.9, 0 }, { 0.5, 1.6 }, { -1.4, 1.1 }, { -2.0, 0 }, { -1.4, -1.1 }, { 0.5, -1.6 } },
				lines = { { 0, 0, 1.3, 0.5 }, { 0, 0, 1.3, -0.5 }, { -1.6, 0, -2.4, 0 } },
			},
			dropship = {
				body = { { 1.6, 1.8 }, { -1.8, 1.2 }, { -2.4, 0 }, { -1.8, -1.2 }, { 1.6, -1.8 }, { 0.8, 0 } },
			},
			manhack = {
				body = { { 0.7, 0.7 }, { 0, 0.35 }, { -0.7, 0.7 }, { -0.35, 0 }, { -0.7, -0.7 }, { 0, -0.35 }, { 0.7, -0.7 }, { 0.35, 0 } },
				lines = { { 0.8, 0, 1.5, 0 }, { -1.5, 0, -0.8, 0 }, { 0, 0.8, 0, 1.5 }, { 0, -1.5, 0, -0.8 } },
			},
			hunter = {
				body = { { 1.4, 0 }, { 0.2, 0.9 }, { -1.2, 0.6 }, { -1.6, 0 }, { -1.2, -0.6 }, { 0.2, -0.9 } },
				lines = { { -1.2, 0.5, -1.9, 1.0 }, { -1.2, -0.5, -1.9, -1.0 } },
			},
			combine = {
				body = { { 0.5, 0.5 }, { -0.4, 0.75 }, { -0.9, 0 }, { -0.4, -0.75 }, { 0.5, -0.5 }, { 0.7, 0 } },
			},
			player = {
				body = { { 0.7, 0 }, { 0, 0.7 }, { -0.7, 0 }, { 0, -0.7 } },
			},
		}

		local function drawIcon(kind, sp, col, bx, by)
			local ic = ICONS[kind]

			if not ic then
				disc(bx, by, 3.4, col)
				return
			end

			-- тёмный контур на 40% больше: иконка читается на любом фоне
			if ic.body then
				local pts, out = {}, {}

				for _, p in ipairs(ic.body) do
					local x, y = sp(p[1], p[2])
					pts[#pts + 1] = { x = x, y = y }
					out[#out + 1] = { x = bx + (x - bx) * 1.45, y = by + (y - by) * 1.45 }
				end

				draw.NoTexture()
				surface.SetDrawColor(0, 0, 0, 200)
				surface.DrawPoly(out)

				surface.SetDrawColor(col)
				surface.DrawPoly(pts)
			end

			if ic.lines then
				-- линии с тёмной подложкой, чтобы не терялись
				for pass = 1, 2 do
					if pass == 1 then
						surface.SetDrawColor(0, 0, 0, 200)
					else
						surface.SetDrawColor(Color(col.r, col.g, col.b, math.min(col.a, 230)))
					end

					for _, l in ipairs(ic.lines) do
						local x1, y1 = sp(l[1], l[2])
						local x2, y2 = sp(l[3], l[4])

						if pass == 1 then
							surface.DrawLine(x1 - 1, y1 - 1, x2 - 1, y2 - 1)
							surface.DrawLine(x1 + 1, y1 + 1, x2 + 1, y2 + 1)
						else
							surface.DrawLine(x1, y1, x2, y2)
						end
					end
				end
			end
		end

		local function kindOf(cls)
			local c = string.lower(cls)

			if c == "lvs_scout_drr" then return "drone" end
			if c:find("antlion", 1, true) then return "antlion" end
			if c:find("strider", 1, true) then return "strider" end
			if c:find("helicopter", 1, true) then return "helicopter" end
			if c:find("gunship", 1, true) then return "gunship" end
			if c:find("dropship", 1, true) then return "dropship" end
			if c:find("manhack", 1, true) then return "manhack" end
			if c:find("hunter", 1, true) then return "hunter" end
			if c:find("scanner", 1, true) then return "scanner" end
			if c:find("combine", 1, true) or c == "npc_metropolice" then return "combine" end

			return "default"
		end

		-- метки без текстуры, иначе цвет берётся от предыдущего материала
		draw.NoTexture()

		for _, v in ipairs(radarCache) do
			if IsValid(v) and v ~= drone and not v:IsDormant() then
				if v:IsPlayer() or v:IsNPC() or v:IsNextBot() or v.IS_DRONE then
					local rel = v:GetPos() - origin
					local dist = rel:Length()

					if dist > 1 and dist < RADAR_RANGE then
						local x = rel:Dot(rgt) / RADAR_RANGE * rs
						local y = rel:Dot(fwd) / RADAR_RANGE * rs

						local cls = v:GetClass()
						local col = (LvsBlipColor and LvsBlipColor(v)) or Color(255, 220, 90)

						local a = 90 + 140 * (1 - dist / RADAR_RANGE)
						local bx, by = rcx + x, rcy - y
						-- мелкие юниты крупнее, чтобы читались на 1024p
						local ICON_SCALE = { combine = 1.4, player = 1.5, manhack = 1.25, drone = 1.15 }
						local scale = (5.2 + 2.4 * (1 - dist / RADAR_RANGE)) * (rs / 170)

						local kind = v:IsPlayer() and "player" or kindOf(cls)
						local colA = Color(col.r, col.g, col.b, a)

						scale = scale * (ICON_SCALE[kind] or 1)

						if kind == "scanner" then
							-- сканер: круглый корпус с «глазом»
							ring(bx, by, scale * 1.1, colA, 12)

							surface.SetDrawColor(colA)
							surface.DrawLine(bx + scale * 1.2, by, bx + scale * 2.0, by)
						else
							-- иконка юнита, повёрнутая по его курсу
							local yaw = v:GetAngles().y
							local f3 = Angle(0, yaw, 0):Forward()
							local r3 = Angle(0, yaw, 0):Right()

							local function sp(f, r)
								local p = f3 * f + r3 * r
								return bx + p:Dot(rgt) * scale, by - p:Dot(fwd) * scale
							end

							drawIcon(kind, sp, colA, bx, by)
						end
					end
				end
			end
		end

		draw.SimpleText("RADAR", "LvsCephSmall", rcx - rs, rcy - rs - 18,
			Color(CYAN.r, CYAN.g, CYAN.b, 220))

		draw.SimpleText(string.format("%.1fK", RADAR_RANGE / 1000), "LvsCephSmall",
			rcx + rs, rcy + rs + 2, Color(CYAN.r, CYAN.g, CYAN.b, 150),
			TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	end


	-- ===== Прицел: тонкий круг + 4 риски =====
	if shouldDrawCrosshair then
		local mx, my = sw / 2, sh / 2
		local col = Color(CYAN.r, CYAN.g, CYAN.b, 200)

		surface.SetDrawColor(col)
		surface.DrawCircle(mx, my, 16, col.r, col.g, col.b, 60)

		surface.DrawLine(mx - 26, my, mx - 10, my)
		surface.DrawLine(mx + 10, my, mx + 26, my)
		surface.DrawLine(mx, my - 26, mx, my - 10)
		surface.DrawLine(mx, my + 10, mx, my + 26)

		surface.SetDrawColor(Color(col.r, col.g, col.b, 255))
		surface.DrawRect(mx - 1, my - 1, 2, 2)
	end
end
-- Регистрация пресета: ждём, пока DRR загрузит таблицу HUD
local registered = false

local function register()
	if registered then hook.Remove("Think", "lvs_scout_crysis_register") return end
	if not (DRONES_REWRITE and DRONES_REWRITE.HUD) then return end

	DRONES_REWRITE.HUD["Crysis Ceph"] = drawCrysis
	registered = true
	hook.Remove("Think", "lvs_scout_crysis_register")
end

hook.Add("Think", "lvs_scout_crysis_register", register)