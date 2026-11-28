-- База: Drones Rewrite (обязательно установлен)
ENT.Base = "dronesrewrite_base"
ENT.Type = "anim"
ENT.PrintName = "DRR Scout"
ENT.Author = "DRR"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.Category = "Drones Rewrite"

-- Явно помечаем себя дроном: радар DRR берёт всех, у кого IS_DRONE
ENT.IS_DRONE = true
ENT.ShowOnRadar = true

ENT.UNIT = "SCT"
ENT.HUD_hudName = "Crysis Ceph"
-- Свой оверлей (цветокор Ceph) — выбирается по умолчанию
ENT.OverlayName = "DRR Ceph"

ENT.Weight = 120
ENT.SpawnHeight = 60
ENT.Model = "models/crysis/scout/scout.mdl"

-- Вид от третьего лица: корпус 633 юнита в длину, стандартные 100
-- ставили камеру внутрь модели. Выносим за габарит и поднимаем.
ENT.ThirdPersonCam_pos = Vector(0, 0, 140)
ENT.ThirdPersonCam_distance = 700

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

ENT.HealthAmount = 200
ENT.DefaultHealth = 200

ENT.Sounds = {
	PropellerSound = {
		Name = "npc/manhack/mh_engine_loop1.wav",
		Pitch = 115,
		Level = 72
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
ENT.DrrAiStandoff = 1400

-- Дистанция против летающих/ближних врагов (маньяки, сканеры)
ENT.DrrAiFlyStandoff = 1900

-- Множитель урона пулемёта по грузу дропшипа
ENT.DrrAiHeavyDamageMul = 8


-- Максимальный подъём над целью по Z (юниты), реальный считается от PitchMin
ENT.DrrAiAltitudeOffset = 2000

-- Минимальная высота над землёй для автономного полёта
ENT.DrrMinAltitude = 800

-- Рабочая высота патруля над землёй (случайно в этом диапазоне)
ENT.DrrPatrolAltitudeMin = 700
ENT.DrrPatrolAltitudeMax = 1200

-- Серво-гул двигателя: низкий рокот, не пересекается с гулом луча
ENT.DrrServoSound = "npc/combine_gunship/gunship_engine_loop3.wav"
ENT.DrrServoVolume = 0.55

-- Адаптивный урон: сколько попаданий в «бронированную» цель нужно,
-- чтобы пробить защиту, и во сколько раз сильнее пробивающий удар
ENT.DrrAdaptLimit = 10
ENT.DrrAdaptMul = 3

-- Приоритет тяжёлой техники в выборе цели:
-- true  — тяжёлая техника выбирается в первую очередь (страйдер и т.п.)
-- false — обычный выбор (ближайшая видимая цель)
ENT.DrrHeavyHighPriority = true

-- Сколько секунд непрерывного луча нужно, чтобы заморозить цель
ENT.DrrFreezeTime = 3

-- Доля максимального HP в секунду при регенерации (0.01 = 1%/с)
ENT.DrrRegenRate = 0.01
ENT.CryoDelay = 0.08

-- Оружие через систему DRR. Класс "Cryo" регистрируется ниже.
ENT.Attachments = {
	["Cryo"] = { Pos = Vector(0, 0, 0) }
}

ENT.Weapons = {
	["Cryo"] = { Name = "Cryo", Attachment = "Cryo" }
}

-- Позиция аттачмента модели (с учётом анимации костей)
function ENT:DrrAttachmentPos(name)
	self.DrrAttCache = self.DrrAttCache or {}

	local id = self.DrrAttCache[name]
	if id == nil then
		id = self:LookupAttachment(name) or 0
		self.DrrAttCache[name] = id
	end

	if id <= 0 then return end

	local att = self:GetAttachment(id)
	return att and att.Pos
end

-- Точка обзора: вынесена вперёд за модель (лоб на уровне x≈84), чтобы
-- в кадр не попадала сама голова. Без GetBonePosition — камера стабильна.
local DRR_EYE_LOCAL = Vector(140, 0, 30)

function ENT:DrrEyePos()
	return self:LocalToWorld(DRR_EYE_LOCAL)
end
-- Камеру позиционируем сами (в Think), поэтому локальное смещение — нулевое
function ENT:GetLocalCamPos()
	return vector_origin
end
-- Трасса прицела/HUD: стартует из аттачмента light (область глаз) и
-- не цепляет собственные прокси-хитбоксы.
function ENT:GetCameraTraceLine(distance, mins, maxs, mask)
	local cam = self:GetCamera()
	if not IsValid(cam) then cam = self end

	-- как в базе DRR: луч из позиции камеры, а не из головы модели
	local start = cam:GetPos()
	local dir = (self.CamAngles or self:GetAngles()):Forward()

	local filter = { self, cam }

	for _, h in ipairs(self.DrrHitboxes or {}) do
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

	for _, h in ipairs(drone.DrrHitboxes or {}) do
		if IsValid(h.ent) then filter[#filter + 1] = h.ent end
	end

	local aimAng = drone.DrrAutoAngles or drone.CamAngles

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

-- Вызов пулемёта из ИИ: флаг на время вызова отличает ИИ от ручной ПКМ
function ENT:DrrAiAttack2(gun)
	self.DrrAiFiring = true
	DRONES_REWRITE.Weapons["Cryo"].Attack2(self, gun)
	self.DrrAiFiring = false
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
				-- отмечаем реальное нажатие: до него гул включать нельзя
				gun.DrrEverFired = true

				if self.DrrScriptPause and self:DrrScriptPause() then return end

				-- ЭМИ-стан: оружие не работает
				if CurTime() < (self.DrrStunnedUntil or 0) then
					gun.Firing = false
					return
				end

				-- автономно стреляем только при ПОЛНОЙ видимости цели
				if self.DrrAutonomous and IsValid(self.DrrAiTarget) and self.DrrFullVisible
					and not self:DrrFullVisible(self.DrrAiTarget) then
					gun.Firing = false
					return
				end

				local enemy = self.Buffer and self.Buffer.Enemy

				-- автономно без цели не стреляем вообще; сам дропшип — не цель
				if self.DrrAutonomous and (not IsValid(self.DrrAiTarget)
					or self.DrrAiTarget:GetClass() == "npc_combinedropship") then
					gun.Firing = false
					return
				end

				-- автономно: цели, которые бьём пулемётом (режим 1, лёд, летун, проп, груз, тяжёлая техника)
				if self.DrrAutonomous then
					local tgt = self.DrrAiTarget

					local useMG = self.DrrAttackMode == 1
						or (self.DrrIsFlyer and self:DrrIsFlyer(tgt))
						or (self.DrrIsPropTarget and self:DrrIsPropTarget(tgt))
						or (self.DrrIsCargo and self:DrrIsCargo(tgt))
						or (DRRScout and DRRScout.IsFrozen(tgt))

					if useMG then
						gun.Firing = false
						self:DrrAiAttack2(gun)
						return
					end
				end

				-- ИИ без пилота: замороженного врага добиваем пулемётом
				if self.AI_installed and not IsValid(self:GetDriver())
					and IsValid(enemy) and DRRScout and DRRScout.IsFrozen(enemy) then
					gun.Firing = false
					self:DrrAiAttack2(gun)
					return
				end

				-- перегрет: выстрел заблокирован до полного остывания
				if gun.DrrOverheat then
					gun.Firing = false
					return
				end

				gun.Firing = true
				gun.FireUntil = CurTime() + 0.6
			end,

			OnAttackStopped = function(self, gun)
				gun.Firing = false
			end,

	Think = function(self, gun)
	-- гул только после реального нажатия: база DRR держит Firing = true
	-- на старте, и при пачке спавнов часть дронов успевала загудеть
	if not gun.DrrEverFired then
		gun.Firing = false
		self:SetNWBool("DrrCryoActive", false)
	end

	-- Гул криолуча: отдельная электрическая петля, не путается с гулом двигателя
	local loopSnd = "ambient/energy/force_field_loop1.wav"

	-- петлю создаём только когда реально стреляем: иначе при спавне
	-- она успевала сыграть на полной громкости до ChangeVolume(0)
	if not gun.DrrLoop then
		-- страховка: если HL2-контента нет, берём точно существующую петлю
		if not file.Exists("sound/" .. loopSnd, "GAME") then
			loopSnd = "npc/combine_gunship/gunship_engine_loop3.wav"
		end

		gun.DrrLoop = CreateSound(self, loopSnd)

		if gun.DrrLoop then
			gun.DrrLoop:SetSoundLevel(130)
			gun.DrrLoop:ChangePitch(120, 0)
			gun.DrrLoop:ChangeVolume(0, 0)
			gun.DrrLoop:Play()
		end
	end

				if gun.DrrLoop then
					gun.DrrLoop:ChangeVolume(gun.Firing and 1 or 0, 0.08)
				end

				-- катсцена HL2: гасим луч, даже если он горел
				if self.DrrScriptPause and self:DrrScriptPause() then
					gun.Firing = false
					self:SetNWBool("DrrCryoActive", false)
					return
				end

	-- разряд в момент начала стрельбы: без него луч стартует «насухо»
	-- DrrWasFiring == false: на первом тике после спавна поле ещё nil,
	-- иначе при появлении дрона играл звук выстрела
	if gun.Firing and gun.DrrWasFiring == false then
					local snd = file.Exists("sound/drones/alien_fire.wav", "GAME") and "drones/alien_fire.wav" or "weapons/ar2/fire1.wav"
					self:EmitSound(snd, 95, math.random(105, 115), 1)
				end
				-- Перегрев настраивается: drr_scout_cryo_heat (секунд до перегрева,
				-- 0 — отключён совсем) и drr_scout_cryo_cool (секунд на остывание)
				local upCv = GetConVar("drr_scout_cryo_heat")
				local coolCv = GetConVar("drr_scout_cryo_cool")
				local upTime = upCv and upCv:GetFloat() or 10
				local coolTime = coolCv and coolCv:GetFloat() or 2.5

				local heat = gun.DrrHeat or 0

				if upTime <= 0 then
					heat = 0
					gun.DrrOverheat = nil
				else
					if gun.Firing then
						heat = math.min(heat + FrameTime() / math.max(upTime, 0.1), 1)
					else
						heat = math.max(heat - FrameTime() / math.max(coolTime, 0.1), 0)
					end

					if heat >= 1 then gun.DrrOverheat = true end
					if gun.DrrOverheat and heat <= 0 then gun.DrrOverheat = nil end

					if gun.DrrOverheat then
						gun.Firing = false
						gun.FireUntil = 0
					end
				end

	gun.DrrHeat = heat
	self:SetNWFloat("DrrCryoHeat", heat)
	self:SetNWBool("DrrCryoOverheat", gun.DrrOverheat == true)
				gun.DrrWasFiring = gun.Firing
				-- автономно без цели: возможности не применяем; дропшип — не цель
				if self.DrrAutonomous and (not IsValid(self.DrrAiTarget)
					or self.DrrAiTarget:GetClass() == "npc_combinedropship") then
					gun.Firing = false
					self:SetNWBool("DrrCryoActive", false)
					return
				end

				-- автономно: луч по живой цели, пулемёт — только по замороженной
				local drrFrozen = self.DrrAutonomous and IsValid(self.DrrAiTarget)
					and DRRScout and DRRScout.IsFrozen(self.DrrAiTarget)

				local drrFlyer = self.DrrAutonomous and self.DrrIsFlyer
					and self:DrrIsFlyer(self.DrrAiTarget)
				local drrProp = self.DrrAutonomous and self.DrrIsPropTarget
					and self:DrrIsPropTarget(self.DrrAiTarget)

				local drrCargo = self.DrrAutonomous and self.DrrIsCargo
					and self:DrrIsCargo(self.DrrAiTarget)

				local drrMGOnly = self.DrrAutonomous and self.DrrAttackMode == 1
					and IsValid(self.DrrAiTarget)

				-- львы: только пулемёт, луч по ним не ведём
				local drrAntlion = self.DrrAutonomous and self.DrrAntlion
					and self:DrrAntlion(self.DrrAiTarget)

				-- страйдер: броня гасит луч, работаем только пулемётом
				local drrMgStrider = self.DrrAutonomous and IsValid(self.DrrAiTarget)
					and self.DrrAiTarget:GetClass() == "npc_strider"

				-- ИИ предпочитает пулемёт: вблизи он эффективнее луча
				local drrClose = self.DrrAutonomous and IsValid(self.DrrAiTarget)
					and self:GetPos():Distance(self.DrrAiTarget:GetPos()) < 1800

				-- львов пулемётом бьём только если класса нет в списке друзей
				local drrMgOk = not self.DrrMgAllowed or not IsValid(self.DrrAiTarget)
					or self:DrrMgAllowed(self.DrrAiTarget)

				-- пулемётные цели: стреляем каждый Think (Attack2 сам держит кулдаун),
				-- иначе один выстрел на скан (2/с) — урон почти не виден
				if (drrFrozen or drrFlyer or drrProp or drrCargo or drrMGOnly or drrAntlion or drrMgStrider or drrClose) and drrMgOk then
					gun.Firing = false
					self:SetNWBool("DrrCryoActive", false)
					self:DrrAiAttack2(gun)
					return
				end

				if self.DrrAutonomous and self.DrrAttackMode ~= 1 and not drrAntlion
					and IsValid(self.DrrAiTarget)
					and CurTime() >= (self.DrrEngageAt or 0)
					and self.DrrAutoAngles and self.DrrAimAligned then
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

				if self.DrrAutonomous and IsValid(self.DrrAiTarget) then
					local tgt = self.DrrAiTarget
					local cam = self:GetCamera()
					local origin = IsValid(cam) and cam:GetPos() or self:GetPos()
					local center = (self.DrrAimPoint and self:DrrAimPoint(tgt)) or tgt:WorldSpaceCenter()

					local filter = { self, cam }

					for _, hb in ipairs(self.DrrHitboxes or {}) do
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
				if (self.AI_installed or self.DrrAutonomous)
					and IsValid(enemy) and DRRScout and DRRScout.IsFrozen(enemy) then
					gun.Firing = false
				end

				self:SetNWBool("DrrCryoActive", gun.Firing)
				-- клиент рисует луч ровно из этой точки (та же, что у осколков)
				self:SetNWVector("DrrCryoStart", start)
				self:SetNWVector("DrrCryoAim", lockPos or tr.HitPos)

				local hit = tr.Hit and IsValid(tr.Entity) and not tr.Entity:IsWorld()
					and tr.Entity ~= self and tr.Entity.DrrDrone ~= self
					and (tr.Entity:IsPlayer() or tr.Entity:IsNPC() or tr.Entity:IsNextBot())
					and tr.Entity or nil

				if lockHit then hit = lockHit end

				-- луч реально достаёт цель: сбрасываем счётчик «нет попаданий»
				if hit and hit == self.DrrAiTarget then
					self.DrrEffectiveAt = CurTime()
				end

				-- заряд заморозки: нужен непрерывный луч, сброс при уходе/смене цели
				if not gun.Firing or not hit or (DRRScout and DRRScout.IsFrozen(hit)) then
					self.DrrFreezeTarget = nil
				self:SetNWFloat("DrrFreezePct", 0)
				self.DrrFreezeCharge = 0
					return
				end

				if self.DrrFreezeTarget ~= hit then
					self.DrrFreezeTarget = hit
					self.DrrFreezeCharge = 0
				end

				self.DrrFreezeCharge = (self.DrrFreezeCharge or 0) + FrameTime()

				-- HUD: видно, сколько ещё держать луч до заморозки
				self:SetNWFloat("DrrFreezePct",
					math.Clamp(self.DrrFreezeCharge / math.max(self.DrrFreezeTime or 3, 0.1), 0, 1))

				if self.DrrFreezeCharge < (self.DrrFreezeTime or 3) then return end
				if gun.NextHit > CurTime() then return end

				gun.NextHit = CurTime() + gun.FireDelay

				-- Луч только замораживает (не убивает): NPC 20с, игрок 5с.
				-- Пока держим луч на цели — заморозка продлевается.
				if DRRScout then
					DRRScout.Freeze(hit, hit:IsPlayer() and 5 or 20, self)
				end
			end,

			-- Второй режим: пулемёт ледяными осколками (Fire2)
			Attack2 = function(self, gun)
				if self.DrrScriptPause and self:DrrScriptPause() then return end

				local dbg = GetConVar("drr_scout_debug") and GetConVar("drr_scout_debug"):GetBool()

				-- ЭМИ-стан: пулемёт молчит
				if CurTime() < (self.DrrStunnedUntil or 0) then return end

				-- Автономный режим стреляет сам: ручная ПКМ не должна давать очередь
				if self.DrrAutonomous and not self.DrrAiFiring then return end

				-- автономно стреляем только при ПОЛНОЙ видимости цели
				if self.DrrAutonomous and IsValid(self.DrrAiTarget) and self.DrrFullVisible
					and not self:DrrFullVisible(self.DrrAiTarget) then return end

				if not self:IsDroneWorkable() then
					if dbg then print("[DRR] mg: drone not workable") end
					return
				end
				if CurTime() < (gun.NextBullet or 0) then return end

				-- Теми же 10 выстр./с на любых настройках: экономим не темпом,
				-- а числом спрайтов трассера и эффектов (см. drr_scout_ice/cl_init).
				gun.NextBullet = CurTime() + 0.1

				-- Пулемёт: короткий электрический щелчок. Свой канал CHAN_WEAPON:
				-- иначе выстрелы наслаиваются в непрерывный гул.
				if not self.DrrMgSnd then
					for _, snd in ipairs({
						"drones/eblade_shock_01.wav",
						"weapons/smg1/smg1_fire1.wav",
						"weapons/ar2/fire1.wav",
					}) do
						if file.Exists("sound/" .. snd, "GAME") then
							self.DrrMgSnd = snd
							break
						end
					end

					self.DrrMgSnd = self.DrrMgSnd or "weapons/ar2/fire1.wav"
				end

				-- soundlevel 110 вместо 72: 72 гас уже к дистанции камеры
				-- третьего лица, и стрельбу было почти не слышно
				self:EmitSound(self.DrrMgSnd, 110, math.random(120, 138), 0.5, CHAN_WEAPON)

				local start = self:GetCryoStart()
				local tr = droneTrace(self, nil, nil, MASK_SHOT)
				local dir = (tr.HitPos - start):GetNormal()

				-- автономно: бьём в цель с упреждением; если мешает рельеф —
				-- поднимаем точку прицела, пока линия огня не освободится
				local tgt = self.DrrAutonomous and self.DrrAiTarget

				-- взятие на прицел с задержкой: цель не умирает в кадре спавна
				if self.DrrAutonomous and CurTime() < (self.DrrEngageAt or 0) then return end

				local aimPoint

				if IsValid(tgt) and self.DrrAimPoint then
					aimPoint = (self.DrrLeadPoint and self:DrrLeadPoint(tgt, start, 7000))
						or (self.DrrAimPoint(tgt) or tgt:WorldSpaceCenter())

					local gunFilter = { self }

					for _, h in ipairs(self.DrrHitboxes or {}) do
						if IsValid(h.ent) then gunFilter[#gunFilter + 1] = h.ent end
					end

					local chosen

					-- только прямая наводка: подъём прицела давал стрельбу «в щель»
					for _, off in ipairs({ 0 }) do
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
						if dbg then print("[DRR] mg path blocked: рельеф по всей линии") end
						return
					end

					aimPoint = chosen
					dir = (aimPoint - start):GetNormal()

					if dbg then
						local v = (self.DrrTargetVel and self:DrrTargetVel(tgt)) or tgt:GetVelocity() or vector_origin
						print(string.format("[DRR] mg aim: %s dist=%d vel=%d lead=%d lift=%d",
							tgt:GetClass(), math.floor(start:Distance(tgt:WorldSpaceCenter())),
							math.floor(v:Length()),
							math.floor(aimPoint:Distance(tgt:WorldSpaceCenter())),
							math.floor(aimPoint.z - tgt:WorldSpaceCenter().z)))
					end
				end

				if dir:IsZero() then dir = self:GetForward() end

				-- в автономном режиме без разброса: попадание важнее вида
				local spread = self.DrrAutonomous and 0.0 or 0.35
				if spread > 0 then
					dir:Rotate(Angle(math.Rand(-spread, spread), math.Rand(-spread, spread), 0))
				end

				-- как у DRR: вылет из дула, впереди модели (иначе пуля стартует внутри и «плывёт»)
				local muzzle = start + dir * 64

				-- если впереди земля/стена — не спавним осколок внутри геометрии
				local filter = { self }

				for _, h in ipairs(self.DrrHitboxes or {}) do
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


				local e = ents.Create("drr_scout_ice")
				if not IsValid(e) then return end

				e:SetPos(muzzle)
				e:SetAngles(dir:Angle())
				e:SetOwner(self)
				e:Spawn()
				e:Activate()
				e:SetDir(dir)
				e:SetRange(start:Distance(aimPoint or tr.HitPos))

				if dbg then
					-- DrrAiTarget мог быть удалён между кадрами: ссылка не nil,
					-- но вызов WorldSpaceCenter на NULL роняет Think
					local tgtPos = IsValid(tgt) and tgt:WorldSpaceCenter()

					print(string.format("[DRR] ice: dir=%s startDist=%d muzzleDist=%d clear=%s",
						tostring(dir),
						math.floor(start:Distance(tgtPos or start)),
						math.floor(muzzle:Distance(tgtPos or muzzle)),
						tostring(clear.Hit)))
				end

				-- вспышка у пасти дрона
				net.Start("drr_scout_muzzle")
				net.WriteVector(muzzle)
				net.SendPVS(muzzle)
			end,

			OnRemove = function(self, gun)
				self:SetNWBool("DrrCryoActive", false)
			end
		}

		DRONES_REWRITE.DrrCryoDef = DRONES_REWRITE.Weapons["Cryo"]
	end
end
