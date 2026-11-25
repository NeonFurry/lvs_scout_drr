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
		if IsValid(e) and not e:IsPlayer() and e:GetNWBool("LvsFrozen") then
			cache[#cache + 1] = e
		end
	end

	return cache
end

hook.Add("PostDrawTranslucentRenderables", "lvs_scout_frozen_shell", function(bDrawingDepth, bDrawingSkybox)
	if bDrawingSkybox or bDrawingDepth then return end

	local list = frozenList()
	if #list == 0 then return end

	local now = CurTime()
	local pulse = 0.3 + 0.1 * math.abs(math.sin(now * 3))

	render.SuppressEngineLighting(true)
	render.MaterialOverride(ICE_MAT)
	render.SetColorModulation(0.55, 0.82, 1)

	for _, e in ipairs(list) do
		if IsValid(e) and e:GetNWFloat("LvsFrozenUntil", 0) > now then
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
		if IsValid(e) and e:GetNWFloat("LvsFrozenUntil", 0) > now then
			local c = e:WorldSpaceCenter()
			render.DrawSprite(c, 150, 150, Color(140, 205, 255, 55))
		end
	end
end)
