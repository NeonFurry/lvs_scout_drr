-- Игроки, пилотирующие дрон DRR, для всех невидимы (без моделей-заглушек),
-- и HUD-пресеты DRR не помечают их как цели.

local hidden = {}

local function piloting(ply)
	return IsValid(ply:GetNWEntity("DronesRewriteDrone"))
end

hook.Add("Think", "lvs_scout_pilot_hide", function()
	if CurTime() < (LvsPilotHideNext or 0) then return end
	LvsPilotHideNext = CurTime() + 0.1

	for _, ply in ipairs(player.GetAll()) do
		if piloting(ply) then
			hidden[ply] = true
			if not ply:GetNoDraw() then ply:SetNoDraw(true) end
		elseif hidden[ply] then
			hidden[ply] = nil
			ply:SetNoDraw(false)
		end
	end
end)

-- На время отрисовки HUD прячем пилотов из проверок IsPlayer,
-- чтобы DRR не рисовал на них маркеры целей.
local function withoutPilots(fn, drone)
	local patched = {}

	for _, ply in ipairs(player.GetAll()) do
		if piloting(ply) then
			patched[#patched + 1] = ply
			ply.IsPlayer = function() return false end
		end
	end

	local ok, err = pcall(fn, drone)

	for _, ply in ipairs(patched) do
		if IsValid(ply) then ply.IsPlayer = nil end
	end

	if not ok then ErrorNoHalt("[LVS Scout] HUD: " .. tostring(err) .. "\n") end
end

local wrapped = {}

local function wrapHud()
	if not (DRONES_REWRITE and DRONES_REWRITE.HUD) then return end
	if not next(DRONES_REWRITE.HUD) then return end

	for name, fn in pairs(DRONES_REWRITE.HUD) do
		if not wrapped[name] then
			wrapped[name] = true
			DRONES_REWRITE.HUD[name] = function(drone) withoutPilots(fn, drone) end
		end
	end

	-- таблица уже не пустая и всё обёрнуто — хук больше не нужен
	hook.Remove("Think", "lvs_scout_hud_wrap")
end

hook.Add("Think", "lvs_scout_hud_wrap", wrapHud)
