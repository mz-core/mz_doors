local V2Doors = {}
local RegisteredLeaves = {}
local RegisteredPoints = {}

local function leafDoorHash(leafId)
    return GetHashKey(('mz_v2_door_leaf_%s'):format(tostring(leafId)))
end

local function removeLeaf(leafId)
    local hash = leafDoorHash(leafId)
    if RegisteredLeaves[leafId] then RemoveDoorFromSystem(hash) end
    RegisteredLeaves[leafId] = nil
end

local function registerLeaf(door, leaf)
    if not leaf or not leaf.id or not leaf.model_hash then return end
    local hash = leafDoorHash(leaf.id)
    if not RegisteredLeaves[leaf.id] then
        AddDoorToSystem(
            hash, tonumber(leaf.model_hash),
            tonumber(leaf.x), tonumber(leaf.y), tonumber(leaf.z),
            false, false, false
        )
        RegisteredLeaves[leaf.id] = door.id
    end
    DoorSystemSetDoorState(hash, door.locked and 1 or 0, false, true)
    DoorSystemSetAutomaticRate(hash, 10.0, false, false)
end

local function removePoint(pointId)
    if GetResourceState('mz_interact') == 'started' then
        pcall(function() exports['mz_interact']:RemovePoint(pointId) end)
    end
    RegisteredPoints[pointId] = nil
end

local function registerPoint(door)
    if Config.UseMzInteract ~= true or GetResourceState('mz_interact') ~= 'started' then return end
    local pointId = 'mz_doors:v2:' .. tostring(door.code)
    removePoint(pointId)
    local action = door.locked and 'Destrancar' or 'Trancar'
    local ok, added = pcall(function()
        return exports['mz_interact']:AddPoint({
            id = pointId,
            coords = vector3(door.interaction_x, door.interaction_y, door.interaction_z),
            drawDistance = door.draw_distance,
            interactDistance = door.interaction_distance,
            priority = 30,
            marker = door.marker_enabled == false and false or Config.InteractionMarker,
            blip = { enabled = false },
            text = {
                enabled = true,
                label = door.show_label_3d == false
                    and ('~g~[E]~s~ %s   ~y~[G]~s~ Bater'):format(action)
                    or ('~b~%s~s~~n~~g~[E]~s~ %s   ~y~[G]~s~ Bater'):format(
                        tostring(door.label), action
                    ),
                offsetZ = 0.2,
                scale = 0.31,
                background = { r = 8, g = 12, b = 18, a = 115 }
            },
            actions = {
                {
                    id = 'toggle',
                    key = Config.ToggleKey,
                    event = {
                        type = 'client',
                        name = 'mz_doors:v2:client:toggle',
                        args = { door.id }
                    }
                },
                {
                    id = 'knock',
                    key = 47,
                    event = {
                        type = 'client',
                        name = 'mz_doors:v2:client:knock',
                        args = { door.id }
                    }
                }
            }
        })
    end)
    if ok and added == true then RegisteredPoints[pointId] = true end
end

local function clearAll()
    for leafId in pairs(RegisteredLeaves) do removeLeaf(leafId) end
    for pointId in pairs(RegisteredPoints) do removePoint(pointId) end
    V2Doors = {}
end

local function applyDoor(door)
    if not door or not door.id or door.active == false then return end
    V2Doors[door.id] = door
    for _, leaf in ipairs(door.leaves or {}) do registerLeaf(door, leaf) end
    registerPoint(door)
end

RegisterNetEvent('mz_doors:v2:client:setDoors', function(definitions)
    clearAll()
    for _, door in pairs(type(definitions) == 'table' and definitions or {}) do applyDoor(door) end
end)

RegisterNetEvent('mz_doors:v2:client:upsertDoor', function(door)
    local previous = door and V2Doors[door.id]
    if previous then
        local nextLeafIds = {}
        for _, leaf in ipairs(door.leaves or {}) do nextLeafIds[leaf.id] = true end
        for _, leaf in ipairs(previous.leaves or {}) do
            if not nextLeafIds[leaf.id] then removeLeaf(leaf.id) end
        end
    end
    applyDoor(door)
end)

RegisterNetEvent('mz_doors:v2:client:removeDoor', function(id)
    id = tonumber(id)
    local door = id and V2Doors[id]
    if not door then return end
    for _, leaf in ipairs(door.leaves or {}) do removeLeaf(leaf.id) end
    removePoint('mz_doors:v2:' .. tostring(door.code))
    V2Doors[id] = nil
end)

RegisterNetEvent('mz_doors:v2:client:toggle', function(id)
    if not MZDoorsCanPerformPropertyAction() then
        TriggerEvent('mz_doors:client:notify', 'Acao bloqueada pelo estado do jogador.', 'error')
        return
    end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        TriggerEvent('mz_doors:client:notify', 'Saia do veiculo para interagir com a porta.', 'error')
        return
    end
    TriggerServerEvent('mz_doors:v2:server:toggle', tonumber(id))
end)

RegisterNetEvent('mz_doors:v2:client:knock', function(id)
    if not MZDoorsCanPerformPropertyAction() then
        TriggerEvent('mz_doors:client:notify', 'Acao bloqueada pelo estado do jogador.', 'error')
        return
    end
    TriggerServerEvent('mz_doors:v2:server:knock', tonumber(id))
end)

RegisterNetEvent('mz_doors:v2:client:playKnock', function(data)
    if type(data) ~= 'table' then return end
    local coords = vector3(tonumber(data.x) or 0.0, tonumber(data.y) or 0.0, tonumber(data.z) or 0.0)
    if #(GetEntityCoords(PlayerPedId()) - coords) > 15.0 then return end
    PlaySoundFromCoord(-1, 'DOOR_BUZZ', coords.x, coords.y, coords.z, 'MP_PLAYER_APARTMENT', false, 5.0, false)
end)

local function nearestV2Door(maxDistance)
    local coords = GetEntityCoords(PlayerPedId())
    local closest, closestDistance
    for _, door in pairs(V2Doors) do
        local distance = #(coords - vector3(door.interaction_x, door.interaction_y, door.interaction_z))
        if distance <= (maxDistance or Config.DrawDistance) and (not closestDistance or distance < closestDistance) then
            closest, closestDistance = door, distance
        end
    end
    return closest, closestDistance
end

AddEventHandler('mz_doors:v2:client:toggleNearest', function()
    if not MZDoorsCanPerformPropertyAction() then
        TriggerEvent('mz_doors:client:notify', 'Acao bloqueada pelo estado do jogador.', 'error')
        return
    end
    local door = nearestV2Door(Config.DrawDistance)
    if not door then
        TriggerEvent('mz_doors:client:notify', 'Nenhuma porta proxima.', 'error')
        return
    end
    TriggerServerEvent('mz_doors:v2:server:toggle', door.id)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        Wait(1000)
        TriggerServerEvent('mz_doors:v2:server:requestDoors')
    elseif resourceName == 'mz_interact' then
        Wait(500)
        for _, door in pairs(V2Doors) do registerPoint(door) end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == 'mz_interact' then RegisteredPoints = {} end
end)
