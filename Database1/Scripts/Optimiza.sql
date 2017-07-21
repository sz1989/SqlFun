DBCC FreeProcCache;
DBCC DROPCLEANBUFFERS; 

--CHECKPOINT;

SET STATISTICS TIME ON;
SET STATISTICS IO ON;


-- force to use index ex: FROM setamper s join debt_hist x with (index (debt_hist$pk_debt_hist)) on x.ipm_as_of_date = s.ipm_as_of_date 