-- Test SCHEMA
CREATE SCHEMA s1;
SET search_path to s1;

CREATE TABLE a(i int);
SELECT diskquota.set_schema_quota('s1', '1 MB');
INSERT INTO a SELECT generate_series(1,200000);
SELECT pg_sleep(10);

select a.nspsize_in_bytes = b.nspsize_in_bytes,
	a.quota_in_mb = b.quota_in_mb,
	a.schema_oid = b.schema_oid
from diskquota.show_schema_quota_view as a,
	diskquota.show_schema_quota_proximate_view as b
where b.schema_name = 's1' and a.schema_name = b.schema_name;

RESET search_path;
DROP TABLE s1.a;
DROP SCHEMA s1;

