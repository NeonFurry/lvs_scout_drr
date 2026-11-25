-- Модуль собран из отдельных файлов: правки вносить сюда.

-- ===== Пресет Sci Fi 2 (lvs_scout_hud_scifi2.lua) =====
-- Своя отрисовка пресета "Sci Fi 2" только для нашего дрона.
-- Отличие от DRR: центр считается от точки впереди камеры, а «низ» — под корпусом.
-- Остальные элементы и логика — как в оригинальном пресете.

local CACHE_DIST = 200

-- те же локальные кеши, что в оригинальном пресете
local oldWep, wepChanged
local oldHealth = 0
local droneDamaged, targetFound

local function viewAnchor(drone)
	local cam = drone:GetCamera()
	local pos = IsValid(cam) and cam:GetPos() or drone:GetPos()
	local ang = drone.CamAngles or drone:GetAngles()

	return pos + ang:Forward() * CACHE_DIST
end

local function centerScreen(drone)
	return viewAnchor(drone):ToScreen()
end

local function bottomScreen(drone)
	local base = drone:GetPos() - drone:GetUp() * 40
	return (base - drone:GetUp() * 10):ToScreen()
end
local function drawSciFi2(drone)
	local shouldDrawCrosshair = drone.HUD_shouldDrawCrosshair and DRONES_REWRITE.ClientCVars.DrawCrosshair:GetBool()
	local shouldDrawHealth = drone.HUD_shouldDrawHealth and DRONES_REWRITE.ClientCVars.DrawHealth:GetBool()
	local shouldDrawTargets = drone.HUD_shouldDrawTargets and DRONES_REWRITE.ClientCVars.DrawTargets:GetBool()
	local shouldDrawFuel = drone.HUD_shouldDrawFuel and DRONES_REWRITE.ClientCVars.DrawFuel:GetBool()
	local shouldDetectDamage = drone.HUD_shouldDetectDamage and DRONES_REWRITE.ClientCVars.DetectDamage:GetBool()
	local shouldDrawCenter = drone.HUD_shouldDrawCenter and DRONES_REWRITE.ClientCVars.DrawCenter:GetBool()
	local shouldDrawWeps = drone.HUD_shouldDrawWeps and DRONES_REWRITE.ClientCVars.DrawWeps:GetBool()

	local x, y = ScrW(), ScrH()
	local pos = centerScreen(drone)

	--surface.SetDrawColor(Color(0, 255, 255))
	--surface.DrawOutlinedRect(50, 50, x - 100, y - 100)

	surface.SetDrawColor(Color(0, 255, 255, 50))

	for i = -2, 2 do
		surface.DrawLine(330, pos.y + i * 2, pos.x - 420, pos.y + i * 2)
		surface.DrawLine(pos.x + 420, pos.y + i * 2, ScrW() - 50, pos.y + i * 2)
	end

	if shouldDrawCrosshair then
		surface.SetMaterial(Material("effects/select_ring"))
		surface.SetDrawColor(Color(0, 255, 255, 100))
		surface.DrawTexturedRect(x / 2 - 20, y / 2 - 20, 40, 40)
		surface.DrawTexturedRect(x / 2 - 2, y / 2 - 2, 4, 4)
	end

	if drone:GetHealth() <= drone:GetDefaultHealth() / 5 then
		surface.SetMaterial(Material("stuff/console/broken4"))
		surface.SetDrawColor(Color(255, 255, 255, math.Clamp(255 - (drone:GetHealth() / drone:GetDefaultHealth()) * 255, 0, 50)))
		surface.DrawTexturedRect(0, 0, x, y)
	end

	if shouldDrawCenter then 
		surface.SetMaterial(Material("stuff/target"))
		surface.SetDrawColor(Color(0, 255, 255, 100))
		surface.DrawTexturedRect(pos.x - 40, pos.y - 40, 80, 80)

		surface.DrawCircle(pos.x, pos.y, 200, Color(0, 255, 255, 50))
		surface.DrawCircle(pos.x, pos.y, 400, Color(0, 255, 255, 150))
		surface.DrawCircle(pos.x, pos.y, 410, Color(0, 255, 255, 150))
		surface.DrawCircle(pos.x, pos.y, 420, Color(0, 255, 255, 250))

		local pos = bottomScreen(drone)
		surface.DrawCircle(pos.x, pos.y, 20, Color(0, 255, 255, 70))
		surface.DrawCircle(pos.x, pos.y, 22, Color(0, 255, 255, 50))
		surface.DrawCircle(pos.x, pos.y, 200, Color(0, 255, 255, 50))
		surface.DrawCircle(pos.x, pos.y, 400, Color(0, 255, 255, 150))
		surface.DrawCircle(pos.x, pos.y, 410, Color(0, 255, 255, 150))
		surface.DrawCircle(pos.x, pos.y, 420, Color(0, 255, 255, 250))
	end

	if shouldDrawHealth then
		local hp = (drone:GetHealth() / drone:GetDefaultHealth()) * 200
		surface.SetDrawColor(Color(255, 255, 255, 20))
		surface.DrawRect(100, ScrH() - 104, 200, 20)
		surface.SetDrawColor(Color(0, 255, 255, 100))
		surface.DrawRect(100, ScrH() - 104, hp, 20)
		surface.SetDrawColor(Color(0, 0, 0, 100))
		surface.DrawOutlinedRect(100, ScrH() - 104, 200, 20)

		draw.SimpleText("HP", "DronesRewrite_font2", 310, ScrH() - 100, Color(255, 255, 255, 100))
	end

	if shouldDrawFuel then
		local fuel = (drone:GetFuel() / drone.MaxFuel) * 200
		surface.SetDrawColor(Color(255, 255, 255, 20))
		surface.DrawRect(100, ScrH() - 64, 200, 20)
		surface.SetDrawColor(Color(255, 125, 0, 100))
		surface.DrawRect(100, ScrH() - 64, fuel, 20)
		surface.SetDrawColor(Color(0, 0, 0, 100))
		surface.DrawOutlinedRect(100, ScrH() - 64, 200, 20)

		draw.SimpleText("Fuel", "DronesRewrite_font2", 310, ScrH() - 60, Color(255, 255, 255, 100))
	end

	if shouldDrawTargets then
		local tr = drone:GetCameraTraceLine(nil, Vector(-32, -32, 0), Vector(32, 32, 0))

		for k, v in pairs(ents.FindInSphere(tr.HitPos, 500)) do
			if v:IsPlayer() or v:IsNPC() or v.IS_DRONE then
				local pos = v:GetPos()
				local bone = v:LookupBone("ValveBiped.Bip01_Head1")
				if bone then pos = v:GetBonePosition(bone) end

				local size = (64 - math.Clamp(drone:GetPos():Distance(pos) * 0.04, 20, 64))
				pos = pos:ToScreen()

				surface.SetMaterial(Material("stuff/center"))
				surface.SetDrawColor(Color(0, 155, 255, math.abs(math.sin(CurTime() * 2)) * 200))
				surface.DrawTexturedRectRotated(pos.x, pos.y, size, size, CurTime() * math.sin(CurTime() * 2) * 2)

				--surface.DrawLine(pos.x + 20, pos.y - size * 0.3, pos.x + 120, pos.y - size * 0.3)
				draw.SimpleText(v:GetClass(), "DronesRewrite_font4", pos.x + 25, pos.y - 10, Color(0, 0, 255, 130))
			end
		end
	end

	if shouldDrawWeps then
		local curWep = drone:GetNWString("CurrentWeapon")

		if oldWep != curWep then
			wepChanged = true

			timer.Create("dronesrewrite_changedwep", 3, 1, function() wepChanged = false end)
		end

		if wepChanged then
			draw.SimpleText("CURRENT WEAPON [" .. curWep .. "]", "DronesRewrite_font1", ScrW() / 2, ScrH() - 128, Color(255, 255, 255, 150), TEXT_ALIGN_CENTER)
		end

		oldWep = curWep

		local ammo = (drone:GetPrimaryAmmo() / drone:GetPrimaryMax()) * 200
		surface.SetDrawColor(Color(255, 255, 255, 20))
		surface.DrawRect(100, ScrH() - 204, 200, 20)
		surface.SetDrawColor(Color(255, 255, 0, 100))
		surface.DrawRect(100, ScrH() - 204, ammo, 20)
		surface.SetDrawColor(Color(0, 0, 0, 100))
		surface.DrawOutlinedRect(100, ScrH() - 204, 200, 20)
		draw.SimpleText("Primary ammo", "DronesRewrite_font2", 310, ScrH() - 200, Color(255, 255, 255, 100))

		local ammo = (drone:GetSecondaryAmmo() / drone:GetSecondaryMax()) * 200
		surface.SetDrawColor(Color(255, 255, 255, 20))
		surface.DrawRect(100, ScrH() - 244, 200, 20)
		surface.SetDrawColor(Color(255, 255, 0, 100))
		surface.DrawRect(100, ScrH() - 244, ammo, 20)
		surface.SetDrawColor(Color(0, 0, 0, 100))
		surface.DrawOutlinedRect(100, ScrH() - 244, 200, 20)
		draw.SimpleText("Secondary ammo", "DronesRewrite_font2", 310, ScrH() - 240, Color(255, 255, 255, 100))
	end

	if shouldDetectDamage then
		if oldHealth > drone:GetHealth() then
			droneDamaged = true
			timer.Create("dronesrewrite_changedamaged", 2, 1, function() droneDamaged = false end)
		end

		if droneDamaged then
			draw.SimpleText("DAMAGED", "DronesRewrite_font1", x / 2, y / 2 + 200, Color(255, 0, 0, 120), TEXT_ALIGN_CENTER)
		end

		oldHealth = drone:GetHealth()
	end
end
-- Оборачиваем пресет: для нашего дрона рисуем свою версию, для остальных — штатную
local wrapped = {}

local function wrap()
	if not (DRONES_REWRITE and DRONES_REWRITE.HUD) then return end
	if not DRONES_REWRITE.HUD["Sci Fi 2"] then return end
	if wrapped.ok then return end

	local orig = DRONES_REWRITE.HUD["Sci Fi 2"]
	wrapped.ok = true

	DRONES_REWRITE.HUD["Sci Fi 2"] = function(drone)
		if drone:GetClass() == "lvs_scout_drr" then
			drawSciFi2(drone)
		else
			orig(drone)
		end
	end

	hook.Remove("Think", "lvs_scout_scifi2_wrap")
end

hook.Add("Think", "lvs_scout_scifi2_wrap", wrap)

-- ===== Стабилизация центра HUD (lvs_scout_hudfix.lua) =====
-- Обёртка для простых пресетов (центр без «низа»): перед отрисовкой подставляем
-- свежий якорь впереди камеры. Файлы пресетов не меняются.

local wrapped = {}

local function anchor(drone)
	local cam = drone:GetCamera()
	local pos = IsValid(cam) and cam:GetPos() or drone:GetPos()
	local ang = drone.CamAngles or drone:GetAngles()

	return drone:WorldToLocal(pos + ang:Forward() * 200)
end

local function wrap()
	if not (DRONES_REWRITE and DRONES_REWRITE.HUD) then return end

	for name, orig in pairs(DRONES_REWRITE.HUD) do
		if name ~= "Sci Fi 2" and not wrapped[name] then
			wrapped[name] = true

			DRONES_REWRITE.HUD[name] = function(drone)
				if drone:GetClass() == "lvs_scout_drr" then
					-- третье лицо/сторонняя камера: чужой пресет не рисуем
					if LvsDroneCameraOn and not LvsDroneCameraOn(drone) then return end

					drone.FirstPersonCam_pos = anchor(drone)
				end

				orig(drone)
			end
		end
	end
end

hook.Add("Think", "lvs_scout_hudfix_wrap", wrap)

-- ===== Центральный прицел: контрастный на любом пресете и на светлом небе =====
local function ourDrone()
	local ply = LocalPlayer()
	local d = IsValid(ply) and ply:GetNWEntity("DronesRewriteDrone")

	if IsValid(d) and d:GetClass() == "lvs_scout_drr" then return d end
end

local function ring(cx, cy, r, col, seg)
	surface.SetDrawColor(col)

	local step = math.pi * 2 / seg
	local px, py = cx + r, cy

	for i = 1, seg do
		local a = step * i
		local x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
		surface.DrawLine(px, py, x, y)
		px, py = x, y
	end
end

hook.Remove("PostDrawHUD", "lvs_scout_center_reticle")

hook.Add("PostDrawHUD", "lvs_scout_center_reticle", function()
	local drone = ourDrone()
	if not drone or LvsNightVision then return end
	if LvsDroneCameraOn and not LvsDroneCameraOn(drone) then return end

	local sw, sh = ScrW(), ScrH()
	local cx, cy = math.Round(sw * 0.5), math.Round(sh * 0.5)
	local pulse = 0.5 + 0.5 * math.sin(CurTime() * 3)

	-- подложка: прицел читается на небе и на снегу
	surface.DrawCircle(cx, cy, 13, 0, 0, 0, 60)

	-- тень контура
	ring(cx, cy, 9, Color(0, 0, 0, 190), 20)

	-- сам прицел
	ring(cx, cy, 8, Color(150, 245, 235, 210 + 20 * pulse), 20)

	-- засечки: тёмная подложка + светлая линия
	local t = 5

	local function tick(x1, y1, x2, y2)
		surface.SetDrawColor(0, 0, 0, 190)
		surface.DrawLine(x1, y1, x2, y2)
		surface.SetDrawColor(170, 250, 240, 235)
		surface.DrawLine(x1 + 1, y1 + 1, x2 + 1, y2 + 1)
	end

	tick(cx - t, cy - 13, cx + t, cy - 13)
	tick(cx - t, cy + 13, cx + t, cy + 13)
	tick(cx - 13, cy - t, cx - 13, cy + t)
	tick(cx + 13, cy - t, cx + 13, cy + t)

	surface.SetDrawColor(230, 255, 250, 240)
	surface.DrawRect(cx - 1, cy - 1, 2, 2)
end)

-- ===== Совместимость с радаром DRR (weapon_drr_radar) =====
-- Радар фильтрует дронов по полю IS_DRONE в таблице класса. Класс грузится
-- один раз при старте карты, поэтому при обновлении скрипта поле может
-- отсутствовать у заспавненных дронов — проставляем его на клиенте.
local radarNext = 0

hook.Remove("Think", "lvs_scout_radar_compat")
hook.Add("Think", "lvs_scout_radar_compat", function()
	if CurTime() < radarNext then return end
	radarNext = CurTime() + 1

	for _, d in ipairs(ents.FindByClass("lvs_scout_drr")) do
		d.IS_DRONE = true
		d.ShowOnRadar = true
	end
end)

concommand.Add("lvs_scout_radar_debug", function()
	for _, d in ipairs(ents.FindByClass("lvs_scout_drr")) do
		print(string.format("[LVS radar] %s IS_DRONE=%s NoDRRRadar=%s dist=%d",
			tostring(d), tostring(d.IS_DRONE),
			tostring(d:GetNWBool("NoDRRRadar", false)),
			math.Round(d:GetPos():Distance(LocalPlayer():GetPos()))))
	end
end)
