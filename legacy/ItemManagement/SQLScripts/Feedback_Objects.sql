/* ============================================================================
   FEEDBACK FEATURE - DATABASE OBJECTS
   ----------------------------------------------------------------------------
   Run this script once against the eMenu database.

   Existing tables used (already in your DB):
       Feedback_Layout (id, BrandID, Questions, Sequence, TypeId)
       Feedback_Type   (id, Type)            -- Star Rating / Smiley / Question / Text

   Feedback is now stored in TWO tables (header + detail):
       Feedback_Customer : one row per submission (who submitted + when)
       Feedback_Data     : one row per answered question, linked by CustomerID

   Objects created below:
       1. Table      dbo.Feedback_Customer        (created only if missing)
       2. Table      dbo.Feedback_Data            (created only if missing)
       3. Table TYPE dbo.FeedBackResponse         (TVP - name MUST match the C# class)
       4. Proc       dbo.sp_GetFeedbackFormQuestion
       5. Proc       dbo.sp_PostFeedbackData
   ============================================================================ */


/* ---------------------------------------------------------------------------
   1) Feedback_Customer  (header - one row per submission)

      NOTE: a primary-key IDENTITY column (CustomerID) is required so that each
      inserted customer row produces an id that Feedback_Data.CustomerID can
      reference (the proc reads it with SCOPE_IDENTITY()). If your existing
      table has no identity column, add one.

      Mobile and UDID are FLOAT per your schema. See the caveats in the proc.
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Feedback_Customer')
BEGIN
    CREATE TABLE [dbo].[Feedback_Customer]
    (
        [CustomerID]   INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_Feedback_Customer] PRIMARY KEY,
        [CustomerName] NVARCHAR(MAX) NULL,
        [Mobile]       FLOAT         NULL,
        [Email]        NVARCHAR(150) NULL,
        [UDID]         FLOAT         NULL,
        [BranchID]     INT           NULL,
        [DateTime]     DATETIME      NULL
    );
END
GO


/* ---------------------------------------------------------------------------
   2) Feedback_Data  (detail - one row per answered question)
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Feedback_Data')
BEGIN
    CREATE TABLE [dbo].[Feedback_Data]
    (
        [id]            INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_Feedback_Data] PRIMARY KEY,
        [CustomerID]    INT           NULL,
        [Question]      NVARCHAR(500) NULL,
        [Response_Type] INT           NULL,
        [Response]      NVARCHAR(500) NULL,
        [Datetime]      DATETIME      NULL
    );
END
GO


/* ---------------------------------------------------------------------------
   3) Table-Valued Parameter type for the submitted answers.

      DB.ToDataTable(List<FeedBackResponse>) names the DataTable after the class
      (typeof(T).Name = "FeedBackResponse") and ADO.NET uses that as the TVP
      type name, so this TYPE must be named exactly "FeedBackResponse" with the
      same columns/order as the C# class:
          public int    QuestionId    { get; set; }
          public int    Response_Type { get; set; }
          public string Response      { get; set; }
   --------------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.types WHERE name = 'FeedBackResponse' AND is_table_type = 1)
BEGIN
    CREATE TYPE [dbo].[FeedBackResponse] AS TABLE
    (
        [QuestionId]    INT           NULL,
        [Response_Type] INT           NULL,
        [Response]      NVARCHAR(500) NULL
    );
END
GO


/* ---------------------------------------------------------------------------
   4) Return the feedback questions for a brand, one per row, in sequence.
      Columns consumed by the JS wizard:
        LayoutID, Questions, FeedbackTypeid, Type, Sequence
   --------------------------------------------------------------------------- */
IF OBJECT_ID('[dbo].[sp_GetFeedbackFormQuestion]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_GetFeedbackFormQuestion];
GO
CREATE PROCEDURE [dbo].[sp_GetFeedbackFormQuestion]
    @BrandId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  fl.[id]        AS [LayoutID],
            fl.[Questions]  AS [Questions],
            fl.[TypeId]     AS [FeedbackTypeid],
            ft.[Type]       AS [Type],
            fl.[Sequence]   AS [Sequence]
    FROM        [dbo].[Feedback_Layout] fl
    INNER JOIN  [dbo].[Feedback_Type]   ft ON ft.[id] = fl.[TypeId]
    WHERE       fl.[BrandID] = @BrandId
    ORDER BY    fl.[Sequence] ASC, fl.[id] ASC;
END
GO


/* ---------------------------------------------------------------------------
   5) Insert a submitted feedback.
        - Writes ONE row into Feedback_Customer (the header).
        - Reads the new id with SCOPE_IDENTITY().
        - Writes ONE row per answered question into Feedback_Data using that id.
        - Question text is resolved from Feedback_Layout using QuestionId.
        - Returns a single column [result] = 'Success' (checked by the C# action).

      The C# action still passes @customerMobile and @UDID as strings; this proc
      converts them to FLOAT to fit the columns:
        * Mobile : separators ( +  -  space  ( ) ) are stripped, then converted.
                   A leading '+' / leading zeros cannot survive in a FLOAT.
        * UDID   : the client now sends a numeric device id, stored as FLOAT.
      TRY_CONVERT is used so a non-numeric value becomes NULL instead of erroring.

      >> Recommendation: Mobile and UDID are more reliably stored as NVARCHAR
         (phone numbers/device ids are identifiers, not quantities). If you switch
         those columns to NVARCHAR, simply replace the TRY_CONVERT(...) wrappers
         below with the raw @customerMobile / @UDID values.
   --------------------------------------------------------------------------- */
IF OBJECT_ID('[dbo].[sp_PostFeedbackData]', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_PostFeedbackData];
GO
CREATE PROCEDURE [dbo].[sp_PostFeedbackData]
    @BranchId          INT,
    @customerEmail     NVARCHAR(500) = NULL,
    @customerMobile    NVARCHAR(100) = NULL,
    @customerName      NVARCHAR(MAX) = NULL,
    @UDID              NVARCHAR(100) = NULL,
    @dttblFeedBackData [dbo].[FeedBackResponse] READONLY
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* digits-only mobile so it can land in a FLOAT column */
        DECLARE @MobileClean NVARCHAR(100) =
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(@customerMobile, ''),
            ' ', ''), '+', ''), '-', ''), '(', ''), ')', '');

        /* ---- header row ---- */
        INSERT INTO [dbo].[Feedback_Customer]
            ([CustomerName], [Mobile], [Email], [UDID], [BranchID], [DateTime])
        VALUES
        (
            @customerName,
            TRY_CONVERT(FLOAT, @MobileClean),
            LEFT(@customerEmail, 150),
            TRY_CONVERT(FLOAT, @UDID),
            @BranchId,
            GETDATE()
        );

        DECLARE @CustomerID INT = CAST(SCOPE_IDENTITY() AS INT);

        /* ---- one detail row per answered question ---- */
        INSERT INTO [dbo].[Feedback_Data]
            ([CustomerID], [Question], [Response_Type], [Response], [Datetime])
        SELECT
            @CustomerID,
            fl.[Questions],
            t.[Response_Type],
            t.[Response],
            GETDATE()
        FROM       @dttblFeedBackData t
        LEFT JOIN  [dbo].[Feedback_Layout] fl ON fl.[id] = t.[QuestionId];

        COMMIT TRANSACTION;

        SELECT 'Success' AS [result], @CustomerID AS [CustomerID];
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT 'Fail' AS [result], ERROR_MESSAGE() AS [ErrorMessage];
    END CATCH
END
GO
