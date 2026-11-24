include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

local MODEL  = "models/props_junk/PopCan01a.mdl"
local SPEED  = 7000
local LIFE   = 1.5
local DAMAGE = 16

-- Kill есть не у всех целей, а урон по замороженным блокирует хук неуязвимости
local function killFrozen(target, owner, inflictor)
	target.LvsForceKill = true

	local dmg = DamageInfo()
	dmg:SetDamage(math.max(target:Health() or 1, 1) + 1000)
	dmg:SetDamageType(DMG_DISSOLVE)
	dmg:SetAttacker(IsValid(owner) and owner or inflictor)
	dmg:SetInflictor(inflictor)
	target:TakeDamageInfo(dmg)

	target.LvsForceKill = nil
end

function ENT:Initialize()
	-- модель нужна только для того, чтобы движок вызывал ENT:Draw (саму модель не рисуем)
	self:SetModel(MODEL)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_NONE)
	self:SetNotSolid(true)

	self.Vel = Vector(0, 0, 0)
	self.DieAt = CurTime() + LIFE
end

function ENT:SetDir(dir)
	dir = dir:GetNormal()

	self.Vel = dir * SPEED
	self:SetNWVector("LvsVel", self.Vel)
	self:SetAngles(dir:Angle())
end

function ENT:Impact(tr)
	if GetConVar("lvs_scout_debug") and GetConVar("lvs_scout_debug"):GetBool() then
		print("[LVS] ice impact:", tr.Entity, "frac:", tr.Fraction)
	end

	local pos = tr.HitPos
	local target = tr.Entity
	local owner = self:GetOwner()

	-- визуал попаданий не чаще 8 раз/с: иначе на броне копится мусор из эффектов
	local fx = true

	if IsValid(owner) then
		if CurTime() < (owner.LvsIceFxAt or 0) then fx = false end
		owner.LvsIceFxAt = CurTime() + 0.12
	end

	-- не бьём собственный дрон и его прокси-хитбоксы
	if IsValid(target) and (target == owner or target.LvsDrone == owner) then
		self:Remove()
		return
	end

	-- замороженная лучом цель → мгновенная смерть с разбиванием льда
	if IsValid(target) and (target:IsPlayer() or target:IsNPC() or target:IsNextBot())
		and LVSScout and LVSScout.IsFrozen(target) then

		if fx then
			self:EmitSound("physics/glass/glass_sheet_break" .. math.random(1, 3) .. ".wav", 85, 100)

			local ef = EffectData()
			ef:SetOrigin(pos)
			ef:SetNormal(tr.HitNormal)
			ef:SetScale(2)
			util.Effect("lvs_ice_shatter", ef, true, true)
		end

		killFrozen(target, owner, self)

		self:Remove()
		return
	end

	-- обычное попадание
	if fx then
		self:EmitSound("physics/glass/glass_impact_bullet" .. math.random(1, 4) .. ".wav", 70, math.random(110, 140))

		local ef = EffectData()
		ef:SetOrigin(pos)
		ef:SetNormal(tr.HitNormal)
		ef:SetScale(0.7)
		util.Effect("lvs_ice_shatter", ef, true, true)
	end

	if IsValid(target) then
		local amount = DAMAGE

		-- груз дропшипа бьём в разы сильнее
		if IsValid(owner) and owner.LvsIsCargo and owner:LvsIsCargo(target) then
			amount = amount * (owner.LvsAiHeavyDamageMul or 8)
		end

		local dmg = DamageInfo()
		dmg:SetDamage(amount)
		dmg:SetDamageType(DMG_DISSOLVE)
		dmg:SetAttacker(IsValid(owner) and owner or self)
		dmg:SetInflictor(self)

		local hpBefore = target:Health() or 0
		target:TakeDamageInfo(dmg)
		local hpAfter = target:Health() or 0

		-- попадание по текущей цели ИИ: сбрасываем счётчик «нет попаданий»
		if IsValid(owner) and owner.LvsAiTarget == target then
			owner.LvsEffectiveAt = CurTime()
		end

		-- адаптивный урон: если защита полностью блокирует выстрелы,
		-- после серии попаданий дрон пробивает её
		if IsValid(owner) and hpBefore > 0 and hpAfter >= hpBefore
			and (target:IsNPC() or target:IsNextBot() or target:IsPlayer()) then
			local now = CurTime()

			owner.LvsAdapt = owner.LvsAdapt or setmetatable({}, { __mode = "k" })
			owner.LvsAdaptAt = owner.LvsAdaptAt or setmetatable({}, { __mode = "k" })

			if now - (owner.LvsAdaptAt[target] or 0) > 3 then
				owner.LvsAdapt[target] = 0
			end

			owner.LvsAdaptAt[target] = now

			local n = (owner.LvsAdapt[target] or 0) + 1
			owner.LvsAdapt[target] = n

			if GetConVar("lvs_scout_debug") and GetConVar("lvs_scout_debug"):GetBool() then
				print("[LVS] adapt:", target:GetClass(), n .. "/" .. (owner.LvsAdaptLimit or 10),
					"hp:", hpBefore)
			end

			if n >= (owner.LvsAdaptLimit or 10) then
				local bypass = amount * (owner.LvsAdaptMul or 3)
				local cur = target:Health() or 0

				if cur > bypass then
					target:SetHealth(cur - bypass)
				else
					target:SetHealth(1)

					local kill = DamageInfo()
					kill:SetDamage(bypass + 1000)
					kill:SetDamageType(DMG_BLAST)
					kill:SetAttacker(owner)
					kill:SetInflictor(self)
					target:TakeDamageInfo(kill)

					if IsValid(target) and (target:Health() or 0) > 0 and isfunction(target.Kill) then
						target:Kill()
					end
				end
			end
		end
	end

	self:Remove()
end

function ENT:Think()
	local newPos = self:GetPos() + self.Vel * FrameTime()

	local owner = self:GetOwner()
	local filter = { self }

	if IsValid(owner) then
		table.insert(filter, owner)

		-- игнорируем собственные хитбоксы-прокси дрона
		for _, h in ipairs(owner.LvsHitboxes or {}) do
			if IsValid(h.ent) then table.insert(filter, h.ent) end
		end
	end

	-- коробка вместо луча: попадаем по краю модели, а не только точно в центр
	local tr = util.TraceHull({
		start  = self:GetPos(),
		endpos = newPos,
		-- шире коробка: шар летит 7000 ю/с, за тик проходит ~230 — узкая
		-- коробка проскакивает мимо краёв модели
		mins   = Vector(-8, -8, -8),
		maxs   = Vector(8, 8, 8),
		filter = filter,
		mask   = MASK_SHOT
	})

	if tr.Hit then
		self:Impact(tr)
		return
	end

	self:SetPos(newPos)

	if CurTime() > self.DieAt then
		self:Remove()
		return
	end

	self:NextThink(CurTime())
	return true
end
