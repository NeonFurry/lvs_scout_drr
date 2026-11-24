-- Автономный режим: ИИ перехватывает обзор, чтобы можно было спокойно наблюдать.
-- Камера DRR считается клиентом от EyeAngles пилота, поэтому наводим её здесь.

local AUTO_CAM_HOOK = "lvs_scout_auto_cam"
local LERP = 0.2

local function lerpView(f, cur, want)
	return Angle(
		Lerp(f, cur.p, want.p),
		cur.y + math.AngleDifference(want.y, cur.y) * f,
		0
	)
end

hook.Remove("CreateMove", AUTO_CAM_HOOK)

hook.Add("CreateMove", AUTO_CAM_HOOK, function(cmd)
	local ply = LocalPlayer()
	local drone = IsValid(ply) and ply:GetNWEntity("DronesRewriteDrone")

	if not IsValid(drone) or drone:GetClass() ~= "lvs_scout_drr" then return end
	if not drone:GetNWBool("LvsAuto") then return end

	local dir = drone:GetNWVector("LvsAutoDir", vector_origin)
	if dir:IsZero() then return end

	local want = drone:WorldToLocalAngles(dir:Angle())
	cmd:SetViewAngles(lerpView(LERP, cmd:GetViewAngles(), want))
end)
