local cache = {
    target = nil,
    health = nil,
    maxHealth = nil,
    lastUpdate = 0,
    playerHealth = nil,
    lastHealthCheck = 0
}

local deadEntities = {}

-- Cache des natives les plus utilisées
local PlayerPedId = PlayerPedId
local GetEntityHealth = GetEntityHealth
local GetEntityCoords = GetEntityCoords
local DoesEntityExist = DoesEntityExist
local GetGameTimer = GetGameTimer
local IsPlayerFreeAiming = IsPlayerFreeAiming
local IsPedInMeleeCombat = IsPedInMeleeCombat
local GetEntityForwardVector = GetEntityForwardVector

function getMeleeFocusTarget(ped)
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    
    -- Convertir le heading en radians et calculer le vecteur de direction
    local headingRad = math.rad(heading)
    local forwardX = -math.sin(headingRad)
    local forwardY = math.cos(headingRad)
    
    -- Point final du raycast (3 unités devant le joueur)
    local endCoords = vec3(
        coords.x + forwardX * 3.0,
        coords.y + forwardY * 3.0,
        coords.z
    )
    
    -- Lancer un raycast devant le joueur
    local ray = StartShapeTestRay(
        coords.x, coords.y, coords.z + 0.5,
        endCoords.x, endCoords.y, endCoords.z + 0.5,
        -1, ped, 0
    )
    
    local _, hit, hitCoords, _, hitEntity = GetShapeTestResult(ray)
    
    if hit and DoesEntityExist(hitEntity) and IsEntityAPed(hitEntity) and not IsPedAPlayer(hitEntity) then
        return hitEntity
    end
    
    -- Si le raycast ne trouve rien, chercher le PED le plus proche devant nous
    local closestPed = nil
    local closestDist = 3.0
    
    for target in pairs(GetGamePool('CPed')) do
        if DoesEntityExist(target) and not IsPedAPlayer(target) and not IsPedDeadOrDying(target) then
            local targetCoords = GetEntityCoords(target)
            local dist = #(coords - targetCoords)
            
            if dist < closestDist then
                -- Vérifier si le PED est devant nous
                local dx = targetCoords.x - coords.x
                local dy = targetCoords.y - coords.y
                
                -- Calculer l'angle entre la direction du joueur et la direction vers la cible
                local targetAngle = math.deg(math.atan2(dx, dy))
                local angleDiff = math.abs((targetAngle - heading + 180) % 360 - 180)
                
                if angleDiff < 60 then -- 60 degrés de chaque côté
                    closestDist = dist
                    closestPed = target
                end
            end
        end
    end
    
    return closestPed
end

function getScreenCoords(entity)
    if not DoesEntityExist(entity) then return nil, nil end
    
    local coords = GetEntityCoords(entity)
    local screenX, screenY = GetActiveScreenResolution()
    local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z + 1.0, screenX, screenY)
    
    if onScreen then
        return math.floor(x * screenX), math.floor(y * screenY)
    end
    return nil, nil
end

function cleanupTarget()
    if cache.target then
        SendNUIMessage({
            type = "hideHealthBar",
            entityId = cache.target
        })
        cache.target = nil
        cache.health = nil
        cache.maxHealth = nil
    end
end

function updateTarget(target)
    if not target or not DoesEntityExist(target) then 
        cleanupTarget()
        return 
    end

    if IsPedDeadOrDying(target) then
        if not deadEntities[target] then
            local x, y = getScreenCoords(target)
            if x and y then
                deadEntities[target] = true
                if Config.XP.enabled then
                    SendNUIMessage({
                        type = "showXP",
                        amount = IsPedHuman(target) and tostring(Config.XP.human) or tostring(Config.XP.animal),
                        x = x,
                        y = y
                    })
                else
                    print("Le système d'XP est désactivé.")
                end
            end
        end
        cleanupTarget()
        return
    end

    local currentTime = GetGameTimer()
    if currentTime - cache.lastUpdate < 50 then return end
    cache.lastUpdate = currentTime

    local health = GetEntityHealth(target) - 100
    local x, y = getScreenCoords(target)
    
    if not x then 
        cleanupTarget()
        return 
    end

    if target ~= cache.target then
        cleanupTarget()
        cache.target = target
        cache.maxHealth = GetPedMaxHealth(target) - 100
    end

    SendNUIMessage({
        type = "updateHealthBar",
        entityId = target,
        currentHealth = health,
        maxHealth = cache.maxHealth,
        previousHealth = cache.health,
        x = x, y = y
    })
    cache.health = health
end

CreateThread(function()
    while true do
        local sleep = 250
        local ped = PlayerPedId()
        local target = nil

        -- Vérification de la santé du joueur (toutes les 100ms)
        local currentTime = GetGameTimer()
        if currentTime - cache.lastHealthCheck >= 100 then
            cache.lastHealthCheck = currentTime
            local health = GetEntityHealth(ped) - 100
            
            if health ~= cache.playerHealth and cache.playerHealth and health < cache.playerHealth then
                local x, y = getScreenCoords(ped)
                if x then
                    SendNUIMessage({
                        type = "showPlayerDamage",
                        damage = cache.playerHealth - health,
                        x = x, y = y
                    })
                end
            end
            cache.playerHealth = health
        end

        -- Détection de cible différente selon le mode
        if IsPedInMeleeCombat(ped) then
            -- Mode corps à corps : basé sur la direction du joueur
            sleep = 0
            target = getMeleeFocusTarget(ped)
        elseif IsPlayerFreeAiming(PlayerId()) then
            -- Mode visée : nécessite un viseur précis
            sleep = 0
            local bool, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
            if bool and IsEntityAPed(entity) and not IsPedAPlayer(entity) then
                target = entity
            end
        end

        -- Mise à jour ou nettoyage de la cible
        if target then
            updateTarget(target)
        elseif cache.target then
            cleanupTarget()
        end

        Wait(sleep)
    end
end)
