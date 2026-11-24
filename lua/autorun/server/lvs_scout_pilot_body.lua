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
