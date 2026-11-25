-- Модуль собран из отдельных файлов: правки вносить сюда.

-- ===== Дамп целей ИИ (lvs_scout_ai_report.lua) =====
-- Диагностика ИИ: почему дрон не стреляет по цели.
-- Выводит состояние каждого дрона в консоль. Запуск: lvs_scout_ai_report

concommand.Add("lvs_scout_ai_report", function()
	local list = ents.FindByClass("lvs_scout_drr")

	if #list == 0 then
		print("[LVS] дронов нет")
		return
	end

	for _, d in ipairs(list) do
		if IsValid(d) then
			local tgt = d.LvsAiTarget
			local info = {
				"ent=" .. d:EntIndex(),
				"auto=" .. tostring(d.LvsAutonomous),
				"pause=" .. tostring(d.LvsScriptPause and d:LvsScriptPause()),
				"tgt=" .. (IsValid(tgt) and tgt:GetClass() or "nil"),
			}

			if IsValid(tgt) then
				info[#info + 1] = "dist=" .. math.floor(d:GetPos():Distance(tgt:GetPos()))
				info[#info + 1] = "see=" .. tostring(d.LvsAiSee)
				info[#info + 1] = "novis=" .. tostring(d.LvsNoVis)
				info[#info + 1] = "full=" .. tostring(d.LvsFullVisible and d:LvsFullVisible(tgt))
				info[#info + 1] = "mode=" .. tostring(d.LvsAttackMode)
				info[#info + 1] = "engage=" .. string.format("%.1f", (d.LvsEngageAt or 0) - CurTime())
			end

			local gun = d.Weapons and d.Weapons[1]

			if gun then
				info[#info + 1] = "firing=" .. tostring(gun.Firing)
				info[#info + 1] = "next=" .. string.format("%.2f", (gun.NextBullet or 0) - CurTime())
			end

			info[#info + 1] = "stun=" .. string.format("%.1f", (d.LvsStunnedUntil or 0) - CurTime())
			info[#info + 1] = "hp=" .. math.floor(d:Health() or 0)

			print("[LVS] " .. table.concat(info, " "))
		end
	end
end)

-- ===== Сверка костей модели (lvs_scout_bones_report.lua) =====
-- Диагностика костей дрона: сколько сегментов щупалец реально найдено.
-- Запуск: lvs_scout_bones_report

concommand.Add("lvs_scout_bones_report", function()
	local list = ents.FindByClass("lvs_scout_drr")

	if #list == 0 then
		print("[LVS] дронов нет")
		return
	end

	for _, d in ipairs(list) do
		if IsValid(d) then
			print(string.format("[LVS] дрон %d: костей в модели %d", d:EntIndex(), d:GetBoneCount()))

			for rope, segs in pairs(d.LvsRopeBones or {}) do
				print(string.format("  rope%d: %d сегментов", rope, #segs))
			end

			for claw, parts in pairs(d.LvsClawBones or {}) do
				print(string.format("  claw%d: %d костей", claw, #parts))
			end

			print(string.format("  хитбоксов: %d", #(d.LvsHitboxes or {})))
		end
	end
end)


-- Тест костей щупалец: жёстко выставить угол на все сегменты.
-- Если щупальца не шевельнулись — кости модели не управляются этим путём.
concommand.Add("lvs_scout_tent_test", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end

	local list = ents.FindByClass("lvs_scout_drr")

	for _, d in ipairs(list) do
		if IsValid(d) then
			d.LvsTentTest = not d.LvsTentTest
			print(string.format("[LVS] tent test на дроне %d: %s", d:EntIndex(), tostring(d.LvsTentTest)))
		end
	end
end)

-- ===== Состояние навигации (lvs_scout_nodes_report.lua) =====
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
