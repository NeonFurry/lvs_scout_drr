-- Модуль собран из отдельных файлов: правки вносить сюда.

-- ===== ЭМИ-импульс (lvs_scout_emp.lua) =====
-- ЭМИ-импульс: визуал, регдол НПС и ослепление игроков как от флешки.
util.AddNetworkString("lvs_scout_emp_fx")

local RADIUS = 2000
local RAGDOLL_NPC = 10.0
local BLIND_PLY = 5.0

local function blindOwner()
	if not ConVarExists("lvs_scout_emp_blind_owner") then
		CreateConVar("lvs_scout_emp_blind_owner", "1", FCVAR_ARCHIVE,
			"Слепить владельца дрона импульсом ЭМИ: 1 = да, 0 = водитель не слепнет")
	end

	return GetConVar("lvs_scout_emp_blind_owner"):GetBool()
end

-- «Регдол» без смерти: НПС жив, но падает физическим телом и ничего не может
local function ragdoll(npc)
	if not IsValid(npc) or npc.LvsEmpRagdoll then return false end

	npc.LvsEmpRagdoll = true

	npc:ClearSchedule()
	npc:SetNPCState(NPC_STATE_NONE)
	npc:SetSchedule(SCHED_NPC_FREEZE)
	npc:StopMoving()
	npc:SetEnemy(NULL)
	npc:ClearEnemyMemory()

	-- без физического тела остаётся только заморозка ИИ
	if not IsValid(npc:GetPhysicsObject()) then return true end

	npc:SetMoveType(MOVETYPE_VPHYSICS)
	npc:SetSolid(SOLID_VPHYSICS)
	npc:PhysicsInit(SOLID_VPHYSICS)

	local ph = npc:GetPhysicsObject()

	if IsValid(ph) then
		ph:Wake()
		ph:EnableGravity(true)
		ph:AddVelocity(Vector(0, 0, 30))
		ph:AddAngleVelocity(Vector(math.Rand(-70, 70), math.Rand(-70, 70), math.Rand(-70, 70)))
	end

	return true
end

local function unragdoll(npc)
	if not IsValid(npc) or not npc.LvsEmpRagdoll then return end

	npc.LvsEmpRagdoll = nil

	-- труп не поднимаем: у мёртвого НПС физика остаётся как есть
	if npc.Health and (npc:Health() or 0) <= 0 then return end

	npc:PhysicsDestroy()
	npc:SetSolid(SOLID_BBOX)
	npc:SetMoveType(MOVETYPE_STEP)
	npc:SetPos(npc:GetPos() + Vector(0, 0, 8))
	npc:SetNPCState(NPC_STATE_ALERT)
	npc:ClearSchedule()
end

-- Вспышка как в CS: белый экран, удержание и плавный спад
local function flashPlayer(ply, seconds)
	if not IsValid(ply) then return end

	ply:ScreenFade(SCREENFADE.IN, Color(255, 255, 255, 255), 0.35, math.max(seconds - 2.0, 0))

	timer.Simple(math.max(seconds - 1.7, 0.1), function()
		if IsValid(ply) then
			ply:ScreenFade(SCREENFADE.OUT, Color(255, 255, 255, 255), 1.7, 0)
		end
	end)
end

function LvsEmpApply(origin, owner)
	local radiusSqr = RADIUS * RADIUS

	-- НПС: на 10 секунд выведены из боя и лежат телом
	for _, n in ipairs(ents.FindInSphere(origin, RADIUS)) do
		if IsValid(n) and n:IsNPC() and (n:Health() or 0) > 0 then
			-- таймер только при первом регдоле: иначе повторный импульс
			-- укоротит оглушение вместо продления
			if ragdoll(n) then
				local npc = n

				timer.Simple(RAGDOLL_NPC, function() unragdoll(npc) end)
			end
		end
	end

	-- игроки: флешка на 5 секунд; владельца можно отключить конваром
	local blinded = {}

	for _, p in ipairs(player.GetAll()) do
		if IsValid(p) and p:Alive() and p:GetPos():DistToSqr(origin) < radiusSqr then
			if p == owner and not blindOwner() then continue end

			blinded[p] = true

			flashPlayer(p, BLIND_PLY)

			net.Start("lvs_scout_emp_fx")
			net.WriteVector(origin)
			net.WriteFloat(RADIUS)
			net.WriteBool(true)
			net.Send(p)
		end
	end

	-- остальным (и ослеплённым не повторно): только сам импульс в мире
	local others = {}

	for _, p in ipairs(player.GetAll()) do
		if IsValid(p) and not blinded[p] then others[#others + 1] = p end
	end

	net.Start("lvs_scout_emp_fx")
	net.WriteVector(origin)
	net.WriteFloat(RADIUS)
	net.WriteBool(false)
	net.Send(others)
end

-- Держим оглушённых без цели: часть НПС восстанавливает врага сама
local nextClear = 0

hook.Add("Think", "lvs_scout_emp_blind", function()
	if nextClear > CurTime() then return end

	nextClear = CurTime() + 0.25

	for _, n in ipairs(ents.FindByClass("npc_*")) do
		if IsValid(n) and n.LvsEmpRagdoll then
			n:ClearSchedule()
			n:SetEnemy(NULL)
		end
	end
end)

-- ===== Заморозка цели (lvs_scout_freeze.lua) =====
-- Заморозка криолучом: NPC 20с, игроки 5с (длительность задаёт вызывающий).
-- NPC/SNPC/NextBot удерживаются на месте; игрок теряет noclip (падает),
-- не может двигаться/прыгать, анимация стоит, урон не проходит.

LVSScout = LVSScout or {}

local frozen = {}
LVSScout.Frozen = frozen

local function isFreezable(ent)
	return IsValid(ent) and (ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot())
end

function LVSScout.IsFrozen(ent)
	return IsValid(ent) and (ent.LvsFrozenUntil or 0) > CurTime()
end

local function holdEntity(ent)
	if not IsValid(ent) then return end

	if ent.SetPlaybackRate then ent:SetPlaybackRate(0) end

	if ent:IsPlayer() then
		-- noclip выключаем; гравитация остаётся → падает и лежит
		if ent:GetMoveType() == MOVETYPE_NOCLIP then
			ent:SetMoveType(MOVETYPE_WALK)
		end

		ent:SetWalkSpeed(0)
		ent:SetRunSpeed(0)
		ent:SetMaxSpeed(0)
		ent:SetJumpPower(0)

		if ent.LvsFreezeAngles then
			ent:SetEyeAngles(ent.LvsFreezeAngles)
		end

		local v = ent:GetVelocity()
		ent:SetVelocity(Vector(0, 0, v.z))

		return
	end

	ent:SetVelocity(vector_origin)
	ent:SetLocalVelocity(vector_origin)

	if ent:IsNPC() then
		ent:SetNPCState(NPC_STATE_SCRIPT)
		if ent.ClearSchedule then ent:ClearSchedule() end
		ent:SetEnemy(NULL)
	end

	if ent.SetMoveType then
		ent:SetMoveType(MOVETYPE_NONE)
	end

	local loco = ent.loco
	if loco and loco.SetVelocity then
		loco:SetVelocity(vector_origin)
		if loco.SetDesiredSpeed then loco:SetDesiredSpeed(0) end
		if loco.SetAcceleration then loco:SetAcceleration(0) end
	end

	if ent.LvsAnchorPos then
		ent:SetPos(ent.LvsAnchorPos)
	end

	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetVelocity(vector_origin)
		phys:AddAngleVelocity(-phys:GetAngleVelocity())
	end
end

function LVSScout.Unfreeze(ent)
	if not IsValid(ent) then return end

	frozen[ent] = nil
	ent.LvsFrozenUntil = 0
	ent.LvsAnchorPos = nil

	if ent.SetPlaybackRate then ent:SetPlaybackRate(ent.LvsOldPlaybackRate or 1) end

	if ent:IsPlayer() then
		ent:SetNWBool("LvsFrozen", false)
		ent:SetNWFloat("LvsFrozenUntil", 0)

		ent:SetWalkSpeed(ent.LvsOldWalkSpeed or 400)
		ent:SetRunSpeed(ent.LvsOldRunSpeed or 600)
		ent:SetMaxSpeed(ent.LvsOldMaxSpeed or 600)
		ent:SetJumpPower(ent.LvsOldJumpPower or 200)
		ent:SetMoveType(ent.LvsOldMoveType or MOVETYPE_WALK)
	else
		if ent:IsNPC() then
			ent:SetNPCState(NPC_STATE_NONE)
		end
		if ent.SetMoveType then
			ent:SetMoveType(ent.LvsOldMoveType or MOVETYPE_STEP)
		end
	end

	if ent:IsPlayer() then
		ent:SetColor(ent.LvsOldColor or Color(255, 255, 255))
		ent:SetRenderMode(RENDERMODE_NORMAL)
	end
end

function LVSScout.Freeze(ent, duration, source)
	if not isFreezable(ent) then return end

	local nick = ""

	if IsValid(source) then
		local ply = source.GetOwner and source:GetOwner() or nil
		if not IsValid(ply) then ply = source.Owner end

		if IsValid(ply) and ply:IsPlayer() then
			nick = ply:Nick()
		else
			nick = source:GetNWString("OwnerName", "")
		end
	end

	local tname = "lvs_freeze_" .. ent:EntIndex()

	if (ent.LvsFrozenUntil or 0) > CurTime() then
		ent.LvsFrozenUntil = CurTime() + duration
		frozen[ent] = true
		ent:SetNWBool("LvsFrozen", true)
		ent:SetNWFloat("LvsFrozenUntil", ent.LvsFrozenUntil)
		if ent:IsPlayer() and nick ~= "" then ent:SetNWString("LvsFrozenBy", nick) end
		if timer.Exists(tname) then timer.Adjust(tname, duration, 1) end
		return
	end

	ent.LvsFrozenUntil = CurTime() + duration
	ent.LvsOldMoveType = ent:GetMoveType()
	ent.LvsOldColor = ent:GetColor()
	ent.LvsAnchorPos = ent:GetPos()
	ent.LvsOldPlaybackRate = (ent.GetPlaybackRate and ent:GetPlaybackRate()) or 1

	if ent:IsPlayer() then
		ent.LvsOldWalkSpeed = ent:GetWalkSpeed()
		ent.LvsOldRunSpeed = ent:GetRunSpeed()
		ent.LvsOldMaxSpeed = ent:GetMaxSpeed()
		ent.LvsOldJumpPower = ent:GetJumpPower()

		-- из noclip выходим с нулевой скоростью, чтобы падение началось с покоя
		if ent:GetMoveType() == MOVETYPE_NOCLIP then
			ent:SetVelocity(vector_origin)
		end

		ent.LvsFreezeAngles = ent:EyeAngles()
	end

	frozen[ent] = true
	holdEntity(ent)

	-- игрока красим плоско, у NPC вместо этого клиентская ледяная корка
	if ent:IsPlayer() then
		ent:SetColor(Color(130, 195, 255))
		ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
	end

	if ent:IsPlayer() then
		ent:SetNWBool("LvsFrozen", true)
		ent:SetNWFloat("LvsFrozenUntil", ent.LvsFrozenUntil)
		ent:SetNWString("LvsFrozenBy", nick)
	end

	local ef = EffectData()
	ef:SetOrigin(ent:WorldSpaceCenter())
	ef:SetEntity(ent)
	ef:SetScale(0.8)
	util.Effect("lvs_ice_shatter", ef, true, true)

	timer.Create(tname, duration, 1, function()
		if IsValid(ent) then LVSScout.Unfreeze(ent) end
	end)
end

-- Пока цель заморожена — урон по ней не проходит (кроме мгновенного убийства через Kill)
-- Лёд хрупкий: по замороженной цели любой урон проходит с множителем (быстрое добивание)
hook.Add("EntityTakeDamage", "lvs_freeze_brittle", function(ent, dmginfo)
	if LVSScout.IsFrozen(ent) and not ent.LvsForceKill then
		dmginfo:ScaleDamage(3)
	end
end)

hook.Add("SetupMove", "lvs_freeze_blockmove", function(ply, mv)
	if not LVSScout.IsFrozen(ply) then return end

	mv:SetForwardSpeed(0)
	mv:SetSideSpeed(0)
	mv:SetUpSpeed(0)
	mv:SetMaxSpeed(0)

	if ply.LvsFreezeAngles then
		mv:SetAngles(ply.LvsFreezeAngles)
	end
end)

hook.Add("Think", "lvs_freeze_enforce", function()
	local now = CurTime()

	for ent in pairs(frozen) do
		if not IsValid(ent) then
			frozen[ent] = nil
		elseif (ent.LvsFrozenUntil or 0) <= now then
			LVSScout.Unfreeze(ent)
		else
			holdEntity(ent)
		end
	end
end)

-- Замороженные NPC не должны стрелять (анимационные события успевают сработать)
hook.Add("EntityFireBullets", "lvs_freeze_noshoot", function(ent)
	if IsValid(ent) and (ent.LvsFrozenUntil or 0) > CurTime() then
		return false
	end
end)

-- Замороженный NPC не наносит урон: ни пулями, ни альт-атакой (снаряд/шар), ни ближним боем
hook.Add("EntityTakeDamage", "lvs_freeze_no_damage_from_frozen", function(_, dmginfo)
	local att = dmginfo:GetAttacker()
	if not IsValid(att) then return end

	if (att.LvsFrozenUntil or 0) > CurTime() then return true end

	local owner = att.GetOwner and att:GetOwner()
	if IsValid(owner) and (owner.LvsFrozenUntil or 0) > CurTime() then return true end
end)

-- ===== Тип урона DMG_CRYO (lvs_scout_cryo_damage.lua) =====
-- Свой тип урона для криооружия: Source не имеет DMG_CRYO,
-- поэтому занимаем свободный бит и сами решаем, кто его принимает.

DMG_CRYO = DMG_CRYO or bit.lshift(1, 25)

-- Страйдер принимает урон только через DMG_BLAST (50 HP + флинч) либо
-- внутренний DMG_GENERIC. Движковый путь ненадёжен: на части сборок
-- DMG_GENERIC по страйдеру просто не проходит. Поэтому сначала пробуем
-- штатно, а если HP не изменился — снимаем ровно 5 HP напрямую.
local STRIDER_DAMAGE = 5

-- Урон по тяжёлым юнитам считается от их максимального HP, чтобы смерть
-- занимала примерно одинаковое время: не ваншот и не марафон на 5 HP.
-- 1.2 % от максимума за попадание: 3500 HP → 40, 1000 HP → 12, 255 HP → 4.
local HEAVY_FRACTION = 0.012

function LvsHeavyHitDamage(ent)
	local mx = 0

	if IsValid(ent) then
		mx = ent.GetMaxHealth and (ent:GetMaxHealth() or 0) or 0
	end

	return math.Clamp(math.max(mx * HEAVY_FRACTION, 4), 4, 40)
end

hook.Remove("OnEntityCreated", "lvs_scout_strider_spawnshield")
hook.Remove("EntityTakeDamage", "lvs_scout_strider_cryo")

local function dbgOn()
	local cv = GetConVar("lvs_scout_debug")
	return cv and cv:GetBool()
end

hook.Add("EntityTakeDamage", "lvs_scout_strider_cryo", function(ent, dmg)
	if not IsValid(ent) or ent:GetClass() ~= "npc_strider" then return end

	local dtype = dmg:GetDamageType()

	if bit.band(dtype, DMG_CRYO) == 0 then return end

	local hpBefore = ent:Health() or 0
	local attacker = dmg:GetAttacker()
	local inflictor = dmg:GetInflictor()

	local hit = LvsHeavyHitDamage(ent)

	dmg:SetDamageType(DMG_GENERIC)
	dmg:SetDamage(hit)

	-- штатный путь мог не сработать: проверяем следующий тик
	timer.Simple(0, function()
		if not IsValid(ent) then return end

		local hpAfter = ent:Health() or 0

		if hpAfter < hpBefore then return end

		local newHp = math.max(hpBefore - hit, 0)

		ent:SetHealth(newHp)

		if newHp <= 0 then
			local kill = DamageInfo()

			kill:SetDamage(100000)
			kill:SetDamageType(DMG_GENERIC)
			kill:SetAttacker(IsValid(attacker) and attacker or ent)
			kill:SetInflictor(IsValid(inflictor) and inflictor or ent)

			ent:TakeDamageInfo(kill)
		end

		if dbgOn() then
			print(string.format("[LVS] strider direct: %d -> %d", hpBefore, ent:Health() or 0))
		end
	end)

	if dbgOn() then
		print(string.format("[LVS] strider cryo: type=%d hp=%d", dtype, hpBefore))
	end
end)


-- Диагностика: нанести 5 криоурона страйдеру под прицелом (обход оружия)
concommand.Add("lvs_scout_strider_test", function(ply)
	if not IsValid(ply) then return end

	local tr = ply:GetEyeTrace()

	if not IsValid(tr.Entity) or tr.Entity:GetClass() ~= "npc_strider" then
		print("[LVS] под прицелом не страйдер:", tr.Entity)
		return
	end

	local ent = tr.Entity
	local before = ent:Health() or 0
	local dmg = DamageInfo()

	dmg:SetDamage(STRIDER_DAMAGE)
	dmg:SetDamageType(DMG_CRYO)
	dmg:SetAttacker(ply)
	dmg:SetInflictor(ply)

	ent:TakeDamageInfo(dmg)

	timer.Simple(0, function()
		if not IsValid(ent) then return end

		print(string.format("[LVS] test: hp %d -> %d", before, ent:Health() or 0))
	end)
end)

-- ===== Дружественный огонь и друзья-НПС (lvs_scout_friendly_dmg.lua) =====
-- Дроны одного владельца не наносят друг другу урон.
-- Дроны разных игроков друг друга бьют как обычно.

local function droneOf(ent)
	if not IsValid(ent) then return end

	if ent:GetClass() == "lvs_scout_drr" then return ent end
	if IsValid(ent.LvsDrone) then return ent.LvsDrone end
	if ent.IS_DRONE then return ent end
end

local function ownerOf(ent)
	local drone = droneOf(ent)
	if not drone then return end

	local owner = drone.Owner or drone:GetOwner()
	return IsValid(owner) and owner or nil
end

hook.Remove("EntityTakeDamage", "lvs_scout_friendly_dmg")

hook.Add("EntityTakeDamage", "lvs_scout_friendly_dmg", function(ent, dmg)
	local attackerOwner = ownerOf(dmg:GetAttacker())
	if not attackerOwner then return end

	if attackerOwner == ownerOf(ent) then return true end
end)

-- Дружественные NPC (класс есть в F3) не атакуют дрона:
-- им выставляется отношение D_LI к дрону, а их урон по нему блокируется
local function friendOf(drone, npcClass)
	if not IsValid(drone) then return false end

	local friends = drone.LvsFriendClasses
	return friends and npcClass and friends[npcClass] or false
end

hook.Remove("EntityTakeDamage", "lvs_scout_friend_npc")

hook.Add("EntityTakeDamage", "lvs_scout_friend_npc", function(ent, dmg)
	local drone = droneOf(ent)
	if not drone then return end

	local attacker = dmg:GetAttacker()
	if IsValid(attacker) and attacker:IsNPC() and friendOf(drone, attacker:GetClass()) then
		return true
	end
end)

-- НПС видят дрон через триггеры базы DRR, а не через сам дрон: дружбу
-- ставим на всё, что может попасть к ним во враги, и приоритетом 100,
-- чтобы перебить D_HT, который база пишет с приоритетом 99
local function calmNpc(npc, drone)
	npc:AddEntityRelationship(drone, D_LI, 100)

	for _, tr in pairs(drone.ValidNpcTriggers or {}) do
		if IsValid(tr) then npc:AddEntityRelationship(tr, D_LI, 100) end
	end

	local enemy = npc:GetEnemy()

	if enemy == drone or (IsValid(enemy) and enemy.LvsDrone == drone) then
		npc:SetEnemy(NULL)
		npc:ClearEnemyMemory()
	end
end

hook.Remove("Think", "lvs_scout_friend_npc_calm")

hook.Add("Think", "lvs_scout_friend_npc_calm", function()
	if CurTime() < (LvsFriendCalmAt or 0) then return end
	LvsFriendCalmAt = CurTime() + 0.5

	for _, drone in ipairs(ents.FindByClass("lvs_scout_drr")) do
		if IsValid(drone) and drone.LvsFriendClasses then
			for _, npc in ipairs(ents.FindInSphere(drone:GetPos(), 4000)) do
				if IsValid(npc) and npc:IsNPC() and friendOf(drone, npc:GetClass()) then
					calmNpc(npc, drone)
				end
			end
		end
	end
end)

-- ===== Джаммер без лимита дистанции (lvs_scout_jammer_range.lua) =====
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

-- ===== Ночной режим GWeather (lvs_scout_gweather.lua) =====
-- Управление ночью через GWeather (сущность gw_t1_night) + рассылка состояния в HUD

util.AddNetworkString("lvs_scout_gw_night")
util.AddNetworkString("lvs_scout_gw_state")

local NIGHT_CLASS = "gw_t1_night"

-- Состояние храним сами: сущность может удаляться после применения ночи
local nightState = false

local function nightEntity()
	return #ents.FindByClass(NIGHT_CLASS) > 0
end

local function broadcast()
	net.Start("lvs_scout_gw_state")
	net.WriteBool(nightState)
	net.Broadcast()
end

local function setNight(on)
	nightState = on
	broadcast()
end

local function reply(ply)
	net.Start("lvs_scout_gw_night")
	net.WriteBool(nightState)
	net.Send(ply)
end

-- Новому игроку отправляем актуальное состояние
hook.Add("PlayerInitialSpawn", "lvs_scout_gw_sync", function()
	timer.Simple(2, function()
		if nightState or nightEntity() then broadcast() end
	end)
end)

-- Состояние следим по наличию сущности ночи в обе стороны:
-- спавн/удаление (в т.ч. сторонним аддоном) сразу меняет флаг
timer.Create("lvs_scout_gw_state", 1, 0, function()
	local present = nightEntity()

	if present ~= nightState then setNight(present) end
end)

net.Receive("lvs_scout_gw_night", function(_, ply)
	if not IsValid(ply) then return end

	local drone = ply:GetNWEntity("DronesRewriteDrone")
	if not IsValid(drone) or drone:GetClass() ~= "lvs_scout_drr" then return end

	-- клиент присылает ЖЕЛАЕМОЕ состояние: true — ночь, false — убрать
	local want = net.ReadBool()

	if want then
		if not nightEntity() then
			local e = ents.Create(NIGHT_CLASS)

			if IsValid(e) then
				e:SetPos(ply:GetPos() + Vector(0, 0, 200))
				e:SetAngles(angle_zero)
				e:Spawn()
				e:Activate()
			else
				print("[LVS] GWeather: не удалось создать " .. NIGHT_CLASS .. " — проверь, что аддон смонтирован")
			end
		end

		setNight(nightEntity())
	else
		for _, e in ipairs(ents.FindByClass(NIGHT_CLASS)) do e:Remove() end
		setNight(false)
	end

	reply(ply)
end)

-- ===== Метка цели пилотом (lvs_scout_mark.lua) =====
-- Метка цели пилотом: игрок из дрона указывает врага (СКМ), автономные
-- дроны владельца летят на него. Цель берётся строго под прицелом камеры.
util.AddNetworkString("lvs_scout_mark")
util.AddNetworkString("lvs_scout_mark_alert")

-- не больше трёх дронов на одну метку, как и для тяжёлой техники
local MARK_ATTACKERS = 3

net.Receive("lvs_scout_mark", function(_, ply)
	if not IsValid(ply) then return end

	local drone = ply:GetNWEntity("DronesRewriteDrone")

	if not IsValid(drone) then
		return
	end

	-- кулдаун: метка за стеной перебирает сущности мира, не даём спамить
	if CurTime() < (ply.LvsMarkCd or 0) then return end

	ply.LvsMarkCd = CurTime() + 0.3

	local cam = drone.GetCamera and drone:GetCamera()

	if not IsValid(cam) then return end

	local filter = { drone, ply }

	for _, h in ipairs(drone.LvsHitboxes or {}) do
		if IsValid(h.ent) then filter[#filter + 1] = h.ent end
	end

	local start = cam:GetPos()
	local dir = cam:GetAngles():Forward()

	local tr = util.TraceLine({
		start  = start,
		endpos = start + dir * 12000,
		filter = filter,
		mask   = MASK_SHOT,
	})

	local tgt = tr.Entity

	if not IsValid(tgt) or not (tgt:IsNPC() or tgt:IsNextBot() or tgt:IsPlayer())
		or tgt == ply or tgt:GetClass() == "lvs_scout_drr" then
		-- Метку можно ставить и за стеной: ищем цель вдоль прицела,
		-- не останавливаясь на геометрии
		local found, foundDist
		local box = Vector(-28, -28, -28)

		for _, e in ipairs(ents.FindAlongRay(start, start + dir * 6000, box, -box)) do
			if IsValid(e) and e ~= drone and e ~= ply
				and (e:IsNPC() or e:IsNextBot() or e:IsPlayer())
				and e:GetClass() ~= "lvs_scout_drr" then
				local d = (e:WorldSpaceCenter() - start):LengthSqr()

				if not foundDist or d < foundDist then
					found, foundDist = e, d
				end
			end
		end

		tgt = found
	end

	if not IsValid(tgt) then
		return
	end

	local origin = drone:GetPos()
	local list = {}

	for _, d in ipairs(ents.FindByClass("lvs_scout_drr")) do
		local owned = d and (d.Owner == ply or d:GetOwner() == ply)

		if IsValid(d) and d ~= drone and owned and d.LvsAutonomous then
			list[#list + 1] = d
		end
	end

	-- ближайшие первыми: они долетят раньше
	table.sort(list, function(a, b)
		return a:GetPos():DistToSqr(origin) < b:GetPos():DistToSqr(origin)
	end)

	local sent = 0

	for _, d in ipairs(list) do
		if sent >= MARK_ATTACKERS then break end

		d:LvsRecvMark(tgt, drone)
		sent = sent + 1
	end

	-- метка в HUD
	net.Start("lvs_scout_mark_alert")
	net.WriteString(tgt:GetClass())
	net.WriteVector(tgt:WorldSpaceCenter())
	net.WriteEntity(tgt)
	net.Send(player.GetAll())

end)

-- ===== Тело пилота (lvs_scout_pilot_body.lua) =====
-- Пока игрок пилотирует дрон DRR, его тело не должно ходить.
-- EyeAngles трогать нельзя: DRR считает рыскание дрона из driver:EyeAngles().

local function pilotDrone(ply)
	local drone = ply:GetNWEntity("DronesRewriteDrone")
	if IsValid(drone) then return drone end
end

hook.Add("SetupMove", "lvs_scout_pilot_body_move", function(ply, mv)
	if not pilotDrone(ply) then return end
	if ply.LvsFrozen then return end

	mv:SetForwardSpeed(0)
	mv:SetSideSpeed(0)
	mv:SetUpSpeed(0)
	mv:SetMaxSpeed(0)
	mv:SetMaxClientSpeed(0)
end)

-- Невидимых пилотов могут убить только NPC/NextBot (и их снаряды).
-- Игроки, дроны и всё остальное урона не наносят.
hook.Add("EntityTakeDamage", "lvs_scout_pilot_immortal", function(ent, dmginfo)
	if not ent:IsPlayer() then return end
	if not IsValid(ent:GetNWEntity("DronesRewriteDrone")) then return end

	local att = dmginfo:GetAttacker()

	if IsValid(att) then
		if att:IsNPC() or att:IsNextBot() then return end

		local owner = att.GetOwner and att:GetOwner()
		if IsValid(owner) and (owner:IsNPC() or owner:IsNextBot()) then return end
	end

	return true
end)
