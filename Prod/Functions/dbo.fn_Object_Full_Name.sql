USE [msdb]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO

CREATE FUNCTION [dbo].[Object_Full_Name](@ObjectId INT)
	RETURNS NVARCHAR(1000) 
	AS
	BEGIN
		DECLARE @fullObjectName NVARCHAR(1000);
		SELECT  @fullObjectName = QuoteName(DB_NAME()) + '.' + 
								  QuoteName(OBJECT_SCHEMA_NAME(@objectId)) + '.' + 
								  QuoteName(OBJECT_NAME(@objectId));
		RETURN  @fullObjectName;
	END;
GO


