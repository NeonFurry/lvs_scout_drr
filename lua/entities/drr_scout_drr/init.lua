include("shared.lua")
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

local SEGS_PER_ROPE = 13

util.AddNetworkString("drr_scout_set_skin")
util.AddNetworkString("drr_scout_set_shield")

util.AddNetworkString("drr_scout_shield_down")
util.AddNetworkString("drr_scout_shield_block")
util.AddNetworkString("drr_scout_shield_hit")
util.AddNetworkString("drr_scout_auto")
util.AddNetworkString("drr_scout_auto_all")
util.AddNetworkString("drr_scout_auto_stats")
util.AddNetworkString("drr_scout_auto_stats_res")
util.AddNetworkString("drr_scout_squad_list")
util.AddNetworkString("drr_scout_muzzle")
util.AddNetworkString("drr_scout_emp")
util.AddNetworkString("drr_scout_setting")
util.AddNetworkString("drr_scout_getsetting")
util.AddNetworkString("drr_scout_state")
util.AddNetworkString("drr_scout_heavy_alert")
util.AddNetworkString("drr_scout_mark_clear")
util.AddNetworkString("drr_scout_hitmark")
util.AddNetworkString("drr_scout_leader")

-- Защита сетевых запросов: кулдаун на игрока и проверка, что дрон его
local function netAllowed(ply, key, perSecond)
	if not IsValid(ply) then return false end

	local at = ply.DrrNetAt

	if not at then
		at = {}
		ply.DrrNetAt = at
	end

	local now = CurTime()

	if now < (at[key] or 0) then return false end

	at[key] = now + 1 / perSecond
	return true
end

-- Дрон, которым сейчас управляет игрок; чужие запросы отбрасываем
local function playerDrone(ply)
	local drone = IsValid(ply) and ply:GetNWEntity("DronesRewriteDrone")

	if not IsValid(drone) or drone:GetClass() ~= "drr_scout_drr" then return end

	local owner = drone.Owner or drone:GetOwner()

	if IsValid(owner) and owner ~= ply then return end

	return drone
end

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
local DrrNavCache, DrrNavCacheAt = nil, 0
local DrrNodeCache, DrrNodeCacheAt = nil, 0

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
			print("[DRR Scout] Кость не найдена: " .. name)
		end
	end

	-- Все кости щупалец из модели, а не только первые 13 сегментов:
	-- так анимируются любые дополнительные сегменты и фаланги
	self.DrrRopeBones = {}
	self.DrrClawBones = {}

	for i = 0, self:GetBoneCount() - 1 do
		local name = string.lower(self:GetBoneName(i))

		local tent, seg = name:match("^rope(%d+)_seg(%d+)$")

		if tent then
			tent, seg = tonumber(tent), tonumber(seg)

			self.DrrRopeBones[tent] = self.DrrRopeBones[tent] or {}
			table.insert(self.DrrRopeBones[tent], { id = i, seg = seg })
		else
			local claw, part = name:match("^claw_rope(%d+)_(%d+)$")

			if claw then
				claw, part = tonumber(claw), tonumber(part)

				self.DrrClawBones[claw] = self.DrrClawBones[claw] or {}
				table.insert(self.DrrClawBones[claw], { id = i, part = part })
			else
				local base = name:match("^claw_rope(%d+)$")

				if base then
					base = tonumber(base)

					self.DrrClawBones[base] = self.DrrClawBones[base] or {}
					table.insert(self.DrrClawBones[base], { id = i })
				end
			end
		end
	end

	-- сегменты в модели могут идти не по порядку
	local segs, claws = 0, 0

	for _, list in pairs(self.DrrRopeBones) do
		table.sort(list, function(a, b) return (a.seg or 0) < (b.seg or 0) end)
		segs = segs + #list
	end

	for _, list in pairs(self.DrrClawBones) do
		claws = claws + #list
	end

	print(string.format("[DRR Scout] кости щупалец: %d сегментов, %d клешней", segs, claws))
end

-- Помеченная цель: проверяем только друзей и живость. Лимит дронов на цель
-- (claimed) не мешает — игрок указал цель явно и вправе перекинуть на неё дрона
function ENT:DrrMarkOk(e)
	if not IsValid(e) or e == self then return false end
	if e:GetClass() == "drr_scout_drr" then return false end

	-- только настоящие цели: bullseye, info_target и прочие служебные сущности
	-- иначе метка ставится на невидимую точку прицела
	if not (e:IsNPC() or e:IsNextBot() or e:IsPlayer()) then return false end

	if self.DrrFriendClasses then
		if self.DrrFriendClasses[e:GetClass()] then return false end
		if e:IsPlayer() and self.DrrFriendClasses["@" .. e:SteamID()] then return false end
	end

	if e.Health and (e:Health() or 0) <= 0 then return false end

	return true
end

-- Точка, в которую целятся NPC: середина шеи (между Bip01_Neck и
-- Bip01_Head). Раньше брали голову — она выше корпуса, и страйдер бил поверх.
function ENT:DrrNeckPos()
	local neck = self:LookupBone("Bip01_Neck")
	local head = self:LookupBone("Bip01_Head")

	local pn = neck and self:GetBonePosition(neck)
	local ph = head and self:GetBonePosition(head)

	if isvector(pn) and isvector(ph) then
		return (pn + ph) * 0.5
	end

	return pn or ph
end

local function drrFallbackCenter(self)
	return self:LocalToWorld(self:OBBCenter())
end

function ENT:WorldSpaceCenter()
	return self:DrrNeckPos() or drrFallbackCenter(self)
end

-- Некоторые NPC берут BodyTarget, а не WorldSpaceCenter
function ENT:BodyTarget(pos, child)
	return self:DrrNeckPos() or drrFallbackCenter(self)
end

-- Хитбоксы-прокси: следуют за костями, урон перенаправляется в дрон
function ENT:DrrBuildHitboxes()
	self.DrrHitboxes = {}

	local function add(boneID, half)
		if not boneID then return end

		local e = ents.Create("drr_scout_hitbox")
		if not IsValid(e) then return end

		e.DrrDrone = self
		e.DrrHalf = half
		e:Spawn()

		self.DrrHitboxes[#self.DrrHitboxes + 1] = { ent = e, bone = boneID }
	end

	-- голова и щупальца крупнее тела: кубик 8 юнитов пули почти всегда
	-- облетали, и попадания по ним не засчитывались
	add(self.BoneIDs.Head, 26)

	-- только нужное: клешни и их фаланги (кончики щупалец). Сегменты и тело
	-- закрывает сам дрон; прокси на каждую кость — лишние сущности и лаги
	for _, list in pairs(self.DrrClawBones or {}) do
		for _, b in ipairs(list) do
			add(b.id, b.part and 9 or 13)
		end
	end

	-- если разбор костей не дал клешней, берём по схеме имён
	if not next(self.DrrClawBones or {}) then
		for i = 1, self.TentacleCount do
			add(self.BoneIDs["Claw" .. i], 13)

			for c = 1, 3 do
				add(self.BoneIDs[string.format("Claw%dPart%d", i, c)], 9)
			end
		end
	end
end

function ENT:DrrUpdateHitboxes()
	-- миграция старых prop_dynamic-прокси на новый класс
	local first = self.DrrHitboxes and self.DrrHitboxes[1]
	if first and IsValid(first.ent) and first.ent:GetClass() ~= "drr_scout_hitbox" then
		self:DrrRemoveHitboxes()
		self:DrrBuildHitboxes()
	end

	-- позиции костей берём матрицами: GetBonePosition считает от закешированной
	-- позы и на анимированных костях отстаёт от модели — прокси «отрывались»
	for _, h in ipairs(self.DrrHitboxes or {}) do
		if IsValid(h.ent) then
			local m = self:GetBoneMatrix(h.bone)

			if m then h.ent:SetPos(m:GetTranslation()) end
		end
	end
end

function ENT:DrrRemoveHitboxes()
	for _, h in ipairs(self.DrrHitboxes or {}) do
		if IsValid(h.ent) then h.ent:Remove() end
	end

	self.DrrHitboxes = nil
end

function ENT:DrrNearAnyBone(pos, radius)
	local r2 = radius * radius

	for i = 0, self:GetBoneCount() - 1 do
		local b = self:GetBonePosition(i)
		if b and b:DistToSqr(pos) <= r2 then return true end
	end

	return false
end

-- Кейс-модуль срабатывает при касании любой части дрона (голова, щупальца и т.д.)
function ENT:DrrCheckModulePickup()
	if not self.AddModule then return end
	if IsValid(self:GetDriver()) then return end

	for _, e in ipairs(ents.FindByClass("dronesrewrite_upgrcase_*")) do
		if IsValid(e) and self:DrrNearAnyBone(e:WorldSpaceCenter(), 40) then
			if self:AddModule(e.PrintName) then e:Remove() end
		end
	end
end

-- Уклонение: после попадания кратко стрейфим, если щит не активен
hook.Remove("EntityTakeDamage", "drr_scout_dodge")
hook.Add("EntityTakeDamage", "drr_scout_dodge", function(ent, dmg)
	if not IsValid(ent) or ent:GetClass() ~= "drr_scout_drr" or not ent.DrrAutonomous then return end

	-- Попадание тяжёлой техники (страйдер, вертолёт, ганшип, хантер) —
	-- тоже повод надеть щит, даже если цель ещё не в поле зрения сканера
	local att = dmg:GetAttacker()

	if not IsValid(att) then att = dmg:GetInflictor() end

	-- только живой тяжёлый юнит: снаряды умирающего страйдера
	-- иначе заново назначали бы мёртвую цель (щит мигал)
	local attAlive = IsValid(att) and (att.Health == nil
		or ((att:Health() or 0) > 0 and (not att.IsNPC or att:Alive())))

	if ent.DrrIsHeavy and ent:DrrIsHeavy(att) and attAlive and (dmg:GetDamage() or 0) > 0 then
		ent.DrrHeavyTarget = att

		-- щит надеваем сразу, не дожидаясь следующего скана ИИ
		if ent.AddModule and not ent:HasModule("Shield") and not ent.DrrShieldManual
			and CurTime() >= (ent.DrrShieldDownUntil or 0) then
			ent.DrrJamBreakAt = nil
			ent.DrrJamUse = nil
			ent.DrrShieldForHeavy = true
			ent:AddModule("Shield")
		end
	end

	if ent:HasModule("Shield") and (ent:GetNWInt("shield_health") or 0) > 0 then return end

	local now = CurTime()

	-- кулдаун: под плотным огнём не уходим в бесконечный стрейф
	if now > (ent.DrrDodgeNext or 0) then
		ent.DrrDodgeNext = now + 1.6
		ent.DrrDodgeUntil = now + 1.4
		ent.DrrDodgeDir = (ent.DrrDodgeDir == "left") and "right" or "left"
	end
end)

-- Щит гасит урон по любой части дрона, включая прокси головы и щупалец:
-- часть урона приходила мимо ветки щита в OnTakeDamage
hook.Add("EntityTakeDamage", "drr_scout_shield_guard", function(ent, dmg)
	local drone = ent

	if IsValid(ent) and ent:GetClass() == "drr_scout_hitbox" then
		drone = ent.DrrDrone
	end

	if not IsValid(drone) or drone:GetClass() ~= "drr_scout_drr" then return end
	if not (drone.HasModule and drone:HasModule("Shield")) then return end
	if not (drone.Buffer and (drone.Buffer.ShieldHealth or 0) > 0) then return end

	dmg:SetDamage(0)
	dmg:SetDamageForce(vector_origin)
end)

-- Свои дроны не сталкиваются между собой: в строю они постоянно врезались
-- друг в друга. Работает через ShouldCollide, а не группы коллизий —
-- группы ломали подбор предметов и тулкит.
-- дрон или его прокси-хитбокс -> сам дрон (для сравнения владельцев)
local function drrDroneOf(e)
	if not IsValid(e) then return end
	if e:GetClass() == "drr_scout_drr" then return e end

	if e:GetClass() == "drr_scout_hitbox" and IsValid(e.DrrDrone) then
		return e.DrrDrone
	end
end

hook.Add("ShouldCollide", "drr_scout_no_drone_collide", function(a, b)
	-- при кастомной проверке nil считается запретом: всё лишнее разрешаем явно
	local da, db = drrDroneOf(a), drrDroneOf(b)

	if not da or not db then return true end

	local oa = da.Owner or da:GetOwner()
	local ob = db.Owner or db:GetOwner()

	if oa ~= nil and oa == ob then return false end

	return true
end)

function ENT:Initialize()
	self.BaseClass.Initialize(self)

	-- радар DRR пропускает дронов с NoDRRRadar; сбрасываем флаг, если модуля
	-- «Invisible for radar» на дроне нет
	if not (self.HasModule and self:HasModule("Invisible for radar")) then
		self:SetNWBool("NoDRRRadar", false)
	end

	-- автономный модуль по умолчанию выключен
	self.DrrAutonomous = false
	self.DrrHomePos = self:GetPos()
	self.DrrPatrolAltitudeMin = self.DrrPatrolAltitudeMin or 700
	self.DrrPatrolAltitudeMax = self.DrrPatrolAltitudeMax or 1200
	self:SetNWBool("DrrAuto", false)

	-- командование и строй не переживают переспавн: стая не должна оживать сама
	self.DrrCommander = nil
	self:SetNWBool("DrrCommander", false)
	self.DrrPatrolPos = nil
	self.DrrPatrolAt = 0

	-- дружественные классы NPC (переживают переспавн: копия с владельца)
	self.DrrFriendClasses = {}

	if IsValid(self.Owner) and self.Owner.DrrFriendClasses then
		self.DrrFriendClasses = table.Copy(self.Owner.DrrFriendClasses)
	end

	-- владелец в сеть: клиент красит свои дроны отдельным цветом на радаре
	if IsValid(self.Owner) then
		self:SetNWEntity("DrrOwner", self.Owner)
		self:SetNWString("DrrOwnerID", self.Owner:SteamID())
	end

	-- флаг ставится на энтити, а не на физобъект: иначе ShouldCollide не зовётся
	if self.SetCustomCollisionCheck then
		pcall(self.SetCustomCollisionCheck, self, true)
	end

	-- у физобъектов имя метода другое; ставим, если доступно
	for i = 0, math.max((self:GetPhysicsObjectCount() or 1) - 1, 0) do
		local phys = self:GetPhysicsObjectNum(i)

		if IsValid(phys) then
			if phys.EnableCustomCollisionCheck then
				pcall(phys.EnableCustomCollisionCheck, phys)
			elseif phys.SetCustomCollisionCheck then
				pcall(phys.SetCustomCollisionCheck, phys, true)
			end
		end
	end

	self:ResolveBones()
	self:DrrBuildHitboxes()

	-- модель не должна играть свои анимации: они перезаписывают движения костей
	if self.SetPlaybackRate then self:SetPlaybackRate(0) end

	-- восстанавливаем выбранную расцветку (0 — обычная, 1 — красная)
	local skin = self:GetNWInt("DrrSkin", 0)
	if skin > 0 then self:SetSkin(skin) end

	for i = 1, self.TentacleCount do
		self["TentaclePhase" .. i] = math.Rand(0, math.pi * 2)
	end

	self:UpdateCameraPos()

	-- синхронизация состояния щита для клиента (визуал + меню F3)
	local tname = "drr_scout_shield_sync_" .. self:EntIndex()
	timer.Create(tname, 0.5, 0, function()
		if not IsValid(self) then timer.Remove(tname) return end

		local has = self:HasModule("Shield")
		if self:GetNWBool("hasModuleShield") ~= has then self:SetNWBool("hasModuleShield", has) end
	end)
end

-- Расцветка: 0 — обычная, 1 — красная (переключение)
function ENT:DrrSetSkin(index)
	-- лидер всегда красный, пока выбран командным
	if self.DrrCommander and index ~= 1 then index = 1 end

	self.DrrSkin = index
	self:SetSkin(index)
	self:SetNWInt("DrrSkin", index)
end

function ENT:DrrToggleSkin()
	self:DrrSetSkin((self:GetSkin() == 0) and 1 or 0)
end

net.Receive("drr_scout_set_skin", function(_, ply)
	if not netAllowed(ply, "skin", 5) then return end

	local drone = playerDrone(ply)
	if not drone then return end

	drone:DrrSetSkin(net.ReadUInt(8))
end)

net.Receive("drr_scout_set_shield", function(_, ply)
	if not netAllowed(ply, "shield", 8) then return end

	local drone = playerDrone(ply)
	if not drone then return end

	local on = net.ReadBool()

	-- ручное решение игрока: автоматика ИИ его больше не трогает
	drone.DrrShieldManual = on

	if on then
		-- после джаммера щит заблокирован до конца перезарядки
		local left = (drone.DrrShieldDownUntil or 0) - CurTime()

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
-- Перегрев криолуча: 0 в drr_scout_cryo_heat полностью отключает его
if not ConVarExists("drr_scout_cryo_heat") then
	CreateConVar("drr_scout_cryo_heat", "10", FCVAR_ARCHIVE, "Секунд до перегрева криолуча; 0 — без перегрева")
end

if not ConVarExists("drr_scout_cryo_cool") then
	CreateConVar("drr_scout_cryo_cool", "2.5", FCVAR_ARCHIVE, "Секунд на остывание криолуча")
end

-- стая: следование за командным дроном, тип строя и его дистанция
if not ConVarExists("drr_scout_follow") then
	CreateConVar("drr_scout_follow", "0", FCVAR_ARCHIVE, "Дроны держат строй за командным дроном: 1 — вкл")
end

if not ConVarExists("drr_scout_formation") then
	CreateConVar("drr_scout_formation", "0", FCVAR_ARCHIVE, "Строй стаи: 0 клин, 1 колонна, 2 круг, 3 линия")
end

if not ConVarExists("drr_scout_form_dist") then
	CreateConVar("drr_scout_form_dist", "620", FCVAR_ARCHIVE, "Дистанция между дронами в строю")
end

-- минимум 620: старые сохранённые значения ниже поднимаем один раз
do
	local fd = GetConVar("drr_scout_form_dist")

	if fd and fd:GetFloat() < 620 then fd:SetFloat(620) end
end

if not ConVarExists("drr_scout_patrol") then
	CreateConVar("drr_scout_patrol", "0", FCVAR_ARCHIVE, "Патруль вокруг своей точки: 1 — вкл, 0 — свободный полёт по карте")
end

local DRR_SETTINGS_ALLOW = {
	drr_scout_perf = true,
	drr_scout_ai_range = true,
	drr_scout_engage_range = true,
	drr_scout_nav_mode = true,
	drr_scout_swarm = true,
	drr_scout_cryo_heat = true,
	drr_scout_cryo_cool = true,
	drr_scout_debug = true,
	drr_scout_follow = true,
	drr_scout_formation = true,
	drr_scout_form_dist = true,
	drr_scout_patrol = true,
}

net.Receive("drr_scout_setting", function(_, ply)
	if not netAllowed(ply, "setting", 10) then return end

	local key = net.ReadString()
	local value = net.ReadString()

	if not DRR_SETTINGS_ALLOW[key] then return end

	local cv = GetConVar(key)

	-- конвар создаётся аддоном; неизвестный ключ игнорируем
	if not cv then return end

	cv:SetString(tostring(value))
end)

-- Клиент спрашивает текущие настройки при открытии панели
net.Receive("drr_scout_getsetting", function(_, ply)
	if not netAllowed(ply, "getsetting", 10) then return end

	local function num(name, default)
		local cv = GetConVar(name)
		return cv and cv:GetInt() or default
	end

	net.Start("drr_scout_state")
	net.WriteInt(num("drr_scout_perf", 1), 8)
	net.WriteInt(num("drr_scout_ai_range", 16000), 32)
	net.WriteInt(num("drr_scout_nav_mode", 1), 8)
	net.WriteInt(num("drr_scout_engage_range", 0), 32)
	net.WriteInt(num("drr_scout_swarm", 0), 8)
	net.WriteFloat(GetConVar("drr_scout_cryo_heat") and GetConVar("drr_scout_cryo_heat"):GetFloat() or 10)
	net.WriteFloat(GetConVar("drr_scout_cryo_cool") and GetConVar("drr_scout_cryo_cool"):GetFloat() or 2.5)
	net.WriteInt(num("drr_scout_follow", 0), 8)
	net.WriteInt(num("drr_scout_formation", 0), 8)
	net.WriteInt(num("drr_scout_form_dist", 400), 32)
	net.WriteInt(num("drr_scout_patrol", 0), 8)

	local pilot = playerDrone(ply)
	net.WriteInt((IsValid(pilot) and pilot.DrrCommander) and 1 or 0, 8)

	net.Send(ply)
end)

-- диагностика строя: drr_scout_squad в консоли сервера/клиента
concommand.Add("drr_scout_squad", function(ply)
	local function cv(n)
		local c = GetConVar(n)
		return c and c:GetString() or "?"
	end

	print("[DRR] follow=" .. cv("drr_scout_follow") .. " formation=" .. cv("drr_scout_formation")
		.. " dist=" .. cv("drr_scout_form_dist") .. " patrol=" .. cv("drr_scout_patrol") .. " nav=" .. cv("drr_scout_nav_mode"))

	local followers = 0

	for _, d in ipairs(ents.FindByClass("drr_scout_drr")) do
		if IsValid(d) and d:DrrFollowLeader() then followers = followers + 1 end
	end

	print("[DRR] followers=" .. followers)

	for _, d in ipairs(ents.FindByClass("drr_scout_drr")) do
		if IsValid(d) and (not IsValid(ply) or d.Owner == ply) then
			local lead = d:DrrFollowLeader()
			local dist = lead and d:GetPos():Distance(lead:GetPos()) or -1
			local dc = GetConVar("drr_scout_form_dist")

			print(string.format("[DRR] drone %d auto=%s cmd=%s leader=%s pos=%s dist=%d keep=%d yaw=%s ang=%s spd=%d",
				d:EntIndex(), tostring(d.DrrAutonomous), tostring(d.DrrCommander),
				tostring(lead ~= nil), tostring(d.DrrPatrolPos), math.floor(dist),
				math.floor((dc and dc:GetFloat() or 400) * 1.25),
				tostring(d.DrrPatrolYaw and math.floor(d.DrrPatrolYaw) or "nil"),
				math.floor(d:GetAngles().y), math.floor(d:GetVelocity():Length())))
		end
	end
end)

-- командный дрон: назначение с клиента (F3 → НАСТРОЙКИ ИИ)
net.Receive("drr_scout_leader", function(_, ply)
	if not netAllowed(ply, "leader", 4) then return end

	local drone = playerDrone(ply)
	if not drone then return end

	local on = drone:DrrSetCommander(not drone.DrrCommander)

	ply:ChatPrint(on and "[DRR Scout] Командный дрон назначен" or "[DRR Scout] Командный дрон снят")
end)

net.Receive("drr_scout_emp", function(_, ply)
	if not netAllowed(ply, "emp", 2) then return end

	local drone = playerDrone(ply)
	if not drone then return end

	local left = (drone.DrrEmpAt or 0) - CurTime()

	if left > 0 then
		return
	end

	local n = drone:DrrEmp()

end)

-- Hit-маркер: сообщаем владельцу, что его выстрел дошёл до цели
local function attackerDrone(att)
	if not IsValid(att) then return end
	if att:GetClass() == "drr_scout_drr" then return att end
	if IsValid(att.DrrDrone) then return att.DrrDrone end

	local own = att:GetOwner()

	if IsValid(own) and own:GetClass() == "drr_scout_drr" then return own end
end

hook.Remove("PostEntityTakeDamage", "drr_scout_hitmark")

hook.Add("PostEntityTakeDamage", "drr_scout_hitmark", function(ent, dmg, took)
	if not took or not IsValid(ent) then return end
	if ent:GetClass() == "drr_scout_drr" then return end

	local drone = attackerDrone(dmg:GetAttacker())
	if not drone then return end

	local owner = drone.Owner or drone:GetOwner()
	if not IsValid(owner) or not owner:IsPlayer() then return end
	if CurTime() < (drone.DrrHitAt or 0) then return end

	drone.DrrHitAt = CurTime() + 0.05

	net.Start("drr_scout_hitmark")
	net.WriteBool(ent:IsNPC() and (ent:Health() or 0) <= 0)
	net.Send(owner)
end)

-- Стазис: пока луч горит, враги рядом с дроном замедляются
hook.Remove("Think", "drr_scout_stasis")

hook.Add("Think", "drr_scout_stasis", function()
	if CurTime() < (DrrStasisAt or 0) then return end
	DrrStasisAt = CurTime() + 0.25

	for _, drone in ipairs(ents.FindByClass("drr_scout_drr")) do
		if IsValid(drone) and drone:GetNWBool("DrrCryoActive") then
			local pos = drone:GetPos()

			for _, npc in ipairs(ents.FindInSphere(pos, 450)) do
				if IsValid(npc) and npc:IsNPC() and npc:GetVelocity():Length() > 40 then
					npc:SetLocalVelocity(npc:GetVelocity() * 0.55)
				end
			end
		end
	end
end)

-- Аура Ремонта: дроны одного владельца рядом друг с другом чинятся
hook.Remove("Think", "drr_scout_repair_aura")

-- Один владелец: .Owner бывает пуст, поэтому сверяем ещё и сетевой SteamID
local function drrSameOwner(a, b)
	if not IsValid(a) or not IsValid(b) then return false end

	local oa = a.Owner or a:GetOwner()
	local ob = b.Owner or b:GetOwner()

	if IsValid(oa) and IsValid(ob) then return oa == ob end

	local sa = a:GetNWString("DrrOwnerID", "")
	local sb = b:GetNWString("DrrOwnerID", "")

	return sa ~= "" and sa == sb
end

hook.Add("Think", "drr_scout_repair_aura", function()
	if CurTime() < (DrrRepairAt or 0) then return end
	DrrRepairAt = CurTime() + 1

	for _, drone in ipairs(ents.FindByClass("drr_scout_drr")) do
		if IsValid(drone) then
			local pos = drone:GetPos()

			for _, other in ipairs(ents.FindByClass("drr_scout_drr")) do
				if other ~= drone and IsValid(other)
					and drrSameOwner(drone, other)
					and other:GetPos():DistToSqr(pos) <= 700 * 700 then
					local hp = other:GetHealth() or 0

					-- GetMaxHealth у дронов DRR всегда 0: реальный максимум в DefHealth
					local max = other:GetDefaultHealth() or 0

					if max <= 0 then max = other:GetMaxHealth() or 0 end

					if hp > 0 and hp < max then
						-- у дронов DRR здоровье живёт в HealthAmount, а не в m_iHealth
						if other.SetHealthAmount then
							other:SetHealthAmount(math.min(max, hp + 2))
						else
							other:SetHealth(math.min(max, hp + 2))
						end
					elseif max > 0 and hp <= 0 then
						-- подбитого тоже поднимаем: стая ремонтирует мёртвого
						local step = math.max(3, max * 0.01)

						if other.SetHealthAmount then
							other:SetHealthAmount(math.min(max, hp + step))
						else
							other:SetHealth(math.min(max, hp + step))
						end
					end
				end
			end
		end
	end
end)

properties.Add("drr_scout_skin_toggle", {
	MenuLabel = "DRR Scout: переключить расцветку",
	MenuIcon = "icon16/paintbrush.png",

	Filter = function(self, ent)
		return IsValid(ent) and ent:GetClass() == "drr_scout_drr"
	end,

	Action = function(self, ent)
		ent:DrrToggleSkin()
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
	local friends = self.DrrFriendClasses

	if friends and class and friends[class] then return false end

	local base = self.BaseClass

	if base and base.IsEnemy then return base.IsEnemy(self, class) end

	-- без базы считаем врагом: иначе НПС перестали бы замечать все дроны
	return true
end

-- Точка попадания рядом с реальными костями (щупальца, голова, корпус)
function ENT:DrrHitVisiblePart(pos)
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
function ENT:DrrNotifyShieldDown(ply, force)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if not force and CurTime() < (ply.DrrShieldMsg or 0) then return end

	ply.DrrShieldMsg = CurTime() + 1

	net.Start("drr_scout_shield_down")
	net.WriteEntity(self)
	net.WriteFloat(math.max((self.DrrShieldDownUntil or 0) - CurTime(), 0))
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
function ENT:DrrEmp()
	local owner = self.Owner or self:GetOwner()
	local pos = self:GetPos()
	local hit = 0

	self.DrrEmpAt = CurTime() + 30
	self:SetNWFloat("DrrEmpReadyAt", self.DrrEmpAt)

	-- визуал, вспышка и ослепление НПС/игроков
	if DrrEmpApply then DrrEmpApply(pos, owner) end

	self:EmitSound("ambient/levels/labs/electric_explosion1.wav", 95, 85)
	self:EmitSound("ambient/energy/weld2.wav", 90, 70)

	for _, d in ipairs(ents.FindByClass("drr_scout_drr")) do
		if IsValid(d) and d ~= self then
			local o = d.Owner or d:GetOwner()

			if o ~= owner and d:GetPos():DistToSqr(pos) < 2000 * 2000 then
				d.DrrStunnedUntil = CurTime() + 3
				d:TakeDamage(80, self, self)
				hit = hit + 1
			end
		end
	end

	return hit
end
-- Одно применение джаммера: щит тратится на 1/N и сбивается на случайном N-м
function ENT:DrrJammerDrain(attacker)
	if not (self.HasModule and self:HasModule("Shield")) then return end
	if (self.Buffer.ShieldHealth or 0) <= 0 then return end

	if not self.DrrJamBreakAt then
		self.DrrJamBreakAt = rollJamBreak()
		self.DrrJamUse = 0
	end

	self.DrrJamUse = (self.DrrJamUse or 0) + 1

	local step = (self.Buffer.ShieldMax or 60) / self.DrrJamBreakAt
	self.Buffer.ShieldHealth = math.max((self.Buffer.ShieldHealth or 0) - step, 0)
	self:SetNWInt("shield_health", math.max(math.floor(self.Buffer.ShieldHealth), 0))

	-- пока щит сбивается джаммером, он не должен восстанавливаться сам
	self.DrrShieldLocked = true
	self.DrrShieldLockHP = self.Buffer.ShieldHealth
	timer.Destroy("dronesrewrite_regen" .. self:EntIndex())

	if self.DrrJamUse < self.DrrJamBreakAt then return end

	self.DrrJamBreakAt = nil
	self.DrrJamUse = nil
	self.Buffer.ShieldHealth = 0
	self.DrrShieldDownUntil = CurTime() + SHIELD_REGEN_DELAY
	self:SetNWFloat("DrrShieldRestoreAt", self.DrrShieldDownUntil)

	if IsValid(attacker) and attacker:IsPlayer() then
		self:DrrNotifyShieldDown(attacker, true)
	end

	local tname = "drr_shield_regen" .. self:EntIndex()

	timer.Create(tname, SHIELD_REGEN_DELAY, 1, function()
		if not IsValid(self) then return end

		-- модуль мог быть снят уничтожением: снимаем блокировку, иначе
		-- щит больше никогда не включится
		if not self:HasModule("Shield") then
			self.DrrShieldDownUntil = nil
			self.DrrShieldLocked = nil
			self.DrrShieldLockHP = nil
			self:SetNWFloat("DrrShieldRestoreAt", 0)
			self.DrrJamBreakAt = nil
			self.DrrJamUse = nil
			return
		end

		self.Buffer.ShieldHealth = self.Buffer.ShieldMax
		self:SetNWInt("shield_health", math.floor(self.Buffer.ShieldMax))
		self.DrrShieldDownUntil = nil
		self.DrrShieldLocked = nil
		self.DrrShieldLockHP = nil
		self:SetNWFloat("DrrShieldRestoreAt", 0)
		self.DrrJamBreakAt = nil
		self.DrrJamUse = nil
	end)
end

-- Джаммер без ограничения дистанции: игрок смотрит на дрон и видит его
function ENT:DrrJamRemote(attacker)
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

		self:DrrNotifyShieldDown(attacker)
		return
	end

	-- одно применение = одна попытка сбить щит
	self:DrrJammerDrain(attacker)
end

function ENT:OnTakeDamage(dmg)	-- Пули должны цеплять только видимые части (кости), а не пустоту внутри коробки
	-- тяжёлое попадание не должно толкать корпус: анимация «дёргалась»
	dmg:SetDamageForce(vector_origin)

	if bit.band(dmg:GetDamageType(), DMG_BULLET) ~= 0 then
		local pos = dmg:GetDamagePosition()
		if not pos:IsZero() and not self:DrrHitVisiblePart(pos) then return end
	end

	local inflictor = dmg:GetInflictor()
	local isJammer = IsValid(inflictor) and inflictor:GetClass() == "weapon_drr_jammer"

	-- Джаммер не должен отключать дрон ни при каком состоянии щита
	if isJammer then self.DrrJamGrace = CurTime() + 0.5 end


	local attacker = dmg:GetAttacker()
	local shieldUp = self.HasModule and self:HasModule("Shield") and (self.Buffer.ShieldHealth or 0) > 0

	-- Щит уже спал: атакующему показываем время до восстановления
	if not shieldUp then self:DrrNotifyShieldDown(attacker) end

	if shieldUp then
		if IsValid(attacker) and attacker:IsPlayer() and CurTime() > (attacker.DrrShieldMsg or 0) then
			attacker.DrrShieldMsg = CurTime() + 1

			-- плашка на экране самого стрелка: щит не пробить
			net.Start("drr_scout_shield_block")
			net.Send(attacker)
		end

		local pos = dmg:GetDamagePosition()

		if not pos:IsZero() then
			ParticleEffect("blade_glow_drr", pos, Angle(0, 0, 0))

			-- рябь на щите: клиент рисует вспышку в точке удара
			net.Start("drr_scout_shield_hit")
			net.WriteUInt(self:EntIndex(), 16)
			net.WriteVector(pos)
			net.Broadcast()
		end

		self:EmitSound("ambient/energy/weld2.wav", 100, 255, 1)

		-- Щит тратится только джаммером DRR (два удара за применение)
		if isJammer then
			self.DrrJamNativeAt = CurTime()
			self:DrrJammerDrain(attacker)
		end

		return
	end

	-- флинч щупалец только по реальному урону и не чаще 4 раз в секунду:
	-- иначе плотный огонь дёргал дрона непрерывно
	if dmg:GetDamage() >= 1 and CurTime() > (self.DrrFlinchOpenAt or 0) then
		self.DrrFlinchOpenAt = CurTime() + 0.25
		self.DrrFlinchAt = CurTime()
		self.DrrFlinchSide = (math.random(0, 1) == 1) and 1 or -1
	end

	-- Без отбрасывания от попаданий
	dmg:SetDamageForce(vector_origin)

	return self.BaseClass.OnTakeDamage(self, dmg)
end

-- Джаммер не отключает дрон: игнорируем его SetEnabled(false)
function ENT:SetEnabled(state)
	if not state and CurTime() < (self.DrrJamGrace or 0) then return end

	return self.BaseClass.SetEnabled(self, state)
end

-- Точка, куда смотрит камера пилота (та же, что у оружий DRR)
function ENT:GetAimPoint()
	local cam = self:GetCamera()
	if not IsValid(cam) then cam = self end

	-- свои прокси-хитбоксы не должны перекрывать прицел
	local filter = { cam, self }

	for _, h in ipairs(self.DrrHitboxes or {}) do
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
	if self.DrrAutonomous and not IsValid(self:GetDriver()) and not self.DrrAutoAngles then
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
	-- Вся анимация живёт в autorun/server/drr_scout_tentacles.lua:
	-- там оригинальные клипы Crysis, и правки применяются без перезахода карты
	if DrrTentacleUpdate then DrrTentacleUpdate(self) end
end

-- Кость оружия смотрит в точку прицела
function ENT:UpdateWeaponAim()
	if not self.BoneIDs.Weapon then return end

	if self.DrrAutonomous and not IsValid(self:GetDriver()) and not self.DrrAutoAngles then
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

	local rec = (self.DrrRecoil or 0) * math.pow(0.03, FrameTime())

	if firing then rec = math.min(rec + 2.2, 5.0) end

	self.DrrRecoil = rec

	target = Angle(math.Clamp(target.p - rec, -PITCH_LIMIT - 6, PITCH_LIMIT), target.y, 0)

	local cur = self:GetManipulateBoneAngles(self.BoneIDs.Weapon) or Angle(0, 0, 0)
	self:ManipulateBoneAngles(self.BoneIDs.Weapon, LerpAngle(math.min(FrameTime() * ARM_ROTATE_SPEED, 1), cur, target))
end

-- Мировая точка начала луча (кость оружия)
-- Точка вылета (луч/осколки): аттачмент moac_muzzle, fallback — кость оружия
function ENT:GetCryoStart()
	local pos = self:DrrAttachmentPos("moac_muzzle")
	if pos then return pos end

	local bone = self.BoneIDs and self.BoneIDs.Weapon
	if bone then
		local p = self:GetBonePosition(bone)
		if p then return p end
	end

	return self:GetPos()
end
-- ИИ: скан сквозь стены, щит при контакте, атака только видимых целей
function ENT:DrrCanSee(e)
	local filter = { self }

	for _, h in ipairs(self.DrrHitboxes or {}) do
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
function ENT:DrrFullVisible(e)
	if not IsValid(e) then return false end

	-- кэш 0.1 с: три трассы на каждый выстрел слишком дорого
	local now = CurTime()

	if self.DrrVisTarget == e and now < (self.DrrVisAt or 0) then
		return self.DrrVisOk == true
	end

	self.DrrVisTarget = e
	self.DrrVisAt = now + (self:DrrPerf() and 0.18 or 0.1)

	local filter = { self }

	for _, h in ipairs(self.DrrHitboxes or {}) do
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
			self.DrrVisOk = false
			return false
		end
	end

	self.DrrVisOk = true
	return true
end

-- Свободное направление: проверяем линию пути на 1200 юнитов.
-- Невидимые стены карты/скайбокс дают короткую трассу и отсекаются.
function ENT:DrrTraceFilter()
	local selfEnt = self
	local cam = self:GetCamera()

	-- игнорируем и свои прокси, и чужие дроны с их хитбоксами:
	-- иначе трасса «земли» упирается в соседа и дрон лезет вверх
	-- игнорируем и свои прокси, и чужие дроны с их хитбоксами:
	-- иначе трасса «земли» упирается в соседа и дрон лезет вверх
	local selfEnt = self
	local cam = self:GetCamera()

	return function(e)
		if e == selfEnt or e == cam then return true end

		local ok, c = pcall(e.GetClass, e)

		return ok and (c == "drr_scout_drr" or c == "drr_scout_hitbox")
	end
end

-- Свободен ли путь с учётом габаритов дрона (в узких коридорах линия врёт)
function ENT:DrrPathClear(yaw, distance, filter)
	local origin = self:WorldSpaceCenter()
	local m = self:OBBMaxs()
	local r = math.max(m.x, m.y) * 0.9

	local tr = util.TraceHull({
		start  = origin,
		endpos = origin + Angle(0, yaw, 0):Forward() * distance,
		mins   = Vector(-r, -r, -m.z * 0.5),
		maxs   = Vector(r, r, m.z * 0.5),
		filter = filter or self:DrrTraceFilter(),
		mask   = MASK_SOLID,
	})

	return tr.Fraction >= 0.95, tr
end

-- Есть ли под точкой навигационная сетка (NavMesh / AI nodes)
function ENT:DrrOverNavArea(pos)
	if not navmesh or not navmesh.GetNearestNavArea then return true end

	local area = navmesh.GetNearestNavArea(pos, true, 600, false, true)

	return area ~= nil
end

function ENT:DrrFreeYaw(base, distance)
	distance = distance or 1200

	local order = { 0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180 }
	local bestYaw, bestFrac, firstClear
	local origin = self:WorldSpaceCenter()

	for _, off in ipairs(order) do
		local yaw = math.NormalizeAngle(base + off)
		local clear, tr = self:DrrPathClear(yaw, distance)

		-- за краем карты пути нет: не выбираем курс в пустоту,
		-- иначе патруль упирается в границу и висит там
		if clear and not util.IsInWorld(origin + Angle(0, yaw, 0):Forward() * distance) then
			clear = false
		end

		if clear then
			-- приоритет направлениям, где внизу есть навигация: там ходят NPC
			local probe = origin + Angle(0, yaw, 0):Forward() * (distance * 0.6)

			local okNav, onNav = pcall(self.DrrNavMode, self)
			local navOk = okNav and onNav ~= 0

			if navOk then
				local okArea, area = pcall(self.DrrOverNavArea, self, probe)
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

-- ПРИОРИТЕТЫ УПРАВЛЕНИЯ
-- Слои ИИ больше не жмут клавиши напрямую: они заявляют намерение с весом.
-- Раз в шаг физики ENT:ControlsPhys выбирает старшее намерение, гасит
-- противоположные пары (Forward/Back, Up/Down, Strafe L/R) и только потом
-- отдаёт клавиши базе DRR. Один тик — одно решение, без драк слоёв.
DRR_PRIO = DRR_PRIO or {
	Pilot     = 100,
	Escape    = 96,
	Formation = 95,
	Retreat   = 90,
	Dodge     = 85,
	Combat    = 80,
	Patrol    = 55,
	Avoid     = 50,
	Turn      = 35,
	Vertical  = 30,
	Floor     = 25,
	Idle      = 10,
}

-- ручные клавиши пилота: в автономе они не должны спорить с ИИ
local DRR_MANUAL_KEYS = {
	Forward = true, Back = true,
	Left = true, Right = true,
	Up = true, Down = true,
	StrafeLeft = true, StrafeRight = true,
}

local DRR_OPPOSITE = {
	Forward = "Back", Back = "Forward",
	Up = "Down", Down = "Up",
	StrafeLeft = "StrafeRight", StrafeRight = "StrafeLeft",
}

function ENT:DrrMove(key, prio)
	self.DrrCmd = self.DrrCmd or {}

	local old = self.DrrCmd[key]

	if not old or (prio or 0) > old then self.DrrCmd[key] = prio or 0 end
end

function ENT:DrrSteer(want, tol, prio)
	if (self.DrrSteerPrio or 0) > (prio or 0) then return end

	self.DrrSteerPrio = prio or 0
	self.DrrSteerWant = want
	self.DrrSteerTol = tol or 10
end

function ENT:DrrSpeed(mul)
	if (mul or 1) > (self.DrrSpeedMul or 1) then self.DrrSpeedMul = mul end
end

function ENT:DrrFlush()
	local cmd = self.DrrCmd

	-- автоном за пилота: игрок только смотрит, ручные клавиши не мешают ИИ
	if self.DrrAutonomous and IsValid(self:GetDriver()) and self.Keys then
		for key in pairs(DRR_MANUAL_KEYS) do
			local st = self.Keys[key]

			if st then st.Pressed = false end
		end
	end

	if cmd then
		for a, b in pairs(DRR_OPPOSITE) do
			if cmd[a] and cmd[b] then
				if cmd[a] > cmd[b] then cmd[b] = nil
				elseif cmd[b] > cmd[a] then cmd[a] = nil end
			end
		end

		if self.ClickKey then
			for key in pairs(cmd) do self:ClickKey(key) end
		end
	end

	if self.DrrSteerWant then
		local tol = self.DrrSteerTol or 10
		local check = math.NormalizeAngle(self:GetAngles().y - self.DrrSteerWant)

		self:ControlMotion("Left", "Right", check, -tol, tol)
	end

	if (self.DrrSpeedMul or 1) > 1 then
		self.MoveCoefficient = (self.MoveCoefficient or 1) * self.DrrSpeedMul
	end

	self.DrrCmd = nil
	self.DrrSteerWant = nil
	self.DrrSteerPrio = 0
	self.DrrSteerTol = nil
	self.DrrSpeedMul = 1
end

function ENT:ControlsPhys()
	self:DrrFlush()

	if self.BaseClass and self.BaseClass.ControlsPhys then
		return self.BaseClass.ControlsPhys(self)
	end
end

-- Кеш списка наших дронов: FindByClass каждый тик на каждого дрона дорого
local DrrDroneCache, DrrDroneCacheAt = nil, 0

local function drrDrones()
	if not DrrDroneCache or CurTime() > DrrDroneCacheAt then
		DrrDroneCache = ents.FindByClass("drr_scout_drr")
		DrrDroneCacheAt = CurTime() + 0.25
	end

	return DrrDroneCache
end

-- Отталкивание от соседних дронов: чем ближе, тем сильнее уводим курс
-- Расталкивание соседних дронов: суммарный вектор «от соседей»
function ENT:DrrSepPush(radius)
	radius = radius or 900

	local origin = self:WorldSpaceCenter()
	local push = Vector(0, 0, 0)
	local n = 0

	for _, e in ipairs(drrDrones()) do
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
function ENT:DrrSepYaw(base, blend)
	local push = self:DrrSepPush()

	if not push then return base end

	-- ровно друг над другом: уводим вбок
	if push:LengthSqr() < 0.01 then return math.NormalizeAngle(base + 90) end

	return math.NormalizeAngle(base + math.NormalizeAngle(push:Angle().y - base) * (blend or 1))
end

-- Оригинальный AI.CheckSide из DRR, но с фильтром своих прокси-хитбоксов
function ENT:DrrAiCheckSide(side, distance)
	local start = self:LocalToWorld(self:OBBCenter())

	local filter = { self }
	local cam = self:GetCamera()
	if IsValid(cam) then filter[#filter + 1] = cam end

	for _, h in ipairs(self.DrrHitboxes or {}) do
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
local DRR_HEAVY_IGNORE = {
	mbn_apc_manager = true,
}

-- Порядок важности тяжёлой техники (чем больше вес, тем раньше выбирается)
local DRR_HEAVY_PRIORITY = {
	npc_strider = 5,
	npc_helicopter = 4,
	npc_combinegunship = 3,
	npc_hunter = 3,
	npc_combinedropship = 1,
}

-- По обычной цели стреляет один дрон, по тяжёлой — до трёх
local DRR_HEAVY_ATTACKERS = 3

-- Сколько дронов бьют одну цель: 0 = вся стая владельца (по умолчанию),
-- число = предел. Иначе часть дронов уходила в патруль во время боя.
function ENT:DrrAttackLimit()
	if not ConVarExists("drr_scout_swarm") then
		CreateConVar("drr_scout_swarm", "0", FCVAR_ARCHIVE,
			"Сколько дронов одновременно бьют одну цель: 0 = все, число = предел")
	end

	local n = GetConVar("drr_scout_swarm"):GetInt()

	return n > 0 and n or 64
end

-- Груз дропшипа: бьём груз, а не сам корабль
function ENT:DrrDropshipCargo(ship)
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
function ENT:DrrIsHeavy(e)
	if not IsValid(e) then return false end

	return DRR_HEAVY_PRIORITY[e:GetClass()] ~= nil or self:DrrIsCargo(e)
end

-- Доложить союзным дронам о тяжёлой цели: цель кроют не больше трёх
function ENT:DrrShareHeavy(tgt, onTarget)
	if not IsValid(tgt) or not self.DrrAutonomous then return end

	-- свободные места: сам уже считаюсь, плюс те, кто цель уже держит
	local slots = DRR_HEAVY_ATTACKERS - 1 - (onTarget or 0)

	if slots <= 0 then return end

	-- не спамим: докладываем о цели не чаще раза в секунду
	if self.DrrShareTarget == tgt and CurTime() < (self.DrrShareAt or 0) then return end

	self.DrrShareTarget = tgt
	self.DrrShareAt = CurTime() + 1

	local myPos = self:GetPos()
	local list = {}

	for _, d in ipairs(ents.FindByClass("drr_scout_drr")) do
		if d ~= self and IsValid(d) and d.DrrAutonomous and d.Owner == self.Owner then
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
		if not (IsValid(d.DrrAiTarget) and d.DrrAiTarget ~= tgt) then
			d:DrrRecvPriority(tgt, self)
			sent = sent + 1
		end
	end
end

-- Раздать увиденную цель всей стае владельца: свободные дроны летят к ней и
-- стреляют вместо патруля. Занятых другой живой целью не отвлекаем.
function ENT:DrrShareSwarm(tgt)
	if not IsValid(tgt) or not self.DrrAutonomous then return end

	for _, d in ipairs(ents.FindByClass("drr_scout_drr")) do
		if d ~= self and IsValid(d) and d.DrrAutonomous and d.Owner == self.Owner then
			local cur = d.DrrPriorityTarget

			if not (IsValid(cur) and cur ~= tgt and d:DrrMarkOk(cur)) then
				d:DrrRecvMark(tgt, self)
			end
		end
	end
end

-- Оповестить пилотов о тяжёлой цели: HUD рисует текст и метку
function ENT:DrrAlertHeavy(tgt)
	if not IsValid(tgt) then return end
	if CurTime() < (self.DrrAlertAt or 0) then return end

	self.DrrAlertAt = CurTime() + 1

	-- шлём всем: HUD отрисует это только у тех, кто сидит в дроне,
	-- а фильтр по пилотам отсекал игроков, если NW-поле ещё не выставилось
	net.Start("drr_scout_heavy_alert")
	net.WriteUInt(self:EntIndex(), 16)
	net.WriteString(tgt:GetClass())
	net.WriteVector(tgt:WorldSpaceCenter())
	net.WriteEntity(tgt)
	net.Send(player.GetAll())

	if GetConVar("drr_scout_debug") and GetConVar("drr_scout_debug"):GetBool() then
		print(string.format("[DRR] alert: дрон %d -> %s (%.0f, %.0f, %.0f)",
			self:EntIndex(), tgt:GetClass(),
			tgt:WorldSpaceCenter().x, tgt:WorldSpaceCenter().y, tgt:WorldSpaceCenter().z))
	end
end

-- Метка от пилота: летим на указанного врага и работаем по нему
function ENT:DrrRecvMark(tgt, from)
	if not IsValid(tgt) or not self.DrrAutonomous then return end

	self.DrrPriorityTarget = tgt
	self.DrrEngageAt = 0

	-- база DRR ведёт дрон к этой цели
	if self.Buffer then self.Buffer.Enemy = tgt end
end

-- Получен приказ от союзника: летим на цель и работаем по ней
function ENT:DrrRecvPriority(tgt, from)
	if not IsValid(tgt) or not self.DrrAutonomous then return end
	if not self:DrrIsHeavy(tgt) then return end

	self.DrrPriorityTarget = tgt
	self.DrrHeavyTarget = tgt
	self.DrrEngageAt = 0

	-- база DRR ведёт дрон к этой цели
	if self.Buffer then self.Buffer.Enemy = tgt end
end

function ENT:DrrIsCargo(e)
	local p = IsValid(e) and e:GetParent()
	return IsValid(p) and p:GetClass() == "npc_combinedropship"
end

-- Не живая цель (груз/техника-проп): лучом не замораживается
function ENT:DrrIsPropTarget(e)
	return IsValid(e) and not (e:IsPlayer() or e:IsNPC() or e:IsNextBot())
end

-- Летающий/ближний враг Альянса (маньяки, сканеры, дроны) — по ним работаем пулемётом
-- Высота патруля по рельефу: в городских коридорах HL2 дрон снижается
-- до уровня улицы, чтобы видеть цели за зданиями; на открытых картах
-- держит запас над рельефом. Считается раз в секунду на дрон.
function ENT:DrrStreetAltitude()
	local now = CurTime()

	if now < (self.DrrAltAt or 0) then return self.DrrAltCache end

	self.DrrAltAt = now + 1

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
		target = (self.DrrPatrolAltitudeMin + self.DrrPatrolAltitudeMax) * 0.5
	end

	-- над водой держим запас, иначе дрон макает нос в канал
	if tr.HitWater then target = math.max(target, 700) end

	self.DrrAltCache = target

	return target
end

-- В HL2 нет катсцен как таковых: есть скриптовые сцены, где у игрока
-- забирают управление и сажают камеру на point_viewcontrol. Только в этот
-- момент дрон молчит; обычная блокировка управления (без внешней камеры)
-- боем не считается.
function ENT:DrrScriptPause()
	local ply = self:GetDriver()

	if not IsValid(ply) then ply = self.Owner end
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	if not ply:IsFlagSet(FL_FROZEN) then return false end

	-- управление забрали, но камера своя: это не сцена, а короткий лок
	local view = ply:GetViewEntity()

	return IsValid(view) and view ~= ply
end

-- Шаблоны HL2: статичные противники, которых не считаем летающими
local DRR_STATIC_ENEMY = {
	npc_turret_floor = true, npc_turret_ceiling = true, npc_combine_camera = true,
	npc_combine_s = true, npc_metropolice = true, npc_zombie = true,
	npc_zombie_torso = true, npc_fastzombie = true, npc_fastzombie_torso = true,
	npc_poisonzombie = true, npc_zombine = true, npc_headcrab = true,
	npc_headcrab_armored = true, npc_headcrab_fast = true, npc_headcrab_poison = true,
	npc_headcrab_black = true, npc_antlion = true, npc_antlion_worker = true,
	npc_antlionguard = true, npc_antlionguardian = true, npc_vortigaunt = true,
	npc_hunter = true, npc_barnacle = true, npc_rollermine = true,
}

function ENT:DrrIsFlyer(e)
	if not IsValid(e) then return false end
	if e.IS_DRONE then return true end

	if e:IsNPC() then
		local cls = e:GetClass()

		if cls == "npc_manhack" or cls == "npc_cscanner" or cls == "npc_clawscanner" then
			return true
		end

		-- штурмовики и зомби «в воздухе» на лестницах — не летающие: иначе
		-- дрон держит высоту, хотя цель пешком
		if DRR_STATIC_ENEMY[cls] then return false end

		return not e:IsOnGround()
	end

	return false
end

-- Дальнобойность по шаблонам кампании: ближний бой не требует высокой
-- орбиты, турели и снайперов лучше держать дальше
local DRR_RANGE_HINT = {
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

function ENT:DrrRangeHint(e)
	if not IsValid(e) then return nil end

	return DRR_RANGE_HINT[e:GetClass()]
end

-- Муравьиные львы (лев, страж, рабочий) — работаем по ним только пулемётом
function ENT:DrrAntlion(e)
	if not IsValid(e) or not e:IsNPC() then return false end

	return string.find(e:GetClass(), "antlion", 1, true) ~= nil
end

-- Львов бьём из пулемёта, если класса нет в списке друзей из F3-меню
function ENT:DrrMgAllowed(e)
	if not IsValid(e) then return false end
	if not self:DrrAntlion(e) then return true end

	local friends = self.DrrFriendClasses or {}

	return not friends[e:GetClass()]
end

-- После оживления HP ниже порога: включаем щит как страховку
function ENT:DrrReviveShield()
	if not self.AddModule then return end
	if CurTime() < (self.DrrShieldDownUntil or 0) then return end
	if self:HasModule("Shield") and (self.Buffer and self.Buffer.ShieldHealth or 0) > 0 then return end

	-- AddModule ничего не возвращает: проверяем результат по HasModule
	self:AddModule("Shield")

	if not self:HasModule("Shield") then return end

	if self.Buffer then
		self.Buffer.ShieldMax = self.Buffer.ShieldMax or 60
		self.Buffer.ShieldHealth = self.Buffer.ShieldMax
		self:SetNWInt("shield_health", math.floor(self.Buffer.ShieldMax))
		self.DrrShieldLocked = nil
		self.DrrShieldLockHP = nil
	end
end

-- Щит активен и держит урон
function ENT:DrrShieldUp()
	return self.HasModule and self:HasModule("Shield") and (self:GetNWInt("shield_health") or 0) > 0
end

-- Автопилот: преследование как «AI Follow enemy» + объезд из AI MovingCore
function ENT:DrrAiMove()
	local tgt = self.DrrAiTarget
	if not IsValid(tgt) then return end
	if not IsValid(self:GetPhysicsObject()) then return end

	-- новая цель — старый обходной курс больше не нужен
	if self.DrrAiPathTarget ~= tgt then
		self.DrrAiPathTarget = tgt
		self.DrrAiPathBlocked = nil
		self.DrrAiPathYaw = nil
	end

	if self.DrrReposTarget ~= tgt then
		self.DrrReposTarget = tgt
		self.DrrEffectiveAt = CurTime()
		self.DrrReposAt = nil
	end

	-- объезд как в AI.MovingCore (DRR), с фильтром своих хитбоксов.
	-- Трассы дорогие — считаем 15 раз/с, клавиши жмём по кешу каждый тик.
	local nowT = CurTime()

	if nowT > (self.DrrAiAvoidAt or 0) then
		self.DrrAiAvoidAt = nowT + (self:DrrPerf() and 1/10 or 1/15)

		-- при 2500 скорости формула DRR даёт трассы в километры и дрон
		-- начинает дёргаться между стенами — ограничиваем
		local num  = math.Clamp(1.5 + self:GetPhysicsObject():GetVelocity():Length() * 0.01, 1.5, 4)
		local side = self:OBBMaxs().x * num
		local vert = self:OBBMaxs().z * 1.5
		local wide = self:OBBMaxs().y * num

		self.DrrAiAvoid = {
			back  = self:DrrAiCheckSide(-self:GetForward(), side),
			front = self:DrrAiCheckSide(self:GetForward(), side),
			below = self:DrrAiCheckSide(-self:GetUp(), vert),
			above = self:DrrAiCheckSide(self:GetUp(), vert),
			left  = self:DrrAiCheckSide(-self:GetRight(), wide),
			right = self:DrrAiCheckSide(self:GetRight(), wide),
		}
	end

	local av = self.DrrAiAvoid

	-- Полная видимость цели: если её нет, дрон выбирает ОДНО направление
	-- обхода и держит его, а не жмёт вперёд-назад-вверх-вниз одновременно
	if self.DrrAutonomous and self.DrrFullVisible then
		if nowT > (self.DrrNoVisAt or 0) then
			self.DrrNoVisAt = nowT + 0.2
			self.DrrNoVis = not self:DrrFullVisible(tgt)
		end
	end

	local flank

	if av and self.DrrNoVis then
		if nowT > (self.DrrFlankAt or 0) then
			local opts = {}

			if not av.left then opts[#opts + 1] = "left" end
			if not av.right then opts[#opts + 1] = "right" end
			if not av.below then opts[#opts + 1] = "below" end
			if not av.above then opts[#opts + 1] = "above" end
			if not av.front then opts[#opts + 1] = "front" end

			if #opts > 0 then
				self.DrrFlankDir = opts[math.random(#opts)]
			end

			self.DrrFlankAt = nowT + 1.2
		end

		flank = self.DrrFlankDir
	end

	if av then
		if flank then
			-- один осознанный манёвр, чтобы открыть линию огня
			if flank == "left" then self:DrrMove("StrafeLeft", DRR_PRIO.Combat)
			elseif flank == "right" then self:DrrMove("StrafeRight", DRR_PRIO.Combat)
			elseif flank == "above" then self:DrrMove("Up", DRR_PRIO.Combat)
			elseif flank == "below" then self:DrrMove("Down", DRR_PRIO.Combat)
			elseif flank == "front" then self:DrrMove("Forward", DRR_PRIO.Combat)
			end
		else
			if av.back  then self:DrrMove("Forward", DRR_PRIO.Combat) end
			if av.front then self:DrrMove("Back", DRR_PRIO.Combat) end
			if av.below then self:DrrMove("Up", DRR_PRIO.Combat) end
			if av.above then self:DrrMove("Down", DRR_PRIO.Combat) end
			if av.left  then self:DrrMove("StrafeRight", DRR_PRIO.Combat) end
			if av.right then self:DrrMove("StrafeLeft", DRR_PRIO.Combat) end
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

	if hdist > 400 and nowT > (self.DrrAiPathAt or 0) then
		self.DrrAiPathAt = nowT + 0.5

		local origin = self:WorldSpaceCenter()
		local dist = math.min(hdist, 900)
		local filter = { self }

		for _, hb in ipairs(self.DrrHitboxes or {}) do
			if IsValid(hb.ent) then filter[#filter + 1] = hb.ent end
		end

		local tr = util.TraceLine({
			start  = origin,
			endpos = origin + Angle(0, aimYaw, 0):Forward() * dist,
			filter = filter,
			mask   = MASK_SOLID,
		})

		self.DrrAiPathBlocked = tr.Fraction < 0.95
	end

	if self.DrrAiPathBlocked then
		if nowT > (self.DrrAiPathYawAt or 0) then
			self.DrrAiPathYawAt = nowT + 0.5
			self.DrrAiPathYaw = self:DrrFreeYaw(aimYaw, 1200) or aimYaw
		end

		aimYaw = self.DrrAiPathYaw or aimYaw
	else
		self.DrrAiPathYaw = nil
	end

	-- несколько секунд без попаданий: цель за укрытием и снаряды уходят в стену —
	-- смещаемся вбок и выше, чтобы открыть линию огня
	if CurTime() - (self.DrrEffectiveAt or 0) > 5 then
		if CurTime() > (self.DrrReposAt or 0) then
			self.DrrReposAt = CurTime() + 3
			self.DrrEffectiveAt = CurTime()
			self.DrrReposYaw = math.NormalizeAngle(self:GetAngles().y
				+ (math.random() < 0.5 and 85 or -85))
			self.DrrReposZ = drpos.z + math.random(150, 450)
		end

		if CurTime() < self.DrrReposAt then
			aimYaw = self:DrrFreeYaw(self.DrrReposYaw or aimYaw, 1200) or aimYaw

			if (self.DrrReposZ or drpos.z) - drpos.z > 60 then self:DrrMove("Up", DRR_PRIO.Combat) end
		end
	end

	-- в бою уводим курс от соседей лишь частично, иначе дрон бросает цель
	aimYaw = self:DrrSepYaw(aimYaw, 0.45)

	-- и физически расходимся: стрейф в сторону от соседа
	local sepPush = self:DrrSepPush(600)

	if sepPush then
		local side = sepPush:Dot(self:GetRight())

		if sepPush:Length() > 0.4 then
			self:ClickKey(side > 0 and "StrafeRight" or "StrafeLeft")
		end

		if sepPush:Length() > 0.7 then self:DrrMove("Back", DRR_PRIO.Combat) end
	end

	local check = math.NormalizeAngle(self:GetAngles().y - aimYaw)

	-- «зрение»: 40 Гц вблизи, 15 Гц издалека — не видим, подходим и поднимаемся
	if CurTime() > (self.DrrAiSeeAt or 0) then
		self.DrrAiSeeAt = CurTime() + (self:DrrPerf() and ((hdist < 1200) and 1/20 or 1/10) or ((hdist < 1200) and 1/40 or 1/15))
		self.DrrAiSee = self:DrrCanSee(tgt)
	end

	-- дистанция адаптивная. Летающие и ближние враги (маньяки Альянса,
	-- сканеры, муравьиные львы) — держим дальше, чтобы не достали в упор
	local flying = self:DrrIsFlyer(tgt)

	local pref = self.DrrAiStandoff or 1400

	-- строй: у каждой особи свой слот, дистанции расходятся на 260 юнитов,
	-- иначе группа сбивается в одну точку и мешает сама себе
	pref = pref + ((self.DrrSlot or 1) - 1) * 260

	-- свой радиус удержания у каждого дрона: иначе все висят на одной дистанции
	if not self.DrrStandoffJitter then self.DrrStandoffJitter = math.random(-300, 300) end
	pref = pref + self.DrrStandoffJitter
	if flying then pref = math.max(pref, self.DrrAiFlyStandoff or 1900) end

	-- шаблоны кампании: под зомби и хедкрабов не держим дистанцию снайпера
	local hint = self:DrrRangeHint(tgt)

	if hint then pref = math.Clamp(math.min(pref, hint), 500, hint) end
	if not self.DrrAiSee then pref = math.max(600, pref * 0.55) end
	pref = math.min(pref, (self.CryoRange or 2048) * (flying and 0.9 or 0.7))

	-- Цель частично закрыта: не играем дистанцией, идём к ней и обходим
	if self.DrrNoVis then pref = 100 end

	-- Цель отмечена пилотом и далеко: идём вплотную, а не висим на дистанции
	if IsValid(self.DrrPriorityTarget) and self.DrrPriorityTarget == tgt and hdist > 3000 then
		pref = 200
	end

	-- далеко — ускоряемся, как AI Follow owner в DRR
	if hdist > 1200 then self:DrrMove("Sprint", DRR_PRIO.Combat) end

	-- сближаемся по горизонтали, высоту держим отдельно (иначе встаёт под целью).
	-- Направление фиксируется на 0.4 с: без этого дрон дёргается вперёд-назад
	-- вокруг дистанции удержания
	local nowPos = CurTime()

	if check > -40 and check < 40 and nowPos > (self.DrrApproachAt or 0) then
		if hdist > pref * 1.1 then
			self.DrrApproach = 1
			self.DrrApproachAt = nowPos + 0.4
		elseif hdist < pref * 0.9 then
			self.DrrApproach = -1
			self.DrrApproachAt = nowPos + 0.4
		else
			self.DrrApproach = 0
		end
	end

	-- Обход стен: в коридорах и дверях кампании HL2 дрон упирался в
	-- геометрию. Смотрим коридор вперёд и уводим в сторону с просветом.
	if self.DrrApproach == 1 and nowPos > (self.DrrWallAt or 0) then
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
				self:DrrMove("Up", DRR_PRIO.Combat)
			else
				local rTr = util.TraceLine({
					start = from, endpos = from + self:GetRight() * 420,
					filter = self, mask = MASK_SOLID,
				})
				local lTr = util.TraceLine({
					start = from, endpos = from - self:GetRight() * 420,
					filter = self, mask = MASK_SOLID,
				})

				self.DrrWallSide = rTr.Fraction > lTr.Fraction and "StrafeRight" or "StrafeLeft"
			end

			self.DrrWallUntil = nowPos + 0.7
			self.DrrWallAt = nowPos + 0.4
		end
	end

	if nowPos < (self.DrrWallUntil or 0) then
		self:ClickKey(self.DrrWallSide or "StrafeRight")
		self.DrrApproach = 0
	end

	-- за границу карты не летим даже за целью
	if util.IsInWorld and not util.IsInWorld(self:GetPos() + self:GetForward() * 500) then
		self.DrrApproach = -1
		self.DrrWallUntil = nowPos + 0.6
		self.DrrWallSide = "StrafeLeft"
	end

	if check > -40 and check < 40 then
		if self.DrrApproach == 1 then
			self:DrrMove("Forward", DRR_PRIO.Combat)
		elseif self.DrrApproach == -1 then
			self:DrrMove("Back", DRR_PRIO.Combat)
		end
	end

	self:DrrSteer(aimYaw, 16, DRR_PRIO.Combat)

	-- Высота в бою: держимся над целью, но под сводом и без «полёта в пустоте».
	-- В большом туннеле (2-3 этажа) дрон идёт на уровне голов, а не под потолком.
	local pitchDown = math.abs(math.min(self.PitchMin or -30, 0))
	local maxOffset = hdist * math.tan(math.rad(math.max(pitchDown - 5, 5)))
	local cap       = self.DrrAiAltitudeOffset or 2000
	local ceilingAlt = self:DrrStreetAltitude()

	local upper = math.min(cap, ceilingAlt or cap)
	local lower = math.min(self.DrrMinAltitude or 800, upper)

	-- тесное помещение или туннель: боремся на уровне цели, а не у свода
	if ceilingAlt and ceilingAlt < 900 and not flying then
		upper = math.min(upper, 420)
		lower = math.min(lower, 220)
	end

	local offset = math.Clamp(math.min(maxOffset, upper), lower, upper)

	if not self.DrrAiSee then offset = math.min(offset + 200, upper) end

	-- личная высота: дроны не выстраиваются в одну линию над целью
	if not self.DrrAltJitter then self.DrrAltJitter = math.random(-200, 260) end
	offset = math.Clamp(offset + self.DrrAltJitter * 0.6, lower, upper)

	local wantZ = opos.z + offset

	-- не поднимаемся в свод: держим запас под корпус дрона
	if self.DrrCeilZ then
		local ceil = self.DrrCeilZ - 170

		if wantZ > ceil then wantZ = ceil end
	end

	if not self.DrrNoVis then
		-- высота боя: сглаженная цель, мёртвая зона и торможение падения.
		-- Без них Up/Down чередуются через тик и дрон «прыгает» у цели.
		self.DrrWantZ = self.DrrWantZ and Lerp(math.min(FrameTime() * 2, 1), self.DrrWantZ, wantZ) or wantZ
		wantZ = self.DrrWantZ

		local dz = wantZ - drpos.z
		local vz = self:GetVelocity().z

		if dz > 150 and (not self.DrrCeilZ or drpos.z < self.DrrCeilZ - 190) then
			self:DrrMove("Up", DRR_PRIO.Combat)
		elseif dz < -150 then
			if vz > -200 then self:DrrMove("Down", DRR_PRIO.Combat) end
		elseif vz < -250 then
			self:DrrMove("Up", DRR_PRIO.Combat)
		end
	end
	-- цель слишком высоко для PitchMax — отходим, чтобы угол влез
	if self.AllowPitchRestrictions then
		local lp = self:WorldToLocalAngles(to:Angle()).p
		if lp > self.PitchMax - 5 then self:DrrMove("Back", DRR_PRIO.Combat) end
	end
end

-- Точка прицеливания: голова NPC/игрока, иначе центр OBB
-- Патруль в покое: медленно летает, осматривается и ищет цели
-- Режим привязки патруля: 0 — выкл, 1 — NavMesh, 2 — AI Nodes
function ENT:DrrNavMode()
	if not ConVarExists("drr_scout_nav_mode") then
		CreateConVar("drr_scout_nav_mode", "1", FCVAR_ARCHIVE,
			"Привязка патруля к навигации: 0 — выкл, 1 — NavMesh, 2 — AI Nodes")
	end

	return math.Clamp(GetConVar("drr_scout_nav_mode"):GetInt(), 0, 2)
end

-- AI-ноды: в приоритете воздушные (info_node_air*) — это готовые точки
-- полёта; если воздушных рядом нет, берём наземную.
function ENT:DrrNodeCenter(pos, radius)
	local now = CurTime()

	if not DrrNodeCache or now > (DrrNodeCacheAt or 0) then
		DrrNodeCache = ents.FindByClass("info_node*") or {}
		DrrNodeCacheAt = now + 10
	end

	local r2 = radius * radius
	local air, land = {}, {}

	for _, n in ipairs(DrrNodeCache) do
		if IsValid(n) then
			local p = n:GetPos()

			if util.IsInWorld and not util.IsInWorld(p) then continue end

			local d = p:DistToSqr(pos)

			if d <= r2 then
				local gz = self:DrrGroundAt(p, 4000)

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
function ENT:DrrNavBelow(pos)
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
function ENT:DrrRandomNavCenter(pos, radius)
	if not navmesh or not navmesh.GetAllNavAreas then return end

	local now = CurTime()

	if not DrrNavCache or now > (DrrNavCacheAt or 0) then
		DrrNavCache = navmesh.GetAllNavAreas() or {}
		DrrNavCacheAt = now + 10
	end

	local count = #DrrNavCache
	if count == 0 then return end

	local r2 = radius * radius
	local pick

	for _ = 1, 40 do
		local area = DrrNavCache[math.random(count)]
		local c = area and area.GetCenter and area:GetCenter()

		if c and c:DistToSqr(pos) <= r2 then
			pick = c

			if math.random() < 0.5 then break end
		end
	end

	return pick
end

-- Высота поверхности под точкой (крыша/земля). nil = под точкой пустота
function ENT:DrrGroundAt(pos, dist)
	local tr = util.TraceLine({
		start  = pos + Vector(0, 0, 64),
		endpos = pos + Vector(0, 0, -(dist or 4000)),
		filter = { self },
		mask   = MASK_SOLID,
	})

	return tr.Hit and tr.HitPos.z or nil
end

-- жёсткое ведение в строю: курс и тяга строго к точке, без случайных манёвров патруля
-- Высота лидера seconds назад: задние дроны строя повторяют её с задержкой
function ENT:DrrZLag(seconds)
	local hist = self.DrrZHist

	if not hist or #hist == 0 then return self:GetPos().z end

	local want = CurTime() - (seconds or 0)
	local best = hist[1]

	for i = #hist, 1, -1 do
		if hist[i].t <= want then
			best = hist[i]
			break
		end
	end

	return best.z
end

function ENT:DrrFormFly()
	local leader = self:DrrFollowLeader()

	if not leader then
		self.DrrVertZ = nil
		return
	end

	local pt = self:DrrFormPoint(leader)
	self.DrrPatrolPos = pt
	self.DrrPatrolAt = CurTime() + 1

	local diff = pt - self:GetPos()
	local dist = diff:Length()
	local speed = self:GetVelocity():Length()

	-- расходимся с соседями: иначе на 6+ дронах они сбиваются в кучу
	-- мягкое расталкивание: сильное отталкивание заставляет дронов метаться
	local myPos = self:GetPos()
	local away = Vector(0, 0, 0)
	local minD = math.huge
	local nearest

	for _, o in ipairs(drrDrones()) do
		if o ~= self and IsValid(o) then
			local d = myPos - o:GetPos()
			local l = d:Length()

			if l > 1 and l < minD then minD, nearest = l, o end

			if l > 1 and l < 300 then
				away = away + d:GetNormalized() * (300 - l) * 0.45
			end
		end
	end

	if away:LengthSqr() > 0 then diff = diff + away * 0.35 end

	-- ПРИОРИТЕТ 1 (застревание): считаем прогресс к своей точке, а не близость
	-- к соседям. При 5 дронах сосед рядом — норма, а прежний «разъезд вплотную»
	-- дёргал их и снимал тягу.
	local now = CurTime()

	if now > (self.DrrFormProgAt or 0) then
		self.DrrFormProgAt = now + 0.5

		local prev = self.DrrFormLastDist

		if prev and dist > 350 and prev - dist < 25 then
			self.DrrFormStall = (self.DrrFormStall or 0) + 1
		else
			self.DrrFormStall = 0
		end

		self.DrrFormLastDist = dist
	end

	-- 2 секунды без прогресса — выходим из застревания своим курсом
	if (self.DrrFormStall or 0) >= 4 then
		self.DrrFormStall = 0
		self.DrrFormEscapeUntil = now + 1.0
		self.DrrFormEscapeYaw = self:DrrFreeYaw(diff:Angle().y, 900) or diff:Angle().y
		self.DrrFormEscapes = (self.DrrFormEscapes or 0) + 1

		-- три неудачных выхода подряд — один перенос к лидеру
		if self.DrrFormEscapes >= 3 then
			self.DrrFormEscapes = 0

			local lead = leader:GetPos()
			local off = pt - lead
			off = off:LengthSqr() > 1 and off:GetNormal() * 320 or Vector(0, 0, 0)

			local spot = lead + off
			local tr = util.TraceHull({
				start = self:GetPos(),
				endpos = spot,
				mins = Vector(-40, -40, -40),
				maxs = Vector(40, 40, 40),
				filter = { self, leader },
			})

			if not tr.Hit then
				self:SetPos(spot)

				local phys = self:GetPhysicsObject()
				if IsValid(phys) then phys:Wake() end
			end

			self.DrrFormLastDist = nil
		end
	end

	-- режим выхода важнее объезда и вертикали: летим по свободному курсу
	if now < (self.DrrFormEscapeUntil or 0) then
		self:DrrSteer(self.DrrFormEscapeYaw or diff:Angle().y, 12, DRR_PRIO.Escape)
		self:DrrMove("Forward", DRR_PRIO.Escape)
		self:DrrMove("Sprint", DRR_PRIO.Escape)
		self:DrrMove("Up", DRR_PRIO.Escape)
		self:DrrSpeed(1.6)
		self.DrrVertZ = nil
		return
	end

	if dist < 160 then self.DrrFormEscapes = nil end

	-- возврат в строй после боя: догоняем лидера на повышенной тяге
	if self.DrrFormReturn then
		self:DrrSpeed(2.0)
		self:DrrMove("Sprint", DRR_PRIO.Formation)
	end
	-- облёт: стена по курсу — временно уводим в сторону, иначе ведомый упирается
	if CurTime() > (self.DrrFormAvoidCheck or 0) then
		self.DrrFormAvoidCheck = CurTime() + 0.3

		if dist > 120 then
			local tr = util.TraceHull({
				start = self:GetPos(),
				endpos = self:GetPos() + diff:GetNormal() * 260,
				mins = Vector(-30, -30, -30),
				maxs = Vector(30, 30, 30),
				filter = { self, leader },
			})

			-- прокси-хитбоксы дронов не считаем стеной
			if tr.Hit and IsValid(tr.Entity) and tr.Entity:GetClass() == "drr_scout_hitbox" then
				tr.Hit = false
			end

			-- попадание ниже корпуса — это крыша/уступ под нами, летим сверху
			if tr.Hit and tr.HitPos.z < self:GetPos().z - 40 then
				tr.Hit = false
			end

			if tr.Hit then
				self.DrrFormAvoidHits = (self.DrrFormAvoidHits or 0) + 1

				if not (self.DrrFormAvoidUntil and CurTime() < self.DrrFormAvoidUntil) then
					self.DrrFormAvoidSide = (self.DrrFormAvoidSide or 0) * -1

					if self.DrrFormAvoidSide == 0 then self.DrrFormAvoidSide = 1 end
				end

				self.DrrFormAvoidUntil = CurTime() + 0.9

				-- упираемся в стену который раз — поднимаемся над ней
				if self.DrrFormAvoidHits >= 3 then
					self:DrrMove("Up", DRR_PRIO.Avoid)
				end
			else
				self.DrrFormAvoidHits = 0
			end
		end
	end

	-- разворот на точку: при большом угле тягу не даём, иначе летим дугой
	if dist > 40 then
		local want = math.NormalizeAngle(diff:Angle().y)

	if CurTime() < (self.DrrFormAvoidUntil or 0) then
		want = math.NormalizeAngle(want + (self.DrrFormAvoidSide or 1) * 45)
	end

	local check = math.NormalizeAngle(self:GetAngles().y - want)

	-- при объезде курс уведён на 45°: допускаем больший угол, иначе тяга
	-- отключалась и дрон висел, пока не закончится окно объезда
	local tol = (CurTime() < (self.DrrFormAvoidUntil or 0)) and 70 or 40

	self:DrrSteer(want, 10, DRR_PRIO.Formation)

	-- отставание от своего места в строю: чем больше разрыв, тем сильнее разгон.
	-- MoveCoefficient база перезаписывает каждый тик, поэтому домножаем её здесь
	local behind = math.max(dist - 80, 0)
	local boost  = math.Clamp(1 + behind / 400, 1, 2.6)

	if behind > 120 then
		self.MoveCoefficient = (self.MoveCoefficient or 1) * boost
	end

	-- тянем вперёд на любом расстоянии: раньше порог 250 оставлял дрона
	-- висеть в четверти тысячи юнитов от собственной точки
	if math.abs(check) < tol and dist > 40 then
		self:DrrMove("Forward", DRR_PRIO.Formation)
	end

	-- спринт включаем раньше и держим, пока не догнали точку
	if behind > 120 then
		self:DrrMove("Sprint", DRR_PRIO.Formation)
		self:DrrMove("Forward", DRR_PRIO.Formation)
	end
end

	-- подошли вплотную к точке: только тогда гасим скорость,
	-- чтобы не тормозить всю дорогу до неё
	if dist < 110 and speed > 170 then
		self:DrrMove("Back", DRR_PRIO.Formation)
	end

	-- в строю держим ровно высоту лидера: без «пола» и ограничений,
	-- чтобы можно было идти и у земли, и высоко
	local targetZ = leader:GetPos().z

	self.DrrVertZ = self.DrrVertZ and Lerp(math.Clamp(FrameTime() * 8, 0, 1), self.DrrVertZ, targetZ) or targetZ

	local dz = self.DrrVertZ - self:GetPos().z

	if dz > 20 then
		self:DrrMove("Up", DRR_PRIO.Vertical)
	elseif dz < -20 then
		self:DrrMove("Down", DRR_PRIO.Vertical)
	end
end

function ENT:DrrAiPatrol()
	if not IsValid(self:GetPhysicsObject()) then return end

	local now = CurTime()

	-- смена режима применяется сразу: сбрасываем текущую цель патруля
	local mode = self:DrrNavMode()

	if self.DrrNavModeLast ~= mode then
		self.DrrNavModeLast = mode
		self.DrrPatrolPos = nil
		self.DrrPatrolAt = 0
		self.DrrPatrolYaw = nil
		self.DrrPatrolTurnAt = 0
	end

	-- дошли до навигационной зоны: сразу выбираем следующую
	if not self:DrrFollowLeader() and self.DrrPatrolPos and self.DrrPatrolPos:DistToSqr(self:GetPos()) < 350 * 350 then
		self.DrrPatrolPos = nil
		self.DrrPatrolAt = 0
	end

	-- режим 0: привязки нет, цель патруля не удерживаем
	if mode == 0 and not self:DrrFollowLeader() then self.DrrPatrolPos = nil end

	if not self:DrrFollowLeader() and now > (self.DrrPatrolAt or 0) then
		self.DrrPatrolAt = now + math.random(3, 6)

		-- патрулируем по навигации: летим в центр случайной NavMesh-зоны;
		-- если дрон вне навигации — возвращаемся к ближайшей зоне
		local myPos = self:GetPos()
		local navMode = mode
		local overNav, navCenter

		if navMode == 1 then
			-- NavMesh: зона под дроном + случайный центр в радиусе
			local okA, area = pcall(self.DrrNavBelow, self, myPos)
			if okA then overNav = area end

			local okB, center = pcall(self.DrrRandomNavCenter, self, myPos, 4500)
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
			local okC, node = pcall(self.DrrNodeCenter, self, myPos, 2600)

			if okC then navCenter = node end

			-- на карте нет нод-сущностей: переключаемся на NavMesh,
			-- иначе дрон просто висит на месте
			if not navCenter then
				local okB, center = pcall(self.DrrRandomNavCenter, self, myPos, 4500)

				if okB then navCenter = center end
			end
		end

			-- патруль вокруг своей точки: не даём дрону улететь от места включения
			local pc = ConVarExists("drr_scout_patrol") and GetConVar("drr_scout_patrol")

			if navCenter and pc and pc:GetBool() then
				if not self.DrrHomePos then self.DrrHomePos = myPos end

				local home = self.DrrHomePos
				local RADIUS = 2400

				if home:DistToSqr(navCenter) > RADIUS * RADIUS then
					navCenter = home + (navCenter - home):GetNormalized() * RADIUS
				end
			end

			if navCenter then
			self.DrrPatrolPos = navCenter
		else
			self.DrrPatrolPos = nil
		end

		local want

		if self.DrrPatrolPos then
			want = math.NormalizeAngle((self.DrrPatrolPos - myPos):Angle().y)
		else
			want = self:DrrFollowLeader() and self:GetAngles().y or math.NormalizeAngle(self:GetAngles().y + math.random(-120, 120))
		end

		-- новый курс принимаем только если линия пути свободна
		self.DrrPatrolYaw = self:DrrFreeYaw(want, 1200) or want

		-- патрульная высота считается от земли: от текущей точки дрон сползал вниз
		local ground = self.DrrGroundZ or myPos.z

	-- центр зоны — уровень пола, но если точка пришла с высоты (строй, нода),
	-- берём настоящую землю: иначе каждая цель выше предыдущей и дрон лезет вверх
	if self.DrrPatrolPos then
		ground = math.min(self.DrrPatrolPos.z, self.DrrGroundZ or self.DrrPatrolPos.z)
	end
		local lo = self.DrrPatrolAltitudeMin or 700
		local hi = self.DrrPatrolAltitudeMax or 1200

		-- AI Nodes: воздушные ноды (info_node_air) — это готовые точки полёта,
		-- летим ровно к ним; наземные — держим 250-350 над ними.
		if self:DrrNavMode() == 2 and self.DrrPatrolPos then
			local gz = self:DrrGroundAt(self.DrrPatrolPos, 4000)
			local above = gz and (self.DrrPatrolPos.z - gz) or 0

			if above > 150 then
				lo, hi = 30, 70      -- смещение от самой ноды
			else
				lo, hi = 450, 650    -- над землёй вдоль улицы
			end
		end

		-- под сводом целимся ниже потолка; далёкий «потолок» (небо или браш
		-- скайбокса) игнорируем, иначе патруль прижимается к земле
		local ceilNear = self.DrrCeilZ and (self.DrrCeilZ - self:GetPos().z) < 1200

		if ceilNear then
			local room = math.floor(self.DrrCeilZ - ground - 150)

			if room < lo then
				hi = math.max(room, 150)
				lo = math.max(150, hi - 250)
			else
				hi = math.min(hi, room)
			end
		end

	self.DrrPatrolZ = ground + math.random(lo, hi)

	-- жёсткий минимум: не ниже 650 над землёй, если свод позволяет
	do
		local floorZ = ground + 650

		if ceilNear then
			floorZ = math.min(floorZ, math.max(self.DrrCeilZ - 150, ground + 150))
		end

		if self.DrrPatrolZ < floorZ then self.DrrPatrolZ = floorZ end
	end

	-- страховка от бесконечного набора высоты
	if self.DrrGroundZ then
		self.DrrPatrolZ = math.min(self.DrrPatrolZ, self.DrrGroundZ + 1500)
	end
end

	-- медленный разворот в выбранную сторону
	self.DrrPatrolYaw = self:DrrSepYaw(self.DrrPatrolYaw or self:GetAngles().y)

	local check = math.NormalizeAngle(self:GetAngles().y - (self.DrrPatrolYaw or self:GetAngles().y))
	self:DrrSteer(self.DrrPatrolYaw or self:GetAngles().y, 10, DRR_PRIO.Patrol)

	-- препятствие впереди проверяем 3 раза в секунду и меняем курс
	if now > (self.DrrPatrolTraceAt or 0) then
		self.DrrPatrolTraceAt = now + 0.3

		local phys = self:GetPhysicsObject()
		local speed = IsValid(phys) and phys:GetVelocity():Length() or 0
		self.DrrPatrolSpeed = speed

		-- смотрим вперёд тем дальше, чем быстрее летим: 0.3 с запаса
		self.DrrPatrolBlocked = self:DrrAiCheckSide(self:GetForward(),
			math.max(self:OBBMaxs().x * 3, speed * 0.3))

		if self.DrrPatrolBlocked then
			self.DrrPatrolHits = (self.DrrPatrolHits or 0) + 1
		else
			self.DrrPatrolHits = 0
		end
	end

	if self.DrrPatrolBlocked then
		-- гасим ход, иначе на 2500 юнитов/с дрон догоняет собственную реакцию
		if (self.DrrPatrolSpeed or 0) > 700 then self:DrrMove("Back", DRR_PRIO.Patrol) end

	-- выбираем свободное направление (в т.ч. от невидимых стен карты), а не «в стену»
	if now > (self.DrrPatrolTurnAt or 0) then
		self.DrrPatrolTurnAt = now + 0.5
		self.DrrPatrolYaw = self:DrrFreeYaw(self:GetAngles().y, 1200)
	end

	-- после разворота сразу летим, если новый курс свободен: иначе дрон
	-- считает себя застрявшим и стоит до следующей проверки
	if self.DrrPatrolYaw then
		local dir = Angle(0, self.DrrPatrolYaw, 0):Forward()

		if not self:DrrAiCheckSide(dir, 900) then
			self.DrrPatrolBlocked = false
			self.DrrPatrolHits = 0
			self:DrrMove("Forward", DRR_PRIO.Patrol)
		end
	end

		-- застряли надолго: разворот и подъём, чтобы выйти из угла/от стены
		if (self.DrrPatrolHits or 0) >= 6 then
			self.DrrPatrolHits = 0
			self.DrrPatrolYaw = math.NormalizeAngle(self:GetAngles().y + 180)
			self.DrrPatrolZ = math.max(
				self:GetPos().z + math.random(100, 250),
				(self.DrrGroundZ or self:GetPos().z) + (self.DrrPatrolAltitudeMin or 700))
			self:DrrMove("Up", DRR_PRIO.Patrol)
		elseif (self.DrrPatrolHits or 0) >= 3 then
			-- стена мешает: поднимаемся над ней, а не стоим перед ней
			self:DrrMove("Up", DRR_PRIO.Patrol)
			self.DrrPatrolZ = math.max(self.DrrPatrolZ or self:GetPos().z, self:GetPos().z + 120)
		end
	elseif math.abs(check) < 25 and (not self.DrrFormHold or (self.DrrPatrolPos and self.DrrPatrolPos:DistToSqr(self:GetPos()) > 120 * 120)) then
		self:DrrMove("Forward", DRR_PRIO.Patrol)
	end

	-- землю под собой проверяем редко (дорогая трасса), с учётом перф-режима
	if now > (self.DrrPatrolGroundAt or 0) then
		self.DrrPatrolGroundAt = now + (self:DrrPerf() and 0.25 or 0.1)
		self.DrrPatrolGround = self:DrrAiCheckSide(-self:GetUp(), 200)
	end

	-- Рельеф впереди: если там крыша выше нас — поднимаемся над ней.
	-- Иначе дрон бьётся низом о край здания.
	if now > (self.DrrPatrolTerrAt or 0) then
		self.DrrPatrolTerrAt = now + 0.4

		local myPos = self:GetPos()
		local ahead = self:DrrGroundAt(myPos + self:GetForward() * 420, 4000)
		local below = self:DrrGroundAt(myPos, 6000)

		-- вылет за карту: нет земли ИЛИ точка впереди вне границ мира
		local outAhead = util.IsInWorld and not util.IsInWorld(myPos + self:GetForward() * 400)

		if (outAhead or (not below and not ahead)) and now > (self.DrrEdgeAt or 0) then
			self.DrrEdgeAt = now + 1
			self.DrrPatrolYaw = math.NormalizeAngle(self:GetAngles().y + 180)
			self.DrrPatrolPos = nil
			self.DrrPatrolAt = now + 2
		end

		if ahead and ahead > myPos.z - 150 then
			self.DrrPatrolZ = math.max(self.DrrPatrolZ or (ahead + 260), ahead + 260)
			self:DrrMove("Up", DRR_PRIO.Patrol)
		end
	end

	-- держим высоту патруля: мёртвая зона и торможение падения. Без них
	-- импульсы Up/Down чередуются через тик, и у земли дрон «прыгает».
	local z = self:GetPos().z
	local dz = (self.DrrPatrolZ or z) - z
	local vz = self:GetVelocity().z
	local ground = self.DrrPatrolGround

	if (ground and dz > -150) or dz > 150 then
		self:DrrMove("Up", DRR_PRIO.Patrol)
	elseif dz < -150 and not ground then
		if vz > -200 then self:DrrMove("Down", DRR_PRIO.Vertical) end
	elseif vz < -250 then
		self:DrrMove("Up", DRR_PRIO.Patrol)
	end
end

-- Кости головы у разных классов: люди/зомби, страйдер, ганшип, вертолёт, дропшип
local DRR_HEAD_BONES = {
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

function ENT:DrrAimPoint(e)
	if not IsValid(e) then return end

	-- все NPC (включая страйдера, ганшип, вертолёт) — целимся в голову
	if e:IsPlayer() or e:IsNPC() or e:IsNextBot() then
		local center = e:LocalToWorld(e:OBBCenter())
		-- верхняя граница габарита: присевший страйдер не должен
		-- «уводить» прицел выше модели
		local top = e:GetPos().z + e:OBBMaxs().z

		for _, name in ipairs(DRR_HEAD_BONES) do
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
function ENT:DrrAiAimNow()
	local tgt = self.DrrAiTarget

	if not IsValid(tgt) then
		self.DrrAimAligned = false

		-- цель потеряна: сбрасываем накопленное наведение, иначе камера
		-- замирает на последнем направлении и не возвращается по курсу
		self.DrrAutoAngles = nil
		self.DrrAimSmooth = nil
		self:SetNWVector("DrrAutoDir", vector_origin)
		return
	end

	local cam = self:GetCamera()
	local origin = IsValid(cam) and cam:GetPos() or self:GetPos()

	local center = self:DrrAimPoint(tgt) or tgt:LocalToWorld(tgt:OBBCenter())

	-- в режиме пулемёта прицел ведём в точку упреждения: иначе камера
	-- отстаёт от цели и осколки идут за моделью
	if self.DrrAttackMode == 1 and self.DrrLeadPoint then
		center = self:DrrLeadPoint(tgt, origin, 7000) or center
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
	self.DrrAimAligned = math.abs(rawP - ang.p) < 2 and math.abs(rawY - ang.y) < 2

	local want = self:LocalToWorldAngles(ang)

	-- сглаживаем направление, но при манёвре/стрейфе наводим точно:
	-- иначе прицел отстаёт от цели и пули идут мимо
	local dodging = self.DrrDodgeUntil and CurTime() < self.DrrDodgeUntil

	if not dodging and self.DrrAimSmooth then
		-- по движущейся цели доворачиваем быстрее, иначе прицел плывёт
		local vel = self:DrrTargetVel(tgt)
		local factor = vel:Length() > 120 and 0.8 or 0.5

		self.DrrAimSmooth = LerpVector(factor, self.DrrAimSmooth, want:Forward()):GetNormal()
		self.DrrAutoAngles = self.DrrAimSmooth:Angle()
	else
		self.DrrAimSmooth = want:Forward()
		self.DrrAutoAngles = want
	end

	-- в сеть — не чаще 15 раз/с, клиент дополнительно сглаживает
	if CurTime() > (self.DrrDirSentAt or 0) then
		self.DrrDirSentAt = CurTime() + 1/15
		self:SetNWVector("DrrAutoDir", self.DrrAutoAngles:Forward())
	end
end

-- NPC с шаговым движением (antlion и др.) отдают GetVelocity() = 0,
-- поэтому скорость считаем сами по смещению позиции
function ENT:DrrTargetVel(tgt)
	if not IsValid(tgt) then return vector_origin end

	self.DrrVelTrack = self.DrrVelTrack or setmetatable({}, { __mode = "k" })

	local pos = tgt:WorldSpaceCenter()
	local now = CurTime()
	local rec = self.DrrVelTrack[tgt]

	if not rec then
		self.DrrVelTrack[tgt] = { pos = pos, t = now, vel = vector_origin }
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
function ENT:DrrLeadPoint(tgt, start, speed)
	if not IsValid(tgt) then return end

	-- центр габарита, а не кость головы: у мелких NPC голова крошечная,
	-- и даже верное упреждение уходило мимо тела
	local center

	-- упреждение считаем от головы; если кости головы нет — от центра габарита
	center = (self.DrrAimPoint and self:DrrAimPoint(tgt)) or tgt:WorldSpaceCenter()

	if not center then center = tgt:WorldSpaceCenter() + Vector(0, 0, 12) end

	local vel = self:DrrTargetVel(tgt)

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

-- Перф-режим: drr_scout_perf 1 — экономные частоты, 0 — полные
function ENT:DrrPerf()
	if not ConVarExists("drr_scout_perf") then
		CreateConVar("drr_scout_perf", "1", FCVAR_ARCHIVE)
	end

	return GetConVar("drr_scout_perf"):GetBool()
end

-- Есть ли игроки рядом: без них логику дрона считать незачем
function ENT:DrrNearPlayers(radius)
	local now = CurTime()

	if now < (self.DrrNearAt or 0) then return self.DrrNear end

	self.DrrNearAt = now + 1
	self.DrrNear = false

	local r2 = radius * radius
	local pos = self:GetPos()

	for _, p in ipairs(player.GetAll()) do
		if p:Alive() and p:GetPos():DistToSqr(pos) <= r2 then
			self.DrrNear = true
			break
		end
	end

	return self.DrrNear
end

-- Кеш списка кандидатов на все наши дроны: ents.GetAll() не дёргаем каждые 0.5 с
local DrrTargetCache, DrrTargetCacheAt = nil, 0

function ENT:DrrAiTargets()
	if not DrrTargetCache or CurTime() > DrrTargetCacheAt then
		local list = { }

		for _, e in ipairs(ents.GetAll()) do
			if IsValid(e) and (e:IsPlayer() or e:IsNPC() or e:IsNextBot() or e.IS_DRONE) then
				list[#list + 1] = e
			end
		end

		DrrTargetCache = list
		DrrTargetCacheAt = CurTime() + 0.5
	end

	return DrrTargetCache
end

-- Отрядная точка: дрон, увидевший группу врагов, ставит метку на место.
-- Свободные дроны владельца летят туда; если целей больше, чем дронов,
-- летят все — нужное число получается само.
local SQUAD_POINT_TIME = 8
local SQUAD_CLUSTER_R = 700

function ENT:DrrSquadMarkPoint(pos, count)
	local owner = self.Owner

	if not IsValid(owner) or not isvector(pos) then return end

	owner.DrrSquadPos = pos
	owner.DrrSquadCount = count
	owner.DrrSquadUntil = CurTime() + SQUAD_POINT_TIME
end

-- назначение командного дрона: он один на владельца
function ENT:DrrSetCommander(on)
	local owner = self.Owner

	for _, d in ipairs(drrDrones()) do
		if IsValid(d) and d ~= self and d.Owner == owner and d.DrrCommander then
			d.DrrCommander = nil
			d:SetNWBool("DrrCommander", false)

			-- прежний лидер возвращает свою расцветку
			if d.DrrSetSkin then d:DrrSetSkin(d.DrrSkinBeforeCmd or 0) end
			d.DrrSkinBeforeCmd = nil
		end
	end

	self.DrrCommander = on and true or nil
	self:SetNWBool("DrrCommander", on and true or false)

	-- лидер всегда красный, пока он лидер
	if self.DrrSetSkin then
		if self.DrrCommander then
			self.DrrSkinBeforeCmd = self.DrrSkinBeforeCmd or self:GetNWInt("DrrSkin", 0)
			self:DrrSetSkin(1)
		else
			self:DrrSetSkin(self.DrrSkinBeforeCmd or 0)
			self.DrrSkinBeforeCmd = nil
		end
	end

	return self.DrrCommander == true
end

-- командный дрон: остальные дроны владельца держат за ним строй
function ENT:DrrFollowLeader()
	local cv = ConVarExists("drr_scout_follow") and GetConVar("drr_scout_follow")

	if not cv or not cv:GetBool() or self.DrrCommander then return end

	local owner = self.Owner

	if not IsValid(owner) then return end

	local best, bestDist

	-- лидер может быть и под управлением игрока: автоном не обязателен
	for _, d in ipairs(drrDrones()) do
		if d ~= self and IsValid(d) and d.Owner == owner and d.DrrCommander then
			local dist = d:GetPos():DistToSqr(self:GetPos())

			if not bestDist or dist < bestDist then best, bestDist = d, dist end
		end
	end

	-- лидер только явно назначенный: посадка в дрон не должна оживлять стаю

	return best
end

-- точка строя для ведомого: номер в колонне + тип формации
function ENT:DrrFormPoint(leader)
	local dc = ConVarExists("drr_scout_form_dist") and GetConVar("drr_scout_form_dist")
	local fc = ConVarExists("drr_scout_formation") and GetConVar("drr_scout_formation")

	local dist = dc and math.Clamp(dc:GetFloat(), 620, 1600) or 620
	local form = fc and fc:GetInt() or 0

	-- свободный полёт: держимся за лидером, но без формации — своё случайное место
	if form == 4 then
		if not self.DrrFreeOffset or CurTime() > (self.DrrFreeAt or 0) then
			local a = math.rad(math.random(0, 359))
			local rad = math.Rand(0.6, 1.8) * dist

			self.DrrFreeOffset = Vector(math.cos(a) * rad, math.sin(a) * rad, math.Rand(-0.25, 0.35) * dist)
			self.DrrFreeAt = CurTime() + math.random(6, 12)
		end

		return leader:GetPos() + self.DrrFreeOffset
	end

	local idx, total, mine = 1, 1, self:EntIndex()

	-- номер в строю считается по всем дронам владельца: лидер может быть пилотируемым
	for _, d in ipairs(drrDrones()) do
		if d ~= self and d ~= leader and IsValid(d) and d.Owner == self.Owner then
			total = total + 1

			if d:EntIndex() < mine then idx = idx + 1 end
		end
	end

	-- больше дронов — шире строй, иначе точки налезают друг на друга
	dist = dist * (1 + math.max(total - 2, 0) * 0.25)

	local ang = leader:GetAngles()
	local fwd = ang:Forward()

	-- правый вектор строго горизонтальный: при наклоне лидера Right() уводит строй
	-- по вертикали, и дроны встают друг над другом
	local right = Vector(-fwd.y, fwd.x, 0)

	if right:LengthSqr() < 0.0001 then right = Vector(1, 0, 0) else right:Normalize() end

	fwd = Vector(fwd.x, fwd.y, 0)

	if fwd:LengthSqr() < 0.0001 then fwd = Vector(0, 1, 0) else fwd:Normalize() end
	local side = (idx % 2 == 0) and 1 or -1
	local off

	if form == 1 then
		off = fwd * (-dist * idx)
	elseif form == 2 then
		-- радиус кольца не меньше, чем нужно для зазора между соседями:
		-- иначе при 3-4 дронах точки стоят почти вплотную
		local n = math.max(total, 2)
		local R = math.max(dist, 380 / math.max(math.sin(math.pi / n), 0.2))
		local a = math.rad(360 / n) * idx

		off = fwd * (math.cos(a) * R) + right * (math.sin(a) * R)

		-- соседи по кольцу идут на разной высоте: не бьются винтами
		off.z = (idx % 2 == 0) and 40 or -40
	elseif form == 3 then
		off = right * (side * math.ceil(idx / 2) * dist)
	else
		local rank = math.ceil(idx / 2)
		off = right * (side * rank * dist * 0.65) + fwd * (-dist * rank * 0.45)
	end

	return leader:GetPos() + off
end

function ENT:DrrSquadPoint()
	local owner = self.Owner

	if not IsValid(owner) or not owner.DrrSquadPos then return end
	if CurTime() > (owner.DrrSquadUntil or 0) then
		owner.DrrSquadPos = nil
		return
	end

	return owner.DrrSquadPos, owner.DrrSquadCount or 1
end

	-- ИИ работает только в автономном режиме: иначе дрон стоит выключенным
function ENT:DrrAiActive()
	-- без автонома дрон стоит как только что заспавненный, даже если включено следование
	return self.DrrAutonomous == true
end

function ENT:DrrAiScan()
	-- по умолчанию модуль выключен: до включения дрон сам ничего не делает
	-- без автонома дрон не двигается и не воюет: стоит как только что заспавненный
	if not self:DrrAiActive() then
		self.DrrFormHold = nil
		self.DrrFormEngage = nil
		self.DrrFormReturn = nil
		self.DrrAiTarget = nil
		self.DrrAimAligned = false
		self.DrrAutoAngles = nil
		self.DrrVertZ = nil
		self.DrrCmd = nil
		return
	end

	-- ведомый держит строй постоянно: точка не снимается, иначе дрон снова свободен
	local leader = self:DrrFollowLeader()

	self.DrrFormHold = leader ~= nil

	if leader then
		self.DrrPatrolPos = self:DrrFormPoint(leader)
		self.DrrPatrolAt = CurTime() + 1

		-- скорость под лидера: чем больше разрыв, тем сильнее догоняем
		-- MoveCoefficient база перезаписывает каждый тик, поэтому догоняем спринтом
		if self:GetPos():Distance(leader:GetPos()) > 600 then self:DrrMove("Sprint", DRR_PRIO.Patrol) end
	elseif self.DrrFormBase then
		self.MoveCoefficient = self.DrrFormBase
		self.DrrFormBase = nil
	end

	if not ConVarExists("drr_scout_engage_leash") then
		CreateConVar("drr_scout_engage_leash", "3000", FCVAR_ARCHIVE,
			"Насколько далеко от лидера ведомый уходит в бой: 0 = без лимита")
	end

	-- бой из строя: пока возвращаемся на своё место, новые цели не берём,
	-- иначе ведомый застревает в бесконечной погоне и не возвращается
	if self.DrrFormReturn then
		local pt = leader and self:DrrFormPoint(leader)

		if not pt or pt:DistToSqr(self:GetPos()) < 320 * 320
		or CurTime() > (self.DrrFormReturnUntil or 0) then
			self.DrrFormReturn = nil
		else
			self.DrrAiTarget = nil
			self.DrrAimAligned = false
			return
		end
	end

	if not leader then
		self.DrrFormEngage = nil
		self.DrrFormReturn = nil
	end

	-- без автонома бой не нужен: только строй
	if not self.DrrAutonomous then return end

	local cam = self:GetCamera()
	local origin = IsValid(cam) and cam:GetPos() or self:GetPos()
	local visible, best, contact = nil, math.huge, false

	-- дальность обнаружения: своя, сильно больше стандартного радиуса DRR
	if not ConVarExists("drr_scout_ai_range") then
		CreateConVar("drr_scout_ai_range", "16000", FCVAR_ARCHIVE, "Радиус обнаружения целей ИИ: 0, inf или max = вся карта")
	end

	if not ConVarExists("drr_scout_debug") then
		CreateConVar("drr_scout_debug", "0", FCVAR_ARCHIVE, "Отладка ИИ дрона")
	end

	if not ConVarExists("drr_scout_engage_range") then
		CreateConVar("drr_scout_engage_range", "0", FCVAR_ARCHIVE,
			"Дистанция боя: по умолчанию без лимита; число ограничивает огонь, но не поиск")
	end

	local cv = GetConVar("drr_scout_ai_range")
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
	local engageCv = GetConVar("drr_scout_engage_range")
	local engageInt = engageCv and engageCv:GetInt() or 0
	local engageText = engageCv and string.lower(string.Trim(engageCv:GetString())) or "3000"
	local engageOpen = engageInt == 0 or engageText == "inf" or engageText == "infinite"
		or engageText == "max" or engageText == "all"
	local engageDist = engageOpen and maxDist or math.min(engageInt, radius) ^ 2

	-- цели и число дронов, которые их уже держат: обычную цель не перебиваем,
	-- тяжёлую делят между собой до DRR_HEAVY_ATTACKERS дронов
	local claimed = {}

	local myPos = self:GetPos()

	for _, d in ipairs(drrDrones()) do
		if d ~= self and IsValid(d) and d.DrrAutonomous and IsValid(d.DrrAiTarget)
			and d:GetPos():DistToSqr(myPos) <= 8000 * 8000 then
			claimed[d.DrrAiTarget] = (claimed[d.DrrAiTarget] or 0) + 1
		end
	end

	local function valid(e)
		if not IsValid(e) or e == self then return false end
		if e:GetClass() == "drr_scout_drr" then return false end
		if self.DrrFriendClasses then
			if self.DrrFriendClasses[e:GetClass()] then return false end

			-- дружественные игроки хранятся как @STEAMID
			if e:IsPlayer() and self.DrrFriendClasses["@" .. e:SteamID()] then return false end
		end
		-- стая: сколько дронов может держать одну цель (см. drr_scout_swarm)
		if (claimed[e] or 0) >= self:DrrAttackLimit() then return false end
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
	local cur = self.DrrAiTarget

	if IsValid(cur) and (DRR_HEAVY_IGNORE[cur:GetClass()] or self:DrrIsCargo(cur)) then
		cur = nil
	end

	-- дропшип без груза целью не считается
	if IsValid(cur) and cur:GetClass() == "npc_combinedropship"
		and not IsValid(self:DrrDropshipCargo(cur)) then
		cur = nil
	end

	if (valid(cur) or self:DrrIsCargo(cur))
		and (self:DrrIsCargo(cur) or cur.IS_DRONE or cur.Health == nil
			or (cur:Health() > 0 and (not cur.IsNPC or cur:Alive()))) then
		local d = origin:DistToSqr(cur:LocalToWorld(cur:OBBCenter()))

		if d <= maxDist then
			if self:DrrCanSee(cur) then
				self.DrrAiTargetSeen = CurTime()
			end

			-- до 2 с без линии видимости держим прежнюю цель
			if CurTime() - (self.DrrAiTargetSeen or 0) <= 2 then
				visible, best = cur, d
			end
		end
	end

	-- приоритет тяжёлой техники (настройка DrrHeavyHighPriority в shared.lua)
	if self.DrrHeavyHighPriority then
		local heavyPick, heavyPri, heavyDist

		for cls, pri in pairs(DRR_HEAVY_PRIORITY) do
			for _, e in ipairs(ents.FindByClass(cls)) do
				if not IsValid(e) or e == self or DRR_HEAVY_IGNORE[cls] then continue end
				if e == self.Owner or e == self:GetDriver() then continue end

				if cls == "npc_combinedropship" and not IsValid(self:DrrDropshipCargo(e)) then
					continue
				end
				if (e:IsNPC() or e:IsNextBot() or e.IS_DRONE) and not valid(e) then continue end

				local d = origin:DistToSqr(e:LocalToWorld(e:OBBCenter()))

				if d <= maxDist and self:DrrCanSee(e) then
					if not heavyPri or pri > heavyPri or (pri == heavyPri and d < heavyDist) then
						heavyPick, heavyPri, heavyDist = e, pri, d
					end
				end
			end
		end

		if IsValid(heavyPick) then
			if heavyPick:GetClass() == "npc_combinedropship" then
				local cargo = self:DrrDropshipCargo(heavyPick)

				if IsValid(cargo) then heavyPick = cargo end
			end

			visible, best = heavyPick, heavyDist
			contact = true
			self.DrrAiTargetSeen = CurTime()
		end
	end

	for _, raw in ipairs(self.DrrAiTargets()) do
		if not IsValid(raw) then continue end
		if DRR_HEAVY_IGNORE[raw:GetClass()] or self:DrrIsCargo(raw) then continue end

		-- с грузом бьём груз, без груза дропшип не цель
		if raw:GetClass() == "npc_combinedropship" then
			raw = self:DrrDropshipCargo(raw)

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

			if not visible and d < best and d <= engageDist and self:DrrCanSee(e) then
				best = d
				visible = e
				self.DrrAiTargetSeen = CurTime()
			end
		end
	end

	-- сам дропшип никогда не цель: только его груз
	if IsValid(visible) and visible:GetClass() == "npc_combinedropship" then
		visible = nil
	end

	if GetConVar("drr_scout_debug"):GetBool() then
		local enemies, npcs = 0, 0

		for _, x in ipairs(self:DrrAiTargets()) do
			if IsValid(x) and x:IsNPC() then
				npcs = npcs + 1
				if self.IsEnemy and self:IsEnemy(x:GetClass()) then enemies = enemies + 1 end
			end
		end

		print(string.format("[DRR] scan: cand=%d npc=%d enemyNPC=%d contact=%s target=%s radius=%d engage=%d ignoreNPC=%s shouldIgnore=%s",
			#self:DrrAiTargets(), npcs, enemies, tostring(contact), tostring(visible), cvRadius,
			math.floor(math.sqrt(engageDist)),
			tostring(DRONES_REWRITE and DRONES_REWRITE.ServerCVars and DRONES_REWRITE.ServerCVars.NPCIgnore
				and DRONES_REWRITE.ServerCVars.NPCIgnore:GetBool()),
			tostring(self.ShouldNpcsIgnore)))
	end

	self.DrrScanContact = contact

	-- увидели группу: делимся точкой с дронами владельца
	if IsValid(visible) and IsValid(self.Owner) and CurTime() > (self.DrrSquadAt or 0) then
		self.DrrSquadAt = CurTime() + 1

		local base = visible:GetPos()
		local cnt = 1

		for _, x in ipairs(self.DrrAiTargets()) do
			if IsValid(x) and x ~= visible and (x:IsNPC() or x:IsNextBot())
				and self.IsEnemy and self:IsEnemy(x:GetClass())
				and x:GetPos():DistToSqr(base) <= SQUAD_CLUSTER_R * SQUAD_CLUSTER_R then
				cnt = cnt + 1
			end
		end

		if cnt > 1 then self:DrrSquadMarkPoint(base, cnt) end

		-- цель уходит всей стае: иначе часть дронов бьёт, часть патрулирует
		self:DrrShareSwarm(visible)
	end

	-- при виде врага — красная расцветка, иначе возвращаем обычную;
	-- командный дрон остаётся красным всегда
	local red = (visible ~= nil) or self.DrrCommander == true

	if self.DrrAiRed ~= red then
		self.DrrAiRed = red
		self:DrrSetSkin(red and 1 or 0)
	end

	-- сброс: цель, найденная сканом, видна напрямую
	self.DrrTargetMarked = false

	-- Помеченная цель приоритетнее обычной: её указал игрок или союзный дрон
	if IsValid(self.DrrPriorityTarget) then
		local pt = self.DrrPriorityTarget

		if self:DrrMarkOk(pt) then
			visible = pt
			self.DrrTargetMarked = true
			self.DrrAiTargetSeen = CurTime()
		else
			-- цель перестала быть валидной: гасим надпись у владельца
			if IsValid(self.Owner) and IsValid(pt) then
				net.Start("drr_scout_mark_clear")
				net.WriteEntity(pt)
				net.Send(self.Owner)
			end

			self.DrrPriorityTarget = nil
		end
	end

	-- прицеливание и огонь по видимой цели
	if visible then		-- разнообразие: 1 — только пулемёт, 2 — луч, затем добивание пулемётом
		if self.DrrAiTarget ~= visible then
			-- роль и слот в стае: первая особь держит цель криолучом, остальные
			-- бьют осколками; у каждой свой номер строя
			local beamTaken, slot = false, 1

			for _, d in ipairs(drrDrones()) do
				if d ~= self and IsValid(d) and d.DrrAiTarget == visible then
					slot = slot + 1

					if d.DrrAttackMode == 2 then beamTaken = true end
				end
			end

			self.DrrAttackMode = beamTaken and 1 or 2
			self.DrrSlot = math.Clamp(slot, 1, 4)
			self.DrrAimSmooth = nil

			-- короткая задержка взятия на прицел: не расстреливаем цель
			-- в тот же кадр, как она появилась
			self.DrrEngageAt = CurTime() + 0.6
		end

		self.DrrAiTarget = visible
		self:DrrAiAimNow()

		if self.ClickKey then
			-- цель от союзника может быть за стеной: не палим в укрытие
			if not self.DrrTargetMarked or self:DrrCanSee(visible) then
				self:ClickKey("Fire1")
			end
		end

	else
		self.DrrAutoAngles = nil
		self.DrrAiTarget = nil
		self.DrrAimAligned = false
		self:SetNWVector("DrrAutoDir", vector_origin)

			-- ведомый держит строй за командным дроном
			local leader = self:DrrFollowLeader()

			if leader then
				local pt = self:DrrFormPoint(leader)
				local dist = math.sqrt(pt:DistToSqr(self:GetPos()))
				local dc = GetConVar("drr_scout_form_dist")
				local keep = (dc and dc:GetFloat() or 400) * 1.25

				if dist > keep then
					self.DrrPatrolPos = pt
					self.DrrPatrolAt = CurTime() + 1
				else
					self.DrrPatrolPos = nil
				end
			else
				-- свободный дрон идёт к точке, отмеченной соседом
				local sp = self:DrrSquadPoint()

				if sp then
					self.DrrPatrolPos = sp
					self.DrrPatrolAt = CurTime() + 2
				end
			end
	end

	-- Тяжёлая техника (страйдер, вертолёт, ганшип, хантер, груз дропшипа):
	-- пока такая цель жива — держим щит и предупреждение в HUD
	local heavy

	if self:DrrIsHeavy(visible) then
		heavy = visible
	end

	local held = self.DrrHeavyTarget

	-- снимаем пометку только когда цель реально умерла: щит держится,
	-- даже если тяжёлый юнит ушёл из зоны видимости
	if IsValid(held) and held.Health and (not held:Alive() or (held:Health() or 0) <= 0) then
		self.DrrHeavyTarget = nil
	end

	if IsValid(heavy) then
		self.DrrHeavyTarget = heavy

		-- доложить союзным дронам: тяжёлую цель кроют втроём
		self:DrrShareHeavy(heavy, claimed[heavy] or 0)

		-- оповестить пилотов: в HUD появится метка обнаружения
		self:DrrAlertHeavy(heavy)
	end

	local ht = self.DrrHeavyTarget
	local heavyAlive = IsValid(ht) and (ht.Health == nil
		or ((ht:Health() or 0) > 0 and (not ht.IsNPC or ht:Alive())))

	-- щит: тяжёлая цель — сразу, обычные — только ниже 20% здоровья.
	-- Ручное решение игрока в F3 всегда главнее авто-логики
	if self.DrrAutonomous and self.AddModule and not self:HasModule("Shield")
		and not self.DrrShieldManual
		and CurTime() >= (self.DrrShieldDownUntil or 0) then
		local hp  = self:GetHealth() or 0
		local max = self:GetDefaultHealth() or 0

		if heavyAlive or (contact and max > 0 and hp / max < 0.2) then
			self.DrrJamBreakAt = nil
			self.DrrJamUse = nil

			-- помним, что щит поставлен из-за тяжёлой цели: только его
			-- и снимаем, когда угроза уйдёт
			self.DrrShieldForHeavy = heavyAlive or nil

			self:AddModule("Shield")
		end
	end

	-- Тяжёлая цель ушла: снимаем только щит, поставленный из-за неё,
	-- один раз и с задержкой. Щит от низкого HP и ручной не трогаем
	if heavyAlive then
		self.DrrHeavyGoneAt = nil
	elseif not self.DrrHeavyGoneAt then
		self.DrrHeavyGoneAt = CurTime() + 2
	elseif CurTime() >= self.DrrHeavyGoneAt then
		if self.DrrAutonomous and self.DrrShieldForHeavy and not self.DrrShieldManual
			and self:HasModule("Shield") then
			self:RemoveModule("Shield")
			self.DrrShieldForHeavy = nil
		end

		self.DrrHeavyGoneAt = false
	end

	-- HUD: тип и здоровье тяжёлой цели (в сеть только при изменении)
	local hv = self.DrrHeavyTarget

	if IsValid(hv) then
		local hp = math.max(hv:Health() or 0, 0)
		local mx = math.max((hv.GetMaxHealth and hv:GetMaxHealth()) or hp, hp)
		local cls = hv:GetClass()

		-- Панель живёт, пока цель жива: неуязвимости у страйдера больше нет
		local show = hp > 0

		if self.DrrHeavySentHp ~= hp or self.DrrHeavySentClass ~= cls or self.DrrHeavySentMax ~= mx then
			self.DrrHeavySentHp = hp
			self.DrrHeavySentClass = cls
			self.DrrHeavySentMax = mx

			self:SetNWBool("DrrHeavyActive", show)
			self:SetNWString("DrrHeavyClass", cls)
			self:SetNWInt("DrrHeavyHp", hp)
			self:SetNWInt("DrrHeavyMax", mx)
		end
	elseif self.DrrHeavySentHp ~= nil then
		self.DrrHeavySentHp = nil
		self.DrrHeavySentClass = nil
		self:SetNWBool("DrrHeavyActive", false)
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
	elseif visible and cur ~= visible and not self:DrrCanSee(cur) then
		self.Buffer.Enemy = visible
	end
end

-- Автономный режим: дрон сам сканирует, целится и стреляет (можно при пилоте)
net.Receive("drr_scout_auto", function(_, ply)
	if not netAllowed(ply, "auto", 5) then return end

	local drone = playerDrone(ply)
	if not drone then return end

	local on = net.ReadBool()
	drone.DrrAutonomous = on
	drone:SetNWBool("DrrAuto", on)

	-- при выключении убираем всё, что могло остаться от автопилота
	if not on then
		drone.DrrAutoAngles = nil
		drone:SetNWVector("DrrAutoDir", vector_origin)
		drone.DrrAiRed = nil
		drone.DrrScanContact = nil

		-- следование не должно оставлять дрон в движении
		drone.DrrPatrolPos = nil
		drone.DrrPatrolAt = 0
		drone.DrrFormHold = nil

		if drone.DrrFormBase then
			drone.MoveCoefficient = drone.DrrFormBase
			drone.DrrFormBase = nil
		end

		if drone.Buffer then drone.Buffer.Enemy = nil end

		if drone.DrrSetSkin then drone:DrrSetSkin(0) end
		-- чистим только Click: Pressed на сервере переключается событиями клиента,
		-- и ручная запись рассинхронизирует клавиши — ЛКМ/ПКМ пилота «мертвеют»
		for _, k in ipairs({ "Fire1", "Fire2", "Forward", "Back" }) do
			local st = drone.Keys and drone.Keys[k]
			if st then st.Click = false end
		end

	end
end)

-- Включить автономность всем дронам игрока, у которых она выключена
net.Receive("drr_scout_auto_all", function(_, ply)
	if not netAllowed(ply, "auto_all", 2) then return end

	local n = 0

	for _, e in ipairs(ents.FindByClass("drr_scout_drr")) do
		if IsValid(e) and (e.Owner == ply or e:GetOwner() == ply) and not e.DrrAutonomous then
			e.DrrAutonomous = true
			e:SetNWBool("DrrAuto", true)
			n = n + 1
		end
	end

end)

-- Сколько дронов игрока в автономном режиме (для счётчика в F3)
net.Receive("drr_scout_auto_stats", function(_, ply)
	if not netAllowed(ply, "auto_stats", 2) then return end

	local on, total = 0, 0

	for _, e in ipairs(ents.FindByClass("drr_scout_drr")) do
		if IsValid(e) and (e.Owner == ply or e:GetOwner() == ply) then
			total = total + 1
			if e.DrrAutonomous then on = on + 1 end
		end
	end

	net.Start("drr_scout_auto_stats_res")
	net.WriteUInt(math.min(on, 255), 8)
	net.WriteUInt(math.min(total, 255), 8)
	net.Send(ply)
end)

-- Список дронов игрока для раздела «Стая»: клиент не всегда видит .Owner
net.Receive("drr_scout_squad_list", function(_, ply)
	if not netAllowed(ply, "squad_list", 4) then return end

	local list = {}

	for _, e in ipairs(ents.FindByClass("drr_scout_drr")) do
		if IsValid(e) then
			local owner = e.Owner or e:GetOwner()

			if owner == ply or e:GetNWString("DrrOwnerID") == ply:SteamID() then
				list[#list + 1] = e
			end
		end
	end

	local n = math.min(#list, 32)
	local first = {}

	for i = 1, n do first[i] = list[i] end

	table.sort(first, function(a, b) return a:EntIndex() < b:EntIndex() end)

	net.Start("drr_scout_squad_list")
	net.WriteUInt(n, 8)

	for _, e in ipairs(first) do
		net.WriteUInt(e:EntIndex(), 16)
		net.WriteUInt(math.Clamp(math.floor(e:GetHealth() or 0), 0, 65535), 16)
		net.WriteUInt(math.Clamp(math.floor(e:GetDefaultHealth() or 0), 0, 65535), 16)
		net.WriteBool(e.DrrAutonomous and true or false)
		net.WriteBool(e.DrrCommander and true or false)
		net.WriteBool(IsValid(e:GetDriver()))
	end

	net.Send(ply)
end)

-- Отступление: HP ниже 25% — уходим к командному дрону или владельцу и не
-- стреляем; возвращаемся в бой сами, когда ремонт поднимет HP до 60%
function ENT:DrrRetreatFly()
	if not self.DrrAutonomous or self.DrrDead then
		self.DrrRetreating = nil
		return false
	end

	local hp  = self:GetHealth() or 0
	local max = self:GetDefaultHealth() or 0

	if max <= 0 then return false end

	if not self.DrrRetreating then
		-- в отступление уходим только под огнём: без цели дрон просто патрулирует
		if hp / max >= 0.25 or not IsValid(self.DrrAiTarget) then return false end

		self.DrrRetreating = true
		self.DrrAimAligned = false
	end

	if hp / max >= 0.6 then
		self.DrrRetreating = nil
		return false
	end

	local safe = self:DrrFollowLeader()

	if not IsValid(safe) then safe = self.Owner end
	if not IsValid(safe) then safe = self:GetOwner() end

	local threat = self.DrrAiTarget
	local dest

	if IsValid(safe) then
		dest = safe:GetPos()
	elseif IsValid(threat) then
		dest = self:GetPos() + (self:GetPos() - threat:GetPos()):GetNormal() * 1200
	else
		self.DrrRetreating = nil
		return false
	end

	local diff = dest - self:GetPos()

	if diff:Length() > 60 then
		local want  = math.NormalizeAngle(diff:Angle().y)
		local check = math.NormalizeAngle(self:GetAngles().y - want)

		self:DrrSteer(want, 10, DRR_PRIO.Retreat)

		if math.abs(check) < 40 then
			self:DrrMove("Forward", DRR_PRIO.Retreat)
			self:DrrMove("Sprint", DRR_PRIO.Retreat)
		end
	end

	-- поднимаемся: по прямой цели проще попасть
	if CurTime() > (self.DrrRetreatUpAt or 0) then
		self.DrrRetreatUpAt = CurTime() + 0.6
		self:DrrMove("Up", DRR_PRIO.Retreat)
	end

	return true
end

function ENT:Think()
	-- Чужое ночное видение DRR у нашего дрона выключено: у нас своя оптика
	-- с отдельной переменной DrrNV (см. drr_scout_nightvision.lua)
	if self.UseNightVision then self.UseNightVision = false end
	if self:GetNWBool("NightVision") then self:SetNWBool("NightVision", false) end

	-- Random moving: вместо полёта задним ходом разворачиваемся корпусом
	if self.AI_installed and self.Buffer and (self.Buffer.RandomBack or 0) > 0 then
		self.Buffer.RandomBack = 0
		self.Buffer.RandomForward = math.max(self.Buffer.RandomForward or 0, 12)
		self.DrrTurnTo = math.NormalizeAngle(self:GetAngles().y + 180)
	end

	-- Горячая перезагрузка DRR пересоздаёт таблицу Weapons: возвращаем
	-- своё оружие, иначе база падает на Weapons["Cryo"] == nil
	if DRONES_REWRITE and DRONES_REWRITE.DrrCryoDef then
		DRONES_REWRITE.Weapons = DRONES_REWRITE.Weapons or {}

		if not DRONES_REWRITE.Weapons["Cryo"] then
			DRONES_REWRITE.Weapons["Cryo"] = DRONES_REWRITE.DrrCryoDef
		end
	end

	-- Ошибка внутри базового Think не должна замораживать дрон:
	-- раньше исключение обрывало весь тик, и наш ИИ/движение не выполнялись
	-- ошибка внутри базового Think не должна замораживать дрон: печатаем её
	-- не чаще раза в 5 секунд и продолжаем свой тик
	if self.BaseClass and self.BaseClass.Think then
		local ok, err = pcall(self.BaseClass.Think, self)

		if not ok and CurTime() > (self.DrrBaseErrAt or 0) then
			self.DrrBaseErrAt = CurTime() + 5
			print("[DRR] base Think: " .. tostring(err))
		end
	end

	-- владелец мог появиться позже Initialize: досылаем в сеть
	if self.Owner ~= self.DrrOwnerSent then
		self.DrrOwnerSent = self.Owner

		if IsValid(self.Owner) then
			self:SetNWEntity("DrrOwner", self.Owner)
			self:SetNWString("DrrOwnerID", self.Owner:SteamID())
		end
	end

	-- состояние патруля (клиент рисует фонарики)
	local patrolNW = self.DrrAutonomous and not IsValid(self.DrrAiTarget)

	if self.DrrPatrolNW ~= patrolNW then
		self.DrrPatrolNW = patrolNW
		self:SetNWBool("DrrPatrol", patrolNW)
	end

	-- Камера от первого лица — ровно в точке обзора (Bip01_Head + вынос)
	local cam = self:GetCamera()
	local eye = self:DrrEyePos()

	if IsValid(cam) and eye then
		cam:SetPos(eye)
	end

	-- Своя отрисовка щита на клиенте; временную сущность DRR прячем
	if self.Buffer and IsValid(self.Buffer.Shield) then
		self.Buffer.Shield:SetNoDraw(true)
	end

	if self.DrrAutonomous and self.DrrTurnTo then
		local ang = self:GetAngles()
		local diff = math.NormalizeAngle(ang.y - self.DrrTurnTo)

		self:DrrSteer(self.DrrTurnTo, 10, DRR_PRIO.Turn)

		if math.abs(diff) < 12 then self.DrrTurnTo = nil end
	end

	local now = CurTime()

	-- край карты: в автономе разворачиваем домой, иначе дрон упирается
	-- в границу мира и продолжает жать вперёд
	if self.DrrAutonomous and now > (self.DrrEdgeCheckAt or 0) then
		self.DrrEdgeCheckAt = now + 0.5

		local p = self:GetPos()

		if not util.IsInWorld(p) or not util.IsInWorld(p + self:GetForward() * 600) then
			local home = self.DrrHomePos or (IsValid(self.Owner) and self.Owner:GetPos()) or vector_origin

			self.DrrTurnTo = (home - p):Angle().y
			self.DrrPatrolPos = home
			self.DrrPatrolAt = CurTime() + 2
		end
	end

	-- сторож: автономный дрон стоит, хотя до цели полёта далеко
	if self.DrrAutonomous and not self.DrrDead then
		local spd = self:GetVelocity():Length()
		local leader = self:DrrFollowLeader()
		local dest = self.DrrPatrolPos

		if leader then dest = self:DrrFormPoint(leader) end

		local far = dest and dest:DistToSqr(self:GetPos()) > 300 * 300
		local stunned = self.DrrStunnedUntil and now < self.DrrStunnedUntil

		if far and not stunned and spd < 40 then
			self.DrrIdleSince = self.DrrIdleSince or now

			if now - self.DrrIdleSince > 3 then
				self.DrrIdleSince = nil
				self.DrrPatrolPos = nil
				self.DrrPatrolAt = 0
				self.DrrStuckSince = nil
				self.DrrFormAvoidUntil = nil

				self:DrrMove("Forward", DRR_PRIO.Idle)

				self:DrrMove("Up", DRR_PRIO.Idle)
			end
		else
			self.DrrIdleSince = nil
		end
	end

	-- автономно: наводим камеру/голову на цель (корпус не крутим — Left/Right
	-- добавляют ещё и тангаж, из-за чего дрон вертелся и стрелял вверх)
	if self.DrrAutonomous and self.DrrAutoAngles then
		self.CamAngles = self.DrrAutoAngles
	elseif self.DrrAutonomous and not IsValid(self:GetDriver()) then
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
	-- без автонома движение полностью запрещено: ни строй, ни патруль
	if not self.DrrAutonomous then
		self.DrrFormHold = nil
		self.DrrFormEngage = nil
		self.DrrFormReturn = nil
		self.DrrVertZ = nil
	end

	local aiOn = self:DrrAiActive()

	local aiActive = not self.DrrDead
		and not (self:DrrPerf() and not IsValid(self.DrrAiTarget) and not self:DrrNearPlayers(6000))

	-- бой из строя: ведомый уходит за целью, после боя возвращается на место
	if self.DrrFormHold then
		local leader = self:DrrFollowLeader()
		local leash = ConVarExists("drr_scout_engage_leash")
			and GetConVar("drr_scout_engage_leash"):GetInt() or 3000

		if IsValid(self.DrrAiTarget) then
			-- цель ушла слишком далеко от лидера: не гонимся через полкарты
			local far = leader and leash > 0
			and self.DrrAiTarget:GetPos():DistToSqr(leader:GetPos()) > leash * leash

			if far then
				self.DrrAiTarget = nil
				self.DrrFormEngage = nil
				self.DrrFormReturn = true
				self.DrrFormReturnUntil = CurTime() + 3
			else
				self.DrrFormEngage = true
				self.DrrFormEngageAt = CurTime()
				self.DrrFormReturn = nil
			end
		elseif self.DrrFormEngage and CurTime() > (self.DrrFormEngageAt or 0) + 1.2 then
			-- бой окончен: возвращаемся в строй и коротко не отвлекаемся
			self.DrrFormEngage = nil
			self.DrrFormReturn = true
			self.DrrFormReturnUntil = CurTime() + 4
		end
	end

	-- перф-режим: без игроков рядом боевая логика спит, но патруль работает
	if aiOn and (not aiActive or not self.DrrAutonomous or self.DrrPatrolPos) then
		if self.DrrFormHold then
			-- есть цель: ведёт бой, иначе держит строй
			if not IsValid(self.DrrAiTarget) then self:DrrFormFly() end
		else
			self:DrrAiPatrol()
		end
	end

	-- мало HP: уходим на ремонт к лидеру/владельцу, огонь не ведём
	if self.DrrAutonomous and aiActive then self:DrrRetreatFly() end

	if aiActive and self.DrrAutonomous and not self.DrrRetreating
		and (not self.DrrFormHold or IsValid(self.DrrAiTarget)) then
		self:DrrAiAimNow()

		-- под обстрелом и без щита — уклоняемся стрейфом вместо полёта по курсу
		if self.DrrDodgeUntil and CurTime() < self.DrrDodgeUntil and not self:DrrShieldUp() then
			-- ускорение на время манёвра: спринт + временный буст коэффициента
			if not self.DrrDodgeBoost then
				self.DrrDodgeBase = self.MoveCoefficient or 1
				self.MoveCoefficient = self.DrrDodgeBase * 1.6
				self.DrrDodgeBoost = true
				self:DrrMove("Sprint", DRR_PRIO.Dodge)
			end

			self:DrrMove(self.DrrDodgeDir == "left" and "StrafeLeft" or "StrafeRight", DRR_PRIO.Dodge)

			if CurTime() > (self.DrrDodgeFlip or 0) then
				self.DrrDodgeFlip = CurTime() + 0.55
				self:DrrMove("Up", DRR_PRIO.Dodge)
			end

			-- манёвр не отменяет доворот к цели, иначе под огнём не наводится
			local tgt = self.DrrAiTarget

			if IsValid(tgt) then
				local drpos = self:LocalToWorld(self:OBBCenter())
				local opos  = tgt:LocalToWorld(tgt:OBBCenter())
				local check = math.NormalizeAngle(self:GetAngles().y - (opos - drpos):Angle().y)

				self:DrrSteer((opos - drpos):Angle().y, 16, DRR_PRIO.Dodge)
			end
		else
			if self.DrrDodgeBoost then
				self.MoveCoefficient = self.DrrDodgeBase or 1
				self.DrrDodgeBoost = false
			end

			if IsValid(self.DrrAiTarget) then
				self:DrrAiMove()
			else
				self:DrrAiPatrol()
			end
		end

		-- пулемёт: по замороженным и по летающим (маньяки, сканеры, дроны)
		local tgt    = self.DrrAiTarget
		local frozen = IsValid(tgt) and DRRScout and DRRScout.IsFrozen(tgt)

		local mgOnly = (self.DrrAttackMode == 1)

		if (frozen or self:DrrIsFlyer(tgt) or self:DrrIsPropTarget(tgt)
			or self:DrrIsCargo(tgt) or mgOnly) and self:DrrMgAllowed(tgt)
			and self.DrrAimAligned and self.ClickKey then
			self:ClickKey("Fire2")
		end
	end


	-- минимальная высота над землёй: автономно не чертим по ней днищем
	if now > (self.DrrNextGroundAt or 0) then
		self.DrrNextGroundAt = now + 0.25

	local pos = self:GetPos()
	local tr = util.TraceLine({
		start  = pos,
		endpos = pos - Vector(0, 0, 3000),
		filter = self:DrrTraceFilter(),
		mask   = MASK_SOLID,
	})

	-- страховка: если фильтр-функция не дала попадания, пробуем табличный.
	-- Без земли высота считается от текущей точки, и дрон летит у самого пола.
	if not tr.Hit then
		tr = util.TraceLine({
			start  = pos,
			endpos = pos - Vector(0, 0, 3000),
			filter = { self },
			mask   = MASK_SOLID,
		})
	end

	self.DrrGroundZ = tr.Hit and tr.HitPos.z or nil

		-- вода не входит в MASK_SOLID, поэтому трасса «земли» её не видит:
		-- дрон уходил под воду и садился на дно. Поверхность воды считаем
		-- твёрдой опорой, чтобы он висел над ней.
		local water = util.TraceLine({
			start  = pos,
			endpos = pos - Vector(0, 0, 3000),
			filter = self:DrrTraceFilter(),
			mask   = MASK_WATER,
		})

		local surface = water.Hit and water.HitPos.z or nil

		-- уже под водой: ищем поверхность вверх, иначе останется на дне
		if util.PointContents(pos) and bit.band(util.PointContents(pos), CONTENTS_WATER) ~= 0 then
			local up = util.TraceLine({
				start  = pos,
				endpos = pos + Vector(0, 0, 3000),
				filter = self:DrrTraceFilter(),
				mask   = MASK_WATER,
			})

			if up.Hit then surface = up.HitPos.z end
		end

		if surface and (not self.DrrGroundZ or surface > self.DrrGroundZ) then
			self.DrrGroundZ = surface
		end

		-- потолок: в помещениях (d2_prison) высоту режет свод, а не земля
		-- Коробкой по габариту дрона, а не лучом из центра: свес крыши
		-- иначе виден только когда дрон уже врезался в него низом.
		local up = util.TraceHull({
			start  = pos,
			endpos = pos + Vector(0, 0, 3000),
			mins   = Vector(-58, -58, 0),
			maxs   = Vector(58, 58, 0),
			filter = self:DrrTraceFilter(),
			mask   = MASK_SOLID,
		})

		self.DrrCeilZ = up.Hit and up.HitPos.z or nil
	end

	-- рабочая высота над землёй с поправкой на потолок
	local minAlt = self.DrrMinAltitude or 800

	if self.DrrCeilZ then
		local head = self.DrrCeilZ - self:GetPos().z - 170
		if head > 150 then minAlt = math.min(minAlt, head) end
	end

	-- подъём только если сверху есть просвет под корпус
	local headroom = self.DrrCeilZ and (self.DrrCeilZ - self:GetPos().z) or 9999

	-- ведомый держится высоты лидера, а не общего «пола» 800: иначе не опускается
	local floorAlt = minAlt
	local follow = self.DrrFormHold and self:DrrFollowLeader() or nil

	-- высота от лидера действует только в строю: вне его сбрасываем сглаживание
	if not follow then self.DrrVertZ = nil end

	if follow then
		local leadAlt = follow.DrrGroundZ and (follow:GetPos().z - follow.DrrGroundZ)
			or (follow:GetPos().z - (self.DrrGroundZ or follow:GetPos().z))

		floorAlt = math.Clamp(leadAlt - 40, 60, minAlt)
	end

	self.DrrFloorZ = self.DrrGroundZ and (self.DrrGroundZ + floorAlt) or nil

	-- в строю вертикаль ведёт DrrFormFly: два «Up» из разных мест и давали скачки
	local formationFly = self.DrrFormHold and not IsValid(self.DrrAiTarget)

	if self.DrrGroundZ and self.DrrAutonomous and not formationFly
		and self:GetPos().z < self.DrrGroundZ + floorAlt
		and headroom > 190 then
		self:DrrMove("Up", DRR_PRIO.Floor)
	end

	-- история высоты: по ней задние дроны повторяют манёвр лидера с задержкой
	if (self.DrrCommander or IsValid(self:GetDriver())) and now > (self.DrrZHistAt or 0) then
		self.DrrZHistAt = now + 0.05
		self.DrrZHist = self.DrrZHist or {}

		local hist = self.DrrZHist
		hist[#hist + 1] = { t = now, z = self:GetPos().z }

		while #hist > 0 and now - hist[1].t > 3 do table.remove(hist, 1) end
	end

	-- серво-гул двигателя: тихий на месте, воет в полёте
	if now > (self.DrrServoAt or 0) then
		self.DrrServoAt = now + 0.15
		self:DrrServoUpdate()
	end

	if self.BoneIDs then
		-- клиент подстраивает HUD под перф-режим
		local perfNow = self:DrrPerf()

		if self.DrrPerfNW ~= perfNow then
			self.DrrPerfNW = perfNow
			self:SetNWBool("DrrPerf", perfNow)
		end

		-- тяжёлые пересчёты — реже кадра (визуально не заметно, нагрузка ниже)
		if now > (self.DrrNextHitbox or 0) then
			self.DrrNextHitbox = now + (self:DrrPerf() and 1/15 or 1/30)

			-- без игроков поблизости хитбоксы можно не двигать
			if not self:DrrPerf() or self:DrrNearPlayers(6000) then
				self:DrrUpdateHitboxes()
			end
		end

		-- Манипуляции костями реплицируются: в perf обновляем реже
		if not self:DrrPerf() or now > (self.DrrNextAim or 0) then
			self.DrrNextAim = now + 0.05
			self:UpdateHead()
			self:UpdateWeaponAim()
		end

		if now > (self.DrrNextTentacle or 0) then
			-- обычный режим: каждый тик сервера (66 по умолчанию, до 100 с -tickrate);
			-- угол кости всё равно не придёт чаще тика, поэтому интервал -tickrate
			self.DrrNextTentacle = now + (self:DrrPerf() and 1/50 or 1/90)
			self:UpdateTentacles()
		end
	end

	if now > (self.DrrNextModuleCheck or 0) then
		self.DrrNextModuleCheck = now + 0.3
		self:DrrCheckModulePickup()
	end

	-- джаммер фиксирует щит на сбитом уровне: автореген DRR не поднимает его
	if now > (self.DrrNextShieldLock or 0) then
		self.DrrNextShieldLock = now + 0.2

		if self.HasModule and self:HasModule("Shield") and self.DrrShieldLocked then
			timer.Destroy("dronesrewrite_regen" .. self:EntIndex())

			if (self.Buffer.ShieldHealth or 0) > (self.DrrShieldLockHP or 0) then
				self.Buffer.ShieldHealth = self.DrrShieldLockHP or 0
				self:SetNWInt("shield_health", math.max(math.floor(self.Buffer.ShieldHealth), 0))
			end
		end
	end

	-- регенерация: медленно лечимся при HP ниже 30%, щит снимаем только на 100%
	if now > (self.DrrNextRegen or 0) then
		self.DrrNextRegen = now + 1

		local hp  = self:GetHealth() or 0
		local max = self:GetDefaultHealth() or 0
		local reviveHP = math.max(max * 0.15, 12)

		-- уничтоженный дрон не воскресает от мелкого лечения (щит, модули, реген)
		if hp <= 0 then
			self.DrrDead = true
			self:SetHealthAmount(0)
		elseif self.DrrDead then
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
				self.DrrDead = nil
				self:DrrReviveShield()
			elseif hp < reviveHP then
			-- рядом свой дрон: он поднимает подбитого, прогресс не обнуляем
			local helper = false

			for _, o in ipairs(ents.FindByClass("drr_scout_drr")) do
				if o ~= self and IsValid(o) and drrSameOwner(self, o)
					and o:GetPos():DistToSqr(self:GetPos()) <= 700 * 700 then
					helper = true
					break
				end
			end

				if not helper then
					self:SetHealthAmount(0)
					hp = 0
				end
			else
				self.DrrDead = nil
				self:DrrReviveShield()
			end
		end

		-- мёртвого дрона не лечим: иначе труп «оживает» и не уничтожается
		if max > 0 and hp > 0 and not self.DrrDead then
			local step = max * (self.DrrRegenRate or 0.01)

			-- чинится всегда, пока жив: медленно, 1% в секунду.
			-- Щит здесь не снимаем: раньше он слетал на полном HP, а скан
			-- ставил его обратно — модуль мигал и звучал каждую секунду
			if hp < max then
				self:SetHealthAmount(math.min(max, hp + step))
			end

		-- страховка: HP ниже порога — поднимаем щит, даже если модуль есть,
		-- но сама плёнка уже нулевая (раньше проверялось только наличие модуля)
		if self.DrrAutonomous and not self.DrrShieldManual
			and hp < max * 0.35 and not self:DrrShieldUp() then
			self:DrrReviveShield()
		end
		end
	end

	if aiOn and now > (self.DrrNextAiScan or 0) then
			self.DrrNextAiScan = now + (self:DrrPerf() and 0.7 or 0.5)
		self:DrrAiScan()
	end

	-- автоном за пилота: камера показывает, куда ведёт ИИ, иначе база
	-- каждый тик возвращает обзор игрока и кажется, что автопилот «не работает»
	if self.DrrAutonomous and IsValid(self:GetDriver()) and self.CamAngles then
		local cam = self:GetCamera()

		if IsValid(cam) then cam:SetAngles(self.CamAngles) end
	end

	return true
end

function ENT:DrrServoUpdate()
	local phys = self:GetPhysicsObject()
	local spd = IsValid(phys) and phys:GetVelocity():Length() or 0

	if not self.DrrServo then
		self.DrrServo = CreateSound(self, self.DrrServoSound or "npc/combine_gunship/gunship_engine_loop3.wav")

		if not self.DrrServo then return end

		self.DrrServo:SetSoundLevel(75)
		self.DrrServo:Play()
	end

	if not self.DrrServo:IsPlaying() then self.DrrServo:Play() end

	local frac = math.Clamp(spd / 900, 0, 1)

	self.DrrServo:ChangeVolume((self.DrrServoVolume or 0.55) * (0.25 + 0.75 * frac))
	self.DrrServo:ChangePitch(55 + 42 * frac)
end

-- Список дружественных NPC: добавление/удаление по классу, запрос списка
util.AddNetworkString("drr_scout_friends_set")
util.AddNetworkString("drr_scout_friends_get")
util.AddNetworkString("drr_scout_friends_list")

-- Список дружественных NPC общий на игрока: правка с одного дрона действует на все его дроны
-- Список друзей лежит в garrysmod/data/drr_scout/<steamid64>.txt:
-- переживает перезапуск сервера и смену карты
local FRIENDS_DIR = "drr_scout"
local FRIENDS_MAX = 40

local function friendsPath(ply)
	local id = string.gsub(tostring(ply:SteamID64() or ""), "[^%d]", "")

	if id == "" then return end

	return FRIENDS_DIR .. "/" .. id .. ".txt"
end

local function saveFriends(ply)
	local path = friendsPath(ply)
	if not path then return end

	file.CreateDir(FRIENDS_DIR)

	local keys = {}

	for cls in pairs(ply.DrrFriendClasses or {}) do
		if type(cls) == "string" and #cls > 0 and #cls <= 64 then
			keys[#keys + 1] = cls
		end
	end

	file.Write(path, util.TableToJSON(keys) or "[]")
end

local function loadFriends(ply)
	local list = {}
	local path = friendsPath(ply)

	if not path or not file.Exists(path, "DATA") then return list end

	local raw = file.Read(path, "DATA")
	local data = raw and util.JSONToTable(raw)

	if type(data) ~= "table" then return list end

	for _, cls in ipairs(data) do
		if type(cls) == "string" and #cls > 0 and #cls <= 64 then
			list[cls] = true
		end
	end

	return list
end

local function friendsOfOwner(ply)
	if not ply.DrrFriendClasses then
		ply.DrrFriendClasses = loadFriends(ply)
	end

	return ply.DrrFriendClasses
end

local function pushToDrones(ply)
	local list = friendsOfOwner(ply)

	for _, e in ipairs(ents.FindByClass("drr_scout_drr")) do
		if IsValid(e) and (e.Owner == ply or e:GetOwner() == ply) then
			e.DrrFriendClasses = table.Copy(list)
		end
	end
end

-- загружаем список при входе, иначе дрон успевает заспавниться с пустым
hook.Add("PlayerInitialSpawn", "drr_scout_friends_load", function(ply)
	timer.Simple(1, function()
		if not IsValid(ply) then return end

		friendsOfOwner(ply)
		pushToDrones(ply)
	end)
end)

net.Receive("drr_scout_friends_set", function(_, ply)
	if not netAllowed(ply, "friends", 10) then return end

	local drone = playerDrone(ply)
	if not drone then return end

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
	saveFriends(ply)
	drone.DrrFriendClasses = table.Copy(list)
end)

net.Receive("drr_scout_friends_get", function(_, ply)
	if not netAllowed(ply, "friends_get", 10) then return end

	local drone = playerDrone(ply)
	if not drone then return end

	local list = ply.DrrFriendClasses or drone.DrrFriendClasses or {}
	local keys = {}

	for cls in pairs(list) do keys[#keys + 1] = cls end

	table.sort(keys)

	net.Start("drr_scout_friends_list")
	net.WriteUInt(#keys, 8)

	for _, cls in ipairs(keys) do
		net.WriteString(cls)
	end

	net.Send(ply)
end)

function ENT:OnRemove()
	if self.DrrServo then
		self.DrrServo:Stop()
		self.DrrServo = nil
	end

	self:DrrRemoveHitboxes()

	if DRONES_REWRITE and DRONES_REWRITE.DrrCryoDef then
		DRONES_REWRITE.Weapons = DRONES_REWRITE.Weapons or {}

		if not DRONES_REWRITE.Weapons["Cryo"] then
			DRONES_REWRITE.Weapons["Cryo"] = DRONES_REWRITE.DrrCryoDef
		end
	end

	if self.BaseClass and self.BaseClass.OnRemove then
		self.BaseClass.OnRemove(self)
	end
end
