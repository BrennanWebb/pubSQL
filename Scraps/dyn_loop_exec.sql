use commissions_cca
go
Drop table if exists #loop
Select identity(int,1,1) rid
,c.name colname,t.name tblname,s.name schname,tr.name trname
into #loop
From sys.tables t
inner join sys.columns c on t.object_id=c.object_id
inner join sys.schemas s on t.schema_id=s.schema_id
Left join sys.triggers tr on t.object_id=tr.parent_id
Where c.name ='modified'
; 

declare @i int=1, @sql varchar(max), @tblname varchar(150), @colname varchar(150), @schname varchar(150);
while @i<=(Select max(rid) from #loop)
Begin
	set @tblname = (Select tblname From #loop where rid=@i);
	set @colname = (Select colname From #loop where rid=@i);
	set @schname = (Select schname From #loop where rid=@i);

Set @sql='
	Alter TRIGGER '+@schname+'.trg_modified_'+@tblname+'
	ON Commissions_CCA.'+@schname+'.'+@tblname+'
	AFTER UPDATE
	AS

	Set nocount on
	Update A
	Set modified = getdate()
	From Commissions_CCA.'+@schname+'.'+@tblname+' a
	Inner join inserted on a.id=inserted.id
	Where inserted.id = a.id
	'
	print @sql
	Exec(@sql)
	set @i=@i+1;	
End
