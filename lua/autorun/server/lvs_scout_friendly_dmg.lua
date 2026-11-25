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

hook.Remove("Think", "lvs_scout_friend_npc_calm")

hook.Add("Think", "lvs_scout_friend_npc_calm", function()
	if CurTime() < (LvsFriendCalmAt or 0) then return end
	LvsFriendCalmAt = CurTime() + 1

	for _, drone in ipairs(ents.FindByClass("lvs_scout_drr")) do
		if IsValid(drone) and drone.LvsFriendClasses then
			for _, npc in ipairs(ents.FindInSphere(drone:GetPos(), 4000)) do
				if IsValid(npc) and npc:IsNPC() and friendOf(drone, npc:GetClass()) then
					npc:AddEntityRelationship(drone, D_LI, 99)

					-- если уже успел взять в враги — сбрасываем
					if npc:GetEnemy() == drone then npc:SetEnemy(NULL) end
				end
			end
		end
	end
end)