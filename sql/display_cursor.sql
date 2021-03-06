SET LIN 300 PAGES 100 VER OFF FEED OFF ECHO OFF SERVEROUT OFF;
PRO FORMAT: 
PRO BASIC, TYPICAL, ALL, ALL ALLSTATS, ALL ALLSTATS LAST, 
PRO ADVANCED, ADVANCED ALLSTATS, ADVANCED ALLSTATS LAST (default)
WITH prev AS 
(SELECT prev_sql_id sql_id, prev_child_number child_number 
FROM v$session WHERE sid = SYS_CONTEXT('USERENV', 'SID'))
SELECT plan.plan_table_output execution_plan 
FROM prev, TABLE(DBMS_XPLAN.DISPLAY_CURSOR(prev.sql_id, prev.child_number, 
NVL('&format.', 'ADVANCED ALLSTATS LAST'))) plan
/
