set echo on 
set timing on 
set feedback on 
set serveroutput on 

CREATE or REPLACE PROCEDURE RMANCATALOG_SETUP(OMNIBACKUP_PASSWORD IN VARCHAR2 DEFAULT NULL, 
					      RMAN_PASSWORD IN VARCHAR2 DEFAULT NULL,
					      TRACKING_FILE IN VARCHAR2 DEFAULT NULL,
					      V_DATAFILE IN VARCHAR2 DEFAULT NULL)
IS

CHECK_NUM           VARCHAR2(3) := '00';
PROC_NAME CONSTANT  VARCHAR2(30) := 'RMANCATALOG';
ERROR_MESSAGE       VARCHAR2(2000);
PROC_NAME_ERRO_NUM  VARCHAR2(2000);
SQL_STATEMENT       VARCHAR2(500);
RMAN_TEST           VARCHAR2(50);
OMNIBACKUP_TEST     VARCHAR2(50);
ARCHIVE_MODE       VARCHAR2(50);

--Types
  TYPE INIT_SETTINGS IS TABLE OF V$PARAMETER.NAME%TYPE;

  --Collections of Types
    C_INIT_SETTINGS INIT_SETTINGS;


BEGIN 
-- Create catalog tablespace 

IF V_DATAFILE is NOT NULL
THEN 
       SQL_STATEMENT:='CREATE TABLESPACE CATALOG DATAFILE '||''''||V_DATAFILE||''''||' size 1024M autoextend on maxsize 8000M';
       EXECUTE IMMEDIATE SQL_STATEMENT;
       CHECK_NUM  := '01';
 END IF; 

  -- Create omnibackup user
IF OMNIBACKUP_PASSWORD IS NOT NULL
THEN
       SQL_STATEMENT:='CREATE USER OMNIBACKUP IDENTIFIED BY '||OMNIBACKUP_PASSWORD ||' DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP';
       EXECUTE IMMEDIATE SQL_STATEMENT;
      CHECK_NUM  := '02';

-- Grant sysdba to omnibackup
       SQL_STATEMENT:='GRANT SYSDBA,CONNECT TO OMNIBACKUP';
       EXECUTE IMMEDIATE SQL_STATEMENT;
      CHECK_NUM  := '02a';
END IF;

-- create rman user
IF RMAN_PASSWORD IS NOT NULL AND V_DATAFILE IS NOT NULL
THEN
       SQL_STATEMENT:='CREATE USER RMAN IDENTIFIED by '||RMAN_PASSWORD ||' DEFAULT TABLESPACE CATALOG TEMPORARY TABLESPACE TEMP'||
		       'QUOTA UNLIMITED CATALOG';
	EXECUTE IMMEDIATE SQL_STATEMENT;
     CHECK_NUM  := '03';

      SQL_STATEMENT:='GRANT RECOVERY_CATALOG_OWNER TO RMAN';
       EXECUTE IMMEDIATE SQL_STATEMENT;
     CHECK_NUM  := '03b';
END IF;


IF TRACKING_FILE IS NOT NULL
     THEN
       SQL_STATEMENT:='ALTER DATABASE ENABLE BLOCK CHANGE TRACKING USING FILE' ||''''|| TRACKING_FILE||'''';
       EXECUTE IMMEDIATE SQL_STATEMENT;
       CHECK_NUM  := '04';
    END IF;

-- check init settings  (SGA_MAX, SGA_TARGET, PGA_A, password file
    select name BULK COLLECT INTO C_INIT_SETTINGS
    from ( select  case when name='backup_tape_io_slaves' then name||':must be TRUE'
		        when name='pga_aggregate_target' Then name||':must be set'
		        when name='processes'  THEN name||':must be more than 100'
		        when name='sessions' THEN name||':must be more than 200'
			when name='sga_max_size' and value is not null THEN name||':must not be set'
		        when name='sga_target' THEN name||':must not be null'
			when name='spfile' THEN name||':must be set'
			when name='remote_login_password' THEN name||':must be set to EXCLUSIVE'
			when name='control_file_record_keep_time' THEN name||':must be 45 or more'
			when name='archive_lag_target' THEN name ||':must to set to 900'
			when name='db_domain' THEN name||':must not be set to '''''
			when name='log_archive_dest_1' THEN name||':must be set'
			--when name='log_archive_start' THEN name||':must be TRUE'
		 ELSE NULL END as name ,
	    case when name='backup_tape_io_slaves' and value='TRUE' then 'PASS'
		 when name='pga_aggregate_target' and value is not NULL Then 'PASS'
	         when name='processes' and value>100 THEN 'PASS'
		 when name='sessions' and value >200 THEN 'PASS'
		 when name='sga_max_size' and value is not null THEN 'PASS'
		 when name='sga_target' and value is not null THEN 'PASS'
		 when name='spfile' and value is not null THEN 'PASS'
		 when name='remote_login_password' and value ='EXCLUSIVE' THEN 'PASS'
		 when name='control_file_record_keep_time' and value >44 THEN 'PASS'
		 when name='archive_lag_target' and value >899 THEN 'PASS'
		 when name='db_domain' and value is null THEN 'PASS'
		 --when name='log_archive_start' and value ='TRUE' THEN 'PASS'
	         when name='log_archive_dest_1' and value is not null THEN 'PASS'
	    ELSE 'FAIL' END as value
	   from v$parameter
	   where name in ('archive_lag_target','backup_tape_io_slaves','control_file_record_keep_time',
			  'db_domain','log_archive_dest_1','log_archive_start','processes','sessions', 'sga_max_size', 'sga_target',
			  'pga_aggregate_target', 'remote_login_password' ,'spfile')
	   )
       where value='FAIL'
       order by name;

  FOR i in C_INIT_SETTINGS.FIRST .. C_INIT_SETTINGS.LAST
	LOOP
	  DBMS_OUTPUT.PUT_LINE('This init parameter is not set correctly: '||C_INIT_SETTINGS(i) );
        END LOOP;
 CHECK_NUM  := '05';

 -- check init settings  (SGA_MAX, SGA_TARGET, PGA_A, password file
     select ARCHIVER into ARCHIVE_MODE
     from v$instance;

   IF archive_mode ='FAIL' THEN
    DBMS_OUTPUT.PUT_LINE('The Database is not in archive log mode.');
   END if;

 CHECK_NUM  := '06';

 EXCEPTION
    WHEN OTHERS THEN
    PROC_NAME_ERRO_NUM := to_char(sqlcode)||','||CHECK_NUM||','||PROC_NAME;
    ERROR_MESSAGE := to_char(sqlerrm);
    DBMS_OUTPUT.PUT_LINE('The Procedure broke with '||ERROR_MESSAGE);
 /* SHOW_EXCEPTIONS(ERROR_MESSAGE,PROC_NAME_ERRO_NUM); */

END RMANCATALOG_SETUP;
/
