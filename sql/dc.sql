SET LIN 300 PAGES 100 VER OFF FEED OFF ECHO OFF SERVEROUT OFF;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('&&sql_id.', NULL, 'ADVANCED ALLSTATS LAST'));
