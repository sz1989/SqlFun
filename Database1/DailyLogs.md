# What I did

# What's Next
- DB
    - inflation_index
        - change the current_login to modify_by
    - debt_cpi
        - enable temporal table
- C#
    - Create a test story to make sure 

# What Broke or Got Weird
- Circular reference on the InflationIndex

# What is ahead
- Docker client
- Cert for NuGet
- CQRS with Clean Architecture
- Using Project file as Nuspec
- Tunnel
- Telemetry

# Code
- EF
    ```                
    await context.Database.EnsureDeletedAsync();
    await context.Database.EnsureCreatedAsync();
    ```

# Existing logic
- GetDirty

# EarningsCalculator
- Adding an argument to skip the Exposure Calculation and not save the PolicyExposure and PolicyDebt

# EarningsCalculator Service that uses by the AGS
- 

# Stored Procedure
- 

# The ETL Service (no updates on the PolicyDebt and PolicyExposure)


https://prod.liveshare.vsengsaas.visualstudio.com/join?6C722F987B3E4B76EB32D8A124791071591A




