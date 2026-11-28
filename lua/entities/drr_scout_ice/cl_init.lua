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
	local perf = IsValid(owner) and owner.GetNWBool and owner:GetNWBool("DrrPerf")
	local steps = perf and 5 or 10

	render.SetMaterial(GLOW_MAT)

	-- хвост-комета: длиннее и ярче, чтобы пули читались в бою
	for i = 1, steps do
		local f = i / steps
		local p = pos - dir * (f * 420)
		local size = 34 * (1 - f) + 3

		render.DrawSprite(p, size, size, Color(90, 185, 255, 245 * (1 - f) * (1 - f)))
	end

	if not perf then
		render.DrawSprite(pos, 60, 60, Color(110, 200, 255, 200))
	end

	-- ядро с ореолом
	render.DrawSprite(pos, 30, 30, Color(150, 220, 255, 220))
	render.DrawSprite(pos, 20, 20, Color(245, 253, 255, 255))
end
