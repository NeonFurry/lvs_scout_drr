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