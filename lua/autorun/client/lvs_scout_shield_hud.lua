-- Таймер восстановления щита дрона после джаммера (для атаковавшего игрока)
surface.CreateFont("LvsShieldTimer", {
	font = "Trebuchet MS",
	size = 24,
	weight = 700,
})

net.Receive("lvs_scout_shield_down", function()
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
