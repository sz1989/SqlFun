# Existing logic
- GetDirty

# EarningsCalculator
- Adding an argument to skip the Exposure Calculation and not save the PolicyExposure and PolicyDebt

# EarningsCalculator Service that uses by the AGS
- CalculatorController
    - PreCalculate (POST) -> ```easy_prc_debt_prj``` needs to call new CPI to save results in Debt_dss
    - ProcessVariableRate -> needs to call ProcessVairableRate
    - Calculate (not used)
    - CalculateConcurrent -> needs to call the new Exposure
- OtherEaringKindController (no updates are needed)
- PolicyServiceController
    - DerivedMaturityDate
    - CalculateDailySumOfBalances -> needs to call new Exposure ([CalculateDailySumOfBalances](https://dev.azure.com/agltd/BAGS/_git/Calculator?path=/Exposure/ExposureCalculation.cs&version=GBdevelop&line=59&lineEnd=112&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents))
    - CalculateDebtService -> needs to call new Exposure CalculateDebtService ([CalculateDebtService](https://dev.azure.com/agltd/BAGS/_git/Calculator?path=/Extensions/ItemExtensions.cs&version=GBdevelop&line=56&lineEnd=91&lineStartColumn=1&lineEndColumn=10&lineStyle=plain&_a=contents))

# Stored Procedure
- ```easy_prc_debt_prj```

# The ETL Service (no updates on the PolicyDebt and PolicyExposure)





