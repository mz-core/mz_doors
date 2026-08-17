MZDoorsV2Logic = MZDoorsV2Logic or {}

function MZDoorsV2Logic.Trim(value, maxLength)
    local text = tostring(value or ''):gsub('%c', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLength and #text > maxLength then text = text:sub(1, maxLength) end
    return text
end

function MZDoorsV2Logic.ValidCode(value)
    local code = MZDoorsV2Logic.Trim(value, 64):lower()
    if #code < 3 then return nil end
    if not code:match('^[a-z0-9][a-z0-9_%-]+$') then return nil end
    return code
end

function MZDoorsV2Logic.LegacySlug(value)
    local text = MZDoorsV2Logic.Trim(value, 64):lower()
    text = text:gsub('[^a-z0-9]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    if text == '' then return 'group' end
    return text:sub(1, 48)
end

function MZDoorsV2Logic.ValidatePolicy(policy, depth)
    depth = tonumber(depth) or 0
    if depth > 3 or type(policy) ~= 'table' then return false, 'invalid_policy' end
    local policyType = MZDoorsV2Logic.Trim(policy.type, 24):lower()
    if policyType == 'public' then return true end

    if policyType == 'staff' then
        local permission = MZDoorsV2Logic.Trim(policy.permission, 128)
        if permission == '' then return false, 'invalid_staff_permission' end
        return true
    end

    if policyType == 'organization' then
        local code = MZDoorsV2Logic.Trim(policy.code, 64):lower()
        if code == '' or not code:match('^[a-z0-9][a-z0-9_%-]*$') then
            return false, 'invalid_organization'
        end
        local minGrade = tonumber(policy.minGrade)
        if minGrade == nil or minGrade < 0 or minGrade > 1000 then
            return false, 'invalid_organization_grade'
        end
        return true
    end

    if policyType == 'citizen' then
        local citizenids = type(policy.citizenids) == 'table' and policy.citizenids or {}
        if #citizenids < 1 or #citizenids > 100 then return false, 'invalid_citizens' end
        for _, citizenid in ipairs(citizenids) do
            if MZDoorsV2Logic.Trim(citizenid, 64) == '' then return false, 'invalid_citizen' end
        end
        return true
    end

    if policyType == 'composite' then
        local rules = type(policy.rules) == 'table' and policy.rules or {}
        local mode = MZDoorsV2Logic.Trim(policy.mode, 8):lower()
        if mode ~= 'any' and mode ~= 'all' then return false, 'invalid_composite_mode' end
        if #rules < 1 or #rules > 10 then return false, 'invalid_composite_rules' end
        for _, rule in ipairs(rules) do
            local valid, reason = MZDoorsV2Logic.ValidatePolicy(rule, depth + 1)
            if not valid then return false, reason end
        end
        return true
    end

    return false, 'invalid_access_policy'
end

function MZDoorsV2Logic.BuildLegacyGroups(rows)
    local groups = {}
    for _, row in ipairs(type(rows) == 'table' and rows or {}) do
        local id = tonumber(row.id)
        if id then
            local groupName = MZDoorsV2Logic.Trim(row.double_group, 100)
            local key = groupName ~= '' and ('group:' .. groupName) or ('door:' .. id)
            if not groups[key] then groups[key] = { key = key, name = groupName, rows = {} } end
            groups[key].rows[#groups[key].rows + 1] = row
        end
    end

    local out = {}
    for _, group in pairs(groups) do
        table.sort(group.rows, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
        out[#out + 1] = group
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

function MZDoorsV2Logic.ResolveGroupInteraction(group, fallbackOffsetZ)
    local explicitX, explicitY, explicitZ, explicitCount = 0.0, 0.0, 0.0, 0
    local x, y, z, count = 0.0, 0.0, 0.0, 0
    for _, row in ipairs(group and group.rows or {}) do
        local rx, ry, rz = tonumber(row.x), tonumber(row.y), tonumber(row.z)
        if rx and ry and rz then
            x, y, z, count = x + rx, y + ry, z + rz, count + 1
        end
        local ix, iy, iz = tonumber(row.interaction_x), tonumber(row.interaction_y), tonumber(row.interaction_z)
        if ix and iy and iz then
            explicitX, explicitY, explicitZ = explicitX + ix, explicitY + iy, explicitZ + iz
            explicitCount = explicitCount + 1
        end
    end
    if explicitCount > 0 then
        return { x = explicitX / explicitCount, y = explicitY / explicitCount, z = explicitZ / explicitCount }
    end
    if count == 0 then return nil end
    return { x = x / count, y = y / count, z = (z / count) + (tonumber(fallbackOffsetZ) or 0.75) }
end
