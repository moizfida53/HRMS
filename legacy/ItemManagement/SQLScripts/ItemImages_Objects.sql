/* ============================================================================
   ITEM IMAGES (gallery) - DATABASE OBJECTS
   ----------------------------------------------------------------------------
   Adds a secondary-image gallery per item. The item's main image (IMAGENAME)
   stays the PRIMARY image; tblItemImages holds the additional images.

   Run this script once against the eMenu database.

   Objects:
     1. Table  dbo.tblItemImages          (created only if missing)
     2. Proc   dbo.sp_GetItemImages        - active images for an item
     3. Proc   dbo.sp_DeleteItemImages     - soft-delete all images for an item
     4. Proc   dbo.sp_AddItemImage         - insert one image row
   ============================================================================ */


/* ---------------------------------------------------------------------------
   1) tblItemImages  (skip if you already created it).
      An identity [id] is added so individual rows can be referenced.
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'tblItemImages')
BEGIN
    CREATE TABLE [dbo].[tblItemImages]
    (
        [id]        INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_tblItemImages] PRIMARY KEY,
        [ItemID]    INT            NULL,
        [Imagename] NVARCHAR(MAX)  NULL,
        [Seq_No]    INT            NULL,
        [Deleted]   BIT            NULL,
        [Datetime]  DATETIME       NULL
    );
END
GO


/* ---------------------------------------------------------------------------
   2) Active images for an item, in sequence order.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('[dbo].[sp_GetItemImages]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_GetItemImages];
GO
CREATE PROCEDURE [dbo].[sp_GetItemImages]
    @ItemID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  [id],
            [ItemID],
            [Imagename] AS [Imagename],
            [Seq_No]
    FROM    [dbo].[tblItemImages]
    WHERE   [ItemID] = @ItemID
      AND   ISNULL([Deleted], 0) = 0
    ORDER BY [Seq_No] ASC, [id] ASC;
END
GO


/* ---------------------------------------------------------------------------
   3) Soft-delete every image for an item (used before re-inserting on save).
   --------------------------------------------------------------------------- */
IF OBJECT_ID('[dbo].[sp_DeleteItemImages]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_DeleteItemImages];
GO
CREATE PROCEDURE [dbo].[sp_DeleteItemImages]
    @ItemID INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [dbo].[tblItemImages]
       SET [Deleted] = 1
     WHERE [ItemID] = @ItemID
       AND ISNULL([Deleted], 0) = 0;
END
GO


/* ---------------------------------------------------------------------------
   4) Insert one secondary image row.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('[dbo].[sp_AddItemImage]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_AddItemImage];
GO
CREATE PROCEDURE [dbo].[sp_AddItemImage]
    @ItemID    INT,
    @ImageName NVARCHAR(MAX),
    @Seq_No    INT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[tblItemImages]
        ([ItemID], [Imagename], [Seq_No], [Deleted], [Datetime])
    VALUES
        (@ItemID, @ImageName, @Seq_No, 0, GETDATE());
END
GO
