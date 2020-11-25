--select distinct(user_id)
--from ms_ee_queue
--where user_id like 'agl\%'

/*

declare @d varchar(max)
--select @d = @d + policy_id + ','
select @d = coalesce(@d + ',','') + policy_id
from policy
where activ_flg = 'a'
and policy_num <= 100

*/

declare @d varchar(max)
select @d = coalesce(@d + ',','') +  id
from (select distinct(user_id) as id
from ms_ee_queue
where user_id like 'agl\%') t

select @d

https://prod.liveshare.vsengsaas.visualstudio.com/join?5F63BA124CE54D5B889A876FB9BC99DD93BD 



