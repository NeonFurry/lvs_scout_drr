include("shared.lua")

hook.Remove("PostDrawTranslucentRenderables", "drr_scout_neon_model")
hook.Remove("PostDrawTranslucentRenderables", "drr_scout_neon_glow")
hook.Remove("PreDrawHalos", "drr_scout_neon_halo")
hook.Remove("PreDrawHalos", "drr_scout_shield_halo")

-- Подчистка хуков из предыдущих версий аддона (иначе при неполном рестарте
-- старый HUD/луч остаются в памяти клиента и рисуются вместе с пресетами DRR).
hook.Remove("HUDPaint", "drr_scout_hud")
hook.Remove("CalcView", "drr_scout_headcam")
hook.Remove("PostDrawTranslucentRenderables", "drr_scout_cryobeam")
hook.Remove("PostDrawOpaqueRenderables", "drr_scout_cryobeam")
hook.Remove("Think", "drr_scout_fire_send")

-- ===== Луч: клиент, каждый кадр, по клиентскому CamAngles =====
local GLOW_MAT = Material("particle/particle_glow_04_additive")
local BEAM_WIDTH = 14
local BEAM_RANGE = 32768

-- Следы заморозки (клиент): лимит 20, новые заменяют старые
local lastMark = 0
local lastMarkPos


hook.Add("PostDrawTranslucentRenderables", "drr_scout_beam", function(bDrawingDepth, bDrawingSkybox)
	-- вызывается дважды за кадр (сцена + скайбокс) — в скайбоксе камера статична
	if bDrawingSkybox then return end

	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local myDrone = ply:GetNWEntity("DronesRewriteDrone")
	local eye = ply:EyePos()

	if not DrrBeamCache or CurTime() > (DrrBeamCacheAt or 0) then
		DrrBeamCache = ents.FindByClass("drr_scout_drr")
		DrrBeamCacheAt = CurTime() + 0.25
	end

	for _, drone in ipairs(DrrBeamCache) do
		-- далёкие дроны не рисуем: их луч всё равно не виден, а спрайты стоят кадров
		if IsValid(drone) and drone:GetNWBool("DrrCryoActive")
			and (drone == myDrone or drone:GetPos():DistToSqr(eye) < 6000 * 6000) then
			local start, aim

			if drone == myDrone then
				-- свой дрон: считаем каждый кадр от той же точки/оси, что и сервер
				start = drone:DrrAttachmentPos("moac_muzzle") or drone:WorldSpaceCenter()

				local cam = drone:GetCamera()
				local na = drone:GetNWVector("DrrCryoAim")

				-- серверная точка попадания (поверхность цели): луч не проходит сквозь модель
				if not na:IsZero() then
					local id = drone:EntIndex()
					DrrBeamSmooth = DrrBeamSmooth or { }
					local st = DrrBeamSmooth[id]

					if not st or not st.aim or st.aim:Distance(na) > 300 then
						st = { aim = na }
						DrrBeamSmooth[id] = st
					else
						st.aim = LerpVector(0.5, st.aim, na)
					end

					aim = st.aim
				end

				local dir = drone:GetNWVector("DrrAutoDir", vector_origin)

				if aim then
					-- уже есть точка на поверхности цели
				elseif not dir:IsZero() then
					-- сглаживаем и у себя: сеть 15 Гц, иначе луч шагает
					local id = drone:EntIndex()
					DrrBeamSmooth = DrrBeamSmooth or { }
					local st = DrrBeamSmooth[id]

					if not st or not st.dir or st.dir:Distance(dir) > 0.5 then
						DrrBeamSmooth[id] = st or { }
						st = DrrBeamSmooth[id]
						st.dir = dir
					else
						st.dir = LerpVector(0.35, st.dir, dir):GetNormal()
					end

					dir = st.dir
				end

				if not aim then
					if dir:IsZero() then
						aim = drone:GetCameraTraceLine(nil, nil, nil, MASK_SHOT).HitPos
					else
						local from = IsValid(cam) and cam:GetPos() or start

						-- игнорируем себя и свои прокси-хитбоксы (на клиенте их список не сетевой)
						local function ignore(e)
							return e == drone or e == cam or e:GetClass() == "drr_scout_hitbox"
						end

						aim = util.TraceLine({
							start  = from,
							endpos = from + dir * BEAM_RANGE,
							filter = ignore,
							mask   = MASK_SHOT,
						}).HitPos
					end
				end
			else
				-- наблюдатель: берём сетевые точки выстрела и сглаживаем,
				-- иначе луч дёргается между пакетами
				local ns = drone:GetNWVector("DrrCryoStart")
				local na = drone:GetNWVector("DrrCryoAim")

				if ns:IsZero() or na:IsZero() then continue end

				local id = drone:EntIndex()
				DrrBeamSmooth = DrrBeamSmooth or { }
				local st = DrrBeamSmooth[id]

				if not st or st.aim:Distance(na) > 400 then
					st = { aim = na }
					DrrBeamSmooth[id] = st
				else
					st.aim = LerpVector(0.35, st.aim, na)
				end

				-- начало берём по кости/аттачменту: он уже интерполирован движком
				start = drone:DrrAttachmentPos("moac_muzzle") or ns
				aim   = st.aim
			end

	local dir = (aim - start):GetNormal()
	if dir:IsZero() then dir = drone:GetForward() end

	-- голова поворачивается плавно (FrameTime * 9): луч догоняет прицел с той же
	-- скоростью, иначе на резком развороте улетает вперёд головы
	if drone == myDrone then
		local id = drone:EntIndex()

		DrrBeamSmooth = DrrBeamSmooth or { }
		local st = DrrBeamSmooth[id] or { }

		if st.bdir and st.bdir:Distance(dir) < 1.5 then
			dir = LerpVector(math.min(FrameTime() * 9, 1), st.bdir, dir):GetNormal()
		end

		st.bdir = dir
		DrrBeamSmooth[id] = st

		aim = start + dir * (aim - start):Length()
	end

			-- Камера (в первом лице она вынесена вперёд дула): конец луча может быть
			-- за ближней плоскостью. Обрезаем отрезок по ней, иначе DrawBeam или
			-- вовсе не рисуется, или тянется полосой через весь экран.
			local view = render.GetViewSetup and render.GetViewSetup(true)
			local camPos = view and view.origin or EyePos()
			local camFwd = view and view.angles:Forward() or EyeAngles():Forward()
			local NEAR = 6
			local muzzle = start + dir * 8
			local dA = (muzzle - camPos):Dot(camFwd)
			local dB = (aim - camPos):Dot(camFwd)

			if dA < NEAR then
				if dB <= NEAR then
					aim = nil
				else
					muzzle = LerpVector((NEAR - dA) / (dB - dA), muzzle, aim)
				end
			end

			if aim then
				local sa, sb = muzzle:ToScreen(), aim:ToScreen()

				-- в ночной оптике луч уходит в зелёный и светит ярче:
				-- на зелёном фоне голубое ядро читается плохо
				local nvOn = DrrNightVision and (DrrNVGain or 0) > 0.05
				local g = nvOn and (DrrNVGain or 1) or 0

				if sa.visible or sb.visible then

					local wide = BEAM_WIDTH * (nvOn and (2.0 + g) or 1.6)

					local cOut = nvOn and Color(110, 235, 225) or Color(90, 190, 255)
					local cMid = nvOn and Color(170, 245, 240) or Color(150, 220, 255)
					local cCore = nvOn and Color(240, 255, 255) or Color(220, 245, 255)

	local flick = 0.88 + 0.12 * math.sin(CurTime() * 37)

	-- Ceph: два слоя свечения без внешнего материала
	render.SetMaterial(GLOW_MAT)
	render.DrawBeam(muzzle, aim, wide * 0.95, 0, wide * 2, Color(cOut.r, cOut.g, cOut.b, 85))
	render.DrawBeam(muzzle, aim, BEAM_WIDTH * 0.3 * flick, 0, 4, Color(cCore.r, cCore.g, cCore.b, 255))

	local SEG = 14
	local phase = CurTime() * 7

	for i = 0, SEG - 1 do
		local f1, f2 = i / SEG, (i + 1) / SEG
		local wave = 0.5 + 0.5 * math.sin(phase - i * 0.9)
		local p1, p2 = LerpVector(f1, muzzle, aim), LerpVector(f2, muzzle, aim)

		render.DrawBeam(p1, p2, wide * (0.24 + 0.36 * wave), 0, 2,
			Color(cMid.r, cMid.g, cMid.b, 90 + 165 * wave))
	end

	-- кристаллики вдоль луча: крупные, с ореолом
	for i = 1, 9 do
		local ph = (i / 10 + CurTime() * 0.55) % 1
		local p = LerpVector(ph, muzzle, aim)
		local pulse = 0.6 + 0.4 * math.sin(CurTime() * 16 + i * 1.7)
		local s = 12 + 7 * pulse

		-- ореол вокруг кристалла
		render.DrawSprite(p, s * 2.1, s * 2.1, Color(120, 210, 255, 70))
		render.DrawSprite(p, s, s, Color(235, 252, 255, 255))
	end
	-- вспышка в точке попадания
	render.DrawSprite(aim, 30 + 6 * math.sin(CurTime() * 25), 30 + 6 * math.sin(CurTime() * 25), Color(160, 235, 255, 240))

	-- свечение у дула: видно, что луч активен даже у самой модели
	render.DrawSprite(muzzle, 26 + 4 * flick, 26 + 4 * flick, Color(180, 240, 255, 210))

	if nvOn then
		render.DrawSprite(muzzle, 34 + 14 * g, 34 + 14 * g, Color(160, 245, 240, 150))
	end
				end

				render.SetMaterial(GLOW_MAT)

				local imp = nvOn and (100 + 45 * g) or 84
				local icol = nvOn and Color(150, 240, 235, 215) or Color(120, 200, 255, 200)

				render.DrawSprite(aim, imp, imp, icol)
			end
		end
	end
end)

-- ===== Фонарики в патруле: луч до первого препятствия, за него не уходит =====
local DrrLightCache = { }

-- Фонарь и конус поискового света отключены полностью
hook.Remove("PreDrawTranslucentRenderables", "drr_scout_flashlight")

-- Пресеты считают:
--   центр = GetForward()*10 + LocalToWorld(FirstPersonCam_pos)
--   низ   = LocalToWorld(FirstPersonCam_pos) - GetUp()*10
-- Чтобы центр был впереди, а низ — под дроном, GetForward отдаём неединичным (×20,
-- задаёт обёртка HUD), а FirstPersonCam_pos держим у корпуса.
function ENT:GetForward()
	local f = self.DrrFwdOverride
	if f then return f end
	return self:GetAngles():Forward()
end

-- ===== Щит по форме модели: ровная плёнка + мягкая кромка =====
local SHIELD_MAT = Material("models/effects/comball_tape")
local SHIELD_HIT_MAT = Material("effects/blueflare1")

-- Вспышки на щите в точке попадания (сервер шлёт drr_scout_shield_hit)
local DrrShieldHits = {}

net.Receive("drr_scout_shield_hit", function()
	local drone = Entity(net.ReadUInt(16))
	local pos = net.ReadVector()

	if not IsValid(drone) then return end
	if #DrrShieldHits >= 24 then table.remove(DrrShieldHits, 1) end

	DrrShieldHits[#DrrShieldHits + 1] = { ent = drone, pos = pos, t = CurTime() }
end)

hook.Add("PostDrawTranslucentRenderables", "drr_scout_shield", function(bDrawingDepth, bDrawingSkybox)
	if bDrawingSkybox or bDrawingDepth then return end

	local now = CurTime()
	local slow = 0.5 + 0.5 * math.sin(now * 2.2)
	local fast = 0.5 + 0.5 * math.sin(now * 7.0)

	if not DrrShieldCache or now > (DrrShieldCacheAt or 0) then
		DrrShieldCache = ents.FindByClass("drr_scout_drr")
		DrrShieldCacheAt = now + 0.25
	end

	for _, drone in ipairs(DrrShieldCache) do
		if IsValid(drone) and drone:GetNWBool("hasModuleShield") and drone:GetNWInt("shield_health") > 0 then
			local red = drone:GetNWInt("DrrSkin", 0) == 1

			render.SuppressEngineLighting(true)
			render.MaterialOverride(SHIELD_MAT)

			-- базовая плёнка: ровный циан по всей модели
			if red then
				render.SetColorModulation(1, 0.45, 0.42)
			else
				render.SetColorModulation(0.42, 0.9, 0.88)
			end

			render.SetBlend(0.30 + 0.18 * slow)
			drone:DrawModel()

			-- кромка: чуть светлее, чтобы силуэт читался днём
			if red then
				render.SetColorModulation(1, 0.75, 0.72)
			else
				render.SetColorModulation(0.75, 1, 0.98)
			end

			render.SetBlend(0.14 + 0.20 * fast)
			drone:DrawModel()

			render.SetColorModulation(1, 1, 1)
			render.SetColorModulation(1, 1, 1)
			render.SetBlend(0.08 + 0.12 * fast)
			drone:DrawModel()

			render.SetBlend(1)
			render.MaterialOverride(nil)
			render.SuppressEngineLighting(false)
		end
	end

	-- рябь: расходящееся пятно в точке удара, гаснет за 0.45 с
	if #DrrShieldHits > 0 then
		render.SuppressEngineLighting(true)
		render.SetMaterial(SHIELD_HIT_MAT)

		for i = #DrrShieldHits, 1, -1 do
			local h = DrrShieldHits[i]

			if not IsValid(h.ent) or not h.ent:GetNWBool("hasModuleShield")
				or h.ent:GetNWInt("shield_health") <= 0 then
				table.remove(DrrShieldHits, i)
			else
				local age = now - h.t

				if age > 0.45 then
					table.remove(DrrShieldHits, i)
				else
					local a  = 1 - age / 0.45
					local sz = 24 + 130 * age

					if h.ent:GetNWInt("DrrSkin", 0) == 1 then
						render.SetColorModulation(1, 0.55, 0.5)
					else
						render.SetColorModulation(0.55, 1, 0.98)
					end

					render.SetBlend(a * 0.9)
					render.DrawSprite(h.pos, sz, sz)
				end
			end
		end

		render.SetBlend(1)
		render.SetColorModulation(1, 1, 1)
		render.SuppressEngineLighting(false)
	end
end)

-- Диагностика HUD: drr_scout_hud_debug
concommand.Add("drr_scout_hud_debug", function()
	local ply = LocalPlayer()
	local drone = ply:GetNWEntity("DronesRewriteDrone")
	if not IsValid(drone) then print("[DRR] нет дрона") return end

	local fwd = drone:GetForward()
	local fpc = drone.FirstPersonCam_pos or vector_origin
	local center = drone:LocalToWorld(fpc) + fwd * 10
	local bottom = drone:LocalToWorld(fpc) - drone:GetUp() * 10

	local c = center:ToScreen()
	local b = bottom:ToScreen()

	print("[DRR] fpc:", tostring(fpc))
	print("[DRR] |GetForward|:", math.Round(fwd:Length(), 2), tostring(fwd))
	print("[DRR] center screen:", math.Round(c.x), math.Round(c.y), c.visible)
	print("[DRR] bottom screen:", math.Round(b.x), math.Round(b.y), b.visible)
	print("[DRR] HUD:", tostring(drone:GetHUDName()), "DoCamEffects:", tostring(drone:DoCamEffects()))
end)

-- Оверлей: по умолчанию наш "DRR Ceph" (ENT.OverlayName), но выбор
-- в панели DRR уважаем. При включённой оптике оверлей не накладываем:
-- два DrawColorModify за кадр перекрывали друг друга.
function ENT:GetOverlayName()
	if self:GetNWBool("DrrNV") then return "No Overlay" end

	local cvs = DRONES_REWRITE and DRONES_REWRITE.ClientCVars

	if cvs and cvs.OverlayDef and not cvs.OverlayDef:GetBool() then
		local picked = cvs.CustomOverlay and cvs.CustomOverlay:GetString()

		if picked and picked ~= "" then return picked end
	end

	return self.OverlayName or "DRR Ceph"
end

-- Свой пресет DRR для этого дрона не рисует: HUD вызывается из
-- drr_scout_hud_crysis.lua напрямую (drr_scout_ceph_force).
function ENT:GetHUDName()
	return "DRR Internal"
end


-- ===== Совместимость с модами вида от третьего лица =====
-- Enhanced ThirdPerson (thirdperson_etp) и подобные вешают свой CalcView,
-- и камера уезжает от дрона. Пока пилотируем наш дрон:
--  - выключаем их конвар thirdperson_etp (если он есть),
--  - снимаем только их CalcView-хуки,
--  - после выхода возвращаем всё как было.
hook.Remove("Think", "drr_scout_tp_suppress")

local tpKeep = {
	dronesrewrite_view_camera = true,
	dronesrewrite_console_camera = true,
}

-- сторонние камеры: только явно «третье лицо», чужие фичи (турели,
-- катсцены, дезкамеры) не трогаем
local tpPatterns = { "third", "etp" }

local function drrIsThirdPersonHook(id)
	local low = string.lower(id)

	for _, pat in ipairs(tpPatterns) do
		if string.find(low, pat, 1, true) then return true end
	end

	return false
end

local tpSuppressed
local tpConvarWas

local function drrPilotingOur()
	local ply = LocalPlayer()

	if not IsValid(ply) then return false end

	local d = ply:GetNWEntity("DronesRewriteDrone")

	return IsValid(d) and d:GetClass() == "drr_scout_drr"
end

hook.Add("Think", "drr_scout_tp_suppress", function()
	local on = drrPilotingOur()

	if on and not tpSuppressed then
		-- конвар мода: выключаем на время пилотажа
		local cv = GetConVar("thirdperson_etp")

		if cv and cv:GetBool() then
			tpConvarWas = "1"
			RunConsoleCommand("thirdperson_etp", "0")
		end

		local list = hook.GetTable().CalcView or {}
		local store = {}

		for id, fn in pairs(list) do
			if not tpKeep[id] and drrIsThirdPersonHook(id) then
				store[id] = fn
			end
		end

		local names = {}

		for id in pairs(store) do
			hook.Remove("CalcView", id)
			names[#names + 1] = id
		end

		tpSuppressed = store

		if #names > 0 or tpConvarWas then
			print("[DRR] третье лицо выключено на время дрона: " .. table.concat(names, ", "))
		end
	elseif not on and tpSuppressed then
		for id, fn in pairs(tpSuppressed) do
			hook.Add("CalcView", id, fn)
		end

		tpSuppressed = nil

		if tpConvarWas then
			RunConsoleCommand("thirdperson_etp", tpConvarWas)
			tpConvarWas = nil
		end
	end
end)
