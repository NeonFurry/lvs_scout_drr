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
