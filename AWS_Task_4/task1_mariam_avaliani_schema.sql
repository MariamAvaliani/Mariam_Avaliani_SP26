-- AWS Cloud for Data Engineering — Task 4, Task 1 (RDS MySQL)
-- Author: Mariam Avaliani
-- Restartable script: every statement here can be run again later without
-- failing, even if it already ran before.
--
-- Run this as the personal user (mariam_avaliani), NOT as admin.
-- Connect to: dilab-mysql.cqlpneuyr8on.eu-central-1.rds.amazonaws.com : 3306

-- 1. Personal schema
CREATE SCHEMA IF NOT EXISTS mariam_avaliani_schema
  DEFAULT CHARACTER SET utf8mb4;

-- 2. Table
CREATE TABLE IF NOT EXISTS mariam_avaliani_schema.students (
  student_id     INT AUTO_INCREMENT PRIMARY KEY,
  full_name      VARCHAR(100) NOT NULL,
  course         VARCHAR(100) NOT NULL,
  enrolled_at    DATE NOT NULL DEFAULT (CURRENT_DATE)
);

-- seed one row only if the table is empty, so re-running does not duplicate data
INSERT INTO mariam_avaliani_schema.students (full_name, course)
SELECT * FROM (SELECT 'Mariam Avaliani', 'AWS Cloud for Data Engineering') AS tmp
WHERE NOT EXISTS (SELECT 1 FROM mariam_avaliani_schema.students LIMIT 1);

-- 3. View
CREATE OR REPLACE VIEW mariam_avaliani_schema.active_students AS
SELECT student_id, full_name, course
FROM mariam_avaliani_schema.students
WHERE enrolled_at >= CURDATE() - INTERVAL 1 YEAR;

-- 4. Stored procedure
-- Note: no DELIMITER / BEGIN...END needed here, because the body is a
-- single SQL statement (one INSERT) — MySQL allows a single-statement
-- procedure body without BEGIN...END, so there is only one semicolon
-- in the whole CREATE PROCEDURE, right at the end.
DROP PROCEDURE IF EXISTS mariam_avaliani_schema.add_student;

CREATE PROCEDURE mariam_avaliani_schema.add_student(
  IN p_name   VARCHAR(100),
  IN p_course VARCHAR(100)
)
INSERT INTO mariam_avaliani_schema.students (full_name, course) VALUES (p_name, p_course);

-- 5. Verification, safe to run every time
CALL mariam_avaliani_schema.add_student('Test Student', 'AWS Cloud for Data Engineering');
SELECT * FROM mariam_avaliani_schema.active_students;
