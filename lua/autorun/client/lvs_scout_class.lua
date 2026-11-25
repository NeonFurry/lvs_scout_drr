-- Позднее переопределение методов класса: при регистрации GMod копирует
-- поля базового класса поверх наших, поэтому методы из cl_init затирались
-- базовыми DRR (оверлей и HUD оставались чужими).
-- Ставим их прямо в зарегистрированную таблицу класса.

hook.Remove("Think", "lvs_scout_class_override")

local function entTable()
	local stored = scripted_ents.GetStored("lvs_scout_drr")

	if stored and stored.t then return stored.t end

	return scripted_ents.Get("lvs_scout_drr")
end

hook.Add("Think", "lvs_scout_class_override", function()
	local ENT = entTable()

	if not ENT then return end

	-- регистрация могла затереть поле базовым «Default»
	ENT.OverlayName = "LVS Ceph"

	-- «Use Default Overlay»: галка — наш LVS Ceph, снята — выбранный в списке.
	-- Оптика живёт только на нашем оверлее и сама гаснет при выборе другого.
	ENT.GetOverlayName = function(self)
		local cvs = DRONES_REWRITE and DRONES_REWRITE.ClientCVars

		if cvs and cvs.OverlayDef and not cvs.OverlayDef:GetBool() then
			local picked = cvs.CustomOverlay and cvs.CustomOverlay:GetString()

			if picked and picked ~= "" then return picked end
		end

		return self.OverlayName or "LVS Ceph"
	end

	-- Пресет HUD DRR для нашего дрона не рисует: HUD зовётся напрямую.
	ENT.GetHUDName = function()
		return "LVS Internal"
	end

	hook.Remove("Think", "lvs_scout_class_override")
end)
