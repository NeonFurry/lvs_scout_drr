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

	if net.ReadBool() then
		if nightState or nightEntity() then
			for _, e in ipairs(ents.FindByClass(NIGHT_CLASS)) do e:Remove() end
			setNight(false)
		elseif scripted_ents.GetStored(NIGHT_CLASS) then
			local e = ents.Create(NIGHT_CLASS)
			e:Spawn()
			e:Activate()
			setNight(true)
		else
			ply:ChatPrint("[LVS Scout] GWeather не установлен (" .. NIGHT_CLASS .. ")")
		end
	end

	reply(ply)
end)
