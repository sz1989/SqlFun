select operation_id,message_time, package_name, message, message_source_name, subcomponent_name
from [SSISDB].[catalog].[event_messages] m 
where 
--[operation_id] >= 2097
--and 
event_name = 'OnError' 
and message not like '%policy closed%'
and package_name in ('PipeAllDirty.dtsx', 'LoadPipePartition.dtsx', 'LoadPipe.dtsx', 'UpdateETL.dtsx','ETLToOracle.dtsx')
and message_time >= '6/15/2017'
order by message_time desc


/*
 update policy set etl_abob = 1
 where policy_id in (select top 1000 policy_id from policy where activ_flg = 'A')
*/

/*
select policy_id from policy where etl_abob = 1
*/

/*

select *
from CalculatorHist
where CalculatorType = 1
and CreateDate >= '7/1/17' and CreateDate < '7/5/17'
and UserId = 'AGL\APP_SQL_PIPE_ETL_P'
--and error is not null
order by CreateDate desc

select CONVERT(DATE, CreateDate), count(1)
from CalculatorHist
where 
CalculatorType = 1
and UserId = 'AGL\APP_SQL_PIPE_ETL_P'
group by CONVERT(DATE, CreateDate)
order by 1 desc

*/

/*
Declare @execution_id bigint
EXEC [SSISDB].[catalog].[create_execution] @package_name=N'PipeAllDirty.dtsx', @execution_id=@execution_id OUTPUT, @folder_name=N'Pipe', @project_name=N'Ag.PipeService', @use32bitruntime=False, @reference_id=Null
Select @execution_id
DECLARE @var0 smallint = 1
EXEC [SSISDB].[catalog].[set_execution_parameter_value] @execution_id,  @object_type=50, @parameter_name=N'LOGGING_LEVEL', @parameter_value=@var0
EXEC [SSISDB].[catalog].[start_execution] @execution_id
GO
*/

/* find out FK ref. tables
SELECT OBJECT_NAME(f.parent_object_id) TableName, COL_NAME(fc.parent_object_id,fc.parent_column_id) ColName
FROM sys.foreign_keys AS f INNER JOIN sys.foreign_key_columns AS fc ON f.OBJECT_ID = fc.constraint_object_id
INNER JOIN sys.tables t ON t.OBJECT_ID = fc.referenced_object_id
WHERE OBJECT_NAME (f.referenced_object_id) = 'MonthlyEarnings'
*/

/* find out which FK is not trusted
SELECT name, is_disabled, is_not_trusted FROM sys.foreign_keys  where is_not_trusted = 1
*/