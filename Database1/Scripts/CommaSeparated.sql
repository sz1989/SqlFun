declare @d varchar(max)
--select @d = @d + policy_id + ','
select @d = coalesce(@d + ',','') + policy_id
from policy
where activ_flg = 'a'
and policy_num <= 100

select @d

/* Or another Way uses XML path

DECLARE @Table1 TABLE(ID INT, Value INT);
INSERT INTO @Table1 VALUES (1,100),(1,200),(1,300),(1,400);

SELECT  ID
       ,STUFF((SELECT ', ' + CAST(Value AS VARCHAR(10)) [text()]
         FROM @Table1 
         WHERE ID = t.ID
         FOR XML PATH(''), TYPE)
        .value('.','NVARCHAR(MAX)'),1,2,'') List_Output
FROM @Table1 t
GROUP BY ID;

SELECT ',' + CAST(Value AS VARCHAR(10)) FROM @Table1 FOR XML PATH('')

*/
