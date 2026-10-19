VJ = VJ or {}
VJ.CPT = VJ.CPT or {}
VJ.CPT.AnimationCache = VJ.CPT.AnimationCache or {}

local bit_band = bit.band
local string_start = string.StartWith
local string_remove = string.gsub

STUDIO_LOOPING = 1
STUDIO_SNAP = 2
STUDIO_DELTA = 4
STUDIO_AUTOPLAY = 8
STUDIO_POST = 16
STUDIO_ALLZEROS = 32
STUDIO_FRAMEANIM = 64
STUDIO_CYCLEPOSE = 128
STUDIO_REALTIME = 256
STUDIO_LOCAL = 512
STUDIO_HIDDEN = 1024
STUDIO_OVERRIDE = 2048
STUDIO_ACTIVITY = 4096
STUDIO_EVENT = 8192
STUDIO_WORLD = 16384
STUDIO_NOFORCELOOP = 32768
STUDIO_EVENT_CLIENT = 65536
STUDIO_WORLD_AND_RELATIVE = 131072
STUDIO_ROOTXFORM = 262144

function VJ.CPT:CacheAnimations(ent)
	if !IsValid(ent) then return end
	local model = ent:GetModel()
    if model == nil then return end
	if VJ.CPT.AnimationCache[model] then return end

	VJ.CPT.AnimationCache[model] = {}
	local animCache = 0
	local info = nil
	local done = ent:GetAnimInfo(0).label
	for i = 0, ent:GetAnimCount() -1 do
		info = ent:GetAnimInfo(i)
		if info then
			local label, fps, flags, frames = info.label, info.fps, info.flags, info.numframes
			if string_start(label,"@") then
				label = string_remove(label,"@","")
			end
			VJ.CPT.AnimationCache[model][label] = {
				Sequence = label,
				FPS = fps,
				StudioFlags = flags,
				FrameCount = frames,
				Activity = ent:GetSequenceActivity(ent:LookupSequence(label)),
				IsLoop = bit_band(flags, STUDIO_LOOPING) != 0,
				IsAdditive = bit_band(flags, STUDIO_DELTA) != 0,
				IsLayered = bit_band(flags, STUDIO_AUTOPLAY) != 0,
				HasEvents = bit_band(flags, STUDIO_EVENT) != 0,
				NoForceLoop = bit_band(flags, STUDIO_NOFORCELOOP) != 0,
			}
			animCache = animCache +1
			-- if label == done then
			-- 	break
			-- end
		end
	end

	print("[Shared Resources] Cached " .. animCache .. " animation data entries for " .. model)
	if GetConVar("developer"):GetInt() == 1 then
		PrintTable(VJ.CPT.AnimationCache[model])
	end
end

function VJ.CPT:GetCachedAnimations(mdlOrEnt)
	if !mdlOrEnt then return end
	if isstring(mdlOrEnt) then
		return VJ.CPT.AnimationCache[mdlOrEnt]
	elseif IsValid(mdlOrEnt) then
		return VJ.CPT.AnimationCache[mdlOrEnt:GetModel()]
	end
end

function VJ.CPT:GetCachedAnimation(mdlOrEnt,anim)
	if !mdlOrEnt or !anim then return end
	local animCache = VJ.CPT:GetCachedAnimations(mdlOrEnt)
	if animCache then
		return animCache[anim]
	end
end

function VJ.CPT:AnimationHasFlag(mdlOrEnt,anim,flag)
	if !mdlOrEnt or !anim or !flag then return end
	local animData = VJ.CPT:GetCachedAnimation(mdlOrEnt,anim)
	if animData then
		return bit_band(animData.StudioFlags,flag) == flag
	end
end

function VJ.CPT:GetAnimationActivity(ent,anim)
	local animCache = VJ.CPT:GetCachedAnimations(ent:GetModel(),anim)
	return animCache && animCache.Activity or -1
end

hook.Add("OnEntityCreated","SRP.CacheAnimations",function(ent)
	if !IsValid(ent) then return end
	if ent:IsNPC() or ent:IsNextBot() or ent:IsPlayer() or ent:IsRagdoll() then
		timer.Simple(0.05,function()
			if !IsValid(ent) then return end
			VJ.CPT:CacheAnimations(ent)
		end)
	end
end)

if SERVER then
	function VJ.CPT:SetClearPos(self,origin,disableGroundSnap)
		if !IsValid(self) then return end
		local mins = self:OBBMins()
		local maxs = self:OBBMaxs()
		local pos = origin || self:GetPos()
		local savePos = pos
		local nearents = ents.FindInBox(pos +mins,pos +maxs)
		maxs.x = maxs.x *2
		maxs.y = maxs.y *2
		local zMax = 0
		local entTgt
		for _,ent in ipairs(nearents) do
			if(ent != self && ent:GetSolid() != SOLID_NONE && ent:GetSolid() != SOLID_BSP && gamemode.Call("ShouldCollide",self,ent) != false) then
				local obbMaxs = ent:OBBMaxs()
				if(obbMaxs.z > zMax) then
					zMax = obbMaxs.z
					entTgt = ent
				end
			end
		end
		local tbl_filter = {self,entTgt}
		local stayaway = zMax > 0
		if(!stayaway) then
			pos.z = pos.z +10
		else
			zMax = zMax +10
		end
		local left = Vector(0,1,0)
		local right = left *-1
		local forward = Vector(1,0,0)
		local back = forward *-1
		local trace_left = util.TraceLine({
			start = pos,
			endpos = pos +left *maxs.y,
			filter = tbl_filter
		})
		local trace_right = util.TraceLine({
			start = pos,
			endpos = pos +right *maxs.y,
			filter = tbl_filter
		})
		if(trace_left.Hit || trace_right.Hit) then
			if(trace_left.Fraction < trace_right.Fraction) then
				pos = pos +right *((trace_right.Fraction -trace_left.Fraction) *maxs.y)
			elseif(trace_right.Fraction < trace_left.Fraction) then
				pos = pos +left *((trace_left.Fraction -trace_right.Fraction) *maxs.y)
			end
		elseif(stayaway) then
			pos = pos +(math.random(1,2) == 1 && left || right) *maxs.y *1.8
			stayaway = false
		end
		local trace_forward = util.TraceLine({
			start = pos,
			endpos = pos +forward *maxs.x,
			filter = tbl_filter
		})
		local trace_backward = util.TraceLine({
			start = pos,
			endpos = pos +back *maxs.x,
			filter = tbl_filter
		})
		if(trace_forward.Hit || trace_backward.Hit) then
			if(trace_forward.Fraction < trace_backward.Fraction) then
				pos = pos +back *((trace_backward.Fraction -trace_forward.Fraction) *maxs.x)
			elseif(trace_backward.Fraction < trace_forward.Fraction) then
				pos = pos +forward *((trace_forward.Fraction -trace_backward.Fraction) *maxs.x)
			end
		elseif(stayaway) then
			pos = pos +(math.random(1,2) == 1 && forward || back) *maxs.x *1.8
			stayaway = false
		end
		if(stayaway) then -- We can't avoid whatever it is we're stuck in,let's try to spawn on top of it
			local start = entTgt:GetPos()
			start.z = start.z +zMax
			local endpos = start
			endpos.z = endpos.z +maxs.z
			local tr = util.TraceLine({
				start = start,
				endpos = endpos,
				filter = tbl_filter
			})
			if(!tr.Hit || (!tr.HitWorld && gamemode.Call("ShouldCollide",self,tr.Entity) == false)) then
				pos.z = start.z
				stayaway = false
			else -- Just try to move to whatever direction seems best
				local trTgt = trace_left
				if(trace_right.Fraction < trTgt.Fraction) then trTgt = trace_right end
				if(trace_forward.Fraction < trTgt.Fraction) then trTgt = trace_forward end
				if(trace_backward.Fraction < trTgt.Fraction) then trTgt = trace_backward end
				pos = pos +trTgt.Normal *maxs.x
			end
		end
		if !disableGroundSnap then
			local trDown = util.TraceLine({
				start = pos,
				endpos = pos +Vector(0,0,maxs.z *-2),
				filter = tbl_filter,
				-- collisiongroup = COLLISION_GROUP_WORLD,
			})
			if(trDown.Hit) then
				debugoverlay.Line(pos,trDown.HitPos,5,Color(255,255,255))
				debugoverlay.Box(pos,Vector(-2,-2,-2),Vector(2,2,2),5,Color(255,255,255))
				pos.z = trDown.HitPos.z
			end
		end
		-- pos.z = pos.z + 3
		-- debugoverlay.Box(pos,Vector(-2,-2,-2),Vector(2,2,2),5,Color(0,26,255))
		local minC,maxC = self:GetCollisionBounds()
		local corners = { // 4 corners
			Vector(minC.x,minC.y,0),
			Vector(minC.x,maxC.y,0),
			Vector(maxC.x,minC.y,0),
			Vector(maxC.x,maxC.y,0)
		}
		for _,v in pairs(corners) do
			if !util.IsInWorld(pos +v) then
				-- print("BAD CORNER: ",pos +v)
				debugoverlay.Box(pos,Vector(-2,-2,-2),Vector(2,2,2),5,Color(255,0,0))
				local toSafeDir = (savePos - v):GetNormalized()
				local trace1 = util.TraceLine({
					start = v,
					endpos = savePos,
					filter = tbl_filter,
					collisiongroup = COLLISION_GROUP_WORLD,
					output = {}
				})
				debugoverlay.Line(v,trace1.HitPos,5,Color(255,0,230))
				if trace1.Hit && util.IsInWorld(trace1.HitPos) then
					-- print("Found possible entry point:",trace1.HitPos)
					debugoverlay.Box(trace1.HitPos,Vector(-4,-4,-4),Vector(4,4,4),5,Color(255,0,230))
					local trace2 = util.TraceLine({
						start = trace1.HitPos,
						endpos = v,
						filter = tbl_filter,
						collisiongroup = COLLISION_GROUP_WORLD,
						output = {}
					})
					debugoverlay.Line(v,trace2.HitPos,5,Color(67,227,255))
					if trace2.Hit && util.IsInWorld(trace2.HitPos) then
						-- print("Final valid position near world edge:",trace2.HitPos)
						debugoverlay.Box(trace2.HitPos,Vector(-4,-4,-4),Vector(4,4,4),5,Color(67,227,255))
						pos = trace2.HitPos + trace2.HitNormal *16
					else
						pos = savePos
					end
				else
					pos = savePos
				end
				break
			end
		end
		if !util.IsInWorld(pos) then
			pos = savePos
		end
		pos = pos +Vector(0,0,6)

		debugoverlay.Line(self:GetPos(),pos,5,Color(47,255,0))
		debugoverlay.Box(pos,Vector(-2,-2,-2),Vector(2,2,2),5,Color(13,255,0))
		self:SetPos(pos)

		return pos
	end

    local world = game.GetWorld()
    local vecZero = Vector(0, 0, 0)
    local vecForward = Vector(1, 0, 0)

    local function _resolveEnt(ent, fallback)
        if IsValid(ent) then return ent end
        if IsValid(fallback) then return fallback end
        return world
    end

    local function _resolvePos(data, attacker)
        local origin = data.Origin or data.StartPos or data.Position
        if isvector(origin) then return origin end
        if IsValid(attacker) && attacker != world then return attacker:GetPos() end
        return vecZero
    end

    local function _resolveDir(data, attacker)
        local dir = data.Direction or data.AttackDirection or data.ConeDirection
        if isvector(dir) && dir:LengthSqr() > 0 then return dir:GetNormalized() end
        if IsValid(attacker) && attacker != world then return attacker:GetForward() end
        return vecForward
    end

    local function _doCallbacks(callbacks, ...)
        if isfunction(callbacks) then
            return callbacks(...) != false
        end
        if istable(callbacks) then
            for _, fn in ipairs(callbacks) do
                if isfunction(fn) && fn(...) == false then return false end
            end
        end
        return true
    end

    local function _isIgnored(ent, ignore)
        if !ignore then return false end
        if IsValid(ignore) then return ent == ignore end
        if isstring(ignore) then return ent:GetClass() == ignore end
        if !istable(ignore) then return false end

        if ignore[ent] == true or ignore[ent:GetClass()] == true then return true end
        for _, value in pairs(ignore) do
            if IsValid(value) && value == ent then return true end
            if isstring(value) && value == ent:GetClass() then return true end
        end
        return false
    end

    local function _runFilter(ent, filter, data)
        if !filter then return true end
        if isfunction(filter) then return filter(ent, data) != false end
        if IsValid(filter) then return ent == filter end
        if isstring(filter) then return ent:GetClass() == filter end
        if !istable(filter) then return true end

        if filter[ent] == true or filter[ent:GetClass()] == true then return true end
        for _, value in pairs(filter) do
            if IsValid(value) && value == ent then return true end
            if isstring(value) && value == ent:GetClass() then return true end
        end
        return false
    end

    local function _getDamage(value, ent, data, fallback)
        if isfunction(value) then
            local result = value(ent, data)
            if isnumber(result) then return result end
            return fallback
        end
        return tonumber(value) or fallback
    end

    local function _applyDamage(dmgInfo, ent, data, attacker, inflictor, amount, dmgType, dmgPos)
        dmgInfo:SetDamage(amount)
        dmgInfo:SetDamageType(dmgType)
        dmgInfo:SetAttacker(attacker)
        dmgInfo:SetInflictor(inflictor)
        dmgInfo:SetDamagePosition(dmgPos)

        if data.DamageFlag != nil then dmgInfo:SetDamageCustom(tonumber(data.DamageFlag) or 0) end
        if data.AmmoType != nil then dmgInfo:SetAmmoType(tonumber(data.AmmoType) or -1) end
        if isvector(data.ReportedPosition) then dmgInfo:SetReportedPosition(data.ReportedPosition) end
    end

    --[[---------------------------------------------------------------------
        Common fields:
            Attacker            entity | default: world
            Inflictor           entity | default: Attacker/world
            Origin              Vector | default: Attacker:GetPos()/0,0,0
            Direction           Vector | default: Attacker:GetForward()/+X
            Distance            number | default: 100
            Angle               number | default: 100 degrees
            Damage              number/function | default: 10
            DamageType          enum | default: DMG_SLASH
            DamageAttacker      bool | default: false
            Use3DAngle          bool | default: false (VJ-style flat XY cone)
            VisibilityCheck     bool | default: false
            Filter              entity/class/table/function | optional allow-list
            Ignore              entity/class/table | optional deny-list
            Entities            table | optional explicit entity list
            MaxHits             number | optional
            DamageForce         Vector/number/function/false | default: VJ-style
            DamagePosition      Vector/function | default: ent:NearestPoint(Origin)
            PreChecks / PostChecks / PreDamage / PostDamage callbacks

        Returns: hitEntities, hitCount
    -----------------------------------------------------------------------]]
    function VJ.CPT:DoDamage(tbl)
        tbl = istable(tbl) && tbl or {}
        local attacker = _resolveEnt(tbl.Attacker)
        local inflictor = _resolveEnt(tbl.Inflictor, attacker)
        local origin = _resolvePos(tbl, attacker)
        local direction = _resolveDir(tbl, attacker)
        local distance = math.max(tonumber(tbl.Distance or tbl.Radius) or 100, 0)
        local angle = math.Clamp(tonumber(tbl.Angle or tbl.AngleRadius) or 100, 0, 180)
        local damageType = tonumber(tbl.DamageType) or DMG_SLASH
        local damageAttacker = tbl.DamageAttacker == true
        local use3DAngle = tbl.Use3DAngle == true
        local visibilityCheck = tbl.VisibilityCheck == true
        local maxHits = tonumber(tbl.MaxHits)
        local preChecks = tbl.PreChecks or tbl.PreCheck
        local postChecks = tbl.PostChecks or tbl.PostCheck
        local hitEnts = {}
        local candidates = istable(tbl.Entities) && tbl.Entities or ents.FindInSphere(origin, distance)
        local angleCos = math.cos(math.rad(angle))

        for _, ent in ipairs(candidates) do
            if !IsValid(ent) then continue end
            if !_doCallbacks(preChecks, ent, tbl) then continue end
            if !damageAttacker && ent == attacker then continue end
            if _isIgnored(ent, tbl.Ignore) then continue end
            if !_runFilter(ent, tbl.Filter, tbl) then continue end

            local targetPos = ent:NearestPoint(origin)
            local delta = targetPos - origin
            if delta:LengthSqr() > (distance * distance) then continue end

            local dot
            if use3DAngle then
                if delta:LengthSqr() <= 0.0001 then
                    dot = 1
                else
                    dot = direction:Dot(delta:GetNormalized())
                end
            else
                local flatDir = Vector(direction.x, direction.y, 0)
                local flatDelta = Vector(delta.x, delta.y, 0)
                if flatDir:LengthSqr() <= 0.0001 or flatDelta:LengthSqr() <= 0.0001 then
                    dot = 1
                else
                    dot = flatDir:GetNormalized():Dot(flatDelta:GetNormalized())
                end
            end
            if dot <= angleCos then continue end

            if visibilityCheck then
                local visible = ent:VisibleVec(origin)
                if !visible && IsValid(attacker) && attacker != world then visible = ent:Visible(attacker) end
                if !visible then continue end
            end
            if !_doCallbacks(postChecks, ent, tbl) then continue end

            local amount = _getDamage(tbl.Damage, ent, tbl, 10)
            local dmgPos = targetPos
            if isvector(tbl.DamagePosition) then
                dmgPos = tbl.DamagePosition
            elseif isfunction(tbl.DamagePosition) then
                local result = tbl.DamagePosition(ent, tbl)
                if isvector(result) then dmgPos = result end
            end

            local dmgInfo = DamageInfo()
            _applyDamage(dmgInfo, ent, tbl, attacker, inflictor, amount, damageType, dmgPos)

            local force = tbl.DamageForce
            if force == nil then
                force = direction * ((math.max(amount, 0) + 100) * 70)
            elseif isfunction(force) then
                force = force(ent, amount, direction, tbl)
            elseif isnumber(force) then
                force = direction * force
            end
            if isvector(force) then dmgInfo:SetDamageForce(force) end

            if !_doCallbacks(tbl.PreDamage, ent, dmgInfo, tbl) then continue end
            ent:TakeDamageInfo(dmgInfo)
            hitEnts[#hitEnts + 1] = ent
            _doCallbacks(tbl.PostDamage, ent, dmgInfo, tbl)

            if maxHits && maxHits > 0 && #hitEnts >= maxHits then break end
        end

        return hitEnts, #hitEnts
    end

    --[[---------------------------------------------------------------------
        Common fields:
            Attacker             entity | default: world
            Inflictor            entity | default: Attacker/world
            Origin               Vector | default: Attacker:GetPos()/0,0,0
            Radius               number | default: 150
            Damage               number/function | default: 15
            DamageType           enum | default: DMG_BLAST
            DamageAttacker       bool | default: false
            RealisticRadius      bool | default: true (VJ-style falloff)
            DisableVisibilityCheck bool | default: false
            Force                number/function/false | default: false
            UpForce              number/false | default: Force behavior
            UseConeDegree        number | optional
            UseConeDirection     Vector | default: Direction/Attacker forward
            Filter / Ignore / Entities / MaxHits
            PreChecks / PostChecks / PreDamage / PostDamage callbacks

        Returns: hitEntities, hitCount
    -----------------------------------------------------------------------]]
    function VJ.CPT:DoSphereDamage(tbl)
        tbl = istable(tbl) && tbl or {}
        local attacker = _resolveEnt(tbl.Attacker)
        local inflictor = _resolveEnt(tbl.Inflictor, attacker)
        local origin = _resolvePos(tbl, attacker)
        local radius = math.max(tonumber(tbl.Radius or tbl.Distance) or 150, 0)
        local damageType = tonumber(tbl.DamageType) or DMG_BLAST
        local damageAttacker = tbl.DamageAttacker == true
        local realisticRadius = tbl.RealisticRadius != false
        local visibilityCheck = tbl.DisableVisibilityCheck != true
        local maxHits = tonumber(tbl.MaxHits)
        local preChecks = tbl.PreChecks or tbl.PreCheck
        local postChecks = tbl.PostChecks or tbl.PostCheck
        local hitEnts = {}

        local candidates
        if istable(tbl.Entities) then
            candidates = tbl.Entities
        elseif isnumber(tbl.UseConeDegree) then
            local coneDir = _resolveDir({Direction = tbl.UseConeDirection or tbl.Direction}, attacker)
            candidates = ents.FindInCone(origin, coneDir, radius, math.cos(math.rad(tbl.UseConeDegree)))
        else
            candidates = ents.FindInSphere(origin, radius)
        end

        for _, ent in ipairs(candidates) do
            if !IsValid(ent) then continue end
            if !_doCallbacks(preChecks, ent, tbl) then continue end
            if !damageAttacker && ent == attacker then continue end
            if _isIgnored(ent, tbl.Ignore) then continue end
            if !_runFilter(ent, tbl.Filter, tbl) then continue end

            local nearestPos = ent:NearestPoint(origin)
            local dist = origin:Distance(nearestPos)
            if dist > radius then continue end

            if visibilityCheck then
                local visible = ent:VisibleVec(origin)
                if !visible && IsValid(attacker) && attacker != world then visible = ent:Visible(attacker) end
                if !visible then continue end
            end
            if !_doCallbacks(postChecks, ent, tbl) then continue end

            local maxDamage = _getDamage(tbl.Damage, ent, tbl, 15)
            local amount = maxDamage
            if realisticRadius && radius > 0 then
                amount = math.min(math.max(maxDamage * ((radius - dist) + 150) / radius, maxDamage / 2), maxDamage)
            end

            local dmgPos = nearestPos
            if isvector(tbl.DamagePosition) then
                dmgPos = tbl.DamagePosition
            elseif isfunction(tbl.DamagePosition) then
                local result = tbl.DamagePosition(ent, tbl)
                if isvector(result) then dmgPos = result end
            end

            local dmgInfo = DamageInfo()
            _applyDamage(dmgInfo, ent, tbl, attacker, inflictor, amount, damageType, dmgPos)

            local force = tbl.Force
            if isfunction(force) then force = force(ent, amount, origin, tbl) end
            if isnumber(force) && force != 0 then
                local upForce = tbl.UpForce
                local entCenter = ent:GetPos() + ent:OBBCenter()
                local forceDir = entCenter - origin
                if forceDir:LengthSqr() <= 0.0001 then forceDir = vecForward end

                if ent:GetClass() == "prop_ragdoll" or ent:GetMoveType() == MOVETYPE_VPHYSICS then
                    local phys = ent:GetPhysicsObject()
                    if IsValid(phys) then
                        local propForce = ent:GetClass() == "prop_ragdoll" && force * 1.5 or force
                        local up = (upForce == false or upForce == nil) && (propForce / 9.4) or (tonumber(upForce) or 0)
                        phys:ApplyForceCenter((entCenter + ent:GetUp() * up - origin) * propForce)
                    end
                else
                    local finalForce = force * 1.2
                    local up = (upForce == false or upForce == nil) && finalForce or (tonumber(upForce) or 0)
                    dmgInfo:SetDamageForce((entCenter + ent:GetUp() * up - origin) * finalForce)
                end
            elseif isvector(force) then
                dmgInfo:SetDamageForce(force)
            end

            if !_doCallbacks(tbl.PreDamage, ent, dmgInfo, tbl) then continue end
            ent:TakeDamageInfo(dmgInfo)
            hitEnts[#hitEnts + 1] = ent
            _doCallbacks(tbl.PostDamage, ent, dmgInfo, tbl)

            if maxHits && maxHits > 0 && #hitEnts >= maxHits then break end
        end

        return hitEnts, #hitEnts
    end
end