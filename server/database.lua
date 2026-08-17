MZDoorsDB = MZDoorsDB or {}

local function ensureColumn(name, definition)
    local exists = MySQL.scalar.await([[
        SELECT COUNT(*)
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'mz_world_doors' AND COLUMN_NAME = ?
    ]], { name })
    if tonumber(exists) == 0 then
        MySQL.query.await(('ALTER TABLE `mz_world_doors` ADD COLUMN `%s` %s'):format(name, definition))
    end
end

function MZDoorsDB.ensure()
    if not Config.AutoCreateTable then return end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mz_world_doors` (
          `id` INT NOT NULL AUTO_INCREMENT,
          `name` VARCHAR(100) NOT NULL DEFAULT 'Porta sem nome',
          `model_hash` BIGINT NOT NULL,
          `model_name` VARCHAR(100) DEFAULT NULL,
          `x` DOUBLE NOT NULL,
          `y` DOUBLE NOT NULL,
          `z` DOUBLE NOT NULL,
          `rx` DOUBLE NOT NULL DEFAULT 0,
          `ry` DOUBLE NOT NULL DEFAULT 0,
          `rz` DOUBLE NOT NULL DEFAULT 0,
          `heading` DOUBLE NOT NULL DEFAULT 0,
          `locked` TINYINT(1) NOT NULL DEFAULT 1,
          `distance` DOUBLE NOT NULL DEFAULT 2,
          `ace_permission` VARCHAR(100) DEFAULT NULL,
          `double_group` VARCHAR(100) DEFAULT NULL,
          `created_by` VARCHAR(100) DEFAULT NULL,
          `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `idx_double_group` (`double_group`),
          KEY `idx_model_hash` (`model_hash`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    ensureColumn('code', 'VARCHAR(64) DEFAULT NULL AFTER `name`')
    ensureColumn('interaction_x', 'DOUBLE DEFAULT NULL AFTER `z`')
    ensureColumn('interaction_y', 'DOUBLE DEFAULT NULL AFTER `interaction_x`')
    ensureColumn('interaction_z', 'DOUBLE DEFAULT NULL AFTER `interaction_y`')
    ensureColumn('marker_enabled', 'TINYINT(1) NOT NULL DEFAULT 1 AFTER `distance`')
    ensureColumn('active', 'TINYINT(1) NOT NULL DEFAULT 1 AFTER `marker_enabled`')
end

function MZDoorsDB.fetchAll()
    return MySQL.query.await('SELECT * FROM mz_world_doors ORDER BY id ASC') or {}
end

function MZDoorsDB.insert(data)
    return MySQL.insert.await([[
        INSERT INTO mz_world_doors
        (`name`, `code`, `model_hash`, `model_name`, `x`, `y`, `z`, `interaction_x`, `interaction_y`, `interaction_z`, `rx`, `ry`, `rz`, `heading`, `locked`, `distance`, `marker_enabled`, `active`, `ace_permission`, `double_group`, `created_by`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.name,
        data.code,
        data.model_hash,
        data.model_name,
        data.x, data.y, data.z,
        data.interaction_x, data.interaction_y, data.interaction_z,
        data.rx or 0, data.ry or 0, data.rz or 0,
        data.heading or 0,
        data.locked and 1 or 0,
        data.distance or Config.DefaultDistance,
        data.marker_enabled ~= false and 1 or 0,
        data.active ~= false and 1 or 0,
        data.ace_permission,
        data.double_group,
        data.created_by
    })
end

function MZDoorsDB.updateLock(id, locked)
    MySQL.update.await('UPDATE mz_world_doors SET locked = ? WHERE id = ?', { locked and 1 or 0, id })
end

function MZDoorsDB.updateLockByGroup(group, locked)
    MySQL.update.await('UPDATE mz_world_doors SET locked = ? WHERE double_group = ?', { locked and 1 or 0, group })
end

function MZDoorsDB.rename(id, name)
    MySQL.update.await('UPDATE mz_world_doors SET name = ? WHERE id = ?', { name, id })
end

function MZDoorsDB.setPermission(id, ace)
    MySQL.update.await('UPDATE mz_world_doors SET ace_permission = ? WHERE id = ?', { ace ~= '' and ace or nil, id })
end

function MZDoorsDB.setDistance(id, distance)
    MySQL.update.await('UPDATE mz_world_doors SET distance = ? WHERE id = ?', { distance, id })
end

function MZDoorsDB.setGroup(id, group)
    MySQL.update.await('UPDATE mz_world_doors SET double_group = ? WHERE id = ?', { group ~= '' and group or nil, id })
end

function MZDoorsDB.setInteraction(id, coords)
    MySQL.update.await([[
        UPDATE mz_world_doors
        SET interaction_x = ?, interaction_y = ?, interaction_z = ?
        WHERE id = ?
    ]], { coords and coords.x or nil, coords and coords.y or nil, coords and coords.z or nil, id })
end

function MZDoorsDB.delete(id)
    MySQL.update.await('DELETE FROM mz_world_doors WHERE id = ?', { id })
end
