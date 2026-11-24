include("shared.lua")

hook.Remove("PostDrawTranslucentRenderables", "lvs_scout_neon_model")
hook.Remove("PostDrawTranslucentRenderables", "lvs_scout_neon_glow")
hook.Remove("PreDrawHalos", "lvs_scout_neon_halo")

-- Подчистка хуков из предыдущих версий аддона (иначе при неполном рестарте
-- старый HUD/луч остаются в памяти клиента и рисуются вместе с пресетами DRR).
hook.Remove("HUDPaint", "lvs_scout_hud")
hook.Remove("CalcView", "lvs_scout_headcam")
hook.Remove("PostDrawTranslucentRenderables", "lvs_scout_cryobeam")
hook.Remove("PostDrawOpaqueRenderables", "lvs_scout_cryobeam")
hook.Remove("Think", "lvs_scout_fire_send")

-- ===== Луч: клиент, каждый кадр, по клиентскому CamAngles =====
local BEAM_MAT = Material("effects/blueblacklargebeam")
local GLOW_MAT = Material("particle/particle_glow_04_additive")
local BEAM_WIDTH = 10
local BEAM_RANGE = 32768

-- Следы заморозки (клиент): лимит 20, новые заменяют старые
local lastMark = 0
local lastMarkPos


hook.Add("PostDrawTranslucentRenderables", "lvs_scout_beam", function(bDrawingDepth, bDrawingSkybox)
	-- вызывается дважды за кадр (сцена + скайбокс) — в скайбоксе камера статична
	if bDrawingSkybox then return end

	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local myDrone = ply:GetNWEntity("DronesRewriteDrone")

	if not LvsBeamCache or CurTime() > (LvsBeamCacheAt or 0) then
		LvsBeamCache = ents.FindByClass("lvs_scout_drr")
		LvsBeamCacheAt = CurTime() + 0.25
	end

	for _, drone in ipairs(LvsBeamCache) do
		if IsValid(drone) and drone:GetNWBool("LvsCryoActive") then
			local start, aim

			if drone == myDrone then
				-- свой дрон: считаем каждый кадр от той же точки/оси, что и сервер
				start = drone:LvsAttachmentPos("moac_muzzle") or drone:WorldSpaceCenter()

				local cam = drone:GetCamera()
				local na = drone:GetNWVector("LvsCryoAim")

				-- серверная точка попадания (поверхность цели): луч не проходит сквозь модель
				if not na:IsZero() then
					local id = drone:EntIndex()
					LvsBeamSmooth = LvsBeamSmooth or { }
					local st = LvsBeamSmooth[id]

					if not st or not st.aim or st.aim:Distance(na) > 300 then
						st = { aim = na }
						LvsBeamSmooth[id] = st
					else
						st.aim = LerpVector(0.5, st.aim, na)
					end

					aim = st.aim
				end

				local dir = drone:GetNWVector("LvsAutoDir", vector_origin)

				if aim then
					-- уже есть точка на поверхности цели
				elseif not dir:IsZero() then
					-- сглаживаем и у себя: сеть 15 Гц, иначе луч шагает
					local id = drone:EntIndex()
					LvsBeamSmooth = LvsBeamSmooth or { }
					local st = LvsBeamSmooth[id]

					if not st or not st.dir or st.dir:Distance(dir) > 0.5 then
						LvsBeamSmooth[id] = st or { }
						st = LvsBeamSmooth[id]
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
							return e == drone or e == cam or e:GetClass() == "lvs_scout_hitbox"
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
				local ns = drone:GetNWVector("LvsCryoStart")
				local na = drone:GetNWVector("LvsCryoAim")

				if ns:IsZero() or na:IsZero() then continue end

				local id = drone:EntIndex()
				LvsBeamSmooth = LvsBeamSmooth or { }
				local st = LvsBeamSmooth[id]

				if not st or st.aim:Distance(na) > 400 then
					st = { aim = na }
					LvsBeamSmooth[id] = st
				else
					st.aim = LerpVector(0.35, st.aim, na)
				end

				-- начало берём по кости/аттачменту: он уже интерполирован движком
				start = drone:LvsAttachmentPos("moac_muzzle") or ns
				aim   = st.aim
			end

			local dir = (aim - start):GetNormal()
			if dir:IsZero() then dir = drone:GetForward() end

			local muzzle = start + dir * 8

			render.SetMaterial(BEAM_MAT)
			render.DrawBeam(muzzle, aim, BEAM_WIDTH, 1, 1, Color(170, 220, 255))

			render.SetMaterial(GLOW_MAT)
			render.DrawSprite(aim, 84, 84, Color(120, 200, 255, 200))
		end
	end
end)

-- ===== Фонарики в патруле: луч до первого препятствия, за него не уходит =====
local LvsLightCache = { }

hook.Add("PreDrawTranslucentRenderables", "lvs_scout_flashlight", function(bDrawingDepth, bDrawingSkybox)
	if bDrawingSkybox then return end

	local now = CurTime()

	if not LvsBeamCache or now > (LvsBeamCacheAt or 0) then
		LvsBeamCache = ents.FindByClass("lvs_scout_drr")
		LvsBeamCacheAt = now + 0.25
	end

	-- фонарь и конус только ночью: флаг GWeather + реальная освещённость карты
	if not LvsGWNight then return end

	local lc = render.GetLightColor(LocalPlayer():GetPos())

	if (lc.r + lc.g + lc.b) / 3 > 140 then return end

	for _, drone in ipairs(LvsBeamCache) do
		if IsValid(drone) and drone:GetNWBool("LvsPatrol") then
			local start = drone:LvsAttachmentPos("light") or drone:WorldSpaceCenter()

			local id = drone:EntIndex()

			-- поисковый фонарь: наклон вниз и медленное качание по сторонам
			local sweep = math.sin(now * 1.1 + id) * 42
			local dir = Angle(48, drone:GetAngles().y + sweep, 0):Forward()

			local c = LvsLightCache[id]

			if not c or now > c.at then
				local filter = function(e)
					return e == drone or e:GetClass() == "lvs_scout_hitbox"
				end

				local tr = util.TraceLine({
					start  = start,
					endpos = start + dir * 3000,
					filter = filter,
					mask   = MASK_SOLID,
				})

				c = { at = now + 0.1, pos = tr.HitPos, dist = tr.Fraction * 3000, nrm = tr.HitNormal }
				LvsLightCache[id] = c
			end

			-- радиус пятна = радиус конца конуса; свет ставим в саму точку попадания
			local radius = math.Clamp((c.dist or 600) * 0.35, 250, 500) * 0.5

			-- реальный свет Source: ставим вдоль конуса, ближе к поверхности,
			-- чтобы он освещал её сверху, а не был зарыт в геометрию
			local lightPos = start + (c.pos - start) * 0.75

			DynamicLight(id % 4, lightPos, 255, 240, 200, 12, 0, radius * 2.2)


			-- конус от атачмента light (радиус 0) до пятна (радиус лампы)
			local axis = c.pos - start

			if axis:LengthSqr() > 64 then
				axis:Normalize()

				local right = axis:Cross(Vector(0, 0, 1))

				if right:LengthSqr() < 0.001 then right = axis:Cross(Vector(1, 0, 0)) end

				right:Normalize()

				local upv = right:Cross(axis):GetNormal()
				local segs = 18

				render.SetMaterial(GLOW_MAT)
				mesh.Begin(MATERIAL_TRIANGLE_STRIP, 2 * (segs + 1))

				for i = 0, segs do
					local a = math.rad(i / segs * 360)
					local ring = c.pos + (right * math.cos(a) + upv * math.sin(a)) * radius

					mesh.Position(start)
					mesh.TexCoord(0, 0.5)
					mesh.Color(255, 240, 200, 0)
					mesh.AdvanceVertex()

					mesh.Position(ring)
					mesh.TexCoord(1, 0.5)
					mesh.Color(255, 240, 200, 22)
					mesh.AdvanceVertex()
				end

				mesh.End()
			end

		end
	end
end)

-- Пресеты считают:
--   центр = GetForward()*10 + LocalToWorld(FirstPersonCam_pos)
--   низ   = LocalToWorld(FirstPersonCam_pos) - GetUp()*10
-- Чтобы центр был впереди, а низ — под дроном, GetForward отдаём неединичным (×20,
-- задаёт обёртка HUD), а FirstPersonCam_pos держим у корпуса.
function ENT:GetForward()
	local f = self.LvsFwdOverride
	if f then return f end
	return self:GetAngles():Forward()
end

-- ===== Видимый щит при модуле Shield (по всей модели, включая все кости) =====
local SHIELD_MAT = Material("models/props_combine/portalball001_sheet")

hook.Add("PostDrawTranslucentRenderables", "lvs_scout_shield", function(bDrawingDepth, bDrawingSkybox)
	if bDrawingSkybox or bDrawingDepth then return end

	local alpha = 0.22 + 0.08 * math.abs(math.sin(CurTime() * 2))

	-- список дронов кешируем, чтобы не искать каждый кадр
	if not LvsShieldCache or CurTime() > (LvsShieldCacheAt or 0) then
		LvsShieldCache = ents.FindByClass("lvs_scout_drr")
		LvsShieldCacheAt = CurTime() + 0.25
	end

	for _, drone in ipairs(LvsShieldCache) do
		if IsValid(drone) and drone:GetNWBool("hasModuleShield") and drone:GetNWInt("shield_health") > 0 then
			render.SuppressEngineLighting(true)
			render.MaterialOverride(SHIELD_MAT)
			render.SetBlend(alpha)

			-- цвет щита под расцветку дрона
			if drone:GetNWInt("LvsSkin", 0) == 1 then
				render.SetColorModulation(1, 0.25, 0.25)
			else
				render.SetColorModulation(0.55, 0.8, 1)
			end

			drone:DrawModel()

			render.SetColorModulation(1, 1, 1)
			render.SetBlend(1)
			render.MaterialOverride(nil)
			render.SuppressEngineLighting(false)
		end
	end
end)

-- Диагностика HUD: lvs_scout_hud_debug
concommand.Add("lvs_scout_hud_debug", function()
	local ply = LocalPlayer()
	local drone = ply:GetNWEntity("DronesRewriteDrone")
	if not IsValid(drone) then print("[LVS] нет дрона") return end

	local fwd = drone:GetForward()
	local fpc = drone.FirstPersonCam_pos or vector_origin
	local center = drone:LocalToWorld(fpc) + fwd * 10
	local bottom = drone:LocalToWorld(fpc) - drone:GetUp() * 10

	local c = center:ToScreen()
	local b = bottom:ToScreen()

	print("[LVS] fpc:", tostring(fpc))
	print("[LVS] |GetForward|:", math.Round(fwd:Length(), 2), tostring(fwd))
	print("[LVS] center screen:", math.Round(c.x), math.Round(c.y), c.visible)
	print("[LVS] bottom screen:", math.Round(b.x), math.Round(b.y), b.visible)
	print("[LVS] HUD:", tostring(drone:GetHUDName()), "DoCamEffects:", tostring(drone:DoCamEffects()))
end)
