# Task 1 — Developer Log

**Intern:** Yash Ladlapure  
**Company:** Augmented Transformations, Pune  
**Date:** July 2026

---

## What I Was Given

A local `titanic.parquet` file stored inside a MinIO bucket called `warehouse`, at path `warehouse/titanic.parquet`.  
All services (MinIO, Hive Metastore, Trino) were running as Docker containers on the local machine.

## What I Had to Do

Register that Parquet file as a queryable Apache Iceberg table and run SQL against it through Trino — verifying the full lakehouse read/write path works end to end.

---

## Architecture (Local Docker Setup)

```
[titanic.parquet]
       │
       ▼
  MinIO (warehouse bucket)          ← S3-compatible object store
       │
       ▼
  Apache Iceberg (table format)     ← metadata layer on top of Parquet
       │
       ▼
  Hive Metastore (catalog)          ← stores schema, location, snapshots
       │
       ▼
  Trino (SQL query engine)          ← compute layer, reads from Iceberg/MinIO
```

---

## Startup Sequence

```bash
docker start minio
docker start metastore-standalone
docker start trino
docker exec -it trino trino
```

Order matters — Trino reads catalog config at startup and needs Metastore reachable.

---

## Errors I Hit and How I Fixed Them

### Error 1 — `SHOW SCHEMAS` returned only `information_schema`

I hadn't created a schema yet. In Iceberg, schemas don't exist unless explicitly created with a `CREATE SCHEMA ... WITH (location = ...)` statement.

### Error 2 — Schema creation failed with `s3://titanic`

Wrong URI format. S3 URIs are `s3://<bucket>/<prefix>`. My bucket is `warehouse` and the folder inside is `warehouse/titanic`, so the correct path is `s3://warehouse/warehouse/titanic`.

### Error 3 — `docker exec -it trino trino` connection error

Docker containers had stopped. Fixed by starting all three in order.

### Error 4 — `iceberg` catalog not showing in `SHOW CATALOGS`

`iceberg.properties` was missing or not mounted correctly inside the Trino container at `/etc/trino/catalog/`. Verified file presence and restarted Trino.

### Error 5 — `SELECT *` returned zero rows after table creation

This was the biggest learning. Apache Iceberg is a table format, not a raw file scanner. The existing `titanic.parquet` in the bucket has no connection to an Iceberg table until explicitly registered. Iceberg manages its own `metadata/` folder with snapshot JSON and manifest files that track which Parquet data files belong to which table version.

**Short-term fix:** Used `INSERT INTO` to write one row through Trino, which created an Iceberg-managed Parquet file and updated the snapshot. `SELECT *` then returned the row correctly.

**Long-term fix:** Use `PyIceberg`'s `add_files` procedure to register the existing Parquet file into the table manifest without rewriting it.

### Error 6 — Type confusion: `BIGINT` vs `INTEGER` vs `DOUBLE`

| Type | Bits | Max range | When to use |
|------|------|-----------|-------------|
| `INTEGER` | 32 | ~±2.1 billion | Flags, counts, class numbers |
| `BIGINT` | 64 | ~±9.2 quintillion | IDs, anything that could grow |
| `DOUBLE` | 64 float | Decimals | Age, Fare, any numeric decimal |

---

## Final Verification

After resolving all errors:

- `SHOW CATALOGS` → `iceberg` listed ✓  
- `CREATE SCHEMA` with correct S3 path → success ✓  
- `CREATE TABLE` → registered in Hive Metastore ✓  
- `INSERT INTO` → Iceberg Parquet file written to MinIO ✓  
- `SELECT *` → row returned ✓  
- `SELECT COUNT(*)` → `1` ✓  

---

## Key Takeaway

Storage (MinIO), table format (Iceberg), catalog (Hive Metastore), and query engine (Trino) are four independent layers. Iceberg is the contract between storage and query — without it, Trino sees raw bytes; with it, Trino sees a versioned, ACID-compliant table backed by open file formats.
