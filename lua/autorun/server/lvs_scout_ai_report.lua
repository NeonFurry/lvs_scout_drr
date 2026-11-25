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
