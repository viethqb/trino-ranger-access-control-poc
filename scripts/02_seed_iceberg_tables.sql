-- Seed Iceberg tables from TPCH data via Trino
-- Run this via: trino --server http://localhost:9090 --user admin -f scripts/02_seed_iceberg_tables.sql

-- Create schema in Iceberg catalog
CREATE SCHEMA IF NOT EXISTS iceberg.tpch;

-- Create and populate customer table
CREATE TABLE IF NOT EXISTS iceberg.tpch.customer AS
SELECT * FROM tpch.tiny.customer;

-- Create and populate orders table
CREATE TABLE IF NOT EXISTS iceberg.tpch.orders AS
SELECT * FROM tpch.tiny.orders;

-- Create and populate lineitem table
CREATE TABLE IF NOT EXISTS iceberg.tpch.lineitem AS
SELECT * FROM tpch.tiny.lineitem;

-- Create and populate nation table
CREATE TABLE IF NOT EXISTS iceberg.tpch.nation AS
SELECT * FROM tpch.tiny.nation;

-- Create and populate region table
CREATE TABLE IF NOT EXISTS iceberg.tpch.region AS
SELECT * FROM tpch.tiny.region;

-- Create and populate supplier table
CREATE TABLE IF NOT EXISTS iceberg.tpch.supplier AS
SELECT * FROM tpch.tiny.supplier;

-- Create and populate part table
CREATE TABLE IF NOT EXISTS iceberg.tpch.part AS
SELECT * FROM tpch.tiny.part;

-- Create and populate partsupp table
CREATE TABLE IF NOT EXISTS iceberg.tpch.partsupp AS
SELECT * FROM tpch.tiny.partsupp;

-- Verify
SELECT 'customer' AS tbl, count(*) AS cnt FROM iceberg.tpch.customer
UNION ALL SELECT 'orders', count(*) FROM iceberg.tpch.orders
UNION ALL SELECT 'lineitem', count(*) FROM iceberg.tpch.lineitem
UNION ALL SELECT 'nation', count(*) FROM iceberg.tpch.nation
UNION ALL SELECT 'region', count(*) FROM iceberg.tpch.region
UNION ALL SELECT 'supplier', count(*) FROM iceberg.tpch.supplier
UNION ALL SELECT 'part', count(*) FROM iceberg.tpch.part
UNION ALL SELECT 'partsupp', count(*) FROM iceberg.tpch.partsupp;
