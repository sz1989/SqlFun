/*
WHILE (SELECT COUNT(1) FROM cusip_bb_price) > 0
BEGIN
	;WITH c AS (SELECT TOP 10000 * FROM cusip_bb_price) DELETE FROM c
END
*/