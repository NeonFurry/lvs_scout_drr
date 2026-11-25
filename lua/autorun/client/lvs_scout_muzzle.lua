-- Вспышка у пасти дрона при стрельбе из ледяного пулемёта.
-- Холодный «плазменный» плевок: ядро, гало и короткие искры.
local GLOW_MAT = Material("particle/particle_glow_04_additive")
local flashes = {}

net.Receive("lvs_scout_muzzle", function()
	local f = {
		pos = net.ReadVector(),
		untilT = CurTime() + 0.09,
		sparks = {},
	}

	-- искры фиксируем на старте, а не каждый кадр: иначе мигает «шумом»
	for i = 1, 6 do
		f.sparks[i] = {
			off = Vector(math.Rand(-14, 14), math.Rand(-14, 14), math.Rand(-10, 10)),
			size = math.Rand(6, 14),
		}
	end

	flashes[#flashes + 1] = f
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
			local f01 = math.Clamp((now - (f.untilT - 0.09)) / 0.09, 0, 1)
			local fade = 1 - f01
			local pulse = 0.85 + 0.3 * math.sin(CurTime() * 90 + i)

			render.DrawSprite(f.pos, 74 * fade * pulse + 12, 74 * fade * pulse + 12,
				Color(70, 170, 255, 150 * fade))
			render.DrawSprite(f.pos, 40 * fade + 8, 40 * fade + 8,
				Color(150, 225, 255, 210 * fade))
			render.DrawSprite(f.pos, 18 * fade + 6, 18 * fade + 6,
				Color(250, 255, 255, 255 * fade))

			for _, s in ipairs(f.sparks) do
				render.DrawSprite(f.pos + s.off * (1 + f01 * 1.8), s.size * fade, s.size * fade,
					Color(120, 200, 255, 180 * fade))
			end
		end
	end
end)
