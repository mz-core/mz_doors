local function read(path)
    local file = assert(io.open(path, 'r'))
    local content = file:read('*a')
    file:close()
    return content
end

local function expect(condition, message)
    if not condition then error(message, 2) end
end

local database = read('mz_doors/server/database_v2.lua')
local server = read('mz_doors/server/v2.lua')
local access = read('mz_doors/server/access_v2.lua')
local client = read('mz_doors/client/v2.lua')
local bridge = read('mz_admin/server/world.lua')
local wizard = read('mz_admin/client/world_wizard.lua')

expect(database:find('CREATE TABLE IF NOT EXISTS `mz_door_groups`', 1, true), 'door group table is missing')
expect(database:find("ensureColumn('mz_door_definitions', 'group_id'", 1, true), 'group migration is missing')
expect(database:find("ensureColumn('mz_door_definitions', 'show_label_3d'", 1, true), '3D label migration is missing')
expect(server:find("exports('CreateV2DoorGroup'", 1, true), 'group creation export is missing')
expect(server:find("exports('SetV2DoorGroupForAdmin'", 1, true), 'group membership export is missing')
expect(server:find("or generatedCode('door')", 1, true), 'automatic door code is missing')
expect(server:find("('Porta #%s'):format(created.id)", 1, true), 'default door label is missing')
expect(access:find('definition.effective_access_policy', 1, true), 'group policy is not applied to access')
expect(client:find('door.show_label_3d == false', 1, true), '3D label visibility is not applied')
expect(bridge:find("mz_admin:server:createWorldDoorGroup", 1, true), 'admin group bridge is missing')
expect(bridge:find("mz_admin:server:setWorldDoorGroup", 1, true), 'admin membership bridge is missing')
expect(wizard:find('Criar grupo de portas', 1, true), 'group menu is missing')
expect(wizard:find('Exibir nome no texto 3D', 1, true), '3D label choice is missing')
expect(wizard:find("request('setWorldDoorGroup'", 1, true), 'membership UI is missing')
expect(wizard:find("'groupDoorDetails'", 1, true), 'doors inside a group do not open their editor')
expect(wizard:find("title = 'Remover deste grupo'", 1, true), 'group removal is not a separate detail action')

print('mz_doors group contract harness: ok')
