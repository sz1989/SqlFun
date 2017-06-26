/*
select policy.policy_id, rtrim(policy.policy_name)name, rtrim(policy.policy_abbr)policy_abbr, item.cusip, item.par_insured, item.created_dt
from policy join policy_pitem item on policy.policy_id = item.policy_id
--where policy.policy_num between 1 and 25
--for json auto, root

where policy.policy_id = '13'
for json auto, without_array_wrapper
*/

/*
declare @data as nvarchar(max)
set @data = (
select policy.policy_id, rtrim(policy.policy_name)name, rtrim(policy.policy_abbr)policy_abbr, item.cusip, item.par_insured, item.created_dt
from policy join policy_pitem item on policy.policy_id = item.policy_id
for json auto
)
select @data
*/

/*
select policy.policy_id [id], rtrim(policy.policy_name) [name], rtrim(policy.policy_abbr) [addr], item.cusip [i.cusip], item.par_insured [i.par], item.created_dt [i.created]
from policy join policy_pitem item on policy.policy_id = item.policy_id
where policy.policy_id = '13-B'
--for json auto
for json path
*/

select policy.policy_id [id], rtrim(policy.policy_name) [name], rtrim(policy.policy_abbr) [addr],
	(select cusip, par_insured, created_dt  
	from policy_pitem WHERE policy_id = policy.policy_id ) 
from policy
where policy.policy_id = '13-B'
--for json auto
for json path

--select policy_id
--from policy