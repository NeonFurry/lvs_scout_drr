-- Экранный эффект «обморожения» у замороженного игрока
surface.CreateFont("LvsFrozenTimer", {
	font = "Trebuchet MS",
	size = 46,
	weight = 900,
})

surface.CreateFont("LvsFrozenBy", {
	font = "Trebuchet MS",
	size = 26,
	weight = 700,
})

local OUTLINE = Color(8, 20, 40, 230)
local ICE = Color(130, 195, 255)

-- Клиентский тинт моделей замороженных игроков (серверный SetColor иногда перебивается)
local tinted = {}

hook.Add("Think", "lvs_scout_frozen_tint", function()
	for _, ply in ipairs(player.GetAll()) do
		if ply:GetNWBool("LvsFrozen") then
			local c = ply:GetColor()

			if c.r ~= ICE.r or c.g ~= ICE.g or c.b ~= ICE.b then
				ply:SetColor(ICE)
				ply:SetRenderMode(RENDERMODE_TRANSCOLOR)
			end

			tinted[ply] = true
		elseif tinted[ply] then
			ply:SetColor(Color(255, 255, 255))
			ply:SetRenderMode(RENDERMODE_NORMAL)
			tinted[ply] = nil
		end
	end
end)

local function frozenPly()
	local ply = LocalPlayer()
	if IsValid(ply) and ply:GetNWBool("LvsFrozen") then return ply end
end

hook.Add("RenderScreenspaceEffects", "lvs_scout_frozen_cm", function()
	if not frozenPly() then return end

	DrawColorModify({
		["$pp_colour_addr"] = 0.02,
		["$pp_colour_addg"] = 0.07,
		["$pp_colour_addb"] = 0.15,
		["$pp_colour_colour"] = 0.5,
		["$pp_colour_contrast"] = 1.1,
		["$pp_colour_brightness"] = -0.04,
	})
end)

hook.Add("HUDPaint", "lvs_scout_frozen_overlay", function()
	local ply = frozenPly()
	if not ply then return end

	local w, h = ScrW(), ScrH()

	-- общий синий тон
	surface.SetDrawColor(120, 180, 255, 45)
	surface.DrawRect(0, 0, w, h)

	-- «иней» по краям
	local edge = math.min(w, h) * 0.14

	for i = 1, 4 do
		local e = edge * i * 0.25

		surface.SetDrawColor(150, 205, 255, 70 / i)
		surface.DrawRect(0, 0, w, e)
		surface.DrawRect(0, h - e, w, e)
		surface.DrawRect(0, 0, e, h)
		surface.DrawRect(w - e, 0, e, h)
	end

	local left = ply:GetNWFloat("LvsFrozenUntil", 0) - CurTime()
	if left <= 0 then return end

	local by = ply:GetNWString("LvsFrozenBy", "")
	local sub = by ~= "" and ("Лучом Scout игрока (" .. by .. ")") or "Лучом Scout"

	local main = string.format("Заморожен = %.1f", left)
	local cx, cy = w * 0.5, h * 0.70

	surface.SetFont("LvsFrozenTimer")
	local tw, th = surface.GetTextSize(main)
	surface.SetFont("LvsFrozenBy")
	local sw, sh = surface.GetTextSize(sub)

	-- подложка для читаемости на любом фоне
	local pad = 18
	local bw = math.max(tw, sw) + pad * 2
	local bh = th + sh + 10 + pad * 2
	draw.RoundedBox(8, cx - bw * 0.5, cy - th * 0.5 - pad, bw, bh, Color(6, 16, 32, 150))

	draw.SimpleTextOutlined(main, "LvsFrozenTimer", cx, cy, Color(240, 250, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 3, OUTLINE)
	draw.SimpleTextOutlined(sub, "LvsFrozenBy", cx, cy + th * 0.5 + 18, Color(200, 230, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, OUTLINE)
end)
