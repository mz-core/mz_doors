local DefinitionsById = {}
local DefinitionsByCode = {}
local GroupsById = {}
local GroupsByCode = {}
local Loaded = false
local AutoLockTokens = {}
local LastKnockAt = {}

local function asBool(value)
    return value == true or value == 1 or value == '1'
end

local function decodePolicy(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return { type = 'public' } end
    local ok, decoded = pcall(json.decode, value)
    return ok and type(decoded) == 'table' and decoded or { type = 'invalid' }
end

local function canonicalizeCreatePolicy(policy)
    local policyType = MZDoorsV2Logic.Trim(policy and policy.type, 24):lower()
    if policyType == 'public' then return { type = 'public' } end

    if policyType == 'staff' then
        return {
            type = 'staff',
            permission = MZDoorsV2Logic.Trim(policy.permission, 128)
        }
    end

    if policyType == 'organization' then
        if GetResourceState('mz_core') ~= 'started' then
            return nil, 'organization_repository_unavailable'
        end

        local orgCode = MZDoorsV2Logic.Trim(policy.code, 64):lower()
        local callOk, organization = pcall(function()
            return exports['mz_core']:GetOrgByCode(orgCode)
        end)
        if not callOk then return nil, 'organization_repository_unavailable' end
        if type(organization) ~= 'table' then return nil, 'organization_not_found' end
        if organization.active ~= true then return nil, 'organization_inactive' end

        local permission = MZDoorsV2Logic.Trim(policy.permission, 128)
        return {
            type = 'organization',
            code = MZDoorsV2Logic.Trim(organization.code, 64):lower(),
            minGrade = math.floor(tonumber(policy.minGrade) or 0),
            permission = permission ~= '' and permission or nil
        }
    end

    return policy
end

local function normalize(row)
    row.id = tonumber(row.id)
    row.locked = asBool(row.locked)
    row.active = asBool(row.active)
    row.interaction_x = tonumber(row.interaction_x)
    row.interaction_y = tonumber(row.interaction_y)
    row.interaction_z = tonumber(row.interaction_z)
    row.interaction_distance = tonumber(row.interaction_distance) or Config.DefaultDistance
    row.draw_distance = tonumber(row.draw_distance) or Config.InteractionDrawDistance
    row.auto_lock_seconds = tonumber(row.auto_lock_seconds) or 0
    row.sound_enabled = asBool(row.sound_enabled)
    row.marker_enabled = asBool(row.marker_enabled)
    row.show_label_3d = row.show_label_3d == nil or asBool(row.show_label_3d)
    row.group_id = tonumber(row.group_id)
    row.revision = tonumber(row.revision) or 1
    row.access_policy = decodePolicy(row.access_policy)
    local group = row.group_id and GroupsById[row.group_id] or nil
    row.group = group
    row.effective_access_policy = group and group.active == true and group.access_policy or row.access_policy
    for index, leaf in ipairs(row.leaves or {}) do
        leaf.id = tonumber(leaf.id)
        leaf.door_id = tonumber(leaf.door_id)
        leaf.leaf_order = tonumber(leaf.leaf_order) or index
        leaf.model_hash = tonumber(leaf.model_hash)
        for _, key in ipairs({ 'x', 'y', 'z', 'rx', 'ry', 'rz', 'heading' }) do
            leaf[key] = tonumber(leaf[key]) or 0
        end
    end
    return row
end

local function normalizeGroup(row)
    row.id = tonumber(row.id)
    row.active = asBool(row.active)
    row.access_policy = decodePolicy(row.access_policy)
    return row
end

local function runtimeProjection(definition)
    return {
        id = definition.id,
        code = definition.code,
        label = definition.label,
        kind = definition.kind,
        locked = definition.locked,
        active = definition.active,
        interaction_x = definition.interaction_x,
        interaction_y = definition.interaction_y,
        interaction_z = definition.interaction_z,
        interaction_distance = definition.interaction_distance,
        draw_distance = definition.draw_distance,
        auto_lock_seconds = definition.auto_lock_seconds,
        sound_enabled = definition.sound_enabled,
        marker_enabled = definition.marker_enabled,
        show_label_3d = definition.show_label_3d,
        group_id = definition.group_id,
        revision = definition.revision,
        restricted = tostring((definition.effective_access_policy or definition.access_policy or {}).type or 'public') ~= 'public',
        leaves = definition.leaves
    }
end

local function isRuntimeDefinition(definition)
    if type(definition) ~= 'table' or definition.active == false then return false end
    if Config.V2.RuntimeEnabled == true then return true end
    if Config.V2.NativeDefinitionsDuringMigration ~= true then return false end
    return MZDoorsV2Logic.Trim(definition.legacy_key, 128) == ''
end

local function runtimeSnapshot()
    local out = {}
    for id, definition in pairs(DefinitionsById) do
        if isRuntimeDefinition(definition) then out[id] = runtimeProjection(definition) end
    end
    return out
end

local function audit(source, action, definition, metadata)
    if GetResourceState('mz_core') ~= 'started' then return end
    pcall(function()
        exports['mz_core']:CreateDetailedLog('world', action, {
            actor = { source = source, name = source == 0 and 'console' or GetPlayerName(source) },
            target = { type = 'door', id = definition and definition.code or 'unknown' },
            metadata = metadata or {},
            state = definition and {
                locked = definition.locked,
                active = definition.active,
                revision = definition.revision
            } or nil
        })
    end)
end

local function setCache(definition)
    definition = normalize(definition)
    DefinitionsById[definition.id] = definition
    DefinitionsByCode[definition.code] = definition
    return definition
end

local function loadDefinitions()
    MZDoorsV2DB.ensure()
    DefinitionsById, DefinitionsByCode = {}, {}
    GroupsById, GroupsByCode = {}, {}
    for _, row in ipairs(MZDoorsV2DB.fetchGroups(true)) do
        local group = normalizeGroup(row)
        GroupsById[group.id] = group
        GroupsByCode[group.code] = group
    end
    local rows = MZDoorsV2DB.fetchAll(true)
    for _, row in ipairs(rows) do setCache(row) end
    Loaded = true
    TriggerClientEvent('mz_doors:v2:client:setDoors', -1, runtimeSnapshot())
    print(('[mz_doors:v2] %s definicoes carregadas | runtime=%s | nativas_durante_migracao=%s'):format(
        tostring(#rows),
        tostring(Config.V2.RuntimeEnabled == true),
        tostring(Config.V2.NativeDefinitionsDuringMigration == true)
    ))
end


local function generatedCode(prefix)
    prefix = prefix == 'group' and 'door_group' or 'door'
    for attempt = 1, 20 do
        local code = ('%s_%s_%06d'):format(prefix, os.time(), math.random(0, 999999))
        local exists = prefix == 'door_group' and MZDoorsV2DB.fetchGroupByCode(code) or MZDoorsV2DB.fetchByCode(code)
        if not exists then return code end
    end
    return nil
end

local function resolveDefinition(idOrCode)
    local id = tonumber(idOrCode)
    return id and DefinitionsById[id] or DefinitionsByCode[tostring(idOrCode or '')]
end

local function playerNear(source, definition)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end
    local coords = GetEntityCoords(ped)
    local dx = coords.x - definition.interaction_x
    local dy = coords.y - definition.interaction_y
    local dz = coords.z - definition.interaction_z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    return distance <= (definition.interaction_distance + 1.5)
end

local function persistLock(source, definition, locked, origin)
    local expectedRevision = definition.revision
    if not MZDoorsV2DB.updateLock(definition.id, locked, expectedRevision) then
        local fresh = MZDoorsV2DB.fetchByCode(definition.code)
        if fresh then setCache(fresh) end
        return false, 'stale_revision'
    end
    definition.locked = locked == true
    definition.revision = expectedRevision + 1
    if isRuntimeDefinition(definition) then
        TriggerClientEvent('mz_doors:v2:client:upsertDoor', -1, runtimeProjection(definition))
    end
    audit(source, definition.locked and 'world.door.locked' or 'world.door.unlocked', definition, {
        origin = origin or 'gameplay'
    })

    AutoLockTokens[definition.id] = (AutoLockTokens[definition.id] or 0) + 1
    local token = AutoLockTokens[definition.id]
    if not definition.locked and definition.auto_lock_seconds > 0 then
        SetTimeout(definition.auto_lock_seconds * 1000, function()
            if AutoLockTokens[definition.id] ~= token or definition.locked or definition.active == false then return end
            persistLock(0, definition, true, 'autolock')
        end)
    end
    return true
end

CreateThread(function()
    Wait(750)
    loadDefinitions()
end)

RegisterNetEvent('mz_doors:v2:server:requestDoors', function()
    if not Loaded then loadDefinitions() end
    TriggerClientEvent('mz_doors:v2:client:setDoors', source, runtimeSnapshot())
end)

RegisterNetEvent('mz_doors:v2:server:toggle', function(idOrCode)
    local sourceId = source
    local definition = resolveDefinition(idOrCode)
    if not isRuntimeDefinition(definition) then return end
    if not playerNear(sourceId, definition) then
        TriggerClientEvent('mz_doors:client:notify', sourceId, 'Voce esta longe demais dessa porta.', 'error')
        return
    end
    local allowed, accessReason = MZDoorsV2Access.CanUse(sourceId, definition)
    if allowed ~= true then
        TriggerClientEvent('mz_doors:client:notify', sourceId, 'A porta esta trancada.', 'warning')
        audit(sourceId, 'world.door.access_denied', definition, {
            origin = 'gameplay',
            reason = accessReason or 'unknown'
        })
        return
    end
    local changed, reason = persistLock(sourceId, definition, not definition.locked, 'gameplay')
    if changed then
        TriggerClientEvent(
            'mz_doors:client:notify',
            sourceId,
            definition.locked and 'Porta trancada.' or 'Porta destrancada.',
            definition.locked and 'info' or 'success'
        )
    else
        TriggerClientEvent('mz_doors:client:notify', sourceId, 'A fechadura nao respondeu.', 'error')
        audit(sourceId, 'world.door.toggle_failed', definition, { reason = reason or 'unknown' })
    end
end)

RegisterNetEvent('mz_doors:v2:server:knock', function(idOrCode)
    local sourceId = source
    local definition = resolveDefinition(idOrCode)
    if not isRuntimeDefinition(definition) or not playerNear(sourceId, definition) then return end
    local key = ('%s:%s'):format(sourceId, definition.id)
    local now = GetGameTimer()
    if LastKnockAt[key] and now - LastKnockAt[key] < 1500 then return end
    LastKnockAt[key] = now
    TriggerClientEvent('mz_doors:v2:client:playKnock', -1, {
        id = definition.id,
        x = definition.interaction_x,
        y = definition.interaction_y,
        z = definition.interaction_z
    })
    TriggerClientEvent('mz_doors:client:notify', sourceId, 'Voce bateu na porta.', 'info')
end)

AddEventHandler('playerDropped', function()
    local prefix = tostring(source) .. ':'
    for key in pairs(LastKnockAt) do
        if key:sub(1, #prefix) == prefix then LastKnockAt[key] = nil end
    end
end)

local function migrationReport()
    local rows = MZDoorsV2DB.fetchLegacy()
    local groups = MZDoorsV2Logic.BuildLegacyGroups(rows)
    local report = {
        rows = #rows,
        groups = #groups,
        simple = 0,
        double = 0,
        multi = 0,
        alreadyMigrated = 0,
        invalid = 0
    }
    for _, group in ipairs(groups) do
        if #group.rows == 1 then report.simple = report.simple + 1
        elseif #group.rows == 2 then report.double = report.double + 1
        else report.multi = report.multi + 1 end
        if MZDoorsV2DB.existsLegacyKey(group.key) then report.alreadyMigrated = report.alreadyMigrated + 1 end
        if not MZDoorsV2Logic.ResolveGroupInteraction(group, Config.InteractionOffsetZ) then
            report.invalid = report.invalid + 1
        end
    end
    return report, groups
end

local function migrateLegacy(source)
    local report, groups = migrationReport()
    local created, skipped, failed = 0, 0, 0
    for _, group in ipairs(groups) do
        if MZDoorsV2DB.existsLegacyKey(group.key) then
            skipped = skipped + 1
        else
            local first = group.rows[1]
            local interaction = MZDoorsV2Logic.ResolveGroupInteraction(group, Config.InteractionOffsetZ)
            local label = MZDoorsV2Logic.Trim(first.name, 100)
            if label == '' then label = ('Porta migrada %s'):format(first.id) end
            local code = group.name ~= ''
                and ('legacy_group_' .. MZDoorsV2Logic.LegacySlug(group.name))
                or ('legacy_door_' .. tostring(first.id))
            local policy = MZDoorsV2Logic.Trim(first.ace_permission, 100) ~= ''
                and { type = 'legacy_ace', permission = first.ace_permission }
                or { type = 'public' }
            local leaves = {}
            for _, row in ipairs(group.rows) do
                leaves[#leaves + 1] = {
                    model_hash = tonumber(row.model_hash),
                    model_name = row.model_name,
                    x = tonumber(row.x), y = tonumber(row.y), z = tonumber(row.z),
                    rx = tonumber(row.rx), ry = tonumber(row.ry), rz = tonumber(row.rz),
                    heading = tonumber(row.heading)
                }
            end
            local definition = interaction and MZDoorsV2DB.create({
                code = code,
                label = label,
                kind = #leaves == 1 and 'single' or (#leaves == 2 and 'double' or 'multi'),
                locked = asBool(first.locked),
                active = first.active == nil or asBool(first.active),
                interaction_x = interaction.x,
                interaction_y = interaction.y,
                interaction_z = interaction.z,
                interaction_distance = math.max(0.5, math.min(5.0, tonumber(first.distance) or Config.DefaultDistance)),
                draw_distance = Config.InteractionDrawDistance,
                access_policy = json.encode(policy),
                auto_lock_seconds = 0,
                sound_enabled = true,
                marker_enabled = first.marker_enabled == nil or asBool(first.marker_enabled),
                legacy_key = group.key,
                created_by = source == 0 and 'console:migration' or (GetPlayerName(source) or tostring(source)),
                updated_by = source == 0 and 'console:migration' or (GetPlayerName(source) or tostring(source))
            }, leaves)
            if definition then created = created + 1 else failed = failed + 1 end
        end
    end
    loadDefinitions()
    audit(source, 'world.migration.completed', nil, {
        created = created, skipped = skipped, failed = failed, legacyRows = report.rows
    })
    return { created = created, skipped = skipped, failed = failed, report = report }
end

local function adminAllowed(source, permission)
    return MZDoorsV2Access.HasStaff(source, permission)
        or (source ~= 0 and IsPlayerAceAllowed(source, Config.AdminAce))
        or source == 0
end

RegisterCommand(Config.V2.Command or 'mzdoorsv2', function(source, args)
    if not adminAllowed(source, Config.V2.AdminManagePermission) then return end
    local action = tostring(args[1] or 'status'):lower()
    if action == 'dryrun' or action == 'status' then
        local report = migrationReport()
        local message = ('V2 runtime=%s | legacy=%s | grupos=%s | simples=%s | duplas=%s | multi=%s | migrados=%s | invalidos=%s'):format(
            tostring(Config.V2.RuntimeEnabled == true), report.rows, report.groups, report.simple,
            report.double, report.multi, report.alreadyMigrated, report.invalid
        )
        if source == 0 then print('[mz_doors:v2] ' .. message)
        else TriggerClientEvent('mz_doors:client:notify', source, message, 'info') end
    elseif action == 'migrate' then
        local result = migrateLegacy(source)
        local message = ('Migracao concluida: criadas=%s ignoradas=%s falhas=%s'):format(
            result.created, result.skipped, result.failed
        )
        if source == 0 then print('[mz_doors:v2] ' .. message)
        else TriggerClientEvent('mz_doors:client:notify', source, message, result.failed > 0 and 'error' or 'success') end
    elseif action == 'reload' then
        loadDefinitions()
    end
end, false)

exports('IsV2Ready', function()
    return Loaded, Config.V2.RuntimeEnabled == true, Config.V2.NativeDefinitionsDuringMigration == true
end)

exports('ListV2DoorsForAdmin', function(source)
    if not adminAllowed(source, Config.V2.AdminViewPermission)
        and not adminAllowed(source, Config.V2.AdminManagePermission) then
        return false, 'permission_denied'
    end
    local out = {}
    for _, definition in pairs(DefinitionsById) do out[#out + 1] = definition end
    table.sort(out, function(a, b) return a.id < b.id end)
    return true, out
end)

exports('ListV2DoorGroupsForAdmin', function(source)
    if not adminAllowed(source, Config.V2.AdminViewPermission)
        and not adminAllowed(source, Config.V2.AdminCreatePermission)
        and not adminAllowed(source, Config.V2.AdminManagePermission) then
        return false, 'permission_denied'
    end
    local out = {}
    for _, group in pairs(GroupsById) do
        local copy = {}
        for key, value in pairs(group) do copy[key] = value end
        copy.door_count = 0
        copy.doors = {}
        for _, definition in pairs(DefinitionsById) do
            if definition.group_id == group.id then
                copy.door_count = copy.door_count + 1
                copy.doors[#copy.doors + 1] = definition
            end
        end
        table.sort(copy.doors, function(a, b) return a.id < b.id end)
        out[#out + 1] = copy
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return true, out
end)

exports('CreateV2DoorGroup', function(source, payload)
    if not adminAllowed(source, Config.V2.AdminManagePermission) then return false, 'permission_denied' end
    if type(payload) ~= 'table' then return false, 'invalid_payload' end
    local label = MZDoorsV2Logic.Trim(payload.label, 100)
    if #label < 3 then return false, 'invalid_group_label' end
    local policy = type(payload.accessPolicy) == 'table' and payload.accessPolicy or nil
    local valid, reason = MZDoorsV2Logic.ValidatePolicy(policy)
    if not valid then return false, reason or 'invalid_access_policy' end
    policy, reason = canonicalizeCreatePolicy(policy)
    if not policy then return false, reason or 'invalid_access_policy' end
    local code = MZDoorsV2Logic.ValidCode(payload.code) or generatedCode('group')
    if not code then return false, 'code_generation_failed' end
    if MZDoorsV2DB.fetchGroupByCode(code) then return false, 'code_exists' end
    local actor = source == 0 and 'console' or (GetPlayerName(source) or tostring(source))
    local created = MZDoorsV2DB.createGroup({
        code = code,
        label = label,
        access_policy = json.encode(policy),
        created_by = actor,
        updated_by = actor
    })
    if not created then return false, 'database_error' end
    created = normalizeGroup(created)
    GroupsById[created.id] = created
    GroupsByCode[created.code] = created
    audit(source, 'world.door_group.created', nil, { groupId = created.id, groupCode = created.code })
    return true, created
end)

exports('SetV2DoorGroupForAdmin', function(source, doorIdOrCode, groupIdOrNil)
    if not adminAllowed(source, Config.V2.AdminManagePermission) then return false, 'permission_denied' end
    local definition = resolveDefinition(doorIdOrCode)
    if not definition then return false, 'door_not_found' end
    local groupId = tonumber(groupIdOrNil)
    local group = groupId and GroupsById[groupId] or nil
    if groupId and (not group or group.active ~= true) then return false, 'group_not_found' end
    if definition.group_id == groupId then return true, definition end
    local actor = source == 0 and 'console' or (GetPlayerName(source) or tostring(source))
    if tonumber(MZDoorsV2DB.setDoorGroup(definition.id, groupId, actor)) ~= 1 then
        return false, 'database_error'
    end
    loadDefinitions()
    local updated = DefinitionsById[definition.id]
    audit(source, 'world.door.group_changed', updated, {
        previousGroupId = definition.group_id,
        groupId = groupId
    })
    return true, updated
end)

exports('UpdateV2DoorPresentationForAdmin', function(source, doorIdOrCode, payload)
    if not adminAllowed(source, Config.V2.AdminManagePermission) then return false, 'permission_denied' end
    local definition = resolveDefinition(doorIdOrCode)
    if not definition then return false, 'door_not_found' end
    if type(payload) ~= 'table' then return false, 'invalid_payload' end
    local label = MZDoorsV2Logic.Trim(payload.label, 100)
    if label == '' then label = ('Porta #%s'):format(definition.id) end
    local actor = source == 0 and 'console' or (GetPlayerName(source) or tostring(source))
    if tonumber(MZDoorsV2DB.updatePresentation(definition.id, label, payload.showLabel3d ~= false, actor)) ~= 1 then
        return false, 'database_error'
    end
    local fresh = MZDoorsV2DB.fetchByCode(definition.code)
    if not fresh then return false, 'reload_failed' end
    local updated = setCache(fresh)
    if isRuntimeDefinition(updated) then
        TriggerClientEvent('mz_doors:v2:client:upsertDoor', -1, runtimeProjection(updated))
    end
    audit(source, 'world.door.presentation_updated', updated, {
        previousLabel = definition.label,
        showLabel3d = updated.show_label_3d
    })
    return true, updated
end)

exports('CreateV2Door', function(source, payload)
    if not adminAllowed(source, Config.V2.AdminCreatePermission) then return false, 'permission_denied' end
    if type(payload) ~= 'table' then return false, 'invalid_payload' end
    local code = MZDoorsV2Logic.ValidCode(payload.code) or generatedCode('door')
    local label = MZDoorsV2Logic.Trim(payload.label, 100)
    local leaves = type(payload.leaves) == 'table' and payload.leaves or {}
    if not code or #leaves < 1 or #leaves > (Config.V2.MaxLeaves or 8) then
        return false, 'invalid_definition'
    end
    if MZDoorsV2DB.fetchByCode(code) then return false, 'code_exists' end
    local interaction = payload.interaction
    if type(interaction) ~= 'table' or not tonumber(interaction.x) or not tonumber(interaction.y) or not tonumber(interaction.z) then
        return false, 'invalid_interaction'
    end
    if source ~= 0 then
        local ped = GetPlayerPed(source)
        if not ped or ped == 0 then return false, 'player_unavailable' end
        local coords = GetEntityCoords(ped)
        local dx = coords.x - tonumber(interaction.x)
        local dy = coords.y - tonumber(interaction.y)
        local dz = coords.z - tonumber(interaction.z)
        if math.sqrt(dx * dx + dy * dy + dz * dz) > 30.0 then return false, 'interaction_too_far' end
    end
    local groupId = tonumber(payload.groupId)
    local group = groupId and GroupsById[groupId] or nil
    if groupId and (not group or group.active ~= true) then return false, 'group_not_found' end
    local policy = group and group.access_policy
        or (type(payload.accessPolicy) == 'table' and payload.accessPolicy or { type = 'public' })
    local validPolicy, policyError = MZDoorsV2Logic.ValidatePolicy(policy)
    if not validPolicy then return false, policyError or 'invalid_access_policy' end
    policy, policyError = canonicalizeCreatePolicy(policy)
    if not policy then return false, policyError or 'invalid_access_policy' end
    for _, leaf in ipairs(leaves) do
        if not tonumber(leaf.model_hash) or not tonumber(leaf.x) or not tonumber(leaf.y) or not tonumber(leaf.z) then
            return false, 'invalid_leaf'
        end
    end
    local actor = source == 0 and 'console' or (GetPlayerName(source) or tostring(source))
    local created = MZDoorsV2DB.create({
        code = code,
        label = label ~= '' and label or 'Porta',
        group_id = groupId,
        kind = #leaves == 1 and 'single' or (#leaves == 2 and 'double' or 'multi'),
        locked = payload.locked ~= false,
        active = true,
        interaction_x = tonumber(interaction.x),
        interaction_y = tonumber(interaction.y),
        interaction_z = tonumber(interaction.z),
        interaction_distance = math.max(0.5, math.min(Config.V2.MaxInteractionDistance or 5.0, tonumber(payload.interactionDistance) or Config.DefaultDistance)),
        draw_distance = math.max(2.0, math.min(Config.V2.MaxDrawDistance or 30.0, tonumber(payload.drawDistance) or Config.InteractionDrawDistance)),
        access_policy = json.encode(policy),
        auto_lock_seconds = math.max(0, math.min(Config.V2.MaxAutoLockSeconds or 3600, tonumber(payload.autoLockSeconds) or 0)),
        sound_enabled = payload.soundEnabled ~= false,
        marker_enabled = payload.markerEnabled ~= false,
        show_label_3d = payload.showLabel3d ~= false,
        created_by = actor,
        updated_by = actor
    }, leaves)
    if not created then return false, 'database_error' end
    if label == '' then
        MZDoorsV2DB.setDefaultLabel(created.id, ('Porta #%s'):format(created.id))
        created = MZDoorsV2DB.fetchByCode(code)
    end
    created = setCache(created)
    if isRuntimeDefinition(created) then
        TriggerClientEvent('mz_doors:v2:client:upsertDoor', -1, runtimeProjection(created))
    end
    audit(source, 'world.door.created', created, { origin = 'admin' })
    return true, created
end)

exports('SetV2DoorLockedForAdmin', function(source, idOrCode, locked)
    if not adminAllowed(source, Config.V2.AdminManagePermission) then
        return false, 'permission_denied'
    end
    local definition = resolveDefinition(idOrCode)
    if not definition then return false, 'door_not_found' end
    if definition.active == false then return false, 'door_archived' end
    locked = locked == true
    if definition.locked == locked then return true, definition end
    local ok, reason = persistLock(source, definition, locked, 'admin')
    if not ok then return false, reason or 'database_error' end
    return true, definition
end)

exports('SetV2DoorActiveForAdmin', function(source, idOrCode, active)
    if not adminAllowed(source, Config.V2.AdminArchivePermission) then
        return false, 'permission_denied'
    end
    local definition = resolveDefinition(idOrCode)
    if not definition then return false, 'door_not_found' end
    active = active == true
    if definition.active == active then return true, definition end

    local actor = source == 0 and 'console' or (GetPlayerName(source) or tostring(source))
    local affected = MZDoorsV2DB.setActive(definition.id, active, actor)
    if tonumber(affected) ~= 1 then return false, 'stale_state' end

    AutoLockTokens[definition.id] = (AutoLockTokens[definition.id] or 0) + 1
    local fresh = MZDoorsV2DB.fetchByCode(definition.code)
    if not fresh then return false, 'reload_failed' end
    definition = setCache(fresh)

    if definition.active then
        if isRuntimeDefinition(definition) then
            TriggerClientEvent('mz_doors:v2:client:upsertDoor', -1, runtimeProjection(definition))
        end
    else
        TriggerClientEvent('mz_doors:v2:client:removeDoor', -1, definition.id)
    end
    audit(source, definition.active and 'world.door.restored' or 'world.door.archived', definition, {
        origin = 'admin'
    })
    return true, definition
end)
