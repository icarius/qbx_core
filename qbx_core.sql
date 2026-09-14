CREATE TABLE IF NOT EXISTS `players` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) NOT NULL,
  `cid` int(11) DEFAULT NULL,
  `license` varchar(255) NOT NULL,
  `name` varchar(255) NOT NULL,
  `money` text NOT NULL,
  `charinfo` text DEFAULT NULL,
  `job` text NOT NULL,
  `gang` text DEFAULT NULL,
  `position` text NOT NULL,
  `metadata` text NOT NULL,
  `inventory` longtext DEFAULT NULL,
  `phone_number` VARCHAR(20) DEFAULT NULL,
  `last_updated` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`citizenid`),
  KEY `id` (`id`),
  KEY `last_updated` (`last_updated`),
  KEY `license` (`license`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `players`
ADD COLUMN IF NOT EXISTS `last_logged_out` timestamp NULL DEFAULT NULL AFTER `last_updated`,
MODIFY COLUMN `name` varchar(255) NOT NULL COLLATE utf8mb4_unicode_ci;

ALTER TABLE `players`
ADD COLUMN IF NOT EXISTS `userId` INT UNSIGNED DEFAULT NULL AFTER `id`;

-- Generated columns materializing the JSON paths that are actually queried (job/gang name,
-- account/phone/fingerprint/wallet/serial identifiers), so searchPlayerEntities and
-- fetchIsUnique can use a normal index instead of a full-table scan with per-row JSON parsing.
-- Applied idempotently at resource start too (server/storage/players.lua ensureGeneratedColumns),
-- this copy just keeps a fresh install's schema in sync.
-- account_number/phone used to be generated here too — moved below (ensureCharinfoColumns
-- mirror), now that charinfo itself is normalized and they're real writable columns instead.
ALTER TABLE `players`
ADD COLUMN IF NOT EXISTS `job_name` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(job, '$.name')) STORED,
ADD COLUMN IF NOT EXISTS `gang_name` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(gang, '$.name')) STORED,
ADD COLUMN IF NOT EXISTS `fingerprint` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(metadata, '$.fingerprint')) STORED,
ADD COLUMN IF NOT EXISTS `wallet_id` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(metadata, '$.walletid')) STORED,
ADD COLUMN IF NOT EXISTS `phone_serial` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(metadata, '$.phonedata.SerialNumber')) STORED;

CREATE INDEX IF NOT EXISTS `idx_players_job_name` ON `players` (`job_name`);
CREATE INDEX IF NOT EXISTS `idx_players_gang_name` ON `players` (`gang_name`);
CREATE INDEX IF NOT EXISTS `idx_players_fingerprint` ON `players` (`fingerprint`);
CREATE INDEX IF NOT EXISTS `idx_players_wallet_id` ON `players` (`wallet_id`);
CREATE INDEX IF NOT EXISTS `idx_players_phone_serial` ON `players` (`phone_serial`);

-- `position` is 4 floats round-tripped through a JSON blob on every save/load for no reason
-- (qbx_core issue #741). Typed columns instead — legacy `position` kept for one migration
-- window (see server/storage/players.lua ensurePositionColumns for the backfill this copy
-- mirrors on a fresh install).
ALTER TABLE `players`
ADD COLUMN IF NOT EXISTS `pos_x` FLOAT DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `pos_y` FLOAT DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `pos_z` FLOAT DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `pos_heading` FLOAT DEFAULT NULL;

UPDATE `players`
SET pos_x = JSON_VALUE(position, '$.x'),
    pos_y = JSON_VALUE(position, '$.y'),
    pos_z = JSON_VALUE(position, '$.z'),
    pos_heading = JSON_VALUE(position, '$.w')
WHERE pos_x IS NULL AND position IS NOT NULL;

-- `money` is a JSON blob (`{"cash":500,"bank":5000,...}`) even though account types are just
-- typed numbers — a real (citizenid, account_type) row-per-type table instead, same shape as
-- player_groups (qbx_core issue #741). Account types are server-configurable
-- (config.money.moneyTypes), so this can't be fixed columns like position was.
-- Legacy `money` column kept for the migration window; server/storage/players.lua's
-- fetchPlayerEntity/fetchAllPlayerEntities fall back to it per-player until each one saves at
-- least once post-upgrade, or an admin runs the `convertaccounts` console command to migrate
-- everyone in one pass (mirrors the existing `convertjobs` command for player_groups).
CREATE TABLE IF NOT EXISTS `character_accounts` (
  `citizenid` VARCHAR(50) NOT NULL,
  `account_type` VARCHAR(50) NOT NULL,
  `balance` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`citizenid`, `account_type`),
  CONSTRAINT `fk_character_accounts_citizenid` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- `charinfo` is a JSON blob for 9 plain typed fields (firstname, lastname, birthdate,
-- nationality, gender, backstory, phone, account, card) — real typed columns instead
-- (qbx_core issue #741). `phone`/`account_number` reuse the old generated columns' names
-- (searchPlayerEntities/fetchIsUnique already reference them); a generated column can't become
-- a regular one in place, so drop-then-recreate (same on a fresh install: harmless no-op since
-- they were never created above). `cid` isn't included — `players.cid` already covers it.
-- See server/storage/players.lua's ensureCharinfoColumns for the full reasoning, including why
-- these aren't UNIQUE despite conceptually being so.
DROP INDEX IF EXISTS `idx_players_account_number` ON `players`;
DROP INDEX IF EXISTS `idx_players_phone` ON `players`;
ALTER TABLE `players` DROP COLUMN IF EXISTS `account_number`, DROP COLUMN IF EXISTS `phone`;

ALTER TABLE `players`
ADD COLUMN IF NOT EXISTS `first_name` VARCHAR(50) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `last_name` VARCHAR(50) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `birthdate` VARCHAR(50) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `nationality` VARCHAR(50) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `gender` TINYINT UNSIGNED DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `backstory` TEXT DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `phone` VARCHAR(50) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `account_number` VARCHAR(50) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `card_number` BIGINT DEFAULT NULL;

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

CREATE INDEX IF NOT EXISTS `idx_players_phone` ON `players` (`phone`);
CREATE INDEX IF NOT EXISTS `idx_players_account_number` ON `players` (`account_number`);
CREATE INDEX IF NOT EXISTS `idx_players_name` ON `players` (`last_name`, `first_name`);

-- `metadata` is a 20+ field open-ended JSON blob (third-party resources add arbitrary keys via
-- SetMetadata) so it can't be fully normalized like charinfo — just the 7 fields that change on
-- every Save() (qbx_core issue #741). Unlike position/charinfo, reads still decode the full
-- `metadata` blob regardless (needed for the fields that aren't extracted) — these columns are
-- a write-side crash-safety net and queryability layer, not a read-path change. See
-- server/storage/players.lua's ensureMetadataColumns for the full reasoning.
ALTER TABLE `players`
ADD COLUMN IF NOT EXISTS `health` SMALLINT UNSIGNED DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `armor` SMALLINT UNSIGNED DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `hunger` DECIMAL(5,2) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `thirst` DECIMAL(5,2) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `stress` DECIMAL(5,2) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `isdead` BOOLEAN DEFAULT NULL,
ADD COLUMN IF NOT EXISTS `injail` INT DEFAULT NULL;

-- JSON_VALUE always returns text, and Lua's json.encode(true) turns out to encode as the JSON
-- number `1` (confirmed by testing, not `true`) — either way, a plain string-to-number cast on
-- whatever comes back is not safe to rely on, so compare against both encodings explicitly.
UPDATE `players`
SET health = JSON_VALUE(metadata, '$.health'),
    armor = JSON_VALUE(metadata, '$.armor'),
    hunger = JSON_VALUE(metadata, '$.hunger'),
    thirst = JSON_VALUE(metadata, '$.thirst'),
    stress = JSON_VALUE(metadata, '$.stress'),
    isdead = (JSON_VALUE(metadata, '$.isdead') IN ('1', 'true')),
    injail = JSON_VALUE(metadata, '$.injail')
WHERE health IS NULL AND metadata IS NOT NULL;

CREATE TABLE IF NOT EXISTS `bans` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(50) DEFAULT NULL,
  `license` varchar(50) DEFAULT NULL,
  `discord` varchar(50) DEFAULT NULL,
  `ip` varchar(50) DEFAULT NULL,
  `reason` text DEFAULT NULL,
  `expire` int(11) DEFAULT NULL,
  `bannedby` varchar(255) NOT NULL DEFAULT 'LeBanhammer',
  PRIMARY KEY (`id`),
  KEY `license` (`license`),
  KEY `discord` (`discord`),
  KEY `ip` (`ip`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `player_groups` (
  `citizenid` VARCHAR(50) NOT NULL,
  `group` VARCHAR(50) NOT NULL,
  `type` VARCHAR(50) NOT NULL,
  `grade` TINYINT(3) UNSIGNED NOT NULL,
  PRIMARY KEY (`citizenid`, `type`, `group`),
  CONSTRAINT `fk_citizenid` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- fetchGroupMembers looks players up by (group, type), which isn't a prefix of the PK
-- above (citizenid, type, group), so it was a full table scan without this index.
CREATE INDEX IF NOT EXISTS `idx_player_groups_group_type` ON `player_groups` (`group`, `type`);

-- `players.job`/`players.gang` are JSON blobs redundant with player_groups (qbx_core issue
-- #741) — CheckPlayerData (server/player.lua) only ever reads `.name`/`.grade.level` out of
-- them, rebuilding every other field fresh from GetJob()/GetGang() regardless of what's
-- stored. `is_primary` marks which player_groups membership is the active one; see
-- server/storage/players.lua's ensurePrimaryGroupColumn for why 'unemployed'/'none' never
-- get a row here at all, and how that's used as the "not migrated yet" fallback signal too.
ALTER TABLE `player_groups` ADD COLUMN IF NOT EXISTS `is_primary` BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS `idx_player_groups_primary` ON `player_groups` (`citizenid`, `type`, `is_primary`);
