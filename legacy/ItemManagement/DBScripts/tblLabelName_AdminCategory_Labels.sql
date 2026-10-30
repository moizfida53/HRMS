/* ============================================================================
   tblLabelName_AdminCategory_Labels.sql
   ----------------------------------------------------------------------------
   Adds the Arabic/English UI labels for the ADMIN "Category / Item Management"
   page (Views/Category/Index.cshtml + Views/Shared/_LayoutNew.cshtml header +
   MainJs/Category.js runtime messages).

   HOW IT PLUGS IN
   ---------------
   * tblLabelName already has 178 rows (MAX(id)=178) used by the CUSTOMER menu,
     which binds those rows BY POSITION (objLabels[0..]). To avoid shifting any
     of those indices, this script only APPENDS new rows (id 179+). The customer
     page never references the new rows, so it is completely unaffected.
   * Every new key is prefixed "adm_" so it can never collide with an existing
     labelName, and the admin page binds BY KEY (labelName) -> not by index.
   * The admin page reuses the existing endpoint /ItemsView/GetLangLabels, which
     runs sp_GetLangLabels and already returns (id, labelName, LabelTest).
     No stored-proc or C# change is required.

   SAFE TO RE-RUN: each row is inserted only WHERE NOT EXISTS (idempotent).
   Arabic text is stored as NVARCHAR via N'...' literals.

   Author: (generated) | Target: SQL Server | Date: 2026-07-24
   ============================================================================ */

SET NOCOUNT ON;

INSERT INTO dbo.tblLabelName (labelName, labelNameEng, labelNameArb)
SELECT v.labelName, v.eng, v.arb
FROM (VALUES
    -- ===== Top header / user menu (_LayoutNew.cshtml) =====================
     (N'adm_navDashboard',              N'Dashboard',                                          N'لوحة التحكم')
    ,(N'adm_navItemManagement',         N'Item Management',                                    N'إدارة الأصناف')
    ,(N'adm_navReservationMaster',      N'Reservation Master',                                 N'إدارة الحجوزات')
    ,(N'adm_navSlideShow',              N'Slide Show',                                         N'عرض الشرائح')
    ,(N'adm_navChangePassword',         N'Change Password',                                    N'تغيير كلمة المرور')
    ,(N'adm_navFeedbackReport',         N'FeedBack Report',                                    N'تقرير الملاحظات')
    ,(N'adm_navWebSlideShows',          N'Web Slide Shows',                                    N'عروض شرائح الويب')
    ,(N'adm_navMenuColors',             N'Menu Colors',                                        N'ألوان القائمة')
    ,(N'adm_navTabTheme',               N'TAB Theme',                                          N'سمة الجهاز اللوحي')
    ,(N'adm_navLogout',                 N'Logout',                                             N'تسجيل الخروج')

    -- ===== Page sections + right-side navigation ==========================
    ,(N'adm_secCategory',               N'Category',                                           N'الفئة')
    ,(N'adm_secSubCategory',            N'Sub Category',                                       N'الفئة الفرعية')
    ,(N'adm_secItem',                   N'Item',                                               N'الصنف')
    ,(N'adm_btnClearAll',               N'Clear All',                                          N'مسح الكل')
    ,(N'adm_navBranch',                 N'Branch',                                             N'الفرع')
    ,(N'adm_navChoices',                N'Choices',                                            N'الخيارات')
    ,(N'adm_navExtraItems',             N'Extra Items',                                        N'الإضافات')
    ,(N'adm_navComments',               N'Comments',                                           N'الملاحظات')
    ,(N'adm_navGroupModifier',          N'Group Modifier',                                     N'مجموعة التعديلات')
    ,(N'adm_navAllergens',              N'Allergens',                                          N'مسببات الحساسية')
    ,(N'adm_btnAddExtraItems',          N'Add Extra Items',                                    N'إضافة أصناف إضافية')

    -- ===== Add Category popup ============================================
    ,(N'adm_titleAddCategory',          N'Add Category',                                       N'إضافة فئة')
    ,(N'adm_lblShowCategory',           N'Show Category',                                       N'إظهار الفئة')
    ,(N'adm_lblIsSubCategory',          N'Is Sub Category',                                     N'فئة فرعية')
    ,(N'adm_lblMainCategory',           N'Main Category',                                       N'الفئة الرئيسية')
    ,(N'adm_valMainCategory',           N'Please select a valid Main Category.',               N'الرجاء تحديد فئة رئيسية صحيحة.')
    ,(N'adm_lblSelectBrand',            N'Select Brand',                                        N'اختر العلامة التجارية')
    ,(N'adm_valSelectBrand',            N'Please select a valid brand.',                        N'الرجاء تحديد علامة تجارية صحيحة.')
    ,(N'adm_lblAssignBranch',           N'Assign Branch',                                       N'تعيين الفرع')
    ,(N'adm_valAssignBranch',           N'Please select a valid branch.',                       N'الرجاء تحديد فرع صحيح.')
    ,(N'adm_lblCategoryName',           N'Category Name',                                       N'اسم الفئة')
    ,(N'adm_valCategoryName',           N'Please insert a valid category name.',               N'الرجاء إدخال اسم فئة صحيح.')
    ,(N'adm_lblCategoryNameAr',         N'Category Name (Arabic)',                              N'اسم الفئة (بالعربية)')
    ,(N'adm_btnDelete',                 N'Delete',                                              N'حذف')
    ,(N'adm_btnAdd',                    N'Add',                                                 N'إضافة')
    ,(N'adm_btnClose',                  N'Close',                                               N'إغلاق')

    -- ===== Add Item popup ================================================
    ,(N'adm_titleAddItem',              N'Add Item',                                            N'إضافة صنف')
    ,(N'adm_lblShowItems',              N'Show Items',                                          N'إظهار الأصناف')
    ,(N'adm_lblCategory',               N'Category',                                            N'الفئة')
    ,(N'adm_lblPrice',                  N'Price',                                               N'السعر')
    ,(N'adm_lblItemNameEng',            N'Item Name (English)',                                 N'اسم الصنف (بالإنجليزية)')
    ,(N'adm_lblItemNameAra',            N'Item Name (Arabic)',                                  N'اسم الصنف (بالعربية)')
    ,(N'adm_lblIngredientEng',          N'Ingredient (English)',                                N'المكوّنات (بالإنجليزية)')
    ,(N'adm_lblIngredientAra',          N'Ingredient (Arabic)',                                 N'المكوّنات (بالعربية)')
    ,(N'adm_lblAssignChoice',           N'Assign Choice',                                       N'تعيين الخيار')
    ,(N'adm_lblAssignExtras',           N'Assign Extras',                                       N'تعيين الإضافات')
    ,(N'adm_lblAssignComments',         N'Assign Comments',                                     N'تعيين الملاحظات')
    ,(N'adm_lblSelectImage3MB',         N'Select Image (max 3MB File Size)',                    N'اختر صورة (بحد أقصى 3 ميجابايت)')
    ,(N'adm_lblChooseFile',             N'Choose file',                                         N'اختر ملفًا')
    ,(N'adm_btnUpload',                 N'Upload',                                              N'رفع')
    ,(N'adm_lblSelectVideo',            N'Select Video',                                        N'اختر فيديو')
    ,(N'adm_lblSecondaryImages',        N'Secondary Images (gallery)',                          N'صور إضافية (معرض)')
    ,(N'adm_hintSecondary',             N'Upload a primary image first to enable secondary images.', N'قم برفع صورة رئيسية أولاً لتفعيل الصور الإضافية.')
    ,(N'adm_lblChooseImages',           N'Choose images',                                       N'اختر الصور')
    ,(N'adm_btnSave',                   N'Save',                                                N'حفظ')

    -- ===== Extra Item / Item Choices popups =============================
    ,(N'adm_titleAddExtraItem',         N'Add Extra Item',                                      N'إضافة صنف إضافي')
    ,(N'adm_lblSelectImage',            N'Select Image',                                        N'اختر صورة')
    ,(N'adm_titleAddItemChoices',       N'Add Item Choices',                                    N'إضافة خيارات الصنف')
    ,(N'adm_lblShowChoice',             N'Show Choice',                                         N'إظهار الخيار')

    -- ===== Add Comment popup ============================================
    ,(N'adm_titleAddNewComment',        N'Add New Comment',                                     N'إضافة ملاحظة جديدة')
    ,(N'adm_lblCommentNameEng',         N'Comment Name (English)',                              N'اسم الملاحظة (بالإنجليزية)')
    ,(N'adm_lblCommentNameAra',         N'Comment Name (Arabic)',                               N'اسم الملاحظة (بالعربية)')

    -- ===== Group Modifier popups ========================================
    ,(N'adm_titleAddGroupModifier',     N'Add Group Modifier',                                  N'إضافة مجموعة تعديلات')
    ,(N'adm_lblModifierType',           N'Modifier Type',                                       N'نوع التعديل')
    ,(N'adm_lblGroupModNameEng',        N'Group Modifier Name (English)',                       N'اسم مجموعة التعديلات (بالإنجليزية)')
    ,(N'adm_lblGroupModNameAra',        N'Group Modifier Name (Arabic)',                        N'اسم مجموعة التعديلات (بالعربية)')
    ,(N'adm_lblMinSelect',              N'Minimum Select',                                      N'الحد الأدنى للاختيار')
    ,(N'adm_lblMaxSelect',              N'Maximum Select',                                      N'الحد الأقصى للاختيار')
    ,(N'adm_lblModifierGroups',         N'Modifier Groups',                                     N'مجموعات التعديلات')
    ,(N'adm_thID',                      N'ID',                                                  N'المعرّف')
    ,(N'adm_thSeqNum',                  N'Seq Num',                                             N'رقم التسلسل')
    ,(N'adm_thSorting',                 N'Sorting',                                             N'الترتيب')
    ,(N'adm_thGroupNameEng',            N'Group Name Eng',                                      N'اسم المجموعة (إنجليزي)')
    ,(N'adm_thGroupNameArb',            N'Group Name Arb',                                      N'اسم المجموعة (عربي)')
    ,(N'adm_thTypeID',                  N'Type ID',                                             N'معرّف النوع')
    ,(N'adm_thType',                    N'Type',                                                N'النوع')
    ,(N'adm_thMinSelect',              N'Min Select',                                           N'الحد الأدنى')
    ,(N'adm_thMaxSelect',              N'Max Select',                                           N'الحد الأقصى')
    ,(N'adm_btnCancel',                 N'Cancel',                                              N'إلغاء')
    ,(N'adm_titleAssignGroupModifier',  N'Assign Group Modifier',                               N'تعيين مجموعة التعديلات')
    ,(N'adm_lblSelectGroupModifier',    N'Select Group Modifier',                               N'اختر مجموعة التعديلات')

    -- ===== Add Branch popup =============================================
    ,(N'adm_titleAddBranch',            N'Add Branch',                                          N'إضافة فرع')
    ,(N'adm_lblShowBranch',             N'Show Branch',                                         N'إظهار الفرع')
    ,(N'adm_lblBranchName',             N'Branch Name',                                         N'اسم الفرع')
    ,(N'adm_valBranchName',             N'Please insert a valid Branch Name.',                  N'الرجاء إدخال اسم فرع صحيح.')
    ,(N'adm_lblBranchNameAr',           N'Branch Name (Arabic)',                                N'اسم الفرع (بالعربية)')

    -- ===== Alert / Warning / Change Password ============================
    ,(N'adm_msgSuccess',                N'Success!',                                            N'تم بنجاح!')
    ,(N'adm_btnOk',                     N'Ok',                                                  N'موافق')
    ,(N'adm_msgWarning',                N'Warning!',                                            N'تحذير!')
    ,(N'adm_titleChangePassword',       N'Change Password',                                     N'تغيير كلمة المرور')
    ,(N'adm_lblOldPassword',            N'Old Password',                                        N'كلمة المرور القديمة')
    ,(N'adm_valPassword',               N'Please insert a Password.',                           N'الرجاء إدخال كلمة المرور.')
    ,(N'adm_lblNewPassword',            N'New Password',                                        N'كلمة المرور الجديدة')
    ,(N'adm_lblRetypePassword',         N'Retype Password',                                     N'إعادة إدخال كلمة المرور')

    -- ===== MainJs/Category.js runtime messages ==========================
    ,(N'adm_msgInsertCatName',          N'Please insert Category Name.',                        N'الرجاء إدخال اسم الفئة.')
    ,(N'adm_msgInsertCatNameAra',       N'Please insert Category Name (Arabic).',               N'الرجاء إدخال اسم الفئة (بالعربية).')
    ,(N'adm_msgInsertItemName',         N'Please insert item Name.',                            N'الرجاء إدخال اسم الصنف.')
    ,(N'adm_msgInsertItemNameAra',      N'Please insert item Name (Arabic).',                   N'الرجاء إدخال اسم الصنف (بالعربية).')
    ,(N'adm_msgInsertPrice',            N'Please insert price.',                                N'الرجاء إدخال السعر.')
    ,(N'adm_msgSelectBranch',           N'Please select Branch',                                N'الرجاء تحديد الفرع.')
    ,(N'adm_msgSelectGroupModifier',    N'Please select Group Modifier.',                       N'الرجاء تحديد مجموعة التعديلات.')
    ,(N'adm_msgPwdNotMatch',            N'New password and retype password not matched.',       N'كلمة المرور الجديدة وتأكيدها غير متطابقين.')
    ,(N'adm_msgOldPwdIncorrect',        N'Old Password is incorrect.',                          N'كلمة المرور القديمة غير صحيحة.')
    ,(N'adm_msgPwdUpdated',             N'Password updated successfully.',                       N'تم تحديث كلمة المرور بنجاح.')
    ,(N'adm_optSelect',                 N'Select',                                              N'اختر')
    ,(N'adm_msgAssignGroupModifierPrefix', N'Assign Group Modifier - ',                         N'تعيين مجموعة التعديلات - ')

    -- ===== Dynamic Add/Edit titles + buttons set at runtime by Category.js =
    ,(N'adm_titleEditCategory',         N'Edit Category',                                       N'تعديل الفئة')
    ,(N'adm_titleEditItem',             N'Edit Item',                                           N'تعديل الصنف')
    ,(N'adm_titleEditExtraItem',        N'Edit Extra Item',                                     N'تعديل الصنف الإضافي')
    ,(N'adm_titleEditItemChoice',       N'Edit Item Choice',                                    N'تعديل خيار الصنف')
    ,(N'adm_titleEditComment',          N'Edit Comment',                                        N'تعديل الملاحظة')
    ,(N'adm_titleEditBranch',           N'Edit Branch',                                         N'تعديل الفرع')
    ,(N'adm_hdrItems',                  N'Items',                                               N'الأصناف')
    ,(N'adm_btnUpdate',                 N'Update',                                              N'تحديث')
) AS v(labelName, eng, arb)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.tblLabelName t WHERE t.labelName = v.labelName
);

--PRINT CONCAT('tblLabelName admin labels inserted. New MAX(id) = ', (SELECT MAX(id) FROM dbo.tblLabelName));
GO

/* ----------------------------------------------------------------------------
   OPTIONAL HARDENING (not required, review before running):
   sp_GetLangLabels currently has no ORDER BY. The customer menu relies on the
   rows coming back in id order (clustered PK) which SQL Server does in practice,
   but you can make it explicit and future-proof:

   -- ALTER PROCEDURE [dbo].[sp_GetLangLabels] @selectedLang nvarchar(10)='EN'
   -- AS BEGIN
   --   IF @selectedLang = 'EN'
   --     SELECT id, labelName, labelNameEng AS LabelTest FROM tblLabelName ORDER BY id;
   --   ELSE
   --     SELECT id, labelName, labelNameArb AS LabelTest FROM tblLabelName ORDER BY id;
   -- END
   ---------------------------------------------------------------------------- */
