Use Master
go

Create proc dbo.sp_Scripter (@script varchar(50) = null, @Like varchar(50)=null,@help bit=0,@search varchar(50)=null,@replace varchar(50)=null)
as

If @script is null
	Begin
		set @help=1
	End;
If @help=0 and PATINDEX('%'+@script+'%','DFDrop')>=1
	Begin
		Select  'alter table '+quotename(S.name)+'.'+quotename(T.name)+' drop constraint '+quotename(d.name) DFDrop
		From sys.default_constraints d
		inner join sys.columns c ON d.parent_object_id = c.object_id AND d.parent_column_id = c.column_id  
		inner join sys.tables t on c.object_id=t.object_id
		inner join sys.schemas s on t.schema_id=s.schema_id
		Where c.name like '%'+isnull(@Like,'')+'%';
	End;
If @help=0 and PATINDEX('%'+@script+'%','FKDrop')>=1
	Begin
		Select 'alter table '+quotename(S.name)+'.'+quotename(T.name)+' drop constraint '+quotename(f.name) FKDrop
		From sys.foreign_keys f
		inner join sys.foreign_key_columns fkc on fkc.constraint_object_id = f.object_id
		inner join sys.tables t on t.object_id=f.parent_object_id
		inner join sys.columns c on c.column_id = fkc.parent_column_id and c.object_id = t.object_id 
		inner join sys.schemas s on t.schema_id=s.schema_id
		Where c.name like '%'+isnull(@Like,'')+'%';
	End;
If @help=0 and PATINDEX('%'+@script+'%','ConstraintDrop')>=1
	Begin
		Select distinct 'alter table '+quotename(S.name)+'.'+quotename(T.name)+' drop constraint '+quotename(k.name) ConstraintDrop
		FROM sys.key_constraints k
		inner join sys.tables t on t.object_id=k.parent_object_id
		inner join sys.schemas s on t.schema_id=s.schema_id
		Where exists (Select * 
						From sys.columns c Where c.object_id = t.object_id 
						and c.name like '%'+isnull(@Like,'')+'%');
	End;
If @help=0 and PATINDEX('%'+@script+'%','TriggerDrop')>=1
	Begin
		Select 'drop trigger '+quotename(S.name)+'.'+quotename(Tr.name) TriggerDrop
		From sys.triggers tr
		inner join sys.tables t on tr.parent_id=t.object_id
		inner join sys.schemas s on t.schema_id=s.schema_id
		Where tr.name like '%'+isnull(@Like,'')+'%';
	End;

If @help=0 and PATINDEX('%'+@script+'%','ColumnDrop')>=1
	Begin
		Select 'alter table '+quotename(S.name)+'.'+quotename(T.name)+' drop column '+quotename(c.name) ColumnDrop
		From sys.columns c
		inner join sys.tables t on c.object_id=t.object_id
		inner join sys.schemas s on t.schema_id=s.schema_id
		Where c.name like '%'+isnull(@Like,'')+'%';
	End;

If @help=0 and PATINDEX('%'+@script+'%','TableDrop')>=1
	Begin
		Select 'drop table '+quotename(S.name)+'.'+quotename(T.name) TableDrop
		From sys.tables t 
		inner join sys.schemas s on t.schema_id=s.schema_id
		Where t.name like '%'+isnull(@Like,'')+'%';
	End;

If @help=0 and PATINDEX('%'+@script+'%','TableColumnDrop')>=1
	Begin
		Select distinct 'drop table '+quotename(S.name)+'.'+quotename(T.name) TableColumnDrop
		From sys.columns c
		inner join sys.tables t on c.object_id=t.object_id
		inner join sys.schemas s on t.schema_id=s.schema_id
		Where c.name like '%'+isnull(@Like,'')+'%';
	End;

If @help=0 and PATINDEX('%'+@script+'%','ColumnRename')>=1
	Begin
		Select 'EXEC sp_rename '''+quotename(S.name)+'.'+quotename(T.name)+'.'+c.name+''', '''+Replace(c.name,@search,@replace) +''', ''Column'';' ColumnRename
		From sys.columns c
		inner join sys.tables t on c.object_id=t.object_id
		inner join sys.schemas s on t.schema_id=s.schema_id
		Where c.name like '%'+isnull(@Like,'')+'%';
	End;

If @help=1
	Begin
		Select 'Exec dbo.sp_Scripter @script =''DFDrop'',@like =''test''' Script,'Default Constraint Drop. Default constraint search is column oriented based on @like search term.' Notes
		Union All
		Select 'Exec dbo.sp_Scripter @script =''FKDrop'',@like =''test''' Script,'Foreign Key Drop. Foreign Key search is column oriented based on @like search term.' Notes
		Union All
		Select 'Exec dbo.sp_Scripter @script =''ConstraintDrop'',@like =''test''' Script,'Constraint Drop. Default constraint search is column oriented based on @like search term.' Notes
		Union All
		Select 'Exec dbo.sp_Scripter @script =''TriggerDrop'',@like =''test''' Script,'Trigger Drop. Trigger search is column oriented based on @like search term.' Notes
		Union All
		Select 'Exec dbo.sp_Scripter @script =''ColumnDrop'',@like =''test''' Script,'Column Drop. Column search is column oriented based on @like search term.' Notes
		Union All
		Select 'Exec dbo.sp_Scripter @script =''TableDrop'',@like =''test''' Script,'Table Drop. Table search is table oriented based on @like search term.' Notes
		Union All
		Select 'Exec dbo.sp_Scripter @script =''TableColumnDrop'',@like =''test''' Script,'Table Drop. Table search is column oriented based on @like search term.' Notes
		Union All
		Select 'Exec dbo.sp_Scripter @script =''ColumnRename'',@like =''test''' Script,'Column Rename. Rename search is column oriented based on @like search term.' Notes
		;
	End;

