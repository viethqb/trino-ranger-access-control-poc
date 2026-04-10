-- Setup Iceberg External Catalog in StarRocks
-- Run this via: mysql -h 127.0.0.1 -P 9030 -u root < scripts/01_setup_starrocks_iceberg_catalog.sql

CREATE EXTERNAL CATALOG IF NOT EXISTS iceberg
PROPERTIES (
    "type" = "iceberg",
    "iceberg.catalog.type" = "rest",
    "iceberg.catalog.uri" = "http://rest:8181",
    "iceberg.catalog.warehouse" = "s3://warehouse/",
    "aws.s3.access_key" = "admin",
    "aws.s3.secret_key" = "password",
    "aws.s3.endpoint" = "http://minio:9000",
    "aws.s3.enable_path_style_access" = "true",
    "aws.s3.region" = "us-east-1"
);

-- Verify the catalog
SHOW CATALOGS;
