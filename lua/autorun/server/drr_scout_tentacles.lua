-- Щупальца DRR Scout.
-- База: оригинальные клипы Crysis (fly_idle / fly_slow), декодированные из SMD.
-- Сверху добавляется только наклон от разворота: он не выдуман, а взят из
-- фактического изменения угла, поэтому щупальца отстают при повороте.

local SEG_LIMIT   = 16          -- предел на кость, градусы (был 12 — кости в него упирались)
local UPDATE_RATE = 30          -- Герц; клипы сняты с частотой 30 кадров/с
local BLEND_RATE  = 2.5         -- скорость перехода fly_idle -> fly_slow
local TURN_GAIN   = 0.010       -- градусов наклона на градус поворота
local TURN_MAX    = 6           -- предел наклона от разворота
local EPSILON     = 0.05        -- ниже этого кость не пишем (репликация дорогая)
local AMP         = 1.0         -- клип добавляет микро-нерегулярность
local WAVE_P      = 2.5         -- изгиб вдоль плоскости щупальца
local WAVE_Y      = 2.0         -- боковое покачивание
local FLINCH_MAX  = 7           -- кивок от попадания, градусы на кончике
local LOD_DIST    = 3000        -- ближе этого к любому игроку — полная частота
local LOD_RATE    = 10          -- Гц для дальних дронов

local VERSION = "clean-11 (2.5/2.0)"

-- карта: id кости -> { колонка в таблице клипа, радиальное направление в локальных осях }
local function buildMap(ent)
	local map = {}

	for idx, name in ipairs(DRR_TENT_BONES) do
		local id = ent:LookupBone(name)

		if id then
			-- доля по длине щупальца: из имени ropeN_segMM; клешни — ближе к концу
			local seg = tonumber(name:match("_seg(%d+)")) or 13

			map[id] = { col = (idx - 1) * 3 + 1, k = seg / 13 }
		end
	end

	-- радиальное направление каждого щупальца берём по его первой кости:
	-- знак наклона в развороте зависит от того, куда смотрит плоскость
	for _, segs in pairs(ent.DrrRopeBones or {}) do
		local first = segs and segs[1]

		if first and first.id and map[first.id] then
			local m = ent:GetBoneMatrix(first.id)

			if m then
				local local_ = ent:WorldToLocal(m:GetTranslation())
				local_.z = 0

				if local_:LengthSqr() > 1 then
					local dir = local_:GetNormalized()

					for _, b in ipairs(segs) do
						if map[b.id] then map[b.id].radial = dir end
					end
				end
			end
		end
	end

	return map
end

local function sample(clip, col, t)
	local n = clip.n
	local tt = t * clip.fps
	local base = math.floor(tt)
	local frac = tt - base
	local A = clip.frames[(base % n) + 1]
	local B = clip.frames[((base + 1) % n) + 1]

	return A[col] + (B[col] - A[col]) * frac,
		A[col + 1] + (B[col + 1] - A[col + 1]) * frac,
		A[col + 2] + (B[col + 2] - A[col + 2]) * frac
end

local function clamp(v)
	return math.Clamp(v, -SEG_LIMIT, SEG_LIMIT)
end

local function solve(ent)
	local t = CurTime()

	if t < (ent.DrrTentNext or 0) then return end

	-- LOD: рядом с игроками полная частота, далеко — 10 Гц.
	-- Коррекция наклона считается от UPDATE_RATE, поэтому вдали она чуть
	-- плавнее по времени; на глаз это незаметно, зато экономит репликацию.
	if t >= (ent.DrrTentLodAt or 0) then
		ent.DrrTentLodAt = t + 1

		local pos = ent:GetPos()
		local near = false

		for _, ply in ipairs(player.GetAll()) do
			if ply:GetPos():DistToSqr(pos) < LOD_DIST * LOD_DIST then
				near = true
				break
			end
		end

		ent.DrrTentLod = near and UPDATE_RATE or LOD_RATE
	end

	ent.DrrTentNext = t + 1 / (ent.DrrTentLod or UPDATE_RATE)

	-- первый вызов: показываем состояние до любых проверок
	if not ent.DrrTentReport then
		ent.DrrTentReport = true

		print(string.format("[DRR tent] вызов солвера: класс %s, костей модели %d, rope-таблица %s, ключи %s",
			ent:GetClass(), ent:GetBoneCount(),
			tostring(ent.DrrRopeBones ~= nil), tostring(DRR_TENT_IDLE ~= nil)))
	end

	if not DRR_TENT_BONES or not DRR_TENT_IDLE then return end
	-- DrrRopeBones больше не требование: карта строится по именам из клипа,
	-- поэтому анимация не зависит от того, успел ли ResolveBones класса

	if not ent.DrrTentMap then
		ent.DrrTentMap = buildMap(ent)

		-- если карта пуста — имена в таблице не совпали с моделью.
		-- Печатаем реальные имена костей, чтобы это было видно сразу.
		local count = 0

		for _ in pairs(ent.DrrTentMap) do count = count + 1 end

		if count == 0 then
			local sample = {}

			for i = 0, ent:GetBoneCount() - 1 do
				local name = ent:GetBoneName(i)

				if name and #sample < 6 and name:lower():find("rope") then
					sample[#sample + 1] = name
				end
			end

			print("[DRR tent] карта пуста. Кости модели: " .. table.concat(sample, ", "))
		end
		ent.DrrTentCur = {}
		ent.DrrTentLean = 0
		ent.DrrTentSlow = 0
		ent.DrrTentAng = ent:GetAngles()

		local drv = ent:GetDriver()
		ent.DrrTentView = IsValid(drv) and drv:EyeAngles() or ent.DrrTentAng
	end

	-- 1. Наклон от разворота. Берём изменение угла с прошлого обновления;
	--    у DRR дрон крутится корпусом, а прицел может стоять — сравниваем оба.
	local ang = ent:GetAngles()
	local drv = ent:GetDriver()
	local view = IsValid(drv) and drv:EyeAngles() or ang

	local dBody = math.AngleDifference(ang.y, ent.DrrTentAng.y)
	local dView = math.AngleDifference(view.y, ent.DrrTentView.y)
	local dYaw = math.abs(dView) > math.abs(dBody) and dView or dBody

	ent.DrrTentAng = ang
	ent.DrrTentView = view

	local decay = math.pow(0.02, 1 / UPDATE_RATE)

	ent.DrrTentLean = math.Clamp((ent.DrrTentLean + dYaw * TURN_GAIN) * decay, -TURN_MAX, TURN_MAX)

	-- отдача от попадания: резкий кивок, гаснет за полсекунды
	local flinch = 0

	if ent.DrrFlinchAt then
		local age = CurTime() - ent.DrrFlinchAt

		if age < 0.5 then
			flinch = (1 - age / 0.5) ^ 2 * (ent.DrrFlinchSide or 1)
		else
			ent.DrrFlinchAt = nil
		end
	end

	-- 2. Переход в клип полёта по скорости: на месте fly_idle, в движении fly_slow
	local speed = ent:GetVelocity():Length()
	local wantSlow = math.Clamp((speed - 60) / 340, 0, 1)

	ent.DrrTentSlow = Lerp(math.min(BLEND_RATE / UPDATE_RATE, 1), ent.DrrTentSlow, wantSlow)

	-- одноразовый отчёт о первом тике: видно, дошло ли до записи костей
	if not ent.DrrTentReport then
		ent.DrrTentReport = true

		local cnt, firstId, firstCol = 0, nil, nil

		for id, info in pairs(ent.DrrTentMap) do
			cnt = cnt + 1
			firstId, firstCol = id, info.col
		end

		local ax, ay, az = 0, 0, 0

		if firstCol then ax, ay, az = sample(DRR_TENT_IDLE, firstCol, t) end

		print(string.format("[DRR tent] тик: костей %d, первая id=%s, кадр %.2f %.2f %.2f",
			cnt, tostring(firstId), ax, ay, az))
	end

	local slowIdx = ent.DrrTentSlow
	local lean = ent.DrrTentLean
	local right = ent:GetRight()
	local fwd, up = ent:GetForward(), ent:GetUp()

	-- 3. Кадры клипа + наклон
	for id, info in pairs(ent.DrrTentMap) do
		local ax, ay, az = sample(DRR_TENT_IDLE, info.col, t)

		if slowIdx > 0.01 and DRR_TENT_SLOW then
			local bx, by, bz = sample(DRR_TENT_SLOW, info.col, t)

			ax = Lerp(slowIdx, ax, bx)
			ay = Lerp(slowIdx, ay, by)
			az = Lerp(slowIdx, az, bz)
		end

		if info.radial and lean ~= 0 then
			local dir = fwd * info.radial.x + ent:GetRight() * info.radial.y + up * info.radial.z

			az = az - lean * dir:Dot(right)
		end

		-- кивок от попадания: сильнее к концу щупальца
		if flinch ~= 0 then
			az = az + flinch * FLINCH_MAX * (0.3 + (info.k or 0.5))
		end

		-- видимая волна поверх клипа: клип даёт только микро-жизнь,
		-- поэтому основной рисунок формируется здесь
		local phase = t * 1.6 - (info.k or 0.5) * 5.0

		ax = ax * AMP + (DRR_TENT_WP or WAVE_P) * math.sin(phase)
		ay = ay * AMP
		az = az * AMP + (DRR_TENT_WY or WAVE_Y) * math.cos(phase * 0.87)

		local target = Angle(clamp(ax), clamp(ay), clamp(az))

		-- ручная проверка: жёсткий угол на все кости, чтобы увидеть скиннинг
		if ent.DrrTentRaw and CurTime() < (ent.DrrTentRawUntil or 0) then
			target = ent.DrrTentRaw
		end
		local last = ent.DrrTentCur[id]

		if not last or math.abs(target.p - last.p) > EPSILON
			or math.abs(target.y - last.y) > EPSILON
			or math.abs(target.r - last.r) > EPSILON then
			ent.DrrTentCur[id] = target
			ent:ManipulateBoneAngles(id, target)
		end
	end
end

-- Ошибки не должны молча убивать анимацию: печатаем не чаще раза в 5 секунд.
function DrrTentacleUpdate(ent)
	local ok, err = pcall(solve, ent)

	if not ok and CurTime() > (ent.DrrTentErrT or 0) then
		ent.DrrTentErrT = CurTime() + 5
		print("[DRR tent] ошибка: " .. tostring(err))
	end
end

-- Подмена и в таблице класса, и на живых дронах: правки применяются
-- обновлением Lua, без перезахода на карту.
local stored = scripted_ents.GetStored and scripted_ents.GetStored("drr_scout_drr")

if stored and stored.t then
	stored.t.UpdateTentacles = DrrTentacleUpdate
end

local function install()
	for _, e in ipairs(ents.FindByClass("drr_scout_drr")) do
		e.UpdateTentacles = DrrTentacleUpdate
	end
end

install()

local nextInstall = 0

hook.Add("Think", "drr_scout_tentacle_install", function()
	if nextInstall > CurTime() then return end

	nextInstall = CurTime() + 1
	install()
end)

concommand.Add("drr_tent_debug", function(ply)
	if not IsValid(ply) then return end

	local e = ply:GetNWEntity("DronesRewriteDrone")

	-- если не пилотируешь — берём ближайшего дрона рядом
	if not IsValid(e) then
		local best, bestD = nil, 800 ^ 2

		for _, d in ipairs(ents.FindByClass("drr_scout_drr")) do
			local dist = d:GetPos():DistToSqr(ply:GetPos())

			if dist < bestD then best, bestD = d, dist end
		end

		e = best
	end

	if not IsValid(e) then print("[DRR tent " .. VERSION .. "] дронов рядом нет (ближе 800)"); return end

	local n = 0

	for _ in pairs(e.DrrTentMap or {}) do n = n + 1 end

	local moved = 0
	local peak = 0
	local tipId, tipAng = nil, 0

	for id in pairs(e.DrrTentMap or {}) do
		local a = e:GetManipulateBoneAngles(id)

		if a then
			local m = math.max(math.abs(a.p), math.abs(a.y), math.abs(a.r))

			if m > 0.3 then moved = moved + 1 end
			if m > peak then peak = m end
			if a.y and math.abs(a.y) > math.abs(tipAng) then tipAng, tipId = a.y, id end
		end
	end

	print(string.format("[DRR tent %s] костей в карте: %d | отклонено >0.3°: %d | макс %.2f° | кость %s y=%.2f",
		VERSION, n, moved, peak, tostring(tipId), tipAng))
	print(string.format("  lean %.2f | slow %.2f", e.DrrTentLean or 0, e.DrrTentSlow or 0))
end)

print("[DRR tent] loaded " .. VERSION .. " (" .. (SERVER and "SERVER" or "CLIENT") .. ")")

-- Собственный тик: анимация не зависит от того, вызывает ли класс
-- UpdateTentacles у этого экземпляра (в памяти карты мог остаться старый код).
local tickNext = 0

hook.Add("Think", "drr_scout_tent_tick", function()
	local now = CurTime()

	if tickNext > now then return end

	tickNext = now + 1 / 30

	for _, e in ipairs(ents.FindByClass("drr_scout_drr")) do
		DrrTentacleUpdate(e)
	end
end)

local function nearestDrone(ply)
	local e = ply:GetNWEntity("DronesRewriteDrone")

	if IsValid(e) then return e end

	local best, bestD = nil, 800 ^ 2

	for _, d in ipairs(ents.FindByClass("drr_scout_drr")) do
		local dist = d:GetPos():DistToSqr(ply:GetPos())

		if dist < bestD then best, bestD = d, dist end
	end

	return best
end

concommand.Add("drr_tent_test", function(ply, cmd, args)
	if not IsValid(ply) then return end

	local e = nearestDrone(ply)

	if not IsValid(e) then print("[DRR tent test] дронов рядом нет"); return end

	local deg = tonumber(args[1]) or 16
	local mode = string.lower(args[2] or "x")

	if mode == "y" then e.DrrTentRaw = Angle(0, deg, 0)
	elseif mode == "z" then e.DrrTentRaw = Angle(0, 0, deg)
	else e.DrrTentRaw = Angle(deg, 0, 0) end

	e.DrrTentRawUntil = CurTime() + 6

	print(string.format("[DRR tent test] %d° по оси %s на 6 с", deg, mode))
end)

concommand.Add("drr_tent_wave", function(ply, cmd, args)
	local p = tonumber(args[1])
	local y = tonumber(args[2])

	if p then DRR_TENT_WP = p end
	if y then DRR_TENT_WY = y end

	print(string.format("[DRR tent] волна: P %.1f | Y %.1f", DRR_TENT_WP or WAVE_P, DRR_TENT_WY or WAVE_Y))
end)
