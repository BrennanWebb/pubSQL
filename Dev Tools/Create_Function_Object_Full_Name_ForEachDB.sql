USE master;

DECLARE @sql NVARCHAR(MAX);

SELECT @sql ='
	Use [?];
	Begin Try
	Drop function if exists dbo.Object_Full_Name;
	
	Exec (''CREATE FUNCTION dbo.Object_Full_Name(@ObjectId INT)
	RETURNS NVARCHAR(1000) 
	AS
	BEGIN
		DECLARE @fullObjectName NVARCHAR(1000);
		SELECT  @fullObjectName = QuoteName(DB_NAME()) + ''''.'''' + 
								  QuoteName(OBJECT_SCHEMA_NAME(@objectId)) + ''''.'''' + 
								  QuoteName(OBJECT_NAME(@objectId));
		RETURN  @fullObjectName;
	END;'');

	ALTER AUTHORIZATION ON OBJECT::dbo.Object_Full_Name TO guest;
	End Try
	Begin Catch
		print Error_Message();
	End Catch

	--Check our work
	Select DB_Name() DB,Object_Definition(Object_ID), *
	From sys.objects
	Where Type in(''FN'',''SN'')
	and name like ''%Object_Full_Name'';
';
EXEC sp_MSforeachdb @sql;
