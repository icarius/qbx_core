local defaultSpawn = require 'config.shared'.defaultSpawn
local characterDataTables = require 'config.server'.characterDataTables

local function createUsersTable()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `users` (
            `userId` int UNSIGNED NOT NULL AUTO_INCREMENT,
            `username` varchar(255) DEFAULT NULL,
            `license` varchar(50) DEFAULT NULL,
            `license2` varchar(50) DEFAULT NULL,
            `fivem` varchar(20) DEFAULT NULL,
            `discord` varchar(30) DEFAULT NULL,
            PRIMARY KEY (`userId`)
        ) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    -- fetchUserByIdentifier resolves a connecting player against these columns.
    -- Without indexes that is a full scan of `users`, which grows for every player
    -- that ever joined and turns the connect deferral into a 1s+ stall. Created
    -- idempotently so existing databases pick them up on resource start.
    MySQL.query('CREATE INDEX IF NOT EXISTS `idx_users_license` ON `users` (`license`)')
    MySQL.query('CREATE INDEX IF NOT EXISTS `idx_users_license2` ON `users` (`license2`)')
    MySQL.query('CREATE INDEX IF NOT EXISTS `idx_users_fivem` ON `users` (`fivem`)')
    MySQL.query('CREATE INDEX IF NOT EXISTS `idx_users_discord` ON `users` (`discord`)')
end

--- `money` is stored as a JSON blob (`{"cash":500,"bank":5000,"crypto":0}`) even though every
--- entry is a plain typed number — a crash mid-write can corrupt the whole blob (all account
--- types at once, not just the one being changed), and there's no way to query balances
--- (e.g. "top 10 richest players") without parsing every row's JSON (see qbx_core issue #741).
---
--- Unlike position, account types are server-configurable (config.money.moneyTypes) rather
--- than a fixed set of fields, so this can't be fixed columns — it needs an actual
--- (citizenid, account_type) row-per-type table, same shape as the existing player_groups
--- table. Schema only; safe to run on every resource start (no data scan).
local function ensureAccountsTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `character_accounts` (
            `citizenid` VARCHAR(50) NOT NULL,
            `account_type` VARCHAR(50) NOT NULL,
            `balance` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`citizenid`, `account_type`),
            CONSTRAINT `fk_character_accounts_citizenid` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])
end

--- `position` is stored as a JSON blob (`{"x":...,"y":...,"z":...,"w":...}`) even though it's
--- always exactly 4 floats — every save/load round-trips through json.encode/decode for no
--- benefit (see qbx_core issue #741). Four real FLOAT columns are cheaper to write, cheaper to
--- read, and open the door to spatial queries later without changing anything Lua-side:
--- `upsertPlayerEntity`'s `request.position` in and `fetchPlayerEntity`'s `.position` out are
--- still plain vec4s either way.
---
--- The legacy `position` JSON column is kept and still written for one migration window
--- (anything reading `players.position` directly via raw SQL outside this file still works);
--- reads prefer the float columns and only fall back to parsing the JSON blob when they're
--- NULL (a row that predates this migration and hasn't been backfilled yet). Idempotent: safe
--- to run on every resource start.
local function ensurePositionColumns()
    -- Awaited (unlike ensureGeneratedColumns below): the UPDATE below depends on these columns
    -- existing, and convertPositionRow's NULL-check depends on the backfill having actually
    -- landed before any player can connect and save — a fire-and-forget MySQL.query() here
    -- would race a fast-reconnecting player against the ALTER/UPDATE still running in the
    -- background.
    MySQL.query.await([[
        ALTER TABLE `players`
        ADD COLUMN IF NOT EXISTS `pos_x` FLOAT DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `pos_y` FLOAT DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `pos_z` FLOAT DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `pos_heading` FLOAT DEFAULT NULL;
    ]])

    MySQL.query.await([[
        UPDATE `players`
        SET pos_x = JSON_VALUE(position, '$.x'),
            pos_y = JSON_VALUE(position, '$.y'),
            pos_z = JSON_VALUE(position, '$.z'),
            pos_heading = JSON_VALUE(position, '$.w')
        WHERE pos_x IS NULL AND position IS NOT NULL;
    ]])
end

--- `job`, `gang`, and `metadata` are stored as JSON in TEXT columns, so any filter on them
--- (searchPlayerEntities, fetchIsUnique) forces a full table scan with per-row JSON parsing.
--- Generated STORED columns materialize the specific paths that are actually queried, so a
--- normal index can cover them instead. Idempotent: safe to run on every resource start.
---
--- `account_number`/`phone` used to be generated columns here too (materializing
--- `charinfo.$.account`/`charinfo.$.phone`) — moved to ensureCharinfoColumns below, which turns
--- them into real writable columns instead of ones computed from the JSON blob, now that
--- charinfo itself is normalized (see qbx_core issue #741).
local function ensureGeneratedColumns()
    MySQL.query([[
        ALTER TABLE `players`
        ADD COLUMN IF NOT EXISTS `job_name` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(job, '$.name')) STORED,
        ADD COLUMN IF NOT EXISTS `gang_name` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(gang, '$.name')) STORED,
        ADD COLUMN IF NOT EXISTS `fingerprint` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(metadata, '$.fingerprint')) STORED,
        ADD COLUMN IF NOT EXISTS `wallet_id` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(metadata, '$.walletid')) STORED,
        ADD COLUMN IF NOT EXISTS `phone_serial` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(metadata, '$.phonedata.SerialNumber')) STORED;
    ]])

    MySQL.query("CREATE INDEX IF NOT EXISTS `idx_players_job_name` ON `players` (`job_name`)")
    MySQL.query("CREATE INDEX IF NOT EXISTS `idx_players_gang_name` ON `players` (`gang_name`)")
    MySQL.query("CREATE INDEX IF NOT EXISTS `idx_players_fingerprint` ON `players` (`fingerprint`)")
    MySQL.query("CREATE INDEX IF NOT EXISTS `idx_players_wallet_id` ON `players` (`wallet_id`)")
    MySQL.query("CREATE INDEX IF NOT EXISTS `idx_players_phone_serial` ON `players` (`phone_serial`)")

    -- fetchGroupMembers looks players up by (group, type), which isn't a prefix of
    -- player_groups' PK (citizenid, type, group), so it was a full table scan.
    MySQL.query("CREATE INDEX IF NOT EXISTS `idx_player_groups_group_type` ON `player_groups` (`group`, `type`)")
end

--- `players.job`/`players.gang` are JSON blobs, but CheckPlayerData (server/player.lua) only
--- ever reads `.name` and `.grade.level` out of them — every other field (label, payment,
--- onduty, isboss, bankAuth) is rebuilt fresh from GetJob()/GetGang() on every load regardless
--- of what was stored. That means the blobs are redundant with player_groups, which already
--- tracks (citizenid, type, group, grade) for every job/gang a player holds (qbx_core issue
--- #741) — they just don't distinguish which membership is the *primary* (active) one.
---
--- `is_primary` closes that gap. 'unemployed'/'none' (the defaults) intentionally never get a
--- player_groups row at all (AddPlayerToJob/AddPlayerToGang already refuse to add players to
--- them), so a citizenid with no is_primary row for a type just means "on the default" — same
--- meaning as "not migrated yet", so both cases can share one fallback (see convertGroupRow).
--- Schema only; safe to run on every resource start (no data scan).
local function ensurePrimaryGroupColumn()
    MySQL.query.await('ALTER TABLE `player_groups` ADD COLUMN IF NOT EXISTS `is_primary` BOOLEAN NOT NULL DEFAULT FALSE')
    MySQL.query("CREATE INDEX IF NOT EXISTS `idx_player_groups_primary` ON `player_groups` (`citizenid`, `type`, `is_primary`)")
end

--- `charinfo` is stored as a JSON blob for 9 plain typed fields (firstname, lastname,
--- birthdate, nationality, gender, backstory, phone, account, card) — same problem as
--- position/money: every load parses the whole blob, and phone/account uniqueness could only
--- ever be checked at the app layer (see qbx_core issue #741). Fixed set of fields like
--- position (account types aren't configurable here, unlike money), so real typed columns.
---
--- `phone`/`account_number` reuse the exact names the old generated columns had (see
--- ensureGeneratedColumns above) — searchPlayerEntities/fetchIsUnique already reference those
--- names, so they need zero changes once these become real columns instead of computed ones.
--- A generated column can't just become a regular one in place, so this drops and re-adds them.
---
--- Not UNIQUE despite phone/account conceptually being so: a live database could already have
--- duplicates the old app-only uniqueness check let through (or predating it entirely), and
--- ADD UNIQUE INDEX hard-fails the whole migration if even one duplicate exists. Once you've
--- confirmed there are none (`SELECT phone, COUNT(*) FROM players GROUP BY phone HAVING
--- COUNT(*) > 1`), add the constraint yourself — safer than this migration silently either
--- skipping it or bricking startup for anyone who does have duplicates.
---
--- `cid` isn't included here — `players.cid` has been its own real column all along; charinfo's
--- `.cid` field is a redundant copy player.lua already keeps in sync (see normalizeCids), so
--- convertCharinfoRow below reads it from the real column instead of re-deriving it here too.
local function ensureCharinfoColumns()
    MySQL.query.await('DROP INDEX IF EXISTS `idx_players_account_number` ON `players`')
    MySQL.query.await('DROP INDEX IF EXISTS `idx_players_phone` ON `players`')
    MySQL.query.await('ALTER TABLE `players` DROP COLUMN IF EXISTS `account_number`, DROP COLUMN IF EXISTS `phone`')

    MySQL.query.await([[
        ALTER TABLE `players`
        ADD COLUMN IF NOT EXISTS `first_name` VARCHAR(50) DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `last_name` VARCHAR(50) DEFAULT NULL,
        -- 50, not a tighter date-shaped size: sanitizeNewCharInfo (server/character.lua)
        -- validates birthdate as free text up to 50 chars, not a real date format — matching
        -- that ceiling avoids silently truncating anything that passed validation.
        ADD COLUMN IF NOT EXISTS `birthdate` VARCHAR(50) DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `nationality` VARCHAR(50) DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `gender` TINYINT UNSIGNED DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `backstory` TEXT DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `phone` VARCHAR(50) DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `account_number` VARCHAR(50) DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `card_number` BIGINT DEFAULT NULL;
    ]])

    MySQL.query.await([[
        UPDATE `players`
        SET first_name = JSON_VALUE(charinfo, '$.firstname'),
            last_name = JSON_VALUE(charinfo, '$.lastname'),
            birthdate = JSON_VALUE(charinfo, '$.birthdate'),
            nationality = JSON_VALUE(charinfo, '$.nationality'),
            gender = JSON_VALUE(charinfo, '$.gender'),
            backstory = JSON_VALUE(charinfo, '$.backstory'),
            phone = JSON_VALUE(charinfo, '$.phone'),
            account_number = JSON_VALUE(charinfo, '$.account'),
            card_number = JSON_VALUE(charinfo, '$.card')
        WHERE first_name IS NULL AND charinfo IS NOT NULL;
    ]])

    MySQL.query("CREATE INDEX IF NOT EXISTS `idx_players_phone` ON `players` (`phone`)")
    MySQL.query("CREATE INDEX IF NOT EXISTS `idx_players_account_number` ON `players` (`account_number`)")
    MySQL.query("CREATE INDEX IF NOT EXISTS `idx_players_name` ON `players` (`last_name`, `first_name`)")
end

--- `metadata` is a 20+ field JSON blob, and unlike position/charinfo it's explicitly
--- open-ended — third-party resources can (and do) stuff arbitrary custom keys into it via
--- SetMetadata, so it can't be fully normalized into fixed columns the way charinfo was
--- (qbx_core issue #741 acknowledges this itself: "the truly variable/schemaless remainder...
--- should stay JSON").
---
--- Scoped deliberately to just the 7 fields that change on *every* Save() (server/player.lua:
--- health/armor from GetEntityHealth/GetPedArmour, hunger/thirst/stress while logged in) plus
--- isdead/injail — the highest-churn, most crash-exposed part of the blob. The 13+ other
--- fields (jailitems, status, phone{background,profilepicture}, bloodtype, callsign,
--- dealerrep/craftingrep, jobrep, criminalrecord, licences, inside, phonedata, and anything a
--- third-party resource adds) stay in the JSON blob — normalizing those properly means separate
--- tables (criminal_records, character_licences, ...), a bigger job than this pass.
---
--- Unlike position/charinfo, reads are NOT changed to prefer these columns — `metadata` is
--- still decoded whole on every fetch either way (needed regardless, for the 13+ fields that
--- aren't extracted), so there's no read-side win to claim here. What these columns buy: a
--- crash mid-write to the metadata blob can no longer corrupt health/hunger/thirst/etc (they
--- also land safely in their own columns in the same write), and they're queryable/indexable
--- for admin tooling without per-row JSON parsing. Schema only; safe to run on every resource
--- start (no data scan of its own — the backfill below only touches unmigrated rows).
local function ensureMetadataColumns()
    MySQL.query.await([[
        ALTER TABLE `players`
        ADD COLUMN IF NOT EXISTS `health` SMALLINT UNSIGNED DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `armor` SMALLINT UNSIGNED DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `hunger` DECIMAL(5,2) DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `thirst` DECIMAL(5,2) DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `stress` DECIMAL(5,2) DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `isdead` BOOLEAN DEFAULT NULL,
        ADD COLUMN IF NOT EXISTS `injail` INT DEFAULT NULL;
    ]])

    MySQL.query.await([[
        UPDATE `players`
        SET health = JSON_VALUE(metadata, '$.health'),
            armor = JSON_VALUE(metadata, '$.armor'),
            hunger = JSON_VALUE(metadata, '$.hunger'),
            thirst = JSON_VALUE(metadata, '$.thirst'),
            stress = JSON_VALUE(metadata, '$.stress'),
            -- JSON_VALUE always returns text, and Lua's json.encode(true) turns out to encode
            -- as the JSON number `1` (confirmed by testing, not `true`) — either way, a plain
            -- string-to-number cast on whatever comes back is not safe to rely on, so compare
            -- against both encodings explicitly rather than assume one.
            isdead = (JSON_VALUE(metadata, '$.isdead') IN ('1', 'true')),
            injail = JSON_VALUE(metadata, '$.injail')
        WHERE health IS NULL AND metadata IS NOT NULL;
    ]])
end

---@param identifiers table<PlayerIdentifier, string>
---@return number?
local function createUser(identifiers)
    return MySQL.insert.await('INSERT INTO users (username, license, license2, fivem, discord) VALUES (?, ?, ?, ?, ?)', {
        identifiers.username,
        identifiers.license,
        identifiers.license2,
        identifiers.fivem,
        identifiers.discord,
    })
end

---@param identifier string
---@return integer?
local function fetchUserByIdentifier(identifier)
    local idType = identifier:match('([^:]+)')
    local select = ('SELECT `userId` FROM `users` WHERE `%s` = ? LIMIT 1'):format(idType)

    return MySQL.scalar.await(select, { identifier })
end

---@param request InsertBanRequest
---@return boolean success
---@return ErrorResult? errorResult
local function insertBan(request)
    if not request.discordId and not request.ip and not request.license then
        return false, {
            code = 'no_identifier',
            message = 'discordId, ip, or license required in the ban request'
        }
    end

    MySQL.insert.await('INSERT INTO bans (name, license, discord, ip, reason, expire, bannedby) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        request.name,
        request.license,
        request.discordId,
        request.ip,
        request.reason,
        request.expiration,
        request.bannedBy,
    })
    return true
end

local banColumns = {
    license = 'license',
    discordId = 'discord',
    ip = 'ip',
}

---@param request GetBanRequest | GetBanRequest[]
---@return string clause, string[] values
local function buildBanFilter(request)
    local requests = request[1] and request or { request }
    local clauses = {}
    local values = {}
    for i = 1, #requests do
        for key, column in pairs(banColumns) do
            local value = requests[i][key]
            if value then
                clauses[#clauses + 1] = column .. ' = ?'
                values[#values + 1] = value
            end
        end
    end
    return table.concat(clauses, ' OR '), values
end

---@param request GetBanRequest | GetBanRequest[]
---@return BanEntity?
local function fetchBan(request)
    local clause, values = buildBanFilter(request)
    if clause == '' then return nil end
    local result = MySQL.single.await('SELECT expire, reason FROM bans WHERE ' .. clause .. ' ORDER BY expire DESC', values)
    return result and {
        expire = result.expire,
        reason = result.reason,
    } or nil
end

---@param request GetBanRequest | GetBanRequest[]
local function deleteBan(request)
    local clause, values = buildBanFilter(request)
    if clause == '' then return end
    MySQL.query.await('DELETE FROM bans WHERE ' .. clause, values)
end

---Writes every account balance for a player in a single multi-row upsert — one round trip
---regardless of how many money types are configured, same cost as the single JSON write it
---replaces (see ensureAccountsTable's header for why this can't be fixed columns).
---@param citizenid string
---@param money table<string, number>
local function upsertAccounts(citizenid, money)
    local placeholders = {}
    local values = {}
    for accountType, balance in pairs(money) do
        placeholders[#placeholders + 1] = '(?, ?, ?)'
        values[#values + 1] = citizenid
        values[#values + 1] = accountType
        values[#values + 1] = balance
    end

    if #placeholders == 0 then return end

    MySQL.query.await(
        ('INSERT INTO character_accounts (citizenid, account_type, balance) VALUES %s ON DUPLICATE KEY UPDATE balance = VALUES(balance)'):format(table.concat(placeholders, ', ')),
        values
    )
end

local defaultGroupName = {
    job = 'unemployed',
    gang = 'none',
}

---Marks (citizenid, groupType, groupName) as the one primary membership in player_groups,
---demoting any other membership of the same type for that player. `unemployed`/`none` never
---get a row (see ensurePrimaryGroupColumn) — demoting everything else is enough to represent
---"back on the default".
---@param citizenid string
---@param groupType GroupType
---@param groupName string
---@param grade integer
local function upsertPrimaryGroup(citizenid, groupType, groupName, grade)
    if groupName == defaultGroupName[groupType] then
        MySQL.query.await('UPDATE player_groups SET is_primary = 0 WHERE citizenid = ? AND type = ?', { citizenid, groupType })
        return
    end

    MySQL.query.await(
        'INSERT INTO player_groups (citizenid, type, `group`, grade, is_primary) VALUES (?, ?, ?, ?, 1) ON DUPLICATE KEY UPDATE grade = VALUES(grade), is_primary = 1',
        { citizenid, groupType, groupName, grade }
    )
    MySQL.query.await('UPDATE player_groups SET is_primary = 0 WHERE citizenid = ? AND type = ? AND `group` != ?', { citizenid, groupType, groupName })
end

---@param request UpsertPlayerRequest
local function upsertPlayerEntity(request)
    local pos = request.position
    local charinfo = request.playerEntity.charinfo
    local params = {
        userId = request.playerEntity.userId,
        citizenid = request.playerEntity.citizenid,
        cid = charinfo.cid,
        license = request.playerEntity.license,
        name = request.playerEntity.name,
        money = json.encode(request.playerEntity.money),
        -- Legacy JSON blob, kept alongside the typed columns below during the migration
        -- window (see ensureCharinfoColumns) — covers anything outside this file still
        -- reading `players.charinfo` directly via raw SQL.
        charinfo = json.encode(charinfo),
        first_name = charinfo.firstname,
        last_name = charinfo.lastname,
        birthdate = charinfo.birthdate,
        nationality = charinfo.nationality,
        gender = charinfo.gender,
        backstory = charinfo.backstory,
        phone = charinfo.phone,
        account_number = charinfo.account,
        card_number = charinfo.card,
        job = json.encode(request.playerEntity.job),
        gang = json.encode(request.playerEntity.gang),
        -- Legacy JSON blob, kept alongside the typed columns below during the migration
        -- window (see ensurePositionColumns) — cheap to keep writing, and covers anything
        -- outside this file still reading `players.position` directly via raw SQL.
        position = json.encode(pos),
        pos_x = pos.x,
        pos_y = pos.y,
        pos_z = pos.z,
        pos_heading = pos.w,
        -- Legacy JSON blob, kept and still the sole source for reads (see ensureMetadataColumns
        -- — unlike position/charinfo, metadata stays open-ended so this can't be fully
        -- replaced). The 7 columns below are a write-side safety net + queryability layer for
        -- just the highest-churn fields, not a read path.
        metadata = json.encode(request.playerEntity.metadata),
        health = request.playerEntity.metadata.health,
        armor = request.playerEntity.metadata.armor,
        hunger = request.playerEntity.metadata.hunger,
        thirst = request.playerEntity.metadata.thirst,
        stress = request.playerEntity.metadata.stress,
        isdead = request.playerEntity.metadata.isdead or false,
        injail = request.playerEntity.metadata.injail,
        last_logged_out = os.date('%Y-%m-%d %H:%M:%S', request.playerEntity.lastLoggedOut)
    }

    -- Existence is checked explicitly rather than relying on `INSERT ... ON DUPLICATE KEY UPDATE`,
    -- which burns an AUTO_INCREMENT value on `players.id` for every save, not just new characters.
    local exists = MySQL.scalar.await('SELECT 1 FROM players WHERE citizenid = ?', { params.citizenid })

    if exists then
        MySQL.update.await('UPDATE players SET userId = :userId, name = :name, money = :money, charinfo = :charinfo, first_name = :first_name, last_name = :last_name, birthdate = :birthdate, nationality = :nationality, gender = :gender, backstory = :backstory, phone = :phone, account_number = :account_number, card_number = :card_number, job = :job, gang = :gang, position = :position, pos_x = :pos_x, pos_y = :pos_y, pos_z = :pos_z, pos_heading = :pos_heading, metadata = :metadata, health = :health, armor = :armor, hunger = :hunger, thirst = :thirst, stress = :stress, isdead = :isdead, injail = :injail, last_logged_out = :last_logged_out WHERE citizenid = :citizenid', params)
    else
        -- character_accounts has a FK on citizenid — the players row has to exist first, so
        -- upsertAccounts below always runs after this branch either way.
        MySQL.insert.await('INSERT INTO players (userId, citizenid, cid, license, name, money, charinfo, first_name, last_name, birthdate, nationality, gender, backstory, phone, account_number, card_number, job, gang, position, pos_x, pos_y, pos_z, pos_heading, metadata, health, armor, hunger, thirst, stress, isdead, injail, last_logged_out) VALUES (:userId, :citizenid, :cid, :license, :name, :money, :charinfo, :first_name, :last_name, :birthdate, :nationality, :gender, :backstory, :phone, :account_number, :card_number, :job, :gang, :position, :pos_x, :pos_y, :pos_z, :pos_heading, :metadata, :health, :armor, :hunger, :thirst, :stress, :isdead, :injail, :last_logged_out)', params)
    end

    -- Legacy `money` JSON column (in `params`, above) kept alongside the typed table during
    -- the migration window — same reasoning as `position`.
    upsertAccounts(params.citizenid, request.playerEntity.money)

    -- Legacy `job`/`gang` JSON columns (in `params`, above) kept alongside player_groups
    -- during the migration window — same reasoning as `position`/`money`.
    local job = request.playerEntity.job
    if job then
        upsertPrimaryGroup(params.citizenid, GroupType.JOB, job.name, job.grade.level)
    end
    local gang = request.playerEntity.gang
    if gang then
        upsertPrimaryGroup(params.citizenid, GroupType.GANG, gang.name, gang.grade.level)
    end
end

---@param citizenId string
---@return PlayerSkin?
local function fetchPlayerSkin(citizenId)
    return MySQL.single.await('SELECT * FROM playerskins WHERE citizenid = ? AND active = 1', {citizenId})
end

local function convertPosition(position)
    local pos = position and json.decode(position)
    local actualPos = (not pos or not pos.x or not pos.y or not pos.z) and defaultSpawn or pos
    return vec4(actualPos.x, actualPos.y, actualPos.z, actualPos.w or defaultSpawn.w)
end

---Prefers the typed pos_x/pos_y/pos_z/pos_heading columns; falls back to parsing the legacy
---JSON `position` blob only for a row that hasn't been backfilled yet (see ensurePositionColumns
---— pos_x is NULL until that migration touches the row).
---@param row { position: string?, pos_x: number?, pos_y: number?, pos_z: number?, pos_heading: number? }
local function convertPositionRow(row)
    if row.pos_x == nil then
        return convertPosition(row.position)
    end
    return vec4(row.pos_x, row.pos_y, row.pos_z, row.pos_heading or defaultSpawn.w)
end

-- Fetch queries below add a correlated subquery aggregating `character_accounts` into a JSON
-- object in the same round trip (`JSON_OBJECTAGG(account_type, balance)`), rather than a
-- second SELECT — see ensureAccountsTable's header for why. `accountsMoney` is NULL for a
-- citizenid with no rows there yet (not backfilled, or a save that predates this migration);
-- that's the same "not migrated" signal position's pos_x NULL check uses.
---@param accountsMoney string? JSON_OBJECTAGG result
---@param legacyMoney string legacy `money` JSON column, always present
---@return table<string, number>
local function convertMoneyRow(accountsMoney, legacyMoney)
    if accountsMoney then
        return json.decode(accountsMoney)
    end
    return json.decode(legacyMoney)
end

---Prefers the typed first_name/last_name/birthdate/nationality/gender/backstory/phone/
---account_number/card_number columns; falls back to parsing the legacy JSON `charinfo` blob
---only for a row that hasn't been backfilled yet (see ensureCharinfoColumns — first_name is
---NULL until that migration touches the row).
---
---`.cid` always comes from the real `players.cid` column rather than either charinfo shape —
---see ensureCharinfoColumns' header for why it's not duplicated as a typed column too.
---@param row table
---@return PlayerCharInfo
local function convertCharinfoRow(row)
    local charinfo
    if row.first_name == nil then
        charinfo = json.decode(row.charinfo)
    else
        charinfo = {
            firstname = row.first_name,
            lastname = row.last_name,
            birthdate = row.birthdate,
            nationality = row.nationality,
            gender = row.gender,
            backstory = row.backstory,
            phone = row.phone,
            account = row.account_number,
            card = row.card_number,
        }
    end
    charinfo.cid = row.cid
    return charinfo
end

local groupGetter = {
    [GroupType.JOB] = GetJob,
    [GroupType.GANG] = GetGang,
}

---Rebuilds the minimal shape CheckPlayerData (server/player.lua) and the character-select
---screen (client/character.lua) actually read off a fetched entity — `.name`, `.label`,
---`.grade.level`, `.grade.name`. Every other PlayerJob/PlayerGang field (payment, onduty,
---isboss, bankAuth, type) is rebuilt fresh from GetJob()/GetGang() by CheckPlayerData on every
---load regardless of what's stored, so there's nothing else worth persisting or reconstructing
---here.
---@param name string
---@param grade integer
---@param groupType GroupType
local function toMinimalGroup(name, grade, groupType)
    local def = groupGetter[groupType](name)
    return {
        name = name,
        label = def and def.label or name,
        grade = {
            level = grade,
            name = def and def.grades[grade] and def.grades[grade].name or tostring(grade),
        },
    }
end

---Prefers the primary player_groups row (aggregated as JSON_OBJECT('group', ..., 'grade', ...)
---by the fetch queries below); falls back to the legacy JSON `job`/`gang` blob when there isn't
---one — which covers both "still on the default job/gang" and "row predates this migration"
---(see ensurePrimaryGroupColumn's header for why those share one fallback).
---@param primaryJson string? JSON_OBJECT result from the fetch query
---@param legacyJson string? legacy `job`/`gang` column
---@param groupType GroupType
local function convertGroupRow(primaryJson, legacyJson, groupType)
    if primaryJson then
        local primary = json.decode(primaryJson)
        return toMinimalGroup(primary.group, primary.grade, groupType)
    end
    return legacyJson and json.decode(legacyJson) or nil
end

---@param license2 string
---@param license? string
---@return PlayerEntity[]
local function fetchAllPlayerEntities(license2, license)
    ---@type PlayerEntity[]
    local chars = {}
    ---@type PlayerEntityDatabase[]
    local result = MySQL.query.await([[
        SELECT citizenid, cid, charinfo, first_name, last_name, birthdate, nationality, gender, backstory, phone, account_number, card_number, money,
            (SELECT JSON_OBJECTAGG(account_type, balance) FROM character_accounts WHERE character_accounts.citizenid = players.citizenid) AS accountsMoney,
            job, gang,
            (SELECT JSON_OBJECT('group', `group`, 'grade', grade) FROM player_groups WHERE player_groups.citizenid = players.citizenid AND type = 'job' AND is_primary = 1 LIMIT 1) AS primaryJob,
            (SELECT JSON_OBJECT('group', `group`, 'grade', grade) FROM player_groups WHERE player_groups.citizenid = players.citizenid AND type = 'gang' AND is_primary = 1 LIMIT 1) AS primaryGang,
            position, pos_x, pos_y, pos_z, pos_heading, metadata, UNIX_TIMESTAMP(last_logged_out) AS lastLoggedOutUnix
        FROM players WHERE license = ? OR license = ? ORDER BY cid
    ]], {license, license2})
    for i = 1, #result do
        chars[i] = result[i]
        chars[i].charinfo = convertCharinfoRow(result[i])
        chars[i].money = convertMoneyRow(result[i].accountsMoney, result[i].money)
        chars[i].job = convertGroupRow(result[i].primaryJob, result[i].job, GroupType.JOB)
        chars[i].gang = convertGroupRow(result[i].primaryGang, result[i].gang, GroupType.GANG)
        chars[i].position = convertPositionRow(result[i])
        chars[i].metadata = json.decode(result[i].metadata)
        chars[i].lastLoggedOut = result[i].lastLoggedOutUnix
    end

    return chars
end

--- Heals accounts whose cids aren't a clean 1..N sequence (duplicates or gaps
--- left by the pre-fix createCharacter bug, or by deleted characters). Slots
--- are reassigned in creation order (`id`) so a character keeps its slot
--- across logins instead of shuffling, and only rows that actually change are
--- written.
---@param license2 string
---@param license? string
local function normalizeCids(license2, license)
    ---@type { id: integer, citizenid: string, cid: integer, charinfo: string }[]
    local rows = MySQL.query.await('SELECT id, citizenid, cid, charinfo FROM players WHERE license = ? OR license = ? ORDER BY id', {license, license2})

    local updates = {}
    for i = 1, #rows do
        if rows[i].cid ~= i then
            local charinfo = json.decode(rows[i].charinfo)
            charinfo.cid = i
            updates[#updates + 1] = {
                query = 'UPDATE players SET cid = ?, charinfo = ? WHERE citizenid = ?',
                values = { i, json.encode(charinfo), rows[i].citizenid }
            }
        end
    end

    if #updates > 0 then
        MySQL.transaction.await(updates)
    end
end

---@param citizenId string
---@return PlayerEntity?
local function fetchPlayerEntity(citizenId)
    ---@type PlayerEntityDatabase
    local player = MySQL.single.await([[
        SELECT userId, citizenid, cid, license, name, charinfo, first_name, last_name, birthdate, nationality, gender, backstory, phone, account_number, card_number, money,
            (SELECT JSON_OBJECTAGG(account_type, balance) FROM character_accounts WHERE character_accounts.citizenid = players.citizenid) AS accountsMoney,
            job, gang,
            (SELECT JSON_OBJECT('group', `group`, 'grade', grade) FROM player_groups WHERE player_groups.citizenid = players.citizenid AND type = 'job' AND is_primary = 1 LIMIT 1) AS primaryJob,
            (SELECT JSON_OBJECT('group', `group`, 'grade', grade) FROM player_groups WHERE player_groups.citizenid = players.citizenid AND type = 'gang' AND is_primary = 1 LIMIT 1) AS primaryGang,
            position, pos_x, pos_y, pos_z, pos_heading, metadata, UNIX_TIMESTAMP(last_logged_out) AS lastLoggedOutUnix
        FROM players WHERE citizenid = ?
    ]], { citizenId })
    local charinfo = player and convertCharinfoRow(player)
    return player and {
        userId = player.userId,
        citizenid = player.citizenid,
        license = player.license,
        name = player.name,
        money = convertMoneyRow(player.accountsMoney, player.money),
        charinfo = charinfo,
        cid = charinfo and charinfo.cid,
        job = convertGroupRow(player.primaryJob, player.job, GroupType.JOB),
        gang = convertGroupRow(player.primaryGang, player.gang, GroupType.GANG),
        position = convertPositionRow(player),
        metadata = json.decode(player.metadata),
        lastLoggedOut = player.lastLoggedOutUnix
    } or nil
end

local charinfoColumns = {
    firstname = 'first_name',
    lastname = 'last_name',
    birthdate = 'birthdate',
    nationality = 'nationality',
    gender = 'gender',
    backstory = 'backstory',
    phone = 'phone',
    account = 'account_number',
}

---@param filters table<string, any>
local function handleSearchFilters(filters)
    if not (filters) then return '', {} end
    local holders = {}
    local clauses = {}
    if filters.license then
        clauses[#clauses + 1] = 'license = ?'
        holders[#holders + 1] = filters.license
    end
    if filters.job then
        -- Indexed generated column (see ensureGeneratedColumns) instead of JSON_EXTRACT,
        -- which forced a full table scan with per-row JSON parsing.
        clauses[#clauses + 1] = 'job_name = ?'
        holders[#holders + 1] = filters.job
    end
    if filters.gang then
        clauses[#clauses + 1] = 'gang_name = ?'
        holders[#holders + 1] = filters.gang
    end
    if filters.charinfo then
        -- Indexed typed columns (see ensureCharinfoColumns) instead of JSON_EXTRACT for the
        -- known charinfo fields — full-table-scan-with-per-row-JSON-parsing otherwise. `card`
        -- isn't mapped (no column: it's a deprecated field, see player.lua's SetCardNumber) and
        -- still falls back to JSON_EXTRACT against the legacy blob, same as any future key that
        -- doesn't have a typed column yet.
        for key, value in pairs(filters.charinfo) do
            local column = charinfoColumns[key]
            if column then
                clauses[#clauses + 1] = column .. ' = ?'
                holders[#holders + 1] = value
            elseif type(value) == "number" then
                clauses[#clauses + 1] = 'JSON_EXTRACT(charinfo, ?) = ?'
                holders[#holders + 1] = '$.' .. key
                holders[#holders + 1] = value
            elseif type(value) == "string" then
                clauses[#clauses + 1] = 'JSON_UNQUOTE(JSON_EXTRACT(charinfo, ?)) = ?'
                holders[#holders + 1] = '$.' .. key
                holders[#holders + 1] = value
            end
        end
    end
    if filters.metadata then
        local strict = filters.metadata.strict
        for key, value in pairs(filters.metadata) do
            if key ~= "strict" then
                if type(value) == "number" then
                    if strict then
                        clauses[#clauses + 1] = 'JSON_EXTRACT(metadata, ?) = ?'
                    else
                        clauses[#clauses + 1] = 'JSON_EXTRACT(metadata, ?) >= ?'
                    end
                    holders[#holders + 1] = '$.' .. key
                    holders[#holders + 1] = value
                elseif type(value) == "boolean" then
                    clauses[#clauses + 1] = 'JSON_EXTRACT(metadata, ?) = ?'
                    holders[#holders + 1] = '$.' .. key
                    holders[#holders + 1] = tostring(value)
                elseif type(value) == "string" then
                    clauses[#clauses + 1] = 'JSON_UNQUOTE(JSON_EXTRACT(metadata, ?)) = ?'
                    holders[#holders + 1] = '$.' .. key
                    holders[#holders + 1] = value
                end
            end
        end
    end
    return (' WHERE %s'):format(table.concat(clauses, ' AND ')), holders
end

---@param filters table <string, any>
---@return PlayerEntityDatabase[]
local function searchPlayerEntities(filters)
    local query = "SELECT citizenid FROM players"
    local where, holders = handleSearchFilters(filters)
    lib.print.debug(query .. where)
    ---@type PlayerEntityDatabase[]
    local response = MySQL.query.await(query .. where, holders)
    return response
end

---Checks if a table exists in the database
---@param tableName string
---@return boolean
local function doesTableExist(tableName)
    -- Aliased explicitly (unlike relying on the engine's default column name for a bare
    -- COUNT(*)): MySQL/MariaDB name that column literally `COUNT(*)`, but Postgres names it
    -- `count` — an unaliased query is not portable between the two.
    local tbl = MySQL.single.await(('SELECT COUNT(*) as count FROM information_schema.TABLES WHERE TABLE_NAME = \'%s\' AND TABLE_SCHEMA in (SELECT DATABASE())'):format(tableName))
    return tbl.count > 0
end

---deletes character data using the characterDataTables object in the config file
---@param citizenId string
---@return boolean success if operation is successful.
local function deletePlayer(citizenId)
    local query = 'DELETE FROM %s WHERE %s = ?'
    local queries = {}

    for i = 1, #characterDataTables do
        local data = characterDataTables[i]
        local tableName = data[1]
        local columnName = data[2]
        if doesTableExist(tableName) then
            queries[#queries + 1] = {
                query = query:format(tableName, columnName),
                values = {
                    citizenId,
                }
            }
        else
            warn(('Table %s does not exist in database, please remove it from qbx_core/config/server.lua or create the table'):format(tableName))
        end
    end

    local success = MySQL.transaction.await(queries)
    return not not success
end

---checks the storage for uniqueness of the given value
---@param type UniqueIdType
---@param value string|number
---@return boolean isUnique if the value does not already exist in storage for the given type
local function fetchIsUnique(type, value)
    -- Indexed generated columns (see ensureGeneratedColumns) instead of JSON_VALUE(...),
    -- which forced a full table scan with per-row JSON parsing on every retry of every
    -- identifier generated during character creation.
    local typeToColumn = {
        citizenid = 'citizenid',
        AccountNumber = 'account_number',
        PhoneNumber = 'phone',
        FingerId = 'fingerprint',
        WalletId = 'wallet_id',
        SerialNumber = 'phone_serial',
    }

    local result = MySQL.single.await('SELECT COUNT(*) as count FROM players WHERE `' .. typeToColumn[type] .. '` = ?', { value })
    return result.count == 0
end

---@param citizenid string
---@param type GroupType type
---@param group string
---@param grade integer
local function addToGroup(citizenid, type, group, grade)
    MySQL.insert.await('INSERT INTO player_groups (citizenid, type, `group`, grade) VALUES (:citizenid, :type, :group, :grade) ON DUPLICATE KEY UPDATE grade = :grade', {
        citizenid = citizenid,
        type = type,
        group = group,
        grade = grade,
    })
end

---@param citizenid string
---@param group string
---@param grade integer
local function addPlayerToJob(citizenid, group, grade)
    addToGroup(citizenid, GroupType.JOB, group, grade)
end

---@param citizenid string
---@param group string
---@param grade integer
local function addPlayerToGang(citizenid, group, grade)
    addToGroup(citizenid, GroupType.GANG, group, grade)
end

---@param citizenid string
---@return table<string, integer> jobs
---@return table<string, integer> gangs
local function fetchPlayerGroups(citizenid)
    local groups = MySQL.query.await('SELECT `group`, type, grade FROM player_groups WHERE citizenid = ?', {citizenid})
    local jobs = {}
    local gangs = {}
    for i = 1, #groups do
        local group = groups[i]
        local validGroup = group.type == GroupType.JOB and GetJob(group.group) or GetGang(group.group)
        if not validGroup then
            lib.print.warn(('Invalid group %s found in player_groups table, Does it exist in shared/%ss.lua?'):format(group.group, group.type))
        elseif not validGroup.grades?[group.grade] then
            lib.print.warn(('Invalid grade %s found in player_groups table for %s %s, Does it exist in shared/%ss.lua?'):format(group.grade, group.type, group.group, group.type))
        elseif group.type == GroupType.JOB then
            jobs[group.group] = group.grade
        elseif group.type == GroupType.GANG then
            gangs[group.group] = group.grade
        end
    end
    return jobs, gangs
end

---@param group string
---@param type GroupType
---@return table<string, integer> players
local function fetchGroupMembers(group, type)
    return MySQL.query.await("SELECT citizenid, grade FROM player_groups WHERE `group` = ? AND `type` = ?", {group, type})
end

---@param citizenid string
---@param type GroupType
---@param group string
local function removeFromGroup(citizenid, type, group)
    MySQL.query.await('DELETE FROM player_groups WHERE citizenid = ? AND type = ? AND `group` = ?', {citizenid, type, group})
end

---@param citizenid string
---@param group string
local function removePlayerFromJob(citizenid, group)
    removeFromGroup(citizenid, GroupType.JOB, group)
end

---@param citizenid string
---@param group string
local function removePlayerFromGang(citizenid, group)
    removeFromGroup(citizenid, GroupType.GANG, group)
end

---Copies player's primary job/gang to the player_groups table. Works for online/offline players.
---Idempotent
RegisterCommand('convertjobs', function(source)
    if source ~= 0 then return warn('This command can only be executed using the server console.') end

    local players = MySQL.query.await('SELECT citizenid, JSON_VALUE(job, \'$.name\') AS jobName, JSON_VALUE(job, \'$.grade.level\') AS jobGrade, JSON_VALUE(gang, \'$.name\') AS gangName, JSON_VALUE(gang, \'$.grade.level\') AS gangGrade FROM players')
    for i = 1, #players do
        local player = players[i]
        local success, err = pcall(AddPlayerToJob, player.citizenid, player.jobName, tonumber(player.jobGrade))
        if not success then lib.print.error(err) end
        success, err = pcall(AddPlayerToGang, player.citizenid, player.gangName, tonumber(player.gangGrade))
        if not success then lib.print.error(err) end
    end

    lib.print.info('Converted jobs and gangs successfully')
    TriggerEvent('qbx_core:server:jobsconverted')
end, true)

---Copies every player's `money` JSON blob into the character_accounts table. Works for
---online/offline players. Idempotent (ON DUPLICATE KEY UPDATE in upsertAccounts). Not required
---for correctness — fetchPlayerEntity/fetchAllPlayerEntities already fall back to the legacy
---JSON column per-player until each one saves at least once post-upgrade — this just lets an
---admin migrate everyone in one pass instead of waiting on that.
RegisterCommand('convertaccounts', function(source)
    if source ~= 0 then return warn('This command can only be executed using the server console.') end

    local players = MySQL.query.await('SELECT citizenid, money FROM players')
    for i = 1, #players do
        local player = players[i]
        local success, err = pcall(upsertAccounts, player.citizenid, json.decode(player.money))
        if not success then lib.print.error(err) end
    end

    lib.print.info('Converted money to character_accounts successfully')
end, true)

---Removes invalid groups from the player_groups table.
local function cleanPlayerGroups()
    local groups = MySQL.query.await('SELECT DISTINCT `group`, type, grade FROM player_groups')
    for i = 1, #groups do
        local group = groups[i]
        local validGroup = group.type == GroupType.JOB and GetJob(group.group) or GetGang(group.group)
        if not validGroup then
            MySQL.query.await('DELETE FROM player_groups WHERE `group` = ? AND type = ?', {group.group, group.type})
            lib.print.info(('Remove invalid %s %s from player_groups table'):format(group.type, group.group))
        elseif not validGroup.grades?[group.grade] then
            MySQL.query.await('DELETE FROM player_groups WHERE `group` = ? AND type = ? AND grade = ?', {group.group, group.type, group.grade})
            lib.print.info(('Remove invalid %s %s grade %s from player_groups table'):format(group.type, group.group, group.grade))
        end
    end

    lib.print.info('Removed invalid groups from player_groups table')
end

RegisterCommand('cleanplayergroups', function(source)
    if source ~= 0 then return warn('This command can only be executed using the server console.') end
    cleanPlayerGroups()
end, true)

CreateThread(function()
    for _, data in pairs(characterDataTables) do
        local tableName = data[1]
        if not doesTableExist(tableName) then
            warn(('Table \'%s\' does not exist in database, please remove it from qbx_core/config/server.lua or create the table'):format(tableName))
        end
    end
    if GetConvar('qbx:cleanPlayerGroups', 'false') == 'true' then
        cleanPlayerGroups()
    end
end)

return {
    createUsersTable = createUsersTable,
    ensureGeneratedColumns = ensureGeneratedColumns,
    ensurePositionColumns = ensurePositionColumns,
    ensureAccountsTable = ensureAccountsTable,
    ensureCharinfoColumns = ensureCharinfoColumns,
    ensurePrimaryGroupColumn = ensurePrimaryGroupColumn,
    ensureMetadataColumns = ensureMetadataColumns,
    createUser = createUser,
    fetchUserByIdentifier = fetchUserByIdentifier,
    insertBan = insertBan,
    fetchBan = fetchBan,
    deleteBan = deleteBan,
    upsertPlayerEntity = upsertPlayerEntity,
    fetchPlayerSkin = fetchPlayerSkin,
    fetchPlayerEntity = fetchPlayerEntity,
    fetchAllPlayerEntities = fetchAllPlayerEntities,
    normalizeCids = normalizeCids,
    deletePlayer = deletePlayer,
    fetchIsUnique = fetchIsUnique,
    addPlayerToJob = addPlayerToJob,
    addPlayerToGang = addPlayerToGang,
    fetchPlayerGroups = fetchPlayerGroups,
    fetchGroupMembers = fetchGroupMembers,
    removePlayerFromJob = removePlayerFromJob,
    removePlayerFromGang = removePlayerFromGang,
    searchPlayerEntities = searchPlayerEntities,
}