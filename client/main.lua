local Doors = {}
local Registered = {}
local RegisteredInteractions = {}

local function notify(msg, typ)
    msg = tostring(msg or '')
    typ = typ or 'info'
    print(('[mz_doors][notify:%s] %s'):format(tostring(typ), msg))

    if Config.UseMzNotify == true and GetResourceState('mz_notify') == 'started' then
        local notifyType = typ == 'inform' and 'info' or (typ == 'warn' and 'warning' or typ)
        local ok, result = pcall(function()
            return exports['mz_notify']:Notify({
                type = notifyType,
                title = Config.NotifyPrefix,
                message = msg,
                duration = 4000
            })
        end)
        if ok and result ~= false then return true end
        print(('[mz_doors] mz_notify falhou: %s'):format(tostring(result)))
    end

    if Config.UseMzMenuNotify == true and GetResourceState('mz_menu') == 'started' then
        local menuType = typ == 'info' and 'inform' or (typ == 'warn' and 'warning' or typ)
        local ok, result = pcall(function()
            return exports['mz_menu']:Notify(msg, menuType, 4000, { title = Config.NotifyPrefix })
        end)
        if ok and result ~= false then return true end
        print(('[mz_doors] mz_menu Notify falhou: %s'):format(tostring(result)))
    end

    if Config.UseChatNotify ~= false and GetResourceState('chat') == 'started' then
        TriggerEvent('chat:addMessage', {
            color = typ == 'error' and { 255, 80, 80 } or { 80, 200, 255 },
            args = { Config.NotifyPrefix, msg }
        })
    end

    if Config.UseNativeNotify ~= false then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(('%s: %s'):format(Config.NotifyPrefix, msg))
        EndTextCommandThefeedPostTicker(false, false)
    end
    return false
end

RegisterNetEvent('mz_doors:client:notify', function(msg, typ)
    notify(msg, typ)
end)

local function doorHash(id)
    return GetHashKey(('mz_world_door_%s'):format(id))
end

local function toVec(door)
    return vector3(tonumber(door.x) or 0.0, tonumber(door.y) or 0.0, tonumber(door.z) or 0.0)
end

local function registerDoor(door)
    if not door or not door.id then return end
    local hash = doorHash(door.id)

    if door.active == false then
        if Registered[door.id] then RemoveDoorFromSystem(hash) end
        Registered[door.id] = nil
        return
    end

    if not Registered[door.id] then
        AddDoorToSystem(hash, tonumber(door.model_hash), tonumber(door.x), tonumber(door.y), tonumber(door.z), false, false, false)
        Registered[door.id] = true
    end

    DoorSystemSetDoorState(hash, door.locked and 1 or 0, false, true)
    DoorSystemSetAutomaticRate(hash, 10.0, false, false)
end

local function registerAll()
    for _, door in pairs(Doors) do
        registerDoor(door)
    end
end

RegisterNetEvent('mz_doors:client:setDoors', function(data)
    for id in pairs(Registered) do RemoveDoorFromSystem(doorHash(id)) end
    Doors = data or {}
    Registered = {}
    Wait(100)
    registerAll()
    TriggerEvent('mz_doors:client:refreshInteractions')
end)

RegisterNetEvent('mz_doors:client:upsertDoor', function(door)
    if not door or not door.id then return end
    Doors[door.id] = door
    registerDoor(door)
    TriggerEvent('mz_doors:client:refreshInteractions')
end)

RegisterNetEvent('mz_doors:client:removeDoor', function(id)
    id = tonumber(id)
    Doors[id] = nil
    local hash = doorHash(id)
    RemoveDoorFromSystem(hash)
    Registered[id] = nil
    TriggerEvent('mz_doors:client:refreshInteractions')
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == GetCurrentResourceName() then
        Wait(1000)
        TriggerServerEvent('mz_doors:server:requestDoors')
    end
end)

local function drawText3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 230)
    SetTextCentre(true)
    SetTextDropshadow(1, 0, 0, 0, 180)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function nearestDoor(maxDistance)
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local nearest, nearestDist = nil, maxDistance or Config.DrawDistance

    for _, door in pairs(Doors) do
        if door.active ~= false then
        local coords = toVec(door)
        local dist = #(pcoords - coords)
        local useDist = tonumber(door.distance) or Config.DefaultDistance
        if dist <= math.max(useDist, nearestDist) and dist <= nearestDist then
            nearest = door
            nearestDist = dist
        end
        end
    end

    return nearest, nearestDist
end

local function canUseMzInteract()
    return Config.UseMzInteract == true and GetResourceState('mz_interact') == 'started'
end

local function logicalGroups()
    local groups = {}
    for _, door in pairs(Doors) do
        if door.active ~= false then
            local key = door.double_group and door.double_group ~= ''
                and ('group:' .. tostring(door.double_group))
                or ('door:' .. tostring(door.id))
            local group = groups[key]
            if not group then
                group = { key = key, members = {} }
                groups[key] = group
            end
            group.members[#group.members + 1] = door
        end
    end

    for _, group in pairs(groups) do
        table.sort(group.members, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
        group.door = group.members[1]
        local explicitX, explicitY, explicitZ, explicitCount = 0.0, 0.0, 0.0, 0
        local x, y, z = 0.0, 0.0, 0.0
        for _, member in ipairs(group.members) do
            if member.interaction_x and member.interaction_y and member.interaction_z then
                explicitX = explicitX + tonumber(member.interaction_x)
                explicitY = explicitY + tonumber(member.interaction_y)
                explicitZ = explicitZ + tonumber(member.interaction_z)
                explicitCount = explicitCount + 1
            end
            x = x + (tonumber(member.x) or 0.0)
            y = y + (tonumber(member.y) or 0.0)
            z = z + (tonumber(member.z) or 0.0)
        end
        local count = math.max(1, #group.members)
        if explicitCount > 0 then
            group.coords = vector3(
                explicitX / explicitCount,
                explicitY / explicitCount,
                explicitZ / explicitCount
            )
        else
            group.coords = vector3(
                x / count,
                y / count,
                (z / count) + (tonumber(Config.InteractionOffsetZ) or 0.75)
            )
        end
    end
    return groups
end

local function clearInteractions()
    if GetResourceState('mz_interact') == 'started' then
        for pointId in pairs(RegisteredInteractions) do
            pcall(function() exports['mz_interact']:RemovePoint(pointId) end)
        end
    end
    RegisteredInteractions = {}
end

local function refreshInteractions()
    clearInteractions()
    if not canUseMzInteract() or Config.ShowDoorText == false then return false end

    for key, group in pairs(logicalGroups()) do
        local door = group.door
        local pointId = 'mz_doors:' .. key
        local action = door.locked and 'Destrancar' or 'Trancar'
        local ok, added = pcall(function()
            return exports['mz_interact']:AddPoint({
                id = pointId,
                coords = group.coords,
                drawDistance = tonumber(Config.InteractionDrawDistance) or Config.DrawDistance,
                interactDistance = tonumber(door.distance) or Config.DefaultDistance,
                priority = 20,
                marker = door.marker_enabled == false and false or Config.InteractionMarker,
                blip = { enabled = false },
                text = {
                    enabled = true,
                    label = ('~b~%s~s~~n~~g~[E]~s~ %s'):format(
                        tostring(door.name or ('Porta #' .. door.id)), action
                    ),
                    offsetZ = 0.2,
                    scale = 0.31,
                    background = { r = 8, g = 12, b = 18, a = 115 }
                },
                event = {
                    type = 'client',
                    name = 'mz_doors:client:toggleByInteract',
                    args = { door.id }
                }
            })
        end)
        if ok and added == true then RegisteredInteractions[pointId] = true end
    end
    return true
end

RegisterNetEvent('mz_doors:client:refreshInteractions', refreshInteractions)

RegisterNetEvent('mz_doors:client:toggleByInteract', function(id)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        notify('Saia do veiculo para interagir com a porta.', 'error')
        return
    end
    TriggerServerEvent('mz_doors:server:toggleNearest', tonumber(id))
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'mz_interact' then
        Wait(500)
        refreshInteractions()
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == 'mz_interact' then RegisteredInteractions = {} end
end)

RegisterCommand(Config.ToggleCommand, function()
    if Config.V2 and Config.V2.RuntimeEnabled == true then
        TriggerEvent('mz_doors:v2:client:toggleNearest')
        return
    end
    local door = nearestDoor(Config.DrawDistance)
    if not door then
        notify('Nenhuma porta proxima.', 'error')
        return
    end
    TriggerServerEvent('mz_doors:server:toggleNearest', door.id)
end, false)

CreateThread(function()
    while true do
        local sleep = 750
        if Config.ShowDoorText and not canUseMzInteract() then
            local ped = PlayerPedId()
            local pcoords = GetEntityCoords(ped)

            for _, group in pairs(logicalGroups()) do
                local door = group.door
                local coords = group.coords
                local dist = #(pcoords - coords)
                local drawDist = tonumber(door.distance) or Config.DefaultDistance

                if dist <= math.max(drawDist, 2.0) then
                    sleep = 0
                    local text = ('~b~%s~s~\n%s'):format(door.name or ('Porta #' .. door.id), door.locked and '~r~Trancada~s~' or '~g~Aberta~s~')
                    if dist <= drawDist then
                        text = text .. '\n~g~E~s~ Alternar'
                        if IsControlJustPressed(0, Config.ToggleKey) then
                            TriggerServerEvent('mz_doors:server:toggleNearest', door.id)
                            Wait(350)
                        end
                    end
                    drawText3D(coords, text)
                end
            end
        end
        Wait(sleep)
    end
end)

RegisterNetEvent('mz_doors:client:gotoDoor', function(door)
    if not door then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, tonumber(door.x), tonumber(door.y), tonumber(door.z) + 0.8, false, false, false, false)
end)

RegisterNetEvent('mz_doors:client:printNearest', function()
    local door, dist = nearestDoor(Config.DrawDistance)
    if not door then
        notify('Nenhuma porta proxima.', 'error')
        return
    end

    TriggerEvent('chat:addMessage', {
        color = { 80, 200, 255 },
        multiline = true,
        args = { Config.NotifyPrefix, ('Mais proxima: #%s | %s | %.2fm | %s | %.2f %.2f %.2f'):format(
            door.id, door.name or 'sem nome', dist or 0.0, door.locked and 'trancada' or 'aberta', door.x, door.y, door.z
        ) }
    })
end)
