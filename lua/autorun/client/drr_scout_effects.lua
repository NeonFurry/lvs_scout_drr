-- Язык интерфейса: 0 — русский, 1 — English (drr_scout_en)
DrrLangEN = CreateClientConVar("drr_scout_en", "0", true, false, "English interface")

function DrrT(ru, en)
	return DrrLangEN:GetBool() and en or ru
end
-- Модуль собран из отдельных файлов: правки вносить сюда.

-- ===== Визуал ЭМИ (drr_scout_emp_fx.lua) =====
-- ЭМИ в стиле Ceph: шестигранная оболочка, ломаные разряды, гекс-кольца
-- и шестигранная сетка на экране у ослеплённого.

local pulses = {}
local flash = 0

-- Палитра Ceph из Crysis 1: холодный циан, бирюзовая глубина, фиолетовый
-- акцент. Белого нет — свечение у Ceph всегда с сине-зелёным уходом.
local CEPH = {
	core   = { 140, 230, 255 },
	bright = { 90, 200, 248 },
	main   = { 58, 160, 222 },
	deep   = { 30, 105, 172 },
	violet = { 130, 138, 250 },
}

local function ceph(col, a)
	return Color(col[1], col[2], col[3], a)
end

local glow

local function glowMat()
	if not glow then glow = Material("sprites/light_glow02_add") end
	return glow
end

-- Предрасчёт решётки сферы: строки по широте, у каждого гекса свой касательный
-- базис, чтобы панели стояли по поверхности, а не плоским диском.
local SHELL = {}

do
	local ROWS = 7

	for i = 1, ROWS do
		local theta = math.rad(16 + (i - 0.5) * (148 / ROWS))
		local cols = math.max(5, math.floor(11 * math.sin(theta)))

		for c = 1, cols do
			local phi = (c / cols) * math.pi * 2
			local n = Vector(math.sin(theta) * math.cos(phi), math.sin(theta) * math.sin(phi), math.cos(theta))
			local up = math.abs(n.z) > 0.9 and Vector(1, 0, 0) or Vector(0, 0, 1)
			local u = n:Cross(up):GetNormal()
			local v = n:Cross(u):GetNormal()

			-- каждый пятый гекс фиолетовый: характерный акцент Ceph
			SHELL[#SHELL + 1] = { n = n, u = u, v = v, violet = (c % 5 == 0) }
		end
	end
end

net.Receive("drr_scout_emp_fx", function()
	local pos = net.ReadVector()
	local radius = net.ReadFloat()
	local selfBlind = net.ReadBool()

	pulses[#pulses + 1] = { pos = pos, r = radius, t = CurTime() }

	if #pulses > 4 then table.remove(pulses, 1) end

	if selfBlind then flash = CurTime() + 1.5 end
end)

-- Гекс каркасом: surface.DrawPoly в 3D в GLua падает на пустой таблице
-- вершин и засыпал консоль ошибками (отсюда и тормоза).
local HEX_UNIT = {}

for k = 0, 5 do
	local a = k * math.pi / 3

	HEX_UNIT[k + 1] = { math.cos(a), math.sin(a) }
end

local function hex3D(pos, u, v, rad, col)
	local prev

	for k = 1, 7 do
		local c = HEX_UNIT[(k - 1) % 6 + 1]
		local p = pos + u * (c[1] * rad) + v * (c[2] * rad)

		if prev then render.DrawLine(prev, p, col, false) end

		prev = p
	end
end

-- Гексагон в плоскости XY (для земляных колец)
local function hexRing(center, rad, rot, col)
	local prev

	for k = 0, 6 do
		local a = k * math.pi / 3 + rot
		local v = center + Vector(math.cos(a) * rad, math.sin(a) * rad, 2)

		if prev then render.DrawLine(prev, v, col, false) end

		prev = v
	end
end

hook.Add("PostDrawTranslucentRenderables", "drr_scout_emp_draw", function(skybox)
	if skybox then return end
	if #pulses == 0 then return end

	local now = CurTime()

	for i = #pulses, 1, -1 do
		local p = pulses[i]
		local age = now - p.t

		if age > 1.3 then
			table.remove(pulses, i)
			continue
		end

		local life = age / 1.3
		local grow = math.min(age / 0.55, 1)
		local fade = (1 - life) ^ 1.5
		local r = p.r * grow

		render.SetColorMaterial()

		-- панцирь: гексы ползут наружу, каждый мерцает в своей фазе
		for k = 1, #SHELL do
			local s = SHELL[k]
			local wob = 0.5 + 0.5 * math.sin(age * 30 + k * 0.9)
			local a = 210 * fade * (0.2 + 0.8 * wob)

			if a >= 3 then
				hex3D(p.pos + s.n * r, s.u, s.v, r * 0.155, ceph(s.violet and CEPH.violet or CEPH.main, a))
			end
		end

		-- разряды: ломаная из сегментов, дёргается каждый кадр
		for a = 1, 7 do
			local ang = (a / 7) * math.pi * 2 + age * 1.6
			local len = r * (0.45 + 0.35 * math.sin(a * 2.3))
			local prev = p.pos
			local seg = 6

			for s = 1, seg do
				local t = s / seg
				local dir = Vector(math.cos(ang), math.sin(ang), math.Rand(-0.55, 0.65)):GetNormal()
				local jit = r * 0.06
				local tip = p.pos + dir * (len * t)
					+ Vector(math.Rand(-jit, jit), math.Rand(-jit, jit), math.Rand(-jit, jit))

				render.DrawLine(prev, tip, ceph(CEPH.bright, 215 * fade), false)
				prev = tip
			end
		end

		-- земля: два гекс-кольца, внешнее вращается
		hexRing(p.pos, r * 1.02, 0, ceph(CEPH.bright, 200 * fade))
		hexRing(p.pos, r * 0.78, age * 0.7, ceph(CEPH.main, 130 * fade))

		-- ядро вспышки
		render.SetMaterial(glowMat())

		local core = r * 0.2 + 70

		render.DrawSprite(p.pos, core * 2, core * 2, ceph(CEPH.main, 230 * fade))
		render.DrawSprite(p.pos, core * 0.7, core * 0.7, ceph(CEPH.core, 255 * fade))
	end
end)

-- Ослепление: циановая вспышка и шестигранная сетка поверх экрана
hook.Add("HUDPaint", "drr_scout_emp_flash", function()
	local left = flash - CurTime()

	if left <= 0 then return end

	local a = math.Clamp(left / 1.5, 0, 1) ^ 0.65
	local w, h = ScrW(), ScrH()

	surface.SetDrawColor(CEPH.deep[1], CEPH.deep[2], CEPH.deep[3], 150 * a)
	surface.DrawRect(0, 0, w, h)

	local step = math.max(90, w / 14)
	local rad = step * 0.42
	local px, py = {}, {}

	for k = 1, 6 do
		local ang = (k - 1) * math.pi / 3 + math.rad(30)

		px[k] = math.cos(ang) * rad
		py[k] = math.sin(ang) * rad
	end

	surface.SetDrawColor(CEPH.core[1], CEPH.core[2], CEPH.core[3], 90 * a)

	for y = -step, h + step, step * 1.5 do
		local shift = 0

		for x = -step, w + step, step do
			for k = 1, 6 do
				local n = k % 6 + 1

				surface.DrawLine(x + shift + px[k], y + py[k], x + shift + px[n], y + py[n])
			end

			shift = shift + step * 0.5
		end
	end
end)

-- ===== Эффекты заморозки (drr_scout_freeze_fx.lua) =====
-- Визуал заморозки: лёд вокруг NPC/игрока, чтобы состояние читалось без HUD

local GLOW_MAT = Material("particle/particle_glow_04_additive")

local frozen = { }
local nextScan = 0
local ICE = Color(130, 215, 255)

local function scan()
	frozen = { }

	local eye = EyePos()

	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) and (e:IsNPC() or e:IsNextBot() or e:IsPlayer())
			and e:GetNWBool("DrrFrozen")
			and e:GetPos():DistToSqr(eye) < 4000 * 4000 then
			frozen[#frozen + 1] = e
		end
	end
end

hook.Remove("PreDrawHalos", "drr_scout_freeze_halo")
hook.Remove("PostDrawTranslucentRenderables", "drr_scout_freeze_fx")

hook.Add("PreDrawHalos", "drr_scout_freeze_halo", function()
	if CurTime() > nextScan then
		nextScan = CurTime() + 0.3
		scan()
	end

	if #frozen == 0 then return end

	local list = { }

	for _, e in ipairs(frozen) do
		if IsValid(e) then list[#list + 1] = e end
	end

	if #list > 0 then
		halo.Add(list, ICE, 2, 6, 1, true, true)
	end
end)

hook.Add("PostDrawTranslucentRenderables", "drr_scout_freeze_fx", function(_, bSkybox)
	if bSkybox then return end
	if #frozen == 0 then return end

	local pulse = 0.55 + 0.25 * math.sin(CurTime() * 3)

	render.SetMaterial(GLOW_MAT)

	for _, e in ipairs(frozen) do
		if IsValid(e) then
			local mins, maxs = e:OBBMins(), e:OBBMaxs()
			local c = e:WorldSpaceCenter()

			-- ледяная корка: контур коробки + мягкое свечение
			render.DrawWireframeBox(e:GetPos(), e:GetAngles(),
				mins, maxs, Color(ICE.r, ICE.g, ICE.b, 120 * pulse), true)

			local size = math.max(maxs.x - mins.x, maxs.z - mins.z)

			render.DrawSprite(c, size * 1.6, size * 1.6,
				Color(ICE.r, ICE.g, ICE.b, 46 * pulse))
		end
	end
end)

-- ===== Следы заморозки (drr_scout_freeze_marks.lua) =====
-- Устарело: следы заморозки теперь генерируются и рисуются в cl_init.lua (клиент, лимит 20).

-- ===== Таймер заморозки (drr_scout_frozen_fx.lua) =====
-- Экранный эффект «обморожения» у замороженного игрока
surface.CreateFont("DrrFrozenTimer", {
	font = "Trebuchet MS",
	size = 46,
	weight = 900,
})

surface.CreateFont("DrrFrozenBy", {
	font = "Trebuchet MS",
	size = 26,
	weight = 700,
})

local OUTLINE = Color(8, 20, 40, 230)
local ICE = Color(130, 195, 255)

-- Клиентский тинт моделей замороженных игроков (серверный SetColor иногда перебивается)
local tinted = {}

hook.Add("Think", "drr_scout_frozen_tint", function()
	for _, ply in ipairs(player.GetAll()) do
		if ply:GetNWBool("DrrFrozen") then
			local c = ply:GetColor()

			if c.r ~= ICE.r or c.g ~= ICE.g or c.b ~= ICE.b then
				ply:SetColor(ICE)
				ply:SetRenderMode(RENDERMODE_TRANSCOLOR)
			end

			tinted[ply] = true
		elseif tinted[ply] then
			ply:SetColor(Color(255, 255, 255))
			ply:SetRenderMode(RENDERMODE_NORMAL)
			tinted[ply] = nil
		end
	end
end)

local function frozenPly()
	local ply = LocalPlayer()
	if IsValid(ply) and ply:GetNWBool("DrrFrozen") then return ply end
end

hook.Add("RenderScreenspaceEffects", "drr_scout_frozen_cm", function()
	if not frozenPly() then return end

	DrawColorModify({
		["$pp_colour_addr"] = 0.02,
		["$pp_colour_addg"] = 0.07,
		["$pp_colour_addb"] = 0.15,
		["$pp_colour_colour"] = 0.5,
		["$pp_colour_contrast"] = 1.1,
		["$pp_colour_brightness"] = -0.04,
	})
end)

-- материал экранной заморозки: текстура щита Combine
local FREEZE_MAT = Material("models/props_combine/com_shield001a")

hook.Add("HUDPaint", "drr_scout_frozen_overlay", function()
	local ply = frozenPly()
	if not ply then return end

	local w, h = ScrW(), ScrH()

	-- плёнка щита на весь экран, с медленной прокруткой текстуры
	surface.SetMaterial(FREEZE_MAT)
	surface.SetDrawColor(130, 195, 255, 80)

	local u = (CurTime() * 0.04) % 1
	surface.DrawTexturedRectUV(0, 0, w, h, u, u, u + w / 512, u + h / 512)

	-- «иней» по краям
	local edge = math.min(w, h) * 0.16

	for i = 1, 4 do
		local e = edge * i * 0.25

		surface.SetDrawColor(170, 220, 255, 80 / i)
		surface.DrawRect(0, 0, w, e)
		surface.DrawRect(0, h - e, w, e)
		surface.DrawRect(0, 0, e, h)
		surface.DrawRect(w - e, 0, e, h)
	end

	local left = ply:GetNWFloat("DrrFrozenUntil", 0) - CurTime()
	if left <= 0 then return end

	local by = ply:GetNWString("DrrFrozenBy", "")
	local sub = by ~= "" and ("Лучом Scout игрока (" .. by .. ")") or "Лучом Scout"

	local main = string.format("Заморожен = %.1f", left)
	local cx, cy = w * 0.5, h * 0.70

	surface.SetFont("DrrFrozenTimer")
	local tw, th = surface.GetTextSize(main)
	surface.SetFont("DrrFrozenBy")
	local sw, sh = surface.GetTextSize(sub)

	-- подложка для читаемости на любом фоне
	local pad = 18
	local bw = math.max(tw, sw) + pad * 2
	local bh = th + sh + 10 + pad * 2
	draw.RoundedBox(8, cx - bw * 0.5, cy - th * 0.5 - pad, bw, bh, Color(6, 16, 32, 150))

	draw.SimpleTextOutlined(main, "DrrFrozenTimer", cx, cy, Color(240, 250, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 3, OUTLINE)
	draw.SimpleTextOutlined(sub, "DrrFrozenBy", cx, cy + th * 0.5 + 18, Color(200, 230, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, OUTLINE)
end)

-- ===== Оболочка замороженного (drr_scout_frozen_shell.lua) =====
-- Ледяная корка на замороженных NPC/NextBot (игроки выглядят иначе: экранный эффект + плоский тон)

local ICE_MAT = Material("models/props_combine/portalball001_sheet")
local GLOW_MAT = Material("particle/particle_glow_04_additive")

local cache
local cacheAt = 0

local function frozenList()
	if cache and CurTime() < cacheAt then return cache end

	cache = {}
	cacheAt = CurTime() + 0.2

	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) and not e:IsPlayer() and e:GetNWBool("DrrFrozen") then
			cache[#cache + 1] = e
		end
	end

	return cache
end

hook.Add("PostDrawTranslucentRenderables", "drr_scout_frozen_shell", function(bDrawingDepth, bDrawingSkybox)
	if bDrawingSkybox or bDrawingDepth then return end

	local list = frozenList()
	if #list == 0 then return end

	local now = CurTime()
	local pulse = 0.3 + 0.1 * math.abs(math.sin(now * 3))

	render.SuppressEngineLighting(true)
	render.MaterialOverride(ICE_MAT)
	render.SetColorModulation(0.55, 0.82, 1)

	for _, e in ipairs(list) do
		if IsValid(e) and e:GetNWFloat("DrrFrozenUntil", 0) > now then
			render.SetBlend(pulse)
			e:DrawModel()
		end
	end

	render.SetBlend(1)
	render.SetColorModulation(1, 1, 1)
	render.MaterialOverride(nil)
	render.SuppressEngineLighting(false)

	-- мягкое свечение, чтобы замороженного было видно издалека
	render.SetMaterial(GLOW_MAT)

	for _, e in ipairs(list) do
		if IsValid(e) and e:GetNWFloat("DrrFrozenUntil", 0) > now then
			local c = e:WorldSpaceCenter()
			render.DrawSprite(c, 150, 150, Color(140, 205, 255, 55))
		end
	end
end)

-- ===== Вспышка дула (drr_scout_muzzle.lua) =====
-- Вспышка у пасти дрона при стрельбе из ледяного пулемёта.
-- Холодный «плазменный» плевок: ядро, гало и короткие искры.
local GLOW_MAT = Material("particle/particle_glow_04_additive")
local flashes = {}

net.Receive("drr_scout_muzzle", function()
	local f = {
		pos = net.ReadVector(),
		untilT = CurTime() + 0.09,
		sparks = {},
	}

	-- искры фиксируем на старте, а не каждый кадр: иначе мигает «шумом»
	for i = 1, 6 do
		f.sparks[i] = {
			off = Vector(math.Rand(-14, 14), math.Rand(-14, 14), math.Rand(-10, 10)),
			size = math.Rand(6, 14),
		}
	end

	flashes[#flashes + 1] = f
end)

hook.Add("PostDrawTranslucentRenderables", "drr_scout_muzzle_flash", function(_, bDrawingSkybox)
	if bDrawingSkybox or #flashes == 0 then return end

	local now = CurTime()
	render.SetMaterial(GLOW_MAT)

	for i = #flashes, 1, -1 do
		local f = flashes[i]

		if now > f.untilT then
			table.remove(flashes, i)
		else
			local f01 = math.Clamp((now - (f.untilT - 0.09)) / 0.09, 0, 1)
			local fade = 1 - f01
			local pulse = 0.85 + 0.3 * math.sin(CurTime() * 90 + i)

			render.DrawSprite(f.pos, 74 * fade * pulse + 12, 74 * fade * pulse + 12,
				Color(70, 170, 255, 150 * fade))
			render.DrawSprite(f.pos, 40 * fade + 8, 40 * fade + 8,
				Color(150, 225, 255, 210 * fade))
			render.DrawSprite(f.pos, 18 * fade + 6, 18 * fade + 6,
				Color(250, 255, 255, 255 * fade))

			for _, s in ipairs(f.sparks) do
				render.DrawSprite(f.pos + s.off * (1 + f01 * 1.8), s.size * fade, s.size * fade,
					Color(120, 200, 255, 180 * fade))
			end
		end
	end
end)

-- ===== Ночная оптика (drr_scout_nightvision.lua) =====
-- Ночное видение Scout: полностью клиентская оптика.
-- Раньше переключение шло через сервер — в кадре DRR сообщение терялось
-- и R ничего не включал. Теперь состояние локальное, сеть не нужна.
hook.Remove("RenderScreenspaceEffects", "drr_scout_nv_effects")
hook.Remove("PreDrawHalos", "drr_scout_nv_halos")
hook.Remove("HUDPaint", "drr_scout_nv_hud")
hook.Remove("Think", "drr_scout_nv_key")

local MAX_DIST = 5000
local cache, cacheAt
local nv = false

-- читается HUD-пресетом и подсветкой целей
DrrNightVision = false
DrrNVGain = 0

local function pilotDrone()
	local drone = LocalPlayer():GetNWEntity("DronesRewriteDrone")
	if IsValid(drone) and drone:GetClass() == "drr_scout_drr" then return drone end
end

local function nvOn(drone)
	if not nv or not IsValid(drone) or not drone:HasFuel() then return false end

	-- камера стороннего мода: цветокор и контуры не накладываем
	if DrrDroneCameraOn and not DrrDroneCameraOn(drone) then return false end

	return true
end

-- Оптика принадлежит нашему оверлею: на чужом она не включается и гаснет.
local function ourOverlay(drone)
	local cvs = DRONES_REWRITE and DRONES_REWRITE.ClientCVars

	if cvs and cvs.OverlayDef and not cvs.OverlayDef:GetBool() then
		local picked = cvs.CustomOverlay and cvs.CustomOverlay:GetString()

		if picked and picked ~= "" then return picked == "DRR Ceph" or picked == "DRR Red" end
	end

	local n = drone.OverlayName or "DRR Ceph"
	return n == "DRR Ceph" or n == "DRR Red"
end

local function tagColor(e)
	if e:IsPlayer() then return Color(255, 235, 120) end
	if DrrIsFriendClass and DrrIsFriendClass(e:GetClass()) then return Color(120, 255, 150) end
	if IsEnemyEntityName and IsEnemyEntityName(e:GetClass()) then return Color(255, 150, 60) end
	return Color(190, 230, 210)
end

local function setNV(on)
	local drone = pilotDrone()

	if on and drone and not ourOverlay(drone) then
		return
	end

	nv = on
	DrrNightVision = on
	DrrNVGain = on and (DrrNVGain or 0) or 0

	surface.PlaySound(on and "drones/nightvisionon.wav" or "drones/nightvisionoff.wav")


end

-- Зелёная оптика: поднимает тени, глушит цвет, даёт блум
hook.Add("RenderScreenspaceEffects", "drr_scout_nv_effects", function()
	local drone = pilotDrone()
	if not nvOn(drone) then return end

	-- Автогейн по свету в точке дрона: ночью усиливаем картинку,
	-- днём приглушаем. Зелёный даём множителем, а не заливкой —
	-- аддитивный зелёный превращал всё в ровный туман без деталей.
	local light = render.GetLightColor(drone:GetPos())
	local lum = (light.r + light.g + light.b) / 3

	if lum > 1 then lum = lum / 255 end

	local gain = math.Clamp(1 - (lum - 0.15) / 0.40, 0, 1)

	DrrNVGain = gain

	DrawColorModify({
		["$pp_colour_addr"] = 0.02 * gain,
		["$pp_colour_addg"] = 0.05 * gain,
		["$pp_colour_addb"] = 0.07 * gain,
		-- ночью поднимаем чёрное, чтобы читались тени; днём приглушаем
		["$pp_colour_brightness"] = -0.10 + 0.32 * gain,
		["$pp_colour_contrast"] = 1.02,
		-- почти монохром с холодным сдвигом: оптика Цефов, а не прибор ночного видения
		["$pp_colour_colour"] = 0.12,
		["$pp_colour_mulr"] = 0.55 + 0.10 * gain,
		["$pp_colour_mulg"] = 0.88 + 0.12 * gain,
		["$pp_colour_mulb"] = 0.98 + 0.02 * gain,
	})

	if gain > 0.3 then
		DrawBloom(0.08 * gain, 0.30 * gain, 3, 3, 1, 0, 1, 1, 0.5)
	end

	DrawSharpen(0.5 + 0.7 * gain, 2)
end)

-- Контуры живых целей в палитре оптики
hook.Add("PreDrawHalos", "drr_scout_nv_halos", function()
	local drone = pilotDrone()
	if not nvOn(drone) then return end

	if not cache or CurTime() > (cacheAt or 0) then
		cache = ents.FindInSphere(drone:GetPos(), MAX_DIST)
		cacheAt = CurTime() + 0.3
	end

	local groups = {}

	for _, e in ipairs(cache) do
		if IsValid(e) and e ~= drone and not e:IsDormant()
			and (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) then
			local c = tagColor(e)
			local key = c.r

			groups[key] = groups[key] or { col = c, list = {} }
			table.insert(groups[key].list, e)
		end
	end

	for _, g in pairs(groups) do
		if #g.list > 0 then halo.Add(g.list, g.col, 2, 2, 1, true, true) end
	end
end)

-- Рамка оптики: виньетка, скан-полосы, свой прицел
hook.Add("HUDPaint", "drr_scout_nv_hud", function()

	local drone = pilotDrone()
	if not nvOn(drone) then return end

	local sw, sh = ScrW(), ScrH()
	local pulse = 0.5 + 0.5 * math.sin(CurTime() * 1.6)

	for i = 1, 6 do
		local a = 16 - i * 2

		surface.SetDrawColor(0, 0, 0, a)
		surface.DrawRect(0, (i - 1) * sh * 0.02, sw, sh * 0.02)
		surface.DrawRect(0, sh - i * sh * 0.02, sw, sh * 0.02)
		surface.DrawRect((i - 1) * sw * 0.02, 0, sw * 0.02, sh)
		surface.DrawRect(sw - i * sw * 0.02, 0, sw * 0.02, sh)
	end

	surface.SetDrawColor(120, 235, 225, 12)

	for y = 0, sh, 4 do surface.DrawRect(0, y, sw, 1) end

	local cx, cy = sw * 0.5, sh * 0.5
	local d = 10 + 2 * pulse

	surface.SetDrawColor(160, 245, 240, 210)
	surface.DrawLine(cx - d, cy, cx, cy - d)
	surface.DrawLine(cx, cy - d, cx + d, cy)
	surface.DrawLine(cx + d, cy, cx, cy + d)
	surface.DrawLine(cx, cy + d, cx - d, cy)

	local label = "CEPH OPTICS // NV"
	local lw = surface.GetTextSize(label)

	surface.SetDrawColor(0, 16, 20, 190)
	surface.DrawRect(sw * 0.5 - lw * 0.5 - 10, 34, lw + 20, 22)
	surface.SetDrawColor(120, 235, 225, 190)
	surface.DrawOutlinedRect(sw * 0.5 - lw * 0.5 - 10, 34, lw + 20, 22)

	draw.SimpleText(label, "DrrCephSmall", sw * 0.5, 45, Color(170, 245, 240),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

-- R: переключаем локально и гасим чужой режим DRR
local rWasDown = false

hook.Add("Think", "drr_scout_nv_key", function()
	local drone = pilotDrone()

	if not drone then
		if nv then
			nv = false
			DrrNightVision = false
		end

		rWasDown = false
		return
	end

	-- иначе R включает старую зелёную картинку DRR поверх нашей
	if drone.UseNightVision then drone.UseNightVision = false end
	if drone:GetNWBool("NightVision") then drone:SetNWBool("NightVision", false) end

	if nv and not ourOverlay(drone) then
		nv = false
		DrrNightVision = false
		DrrNVGain = 0
	end

	local down = input.IsKeyDown(KEY_R)

	if down and not rWasDown then setNV(not nv) end

	rWasDown = down
end)

concommand.Add("drr_scout_nv", function()
	if not pilotDrone() then return end

	setNV(not nv)
end)

-- ===== Экран джаммера (drr_scout_jammer_screen.lua) =====
-- Экран джаммера DRR: к режиму и полосе прогресса добавляем таймер перезарядки
local FONT = "DronesRewrite_font5"

local function drawScreen(self)
	if not self.DrrScreenDbg then
		self.DrrScreenDbg = true
		print("[DRR] экран джаммера: ViewModelDrawn вызван")
	end

	if not self:GetNWBool("IsScreenActive", false) then return end

	local owner = self.Owner or self:GetOwner()
	if not IsValid(owner) then return end

	local vm = owner:GetViewModel()
	if not IsValid(vm) then return end

	local m = vm:GetBoneMatrix(vm:LookupBone("jammer_weapon"))
	if not m then return end

	local pos, ang = m:GetTranslation(), m:GetAngles()
	if not pos or not ang then return end

	ang:RotateAroundAxis(ang:Up(), 180)

	pos = pos - ang:Right() * 3.165
	pos = pos - ang:Forward() * 4.18
	pos = pos + ang:Up() * 0.95

	local direct = self:GetNWBool("IsInDirectMode")
	local useDelay = (self.UseDelay or 2)
		* (direct and 1 or (self.AreaModeDelayMult or 1.5))

	local left = math.max((self:GetNextPrimaryFire() or 0) - CurTime(), 0)
	local frac = math.Clamp(1 - left / useDelay, 0, 1)

	cam.Start3D2D(pos, ang, 0.01)
		-- разметка как в штатном DRR
		draw.SimpleText("MODE", FONT, 10, 8, Color(0, 255, 0, 180))
		draw.SimpleText(direct and "DIRECT" or "AREA", FONT, 74, 8, Color(0, 255, 0, 230))

		draw.SimpleText("STATE", FONT, 10, 30, Color(0, 255, 0, 180))

		if left > 0.05 then
			draw.SimpleText(string.format("RELOAD %.1f", left), FONT, 74, 30,
				Color(255, 205, 70, 240))
		else
			draw.SimpleText("READY", FONT, 74, 30, Color(60, 255, 90, 240))
		end

		surface.SetDrawColor(Color(0, 255, 0, 60))
		surface.DrawRect(10, 62, 182, 8)

		surface.SetDrawColor(left > 0.05 and Color(255, 205, 70, 220) or Color(60, 255, 90, 220))
		surface.DrawRect(10, 62, 182 * frac, 8)

		surface.SetDrawColor(Color(0, 255, 0, 120))
		surface.DrawOutlinedRect(8, 4, 186, 70, 1)
	cam.End3D2D()
end
local patchedClass = false

local function patchClass()
	local swep = weapons.Get("weapon_drr_jammer")
	if not swep then return end

	swep.ViewModelDrawn = drawScreen

	if not patchedClass then
		patchedClass = true
		print("[DRR] экран джаммера: класс пропатчен")
	end
end

local function patch(ent)
	if IsValid(ent) and ent:GetClass() == "weapon_drr_jammer" then
		ent.ViewModelDrawn = drawScreen
	end
end

hook.Add("OnEntityCreated", "drr_jammer_screen", function(ent)
	timer.Simple(0, function() patch(ent) end)
end)

hook.Add("PlayerSwitchWeapon", "drr_jammer_screen_switch", function(ply, old, new)
	patch(new)
end)

hook.Add("InitPostEntity", "drr_jammer_screen_init", function()
	patchClass()

	for _, ply in ipairs(player.GetAll()) do
		for _, w in ipairs(ply:GetWeapons()) do
			patch(w)
		end
	end
end)

timer.Simple(0, patchClass)
timer.Simple(3, patchClass)
-- Дублирующий индикатор под прицелом: виден всегда, даже если 3D-экран не отрисовался
hook.Add("HUDPaint", "drr_jammer_cooldown", function()

	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() ~= "weapon_drr_jammer" then return end

	local left = (wep:GetNextPrimaryFire() or 0) - CurTime()
	local sw, sh = ScrW(), ScrH()

	local text, col

	if left > 0.05 then
		text = string.format("JAMMER: RELOAD %.1f", left)
		col = Color(255, 205, 70, 230)
	else
		text = "JAMMER: READY"
		col = Color(60, 255, 90, 230)
	end

	draw.SimpleText(text, "DermaDefaultBold", sw / 2, sh / 2 + 64, col,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end)

-- ===== Плашки щита (drr_scout_shield_hud.lua) =====
-- Таймер восстановления щита дрона после джаммера (для атаковавшего игрока)
surface.CreateFont("DrrShieldTimer", {
	font = "Trebuchet MS",
	size = 24,
	weight = 700,
})

net.Receive("drr_scout_shield_down", function()
	-- звук снятия щита: слышно в дроне
	surface.PlaySound("drones/nio_dissolve.wav")

	local ply = LocalPlayer()
	ply.DrrShieldDrone = net.ReadEntity()
	ply.DrrShieldDownUntil = CurTime() + net.ReadFloat()
end)

-- Плашка в HUD пилота: щит дрона восстанавливается
surface.CreateFont("DrrShieldPlate", {
	font = "Trebuchet MS",
	size = 26,
	weight = 700,
})

hook.Add("HUDPaint", "drr_scout_shield_plate", function()

	local ply = LocalPlayer()
	local drone = ply:GetNWEntity("DronesRewriteDrone")

	if not IsValid(drone) or drone:GetClass() ~= "drr_scout_drr" then return end

	local at = drone:GetNWFloat("DrrShieldRestoreAt", 0)
	local left = at - CurTime()
	if left <= 0 then return end

	local text = string.format("Щит восстанавливается: %d с", math.ceil(left))
	local w, h = ScrW(), ScrH()

	surface.SetFont("DrrShieldPlate")
	local tw, th = surface.GetTextSize(text)

	local bw, bh = tw + 40, th + 20
	local x, y = w * 0.5 - bw * 0.5, h * 0.78

	draw.RoundedBox(8, x, y, bw, bh, Color(8, 20, 40, 190))
	draw.SimpleTextOutlined(
		text, "DrrShieldPlate",
		x + bw * 0.5, y + bh * 0.5,
		Color(235, 245, 255),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
		2, Color(8, 20, 40, 230)
	)
end)

hook.Add("HUDPaint", "drr_scout_shield_hud", function()

	local ply = LocalPlayer()
	local untilT = ply.DrrShieldDownUntil
	if not untilT then return end

	local drone = ply.DrrShieldDrone
	local left = untilT - CurTime()

	-- щит уже восстановили, сняли модуль или дрон исчез
	if left <= 0 or not IsValid(drone) or drone:GetNWInt("shield_health", 0) > 0 then
		ply.DrrShieldDownUntil = nil
		ply.DrrShieldDrone = nil
		return
	end

	local text = string.format("Щит дрона спал — атакуйте в полную силу (%.1f c)", left)

	draw.SimpleTextOutlined(
		text, "DrrShieldTimer",
		ScrW() * 0.5, 80,
		Color(235, 245, 255),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
		2, Color(8, 20, 40, 230)
	)
end)


-- Плашка стрелку: щит дрона не пробить
surface.CreateFont("DrrShieldBlock", {
	font = "Bahnschrift SemiBold Condensed",
	size = 22,
	weight = 700,
	extended = true,
})

hook.Remove("HUDPaint", "drr_scout_shield_block_msg")

net.Receive("drr_scout_shield_block", function()
	DrrShieldBlockUntil = CurTime() + 1.4
end)

hook.Add("HUDPaint", "drr_scout_shield_block_msg", function()

	local left = (DrrShieldBlockUntil or 0) - CurTime()

	if left <= 0 then return end

	local alpha = math.Clamp(left / 0.35, 0, 1)
	local text = "ДРОН ЗАЩИЩЁН ОТ ЛЮБОГО УРОНА"

	surface.SetFont("DrrShieldBlock")

	local tw, th = surface.GetTextSize(text)
	local w, h = ScrW(), ScrH()
	local bw, bh = tw + 46, th + 22
	local x, y = w * 0.5 - bw * 0.5, h * 0.42 - bh * 0.5

	surface.SetDrawColor(4, 16, 22, 200 * alpha)
	surface.DrawRect(x, y, bw, bh)

	surface.SetDrawColor(90, 220, 255, 220 * alpha)
	surface.DrawOutlinedRect(x, y, bw, bh)
	surface.DrawOutlinedRect(x + 1, y + 1, bw - 2, bh - 2)

	-- ромбы по углам, как у остальных панелей
	local d = 4

	for _, c in ipairs({ { x, y }, { x + bw, y }, { x, y + bh }, { x + bw, y + bh } }) do
		surface.SetDrawColor(90, 220, 255, 200 * alpha)
		surface.DrawLine(c[1] - d, c[2], c[1], c[2] - d)
		surface.DrawLine(c[1], c[2] - d, c[1] + d, c[2])
		surface.DrawLine(c[1] + d, c[2], c[1], c[2] + d)
		surface.DrawLine(c[1], c[2] + d, c[1] - d, c[2])
	end

	draw.SimpleTextOutlined(text, "DrrShieldBlock", w * 0.5, y + bh * 0.5,
		Color(200, 245, 255, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
		1, Color(0, 0, 0, 180 * alpha))
end)

-- ===== Hit-маркер (добавлено отдельным модулем) =====
local hitMarkUntil, hitMarkKill = 0, false

net.Receive("drr_scout_hitmark", function()
	hitMarkUntil = CurTime() + 0.22
	hitMarkKill = net.ReadBool()
end)

hook.Remove("HUDPaint", "drr_scout_hitmark")

hook.Add("HUDPaint", "drr_scout_hitmark", function()
	if CurTime() > hitMarkUntil then return end

	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local drone = ply:GetNWEntity("DronesRewriteDrone")
	if not IsValid(drone) or drone:GetClass() ~= "drr_scout_drr" then return end

	local alpha = math.Clamp((hitMarkUntil - CurTime()) / 0.22, 0, 1) * 255
	local col = hitMarkKill and Color(255, 90, 80, alpha) or Color(150, 240, 255, alpha)
	local cx, cy = ScrW() * 0.5, ScrH() * 0.5
	local r1, r2 = 6, 13

	surface.SetDrawColor(col)

	for i = 0, 3 do
		local sx = (i == 0 or i == 3) and -1 or 1
		local sy = (i < 2) and -1 or 1

		surface.DrawLine(cx + sx * r1, cy + sy * r1, cx + sx * r2, cy + sy * r2)
	end
end)

surface.CreateFont("DrrHeatWarn", {
	font = "Roboto", size = 17, weight = 800, extended = true
})

-- кольцо перегрева: толстое, линиями (DrawPoly в HUD не работает)
hook.Remove("HUDPaint", "drr_scout_cryo_heat")

hook.Add("HUDPaint", "drr_scout_cryo_heat", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local drone = ply:GetNWEntity("DronesRewriteDrone")
	if not IsValid(drone) or drone:GetClass() ~= "drr_scout_drr" then return end

	local heat = math.Clamp(drone:GetNWFloat("DrrCryoHeat", 0), 0, 1)
	if heat <= 0.02 then return end

	local cx, cy = ScrW() * 0.5, ScrH() * 0.5

	-- привязка к точке прицела DRR: его собственная трасса, иначе центр
	-- точка прицела как в базе DRR: луч из позиции камеры по CamAngles
	local cam = drone.GetCamera and drone:GetCamera()
	local start = IsValid(cam) and cam:GetPos() or drone:GetPos()
	local dir = (drone.CamAngles or drone:GetAngles()):Forward()
	local tr = util.TraceLine({ start = start, endpos = start + dir * 100000, filter = { drone, cam } })

	if tr and tr.HitPos then
		local a, b = tr.HitPos:ToScreen()

		if isvector(a) or type(a) == "table" then
			cx, cy = a.x, a.y
		elseif type(a) == "number" and type(b) == "number" then
			cx, cy = a, b
		end
	end
	local r = 30
	local seg = 36
	local thick = 2

	-- гекс-паттерн Ceph: каждые 6 сегментов разрыв
	local function arc(from, to, col)
		surface.SetDrawColor(col)

		for i = from, to - 1 do
			if i % 6 == 5 then continue end

			local a1 = math.rad(-90 + i * 360 / seg)
			local a2 = math.rad(-90 + (i + 1) * 360 / seg)

			local c1, s1 = math.cos(a1), math.sin(a1)
			local c2, s2 = math.cos(a2), math.sin(a2)

			for k = -thick, thick do
				surface.DrawLine(cx + c1 * (r + k), cy + s1 * (r + k), cx + c2 * (r + k), cy + s2 * (r + k))
			end
		end
	end

	arc(0, seg, Color(0, 0, 0, 190))
	arc(0, math.floor(seg * heat), heat >= 0.99 and Color(255, 135, 95, 255) or Color(120, 240, 220, 255))

	if drone:GetNWBool("DrrCryoOverheat") then
		-- пульсация и тень: надпись читается на любом фоне
		local pulse = 0.72 + 0.28 * math.sin(CurTime() * 7)
		local a = math.floor(255 * pulse)
		local text = DrrT("ПЕРЕГРЕВ", "OVERHEAT")
		local ty = cy - r - 12

		draw.SimpleText(text, "DrrHeatWarn", cx + 1, ty + 1, Color(0, 0, 0, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		draw.SimpleText(text, "DrrHeatWarn", cx, ty, Color(255, 150, 110, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

		-- гекс-скобки по бокам, как у Ceph-маркеров
		local half = surface.GetTextSize(text) * 0.5 + 8
		surface.SetDrawColor(255, 150, 110, a)
		surface.DrawLine(cx - half, ty - 14, cx - half, ty - 3)
		surface.DrawLine(cx + half, ty - 14, cx + half, ty - 3)
	end
end)

-- ===== Командный дрон (лидер стаи): метка над корпусом =====
local leaderList, leaderListAt = {}, 0

local function refreshLeaders()
	local now = CurTime()

	if now < leaderListAt then return leaderList end

	leaderListAt = now + 0.5
	leaderList = {}

	local ply = LocalPlayer()
	if not IsValid(ply) then return leaderList end

	for _, d in ipairs(ents.FindByClass("drr_scout_drr")) do
		if IsValid(d) and d:GetNWBool("DrrCommander")
			and (d.Owner == ply or d:GetNWString("DrrOwnerID") == ply:SteamID()) then
			leaderList[#leaderList + 1] = d
		end
	end

	return leaderList
end

hook.Add("PostDrawTranslucentRenderables", "drr_scout_leader_beacon", function(bDrawingDepth, bDrawingSkybox)
	if bDrawingDepth or bDrawingSkybox then return end

	local list = refreshLeaders()
	if #list == 0 then return end

	local t = CurTime()

	for _, d in ipairs(list) do
		if IsValid(d) then
			local pos = d:GetPos() + Vector(0, 0, 120 + math.sin(t * 2.4) * 6)

			render.SetMaterial(glowMat())
			render.DrawSprite(pos, 30, 30, Color(120, 235, 255, 200))
			render.DrawSprite(pos, 12, 12, Color(230, 255, 255, 240))
		end
	end
end)

hook.Add("HUDPaint", "drr_scout_leader_label", function()
	for _, d in ipairs(refreshLeaders()) do
		if IsValid(d) then
			local sp = (d:GetPos() + Vector(0, 0, 150)):ToScreen()

			if sp.visible and sp.x and sp.y then
				draw.SimpleText(DrrT("ЛИДЕР", "LEADER"), "DrrCrysisSmall", sp.x, sp.y,
					Color(160, 245, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
	end
end)