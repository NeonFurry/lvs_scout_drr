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
