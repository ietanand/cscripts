ACC sample_time PROMPT 'Date and Time (i.e. 2017-09-15T18:00:07): ';
PRO KIEV Transaction: C=commitTx | B=beginTx | R=read | G=GC | CB=commitTx+beginTx | <null>=commitTx+beginTx+read+GC
ACC kiev_tx PROMPT 'KIEV Transaction (opt): ';

SET HEA ON LIN 32767 NEWP 1 PAGES 100 TAB OFF FEED OFF ECHO OFF VER OFF LONG 32000 LONGC 2000 WRA ON TRIMS ON TRIM ON TI OFF TIMI OFF ARRAY 100 NUM 20 SQLBL ON BLO . RECSEP OFF;

COL current_time NEW_V current_time FOR A15;
SELECT 'current_time: ' x, TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS') current_time FROM DUAL;
COL x_host_name NEW_V x_host_name;
SELECT host_name x_host_name FROM v$instance;
COL x_db_name NEW_V x_db_name;
SELECT name x_db_name FROM v$database;
COL x_container NEW_V x_container;
SELECT 'NONE' x_container FROM DUAL;
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') x_container FROM DUAL;
COL num_cpu_cores NEW_V num_cpu_cores;
SELECT TO_CHAR(value) num_cpu_cores FROM v$osstat WHERE stat_name = 'NUM_CPU_CORES';

CL BREAK
COL sql_text_100_only FOR A100 HEA 'SQL Text';
COL sample_date_time FOR A20 HEA 'Sample Date and Time';
COL samples FOR 9999,999 HEA 'Sessions';
COL on_cpu_or_wait_class FOR A14 HEA 'ON CPU or|Wait Class';
COL on_cpu_or_wait_event FOR A50 HEA 'ON CPU or Timed Event';
COL session_serial FOR A16 HEA 'Session,Serial';
COL blocking_session_serial FOR A16 HEA 'Blocking|Session,Serial';
COL machine FOR A60 HEA 'Application Server';
COL con_id FOR 999999;
COL plans FOR 99999 HEA 'Plans';
COL sessions FOR 9999,999 HEA 'Sessions|this SQL';

SPO ash_awr_sample_kiev_&&current_time..txt;
PRO HOST: &&x_host_name.
PRO CORES: &&num_cpu_cores.
PRO DATABASE: &&x_db_name.
PRO CONTAINER: &&x_container.
PRO SAMPLE_TIME: &&sample_time.

PRO
PRO ASH spikes by sample time and top SQL (spikes higher than &&num_cpu_cores. cores)
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

WITH
all_sql AS (
SELECT DISTINCT sql_id, sql_text FROM v$sql
UNION
SELECT DISTINCT sql_id, DBMS_LOB.SUBSTR(sql_text, 1000) FROM dba_hist_sqltext
),
all_sql_with_type AS (
SELECT sql_id, sql_text, 
       CASE 
         WHEN sql_text LIKE '/* addTransactionRow('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* checkStartRowValid('||CHR(37)||') */'||CHR(37) 
         THEN 'BEGIN'
         WHEN sql_text LIKE '/* findMatchingRows('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* readTransactionsSince('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* writeTransactionKeys('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* setValueByUpdate('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* setValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* deleteValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* exists('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* existsUnique('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* updateIdentityValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE 'LOCK TABLE '||CHR(37)||'KievTransactions IN EXCLUSIVE MODE'||CHR(37) 
           OR sql_text LIKE '/* getTransactionProgress('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* recordTransactionState('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* checkEndRowValid('||CHR(37)||') */'||CHR(37)
         THEN 'COMMIT'
         WHEN sql_text LIKE '/* getValues('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* getNextIdentityValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* performScanQuery('||CHR(37)||') */'||CHR(37)
         THEN 'READ'
         WHEN sql_text LIKE '/* populateBucketGCWorkspace */'||CHR(37) 
           OR sql_text LIKE '/* deleteBucketGarbage */'||CHR(37) 
           OR sql_text LIKE '/* Populate workspace for transaction GC */'||CHR(37) 
           OR sql_text LIKE '/* Delete garbage for transaction GC */'||CHR(37) 
           OR sql_text LIKE '/* Populate workspace in KTK GC */'||CHR(37) 
           OR sql_text LIKE '/* Delete garbage in KTK GC */'||CHR(37) 
         THEN 'GC'
        END application_module
  FROM all_sql
),
my_tx_sql AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       sql_id, MAX(sql_text) sql_text, MAX(application_module) application_module
  FROM all_sql_with_type
 WHERE application_module IS NOT NULL
  AND (  
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%C%' AND application_module = 'COMMIT') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%B%' AND application_module = 'BEGIN') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%R%' AND application_module = 'READ') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%G%' AND application_module = 'GC')
      )
 GROUP BY
       sql_id
),
ash_by_sample_and_sql AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       h.sample_time,
       h.sql_id,
       h.con_id,
       COUNT(*) samples,
       COUNT(DISTINCT h.sql_plan_hash_value) plans,
       ROW_NUMBER () OVER (PARTITION BY h.sample_time ORDER BY COUNT(*) DESC NULLS LAST, h.sql_id) row_number
  FROM v$active_session_history h
 WHERE CAST(h.sample_time AS DATE) BETWEEN TO_DATE('&&sample_time.', 'YYYY-MM-DD"T"HH24:MI:SS') - (0.5/60/24) AND TO_DATE('&&sample_time.', 'YYYY-MM-DD"T"HH24:MI:SS') + (0.5/60/24) -- +/- 0.5m
   AND h.sql_id IN (SELECT sql_id FROM my_tx_sql)
 GROUP BY
       h.sample_time,
       h.sql_id,
       h.con_id
)
SELECT TO_CHAR(CAST(h.sample_time AS DATE), 'YYYY-MM-DD"T"HH24:MI:SS') sample_date_time,
       SUM(h.samples) samples,
       MAX(CASE h.row_number WHEN 1 THEN h.sql_id END) sql_id,
       SUM(CASE h.row_number WHEN 1 THEN h.samples ELSE 0 END) sessions,
       MAX(CASE WHEN h.row_number = 1 AND h.sql_id IS NOT NULL THEN h.plans END) plans,
       MAX(CASE h.row_number WHEN 1 THEN h.con_id END) con_id,       
       MAX(CASE WHEN h.row_number = 1 AND h.sql_id IS NOT NULL THEN (SELECT SUBSTR(q.sql_text, 1, 100) FROM my_tx_sql q WHERE q.sql_id = h.sql_id AND ROWNUM = 1) END) sql_text_100_only
  FROM ash_by_sample_and_sql h
 GROUP BY
       h.sample_time
HAVING SUM(h.samples) >= &&num_cpu_cores.
 ORDER BY
       h.sample_time
/

PRO
PRO ASH by sample time and top SQL
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

WITH
all_sql AS (
SELECT DISTINCT sql_id, sql_text FROM v$sql
UNION
SELECT DISTINCT sql_id, DBMS_LOB.SUBSTR(sql_text, 1000) FROM dba_hist_sqltext
),
all_sql_with_type AS (
SELECT sql_id, sql_text, 
       CASE 
         WHEN sql_text LIKE '/* addTransactionRow('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* checkStartRowValid('||CHR(37)||') */'||CHR(37) 
         THEN 'BEGIN'
         WHEN sql_text LIKE '/* findMatchingRows('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* readTransactionsSince('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* writeTransactionKeys('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* setValueByUpdate('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* setValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* deleteValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* exists('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* existsUnique('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* updateIdentityValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE 'LOCK TABLE '||CHR(37)||'KievTransactions IN EXCLUSIVE MODE'||CHR(37) 
           OR sql_text LIKE '/* getTransactionProgress('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* recordTransactionState('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* checkEndRowValid('||CHR(37)||') */'||CHR(37)
         THEN 'COMMIT'
         WHEN sql_text LIKE '/* getValues('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* getNextIdentityValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* performScanQuery('||CHR(37)||') */'||CHR(37)
         THEN 'READ'
         WHEN sql_text LIKE '/* populateBucketGCWorkspace */'||CHR(37) 
           OR sql_text LIKE '/* deleteBucketGarbage */'||CHR(37) 
           OR sql_text LIKE '/* Populate workspace for transaction GC */'||CHR(37) 
           OR sql_text LIKE '/* Delete garbage for transaction GC */'||CHR(37) 
           OR sql_text LIKE '/* Populate workspace in KTK GC */'||CHR(37) 
           OR sql_text LIKE '/* Delete garbage in KTK GC */'||CHR(37) 
         THEN 'GC'
        END application_module
  FROM all_sql
),
my_tx_sql AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       sql_id, MAX(sql_text) sql_text, MAX(application_module) application_module
  FROM all_sql_with_type
 WHERE application_module IS NOT NULL
  AND (  
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%C%' AND application_module = 'COMMIT') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%B%' AND application_module = 'BEGIN') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%R%' AND application_module = 'READ') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%G%' AND application_module = 'GC')
      )
 GROUP BY
       sql_id
),
ash_by_sample_and_sql AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       h.sample_time,
       h.sql_id,
       h.con_id,
       COUNT(*) samples,
       COUNT(DISTINCT h.sql_plan_hash_value) plans,
       ROW_NUMBER () OVER (PARTITION BY h.sample_time ORDER BY COUNT(*) DESC NULLS LAST, h.sql_id) row_number
  FROM v$active_session_history h
 WHERE CAST(h.sample_time AS DATE) BETWEEN TO_DATE('&&sample_time.', 'YYYY-MM-DD"T"HH24:MI:SS') - (0.5/60/24) AND TO_DATE('&&sample_time.', 'YYYY-MM-DD"T"HH24:MI:SS') + (0.5/60/24) -- +/- 0.5m
   AND h.sql_id IN (SELECT sql_id FROM my_tx_sql)
 GROUP BY
       h.sample_time,
       h.sql_id,
       h.con_id
)
SELECT TO_CHAR(CAST(h.sample_time AS DATE), 'YYYY-MM-DD"T"HH24:MI:SS') sample_date_time,
       SUM(h.samples) samples,
       MAX(CASE h.row_number WHEN 1 THEN h.sql_id END) sql_id,
       SUM(CASE h.row_number WHEN 1 THEN h.samples ELSE 0 END) sessions,
       MAX(CASE WHEN h.row_number = 1 AND h.sql_id IS NOT NULL THEN h.plans END) plans,
       MAX(CASE h.row_number WHEN 1 THEN h.con_id END) con_id,       
       MAX(CASE WHEN h.row_number = 1 AND h.sql_id IS NOT NULL THEN (SELECT SUBSTR(q.sql_text, 1, 100) FROM my_tx_sql q WHERE q.sql_id = h.sql_id AND ROWNUM = 1) END) sql_text_100_only
  FROM ash_by_sample_and_sql h
 GROUP BY
       h.sample_time
 ORDER BY
       h.sample_time
/

BREAK ON sample_date_time SKIP 1;
PRO
PRO ASH by sample time, SQL_ID and timed class
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

WITH
all_sql AS (
SELECT DISTINCT sql_id, sql_text FROM v$sql
UNION
SELECT DISTINCT sql_id, DBMS_LOB.SUBSTR(sql_text, 1000) FROM dba_hist_sqltext
),
all_sql_with_type AS (
SELECT sql_id, sql_text, 
       CASE 
         WHEN sql_text LIKE '/* addTransactionRow('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* checkStartRowValid('||CHR(37)||') */'||CHR(37) 
         THEN 'BEGIN'
         WHEN sql_text LIKE '/* findMatchingRows('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* readTransactionsSince('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* writeTransactionKeys('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* setValueByUpdate('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* setValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* deleteValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* exists('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* existsUnique('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* updateIdentityValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE 'LOCK TABLE '||CHR(37)||'KievTransactions IN EXCLUSIVE MODE'||CHR(37) 
           OR sql_text LIKE '/* getTransactionProgress('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* recordTransactionState('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* checkEndRowValid('||CHR(37)||') */'||CHR(37)
         THEN 'COMMIT'
         WHEN sql_text LIKE '/* getValues('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* getNextIdentityValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* performScanQuery('||CHR(37)||') */'||CHR(37)
         THEN 'READ'
         WHEN sql_text LIKE '/* populateBucketGCWorkspace */'||CHR(37) 
           OR sql_text LIKE '/* deleteBucketGarbage */'||CHR(37) 
           OR sql_text LIKE '/* Populate workspace for transaction GC */'||CHR(37) 
           OR sql_text LIKE '/* Delete garbage for transaction GC */'||CHR(37) 
           OR sql_text LIKE '/* Populate workspace in KTK GC */'||CHR(37) 
           OR sql_text LIKE '/* Delete garbage in KTK GC */'||CHR(37) 
         THEN 'GC'
        END application_module
  FROM all_sql
),
my_tx_sql AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       sql_id, MAX(sql_text) sql_text, MAX(application_module) application_module
  FROM all_sql_with_type
 WHERE application_module IS NOT NULL
  AND (  
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%C%' AND application_module = 'COMMIT') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%B%' AND application_module = 'BEGIN') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%R%' AND application_module = 'READ') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%G%' AND application_module = 'GC')
      )
 GROUP BY
       sql_id
)
SELECT TO_CHAR(CAST(h.sample_time AS DATE), 'YYYY-MM-DD"T"HH24:MI:SS') sample_date_time,
       COUNT(*) samples, 
       h.sql_id,
       h.con_id,
       CASE h.session_state WHEN 'ON CPU' THEN h.session_state ELSE h.wait_class END on_cpu_or_wait_class,
       (SELECT SUBSTR(q.sql_text, 1, 100) FROM my_tx_sql q WHERE q.sql_id = h.sql_id AND ROWNUM = 1) sql_text_100_only
  FROM v$active_session_history h
 WHERE CAST(h.sample_time AS DATE) BETWEEN TO_DATE('&&sample_time.', 'YYYY-MM-DD"T"HH24:MI:SS') - (0.5/60/24) AND TO_DATE('&&sample_time.', 'YYYY-MM-DD"T"HH24:MI:SS') + (0.5/60/24) -- +/- 0.5m
   AND h.sql_id IN (SELECT sql_id FROM my_tx_sql)
 GROUP BY
       CAST(h.sample_time AS DATE),
       h.sql_id, 
       h.con_id,
       CASE h.session_state WHEN 'ON CPU' THEN h.session_state ELSE h.wait_class END
 ORDER BY
       CAST(h.sample_time AS DATE),
       samples DESC,
       h.sql_id,
       h.con_id,
       CASE h.session_state WHEN 'ON CPU' THEN h.session_state ELSE h.wait_class END
/

BREAK ON sample_date_time SKIP PAGE ON machine SKIP 1;
PRO
PRO ASH by sample time, appl server, session and SQL_ID
PRO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

WITH
all_sql AS (
SELECT DISTINCT sql_id, sql_text FROM v$sql
UNION
SELECT DISTINCT sql_id, DBMS_LOB.SUBSTR(sql_text, 1000) FROM dba_hist_sqltext
),
all_sql_with_type AS (
SELECT sql_id, sql_text, 
       CASE 
         WHEN sql_text LIKE '/* addTransactionRow('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* checkStartRowValid('||CHR(37)||') */'||CHR(37) 
         THEN 'BEGIN'
         WHEN sql_text LIKE '/* findMatchingRows('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* readTransactionsSince('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* writeTransactionKeys('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* setValueByUpdate('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* setValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* deleteValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* exists('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* existsUnique('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* updateIdentityValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE 'LOCK TABLE '||CHR(37)||'KievTransactions IN EXCLUSIVE MODE'||CHR(37) 
           OR sql_text LIKE '/* getTransactionProgress('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* recordTransactionState('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* checkEndRowValid('||CHR(37)||') */'||CHR(37)
         THEN 'COMMIT'
         WHEN sql_text LIKE '/* getValues('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* getNextIdentityValue('||CHR(37)||') */'||CHR(37) 
           OR sql_text LIKE '/* performScanQuery('||CHR(37)||') */'||CHR(37)
         THEN 'READ'
         WHEN sql_text LIKE '/* populateBucketGCWorkspace */'||CHR(37) 
           OR sql_text LIKE '/* deleteBucketGarbage */'||CHR(37) 
           OR sql_text LIKE '/* Populate workspace for transaction GC */'||CHR(37) 
           OR sql_text LIKE '/* Delete garbage for transaction GC */'||CHR(37) 
           OR sql_text LIKE '/* Populate workspace in KTK GC */'||CHR(37) 
           OR sql_text LIKE '/* Delete garbage in KTK GC */'||CHR(37) 
         THEN 'GC'
        END application_module
  FROM all_sql
),
my_tx_sql AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       sql_id, MAX(sql_text) sql_text, MAX(application_module) application_module
  FROM all_sql_with_type
 WHERE application_module IS NOT NULL
  AND (  
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%C%' AND application_module = 'COMMIT') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%B%' AND application_module = 'BEGIN') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%R%' AND application_module = 'READ') OR
         (NVL('&&kiev_tx.', 'CBRG') LIKE '%G%' AND application_module = 'GC')
      )
 GROUP BY
       sql_id
)
SELECT TO_CHAR(CAST(h.sample_time AS DATE), 'YYYY-MM-DD"T"HH24:MI:SS') sample_date_time,
       h.machine,
       h.session_id||','||h.session_serial# session_serial,
       h.blocking_session||','||h.blocking_session_serial# blocking_session_serial,
       h.sql_id,
       h.sql_plan_hash_value,
       h.sql_child_number,
       h.con_id,
       CASE h.session_state WHEN 'ON CPU' THEN h.session_state ELSE h.wait_class||' - '||h.event END on_cpu_or_wait_event,
       (SELECT SUBSTR(q.sql_text, 1, 100) FROM my_tx_sql q WHERE q.sql_id = h.sql_id AND ROWNUM = 1) sql_text_100_only
  FROM v$active_session_history h
 WHERE CAST(h.sample_time AS DATE) BETWEEN TO_DATE('&&sample_time.', 'YYYY-MM-DD"T"HH24:MI:SS') - (0.5/60/24) AND TO_DATE('&&sample_time.', 'YYYY-MM-DD"T"HH24:MI:SS') + (0.5/60/24) -- +/- 0.5m
   AND h.sql_id IN (SELECT sql_id FROM my_tx_sql)
 ORDER BY
       CAST(h.sample_time AS DATE),
       h.machine,
       h.session_id,
       h.session_serial#,
       h.sql_id
/

SPO OFF;
