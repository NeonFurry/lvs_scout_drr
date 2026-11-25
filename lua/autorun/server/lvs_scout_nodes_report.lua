-- Диагностика навигации дрона: что реально есть на карте.
-- Запуск: lvs_scout_nodes_report

concommand.Add("lvs_scout_nodes_report", function()
	local air = ents.FindByClass("info_node_air*") or {}
	local land = ents.FindByClass("info_node") or {}
	local hint = ents.FindByClass("info_node_hint*") or {}
	local areas = navmesh and navmesh.GetAllNavAreas and navmesh.GetAllNavAreas() or {}

	local mode = GetConVar("lvs_scout_nav_mode") and GetConVar("lvs_scout_nav_mode"):GetInt() or -1
	local map = game.GetMap()

	print(string.format("[LVS] map=%s nav_mode=%d", map, mode))
	print(string.format("[LVS] info_node_air=%d info_node=%d info_node_hint=%d navareas=%d",
		#air, #land, #hint, #areas))

	-- первые воздушные ноды: видно, на какой высоте они висят
	for i = 1, math.min(#air, 5) do
		local p = air[i]:GetPos()

		print(string.format("[LVS] air[%d] %.0f %.0f %.0f", i, p.x, p.y, p.z))
	end
end)
