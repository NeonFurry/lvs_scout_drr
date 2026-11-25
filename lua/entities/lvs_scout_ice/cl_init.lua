include("shared.lua")

-- Пуля-льдышка: голова с гало и сужающийся хвост-комета.
-- Спрайты вдоль оси дают сплошной след без DrawBeam и без сетевых переменных.
-- На слабом ПК (пресет «слабый») хвост короче: темп стрельбы тот же,
-- экономим только на отрисовке.
local GLOW_MAT = Material("particle/particle_glow_04_additive")

function ENT:Draw()
	local pos = self:GetPos()
	local dir = self:GetAngles():Forward()

	if dir:IsZero() then return end

	local owner = self:GetOwner()
	local perf = IsValid(owner) and owner.GetNWBool and owner:GetNWBool("LvsPerf")
	local steps = perf and 3 or 7

	render.SetMaterial(GLOW_MAT)

	for i = 1, steps do
		local f = i / steps
		local p = pos - dir * (f * 260)
		local size = 26 * (1 - f) + 3

		render.DrawSprite(p, size, size, Color(80, 170, 255, 190 * (1 - f) * (1 - f)))
	end

	if not perf then
		render.DrawSprite(pos, 42, 42, Color(110, 195, 255, 130))
	end

	render.DrawSprite(pos, 15, 15, Color(240, 252, 255, 255))
end
