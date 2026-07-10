# 🧊 Parquet → MinIO → Apache Iceberg → Trino

> **Internship Project — Task 1**  
> End-to-end data lakehouse PoC: Upload a Parquet file to MinIO (S3-compatible), register it as an Apache Iceberg table, and query it using Trino.

---

## 📌 Project Goal

Validate the full data path:

```
Parquet File  →  MinIO (warehouse bucket)  →  Apache Iceberg Table  →  Trino SQL Query
```

The Titanic dataset (`titanic.parquet`) was used as the source file stored at `warehouse/titanic.parquet` inside the MinIO bucket.

---

## 🛠️ Stack

| Component | Role |
|---|---|
| **MinIO** | S3-compatible local object storage (bucket: `warehouse`) |
| **Apache Iceberg** | Open table format that wraps Parquet files into queryable tables |
| **Hive Metastore** | Stores Iceberg table metadata (schema, location, snapshots) |
| **Trino** | Distributed SQL engine that queries Iceberg tables |
| **Docker** | Runs all services locally in containers |

---

## 📂 File Location

```
MinIO Bucket:  warehouse
File Path:     warehouse/titanic.parquet
S3 URI:        s3://warehouse/warehouse/titanic
```

---

## ⚙️ Docker Services Used

```bash
# Start all required services
docker start minio
docker start metastore-standalone
docker start trino

# Enter Trino CLI
docker exec -it trino trino
```

---

## 🗃️ Titanic Table Schema

```sql
CREATE TABLE iceberg.titanic.passengers (
  PassengerId  BIGINT,
  Survived     INTEGER,
  Pclass       INTEGER,
  Name         VARCHAR,
  Sex          VARCHAR,
  Age          DOUBLE,
  SibSp        INTEGER,
  Parch        INTEGER,
  Ticket       VARCHAR,
  Fare         DOUBLE,
  Cabin        VARCHAR,
  Embarked     VARCHAR
);
```

### Column Type Reference

| Column | Type | Why |
|---|---|---|
| PassengerId | BIGINT | 64-bit ID — safe for large datasets |
| Survived, Pclass, SibSp, Parch | INTEGER | Small whole numbers (32-bit is enough) |
| Age, Fare | DOUBLE | Decimal values (64-bit float) |
| Name, Sex, Ticket, Cabin, Embarked | VARCHAR | Variable-length text |

> **BIGINT vs INT**: `INTEGER` is 32-bit (range ~±2 billion). `BIGINT` is 64-bit (range ~±9 quintillion). Use `BIGINT` for IDs that may grow large.

---

## 🧱 Full SQL Command Sequence (Trino CLI)

```sql
-- 1. Verify catalogs and schemas
SHOW CATALOGS;
SHOW SCHEMAS FROM iceberg;

-- 2. Drop schema if re-running
DROP SCHEMA IF EXISTS iceberg.titanic CASCADE;

-- 3. Create schema pointing to MinIO warehouse bucket
CREATE SCHEMA iceberg.titanic
WITH (location = 's3://warehouse/warehouse/titanic');

-- 4. Create Iceberg table with Titanic schema
CREATE TABLE iceberg.titanic.passengers (
  PassengerId  BIGINT,
  Survived     INTEGER,
  Pclass       INTEGER,
  Name         VARCHAR,
  Sex          VARCHAR,
  Age          DOUBLE,
  SibSp        INTEGER,
  Parch        INTEGER,
  Ticket       VARCHAR,
  Fare         DOUBLE,
  Cabin        VARCHAR,
  Embarked     VARCHAR
);

-- 5. Insert a test row
INSERT INTO iceberg.titanic.passengers VALUES
(1, 0, 3, 'Braund, Mr. Owen Harris', 'male', 22, 1, 0, 'A/5 21171', 7.25, NULL, 'S');

-- 6. Query the table
SELECT * FROM iceberg.titanic.passengers;

-- 7. Count rows
SELECT COUNT(*) FROM iceberg.titanic.passengers;
```

---

## 🐛 Errors Faced & Solutions

### ❌ Error 1: `SHOW SCHEMAS FROM iceberg` returned only `information_schema`

**Cause:** No schema had been created yet under the Iceberg catalog.  
**Solution:** Run `CREATE SCHEMA iceberg.titanic WITH (location = '...')` before trying to create any tables.

---

### ❌ Error 2: Schema creation failed — wrong S3 path

**Cause:** Used `s3://titanic` (just the file name) instead of a proper bucket path.  
**Solution:** Bucket name is `warehouse`, so the correct path is:
```sql
WITH (location = 's3://warehouse/warehouse/titanic')
```
The first `warehouse` is the **bucket name**, and the second is the **folder path inside it**.

---

### ❌ Error 3: Docker container `trino` not running

**Cause:** Containers were stopped after a system restart.  
**Solution:**
```bash
docker start minio
docker start metastore-standalone
docker start trino
```
Always start all three services before opening the Trino CLI.

---

### ❌ Error 4: `CREATE TABLE` failed — Iceberg catalog not found

**Cause:** `iceberg` catalog not configured in Trino, or wrong catalog name used.  
**Solution:** Verify the catalog name with `SHOW CATALOGS;` first, and confirm `iceberg.properties` is mounted inside the Trino container at `/etc/trino/catalog/`.

---

### ❌ Error 5: Existing Parquet file at `warehouse/titanic.parquet` not automatically queryable

**Cause:** Iceberg is a **table format**, not a raw file scanner. A raw `.parquet` file in a bucket is NOT automatically an Iceberg table — Iceberg needs its own metadata layer.  
**Solution (two options):**
- **Option A:** Insert test data manually via `INSERT INTO` to validate the pipeline.
- **Option B:** Use PyIceberg or Spark to register/adopt the existing Parquet file into the Iceberg table using the `add_files` procedure.

---

### ❌ Error 6: Type confusion — when to use `BIGINT` vs `INTEGER`

**Cause:** Not clear which Trino type to use for numeric columns.  
**Solution:**

| Type | Bits | Range | Use for |
|---|---|---|---|
| `INTEGER` / `INT` | 32-bit | ~±2.1 billion | Small counts, flags, class numbers |
| `BIGINT` | 64-bit | ~±9.2 quintillion | IDs, large counters |
| `DOUBLE` | 64-bit float | Decimals | Age, Fare, any decimal value |

---

## 📋 Key Concepts Learned

- **Apache Iceberg** wraps Parquet files with a metadata layer (snapshots, manifests, schema). This allows schema evolution, time travel, and ACID transactions on top of object storage.
- **MinIO** acts as a local S3-compatible bucket store. Trino accesses it using the `s3://` URI scheme.
- **Hive Metastore** stores the Iceberg catalog metadata so Trino can discover table schemas and file locations.
- **Trino** is the SQL execution layer — it does not store data, it queries it from Iceberg/Parquet via the catalog.
- A **raw Parquet file** in a bucket is NOT an Iceberg table until registered. Iceberg uses its own metadata files (`metadata/`, `data/`) separate from the Parquet data files.

---

## 🔮 Next Steps (Task 2)

- [ ] Generate relational synthetic data using Python + Faker + PostgreSQL (with proper foreign keys)
- [ ] Export PostgreSQL tables as Parquet files
- [ ] Upload Parquet files to MinIO `warehouse` bucket
- [ ] Register them as Iceberg tables in Trino
- [ ] Run analytical SQL queries across multiple related Iceberg tables

---

## 👤 Author

**Yash Ladlapure**  
B.Tech CSE @ MIT-WPU | Full-Stack Dev & Cloud Enthusiast  
[GitHub Profile](https://github.com/YashLadlapure) | [Portfolio](https://yashladlapure.github.io/portfolio-website/)
