SET NOCOUNT ON
IF lower(@@SERVERNAME) IN ('sqlcoredev', 'sqldev3')
	BEGIN
	DECLARE @cnt INT = 1,  @user VARCHAR(128), @loginsql NVARCHAR(MAX), @usersql NVARCHAR(MAX),@permissionssql NVARCHAR(MAX)
	DECLARE @users TABLE
	(
		   [id] INT IDENTITY(1,1) NOT NULL,
		   [user] VARCHAR(128) NOT NULL
	)
	-----------------------------------------------------------------------------
	BEGIN
		   INSERT INTO @users ([user]) VALUES ('AGL\jzh'), ('AGL\devjzh'),
																		 ('AGL\mva'), ('AGL\devjzh'),
																		 ('AGL\map'), ('AGL\devmap'),
																		 ('AGL\jdy'), ('AGL\devjdy'),
																		 ('AGL\lxu'), ('AGL\devlxu'),
																		 ('AGL\dka'), ('AGL\devdka'),
																		 ('AGL\rqu'), ('AGL\devrqu'),
																		 ('AGL\apk'), ('AGL\devapk'),
																		 ('AGL\sah'), ('AGL\testsah')
	END
	-----------------------------------------------------------------------------

	WHILE (@cnt <= (SELECT COUNT(*) FROM @users))
	BEGIN
		   SELECT @user = [user] FROM @users WHERE [id] = @cnt
		   SELECT @loginsql = FORMATMESSAGE('
				  IF NOT EXISTS (SELECT name FROM master.sys.server_principals WHERE name = ''%s'') CREATE LOGIN [%s] FROM WINDOWS WITH DEFAULT_DATABASE=[das], DEFAULT_LANGUAGE=[us_english]', @user,@user)
		   SELECT @usersql = FORMATMESSAGE('IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = ''%s'') 
				CREATE USER [%s] FOR LOGIN [%s] WITH DEFAULT_SCHEMA = [dbo]       
				IF DATABASE_PRINCIPAL_ID(''test_user_role'') IS NULL
						 CREATE ROLE [test_user_role] AUTHORIZATION [dbo];

				  GRANT ALTER ANY ROLE TO [test_user_role]
				  ALTER ROLE [test_user_role] ADD MEMBER [%s]
		   ', @user,@user,@user,@user,@user, @user)

		   SELECT @usersql

		   --EXEC (@loginsql)

		   --EXEC das..sp_executesql @usersql;
		   --EXEC cusip_db..sp_executesql @usersql;
		   --EXEC intex..sp_executesql @usersql;
		   --EXEC ddf..sp_executesql @usersql;

		   SET @cnt = @cnt + 1;
	END
END
--USE das
--go

--GRANT SELECT ON OBJECT::[das].[dbo].[permissions] TO [test_user_role] AS [dbo];
--GRANT SELECT ON OBJECT::[das].[dbo].[fsa_staff] TO [test_user_role] AS [dbo];
--GRANT SELECT ON OBJECT::[das].[dbo].[user_roles_ad_vw] TO [test_user_role] AS [dbo];
-----------------------------------------------------------------------------
