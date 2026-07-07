# parquet-iceberg-trino-demo

## Overview

Proof of concept for ingesting a Parquet file into S3, registering it as an Apache Iceberg table via a REST or Hive catalog, and querying it with Trino. Goal is to validate the end-to-end data path and confirm query output matches source data.

---

## Requirements

- Python 3.9+
- `boto3`, `pyarrow`, `pandas`
- AWS CLI configured with S3 access
- Trino server (local Docker or remote)
- Iceberg catalog: REST, Hive Metastore, or AWS Glue
- `trino` Python client or `trino` CLI

---

## Workflow

1. **Generate or source a Parquet file** — use `pyarrow` or export from an existing DataFrame.
2. **Upload to S3** — `aws s3 cp data.parquet s3://<your-bucket>/warehouse/demo/`
3. **Register Iceberg table** — create the table in Trino pointing to the S3 path:
   ```sql
   CREATE TABLE iceberg.demo.sample (
     id BIGINT,
     name VARCHAR,
     value DOUBLE
   )
   WITH (
     location = 's3://<your-bucket>/warehouse/demo/'
   );
   ```
4. **Verify schema** — `DESCRIBE iceberg.demo.sample;`
5. **Query and validate** — run example queries below and compare against source.

---

## Example Queries

```sql
-- Row count check
SELECT COUNT(*) FROM iceberg.demo.sample;

-- Spot check
SELECT * FROM iceberg.demo.sample LIMIT 10;

-- Aggregation
SELECT name, SUM(value) FROM iceberg.demo.sample GROUP BY name;

-- Iceberg metadata
SELECT * FROM iceberg.demo."sample$snapshots";
```

---

## Notes

- Replace `<your-bucket>` with your actual S3 bucket name.
- Catalog name (`iceberg`) must match your Trino catalog config file (`iceberg.properties`).
- If using Docker for Trino, mount the catalog config at `/etc/trino/catalog/`.
- Parquet files must be written with a compatible schema — avoid nested types unless Trino version supports them.
- This repo contains no credentials or environment-specific config.
