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
- Http Redirect

# Code
- EF
    ```                
    await context.Database.EnsureDeletedAsync();
    await context.Database.EnsureCreatedAsync();
    ```

