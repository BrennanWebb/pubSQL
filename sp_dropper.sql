Use Commissions_CCA
go

Create proc sp_dropper (@ColumnLike varchar(50) =Null)
as

Select  'alter table '+quotename(S.name)+'.'+quotename(T.name)+' drop constraint '+quotename(d.name) ConstraintDrop
From sys.default_constraints d
inner join sys.columns c ON d.parent_object_id = c.object_id AND d.parent_column_id = c.column_id  
inner join sys.tables t on c.object_id=t.object_id
inner join sys.schemas s on t.schema_id=s.schema_id
Where c.name like isnull(@ColumnLike,'')+'%';

Select 'alter table '+quotename(S.name)+'.'+quotename(T.name)+' drop constraint '+quotename(f.name) FKDrop
From sys.foreign_keys f
inner join sys.foreign_key_columns fkc on fkc.constraint_object_id = f.object_id
inner join sys.tables t on t.object_id=f.parent_object_id
inner join sys.columns c on c.column_id = fkc.parent_column_id and c.object_id = t.object_id 
inner join sys.schemas s on t.schema_id=s.schema_id
Where c.name like isnull(@ColumnLike,'')+'%';

Select distinct 'alter table '+quotename(S.name)+'.'+quotename(T.name)+' drop constraint '+quotename(k.name) ConstraintDrop
FROM sys.key_constraints k
inner join sys.tables t on t.object_id=k.parent_object_id
inner join sys.schemas s on t.schema_id=s.schema_id
Where exists (Select * 
				From sys.columns c Where c.object_id = t.object_id 
				and c.name like isnull(@ColumnLike,'')+'%')
;

Select 'drop trigger '+quotename(S.name)+'.'+quotename(Tr.name) TriggerDrop
From sys.triggers tr
inner join sys.tables t on tr.parent_id=t.object_id
inner join sys.schemas s on t.schema_id=s.schema_id
Where tr.name like isnull(@ColumnLike,'')+'%';

Select 'alter table '+quotename(S.name)+'.'+quotename(T.name)+' drop column '+quotename(c.name) ColumnDrop
From sys.columns c
inner join sys.tables t on c.object_id=t.object_id
inner join sys.schemas s on t.schema_id=s.schema_id
Where c.name like isnull(@ColumnLike,'')+'%';

