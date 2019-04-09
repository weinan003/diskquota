/* contrib/diskquota/diskquota--1.0.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION diskquota" to load this file. \quit

CREATE SCHEMA diskquota;

-- Configuration table
create table diskquota.quota_config (targetOid oid, quotatype int, quotalimitMB int8, PRIMARY KEY(targetOid, quotatype));

SELECT pg_catalog.pg_extension_config_dump('diskquota.quota_config', '');

CREATE FUNCTION diskquota.set_schema_quota(text, text)
RETURNS void STRICT
AS 'MODULE_PATHNAME'
LANGUAGE C;

CREATE FUNCTION diskquota.set_role_quota(text, text)
RETURNS void STRICT
AS 'MODULE_PATHNAME'
LANGUAGE C;

CREATE TABLE diskquota.table_size (tableid oid, size int8, PRIMARY KEY(tableid));

CREATE TABLE diskquota.state (state int, PRIMARY KEY(state));

INSERT INTO diskquota.state SELECT (count(relname) = 0)::int  FROM pg_class AS c, pg_namespace AS n WHERE c.oid > 16384 and relnamespace = n.oid and nspname != 'diskquota';

CREATE FUNCTION diskquota.diskquota_start_worker()
RETURNS void STRICT
AS 'MODULE_PATHNAME'
LANGUAGE C;

CREATE FUNCTION diskquota.init_table_size_table()
RETURNS void STRICT
AS 'MODULE_PATHNAME'
LANGUAGE C;

CREATE VIEW diskquota.show_schema_quota_proximate_view AS
select pgns.nspname as schema_name, pgc.relnamespace as schema_oid, qc.quotalimitMB as quota_in_mb, sum(ts.size) as nspsize_in_bytes
from diskquota.table_size as ts,
        pg_class as pgc,
        diskquota.quota_config as qc,
        pg_namespace as pgns
where ts.tableid = pgc.oid and qc.targetoid = pgc.relnamespace and pgns.oid = pgc.relnamespace
group by relnamespace, qc.quotalimitMB, pgns.nspname
order by pgns.nspname;

CREATE VIEW diskquota.show_schema_quota_view AS
SELECT pg_namespace.nspname as schema_name, pg_class.relnamespace as schema_oid, quota.quotalimitMB as quota_in_mb, sum(pg_total_relation_size(pg_class.oid)) as nspsize_in_bytes
FROM pg_namespace, pg_class, diskquota.quota_config as quota
WHERE pg_class.relnamespace = quota.targetoid and pg_class.relnamespace = pg_namespace.oid and quota.quotatype=0
GROUP BY pg_class.relnamespace, pg_namespace.nspname, quota.quotalimitMB;

CREATE VIEW diskquota.show_role_quota_view AS
SELECT pg_roles.rolname as role_name, pg_class.relowner as role_oid, quota.quotalimitMB as quota_in_mb, sum(pg_total_relation_size(pg_class.oid)) as rolsize_in_bytes
FROM pg_roles, pg_class, diskquota.quota_config as quota
WHERE pg_class.relowner = quota.targetoid and pg_class.relowner = pg_roles.oid and quota.quotatype=1
GROUP BY pg_class.relowner, pg_roles.rolname, quota.quotalimitMB;

CREATE VIEW diskquota.database_size_view AS
SELECT ((SELECT SUM(pg_relation_size(oid)) FROM pg_class WHERE oid <= 16384)+ (SELECT SUM(size) FROM diskquota.table_size)) AS dbsize;

CREATE TYPE diskquota.diskquota_active_table_type AS ("TABLE_OID" oid,  "TABLE_SIZE" int8);

CREATE OR REPLACE FUNCTION diskquota.diskquota_fetch_table_stat(int4, oid[]) RETURNS setof diskquota.diskquota_active_table_type
AS 'MODULE_PATHNAME', 'diskquota_fetch_table_stat'
LANGUAGE C VOLATILE;

SELECT diskquota.diskquota_start_worker();
DROP FUNCTION diskquota.diskquota_start_worker();
