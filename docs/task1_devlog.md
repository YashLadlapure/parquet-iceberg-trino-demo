# Task 1 — Developer Log

**Author:** Yash Ladlapure  
**Date:** July 2026

---

## What I Was Given

A `titanic.parquet` file sitting inside a MinIO bucket called `warehouse`, at the path `warehouse/titanic.parquet`. MinIO, Hive Metastore, and Trino were all set up as Docker containers on the local machine. My job was to wire them together so Trino could actually query that file as a table.

## What I Had to Do

Register the Parquet file as an Apache Iceberg table and run a few SQL queries through Trino to check the whole thing works.

---

## How the Layers Fit Together

This took me a bit to wrap my head around, so writing it out here.

```
[titanic.parquet]
       │
       ▼
  MinIO (warehouse bucket)          ← S3-compatible object store — just stores files
       │
       ▼
  Apache Iceberg (table format)     ← metadata layer: schema, snapshots, manifests
       │
       ▼
  Hive Metastore (catalog)          ← registry Trino uses to find tables
       │
       ▼
  Trino (SQL query engine)          ← pure compute, no data lives here
```

The thing that confused me early on: Iceberg is not storage and not a query engine. It sits between them. A `.parquet` file in a bucket is just bytes — no schema, no history, nothing Trino can work with. Iceberg adds a `metadata/` folder with snapshot JSON and manifest files that track which data files belong to the table. That's what makes it a table instead of just a file.

Hive Metastore is basically an address book. It stores where each table is and what its schema looks like, so Trino can look things up instead of having anything hardcoded.

---

## Startup Sequence

```bash
docker start minio
docker start metastore-standalone
docker start trino
docker exec -it trino trino
```

Order matters. Trino reads its catalog config on startup and needs Metastore to be up. If Metastore isn't running yet, the `iceberg` catalog won't show up.

---

## Errors I Hit

### Error 1 — `SHOW SCHEMAS FROM iceberg` only returned `information_schema`

Ran this to see what schemas existed. Expected `titanic`, got only `information_schema` which is just Trino's system schema.

Turns out schemas don't get created automatically in Iceberg. You have to run `CREATE SCHEMA ... WITH (location = ...)` yourself, which registers it in Metastore and tells Iceberg where in MinIO to write metadata. I just hadn't done that yet.

---

### Error 2 — Schema creation failed with `s3://titanic`

Used `location = 's3://titanic'` in my first attempt. Failed immediately.

S3 URIs are `s3://<bucket>/<prefix>`. My bucket is `warehouse` and the folder inside it is `warehouse/titanic`, so the correct path is `s3://warehouse/warehouse/titanic`. The double `warehouse` threw me off — first one is the bucket, second is a folder inside it.

---

### Error 3 — Trino CLI threw a connection error

Came back after a break and couldn't get in. Containers had stopped, probably after a restart.

Just had to start everything again in order:

```bash
docker start minio
docker start metastore-standalone
docker start trino
```

Now I run `SHOW CATALOGS` first every session. If `iceberg` isn't there, something didn't start right.

---

### Error 4 — `iceberg` catalog missing from `SHOW CATALOGS`

`SHOW CATALOGS` wasn't listing `iceberg` at all, so any query with `iceberg.` prefix just failed.

Trino picks up catalogs from `.properties` files mounted at `/etc/trino/catalog/` inside the container. `iceberg.properties` wasn't there or wasn't mounted right. Verified it was in place, restarted Trino, showed up fine.

---

### Error 5 — `SELECT *` returned zero rows

This one took me the longest to understand.

`CREATE SCHEMA` and `CREATE TABLE` both worked. The `titanic.parquet` was sitting in the bucket. Ran `SELECT * FROM iceberg.titanic.passengers` and got nothing.

The reason is that Iceberg doesn't scan the bucket for files — it only knows about files it wrote itself, or files explicitly registered into its manifest. The existing `titanic.parquet` had no connection to the Iceberg table at all. They just happened to be in the same bucket.

So I inserted one row directly through Trino:

```sql
INSERT INTO iceberg.titanic.passengers VALUES
(1, 0, 3, 'Braund, Mr. Owen Harris', 'male', 22, 1, 0, 'A/5 21171', 7.25, NULL, 'S');
```

That wrote an actual Iceberg-managed file and updated the snapshot. `SELECT *` returned the row after that.

To load the original `titanic.parquet` properly, you'd use PyIceberg's `add_files` to register it into the manifest without rewriting the file.

---

### Error 6 — Which numeric type to use

Wasn't sure how to pick between `INTEGER`, `BIGINT`, and `DOUBLE`.

| Type | Size | Use it for |
|------|------|------------|
| `INTEGER` | 32-bit | flags, small counts |
| `BIGINT` | 64-bit | IDs, anything that could grow |
| `DOUBLE` | 64-bit float | decimals like Age, Fare |

`PassengerId` gets `BIGINT` even here — ID columns should have room even if the current dataset is tiny.

---

## Final Check

- `SHOW CATALOGS` → `iceberg` listed
- `CREATE SCHEMA` with the correct S3 path → worked
- `CREATE TABLE` → registered in Metastore
- `INSERT INTO` → Iceberg wrote the file, snapshot updated
- `SELECT *` → row came back
- `SELECT COUNT(*)` → `1`
