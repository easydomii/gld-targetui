local previousEntity = nil
local previousHealth = {}
local deadEntities = {}
local deadEntitiesQueue = {}
local deadEntitiesTimeout = {}
local meleeTarget = nil
local playerPreviousHealth = nil

function Round(value, numDecimalPlaces)
    if numDecimalPlaces then
        local power = 10^numDecimalPlaces
        return math.floor((value * power) + 0.5) / (power)
    else
        return math.floor(value + 0.5)
    end
end

function getEntityScreenCoordsUsingCenter(entity)
    local entityCenter = GetEntityCoords(entity)
    local screenX, screenY = GetActiveScreenResolution()
    local onScreen, x, y = GetScreenCoordFromWorldCoord(entityCenter.x, entityCenter.y, entityCenter.z + 1.0, screenX, screenY)
    
    if onScreen then
        x = math.floor(x * screenX)
        y = math.floor(y * screenY)
        return x, y
    end
    return nil, nil
end

function checkPlayerDamage()
    local ped = PlayerPedId()
    local currentHealth = GetEntityHealth(ped) - 100

    if not playerPreviousHealth then
        playerPreviousHealth = currentHealth
        return
    end

    if currentHealth < playerPreviousHealth then
        local damage = playerPreviousHealth - currentHealth
        local coords = GetEntityCoords(ped)
        local screenX, screenY = GetActiveScreenResolution()
        local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z + 1.0, screenX, screenY)
        
        if onScreen then
            SendNUIMessage({
                type = "showPlayerDamage",
                damage = damage,
                x = x * screenX,
                y = y * screenY
            })
        end
    end
    
    playerPreviousHealth = currentHealth
end

function updateHealthBarOnClient(entity, currentHealth, maxHealth, x, y, previousHealth)
    SendNUIMessage({
        type = "updateHealthBar",
        entityId = entity,
        currentHealth = currentHealth,
        maxHealth = maxHealth,
        previousHealth = previousHealth or currentHealth,
        x = x,
        y = y
    })
end

function showXPGain(entity, x, y)
    if not Config.XP.enabled then return end
    
    local xpAmount = IsPedHuman(entity) and Config.XP.human or Config.XP.animal
    SendNUIMessage({
        type = "showXP",
        entityId = entity,
        x = x,
        y = y,
        amount = tostring(xpAmount)
    })
end

function hideHealthBarOnClient(entity)
    SendNUIMessage({
        type = "hideHealthBar",
        entityId = entity
    })
end

function isEntityInRange(entity, range)
    if not DoesEntityExist(entity) then return false end
    
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local entityCoords = GetEntityCoords(entity)
    local distance = #(playerCoords - entityCoords)
    
    return distance <= range
end

function checkDeadEntity(entity)
    if not entity or not DoesEntityExist(entity) then return end
    if not IsEntityAPed(entity) or IsPedAPlayer(entity) then return end
    
    if IsPedDeadOrDying(entity) and not deadEntities[entity] then
        local x, y = getEntityScreenCoordsUsingCenter(entity)
        if x and y then
            deadEntities[entity] = true
            showXPGain(entity, x, y)
        else
            -- Si on ne peut pas afficher l'XP maintenant, on met l'entité en file d'attente
            if not deadEntitiesQueue[entity] then
                deadEntitiesQueue[entity] = true
                deadEntitiesTimeout[entity] = GetGameTimer() + 5000 -- 5 secondes de timeout
            end
        end
    end
end

function processDeadEntitiesQueue()
    local currentTime = GetGameTimer()
    
    for entity, _ in pairs(deadEntitiesQueue) do
        if DoesEntityExist(entity) then
            local x, y = getEntityScreenCoordsUsingCenter(entity)
            if x and y then
                deadEntities[entity] = true
                showXPGain(entity, x, y)
                deadEntitiesQueue[entity] = nil
                deadEntitiesTimeout[entity] = nil
            elseif currentTime > deadEntitiesTimeout[entity] then
                -- Si on dépasse le timeout, on abandonne
                deadEntitiesQueue[entity] = nil
                deadEntitiesTimeout[entity] = nil
            end
        else
            deadEntitiesQueue[entity] = nil
            deadEntitiesTimeout[entity] = nil
        end
    end
end

function processEntity(entity)
    if not entity or not DoesEntityExist(entity) then return false end
    if not IsEntityAPed(entity) or IsPedAPlayer(entity) then return false end

    -- Vérifier d'abord si l'entité est morte pour l'XP
    if IsPedDeadOrDying(entity) then
        checkDeadEntity(entity)
        return false
    end

    local x, y = getEntityScreenCoordsUsingCenter(entity)
    if x and y then
        local health = GetEntityHealth(entity) - 100
        local maxHealth = GetPedMaxHealth(entity) - 100
        local percentage = Round((health / maxHealth) * 100)
                
        updateHealthBarOnClient(entity, health, maxHealth, x, y, previousHealth[entity])
        previousHealth[entity] = health
        return true
    end

    return false
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local currentTarget = nil
        local isTargetValid = false

        -- Vérification des dégâts du joueur
        checkPlayerDamage()

        -- Traitement de la file d'attente des XP
        processDeadEntitiesQueue()

        -- Vérification de la visée (sans limite de distance)
        if IsPlayerFreeAiming(PlayerId()) then
            local bool, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
            if bool then
                currentTarget = entity
                isTargetValid = true
                meleeTarget = nil
            end
        end

        -- Vérification du corps à corps (avec limite de distance)
        if not currentTarget and IsPedInMeleeCombat(ped) then
            if meleeTarget and DoesEntityExist(meleeTarget) and isEntityInRange(meleeTarget, 3.0) then
                currentTarget = meleeTarget
                isTargetValid = true
            else
                local playerCoords = GetEntityCoords(ped)
                local nearbyPeds = GetGamePool('CPed')
                local closestDistance = 3.0
                
                for _, nearbyPed in ipairs(nearbyPeds) do
                    if DoesEntityExist(nearbyPed) and not IsPedAPlayer(nearbyPed) 
                    and not IsPedDeadOrDying(nearbyPed) and isEntityInRange(nearbyPed, closestDistance) then
                        local pedCoords = GetEntityCoords(nearbyPed)
                        local distance = #(playerCoords - pedCoords)
                        
                        if distance < closestDistance then
                            currentTarget = nearbyPed
                            meleeTarget = nearbyPed
                            isTargetValid = true
                            closestDistance = distance
                        end
                    end
                end
            end
        end

        -- Gestion de l'affichage et vérification des entités mortes
        if not isTargetValid and previousEntity then
            hideHealthBarOnClient(previousEntity)
            previousHealth[previousEntity] = nil
            previousEntity = nil
            meleeTarget = nil
        end

        if currentTarget then
            if isTargetValid then
                if processEntity(currentTarget) then
                    previousEntity = currentTarget
                end
            else
                checkDeadEntity(currentTarget)
            end
        end

        Wait(0)
    end
end)