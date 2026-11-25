-- Попадание ледяной пули: вспышка, расходящееся кольцо инея и шарды.
-- Нормаль приходит из импакта, поэтому кольцо лежит в плоскости поверхности.
local MAT = Material("particle/particle_glow_04_additive")

local RING = 12
local SHARDS = 5

function EFFECT:Init(data)
	self.pos = data:GetOrigin()
	self.nrm = (data:GetNormal() or Vector(0, 0, 1)):GetNormal()

	if self.nrm:IsZero() then self.nrm = Vector(0, 0, 1) end
	self.start = CurTime()
	self.dur = 0.34
	self.scale = math.Clamp(data:GetScale() or 1, 0.3, 3)

	-- базис в плоскости попадания
	local right = self.nrm:Cross(Vector(0, 0, 1))

	if right:LengthSqr() < 0.01 then right = self.nrm:Cross(Vector(1, 0, 0)) end

	right:Normalize()

	self.up = right:Cross(self.nrm)
	self.right = right

	self.ring = {}
	self.shards = {}

	for i = 1, RING do
		self.ring[i] = (i / RING) * math.pi * 2
	end

	for i = 1, SHARDS do
		local a = math.Rand(0, math.pi * 2)

		self.shards[i] = {
			dir = self.right * math.cos(a) + self.up * math.sin(a),
			dist = math.Rand(18, 42),
			size = math.Rand(7, 16),
		}
	end
end

function EFFECT:Think()
	return CurTime() < self.start + self.dur
end

function EFFECT:Render()
	local t = math.Clamp((CurTime() - self.start) / self.dur, 0, 1)

	render.SetMaterial(MAT)

	-- ядро вспышки живёт первые 30 % времени
	if t < 0.3 then
		local f = 1 - t / 0.3

		render.DrawSprite(self.pos, 62 * self.scale * f + 8, 62 * self.scale * f + 8,
			Color(140, 210, 255, 190 * f))
		render.DrawSprite(self.pos, 26 * self.scale * f + 6, 26 * self.scale * f + 6,
			Color(245, 252, 255, 240 * f))
	end

	-- кольцо инея расходится и гаснет
	local rad = Lerp(t, 4, 58) * self.scale

	for _, a in ipairs(self.ring) do
		local p = self.pos + (self.right * math.cos(a) + self.up * math.sin(a)) * rad
		local size = 12 * self.scale * (1 - t)

		render.DrawSprite(p, size, size, Color(120, 200, 255, 160 * (1 - t)))
	end

	-- шарды улетают в стороны и вниз, как осколки льда
	for _, s in ipairs(self.shards) do
		local p = self.pos + s.dir * s.dist * self.scale * (0.4 + t)
		local size = s.size * (1 - t) * self.scale

		render.DrawSprite(p, size, size, Color(190, 235, 255, 210 * (1 - t)))
	end
end
