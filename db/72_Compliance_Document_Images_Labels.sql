/* =====================================================================
   72_Compliance_Document_Images_Labels.sql  -  HRMS: labels for db/71
   ---------------------------------------------------------------------
   Run after 71. Safe to re-run. Labels only (English + Arabic): the
   Kuwait Compliance documents on the Documents tab, the confirm /
   renewal dialog, "Previous images" and the Kuwait Compliance thumbnails.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('kcd.applied_to', 'kcd', N'Applied to {0}', N'مطبّقة على {0}', NULL),
        ('kcd.applied_to_expiry', 'kcd', N'Applied to expiry', N'مطبّقة على تاريخ الانتهاء', NULL),
        ('kcd.archived_on', 'kcd', N'Archived {0}', N'مؤرشفة {0}', NULL),
        ('kcd.confirm_bar', 'kcd', N'New images uploaded - confirm they apply to the expiry date above.', N'تم رفع صور جديدة - أكّد أنها تنطبق على تاريخ الانتهاء أعلاه.', NULL),
        ('kcd.card_title', 'kcd', N'Kuwait Compliance documents', N'مستندات الامتثال الكويتي', NULL),
        ('kcd.card_sub', 'kcd', N'Civil ID, Passport, Residency and Work Permit images: confirm new images against the expiry date. From {0} days before the expiry, upload the renewed image and confirm it with the new date - the previous image is archived.', N'صور البطاقة المدنية وجواز السفر والإقامة وإذن العمل: أكّد الصور الجديدة على تاريخ الانتهاء. قبل {0} يوماً من الانتهاء، ارفع الصورة المجدّدة وأكّدها بالتاريخ الجديد - تُؤرشف الصورة السابقة.', NULL),
        ('kcd.confirm_bar_docs', 'kcd', N'New images uploaded - confirm them against the expiry date.', N'تم رفع صور جديدة - أكّدها على تاريخ الانتهاء.', NULL),
        ('kcd.expires_on', 'kcd', N'Expires {0}', N'تنتهي في {0}', NULL),
        ('kcd.no_expiry_date', 'kcd', N'No expiry date yet', N'لا يوجد تاريخ انتهاء بعد', NULL),
        ('kct.no_image', 'kct', N'No image uploaded - add it on the Documents tab', N'لم تُرفع صورة - أضفها من تبويب المستندات', NULL),
        ('kcd.confirm_hint_first', 'kcd', N'The images are applied to this expiry date and number, which are also saved on Kuwait Compliance.', N'تُطبَّق الصور على تاريخ الانتهاء والرقم هذين، ويُحفظان أيضاً في الامتثال الكويتي.', NULL),
        ('kcd.confirm_hint_renewal', 'kcd', N'Enter the new expiry date of the renewed document. The current images are archived (see Previous images) and the expiry date on Kuwait Compliance is updated.', N'أدخل تاريخ الانتهاء الجديد للمستند المجدّد. تُؤرشف الصور الحالية (راجع الصور السابقة) ويُحدَّث تاريخ الانتهاء في الامتثال الكويتي.', NULL),
        ('kcd.confirm_images', 'kcd', N'Confirm images', N'تأكيد الصور', NULL),
        ('kcd.confirm_renewal', 'kcd', N'Confirm renewal', N'تأكيد التجديد', NULL),
        ('kcd.confirm_title', 'kcd', N'Confirm {0} images', N'تأكيد صور {0}', NULL),
        ('kcd.confirmed_until', 'kcd', N'Confirmed · expires {0}', N'مؤكدة · تنتهي في {0}', NULL),
        ('kcd.current', 'kcd', N'Current', N'الحالية', NULL),
        ('kcd.current_expiry_was', 'kcd', N'The current images apply to {0}.', N'الصور الحالية مطبّقة على {0}.', NULL),
        ('kcd.discard_renewal', 'kcd', N'Discard the renewal image', N'تجاهل صورة التجديد', NULL),
        ('kcd.discard_renewal_q', 'kcd', N'Discard the renewal image?', N'تجاهل صورة التجديد؟', NULL),
        ('kcd.document_images', 'kcd', N'Document images', N'صور المستند', NULL),
        ('kcd.document_number', 'kcd', N'Document number', N'رقم المستند', NULL),
        ('kcd.due_bar', 'kcd', N'The expiry date is near - upload the renewed document with Update renewal image.', N'تاريخ الانتهاء قريب - ارفع المستند المجدّد من خلال تحديث صورة التجديد.', NULL),
        ('kcd.expired_days_ago', 'kcd', N'Expired {0} days ago', N'منتهية منذ {0} يوماً', NULL),
        ('kcd.expiry_date', 'kcd', N'Expiry date', N'تاريخ الانتهاء', NULL),
        ('kcd.image', 'kcd', N'Image', N'الصورة', NULL),
        ('kcd.item_civil_id', 'kcd', N'Civil ID', N'البطاقة المدنية', NULL),
        ('kcd.item_passport', 'kcd', N'Passport', N'جواز السفر', NULL),
        ('kcd.item_residency', 'kcd', N'Residency', N'الإقامة', NULL),
        ('kcd.item_work_permit', 'kcd', N'Work Permit', N'إذن العمل', NULL),
        ('kcd.new_expiry_date', 'kcd', N'New expiry date', N'تاريخ الانتهاء الجديد', NULL),
        ('kcd.no_images_yet', 'kcd', N'No images uploaded yet.', N'لم تُرفع أي صور بعد.', NULL),
        ('kcd.no_types_linked', 'kcd', N'No document type is linked to this item yet (Kuwait.ComplianceDocumentTypes).', N'لا يوجد نوع مستند مرتبط بهذا البند بعد (Kuwait.ComplianceDocumentTypes).', NULL),
        ('kcd.not_confirmed', 'kcd', N'Not confirmed', N'غير مؤكدة', NULL),
        ('kcd.not_uploaded', 'kcd', N'Not uploaded', N'لم تُرفع', NULL),
        ('kcd.partly_renewed', 'kcd', N'Partly renewed', N'مجدّد جزئياً', NULL),
        ('kcd.previous_document', 'kcd', N'Previous document ({0}) - upload the renewed image', N'المستند السابق ({0}) - ارفع الصورة المجدّدة', NULL),
        ('kcd.previous_images', 'kcd', N'Previous images', N'الصور السابقة', NULL),
        ('kcd.previous_images_of', 'kcd', N'Previous images · {0}', N'الصور السابقة · {0}', NULL),
        ('kcd.renewal', 'kcd', N'Renewal', N'تجديد', NULL),
        ('kcd.renewal_bar', 'kcd', N'Renewal images uploaded - confirm them with the new expiry date. Until then the current images stay in use.', N'تم رفع صور التجديد - أكّدها بتاريخ الانتهاء الجديد. حتى ذلك الحين تبقى الصور الحالية مستخدمة.', NULL),
        ('kcd.renewal_due_in', 'kcd', N'Renewal due · {0} days', N'التجديد مستحق · {0} يوماً', NULL),
        ('kcd.renewal_title', 'kcd', N'Confirm {0} renewal', N'تأكيد تجديد {0}', NULL),
        ('kcd.renewal_waiting', 'kcd', N'Renewal waiting confirmation', N'تجديد بانتظار التأكيد', NULL),
        ('kcd.replace_new_image', 'kcd', N'Replace new image', N'استبدال الصورة الجديدة', NULL),
        ('kcd.update_renewal_image', 'kcd', N'Update renewal image', N'تحديث صورة التجديد', NULL),
        ('kcd.upload_image', 'kcd', N'Upload image', N'رفع صورة', NULL),
        ('kcd.uploaded', 'kcd', N'Uploaded', N'تاريخ الرفع', NULL),
        ('kcd.view_image', 'kcd', N'View image', N'عرض الصورة', NULL),
        ('kcd.waiting_confirmation', 'kcd', N'Waiting for confirmation', N'بانتظار التأكيد', NULL),
        ('js.kcd_expiry_needed', 'js', N'Enter the expiry date the images apply to.', N'أدخل تاريخ الانتهاء الذي تنطبق عليه الصور.', NULL),
        ('js.kcd_too_big', 'js', N'The file is larger than {0} MB.', N'حجم الملف أكبر من {0} ميجابايت.', NULL),
        ('msg.kcd_expiry_needed', 'msg', N'Enter the expiry date the images apply to.', N'أدخل تاريخ الانتهاء الذي تنطبق عليه الصور.', N'Enter the expiry date the images apply to.'),
        ('msg.kcd_nothing_to_confirm', 'msg', N'There are no new images to confirm.', N'لا توجد صور جديدة لتأكيدها.', N'There are no new images to confirm.'),
        ('msg.kcd_after_current', 'msg', N'The new expiry date must be after the current one ({0}).', N'يجب أن يكون تاريخ الانتهاء الجديد بعد التاريخ الحالي ({0}).', N'The new expiry date must be after the current one ({0}).'),
        ('msg.kcd_renewal_confirmed', 'msg', N'Renewal confirmed - the previous images are archived and the expiry date is updated.', N'تم تأكيد التجديد - أُرشفت الصور السابقة وحُدّث تاريخ الانتهاء.', N'Renewal confirmed - the previous images are archived and the expiry date is updated.'),
        ('msg.kcd_confirmed', 'msg', N'Images confirmed against the expiry date.', N'تم تأكيد الصور على تاريخ الانتهاء.', N'Images confirmed against the expiry date.'),
        ('msg.kcd_renewal_uploaded', 'msg', N'Renewal image uploaded - confirm it with the new expiry date to apply it.', N'تم رفع صورة التجديد - أكّدها بتاريخ الانتهاء الجديد لتطبيقها.', N'Renewal image uploaded - confirm it with the new expiry date to apply it.'),
        ('msg.kcd_unknown_item', 'msg', N'Unknown compliance item.', N'بند امتثال غير معروف.', N'Unknown compliance item.')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Compliance image labels inserted: ', @LabelsInserted);
GO
