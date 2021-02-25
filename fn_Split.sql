USE [master]
GO

/****** Object:  UserDefinedFunction [rpt].[Split]    Script Date: 2/25/2021 10:37:33 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[Split]
(
    @ListString nvarchar(max),
    @Delimiter  nvarchar(5)
) 
RETURNS @ListTable TABLE (ListValue nvarchar(1000))
AS
BEGIN

DECLARE @CurrentPosition int
DECLARE @NextPosition int
DECLARE @Item nvarchar(max)
DECLARE @ID int
DECLARE @Length int

SELECT 
	  @ID = 1
	, @Length = len(replace(@Delimiter, ' ', '^'))
	, @ListString = @ListString + @Delimiter
	, @CurrentPosition = 1 

SELECT @NextPosition = Charindex(@Delimiter, @ListString, @CurrentPosition)

WHILE @NextPosition > 0 
BEGIN
	SET @Item = SUBSTRING(@ListString, @CurrentPosition, @NextPosition-@CurrentPosition)
		IF LEN(@Item) >= 0 
			BEGIN 
			    INSERT INTO @ListTable (ListValue) 
			    VALUES (@Item)
				
				SET @ID = @ID+1
			END
	SET @CurrentPosition = @NextPosition + @Length
	SET @NextPosition = Charindex(@Delimiter, @ListString, @CurrentPosition)
END


RETURN
END


GO


