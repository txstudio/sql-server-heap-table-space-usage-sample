/*
--https://www.sqlshack.com/how-to-determine-free-space-and-file-size-for-sql-server-databases/
DECLARE @FileGroupName sysname = N'PRIMARY';
 
;WITH src AS
(
  SELECT FG          = fg.name, 
         FileID      = f.file_id,
         LogicalName = f.name,
         [Path]      = f.physical_name, 
         FileSizeMB  = f.size/128.0, 
         UsedSpaceMB = CONVERT(bigint, FILEPROPERTY(f.[name], 'SpaceUsed'))/128.0, 
         GrowthMB    = CASE f.is_percent_growth WHEN 1 THEN NULL ELSE f.growth/128.0 END,
         MaxSizeMB   = NULLIF(f.max_size, -1)/128.0,
         DriveSizeMB = vs.total_bytes/1048576.0,
         DriveFreeMB = vs.available_bytes/1048576.0
  FROM sys.database_files AS f
  INNER JOIN sys.filegroups AS fg
        ON f.data_space_id = fg.data_space_id
  CROSS APPLY sys.dm_os_volume_stats(DB_ID(), f.file_id) AS vs
  --WHERE fg.name = COALESCE(@FileGroupName, fg.name)
)
SELECT [Filegroup] = FG, FileID, LogicalName, [Path],
  FileSizeMB  = CONVERT(decimal(18,2), FileSizeMB),
  FreeSpaceMB = CONVERT(decimal(18,2), FileSizeMB-UsedSpaceMB),
  [%]         = CONVERT(decimal(5,2), 100.0*(FileSizeMB-UsedSpaceMB)/FileSizeMB),
  GrowthMB    = COALESCE(RTRIM(CONVERT(decimal(18,2), GrowthMB)), '% warning!'),
  MaxSizeMB   = CONVERT(decimal(18,2), MaxSizeMB),
  DriveSizeMB = CONVERT(bigint, DriveSizeMB),
  DriveFreeMB = CONVERT(bigint, DriveFreeMB),
  [%]         = CONVERT(decimal(5,2), 100.0*(DriveFreeMB)/DriveSizeMB)
FROM src
ORDER BY FG, LogicalName;

--References link
--https://www.mssqltips.com/sqlservertip/2537/sql-server-row-count-for-all-tables-in-a-database/
SELECT
      QUOTENAME(SCHEMA_NAME(sOBJ.schema_id)) + '.' + QUOTENAME(sOBJ.name) AS [TableName]
      , SUM(sdmvPTNS.row_count) AS [RowCount]
FROM
      sys.objects AS sOBJ
      INNER JOIN sys.dm_db_partition_stats AS sdmvPTNS
            ON sOBJ.object_id = sdmvPTNS.object_id
WHERE 
      sOBJ.type = 'U'
      AND sOBJ.is_ms_shipped = 0x0
      AND sdmvPTNS.index_id < 2
	  AND QUOTENAME(sOBJ.name) IN (
		'[SalesOrderDetail_Clustered]','[SalesOrderDetail_Heap]'
	  )
GROUP BY
      sOBJ.schema_id
      , sOBJ.name
ORDER BY [TableName]
GO
*/

/*
DROP TABLE [Sales].[SalesOrderDetail_Heap]
GO

DROP TABLE [Sales].[SalesOrderDetail_Clustered]
GO

ALTER DATABASE [AdventureWorks2019] REMOVE FILE [Clustered_1]
GO

ALTER DATABASE [AdventureWorks2019] REMOVE FILEGROUP [Clustered]
GO

ALTER DATABASE [AdventureWorks2019] REMOVE FILE [Heap_1]
GO

ALTER DATABASE [AdventureWorks2019] REMOVE FILEGROUP [Heap]
GO
*/

--https://docs.microsoft.com/en-us/sql/relational-databases/databases/database-files-and-filegroups?view=sql-server-ver15
ALTER DATABASE [AdventureWorks2019]
	ADD FILEGROUP [Heap]
GO

ALTER DATABASE [AdventureWorks2019]
	ADD FILE
	(
		Name = N'Heap_1'
		, FILENAME = N'/var/opt/mssql/data/Heap_1.mdf'
		, SIZE = 5MB
		, FILEGROWTH = 5MB
	)
TO FILEGROUP [Heap]
GO

ALTER DATABASE [AdventureWorks2019]
	ADD FILEGROUP [Clustered]
GO

ALTER DATABASE [AdventureWorks2019]
	ADD FILE
	(
		Name = N'Clustered_1'
		, FILENAME = N'/var/opt/mssql/data/Clustered_1.mdf'
		, SIZE = 5MB
		, FILEGROWTH = 5MB
	)
TO FILEGROUP [Clustered]
GO

--CLUSTERED INDEX 沒有遞增屬性的話差異不大
CREATE TABLE [Sales].[SalesOrderDetail_Heap]
(
	[Id] [uniqueidentifier] NOT NULL DEFAULT NEWSEQUENTIALID(),
	[SalesOrderID] [int] NOT NULL,
	[SalesOrderDetailID] [int] NOT NULL,
	[CarrierTrackingNumber] [nvarchar](25) NULL,
	[OrderQty] [smallint] NOT NULL,
	[ProductID] [int] NOT NULL,
	[SpecialOfferID] [int] NOT NULL,
	[UnitPrice] [money] NOT NULL,
	[UnitPriceDiscount] [money] NOT NULL,
	[LineTotal]  AS (isnull(([UnitPrice]*((1.0)-[UnitPriceDiscount]))*[OrderQty],(0.0))),
	[rowguid] [uniqueidentifier] ROWGUIDCOL NOT NULL,
	[ModifiedDate] [datetime] NOT NULL,

	CONSTRAINT [PK_SalesOrderDetail_Heap] PRIMARY KEY NONCLUSTERED 
	(
		[Id] ASC
	)
) ON [Heap]
GO

CREATE TABLE [Sales].[SalesOrderDetail_Clustered]
(
	[Id] [uniqueidentifier] NOT NULL DEFAULT NEWSEQUENTIALID(),
	[SalesOrderID] [int] NOT NULL,
	[SalesOrderDetailID] [int] NOT NULL,
	[CarrierTrackingNumber] [nvarchar](25) NULL,
	[OrderQty] [smallint] NOT NULL,
	[ProductID] [int] NOT NULL,
	[SpecialOfferID] [int] NOT NULL,
	[UnitPrice] [money] NOT NULL,
	[UnitPriceDiscount] [money] NOT NULL,
	[LineTotal]  AS (isnull(([UnitPrice]*((1.0)-[UnitPriceDiscount]))*[OrderQty],(0.0))),
	[rowguid] [uniqueidentifier] ROWGUIDCOL NOT NULL,
	[ModifiedDate] [datetime] NOT NULL,

	CONSTRAINT [PK_SalesOrderDetail_Clustered] PRIMARY KEY CLUSTERED 
	(
		[Id] ASC
	)
) ON [Clustered]
GO

--Elasped: 3 minutes
DECLARE @index INT 

SET NOCOUNT ON
SET @index = 0

DECLARE @removeItems AS TABLE
(
	[Id] UNIQUEIDENTIFIER
)

WHILE @index < 30
BEGIN
	
	BEGIN TRANSACTION

	INSERT INTO [Sales].[SalesOrderDetail_Heap] (
		[SalesOrderID]
		,[SalesOrderDetailID]
		,[CarrierTrackingNumber]
		,[OrderQty]
		,[ProductID]
		,[SpecialOfferID]
		,[UnitPrice]
		,[UnitPriceDiscount]
		,[rowguid]
		,[ModifiedDate]
	)
	SELECT [SalesOrderID]
		,[SalesOrderDetailID]
		,[CarrierTrackingNumber]
		,[OrderQty]
		,[ProductID]
		,[SpecialOfferID]
		,[UnitPrice]
		,[UnitPriceDiscount]
		,[rowguid]
		,[ModifiedDate]
	FROM [Sales].[SalesOrderDetail] with (nolock)

	INSERT INTO [Sales].[SalesOrderDetail_Clustered] (
		[SalesOrderID]
		,[SalesOrderDetailID]
		,[CarrierTrackingNumber]
		,[OrderQty]
		,[ProductID]
		,[SpecialOfferID]
		,[UnitPrice]
		,[UnitPriceDiscount]
		,[rowguid]
		,[ModifiedDate]
	)
	SELECT [SalesOrderID]
		,[SalesOrderDetailID]
		,[CarrierTrackingNumber]
		,[OrderQty]
		,[ProductID]
		,[SpecialOfferID]
		,[UnitPrice]
		,[UnitPriceDiscount]
		,[rowguid]
		,[ModifiedDate]
	FROM [Sales].[SalesOrderDetail] with (nolock)

	INSERT INTO @removeItems ([Id])
		SELECT TOP (2500) [rowguid] 
		FROM [Sales].[SalesOrderDetail_Heap]
		ORDER BY NEWID()

	DELETE FROM [Sales].[SalesOrderDetail_Heap]
	WHERE [Id] IN (
		SELECT * FROM @removeItems
	)

	DELETE FROM [Sales].[SalesOrderDetail_Clustered]
	WHERE [Id] IN (
		SELECT * FROM @removeItems
	)

	DELETE FROM @removeItems
	
	COMMIT

	SET @Index = @Index + 1

END
GO

SELECT COUNT(*) FROM [Sales].[SalesOrderDetail_Heap] with (nolock)
SELECT COUNT(*) FROM [Sales].[SalesOrderDetail_Clustered] with (nolock)
GO