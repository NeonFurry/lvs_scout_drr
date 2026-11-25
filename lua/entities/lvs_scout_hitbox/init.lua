AddCSLuaFile("shared.lua")
include("shared.lua")

local HALF = 8

function ENT:Initialize()
	self:SetModel("models/props_junk/PopCan01a.mdl")
	self:SetNoDraw(true)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	self:SetCollisionBounds(Vector(-HALF, -HALF, -HALF), Vector(HALF, HALF, HALF))
end

-- Урон по прокси уходит в дрона
function ENT:OnTakeDamage(dmg)
	local drone = self.LvsDrone
	if not IsValid(drone) then return end

	drone:TakeDamageInfo(dmg)
end
