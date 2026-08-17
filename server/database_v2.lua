MZDoorsV2DB = MZDoorsV2DB or {}

local function ensureColumn(tableName, columnName, definition)
    local exists = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    ]], { tableName, columnName })
    if tonumber(exists) == 0 then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition))
    end
end

local function ensureIndex(tableName, indexName, columns)
    local exists = MySQL.scalar.await([[
        SELECT COUNT(*) FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?
    ]], { tableName, indexName })
    if tonumber(exists) == 0 then
        MySQL.query.await(('ALTER TABLE `%s` ADD INDEX `%s` (%s)'):format(tableName, indexName, columns))
    end
end

function MZDoorsV2DB.ensure()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mz_door_groups` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `code` VARCHAR(64) NOT NULL,
          `label` VARCHAR(100) NOT NULL,
          `access_policy` LONGTEXT NOT NULL,
          `active` TINYINT(1) NOT NULL DEFAULT 1,
          `created_by` VARCHAR(100) DEFAULT NULL,
          `updated_by` VARCHAR(100) DEFAULT NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uq_mz_door_groups_code` (`code`),
          KEY `idx_mz_door_groups_active` (`active`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mz_door_definitions` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `code` VARCHAR(64) NOT NULL,
          `label` VARCHAR(100) NOT NULL,
          `kind` VARCHAR(16) NOT NULL DEFAULT 'single',
          `locked` TINYINT(1) NOT NULL DEFAULT 1,
          `active` TINYINT(1) NOT NULL DEFAULT 1,
          `interaction_x` DOUBLE NOT NULL,
          `interaction_y` DOUBLE NOT NULL,
          `interaction_z` DOUBLE NOT NULL,
          `interaction_distance` DOUBLE NOT NULL DEFAULT 2,
          `draw_distance` DOUBLE NOT NULL DEFAULT 8,
          `access_policy` LONGTEXT DEFAULT NULL,
          `auto_lock_seconds` INT NOT NULL DEFAULT 0,
          `sound_enabled` TINYINT(1) NOT NULL DEFAULT 1,
          `marker_enabled` TINYINT(1) NOT NULL DEFAULT 1,
          `revision` INT NOT NULL DEFAULT 1,
          `legacy_key` VARCHAR(128) DEFAULT NULL,
          `created_by` VARCHAR(100) DEFAULT NULL,
          `updated_by` VARCHAR(100) DEFAULT NULL,
          `archived_by` VARCHAR(100) DEFAULT NULL,
          `archived_at` TIMESTAMP NULL DEFAULT NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uq_mz_door_definitions_code` (`code`),
          UNIQUE KEY `uq_mz_door_definitions_legacy` (`legacy_key`),
          KEY `idx_mz_door_definitions_active` (`active`),
          KEY `idx_mz_door_definitions_locked` (`locked`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mz_door_leaves` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `door_id` INT NOT NULL,
          `leaf_order` INT NOT NULL DEFAULT 1,
          `model_hash` BIGINT NOT NULL,
          `model_name` VARCHAR(100) DEFAULT NULL,
          `x` DOUBLE NOT NULL,
          `y` DOUBLE NOT NULL,
          `z` DOUBLE NOT NULL,
          `rx` DOUBLE NOT NULL DEFAULT 0,
          `ry` DOUBLE NOT NULL DEFAULT 0,
          `rz` DOUBLE NOT NULL DEFAULT 0,
          `heading` DOUBLE NOT NULL DEFAULT 0,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          UNIQUE KEY `uq_mz_door_leaf_order` (`door_id`, `leaf_order`),
          KEY `idx_mz_door_leaves_model` (`model_hash`),
          KEY `idx_mz_door_leaves_door` (`door_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    ensureColumn('mz_door_definitions', 'group_id', 'INT DEFAULT NULL AFTER `label`')
    ensureColumn('mz_door_definitions', 'show_label_3d', 'TINYINT(1) NOT NULL DEFAULT 1 AFTER `marker_enabled`')
    ensureIndex('mz_door_definitions', 'idx_mz_door_definitions_group', '`group_id`')
end

function MZDoorsV2DB.fetchGroups(includeInactive)
    local where = includeInactive == true and '' or ' WHERE active = 1'
    return MySQL.query.await('SELECT * FROM mz_door_groups' .. where .. ' ORDER BY label ASC, id ASC') or {}
end

function MZDoorsV2DB.fetchGroupById(id)
    return MySQL.single.await('SELECT * FROM mz_door_groups WHERE id = ? LIMIT 1', { id })
end

function MZDoorsV2DB.fetchGroupByCode(code)
    return MySQL.single.await('SELECT * FROM mz_door_groups WHERE code = ? LIMIT 1', { code })
end

function MZDoorsV2DB.createGroup(group)
    local id = MySQL.insert.await([[
        INSERT INTO mz_door_groups (`code`, `label`, `access_policy`, `active`, `created_by`, `updated_by`)
        VALUES (?, ?, ?, 1, ?, ?)
    ]], { group.code, group.label, group.access_policy, group.created_by, group.updated_by })
    return id and MZDoorsV2DB.fetchGroupById(id) or nil
end

function MZDoorsV2DB.setDoorGroup(doorId, groupId, actor)
    return MySQL.update.await([[
        UPDATE mz_door_definitions
        SET group_id = ?, updated_by = ?, revision = revision + 1
        WHERE id = ?
    ]], { groupId, actor, doorId })
end

function MZDoorsV2DB.setDefaultLabel(id, label)
    MySQL.update.await('UPDATE mz_door_definitions SET label = ? WHERE id = ?', { label, id })
end

function MZDoorsV2DB.updatePresentation(id, label, showLabel3d, actor)
    return MySQL.update.await([[
        UPDATE mz_door_definitions
        SET label = ?, show_label_3d = ?, updated_by = ?, revision = revision + 1
        WHERE id = ?
    ]], { label, showLabel3d and 1 or 0, actor, id })
end

function MZDoorsV2DB.fetchAll(includeArchived)
    local where = includeArchived == true and '' or ' WHERE active = 1'
    local definitions = MySQL.query.await('SELECT * FROM mz_door_definitions' .. where .. ' ORDER BY id ASC') or {}
    local leaves = MySQL.query.await([[
        SELECT l.*
        FROM mz_door_leaves l
        INNER JOIN mz_door_definitions d ON d.id = l.door_id
    ]] .. (includeArchived == true and '' or ' WHERE d.active = 1') .. ' ORDER BY l.door_id ASC, l.leaf_order ASC') or {}

    local byId = {}
    for _, definition in ipairs(definitions) do
        definition.leaves = {}
        byId[tonumber(definition.id)] = definition
    end
    for _, leaf in ipairs(leaves) do
        local definition = byId[tonumber(leaf.door_id)]
        if definition then definition.leaves[#definition.leaves + 1] = leaf end
    end
    return definitions
end

function MZDoorsV2DB.fetchByCode(code)
    local definition = MySQL.single.await('SELECT * FROM mz_door_definitions WHERE code = ? LIMIT 1', { code })
    if not definition then return nil end
    definition.leaves = MySQL.query.await(
        'SELECT * FROM mz_door_leaves WHERE door_id = ? ORDER BY leaf_order ASC',
        { definition.id }
    ) or {}
    return definition
end

function MZDoorsV2DB.existsLegacyKey(key)
    return tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM mz_door_definitions WHERE legacy_key = ?',
        { key }
    )) > 0
end

function MZDoorsV2DB.create(definition, leaves)
    local queries = {
        {
            query = [[
                INSERT INTO mz_door_definitions
                (`code`, `label`, `group_id`, `kind`, `locked`, `active`,
                 `interaction_x`, `interaction_y`, `interaction_z`,
                 `interaction_distance`, `draw_distance`, `access_policy`,
                 `auto_lock_seconds`, `sound_enabled`, `marker_enabled`, `show_label_3d`,
                 `legacy_key`, `created_by`, `updated_by`)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ]],
            values = {
                definition.code, definition.label, definition.group_id, definition.kind,
                definition.locked and 1 or 0, definition.active ~= false and 1 or 0,
                definition.interaction_x, definition.interaction_y, definition.interaction_z,
                definition.interaction_distance, definition.draw_distance, definition.access_policy,
                definition.auto_lock_seconds, definition.sound_enabled ~= false and 1 or 0,
                definition.marker_enabled ~= false and 1 or 0,
                definition.show_label_3d ~= false and 1 or 0,
                definition.legacy_key, definition.created_by, definition.updated_by
            }
        }
    }

    for index, leaf in ipairs(leaves or {}) do
        queries[#queries + 1] = {
            query = [[
                INSERT INTO mz_door_leaves
                (`door_id`, `leaf_order`, `model_hash`, `model_name`,
                 `x`, `y`, `z`, `rx`, `ry`, `rz`, `heading`)
                SELECT `id`, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                FROM mz_door_definitions WHERE code = ?
            ]],
            values = {
                index, leaf.model_hash, leaf.model_name,
                leaf.x, leaf.y, leaf.z,
                leaf.rx or 0, leaf.ry or 0, leaf.rz or 0, leaf.heading or 0,
                definition.code
            }
        }
    end

    local ok = MySQL.transaction.await(queries)
    if not ok then return nil end
    return MZDoorsV2DB.fetchByCode(definition.code)
end

function MZDoorsV2DB.updateLock(id, locked, expectedRevision)
    local affected = MySQL.update.await([[
        UPDATE mz_door_definitions
        SET locked = ?, revision = revision + 1
        WHERE id = ? AND revision = ?
    ]], { locked and 1 or 0, id, expectedRevision })
    return tonumber(affected) == 1
end

function MZDoorsV2DB.setActive(id, active, actor)
    if active then
        return MySQL.update.await([[
            UPDATE mz_door_definitions
            SET active = 1, archived_by = NULL, archived_at = NULL,
                updated_by = ?, revision = revision + 1
            WHERE id = ? AND active = 0
        ]], { actor, id })
    end

    return MySQL.update.await([[
        UPDATE mz_door_definitions
        SET active = 0, archived_by = ?, archived_at = UTC_TIMESTAMP(),
            updated_by = ?, revision = revision + 1
        WHERE id = ? AND active = 1
    ]], { actor, actor, id })
end

function MZDoorsV2DB.fetchLegacy()
    return MySQL.query.await('SELECT * FROM mz_world_doors ORDER BY id ASC') or {}
end
