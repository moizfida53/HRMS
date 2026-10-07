/* ================================================================
   HRMS Kuwait - Documents: Document Sections + DocumentTypes extension
   ----------------------------------------------------------------
   PURELY ADDITIVE, and idempotent (guarded by OBJECT_ID / COL_LENGTH),
   same pattern as db/08, db/13 and db/17.

   1. Creates [Documents].[DocumentSections] - the header/group that
      Document Types are listed under on the Employee Profile ->
      Documents tab (one band per section, ordered by Seq_num).

   2. Extends [Documents].[DocumentTypes] with:
        - SectionID            INT NULL  -> FK to DocumentSections(ID)
        - Attachment_Mandatory BIT NOT NULL DEFAULT 0
          (1 = the employee must have a file attached for this type)

   SectionID is NULL-able so existing DocumentTypes rows keep working
   until they are assigned to a section; the UI lists unassigned
   types under an "Other Documents" band.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF SCHEMA_ID(N'Documents') IS NULL
    EXEC (N'CREATE SCHEMA [Documents] AUTHORIZATION [dbo];');
GO

/* ================================================================
   1. Documents.DocumentSections
================================================================ */
IF OBJECT_ID(N'[Documents].[DocumentSections]', N'U') IS NULL
BEGIN
    CREATE TABLE [Documents].[DocumentSections]
    (
        [ID]               INT IDENTITY(1,1) NOT NULL,
        [Section_Name_Eng] NVARCHAR(150)     NOT NULL,
        [Section_Name_Arb] NVARCHAR(150)     NULL,
        [Seq_num]          INT               NOT NULL CONSTRAINT [DF_DocumentSections_Seq_num]  DEFAULT (0),
        [IsActive]         BIT               NOT NULL CONSTRAINT [DF_DocumentSections_IsActive] DEFAULT (1),

        CONSTRAINT [PK_DocumentSections] PRIMARY KEY CLUSTERED ([ID])
    );

    -- No two sections with the same English name
    CREATE UNIQUE NONCLUSTERED INDEX [UX_DocumentSections_Section_Name_Eng]
        ON [Documents].[DocumentSections] ([Section_Name_Eng]);

    -- Ordered listing of active sections (the Documents tab query)
    CREATE NONCLUSTERED INDEX [IX_DocumentSections_IsActive_Seq_num]
        ON [Documents].[DocumentSections] ([IsActive], [Seq_num])
        INCLUDE ([Section_Name_Eng], [Section_Name_Arb]);

    PRINT 'Created [Documents].[DocumentSections].';
END
GO

/* ================================================================
   2. Documents.DocumentTypes - SectionID + Attachment_Mandatory
================================================================ */
IF COL_LENGTH(N'[Documents].[DocumentTypes]', N'SectionID') IS NULL
BEGIN
    ALTER TABLE [Documents].[DocumentTypes]
        ADD [SectionID] INT NULL;
    PRINT 'Added [Documents].[DocumentTypes].[SectionID].';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys
               WHERE name = N'FK_DocumentTypes_DocumentSections'
                 AND parent_object_id = OBJECT_ID(N'[Documents].[DocumentTypes]'))
BEGIN
    ALTER TABLE [Documents].[DocumentTypes]
        ADD CONSTRAINT [FK_DocumentTypes_DocumentSections]
        FOREIGN KEY ([SectionID]) REFERENCES [Documents].[DocumentSections] ([ID]);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_DocumentTypes_SectionID'
                 AND object_id = OBJECT_ID(N'[Documents].[DocumentTypes]'))
BEGIN
    CREATE NONCLUSTERED INDEX [IX_DocumentTypes_SectionID]
        ON [Documents].[DocumentTypes] ([SectionID]);
END
GO

IF COL_LENGTH(N'[Documents].[DocumentTypes]', N'Attachment_Mandatory') IS NULL
BEGIN
    ALTER TABLE [Documents].[DocumentTypes]
        ADD [Attachment_Mandatory] BIT NOT NULL
            CONSTRAINT [DF_DocumentTypes_Attachment_Mandatory] DEFAULT (0)
            WITH VALUES;   -- existing rows get 0 (optional)
    PRINT 'Added [Documents].[DocumentTypes].[Attachment_Mandatory].';
END
GO

PRINT 'Documents: DocumentSections created; DocumentTypes extended with SectionID and Attachment_Mandatory.';
GO
