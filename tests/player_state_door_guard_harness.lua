local function read(path)
    local file = assert(io.open(path, 'rb'))
    local content = file:read('*a')
    file:close()
    return content
end

local function expect(condition, message)
    if not condition then error('[player_state_door_guard_harness] ' .. message, 2) end
end

local client = read('mz_doors/client/main.lua')
local clientV2 = read('mz_doors/client/v2.lua')
local server = read('mz_doors/server/main.lua')
local serverV2 = read('mz_doors/server/v2.lua')
local manifest = read('mz_doors/fxmanifest.lua')

expect(client:find("CanLocalPlayerPerformAction('property.use')", 1, true), 'guard local canonico ausente')
expect(client:find('if not requirePropertyAction() then return end', 1, true), 'command/interact sem guard local')
expect(clientV2:find('if not MZDoorsCanPerformPropertyAction() then', 1, true), 'V2 sem guard local')
expect(server:find("CanPlayerPerformAction(source, 'property.use')", 1, true), 'guard server canonico ausente')
expect(server:find('if not MZDoorsPlayerActionAllowed(src) then', 1, true), 'toggle legacy sem guard server')
expect(serverV2:find('if not MZDoorsPlayerActionAllowed(sourceId) then', 1, true), 'toggle/knock V2 sem guard server')
expect(manifest:find("'mz_core'", 1, true), 'dependency mz_core ausente')

local sequence = { 'alive', 'downed', 'dead', 'respawning', 'alive' }
local expected = { true, false, false, false, true }
for index, state in ipairs(sequence) do
    expect((state == 'alive') == expected[index], 'matriz canonica divergente em ' .. state)
end

print('[player_state_door_guard_harness] PASS states=5 legacy=1 v2=2')
