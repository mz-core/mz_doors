local Doors = {}
local Loaded = false

local function bool(v)
    return v == true or v == 1 or v == '1'
end

local function getAllowedAce(src)
    if src == 0 then return true, 'console' end
    for _, ace in ipairs(Config.AdminAces or { Config.AdminAce }) do
        if ace and ace ~= '' and IsPlayerAceAllowed(src, ace) then
            return true, ace
        end
    end
    return false, nil
end

local function canAdmin(src)
    local allowed = getAllowedAce(src)
    return allowed == true
end

local function adminAceText()
    return table.concat(Config.AdminAces or { Config.AdminAce }, ', ')
end

local function notify(src, msg, typ)
    TriggerClientEvent('mz_doors:client:notify', src, msg, typ or 'info')
end

local function normalize(row)
    row.id = tonumber(row.id)
    row.model_hash = tonumber(row.model_hash)
    row.x = tonumber(row.x)
    row.y = tonumber(row.y)
    row.z = tonumber(row.z)
    row.rx = tonumber(row.rx) or 0
    row.ry = tonumber(row.ry) or 0
    row.rz = tonumber(row.rz) or 0
    row.heading = tonumber(row.heading) or 0
    row.locked = bool(row.locked)
    row.distance = math.max(0.5, math.min(5.0, tonumber(row.distance) or Config.DefaultDistance))
    row.interaction_x = tonumber(row.interaction_x)
    row.interaction_y = tonumber(row.interaction_y)
    row.interaction_z = tonumber(row.interaction_z)
    row.marker_enabled = row.marker_enabled == nil or bool(row.marker_enabled)
    row.active = row.active == nil or bool(row.active)
    if row.ace_permission == '' then row.ace_permission = nil end
    if row.double_group == '' then row.double_group = nil end
    return row
end

local function loadDoors()
    Doors = {}
    if Config.V2 and Config.V2.RuntimeEnabled == true then
        Loaded = true
        TriggerClientEvent('mz_doors:client:setDoors', -1, Doors)
        print('[mz_doors] runtime legado desativado; mz_doors V2 e a autoridade.')
        return
    end
    MZDoorsDB.ensure()
    local rows = MZDoorsDB.fetchAll()
    for _, row in ipairs(rows) do
        local door = normalize(row)
        Doors[door.id] = door
    end
    Loaded = true
    TriggerClientEvent('mz_doors:client:setDoors', -1, Doors)
    print(('[mz_doors] %s portas carregadas.'):format(#rows))
end

local function canUseDoor(src, door)
    if canAdmin(src) then return true end
    if not door.ace_permission or door.ace_permission == '' then return true end
    return IsPlayerAceAllowed(src, door.ace_permission)
end

local function playerNearDoor(src, door)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    local coords = GetEntityCoords(ped)
    local dx = coords.x - door.x
    local dy = coords.y - door.y
    local dz = coords.z - door.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    return dist <= ((tonumber(door.distance) or Config.DefaultDistance) + 2.5)
end


local function broadcastDoor(door)
    TriggerClientEvent('mz_doors:client:upsertDoor', -1, door)
end

local function removeDoor(id)
    TriggerClientEvent('mz_doors:client:removeDoor', -1, id)
end

CreateThread(function()
    Wait(500)
    loadDoors()
end)

function MZDoorsPlayerActionAllowed(source)
    local ok, allowed, result = pcall(function()
        return exports['mz_core']:CanPlayerPerformAction(source, 'property.use')
    end)
    return ok and allowed == true and type(result) == 'table' and result.allowed == true
end

RegisterNetEvent('mz_doors:server:requestDoors', function()
    local src = source
    if not Loaded then loadDoors() end
    TriggerClientEvent('mz_doors:client:setDoors', src, Doors)
end)

RegisterNetEvent('mz_doors:server:createFromEditor', function(data)
    local src = source
    if Config.V2 and Config.V2.RuntimeEnabled == true then
        notify(src, 'Use o assistente visual V2 para criar portas.', 'error')
        return
    end
    if not canAdmin(src) then
        notify(src, ('Sem permissao ACE. Testados: %s'):format(adminAceText()), 'error')
        return
    end

    if type(data) ~= 'table' or not data.model_hash or not data.coords then
        notify(src, 'Dados invalidos para criar porta.', 'error')
        return
    end

    local door = {
        name = tostring(data.name or ('Porta ' .. tostring(data.model_hash))):sub(1, 100),
        model_hash = tonumber(data.model_hash),
        model_name = data.model_name,
        x = tonumber(data.coords.x),
        y = tonumber(data.coords.y),
        z = tonumber(data.coords.z),
        rx = tonumber(data.rotation and data.rotation.x) or 0,
        ry = tonumber(data.rotation and data.rotation.y) or 0,
        rz = tonumber(data.rotation and data.rotation.z) or 0,
        heading = tonumber(data.heading) or 0,
        locked = data.locked ~= false,
        distance = tonumber(data.distance) or Config.DefaultDistance,
        code = data.code,
        interaction_x = tonumber(data.interaction_coords and data.interaction_coords.x),
        interaction_y = tonumber(data.interaction_coords and data.interaction_coords.y),
        interaction_z = tonumber(data.interaction_coords and data.interaction_coords.z),
        marker_enabled = data.marker_enabled ~= false,
        active = data.active ~= false,
        ace_permission = data.ace_permission or Config.DefaultDoorAce,
        double_group = data.double_group,
        created_by = GetPlayerName(src) or tostring(src)
    }

    if not door.model_hash or not door.x or not door.y or not door.z then
        notify(src, 'Dados incompletos para criar porta.', 'error')
        return
    end
    door.distance = math.max(0.5, math.min(5.0, door.distance))

    local id = MZDoorsDB.insert(door)
    door.id = tonumber(id)
    Doors[door.id] = normalize(door)
    broadcastDoor(Doors[door.id])
    notify(src, ('Porta criada: ID %s. Use /%s list para listar.'):format(door.id, Config.Command), 'success')
end)

RegisterNetEvent('mz_doors:server:toggleNearest', function(id)
    local src = source
    if not MZDoorsPlayerActionAllowed(src) then
        notify(src, 'Acao bloqueada pelo estado do jogador.', 'error')
        return
    end
    id = tonumber(id)
    local door = id and Doors[id]
    if not door or door.active == false then return end

    if not canUseDoor(src, door) then
        notify(src, 'A porta esta trancada.', 'warning')
        return
    end

    if not canAdmin(src) and not playerNearDoor(src, door) then
        notify(src, 'Voce esta longe demais dessa porta.', 'error')
        return
    end

    local newState = not door.locked

    if door.double_group and door.double_group ~= '' then
        for _, d in pairs(Doors) do
            if d.double_group == door.double_group then
                d.locked = newState
                broadcastDoor(d)
            end
        end
        MZDoorsDB.updateLockByGroup(door.double_group, newState)
    else
        door.locked = newState
        MZDoorsDB.updateLock(door.id, door.locked)
        broadcastDoor(door)
    end
    notify(src, newState and 'Porta trancada.' or 'Porta destrancada.', newState and 'info' or 'success')
end)

RegisterNetEvent('mz_doors:server:adminSetLock', function(id, locked)
    local src = source
    if not canAdmin(src) then return end
    id = tonumber(id)
    local door = id and Doors[id]
    if not door then return end
    local state = locked == true
    if door.double_group and door.double_group ~= '' then
        for _, member in pairs(Doors) do
            if member.double_group == door.double_group then
                member.locked = state
                broadcastDoor(member)
            end
        end
        MZDoorsDB.updateLockByGroup(door.double_group, state)
    else
        door.locked = state
        MZDoorsDB.updateLock(id, door.locked)
        broadcastDoor(door)
    end
end)

RegisterNetEvent('mz_doors:server:setInteractionPoint', function(id, coords)
    local src = source
    if not canAdmin(src) then return end
    id = tonumber(id)
    local door = id and Doors[id]
    if not door or type(coords) ~= 'table' then return end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return end

    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local playerCoords = GetEntityCoords(ped)
        local dx, dy, dz = playerCoords.x - x, playerCoords.y - y, playerCoords.z - z
        if math.sqrt(dx * dx + dy * dy + dz * dz) > 25.0 then
            notify(src, 'O ponto de interacao esta longe demais.', 'error')
            return
        end
    end

    door.interaction_x, door.interaction_y, door.interaction_z = x, y, z
    MZDoorsDB.setInteraction(id, { x = x, y = y, z = z })
    broadcastDoor(door)
    notify(src, ('Ponto de interacao da porta #%s atualizado.'):format(id), 'success')
end)

local function chat(src, msg)
    if src == 0 then
        print(msg:gsub('~%a~', ''))
    else
        TriggerClientEvent('chat:addMessage', src, { color = { 80, 200, 255 }, args = { Config.NotifyPrefix, msg } })
    end
end

local function usage(src)
    chat(src, ('Uso: /%s list [pag] | near | goto [id] | lock [id] | unlock [id] | delete [id] | rename [id] [nome] | perm [id] [ace/none] | dist [id] [dist] | group [id] [grupo/none] | reload'):format(Config.Command))
end

RegisterCommand(Config.Command, function(src, args)
    if not canAdmin(src) then
        notify(src, ('Sem permissao ACE. Testados: %s'):format(adminAceText()), 'error')
        return
    end

    local sub = tostring(args[1] or ''):lower()
    if sub == '' or sub == 'help' then return usage(src) end

    if sub == 'reload' then
        loadDoors()
        chat(src, 'Portas recarregadas do banco.')
        return
    end

    if sub == 'list' then
        local ids = {}
        for id in pairs(Doors) do ids[#ids + 1] = id end
        table.sort(ids)
        local page = math.max(1, tonumber(args[2]) or 1)
        local perPage = Config.ListPageSize
        local startIdx = ((page - 1) * perPage) + 1
        local endIdx = math.min(startIdx + perPage - 1, #ids)
        chat(src, ('Lista de portas: pagina %s | total %s'):format(page, #ids))
        for i = startIdx, endIdx do
            local d = Doors[ids[i]]
            chat(src, ('#%s | %s | %s | %.2f %.2f %.2f | perm=%s | dist=%.1f | group=%s'):format(
                d.id, d.locked and 'trancada' or 'aberta', d.name or 'sem nome', d.x, d.y, d.z,
                d.ace_permission or 'livre', d.distance or 2.0, d.double_group or '-'
            ))
        end
        return
    end

    if sub == 'near' then
        TriggerClientEvent('mz_doors:client:printNearest', src)
        return
    end

    local id = tonumber(args[2])
    if not id and sub ~= 'list' then return usage(src) end
    local door = id and Doors[id]
    if not door then
        chat(src, 'Porta nao encontrada.')
        return
    end

    if sub == 'goto' then
        TriggerClientEvent('mz_doors:client:gotoDoor', src, door)
    elseif sub == 'lock' or sub == 'unlock' then
        door.locked = sub == 'lock'
        MZDoorsDB.updateLock(id, door.locked)
        broadcastDoor(door)
        chat(src, ('Porta #%s agora esta %s.'):format(id, door.locked and 'trancada' or 'aberta'))
    elseif sub == 'delete' then
        Doors[id] = nil
        MZDoorsDB.delete(id)
        removeDoor(id)
        chat(src, ('Porta #%s removida.'):format(id))
    elseif sub == 'rename' then
        local name = table.concat(args, ' ', 3)
        if name == '' then return usage(src) end
        door.name = name:sub(1, 100)
        MZDoorsDB.rename(id, door.name)
        broadcastDoor(door)
        chat(src, ('Porta #%s renomeada para %s.'):format(id, door.name))
    elseif sub == 'perm' then
        local ace = table.concat(args, ' ', 3)
        if ace == 'none' then ace = '' end
        door.ace_permission = ace ~= '' and ace or nil
        MZDoorsDB.setPermission(id, ace)
        broadcastDoor(door)
        chat(src, ('Permissao da porta #%s: %s'):format(id, door.ace_permission or 'livre'))
    elseif sub == 'dist' then
        local dist = tonumber(args[3])
        if not dist then return usage(src) end
        dist = math.max(0.5, math.min(5.0, dist))
        door.distance = dist
        MZDoorsDB.setDistance(id, dist)
        broadcastDoor(door)
        chat(src, ('Distancia da porta #%s: %.1f'):format(id, dist))
    elseif sub == 'group' then
        local group = table.concat(args, ' ', 3)
        if group == 'none' then group = '' end
        door.double_group = group ~= '' and group or nil
        MZDoorsDB.setGroup(id, group)
        broadcastDoor(door)
        chat(src, ('Grupo duplo da porta #%s: %s'):format(id, door.double_group or '-'))
    else
        usage(src)
    end
end, false)

exports('GetDoors', function()
    return Doors
end)

exports('IsAdmin', function(src)
    return canAdmin(src)
end)
