-- Свой тип урона для криооружия: Source не имеет DMG_CRYO,
-- поэтому занимаем свободный бит и сами решаем, кто его принимает.

DMG_CRYO = DMG_CRYO or bit.lshift(1, 25)

-- Страйдер принимает урон только через DMG_BLAST (50 HP + флинч) либо
-- внутренний DMG_GENERIC. Движковый путь ненадёжен: на части сборок
-- DMG_GENERIC по страйдеру просто не проходит. Поэтому сначала пробуем
-- штатно, а если HP не изменился — снимаем ровно 5 HP напрямую.
local STRIDER_DAMAGE = 5

-- Урон по тяжёлым юнитам считается от их максимального HP, чтобы смерть
-- занимала примерно одинаковое время: не ваншот и не марафон на 5 HP.
-- 1.2 % от максимума за попадание: 3500 HP → 40, 1000 HP → 12, 255 HP → 4.
local HEAVY_FRACTION = 0.012

function LvsHeavyHitDamage(ent)
	local mx = 0

	if IsValid(ent) then
		mx = ent.GetMaxHealth and (ent:GetMaxHealth() or 0) or 0
	end

	return math.Clamp(math.max(mx * HEAVY_FRACTION, 4), 4, 40)
end

hook.Remove("OnEntityCreated", "lvs_scout_strider_spawnshield")
hook.Remove("EntityTakeDamage", "lvs_scout_strider_cryo")

local function dbgOn()
	local cv = GetConVar("lvs_scout_debug")
	return cv and cv:GetBool()
end

hook.Add("EntityTakeDamage", "lvs_scout_strider_cryo", function(ent, dmg)
	if not IsValid(ent) or ent:GetClass() ~= "npc_strider" then return end

	local dtype = dmg:GetDamageType()

	if bit.band(dtype, DMG_CRYO) == 0 then return end

	local hpBefore = ent:Health() or 0
	local attacker = dmg:GetAttacker()
	local inflictor = dmg:GetInflictor()

	local hit = LvsHeavyHitDamage(ent)

	dmg:SetDamageType(DMG_GENERIC)
	dmg:SetDamage(hit)

	-- штатный путь мог не сработать: проверяем следующий тик
	timer.Simple(0, function()
		if not IsValid(ent) then return end

		local hpAfter = ent:Health() or 0

		if hpAfter < hpBefore then return end

		local newHp = math.max(hpBefore - hit, 0)

		ent:SetHealth(newHp)

		if newHp <= 0 then
			local kill = DamageInfo()

			kill:SetDamage(100000)
			kill:SetDamageType(DMG_GENERIC)
			kill:SetAttacker(IsValid(attacker) and attacker or ent)
			kill:SetInflictor(IsValid(inflictor) and inflictor or ent)

			ent:TakeDamageInfo(kill)
		end

		if dbgOn() then
			print(string.format("[LVS] strider direct: %d -> %d", hpBefore, ent:Health() or 0))
		end
	end)

	if dbgOn() then
		print(string.format("[LVS] strider cryo: type=%d hp=%d", dtype, hpBefore))
	end
end)


-- Диагностика: нанести 5 криоурона страйдеру под прицелом (обход оружия)
concommand.Add("lvs_scout_strider_test", function(ply)
	if not IsValid(ply) then return end

	local tr = ply:GetEyeTrace()

	if not IsValid(tr.Entity) or tr.Entity:GetClass() ~= "npc_strider" then
		print("[LVS] под прицелом не страйдер:", tr.Entity)
		return
	end

	local ent = tr.Entity
	local before = ent:Health() or 0
	local dmg = DamageInfo()

	dmg:SetDamage(STRIDER_DAMAGE)
	dmg:SetDamageType(DMG_CRYO)
	dmg:SetAttacker(ply)
	dmg:SetInflictor(ply)

	ent:TakeDamageInfo(dmg)

	timer.Simple(0, function()
		if not IsValid(ent) then return end

		print(string.format("[LVS] test: hp %d -> %d", before, ent:Health() or 0))
	end)
end)
