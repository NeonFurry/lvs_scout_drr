-- ЭМИ в стиле Ceph: шестигранная оболочка, ломаные разряды, гекс-кольца
-- и шестигранная сетка на экране у ослеплённого.

local pulses = {}
local flash = 0

-- Палитра Ceph из Crysis 1: холодный циан, бирюзовая глубина, фиолетовый
-- акцент. Белого нет — свечение у Ceph всегда с сине-зелёным уходом.
local CEPH = {
	core   = { 140, 230, 255 },
	bright = { 90, 200, 248 },
	main   = { 58, 160, 222 },
	deep   = { 30, 105, 172 },
	violet = { 130, 138, 250 },
}

local function ceph(col, a)
	return Color(col[1], col[2], col[3], a)
end

local glow

local function glowMat()
	if not glow then glow = Material("sprites/light_glow02_add") end
	return glow
end

-- Предрасчёт решётки сферы: строки по широте, у каждого гекса свой касательный
-- базис, чтобы панели стояли по поверхности, а не плоским диском.
local SHELL = {}

do
	local ROWS = 7

	for i = 1, ROWS do
		local theta = math.rad(16 + (i - 0.5) * (148 / ROWS))
		local cols = math.max(5, math.floor(11 * math.sin(theta)))

		for c = 1, cols do
			local phi = (c / cols) * math.pi * 2
			local n = Vector(math.sin(theta) * math.cos(phi), math.sin(theta) * math.sin(phi), math.cos(theta))
			local up = math.abs(n.z) > 0.9 and Vector(1, 0, 0) or Vector(0, 0, 1)
			local u = n:Cross(up):GetNormal()
			local v = n:Cross(u):GetNormal()

			-- каждый пятый гекс фиолетовый: характерный акцент Ceph
			SHELL[#SHELL + 1] = { n = n, u = u, v = v, violet = (c % 5 == 0) }
		end
	end
end

net.Receive("lvs_scout_emp_fx", function()
	local pos = net.ReadVector()
	local radius = net.ReadFloat()
	local selfBlind = net.ReadBool()

	pulses[#pulses + 1] = { pos = pos, r = radius, t = CurTime() }

	if #pulses > 4 then table.remove(pulses, 1) end

	if selfBlind then flash = CurTime() + 1.5 end
end)

-- Гекс каркасом: surface.DrawPoly в 3D в GLua падает на пустой таблице
-- вершин и засыпал консоль ошибками (отсюда и тормоза).
local HEX_UNIT = {}

for k = 0, 5 do
	local a = k * math.pi / 3

	HEX_UNIT[k + 1] = { math.cos(a), math.sin(a) }
end

local function hex3D(pos, u, v, rad, col)
	local prev

	for k = 1, 7 do
		local c = HEX_UNIT[(k - 1) % 6 + 1]
		local p = pos + u * (c[1] * rad) + v * (c[2] * rad)

		if prev then render.DrawLine(prev, p, col, false) end

		prev = p
	end
end

-- Гексагон в плоскости XY (для земляных колец)
local function hexRing(center, rad, rot, col)
	local prev

	for k = 0, 6 do
		local a = k * math.pi / 3 + rot
		local v = center + Vector(math.cos(a) * rad, math.sin(a) * rad, 2)

		if prev then render.DrawLine(prev, v, col, false) end

		prev = v
	end
end

hook.Add("PostDrawTranslucentRenderables", "lvs_scout_emp_draw", function(skybox)
	if skybox then return end
	if #pulses == 0 then return end

	local now = CurTime()

	for i = #pulses, 1, -1 do
		local p = pulses[i]
		local age = now - p.t

		if age > 1.3 then
			table.remove(pulses, i)
			continue
		end

		local life = age / 1.3
		local grow = math.min(age / 0.55, 1)
		local fade = (1 - life) ^ 1.5
		local r = p.r * grow

		render.SetColorMaterial()

		-- панцирь: гексы ползут наружу, каждый мерцает в своей фазе
		for k = 1, #SHELL do
			local s = SHELL[k]
			local wob = 0.5 + 0.5 * math.sin(age * 30 + k * 0.9)
			local a = 210 * fade * (0.2 + 0.8 * wob)

			if a >= 3 then
				hex3D(p.pos + s.n * r, s.u, s.v, r * 0.155, ceph(s.violet and CEPH.violet or CEPH.main, a))
			end
		end

		-- разряды: ломаная из сегментов, дёргается каждый кадр
		for a = 1, 7 do
			local ang = (a / 7) * math.pi * 2 + age * 1.6
			local len = r * (0.45 + 0.35 * math.sin(a * 2.3))
			local prev = p.pos
			local seg = 6

			for s = 1, seg do
				local t = s / seg
				local dir = Vector(math.cos(ang), math.sin(ang), math.Rand(-0.55, 0.65)):GetNormal()
				local jit = r * 0.06
				local tip = p.pos + dir * (len * t)
					+ Vector(math.Rand(-jit, jit), math.Rand(-jit, jit), math.Rand(-jit, jit))

				render.DrawLine(prev, tip, ceph(CEPH.bright, 215 * fade), false)
				prev = tip
			end
		end

		-- земля: два гекс-кольца, внешнее вращается
		hexRing(p.pos, r * 1.02, 0, ceph(CEPH.bright, 200 * fade))
		hexRing(p.pos, r * 0.78, age * 0.7, ceph(CEPH.main, 130 * fade))

		-- ядро вспышки
		render.SetMaterial(glowMat())

		local core = r * 0.2 + 70

		render.DrawSprite(p.pos, core * 2, core * 2, ceph(CEPH.main, 230 * fade))
		render.DrawSprite(p.pos, core * 0.7, core * 0.7, ceph(CEPH.core, 255 * fade))
	end
end)

-- Ослепление: циановая вспышка и шестигранная сетка поверх экрана
hook.Add("HUDPaint", "lvs_scout_emp_flash", function()
	local left = flash - CurTime()

	if left <= 0 then return end

	local a = math.Clamp(left / 1.5, 0, 1) ^ 0.65
	local w, h = ScrW(), ScrH()

	surface.SetDrawColor(CEPH.deep[1], CEPH.deep[2], CEPH.deep[3], 150 * a)
	surface.DrawRect(0, 0, w, h)

	local step = math.max(90, w / 14)
	local rad = step * 0.42
	local px, py = {}, {}

	for k = 1, 6 do
		local ang = (k - 1) * math.pi / 3 + math.rad(30)

		px[k] = math.cos(ang) * rad
		py[k] = math.sin(ang) * rad
	end

	surface.SetDrawColor(CEPH.core[1], CEPH.core[2], CEPH.core[3], 90 * a)

	for y = -step, h + step, step * 1.5 do
		local shift = 0

		for x = -step, w + step, step do
			for k = 1, 6 do
				local n = k % 6 + 1

				surface.DrawLine(x + shift + px[k], y + py[k], x + shift + px[n], y + py[n])
			end

			shift = shift + step * 0.5
		end
	end
end)
