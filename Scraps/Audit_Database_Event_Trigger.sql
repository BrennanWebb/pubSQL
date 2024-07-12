
If not exists (Select * From sys.schemas where name = 'adt')
	Begin
		Create schema [adt];
	End; 
Go

If not exists (Select * From sys.tables where name = 'event' and schema_name(schema_id)='adt')
	Begin
		CREATE TABLE  [adt].[Event](
			Event_ID int identity(1,1) Primary Key,
			[Event_Data] [xml] NOT NULL
		) ON [PRIMARY]
	End
GO


CREATE OR ALTER view [adt].[v_Event]
as
SELECT
Event_ID,
[event_data].value('(/EVENT_INSTANCE/EventType)[1]','Varchar(150)')[EventType],
[event_data].value('(/EVENT_INSTANCE/PostTime)[1]','DATETIME')[Timestamp],
[event_data].value('(/EVENT_INSTANCE/LoginName)[1]','Varchar(150)')LoginName,
[event_data].value('(/EVENT_INSTANCE/UserName)[1]','Varchar(150)')UserName,
[event_data].value('(/EVENT_INSTANCE/DatabaseName)[1]','Varchar(150)')DatabaseName,
[event_data].value('(/EVENT_INSTANCE/SchemaName)[1]','Varchar(150)')SchemaName,
[event_data].value('(/EVENT_INSTANCE/ObjectName)[1]','Varchar(500)')ObjectName,
[event_data].value('(/EVENT_INSTANCE/ObjectType)[1]','Varchar(150)')ObjectType,
LTRIM([event_data].value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]','Varchar(max)'))CommandText,
[event_data].query('(/EVENT_INSTANCE/Parameters/Param)')[Parameters]
From adt.[Event];

GO

CREATE or Alter TRIGGER [trg_Event]
ON Database
FOR 
	DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;

	If SYSTEM_USER<>'SQIS-CORP\svc-prd_sql' --Don't log SQL Agent service accounts.  Modify as needed.
	Begin
		INSERT INTO [adt].[Event] (
			Event_Data
		)
		VALUES (
			EVENTDATA()
		);
	End;
	
	--Maintenance adt.event table.Keep only the last 100K events.
	Declare  @EventLimit bigint = (Select Isnull(Max(Event_ID),0)-100000 From adt.[Event])
	Delete from adt.[Event] Where Event_ID < @EventLimit ;

END;
GO

