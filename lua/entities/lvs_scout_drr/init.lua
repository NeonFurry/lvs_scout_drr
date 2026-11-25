include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

local SEGS_PER_ROPE = 13

util.AddNetworkString("lvs_scout_set_skin")
util.AddNetworkString("lvs_scout_set_shield")

util.AddNetworkString("lvs_scout_shield_down")
util.AddNetworkString("lvs_scout_shield_block")
util.AddNetworkString("lvs_scout_auto")
util.AddNetworkString("lvs_scout_auto_all")
util.AddNetworkString("lvs_scout_auto_stats")
util.AddNetworkString("lvs_scout_auto_stats_res")
util.AddNetworkString("lvs_scout_muzzle")
util.AddNetworkString("lvs_scout_emp")
util.AddNetworkString("lvs_scout_setting")
util.AddNetworkString("lvs_scout_getsetting")
util.AddNetworkString("lvs_scout_state")
util.AddNetworkString("lvs_scout_heavy_alert")
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
local TENTACLE_MAX_BEND = 8
local TENTACLE_SPEED    = 3.4
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

		-- LookupBone чувствителен к регистру/формату: второй проход по
		-- нормализованному имени (rope1_seg01 против Rope1_Seg01)
		if not id then
			local want = string.lower(name)

			for i = 0, self:GetBoneCount() - 1 do
				if string.lower(self:GetBoneName(i)) == want then
					id = i
					break
				end
			end
		end

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

-- Помеченная цель: проверяем только друзей и живость. Лимит дронов на цель
-- (claimed) не мешает — игрок указал цель явно и вправе перекинуть на неё дрона
function ENT:LvsMarkOk(e)
	if not IsValid(e) or e == self then return false end
	if e:GetClass() == "lvs_scout_drr" then return false end

	if self.LvsFriendClasses then
		if self.LvsFriendClasses[e:GetClass()] then return false end
		if e:IsPlayer() and self.LvsFriendClasses["@" .. e:SteamID()] then return false end
	end

	if e.Health and (e:Health() or 0) <= 0 then return false end

	return true
end

-- Точка, в которую целятся NPC: середина шеи (между Bip01_Neck и
-- Bip01_Head). Раньше брали голову — она выше корпуса, и страйдер бил поверх.
function ENT:LvsNeckPos()
	local neck = self:LookupBone("Bip01_Neck")
	local head = self:LookupBone("Bip01_Head")

	local pn = neck and self:GetBonePosition(neck)
	local ph = head and self:GetBonePosition(head)

	if isvector(pn) and isvector(ph) then
		return (pn + ph) * 0.5
	end

	return pn or ph
end

local function lvsFallbackCenter(self)
	return self:LocalToWorld(self:OBBCenter())
end

function ENT:WorldSpaceCenter()
	return self:LvsNeckPos() or lvsFallbackCenter(self)
end

-- Некоторые NPC берут BodyTarget, а не WorldSpaceCenter
function ENT:BodyTarget(pos, child)
	return self:LvsNeckPos() or lvsFallbackCenter(self)
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

	-- Попадание тяжёлой техники (страйдер, вертолёт, ганшип, хантер) —
	-- тоже повод надеть щит, даже если цель ещё не в поле зрения сканера
	local att = dmg:GetAttacker()

	if not IsValid(att) then att = dmg:GetInflictor() end

	-- только живой тяжёлый юнит: снаряды умирающего страйдера
	-- иначе заново назначали бы мёртвую цель (щит мигал)
	local attAlive = IsValid(att) and (att.Health == nil
		or ((att:Health() or 0) > 0 and (not att.IsNPC or att:Alive())))

	if ent.LvsIsHeavy and ent:LvsIsHeavy(att) and attAlive and (dmg:GetDamage() or 0) > 0 then
		ent.LvsHeavyTarget = att

		-- щит надеваем сразу, не дожидаясь следующего скана ИИ
		if ent.AddModule and not ent:HasModule("Shield") and not ent.LvsShieldManual
			and CurTime() >= (ent.LvsShieldDownUntil or 0) then
			ent.LvsJamBreakAt = nil
			ent.LvsJamUse = nil
			ent.LvsShieldForHeavy = true
			ent:AddModule("Shield")
		end
	end

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

	-- радар DRR пропускает дронов с NoDRRRadar; сбрасываем флаг, если модуля
	-- «Invisible for radar» на дроне нет
	if not (self.HasModule and self:HasModule("Invisible for radar")) then
		self:SetNWBool("NoDRRRadar", false)
	end

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
			end

			return
		end

		drone:AddModule("Shield")
	elseif drone:HasModule("Shield") then
		drone:RemoveModule("Shield")
	end
end)

-- ЭМИ-импульс: глушит вражеские дроны вокруг
-- Настройки производительности из F3: только белый список конваров
local LVS_SETTINGS_ALLOW = {
	lvs_scout_perf = true,
	lvs_scout_ai_range = true,
	lvs_scout_engage_range = true,
	lvs_scout_nav_mode = true,
	lvs_scout_debug = true,
}

net.Receive("lvs_scout_setting", function(_, ply)
	if not IsValid(ply) then return end

	local key = net.ReadString()
	local value = net.ReadString()

	if not LVS_SETTINGS_ALLOW[key] then return end

	local cv = GetConVar(key)

	-- конвар создаётся аддоном; неизвестный ключ игнорируем
	if not cv then return end

	cv:SetString(tostring(value))

-- Клиент спрашивает текущие настройки при открытии панели
net.Receive("lvs_scout_getsetting", function(_, ply)
	if not IsValid(ply) then return end

	local function num(name, default)
		local cv = GetConVar(name)
		return cv and cv:GetInt() or default
	end

	net.Start("lvs_scout_state")
	net.WriteInt(num("lvs_scout_perf", 1), 8)
	net.WriteInt(num("lvs_scout_ai_range", 16000), 32)
	net.WriteInt(num("lvs_scout_nav_mode", 1), 8)
	net.Send(ply)
end)
end)

net.Receive("lvs_scout_emp", function(_, ply)
	local drone = ply:GetNWEntity("DronesRewriteDrone")
	if not IsValid(drone) or drone:GetClass() ~= "lvs_scout_drr" then return end

	local left = (drone.LvsEmpAt or 0) - CurTime()

	if left > 0 then
		return
	end

	local n = drone:LvsEmp()

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

-- База DRR выставляет отношение НПС по IsEnemy(класс) каждые 0.1 с и для
-- «враждебного» класса ставит D_HT нашим NPC-триггерам. Дружественный класс
-- должен считаться другом и здесь, иначе НПС снова берут дрон в враги.
function ENT:IsEnemy(class)
	local friends = self.LvsFriendClasses

	if friends and class and friends[class] then return false end

	local base = self.BaseClass

	if base and base.IsEnemy then return base.IsEnemy(self, class) end

	-- без базы считаем врагом: иначе НПС перестали бы замечать все дроны
	return true
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


-- ЭМИ-импульс: 30 с перезарядки, глушит вражеские дроны в радиусе 2000
function ENT:LvsEmp()
	local owner = self.Owner or self:GetOwner()
	local pos = self:GetPos()
	local hit = 0

	self.LvsEmpAt = CurTime() + 30
	self:SetNWFloat("LvsEmpReadyAt", self.LvsEmpAt)

	-- визуал, вспышка и ослепление НПС/игроков
	if LvsEmpApply then LvsEmpApply(pos, owner) end

	self:EmitSound("ambient/levels/labs/electric_explosion1.wav", 95, 85)
	self:EmitSound("ambient/energy/weld2.wav", 90, 70)

	for _, d in ipairs(ents.FindByClass("lvs_scout_drr")) do
		if IsValid(d) and d ~= self then
			local o = d.Owner or d:GetOwner()

			if o ~= owner and d:GetPos():DistToSqr(pos) < 2000 * 2000 then
				d.LvsStunnedUntil = CurTime() + 3
				d:TakeDamage(80, self, self)
				hit = hit + 1
			end
		end
	end

	return hit
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

			-- плашка на экране самого стрелка: щит не пробить
			net.Start("lvs_scout_shield_block")
			net.Send(attacker)
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

	-- автоном без пилота и без цели: голова (камера) возвращается по курсу
	if self.LvsAutonomous and not IsValid(self:GetDriver()) and not self.LvsAutoAngles then
		local cur = self:GetManipulateBoneAngles(self.BoneIDs.Head) or Angle(0, 0, 0)
		self:ManipulateBoneAngles(self.BoneIDs.Head,
			LerpAngle(math.min(FrameTime() * HEAD_ROTATE_SPEED, 1), cur, Angle(0, 0, 0)))
		return
	end

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

-- Щупальца: только анимация (бегущая волна по костям).
-- Инерционный «хвост» убран: он накладывался на волну и гасил её.
local WAVE_DEG     = 22     -- амплитуда волны на кончике, градусы
local WAVE_STEP    = 0.55   -- сдвиг фазы на сегмент, рад
local WAVE_POW     = 0.6    -- профиль волны по длине
local SEG_LIMIT    = 10      -- предел угла одной кости, градусы

function ENT:UpdateTentacles()
	-- Вся анимация живёт в autorun/server/lvs_scout_tentacles.lua:
	-- там оригинальные клипы Crysis, и правки применяются без перезахода карты
	if LvsTentacleUpdate then LvsTentacleUpdate(self) end
end

-- Кость оружия смотрит в точку прицела
function ENT:UpdateWeaponAim()
	if not self.BoneIDs.Weapon then return end

	if self.LvsAutonomous and not IsValid(self:GetDriver()) and not self.LvsAutoAngles then
		local cur = self:GetManipulateBoneAngles(self.BoneIDs.Weapon) or Angle(0, 0, 0)
		self:ManipulateBoneAngles(self.BoneIDs.Weapon,
			LerpAngle(math.min(FrameTime() * ARM_ROTATE_SPEED, 1), cur, Angle(0, 0, 0)))
		return
	end

	local off = self:GetBoneAimOffset(self.BoneIDs.Weapon)

	local target = Angle(
		math.Clamp(off.p, -PITCH_LIMIT, PITCH_LIMIT),
		math.Clamp(math.AngleDifference(off.y, 0), -YAW_LIMIT, YAW_LIMIT),
		0
	)

	-- Отдача: клипов стрельбы в модели нет (в QC только idle/turret/fly_idle/fly_slow),
	-- поэтому кик считается по факту огня и плавно возвращается
	local firing = false

	for _, g in pairs(self.ValidWeapons or {}) do
		if IsValid(g) and g.Firing then firing = true break end
	end

	local rec = (self.LvsRecoil or 0) * math.pow(0.03, FrameTime())

	if firing then rec = math.min(rec + 2.2, 5.0) end

	self.LvsRecoil = rec

	target = Angle(math.Clamp(target.p - rec, -PITCH_LIMIT - 6, PITCH_LIMIT), target.y, 0)

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

-- Полная видимость: открыты все опорные точки цели (центр и две по высоте).
-- Если хоть одна перекрыта — дрон не стреляет, а ждёт чистого сектора.
function ENT:LvsFullVisible(e)
	if not IsValid(e) then return false end

	-- кэш 0.1 с: три трассы на каждый выстрел слишком дорого
	local now = CurTime()

	if self.LvsVisTarget == e and now < (self.LvsVisAt or 0) then
		return self.LvsVisOk == true
	end

	self.LvsVisTarget = e
	self.LvsVisAt = now + (self:LvsPerf() and 0.18 or 0.1)

	local filter = { self }

	for _, h in ipairs(self.LvsHitboxes or {}) do
		if IsValid(h.ent) then filter[#filter + 1] = h.ent end
	end

	local cam = self:GetCamera()
	local origin = IsValid(cam) and cam:GetPos() or self:GetPos()

	local base = e:GetPos()
	local maxs = e:OBBMaxs()
	local c = e:LocalToWorld(e:OBBCenter())

	local pts = {
		c,
		Vector(c.x, c.y, base.z + maxs.z * 0.75),
		Vector(c.x, c.y, base.z + maxs.z * 0.3),
	}

	for _, p in ipairs(pts) do
		local tr = util.TraceLine({
			start  = origin,
			endpos = p,
			filter = filter,
			mask   = MASK_SOLID,
		})

		-- попали в саму цель или трасса почти дошла — точка открыта
		if tr.Hit and tr.Entity ~= e and tr.Fraction < 0.98 then
			self.LvsVisOk = false
			return false
		end
	end

	self.LvsVisOk = true
	return true
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

-- Кеш списка наших дронов: FindByClass каждый тик на каждого дрона дорого
local LvsDroneCache, LvsDroneCacheAt = nil, 0

local function lvsDrones()
	if not LvsDroneCache or CurTime() > LvsDroneCacheAt then
		LvsDroneCache = ents.FindByClass("lvs_scout_drr")
		LvsDroneCacheAt = CurTime() + 0.25
	end

	return LvsDroneCache
end

-- Отталкивание от соседних дронов: чем ближе, тем сильнее уводим курс
-- Расталкивание соседних дронов: суммарный вектор «от соседей»
function ENT:LvsSepPush(radius)
	radius = radius or 900

	local origin = self:WorldSpaceCenter()
	local push = Vector(0, 0, 0)
	local n = 0

	for _, e in ipairs(lvsDrones()) do
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

-- По обычной цели стреляет один дрон, по тяжёлой — до трёх
local LVS_HEAVY_ATTACKERS = 3

-- Сколько дронов бьют одну цель: 0 = вся стая владельца (по умолчанию),
-- число = предел. Иначе часть дронов уходила в патруль во время боя.
function ENT:LvsAttackLimit()
	if not ConVarExists("lvs_scout_swarm") then
		CreateConVar("lvs_scout_swarm", "0", FCVAR_ARCHIVE,
			"Сколько дронов одновременно бьют одну цель: 0 = все, число = предел")
	end

	local n = GetConVar("lvs_scout_swarm"):GetInt()

	return n > 0 and n or 64
end

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

-- Тяжёлый юнит: страйдер, вертолёт, ганшип, хантер или груз дропшипа
function ENT:LvsIsHeavy(e)
	if not IsValid(e) then return false end

	return LVS_HEAVY_PRIORITY[e:GetClass()] ~= nil or self:LvsIsCargo(e)
end

-- Доложить союзным дронам о тяжёлой цели: цель кроют не больше трёх
function ENT:LvsShareHeavy(tgt, onTarget)
	if not IsValid(tgt) or not self.LvsAutonomous then return end

	-- свободные места: сам уже считаюсь, плюс те, кто цель уже держит
	local slots = LVS_HEAVY_ATTACKERS - 1 - (onTarget or 0)

	if slots <= 0 then return end

	-- не спамим: докладываем о цели не чаще раза в секунду
	if self.LvsShareTarget == tgt and CurTime() < (self.LvsShareAt or 0) then return end

	self.LvsShareTarget = tgt
	self.LvsShareAt = CurTime() + 1

	local myPos = self:GetPos()
	local list = {}

	for _, d in ipairs(ents.FindByClass("lvs_scout_drr")) do
		if d ~= self and IsValid(d) and d.LvsAutonomous and d.Owner == self.Owner then
			list[#list + 1] = d
		end
	end

	-- ближайшие первыми: долетят быстрее
	table.sort(list, function(a, b)
		return a:GetPos():DistToSqr(myPos) < b:GetPos():DistToSqr(myPos)
	end)

	local sent = 0

	for _, d in ipairs(list) do
		if sent >= slots then break end

		-- занятых другой целью не отвлекаем
		if not (IsValid(d.LvsAiTarget) and d.LvsAiTarget ~= tgt) then
			d:LvsRecvPriority(tgt, self)
			sent = sent + 1
		end
	end
end

-- Раздать увиденную цель всей стае владельца: свободные дроны летят к ней и
-- стреляют вместо патруля. Занятых другой живой целью не отвлекаем.
function ENT:LvsShareSwarm(tgt)
	if not IsValid(tgt) or not self.LvsAutonomous then return end

	for _, d in ipairs(ents.FindByClass("lvs_scout_drr")) do
		if d ~= self and IsValid(d) and d.LvsAutonomous and d.Owner == self.Owner then
			local cur = d.LvsPriorityTarget

			if not (IsValid(cur) and cur ~= tgt and d:LvsMarkOk(cur)) then
				d:LvsRecvMark(tgt, self)
			end
		end
	end
end

-- Оповестить пилотов о тяжёлой цели: HUD рисует текст и метку
function ENT:LvsAlertHeavy(tgt)
	if not IsValid(tgt) then return end
	if CurTime() < (self.LvsAlertAt or 0) then return end

	self.LvsAlertAt = CurTime() + 1

	-- шлём всем: HUD отрисует это только у тех, кто сидит в дроне,
	-- а фильтр по пилотам отсекал игроков, если NW-поле ещё не выставилось
	net.Start("lvs_scout_heavy_alert")
	net.WriteUInt(self:EntIndex(), 16)
	net.WriteString(tgt:GetClass())
	net.WriteVector(tgt:WorldSpaceCenter())
	net.WriteEntity(tgt)
	net.Send(player.GetAll())

	if GetConVar("lvs_scout_debug") and GetConVar("lvs_scout_debug"):GetBool() then
		print(string.format("[LVS] alert: дрон %d -> %s (%.0f, %.0f, %.0f)",
			self:EntIndex(), tgt:GetClass(),
			tgt:WorldSpaceCenter().x, tgt:WorldSpaceCenter().y, tgt:WorldSpaceCenter().z))
	end
end

-- Метка от пилота: летим на указанного врага и работаем по нему
function ENT:LvsRecvMark(tgt, from)
	if not IsValid(tgt) or not self.LvsAutonomous then return end

	self.LvsPriorityTarget = tgt
	self.LvsEngageAt = 0

	-- база DRR ведёт дрон к этой цели
	if self.Buffer then self.Buffer.Enemy = tgt end
end

-- Получен приказ от союзника: летим на цель и работаем по ней
function ENT:LvsRecvPriority(tgt, from)
	if not IsValid(tgt) or not self.LvsAutonomous then return end
	if not self:LvsIsHeavy(tgt) then return end

	self.LvsPriorityTarget = tgt
	self.LvsHeavyTarget = tgt
	self.LvsEngageAt = 0

	-- база DRR ведёт дрон к этой цели
	if self.Buffer then self.Buffer.Enemy = tgt end
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
-- Высота патруля по рельефу: в городских коридорах HL2 дрон снижается
-- до уровня улицы, чтобы видеть цели за зданиями; на открытых картах
-- держит запас над рельефом. Считается раз в секунду на дрон.
function ENT:LvsStreetAltitude()
	local now = CurTime()

	if now < (self.LvsAltAt or 0) then return self.LvsAltCache end

	self.LvsAltAt = now + 1

	local pos = self:GetPos()
	local groundDist = 3000
	local tr = util.TraceHull({
		start = pos,
		endpos = pos - Vector(0, 0, 3000),
		mins = Vector(-64, -64, 0),
		maxs = Vector(64, 64, 0),
		mask = MASK_SOLID,
		filter = self,
	})

	if tr.Hit then groundDist = math.max(0, pos.z - tr.HitPos.z) end

	-- Вода/кислота в каналах HL2: не спускаемся к самой поверхности
	if tr.HitWater then groundDist = math.max(groundDist, 300) end

	-- крыша над дроном: в тесных картах кампании здания почти сразу над
	-- улицей, на открытых — небо на много тысяч юнитов
	local base = pos - Vector(0, 0, groundDist)
	local ceilTr = util.TraceLine({
		start = base + Vector(0, 0, 2),
		endpos = base + Vector(0, 0, 9000),
		mask = MASK_SOLID,
		filter = self,
	})

	local roof = ceilTr.Hit and math.max(0, ceilTr.HitPos.z - base.z) or 9000
	local target

	if roof < 2200 then
		-- в тесных картах: чуть выше домов-коридоров, но ниже крыш
		-- низкий свод (туннель, подвал): идём под потолком, а не в него
		if roof < 900 then
			target = math.Clamp(roof * 0.45, 200, 500)
		else
			target = math.Clamp(roof * 0.55, 400, 2100)
		end
	else
		target = (self.LvsPatrolAltitudeMin + self.LvsPatrolAltitudeMax) * 0.5
	end

	-- над водой держим запас, иначе дрон макает нос в канал
	if tr.HitWater then target = math.max(target, 700) end

	self.LvsAltCache = target

	return target
end

-- В HL2 нет катсцен как таковых: есть скриптовые сцены, где у игрока
-- забирают управление и сажают камеру на point_viewcontrol. Только в этот
-- момент дрон молчит; обычная блокировка управления (без внешней камеры)
-- боем не считается.
function ENT:LvsScriptPause()
	local ply = self:GetDriver()

	if not IsValid(ply) then ply = self.Owner end
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	if not ply:IsFlagSet(FL_FROZEN) then return false end

	-- управление забрали, но камера своя: это не сцена, а короткий лок
	local view = ply:GetViewEntity()

	return IsValid(view) and view ~= ply
end

-- Шаблоны HL2: статичные противники, которых не считаем летающими
local LVS_STATIC_ENEMY = {
	npc_turret_floor = true, npc_turret_ceiling = true, npc_combine_camera = true,
	npc_combine_s = true, npc_metropolice = true, npc_zombie = true,
	npc_zombie_torso = true, npc_fastzombie = true, npc_fastzombie_torso = true,
	npc_poisonzombie = true, npc_zombine = true, npc_headcrab = true,
	npc_headcrab_armored = true, npc_headcrab_fast = true, npc_headcrab_poison = true,
	npc_headcrab_black = true, npc_antlion = true, npc_antlion_worker = true,
	npc_antlionguard = true, npc_antlionguardian = true, npc_vortigaunt = true,
	npc_hunter = true, npc_barnacle = true, npc_rollermine = true,
}

function ENT:LvsIsFlyer(e)
	if not IsValid(e) then return false end
	if e.IS_DRONE then return true end

	if e:IsNPC() then
		local cls = e:GetClass()

		if cls == "npc_manhack" or cls == "npc_cscanner" or cls == "npc_clawscanner" then
			return true
		end

		-- штурмовики и зомби «в воздухе» на лестницах — не летающие: иначе
		-- дрон держит высоту, хотя цель пешком
		if LVS_STATIC_ENEMY[cls] then return false end

		return not e:IsOnGround()
	end

	return false
end

-- Дальнобойность по шаблонам кампании: ближний бой не требует высокой
-- орбиты, турели и снайперов лучше держать дальше
local LVS_RANGE_HINT = {
	npc_zombie = 900, npc_zombie_torso = 800, npc_fastzombie = 800,
	npc_fastzombie_torso = 750, npc_zombine = 1100,
	npc_poisonzombie = 1000, npc_headcrab = 700, npc_headcrab_armored = 900,
	npc_headcrab_fast = 700, npc_headcrab_poison = 800, npc_headcrab_black = 800,
	npc_antlion = 800, npc_antlion_worker = 900, npc_antlionguard = 1200,
	npc_antlionguardian = 1400, npc_barnacle = 900, npc_rollermine = 700,
	npc_combine_s = 1500, npc_metropolice = 1300,
	npc_turret_floor = 2200, npc_turret_ceiling = 1200, npc_combine_camera = 900,
	npc_strider = 2600, npc_helicopter = 2600, npc_combinegunship = 2600,
	npc_combinedropship = 3000, npc_hunter = 1800, npc_stalker = 1800,
	npc_vortigaunt = 1600,
}

function ENT:LvsRangeHint(e)
	if not IsValid(e) then return nil end

	return LVS_RANGE_HINT[e:GetClass()]
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
		self.LvsAiAvoidAt = nowT + (self:LvsPerf() and 1/10 or 1/15)

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

	-- Полная видимость цели: если её нет, дрон выбирает ОДНО направление
	-- обхода и держит его, а не жмёт вперёд-назад-вверх-вниз одновременно
	if self.LvsAutonomous and self.LvsFullVisible then
		if nowT > (self.LvsNoVisAt or 0) then
			self.LvsNoVisAt = nowT + 0.2
			self.LvsNoVis = not self:LvsFullVisible(tgt)
		end
	end

	local flank

	if av and self.LvsNoVis then
		if nowT > (self.LvsFlankAt or 0) then
			local opts = {}

			if not av.left then opts[#opts + 1] = "left" end
			if not av.right then opts[#opts + 1] = "right" end
			if not av.below then opts[#opts + 1] = "below" end
			if not av.above then opts[#opts + 1] = "above" end
			if not av.front then opts[#opts + 1] = "front" end

			if #opts > 0 then
				self.LvsFlankDir = opts[math.random(#opts)]
			end

			self.LvsFlankAt = nowT + 1.2
		end

		flank = self.LvsFlankDir
	end

	if av then
		if flank then
			-- один осознанный манёвр, чтобы открыть линию огня
			if flank == "left" then self:ClickKey("StrafeLeft")
			elseif flank == "right" then self:ClickKey("StrafeRight")
			elseif flank == "above" then self:ClickKey("Up")
			elseif flank == "below" then self:ClickKey("Down")
			elseif flank == "front" then self:ClickKey("Forward")
			end
		else
			if av.back  then self:ClickKey("Forward") end
			if av.front then self:ClickKey("Back") end
			if av.below then self:ClickKey("Up") end
			if av.above then self:ClickKey("Down") end
			if av.left  then self:ClickKey("StrafeRight") end
			if av.right then self:ClickKey("StrafeLeft") end
		end
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
		self.LvsAiSeeAt = CurTime() + (self:LvsPerf() and ((hdist < 1200) and 1/20 or 1/10) or ((hdist < 1200) and 1/40 or 1/15))
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

	-- шаблоны кампании: под зомби и хедкрабов не держим дистанцию снайпера
	local hint = self:LvsRangeHint(tgt)

	if hint then pref = math.Clamp(math.min(pref, hint), 500, hint) end
	if not self.LvsAiSee then pref = math.max(600, pref * 0.55) end
	pref = math.min(pref, (self.CryoRange or 2048) * (flying and 0.9 or 0.7))

	-- Цель частично закрыта: не играем дистанцией, идём к ней и обходим
	if self.LvsNoVis then pref = 100 end

	-- Цель отмечена пилотом и далеко: идём вплотную, а не висим на дистанции
	if IsValid(self.LvsPriorityTarget) and self.LvsPriorityTarget == tgt and hdist > 3000 then
		pref = 200
	end

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

	-- Обход стен: в коридорах и дверях кампании HL2 дрон упирался в
	-- геометрию. Смотрим коридор вперёд и уводим в сторону с просветом.
	if self.LvsApproach == 1 and nowPos > (self.LvsWallAt or 0) then
		local from = self:WorldSpaceCenter()
		local ahead = util.TraceHull({
			start  = from,
			endpos = from + self:GetForward() * 320,
			mins   = Vector(-30, -30, -24),
			maxs   = Vector(30, 30, 24),
			filter = self,
			mask   = MASK_SOLID,
		})

		if ahead.Hit then
			-- сначала пробуем перелететь: если сверху чисто — поднимаемся,
			-- иначе обходим в сторону (дома d3_c17 выше рабочей высоты)
			local upTr = util.TraceHull({
				start  = from,
				endpos = from + Vector(0, 0, 700),
				mins   = Vector(-58, -58, 0),
				maxs   = Vector(58, 58, 0),
				filter = self,
				mask   = MASK_SOLID,
			})

			if not upTr.Hit then
				self:ClickKey("Up")
			else
				local rTr = util.TraceLine({
					start = from, endpos = from + self:GetRight() * 420,
					filter = self, mask = MASK_SOLID,
				})
				local lTr = util.TraceLine({
					start = from, endpos = from - self:GetRight() * 420,
					filter = self, mask = MASK_SOLID,
				})

				self.LvsWallSide = rTr.Fraction > lTr.Fraction and "StrafeRight" or "StrafeLeft"
			end

			self.LvsWallUntil = nowPos + 0.7
			self.LvsWallAt = nowPos + 0.4
		end
	end

	if nowPos < (self.LvsWallUntil or 0) then
		self:ClickKey(self.LvsWallSide or "StrafeRight")
		self.LvsApproach = 0
	end

	-- за границу карты не летим даже за целью
	if util.IsInWorld and not util.IsInWorld(self:GetPos() + self:GetForward() * 500) then
		self.LvsApproach = -1
		self.LvsWallUntil = nowPos + 0.6
		self.LvsWallSide = "StrafeLeft"
	end

	if check > -40 and check < 40 then
		if self.LvsApproach == 1 then
			self:ClickKey("Forward")
		elseif self.LvsApproach == -1 then
			self:ClickKey("Back")
		end
	end

	self:ControlMotion("Left", "Right", check, -16, 16)

	-- Высота в бою: держимся над целью, но под сводом и без «полёта в пустоте».
	-- В большом туннеле (2-3 этажа) дрон идёт на уровне голов, а не под потолком.
	local pitchDown = math.abs(math.min(self.PitchMin or -30, 0))
	local maxOffset = hdist * math.tan(math.rad(math.max(pitchDown - 5, 5)))
	local cap       = self.LvsAiAltitudeOffset or 2000
	local ceilingAlt = self:LvsStreetAltitude()

	local upper = math.min(cap, ceilingAlt or cap)
	local lower = math.min(self.LvsMinAltitude or 800, upper)

	-- тесное помещение или туннель: боремся на уровне цели, а не у свода
	if ceilingAlt and ceilingAlt < 900 and not flying then
		upper = math.min(upper, 420)
		lower = math.min(lower, 220)
	end

	local offset = math.Clamp(math.min(maxOffset, upper), lower, upper)

	if not self.LvsAiSee then offset = math.min(offset + 200, upper) end

	-- личная высота: дроны не выстраиваются в одну линию над целью
	if not self.LvsAltJitter then self.LvsAltJitter = math.random(-200, 260) end
	offset = math.Clamp(offset + self.LvsAltJitter * 0.6, lower, upper)

	local wantZ = opos.z + offset

	-- не поднимаемся в свод: держим запас под корпус дрона
	if self.LvsCeilZ then
		local ceil = self.LvsCeilZ - 170

		if wantZ > ceil then wantZ = ceil end
	end

	if not self.LvsNoVis then
		-- высота боя: сглаженная цель, мёртвая зона и торможение падения.
		-- Без них Up/Down чередуются через тик и дрон «прыгает» у цели.
		self.LvsWantZ = self.LvsWantZ and Lerp(math.min(FrameTime() * 2, 1), self.LvsWantZ, wantZ) or wantZ
		wantZ = self.LvsWantZ

		local dz = wantZ - drpos.z
		local vz = self:GetVelocity().z

		if dz > 150 and (not self.LvsCeilZ or drpos.z < self.LvsCeilZ - 190) then
			self:ClickKey("Up")
		elseif dz < -150 then
			if vz > -200 then self:ClickKey("Down") end
		elseif vz < -250 then
			self:ClickKey("Up")
		end
	end
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

-- AI-ноды: в приоритете воздушные (info_node_air*) — это готовые точки
-- полёта; если воздушных рядом нет, берём наземную.
function ENT:LvsNodeCenter(pos, radius)
	local now = CurTime()

	if not LvsNodeCache or now > (LvsNodeCacheAt or 0) then
		LvsNodeCache = ents.FindByClass("info_node*") or {}
		LvsNodeCacheAt = now + 10
	end

	local r2 = radius * radius
	local air, land = {}, {}

	for _, n in ipairs(LvsNodeCache) do
		if IsValid(n) then
			local p = n:GetPos()

			if util.IsInWorld and not util.IsInWorld(p) then continue end

			local d = p:DistToSqr(pos)

			if d <= r2 then
				local gz = self:LvsGroundAt(p, 4000)

				if not gz then continue end

				local e = { p = p, d = d }

				if p.z - gz > 150 then
					air[#air + 1] = e
				else
					land[#land + 1] = e
				end
			end
		end
	end

	local list = #air > 0 and air or land

	if #list == 0 then return end

	table.sort(list, function(a, b) return a.d < b.d end)

	local pick = list[math.random(1, math.min(3, #list))]

	return pick and pick.p
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

-- Высота поверхности под точкой (крыша/земля). nil = под точкой пустота
function ENT:LvsGroundAt(pos, dist)
	local tr = util.TraceLine({
		start  = pos + Vector(0, 0, 64),
		endpos = pos + Vector(0, 0, -(dist or 4000)),
		filter = { self },
		mask   = MASK_SOLID,
	})

	return tr.Hit and tr.HitPos.z or nil
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

		if navMode == 1 then
			-- NavMesh: зона под дроном + случайный центр в радиусе
			local okA, area = pcall(self.LvsNavBelow, self, myPos)
			if okA then overNav = area end

			local okB, center = pcall(self.LvsRandomNavCenter, self, myPos, 4500)
			if okB then navCenter = center end

			if not overNav then
				local okD, near = pcall(function()
					return navmesh and navmesh.GetNearestNavArea
						and navmesh.GetNearestNavArea(myPos, true, 8000, false, true)
				end)

				if okD and near and near.GetCenter then navCenter = near:GetCenter() end
			end
		elseif navMode == 2 then
			-- AI nodes. Воздушные info_node_air* в приоритете.
			local okC, node = pcall(self.LvsNodeCenter, self, myPos, 2600)

			if okC then navCenter = node end

			-- на карте нет нод-сущностей: переключаемся на NavMesh,
			-- иначе дрон просто висит на месте
			if not navCenter then
				local okB, center = pcall(self.LvsRandomNavCenter, self, myPos, 4500)

				if okB then navCenter = center end
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

		-- AI Nodes: воздушные ноды (info_node_air) — это готовые точки полёта,
		-- летим ровно к ним; наземные — держим 250-350 над ними.
		if self:LvsNavMode() == 2 and self.LvsPatrolPos then
			local gz = self:LvsGroundAt(self.LvsPatrolPos, 4000)
			local above = gz and (self.LvsPatrolPos.z - gz) or 0

			if above > 150 then
				lo, hi = 30, 70      -- смещение от самой ноды
			else
				lo, hi = 250, 350    -- над землёй вдоль улицы
			end
		end

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

	-- Рельеф впереди: если там крыша выше нас — поднимаемся над ней.
	-- Иначе дрон бьётся низом о край здания.
	if now > (self.LvsPatrolTerrAt or 0) then
		self.LvsPatrolTerrAt = now + 0.4

		local myPos = self:GetPos()
		local ahead = self:LvsGroundAt(myPos + self:GetForward() * 420, 4000)
		local below = self:LvsGroundAt(myPos, 6000)

		-- вылет за карту: нет земли ИЛИ точка впереди вне границ мира
		local outAhead = util.IsInWorld and not util.IsInWorld(myPos + self:GetForward() * 400)

		if (outAhead or (not below and not ahead)) and now > (self.LvsEdgeAt or 0) then
			self.LvsEdgeAt = now + 1
			self.LvsPatrolYaw = math.NormalizeAngle(self:GetAngles().y + 180)
			self.LvsPatrolPos = nil
			self.LvsPatrolAt = now + 2
		end

		if ahead and ahead > myPos.z - 150 then
			self.LvsPatrolZ = ahead + 260
			self:ClickKey("Up")
		end
	end

	-- держим высоту патруля: мёртвая зона и торможение падения. Без них
	-- импульсы Up/Down чередуются через тик, и у земли дрон «прыгает».
	local z = self:GetPos().z
	local dz = (self.LvsPatrolZ or z) - z
	local vz = self:GetVelocity().z
	local ground = self.LvsPatrolGround

	if (ground and dz > -150) or dz > 150 then
		self:ClickKey("Up")
	elseif dz < -150 and not ground then
		if vz > -200 then self:ClickKey("Down") end
	elseif vz < -250 then
		self:ClickKey("Up")
	end
end

-- Кости головы у разных классов: люди/зомби, страйдер, ганшип, вертолёт, дропшип
local LVS_HEAD_BONES = {
	"ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Head", "Head", "head",
	-- у страйдера в модели нет кости Head: движок сам берёт шею
	-- (npc_strider.cpp: pszBodyTargetBone = "combine_strider.neck_bone")
	"combine_strider.neck_bone", "combine_strider.head_bone",
	"combine_strider.head", "Combine_Strider.Neck",
	"Combine_Strider.Head", "Combine_Strider.head", "strider_head",
	"Combine_Gunship.Head", "Combine_Gunship.head",
	"Combine_Dropship.Head", "Combine_Dropship.head",
	"Helicopter.Head", "helicopter_head", "Hunter.Head", "hunter_head",
}

function ENT:LvsAimPoint(e)
	if not IsValid(e) then return end

	-- все NPC (включая страйдера, ганшип, вертолёт) — целимся в голову
	if e:IsPlayer() or e:IsNPC() or e:IsNextBot() then
		local center = e:LocalToWorld(e:OBBCenter())
		-- верхняя граница габарита: присевший страйдер не должен
		-- «уводить» прицел выше модели
		local top = e:GetPos().z + e:OBBMaxs().z

		for _, name in ipairs(LVS_HEAD_BONES) do
			local b = e:LookupBone(name)

			if b and b >= 0 then
				local p = e:GetBonePosition(b)

				if isvector(p) then
					if p.z > top then p.z = top end
					if p.z > center.z + e:OBBMaxs().z * 0.3 then
						p = Vector(p.x, p.y, center.z)
					end

					return p
				end
			end
		end

		if e:IsPlayer() then return e:GetShootPos() end

		return center
	end

	return e:LocalToWorld(e:OBBCenter())
end

-- Наведение каждый тик (цель движется — при 0.5 с прицел отставал)
function ENT:LvsAiAimNow()
	local tgt = self.LvsAiTarget

	if not IsValid(tgt) then
		self.LvsAimAligned = false

		-- цель потеряна: сбрасываем накопленное наведение, иначе камера
		-- замирает на последнем направлении и не возвращается по курсу
		self.LvsAutoAngles = nil
		self.LvsAimSmooth = nil
		self:SetNWVector("LvsAutoDir", vector_origin)
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
	local center

	-- упреждение считаем от головы; если кости головы нет — от центра габарита
	center = (self.LvsAimPoint and self:LvsAimPoint(tgt)) or tgt:WorldSpaceCenter()

	if not center then center = tgt:WorldSpaceCenter() + Vector(0, 0, 12) end

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

-- Отрядная точка: дрон, увидевший группу врагов, ставит метку на место.
-- Свободные дроны владельца летят туда; если целей больше, чем дронов,
-- летят все — нужное число получается само.
local SQUAD_POINT_TIME = 8
local SQUAD_CLUSTER_R = 700

function ENT:LvsSquadMarkPoint(pos, count)
	local owner = self.Owner

	if not IsValid(owner) or not isvector(pos) then return end

	owner.LvsSquadPos = pos
	owner.LvsSquadCount = count
	owner.LvsSquadUntil = CurTime() + SQUAD_POINT_TIME
end

function ENT:LvsSquadPoint()
	local owner = self.Owner

	if not IsValid(owner) or not owner.LvsSquadPos then return end
	if CurTime() > (owner.LvsSquadUntil or 0) then
		owner.LvsSquadPos = nil
		return
	end

	return owner.LvsSquadPos, owner.LvsSquadCount or 1
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

	-- цели и число дронов, которые их уже держат: обычную цель не перебиваем,
	-- тяжёлую делят между собой до LVS_HEAVY_ATTACKERS дронов
	local claimed = {}

	local myPos = self:GetPos()

	for _, d in ipairs(lvsDrones()) do
		if d ~= self and IsValid(d) and d.LvsAutonomous and IsValid(d.LvsAiTarget)
			and d:GetPos():DistToSqr(myPos) <= 8000 * 8000 then
			claimed[d.LvsAiTarget] = (claimed[d.LvsAiTarget] or 0) + 1
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
		-- стая: сколько дронов может держать одну цель (см. lvs_scout_swarm)
		if (claimed[e] or 0) >= self:LvsAttackLimit() then return false end
		if not (e:IsPlayer() or e:IsNPC() or e:IsNextBot() or e.IS_DRONE) then return false end
		if e:IsPlayer() and IsValid(e:GetNWEntity("DronesRewriteDrone")) then return false end

		-- Правила как в DRR, но без его лимита дистанции: ShouldAttack режет
		-- по клиентскому конвару владельца (dronesrewrite_ai_radius, 3000)
		local owner = IsValid(self.Owner) and self.Owner or nil

		if e:IsNPC() then
			-- LifeState умирающего NPC ещё LIFE_DYING, а HP уже 0 или добивается:
			-- без Alive() ИИ продолжает стрелять по падающему телу
			if not e:Alive() or (e:Health() or 0) <= 0 then return false end
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
		and (self:LvsIsCargo(cur) or cur.IS_DRONE or cur.Health == nil
			or (cur:Health() > 0 and (not cur.IsNPC or cur:Alive()))) then
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

	-- увидели группу: делимся точкой с дронами владельца
	if IsValid(visible) and IsValid(self.Owner) and CurTime() > (self.LvsSquadAt or 0) then
		self.LvsSquadAt = CurTime() + 1

		local base = visible:GetPos()
		local cnt = 1

		for _, x in ipairs(self.LvsAiTargets()) do
			if IsValid(x) and x ~= visible and (x:IsNPC() or x:IsNextBot())
				and self.IsEnemy and self:IsEnemy(x:GetClass())
				and x:GetPos():DistToSqr(base) <= SQUAD_CLUSTER_R * SQUAD_CLUSTER_R then
				cnt = cnt + 1
			end
		end

		if cnt > 1 then self:LvsSquadMarkPoint(base, cnt) end

		-- цель уходит всей стае: иначе часть дронов бьёт, часть патрулирует
		self:LvsShareSwarm(visible)
	end

	-- при виде врага — красная расцветка, иначе возвращаем обычную
	local red = visible ~= nil

	if self.LvsAiRed ~= red then
		self.LvsAiRed = red
		self:LvsSetSkin(red and 1 or 0)
	end

	-- сброс: цель, найденная сканом, видна напрямую
	self.LvsTargetMarked = false

	-- Помеченная цель приоритетнее обычной: её указал игрок или союзный дрон
	if IsValid(self.LvsPriorityTarget) then
		local pt = self.LvsPriorityTarget

		if self:LvsMarkOk(pt) then
			visible = pt
			self.LvsTargetMarked = true
			self.LvsAiTargetSeen = CurTime()
		else
			self.LvsPriorityTarget = nil
		end
	end

	-- прицеливание и огонь по видимой цели
	if visible then		-- разнообразие: 1 — только пулемёт, 2 — луч, затем добивание пулемётом
		if self.LvsAiTarget ~= visible then
			self.LvsAttackMode = math.random(1, 2)
			self.LvsAimSmooth = nil

			-- короткая задержка взятия на прицел: не расстреливаем цель
			-- в тот же кадр, как она появилась
			self.LvsEngageAt = CurTime() + 0.6
		end

		self.LvsAiTarget = visible
		self:LvsAiAimNow()

		if self.ClickKey then
			-- цель от союзника может быть за стеной: не палим в укрытие
			if not self.LvsTargetMarked or self:LvsCanSee(visible) then
				self:ClickKey("Fire1")
			end
		end

	else
		self.LvsAutoAngles = nil
		self.LvsAiTarget = nil
		self.LvsAimAligned = false
		self:SetNWVector("LvsAutoDir", vector_origin)

		-- свободный дрон идёт к точке, отмеченной соседом
		local sp = self:LvsSquadPoint()

		if sp then
			self.LvsPatrolPos = sp
			self.LvsPatrolAt = CurTime() + 2
		end
	end

	-- Тяжёлая техника (страйдер, вертолёт, ганшип, хантер, груз дропшипа):
	-- пока такая цель жива — держим щит и предупреждение в HUD
	local heavy

	if self:LvsIsHeavy(visible) then
		heavy = visible
	end

	local held = self.LvsHeavyTarget

	-- снимаем пометку только когда цель реально умерла: щит держится,
	-- даже если тяжёлый юнит ушёл из зоны видимости
	if IsValid(held) and held.Health and (not held:Alive() or (held:Health() or 0) <= 0) then
		self.LvsHeavyTarget = nil
	end

	if IsValid(heavy) then
		self.LvsHeavyTarget = heavy

		-- доложить союзным дронам: тяжёлую цель кроют втроём
		self:LvsShareHeavy(heavy, claimed[heavy] or 0)

		-- оповестить пилотов: в HUD появится метка обнаружения
		self:LvsAlertHeavy(heavy)
	end

	local ht = self.LvsHeavyTarget
	local heavyAlive = IsValid(ht) and (ht.Health == nil
		or ((ht:Health() or 0) > 0 and (not ht.IsNPC or ht:Alive())))

	-- щит: тяжёлая цель — сразу, обычные — только ниже 20% здоровья.
	-- Ручное решение игрока в F3 всегда главнее авто-логики
	if self.LvsAutonomous and self.AddModule and not self:HasModule("Shield")
		and not self.LvsShieldManual
		and CurTime() >= (self.LvsShieldDownUntil or 0) then
		local hp  = self:GetHealth() or 0
		local max = self:GetDefaultHealth() or 0

		if heavyAlive or (contact and max > 0 and hp / max < 0.2) then
			self.LvsJamBreakAt = nil
			self.LvsJamUse = nil

			-- помним, что щит поставлен из-за тяжёлой цели: только его
			-- и снимаем, когда угроза уйдёт
			self.LvsShieldForHeavy = heavyAlive or nil

			self:AddModule("Shield")
		end
	end

	-- Тяжёлая цель ушла: снимаем только щит, поставленный из-за неё,
	-- один раз и с задержкой. Щит от низкого HP и ручной не трогаем
	if heavyAlive then
		self.LvsHeavyGoneAt = nil
	elseif not self.LvsHeavyGoneAt then
		self.LvsHeavyGoneAt = CurTime() + 2
	elseif CurTime() >= self.LvsHeavyGoneAt then
		if self.LvsAutonomous and self.LvsShieldForHeavy and not self.LvsShieldManual
			and self:HasModule("Shield") then
			self:RemoveModule("Shield")
			self.LvsShieldForHeavy = nil
		end

		self.LvsHeavyGoneAt = false
	end

	-- HUD: тип и здоровье тяжёлой цели (в сеть только при изменении)
	local hv = self.LvsHeavyTarget

	if IsValid(hv) then
		local hp = math.max(hv:Health() or 0, 0)
		local mx = math.max((hv.GetMaxHealth and hv:GetMaxHealth()) or hp, hp)
		local cls = hv:GetClass()

		-- Панель живёт, пока цель жива: неуязвимости у страйдера больше нет
		local show = hp > 0

		if self.LvsHeavySentHp ~= hp or self.LvsHeavySentClass ~= cls or self.LvsHeavySentMax ~= mx then
			self.LvsHeavySentHp = hp
			self.LvsHeavySentClass = cls
			self.LvsHeavySentMax = mx

			self:SetNWBool("LvsHeavyActive", show)
			self:SetNWString("LvsHeavyClass", cls)
			self:SetNWInt("LvsHeavyHp", hp)
			self:SetNWInt("LvsHeavyMax", mx)
		end
	elseif self.LvsHeavySentHp ~= nil then
		self.LvsHeavySentHp = nil
		self.LvsHeavySentClass = nil
		self:SetNWBool("LvsHeavyActive", false)
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
	-- Чужое ночное видение DRR у нашего дрона выключено: у нас своя оптика
	-- с отдельной переменной LvsNV (см. lvs_scout_nightvision.lua)
	if self.UseNightVision then self.UseNightVision = false end
	if self:GetNWBool("NightVision") then self:SetNWBool("NightVision", false) end

	-- Random moving: вместо полёта задним ходом разворачиваемся корпусом
	if self.AI_installed and self.Buffer and (self.Buffer.RandomBack or 0) > 0 then
		self.Buffer.RandomBack = 0
		self.Buffer.RandomForward = math.max(self.Buffer.RandomForward or 0, 12)
		self.LvsTurnTo = math.NormalizeAngle(self:GetAngles().y + 180)
	end

	-- Горячая перезагрузка DRR пересоздаёт таблицу Weapons: возвращаем
	-- своё оружие, иначе база падает на Weapons["Cryo"] == nil
	if DRONES_REWRITE and DRONES_REWRITE.LvsCryoDef then
		DRONES_REWRITE.Weapons = DRONES_REWRITE.Weapons or {}

		if not DRONES_REWRITE.Weapons["Cryo"] then
			DRONES_REWRITE.Weapons["Cryo"] = DRONES_REWRITE.LvsCryoDef
		end
	end

	-- Ошибка внутри базового Think не должна замораживать дрон:
	-- раньше исключение обрывало весь тик, и наш ИИ/движение не выполнялись
	if self.BaseClass and self.BaseClass.Think then
		local ok, err = pcall(self.BaseClass.Think, self)

		if not ok and CurTime() > (self.LvsBaseErrAt or 0) then
			self.LvsBaseErrAt = CurTime() + 5
			print("[LVS] base Think: " .. tostring(err))
		end
	end

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
	elseif self.LvsAutonomous and not IsValid(self:GetDriver()) then
		-- без цели и без пилота камера плавно смотрит по курсу
		local want = self:GetAngles()

		if self.CamAngles then
			self.CamAngles = LerpAngle(math.Clamp(FrameTime() * 3, 0, 1), self.CamAngles, want)
		else
			self.CamAngles = want
		end
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

		-- вода не входит в MASK_SOLID, поэтому трасса «земли» её не видит:
		-- дрон уходил под воду и садился на дно. Поверхность воды считаем
		-- твёрдой опорой, чтобы он висел над ней.
		local water = util.TraceLine({
			start  = pos,
			endpos = pos - Vector(0, 0, 3000),
			filter = { self },
			mask   = MASK_WATER,
		})

		local surface = water.Hit and water.HitPos.z or nil

		-- уже под водой: ищем поверхность вверх, иначе останется на дне
		if util.PointContents(pos) and bit.band(util.PointContents(pos), CONTENTS_WATER) ~= 0 then
			local up = util.TraceLine({
				start  = pos,
				endpos = pos + Vector(0, 0, 3000),
				filter = { self },
				mask   = MASK_WATER,
			})

			if up.Hit then surface = up.HitPos.z end
		end

		if surface and (not self.LvsGroundZ or surface > self.LvsGroundZ) then
			self.LvsGroundZ = surface
		end

		-- потолок: в помещениях (d2_prison) высоту режет свод, а не земля
		-- Коробкой по габариту дрона, а не лучом из центра: свес крыши
		-- иначе виден только когда дрон уже врезался в него низом.
		local up = util.TraceHull({
			start  = pos,
			endpos = pos + Vector(0, 0, 3000),
			mins   = Vector(-58, -58, 0),
			maxs   = Vector(58, 58, 0),
			filter = { self },
			mask   = MASK_SOLID,
		})

		self.LvsCeilZ = up.Hit and up.HitPos.z or nil
	end

	-- рабочая высота над землёй с поправкой на потолок
	local minAlt = self.LvsMinAltitude or 800

	if self.LvsCeilZ then
		local head = self.LvsCeilZ - self:GetPos().z - 170
		if head > 150 then minAlt = math.min(minAlt, head) end
	end

	-- подъём только если сверху есть просвет под корпус
	local headroom = self.LvsCeilZ and (self.LvsCeilZ - self:GetPos().z) or 9999

	if self.LvsGroundZ and self.LvsAutonomous
		and self:GetPos().z < self.LvsGroundZ + minAlt
		and headroom > 190 then
		if self.ClickKey then self:ClickKey("Up") end
	end

	-- серво-гул двигателя: тихий на месте, воет в полёте
	if now > (self.LvsServoAt or 0) then
		self.LvsServoAt = now + 0.15
		self:LvsServoUpdate()
	end

	if self.BoneIDs then
		-- клиент подстраивает HUD под перф-режим
		local perfNow = self:LvsPerf()

		if self.LvsPerfNW ~= perfNow then
			self.LvsPerfNW = perfNow
			self:SetNWBool("LvsPerf", perfNow)
		end

		-- тяжёлые пересчёты — реже кадра (визуально не заметно, нагрузка ниже)
		if now > (self.LvsNextHitbox or 0) then
			self.LvsNextHitbox = now + (self:LvsPerf() and 1/20 or 1/75)

			-- без игроков поблизости хитбоксы можно не двигать
			if not self:LvsPerf() or self:LvsNearPlayers(6000) then
				self:LvsUpdateHitboxes()
			end
		end

		-- Манипуляции костями реплицируются: в perf обновляем реже
		if not self:LvsPerf() or now > (self.LvsNextAim or 0) then
			self.LvsNextAim = now + 0.05
			self:UpdateHead()
			self:UpdateWeaponAim()
		end

		if now > (self.LvsNextTentacle or 0) then
			-- обычный режим: каждый тик сервера (66 по умолчанию, до 100 с -tickrate);
			-- угол кости всё равно не придёт чаще тика, поэтому интервал -tickrate
			self.LvsNextTentacle = now + (self:LvsPerf() and 1/50 or 1/90)
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
			local step = max * (self.LvsRegenRate or 0.01)

			-- чинится всегда, пока жив: медленно, 1% в секунду.
			-- Щит здесь не снимаем: раньше он слетал на полном HP, а скан
			-- ставил его обратно — модуль мигал и звучал каждую секунду
			if hp < max then
				self:SetHealthAmount(math.min(max, hp + step))
			end

			-- страховка: HP ниже минимального порога — поднимаем щит.
			-- Только в автономном режиме: в ручном щит ставит пилот
			if self.LvsAutonomous and hp < max * 0.2 and not self:HasModule("Shield") then
				self:LvsReviveShield()
			end
		end
	end

	if aiActive and self.LvsAutonomous and now > (self.LvsNextAiScan or 0) then
			self.LvsNextAiScan = now + (self:LvsPerf() and 0.7 or 0.5)
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
	self.LvsServo:ChangePitch(55 + 42 * frac)
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

	if DRONES_REWRITE and DRONES_REWRITE.LvsCryoDef then
		DRONES_REWRITE.Weapons = DRONES_REWRITE.Weapons or {}

		if not DRONES_REWRITE.Weapons["Cryo"] then
			DRONES_REWRITE.Weapons["Cryo"] = DRONES_REWRITE.LvsCryoDef
		end
	end

	if self.BaseClass and self.BaseClass.OnRemove then
		self.BaseClass.OnRemove(self)
	end
end