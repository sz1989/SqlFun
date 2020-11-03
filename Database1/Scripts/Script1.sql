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

https://prod.liveshare.vsengsaas.visualstudio.com/join?771451B185181B1E0B761F6B335A61D510CA


		{{$Project::ETLWEBAPI_URL}}			
http://webapidev/api/OtherEarningsKind/AGReportLevelMap

US37406_DACAdj_SeedAGSRptLevel

foo.OrderBy(c => c.Value).ToArray()
{System.Collections.Generic.KeyValuePair<string, string>[27]}
    [0]: Key = "ACEG", Value = "AGC"
    [1]: Key = "AGC", Value = "AGC"
    [2]: Key = "RADA", Value = "AGC"
    [3]: Key = "RADR", Value = "AGC"
    [4]: Key = "UCAP", Value = "AGC"
    [5]: Key = "AGRE", Value = "AGC"
    [6]: Key = "ENRE", Value = "AGC"
    [7]: Key = "CAPR", Value = "AGC"
    [8]: Key = "CAPG", Value = "AGM"
    [9]: Key = "CGIC", Value = "AGM"
    [10]: Key = "FSA", Value = "AGM"
    [11]: Key = "FSAN", Value = "AGM"
    [12]: Key = "AGCU", Value = "AGM"
    [13]: Key = "FSAU", Value = "AGM"
    [14]: Key = "CIEU", Value = "AGM"
    [15]: Key = "MBUK", Value = "AGM"
    [16]: Key = "MAC", Value = "AGM"
    [17]: Key = "MAC1", Value = "AGM"
    [18]: Key = "MAC2", Value = "AGM"
    [19]: Key = "MAC3", Value = "AGM"
    [20]: Key = "AGFR", Value = "AGM"
    [21]: Key = "ACEC", Value = "AGR"
    [22]: Key = "AGR", Value = "AGR"
    [23]: Key = "AGRT", Value = "AGR"
    [24]: Key = "AGRO", Value = "AGR"
    [25]: Key = "CAMR", Value = "AGR"
    [26]: Key = "CAPC", Value = "AGR"
bar.OrderBy(c => c.Value).ToArray()
{System.Collections.Generic.KeyValuePair<string, string>[20]}
    [0]: Key = "AGC", Value = "AGC"
    [1]: Key = "AGRE", Value = "AGC"
    [2]: Key = "ENRE", Value = "AGC"
    [3]: Key = "RADA", Value = "AGC"
    [4]: Key = "RADR", Value = "AGC"
    [5]: Key = "UCAP", Value = "AGC"
    [6]: Key = "APEG", Value = "AGC"
    [7]: Key = "FSAB", Value = "AGM"
    [8]: Key = "FSAI", Value = "AGM"
    [9]: Key = "FSAN", Value = "AGM"
    [10]: Key = "FSAU", Value = "AGM"
    [11]: Key = "CIEU", Value = "AGM"
    [12]: Key = "MBUK", Value = "AGM"
    [13]: Key = "AGCU", Value = "AGM"
    [14]: Key = "AGFR", Value = "AGM"
    [15]: Key = "ACEC", Value = "AGRE"
    [16]: Key = "AGR", Value = "AGRE"
    [17]: Key = "AGRT", Value = "AGRE"
    [18]: Key = "CAMR", Value = "AGRE"
    [19]: Key = "CAPC", Value = "AGRE"

	
IF NOT EXISTS( SELECT 1 FROM COMPANYHIERARCHY WHERE CODE = 'AGM')
BEGIN
	INSERT COMPANYHIERARCHY (CODE, NAME, DESCRIPTION) 
	VALUES ('AGM','AGREPORTLEVEL','AG REPORTING LEVEL FOR AGM')

	INSERT COMPANYHIERARCHYLINK (COMPANYHIERARCHY_ID, COMPANY_ID)
	SELECT CH.ID, C.ID
	FROM COMPANY C, COMPANYHIERARCHY CH
	WHERE C.SHORTCODE IN ('FSANY','FSAUK','MACRP','AGFRA')
	AND CH.CODE = 'AGM'
END

IF NOT EXISTS( SELECT 1 FROM COMPANYHIERARCHY WHERE CODE = 'AGC')
BEGIN
	INSERT COMPANYHIERARCHY (CODE, NAME, DESCRIPTION) 
	VALUES ('AGC','AGREPORTLEVEL','AG REPORTING LEVEL FOR AGC')

	INSERT COMPANYHIERARCHYLINK (COMPANYHIERARCHY_ID, COMPANY_ID)
	SELECT CH.ID, C.ID
	FROM COMPANY C, COMPANYHIERARCHY CH
	WHERE C.SHORTCODE = 'AGCRP'
	AND CH.CODE = 'AGC'
END

IF NOT EXISTS( SELECT 1 FROM COMPANYHIERARCHY WHERE CODE = 'AGR')
BEGIN
	INSERT COMPANYHIERARCHY (CODE, NAME, DESCRIPTION) 
	VALUES ('AGR','AGREPORTLEVEL','AG REPORTING LEVEL FOR AGR')

	INSERT COMPANYHIERARCHYLINK (COMPANYHIERARCHY_ID, COMPANY_ID)
	SELECT CH.ID, C.ID
	FROM COMPANY C, COMPANYHIERARCHY CH
	WHERE C.SHORTCODE IN ('AGREL', 'AGROL')
	AND CH.CODE = 'AGR'
END

            var ret = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            using (var unit = new DasUnitOfWorkFactory().Create())
            {
                var repo = unit.Repository<CompanyTree>().Query();
                var repoBusLinkInternal = repo.Include(a => a.Company).Where(a => a.Hierarchy.Id == 5 && a.Company.InternalExternalFlag == CompanyRelativeLocation.Internal);
                var rpt = from r in repo
                          where r.Hierarchy.AahCode == null
                          select new { r.Hierarchy.Code, r.Company.Id };
                var parent = from p in repoBusLinkInternal
                             join r in rpt on p.Company.Id equals r.Id
                             select new { p.Company.Id, r.Code };
                var co = from p in parent
                         join c in repoBusLinkInternal
                         on p.Id equals c.Parent.Company.Id
                         select new { c.Company.ShortCode, p.Code };
                ret = co.ToDictionary(k => k.ShortCode, v => v.Code, StringComparer.OrdinalIgnoreCase);
            }
            return ret;
