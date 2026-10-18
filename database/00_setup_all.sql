-- Loads the whole database in the right order. Run from INSIDE the database folder:
--     cd database
--     mysql -u root -p < 00_setup_all.sql
-- WARNING: 01_schema_ddl.sql drops and recreates clinic_portal (all data is reset).
SOURCE 01_schema_ddl.sql;
SOURCE 02_triggers.sql;
SOURCE 03_procedures_functions.sql;
SOURCE 04_views_queries.sql;
SOURCE 05_sample_data.sql;
