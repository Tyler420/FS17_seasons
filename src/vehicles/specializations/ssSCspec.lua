----------------------------------------------------------------------------------------------------
-- SC SPECIALIZATION
----------------------------------------------------------------------------------------------------
-- Author:  Rahkiin, reallogger
--
-- Copyright (c) Realismus Modding, 2017
----------------------------------------------------------------------------------------------------

ssSCspec = {}

ssSCspec.MAX_CHARS_TO_DISPLAY = 20
ssSCspec.inflationPressures = {"Low","Normal"}
ssSCspec.LOW_INFLATION_PRESSURE = 80
ssSCspec.NORMAL_INFLATION_PRESSURE = 180

function ssSCspec:prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Motorized, specializations)
end

function ssSCspec:load(savegame)

    self.ssPlayerInRangeTire = false
    self.ssInRangeOfWorkshop = nil
    self.ssTireLoadExceed = false

    if savegame ~= nil then
        -- TODO: save setting
        self.ssInflationPressure = ssXMLUtil.getFloat(savegame.xmlFile, savegame.key .. "#ssInflationPressure", "Normal")
    end

end

function ssSCspec:delete()
end

function ssSCspec:mouseEvent(posX, posY, isDown, isUp, button)
end

function ssSCspec:keyEvent(unicode, sym, modifier, isDown)
end

local function applySC(self)

    local soilWater = g_currentMission.environment.groundWetness

    for _, wheel in pairs(self.wheels) do

        if wheel.hasGroundContact and not wheel.mrNotAWheel then
            local x0, y0, z0
            local x1, y1, z1
            local x2, y2, z2

            local width = wheel.width
            local radius = wheel.radius
            local length = math.max(0.1, 0.35 * radius);
            local contactArea = length * width
            local penetrationResistance = 4e5 / (20 + (g_currentMission.environment.groundWetness * 100 + 5)^2)

            wheel.load = getWheelShapeContactForce(wheel.node, wheel.wheelShape)
            local oldPressure = wheel.groundPressure
            if oldPressure == nil then oldPressure = 10 end
            if wheel.load == nil then wheel.load = 0 end

            local inflationPressure = ssSCspec.NORMAL_INFLATION_PRESSURE
            if self.ssInflationPressure == "Low" then
                inflationPressure = ssSCspec.LOW_INFLATION_PRESSURE
            end

            if wheel.ssMaxLoad == nil then
                wheel.ssMaxDeformation = wheel.maxDeformation
                wheel.ssMaxLoad = ssSCspec:getTireMaxLoad(wheel, inflationPressure)
            end

            wheel.contactArea = 0.38 * wheel.load^0.7 * math.sqrt(width / (radius * 2)) / inflationPressure^0.45

            -- TODO: No need to store groundPressure, but for display
            wheel.groundPressure = oldPressure * 999 / 1000 +  wheel.load / wheel.contactArea / 1000

            -- soil saturation index 0.2
            -- c index Cp 0.7
            -- reference pressure 100 kPa
            -- reference saturation Sk 50%
            local soilBulkDensityRef = 0.2 * (soilWater - 0.5) + 0.7 * math.log10(wheel.groundPressure / 100)

            --below only for debug print. TODO: remove when done
            wheel.soilBulkDensity = soilBulkDensityRef

            local wheelRot = getWheelShapeAxleSpeed(wheel.node, wheel.wheelShape)
            local wheelRotDir

            if wheelRot ~= 0 then
                wheelRotDir = wheelRot / math.abs(wheelRot)
            else
                wheelRotDir = 1
            end

            local underTireCLayers = 0
            local fwdTireCLayers = 0
            local wantedC = 3

            -- TODO: 2 lines below can be local and no need to store CLayers in wheel
            local x0, z0, x1, z1, x2, z2, fwdLayers = ssSCspec:getCLayers(wheel, width, length, radius, radius * wheelRotDir * -1, 2 * radius * wheelRotDir)
            local x, z, widthX, widthZ, heightX, heightZ = Utils.getXZWidthAndHeight(g_currentMission.terrainDetailHeightId, x0, z0, x1, z1, x2, z2)
            ssDebug:drawDensityParallelogram(x, z, widthX, widthZ, heightX, heightZ, 0.25, 255, 255, 0)

            local x0, z0, x1, z1, x2, z2, underLayers = ssSCspec:getCLayers(wheel, width, length, radius, length, length)
            local x, z, widthX, widthZ, heightX, heightZ = Utils.getXZWidthAndHeight(g_currentMission.terrainDetailHeightId, x0, z0, x1, z1, x2, z2)
            ssDebug:drawDensityParallelogram(x, z, widthX, widthZ, heightX, heightZ, 0.25, 255, 0, 0)

            wheel.underTireCLayers = mathRound(underLayers,0)
            wheel.fwdTireCLayers = mathRound(fwdLayers,0)

            if wheel.underTireCLayers ==  3 and soilBulkDensityRef > -0.15 then
                wantedC = 2

            elseif wheel.underTireCLayers == 2 and wheel.fwdTireCLayers == 2 
                and soilBulkDensityRef > 0.0 and soilBulkDensityRef <= 0.15 then
                wantedC = 1

            elseif wheel.underTireCLayers == 1 and wheel.fwdTireCLayers == 1 and soilBulkDensityRef > 0.15 then
                wantedC = 0
            end

            if wantedC ~= 3 then
                local _, _, _ = setDensityParallelogram(g_currentMission.terrainDetailId, x, z, widthX, widthZ, heightX, heightZ, g_currentMission.ploughCounterFirstChannel, g_currentMission.ploughCounterNumChannels, wantedC)
            end

            -- for debug
            --penetrationResistance = 0

            if wheel.groundPressure > penetrationResistance and self:getLastSpeed() > 0 and self.isEntered then
                local dx, dy, dz = getWorldRotation(wheel.node)
                local x0, z0, x1, z1, x2, z2, underLayers = ssSCspec:getCLayers(wheel, math.max(0.1,width-0.1), length, radius, length, length)
                local x, z, widthX, widthZ, heightX, heightZ = Utils.getXZWidthAndHeight(g_currentMission.terrainDetailHeightId, x0, z0, x1, z1, x2, z2)

                setDensityMaskedParallelogram(g_currentMission.terrainDetailId, x, z, widthX, widthZ, heightX, heightZ, 
                    g_currentMission.terrainDetailTypeFirstChannel, g_currentMission.terrainDetailTypeNumChannels, 
                    g_currentMission.terrainDetailId, g_currentMission.terrainDetailTypeFirstChannel, g_currentMission.terrainDetailTypeNumChannels, g_currentMission.ploughValue)
                --angle not working well atm
                setDensityMaskedParallelogram(g_currentMission.terrainDetailId, x, z, widthX, widthZ, heightX, heightZ, 
                    g_currentMission.terrainDetailAngleFirstChannel, g_currentMission.terrainDetailAngleNumChannels, 
                    g_currentMission.terrainDetailId, g_currentMission.terrainDetailTypeFirstChannel, g_currentMission.terrainDetailTypeNumChannels, dx * 180 / math.pi)

            end
        end
    end
end

function ssSCspec:getTireMaxLoad(wheel,inflationPressure)

    local tireLoadIndex = 981 * wheel.ssMaxDeformation + 73
    local inflationFac = 0.56 + 0.002 * inflationPressure

    -- in kN
    return 44 * math.exp(0.0288 * tireLoadIndex) * inflationFac / 100

end

function ssSCspec:getCLayers(wheel, width, length, radius, delta0, delta2)
    local x0, y0, z0
    local x1, y1, z1
    local x2, y2, z2

    if wheel.repr == wheel.driveNode then
        x0, y0, z0 = localToWorld(wheel.node, wheel.positionX + width / 2, wheel.positionY, wheel.positionZ - delta0)
        x1, y1, z1 = localToWorld(wheel.node, wheel.positionX - width / 2, wheel.positionY, wheel.positionZ - delta0)
        x2, y2, z2 = localToWorld(wheel.node, wheel.positionX + width / 2, wheel.positionY, wheel.positionZ + delta2)
    else
        local x, _, z = localToLocal(wheel.driveNode, wheel.repr, 0, 0, 0)
        x0, y0, z0 = localToWorld(wheel.repr, x + width / 2, 0, z - delta0)
        x1, y1, z1 = localToWorld(wheel.repr, x - width / 2, 0, z - delta0)
        x2, y2, z2 = localToWorld(wheel.repr, x + width / 2, 0, z + delta2)
    end

    local x, z, widthX, widthZ, heightX, heightZ = Utils.getXZWidthAndHeight(g_currentMission.terrainDetailId, x0, z0, x1, z1, x2, z2)

    local density, area, _ = getDensityParallelogram(g_currentMission.terrainDetailId, x, z, widthX, widthZ, heightX, heightZ, g_currentMission.ploughCounterFirstChannel, g_currentMission.ploughCounterNumChannels)
    local CLayers = density/area

    return x0, z0, x1, z1, x2, z2, CLayers
end

local function updateInflationPressure(self)
    --TODO: Probably needs an event
    local wantedInflationPressure = ssSCspec.NORMAL_INFLATION_PRESSURE
        
    if self.ssInflationPressure == "Normal" then
        self.ssInflationPressure = "Low"
        wantedInflationPressure = ssSCspec.LOW_INFLATION_PRESSURE
    else
        self.ssInflationPressure = "Normal"
    end

    for _, wheel in pairs(self.wheels) do
        wheel.ssMaxLoad = ssSCspec:getTireMaxLoad(wheel, wantedInflationPressure)
        wheel.maxDeformation = wheel.ssMaxDeformation * ssSCspec.NORMAL_INFLATION_PRESSURE / wantedInflationPressure
    end
end

function ssSCspec:update(dt)
    
    if not g_currentMission:getIsServer() then 
        return 
    end
    --    or not g_seasons.vehicle.ssSCEnabled -- TODO: Make toggle

    if self.lastSpeedReal ~= 0 and not ssWeatherManager:isGroundFrozen() then
        applySC(self)
    end

    for _, wheel in pairs(self.wheels) do
        if wheel.hasGroundContact and not wheel.mrNotAWheel and wheel.load ~= nil and wheel.ssMaxLoad ~= nil then
            -- only exceed rated tire load for low tire pressure
            if wheel.load > wheel.ssMaxLoad and self.ssInflationPressure == "Low" then
                self.ssTireLoadExceed = true
            else
                self.ssTireLoadExceed = false
            end
        end
    end

    if self.isClient and self.ssPlayerInRange == g_currentMission.player and self.ssInRangeOfWorkshop ~= nil then
        local storeItem = StoreItemsUtil.storeItemsByXMLFilename[self.configFileName:lower()]
        local vehicleName = storeItem.brand .. " " .. storeItem.name

        -- Show text for changing inflation pressure
        local storeItemName = storeItem.name
        if string.len(storeItemName) > ssSCspec.MAX_CHARS_TO_DISPLAY then
            storeItemName = ssUtil.trim(string.sub(storeItemName, 1, ssSCspec.MAX_CHARS_TO_DISPLAY - 3)) .. "..."
        end

        if self.ssPlayerInRangeTire ~= nil and self.ssInRangeOfWorkshop ~= nil then 
            g_currentMission:addHelpButtonText(string.format(g_i18n:getText("input_TIRE_PRESSURE"), self.ssInflationPressure), InputBinding.IMPLEMENT_EXTRA2, nil, GS_PRIO_HIGH)
        end

        if InputBinding.hasEvent(InputBinding.IMPLEMENT_EXTRA2) then
            updateInflationPressure(self)
        end
    end

end

-- from ssRepairable
local function isInDistance(self, player, maxDistance, refNode)
    local vx, _, vz = getWorldTranslation(player.rootNode)
    local sx, _, sz = getWorldTranslation(refNode)

    local dist = Utils.vector2Length(vx - sx, vz - sz)

    return dist <= maxDistance
end

-- from ssRepairable
local function getIsPlayerInRange(self, distance, player)
    if self.rootNode ~= 0 and SpecializationUtil.hasSpecialization(Washable, self.specializations) then
        return isInDistance(self, player, distance, self.rootNode), player
    end

    return false, nil
end

function ssSCspec:updateTick(dt)
    if self.isClient and g_currentMission.controlPlayer and g_currentMission.player ~= nil then
        local isPlayerInRangeTire, player = getIsPlayerInRange(self, 4.0, g_currentMission.player)

        if isPlayerInRangeTire then
            self.ssPlayerInRangeTire = player
        else
            self.ssPlayerInRangeTire = nil
        end

    end
end

function ssSCspec:draw()
    local storeItem = StoreItemsUtil.storeItemsByXMLFilename[self.configFileName:lower()]

    if self.isEntered and self.ssTireLoadExceed then
        g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("warning_tireload"), storeItem.name), 2000)
    end

end