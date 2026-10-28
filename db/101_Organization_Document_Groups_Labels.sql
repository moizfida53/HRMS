/* =====================================================================
   101_Organization_Document_Groups_Labels.sql  -  HRMS: labels
   ---------------------------------------------------------------------
   Safe to re-run. Labels only (English + Arabic): Workforce > Organizations
   - the companies in one row, the document categories (master) and the
   documents as cards (child): validity ring, expiry, required.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('od.collapse_all', 'od', N'Collapse all', N'طي الكل', NULL),
        ('od.expand_all', 'od', N'Expand all', N'توسيع الكل', NULL),
        ('od.categories', 'od', N'Categories', N'الفئات', NULL),
        ('od.all_documents', 'od', N'All documents', N'كل المستندات', NULL),
        ('od.required', 'od', N'Required', N'إلزامي', NULL),
        ('od.validity_left', 'od', N'{0}% of its validity left', N'تبقى {0}% من مدة صلاحيته', NULL),
        ('od.days_left', 'od', N'days left', N'يوم متبقٍ', NULL),
        ('od.days_over', 'od', N'days over', N'يوم تأخير', NULL),
        ('od.expires_on', 'od', N'Expires {0}', N'ينتهي في {0}', NULL),
        ('od.expired_on', 'od', N'Expired {0}', N'انتهى في {0}', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Organization document group labels inserted: ', @LabelsInserted);
GO
