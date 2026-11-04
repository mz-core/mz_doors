MZDoorsV2Access = MZDoorsV2Access or {}

local function coreCall(exportName, ...)
    if GetResourceState('mz_core') ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        -- Exports dinamicos com [] deslocam o primeiro argumento no proxy do
        -- FiveM. Para acesso organizacional, isso fazia o source virar orgCode.
        if exportName == 'ResolvePlayerIdentity' then
            return exports['mz_core']:ResolvePlayerIdentity(args[1])
        elseif exportName == 'HasGlobalPermission' then
            return exports['mz_core']:HasGlobalPermission(args[1], args[2])
        elseif exportName == 'HasGradeOrAbove' then
            return exports['mz_org']:HasGradeOrAbove(args[1], args[2], args[3])
        elseif exportName == 'CanOrg' then
            return exports['mz_org']:CanOrg(args[1], args[2], args[3])
        elseif exportName == 'GetPlayerOrgs' then
            return exports['mz_org']:GetPlayerOrgs(args[1])
        end
        error(('unsupported mz_core export: %s'):format(tostring(exportName)))
    end)
    if not ok then
        print(('[mz_doors:v2] mz_core export %s falhou: %s'):format(
            tostring(exportName), tostring(result)
        ))
        return nil
    end
    return result
end

local function resolveCitizenId(source)
    local identity = coreCall('ResolvePlayerIdentity', source)
    if type(identity) ~= 'table' or identity.ok ~= true then return nil end
    local citizenid = MZDoorsV2Logic.Trim(identity.citizenid, 64)
    return citizenid ~= '' and citizenid or nil
end

local function evaluate(source, policy, depth)
    depth = tonumber(depth) or 0
    if depth > 3 or type(policy) ~= 'table' then return false, 'invalid_policy' end
    local policyType = MZDoorsV2Logic.Trim(policy.type, 24):lower()

    if policyType == 'public' then return true, 'public' end

    if policyType == 'legacy_ace' then
        local permission = MZDoorsV2Logic.Trim(policy.permission, 100)
        if permission == '' then return false, 'invalid_legacy_ace' end
        return IsPlayerAceAllowed(source, permission) == true, 'legacy_ace'
    end

    if policyType == 'staff' then
        local permission = MZDoorsV2Logic.Trim(policy.permission, 128)
        if permission == '' then return false, 'invalid_staff_permission' end
        return coreCall('HasGlobalPermission', source, permission) == true, 'staff'
    end

    if policyType == 'organization' then
        local orgCode = MZDoorsV2Logic.Trim(policy.code, 64):lower()
        if orgCode == '' then return false, 'invalid_organization' end
        local minGrade = math.max(0, tonumber(policy.minGrade) or 0)
        local gradeAllowed = coreCall('HasGradeOrAbove', source, orgCode, minGrade) == true
        if not gradeAllowed then
            for _, org in ipairs(coreCall('GetPlayerOrgs', source) or {}) do
                local grade = type(org.grade) == 'table' and org.grade.level or org.gradeLevel or org.grade
                if MZDoorsV2Logic.Trim(org.code, 64):lower() == orgCode
                    and org.active ~= false
                    and (tonumber(grade) or 0) >= minGrade then
                    gradeAllowed = true
                    break
                end
            end
        end
        if not gradeAllowed then
            return false, 'organization_grade'
        end
        local permission = MZDoorsV2Logic.Trim(policy.permission, 128)
        if permission ~= '' and coreCall('CanOrg', source, orgCode, permission) ~= true then
            return false, 'organization_permission'
        end
        return true, 'organization'
    end

    if policyType == 'citizen' then
        local citizenid = resolveCitizenId(source)
        if not citizenid then return false, 'identity_unavailable' end
        for _, allowed in ipairs(type(policy.citizenids) == 'table' and policy.citizenids or {}) do
            if citizenid == MZDoorsV2Logic.Trim(allowed, 64) then return true, 'citizen' end
        end
        return false, 'citizen_denied'
    end

    if policyType == 'composite' then
        local rules = type(policy.rules) == 'table' and policy.rules or {}
        if #rules == 0 or #rules > 10 then return false, 'invalid_composite' end
        local mode = tostring(policy.mode or 'any'):lower()
        if mode == 'all' then
            for _, rule in ipairs(rules) do
                local allowed = evaluate(source, rule, depth + 1)
                if allowed ~= true then return false, 'composite_all' end
            end
            return true, 'composite_all'
        end
        for _, rule in ipairs(rules) do
            local allowed = evaluate(source, rule, depth + 1)
            if allowed == true then return true, 'composite_any' end
        end
        return false, 'composite_any'
    end

    return false, 'unknown_policy'
end

function MZDoorsV2Access.CanUse(source, definition)
    if source == 0 then return true, 'console' end
    if type(definition) ~= 'table' or definition.active == false then return false, 'inactive' end
    if MZDoorsV2Access.HasStaff(source, (Config.V2 or {}).AdminManagePermission) then
        return true, 'staff_override'
    end
    return evaluate(source, definition.effective_access_policy or definition.access_policy or { type = 'public' }, 0)
end

function MZDoorsV2Access.HasStaff(source, permission)
    if source == 0 then return true end
    if type(permission) ~= 'string' or permission == '' then return false end
    return coreCall('HasGlobalPermission', source, permission) == true
end
