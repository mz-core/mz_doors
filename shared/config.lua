Config = Config or {}

Config.AdminAce = 'group.mz_owner'
Config.AdminAces = {
    'group.mz_owner',
    'mz.world',
    'sbstudio.open',
    'command'
}
Config.AutoCreateTable = true
Config.Command = 'mzdoors'
Config.ToggleCommand = 'doorlock'
Config.ListPageSize = 10
Config.DrawDistance = 12.0
Config.DefaultDistance = 2.0
Config.DefaultDoorAce = 'group.mz_owner'
Config.ShowDoorText = true
Config.UseDoorTextOnlyForNearby = true
Config.ToggleKey = 38 -- E

Config.UseMzInteract = true
Config.InteractionOffsetZ = 0.75
Config.InteractionDrawDistance = 8.0
Config.InteractionMarker = {
    -- O texto contextual e a marcacao principal. O marker geometrico azul
    -- fica desligado para nao parecer um objeto criado no mundo.
    enabled = false,
    type = 20,
    size = vec3(0.16, 0.16, 0.16),
    color = { r = 245, g = 210, b = 120, a = 120 },
    rotate = false,
    bobUpAndDown = false,
    faceCamera = true
}

Config.NotifyPrefix = 'MZ Doors'
Config.UseMzNotify = true
Config.UseMzMenuNotify = true
Config.UseChatNotify = true
Config.UseNativeNotify = true

Config.V2 = {
    -- O repositorio V2 e criado e pode receber migracao mesmo com runtime desligado.
    -- Ative somente depois de executar /mzdoorsv2 dryrun e /mzdoorsv2 migrate.
    RuntimeEnabled = false,
    -- Durante a migracao, portas criadas diretamente pelo painel V2 ja podem
    -- funcionar sem ativar as definicoes importadas e sem desligar o legado.
    NativeDefinitionsDuringMigration = true,
    Command = 'mzdoorsv2',
    MaxLeaves = 8,
    MaxInteractionDistance = 5.0,
    MaxDrawDistance = 30.0,
    MaxAutoLockSeconds = 3600,
    AdminViewPermission = 'staff.world.view',
    AdminCreatePermission = 'staff.world.doors.create',
    AdminManagePermission = 'staff.world.doors.manage',
    AdminArchivePermission = 'staff.world.doors.archive'
}
