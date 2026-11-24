include("shared.lua")

-- Пуля-льдышка: яркий светящийся снаряд с длинным хвостом, чтобы был виден полёт.
local BEAM_MAT = Material("effects/blueblacklargebeam")
local GLOW_MAT = Material("particle/particle_glow_04_additive")

local TRAIL_LEN = 110

function ENT:Draw()
	local pos = self:GetPos()
	local vel = self:GetNWVector("LvsVel", vector_origin)

	local dir = vel:GetNormal()
	if dir:IsZero() then dir = self:GetForward() end

	local tail = pos - dir * TRAIL_LEN

	-- хвост
	render.SetMaterial(BEAM_MAT)
	render.DrawBeam(tail, pos, 9, 1, 1, Color(175, 225, 255, 235))

	-- затухающие точки вдоль хвоста
	render.SetMaterial(GLOW_MAT)
	render.DrawSprite(tail, 14, 14, Color(140, 205, 255, 90))
	render.DrawSprite(pos - dir * (TRAIL_LEN * 0.55), 18, 18, Color(160, 215, 255, 140))

	-- ядро снаряда
	render.DrawSprite(pos, 36, 36, Color(190, 235, 255, 235))
	render.DrawSprite(pos, 16, 16, Color(255, 255, 255, 255))
end
