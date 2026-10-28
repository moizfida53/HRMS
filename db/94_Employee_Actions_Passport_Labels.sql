/* =====================================================================
   94_Employee_Actions_Passport_Labels.sql  -  HRMS: labels for 93
   ---------------------------------------------------------------------
   Run after 93. Safe to re-run. Labels only (English + Arabic): the
   Actions menu of the Employees list, Passport In / Out, and the
   "fill in the mandatory fields" prompt of the employee profile.
   ===================================================================== */
SET NOCOUNT ON;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('emp.actions_named', 'emp', N'Actions for {0}', N'إجراءات {0}', NULL),
        ('emp.act_terminate', 'emp', N'Terminate employee', N'إنهاء خدمة الموظف', NULL),
        ('emp.act_renew_civil_id', 'emp', N'Renew Civil ID', N'تجديد البطاقة المدنية', NULL),
        ('emp.act_renew_passport', 'emp', N'Renew passport', N'تجديد جواز السفر', NULL),
        ('emp.act_passport_inout', 'emp', N'Passport In / Out', N'استلام وتسليم الجواز', NULL),
        ('emp.act_general', 'emp', N'General', N'عام', NULL),
        ('emp.pp_title', 'emp', N'Passport In / Out', N'استلام وتسليم الجواز', NULL),
        ('emp.pp_with_company', 'emp', N'With the company', N'لدى الشركة', NULL),
        ('emp.pp_with_employee', 'emp', N'With the employee', N'لدى الموظف', NULL),
        ('emp.pp_not_recorded', 'emp', N'Not recorded yet', N'غير مسجل بعد', NULL),
        ('emp.pp_expires', 'emp', N'Expires {0}', N'ينتهي في {0}', NULL),
        ('emp.pp_current_status', 'emp', N'Current status', N'الحالة الحالية', NULL),
        ('emp.pp_since', 'emp', N'since {0}', N'منذ {0}', NULL),
        ('emp.pp_no_passport', 'emp', N'No passport number yet - enter it on the employee''s Kuwait Compliance tab first.', N'لا يوجد رقم جواز بعد - أدخله أولاً في تبويب الامتثال الكويتي للموظف.', NULL),
        ('emp.pp_record_first', 'emp', N'Record where the passport is', N'سجّل مكان الجواز', NULL),
        ('emp.pp_passport_with', 'emp', N'Passport with', N'الجواز لدى', NULL),
        ('emp.pp_company', 'emp', N'Company', N'الشركة', NULL),
        ('emp.pp_employee', 'emp', N'Employee', N'الموظف', NULL),
        ('emp.pp_date_received', 'emp', N'Date of receiving', N'تاريخ الاستلام', NULL),
        ('emp.pp_date_handed', 'emp', N'Date handed over', N'تاريخ التسليم', NULL),
        ('emp.pp_transfer_company', 'emp', N'Transfer to company', N'تحويل إلى الشركة', NULL),
        ('emp.pp_transfer_employee', 'emp', N'Hand over to the employee', N'تسليم إلى الموظف', NULL),
        ('emp.pp_remarks', 'emp', N'Remarks', N'ملاحظات', NULL),
        ('emp.pp_remarks_hint', 'emp', N'Optional - e.g. for the residency renewal', N'اختياري - مثلاً لتجديد الإقامة', NULL),
        ('emp.pp_transactions', 'emp', N'Transactions', N'الحركات', NULL),
        ('emp.pp_export_excel', 'emp', N'Export to Excel', N'تصدير إلى إكسل', NULL),
        ('emp.pp_no_transactions', 'emp', N'No hand-over recorded yet.', N'لم يتم تسجيل أي استلام أو تسليم بعد.', NULL),
        ('emp.pp_date', 'emp', N'Date', N'التاريخ', NULL),
        ('emp.pp_entered_by', 'emp', N'Entered by', N'أدخله', NULL),
        ('emp.pp_view_transactions', 'emp', N'View transactions', N'عرض الحركات', NULL),
        ('emp.pp_hide_transactions', 'emp', N'Hide transactions', N'إخفاء الحركات', NULL),
        ('emp.pp_submit', 'emp', N'Submit', N'إرسال', NULL),
        ('emp.pp_x_passport_no', 'emp', N'Passport no.', N'رقم الجواز', NULL),
        ('emp.pp_x_entered_on', 'emp', N'Entered on', N'تاريخ الإدخال', NULL),
        ('sec.fn_passport_custody', 'sec', N'Passport In / Out', N'استلام وتسليم الجواز', NULL),
        ('sec.fn_passport_custody_hint', 'sec', N'Who holds the passport (company / employee) and the log of hand-overs', N'لدى من الجواز (الشركة / الموظف) وسجل الاستلام والتسليم', NULL),
        ('js.field_required', 'js', N'This field is required.', N'هذا الحقل مطلوب.', NULL),
        ('js.fill_mandatory_title', 'js', N'Fill in the mandatory fields', N'أكمل الحقول الإلزامية', NULL),
        ('js.fill_mandatory_text', 'js', N'These fields are required before the changes can be saved:', N'هذه الحقول مطلوبة قبل حفظ التغييرات:', NULL),
        ('js.fill_mandatory_ok', 'js', N'Fill in now', N'أكملها الآن', NULL),
        ('js.close', 'js', N'Close', N'إغلاق', NULL),
        ('js.pp_choose_holder', 'js', N'Choose who has the passport.', N'اختر لدى من الجواز.', NULL),
        ('js.pp_enter_date', 'js', N'Enter the date.', N'أدخل التاريخ.', NULL),
        ('msg.pp_not_found', 'msg', N'That employee was not found.', N'لم يتم العثور على هذا الموظف.', N'That employee was not found.'),
        ('msg.pp_choose', 'msg', N'Choose who has the passport.', N'اختر لدى من الجواز.', N'Choose who has the passport.'),
        ('msg.pp_no_number', 'msg', N'Enter the passport number on the Kuwait Compliance tab first.', N'أدخل رقم الجواز في تبويب الامتثال الكويتي أولاً.', N'Enter the passport number on the Kuwait Compliance tab first.'),
        ('msg.pp_date', 'msg', N'Enter the date.', N'أدخل التاريخ.', N'Enter the date.'),
        ('msg.pp_future', 'msg', N'The date cannot be in the future.', N'لا يمكن أن يكون التاريخ في المستقبل.', N'The date cannot be in the future.'),
        ('msg.pp_already_company', 'msg', N'The passport is already with the company.', N'الجواز لدى الشركة بالفعل.', N'The passport is already with the company.'),
        ('msg.pp_already_employee', 'msg', N'The passport is already with the employee.', N'الجواز لدى الموظف بالفعل.', N'The passport is already with the employee.'),
        ('msg.pp_before_last', 'msg', N'The date cannot be before the last hand-over ({0}).', N'لا يمكن أن يكون التاريخ قبل آخر استلام أو تسليم ({0}).', N'The date cannot be before the last hand-over ({0}).'),
        ('msg.pp_received', 'msg', N'Passport received by the company.', N'تم استلام الجواز من قبل الشركة.', N'Passport received by the company.'),
        ('msg.pp_handed', 'msg', N'Passport handed to the employee.', N'تم تسليم الجواز إلى الموظف.', N'Passport handed to the employee.')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Employee actions / passport labels inserted: ', @LabelsInserted);
GO
