local targetInfo = {
    entity = nil,
    health = nil,
    maxHealth = nil,
    lastUpdate = 0
}
local deadEntities = {}
local playerHealth = nil
local lastHealthCheck = 0

-- Cache des natives pour de meilleures performances
local GetEntityHealth = GetEntityHealth
local IsPedDeadOrDying = IsPedDeadOrDying
local DoesEntityExist = DoesEntityExist
local PlayerPedId = PlayerPedId
local GetEntityCoords = GetEntityCoords
local GetGameTimer = GetGameTimer
local pairs = pairs
local Wait = Wait

function getEntityScreenCoordsUsingCenter(entity)
    if not DoesEntityExist(entity) then return nil, nil end
    local coords = GetEntityCoords(entity)
    local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z + 1.0)
    return onScreen and x * GetActiveScreenResolution(), y * GetActiveScreenResolution() or nil, nil
end

function cleanupTarget()
    if targetInfo.entity then
        SendNUIMessage({
            type = "hideHealthBar",
            entityId = targetInfo.entity
        })
        targetInfo.entity = nil
        targetInfo.health = nil
        targetInfo.maxHealth = nil
        targetInfo.lastUpdate = 0
    end
end

function getClosestTarget(coords, maxDistance)
    local closestPed, closestDistance = nil, maxDistance
    local maxDistanceSquared = maxDistance * maxDistance

    for ped in pairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped) then
            local pedCoords = GetEntityCoords(ped)
            local distanceSquared = #(coords - pedCoords)
            
            if distanceSquared < maxDistanceSquared and distanceSquared < closestDistance then
                closestDistance = distanceSquared
                closestPed = ped
            end
        end
    end

    return closestPed
end

function handleTarget(target)
    if not target or not DoesEntityExist(target) then
        cleanupTarget()
        return false
    end

    -- Vérifier si le PED est mort
    if IsPedDeadOrDying(target) then
        if not deadEntities[target] then
            local x, y = getEntityScreenCoordsUsingCenter(target)
            if x and y then
                deadEntities[target] = true
                SendNUIMessage({
                    type = "showXP",
                    amount = IsPedHuman(target) and "45" or "10",
                    x = x,
                    y = y
                })
            end
        end
        cleanupTarget()
        return false
    end

    local currentTime = GetGameTimer()
    if currentTime - targetInfo.lastUpdate < 50 then return true end
    targetInfo.lastUpdate = currentTime

    -- Mise à jour des infos de la cible si nouvelle
    if target ~= targetInfo.entity then
        targetInfo.entity = target
        targetInfo.maxHealth = GetPedMaxHealth(target) - 100
    end

    -- Obtention des coordonnées et santé actuelles
    local health = GetEntityHealth(target) - 100
    local x, y = getEntityScreenCoordsUsingCenter(target)
    
    -- Si on ne peut pas obtenir les coordonnées écran ou que la santé a changé
    if not x or not y then
        cleanupTarget()
        return false
    end

    -- Mise à jour de la barre de vie uniquement si nécessaire
    if health ~= targetInfo.health then
        SendNUIMessage({
            type = "updateHealthBar",
            entityId = target,
            currentHealth = health,
            maxHealth = targetInfo.maxHealth,
            previousHealth = targetInfo.health,
            x = x,
            y = y
        })
        targetInfo.health = health
    else
        -- Mettre à jour la position même si la santé n'a pas changé
        SendNUIMessage({
            type = "updateHealthBar",
            entityId = target,
            currentHealth = health,
            maxHealth = targetInfo.maxHealth,
            previousHealth = health,
            x = x,
            y = y
        })
    end

    return true
end

function checkPlayerHealth()
    local currentTime = GetGameTimer()
    if currentTime - lastHealthCheck < 100 then return end
    lastHealthCheck = currentTime

    local currentHealth = GetEntityHealth(PlayerPedId()) - 100
    if currentHealth ~= playerHealth then
        if playerHealth and currentHealth < playerHealth then
            local x, y = getEntityScreenCoordsUsingCenter(PlayerPedId())
            if x and y then
                SendNUIMessage({
                    type = "showPlayerDamage",
                    damage = playerHealth - currentHealth,
                    x = x,
                    y = y
                })
            end
        end
        playerHealth = currentHealth
    end
end

function getEntityScreenCoordsUsingCenter(entity)
    if not DoesEntityExist(entity) then return nil, nil end
    
    local coords = GetEntityCoords(entity)
    local screenX, screenY = GetActiveScreenResolution()
    local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z + 1.0, screenX, screenY)
    
    if onScreen then
        -- Les coordonnées retournées sont entre 0 et 1, il faut les multiplier par la résolution
        x = x * screenX
        y = y * screenY
        return math.floor(x), math.floor(y)
    end
    
    return nil, nil
end

CreateThread(function()
    while true do
        local sleep = 250
        local isActive = false
        local ped = PlayerPedId()

        checkPlayerHealth()

        if IsPlayerFreeAiming(PlayerId()) or IsPedInMeleeCombat(ped) then
            isActive = true
            sleep = 0
            local target = nil

            if IsPlayerFreeAiming(PlayerId()) then
                local bool, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
                if bool and IsEntityAPed(entity) and not IsPedAPlayer(entity) then
                    target = entity
                end
            else
                target = getClosestTarget(GetEntityCoords(ped), 3.0)
            end

            if target then
                handleTarget(target)
            end
        end

        if not isActive and targetInfo.entity then
            cleanupTarget()
        end

        Wait(sleep)
    end
end)
