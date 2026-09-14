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
ALTER TABLE `players`
ADD COLUMN IF NOT EXISTS `job_name` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(job, '$.name')) STORED,
ADD COLUMN IF NOT EXISTS `gang_name` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(gang, '$.name')) STORED,
ADD COLUMN IF NOT EXISTS `account_number` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(charinfo, '$.account')) STORED,
ADD COLUMN IF NOT EXISTS `phone` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(charinfo, '$.phone')) STORED,
ADD COLUMN IF NOT EXISTS `fingerprint` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(metadata, '$.fingerprint')) STORED,
ADD COLUMN IF NOT EXISTS `wallet_id` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(metadata, '$.walletid')) STORED,
ADD COLUMN IF NOT EXISTS `phone_serial` VARCHAR(50) GENERATED ALWAYS AS (JSON_VALUE(metadata, '$.phonedata.SerialNumber')) STORED;

CREATE INDEX IF NOT EXISTS `idx_players_job_name` ON `players` (`job_name`);
CREATE INDEX IF NOT EXISTS `idx_players_gang_name` ON `players` (`gang_name`);
CREATE INDEX IF NOT EXISTS `idx_players_account_number` ON `players` (`account_number`);
CREATE INDEX IF NOT EXISTS `idx_players_phone` ON `players` (`phone`);
CREATE INDEX IF NOT EXISTS `idx_players_fingerprint` ON `players` (`fingerprint`);
CREATE INDEX IF NOT EXISTS `idx_players_wallet_id` ON `players` (`wallet_id`);
CREATE INDEX IF NOT EXISTS `idx_players_phone_serial` ON `players` (`phone_serial`);

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
