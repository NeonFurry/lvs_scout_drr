-- Ночное видение Scout: полностью клиентская оптика.
-- Раньше переключение шло через сервер — в кадре DRR сообщение терялось
-- и R ничего не включал. Теперь состояние локальное, сеть не нужна.
hook.Remove("RenderScreenspaceEffects", "lvs_scout_nv_effects")
hook.Remove("PreDrawHalos", "lvs_scout_nv_halos")
hook.Remove("HUDPaint", "lvs_scout_nv_hud")
hook.Remove("Think", "lvs_scout_nv_key")

local MAX_DIST = 5000
local cache, cacheAt
local nv = false

-- читается HUD-пресетом и подсветкой целей
LvsNightVision = false
LvsNVGain = 0

local function pilotDrone()
	local drone = LocalPlayer():GetNWEntity("DronesRewriteDrone")
	if IsValid(drone) and drone:GetClass() == "lvs_scout_drr" then return drone end
end

local function nvOn(drone)
	if not nv or not IsValid(drone) or not drone:HasFuel() then return false end

	-- камера стороннего мода: цветокор и контуры не накладываем
	if LvsDroneCameraOn and not LvsDroneCameraOn(drone) then return false end

	return true
end

-- Оптика принадлежит нашему оверлею: на чужом она не включается и гаснет.
local function ourOverlay(drone)
	local cvs = DRONES_REWRITE and DRONES_REWRITE.ClientCVars

	if cvs and cvs.OverlayDef and not cvs.OverlayDef:GetBool() then
		local picked = cvs.CustomOverlay and cvs.CustomOverlay:GetString()

		if picked and picked ~= "" then return picked == "LVS Ceph" or picked == "LVS Red" end
	end

	local n = drone.OverlayName or "LVS Ceph"
	return n == "LVS Ceph" or n == "LVS Red"
end

local function tagColor(e)
	if e:IsPlayer() then return Color(255, 235, 120) end
	if LvsIsFriendClass and LvsIsFriendClass(e:GetClass()) then return Color(120, 255, 150) end
	if IsEnemyEntityName and IsEnemyEntityName(e:GetClass()) then return Color(255, 150, 60) end
	return Color(190, 230, 210)
end

local function setNV(on)
	local drone = pilotDrone()

	if on and drone and not ourOverlay(drone) then
		return
	end

	nv = on
	LvsNightVision = on
	LvsNVGain = on and (LvsNVGain or 0) or 0

	surface.PlaySound(on and "drones/nightvisionon.wav" or "drones/nightvisionoff.wav")


end

-- Зелёная оптика: поднимает тени, глушит цвет, даёт блум
hook.Add("RenderScreenspaceEffects", "lvs_scout_nv_effects", function()
	local drone = pilotDrone()
	if not nvOn(drone) then return end

	-- Автогейн по свету в точке дрона: ночью усиливаем картинку,
	-- днём приглушаем. Зелёный даём множителем, а не заливкой —
	-- аддитивный зелёный превращал всё в ровный туман без деталей.
	local light = render.GetLightColor(drone:GetPos())
	local lum = (light.r + light.g + light.b) / 3

	if lum > 1 then lum = lum / 255 end

	local gain = math.Clamp(1 - (lum - 0.15) / 0.40, 0, 1)

	LvsNVGain = gain

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
hook.Add("PreDrawHalos", "lvs_scout_nv_halos", function()
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
hook.Add("HUDPaint", "lvs_scout_nv_hud", function()

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

	draw.SimpleText(label, "LvsCephSmall", sw * 0.5, 45, Color(170, 245, 240),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

-- R: переключаем локально и гасим чужой режим DRR
local rWasDown = false

hook.Add("Think", "lvs_scout_nv_key", function()
	local drone = pilotDrone()

	if not drone then
		if nv then
			nv = false
			LvsNightVision = false
		end

		rWasDown = false
		return
	end

	-- иначе R включает старую зелёную картинку DRR поверх нашей
	if drone.UseNightVision then drone.UseNightVision = false end
	if drone:GetNWBool("NightVision") then drone:SetNWBool("NightVision", false) end

	if nv and not ourOverlay(drone) then
		nv = false
		LvsNightVision = false
		LvsNVGain = 0
	end

	local down = input.IsKeyDown(KEY_R)

	if down and not rWasDown then setNV(not nv) end

	rWasDown = down
end)

concommand.Add("lvs_scout_nv", function()
	if not pilotDrone() then return end

	setNV(not nv)
end)
