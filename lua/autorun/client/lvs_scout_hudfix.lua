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
