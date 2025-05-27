# What I did

# What's Next
- DB
    - inflation_index
        - Change the current_login to modify_by
    - debt_cpi
        - Enable temporal table
- C#
    - Create a test story to make sure 
- Earning Calculator
    Find out what does the app.config.deploy file do
    Making the cpi code update is in the Ling's repo  11/9/23

# What Broke or Got Weird
- Circular reference on the InflationIndex

# What is ahead
- Docker client
- Cert for NuGet
- CQRS with Clean Architecture
- Using the Project file as Nuspec
- Tunnel
- Telemetry

# Code
- EF
    ```                
    await context.Database.EnsureDeletedAsync();
    await context.Database.EnsureCreatedAsync();
    ```
# YAML
- Sample
    https://github.com/Humanizr/Humanizer/blob/main/azure-pipelines.yml
    
# Existing logic
- GetDirty

# EarningsCalculator
- Adding an argument to skip the Exposure Calculation and not save the PolicyExposure and PolicyDebt
- Run variable rate though web api cusiprate/queue

# EarningsCalculator Service EndPoints that the AGS uses
- 

# Stored Procedure
- 

# The ETL Service (no updates on the PolicyDebt and PolicyExposure)

# The Exposure Calculation




