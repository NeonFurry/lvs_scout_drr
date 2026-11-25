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
