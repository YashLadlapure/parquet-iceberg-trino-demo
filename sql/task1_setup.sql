-- Task 1: Parquet → MinIO → Apache Iceberg → Trino
-- Run all commands inside the Trino CLI
-- Entry: docker exec -it trino trino

-- Step 1: Verify catalog is registered
SHOW CATALOGS;

-- Step 2: Check existing schemas under iceberg catalog
SHOW SCHEMAS FROM iceberg;

-- Step 3: Drop schema if re-running from scratch
DROP SCHEMA IF EXISTS iceberg.titanic CASCADE;

-- Step 4: Create schema — location must match bucket + prefix in MinIO
-- Format: s3://<bucket-name>/<folder-path>
-- Bucket: warehouse | Folder: warehouse/titanic
CREATE SCHEMA iceberg.titanic
WITH (location = 's3://warehouse/warehouse/titanic');

-- Step 5: Create Iceberg table with Titanic column schema
CREATE TABLE iceberg.titanic.passengers (
  PassengerId  BIGINT,    -- 64-bit ID, safe for scale
  Survived     INTEGER,   -- 0 or 1 flag
  Pclass       INTEGER,   -- passenger class (1, 2, 3)
  Name         VARCHAR,
  Sex          VARCHAR,
  Age          DOUBLE,    -- decimal age
  SibSp        INTEGER,   -- siblings/spouses aboard
  Parch        INTEGER,   -- parents/children aboard
  Ticket       VARCHAR,
  Fare         DOUBLE,    -- ticket price
  Cabin        VARCHAR,
  Embarked     VARCHAR    -- port of embarkation
);

-- Step 6: Insert one row to validate the write path
-- Iceberg will write this as a managed Parquet file + update snapshot metadata
INSERT INTO iceberg.titanic.passengers VALUES
(1, 0, 3, 'Braund, Mr. Owen Harris', 'male', 22, 1, 0, 'A/5 21171', 7.25, NULL, 'S');

-- Step 7: Confirm read path works
SELECT * FROM iceberg.titanic.passengers;

-- Step 8: Count rows — should return 1
SELECT COUNT(*) FROM iceberg.titanic.passengers;
