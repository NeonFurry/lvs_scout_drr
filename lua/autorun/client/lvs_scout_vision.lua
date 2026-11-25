hook.Remove("PlayerBindPress", "lvs_scout_vision")
hook.Remove("PostDrawTranslucentRenderables", "lvs_scout_vision_glow")
-- F в режиме пилотирования: подсветка игроков и NPC обводкой.
-- Цвет обводки берётся из текущего overlay дрона DRR (Red → красная).

local enabled = false
local MAX_DIST = 6000

local function pilotDrone()
	local drone = LocalPlayer():GetNWEntity("DronesRewriteDrone")
	if IsValid(drone) and drone:GetClass() == "lvs_scout_drr" then return drone end
end

local function toggleVision()
	if not pilotDrone() then return end

	enabled = not enabled
	LVSScoutVision = enabled


	print("[LVS Scout] vision =", enabled, "drone =", tostring(pilotDrone()))
end

concommand.Add("lvs_scout_vision", toggleVision)

-- Диагностика: что видит подсветка и в каком состоянии каждая цель
concommand.Add("lvs_scout_vision_dump", function()
	local drone = pilotDrone()
	if not drone then print("[LVS] дрон не найден") return end

	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) and e ~= drone and (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) then
			local bone = e:LookupBone("ValveBiped.Bip01_Head1")
			local bp = bone and e:GetBonePosition(bone)

			print(string.format("[LVS] %s | dormant=%s | bone=%s | bp=%s | dist=%d",
				e:GetClass(), tostring(e:IsDormant()), tostring(bone), type(bp),
				math.floor(drone:GetPos():Distance(e:GetPos()))))
		end
	end
end)

-- Цвет метки: друг — зелёный, враг — красный, нейтрал — жёлтый,
-- свой дрон — фиолетовый, чужой дрон — жёлтый
function LvsBlipColor(ent)
	if not IsValid(ent) then return Color(255, 220, 90) end

	-- дружественные игроки — салатовый
	if ent:IsPlayer() and LvsFriendSet and LvsFriendSet["@" .. ent:SteamID()] then
		return Color(170, 255, 90)
	end

	local cls = ent:GetClass()
	local owner = ent.GetNWEntity and ent:GetNWEntity("LvsOwner")
	local ownerID = ent.GetNWString and ent:GetNWString("LvsOwnerID")
	local me = LocalPlayer()

	if ent.IS_DRONE or cls == "lvs_scout_drr" then
		local mine = (IsValid(owner) and owner == me)
			or (IsValid(me) and ownerID ~= "" and ownerID == me:SteamID())

		if mine then return Color(190, 120, 255) end

		return Color(255, 220, 90)
	end

	if LvsIsFriendClass and LvsIsFriendClass(cls) then
		return Color(120, 255, 150)
	end

	if IsEnemyEntityName and IsEnemyEntityName(cls) then
		return Color(255, 70, 70)
	end

	return Color(255, 220, 90)
end

hook.Add("PreDrawHalos", "lvs_scout_vision_halos", function()
	if not enabled then return end

	local drone = pilotDrone()
	if not drone then return end

	local origin = drone:GetPos()
	local maxSqr = MAX_DIST * MAX_DIST
	local ply = LocalPlayer()
	local friends, enemies, neutrals, own, players = {}, {}, {}, {}, {}

	-- ночная оптика рисует свои контуры: иначе обводки складываются
	if LvsNightVision then return end

	-- список сущностей кешируем: ents.GetAll каждый кадр — дорого
	if not LvsVisionCache or CurTime() > (LvsVisionCacheAt or 0) then
		LvsVisionCache = ents.GetAll()
		LvsVisionCacheAt = CurTime() + 0.25
	end

	for _, e in ipairs(LvsVisionCache) do
		if e ~= drone and IsValid(e) and not e:IsDormant() then
			-- свой игрок обводится всегда, независимо от дистанции до дрона
			local inRange = e == ply or e:GetPos():DistToSqr(origin) <= maxSqr

			if (e:IsPlayer() or e:IsNPC() or e:IsNextBot()) and inRange then
				local cls = e:GetClass()
				local owner = e.GetNWEntity and e:GetNWEntity("LvsOwner")

				if (e.IS_DRONE or cls == "lvs_scout_drr") and IsValid(owner) and owner == ply then
					own[#own + 1] = e
				elseif e:IsPlayer() and LvsFriendSet and LvsFriendSet["@" .. e:SteamID()] then
					players[#players + 1] = e
				elseif LvsIsFriendClass and LvsIsFriendClass(cls) then
					friends[#friends + 1] = e
				elseif IsEnemyEntityName and IsEnemyEntityName(cls) then
					enemies[#enemies + 1] = e
				else
					neutrals[#neutrals + 1] = e
				end
			end
		end
	end

	local function add(list, col)
		if #list > 0 then halo.Add(list, col, 1, 1, 1, true, true) end
	end

	add(own, Color(190, 120, 255, 255))
	add(players, Color(170, 255, 90, 255))
	add(friends, Color(120, 255, 150, 255))
	add(enemies, Color(255, 70, 70, 255))
	add(neutrals, Color(255, 220, 90, 255))
end)
-- Дублирующий триггер: сама клавиша F, независимо от бинда
local fWasDown = false

hook.Add("Think", "lvs_scout_vision_key", function()
	if not pilotDrone() then
		fWasDown = false
		return
	end

	local down = input.IsKeyDown(KEY_F)

	if down and not fWasDown then toggleVision() end

	fWasDown = down
end)
