-- pls_mechanic
-- Tables are created automatically on resource start. This file is only for manual installation.

CREATE TABLE IF NOT EXISTS `pls_mechanic_shops` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `data` LONGTEXT NOT NULL,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pls_mechanic_vehicles` (
    `plate` VARCHAR(12) NOT NULL,
    `mileage` DOUBLE NOT NULL DEFAULT 0,
    `data` LONGTEXT NOT NULL,
    `updated_at` INT(11) NOT NULL DEFAULT 0,
    PRIMARY KEY (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pls_mechanic_history` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `plate` VARCHAR(12) NOT NULL,
    `shop_id` INT(11) NULL DEFAULT NULL,
    `mechanic` VARCHAR(100) NULL DEFAULT NULL,
    `type` VARCHAR(20) NOT NULL,
    `label` VARCHAR(255) NOT NULL,
    `data` LONGTEXT NULL DEFAULT NULL,
    `mileage` DOUBLE NOT NULL DEFAULT 0,
    `created_at` INT(11) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    INDEX `plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pls_mechanic_bills` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `shop_id` INT(11) NOT NULL,
    `mechanic` VARCHAR(100) NOT NULL,
    `mechanic_name` VARCHAR(100) NULL DEFAULT NULL,
    `customer` VARCHAR(100) NULL DEFAULT NULL,
    `customer_name` VARCHAR(100) NULL DEFAULT NULL,
    `plate` VARCHAR(12) NULL DEFAULT NULL,
    `lines` LONGTEXT NOT NULL,
    `note` TEXT NULL DEFAULT NULL,
    `total` INT(11) NOT NULL DEFAULT 0,
    `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
    `created_at` INT(11) NOT NULL DEFAULT 0,
    `paid_at` INT(11) NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    INDEX `shop_id` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `pls_mechanic_orders` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `shop_id` INT(11) NOT NULL,
    `charid` VARCHAR(100) NULL DEFAULT NULL,
    `name` VARCHAR(100) NULL DEFAULT NULL,
    `items` LONGTEXT NOT NULL,
    `total` INT(11) NOT NULL DEFAULT 0,
    `mode` VARCHAR(20) NOT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
    `deliver_at` INT(11) NULL DEFAULT NULL,
    `created_at` INT(11) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    INDEX `shop_id` (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
