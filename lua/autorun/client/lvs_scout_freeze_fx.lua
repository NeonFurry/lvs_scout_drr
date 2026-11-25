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
			and e:GetNWBool("LvsFrozen")
			and e:GetPos():DistToSqr(eye) < 4000 * 4000 then
			frozen[#frozen + 1] = e
		end
	end
end

hook.Remove("PreDrawHalos", "lvs_scout_freeze_halo")
hook.Remove("PostDrawTranslucentRenderables", "lvs_scout_freeze_fx")

hook.Add("PreDrawHalos", "lvs_scout_freeze_halo", function()
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

hook.Add("PostDrawTranslucentRenderables", "lvs_scout_freeze_fx", function(_, bSkybox)
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
