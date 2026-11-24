include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

local SEGS_PER_ROPE = 13

util.AddNetworkString("lvs_scout_set_skin")
util.AddNetworkString("lvs_scout_set_shield")

util.AddNetworkString("lvs_scout_shield_down")
util.AddNetworkString("lvs_scout_auto")
util.AddNetworkString("lvs_scout_auto_all")
util.AddNetworkString("lvs_scout_auto_stats")
util.AddNetworkString("lvs_scout_auto_stats_res")
util.AddNetworkString("lvs_scout_muzzle")
-- Сколько секунд щит восстанавливается после истощения джаммером
local SHIELD_REGEN_DELAY = 30

local BONE_NAMES = {
	Head   = ENT.HeadBone,
	Weapon = ENT.WeaponBone
}

for i = 1, ENT.TentacleCount do
	for s = 1, SEGS_PER_ROPE do
		BONE_NAMES[string.format("Rope%dSeg%d", i, s)] = string.format("rope%d_seg%02d", i, s)
	end
	BONE_NAMES["Claw" .. i] = "claw_rope" .. i
	for c = 1, 3 do
		BONE_NAMES[string.format("Claw%dPart%d", i, c)] = string.format("claw_rope%d_%02d", i, c)
	end
end

local TENTACLE_WAVE     = 9
local TENTACLE_MAX_BEND = 12
local TENTACLE_SPEED    = 2.2
local HEAD_ROTATE_SPEED = 9
local ARM_ROTATE_SPEED  = 8
local PITCH_LIMIT       = 55
local YAW_LIMIT         = 75
local CAM_OFFSET        = 4

-- Невидимые хитбоксы на костях: пули должны цеплять щупальца/клешни/голову
local HITBOX_MODEL = "models/props_junk/PopCan01a.mdl"
local HITBOX_HALF  = 8

-- Кеш навигационных зон и AI-нод для патруля
local LvsNavCache, LvsNavCacheAt = nil, 0
local LvsNodeCache, LvsNodeCacheAt = nil, 0

function ENT:ResolveBones()
	self.BoneIDs = {}

	local lookup = {}
	for i = 0, self:GetBoneCount() - 1 do
		lookup[string.lower(self:GetBoneName(i))] = i
	end

	for role, name in pairs(BONE_NAMES) do
		local id = self:LookupBone(name)
		if not id then id = lookup[string.lower(name)] end
		self.BoneIDs[role] = id

		if not id and (role == "Head" or role == "Weapon") then
			print("[LVS Scout] Кость не найдена: " .. name)
		end
	end

	-- Все кости щупалец из модели, а не только первые 13 сегментов:
	-- так анимируются любые дополнительные сегменты и фаланги
	self.LvsRopeBones = {}
	self.LvsClawBones = {}

	for i = 0, self:GetBoneCount() - 1 do
		local name = string.lower(self:GetBoneName(i))

		local tent, seg = name:match("^rope(%d+)_seg(%d+)$")

		if tent then
			tent, seg = tonumber(tent), tonumber(seg)

			self.LvsRopeBones[tent] = self.LvsRopeBones[tent] or {}
			table.insert(self.LvsRopeBones[tent], { id = i, seg = seg })
		else
			local claw, part = name:match("^claw_rope(%d+)_(%d+)$")

			if claw then
				claw, part = tonumber(claw), tonumber(part)

				self.LvsClawBones[claw] = self.LvsClawBones[claw] or {}
				table.insert(self.LvsClawBones[claw], { id = i, part = part })
			else
				local base = name:match("^claw_rope(%d+)$")

				if base then
					base = tonumber(base)

					self.LvsClawBones[base] = self.LvsClawBones[base] or {}
					table.insert(self.LvsClawBones[base], { id = i })
				end
			end
		end
	end

	-- сегменты в модели могут идти не по порядку
	local segs, claws = 0, 0

	for _, list in pairs(self.LvsRopeBones) do
		table.sort(list, function(a, b) return (a.seg or 0) < (b.seg or 0) end)
		segs = segs + #list
	end

	for _, list in pairs(self.LvsClawBones) do
		claws = claws + #list
	end

	print(string.format("[LVS Scout] кости щупалец: %d сегментов, %d клешней", segs, claws))
end

-- Хитбоксы-прокси: следуют за костями, урон перенаправляется в дрон
function ENT:LvsBuildHitboxes()
	self.LvsHitboxes = {}

	local function add(boneID)
		if not boneID then return end

		local e = ents.Create("lvs_scout_hitbox")
		if not IsValid(e) then return end

		e.LvsDrone = self
		e:Spawn()

		self.LvsHitboxes[#self.LvsHitboxes + 1] = { ent = e, bone = boneID }
	end

	add(self.BoneIDs.Head)

	for i = 1, self.TentacleCount do
		add(self.BoneIDs["Claw" .. i])

		for s = 1, SEGS_PER_ROPE do
			add(self.BoneIDs[string.format("Rope%dSeg%d", i, s)])
		end
	end
end

function ENT:LvsUpdateHitboxes()
	-- миграция старых prop_dynamic-прокси на новый класс
	local first = self.LvsHitboxes and self.LvsHitboxes[1]
	if first and IsValid(first.ent) and first.ent:GetClass() ~= "lvs_scout_hitbox" then
		self:LvsRemoveHitboxes()
		self:LvsBuildHitboxes()
	end

	for _, h in ipairs(self.LvsHitboxes or {}) do
		if IsValid(h.ent) then
			local pos = self:GetBonePosition(h.bone)
			if pos then h.ent:SetPos(pos) end
		end
	end
end

function ENT:LvsRemoveHitboxes()
	for _, h in ipairs(self.LvsHitboxes or {}) do
		if IsValid(h.ent) then h.ent:Remove() end
	end

	self.LvsHitboxes = nil
end

function ENT:LvsNearAnyBone(pos, radius)
	local r2 = radius * radius

	for i = 0, self:GetBoneCount() - 1 do
		local b = self:GetBonePosition(i)
		if b and b:DistToSqr(pos) <= r2 then return true end
	end

	return false
end

-- Кейс-модуль срабатывает при касании любой части дрона (голова, щупальца и т.д.)
function ENT:LvsCheckModulePickup()
	if not self.AddModule then return end
	if IsValid(self:GetDriver()) then return end

	for _, e in ipairs(ents.FindByClass("dronesrewrite_upgrcase_*")) do
		if IsValid(e) and self:LvsNearAnyBone(e:WorldSpaceCenter(), 40) then
			if self:AddModule(e.PrintName) then e:Remove() end
		end
	end
end

-- Уклонение: после попадания кратко стрейфим, если щит не активен
hook.Remove("EntityTakeDamage", "lvs_scout_dodge")
hook.Add("EntityTakeDamage", "lvs_scout_dodge", function(ent, dmg)
	if not IsValid(ent) or ent:GetClass() ~= "lvs_scout_drr" or not ent.LvsAutonomous then return end
	if ent:HasModule("Shield") and (ent:GetNWInt("shield_health") or 0) > 0 then return end

	local now = CurTime()

	-- кулдаун: под плотным огнём не уходим в бесконечный стрейф
	if now > (ent.LvsDodgeNext or 0) then
		ent.LvsDodgeNext = now + 1.6
		ent.LvsDodgeUntil = now + 1.4
		ent.LvsDodgeDir = (ent.LvsDodgeDir == "left") and "right" or "left"
	end
end)

function ENT:Initialize()
	self.BaseClass.Initialize(self)

	-- автономный модуль по умолчанию выключен
	self.LvsAutonomous = false
	self:SetNWBool("LvsAuto", false)

	-- дружественные классы NPC (переживают переспавн: копия с владельца)
	self.LvsFriendClasses = {}

	if IsValid(self.Owner) and self.Owner.LvsFriendClasses then
		self.LvsFriendClasses = table.Copy(self.Owner.LvsFriendClasses)
	end

	-- владелец в сеть: клиент красит свои дроны отдельным цветом на радаре
	if IsValid(self.Owner) then
		self:SetNWEntity("LvsOwner", self.Owner)
		self:SetNWString("LvsOwnerID", self.Owner:SteamID())
	end

	self:ResolveBones()
	self:LvsBuildHitboxes()

	-- модель не должна играть свои анимации: они перезаписывают движения костей
	if self.SetPlaybackRate then self:SetPlaybackRate(0) end

	-- восстанавливаем выбранную расцветку (0 — обычная, 1 — красная)
	local skin = self:GetNWInt("LvsSkin", 0)
	if skin > 0 then self:SetSkin(skin) end

	for i = 1, self.TentacleCount do
		self["TentaclePhase" .. i] = math.Rand(0, math.pi * 2)
	end

	self:UpdateCameraPos()

	-- синхронизация состояния щита для клиента (визуал + меню F3)
	local tname = "lvs_scout_shield_sync_" .. self:EntIndex()
	timer.Create(tname, 0.5, 0, function()
		if not IsValid(self) then timer.Remove(tname) return end

		local has = self:HasModule("Shield")
		if self:GetNWBool("hasModuleShield") ~= has then self:SetNWBool("hasModuleShield", has) end
	end)
end

-- Расцветка: 0 — обычная, 1 — красная (переключение)
function ENT:LvsSetSkin(index)
	self.LvsSkin = index
	self:SetSkin(index)
	self:SetNWInt("LvsSkin", index)
end

function ENT:LvsToggleSkin()
	self:LvsSetSkin((self:GetSkin() == 0) and 1 or 0)
end

net.Receive("lvs_scout_set_skin", function(_, ply)
	local drone = ply:GetNWEntity("DronesRewriteDrone")
	if not IsValid(drone) or drone:GetClass() ~= "lvs_scout_drr" then return end

	drone:LvsSetSkin(net.ReadUInt(8))
end)

net.Receive("lvs_scout_set_shield", function(_, ply)
	local drone = ply:GetNWEntity("DronesRewriteDrone")
	if not IsValid(drone) or drone:GetClass() ~= "lvs_scout_drr" then return end

	local on = net.ReadBool()

	-- ручное решение игрока: автоматика ИИ его больше не трогает
	drone.LvsShieldManual = on

	if on then
		-- после джаммера щит заблокирован до конца перезарядки
		local left = (drone.LvsShieldDownUntil or 0) - CurTime()

		if left > 0 then
			if IsValid(ply) then
				ply:ChatPrint(string.format("[LVS Scout] Щит перезагружается: %d с", math.ceil(left)))
			end

			return
		end

		drone:AddModule("Shield")
	elseif drone:HasModule("Shield") then
		drone:RemoveModule("Shield")
	end
end)

properties.Add("lvs_scout_skin_toggle", {
	MenuLabel = "LVS Scout: переключить расцветку",
	MenuIcon = "icon16/paintbrush.png",

	Filter = function(self, ent)
		return IsValid(ent) and ent:GetClass() == "lvs_scout_drr"
	end,

	Action = function(self, ent)
		ent:LvsToggleSkin()
	end
})

local function segDistSqr(p, a, b)
	local ab = b - a
	local len = ab:LengthSqr()
	local t = len > 0 and math.Clamp((p - a):Dot(ab) / len, 0, 1) or 0

	return (p - (a + ab * t)):LengthSqr()
end

-- Точка попадания рядом с реальными костями (щупальца, голова, корпус)
function ENT:LvsHitVisiblePart(pos)
	local count = self:GetBoneCount()
	if not count or count <= 0 then return true end

	local r2 = 34 * 34

	for i = 0, count - 1 do
		local b = self:GetBonePosition(i)
		if b then
			local parent = self:GetBoneParent(i)
			local a = (parent and parent >= 0) and self:GetBonePosition(parent) or nil

			if a then
				if segDistSqr(pos, a, b) <= r2 then return true end
			elseif b:DistToSqr(pos) <= r2 then
				return true
			end
		end
	end

	-- попадание внутри корпуса тоже считаем валидным
	local lp = self:WorldToLocal(pos)
	local mn, mx = self:OBBMins(), self:OBBMaxs()

	if lp.x >= mn.x - 8 and lp.x <= mx.x + 8
		and lp.y >= mn.y - 8 and lp.y <= mx.y + 8
		and lp.z >= mn.z - 8 and lp.z <= mx.z + 8 then
		return true
	end

	return false
end

-- При установленном модуле Shield дрон не получает урона вообще
function ENT:LvsNotifyShieldDown(ply, force)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if not force and CurTime() < (ply.LvsShieldMsg or 0) then return end

	ply.LvsShieldMsg = CurTime() + 1

	net.Start("lvs_scout_shield_down")
	net.WriteEntity(self)
	net.WriteFloat(math.max((self.LvsShieldDownUntil or 0) - CurTime(), 0))
	net.Send(ply)
end

-- Сколько применений джаммера выдержит щит: чаще всего 5, но бывает и 1-7
local JAM_BREAK_WEIGHTS = { 5, 10, 15, 20, 35, 10, 5 }

local function rollJamBreak()
	local total = 0

	for _, w in ipairs(JAM_BREAK_WEIGHTS) do
		total = total + w
	end

	local r = math.random() * total
	local acc = 0

	for i, w in ipairs(JAM_BREAK_WEIGHTS) do
		acc = acc + w

		if r <= acc then return i end
	end

	return 5
end

-- Одно применение джаммера: щит тратится на 1/N и сбивается на случайном N-м
function ENT:LvsJammerDrain(attacker)
	if not (self.HasModule and self:HasModule("Shield")) then return end
	if (self.Buffer.ShieldHealth or 0) <= 0 then return end

	if not self.LvsJamBreakAt then
		self.LvsJamBreakAt = rollJamBreak()
		self.LvsJamUse = 0
	end

	self.LvsJamUse = (self.LvsJamUse or 0) + 1

	local step = (self.Buffer.ShieldMax or 60) / self.LvsJamBreakAt
	self.Buffer.ShieldHealth = math.max((self.Buffer.ShieldHealth or 0) - step, 0)
	self:SetNWInt("shield_health", math.max(math.floor(self.Buffer.ShieldHealth), 0))

	-- пока щит сбивается джаммером, он не должен восстанавливаться сам
	self.LvsShieldLocked = true
	self.LvsShieldLockHP = self.Buffer.ShieldHealth
	timer.Destroy("dronesrewrite_regen" .. self:EntIndex())

	if self.LvsJamUse < self.LvsJamBreakAt then return end

	self.LvsJamBreakAt = nil
	self.LvsJamUse = nil
	self.Buffer.ShieldHealth = 0
	self.LvsShieldDownUntil = CurTime() + SHIELD_REGEN_DELAY
	self:SetNWFloat("LvsShieldRestoreAt", self.LvsShieldDownUntil)

	if IsValid(attacker) and attacker:IsPlayer() then
		attacker:ChatPrint("[LVS Scout] Щит дрона спал — можно атаковать в полную силу")
		self:LvsNotifyShieldDown(attacker, true)
	end

	local tname = "lvs_shield_regen" .. self:EntIndex()

	timer.Create(tname, SHIELD_REGEN_DELAY, 1, function()
		if not IsValid(self) then return end

		-- модуль мог быть снят уничтожением: снимаем блокировку, иначе
		-- щит больше никогда не включится
		if not self:HasModule("Shield") then
			self.LvsShieldDownUntil = nil
			self.LvsShieldLocked = nil
			self.LvsShieldLockHP = nil
			self:SetNWFloat("LvsShieldRestoreAt", 0)
			self.LvsJamBreakAt = nil
			self.LvsJamUse = nil
			return
		end

		self.Buffer.ShieldHealth = self.Buffer.ShieldMax
		self:SetNWInt("shield_health", math.floor(self.Buffer.ShieldMax))
		self.LvsShieldDownUntil = nil
		self.LvsShieldLocked = nil
		self.LvsShieldLockHP = nil
		self:SetNWFloat("LvsShieldRestoreAt", 0)
		self.LvsJamBreakAt = nil
		self.LvsJamUse = nil
	end)
end

-- Джаммер без ограничения дистанции: игрок смотрит на дрон и видит его
function ENT:LvsJamRemote(attacker)
	self:EmitSound("ambient/energy/weld2.wav", 100, 255, 1)

	-- щита нет: джаммер бьёт корпус (иначе на дистанции не наносил урона вообще)
	if not (self.HasModule and self:HasModule("Shield")) or (self.Buffer.ShieldHealth or 0) <= 0 then
		local coef = 1

		if DRONES_REWRITE and DRONES_REWRITE.ServerCVars and DRONES_REWRITE.ServerCVars.DmgCoef then
			coef = DRONES_REWRITE.ServerCVars.DmgCoef:GetFloat()
		end

		local dmg = DamageInfo()
		dmg:SetDamage(math.random(45, 60) * coef)
		dmg:SetDamageType(DMG_SHOCK)
		dmg:SetAttacker(IsValid(attacker) and attacker or self)
		dmg:SetInflictor(self)
		self:TakeDamageInfo(dmg)

		self:LvsNotifyShieldDown(attacker)
		return
	end

	-- одно применение = одна попытка сбить щит
	self:LvsJammerDrain(attacker)
end

function ENT:OnTakeDamage(dmg)	-- Пули должны цеплять только видимые части (кости), а не пустоту внутри коробки
	if bit.band(dmg:GetDamageType(), DMG_BULLET) ~= 0 then
		local pos = dmg:GetDamagePosition()
		if not pos:IsZero() and not self:LvsHitVisiblePart(pos) then return end
	end

	local inflictor = dmg:GetInflictor()
	local isJammer = IsValid(inflictor) and inflictor:GetClass() == "weapon_drr_jammer"

	-- Джаммер не должен отключать дрон ни при каком состоянии щита
	if isJammer then self.LvsJamGrace = CurTime() + 0.5 end

	local attacker = dmg:GetAttacker()
	local shieldUp = self.HasModule and self:HasModule("Shield") and (self.Buffer.ShieldHealth or 0) > 0

	-- Щит уже спал: атакующему показываем время до восстановления
	if not shieldUp then self:LvsNotifyShieldDown(attacker) end

	if shieldUp then
		if IsValid(attacker) and attacker:IsPlayer() and CurTime() > (attacker.LvsShieldMsg or 0) then
			attacker.LvsShieldMsg = CurTime() + 1
			attacker:ChatPrint("[LVS Scout] Дрон защищён на 100% от любого урона")
		end

		local pos = dmg:GetDamagePosition()
		if not pos:IsZero() then ParticleEffect("blade_glow_drr", pos, Angle(0, 0, 0)) end
		self:EmitSound("ambient/energy/weld2.wav", 100, 255, 1)

		-- Щит тратится только джаммером DRR (два удара за применение)
		if isJammer then
			self.LvsJamNativeAt = CurTime()
			self:LvsJammerDrain(attacker)
		end

		return
	end

	-- Без отбрасывания от попаданий
	dmg:SetDamageForce(vector_origin)

	return self.BaseClass.OnTakeDamage(self, dmg)
end

-- Джаммер не отключает дрон: игнорируем его SetEnabled(false)
function ENT:SetEnabled(state)
	if not state and CurTime() < (self.LvsJamGrace or 0) then return end

	return self.BaseClass.SetEnabled(self, state)
end

-- Точка, куда смотрит камера пилота (та же, что у оружий DRR)
function ENT:GetAimPoint()
	local cam = self:GetCamera()
	if not IsValid(cam) then cam = self end

	-- свои прокси-хитбоксы не должны перекрывать прицел
	local filter = { cam, self }

	for _, h in ipairs(self.LvsHitboxes or {}) do
		if IsValid(h.ent) then filter[#filter + 1] = h.ent end
	end

	return util.TraceLine({
		start  = cam:GetPos(),
		endpos = cam:GetPos() + self.CamAngles:Forward() * 100000,
		filter = filter,
		mask   = MASK_SOLID,
	}).HitPos
end
function ENT:GetBoneAimOffset(boneID)
	local wpos = self:GetBonePosition(boneID)
	local target = (self:GetAimPoint() - wpos):Angle()
	return self:WorldToLocalAngles(target)
end

-- Голова смотрит в точку прицела
function ENT:UpdateHead()
	if not self.BoneIDs.Head then return end

	local off = self:GetBoneAimOffset(self.BoneIDs.Head)

	local target = Angle(
		math.Clamp(off.p, -PITCH_LIMIT, PITCH_LIMIT),
		math.Clamp(math.AngleDifference(off.y, 0), -YAW_LIMIT, YAW_LIMIT),
		0
	)

	local cur = self:GetManipulateBoneAngles(self.BoneIDs.Head) or Angle(0, 0, 0)
	self:ManipulateBoneAngles(self.BoneIDs.Head, LerpAngle(math.min(FrameTime() * HEAD_ROTATE_SPEED, 1), cur, target))
end

-- Камера DRR садится в голову
function ENT:UpdateCameraPos()
	local cam = self.Camera
	local bone = self.BoneIDs and self.BoneIDs.Head
	if not IsValid(cam) or not bone then return end

	local wpos, wang = self:GetBonePosition(bone)
	if not wpos or not wang then return end

	cam:SetLocalPos(self:WorldToLocal(wpos + wang:Forward() * CAM_OFFSET))
end

-- Щупальца в духе Crysis: тяжёлая волна по ВСЕМ костям модели,
-- инерция каждого сегмента, «живая» неравномерность и дышащие клешни
function ENT:UpdateTentacles()
	local t = CurTime()
	local dt = math.min(FrameTime(), 0.1)

	local vel = self:GetVelocity()
	local move = math.Clamp(vel:Length() / 600, 0, 1)

	self.TentacleCur = self.TentacleCur or {}
	self.ClawCur = self.ClawCur or {}

	-- при полёте щупальца отстают и тянутся назад
	local leanF, leanR = 0, 0

	if vel:LengthSqr() > 1 then
		local lv = self:WorldToLocal(self:GetPos() + vel)
		leanF = math.Clamp(lv.x * 0.0025, -6, 6)
		leanR = math.Clamp(lv.y * 0.0025, -6, 6)
	end

	for i, segs in pairs(self.LvsRopeBones or {}) do
		local seed = self["TentaclePhase" .. i]

		if not seed then
			seed = math.Rand(0, math.pi * 2)
			self["TentaclePhase" .. i] = seed
		end

		local n = math.max(#segs, 1)
		local freq = 0.55 + (i % 3) * 0.07
		local lag = 0.14 + (i % 4) * 0.05

		for idx, b in ipairs(segs) do
			local k = idx / n
			local ph = seed + t * TENTACLE_SPEED * freq - idx * 0.3

			-- у каждой кости своя мелкая гармоника: движение не механическое
			local jitter = math.sin(ph * 2.3 + idx * 1.7) * 0.15
				+ math.cos(ph * 0.9 + i) * 0.1

			-- амплитуда растёт к кончику квадратично
			local env = 0.18 + 1.15 * k * k
			local amp = TENTACLE_WAVE * (0.55 + 0.85 * move) * env

			local pitch = math.sin(ph) * amp * (1 + jitter)
				+ math.sin(ph * 0.47 + seed * 1.9) * amp * 0.35
				+ leanF * k * 1.6
			local yaw = math.sin(ph * 0.68 + seed * 1.3 + k * 1.6) * amp * 0.6
				+ math.sin(ph * 1.31 + i * 0.9) * amp * 0.18
				+ leanR * k * 1.6
			local roll = math.cos(ph * 0.92 + idx * 0.21) * amp * 0.2

			local target = Angle(
				math.Clamp(pitch, -TENTACLE_MAX_BEND, TENTACLE_MAX_BEND),
				math.Clamp(yaw, -TENTACLE_MAX_BEND, TENTACLE_MAX_BEND),
				math.Clamp(roll, -TENTACLE_MAX_BEND, TENTACLE_MAX_BEND))

			-- инерция: кончики догоняют позу медленнее основания
			local cur = self.TentacleCur[b.id] or target
			cur = LerpAngle(math.min(dt / (lag * (0.8 + k * 0.7)), 1), cur, target)

			self.TentacleCur[b.id] = cur
			self:ManipulateBoneAngles(b.id, cur)
		end
	end

	-- клешни и все фаланги, которые есть в модели
	for i, parts in pairs(self.LvsClawBones or {}) do
		local seed = self["TentaclePhase" .. i] or i

		for _, b in ipairs(parts) do
			local target, rate

			if b.part then
				local curl = 4 + b.part * 3.5
					+ math.sin(seed * 1.7 + t * 1.15 - b.part * 0.65) * (3 + b.part * 1.8)

				target = Angle(curl, 0, 0)
				rate = 0.16
			else
				-- основание клешни медленно раскрывается
				target = Angle(2 + math.sin(seed + t * 0.85) * 7, 0, 0)
				rate = 0.22
			end

			local cur = self.ClawCur[b.id] or target
			cur = LerpAngle(math.min(dt / rate, 1), cur, target)

			self.ClawCur[b.id] = cur
			self:ManipulateBoneAngles(b.id, cur)
		end
	end
end

-- Кость оружия смотрит в точку прицела
function ENT:UpdateWeaponAim()
	if not self.BoneIDs.Weapon then return end

	local off = self:GetBoneAimOffset(self.BoneIDs.Weapon)

	local target = Angle(
		math.Clamp(off.p, -PITCH_LIMIT, PITCH_LIMIT),
		math.Clamp(math.AngleDifference(off.y, 0), -YAW_LIMIT, YAW_LIMIT),
		0
	)

	local cur = self:GetManipulateBoneAngles(self.BoneIDs.Weapon) or Angle(0, 0, 0)
	self:ManipulateBoneAngles(self.BoneIDs.Weapon, LerpAngle(math.min(FrameTime() * ARM_ROTATE_SPEED, 1), cur, target))
end

-- Мировая точка начала луча (кость оружия)
-- Точка вылета (луч/осколки): аттачмент moac_muzzle, fallback — кость оружия
function ENT:GetCryoStart()
	local pos = self:LvsAttachmentPos("moac_muzzle")
	if pos then return pos end

	local bone = self.BoneIDs and self.BoneIDs.Weapon
	if bone then
		local p = self:GetBonePosition(bone)
		if p then return p end
	end

	return self:GetPos()
end
-- ИИ: скан сквозь стены, щит при контакте, атака только видимых целей
function ENT:LvsCanSee(e)
	local filter = { self }

	for _, h in ipairs(self.LvsHitboxes or {}) do
		if IsValid(h.ent) then filter[#filter + 1] = h.ent end
	end


	local cam = self:GetCamera()
	local origin = IsValid(cam) and cam:GetPos() or self:GetPos()

	local tr = util.TraceLine({
		start  = origin,
		endpos = e:LocalToWorld(e:OBBCenter()),
		filter = filter,
		mask   = MASK_SOLID,
	})

	return tr.Entity == e or tr.Fraction >= 0.98
end

-- Свободное направление: проверяем линию пути на 1200 юнитов.
-- Невидимые стены карты/скайбокс дают короткую трассу и отсекаются.
function ENT:LvsTraceFilter()
	local filter = { self }

	local cam = self:GetCamera()
	if IsValid(cam) then filter[#filter + 1] = cam end

	for _, hb in ipairs(self.LvsHitboxes or {}) do
		if IsValid(hb.ent) then filter[#filter + 1] = hb.ent end
	end

	return filter
end

-- Свободен ли путь с учётом габаритов дрона (в узких коридорах линия врёт)
function ENT:LvsPathClear(yaw, distance, filter)
	local origin = self:WorldSpaceCenter()
	local m = self:OBBMaxs()
	local r = math.max(m.x, m.y) * 0.9

	local tr = util.TraceHull({
		start  = origin,
		endpos = origin + Angle(0, yaw, 0):Forward() * distance,
		mins   = Vector(-r, -r, -m.z * 0.5),
		maxs   = Vector(r, r, m.z * 0.5),
		filter = filter or self:LvsTraceFilter(),
		mask   = MASK_SOLID,
	})

	return tr.Fraction >= 0.95, tr
end

-- Есть ли под точкой навигационная сетка (NavMesh / AI nodes)
function ENT:LvsOverNavArea(pos)
	if not navmesh or not navmesh.GetNearestNavArea then return true end

	local area = navmesh.GetNearestNavArea(pos, true, 600, false, true)

	return area ~= nil
end

function ENT:LvsFreeYaw(base, distance)
	distance = distance or 1200

	local order = { 0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180 }
	local bestYaw, bestFrac, firstClear
	local origin = self:WorldSpaceCenter()

	for _, off in ipairs(order) do
		local yaw = math.NormalizeAngle(base + off)
		local clear, tr = self:LvsPathClear(yaw, distance)

		if clear then
			-- приоритет направлениям, где внизу есть навигация: там ходят NPC
			local probe = origin + Angle(0, yaw, 0):Forward() * (distance * 0.6)

			local okNav, onNav = pcall(self.LvsNavMode, self)
			local navOk = okNav and onNav ~= 0

			if navOk then
				local okArea, area = pcall(self.LvsOverNavArea, self, probe)
				if okArea and area then return yaw end
			else
				return yaw
			end

			if not firstClear then firstClear = yaw end
		end

		if not bestFrac or tr.Fraction > bestFrac then bestFrac, bestYaw = tr.Fraction, yaw end
	end

	return firstClear or bestYaw
end

-- Отталкивание от соседних дронов: чем ближе, тем сильнее уводим курс
-- Расталкивание соседних дронов: суммарный вектор «от соседей»
function ENT:LvsSepPush(radius)
	radius = radius or 900

	local origin = self:WorldSpaceCenter()
	local push = Vector(0, 0, 0)
	local n = 0

	for _, e in ipairs(ents.FindByClass("lvs_scout_drr")) do
		if e ~= self and IsValid(e) then
			local d = origin - e:WorldSpaceCenter()
			local len = d:Length()

			if len > 1 and len < radius then
				push = push + (d / len) * ((radius - len) / radius)
				n = n + 1
			end
		end
	end

	if n == 0 then return end

	push.z = 0
	return push
end

-- Доворот курса от соседей: blend 0…1 (1 — уходим полностью, 0.45 — не бросаем цель)
function ENT:LvsSepYaw(base, blend)
	local push = self:LvsSepPush()

	if not push then return base end

	-- ровно друг над другом: уводим вбок
	if push:LengthSqr() < 0.01 then return math.NormalizeAngle(base + 90) end

	return math.NormalizeAngle(base + math.NormalizeAngle(push:Angle().y - base) * (blend or 1))
end

-- Оригинальный AI.CheckSide из DRR, но с фильтром своих прокси-хитбоксов
function ENT:LvsAiCheckSide(side, distance)
	local start = self:LocalToWorld(self:OBBCenter())

	local filter = { self }
	local cam = self:GetCamera()
	if IsValid(cam) then filter[#filter + 1] = cam end

	for _, h in ipairs(self.LvsHitboxes or {}) do
		if IsValid(h.ent) then filter[#filter + 1] = h.ent end
	end

	local tr = util.TraceLine({
		start  = start,
		endpos = start + side * (distance or 180),
		filter = filter,
	})

	return tr.Hit
end

-- Тяжёлая техника в цели не берётся вообще
-- ИИ не видит БТР как цель (не NPC/NextBot), остальную технику бьёт
-- с адаптивным уроном
local LVS_HEAVY_IGNORE = {
	mbn_apc_manager = true,
}

-- Порядок важности тяжёлой техники (чем больше вес, тем раньше выбирается)
local LVS_HEAVY_PRIORITY = {
	npc_strider = 5,
	npc_helicopter = 4,
	npc_combinegunship = 3,
	npc_hunter = 3,
	npc_combinedropship = 1,
}

-- Груз дропшипа: бьём груз, а не сам корабль
function ENT:LvsDropshipCargo(ship)
	if not IsValid(ship) then return end

	-- груз = живой NPC/NextBot на борту, а не любой дочерний проп
	for _, c in ipairs(ship:GetChildren()) do
		if IsValid(c) and c ~= ship
			and (c:IsNPC() or c:IsNextBot() or c:IsPlayer()) then
			return c
		end
	end
end

function ENT:LvsIsCargo(e)
	local p = IsValid(e) and e:GetParent()
	return IsValid(p) and p:GetClass() == "npc_combinedropship"
end

-- Не живая цель (груз/техника-проп): лучом не замораживается
function ENT:LvsIsPropTarget(e)
	return IsValid(e) and not (e:IsPlayer() or e:IsNPC() or e:IsNextBot())
end

-- Летающий/ближний враг Альянса (маньяки, сканеры, дроны) — по ним работаем пулемётом
function ENT:LvsIsFlyer(e)
	if not IsValid(e) then return false end
	if e.IS_DRONE then return true end

	if e:IsNPC() then
		local cls = e:GetClass()
		return cls == "npc_manhack" or cls == "npc_cscanner" or cls == "npc_clawscanner"
			or not e:IsOnGround()
	end

	return false
end

-- Муравьиные львы (лев, страж, рабочий) — работаем по ним только пулемётом
function ENT:LvsAntlion(e)
	if not IsValid(e) or not e:IsNPC() then return false end

	return string.find(e:GetClass(), "antlion", 1, true) ~= nil
end

-- Львов бьём из пулемёта, если класса нет в списке друзей из F3-меню
function ENT:LvsMgAllowed(e)
	if not IsValid(e) then return false end
	if not self:LvsAntlion(e) then return true end

	local friends = self.LvsFriendClasses or {}

	return not friends[e:GetClass()]
end

-- После оживления HP ниже порога: включаем щит как страховку
function ENT:LvsReviveShield()
	if not self.AddModule then return end
	if CurTime() < (self.LvsShieldDownUntil or 0) then return end
	if self:HasModule("Shield") and (self.Buffer and self.Buffer.ShieldHealth or 0) > 0 then return end

	-- AddModule ничего не возвращает: проверяем результат по HasModule
	self:AddModule("Shield")

	if not self:HasModule("Shield") then return end

	if self.Buffer then
		self.Buffer.ShieldMax = self.Buffer.ShieldMax or 60
		self.Buffer.ShieldHealth = self.Buffer.ShieldMax
		self:SetNWInt("shield_health", math.floor(self.Buffer.ShieldMax))
		self.LvsShieldLocked = nil
		self.LvsShieldLockHP = nil
	end
end

-- Щит активен и держит урон
function ENT:LvsShieldUp()
	return self.HasModule and self:HasModule("Shield") and (self:GetNWInt("shield_health") or 0) > 0
end

-- Автопилот: преследование как «AI Follow enemy» + объезд из AI MovingCore
function ENT:LvsAiMove()
	local tgt = self.LvsAiTarget
	if not IsValid(tgt) then return end
	if not IsValid(self:GetPhysicsObject()) then return end

	-- новая цель — старый обходной курс больше не нужен
	if self.LvsAiPathTarget ~= tgt then
		self.LvsAiPathTarget = tgt
		self.LvsAiPathBlocked = nil
		self.LvsAiPathYaw = nil
	end

	if self.LvsReposTarget ~= tgt then
		self.LvsReposTarget = tgt
		self.LvsEffectiveAt = CurTime()
		self.LvsReposAt = nil
	end

	-- объезд как в AI.MovingCore (DRR), с фильтром своих хитбоксов.
	-- Трассы дорогие — считаем 15 раз/с, клавиши жмём по кешу каждый тик.
	local nowT = CurTime()

	if nowT > (self.LvsAiAvoidAt or 0) then
		self.LvsAiAvoidAt = nowT + 1/15

		-- при 2500 скорости формула DRR даёт трассы в километры и дрон
		-- начинает дёргаться между стенами — ограничиваем
		local num  = math.Clamp(1.5 + self:GetPhysicsObject():GetVelocity():Length() * 0.01, 1.5, 4)
		local side = self:OBBMaxs().x * num
		local vert = self:OBBMaxs().z * 1.5
		local wide = self:OBBMaxs().y * num

		self.LvsAiAvoid = {
			back  = self:LvsAiCheckSide(-self:GetForward(), side),
			front = self:LvsAiCheckSide(self:GetForward(), side),
			below = self:LvsAiCheckSide(-self:GetUp(), vert),
			above = self:LvsAiCheckSide(self:GetUp(), vert),
			left  = self:LvsAiCheckSide(-self:GetRight(), wide),
			right = self:LvsAiCheckSide(self:GetRight(), wide),
		}
	end

	local av = self.LvsAiAvoid

	if av then
		if av.back  then self:ClickKey("Forward") end
		if av.front then self:ClickKey("Back") end
		if av.below then self:ClickKey("Up") end
		if av.above then self:ClickKey("Down") end
		if av.left  then self:ClickKey("StrafeRight") end
		if av.right then self:ClickKey("StrafeLeft") end
	end

	local drpos = self:LocalToWorld(self:OBBCenter())
	local opos  = tgt:LocalToWorld(tgt:OBBCenter())
	local to    = opos - drpos
	local hdist = Vector(to.x, to.y, 0):Length()
	local st    = opos.z - drpos.z
	-- проверка линии пути к цели: если она проходит через стену карты,
	-- курс пересобирается по свободному направлению
	local aimYaw = to:Angle().y

	if hdist > 400 and nowT > (self.LvsAiPathAt or 0) then
		self.LvsAiPathAt = nowT + 0.5

		local origin = self:WorldSpaceCenter()
		local dist = math.min(hdist, 900)
		local filter = { self }

		for _, hb in ipairs(self.LvsHitboxes or {}) do
			if IsValid(hb.ent) then filter[#filter + 1] = hb.ent end
		end

		local tr = util.TraceLine({
			start  = origin,
			endpos = origin + Angle(0, aimYaw, 0):Forward() * dist,
			filter = filter,
			mask   = MASK_SOLID,
		})

		self.LvsAiPathBlocked = tr.Fraction < 0.95
	end

	if self.LvsAiPathBlocked then
		if nowT > (self.LvsAiPathYawAt or 0) then
			self.LvsAiPathYawAt = nowT + 0.5
			self.LvsAiPathYaw = self:LvsFreeYaw(aimYaw, 1200) or aimYaw
		end

		aimYaw = self.LvsAiPathYaw or aimYaw
	else
		self.LvsAiPathYaw = nil
	end

	-- несколько секунд без попаданий: цель за укрытием и снаряды уходят в стену —
	-- смещаемся вбок и выше, чтобы открыть линию огня
	if CurTime() - (self.LvsEffectiveAt or 0) > 5 then
		if CurTime() > (self.LvsReposAt or 0) then
			self.LvsReposAt = CurTime() + 3
			self.LvsEffectiveAt = CurTime()
			self.LvsReposYaw = math.NormalizeAngle(self:GetAngles().y
				+ (math.random() < 0.5 and 85 or -85))
			self.LvsReposZ = drpos.z + math.random(150, 450)
		end

		if CurTime() < self.LvsReposAt then
			aimYaw = self:LvsFreeYaw(self.LvsReposYaw or aimYaw, 1200) or aimYaw

			if (self.LvsReposZ or drpos.z) - drpos.z > 60 then self:ClickKey("Up") end
		end
	end

	-- в бою уводим курс от соседей лишь частично, иначе дрон бросает цель
	aimYaw = self:LvsSepYaw(aimYaw, 0.45)

	-- и физически расходимся: стрейф в сторону от соседа
	local sepPush = self:LvsSepPush(600)

	if sepPush then
		local side = sepPush:Dot(self:GetRight())

		if sepPush:Length() > 0.4 then
			self:ClickKey(side > 0 and "StrafeRight" or "StrafeLeft")
		end

		if sepPush:Length() > 0.7 then self:ClickKey("Back") end
	end

	local check = math.NormalizeAngle(self:GetAngles().y - aimYaw)

	-- «зрение»: 40 Гц вблизи, 15 Гц издалека — не видим, подходим и поднимаемся
	if CurTime() > (self.LvsAiSeeAt or 0) then
		self.LvsAiSeeAt = CurTime() + ((hdist < 1200) and 1/40 or 1/15)
		self.LvsAiSee = self:LvsCanSee(tgt)
	end

	-- дистанция адаптивная. Летающие и ближние враги (маньяки Альянса,
	-- сканеры, муравьиные львы) — держим дальше, чтобы не достали в упор
	local flying = self:LvsIsFlyer(tgt)

	local pref = self.LvsAiStandoff or 1400

	-- свой радиус удержания у каждого дрона: иначе все висят на одной дистанции
	if not self.LvsStandoffJitter then self.LvsStandoffJitter = math.random(-300, 300) end
	pref = pref + self.LvsStandoffJitter
	if flying then pref = math.max(pref, self.LvsAiFlyStandoff or 1900) end
	if not self.LvsAiSee then pref = math.max(600, pref * 0.55) end
	pref = math.min(pref, (self.CryoRange or 2048) * (flying and 0.9 or 0.7))

	-- далеко — ускоряемся, как AI Follow owner в DRR
	if hdist > 1200 then self:ClickKey("Sprint") end

	-- сближаемся по горизонтали, высоту держим отдельно (иначе встаёт под целью).
	-- Направление фиксируется на 0.4 с: без этого дрон дёргается вперёд-назад
	-- вокруг дистанции удержания
	local nowPos = CurTime()

	if check > -40 and check < 40 and nowPos > (self.LvsApproachAt or 0) then
		if hdist > pref * 1.1 then
			self.LvsApproach = 1
			self.LvsApproachAt = nowPos + 0.4
		elseif hdist < pref * 0.9 then
			self.LvsApproach = -1
			self.LvsApproachAt = nowPos + 0.4
		else
			self.LvsApproach = 0
		end
	end

	if check > -40 and check < 40 then
		if self.LvsApproach == 1 then
			self:ClickKey("Forward")
		elseif self.LvsApproach == -1 then
			self:ClickKey("Back")
		end
	end

	self:ControlMotion("Left", "Right", check, -16, 16)

	-- высота: максимально высоко, но чтобы угол вниз влезал в PitchMin;
	-- без линии видимости поднимаемся ещё выше — обзор через укрытие
	local pitchDown = math.abs(math.min(self.PitchMin or -30, 0))
	local maxOffset = hdist * math.tan(math.rad(math.max(pitchDown - 5, 5)))
	local cap       = self.LvsAiAltitudeOffset or 2000
	-- не опускаемся к земле даже вплотную к цели
	local offset    = math.Clamp(math.min(maxOffset, cap), self.LvsMinAltitude or 800, cap)

	if not self.LvsAiSee then offset = math.min(offset + 250, cap) end

	-- личная высота: дроны не выстраиваются в одну линию над целью
	if not self.LvsAltJitter then self.LvsAltJitter = math.random(-250, 350) end
	offset = math.Clamp(offset + self.LvsAltJitter, self.LvsMinAltitude or 800, cap)

	local wantZ = opos.z + offset

	if wantZ - drpos.z > 40 then self:ClickKey("Up")
	elseif wantZ - drpos.z < -40 then self:ClickKey("Down") end

	-- цель слишком высоко для PitchMax — отходим, чтобы угол влез
	if self.AllowPitchRestrictions then
		local lp = self:WorldToLocalAngles(to:Angle()).p
		if lp > self.PitchMax - 5 then self:ClickKey("Back") end
	end
end

-- Точка прицеливания: голова NPC/игрока, иначе центр OBB
-- Патруль в покое: медленно летает, осматривается и ищет цели
-- Режим привязки патруля: 0 — выкл, 1 — NavMesh, 2 — AI Nodes
function ENT:LvsNavMode()
	if not ConVarExists("lvs_scout_nav_mode") then
		CreateConVar("lvs_scout_nav_mode", "1", FCVAR_ARCHIVE,
			"Привязка патруля к навигации: 0 — выкл, 1 — NavMesh, 2 — AI Nodes")
	end

	return math.Clamp(GetConVar("lvs_scout_nav_mode"):GetInt(), 0, 2)
end

-- Ближайшая AI-нода (info_node*) в радиусе
function ENT:LvsNodeCenter(pos, radius)
	local now = CurTime()

	if not LvsNodeCache or now > (LvsNodeCacheAt or 0) then
		LvsNodeCache = ents.FindByClass("info_node*") or {}
		LvsNodeCacheAt = now + 10
	end

	local r2 = radius * radius
	local pick

	for _, n in ipairs(LvsNodeCache) do
		if IsValid(n) and n:GetPos():DistToSqr(pos) <= r2 then
			if not pick or math.random() < 0.35 then pick = n:GetPos() end
		end
	end

	return pick
end

-- Навигация: зона под точкой (луч вниз, затем поиск NavMesh / AI nodes)
function ENT:LvsNavBelow(pos)
	if not navmesh or not navmesh.GetNearestNavArea then return end

	local tr = util.TraceLine({
		start  = pos,
		endpos = pos - Vector(0, 0, 6000),
		filter = self,
		mask   = MASK_SOLID_BRUSHONLY,
	})

	local ground = tr.Hit and tr.HitPos or pos

	return navmesh.GetNearestNavArea(ground, false, 300, false, true)
end

-- Случайная навигационная зона в радиусе: центр, куда лететь патрулём
function ENT:LvsRandomNavCenter(pos, radius)
	if not navmesh or not navmesh.GetAllNavAreas then return end

	local now = CurTime()

	if not LvsNavCache or now > (LvsNavCacheAt or 0) then
		LvsNavCache = navmesh.GetAllNavAreas() or {}
		LvsNavCacheAt = now + 10
	end

	local count = #LvsNavCache
	if count == 0 then return end

	local r2 = radius * radius
	local pick

	for _ = 1, 40 do
		local area = LvsNavCache[math.random(count)]
		local c = area and area.GetCenter and area:GetCenter()

		if c and c:DistToSqr(pos) <= r2 then
			pick = c

			if math.random() < 0.5 then break end
		end
	end

	return pick
end

function ENT:LvsAiPatrol()
	if not IsValid(self:GetPhysicsObject()) then return end

	local now = CurTime()

	-- смена режима применяется сразу: сбрасываем текущую цель патруля
	local mode = self:LvsNavMode()

	if self.LvsNavModeLast ~= mode then
		self.LvsNavModeLast = mode
		self.LvsPatrolPos = nil
		self.LvsPatrolAt = 0
		self.LvsPatrolYaw = nil
		self.LvsPatrolTurnAt = 0
	end

	-- дошли до навигационной зоны: сразу выбираем следующую
	if self.LvsPatrolPos and self.LvsPatrolPos:DistToSqr(self:GetPos()) < 350 * 350 then
		self.LvsPatrolPos = nil
		self.LvsPatrolAt = 0
	end

	-- режим 0: привязки нет, цель патруля не удерживаем
	if mode == 0 then self.LvsPatrolPos = nil end

	if now > (self.LvsPatrolAt or 0) then
		self.LvsPatrolAt = now + math.random(3, 6)

		-- патрулируем по навигации: летим в центр случайной NavMesh-зоны;
		-- если дрон вне навигации — возвращаемся к ближайшей зоне
		local myPos = self:GetPos()
		local navMode = mode
		local overNav, navCenter

		if navMode ~= 0 then
			local okA, area = pcall(self.LvsNavBelow, self, myPos)
			if okA then overNav = area end

			local okB, center = pcall(self.LvsRandomNavCenter, self, myPos, 4500)
			if okB then navCenter = center end

			if navMode == 2 then
				local okC, node = pcall(self.LvsNodeCenter, self, myPos, 4500)
				if okC and node then navCenter = node end
			end

			if not overNav then
				local okD, near = pcall(function()
					return navmesh and navmesh.GetNearestNavArea
						and navmesh.GetNearestNavArea(myPos, true, 8000, false, true)
				end)

				if okD and near and near.GetCenter then navCenter = near:GetCenter() end
			end
		end

		if navCenter then
			self.LvsPatrolPos = navCenter
		else
			self.LvsPatrolPos = nil
		end

		local want

		if self.LvsPatrolPos then
			want = math.NormalizeAngle((self.LvsPatrolPos - myPos):Angle().y)
		else
			want = math.NormalizeAngle(self:GetAngles().y + math.random(-120, 120))
		end

		-- новый курс принимаем только если линия пути свободна
		self.LvsPatrolYaw = self:LvsFreeYaw(want, 1200) or want

		-- патрульная высота считается от земли: от текущей точки дрон сползал вниз
		local ground = self.LvsGroundZ or myPos.z

		-- летим над самой зоной: её центр по Z — уровень пола
		if self.LvsPatrolPos then ground = self.LvsPatrolPos.z end
		local lo = self.LvsPatrolAltitudeMin or 700
		local hi = self.LvsPatrolAltitudeMax or 1200

		-- под сводом целимся ниже потолка, даже если он ниже рабочей высоты
		if self.LvsCeilZ then
			local room = math.floor(self.LvsCeilZ - ground - 150)

			if room < lo then
				hi = math.max(room, 150)
				lo = math.max(150, hi - 250)
			else
				hi = math.min(hi, room)
			end
		end

		self.LvsPatrolZ = ground + math.random(lo, hi)
	end

	-- медленный разворот в выбранную сторону
	self.LvsPatrolYaw = self:LvsSepYaw(self.LvsPatrolYaw or self:GetAngles().y)

	local check = math.NormalizeAngle(self:GetAngles().y - (self.LvsPatrolYaw or self:GetAngles().y))
	self:ControlMotion("Left", "Right", check, -10, 10)

	-- препятствие впереди проверяем 3 раза в секунду и меняем курс
	if now > (self.LvsPatrolTraceAt or 0) then
		self.LvsPatrolTraceAt = now + 0.3

		local phys = self:GetPhysicsObject()
		local speed = IsValid(phys) and phys:GetVelocity():Length() or 0
		self.LvsPatrolSpeed = speed

		-- смотрим вперёд тем дальше, чем быстрее летим: 0.3 с запаса
		self.LvsPatrolBlocked = self:LvsAiCheckSide(self:GetForward(),
			math.max(self:OBBMaxs().x * 3, speed * 0.3))

		if self.LvsPatrolBlocked then
			self.LvsPatrolHits = (self.LvsPatrolHits or 0) + 1
		else
			self.LvsPatrolHits = 0
		end
	end

	if self.LvsPatrolBlocked then
		-- гасим ход, иначе на 2500 юнитов/с дрон догоняет собственную реакцию
		if (self.LvsPatrolSpeed or 0) > 700 then self:ClickKey("Back") end

		-- выбираем свободное направление (в т.ч. от невидимых стен карты), а не «в стену»
		if now > (self.LvsPatrolTurnAt or 0) then
			self.LvsPatrolTurnAt = now + 0.5
			self.LvsPatrolYaw = self:LvsFreeYaw(self:GetAngles().y, 1200)
		end

		-- застряли надолго: разворот и подъём, чтобы выйти из угла/от стены
		if (self.LvsPatrolHits or 0) >= 6 then
			self.LvsPatrolHits = 0
			self.LvsPatrolYaw = math.NormalizeAngle(self:GetAngles().y + 180)
			self.LvsPatrolZ = math.max(
				self:GetPos().z + math.random(100, 250),
				(self.LvsGroundZ or self:GetPos().z) + (self.LvsPatrolAltitudeMin or 700))
			self:ClickKey("Up")
		end
	elseif math.abs(check) < 25 then
		self:ClickKey("Forward")
	end

	-- землю под собой проверяем редко (дорогая трасса), с учётом перф-режима
	if now > (self.LvsPatrolGroundAt or 0) then
		self.LvsPatrolGroundAt = now + (self:LvsPerf() and 0.25 or 0.1)
		self.LvsPatrolGround = self:LvsAiCheckSide(-self:GetUp(), 200)
	end

	-- держим высоту патруля и не прижимаемся к земле
	local dz = (self.LvsPatrolZ or self:GetPos().z) - self:GetPos().z

	if dz > 60 or self.LvsPatrolGround then self:ClickKey("Up")
	elseif dz < -60 then self:ClickKey("Down") end
end

local LVS_HEAD_BONES = { "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Head", "Head", "head" }

function ENT:LvsAimPoint(e)
	if not IsValid(e) then return end

	if e:IsPlayer() or e:IsNPC() or e:IsNextBot() then
		for _, name in ipairs(LVS_HEAD_BONES) do
			local b = e:LookupBone(name)

			if b and b >= 0 then
				local p = e:GetBonePosition(b)
				if p then return p end
			end
		end

		if e:IsPlayer() then return e:GetShootPos() end
	end

	return e:LocalToWorld(e:OBBCenter())
end

-- Наведение каждый тик (цель движется — при 0.5 с прицел отставал)
function ENT:LvsAiAimNow()
	local tgt = self.LvsAiTarget

	if not IsValid(tgt) then
		self.LvsAimAligned = false
		return
	end

	local cam = self:GetCamera()
	local origin = IsValid(cam) and cam:GetPos() or self:GetPos()

	local center = self:LvsAimPoint(tgt) or tgt:LocalToWorld(tgt:OBBCenter())

	-- в режиме пулемёта прицел ведём в точку упреждения: иначе камера
	-- отстаёт от цели и осколки идут за моделью
	if self.LvsAttackMode == 1 and self.LvsLeadPoint then
		center = self:LvsLeadPoint(tgt, origin, 7000) or center
	end

	local dir = (center - origin):GetNormal()

	if dir:IsZero() then return end

	-- во время манёвра прицел не замораживаем: иначе направление уходит от цели
	-- и дрон не может стрелять, пока уклоняется

	-- ограничения как в DRR: не выходим за PitchMin/Max и YawMin/Max
	local ang = self:WorldToLocalAngles(dir:Angle())
	local rawP, rawY = ang.p, ang.y

	local restrict = not (DRONES_REWRITE and DRONES_REWRITE.ServerCVars
		and DRONES_REWRITE.ServerCVars.NoCameraRestrictions
		and DRONES_REWRITE.ServerCVars.NoCameraRestrictions:GetBool())

	if restrict then
		if self.AllowPitchRestrictions then
			ang.p = math.Clamp(ang.p, self.PitchMin, self.PitchMax)
		end
		if self.AllowYawRestrictions then
			ang.y = math.Clamp(ang.y, self.YawMin, self.YawMax)
		end
	end

	-- стреляем только когда после обрезки прицел реально смотрит на цель
	self.LvsAimAligned = math.abs(rawP - ang.p) < 2 and math.abs(rawY - ang.y) < 2

	local want = self:LocalToWorldAngles(ang)

	-- сглаживаем направление, но при манёвре/стрейфе наводим точно:
	-- иначе прицел отстаёт от цели и пули идут мимо
	local dodging = self.LvsDodgeUntil and CurTime() < self.LvsDodgeUntil

	if not dodging and self.LvsAimSmooth then
		-- по движущейся цели доворачиваем быстрее, иначе прицел плывёт
		local vel = self:LvsTargetVel(tgt)
		local factor = vel:Length() > 120 and 0.8 or 0.5

		self.LvsAimSmooth = LerpVector(factor, self.LvsAimSmooth, want:Forward()):GetNormal()
		self.LvsAutoAngles = self.LvsAimSmooth:Angle()
	else
		self.LvsAimSmooth = want:Forward()
		self.LvsAutoAngles = want
	end

	-- в сеть — не чаще 15 раз/с, клиент дополнительно сглаживает
	if CurTime() > (self.LvsDirSentAt or 0) then
		self.LvsDirSentAt = CurTime() + 1/15
		self:SetNWVector("LvsAutoDir", self.LvsAutoAngles:Forward())
	end
end

-- NPC с шаговым движением (antlion и др.) отдают GetVelocity() = 0,
-- поэтому скорость считаем сами по смещению позиции
function ENT:LvsTargetVel(tgt)
	if not IsValid(tgt) then return vector_origin end

	self.LvsVelTrack = self.LvsVelTrack or setmetatable({}, { __mode = "k" })

	local pos = tgt:WorldSpaceCenter()
	local now = CurTime()
	local rec = self.LvsVelTrack[tgt]

	if not rec then
		self.LvsVelTrack[tgt] = { pos = pos, t = now, vel = vector_origin }
		return tgt:GetVelocity() or vector_origin
	end

	local dt = now - rec.t

	-- окно замера шире, сглаживание сильнее: иначе прицел качает
	if dt >= 0.15 then
		local raw = (pos - rec.pos) / dt

		-- вертикаль не учитываем: у львов она скачет на склонах
		raw.z = 0

		if raw:Length() > 600 then raw = raw:GetNormal() * 600 end

		rec.vel = rec.vel and LerpVector(0.25, rec.vel, raw) or raw
		rec.pos, rec.t = pos, now
	end

	local v = tgt:GetVelocity() or vector_origin

	if v:Length() < 5 then v = rec.vel or vector_origin end

	return v
end

-- Точка упреждения: где цель окажется, пока осколок до неё летит
function ENT:LvsLeadPoint(tgt, start, speed)
	if not IsValid(tgt) then return end

	-- центр габарита, а не кость головы: у мелких NPC голова крошечная,
	-- и даже верное упреждение уходило мимо тела
	-- чуть выше центра габарита: у земли мешают склоны и кочки
	local center = tgt:WorldSpaceCenter() + Vector(0, 0, 12)
	local vel = self:LvsTargetVel(tgt)

	if vel:LengthSqr() < 1 then return center end

	speed = speed or 7000

	local point = center

	-- три итерации: время полёта зависит от самой точки упреждения
	for _ = 1, 3 do
		local t = (point - start):Length() / speed
		point = center + vel * t
	end

	-- не уводим прицел за спину цели при резком рывке
	local maxLead = vel:Length() * 0.5

	if (point - center):Length() > maxLead then
		point = center + (point - center):GetNormal() * maxLead
	end

	return point
end

-- Перф-режим: lvs_scout_perf 1 — экономные частоты, 0 — полные
function ENT:LvsPerf()
	if not ConVarExists("lvs_scout_perf") then
		CreateConVar("lvs_scout_perf", "1", FCVAR_ARCHIVE)
	end

	return GetConVar("lvs_scout_perf"):GetBool()
end

-- Есть ли игроки рядом: без них логику дрона считать незачем
function ENT:LvsNearPlayers(radius)
	local now = CurTime()

	if now < (self.LvsNearAt or 0) then return self.LvsNear end

	self.LvsNearAt = now + 1
	self.LvsNear = false

	local r2 = radius * radius
	local pos = self:GetPos()

	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and p:GetPos():DistToSqr(pos) <= r2 then
			self.LvsNear = true
			break
		end
	end

	return self.LvsNear
end

-- Кеш списка кандидатов на все наши дроны: ents.GetAll() не дёргаем каждые 0.5 с
local LvsTargetCache, LvsTargetCacheAt = nil, 0

function ENT:LvsAiTargets()
	if not LvsTargetCache or CurTime() > LvsTargetCacheAt then
		local list = { }

		for _, e in ipairs(ents.GetAll()) do
			if IsValid(e) and (e:IsPlayer() or e:IsNPC() or e:IsNextBot() or e.IS_DRONE) then
				list[#list + 1] = e
			end
		end

		LvsTargetCache = list
		LvsTargetCacheAt = CurTime() + 0.5
	end

	return LvsTargetCache
end

function ENT:LvsAiScan()
	-- по умолчанию модуль выключен: до включения дрон сам ничего не делает
	if not self.LvsAutonomous then return end

	local cam = self:GetCamera()
	local origin = IsValid(cam) and cam:GetPos() or self:GetPos()
	local visible, best, contact = nil, math.huge, false

	-- дальность обнаружения: своя, сильно больше стандартного радиуса DRR
	if not ConVarExists("lvs_scout_ai_range") then
		CreateConVar("lvs_scout_ai_range", "16000", FCVAR_ARCHIVE, "Радиус обнаружения целей ИИ: 0, inf или max = вся карта")
	end

	if not ConVarExists("lvs_scout_debug") then
		CreateConVar("lvs_scout_debug", "0", FCVAR_ARCHIVE, "Отладка ИИ дрона")
	end

	if not ConVarExists("lvs_scout_engage_range") then
		CreateConVar("lvs_scout_engage_range", "0", FCVAR_ARCHIVE,
			"Дистанция боя: по умолчанию без лимита; число ограничивает огонь, но не поиск")
	end

	local cv = GetConVar("lvs_scout_ai_range")
	local cvRadius = cv:GetInt()
	local cvText = string.lower(string.Trim(cv:GetString()))

	-- 0, INF, MAX или ALL = вся карта: кандидаты и так берутся из
	-- ents.GetAll(), поэтому расстояние фактически не ограничиваем
	local unlimited = cvRadius == 0 or cvText == "inf" or cvText == "infinite"
		or cvText == "max" or cvText == "all"

	local radius

	if unlimited then
		radius = 1000000
	else
		radius = math.max(cvRadius,
			IsValid(self.Owner) and self.Owner:GetInfoNum("dronesrewrite_ai_radius", 3000) or 3000)
	end

	local maxDist = radius * radius

	-- дистанция, на которой дрон реально стреляет: поиск и огонь разделены,
	-- иначе при inf дрон расстреливал цели на другом конце карты
	local engageCv = GetConVar("lvs_scout_engage_range")
	local engageInt = engageCv and engageCv:GetInt() or 0
	local engageText = engageCv and string.lower(string.Trim(engageCv:GetString())) or "3000"
	local engageOpen = engageInt == 0 or engageText == "inf" or engageText == "infinite"
		or engageText == "max" or engageText == "all"
	local engageDist = engageOpen and maxDist or math.min(engageInt, radius) ^ 2

	-- цели, которые уже держат другие дроны: их не перебиваем
	local claimed = {}

	local myPos = self:GetPos()

	for _, d in ipairs(ents.FindByClass("lvs_scout_drr")) do
		if d ~= self and IsValid(d) and d.LvsAutonomous and IsValid(d.LvsAiTarget)
			and d:GetPos():DistToSqr(myPos) <= 8000 * 8000 then
			claimed[d.LvsAiTarget] = true
		end
	end

	local function valid(e)
		if not IsValid(e) or e == self then return false end
		if e:GetClass() == "lvs_scout_drr" then return false end
		if self.LvsFriendClasses then
			if self.LvsFriendClasses[e:GetClass()] then return false end

			-- дружественные игроки хранятся как @STEAMID
			if e:IsPlayer() and self.LvsFriendClasses["@" .. e:SteamID()] then return false end
		end
		if claimed[e] then return false end
		if not (e:IsPlayer() or e:IsNPC() or e:IsNextBot() or e.IS_DRONE) then return false end
		if e:IsPlayer() and IsValid(e:GetNWEntity("DronesRewriteDrone")) then return false end

		-- Правила как в DRR, но без его лимита дистанции: ShouldAttack режет
		-- по клиентскому конвару владельца (dronesrewrite_ai_radius, 3000)
		local owner = IsValid(self.Owner) and self.Owner or nil

		if e:IsNPC() then
			if (e:Health() or 0) <= 0 then return false end
			if owner and owner:GetInfoNum("dronesrewrite_ai_noattacknpcs", 0) ~= 0 then return false end
			if self.IsEnemy and not self:IsEnemy(e:GetClass()) then return false end
		elseif e:IsPlayer() then
			if e == owner or e == self:GetDriver() then return false end
			if (e:Health() or 0) <= 0 then return false end
			if owner and owner:GetInfoNum("dronesrewrite_ai_noattackplayers", 0) ~= 0 then return false end
		end

		if owner and owner.dronesrewrite_friends
			and table.HasValue(owner.dronesrewrite_friends, e:EntIndex()) then
			return false
		end

		return e ~= self.Owner and e ~= self:GetOwner() and e ~= self:GetDriver()
	end

	-- липкая цель: не мечемся между врагами, иначе никто не умирает
	local cur = self.LvsAiTarget

	if IsValid(cur) and (LVS_HEAVY_IGNORE[cur:GetClass()] or self:LvsIsCargo(cur)) then
		cur = nil
	end

	-- дропшип без груза целью не считается
	if IsValid(cur) and cur:GetClass() == "npc_combinedropship"
		and not IsValid(self:LvsDropshipCargo(cur)) then
		cur = nil
	end

	if (valid(cur) or self:LvsIsCargo(cur))
		and (self:LvsIsCargo(cur) or cur.IS_DRONE or cur.Health == nil or cur:Health() > 0) then
		local d = origin:DistToSqr(cur:LocalToWorld(cur:OBBCenter()))

		if d <= maxDist then
			if self:LvsCanSee(cur) then
				self.LvsAiTargetSeen = CurTime()
			end

			-- до 2 с без линии видимости держим прежнюю цель
			if CurTime() - (self.LvsAiTargetSeen or 0) <= 2 then
				visible, best = cur, d
			end
		end
	end

	-- приоритет тяжёлой техники (настройка LvsHeavyHighPriority в shared.lua)
	if self.LvsHeavyHighPriority then
		local heavyPick, heavyPri, heavyDist

		for cls, pri in pairs(LVS_HEAVY_PRIORITY) do
			for _, e in ipairs(ents.FindByClass(cls)) do
				if not IsValid(e) or e == self or LVS_HEAVY_IGNORE[cls] then continue end
				if e == self.Owner or e == self:GetDriver() then continue end

				if cls == "npc_combinedropship" and not IsValid(self:LvsDropshipCargo(e)) then
					continue
				end
				if (e:IsNPC() or e:IsNextBot() or e.IS_DRONE) and not valid(e) then continue end

				local d = origin:DistToSqr(e:LocalToWorld(e:OBBCenter()))

				if d <= maxDist and self:LvsCanSee(e) then
					if not heavyPri or pri > heavyPri or (pri == heavyPri and d < heavyDist) then
						heavyPick, heavyPri, heavyDist = e, pri, d
					end
				end
			end
		end

		if IsValid(heavyPick) then
			if heavyPick:GetClass() == "npc_combinedropship" then
				local cargo = self:LvsDropshipCargo(heavyPick)

				if IsValid(cargo) then heavyPick = cargo end
			end

			visible, best = heavyPick, heavyDist
			contact = true
			self.LvsAiTargetSeen = CurTime()
		end
	end

	for _, raw in ipairs(self.LvsAiTargets()) do
		if not IsValid(raw) then continue end
		if LVS_HEAVY_IGNORE[raw:GetClass()] or self:LvsIsCargo(raw) then continue end

		-- с грузом бьём груз, без груза дропшип не цель
		if raw:GetClass() == "npc_combinedropship" then
			raw = self:LvsDropshipCargo(raw)

			if not IsValid(raw) then continue end
		end

		local e = raw

		if not valid(e) then
			continue
		end

		local center = e:LocalToWorld(e:OBBCenter())
		local d = origin:DistToSqr(center)

		if d <= maxDist then
			contact = true

			if not visible and d < best and d <= engageDist and self:LvsCanSee(e) then
				best = d
				visible = e
				self.LvsAiTargetSeen = CurTime()
			end
		end
	end

	-- сам дропшип никогда не цель: только его груз
	if IsValid(visible) and visible:GetClass() == "npc_combinedropship" then
		visible = nil
	end

	if GetConVar("lvs_scout_debug"):GetBool() then
		local enemies, npcs = 0, 0

		for _, x in ipairs(self:LvsAiTargets()) do
			if IsValid(x) and x:IsNPC() then
				npcs = npcs + 1
				if self.IsEnemy and self:IsEnemy(x:GetClass()) then enemies = enemies + 1 end
			end
		end

		print(string.format("[LVS] scan: cand=%d npc=%d enemyNPC=%d contact=%s target=%s radius=%d engage=%d ignoreNPC=%s shouldIgnore=%s",
			#self:LvsAiTargets(), npcs, enemies, tostring(contact), tostring(visible), cvRadius,
			math.floor(math.sqrt(engageDist)),
			tostring(DRONES_REWRITE and DRONES_REWRITE.ServerCVars and DRONES_REWRITE.ServerCVars.NPCIgnore
				and DRONES_REWRITE.ServerCVars.NPCIgnore:GetBool()),
			tostring(self.ShouldNpcsIgnore)))
	end

	self.LvsScanContact = contact

	-- при виде врага — красная расцветка, иначе возвращаем обычную
	local red = visible ~= nil

	if self.LvsAiRed ~= red then
		self.LvsAiRed = red
		self:LvsSetSkin(red and 1 or 0)
	end

	-- прицеливание и огонь по видимой цели
	if visible then
		-- разнообразие: 1 — только пулемёт, 2 — луч, затем добивание пулемётом
		if self.LvsAiTarget ~= visible then
			self.LvsAttackMode = math.random(1, 2)
			self.LvsAimSmooth = nil

			-- короткая задержка взятия на прицел: не расстреливаем цель
			-- в тот же кадр, как она появилась
			self.LvsEngageAt = CurTime() + 0.6
		end

		self.LvsAiTarget = visible
		self:LvsAiAimNow()

		if self.ClickKey then self:ClickKey("Fire1") end

	else
		self.LvsAutoAngles = nil
		self.LvsAiTarget = nil
		self.LvsAimAligned = false
		self:SetNWVector("LvsAutoDir", vector_origin)
	end

	-- щит: при контакте только ниже 20% здоровья и только в автономном режиме
	if contact and self.LvsAutonomous and self.AddModule and not self:HasModule("Shield")
		and not self.LvsShieldManual and CurTime() >= (self.LvsShieldDownUntil or 0) then
		local hp  = self:GetHealth() or 0
		local max = self:GetDefaultHealth() or 0

		if max > 0 and hp / max < 0.2 then
			self.LvsJamBreakAt = nil
			self.LvsJamUse = nil
			self:AddModule("Shield")
		end
	end

	-- держим в цели только видимого противника
	local cur = self.Buffer and self.Buffer.Enemy

	-- сбрасываем старую цель, если это владелец или пилот
	if cur == self.Owner or cur == self:GetDriver() then
		self.Buffer.Enemy = nil
		cur = nil
	end

	if not IsValid(cur) then
		self.Buffer.Enemy = visible
	elseif visible and cur ~= visible and not self:LvsCanSee(cur) then
		self.Buffer.Enemy = visible
	end
end

-- Автономный режим: дрон сам сканирует, целится и стреляет (можно при пилоте)
net.Receive("lvs_scout_auto", function(_, ply)
	local drone = ply:GetNWEntity("DronesRewriteDrone")
	if not IsValid(drone) or drone:GetClass() ~= "lvs_scout_drr" then return end

	local on = net.ReadBool()
	drone.LvsAutonomous = on
	drone:SetNWBool("LvsAuto", on)

	-- при выключении убираем всё, что могло остаться от автопилота
	if not on then
		drone.LvsAutoAngles = nil
		drone:SetNWVector("LvsAutoDir", vector_origin)
		drone.LvsAiRed = nil
		drone.LvsScanContact = nil

		if drone.Buffer then drone.Buffer.Enemy = nil end

		if drone.LvsSetSkin then drone:LvsSetSkin(0) end
		-- чистим только Click: Pressed на сервере переключается событиями клиента,
		-- и ручная запись рассинхронизирует клавиши — ЛКМ/ПКМ пилота «мертвеют»
		for _, k in ipairs({ "Fire1", "Fire2", "Forward", "Back" }) do
			local st = drone.Keys and drone.Keys[k]
			if st then st.Click = false end
		end

	end
end)

-- Включить автономность всем дронам игрока, у которых она выключена
net.Receive("lvs_scout_auto_all", function(_, ply)
	if not IsValid(ply) then return end

	local n = 0

	for _, e in ipairs(ents.FindByClass("lvs_scout_drr")) do
		if IsValid(e) and (e.Owner == ply or e:GetOwner() == ply) and not e.LvsAutonomous then
			e.LvsAutonomous = true
			e:SetNWBool("LvsAuto", true)
			n = n + 1
		end
	end

	if n > 0 then ply:ChatPrint(string.format("[LVS Scout] Автономность включена: %d", n)) end
end)

-- Сколько дронов игрока в автономном режиме (для счётчика в F3)
net.Receive("lvs_scout_auto_stats", function(_, ply)
	if not IsValid(ply) then return end

	local on, total = 0, 0

	for _, e in ipairs(ents.FindByClass("lvs_scout_drr")) do
		if IsValid(e) and (e.Owner == ply or e:GetOwner() == ply) then
			total = total + 1
			if e.LvsAutonomous then on = on + 1 end
		end
	end

	net.Start("lvs_scout_auto_stats_res")
	net.WriteUInt(math.min(on, 255), 8)
	net.WriteUInt(math.min(total, 255), 8)
	net.Send(ply)
end)

function ENT:Think()
	-- Random moving: вместо полёта задним ходом разворачиваемся корпусом
	if self.AI_installed and self.Buffer and (self.Buffer.RandomBack or 0) > 0 then
		self.Buffer.RandomBack = 0
		self.Buffer.RandomForward = math.max(self.Buffer.RandomForward or 0, 12)
		self.LvsTurnTo = math.NormalizeAngle(self:GetAngles().y + 180)
	end

	self.BaseClass.Think(self)

	-- владелец мог появиться позже Initialize: досылаем в сеть
	if self.Owner ~= self.LvsOwnerSent then
		self.LvsOwnerSent = self.Owner

		if IsValid(self.Owner) then
			self:SetNWEntity("LvsOwner", self.Owner)
			self:SetNWString("LvsOwnerID", self.Owner:SteamID())
		end
	end

	-- состояние патруля (клиент рисует фонарики)
	local patrolNW = self.LvsAutonomous and not IsValid(self.LvsAiTarget)

	if self.LvsPatrolNW ~= patrolNW then
		self.LvsPatrolNW = patrolNW
		self:SetNWBool("LvsPatrol", patrolNW)
	end

	-- Камера от первого лица — ровно в точке обзора (Bip01_Head + вынос)
	local cam = self:GetCamera()
	local eye = self:LvsEyePos()

	if IsValid(cam) and eye then
		cam:SetPos(eye)
	end

	-- Своя отрисовка щита на клиенте; временную сущность DRR прячем
	if self.Buffer and IsValid(self.Buffer.Shield) then
		self.Buffer.Shield:SetNoDraw(true)
	end

	if self.LvsTurnTo then
		local ang = self:GetAngles()
		local diff = math.NormalizeAngle(ang.y - self.LvsTurnTo)

		self:ControlMotion("Left", "Right", diff, -10, 10)

		if math.abs(diff) < 12 then self.LvsTurnTo = nil end
	end

	local now = CurTime()
	-- автономно: наводим камеру/голову на цель (корпус не крутим — Left/Right
	-- добавляют ещё и тангаж, из-за чего дрон вертелся и стрелял вверх)
	if self.LvsAutonomous and self.LvsAutoAngles then
		self.CamAngles = self.LvsAutoAngles
	end
	-- автопилот: подлёт к врагу (как AI Follow enemy + MovingCore) — каждый тик,
	-- иначе импульсы ClickKey редкие и дрон еле ползёт
	-- уничтоженный дрон не воюет и не патрулирует
	local aiActive = not self.LvsDead
		and not (self:LvsPerf() and not IsValid(self.LvsAiTarget) and not self:LvsNearPlayers(6000))

	-- перф-режим: без игроков рядом боевая логика спит, но патруль работает
	if self.LvsAutonomous and not aiActive then
		self:LvsAiPatrol()
	end

	if aiActive and self.LvsAutonomous then
		self:LvsAiAimNow()

		-- под обстрелом и без щита — уклоняемся стрейфом вместо полёта по курсу
		if self.LvsDodgeUntil and CurTime() < self.LvsDodgeUntil and not self:LvsShieldUp() then
			-- ускорение на время манёвра: спринт + временный буст коэффициента
			if not self.LvsDodgeBoost then
				self.LvsDodgeBase = self.MoveCoefficient or 1
				self.MoveCoefficient = self.LvsDodgeBase * 1.6
				self.LvsDodgeBoost = true
				self:ClickKey("Sprint")
			end

			self:ClickKey(self.LvsDodgeDir == "left" and "StrafeLeft" or "StrafeRight")

			if CurTime() > (self.LvsDodgeFlip or 0) then
				self.LvsDodgeFlip = CurTime() + 0.55
				self:ClickKey("Up")
			end

			-- манёвр не отменяет доворот к цели, иначе под огнём не наводится
			local tgt = self.LvsAiTarget

			if IsValid(tgt) then
				local drpos = self:LocalToWorld(self:OBBCenter())
				local opos  = tgt:LocalToWorld(tgt:OBBCenter())
				local check = math.NormalizeAngle(self:GetAngles().y - (opos - drpos):Angle().y)

				self:ControlMotion("Left", "Right", check, -16, 16)
			end
		else
			if self.LvsDodgeBoost then
				self.MoveCoefficient = self.LvsDodgeBase or 1
				self.LvsDodgeBoost = false
			end

			if IsValid(self.LvsAiTarget) then
				self:LvsAiMove()
			else
				self:LvsAiPatrol()
			end
		end

		-- пулемёт: по замороженным и по летающим (маньяки, сканеры, дроны)
		local tgt    = self.LvsAiTarget
		local frozen = IsValid(tgt) and LVSScout and LVSScout.IsFrozen(tgt)

		local mgOnly = (self.LvsAttackMode == 1)

		if (frozen or self:LvsIsFlyer(tgt) or self:LvsIsPropTarget(tgt)
			or self:LvsIsCargo(tgt) or mgOnly) and self:LvsMgAllowed(tgt)
			and self.LvsAimAligned and self.ClickKey then
			self:ClickKey("Fire2")
		end
	end


	-- минимальная высота над землёй: автономно не чертим по ней днищем
	if now > (self.LvsNextGroundAt or 0) then
		self.LvsNextGroundAt = now + 0.25

		local pos = self:GetPos()
		local tr = util.TraceLine({
			start  = pos,
			endpos = pos - Vector(0, 0, 3000),
			filter = { self },
			mask   = MASK_SOLID,
		})

		self.LvsGroundZ = tr.Hit and tr.HitPos.z or nil

		-- потолок: в помещениях (d2_prison) высоту режет свод, а не земля
		local up = util.TraceLine({
			start  = pos,
			endpos = pos + Vector(0, 0, 3000),
			filter = { self },
			mask   = MASK_SOLID,
		})

		self.LvsCeilZ = up.Hit and up.HitPos.z or nil
	end

	-- рабочая высота над землёй с поправкой на потолок
	local minAlt = self.LvsMinAltitude or 800

	if self.LvsCeilZ then
		local head = self.LvsCeilZ - self:GetPos().z - 120
		if head > 150 then minAlt = math.min(minAlt, head) end
	end

	if self.LvsGroundZ and self.LvsAutonomous
		and self:GetPos().z < self.LvsGroundZ + minAlt then
		if self.ClickKey then self:ClickKey("Up") end
	end

	-- серво-гул двигателя: тихий на месте, воет в полёте
	if now > (self.LvsServoAt or 0) then
		self.LvsServoAt = now + 0.15
		self:LvsServoUpdate()
	end

	if self.BoneIDs then
		-- тяжёлые пересчёты — реже кадра (визуально не заметно, нагрузка ниже)
		if now > (self.LvsNextHitbox or 0) then
			self.LvsNextHitbox = now + (self:LvsPerf() and 1/20 or 1/75)

			-- без игроков поблизости хитбоксы можно не двигать
			if not self:LvsPerf() or self:LvsNearPlayers(6000) then
				self:LvsUpdateHitboxes()
			end
		end

		self:UpdateHead()
		self:UpdateWeaponAim()

		if now > (self.LvsNextTentacle or 0) then
			self.LvsNextTentacle = now + (self:LvsPerf() and 1/30 or 1/75)
			self:UpdateTentacles()
		end
	end

	if now > (self.LvsNextModuleCheck or 0) then
		self.LvsNextModuleCheck = now + 0.3
		self:LvsCheckModulePickup()
	end

	-- джаммер фиксирует щит на сбитом уровне: автореген DRR не поднимает его
	if now > (self.LvsNextShieldLock or 0) then
		self.LvsNextShieldLock = now + 0.2

		if self.HasModule and self:HasModule("Shield") and self.LvsShieldLocked then
			timer.Destroy("dronesrewrite_regen" .. self:EntIndex())

			if (self.Buffer.ShieldHealth or 0) > (self.LvsShieldLockHP or 0) then
				self.Buffer.ShieldHealth = self.LvsShieldLockHP or 0
				self:SetNWInt("shield_health", math.max(math.floor(self.Buffer.ShieldHealth), 0))
			end
		end
	end

	-- регенерация: медленно лечимся при HP ниже 30%, щит снимаем только на 100%
	if now > (self.LvsNextRegen or 0) then
		self.LvsNextRegen = now + 1

		local hp  = self:GetHealth() or 0
		local max = self:GetDefaultHealth() or 0
		local reviveHP = math.max(max * 0.15, 12)

		-- уничтоженный дрон не воскресает от мелкого лечения (щит, модули, реген)
		if hp <= 0 then
			self.LvsDead = true
			self:SetHealthAmount(0)
		elseif self.LvsDead then
			-- ремонтным инструментом можно поднять дрон с нуля
			local repairing = false

			for _, p in ipairs(player.GetAll()) do
				local w = IsValid(p) and p:GetActiveWeapon()

				if IsValid(w) and string.find(string.lower(w:GetClass()), "repair", 1, true)
					and p:GetPos():DistToSqr(self:GetPos()) < 400 * 400 then
					repairing = true
					break
				end
			end

			if repairing then
				self.LvsDead = nil
				self:LvsReviveShield()
			elseif hp < reviveHP then
				self:SetHealthAmount(0)
				hp = 0
			else
				self.LvsDead = nil
				self:LvsReviveShield()
			end
		end

		-- мёртвого дрона не лечим: иначе труп «оживает» и не уничтожается
		if max > 0 and hp > 0 and not self.LvsDead then
			local shield = self:HasModule("Shield")
			local step   = max * (self.LvsRegenRate or 0.01)

			-- чинится всегда, пока жив: медленно, 1% в секунду
			if hp < max then
				self:SetHealthAmount(math.min(max, hp + step))
			elseif shield and self.LvsAutonomous and not self.LvsShieldManual then
				-- снимаем щит только в автономном режиме и только если игрок
				-- не включал его вручную
				self:RemoveModule("Shield")
			end

			-- страховка: HP ниже минимального порога — поднимаем щит
			if hp < max * 0.2 and not shield then
				self:LvsReviveShield()
			end
		end
	end

	if aiActive and self.LvsAutonomous and now > (self.LvsNextAiScan or 0) then
		self.LvsNextAiScan = now + 0.5
		self:LvsAiScan()
	end

	return true
end

function ENT:LvsServoUpdate()
	local phys = self:GetPhysicsObject()
	local spd = IsValid(phys) and phys:GetVelocity():Length() or 0

	if not self.LvsServo then
		self.LvsServo = CreateSound(self, self.LvsServoSound or "npc/combine_gunship/gunship_engine_loop3.wav")

		if not self.LvsServo then return end

		self.LvsServo:SetSoundLevel(75)
		self.LvsServo:Play()
	end

	if not self.LvsServo:IsPlaying() then self.LvsServo:Play() end

	local frac = math.Clamp(spd / 900, 0, 1)

	self.LvsServo:ChangeVolume((self.LvsServoVolume or 0.55) * (0.25 + 0.75 * frac))
	self.LvsServo:ChangePitch(70 + 55 * frac)
end

-- Список дружественных NPC: добавление/удаление по классу, запрос списка
util.AddNetworkString("lvs_scout_friends_set")
util.AddNetworkString("lvs_scout_friends_get")
util.AddNetworkString("lvs_scout_friends_list")

-- Список дружественных NPC общий на игрока: правка с одного дрона действует на все его дроны
local function friendsOfOwner(ply)
	ply.LvsFriendClasses = ply.LvsFriendClasses or {}
	return ply.LvsFriendClasses
end

local function pushToDrones(ply)
	local list = friendsOfOwner(ply)

	for _, e in ipairs(ents.FindByClass("lvs_scout_drr")) do
		if IsValid(e) and (e.Owner == ply or e:GetOwner() == ply) then
			e.LvsFriendClasses = table.Copy(list)
		end
	end
end

net.Receive("lvs_scout_friends_set", function(_, ply)
	local drone = IsValid(ply) and ply:GetNWEntity("DronesRewriteDrone")
	if not IsValid(drone) or drone:GetClass() ~= "lvs_scout_drr" then return end

	local add = net.ReadBool()
	local cls = net.ReadString()

	if cls == "" or #cls > 64 then return end

	local list = friendsOfOwner(ply)

	if add then
		local n = 0
		for _ in pairs(list) do n = n + 1 end

		if n < 40 then list[cls] = true end
	else
		list[cls] = nil
	end

	pushToDrones(ply)
	drone.LvsFriendClasses = table.Copy(list)
end)

net.Receive("lvs_scout_friends_get", function(_, ply)
	if not IsValid(ply) then return end

	local drone = ply:GetNWEntity("DronesRewriteDrone")
	if not IsValid(drone) or drone:GetClass() ~= "lvs_scout_drr" then return end

	local list = ply.LvsFriendClasses or drone.LvsFriendClasses or {}
	local keys = {}

	for cls in pairs(list) do keys[#keys + 1] = cls end

	table.sort(keys)

	net.Start("lvs_scout_friends_list")
	net.WriteUInt(#keys, 8)

	for _, cls in ipairs(keys) do
		net.WriteString(cls)
	end

	net.Send(ply)
end)

function ENT:OnRemove()
	if self.LvsServo then
		self.LvsServo:Stop()
		self.LvsServo = nil
	end

	self:LvsRemoveHitboxes()

	if self.BaseClass and self.BaseClass.OnRemove then
		self.BaseClass.OnRemove(self)
	end
end
