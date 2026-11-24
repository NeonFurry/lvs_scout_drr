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
					drone.FirstPersonCam_pos = anchor(drone)
				end

				orig(drone)
			end
		end
	end
end

hook.Add("Think", "lvs_scout_hudfix_wrap", wrap)
