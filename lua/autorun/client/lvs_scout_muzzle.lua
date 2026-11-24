-- Вспышка у пасти дрона при стрельбе из ледяного пулемёта
local GLOW_MAT = Material("particle/particle_glow_04_additive")
local flashes = {}

net.Receive("lvs_scout_muzzle", function()
	flashes[#flashes + 1] = {
		pos = net.ReadVector(),
		untilT = CurTime() + 0.07,
	}
end)

hook.Add("PostDrawTranslucentRenderables", "lvs_scout_muzzle_flash", function(_, bDrawingSkybox)
	if bDrawingSkybox or #flashes == 0 then return end

	local now = CurTime()
	render.SetMaterial(GLOW_MAT)

	for i = #flashes, 1, -1 do
		local f = flashes[i]

		if now > f.untilT then
			table.remove(flashes, i)
		else
			render.DrawSprite(f.pos, 46, 46, Color(170, 225, 255, 220))
			render.DrawSprite(f.pos, 20, 20, Color(255, 255, 255, 255))
		end
	end
end)
