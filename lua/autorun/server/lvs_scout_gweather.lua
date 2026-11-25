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
