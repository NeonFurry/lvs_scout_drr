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
