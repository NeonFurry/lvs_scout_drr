-- База: Drones Rewrite (обязательно установлен)
ENT.Base = "dronesrewrite_base"
ENT.Type = "anim"
ENT.PrintName = "LVS Scout"
ENT.Author = "LVS"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.Category = "Drones Rewrite"

ENT.UNIT = "SCT"
ENT.HUD_hudName = "Crysis Ceph"

ENT.Weight = 120
ENT.SpawnHeight = 60
ENT.Model = "models/crysis/scout/scout.mdl"

-- Камеру-модель и корпус прячем от собственного пилота (вид от первого лица)
ENT.RenderCam = false
ENT.RenderInCam = false
ENT.UseFlashlight = false -- фонарик дрону не нужен (F занят подсветкой целей)

ENT.Speed = 2500
ENT.UpSpeed = 14000
ENT.RotateSpeed = 6

ENT.Alignment = 0
ENT.AlignmentRoll = 0.7
ENT.AlignmentPitch = 1.6
ENT.NoiseCoefficient = 0.15
ENT.AngOffset = 3
ENT.PitchOffset = 0.45

ENT.AllowYawRestrictions = true
ENT.YawMin = -60
ENT.YawMax = 60
ENT.PitchMin = -30
ENT.PitchMax = 50

ENT.HealthAmount = 120
ENT.DefaultHealth = 120

ENT.Sounds = {
	PropellerSound = {
		Name = "npc/manhack/mh_engine_loop1.wav",
		Pitch = 120,
		Level = 60
	},
	ExplosionSound = {
		Name = "ambient/explosions/explode_7.wav",
		Level = 80
	}
}

-- Пропеллеры нужны логике полёта DRR; визуально не рисуем (NoPropellers)
ENT.NoPropellers = true
ENT.Propellers = {
	Damage = 1,
	Health = 30,
	HitRange = 12,
	Model = "models/dronesrewrite/propellers/propeller2_3.mdl",
	Info = {
		Vector(0, 24, 0),
		Vector(0, -24, 0)
	}
}

-- Кости (имена из Bones.txt)
ENT.HeadBone = "Bip01_Head"
ENT.WeaponBone = "weapon_bone"
ENT.TentacleCount = 6

-- Криолуч (параметры оружия DRR)
ENT.CryoDamage = 10
ENT.CryoRange = 2048

-- Дистанция, с которой автономный ИИ держится от цели (юниты)
ENT.LvsAiStandoff = 1400

-- Дистанция против летающих/ближних врагов (маньяки, сканеры)
ENT.LvsAiFlyStandoff = 1900

-- Множитель урона пулемёта по грузу дропшипа
ENT.LvsAiHeavyDamageMul = 8


-- Максимальный подъём над целью по Z (юниты), реальный считается от PitchMin
ENT.LvsAiAltitudeOffset = 2000

-- Минимальная высота над землёй для автономного полёта
ENT.LvsMinAltitude = 800

-- Рабочая высота патруля над землёй (случайно в этом диапазоне)
ENT.LvsPatrolAltitudeMin = 700
ENT.LvsPatrolAltitudeMax = 1200

-- Серво-гул двигателя (петля из HL2, есть в базовой игре)
ENT.LvsServoSound = "npc/combine_gunship/gunship_engine_loop3.wav"
ENT.LvsServoVolume = 0.55

-- Адаптивный урон: сколько попаданий в «бронированную» цель нужно,
-- чтобы пробить защиту, и во сколько раз сильнее пробивающий удар
ENT.LvsAdaptLimit = 10
ENT.LvsAdaptMul = 3

-- Приоритет тяжёлой техники в выборе цели:
-- true  — тяжёлая техника выбирается в первую очередь (страйдер и т.п.)
-- false — обычный выбор (ближайшая видимая цель)
ENT.LvsHeavyHighPriority = true

-- Сколько секунд непрерывного луча нужно, чтобы заморозить цель
ENT.LvsFreezeTime = 3

-- Доля максимального HP в секунду при регенерации (0.01 = 1%/с)
ENT.LvsRegenRate = 0.01
ENT.CryoDelay = 0.08

-- Оружие через систему DRR. Класс "Cryo" регистрируется ниже.
ENT.Attachments = {
	["Cryo"] = { Pos = Vector(0, 0, 0) }
}

ENT.Weapons = {
	["Cryo"] = { Name = "Cryo", Attachment = "Cryo" }
}

-- Позиция аттачмента модели (с учётом анимации костей)
function ENT:LvsAttachmentPos(name)
	self.LvsAttCache = self.LvsAttCache or {}

	local id = self.LvsAttCache[name]
	if id == nil then
		id = self:LookupAttachment(name) or 0
		self.LvsAttCache[name] = id
	end

	if id <= 0 then return end

	local att = self:GetAttachment(id)
	return att and att.Pos
end

-- Точка обзора: вынесена вперёд за модель (лоб на уровне x≈84), чтобы
-- в кадр не попадала сама голова. Без GetBonePosition — камера стабильна.
local LVS_EYE_LOCAL = Vector(140, 0, 30)

function ENT:LvsEyePos()
	return self:LocalToWorld(LVS_EYE_LOCAL)
end
-- Камеру позиционируем сами (в Think), поэтому локальное смещение — нулевое
function ENT:GetLocalCamPos()
	return vector_origin
end
-- Трасса прицела/HUD: стартует из аттачмента light (область глаз) и
-- не цепляет собственные прокси-хитбоксы.
function ENT:GetCameraTraceLine(distance, mins, maxs, mask)
	local cam = self:GetCamera()

	local start = self:LvsEyePos()
	if not start then start = IsValid(cam) and cam:GetPos() or self:GetPos() end

	local dir = (self.CamAngles or self:GetAngles()):Forward()

	local filter = { self }

	if IsValid(cam) then filter[#filter + 1] = cam end

	for _, h in ipairs(self.LvsHitboxes or {}) do
		if IsValid(h.ent) then filter[#filter + 1] = h.ent end
	end

	return util.TraceHull({
		start  = start,
		endpos = start + dir * (distance or 100000),
		filter = filter,
		mins   = mins or vector_origin,
		maxs   = maxs or vector_origin,
		mask   = mask,
	})
end
-- Трасса оружия: от камеры по CamAngles, мимо своих прокси-хитбоксов
local function droneTrace(drone, mins, maxs, mask)
	local cam = drone:GetCamera()
	if not IsValid(cam) then cam = drone end

	local filter = { drone, cam }

	for _, h in ipairs(drone.LvsHitboxes or {}) do
		if IsValid(h.ent) then filter[#filter + 1] = h.ent end
	end

	local aimAng = drone.LvsAutoAngles or drone.CamAngles

	return util.TraceHull({
		start  = cam:GetPos(),
		endpos = cam:GetPos() + aimAng:Forward() * 100000,
		filter = filter,
		mins   = mins or vector_origin,
		maxs   = maxs or vector_origin,
		mask   = mask,
	})
end
if DRONES_REWRITE then
	ENT.KeysFuncs = DRONES_REWRITE.DefaultKeys()

	if DRONES_REWRITE.GetBaseModules then
		ENT.Modules = DRONES_REWRITE.GetBaseModules()
	end

	-- Оружие криолуча: стреляет по Fire1 (Attack/OnAttackStopped), луч — только во время выстрела.
	if DRONES_REWRITE.Weapons and DRONES_REWRITE.Weapons["Template"] then
		DRONES_REWRITE.Weapons["Cryo"] = {
			Initialize = function(self, pos, ang)
				local gun = DRONES_REWRITE.Weapons["Template"].InitializeNoDraw(self)

				gun.Firing = false
				gun.NextHit = 0
				gun.FireUntil = 0
				gun.FireDelay = self.CryoDelay or 0.08

				-- Ненулевой боезапас: иначе HUD делит на GetPrimaryMax() == 0
				gun.PrimaryAmmoMax = 100
				gun.PrimaryAmmo = 100
				gun.SecondaryAmmoMax = 100
				gun.SecondaryAmmo = 100

				self:SetNWInt("Ammo1", gun.PrimaryAmmo)
				self:SetNWInt("MaxAmmo1", gun.PrimaryAmmoMax)
				self:SetNWInt("Ammo2", gun.SecondaryAmmo)
				self:SetNWInt("MaxAmmo2", gun.SecondaryAmmoMax)

				return gun
			end,

			Attack = function(self, gun)
				local enemy = self.Buffer and self.Buffer.Enemy

				-- автономно без цели не стреляем вообще; сам дропшип — не цель
				if self.LvsAutonomous and (not IsValid(self.LvsAiTarget)
					or self.LvsAiTarget:GetClass() == "npc_combinedropship") then
					gun.Firing = false
					return
				end

				-- автономно: цели, которые бьём пулемётом (режим 1, лёд, летун, проп, груз, тяжёлая техника)
				if self.LvsAutonomous then
					local tgt = self.LvsAiTarget

					local useMG = self.LvsAttackMode == 1
						or (self.LvsIsFlyer and self:LvsIsFlyer(tgt))
						or (self.LvsIsPropTarget and self:LvsIsPropTarget(tgt))
						or (self.LvsIsCargo and self:LvsIsCargo(tgt))
						or (LVSScout and LVSScout.IsFrozen(tgt))

					if useMG then
						gun.Firing = false
						DRONES_REWRITE.Weapons["Cryo"].Attack2(self, gun)
						return
					end
				end

				-- ИИ без пилота: замороженного врага добиваем пулемётом
				if self.AI_installed and not IsValid(self:GetDriver())
					and IsValid(enemy) and LVSScout and LVSScout.IsFrozen(enemy) then
					gun.Firing = false
					DRONES_REWRITE.Weapons["Cryo"].Attack2(self, gun)
					return
				end

				gun.Firing = true
				gun.FireUntil = CurTime() + 0.6
			end,

			OnAttackStopped = function(self, gun)
				gun.Firing = false
			end,

			Think = function(self, gun)
				-- автономно без цели: возможности не применяем; дропшип — не цель
				if self.LvsAutonomous and (not IsValid(self.LvsAiTarget)
					or self.LvsAiTarget:GetClass() == "npc_combinedropship") then
					gun.Firing = false
					self:SetNWBool("LvsCryoActive", false)
					return
				end

				-- автономно: луч по живой цели, пулемёт — только по замороженной
				local lvsFrozen = self.LvsAutonomous and IsValid(self.LvsAiTarget)
					and LVSScout and LVSScout.IsFrozen(self.LvsAiTarget)

				local lvsFlyer = self.LvsAutonomous and self.LvsIsFlyer
					and self:LvsIsFlyer(self.LvsAiTarget)
				local lvsProp = self.LvsAutonomous and self.LvsIsPropTarget
					and self:LvsIsPropTarget(self.LvsAiTarget)

				local lvsCargo = self.LvsAutonomous and self.LvsIsCargo
					and self:LvsIsCargo(self.LvsAiTarget)

				local lvsMGOnly = self.LvsAutonomous and self.LvsAttackMode == 1
					and IsValid(self.LvsAiTarget)

				-- львы: только пулемёт, луч по ним не ведём
				local lvsAntlion = self.LvsAutonomous and self.LvsAntlion
					and self:LvsAntlion(self.LvsAiTarget)

				-- ИИ предпочитает пулемёт: вблизи он эффективнее луча
				local lvsClose = self.LvsAutonomous and IsValid(self.LvsAiTarget)
					and self:GetPos():Distance(self.LvsAiTarget:GetPos()) < 1800

				-- львов пулемётом бьём только если класса нет в списке друзей
				local lvsMgOk = not self.LvsMgAllowed or not IsValid(self.LvsAiTarget)
					or self:LvsMgAllowed(self.LvsAiTarget)

				-- пулемётные цели: стреляем каждый Think (Attack2 сам держит кулдаун),
				-- иначе один выстрел на скан (2/с) — урон почти не виден
				if (lvsFrozen or lvsFlyer or lvsProp or lvsCargo or lvsMGOnly or lvsAntlion or lvsClose) and lvsMgOk then
					gun.Firing = false
					self:SetNWBool("LvsCryoActive", false)
					DRONES_REWRITE.Weapons["Cryo"].Attack2(self, gun)
					return
				end

				if self.LvsAutonomous and self.LvsAttackMode ~= 1 and not lvsAntlion
					and IsValid(self.LvsAiTarget)
					and CurTime() >= (self.LvsEngageAt or 0)
					and self.LvsAutoAngles and self.LvsAimAligned then
					gun.Firing = true
					gun.FireUntil = CurTime() + 0.3
				elseif gun.Firing and CurTime() > gun.FireUntil then
					gun.Firing = false
				end

				local start = self:GetCryoStart()
				local tr = droneTrace(self, nil, nil, MASK_SHOT)

				-- автономно: луч бьёт ровно в точку прицеливания цели, а не по
				-- сглаженному прицелу — при стрейфе он уходил мимо
				local lockHit, lockPos

				if self.LvsAutonomous and IsValid(self.LvsAiTarget) then
					local tgt = self.LvsAiTarget
					local cam = self:GetCamera()
					local origin = IsValid(cam) and cam:GetPos() or self:GetPos()
					local center = (self.LvsAimPoint and self:LvsAimPoint(tgt)) or tgt:WorldSpaceCenter()

					local filter = { self, cam }

					for _, hb in ipairs(self.LvsHitboxes or {}) do
						if IsValid(hb.ent) then filter[#filter + 1] = hb.ent end
					end

					filter[#filter + 1] = tgt

					local chk = util.TraceLine({
						start  = origin,
						endpos = center,
						filter = filter,
						mask   = MASK_SOLID,
					})

					if chk.Fraction >= 0.97 then
						lockHit = tgt

						-- точка на поверхности модели: луч не проходит сквозь неё
						-- (цель убираем из фильтра, чтобы попасть в её модель)
						local stopFilter = {}

						for i = 1, #filter - 1 do stopFilter[i] = filter[i] end

						local stop = util.TraceLine({
							start  = start,
							endpos = center,
							filter = stopFilter,
							mask   = MASK_SHOT,
						})

						lockPos = (stop.Hit and stop.Entity == tgt) and stop.HitPos or center
					end
				end

				-- тонкая трасса может пройти мимо хитбокса игрока — добираем шириной
				local function isTarget(e)
					return IsValid(e) and (e:IsPlayer() or e:IsNPC() or e:IsNextBot())
				end

				if not isTarget(tr.Entity) then
					local wide = Vector(8, 8, 8)
					local tr2 = droneTrace(self, -wide, wide, MASK_SHOT)

					-- перестраховка: не цепляем цель за стеной/углом
					if isTarget(tr2.Entity) then
						local cam = self:GetCamera()
						if not IsValid(cam) then cam = self end

						local check = util.TraceLine({
							start  = cam:GetPos(),
							endpos = tr2.Entity:WorldSpaceCenter(),
							filter = { self, cam, tr2.Entity },
							mask   = MASK_SOLID,
						})

						if not check.Hit then tr = tr2 end
					end
				end

				-- ИИ не держит луч на уже замороженной цели — добивает пулемётом
				local enemy = self.Buffer and self.Buffer.Enemy
				if (self.AI_installed or self.LvsAutonomous)
					and IsValid(enemy) and LVSScout and LVSScout.IsFrozen(enemy) then
					gun.Firing = false
				end

				self:SetNWBool("LvsCryoActive", gun.Firing)
				-- клиент рисует луч ровно из этой точки (та же, что у осколков)
				self:SetNWVector("LvsCryoStart", start)
				self:SetNWVector("LvsCryoAim", lockPos or tr.HitPos)

				local hit = tr.Hit and IsValid(tr.Entity) and not tr.Entity:IsWorld()
					and tr.Entity ~= self and tr.Entity.LvsDrone ~= self
					and (tr.Entity:IsPlayer() or tr.Entity:IsNPC() or tr.Entity:IsNextBot())
					and tr.Entity or nil

				if lockHit then hit = lockHit end

				-- луч реально достаёт цель: сбрасываем счётчик «нет попаданий»
				if hit and hit == self.LvsAiTarget then
					self.LvsEffectiveAt = CurTime()
				end

				-- заряд заморозки: нужен непрерывный луч, сброс при уходе/смене цели
				if not gun.Firing or not hit or (LVSScout and LVSScout.IsFrozen(hit)) then
					self.LvsFreezeTarget = nil
					self.LvsFreezeCharge = 0
					return
				end

				if self.LvsFreezeTarget ~= hit then
					self.LvsFreezeTarget = hit
					self.LvsFreezeCharge = 0
				end

				self.LvsFreezeCharge = (self.LvsFreezeCharge or 0) + FrameTime()

				if self.LvsFreezeCharge < (self.LvsFreezeTime or 3) then return end
				if gun.NextHit > CurTime() then return end

				gun.NextHit = CurTime() + gun.FireDelay

				-- Луч только замораживает (не убивает): NPC 20с, игрок 5с.
				-- Пока держим луч на цели — заморозка продлевается.
				if LVSScout then
					LVSScout.Freeze(hit, hit:IsPlayer() and 5 or 20, self)
				end
			end,

			-- Второй режим: пулемёт ледяными осколками (Fire2)
			Attack2 = function(self, gun)
				local dbg = GetConVar("lvs_scout_debug") and GetConVar("lvs_scout_debug"):GetBool()

				if not self:IsDroneWorkable() then
					if dbg then print("[LVS] mg: drone not workable") end
					return
				end
				if CurTime() < (gun.NextBullet or 0) then return end

				local perf = self.LvsPerf and self:LvsPerf(self)
				gun.NextBullet = CurTime() + (perf and 1/6 or 0.1)

				local start = self:GetCryoStart()
				local tr = droneTrace(self, nil, nil, MASK_SHOT)
				local dir = (tr.HitPos - start):GetNormal()

				-- автономно: бьём в цель с упреждением; если мешает рельеф —
				-- поднимаем точку прицела, пока линия огня не освободится
				local tgt = self.LvsAutonomous and self.LvsAiTarget

				-- взятие на прицел с задержкой: цель не умирает в кадре спавна
				if self.LvsAutonomous and CurTime() < (self.LvsEngageAt or 0) then return end

				local aimPoint

				if IsValid(tgt) and self.LvsAimPoint then
					aimPoint = (self.LvsLeadPoint and self:LvsLeadPoint(tgt, start, 7000))
						or (self.LvsAimPoint(tgt) or tgt:WorldSpaceCenter())

					local gunFilter = { self }

					for _, h in ipairs(self.LvsHitboxes or {}) do
						if IsValid(h.ent) then gunFilter[#gunFilter + 1] = h.ent end
					end

					local chosen

					for _, off in ipairs({ 0, 18, 36, 60 }) do
						local p = aimPoint + Vector(0, 0, off)
						local d = (p - start):GetNormal()
						local path = util.TraceHull({
							start  = start,
							endpos = start + d * math.min(start:Distance(p) + 64, 6000),
							mins   = Vector(-6, -6, -6),
							maxs   = Vector(6, 6, 6),
							filter = gunFilter,
							mask   = MASK_SOLID,
						})

						if not path.Hit or path.Entity == tgt then
							chosen = p
							break
							end
						end

					if not chosen then
						if dbg then print("[LVS] mg path blocked: рельеф по всей линии") end
						return
					end

					aimPoint = chosen
					dir = (aimPoint - start):GetNormal()

					if dbg then
						local v = (self.LvsTargetVel and self:LvsTargetVel(tgt)) or tgt:GetVelocity() or vector_origin
						print(string.format("[LVS] mg aim: %s dist=%d vel=%d lead=%d lift=%d",
							tgt:GetClass(), math.floor(start:Distance(tgt:WorldSpaceCenter())),
							math.floor(v:Length()),
							math.floor(aimPoint:Distance(tgt:WorldSpaceCenter())),
							math.floor(aimPoint.z - tgt:WorldSpaceCenter().z)))
					end
				end

				if dir:IsZero() then dir = self:GetForward() end

				-- в автономном режиме без разброса: попадание важнее вида
				local spread = self.LvsAutonomous and 0.0 or 0.35
				if spread > 0 then
					dir:Rotate(Angle(math.Rand(-spread, spread), math.Rand(-spread, spread), 0))
				end

				-- как у DRR: вылет из дула, впереди модели (иначе пуля стартует внутри и «плывёт»)
				local muzzle = start + dir * 64

				-- если впереди земля/стена — не спавним осколок внутри геометрии
				local filter = { self }

				for _, h in ipairs(self.LvsHitboxes or {}) do
					if IsValid(h.ent) then filter[#filter + 1] = h.ent end
				end

				local clear = util.TraceLine({
					start  = start,
					endpos = muzzle,
					filter = filter,
					mask   = MASK_SHOT,
				})

				if clear.Hit then
					muzzle = start + dir * math.max(clear.Fraction * 64 - 6, 2)
				end

				local e = ents.Create("lvs_scout_ice")
				if not IsValid(e) then return end

				e:SetPos(muzzle)
				e:SetAngles(dir:Angle())
				e:SetOwner(self)
				e:Spawn()
				e:Activate()
				e:SetDir(dir)

				if dbg then
					print(string.format("[LVS] ice: dir=%s startDist=%d muzzleDist=%d clear=%s",
						tostring(dir), math.floor(start:Distance(tgt and tgt:WorldSpaceCenter() or start)),
						math.floor(muzzle:Distance(tgt and tgt:WorldSpaceCenter() or muzzle)),
						tostring(clear.Hit)))
				end

				-- вспышка у пасти дрона
				net.Start("lvs_scout_muzzle")
				net.WriteVector(muzzle)
				net.SendPVS(muzzle)
			end,

			OnRemove = function(self, gun)
				self:SetNWBool("LvsCryoActive", false)
			end
		}
	end
end
