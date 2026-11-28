include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

local MODEL  = "models/props_junk/PopCan01a.mdl"
local SPEED  = 7000
-- Живёт 0.4 с: за это время осколок пролетает 2800 юнитов — больше любой
-- дистанции боя. Раньше жил 1.5 с и десятки «пустых» сущностей висели
-- в воздухе, трассируя каждый кадр
local LIFE   = 0.6
local DAMAGE = 16

-- Kill есть не у всех целей, а урон по замороженным блокирует хук неуязвимости
local function killFrozen(target, owner, inflictor)
	target.DrrForceKill = true

	local dmg = DamageInfo()
	dmg:SetDamage(math.max(target:Health() or 1, 1) + 1000)
	dmg:SetDamageType(DMG_DISSOLVE)
	dmg:SetAttacker(IsValid(owner) and owner or inflictor)
	dmg:SetInflictor(inflictor)
	target:TakeDamageInfo(dmg)

	target.DrrForceKill = nil
end

-- Урон всегда засчитываем игроку: пилоту, а в автономном режиме — владельцу
-- дрона. Иначе часть фильтров (страйдер, killfeed) видит атакующего-дрон.
local function creditOf(owner)
	if not IsValid(owner) then return nil end

	local drv = owner.GetDriver and owner:GetDriver()
	if IsValid(drv) then return drv end

	if IsValid(owner.Owner) then return owner.Owner end

	if owner.GetOwner and IsValid(owner:GetOwner()) then return owner:GetOwner() end

	local nw = owner.GetNWEntity and owner:GetNWEntity("DrrOwner")
	if IsValid(nw) then return nw end
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
	self:SetAngles(dir:Angle())
end

-- Дальность выстрела: время жизни считаем от неё. Фиксированных 0.3 с
-- хватало только на ~2100 юнитов, и на низком FPS осколок затухал в полёте.
function ENT:SetRange(d)
	self.DrrRange = d
	self.DieAt = CurTime() + math.Clamp(d / SPEED + 0.15, 0.2, 0.9)
end

function ENT:Impact(tr)
	if GetConVar("drr_scout_debug") and GetConVar("drr_scout_debug"):GetBool() then
		print("[DRR] ice impact:", tr.Entity, "frac:", tr.Fraction)
	end

	local pos = tr.HitPos
	local target = tr.Entity
	local owner = self:GetOwner()
	local cred = creditOf(owner)

	-- Визуал попаданий: окно короче темпа пулемёта (1/6 с), иначе таймер
	-- продлевался каждым попаданием и эффект гас навсегда после первой пули
	local fx = true

	if IsValid(owner) then
		if CurTime() < (owner.DrrIceFxAt or 0) then
			fx = false
		else
			owner.DrrIceFxAt = CurTime() + 0.05
		end
	end

	-- не бьём собственный дрон и его прокси-хитбоксы
	if IsValid(target) and (target == owner or target.DrrDrone == owner) then
		self:Remove()
		return
	end

	-- замороженная лучом цель → мгновенная смерть с разбиванием льда
	if IsValid(target) and (target:IsPlayer() or target:IsNPC() or target:IsNextBot())
		and DRRScout and DRRScout.IsFrozen(target) then

		if fx then
			self:EmitSound("physics/glass/glass_sheet_break" .. math.random(1, 3) .. ".wav", 85, 100)

			local ef = EffectData()
			ef:SetOrigin(pos)
			ef:SetNormal(tr.HitNormal)
			ef:SetScale(2)
			util.Effect("drr_ice_shatter", ef, true, true)
		end

		killFrozen(target, cred or owner, self)

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
		util.Effect("drr_ice_shatter", ef, true, true)
	end

	if IsValid(target) then
		local amount = DAMAGE

		local heavy = IsValid(owner) and owner.DrrIsHeavy and owner:DrrIsHeavy(target)

		-- тяжёлые юниты: урон от их максимального HP,
		-- чтобы убийство занимало предсказуемое время
		if heavy and DrrHeavyHitDamage then amount = DrrHeavyHitDamage(target) end

		-- груз дропшипа бьём в разы сильнее
		if IsValid(owner) and owner.DrrIsCargo and owner:DrrIsCargo(target) then
			amount = amount * (owner.DrrAiHeavyDamageMul or 8)
		end

		-- урон засчитываем пилоту, а без пилота (ИИ) — владельцу дрона
		local dmg = DamageInfo()
		dmg:SetDamage(amount)
		-- свой крио-тип: страйдер принимает его через обёртку (см. autorun/server)
		dmg:SetDamageType(DMG_CRYO or bit.lshift(1, 25))
		dmg:SetAttacker(IsValid(cred) and cred or self)
		dmg:SetInflictor(self)

		local hpBefore = target:Health() or 0
		target:TakeDamageInfo(dmg)
		local hpAfter = target:Health() or 0

		-- попадание по текущей цели ИИ: сбрасываем счётчик «нет попаданий»
		if IsValid(owner) and owner.DrrAiTarget == target then
			owner.DrrEffectiveAt = CurTime()
		end

		-- Броня погасила урон: пробиваем вручную, пока не сработает
		if hpBefore > 0 and hpAfter >= hpBefore
			and (target:IsNPC() or target:IsNextBot() or target:IsPlayer()) then
			-- по тяжёлым не множим пробитие: иначе урон прыгает втрое
			local pierceAmount = heavy and amount
				or amount * (IsValid(owner) and owner.DrrAdaptMul or 3)
			local pierce = DamageInfo()
			pierce:SetDamage(pierceAmount)
			pierce:SetDamageType(DMG_BLAST)
			pierce:SetAttacker(IsValid(cred) and cred or self)
			pierce:SetInflictor(self)

			local hp1 = target:Health() or 0
			target:TakeDamageInfo(pierce)
			local hp2 = target:Health() or 0

			-- последняя попытка: взрыв от пилота (так страйдер урон принимает)
			if (target:Health() or 0) >= hp1 then
				util.BlastDamage(self, IsValid(cred) and cred or self, target:WorldSpaceCenter(),
					64, pierceAmount * 2)
			end

			if GetConVar("drr_scout_debug") and GetConVar("drr_scout_debug"):GetBool() then
				print("[DRR] pierce:", target:GetClass(), "attacker:", tostring(cred),
					"hp:", hp1, "->", target:Health())
			end
		end
	end

	self:Remove()
end

function ENT:Think()
	local newPos = self:GetPos() + self.Vel * FrameTime()

	-- Фильтр собираем один раз: раньше таблица с прокси-хитбоксами
	-- пересоздавалась 60 раз в секунду на каждый осколок
	if not self.TrFilter then
		local owner = self:GetOwner()
		local filter = { self }

		if IsValid(owner) then
			filter[#filter + 1] = owner

			for _, h in ipairs(owner.DrrHitboxes or {}) do
				if IsValid(h.ent) then filter[#filter + 1] = h.ent end
			end
		end

		self.TrFilter = filter
	end

	-- коробка вместо луча: попадаем по краю модели, а не только точно в центр
	local tr = util.TraceHull({
		start  = self:GetPos(),
		endpos = newPos,
		-- шире коробка: шар летит 7000 ю/с, за тик проходит ~230 — узкая
		-- коробка проскакивает мимо краёв модели
		mins   = Vector(-8, -8, -8),
		maxs   = Vector(8, 8, 8),
		filter = self.TrFilter,
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
