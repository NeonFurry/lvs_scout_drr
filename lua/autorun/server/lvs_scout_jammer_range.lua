-- Джаммер DRR: работает на любой дистанции и в обоих режимах (ПКМ — прямое наведение).
-- Штатный код ограничен Range = 5000 и не находит дрон за прокси-хитбоксами,
-- поэтому переопределяем PrimaryAttack и на классе, и на каждом экземпляре оружия.

local MAX_DIST = 65536

local function resolveDrone(ent)
	if not IsValid(ent) then return end
	if IsValid(ent.LvsDrone) then return ent.LvsDrone end
	if ent:GetClass() == "lvs_scout_drr" then return ent end
end

local function jam(drone, owner)
	if not IsValid(drone) or not drone.LvsJamRemote then return end
	drone:LvsJamRemote(owner)
end

-- Прямое наведение: дистанция не ограничена, нужна только видимость
-- (дрон держится в конусе прицела, между вами и им нет геометрии)
local function visibleDrone(owner)
	local eye = owner:GetShootPos()
	local aim = owner:GetAimVector()

	local best, bestDot = nil, 0.92

	for _, drone in ipairs(ents.FindByClass("lvs_scout_drr")) do
		if IsValid(drone) then
			local target = drone:WorldSpaceCenter()
			local dir = (target - eye):GetNormal()
			local dot = dir:Dot(aim)

			if dot > bestDot then
				local filter = { owner, drone }

				for _, hb in ipairs(drone.LvsHitboxes or {}) do
					if IsValid(hb.ent) then filter[#filter + 1] = hb.ent end
				end

				-- только геометрия мира: другие сущности не считаются укрытием
				local tr = util.TraceLine({
					start  = eye,
					endpos = target,
					filter = filter,
					mask   = MASK_SOLID_BRUSHONLY,
				})

				if not tr.Hit then
					best, bestDot = drone, dot
				end
			end
		end
	end

	return best
end

-- Запасной вариант: коробка вдоль прицела (мелкая цель рядом с перекрестием)
local function directTarget(owner)
	local drone = visibleDrone(owner)
	if IsValid(drone) then return drone end

	local tr = util.TraceHull({
		start  = owner:GetShootPos(),
		endpos = owner:GetShootPos() + owner:GetAimVector() * MAX_DIST,
		mins   = Vector(-24, -24, -24),
		maxs   = Vector(24, 24, 24),
		mask   = MASK_SHOT,
		filter = owner,
	})

	return resolveDrone(tr.Entity)
end

-- Режим по площади: прокси-хитбоксы сводятся к одному дрону
local function areaTargets(swep)
	local range = (swep.Range or 5000) * (swep.AreaModeRangeMult or 1 / 5)
	local seen, out = {}, {}

	for _, v in ipairs(ents.FindInSphere(swep:GetPos(), range)) do
		local drone = resolveDrone(v)

		if IsValid(drone) and not seen[drone] then
			seen[drone] = true
			out[#out + 1] = drone
		end
	end

	return out
end

local function jammerPrimary(self)
	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)

	local direct = self.IsInDirectMode
	local seq = (self.SequenceDuration and self:SequenceDuration()) or 0.5
	local useDelay = self.UseDelay or 2

	if not direct then useDelay = useDelay * (self.AreaModeDelayMult or 1.5) end

	self:SetNextPrimaryFire(CurTime() + useDelay)
	self:SetNWBool("WasInDirectMode", direct)

	timer.Simple(seq / 2, function()
		if not IsValid(self) then return end
		self:EmitSound("buttons/button14.wav", 50, 90)
	end)

	timer.Simple(seq + 0.2, function()
		if not IsValid(self) or not IsValid(owner) then return end

		if direct then
			jam(directTarget(owner), owner)
			return
		end

		for _, drone in ipairs(areaTargets(self)) do
			jam(drone, owner)
		end
	end)
end

-- 1) класс (для новых экземпляров) — без флага, чтобы переживало перезагрузку скриптов
local function patchClass()
	local swep = weapons.Get("weapon_drr_jammer")
	if not swep then return end

	swep.PrimaryAttack = jammerPrimary
end

-- 2) конкретный экземпляр: перебивает штатный код даже если он загрузился позже
hook.Add("OnEntityCreated", "lvs_jammer_instances", function(ent)
	timer.Simple(0, function()
		if not IsValid(ent) or ent:GetClass() ~= "weapon_drr_jammer" then return end

		ent.PrimaryAttack = jammerPrimary
	end)
end)

-- 3) уже выданные оружия в руках игроков
local function patchHeld()
	for _, ply in ipairs(player.GetAll()) do
		for _, w in ipairs(ply:GetWeapons()) do
			if IsValid(w) and w:GetClass() == "weapon_drr_jammer" then
				w.PrimaryAttack = jammerPrimary
			end
		end
	end
end

hook.Add("InitPostEntity", "lvs_jammer_class", function()
	patchClass()
	patchHeld()
end)

hook.Add("PlayerSwitchWeapon", "lvs_jammer_switch", function(ply, old, new)
	if IsValid(new) and new:GetClass() == "weapon_drr_jammer" then
		new.PrimaryAttack = jammerPrimary
	end
end)

timer.Simple(0, patchClass)
timer.Simple(3, function()
	patchClass()
	patchHeld()
end)
timer.Simple(10, function()
	patchClass()
	patchHeld()
end)
