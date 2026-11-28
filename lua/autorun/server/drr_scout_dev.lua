-- Модуль собран из отдельных файлов: правки вносить сюда.

-- ===== Дамп целей ИИ (drr_scout_ai_report.lua) =====
-- Диагностика ИИ: почему дрон не стреляет по цели.
-- Выводит состояние каждого дрона в консоль. Запуск: drr_scout_ai_report

concommand.Add("drr_scout_ai_report", function()
	local list = ents.FindByClass("drr_scout_drr")

	if #list == 0 then
		print("[DRR] дронов нет")
		return
	end

	for _, d in ipairs(list) do
		if IsValid(d) then
			local tgt = d.DrrAiTarget
			local info = {
				"ent=" .. d:EntIndex(),
				"auto=" .. tostring(d.DrrAutonomous),
				"pause=" .. tostring(d.DrrScriptPause and d:DrrScriptPause()),
				"tgt=" .. (IsValid(tgt) and tgt:GetClass() or "nil"),
			}

			if IsValid(tgt) then
				info[#info + 1] = "dist=" .. math.floor(d:GetPos():Distance(tgt:GetPos()))
				info[#info + 1] = "see=" .. tostring(d.DrrAiSee)
				info[#info + 1] = "novis=" .. tostring(d.DrrNoVis)
				info[#info + 1] = "full=" .. tostring(d.DrrFullVisible and d:DrrFullVisible(tgt))
				info[#info + 1] = "mode=" .. tostring(d.DrrAttackMode)
				info[#info + 1] = "engage=" .. string.format("%.1f", (d.DrrEngageAt or 0) - CurTime())
			end

			local gun = d.Weapons and d.Weapons[1]

			if gun then
				info[#info + 1] = "firing=" .. tostring(gun.Firing)
				info[#info + 1] = "next=" .. string.format("%.2f", (gun.NextBullet or 0) - CurTime())
			end

			info[#info + 1] = "stun=" .. string.format("%.1f", (d.DrrStunnedUntil or 0) - CurTime())
			info[#info + 1] = "hp=" .. math.floor(d:Health() or 0)

			print("[DRR] " .. table.concat(info, " "))
		end
	end
end)

-- ===== Сверка костей модели (drr_scout_bones_report.lua) =====
-- Диагностика костей дрона: сколько сегментов щупалец реально найдено.
-- Запуск: drr_scout_bones_report

concommand.Add("drr_scout_bones_report", function()
	local list = ents.FindByClass("drr_scout_drr")

	if #list == 0 then
		print("[DRR] дронов нет")
		return
	end

	for _, d in ipairs(list) do
		if IsValid(d) then
			print(string.format("[DRR] дрон %d: костей в модели %d", d:EntIndex(), d:GetBoneCount()))

			for rope, segs in pairs(d.DrrRopeBones or {}) do
				print(string.format("  rope%d: %d сегментов", rope, #segs))
			end

			for claw, parts in pairs(d.DrrClawBones or {}) do
				print(string.format("  claw%d: %d костей", claw, #parts))
			end

			print(string.format("  хитбоксов: %d", #(d.DrrHitboxes or {})))
		end
	end
end)


-- Тест костей щупалец: жёстко выставить угол на все сегменты.
-- Если щупальца не шевельнулись — кости модели не управляются этим путём.
concommand.Add("drr_scout_tent_test", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end

	local list = ents.FindByClass("drr_scout_drr")

	for _, d in ipairs(list) do
		if IsValid(d) then
			d.DrrTentTest = not d.DrrTentTest
			print(string.format("[DRR] tent test на дроне %d: %s", d:EntIndex(), tostring(d.DrrTentTest)))
		end
	end
end)

-- ===== Состояние навигации (drr_scout_nodes_report.lua) =====
-- Диагностика навигации дрона: что реально есть на карте.
-- Запуск: drr_scout_nodes_report

concommand.Add("drr_scout_nodes_report", function()
	local air = ents.FindByClass("info_node_air*") or {}
	local land = ents.FindByClass("info_node") or {}
	local hint = ents.FindByClass("info_node_hint*") or {}
	local areas = navmesh and navmesh.GetAllNavAreas and navmesh.GetAllNavAreas() or {}

	local mode = GetConVar("drr_scout_nav_mode") and GetConVar("drr_scout_nav_mode"):GetInt() or -1
	local map = game.GetMap()

	print(string.format("[DRR] map=%s nav_mode=%d", map, mode))
	print(string.format("[DRR] info_node_air=%d info_node=%d info_node_hint=%d navareas=%d",
		#air, #land, #hint, #areas))

	-- первые воздушные ноды: видно, на какой высоте они висят
	for i = 1, math.min(#air, 5) do
		local p = air[i]:GetPos()

		print(string.format("[DRR] air[%d] %.0f %.0f %.0f", i, p.x, p.y, p.z))
	end
end)
