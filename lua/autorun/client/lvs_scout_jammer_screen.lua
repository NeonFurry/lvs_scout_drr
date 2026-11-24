-- Экран джаммера DRR: к режиму и полосе прогресса добавляем таймер перезарядки
local FONT = "DronesRewrite_font5"

local function drawScreen(self)
	if not self.LvsScreenDbg then
		self.LvsScreenDbg = true
		print("[LVS] экран джаммера: ViewModelDrawn вызван")
	end

	if not self:GetNWBool("IsScreenActive", false) then return end

	local owner = self.Owner or self:GetOwner()
	if not IsValid(owner) then return end

	local vm = owner:GetViewModel()
	if not IsValid(vm) then return end

	local m = vm:GetBoneMatrix(vm:LookupBone("jammer_weapon"))
	if not m then return end

	local pos, ang = m:GetTranslation(), m:GetAngles()
	if not pos or not ang then return end

	ang:RotateAroundAxis(ang:Up(), 180)

	pos = pos - ang:Right() * 3.165
	pos = pos - ang:Forward() * 4.18
	pos = pos + ang:Up() * 0.95

	local direct = self:GetNWBool("IsInDirectMode")
	local useDelay = (self.UseDelay or 2)
		* (direct and 1 or (self.AreaModeDelayMult or 1.5))

	local left = math.max((self:GetNextPrimaryFire() or 0) - CurTime(), 0)
	local frac = math.Clamp(1 - left / useDelay, 0, 1)

	cam.Start3D2D(pos, ang, 0.01)
		-- разметка как в штатном DRR
		draw.SimpleText("MODE", FONT, 10, 8, Color(0, 255, 0, 180))
		draw.SimpleText(direct and "DIRECT" or "AREA", FONT, 74, 8, Color(0, 255, 0, 230))

		draw.SimpleText("STATE", FONT, 10, 30, Color(0, 255, 0, 180))

		if left > 0.05 then
			draw.SimpleText(string.format("RELOAD %.1f", left), FONT, 74, 30,
				Color(255, 205, 70, 240))
		else
			draw.SimpleText("READY", FONT, 74, 30, Color(60, 255, 90, 240))
		end

		surface.SetDrawColor(Color(0, 255, 0, 60))
		surface.DrawRect(10, 62, 182, 8)

		surface.SetDrawColor(left > 0.05 and Color(255, 205, 70, 220) or Color(60, 255, 90, 220))
		surface.DrawRect(10, 62, 182 * frac, 8)

		surface.SetDrawColor(Color(0, 255, 0, 120))
		surface.DrawOutlinedRect(8, 4, 186, 70, 1)
	cam.End3D2D()
end
local patchedClass = false

local function patchClass()
	local swep = weapons.Get("weapon_drr_jammer")
	if not swep then return end

	swep.ViewModelDrawn = drawScreen

	if not patchedClass then
		patchedClass = true
		print("[LVS] экран джаммера: класс пропатчен")
	end
end

local function patch(ent)
	if IsValid(ent) and ent:GetClass() == "weapon_drr_jammer" then
		ent.ViewModelDrawn = drawScreen
	end
end

hook.Add("OnEntityCreated", "lvs_jammer_screen", function(ent)
	timer.Simple(0, function() patch(ent) end)
end)

hook.Add("PlayerSwitchWeapon", "lvs_jammer_screen_switch", function(ply, old, new)
	patch(new)
end)

hook.Add("InitPostEntity", "lvs_jammer_screen_init", function()
	patchClass()

	for _, ply in ipairs(player.GetAll()) do
		for _, w in ipairs(ply:GetWeapons()) do
			patch(w)
		end
	end
end)

timer.Simple(0, patchClass)
timer.Simple(3, patchClass)
-- Дублирующий индикатор под прицелом: виден всегда, даже если 3D-экран не отрисовался
hook.Add("HUDPaint", "lvs_jammer_cooldown", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() ~= "weapon_drr_jammer" then return end

	local left = (wep:GetNextPrimaryFire() or 0) - CurTime()
	local sw, sh = ScrW(), ScrH()

	local text, col

	if left > 0.05 then
		text = string.format("JAMMER: RELOAD %.1f", left)
		col = Color(255, 205, 70, 230)
	else
		text = "JAMMER: READY"
		col = Color(60, 255, 90, 230)
	end

	draw.SimpleText(text, "DermaDefaultBold", sw / 2, sh / 2 + 64, col,
		TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end)