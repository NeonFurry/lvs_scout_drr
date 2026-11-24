-- Лёгкий эффект разбивания льда: расширяющаяся светящаяся вспышка.
local MAT = Material("particle/particle_glow_04_additive")

function EFFECT:Init(data)
	self.pos = data:GetOrigin()
	self.start = CurTime()
	self.dur = 0.22
	self.scale = math.Clamp(data:GetScale() or 1, 0.3, 3)
end

function EFFECT:Think()
	return CurTime() < self.start + self.dur
end

function EFFECT:Render()
	local f = math.Clamp((CurTime() - self.start) / self.dur, 0, 1)
	local size = Lerp(f, 18, 64) * self.scale

	render.SetMaterial(MAT)
	render.DrawSprite(self.pos, size, size, Color(150, 210, 255, 220 * (1 - f)))
end
