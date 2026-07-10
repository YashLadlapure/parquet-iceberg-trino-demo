# Task 1 — Developer Log

**Author:** Yash Ladlapure  
**Date:** July 2026

---

## What I Was Given

A `titanic.parquet` file already sitting inside a MinIO bucket called `warehouse`, at the path `warehouse/titanic.parquet`.  
MinIO, Hive Metastore, and Trino were all pre-configured as Docker containers on the local machine. My job was to wire them together so Trino could actually query that Parquet file as a proper table.

## What I Had to Do

Register the Parquet file as an Apache Iceberg table, confirm the schema and write path work, and run a few SQL queries through Trino to verify everything end to end.

---

## How the Layers Fit Together

This took me a while to actually understand, so I want to write it out clearly.

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
  Hive Metastore (catalog)          ← registry Trino uses to discover tables
       │
       ▼
  Trino (SQL query engine)          ← pure compute, no data lives here
```

The key thing I kept confusing early on: **Iceberg is not storage and not a query engine**. It's the layer between them. A `.parquet` file in a bucket is just bytes — it has no schema Trino can read, no snapshot history, nothing. Iceberg wraps it with a `metadata/` folder that holds JSON snapshot files and manifest files listing which data files belong to the current table version. That's what makes it a "table" instead of just a file.

Hive Metastore is just the address book. It stores where each table lives and what its schema is, so Trino doesn't have to hardcode that anywhere — it just asks Metastore.

---

## Startup Sequence

```bash
docker start minio
docker start metastore-standalone
docker start trino
docker exec -it trino trino
```

Order matters. Trino reads its catalog config at startup, and that config points to the Metastore. If Metastore isn't up when Trino starts, the `iceberg` catalog won't register properly.

---

## Errors I Hit (and How I Fixed Them)

### Error 1 — `SHOW SCHEMAS FROM iceberg` only returned `information_schema`

Ran this to check what schemas existed. Expected to see something called `titanic`. Got only `information_schema`, which is Trino's system-level schema that always exists.

The fix was obvious once I understood it: in Iceberg, schemas don't get created automatically. You have to run `CREATE SCHEMA ... WITH (location = ...)` explicitly, which registers it in the Metastore and tells Iceberg where in MinIO to write metadata for that schema's tables. I hadn't done that yet.

---

### Error 2 — Schema creation failed, `s3://titanic` is not a valid path

My first attempt at `CREATE SCHEMA` used `location = 's3://titanic'`. That failed.

S3 URIs are `s3://<bucket-name>/<prefix-path>`. My bucket is named `warehouse`. Inside that bucket, the folder structure is `warehouse/titanic/`. So the correct path is:

```
s3://warehouse/warehouse/titanic
```

The double `warehouse` tripped me up — the first is the bucket name, the second is a folder prefix inside it. Once I used the right path, schema creation worked and it showed up in `SHOW SCHEMAS FROM iceberg`.

---

### Error 3 — `docker exec -it trino trino` threw a connection error

Came back to the project after a break and got an error trying to enter the Trino CLI. The containers had stopped — probably after a system restart.

Fix: start everything in order again.

```bash
docker start minio
docker start metastore-standalone
docker start trino
```

This is also why I now run `SHOW CATALOGS` as the very first thing every time I open a session. If `iceberg` isn't listed, something in the startup didn't work and there's no point running anything else.

---

### Error 4 — `iceberg` catalog wasn't showing in `SHOW CATALOGS`

At one point, `SHOW CATALOGS` didn't list `iceberg` at all. Any SQL with the `iceberg.` prefix would just fail with "catalog does not exist".

Root cause: Trino discovers catalogs through `.properties` files mounted at `/etc/trino/catalog/` inside the container. If `iceberg.properties` is missing or wasn't mounted correctly when the container started, Trino has no idea that catalog exists.

Verified the file was there, restarted Trino, and it showed up. Not a complicated fix, but finding the root cause took a few minutes.

---

### Error 5 — `SELECT *` returned zero rows after the table was created

This was the one that took the most thinking to understand.

After running `CREATE SCHEMA`, `CREATE TABLE`, everything looked fine. The table existed in Metastore. The `titanic.parquet` file was sitting in the MinIO bucket at `warehouse/titanic.parquet`. I ran `SELECT * FROM iceberg.titanic.passengers` expecting to see the Titanic data.

Zero rows.

The reason: **Iceberg doesn't scan files — it tracks files**. When you create an Iceberg table, Iceberg creates a `metadata/` directory in the schema location and starts managing snapshots. A raw Parquet file that was already in the bucket before the table was created has no relationship to the table — it's not listed in any manifest, so Iceberg doesn't know it exists. Iceberg only knows about files it wrote itself or files that were explicitly registered via something like PyIceberg's `add_files` procedure.

To validate the pipeline was actually working, I inserted one row directly through Trino:

```sql
INSERT INTO iceberg.titanic.passengers VALUES
(1, 0, 3, 'Braund, Mr. Owen Harris', 'male', 22, 1, 0, 'A/5 21171', 7.25, NULL, 'S');
```

Trino wrote that as a new Iceberg-managed Parquet file under the schema location and updated the snapshot. `SELECT *` then returned the row. `SELECT COUNT(*)` returned `1`. The pipeline works — the pre-existing Parquet file just isn't connected to the table yet.

Longer term, loading the original `titanic.parquet` properly means using PyIceberg's `add_files` to register it into the table's manifest without rewriting it. That's a Task 2-level thing.

---

### Error 6 — Wasn't sure which numeric type to use for each column

Not really an error, more like a gap I had to fill. Ended up looking at what each type actually means:

| Type | Size | Use it for |
|------|------|------------|
| `INTEGER` | 32-bit signed | flags, small counts (Survived, Pclass, SibSp, Parch) |
| `BIGINT` | 64-bit signed | IDs — anything that could grow large at scale |
| `DOUBLE` | 64-bit float | decimal values (Age, Fare) |

`PassengerId` got `BIGINT` even though the Titanic dataset only has ~891 rows. The convention for ID columns is to give them room to grow. If this were a real production table and you'd used `INTEGER`, you'd eventually overflow it.

---

## Final Verification

Once all the above was sorted:

- `SHOW CATALOGS` → `iceberg` listed
- `CREATE SCHEMA iceberg.titanic WITH (location = 's3://warehouse/warehouse/titanic')` → success
- `CREATE TABLE iceberg.titanic.passengers (...)` → table registered in Metastore
- `INSERT INTO` → Trino wrote an Iceberg-managed Parquet file to MinIO, snapshot updated
- `SELECT * FROM iceberg.titanic.passengers` → row returned correctly
- `SELECT COUNT(*)` → `1`

Full read-write path confirmed.

---

## What's Next (Task 2)

Generate a larger relational synthetic dataset using Python + Faker + PostgreSQL with proper FK constraints, export as Parquet files, upload to the same MinIO bucket, register them as Iceberg tables, and run multi-table analytical SQL through Trino.
