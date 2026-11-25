-- Таймер восстановления щита дрона после джаммера (для атаковавшего игрока)
surface.CreateFont("LvsShieldTimer", {
	font = "Trebuchet MS",
	size = 24,
	weight = 700,
})

net.Receive("lvs_scout_shield_down", function()
	-- звук снятия щита: слышно в дроне
	surface.PlaySound("drones/nio_dissolve.wav")

	local ply = LocalPlayer()
	ply.LvsShieldDrone = net.ReadEntity()
	ply.LvsShieldDownUntil = CurTime() + net.ReadFloat()
end)

-- Плашка в HUD пилота: щит дрона восстанавливается
surface.CreateFont("LvsShieldPlate", {
	font = "Trebuchet MS",
	size = 26,
	weight = 700,
})

hook.Add("HUDPaint", "lvs_scout_shield_plate", function()

	local ply = LocalPlayer()
	local drone = ply:GetNWEntity("DronesRewriteDrone")

	if not IsValid(drone) or drone:GetClass() ~= "lvs_scout_drr" then return end

	local at = drone:GetNWFloat("LvsShieldRestoreAt", 0)
	local left = at - CurTime()
	if left <= 0 then return end

	local text = string.format("Щит восстанавливается: %d с", math.ceil(left))
	local w, h = ScrW(), ScrH()

	surface.SetFont("LvsShieldPlate")
	local tw, th = surface.GetTextSize(text)

	local bw, bh = tw + 40, th + 20
	local x, y = w * 0.5 - bw * 0.5, h * 0.78

	draw.RoundedBox(8, x, y, bw, bh, Color(8, 20, 40, 190))
	draw.SimpleTextOutlined(
		text, "LvsShieldPlate",
		x + bw * 0.5, y + bh * 0.5,
		Color(235, 245, 255),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
		2, Color(8, 20, 40, 230)
	)
end)

hook.Add("HUDPaint", "lvs_scout_shield_hud", function()

	local ply = LocalPlayer()
	local untilT = ply.LvsShieldDownUntil
	if not untilT then return end

	local drone = ply.LvsShieldDrone
	local left = untilT - CurTime()

	-- щит уже восстановили, сняли модуль или дрон исчез
	if left <= 0 or not IsValid(drone) or drone:GetNWInt("shield_health", 0) > 0 then
		ply.LvsShieldDownUntil = nil
		ply.LvsShieldDrone = nil
		return
	end

	local text = string.format("Щит дрона спал — атакуйте в полную силу (%.1f c)", left)

	draw.SimpleTextOutlined(
		text, "LvsShieldTimer",
		ScrW() * 0.5, 80,
		Color(235, 245, 255),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
		2, Color(8, 20, 40, 230)
	)
end)


-- Плашка стрелку: щит дрона не пробить
surface.CreateFont("LvsShieldBlock", {
	font = "Bahnschrift SemiBold Condensed",
	size = 22,
	weight = 700,
	extended = true,
})

hook.Remove("HUDPaint", "lvs_scout_shield_block_msg")

net.Receive("lvs_scout_shield_block", function()
	LvsShieldBlockUntil = CurTime() + 1.4
end)

hook.Add("HUDPaint", "lvs_scout_shield_block_msg", function()

	local left = (LvsShieldBlockUntil or 0) - CurTime()

	if left <= 0 then return end

	local alpha = math.Clamp(left / 0.35, 0, 1)
	local text = "ДРОН ЗАЩИЩЁН ОТ ЛЮБОГО УРОНА"

	surface.SetFont("LvsShieldBlock")

	local tw, th = surface.GetTextSize(text)
	local w, h = ScrW(), ScrH()
	local bw, bh = tw + 46, th + 22
	local x, y = w * 0.5 - bw * 0.5, h * 0.42 - bh * 0.5

	surface.SetDrawColor(4, 16, 22, 200 * alpha)
	surface.DrawRect(x, y, bw, bh)

	surface.SetDrawColor(90, 220, 255, 220 * alpha)
	surface.DrawOutlinedRect(x, y, bw, bh)
	surface.DrawOutlinedRect(x + 1, y + 1, bw - 2, bh - 2)

	-- ромбы по углам, как у остальных панелей
	local d = 4

	for _, c in ipairs({ { x, y }, { x + bw, y }, { x, y + bh }, { x + bw, y + bh } }) do
		surface.SetDrawColor(90, 220, 255, 200 * alpha)
		surface.DrawLine(c[1] - d, c[2], c[1], c[2] - d)
		surface.DrawLine(c[1], c[2] - d, c[1] + d, c[2])
		surface.DrawLine(c[1] + d, c[2], c[1], c[2] + d)
		surface.DrawLine(c[1], c[2] + d, c[1] - d, c[2])
	end

	draw.SimpleTextOutlined(text, "LvsShieldBlock", w * 0.5, y + bh * 0.5,
		Color(200, 245, 255, 255 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
		1, Color(0, 0, 0, 180 * alpha))
end)
