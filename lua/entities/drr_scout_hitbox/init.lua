AddCSLuaFile("shared.lua")
include("shared.lua")

local HALF_DEFAULT = 8

function ENT:Initialize()
	self:SetModel("models/props_junk/PopCan01a.mdl")
	self:SetNoDraw(true)
	self:DrawShadow(false)
	self:SetMoveType(MOVETYPE_NONE)
	self:SetSolid(SOLID_BBOX)
	self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	local half = self.DrrHalf or HALF_DEFAULT
	self:SetCollisionBounds(Vector(-half, -half, -half), Vector(half, half, half))
end

-- Урон по прокси уходит в дрона
function ENT:OnTakeDamage(dmg)
	local drone = self.DrrDrone
	if not IsValid(drone) then return end

	drone:TakeDamageInfo(dmg)
end
