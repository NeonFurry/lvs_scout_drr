-- Пресет HUD "Crysis Ceph" — по структуре DRR "Drones 2",
-- но в стиле нанокостюма Crysis 1 / биолюминесцентных Цефов.
-- Только визуал: данные берутся те же, что и у Drones 2.

-- Голосовое оповещение об обнаружении: не чаще раза в 6 секунд
local heavySfxAt = 0

-- регистрируем пресет, когда DRR уже загружен (иначе таблицы HUD ещё нет)

-- Заголовки: узкий полужирный, с разрядкой (стиль Crysis)
surface.CreateFont("DrrCephTitle", {
	font = "Bahnschrift SemiBold Condensed",
	size = 18,
	weight = 600,
	antialias = true,
	extended = true,
})

-- Значения: тонкий, крупнее
surface.CreateFont("DrrCephValue", {
	font = "Bahnschrift Light Condensed",
	size = 19,
	weight = 300,
	antialias = true,
	extended = true,
})

-- Мелкие подписи
surface.CreateFont("DrrCephSmall", {
	font = "Bahnschrift Light Condensed",
	size = 16,
	weight = 250,
	antialias = true,
	extended = true,
})

-- Клавиши подсказок: крупнее и плотнее мелких подписей
surface.CreateFont("DrrCephKey", {
	font = "Bahnschrift SemiBold Condensed",
	size = 19,
	weight = 700,
	antialias = true,
	extended = true,
})

-- Крупный акцент (критическое состояние)
surface.CreateFont("DrrCeph", {
	font = "Bahnschrift SemiBold Condensed",
	size = 22,
	weight = 600,
	antialias = true,
	extended = true,
})

-- Состояние ночи приходит с сервера (см. drr_scout_gweather.lua)
DrrGWNight = false

net.Receive("drr_scout_gw_state", function()
	DrrGWNight = net.ReadBool()
end)

net.Receive("drr_scout_mark_alert", function()
	local cls = net.ReadString()
	local pos = net.ReadVector()
	local tgt = net.ReadEntity()

	-- подтверждение, что метка ушла
	surface.PlaySound("ui/buttonclick.wav")

	-- новая метка заменяет предыдущую: у пилота одна цель
	for k2, a2 in pairs(DrrHeavyAlerts or {}) do
		if a2.byPlayer then DrrHeavyAlerts[k2] = nil end
	end

	local key = IsValid(tgt) and ("t" .. tgt:EntIndex()) or "mark"

	DrrHeavyAlerts[key] = {
		id = 0,
		byPlayer = true,
		hadTarget = IsValid(tgt),
		bornAt = CurTime(),
		cls = cls,
		pos = pos,
		target = tgt,
		at = CurTime(),
		markUntil = CurTime() + 60,
	}
end)

-- сервер снял метку (цель умерла или перестала быть валидной): гасим надпись
net.Receive("drr_scout_mark_clear", function()
	local tgt = net.ReadEntity()
	local key = IsValid(tgt) and ("t" .. tgt:EntIndex()) or "mark"

	DrrHeavyAlerts[key] = nil
end)

-- Метка цели: средняя кнопка мыши в дроне (и команда drr_scout_mark)
local markReady = 0

hook.Add("Think", "drr_scout_mark_key", function()
	local ply = LocalPlayer()

	if not IsValid(ply) or not IsValid(ply:GetNWEntity("DronesRewriteDrone")) then return end
	if not input.IsMouseDown(MOUSE_MIDDLE) or CurTime() < markReady then return end

	markReady = CurTime() + 0.5

	net.Start("drr_scout_mark")
	net.SendToServer()
end)

concommand.Add("drr_scout_mark", function()
	local ply = LocalPlayer()

	if not IsValid(ply) or not IsValid(ply:GetNWEntity("DronesRewriteDrone")) then
		return
	end

	net.Start("drr_scout_mark")
	net.SendToServer()
end)

-- Оповещения о тяжёлых целях: дрон с ИИ нашёл страйдера и доложил пилотам
DrrHeavyAlerts = DrrHeavyAlerts or {}


net.Receive("drr_scout_heavy_alert", function()
	local id = net.ReadUInt(16)
	local cls = net.ReadString()
	local pos = net.ReadVector()
	local tgt = net.ReadEntity()

	if CurTime() > heavySfxAt then
		heavySfxAt = CurTime() + 6
		surface.PlaySound("npc/scanner/scanner_alert1.wav")
	end

	-- Ключ по цели, а не по дрону: на одном страйдере сидят до трёх
	-- дронов, и подпись иначе перескакивала между ними каждую секунду
	local key = IsValid(tgt) and ("t" .. tgt:EntIndex()) or ("d" .. id)
	local cur = DrrHeavyAlerts[key]

	DrrHeavyAlerts[key] = {
		id = (cur and cur.id) or id,   -- автор — тот, кто обнаружил первым
		bornAt = (cur and cur.bornAt) or CurTime(),
		hadTarget = IsValid(tgt),
		cls = cls,
		pos = pos,
		target = tgt,
		at = CurTime(),
		-- метка пилота переживает доклады дронов и гаснет по своему таймеру
		byPlayer = cur and cur.byPlayer,
		markUntil = cur and cur.markUntil,
	}
end)

local CYAN = Color(120, 235, 255)
local CYAN_DIM = Color(60, 170, 200, 170)
local CEPH = Color(130, 255, 210)
local WARN = Color(255, 165, 60)
local DANGER = Color(255, 70, 70)
local FRIEND = Color(120, 255, 150)

-- Ceph: глубокий «живой» фон и янтарная тревога вместо чистого красного
local CEPH_DEEP = Color(6, 20, 22, 215)
local ALERT = Color(255, 110, 70)

local function anchor(drone)
	local cam = drone:GetCamera()
	local pos = IsValid(cam) and cam:GetPos() or drone:GetPos()
	local ang = drone.CamAngles or drone:GetAngles()

	return pos + ang:Forward() * 200
end

-- Угловые скобки (стиль Crysis)
-- Углы в стиле Цефов: короткие лучи + ромбовидный наконечник
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

	-- ромб в каждом углу: биолюминесцентные наконечники
	local d = math.max(size * 0.26, 3)
	local function diamond(cx, cy, r)
		surface.DrawLine(cx - r, cy, cx, cy - r)
		surface.DrawLine(cx, cy - r, cx + r, cy)
		surface.DrawLine(cx + r, cy, cx, cy + r)
		surface.DrawLine(cx, cy + r, cx - r, cy)
	end

	diamond(x, y, d)
	diamond(x + w, y, d)
	diamond(x, y + h, d)
	diamond(x + w, y + h, d)
end

-- Полоса в стиле Crysis: только контуры сегментов, без сплошной заливки
local function bar(x, y, w, h, frac, col)
	frac = math.Clamp(frac, 0, 1)

	local segs = 20
	local sw = (w - (segs - 1) * 2) / segs
	local on = frac * segs

	for i = 0, segs - 1 do
		local active = i < on
		local sx = x + i * (sw + 2)

		if active then
			-- ореол вокруг сегмента + мягкая заливка: свечение Цефов
			surface.SetDrawColor(Color(col.r, col.g, col.b, 28))
			surface.DrawRect(sx - 1, y - 2, sw + 2, h + 4)

			surface.SetDrawColor(Color(col.r, col.g, col.b, 70))
			surface.DrawRect(sx, y, sw, h)

			surface.SetDrawColor(Color(col.r, col.g, col.b, 240))
			surface.DrawOutlinedRect(sx, y, sw, h)
		else
			surface.SetDrawColor(Color(col.r, col.g, col.b, 40))
			surface.DrawOutlinedRect(sx, y, sw, h)
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

	draw.SimpleText(t, "DrrCephTitle", x, y, Color(col.r, col.g, col.b, 40), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	draw.SimpleText(t, "DrrCephTitle", x, y, Color(col.r, col.g, col.b, 220), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end

-- Значение: с тонкой тёмной обводкой, чтобы читалось на любом фоне
local function valueText(text, x, y, col, xalign)
	draw.SimpleTextOutlined(text, "DrrCephValue", x, y, col, xalign or TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 190))
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

	if c == "drr_scout_drr" then return "SCOUT" end

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

local function heavyName(class)
	local names = {
		npc_strider = "STRIDER",
		npc_helicopter = "HELICOPTER",
		npc_combinegunship = "GUNSHIP",
		npc_hunter = "HUNTER",
		npc_combinedropship = "DROPSHIP",
	}

	return names[string.lower(class or "")] or friendlyClass(class or "")
end

-- Метки обнаружения и метки пилота: рисуются и в дроне, и пешком
local function drawHeavyAlerts(drone)
	local sw, sh = ScrW(), ScrH()

	-- слабый ПК: реже обновляем радар и список целей
	local perf = drone:GetNWBool("DrrPerf", false)


	-- Углы экрана: лёгкая рамка нанокостюма, чтению не мешает
	do
		local cLen, cm = 26, 10
		local a = 60 + 30 * math.abs(math.sin(CurTime() * 1.2))

		surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, a))

		surface.DrawLine(cm, cm, cm + cLen, cm)
		surface.DrawLine(cm, cm, cm, cm + cLen)

		surface.DrawLine(sw - cm, cm, sw - cm - cLen, cm)
		surface.DrawLine(sw - cm, cm, sw - cm, cm + cLen)

		surface.DrawLine(cm, sh - cm, cm + cLen, sh - cm)
		surface.DrawLine(cm, sh - cm, cm, sh - cm - cLen)

		surface.DrawLine(sw - cm, sh - cm, sw - cm - cLen, sh - cm)
		surface.DrawLine(sw - cm, sh - cm, sw - cm, sh - cm - cLen)
	end
	-- Критическое состояние: пульсирующая рамка по краям экрана
	local hpHud = drone:GetHealth() or 0
	local maxHud = math.max(drone:GetDefaultHealth() or 1, 1)
	local danger = 1 - math.Clamp(hpHud / maxHud, 0, 1)

	if danger > 0.6 then
		local k = (danger - 0.6) / 0.4
		local pulse = 0.55 + 0.45 * math.abs(math.sin(CurTime() * 4))
		local a = 100 * k * pulse

		surface.SetDrawColor(Color(255, 45, 45, a))
		surface.DrawRect(0, 0, sw, 7)
		surface.DrawRect(0, sh - 7, sw, 7)
		surface.DrawRect(0, 0, 7, sh)
		surface.DrawRect(sw - 7, 0, 7, sh)
	end
	local sw, sh = ScrW(), ScrH()

	-- ===== Метки обнаружения от союзных дронов =====
	-- Текст подписываем только у самого свежего доклада: иначе несколько
	-- дронов печатают строки друг на друга и их не прочитать
	local newestKey, newestBorn

	for key, a in pairs(DrrHeavyAlerts or {}) do
		if not newestBorn or (a.bornAt or 0) > newestBorn then
			newestKey, newestBorn = key, a.bornAt or 0
		end
	end

	for key, a in pairs(DrrHeavyAlerts or {}) do
		local tgt = a.target

		-- цель умерла или исчезла — метку убираем сразу, иначе она
		-- висела на месте смерти до таймаута
		if (a.hadTarget and not IsValid(tgt))
			or (IsValid(tgt) and tgt.Health and (tgt:Health() or 0) <= 0) then
			DrrHeavyAlerts[key] = nil
			continue
		end

		local pos = (IsValid(tgt) and tgt:WorldSpaceCenter()) or a.pos

		local deadline = a.markUntil or ((a.at or 0) + 60)

		if not pos or CurTime() > deadline then
			DrrHeavyAlerts[key] = nil
			continue
		end

		local cam = IsValid(drone) and drone:GetCamera() or nil
		local eye = IsValid(cam) and cam:GetPos() or EyePos()


		local name = heavyName(a.cls)
		local label = a.byPlayer
			and string.format(DrrT("ЦЕЛЬ ОТМЕЧЕНА: %s", "TARGET MARKED: %s"), name)
			or string.format(DrrT("ДРОН-%d ОБНАРУЖИЛ %s", "DRONE-%d SPOTTED %s"), a.id or 0, name)
		local ly = sh * 0.245

		-- один заголовок: свечение убрано, оставлены только тень и глиф
		if key == newestKey then
			draw.SimpleText(label, "DrrCeph", sw / 2 + 1, ly + 1, Color(0, 0, 0, 210),
				TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
			draw.SimpleText(label, "DrrCeph", sw / 2, ly, Color(ALERT.r, ALERT.g, ALERT.b, 245),
				TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

			surface.SetDrawColor(Color(CEPH.r, CEPH.g, CEPH.b, 70))
			surface.DrawLine(sw / 2 - 130, ly + 26, sw / 2 + 130, ly + 26)
		end

		local scr = pos:ToScreen()

		-- В этой сборке ToScreen возвращает visible, а не onScreen:
		-- без этой проверки условие всегда было истинным и метка
		-- прилипала к краю экрана / к посторонним моделям
		local inView = scr.visible

		if inView == nil then inView = scr.onScreen end
		if not inView then continue end

		local sx, sy = scr.x, scr.y

		if not sx or not sy then continue end

		local pulse = 0.6 + 0.4 * math.abs(math.sin(CurTime() * 3))
		local r = 22
		local col = Color(ALERT.r, ALERT.g, ALERT.b, 200 + 55 * pulse)

		-- ромб-полигон: тёмная подложка + ядро + двойной контур
		local function corePoly(cx, cy, rr)
			return {
				{ x = cx, y = cy - rr },
				{ x = cx + rr, y = cy },
				{ x = cx, y = cy + rr },
				{ x = cx - rr, y = cy },
			}
		end

		draw.NoTexture()

		surface.SetDrawColor(0, 0, 0, 150)
		surface.DrawPoly(corePoly(sx, sy, r + 4))

		surface.SetDrawColor(Color(col.r, col.g, col.b, 80))
		surface.DrawPoly(corePoly(sx, sy, r))

		local function rhomb(cx, cy, rr)
			surface.DrawLine(cx - rr, cy, cx, cy - rr)
			surface.DrawLine(cx, cy - rr, cx + rr, cy)
			surface.DrawLine(cx + rr, cy, cx, cy + rr)
			surface.DrawLine(cx, cy + rr, cx - rr, cy)
		end

		surface.SetDrawColor(col)
		rhomb(sx, sy, r)

		surface.SetDrawColor(Color(255, 255, 255, 230))
		rhomb(sx, sy, r * 0.5)

		-- пульсирующее кольцо вокруг метки
		local pr = r + 9 + 7 * pulse

		surface.SetDrawColor(Color(col.r, col.g, col.b, 120))

		local prev

		for i = 0, 12 do
			local ang = math.rad(i * 30)
			local px, py = sx + math.cos(ang) * pr, sy + math.sin(ang) * pr

			if prev then surface.DrawLine(prev[1], prev[2], px, py) end

			prev = { px, py }
		end

		-- четыре «усика» по осям: метка видна даже на светлом небе
		surface.SetDrawColor(Color(255, 255, 255, 210))
		surface.DrawLine(sx, sy - r - 2, sx, sy - r - 10)
		surface.DrawLine(sx, sy + r + 2, sx, sy + r + 10)
		surface.DrawLine(sx - r - 2, sy, sx - r - 10, sy)
		surface.DrawLine(sx + r + 2, sy, sx + r + 10, sy)

		draw.SimpleText(string.format(DrrT("%d м", "%d m"), math.floor(eye:Distance(pos) / 39)),
			"DrrCephSmall", sx, sy + r + 14, Color(col.r, col.g, col.b, 230),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
end

-- Сторонние моды вида (Enhanced ThirdPerson и др.) подменяют CalcView,
-- и рендер-камера уезжает от дрона. Смотрим фактическую камеру, а не флаг
-- DRR: если она не у дрона, HUD и эффекты рисовать нельзя.
function DrrDroneCameraOn(drone)
	if not IsValid(drone) or not drone.GetCamera then return true end

	-- штатный вид от третьего лица: DRR сам гасит HUD и эффекты,
	-- а камера стоит в 700 юнитах позади — проверка по расстоянию тут врёт
	if drone.GetNWBool and drone:GetNWBool("ThirdPerson") then return false end

	local cam = drone:GetCamera()

	if not IsValid(cam) or not drone.GetLocalCamPos then return true end
	if not render.GetViewSetup then return true end

	local setup = render.GetViewSetup()

	if not setup or not setup.origin then return true end

	local pos = cam:LocalToWorld(drone:GetLocalCamPos())

	return setup.origin:DistToSqr(pos) < 220 * 220
end

local function drawCrysis(drone)
	-- Пресет принадлежит только нашему Scout: чужие дроны DRR его не получают
	if not IsValid(drone) or drone:GetClass() ~= "drr_scout_drr" then return end

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

	-- На свету оптика пересвечивает фон: подложка держит контраст HUD
	if DrrNightVision then
		-- затемняем только на свету: ночью подложка съедала и без того тёмный кадр
		local scrim = math.Round(75 * (1 - (DrrNVGain or 0)))

		if scrim > 0 then
			surface.SetDrawColor(0, 0, 0, scrim)
			surface.DrawRect(0, 0, sw, sh)
		end
	end

	-- ===== Цели: биолюминесцентные скобки Цефов =====
	if shouldDrawTargets then
		local list

		if DRRScoutVision then
			-- режим сканирования (F): все цели в радиусе, даже за стенами
			if not scanCache or CurTime() > scanAt then
			-- только ближние сущности: ents.GetAll() по всей карте дорого
			scanCache = ents.FindInSphere(drone:GetPos(), 6000)
			scanAt = CurTime() + (perf and 0.5 or 0.3)
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

			if DRRScoutVision then
				if distSqr > 6000 * 6000 then continue end
			else
				local los = util.TraceLine({ start = drone:GetPos(), endpos = pos, filter = drone })
				if los.Entity ~= v then continue end
			end

			local size = 78 - math.Clamp(drone:GetPos():Distance(pos) * 0.03, 18, 78)
			local scr = pos:ToScreen()
			local isFriend = DrrIsFriendClass and DrrIsFriendClass(v:GetClass())
			local col = isFriend and FRIEND or enemyCol(v:GetClass())

			local pulse = 0.55 + 0.45 * math.abs(math.sin(CurTime() * 2.5))
			col = Color(col.r, col.g, col.b, 90 + 120 * pulse)

			brackets(scr.x - size * 0.5, scr.y - size * 0.5, size, size, size * 0.35, col)

			surface.SetDrawColor(Color(col.r, col.g, col.b, 60))
			surface.DrawCircle(scr.x, scr.y, size * 0.18, col.r, col.g, col.b, 60)

			-- подпись всегда человекочитаемая: у игроков ник, у NPC — тип
			local label = v:IsPlayer() and v:Nick() or friendlyClass(v:GetClass())
			if isFriend then label = label .. " · FRIEND" end
			draw.SimpleText(label, "DrrCephSmall", scr.x + size * 0.5 + 6, scr.y - 8, Color(col.r, col.g, col.b, 170))
		end
	end

	-- ===== Левая колонка: единая сетка панелей =====
	local px = cx - 470
	local pw = 246

	-- Подложка под колонку: полупрозрачная плашка, чтобы текст читался
	-- на светлом небе и на снегу, не превращаясь в «стену»
	do
		local bx, by = px - 10, cy - 212
		local bh = 520

		surface.SetDrawColor(Color(2, 6, 9, 240))
		surface.DrawRect(bx, by, pw + 20, bh)

		-- мягкие края сверху и снизу
		surface.SetDrawColor(Color(2, 6, 9, 190))
		surface.DrawRect(bx, by - 10, pw + 20, 10)
		surface.DrawRect(bx, by + bh, pw + 20, 10)
	end

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
		panel(y, drone:GetClass() == "drr_scout_drr" and 200 or 132)

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

		local red = drone:GetNWInt("DrrSkin", 0) == 1
		titleText("COLOR", px + 10, y + 64, CYAN)
		valueText(red and "RED" or "DEFAULT", px + pw - 14, y + 62, red and DANGER or CYAN, TEXT_ALIGN_RIGHT)

		surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 40))
		surface.DrawLine(px + 8, y + 92, px + pw - 8, y + 92)

		local night = DrrGWNight
		titleText("LIGHT", px + 10, y + 100, CYAN)
		valueText(night and "NIGHT" or "DAY", px + pw - 14, y + 98, night and Color(140, 170, 255) or WARN, TEXT_ALIGN_RIGHT)

		if drone:GetClass() == "drr_scout_drr" then
			surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 40))
			surface.DrawLine(px + 8, y + 126, px + pw - 8, y + 126)

			local auto = drone:GetNWBool("DrrAuto")
			titleText("AUTO", px + 10, y + 134, CYAN)
			valueText(auto and "MODULE ON" or "OFF", px + pw - 14, y + 132, auto and CEPH or Color(150, 160, 170), TEXT_ALIGN_RIGHT)
			-- собственное ночное видение: отдельная строка, не путается с оптикой DRR
			surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 40))
			surface.DrawLine(px + 8, y + 160, px + pw - 8, y + 160)

			local nv = DrrNightVision
			titleText("NIGHTOPTICS", px + 10, y + 168, CYAN)
			valueText(nv and "ACTIVE" or "STANDBY", px + pw - 14, y + 166, nv and Color(120, 255, 160) or Color(150, 160, 170), TEXT_ALIGN_RIGHT)
		end
	end

	-- AMMO (у нашего дрона — бесконечность)
	if shouldDrawWeps then
		local inf = drone:GetClass() == "drr_scout_drr"

		local y1 = cy + 168
		panel(y1, 74)
		titleText("PRIMARY", px + 10, y1 + 8, CYAN)

		local f1 = inf and 1 or drone:GetPrimaryAmmo() / math.max(drone:GetPrimaryMax(), 1)
		bar(px + 10, y1 + 30, pw - 20, 8, f1, WARN)

		if inf then
			infinityIcon(px + 22, y1 + 56, WARN)
		else
			valueText(drone:GetPrimaryAmmo() .. " / " .. drone:GetPrimaryMax(), px + 10, y1 + 44, CYAN_DIM)
		end

		local y2 = cy + 252
		panel(y2, 74)
		titleText("SECONDARY", px + 10, y2 + 8, CYAN)

		local f2 = inf and 1 or drone:GetSecondaryAmmo() / math.max(drone:GetSecondaryMax(), 1)
		bar(px + 10, y2 + 30, pw - 20, 8, f2, WARN)

		if inf then
			infinityIcon(px + 22, y2 + 56, WARN)
		else
			valueText(drone:GetSecondaryAmmo() .. " / " .. drone:GetSecondaryMax(), px + 10, y2 + 44, CYAN_DIM)
		end

		valueText("» " .. string.upper(drone:GetNWString("CurrentWeapon")), cx, cy + 338, CYAN, TEXT_ALIGN_CENTER)
	end
	-- ===== Подсказки управления (только наш дрон) =====
	if drone:GetClass() == "drr_scout_drr" then
		-- подписи берём из реальных привязок: DRR и наши клавиши
		local function drrKey(name, fallback)
			local k = DRONES_REWRITE and DRONES_REWRITE.Keys and DRONES_REWRITE.Keys[name]

			if not k then return fallback end

			return string.upper(input.GetKeyName(k) or fallback)
		end

		local function engKey(code, fallback)
			return string.upper(input.GetKeyName(code) or fallback)
		end

		local rows = {
			{ { "LMB", "CRYOLASER" }, { "RMB", "MACHINE GUN" }, { "MMB", "MARK TARGET" } },
			{ { engKey(KEY_H, "H"), "EMP PULSE" }, { drrKey("NightVision", "R"), "NIGHT VISION" }, { engKey(KEY_F, "F"), "TARGET GLOW" } },
			{ { drrKey("ThirdPerson", "I"), "THIRD PERSON" }, { string.upper(input.LookupBinding("gm_showspare1", true) or "F3"), "MENU" }, { drrKey("Sprint", "SHIFT"), "BOOST" } },
		}

		local function diamond(px, py, d)
			surface.DrawLine(px - d, py, px, py - d)
			surface.DrawLine(px, py - d, px + d, py)
			surface.DrawLine(px + d, py, px, py + d)
			surface.DrawLine(px, py + d, px - d, py)
		end

			-- ширину меряем тем же шрифтом, которым рисуем: иначе
			-- панель «плывёт» на 1-2 px и клавиши дрожат
			surface.SetFont("DrrCephTitle")

			local gap, keyW, pad = 9, 40, 13
			local ph, rowGap = 34, 8
			local baseY = sh - 124

			for r, row in ipairs(rows) do
				local widths, total = {}, 0

				for i, h in ipairs(row) do
					widths[i] = math.Round(pad * 2 + keyW + gap + surface.GetTextSize(h[2]))
					total = total + widths[i] + (i > 1 and 12 or 0)
				end

				local x = math.Round(cx - total * 0.5)
				local y = math.Round(baseY + (r - 1) * (ph + rowGap))

				for i, h in ipairs(row) do
					local w = widths[i]

					-- плотный фон: на светлом небе надпись должна читаться
					surface.SetDrawColor(Color(2, 8, 10, 240))
					surface.DrawRect(x, y, w, ph)

					-- двойная рамка: внешнее свечение + чёткий контур
					surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 60))
					surface.DrawOutlinedRect(x - 2, y - 2, w + 4, ph + 4)

					surface.SetDrawColor(Color(CYAN.r, CYAN.g, CYAN.b, 235))
					surface.DrawOutlinedRect(x, y, w, ph)
					surface.DrawOutlinedRect(x + 1, y + 1, w - 2, ph - 2)

					-- ромбы по углам в стиле Цефов
					surface.SetDrawColor(Color(CEPH.r, CEPH.g, CEPH.b, 255))
					diamond(x, y, 4)
					diamond(x + w, y, 4)
					diamond(x, y + ph, 4)
					diamond(x + w, y + ph, 4)

					-- клавиша: яркая бирюзовая плашка с тёмной буквой —
					-- максимальный контраст, читается на любом фоне
					surface.SetDrawColor(Color(CEPH.r, CEPH.g, CEPH.b, 220))
					surface.DrawRect(x + pad, math.Round(y + (ph - 22) * 0.5), keyW, 22)

					local kx = math.Round(x + pad + keyW * 0.5)
					local ky = math.Round(y + ph * 0.5)

					draw.SimpleText(h[1], "DrrCephTitle", kx, ky, Color(4, 16, 18, 255),
						TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

					-- подпись: белая, в два слоя ради контраста
					local tx = math.Round(x + pad + keyW + gap)

					draw.SimpleText(h[2], "DrrCephTitle", tx + 1, ky + 2, Color(0, 0, 0, 235),
						TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					draw.SimpleText(h[2], "DrrCephTitle", tx, ky,
						Color(245, 253, 255, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

					x = math.Round(x + w + 12)
				end
			end
		end
	-- ===== Режим сканирования (F): оверлей в стиле Crysis =====
	if DRRScoutVision then
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

		if DrrNightVision then
			valueText("NIGHTVISION // ACTIVE", cx - 210, cy + 30, CEPH)
		end
	end

	-- ===== Критическое состояние =====
	if shouldDetectDamage and drone:GetHealth() < drone.CriticalHealthPoint then
		local a = 120 + 135 * math.abs(math.sin(CurTime() * 5))
		draw.SimpleTextOutlined(spaced("SUIT INTEGRITY CRITICAL"), "DrrCeph", cx, cy + 60, Color(WARN.r, WARN.g, WARN.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
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

		-- Ceph: мягкое свечение по краю вместо резкой подложки
		local rt = CurTime()
		local rpulse = 0.6 + 0.4 * math.abs(math.sin(rt * 1.8))

		disc(rcx, rcy, rs + 15, Color(CEPH.r, CEPH.g, CEPH.b, 9))
		disc(rcx, rcy, rs + 7, Color(CEPH.r, CEPH.g, CEPH.b, 15))
		disc(rcx, rcy, rs, Color(3, 14, 16, 246))

		ring(rcx, rcy, rs, Color(CEPH.r, CEPH.g, CEPH.b, 80 + 70 * rpulse), 72)
		ring(rcx, rcy, rs * 0.66, Color(CEPH.r, CEPH.g, CEPH.b, 34), 64)
		ring(rcx, rcy, rs * 0.33, Color(CEPH.r, CEPH.g, CEPH.b, 22), 56)

		-- сегментированные насечки по краю: «живое» кольцо вместо жёсткой сетки
		for i = 0, 35 do
			local a = math.rad(i * 10 + rt * 6)
			local c, s = math.cos(a), math.sin(a)

			surface.SetDrawColor(Color(CEPH.r, CEPH.g, CEPH.b, 50))
			surface.DrawLine(rcx + c * (rs - 5), rcy + s * (rs - 5),
				rcx + c * rs, rcy + s * rs)
		end

		surface.SetDrawColor(Color(CEPH.r, CEPH.g, CEPH.b, 32))
		surface.DrawLine(rcx - rs * 0.9, rcy, rcx + rs * 0.9, rcy)
		surface.DrawLine(rcx, rcy - rs * 0.9, rcx, rcy + rs * 0.9)

		-- медленный сканирующий луч
		local sa = math.rad((rt * 55) % 360)

		surface.SetDrawColor(Color(CEPH.r, CEPH.g, CEPH.b, 26))
		surface.DrawLine(rcx, rcy, rcx + math.cos(sa) * rs, rcy + math.sin(sa) * rs)

		-- четыре ромба по осям: рама «глаза» Цефов
		local function rdiamond(cx, cy, r)
			surface.DrawLine(cx - r, cy, cx, cy - r)
			surface.DrawLine(cx, cy - r, cx + r, cy)
			surface.DrawLine(cx + r, cy, cx, cy + r)
			surface.DrawLine(cx, cy + r, cx - r, cy)
		end

		surface.SetDrawColor(Color(CEPH.r, CEPH.g, CEPH.b, 110 + 90 * rpulse))
		rdiamond(rcx, rcy - rs, 4)
		rdiamond(rcx, rcy + rs, 4)
		rdiamond(rcx - rs, rcy, 4)
		rdiamond(rcx + rs, rcy, 4)

		-- своя машина: ромб-«глаз» Цефов
		local blipCol = Color(CEPH.r, CEPH.g, CEPH.b, 240)
		local br = 6

		surface.SetDrawColor(blipCol)
		surface.DrawLine(rcx, rcy - br, rcx + br, rcy)
		surface.DrawLine(rcx + br, rcy, rcx, rcy + br)
		surface.DrawLine(rcx, rcy + br, rcx - br, rcy)
		surface.DrawLine(rcx - br, rcy, rcx, rcy - br)

		if not radarCache or CurTime() > radarAt then
			radarCache = ents.FindInSphere(drone:GetPos(), RADAR_RANGE + 300)
			radarAt = CurTime() + (perf and 0.7 or 0.4)
		end

		local heading = (drone.CamAngles or drone:GetAngles()).y
		local fwd = Angle(0, heading, 0):Forward()
		local rgt = Angle(0, heading, 0):Right()
		local origin = drone:GetPos()

		-- Индивидуальные иконки сверху: заливка + акценты (без 3D-рендера)
		-- Иконки нарисованы с нуля: силуэт + «жилки», читаемые в 6-8 px.
		-- Ось X — нос (вперёд), ось Y — правый борт.
		local ICONS = {
			drone = {
				body = { { 2.0, 0 }, { 0.5, 0.55 }, { -0.5, 0.35 }, { -0.9, 0 },
					{ -0.5, -0.35 }, { 0.5, -0.55 } },
				lines = { { 0.5, 0.55, 0.9, 1.15 }, { 0.5, -0.55, 0.9, -1.15 },
					{ -0.5, 0, -1.2, 0 } },
			},
			strider = {
				body = { { 2.2, 0 }, { 1.2, 0.42 }, { -1.6, 0.30 }, { -2.3, 0 },
					{ -1.6, -0.30 }, { 1.2, -0.42 } },
				lines = {
					{ 1.3, 0.42, 1.9, 1.35 }, { 0.4, 0.42, 0.7, 1.75 }, { -0.8, 0.34, -1.25, 1.7 },
					{ 1.3, -0.42, 1.9, -1.35 }, { 0.4, -0.42, 0.7, -1.75 }, { -0.8, -0.34, -1.25, -1.7 },
					{ 2.2, 0, 2.9, 0 },
				},
			},
			helicopter = {
				body = { { 1.9, 0.30 }, { 1.3, 0.62 }, { -0.9, 0.45 }, { -2.6, 0.20 },
					{ -2.6, -0.20 }, { -0.9, -0.45 }, { 1.3, -0.62 }, { 1.9, -0.30 } },
				lines = { { 0.4, 0, 0.4, 1.9 }, { 0.4, 0, 0.4, -1.9 },
					{ 0.4, 1.9, 1.2, 1.9 }, { 0.4, -1.9, 1.2, -1.9 },
					{ -2.6, 0, -3.1, 0 } },
			},
			gunship = {
				body = { { 1.6, 0 }, { 0.3, 0.55 }, { -0.9, 1.75 }, { -1.6, 1.2 },
					{ -0.8, 0 }, { -1.6, -1.2 }, { -0.9, -1.75 }, { 0.3, -0.55 } },
				lines = { { 1.6, 0, 2.5, 0 }, { 2.5, 0, 2.9, 0.55 }, { 2.5, 0, 2.9, -0.55 } },
			},
			dropship = {
				body = { { 1.4, 0.5 }, { 0.6, 1.6 }, { -1.4, 1.9 }, { -2.2, 0.9 },
					{ -2.2, -0.9 }, { -1.4, -1.9 }, { 0.6, -1.6 }, { 1.4, -0.5 } },
				lines = { { 1.4, 0.5, 2.0, 0 }, { 1.4, -0.5, 2.0, 0 } },
			},
			hunter = {
				body = { { 1.7, 0 }, { -0.4, 1.0 }, { -1.3, 0.55 }, { -0.9, 0 },
					{ -1.3, -0.55 }, { -0.4, -1.0 } },
				lines = { { -0.9, 0.5, -1.7, 1.0 }, { -0.9, -0.5, -1.7, -1.0 },
					{ 1.7, 0, 2.4, 0 } },
			},
			antlion = {
				body = { { 1.9, 0 }, { 0.9, 0.5 }, { -0.5, 0.42 }, { -1.4, 0 },
					{ -0.5, -0.42 }, { 0.9, -0.5 } },
				lines = {
					{ 1.0, 0.45, 1.4, 1.35 }, { 0.1, 0.45, 0.4, 1.6 }, { -0.7, 0.4, -1.0, 1.5 },
					{ 1.0, -0.45, 1.4, -1.35 }, { 0.1, -0.45, 0.4, -1.6 }, { -0.7, -0.4, -1.0, -1.5 },
				},
			},
			manhack = {
				body = { { 0.85, 0 }, { 0, 0.85 }, { -0.85, 0 }, { 0, -0.85 } },
				lines = { { 0.85, 0, 1.7, 0.55 }, { 0.85, 0, 1.7, -0.55 },
					{ -0.85, 0, -1.7, 0.55 }, { -0.85, 0, -1.7, -0.55 } },
			},
			scanner = {
				body = { { 0, 0.8 }, { 0.8, 0 }, { 0, -0.8 }, { -0.8, 0 } },
				lines = { { 0, 0.8, 0, 1.6 }, { 0, -0.8, 0, -1.6 } },
			},
			combine = {
				body = { { 0.6, 0.35 }, { 0.35, 0.8 }, { -0.5, 0.8 }, { -0.8, 0.3 },
					{ -0.8, -0.3 }, { -0.5, -0.8 }, { 0.35, -0.8 }, { 0.6, -0.35 } },
				lines = { { 0.6, 0.35, 1.1, 0.75 }, { 0.6, -0.35, 1.1, -0.75 } },
			},
			player = {
				body = { { 0.55, 0.4 }, { 0, 0.75 }, { -0.55, 0.4 }, { -0.55, -0.4 },
					{ 0, -0.75 }, { 0.55, -0.4 } },
				lines = { { 0.55, 0.4, 1.15, 0.15 }, { 0.55, -0.4, 1.15, -0.15 } },
			},
		}

		local function drawIcon(kind, sp, col, bx, by)
			local ic = ICONS[kind]

			if not ic then
				disc(bx, by, 3.4, col)
				return
			end

			-- Контур вместо плотной заливки: на 6-10 px силуэт читается,
			-- а не превращается в цветную кляксу
			if ic.body then
				local pts, halo = {}, {}

				for _, p in ipairs(ic.body) do
					local x, y = sp(p[1], p[2])
					pts[#pts + 1] = { x = x, y = y }
					halo[#halo + 1] = { x = bx + (x - bx) * 1.6, y = by + (y - by) * 1.6 }
				end

				draw.NoTexture()

				-- мягкий ореол Цефов
				surface.SetDrawColor(Color(col.r, col.g, col.b, 16))
				surface.DrawPoly(halo)

				-- лёгкая заливка + бледная тень под контуром
				surface.SetDrawColor(0, 0, 0, 90)
				surface.DrawPoly(pts)

				surface.SetDrawColor(Color(col.r, col.g, col.b, 70))
				surface.DrawPoly(pts)

				surface.SetDrawColor(Color(col.r, col.g, col.b, 245))

				for i = 1, #pts do
					local a, b = pts[i], pts[i % #pts + 1]

					surface.DrawLine(a.x, a.y, b.x, b.y)
				end
			end

			if ic.lines then
				-- одна тонкая тень, без жирной каймы
				surface.SetDrawColor(0, 0, 0, 150)

				for _, l in ipairs(ic.lines) do
					local x1, y1 = sp(l[1], l[2])
					local x2, y2 = sp(l[3], l[4])

					surface.DrawLine(x1 + 1, y1 + 1, x2 + 1, y2 + 1)
				end

				surface.SetDrawColor(Color(col.r, col.g, col.b, math.min(col.a, 235)))

				for _, l in ipairs(ic.lines) do
					local x1, y1 = sp(l[1], l[2])
					local x2, y2 = sp(l[3], l[4])

					surface.DrawLine(x1, y1, x2, y2)
				end
			end

			-- центральная точка: метка остаётся видимой даже в 5 px
			surface.SetDrawColor(Color(255, 255, 255, 225))
			surface.DrawRect(bx - 1, by - 1, 2, 2)
		end

		local function kindOf(cls)
			local c = string.lower(cls)

			if c == "drr_scout_drr" then return "drone" end
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
						local col = (DrrBlipColor and DrrBlipColor(v)) or Color(255, 220, 90)

						local a = 90 + 140 * (1 - dist / RADAR_RANGE)
						local bx, by = rcx + x, rcy - y
						-- мелкие юниты крупнее, чтобы читались на 1024p
						local ICON_SCALE = { combine = 1.15, player = 1.2, manhack = 1.05, drone = 1.05 }
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

		draw.SimpleText("RADAR", "DrrCephSmall", rcx - rs, rcy - rs - 18,
			Color(CEPH.r, CEPH.g, CEPH.b, 230))

		draw.SimpleText(string.format("%.1fK", RADAR_RANGE / 1000), "DrrCephSmall",
			rcx + rs, rcy + rs + 2, Color(CEPH.r, CEPH.g, CEPH.b, 170),
			TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
	end


	-- ===== Тяжёлая цель: предупреждение сверху, здоровье снизу =====
	if drone:GetNWBool("DrrHeavyActive", false) then
		local cls = drone:GetNWString("DrrHeavyClass", "")
		local name = heavyName(cls)
		local hp = drone:GetNWInt("DrrHeavyHp", 0)
		local mx = math.max(drone:GetNWInt("DrrHeavyMax", 1), 1)
		local frac = math.Clamp(hp / mx, 0, 1)
		local pulse = 0.55 + 0.45 * math.abs(math.sin(CurTime() * 2.2))
		local a = 150 + 105 * pulse

		-- Панель в стиле Цефов: срезанные углы, слоистое свечение,
		-- глубокий «живой» фон и медленная скан-линия
		local pw, ph = 480, 100
		local px, py = sw / 2 - pw / 2, sh * 0.09

		local cut = 16

		local function panelPoly(inset)
			local x1, y1 = px + inset, py + inset
			local x2, y2 = px + pw - inset, py + ph - inset
			local c = math.max(cut - inset, 4)

			return {
				{ x = x1 + c, y = y1 },
				{ x = x2, y = y1 },
				{ x = x2, y = y2 - c },
				{ x = x2 - c, y = y2 },
				{ x = x1, y = y2 },
				{ x = x1, y = y1 + c },
			}
		end

		-- внешний ореол
		surface.SetDrawColor(Color(ALERT.r, ALERT.g, ALERT.b, 16 + 16 * pulse))
		surface.DrawPoly(panelPoly(-5))

		surface.SetDrawColor(CEPH_DEEP)
		surface.DrawPoly(panelPoly(0))

		-- внутренняя биолюминесцентная кромка
		brackets(px, py, pw, ph, 22, Color(ALERT.r, ALERT.g, ALERT.b, a))

		-- скан-линия, медленно идущая сверху вниз
		local scanY = py + 8 + ((CurTime() * 38) % (ph - 16))

		surface.SetDrawColor(Color(CEPH.r, CEPH.g, CEPH.b, 24))
		surface.DrawRect(px + cut, scanY, pw - cut * 2, 1)

		-- разделитель под заголовком
		surface.SetDrawColor(Color(CEPH.r, CEPH.g, CEPH.b, 55))
		surface.DrawLine(px + cut + 8, py + 37, px + pw - cut - 8, py + 37)

		local label = DrrT("ОБНАРУЖЕНА ОПАСНОСТЬ", "THREAT DETECTED")

		draw.SimpleText(label, "DrrCeph", sw / 2 + 1, py + 12,
			Color(0, 0, 0, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		draw.SimpleText(label, "DrrCeph", sw / 2, py + 11,
			Color(ALERT.r, ALERT.g, ALERT.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

		draw.SimpleText(name .. "  //  HEAVY TARGET", "DrrCephSmall", sw / 2, py + 42,
			Color(CEPH.r, CEPH.g, CEPH.b, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

		-- HP тяжёлого юнита крупно, прямо в панели
		draw.SimpleText(string.format("%d / %d", hp, mx), "DrrCeph", sw / 2, py + 60,
			Color(CEPH.r, CEPH.g, CEPH.b, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)


		bar(px + 44, py + ph - 18, pw - 88, 7, frac, ALERT)
	end

	drawHeavyAlerts(drone)

	-- ===== Прицел: ромб Цефов + четыре насечки =====
	if shouldDrawCrosshair then
		local mx, my = sw / 2, sh / 2
		local pulse = 0.6 + 0.4 * math.abs(math.sin(CurTime() * 2.6))
		local col = Color(CEPH.r, CEPH.g, CEPH.b, 120 + 100 * pulse)
		local r = 15

		surface.SetDrawColor(col)

		-- ромб
		surface.DrawLine(mx - r, my, mx, my - r)
		surface.DrawLine(mx, my - r, mx + r, my)
		surface.DrawLine(mx + r, my, mx, my + r)
		surface.DrawLine(mx, my + r, mx - r, my)

		-- насечки по осям
		surface.SetDrawColor(Color(col.r, col.g, col.b, 170))
		surface.DrawLine(mx - 30, my, mx - 20, my)
		surface.DrawLine(mx + 20, my, mx + 30, my)
		surface.DrawLine(mx, my - 30, mx, my - 20)
		surface.DrawLine(mx, my + 20, mx, my + 30)

		-- центральная точка
		surface.SetDrawColor(Color(255, 255, 255, 230))
		surface.DrawRect(mx - 1, my - 1, 2, 2)
	end

	-- ===== Заморозка: прогресс луча и состояние цели =====
	do
		local mx, my = sw / 2, sh / 2
		local pct = drone:GetNWFloat("DrrFreezePct", 0)

		if pct > 0.01 then
			local r = 26
			local segs = 32
			local steps = math.max(math.floor(segs * pct), 1)

			surface.SetDrawColor(Color(CEPH.r, CEPH.g, CEPH.b, 210))

			for k = 0, steps - 1 do
				local a1 = math.rad(-90 + k * (360 / segs))
				local a2 = math.rad(-90 + (k + 1) * (360 / segs))

				surface.DrawLine(mx + math.cos(a1) * r, my + math.sin(a1) * r,
					mx + math.cos(a2) * r, my + math.sin(a2) * r)
			end

			draw.SimpleText(string.format("%d%%", math.floor(pct * 100)), "DrrCephSmall",
				mx, my - 30, Color(CEPH.r, CEPH.g, CEPH.b, 230),
				TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end

		-- цель под прицелом: сколько ещё лежит во льду
		local cam = drone:GetCamera()

		if IsValid(cam) then
			local tr = util.TraceLine({
				start  = cam:GetPos(),
				endpos = cam:GetPos() + cam:GetAngles():Forward() * 3000,
				filter = drone,
				mask   = MASK_SHOT,
			})

			local tgt = tr.Entity

			if IsValid(tgt) then
				local left = tgt:GetNWFloat("DrrFrozenUntil", 0) - CurTime()

				if left > 0 then
					draw.SimpleText(string.format(DrrT("ЗАМОРОЖЕН %d с", "FROZEN %d s"), math.ceil(left)),
						"DrrCephSmall", mx, my + 66, Color(160, 220, 255, 240),
						TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
				end
			end
		end
	end

	-- ===== ЭМИ: готовность под прицелом =====
	local empLeft = (drone:GetNWFloat("DrrEmpReadyAt", 0)) - CurTime()

	if empLeft > 0 then
		draw.SimpleText(string.format(DrrT("ЭМИ: %d с", "EMP: %d s"), math.ceil(empLeft)), "DrrCephSmall",
			sw / 2, sh / 2 + 46, Color(WARN.r, WARN.g, WARN.b, 225),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	else
		draw.SimpleText(DrrT("ЭМИ: ГОТОВ", "EMP: READY"), "DrrCephSmall",
			sw / 2, sh / 2 + 46, Color(CEPH.r, CEPH.g, CEPH.b, 190),
			TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
end
-- Регистрация пресета: ждём, пока DRR загрузит таблицу HUD
local registered = false

local function register()
	if registered then hook.Remove("Think", "drr_scout_crysis_register") return end
	if not (DRONES_REWRITE and DRONES_REWRITE.HUD) then return end

	DRONES_REWRITE.HUD["Crysis Ceph"] = drawCrysis
	registered = true
	hook.Remove("Think", "drr_scout_crysis_register")
end

hook.Add("Think", "drr_scout_crysis_register", register)

-- Жёсткая привязка HUD: даже если в DRR выбран другой пресет или включён
-- кастомный HUD, наш Scout рисует только Ceph. Свой пресет зовём напрямую,
-- поэтому чужой HUDPaint для этого дрона повторно не срабатывает.
hook.Remove("HUDPaint", "drr_scout_ceph_force")

hook.Add("HUDPaint", "drr_scout_ceph_force", function()

	local ply = LocalPlayer()
	local drone = ply:GetNWEntity("DronesRewriteDrone")

	if not IsValid(drone) or drone:GetClass() ~= "drr_scout_drr" then return end
	if not (DRONES_REWRITE and DRONES_REWRITE.ClientCVars and DRONES_REWRITE.ClientCVars.DrawHUD:GetBool()) then return end
	if not drone:DoCamEffects() or not drone.HUD_shouldDrawHud then return end
	if not DrrDroneCameraOn(drone) then return end

	local ok, err = pcall(drawCrysis, drone)

	if not ok then print("[DRR] HUD error:", err) end
end)

-- ЭМИ от третьего лица: штатный HUD там гасится вместе с камерой, поэтому
-- готовность импульса рисуем отдельной строкой
hook.Add("HUDPaint", "drr_scout_emp_third", function()
	local ply = LocalPlayer()

	if not IsValid(ply) then return end

	local drone = ply:GetNWEntity("DronesRewriteDrone")

	if not IsValid(drone) or drone:GetClass() ~= "drr_scout_drr" then return end
	if not (DRONES_REWRITE and DRONES_REWRITE.ClientCVars and DRONES_REWRITE.ClientCVars.DrawHUD:GetBool()) then return end
	if DrrDroneCameraOn(drone) then return end

	local left = (drone:GetNWFloat("DrrEmpReadyAt", 0)) - CurTime()
	local text, col

	if left > 0 then
		text = string.format(DrrT("ЭМИ: %d с", "EMP: %d s"), math.ceil(left))
		col = Color(WARN.r, WARN.g, WARN.b, 225)
	else
		text = DrrT("ЭМИ: ГОТОВ", "EMP: READY")
		col = Color(CEPH.r, CEPH.g, CEPH.b, 190)
	end

	draw.SimpleText(text, "DrrCephSmall", ScrW() * 0.5, ScrH() - 80, col,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
end)
-- ЭМИ-импульс: клавиша H в дроне (и команда drr_scout_emp), G занята выходом
local empReady = 0

hook.Add("Think", "drr_scout_emp_key", function()
	local ply = LocalPlayer()

	if not IsValid(ply) or not IsValid(ply:GetNWEntity("DronesRewriteDrone")) then return end
	if not input.IsKeyDown(KEY_H) or CurTime() < empReady then return end

	empReady = CurTime() + 1

	net.Start("drr_scout_emp")
	net.SendToServer()
end)

concommand.Add("drr_scout_emp", function()
	local ply = LocalPlayer()

	if not IsValid(ply) or not IsValid(ply:GetNWEntity("DronesRewriteDrone")) then return end

	net.Start("drr_scout_emp")
	net.SendToServer()
end)
