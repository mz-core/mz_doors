local failures = {}

local function expect(label, condition)
    if not condition then failures[#failures + 1] = label end
end

dofile('mz_doors/shared/v2_logic.lua')

expect('valid structural code', MZDoorsV2Logic.ValidCode('mrpd_main_01') == 'mrpd_main_01')
expect('code normalizes case', MZDoorsV2Logic.ValidCode('MRPD_MAIN') == 'mrpd_main')
expect('code rejects spaces', MZDoorsV2Logic.ValidCode('mrpd main') == nil)
expect('code rejects short values', MZDoorsV2Logic.ValidCode('a') == nil)

local rows = {
    { id = 3, double_group = '', x = 30, y = 0, z = 0 },
    { id = 2, double_group = 'mrpd', x = 12, y = 0, z = 2 },
    { id = 1, double_group = 'mrpd', x = 10, y = 0, z = 2 }
}
local groups = MZDoorsV2Logic.BuildLegacyGroups(rows)
expect('legacy rows grouped into logical doors', #groups == 2)

local grouped
for _, group in ipairs(groups) do
    if group.key == 'group:mrpd' then grouped = group end
end
expect('double group found', grouped and #grouped.rows == 2)
expect('leaves sorted by id', grouped and grouped.rows[1].id == 1)

local interaction = MZDoorsV2Logic.ResolveGroupInteraction(grouped, 0.75)
expect('fallback interaction averages x', interaction and interaction.x == 11)
expect('fallback interaction offsets z', interaction and interaction.z == 2.75)

grouped.rows[1].interaction_x = 20
grouped.rows[1].interaction_y = 30
grouped.rows[1].interaction_z = 40
interaction = MZDoorsV2Logic.ResolveGroupInteraction(grouped, 0.75)
expect('explicit interaction wins', interaction and interaction.x == 20 and interaction.z == 40)

expect('legacy slug is stable', MZDoorsV2Logic.LegacySlug('MRPD Entrada Principal') == 'mrpd_entrada_principal')
expect('public policy is valid', MZDoorsV2Logic.ValidatePolicy({ type = 'public' }) == true)
expect('staff policy requires permission', MZDoorsV2Logic.ValidatePolicy({ type = 'staff' }) == false)
expect('organization policy requires code', MZDoorsV2Logic.ValidatePolicy({
    type = 'organization', code = 'police', minGrade = 2
}) == true)
expect('organization grade is bounded', MZDoorsV2Logic.ValidatePolicy({
    type = 'organization', code = 'police', minGrade = 1001
}) == false)
expect('composite policy validates nested rules', MZDoorsV2Logic.ValidatePolicy({
    type = 'composite',
    mode = 'any',
    rules = {
        { type = 'public' },
        { type = 'staff', permission = 'staff.world.doors.manage' }
    }
}) == true)

local accessFile = assert(io.open('mz_doors/server/access_v2.lua', 'r'))
local accessSource = accessFile:read('*a')
accessFile:close()
expect('core access bridge does not use shifting dynamic export calls',
    accessSource:find("exports['mz_core'][exportName]", 1, true) == nil)
expect('organization grade uses official method export',
    accessSource:find("exports['mz_core']:HasGradeOrAbove", 1, true) ~= nil)
expect('organization capability uses official method export',
    accessSource:find("exports['mz_core']:CanOrg", 1, true) ~= nil)
expect('organization access can refresh memberships from the core',
    accessSource:find("exports['mz_core']:GetPlayerOrgs", 1, true) ~= nil)

local serverFile = assert(io.open('mz_doors/server/v2.lua', 'r'))
local serverSource = serverFile:read('*a')
serverFile:close()
expect('door creation validates organization against the core catalog',
    serverSource:find("exports['mz_core']:GetOrgByCode", 1, true) ~= nil)
expect('door creation stores the canonical organization code',
    serverSource:find("code = MZDoorsV2Logic.Trim(organization.code, 64):lower()", 1, true) ~= nil)

local adminServerFile = assert(io.open('mz_admin/server/world.lua', 'r'))
local adminServerSource = adminServerFile:read('*a')
adminServerFile:close()
expect('admin exposes the organization catalog callback',
    adminServerSource:find('listWorldOrganizations', 1, true) ~= nil)
expect('admin organization catalog comes from mz_core',
    adminServerSource:find("exports['mz_core']:ListOrgs", 1, true) ~= nil)

local wizardFile = assert(io.open('mz_admin/client/world_wizard.lua', 'r'))
local wizardSource = wizardFile:read('*a')
wizardFile:close()
expect('door wizard requests organization catalog',
    wizardSource:find("request('listWorldOrganizations')", 1, true) ~= nil)
expect('door wizard uses organization select',
    wizardSource:find("type = 'select'", 1, true) ~= nil)
expect('door wizard no longer asks for a typed organization code',
    wizardSource:find('Codigo da organizacao', 1, true) == nil)

if #failures > 0 then
    error(('mz_doors v2 logic harness failed:\n- %s'):format(table.concat(failures, '\n- ')))
end

print('mz_doors v2 logic harness: ok')
