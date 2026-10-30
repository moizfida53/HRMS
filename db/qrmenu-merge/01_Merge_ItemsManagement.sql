/*==============================================================================
  Merge Pistachio_v4 (Items Management: QR menu, items, POS, Dine-In) into HRMS_Kuwait
  ------------------------------------------------------------------------------
  Run this ONCE, on HRMS_Kuwait, in SSMS (it uses GO batches).
  Both databases must be on the same instance. Pistachio_v4 is only READ.

  What it does
    0. Pre-checks: right database, source exists, same collation, no name clashes.
       Any failure stops the whole script before anything is changed.
    1. Creates the Items Management objects in [dbo]:
         22 table types, 3 functions, 88 tables (+ keys, defaults,
         indexes, foreign keys), 221 stored procedures.
       Taken unchanged from the Pistachio_v4 schema script of 30/10/2026,
       minus the CREATE DATABASE / ALTER DATABASE / user [test] parts.
    2. Copies all rows from Pistachio_v4, keeping identity values, in one
       transaction. Constraints are re-checked afterwards.
    3. Grants hrms_app_role execute rights on the new procedures and types.
    4. Verifies: object counts and row counts, source vs target.

  Notes
    - Objects stay in [dbo]. HRMS's DDL triggers (TR_HRMS_NoPhysicalDelete,
      TR_HRMS_SoftDelete_OnCreateTable) skip [dbo], so they do not touch them.
    - Take a backup of HRMS_Kuwait first. Section 1 is not transactional.
==============================================================================*/
SET NOCOUNT ON;
GO
/*------------------------------------------------------------------------------
  0. PRE-CHECKS
------------------------------------------------------------------------------*/
SET NOEXEC OFF;
GO
IF DB_NAME() <> N'HRMS_Kuwait'
BEGIN
    DECLARE @db sysname = DB_NAME();
    RAISERROR(N'STOPPED: run this script on HRMS_Kuwait (current database: %s). Nothing below this point runs - ignore the further errors SSMS lists after this one.', 16, 1, @db) WITH NOWAIT;
    SET NOEXEC ON;
END;
GO
IF DB_ID(N'Pistachio_v4') IS NULL
BEGIN
    RAISERROR(N'STOPPED: source database Pistachio_v4 not found on this instance. Nothing below this point runs - ignore the further errors SSMS lists after this one.', 16, 1) WITH NOWAIT;
    SET NOEXEC ON;
END;
GO
IF CONVERT(sysname, DATABASEPROPERTYEX(N'HRMS_Kuwait', 'Collation')) <> CONVERT(sysname, DATABASEPROPERTYEX(N'Pistachio_v4', 'Collation'))
BEGIN
    DECLARE @c1 sysname = CONVERT(sysname, DATABASEPROPERTYEX(N'HRMS_Kuwait', 'Collation')),
            @c2 sysname = CONVERT(sysname, DATABASEPROPERTYEX(N'Pistachio_v4', 'Collation'));
    RAISERROR(N'STOPPED: collations differ (HRMS_Kuwait = %s, Pistachio_v4 = %s). Decide which to keep before merging. Nothing below this point runs - ignore the further errors SSMS lists after this one.', 16, 1, @c1, @c2) WITH NOWAIT;
    SET NOEXEC ON;
END;
GO
DECLARE @Incoming TABLE (Kind nvarchar(2), Name sysname);
INSERT INTO @Incoming (Kind, Name) VALUES
    (N'U', N'tblPOS_TableSession'),
    (N'U', N'tblInvoicePayment'),
    (N'U', N'tblInvoice'),
    (N'U', N'tblTable'),
    (N'U', N'Assign_Cat'),
    (N'U', N'Assign_Item'),
    (N'U', N'AuditTrail'),
    (N'U', N'Feedback_Customer'),
    (N'U', N'Feedback_Data'),
    (N'U', N'Feedback_Layout'),
    (N'U', N'Feedback_Type'),
    (N'U', N'tbl_Allergen'),
    (N'U', N'tbl_Allergen_Assign'),
    (N'U', N'tbl_Menu_Colors'),
    (N'U', N'tblArea'),
    (N'U', N'TblArea_Mapping'),
    (N'U', N'tblAreaMapData'),
    (N'U', N'tblAudit'),
    (N'U', N'tblAuditDetails'),
    (N'U', N'tblbranch'),
    (N'U', N'tblBrand'),
    (N'U', N'tblCategory'),
    (N'U', N'tblCategoryName_Languages'),
    (N'U', N'tblcomments'),
    (N'U', N'tblcompany'),
    (N'U', N'tblCustomer'),
    (N'U', N'tblCustomerAddress'),
    (N'U', N'tblDenomination'),
    (N'U', N'tblDenominationDetails'),
    (N'U', N'tblDiscount_Type'),
    (N'U', N'tblDiscountCode'),
    (N'U', N'tblDriver'),
    (N'U', N'tblDriverTracking'),
    (N'U', N'tblEndDay'),
    (N'U', N'tblEndDayDiscount'),
    (N'U', N'tblEndDayPayment'),
    (N'U', N'tblEndDayPaymentTypeDetails'),
    (N'U', N'tblEndshiftPaymentTypeDetails'),
    (N'U', N'tblExtra'),
    (N'U', N'tblGroup_Modifier_Details'),
    (N'U', N'tblGroup_Modifier_Master'),
    (N'U', N'tblGroup_Modifier_Sub_Details'),
    (N'U', N'tblGroup_Modifier_Type'),
    (N'U', N'tblImageSlideShow'),
    (N'U', N'tblIngredientName_Languages'),
    (N'U', N'tblInvoicePaymentType'),
    (N'U', N'tblInvoiceType_Master'),
    (N'U', N'tblInvoiceType_Master_Details'),
    (N'U', N'tblItem_Choices'),
    (N'U', N'tblItem_Extras'),
    (N'U', N'tblItemComments'),
    (N'U', N'tblItemImages'),
    (N'U', N'tblItems'),
    (N'U', N'tblItemsName_Languages'),
    (N'U', N'tblLabelName'),
    (N'U', N'tblMenuTheme'),
    (N'U', N'tblOrder'),
    (N'U', N'tblOrderStatus'),
    (N'U', N'tblPaymentVoucher'),
    (N'U', N'tblPaymentVoucherDetails'),
    (N'U', N'tblPaymentVoucherType'),
    (N'U', N'tblPOS_AuditLog'),
    (N'U', N'tblPOS_BranchSetting'),
    (N'U', N'tblPOS_CancelReason_Master'),
    (N'U', N'tblPOS_DailyCounter'),
    (N'U', N'tblPOS_GeoCache'),
    (N'U', N'tblPOS_OrderStatusHistory'),
    (N'U', N'tblPOS_OrderStatusTransition'),
    (N'U', N'tblPOS_OrderTransfer'),
    (N'U', N'tblPOS_PaymentLink'),
    (N'U', N'tblPOS_Printer'),
    (N'U', N'tblPOS_PrinterCategory'),
    (N'U', N'tblPOS_Role_Master'),
    (N'U', N'tblPOS_TableArea'),
    (N'U', N'tblPOS_UserBranch_Map'),
    (N'U', N'tblPrinter'),
    (N'U', N'tblPromotion'),
    (N'U', N'tblReservation'),
    (N'U', N'tblReservationSlot'),
    (N'U', N'tblReservationStatus'),
    (N'U', N'tblReservationTableStructure'),
    (N'U', N'tblRole'),
    (N'U', N'tblSection'),
    (N'U', N'tblSetting'),
    (N'U', N'tblTableType'),
    (N'U', N'tblTheme'),
    (N'U', N'tblUser'),
    (N'U', N'tblWebImageSlideShow'),
    (N'P', N'AddFeedBackLayout'),
    (N'P', N'BrandPromotion_ShowHide'),
    (N'P', N'Category_UpdateSequence'),
    (N'P', N'geticatdetails'),
    (N'P', N'Getitem'),
    (N'P', N'Getitemselect'),
    (N'P', N'Image_Promotion'),
    (N'P', N'Image_Slideshow'),
    (N'P', N'Items_UpdateSequence'),
    (N'P', N'Mobile_GetFeedBackLayout'),
    (N'P', N'mvc_sp_AddCategory'),
    (N'P', N'mvc_sp_AddItem'),
    (N'P', N'mvc_sp_AddWaiter'),
    (N'P', N'mvc_sp_GetItems'),
    (N'P', N'mvc_sp_GetItems_Mobile'),
    (N'P', N'mvc_sp_GetRole'),
    (N'P', N'mvc_sp_GetWaiter'),
    (N'P', N'mvc_sp_Login'),
    (N'P', N'mvc_sp_UpdateCategory'),
    (N'P', N'mvc_sp_UpdateItem'),
    (N'P', N'mvc_sp_UpdateWaiter'),
    (N'P', N'Promotion_Add'),
    (N'P', N'Promotion_UpdateSequence'),
    (N'P', N'SlideShow_UpdateSequence'),
    (N'P', N'SlideShows_Add'),
    (N'P', N'sp_AddBranch'),
    (N'P', N'sp_AddBrand'),
    (N'P', N'sp_AddEditReservationSlot'),
    (N'P', N'sp_AddEditReservationTableStructure'),
    (N'P', N'sp_AddGroupModifier'),
    (N'P', N'sp_AddItem'),
    (N'P', N'sp_AddItemImage'),
    (N'P', N'sp_AddUpdateBranch'),
    (N'P', N'sp_AddUpdateComments'),
    (N'P', N'sp_ArrangeTable'),
    (N'P', N'sp_Assign_Item_Choices'),
    (N'P', N'sp_Assign_Item_Comments'),
    (N'P', N'sp_Assign_Item_Extras'),
    (N'P', N'sp_AssignAllergenToItem'),
    (N'P', N'sp_AssignBrand'),
    (N'P', N'sp_AssignBrandItems'),
    (N'P', N'sp_AssignChoiceToItem'),
    (N'P', N'sp_AssignCommentToItem'),
    (N'P', N'sp_AssignExtraItemToItem'),
    (N'P', N'sp_AssignGroupModifier'),
    (N'P', N'sp_AssignItemToBranch'),
    (N'P', N'sp_AuditTrail'),
    (N'P', N'sp_Authentication'),
    (N'P', N'sp_BrandData'),
    (N'P', N'sp_changePassword'),
    (N'P', N'sp_DashboardFilter'),
    (N'P', N'sp_Dashbord_DeletedItems'),
    (N'P', N'sp_DashbordDeletedReUseWiseItemsData'),
    (N'P', N'sp_DashbordDeletedWasteWiseItemsData'),
    (N'P', N'sp_DashbordDiscountWiseItemsData'),
    (N'P', N'sp_DashbordPaymentTypesData'),
    (N'P', N'sp_DashbordSalesData'),
    (N'P', N'sp_DeleteCategory'),
    (N'P', N'sp_DeleteGroupModifier'),
    (N'P', N'sp_DeleteItem'),
    (N'P', N'sp_DeleteItemImages'),
    (N'P', N'sp_DeleteReservationSlot'),
    (N'P', N'sp_DeleteReservationTableStructure'),
    (N'P', N'sp_editThemes'),
    (N'P', N'sp_GenerateCartCommentsObject'),
    (N'P', N'sp_GenerateCartExtraAndChoicesObject'),
    (N'P', N'sp_GenerateCartExtraItemsObject'),
    (N'P', N'sp_GetAllChoices'),
    (N'P', N'sp_GetAllergens'),
    (N'P', N'sp_GetAllExtraItems'),
    (N'P', N'sp_GetAreaListForDeliveryAddress'),
    (N'P', N'sp_GetAssignBranch'),
    (N'P', N'sp_GetAssignBranchItemsAndComments'),
    (N'P', N'sp_GetAssignBrand'),
    (N'P', N'sp_GetAuditReportsData'),
    (N'P', N'sp_GetAvailability'),
    (N'P', N'sp_GetAvilableTablesForChangeTable'),
    (N'P', N'sp_GetBindAssignGroupModifier'),
    (N'P', N'sp_GetBranchAndSectionList'),
    (N'P', N'sp_GetBranchs'),
    (N'P', N'sp_GetBranchsBrandWise'),
    (N'P', N'sp_GetBranchTablesReservations'),
    (N'P', N'sp_GetBrandBranchDetails'),
    (N'P', N'sp_GetBrandHomePageImage'),
    (N'P', N'sp_GetBrandHomePaggeImage'),
    (N'P', N'sp_GetBrandImages'),
    (N'P', N'sp_GetBrands'),
    (N'P', N'sp_GetBrandsMobile'),
    (N'P', N'sp_GetCartItemChoicesExtraCommentList'),
    (N'P', N'sp_GetCartItemList'),
    (N'P', N'sp_GetCategory'),
    (N'P', N'sp_GetCategoryBranchwise'),
    (N'P', N'sp_GetCategoryDetails'),
    (N'P', N'sp_GetCategoryDragDrop'),
    (N'P', N'sp_GetCategoryList'),
    (N'P', N'sp_GetCategoryMobile'),
    (N'P', N'sp_GetCategoryVisits'),
    (N'P', N'sp_GetCategoryWiseItemList'),
    (N'P', N'sp_GetCategoryWiseItemListDragDrop'),
    (N'P', N'sp_GetChoicesItemsWise'),
    (N'P', N'sp_GetComments'),
    (N'P', N'sp_GetDashboardLateOrdersData'),
    (N'P', N'sp_GetDashboardTopItemsSummaryData'),
    (N'P', N'sp_GetDeliveryServiceData'),
    (N'P', N'sp_GetEndDatesForRptDashboard'),
    (N'P', N'sp_GetExpiredBrandList'),
    (N'P', N'sp_GetExtra'),
    (N'P', N'sp_GetExtraComments'),
    (N'P', N'sp_GetExtraItems'),
    (N'P', N'sp_GetFeedbackFormQuestion'),
    (N'P', N'sp_GetFeedBackLayout'),
    (N'P', N'sp_GetGroupModifier'),
    (N'P', N'sp_GetGroupModifierTypes'),
    (N'P', N'sp_GetIoutofStock'),
    (N'P', N'sp_GetItemChoices'),
    (N'P', N'sp_GetItemComments'),
    (N'P', N'sp_GetItemDetails'),
    (N'P', N'sp_GetItemExtraItemsAndComments'),
    (N'P', N'sp_GetItemExtras'),
    (N'P', N'sp_GetItemImages'),
    (N'P', N'sp_GetItemMobile'),
    (N'P', N'sp_GetItemMobileIPad'),
    (N'P', N'sp_GetItemsAllergenWise'),
    (N'P', N'sp_GetItemsBranchwise'),
    (N'P', N'sp_GetItemsCommentWise'),
    (N'P', N'sp_GetItemsExtraItemsWise'),
    (N'P', N'sp_GetItemsVisits'),
    (N'P', N'sp_GetLangLabels'),
    (N'P', N'sp_GetMainCategoryList'),
    (N'P', N'sp_GetMenuColors'),
    (N'P', N'sp_GetMenuTheme'),
    (N'P', N'sp_GetMenuThemeVersion'),
    (N'P', N'sp_GetNewThemes'),
    (N'P', N'sp_GetOnlinePaymentTypes'),
    (N'P', N'sp_GetReservationData'),
    (N'P', N'sp_GetReservationMasterData'),
    (N'P', N'sp_getSetting'),
    (N'P', N'sp_GetSettings'),
    (N'P', N'sp_GetTabThemes'),
    (N'P', N'sp_GetTheme'),
    (N'P', N'sp_GetThemes'),
    (N'P', N'sp_GetTimeSlot'),
    (N'P', N'sp_GetTimeSlotDataDateWise'),
    (N'P', N'sp_InsertIntoBrandSyncCategory'),
    (N'P', N'sp_InsertIntoBrandSyncItems'),
    (N'P', N'sp_MobileGetGroupModifierAllergenMasterData'),
    (N'P', N'sp_POS_AddPayment'),
    (N'P', N'sp_POS_CancelOrder'),
    (N'P', N'sp_POS_CancelOrderReject'),
    (N'P', N'sp_POS_ChangeStatus'),
    (N'P', N'sp_POS_ChangeToPickup'),
    (N'P', N'sp_POS_DineIn_AddItems'),
    (N'P', N'sp_POS_DineIn_AttachInvoice'),
    (N'P', N'sp_POS_DineIn_CloseIfSettled'),
    (N'P', N'sp_POS_DineIn_Context'),
    (N'P', N'sp_POS_DineIn_GetFloor'),
    (N'P', N'sp_POS_DineIn_GetMenu'),
    (N'P', N'sp_POS_DineIn_GetTable'),
    (N'P', N'sp_POS_DineIn_LockTable'),
    (N'P', N'sp_POS_DineIn_ReleaseTable'),
    (N'P', N'sp_POS_DineIn_SaveLayout'),
    (N'P', N'sp_POS_DineIn_SetGuest'),
    (N'P', N'sp_POS_DineIn_SetLineTakeAway'),
    (N'P', N'sp_POS_DineIn_SplitInvoice'),
    (N'P', N'sp_POS_DineIn_TakeAwayList'),
    (N'P', N'sp_POS_DineIn_TransferTable'),
    (N'P', N'sp_POS_GeoCacheGet'),
    (N'P', N'sp_POS_GeoCacheSet'),
    (N'P', N'sp_POS_GetInvoiceNumShow'),
    (N'P', N'sp_POS_GetLookups'),
    (N'P', N'sp_POS_GetOrderChanges'),
    (N'P', N'sp_POS_GetOrderDetails'),
    (N'P', N'sp_POS_GetOrderFacets'),
    (N'P', N'sp_POS_GetOrders'),
    (N'P', N'sp_POS_GetPaymentProvider'),
    (N'P', N'sp_POS_IsOnlinePaymentType'),
    (N'P', N'sp_POS_Login'),
    (N'P', N'sp_POS_MarkPrinted'),
    (N'P', N'sp_POS_PaymentLink_Complete'),
    (N'P', N'sp_POS_PaymentLink_Create'),
    (N'P', N'sp_POS_PaymentLink_Get'),
    (N'P', N'sp_POS_PaymentLink_SetProvider'),
    (N'P', N'sp_POS_Print_MarkSent'),
    (N'P', N'sp_POS_Print_Ticket'),
    (N'P', N'sp_POS_Printer_Delete'),
    (N'P', N'sp_POS_Printer_List'),
    (N'P', N'sp_POS_Printer_Save'),
    (N'P', N'sp_POS_ProcessOrder'),
    (N'P', N'sp_POS_ResolveArea'),
    (N'P', N'sp_POS_Role_List'),
    (N'P', N'sp_POS_TakePaymentSplit'),
    (N'P', N'sp_POS_TransferOrder'),
    (N'P', N'sp_POS_User_ChangeRole'),
    (N'P', N'sp_POS_User_List'),
    (N'P', N'sp_POS_User_Save'),
    (N'P', N'sp_PostFeedbackData'),
    (N'P', N'sp_SaveMenuColors'),
    (N'P', N'sp_SaveMenuTheme'),
    (N'P', N'sp_SaveTabTheme'),
    (N'P', N'sp_SetArrived'),
    (N'P', N'sp_GetAvailability'),
    (N'P', N'sp_SubmitReservationData'),
    (N'P', N'sp_UpdateAuditDetails'),
    (N'P', N'sp_UpdateBranch'),
    (N'P', N'sp_UpdateBranchSequence'),
    (N'P', N'sp_UpdateBranchStatus'),
    (N'P', N'sp_UpdateBrand'),
    (N'P', N'sp_UpdateBrandImage'),
    (N'P', N'sp_UpdateBrandLayout'),
    (N'P', N'sp_UpdateCategoryBranchAssign'),
    (N'P', N'sp_updateCategorySequance'),
    (N'P', N'sp_UpdateGroupModifier'),
    (N'P', N'sp_UpdateGroupModifierSequence'),
    (N'P', N'sp_UpdateItem'),
    (N'P', N'sp_updateItemsSequance'),
    (N'P', N'sp_UpdateOutOfStock'),
    (N'P', N'sp_UpdateReservedTable'),
    (N'P', N'sp_updatethemes'),
    (N'P', N'UpdateFeedBackLayout'),
    (N'P', N'WebSlideshow_GetImages'),
    (N'P', N'WebSlideShow_UpdateSequence'),
    (N'P', N'WebSlideShows_Add'),
    (N'FN', N'SplitString'),
    (N'FN', N'fn_POS_DineIn_Tables'),
    (N'FN', N'fn_POS_NormalizeAreaName'),
    (N'TT', N'DT_tblCartComment'),
    (N'TT', N'DT_tblCartExtraItems'),
    (N'TT', N'DT_tblCartItems'),
    (N'TT', N'DT_tblCartItemsWithUID'),
    (N'TT', N'DT_tblCategorySeqUpdate'),
    (N'TT', N'DT_tblCategorySync'),
    (N'TT', N'DT_tblChoiceItems'),
    (N'TT', N'DT_tblComments'),
    (N'TT', N'DT_tblExtraItems'),
    (N'TT', N'DT_tblGroup_Modifier_Details'),
    (N'TT', N'DT_tblItemsSeqUpdate'),
    (N'TT', N'DT_tblItemsSync'),
    (N'TT', N'DT_tblWaiterChoice'),
    (N'TT', N'DT_tblWaiterExtra'),
    (N'TT', N'FeedBackResponse'),
    (N'TT', N'MenuThemeTVP'),
    (N'TT', N'TVP_POS_BigIntList'),
    (N'TT', N'TVP_POS_DineInSplitLine'),
    (N'TT', N'TVP_POS_IntList'),
    (N'TT', N'TVP_POS_OrderItem'),
    (N'TT', N'TVP_POS_PaymentLine'),
    (N'TT', N'TVP_POS_TablePosition');

DECLARE @Clash nvarchar(max) =
    (SELECT STRING_AGG(CONVERT(nvarchar(max), N'dbo.' + i.Name), N', ')
     FROM @Incoming i
     WHERE (i.Kind <> N'TT' AND OBJECT_ID(N'dbo.' + QUOTENAME(i.Name)) IS NOT NULL)
        OR (i.Kind =  N'TT' AND TYPE_ID(N'dbo.' + QUOTENAME(i.Name)) IS NOT NULL));
IF @Clash IS NOT NULL
BEGIN
    DECLARE @ClashMsg nvarchar(1800) = LEFT(@Clash, 1800);
    RAISERROR(N'STOPPED: these objects already exist in HRMS_Kuwait (already merged?): %s Nothing below this point runs - ignore the further errors SSMS lists after this one.', 16, 1, @ClashMsg) WITH NOWAIT;
    SET NOEXEC ON;
END
ELSE
    PRINT N'Pre-checks passed.';
GO
/*------------------------------------------------------------------------------
  1. CREATE ITEMS MANAGEMENT OBJECTS IN [dbo]
------------------------------------------------------------------------------*/
/****** Object:  UserDefinedTableType [dbo].[DT_tblCartComment]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblCartComment] AS TABLE(
	[II] [int] NULL,
	[CI] [int] NULL,
	[comments_eng] [nvarchar](600) NULL,
	[comments_arb] [nvarchar](600) NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblCartExtraItems]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblCartExtraItems] AS TABLE(
	[II] [int] NULL,
	[EI] [int] NULL,
	[ITEM_NAME] [nvarchar](500) NULL,
	[ITEM_NAME_ARABIC] [nvarchar](500) NULL,
	[PRICE] [decimal](18, 3) NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblCartItems]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblCartItems] AS TABLE(
	[ItemId] [int] NULL,
	[HID] [int] NULL,
	[qty] [int] NULL,
	[Comments] [nvarchar](500) NULL,
	[ChoiceId] [int] NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblCartItemsWithUID]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblCartItemsWithUID] AS TABLE(
	[UID] [int] NULL,
	[ItemId] [int] NULL,
	[HID] [int] NULL,
	[qty] [int] NULL,
	[Comments] [nvarchar](500) NULL,
	[ChoiceId] [int] NULL,
	[CartItemUniqID] [int] NULL,
	[ParentItemID] [int] NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblCategorySeqUpdate]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblCategorySeqUpdate] AS TABLE(
	[CAT_NUM] [int] NULL,
	[SEQ_NUM] [int] NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblCategorySync]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblCategorySync] AS TABLE(
	[CAT_NUM] [int] NULL,
	[CAT_NAME] [varchar](1000) NULL,
	[SEQ_NUM] [varchar](500) NULL,
	[PrinterName] [varchar](1000) NULL,
	[ImageName] [varchar](500) NULL,
	[ShowInTablet] [bit] NULL,
	[CAT_NAME_ARABIC] [nvarchar](1000) NULL,
	[BrandID] [int] NULL,
	[DineIn] [bit] NULL,
	[HomeDelivery] [bit] NULL,
	[Deleted] [bit] NULL,
	[MainCategory] [int] NULL,
	[isactive] [bit] NULL,
	[HID] [int] NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblChoiceItems]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblChoiceItems] AS TABLE(
	[UID] [int] NULL,
	[ChoiceItemId] [int] NULL,
	[GroupId] [int] NULL,
	[MainItemId] [int] NULL,
	[Price] [decimal](18, 3) NULL,
	[ItemName] [nvarchar](500) NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblComments]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblComments] AS TABLE(
	[UID] [int] NULL,
	[CommentId] [int] NULL,
	[MainItemId] [int] NULL,
	[Comment] [nvarchar](1000) NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblExtraItems]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblExtraItems] AS TABLE(
	[UID] [int] NULL,
	[ExtraItemId] [int] NULL,
	[GroupId] [int] NULL,
	[MainItemId] [int] NULL,
	[Price] [decimal](18, 3) NULL,
	[ItemName] [nvarchar](500) NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblGroup_Modifier_Details]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblGroup_Modifier_Details] AS TABLE(
	[MainItemId] [int] NULL,
	[GroupId] [int] NULL,
	[ItemID] [int] NULL,
	[Seq_Num] [int] NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblItemsSeqUpdate]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblItemsSeqUpdate] AS TABLE(
	[ItemId] [int] NULL,
	[SEQ_NUM] [int] NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblItemsSync]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblItemsSync] AS TABLE(
	[ID] [int] NULL,
	[CAT_NUM] [int] NULL,
	[ITEM_NAME] [varchar](1000) NULL,
	[PRICE] [decimal](18, 3) NULL,
	[ITEM_NAME_ARABIC] [nvarchar](1000) NULL,
	[INGREDIENT] [varchar](1000) NULL,
	[INGREDIENT_ARABIC] [nvarchar](1000) NULL,
	[IMAGENAME] [varchar](500) NULL,
	[ITEM_DESC_ENG] [nvarchar](2000) NULL,
	[Seq_Num] [int] NULL,
	[Deleted] [bit] NULL,
	[CostPrice] [decimal](18, 3) NULL,
	[Franchise_GroupID] [int] NULL,
	[isactive] [bit] NULL,
	[HID] [int] NULL,
	[isExtra] [bit] NULL,
	[Ischoice] [bit] NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblWaiterChoice]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblWaiterChoice] AS TABLE(
	[UID] [int] NULL,
	[MI] [int] NULL,
	[ChId] [int] NULL,
	[GId] [int] NULL,
	[ITEM_NAME] [nvarchar](500) NULL,
	[ITEM_NAME_ARABIC] [nvarchar](500) NULL,
	[PRICE] [decimal](18, 3) NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[DT_tblWaiterExtra]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[DT_tblWaiterExtra] AS TABLE(
	[UID] [int] NULL,
	[MI] [int] NULL,
	[ExId] [int] NULL,
	[GId] [int] NULL,
	[ITEM_NAME] [nvarchar](500) NULL,
	[ITEM_NAME_ARABIC] [nvarchar](500) NULL,
	[PRICE] [decimal](18, 3) NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[FeedBackResponse]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[FeedBackResponse] AS TABLE(
	[QuestionId] [int] NULL,
	[Response_Type] [int] NULL,
	[Response] [nvarchar](500) NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[MenuThemeTVP]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[MenuThemeTVP] AS TABLE(
	[Name] [nvarchar](100) NOT NULL,
	[Color] [nvarchar](50) NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[TVP_POS_BigIntList]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[TVP_POS_BigIntList] AS TABLE(
	[Value] [bigint] NOT NULL,
	PRIMARY KEY CLUSTERED 
(
	[Value] ASC
)WITH (IGNORE_DUP_KEY = OFF)
)
GO
/****** Object:  UserDefinedTableType [dbo].[TVP_POS_DineInSplitLine]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[TVP_POS_DineInSplitLine] AS TABLE(
	[OrderID] [bigint] NOT NULL,
	[Quantity] [int] NOT NULL,
	PRIMARY KEY CLUSTERED 
(
	[OrderID] ASC
)WITH (IGNORE_DUP_KEY = OFF)
)
GO
/****** Object:  UserDefinedTableType [dbo].[TVP_POS_IntList]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[TVP_POS_IntList] AS TABLE(
	[Value] [int] NOT NULL,
	PRIMARY KEY CLUSTERED 
(
	[Value] ASC
)WITH (IGNORE_DUP_KEY = OFF)
)
GO
/****** Object:  UserDefinedTableType [dbo].[TVP_POS_OrderItem]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[TVP_POS_OrderItem] AS TABLE(
	[ItemID] [int] NULL,
	[HID] [int] NULL,
	[ParentItemID] [int] NULL,
	[CartItemUniqID] [int] NULL,
	[LineType] [tinyint] NOT NULL DEFAULT ((1)),
	[Quantity] [int] NOT NULL,
	[Price] [decimal](18, 3) NULL,
	[Comments] [nvarchar](max) NULL,
	[Extra] [nvarchar](max) NULL
)
GO
/****** Object:  UserDefinedTableType [dbo].[TVP_POS_PaymentLine]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[TVP_POS_PaymentLine] AS TABLE(
	[PaymentTypeID] [int] NOT NULL,
	[Amount] [decimal](18, 3) NOT NULL,
	PRIMARY KEY CLUSTERED 
(
	[PaymentTypeID] ASC
)WITH (IGNORE_DUP_KEY = OFF)
)
GO
/****** Object:  UserDefinedTableType [dbo].[TVP_POS_TablePosition]    Script Date: 30/10/2026 13:37:40 ******/
CREATE TYPE [dbo].[TVP_POS_TablePosition] AS TABLE(
	[TableID] [int] NOT NULL,
	[Xaxis] [decimal](18, 2) NOT NULL,
	[Yaxis] [decimal](18, 2) NOT NULL,
	PRIMARY KEY CLUSTERED 
(
	[TableID] ASC
)WITH (IGNORE_DUP_KEY = OFF)
)
GO
/****** Object:  UserDefinedFunction [dbo].[SplitString]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Taher Vakil
-- =============================================


CREATE FUNCTION [dbo].[SplitString]
(    
      @Input NVARCHAR(MAX),
      @Character CHAR(1)
)
RETURNS @Output TABLE (
      Item NVARCHAR(1000)
)
AS
BEGIN
      DECLARE @StartIndex INT, @EndIndex INT
 
      SET @StartIndex = 1
      IF SUBSTRING(@Input, LEN(@Input) - 1, LEN(@Input)) <> @Character
      BEGIN
            SET @Input = @Input + @Character
      END
 
      WHILE CHARINDEX(@Character, @Input) > 0
      BEGIN
            SET @EndIndex = CHARINDEX(@Character, @Input)
           
            INSERT INTO @Output(Item)
            SELECT SUBSTRING(@Input, @StartIndex, @EndIndex - 1)
           
            SET @Input = SUBSTRING(@Input, @EndIndex + 1, LEN(@Input))
      END
 
      RETURN
END



GO
/****** Object:  Table [dbo].[tblPOS_TableSession]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_TableSession](
	[SessionID] [int] IDENTITY(1,1) NOT NULL,
	[TableID] [int] NOT NULL,
	[BranchID] [int] NULL,
	[CustomerName] [nvarchar](200) NULL,
	[Mobile] [nvarchar](30) NULL,
	[Persons] [int] NOT NULL,
	[OpenedOn] [datetime] NOT NULL,
	[OpenedBy] [int] NULL,
	[OpenedByName] [nvarchar](100) NULL,
	[ClosedOn] [datetime] NULL,
	[ClosedBy] [int] NULL,
	[ClosedByName] [nvarchar](100) NULL,
	[CloseReason] [nvarchar](50) NULL,
 CONSTRAINT [PK_tblPOS_TableSession] PRIMARY KEY CLUSTERED 
(
	[SessionID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblInvoicePayment]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblInvoicePayment](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[HID] [int] NULL,
	[BID] [int] NULL,
	[PaymentTypeID] [int] NULL,
	[InvoiceId] [bigint] NOT NULL,
	[PaymentType] [nvarchar](500) NULL,
	[BranchId] [int] NULL,
	[Amount] [decimal](18, 3) NULL,
	[SynchroniseDate] [datetime] NULL,
	[isSent] [bit] NULL,
	[isdeleted] [bit] NULL,
	[AmountTendered] [decimal](18, 3) NULL,
	[ChangeGiven] [decimal](18, 3) NULL,
	[ReferenceNo] [nvarchar](100) NULL,
	[IsRefund] [bit] NOT NULL,
	[ReceivedBy] [int] NULL,
	[ReceivedOn] [datetime] NOT NULL,
	[Comments] [nvarchar](500) NULL,
 CONSTRAINT [PK_tblInvoicePayment] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblInvoice]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblInvoice](
	[InvoiceNo] [bigint] IDENTITY(1,1) NOT NULL,
	[WaiterID] [int] NULL,
	[BillAmount] [decimal](18, 3) NULL,
	[Discount] [decimal](18, 3) NULL,
	[FinalAmount]  AS (case when ([BillAmount]-isnull([Discount],(0)))<(0) then (0) else [BillAmount]-isnull([Discount],(0)) end),
	[Comments] [nvarchar](500) NULL,
	[Person] [int] NULL,
	[Status] [int] NULL,
	[InvoiceDate] [datetime] NULL,
	[InvoiceTime] [datetime] NULL,
	[PaymentType] [int] NOT NULL,
	[Printed] [bit] NULL,
	[Mobile] [bigint] NULL,
	[Driver] [int] NULL,
	[OrderStatus] [int] NULL,
	[CustomerId] [int] NULL,
	[DriverName] [nvarchar](250) NULL,
	[OrderStatusID] [int] NULL,
	[Dispatcher] [bit] NULL,
	[RunningOrder] [int] NULL,
	[Deleted] [bit] NULL,
	[PaidDate] [datetime] NULL,
	[UpdatedInvoiceDate] [datetime] NULL,
	[BranchID] [int] NULL,
	[AddressID] [int] NULL,
	[BrandID] [int] NULL,
	[DriverAssignDate] [datetime] NULL,
	[Complaints] [nvarchar](500) NULL,
	[DeliveryDate] [datetime] NULL,
	[Change]  AS ((([CashAmount]+[K_NETAmount])+[Discount])-[BillAmount]),
	[Closed] [bit] NULL,
	[ClosedDate] [datetime] NULL,
	[InvoiceType] [int] NULL,
	[CashierID] [int] NULL,
	[DiscountTypeID] [int] NULL,
	[CashAmount] [decimal](18, 3) NULL,
	[K_NETAmount] [decimal](18, 3) NULL,
	[CashTalabat] [decimal](18, 3) NULL,
	[KnetTalabat] [decimal](18, 3) NULL,
	[DeliveryCharges] [decimal](18, 3) NULL,
	[EndShiftID] [int] NULL,
	[SynchroniseDate] [datetime] NULL,
	[syncAttempt] [int] NULL,
	[IsSent] [int] NULL,
	[Voucher] [nvarchar](max) NULL,
	[MasterAmount] [decimal](18, 3) NULL,
	[VisaAmount] [decimal](18, 3) NULL,
	[CravezAmount] [decimal](18, 3) NULL,
	[CofeDeliveryAmount] [decimal](18, 3) NULL,
	[CofePickupCash] [decimal](18, 3) NULL,
	[CofePickupCredit] [decimal](18, 3) NULL,
	[IsRevoke] [int] NULL,
	[EndShiftDate] [datetime] NULL,
	[EndDayID] [int] NULL,
	[StoreID] [int] NULL,
	[CarriageCash] [decimal](18, 3) NULL,
	[CarriageCredit] [decimal](18, 3) NULL,
	[DeliverooCredit] [decimal](18, 3) NULL,
	[DeliverooCash] [decimal](18, 3) NULL,
	[Tpay] [decimal](18, 3) NULL,
	[Bookeey] [decimal](18, 3) NULL,
	[MobileText] [nvarchar](30) NULL,
	[CustomerName] [nvarchar](200) NULL,
	[OrderType] [int] NOT NULL,
	[TrackingCode] [varchar](12) NULL,
	[ClientOrderGuid] [uniqueidentifier] NULL,
	[DiscountCode] [nvarchar](50) NULL,
	[SourceID] [int] NOT NULL,
	[PromisedTime] [datetime] NULL,
	[CancelReasonID] [int] NULL,
	[CancelComments] [nvarchar](1000) NULL,
	[CancelDisposition] [tinyint] NULL,
	[PrintCount] [int] NOT NULL,
	[LastPrintedOn] [datetime] NULL,
	[ModifiedOn] [datetime] NULL,
	[ModifiedBy] [int] NULL,
	[RowVer] [timestamp] NOT NULL,
	[InvoiceNumShow]  AS (CONVERT([char](8),[InvoiceDate],(112))+CONVERT([varchar](20),[InvoiceNo])) PERSISTED,
	[TableID] [int] NULL,
	[TableSessionID] [int] NULL,
 CONSTRAINT [PK_tblInvoice] PRIMARY KEY CLUSTERED 
(
	[InvoiceNo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblTable]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblTable](
	[TableID] [int] IDENTITY(1,1) NOT NULL,
	[Table_No] [varchar](50) NULL,
	[Capacity] [varchar](50) NULL,
	[Status] [int] NULL,
	[TableType] [int] NULL,
	[Xaxis] [decimal](18, 10) NULL,
	[Yaxis] [decimal](18, 10) NULL,
	[TakeAwayTableID] [nvarchar](50) NULL,
 CONSTRAINT [PK_tblTable] PRIMARY KEY CLUSTERED 
(
	[TableID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  UserDefinedFunction [dbo].[fn_POS_DineIn_Tables]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[fn_POS_DineIn_Tables] ()
RETURNS TABLE
AS
RETURN
(
    SELECT  t.TableID
          , Table_No      = LTRIM(RTRIM(CAST(t.Table_No AS NVARCHAR(30))))
          , Capacity      = ISNULL(TRY_CAST(t.Capacity AS INT), 4)
          , TableType     = ISNULL(t.TableType, 0)
          , Xaxis         = CAST(ISNULL(TRY_CAST(t.Xaxis AS DECIMAL(18,2)), 0) AS DECIMAL(18,2))
          , Yaxis         = CAST(ISNULL(TRY_CAST(t.Yaxis AS DECIMAL(18,2)), 0) AS DECIMAL(18,2))
          , Status        = CAST(CASE WHEN s.SessionID IS NOT NULL OR ISNULL(TRY_CAST(t.Status AS INT), 0) = 1
                                      THEN 1 ELSE 0 END AS INT)
          , IsLegacyLock  = CAST(CASE WHEN s.SessionID IS NULL AND ISNULL(TRY_CAST(t.Status AS INT), 0) = 1
                                      THEN 1 ELSE 0 END AS BIT)
          , s.SessionID
          , s.CustomerName
          , s.Mobile
          , Persons       = ISNULL(s.Persons, 0)
          , s.OpenedOn
          , s.OpenedByName
          , MinutesSeated = CASE WHEN s.OpenedOn IS NULL THEN 0 ELSE DATEDIFF(MINUTE, s.OpenedOn, GETDATE()) END
          , BillAmount    = CAST(ISNULL(b.Bill, 0) AS DECIMAL(18,3))
          , AmountPaid    = CAST(ISNULL(b.Paid, 0) AS DECIMAL(18,3))
          , InvoiceCount  = ISNULL(b.Cnt, 0)
    FROM      dbo.tblTable t
    LEFT JOIN dbo.tblPOS_TableSession s
           ON s.TableID = t.TableID AND s.ClosedOn IS NULL
    OUTER APPLY
    (
        SELECT  Bill = SUM(i.FinalAmount + ISNULL(i.DeliveryCharges, 0))
              , Paid = SUM(ISNULL(pp.Paid, 0))
              , Cnt  = COUNT(*)
        FROM    dbo.tblInvoice i
        OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                     FROM   dbo.tblInvoicePayment p
                     WHERE  p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0) pp
        WHERE   s.SessionID IS NOT NULL
          AND   i.TableSessionID = s.SessionID
          AND   ISNULL(i.Deleted, 0) = 0
          AND   ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
    ) b
);

GO
/****** Object:  UserDefinedFunction [dbo].[fn_POS_NormalizeAreaName]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fn_POS_NormalizeAreaName] (@n NVARCHAR(500))
RETURNS NVARCHAR(500)
WITH SCHEMABINDING
AS
BEGIN
    IF @n IS NULL RETURN NULL;

    DECLARE @s NVARCHAR(500) = LOWER(LTRIM(RTRIM(@n)));

    SET @s = REPLACE(@s, N'-',  N' ');
    SET @s = REPLACE(@s, N'_',  N' ');
    SET @s = REPLACE(@s, N'''', N'');
    SET @s = REPLACE(@s, N'.',  N'');
    SET @s = REPLACE(@s, N',',  N'');

    -- leading article, in both transliterations
    IF LEFT(@s, 3) = N'al '  SET @s = SUBSTRING(@s, 4, 500);
    IF LEFT(@s, 3) = N'el '  SET @s = SUBSTRING(@s, 4, 500);
    IF LEFT(@s, 3) = N'ال'   SET @s = SUBSTRING(@s, 3, 500);

    -- common transliteration tails: salmiya / salmiyah / salmiyeh
    IF RIGHT(@s, 3) = N'yah' SET @s = LEFT(@s, LEN(@s) - 1);
    IF RIGHT(@s, 3) = N'yeh' SET @s = LEFT(@s, LEN(@s) - 2) + N'a';

    SET @s = REPLACE(@s, N' ', N'');    -- collapse all spacing last

    RETURN @s;
END

GO
/****** Object:  Table [dbo].[Assign_Cat]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Assign_Cat](
	[CatNum] [int] NOT NULL,
	[BrandID] [int] NOT NULL,
	[BranchId] [int] NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[Assign_Item]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Assign_Item](
	[ItemId] [int] NOT NULL,
	[BrandID] [int] NOT NULL,
	[BranchId] [int] NOT NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[AuditTrail]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[AuditTrail](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[ErrorMessaage] [nvarchar](max) NULL,
	[StackTrace] [nvarchar](max) NULL,
	[InnerException] [nvarchar](max) NULL,
	[ControllerName] [nvarchar](500) NULL,
	[MethodName] [nvarchar](500) NULL,
	[Userid] [int] NULL,
	[CreatedOn] [datetime] NULL,
 CONSTRAINT [PK_AuditTrail] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[Feedback_Customer]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Feedback_Customer](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[CustomerName] [nvarchar](max) NULL,
	[Mobile] [float] NULL,
	[Email] [nvarchar](150) NULL,
	[UDID] [float] NULL,
	[BranchID] [int] NULL,
	[DateTime] [datetime] NULL,
 CONSTRAINT [PK_Feedback_Customer] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[Feedback_Data]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Feedback_Data](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[CustomerID] [int] NOT NULL,
	[Question] [nvarchar](500) NULL,
	[Response_Type] [int] NULL,
	[Response] [nvarchar](500) NULL,
	[Datetime] [datetime] NULL,
 CONSTRAINT [PK_Feedback_Data] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[Feedback_Layout]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Feedback_Layout](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[BrandID] [int] NULL,
	[Questions] [nvarchar](max) NULL,
	[Sequence] [int] NULL,
	[TypeId] [int] NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[Feedback_Type]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[Feedback_Type](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[Type] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tbl_Allergen]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tbl_Allergen](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[name] [nvarchar](500) NULL,
	[Name_arabic] [nvarchar](500) NULL,
	[image] [nvarchar](1000) NULL,
 CONSTRAINT [PK_tbl_Allergen] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tbl_Allergen_Assign]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tbl_Allergen_Assign](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[itemid] [int] NULL,
	[allergenid] [int] NULL,
 CONSTRAINT [PK_tbl_Allergen_Assign] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tbl_Menu_Colors]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tbl_Menu_Colors](
	[MenuColorId] [int] IDENTITY(1,1) NOT NULL,
	[BrandId] [int] NOT NULL,
	[BranchId] [int] NOT NULL,
	[header_background_color] [nvarchar](50) NULL,
	[header_icon_color] [nvarchar](50) NULL,
	[scroll_header_background_color] [nvarchar](50) NULL,
	[scroll_header_icon_color] [nvarchar](50) NULL,
	[fixd_item_list_title_background_color] [nvarchar](50) NULL,
	[fixd_item_list_title_text_color] [nvarchar](50) NULL,
	[category_page_background_color] [nvarchar](50) NULL,
	[category_page_card_primary_background_color] [nvarchar](50) NULL,
	[category_page_categoryname_color] [nvarchar](50) NULL,
	[item_page_background_color] [nvarchar](50) NULL,
	[item_page_category_title_bg_color] [nvarchar](50) NULL,
	[item_page_category_title_font_color] [nvarchar](50) NULL,
	[item_page_item_background_color] [nvarchar](50) NULL,
	[item_page_itemname_color] [nvarchar](50) NULL,
	[item_page_price_color] [nvarchar](50) NULL,
	[item_page_plus_button_color] [nvarchar](50) NULL,
	[item_page_plus_button_icon_color] [nvarchar](50) NULL,
	[product_details_title_bg_color] [nvarchar](50) NULL,
	[product_details_title_font_color] [nvarchar](50) NULL,
	[product_details_background_color] [nvarchar](50) NULL,
	[product_name] [nvarchar](50) NULL,
	[product_details_text] [nvarchar](50) NULL,
	[product_details_price] [nvarchar](50) NULL,
	[product_details_price_text] [nvarchar](50) NULL,
	[product_details_price_background_color] [nvarchar](50) NULL,
	[product_details_plus_button_color] [nvarchar](50) NULL,
	[product_details_plus_button_icon_color] [nvarchar](50) NULL,
	[category_carousel_background_color] [nvarchar](50) NULL,
	[Item_details_price_background_color] [nvarchar](50) NULL,
	[item_details_price_text] [nvarchar](50) NULL,
	[item_details_price_total_price_background_color] [nvarchar](50) NULL,
	[item_details_price_total_price_text] [nvarchar](50) NULL,
	[item_details_extra_price_text_color] [nvarchar](50) NULL,
 CONSTRAINT [PK_tbl_Menu_Colors] PRIMARY KEY CLUSTERED 
(
	[MenuColorId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblArea]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblArea](
	[AreaID] [int] IDENTITY(1,1) NOT NULL,
	[AreaName] [nvarchar](500) NULL,
	[AreaNameAra] [nvarchar](500) NULL,
	[DeliveryCharges] [decimal](18, 3) NULL,
	[Points] [decimal](18, 3) NULL,
	[BranchID] [int] NULL,
	[CenterLat] [decimal](10, 7) NULL,
	[CenterLng] [decimal](10, 7) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[TblArea_Mapping]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[TblArea_Mapping](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[AreaID] [int] NULL,
	[BranchID] [int] NULL,
 CONSTRAINT [PK_TblArea_Mapping] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblAreaMapData]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblAreaMapData](
	[AreaID] [int] NOT NULL,
	[PolygonVal] [varchar](max) NOT NULL,
 CONSTRAINT [PK_tblAreaMapData] PRIMARY KEY CLUSTERED 
(
	[AreaID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblAudit]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblAudit](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[IPAddress] [nvarchar](50) NULL,
	[BrowserName] [nvarchar](100) NULL,
	[DeviceModal] [nvarchar](50) NULL,
	[DeviceManufacturer] [nvarchar](50) NULL,
	[BranchId] [int] NULL,
	[CreatedOn] [datetime] NULL,
 CONSTRAINT [PK_tblAudit] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblAuditDetails]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblAuditDetails](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[AuditID] [int] NOT NULL,
	[ItemSelectionType] [int] NOT NULL,
	[ItemSelectionID] [int] NOT NULL,
	[ItemSelectionName] [nvarchar](100) NOT NULL,
	[CreatedOn] [datetime] NULL,
	[BranchId] [int] NULL,
 CONSTRAINT [PK_tblAuditDetails] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblbranch]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblbranch](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[branchName] [nvarchar](200) NULL,
	[branchNameAra] [nvarchar](200) NULL,
	[brandId] [int] NOT NULL,
	[SectionId] [int] NULL,
	[IsActive] [bit] NULL,
	[IsDeleted] [bit] NULL,
	[createdon] [datetime] NULL,
	[Image] [varchar](1000) NULL,
	[SEQ_NUM] [int] NULL,
 CONSTRAINT [PK_tblbranch] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblBrand]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblBrand](
	[BrandID] [int] IDENTITY(1,1) NOT NULL,
	[BrandName] [nvarchar](250) NULL,
	[BrandSeq] [int] NULL,
	[BrandNameAra] [nvarchar](500) NULL,
	[BrandImage] [nvarchar](500) NULL,
	[Theme] [nvarchar](50) NULL,
	[Russian] [int] NULL,
	[Mandarin] [int] NULL,
	[FeedBack] [bit] NULL,
	[Currency] [nvarchar](500) NULL,
	[Telephone] [nvarchar](500) NULL,
	[Facebook] [nvarchar](500) NULL,
	[Instagram] [nvarchar](500) NULL,
	[ShowPromotion] [bit] NULL,
	[IsOtherLanguages] [int] NULL,
	[url] [nvarchar](1000) NULL,
	[BrandHomePageImage] [nvarchar](500) NULL,
	[WhatsAppURL] [nvarchar](1000) NULL,
	[CurrencyArabic] [nvarchar](1000) NULL,
	[BannerImage] [varchar](500) NULL,
	[MobileImage] [varchar](500) NULL,
	[DesktopImage] [varchar](500) NULL,
	[Css] [varchar](1000) NULL,
	[ExpiryDate] [datetime] NULL,
	[Email] [varchar](500) NULL,
	[EmailReminderContent] [nvarchar](max) NULL,
	[EmailReminderCount] [int] NULL,
	[ContactDetails] [nvarchar](500) NULL,
	[Layout] [nvarchar](200) NULL,
	[Alert] [nvarchar](max) NULL,
	[MultipleBranch] [bit] NULL,
	[IsCartVisible] [bit] NULL,
	[PopupBannerImage] [nvarchar](1000) NULL,
	[ShowAllergen] [bit] NULL,
	[DecimalPlaces] [int] NULL,
	[WaiterLayout] [varchar](100) NULL,
	[IsItemDetailsBackToCategory] [bit] NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblCategory]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblCategory](
	[CAT_NUM] [int] IDENTITY(1,1) NOT NULL,
	[CAT_NAME] [varchar](50) NULL,
	[SEQ_NUM] [int] NULL,
	[ShowInTablet] [bit] NULL,
	[CAT_NAME_ARABIC] [nvarchar](150) NULL,
	[CatNameRus] [nvarchar](150) NULL,
	[CatNameMan] [nvarchar](150) NULL,
	[MainCategory] [int] NULL,
	[IsActive] [bit] NULL,
	[HID] [int] NULL,
	[BrandID] [int] NULL,
 CONSTRAINT [PK_tblCategory] PRIMARY KEY CLUSTERED 
(
	[CAT_NUM] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblCategoryName_Languages]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblCategoryName_Languages](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[CAT_NUM] [int] NULL,
	[chinese] [nvarchar](400) NULL,
	[turkish] [nvarchar](400) NULL,
	[hindi] [nvarchar](400) NULL,
	[korean] [nvarchar](400) NULL,
	[spain] [nvarchar](400) NULL,
	[bangladeshi] [nvarchar](400) NULL,
	[srilanka] [nvarchar](400) NULL,
	[iranian] [nvarchar](400) NULL,
	[italian] [nvarchar](400) NULL,
	[urdu] [nvarchar](400) NULL,
	[philippines] [nvarchar](400) NULL,
	[french] [nvarchar](400) NULL,
	[germany] [nvarchar](400) NULL,
 CONSTRAINT [PK_tblCategoryName_Languages] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblcomments]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblcomments](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[comments_eng] [nvarchar](300) NULL,
	[comments_arb] [nvarchar](300) NULL,
	[BrandId] [int] NULL,
 CONSTRAINT [PK_tblcomments] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblcompany]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblcompany](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[companyName] [nvarchar](200) NULL,
	[companyNameAra] [nvarchar](200) NULL,
	[NoOfFranchises] [int] NULL,
 CONSTRAINT [PK_tblcompany] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblCustomer]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblCustomer](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[firstName] [nvarchar](50) NULL,
	[lastName] [nvarchar](50) NULL,
	[mobile] [nvarchar](20) NULL,
	[email] [nvarchar](100) NULL,
	[areaId] [int] NULL,
	[block] [nvarchar](50) NULL,
	[street] [nvarchar](500) NULL,
	[building] [nvarchar](50) NULL,
	[flat] [nvarchar](50) NULL,
	[landmark] [nvarchar](50) NULL,
	[BrandID] [int] NULL,
	[CivilID] [nvarchar](50) NULL,
	[Mobile2] [nvarchar](20) NULL,
	[Notes] [nvarchar](1000) NULL,
	[IsBlocked] [bit] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[CreatedOn] [datetime] NOT NULL,
	[ModifiedOn] [datetime] NULL,
 CONSTRAINT [PK_tblCustomer] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblCustomerAddress]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblCustomerAddress](
	[AddressID] [int] IDENTITY(1,1) NOT NULL,
	[CustomerID] [int] NULL,
	[AreaID] [int] NULL,
	[Block] [nvarchar](50) NULL,
	[Street] [nvarchar](500) NULL,
	[Lane] [nvarchar](100) NULL,
	[Building] [nvarchar](50) NULL,
	[Floor] [nvarchar](50) NULL,
	[Flat] [nvarchar](50) NULL,
	[HouseNo] [nvarchar](50) NULL,
	[PACI] [nvarchar](50) NULL,
	[AddressRemark] [nvarchar](500) NULL,
	[Lat] [nvarchar](50) NULL,
	[Lng] [nvarchar](50) NULL,
	[Email] [nvarchar](100) NULL,
	[IsDefault] [bit] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[CreatedOn] [datetime] NOT NULL,
 CONSTRAINT [PK_tblCustomerAddress] PRIMARY KEY CLUSTERED 
(
	[AddressID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblDenomination]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblDenomination](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[DenominationType] [nvarchar](50) NULL,
	[DenominationValue] [decimal](18, 3) NULL,
 CONSTRAINT [PK_tblDenomination] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblDenominationDetails]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblDenominationDetails](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[EndShiftID] [int] NULL,
	[DenominationTypeID] [int] NULL,
	[DenominationType] [nvarchar](50) NULL,
	[Count] [int] NULL,
	[Total] [decimal](18, 3) NULL,
 CONSTRAINT [PK_tblDenominationDetails] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblDiscount_Type]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblDiscount_Type](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[DiscountTypeName] [nvarchar](500) NULL,
	[DiscountPercentage] [int] NULL,
	[SequenceNo] [int] NULL,
	[isPercentage] [bit] NULL,
	[IsActive] [bit] NULL,
	[IsDeleted] [bit] NULL,
	[createdon] [datetime] NULL,
	[updatedon] [datetime] NULL,
 CONSTRAINT [PK_tblDiscount_Type] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblDiscountCode]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblDiscountCode](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[DiscountCode] [nvarchar](500) NULL,
	[DiscountTypeId] [int] NULL,
	[Isactive] [bit] NULL,
 CONSTRAINT [PK_tblDiscountCode] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblDriver]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblDriver](
	[DriverID] [int] IDENTITY(1,1) NOT NULL,
	[BranchID] [int] NULL,
	[DriverName] [nvarchar](max) NULL,
	[DriverCode] [nvarchar](250) NULL,
	[DriverNameAr] [nvarchar](250) NULL,
	[DriverTel] [int] NULL,
	[color] [nvarchar](20) NULL,
	[DriverImage] [nvarchar](100) NULL,
	[Password] [nvarchar](100) NULL,
	[CompanyName] [nvarchar](500) NULL,
	[DeliveryCost] [decimal](18, 3) NULL,
	[CivilID] [nvarchar](200) NULL,
 CONSTRAINT [PK_tblDriver] PRIMARY KEY CLUSTERED 
(
	[DriverID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblDriverTracking]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblDriverTracking](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[DriverId] [int] NULL,
	[InvoiceNo] [bigint] NULL,
	[latitude] [nvarchar](50) NULL,
	[longitude] [nvarchar](50) NULL,
	[OnDateTime] [datetime] NULL,
	[deleted] [bit] NULL,
	[EstimatedTimeArrivalMinutes] [int] NULL,
 CONSTRAINT [PK_tblDriverTracking] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblEndDay]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblEndDay](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[HID] [int] NULL,
	[BID] [int] NULL,
	[BranchID] [int] NULL,
	[StartDate] [datetime] NULL,
	[EndDate] [datetime] NULL,
	[ManagerName] [varchar](50) NULL,
	[ManagerID] [int] NULL,
	[IsSent] [bit] NULL,
	[SynchroniseDate] [datetime] NULL,
	[reUseAmount] [money] NULL,
	[reUseCount] [int] NULL,
	[wasteAmount] [money] NULL,
	[wasteCount] [int] NULL,
 CONSTRAINT [PK_tblEndDay] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblEndDayDiscount]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblEndDayDiscount](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[HID] [int] NULL,
	[BID] [int] NULL,
	[EndDayID] [int] NOT NULL,
	[DiscountAmount] [money] NULL,
	[DiscountType] [nvarchar](50) NULL,
	[DiscountTypeID] [int] NULL,
	[InvoiceType] [varchar](10) NULL,
	[ItemID] [int] NULL,
	[DiscountDate] [datetime] NULL,
	[InvoiceNo] [bigint] NULL,
	[SynchroniseDate] [datetime] NULL,
	[IsSent] [bit] NULL,
	[BranchID] [int] NULL,
 CONSTRAINT [PK_tblEndDayDiscount] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblEndDayPayment]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblEndDayPayment](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[EndDayID] [int] NULL,
	[HID] [int] NULL,
	[BID] [int] NULL,
	[BranchID] [int] NULL,
	[InvoiceType] [int] NULL,
	[CashAmount] [money] NULL,
	[CancelAmount] [money] NULL,
	[InvoiceCount] [int] NULL,
	[DeleteInvoiceCount] [int] NULL,
	[IsSent] [int] NULL,
	[SynchroniseDate] [datetime] NULL,
	[GrossSales] [money] NULL,
	[Discount] [money] NULL,
	[TotalSales] [money] NULL,
	[DeliveryCharges] [money] NULL,
	[NetSales] [money] NULL,
	[NetSalesWOVATamount]  AS ([TotalSales]-[DeliveryCharges]),
	[VATamount]  AS ((0)),
 CONSTRAINT [PK_tblEndDayPayment] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblEndDayPaymentTypeDetails]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblEndDayPaymentTypeDetails](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[EndDayID] [int] NULL,
	[HID] [int] NULL,
	[BID] [int] NULL,
	[InvoiceType] [int] NULL,
	[PaymentTypeID] [int] NULL,
	[PaymentType] [nvarchar](50) NULL,
	[BranchId] [int] NULL,
	[Amount] [money] NULL,
	[InvoiceCount] [int] NULL,
	[IsSent] [bit] NULL,
	[SynchroniseDate] [datetime] NULL,
 CONSTRAINT [PK_tblEndDayPaymentTypeDetails] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblEndshiftPaymentTypeDetails]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblEndshiftPaymentTypeDetails](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[EndShiftID] [int] NULL,
	[HID] [int] NULL,
	[BID] [int] NULL,
	[PaymentID] [int] NULL,
	[PaymentType] [nvarchar](50) NULL,
	[BranchId] [int] NULL,
	[Amount] [money] NULL,
	[AmountPK] [money] NULL,
	[AmountCC] [money] NULL,
	[InvoiceCount] [int] NULL,
	[IsSent] [bit] NULL,
	[SynchroniseDate] [datetime] NULL,
 CONSTRAINT [PK_tblEndshiftPaymentTypeDetails] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblExtra]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblExtra](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[ItemID] [int] NULL,
	[ExtraName] [nvarchar](max) NULL,
	[ExtraNameAra] [nvarchar](max) NULL,
	[Price] [nvarchar](max) NULL,
	[ImageName] [nvarchar](max) NULL,
	[BrandID] [int] NOT NULL,
 CONSTRAINT [PK_tblExtra] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblGroup_Modifier_Details]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblGroup_Modifier_Details](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[MainItemId] [int] NULL,
	[GroupId] [int] NULL,
	[Deleted] [bit] NULL,
	[ItemID] [int] NULL,
	[Seq_Num] [int] NULL,
 CONSTRAINT [PK_tblItemsGroupModifier] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblGroup_Modifier_Master]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblGroup_Modifier_Master](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[GroupNameEng] [nvarchar](500) NULL,
	[GroupNameArb] [nvarchar](500) NULL,
	[Type] [int] NULL,
	[MinSelect] [int] NULL,
	[MaxSelect] [int] NULL,
	[Seq_Num] [int] NULL,
	[BrandId] [int] NULL,
 CONSTRAINT [PK_tblGroup_Modifier] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblGroup_Modifier_Sub_Details]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblGroup_Modifier_Sub_Details](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[GroupID] [int] NOT NULL,
	[ItemID] [int] NULL,
	[ExtraID] [int] NOT NULL,
	[Seq_Num] [int] NULL,
 CONSTRAINT [PK_tblItem_Extra] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblGroup_Modifier_Type]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblGroup_Modifier_Type](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[TypeName_Deliverect] [nvarchar](200) NULL,
	[TypeName_TMM] [nvarchar](200) NULL,
 CONSTRAINT [PK_tblGroup_Modifier_Type] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblImageSlideShow]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblImageSlideShow](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[SlideImageName] [nvarchar](max) NULL,
	[ImageSequence] [int] NOT NULL,
	[BrandID] [int] NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblIngredientName_Languages]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblIngredientName_Languages](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[ItemID] [int] NULL,
	[chinese] [nvarchar](400) NULL,
	[turkish] [nvarchar](400) NULL,
	[hindi] [nvarchar](400) NULL,
	[korean] [nvarchar](400) NULL,
	[spain] [nvarchar](400) NULL,
	[bangladeshi] [nvarchar](400) NULL,
	[srilanka] [nvarchar](400) NULL,
	[iranian] [nvarchar](400) NULL,
	[italian] [nvarchar](400) NULL,
	[urdu] [nvarchar](400) NULL,
	[philippines] [nvarchar](400) NULL,
	[french] [nvarchar](400) NULL,
	[germany] [nvarchar](400) NULL,
 CONSTRAINT [PK_tblIngredientName_Languages] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblInvoicePaymentType]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblInvoicePaymentType](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[PaymentTypeName] [nvarchar](100) NULL,
	[PaymentTypeNameArb] [nvarchar](100) NULL,
	[Seqnum] [int] NULL,
	[IsActive] [bit] NULL,
	[IsDeleted] [bit] NULL,
	[createdon] [datetime] NULL,
	[updatedon] [datetime] NULL,
	[IsCash] [bit] NOT NULL,
	[IsOnline] [bit] NOT NULL,
	[RequiresReference] [bit] NOT NULL,
	[LegacyColumn] [sysname] NULL,
	[IsCOD] [bit] NOT NULL,
	[Image] [nvarchar](max) NULL,
	[Provider] [varchar](30) NULL,
 CONSTRAINT [PK_tblInvoicePaymentType] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblInvoiceType_Master]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblInvoiceType_Master](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[Name] [nvarchar](100) NULL,
	[ShowInCallCentre] [bit] NULL,
 CONSTRAINT [PK_tblInvoiceType_Master] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblInvoiceType_Master_Details]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblInvoiceType_Master_Details](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[Channel_Name] [nvarchar](100) NULL,
	[Invoice_Type] [int] NULL,
	[Channel_ID] [nvarchar](100) NULL,
	[BrandID] [int] NULL,
 CONSTRAINT [PK_tblInvoiceTypeMapping] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblItem_Choices]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblItem_Choices](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[ItemId] [int] NULL,
	[ChoiceId] [int] NULL,
 CONSTRAINT [PK_tblItem_Choices] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblItem_Extras]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblItem_Extras](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[ItemId] [int] NULL,
	[ExtraItemId] [int] NULL,
 CONSTRAINT [PK_tblItem_Extras] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblItemComments]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblItemComments](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[commentid] [int] NULL,
	[itemid] [int] NULL,
 CONSTRAINT [PK_tblItemComments] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblItemImages]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblItemImages](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[ItemID] [int] NOT NULL,
	[Imagename] [nvarchar](max) NULL,
	[Seq_No] [int] NULL,
	[Deleted] [bit] NULL,
	[Datetime] [datetime] NULL,
 CONSTRAINT [PK_tblItemImages] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblItems]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblItems](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[CAT_NUM] [int] NULL,
	[ITEM_NAME] [varchar](100) NULL,
	[PRICE] [decimal](18, 3) NULL,
	[ITEM_NAME_ARABIC] [nvarchar](100) NULL,
	[INGREDIENT] [varchar](max) NULL,
	[INGREDIENT_ARABIC] [nvarchar](max) NULL,
	[IMAGENAME] [nvarchar](50) NULL,
	[ITEM_DESC_ENG] [nvarchar](500) NULL,
	[Seq_Num] [int] NULL,
	[ItemNameRus] [nvarchar](500) NULL,
	[ItemNameMan] [nvarchar](500) NULL,
	[INGREDIENT_Rus] [nvarchar](500) NULL,
	[INGREDIENT_Man] [nvarchar](500) NULL,
	[ShowInTablet] [bit] NULL,
	[Video] [nvarchar](500) NULL,
	[OutOfStock] [bit] NULL,
	[HID] [int] NULL,
	[isExtra] [bit] NULL,
	[IsActive] [bit] NULL,
	[Ischoice] [bit] NULL,
 CONSTRAINT [PK_tblItems_1] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblItemsName_Languages]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblItemsName_Languages](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[ItemID] [int] NULL,
	[chinese] [nvarchar](400) NULL,
	[turkish] [nvarchar](400) NULL,
	[hindi] [nvarchar](400) NULL,
	[korean] [nvarchar](400) NULL,
	[spain] [nvarchar](400) NULL,
	[bangladeshi] [nvarchar](400) NULL,
	[srilanka] [nvarchar](400) NULL,
	[iranian] [nvarchar](400) NULL,
	[italian] [nvarchar](400) NULL,
	[urdu] [nvarchar](400) NULL,
	[philippines] [nvarchar](400) NULL,
	[french] [nvarchar](400) NULL,
	[germany] [nvarchar](400) NULL,
 CONSTRAINT [PK_tblItemsName_Languages] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblLabelName]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblLabelName](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[labelName] [nvarchar](100) NULL,
	[labelNameEng] [nvarchar](200) NULL,
	[labelNameArb] [nvarchar](200) NULL,
 CONSTRAINT [PK_tblLabelName] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblMenuTheme]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblMenuTheme](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[Name] [nvarchar](500) NULL,
	[BrandID] [int] NULL,
	[BranchID] [int] NULL,
	[Color] [nvarchar](50) NULL,
 CONSTRAINT [PK_tblMenuTheme] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblOrder]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblOrder](
	[OrderID] [bigint] IDENTITY(1,1) NOT NULL,
	[InvoiceNo] [bigint] NULL,
	[ItemID] [int] NULL,
	[Quantity] [int] NULL,
	[Price] [decimal](18, 3) NULL,
	[SentToPrinter] [bit] NULL,
	[Comments] [nvarchar](max) NULL,
	[Extra] [nvarchar](max) NULL,
	[DeleteOrderComment] [nvarchar](max) NULL,
	[WaiterID] [int] NULL,
	[Prepared] [bit] NULL,
	[Combined] [bit] NULL,
	[Delivered] [bit] NULL,
	[Dispatcher] [bit] NULL,
	[Deleted] [bit] NULL,
	[OrderDate] [datetime] NULL,
	[TableType] [int] NULL,
	[TotalAmount]  AS ([Quantity]*[Price]-isnull([Discount],(0))),
	[Waste] [bit] NULL,
	[DeletePasswordUserID] [nvarchar](max) NULL,
	[DeletedDate] [datetime] NULL,
	[SynchroniseDate] [datetime] NULL,
	[IsSent] [bit] NULL,
	[syncAttempt] [int] NULL,
	[DiscountTypeID] [int] NULL,
	[Discount] [decimal](18, 3) NULL,
	[BranchID] [int] NULL,
	[CostPrice] [decimal](18, 3) NULL,
	[ParentOrderID] [bigint] NULL,
	[CartItemUniqID] [int] NULL,
	[LineType] [tinyint] NOT NULL,
	[ItemNameSnapshot] [nvarchar](200) NULL,
	[IsSplit] [bit] NOT NULL,
	[SplitToInvoiceNo] [bigint] NULL,
	[SplitFromOrderID] [bigint] NULL,
 CONSTRAINT [PK_tblOrder] PRIMARY KEY CLUSTERED 
(
	[OrderID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblOrderStatus]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblOrderStatus](
	[OrderStatusID] [int] NOT NULL,
	[OrderStatusName] [nvarchar](max) NULL,
	[SmsContent] [nvarchar](max) NULL,
	[MessageSend] [bit] NULL,
	[OrderStatusNameAra] [nvarchar](100) NULL,
	[SortOrder] [int] NULL,
	[ColorHex] [varchar](7) NULL,
	[IsTerminal] [bit] NOT NULL,
	[AppliesToPickup] [bit] NOT NULL,
	[AppliesToDelivery] [bit] NOT NULL,
	[IsActive] [bit] NOT NULL,
 CONSTRAINT [PK_tblOrderStatus] PRIMARY KEY CLUSTERED 
(
	[OrderStatusID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPaymentVoucher]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPaymentVoucher](
	[VoucherID] [int] IDENTITY(1,1) NOT NULL,
	[VoucherType] [int] NULL,
	[PaymentTo] [int] NULL,
	[PaymentType] [int] NULL,
 CONSTRAINT [PK_tblPaymentVoucher] PRIMARY KEY CLUSTERED 
(
	[VoucherID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPaymentVoucherDetails]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPaymentVoucherDetails](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[VoucherID] [int] NULL,
	[Description] [nvarchar](max) NULL,
	[Amount] [decimal](18, 3) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPaymentVoucherType]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPaymentVoucherType](
	[VoucherTypeID] [int] IDENTITY(1,1) NOT NULL,
	[Description] [nvarchar](max) NULL,
 CONSTRAINT [PK_tblPaymentVoucherType] PRIMARY KEY CLUSTERED 
(
	[VoucherTypeID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_AuditLog]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_AuditLog](
	[AuditID] [bigint] IDENTITY(1,1) NOT NULL,
	[EntityType] [varchar](50) NOT NULL,
	[EntityID] [bigint] NULL,
	[Action] [varchar](50) NOT NULL,
	[UserID] [int] NULL,
	[UserName] [nvarchar](100) NULL,
	[Details] [nvarchar](max) NULL,
	[IPAddress] [varchar](45) NULL,
	[CreatedOn] [datetime] NOT NULL,
 CONSTRAINT [PK_tblPOS_AuditLog] PRIMARY KEY CLUSTERED 
(
	[AuditID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_BranchSetting]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_BranchSetting](
	[BranchID] [int] NOT NULL,
	[ThermalWidthMM] [int] NOT NULL,
	[AutoPrintOnNew] [bit] NOT NULL,
	[DefaultPrepMinutes] [int] NOT NULL,
	[MaxOpenOrders] [int] NULL,
	[SoundOnNewOrder] [bit] NOT NULL,
 CONSTRAINT [PK_tblPOS_BranchSetting] PRIMARY KEY CLUSTERED 
(
	[BranchID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_CancelReason_Master]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_CancelReason_Master](
	[CancelReasonID] [int] IDENTITY(1,1) NOT NULL,
	[ReasonName] [nvarchar](100) NOT NULL,
	[ReasonNameAra] [nvarchar](100) NULL,
	[DefaultDisposition] [tinyint] NULL,
	[IsActive] [bit] NOT NULL,
	[FeedsEndDay] [bit] NOT NULL,
 CONSTRAINT [PK_tblPOS_CancelReason_Master] PRIMARY KEY CLUSTERED 
(
	[CancelReasonID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_DailyCounter]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_DailyCounter](
	[BranchID] [int] NOT NULL,
	[CounterDate] [date] NOT NULL,
	[LastNumber] [int] NOT NULL,
 CONSTRAINT [PK_tblPOS_DailyCounter] PRIMARY KEY CLUSTERED 
(
	[BranchID] ASC,
	[CounterDate] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_GeoCache]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_GeoCache](
	[Lat] [decimal](10, 4) NOT NULL,
	[Lng] [decimal](10, 4) NOT NULL,
	[Block] [nvarchar](50) NULL,
	[Neighbourhood] [nvarchar](200) NULL,
	[RawJson] [nvarchar](max) NULL,
	[CreatedOn] [datetime] NOT NULL,
	[HitCount] [int] NOT NULL,
 CONSTRAINT [PK_tblPOS_GeoCache] PRIMARY KEY CLUSTERED 
(
	[Lat] ASC,
	[Lng] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_OrderStatusHistory]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_OrderStatusHistory](
	[HistoryID] [bigint] IDENTITY(1,1) NOT NULL,
	[InvoiceNo] [bigint] NOT NULL,
	[FromStatusID] [int] NULL,
	[ToStatusID] [int] NOT NULL,
	[ChangedBy] [int] NULL,
	[ChangedByName] [nvarchar](100) NULL,
	[ChangedOn] [datetime] NOT NULL,
	[Comments] [nvarchar](1000) NULL,
	[DriverID] [int] NULL,
 CONSTRAINT [PK_tblPOS_OrderStatusHistory] PRIMARY KEY CLUSTERED 
(
	[HistoryID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_OrderStatusTransition]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_OrderStatusTransition](
	[FromStatusID] [int] NOT NULL,
	[ToStatusID] [int] NOT NULL,
	[RequiresRole] [int] NULL,
 CONSTRAINT [PK_tblPOS_OrderStatusTransition] PRIMARY KEY CLUSTERED 
(
	[FromStatusID] ASC,
	[ToStatusID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_OrderTransfer]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_OrderTransfer](
	[TransferID] [bigint] IDENTITY(1,1) NOT NULL,
	[InvoiceNo] [bigint] NOT NULL,
	[FromBranchID] [int] NOT NULL,
	[ToBranchID] [int] NOT NULL,
	[Reason] [nvarchar](500) NULL,
	[TransferredBy] [int] NULL,
	[TransferredOn] [datetime] NOT NULL,
 CONSTRAINT [PK_tblPOS_OrderTransfer] PRIMARY KEY CLUSTERED 
(
	[TransferID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_PaymentLink]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_PaymentLink](
	[LinkID] [bigint] IDENTITY(1,1) NOT NULL,
	[InvoiceNo] [bigint] NOT NULL,
	[Provider] [varchar](30) NOT NULL,
	[PaymentTypeID] [int] NULL,
	[CustomerReference] [varchar](60) NOT NULL,
	[ProviderInvoiceId] [varchar](60) NULL,
	[ProviderPaymentId] [varchar](60) NULL,
	[Amount] [decimal](18, 3) NOT NULL,
	[PaidAmount] [decimal](18, 3) NULL,
	[CurrencyIso] [varchar](5) NULL,
	[PaymentUrl] [nvarchar](1000) NULL,
	[Status] [varchar](20) NOT NULL,
	[FailureReason] [nvarchar](500) NULL,
	[RawResponse] [nvarchar](max) NULL,
	[CreatedBy] [int] NULL,
	[CreatedOn] [datetime] NOT NULL,
	[CompletedOn] [datetime] NULL,
 CONSTRAINT [PK_tblPOS_PaymentLink] PRIMARY KEY CLUSTERED 
(
	[LinkID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_Printer]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_Printer](
	[PrinterID] [int] IDENTITY(1,1) NOT NULL,
	[BranchID] [int] NOT NULL,
	[PrinterName] [nvarchar](100) NOT NULL,
	[IPAddress] [varchar](45) NOT NULL,
	[Port] [int] NOT NULL,
	[PaperWidthMM] [int] NOT NULL,
	[PrintInvoice] [bit] NOT NULL,
	[PrintOrder] [bit] NOT NULL,
	[AllCategories] [bit] NOT NULL,
	[IsActive] [bit] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[CreatedOn] [datetime] NOT NULL,
	[CreatedBy] [int] NULL,
	[ModifiedOn] [datetime] NULL,
	[ModifiedBy] [int] NULL,
 CONSTRAINT [PK_tblPOS_Printer] PRIMARY KEY CLUSTERED 
(
	[PrinterID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_PrinterCategory]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_PrinterCategory](
	[PrinterID] [int] NOT NULL,
	[CAT_NUM] [int] NOT NULL,
 CONSTRAINT [PK_tblPOS_PrinterCategory] PRIMARY KEY CLUSTERED 
(
	[PrinterID] ASC,
	[CAT_NUM] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_Role_Master]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_Role_Master](
	[RoleID] [int] NOT NULL,
	[RoleName] [nvarchar](50) NOT NULL,
	[CanChangeStatus] [bit] NOT NULL,
	[CanCancel] [bit] NOT NULL,
	[CanRefund] [bit] NOT NULL,
	[CanTransfer] [bit] NOT NULL,
	[CanTakePayment] [bit] NOT NULL,
	[CanViewReports] [bit] NOT NULL,
	[CanEndDay] [bit] NOT NULL,
	[CanManageMasters] [bit] NOT NULL,
 CONSTRAINT [PK_tblPOS_Role_Master] PRIMARY KEY CLUSTERED 
(
	[RoleID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_TableArea]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_TableArea](
	[TableType] [int] NOT NULL,
	[AreaName] [nvarchar](100) NOT NULL,
	[SortOrder] [int] NOT NULL,
	[IsActive] [bit] NOT NULL,
 CONSTRAINT [PK_tblPOS_TableArea] PRIMARY KEY CLUSTERED 
(
	[TableType] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPOS_UserBranch_Map]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPOS_UserBranch_Map](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[UserID] [int] NOT NULL,
	[BranchID] [int] NOT NULL,
 CONSTRAINT [PK_tblPOS_UserBranch_Map] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblPOS_UserBranch_Map] UNIQUE NONCLUSTERED 
(
	[UserID] ASC,
	[BranchID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPrinter]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPrinter](
	[PrinterNo] [int] NULL,
	[PrinterName] [nvarchar](max) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblPromotion]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblPromotion](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[ImageName] [nvarchar](max) NULL,
	[ImageSequence] [int] NOT NULL,
	[BrandID] [int] NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblReservation]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblReservation](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[branchId] [int] NULL,
	[sloteId] [int] NULL,
	[reservationDate] [datetime] NULL,
	[customerName] [nvarchar](100) NULL,
	[customerMobile] [nvarchar](20) NULL,
	[customerEmail] [nvarchar](100) NULL,
	[comments] [nvarchar](250) NULL,
	[confirmationId] [nvarchar](50) NULL,
	[Status] [int] NULL,
	[TransactionDate] [datetime] NULL,
	[TableStructureID] [int] NULL,
	[MeargedTableid] [int] NULL,
 CONSTRAINT [PK_tblReservation] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblReservationSlot]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblReservationSlot](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[slotName] [nvarchar](100) NULL,
	[slotNameArabic] [nvarchar](100) NULL,
	[fromTime] [time](7) NULL,
	[toTime] [time](7) NULL,
	[IsDeleted] [bit] NULL,
 CONSTRAINT [PK_tblReservationSlot] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblReservationStatus]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblReservationStatus](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[StatusName] [nvarchar](100) NULL,
	[isActive] [bit] NULL,
 CONSTRAINT [PK_tblReservationStatus] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblReservationTableStructure]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblReservationTableStructure](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[TableName] [nvarchar](50) NULL,
	[DiningArea] [nvarchar](50) NULL,
	[Seating] [int] NULL,
	[Xaxis] [decimal](18, 10) NULL,
	[Yaxis] [decimal](18, 10) NULL,
	[IsDeleted] [bit] NULL,
 CONSTRAINT [PK_tblReservationTableStructure] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblRole]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblRole](
	[Role_ID] [int] NOT NULL,
	[RoleName] [varchar](50) NOT NULL,
 CONSTRAINT [PK_tblRole] PRIMARY KEY CLUSTERED 
(
	[Role_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblSection]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblSection](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[SectionName] [nvarchar](100) NULL,
	[SectionNameArabic] [nvarchar](100) NULL,
	[SequanceNo] [int] NULL,
 CONSTRAINT [PK_tblSection] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblSetting]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblSetting](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[ExpiryDate] [date] NULL,
	[Password] [nchar](20) NULL,
	[ORdertaking] [bit] NULL,
	[isReservation] [bit] NULL,
	[MultipleBranch] [bit] NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblTableType]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblTableType](
	[ID] [int] NOT NULL,
	[Description] [nvarchar](50) NOT NULL,
	[InvoicePrinter] [varchar](150) NULL,
	[AssignDriverPrint] [varchar](150) NULL,
 CONSTRAINT [PK_tblTableType] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblTheme]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblTheme](
	[ThemeID] [int] IDENTITY(1,1) NOT NULL,
	[ThemeName] [nvarchar](50) NULL,
	[CategoryActive] [nvarchar](50) NULL,
	[CategoryInActive] [nvarchar](50) NULL,
	[Setting] [nvarchar](50) NULL,
	[SeperatorLine] [nvarchar](50) NULL,
	[EnglishButton] [nvarchar](50) NULL,
	[ArabicButton] [nvarchar](50) NULL,
	[MandarinButton] [nvarchar](50) NULL,
	[RussianButton] [nvarchar](50) NULL,
	[CloseButton] [nvarchar](50) NULL,
	[HomeScreen] [nvarchar](50) NULL,
	[LeftArrow] [nvarchar](50) NULL,
	[LeftBottom] [nvarchar](50) NULL,
	[LeftTop] [nvarchar](50) NULL,
	[PopUpBackground] [nvarchar](50) NULL,
	[RightArrow] [nvarchar](50) NULL,
	[RightButton] [nvarchar](50) NULL,
	[RightTop] [nvarchar](50) NULL,
	[FontColor] [varchar](9) NULL,
	[FontColorItemName] [varchar](9) NULL,
	[FontColorIngName] [varchar](9) NULL,
	[FontColorPrice] [varchar](9) NULL,
	[ItemBackgroundColor] [varchar](9) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblUser]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblUser](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[NAME] [varchar](50) NULL,
	[USERNAME] [varchar](50) NULL,
	[PASSWORD] [varchar](50) NULL,
	[DeletePassword] [varchar](50) NULL,
	[BrandID] [varchar](50) NULL,
	[RoleID] [int] NULL,
	[PasswordHash] [varbinary](64) NULL,
	[PasswordSalt] [varbinary](32) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[tblWebImageSlideShow]    Script Date: 30/10/2026 13:37:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblWebImageSlideShow](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[WebSlideImageName] [nvarchar](max) NULL,
	[WebImageSequence] [int] NOT NULL,
	[BrandID] [int] NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Index [UX_Allergen_Assign_Item_Allergen]    Script Date: 30/10/2026 13:37:40 ******/
CREATE UNIQUE NONCLUSTERED INDEX [UX_Allergen_Assign_Item_Allergen] ON [dbo].[tbl_Allergen_Assign]
(
	[itemid] ASC,
	[allergenid] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [UX_tbl_Menu_Colors_Brand_Branch]    Script Date: 30/10/2026 13:37:40 ******/
CREATE UNIQUE NONCLUSTERED INDEX [UX_tbl_Menu_Colors_Brand_Branch] ON [dbo].[tbl_Menu_Colors]
(
	[BrandId] ASC,
	[BranchId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_TblArea_Mapping_Area]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_TblArea_Mapping_Area] ON [dbo].[TblArea_Mapping]
(
	[AreaID] ASC
)
INCLUDE([BranchID]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_TblArea_Mapping_Branch]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_TblArea_Mapping_Branch] ON [dbo].[TblArea_Mapping]
(
	[BranchID] ASC
)
INCLUDE([AreaID]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [UX_tblCustomer_Mobile]    Script Date: 30/10/2026 13:37:40 ******/
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblCustomer_Mobile] ON [dbo].[tblCustomer]
(
	[mobile] ASC
)
WHERE ([mobile] IS NOT NULL AND [IsDeleted]=(0))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_tblCustomerAddress_Customer]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblCustomerAddress_Customer] ON [dbo].[tblCustomerAddress]
(
	[CustomerID] ASC
)
WHERE ([IsDeleted]=(0))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [IX_tblDiscountCode_Code]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblDiscountCode_Code] ON [dbo].[tblDiscountCode]
(
	[DiscountCode] ASC
)
INCLUDE([DiscountTypeId],[Isactive]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_tblDriver_Branch]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblDriver_Branch] ON [dbo].[tblDriver]
(
	[BranchID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_tblDriverTracking_Invoice]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblDriverTracking_Invoice] ON [dbo].[tblDriverTracking]
(
	[InvoiceNo] ASC,
	[OnDateTime] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_tblInvoice_Customer]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblInvoice_Customer] ON [dbo].[tblInvoice]
(
	[CustomerId] ASC,
	[InvoiceDate] DESC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
SET ARITHABORT ON
SET CONCAT_NULL_YIELDS_NULL ON
SET QUOTED_IDENTIFIER ON
SET ANSI_NULLS ON
SET ANSI_PADDING ON
SET ANSI_WARNINGS ON
SET NUMERIC_ROUNDABORT OFF
GO
/****** Object:  Index [IX_tblInvoice_InvoiceNumShow]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblInvoice_InvoiceNumShow] ON [dbo].[tblInvoice]
(
	[InvoiceNumShow] ASC
)
INCLUDE([InvoiceNo],[InvoiceDate]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [IX_tblInvoice_Mobile]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblInvoice_Mobile] ON [dbo].[tblInvoice]
(
	[MobileText] ASC
)
INCLUDE([InvoiceDate],[BillAmount]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_tblInvoice_POSGrid]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblInvoice_POSGrid] ON [dbo].[tblInvoice]
(
	[BranchID] ASC,
	[InvoiceDate] ASC,
	[OrderStatusID] ASC
)
INCLUDE([InvoiceNo],[TrackingCode],[CustomerName],[CustomerId],[AddressID],[BrandID],[Deleted],[MobileText],[BillAmount],[Discount],[DeliveryCharges],[PaymentType],[OrderType]) 
WHERE ([Deleted]=(0))
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_tblInvoice_TableSessionID]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblInvoice_TableSessionID] ON [dbo].[tblInvoice]
(
	[TableSessionID] ASC
)
INCLUDE([BillAmount],[Discount],[Deleted],[OrderStatusID]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [UX_tblInvoice_ClientOrderGuid]    Script Date: 30/10/2026 13:37:40 ******/
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblInvoice_ClientOrderGuid] ON [dbo].[tblInvoice]
(
	[ClientOrderGuid] ASC
)
WHERE ([ClientOrderGuid] IS NOT NULL)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [UX_tblInvoice_TrackingCode]    Script Date: 30/10/2026 13:37:40 ******/
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblInvoice_TrackingCode] ON [dbo].[tblInvoice]
(
	[TrackingCode] ASC
)
WHERE ([TrackingCode] IS NOT NULL)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_tblInvoicePayment_Invoice]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblInvoicePayment_Invoice] ON [dbo].[tblInvoicePayment]
(
	[InvoiceId] ASC
)
INCLUDE([PaymentTypeID],[Amount],[IsRefund]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_tblOrder_InvoiceNo]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblOrder_InvoiceNo] ON [dbo].[tblOrder]
(
	[InvoiceNo] ASC
)
INCLUDE([ItemID],[Quantity],[Price],[Comments],[Extra],[Deleted]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [IX_tblPOS_AuditLog_Entity]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblPOS_AuditLog_Entity] ON [dbo].[tblPOS_AuditLog]
(
	[EntityType] ASC,
	[EntityID] ASC,
	[CreatedOn] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_tblPOS_OrderStatusHistory_Invoice]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblPOS_OrderStatusHistory_Invoice] ON [dbo].[tblPOS_OrderStatusHistory]
(
	[InvoiceNo] ASC,
	[ChangedOn] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_tblPOS_OrderTransfer_Invoice]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblPOS_OrderTransfer_Invoice] ON [dbo].[tblPOS_OrderTransfer]
(
	[InvoiceNo] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [IX_PayLink_Invoice]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_PayLink_Invoice] ON [dbo].[tblPOS_PaymentLink]
(
	[InvoiceNo] ASC,
	[Status] ASC
)
INCLUDE([Amount],[CreatedOn]) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [IX_PayLink_ProviderInvoice]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_PayLink_ProviderInvoice] ON [dbo].[tblPOS_PaymentLink]
(
	[ProviderInvoiceId] ASC
)
WHERE ([ProviderInvoiceId] IS NOT NULL)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
SET ANSI_PADDING ON
GO
/****** Object:  Index [UX_PayLink_Reference]    Script Date: 30/10/2026 13:37:40 ******/
CREATE UNIQUE NONCLUSTERED INDEX [UX_PayLink_Reference] ON [dbo].[tblPOS_PaymentLink]
(
	[CustomerReference] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [UX_tblPOS_TableSession_Open]    Script Date: 30/10/2026 13:37:40 ******/
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblPOS_TableSession_Open] ON [dbo].[tblPOS_TableSession]
(
	[TableID] ASC
)
WHERE ([ClosedOn] IS NULL)
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
/****** Object:  Index [IX_tblPOS_UserBranch_Map_UserID]    Script Date: 30/10/2026 13:37:40 ******/
CREATE NONCLUSTERED INDEX [IX_tblPOS_UserBranch_Map_UserID] ON [dbo].[tblPOS_UserBranch_Map]
(
	[UserID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO
ALTER TABLE [dbo].[tbl_Menu_Colors] ADD  CONSTRAINT [DF_tbl_Menu_Colors_BranchId]  DEFAULT ((0)) FOR [BranchId]
GO
ALTER TABLE [dbo].[tblArea] ADD  CONSTRAINT [DF_tblArea_DeliveryCharges]  DEFAULT ((0.000)) FOR [DeliveryCharges]
GO
ALTER TABLE [dbo].[tblArea] ADD  CONSTRAINT [DF_tblArea_Points]  DEFAULT ((0)) FOR [Points]
GO
ALTER TABLE [dbo].[tblArea] ADD  CONSTRAINT [DF_tblArea_BranchID]  DEFAULT ((1)) FOR [BranchID]
GO
ALTER TABLE [dbo].[tblAreaMapData] ADD  DEFAULT ('') FOR [PolygonVal]
GO
ALTER TABLE [dbo].[tblBrand] ADD  CONSTRAINT [DF_tblBrand_Russian]  DEFAULT ((0)) FOR [Russian]
GO
ALTER TABLE [dbo].[tblBrand] ADD  CONSTRAINT [DF_tblBrand_Mandarin]  DEFAULT ((0)) FOR [Mandarin]
GO
ALTER TABLE [dbo].[tblBrand] ADD  CONSTRAINT [DF_tblBrand_FeedBack]  DEFAULT ((0)) FOR [FeedBack]
GO
ALTER TABLE [dbo].[tblBrand] ADD  CONSTRAINT [DF_tblBrand_Telephone]  DEFAULT ('') FOR [Telephone]
GO
ALTER TABLE [dbo].[tblBrand] ADD  CONSTRAINT [DF_tblBrand_Facebook]  DEFAULT ('') FOR [Facebook]
GO
ALTER TABLE [dbo].[tblBrand] ADD  CONSTRAINT [DF_tblBrand_Instagram]  DEFAULT ('') FOR [Instagram]
GO
ALTER TABLE [dbo].[tblBrand] ADD  DEFAULT ((0)) FOR [ShowAllergen]
GO
ALTER TABLE [dbo].[tblCustomer] ADD  CONSTRAINT [DF_tblCustomer_IsBlocked]  DEFAULT ((0)) FOR [IsBlocked]
GO
ALTER TABLE [dbo].[tblCustomer] ADD  CONSTRAINT [DF_tblCustomer_IsDeleted]  DEFAULT ((0)) FOR [IsDeleted]
GO
ALTER TABLE [dbo].[tblCustomer] ADD  CONSTRAINT [DF_tblCustomer_CreatedOn]  DEFAULT (getdate()) FOR [CreatedOn]
GO
ALTER TABLE [dbo].[tblCustomerAddress] ADD  DEFAULT ((0)) FOR [IsDefault]
GO
ALTER TABLE [dbo].[tblCustomerAddress] ADD  DEFAULT ((0)) FOR [IsDeleted]
GO
ALTER TABLE [dbo].[tblCustomerAddress] ADD  DEFAULT (getdate()) FOR [CreatedOn]
GO
ALTER TABLE [dbo].[tblEndDayPayment] ADD  CONSTRAINT [DF_tblEndDayPayment_CashAmount]  DEFAULT ((0)) FOR [CashAmount]
GO
ALTER TABLE [dbo].[tblEndDayPayment] ADD  CONSTRAINT [DF_tblEndDayPayment_CancelAmount]  DEFAULT ((0)) FOR [CancelAmount]
GO
ALTER TABLE [dbo].[tblEndDayPayment] ADD  CONSTRAINT [DF_tblEndDayPayment_BillAmount]  DEFAULT ((0)) FOR [GrossSales]
GO
ALTER TABLE [dbo].[tblEndDayPayment] ADD  CONSTRAINT [DF_tblEndDayPayment_Discount]  DEFAULT ((0)) FOR [Discount]
GO
ALTER TABLE [dbo].[tblImageSlideShow] ADD  CONSTRAINT [DF_Table_1_Image Sequence]  DEFAULT ((0)) FOR [ImageSequence]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__BillA__52CE3E04]  DEFAULT ((0)) FOR [BillAmount]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__Disco__53C2623D]  DEFAULT ((0)) FOR [Discount]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__Statu__5792F321]  DEFAULT ((0)) FOR [Status]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__Invoi__5887175A]  DEFAULT (getdate()) FOR [InvoiceDate]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__Invoi__597B3B93]  DEFAULT (getdate()) FOR [InvoiceTime]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__Payme__5A6F5FCC]  DEFAULT ((4)) FOR [PaymentType]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__Print__5B638405]  DEFAULT ((0)) FOR [Printed]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__Order__5C57A83E]  DEFAULT ((0)) FOR [OrderStatus]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__Order__5D4BCC77]  DEFAULT ((0)) FOR [OrderStatusID]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__Dispa__5E3FF0B0]  DEFAULT ((0)) FOR [Dispatcher]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__Runni__5F3414E9]  DEFAULT ((0)) FOR [RunningOrder]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__Delet__60283922]  DEFAULT ((0)) FOR [Deleted]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF_tblInvoice_Closed]  DEFAULT ((0)) FOR [Closed]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF_tblInvoice_InvoiceType]  DEFAULT ((0)) FOR [InvoiceType]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__CashA__54B68676]  DEFAULT ((0)) FOR [CashAmount]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF__tblInvoic__K_NET__569ECEE8]  DEFAULT ((0)) FOR [K_NETAmount]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF_tblInvoice_CashTalabat]  DEFAULT ((0)) FOR [CashTalabat]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF_tblInvoice_KnetTalabat]  DEFAULT ((0)) FOR [KnetTalabat]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF_tblInvoice_OrderType]  DEFAULT ((2)) FOR [OrderType]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF_tblInvoice_SourceID]  DEFAULT ((1)) FOR [SourceID]
GO
ALTER TABLE [dbo].[tblInvoice] ADD  CONSTRAINT [DF_tblInvoice_PrintCount]  DEFAULT ((0)) FOR [PrintCount]
GO
ALTER TABLE [dbo].[tblInvoicePayment] ADD  CONSTRAINT [DF_tblInvoicePayment_IsRefund]  DEFAULT ((0)) FOR [IsRefund]
GO
ALTER TABLE [dbo].[tblInvoicePayment] ADD  CONSTRAINT [DF_tblInvoicePayment_ReceivedOn]  DEFAULT (getdate()) FOR [ReceivedOn]
GO
ALTER TABLE [dbo].[tblInvoicePaymentType] ADD  CONSTRAINT [DF_tblIPT_IsCash]  DEFAULT ((0)) FOR [IsCash]
GO
ALTER TABLE [dbo].[tblInvoicePaymentType] ADD  CONSTRAINT [DF_tblIPT_IsOnline]  DEFAULT ((0)) FOR [IsOnline]
GO
ALTER TABLE [dbo].[tblInvoicePaymentType] ADD  CONSTRAINT [DF_tblIPT_ReqRef]  DEFAULT ((0)) FOR [RequiresReference]
GO
ALTER TABLE [dbo].[tblInvoicePaymentType] ADD  CONSTRAINT [DF_tblIPT_IsCOD]  DEFAULT ((0)) FOR [IsCOD]
GO
ALTER TABLE [dbo].[tblOrder] ADD  CONSTRAINT [DF__tblOrder__SentT__4C214075]  DEFAULT ((0)) FOR [SentToPrinter]
GO
ALTER TABLE [dbo].[tblOrder] ADD  CONSTRAINT [DF__tblOrder__Prepa__4D1564AE]  DEFAULT ((0)) FOR [Prepared]
GO
ALTER TABLE [dbo].[tblOrder] ADD  CONSTRAINT [DF__tblOrder__Combi__4E0988E7]  DEFAULT ((0)) FOR [Combined]
GO
ALTER TABLE [dbo].[tblOrder] ADD  CONSTRAINT [DF__tblOrder__Deliv__4EFDAD20]  DEFAULT ((0)) FOR [Delivered]
GO
ALTER TABLE [dbo].[tblOrder] ADD  CONSTRAINT [DF__tblOrder__Dispa__4FF1D159]  DEFAULT ((0)) FOR [Dispatcher]
GO
ALTER TABLE [dbo].[tblOrder] ADD  CONSTRAINT [DF__tblOrder__Delet__50E5F592]  DEFAULT ((0)) FOR [Deleted]
GO
ALTER TABLE [dbo].[tblOrder] ADD  CONSTRAINT [DF_tblOrder_OrderDate]  DEFAULT (getdate()) FOR [OrderDate]
GO
ALTER TABLE [dbo].[tblOrder] ADD  CONSTRAINT [DF_tblOrder_TableType]  DEFAULT ((0)) FOR [TableType]
GO
ALTER TABLE [dbo].[tblOrder] ADD  CONSTRAINT [DF_tblOrder_Waste]  DEFAULT ((0)) FOR [Waste]
GO
ALTER TABLE [dbo].[tblOrder] ADD  CONSTRAINT [DF_tblOrder_LineType]  DEFAULT ((1)) FOR [LineType]
GO
ALTER TABLE [dbo].[tblOrder] ADD  CONSTRAINT [DF_tblOrder_IsSplit]  DEFAULT ((0)) FOR [IsSplit]
GO
ALTER TABLE [dbo].[tblOrderStatus] ADD  CONSTRAINT [DF_tblOrderStatus_IsTerminal]  DEFAULT ((0)) FOR [IsTerminal]
GO
ALTER TABLE [dbo].[tblOrderStatus] ADD  CONSTRAINT [DF_tblOrderStatus_Pickup]  DEFAULT ((1)) FOR [AppliesToPickup]
GO
ALTER TABLE [dbo].[tblOrderStatus] ADD  CONSTRAINT [DF_tblOrderStatus_Delivery]  DEFAULT ((1)) FOR [AppliesToDelivery]
GO
ALTER TABLE [dbo].[tblOrderStatus] ADD  CONSTRAINT [DF_tblOrderStatus_IsActive]  DEFAULT ((1)) FOR [IsActive]
GO
ALTER TABLE [dbo].[tblPOS_AuditLog] ADD  DEFAULT (getdate()) FOR [CreatedOn]
GO
ALTER TABLE [dbo].[tblPOS_BranchSetting] ADD  DEFAULT ((80)) FOR [ThermalWidthMM]
GO
ALTER TABLE [dbo].[tblPOS_BranchSetting] ADD  DEFAULT ((1)) FOR [AutoPrintOnNew]
GO
ALTER TABLE [dbo].[tblPOS_BranchSetting] ADD  DEFAULT ((20)) FOR [DefaultPrepMinutes]
GO
ALTER TABLE [dbo].[tblPOS_BranchSetting] ADD  DEFAULT ((1)) FOR [SoundOnNewOrder]
GO
ALTER TABLE [dbo].[tblPOS_CancelReason_Master] ADD  DEFAULT ((1)) FOR [IsActive]
GO
ALTER TABLE [dbo].[tblPOS_CancelReason_Master] ADD  CONSTRAINT [DF_tblPOSCancel_FeedsEndDay]  DEFAULT ((1)) FOR [FeedsEndDay]
GO
ALTER TABLE [dbo].[tblPOS_GeoCache] ADD  CONSTRAINT [DF_tblPOS_GeoCache_CreatedOn]  DEFAULT (getdate()) FOR [CreatedOn]
GO
ALTER TABLE [dbo].[tblPOS_GeoCache] ADD  CONSTRAINT [DF_tblPOS_GeoCache_HitCount]  DEFAULT ((0)) FOR [HitCount]
GO
ALTER TABLE [dbo].[tblPOS_OrderStatusHistory] ADD  DEFAULT (getdate()) FOR [ChangedOn]
GO
ALTER TABLE [dbo].[tblPOS_OrderTransfer] ADD  DEFAULT (getdate()) FOR [TransferredOn]
GO
ALTER TABLE [dbo].[tblPOS_PaymentLink] ADD  CONSTRAINT [DF_PayLink_Provider]  DEFAULT ('MyFatoorah') FOR [Provider]
GO
ALTER TABLE [dbo].[tblPOS_PaymentLink] ADD  CONSTRAINT [DF_PayLink_Status]  DEFAULT ('Pending') FOR [Status]
GO
ALTER TABLE [dbo].[tblPOS_PaymentLink] ADD  CONSTRAINT [DF_PayLink_CreatedOn]  DEFAULT (getdate()) FOR [CreatedOn]
GO
ALTER TABLE [dbo].[tblPOS_Printer] ADD  CONSTRAINT [DF_tblPOS_Printer_Port]  DEFAULT ((9100)) FOR [Port]
GO
ALTER TABLE [dbo].[tblPOS_Printer] ADD  CONSTRAINT [DF_tblPOS_Printer_Paper]  DEFAULT ((80)) FOR [PaperWidthMM]
GO
ALTER TABLE [dbo].[tblPOS_Printer] ADD  CONSTRAINT [DF_tblPOS_Printer_Inv]  DEFAULT ((0)) FOR [PrintInvoice]
GO
ALTER TABLE [dbo].[tblPOS_Printer] ADD  CONSTRAINT [DF_tblPOS_Printer_Ord]  DEFAULT ((0)) FOR [PrintOrder]
GO
ALTER TABLE [dbo].[tblPOS_Printer] ADD  CONSTRAINT [DF_tblPOS_Printer_All]  DEFAULT ((1)) FOR [AllCategories]
GO
ALTER TABLE [dbo].[tblPOS_Printer] ADD  CONSTRAINT [DF_tblPOS_Printer_Act]  DEFAULT ((1)) FOR [IsActive]
GO
ALTER TABLE [dbo].[tblPOS_Printer] ADD  CONSTRAINT [DF_tblPOS_Printer_Del]  DEFAULT ((0)) FOR [IsDeleted]
GO
ALTER TABLE [dbo].[tblPOS_Printer] ADD  CONSTRAINT [DF_tblPOS_Printer_Cr]  DEFAULT (getdate()) FOR [CreatedOn]
GO
ALTER TABLE [dbo].[tblPOS_Role_Master] ADD  DEFAULT ((1)) FOR [CanChangeStatus]
GO
ALTER TABLE [dbo].[tblPOS_Role_Master] ADD  DEFAULT ((0)) FOR [CanCancel]
GO
ALTER TABLE [dbo].[tblPOS_Role_Master] ADD  DEFAULT ((0)) FOR [CanRefund]
GO
ALTER TABLE [dbo].[tblPOS_Role_Master] ADD  DEFAULT ((0)) FOR [CanTransfer]
GO
ALTER TABLE [dbo].[tblPOS_Role_Master] ADD  DEFAULT ((1)) FOR [CanTakePayment]
GO
ALTER TABLE [dbo].[tblPOS_Role_Master] ADD  DEFAULT ((0)) FOR [CanViewReports]
GO
ALTER TABLE [dbo].[tblPOS_Role_Master] ADD  DEFAULT ((0)) FOR [CanEndDay]
GO
ALTER TABLE [dbo].[tblPOS_Role_Master] ADD  DEFAULT ((0)) FOR [CanManageMasters]
GO
ALTER TABLE [dbo].[tblPOS_TableArea] ADD  CONSTRAINT [DF_tblPOS_TableArea_Sort]  DEFAULT ((0)) FOR [SortOrder]
GO
ALTER TABLE [dbo].[tblPOS_TableArea] ADD  CONSTRAINT [DF_tblPOS_TableArea_Active]  DEFAULT ((1)) FOR [IsActive]
GO
ALTER TABLE [dbo].[tblPOS_TableSession] ADD  CONSTRAINT [DF_tblPOS_TableSession_Persons]  DEFAULT ((1)) FOR [Persons]
GO
ALTER TABLE [dbo].[tblPOS_TableSession] ADD  CONSTRAINT [DF_tblPOS_TableSession_Opened]  DEFAULT (getdate()) FOR [OpenedOn]
GO
ALTER TABLE [dbo].[tblPromotion] ADD  CONSTRAINT [DF_Table_2_Image Sequence]  DEFAULT ((0)) FOR [ImageSequence]
GO
ALTER TABLE [dbo].[tblSetting] ADD  CONSTRAINT [DF_tblSetting_ORdertaking]  DEFAULT ((0)) FOR [ORdertaking]
GO
ALTER TABLE [dbo].[tblTable] ADD  CONSTRAINT [DF_tblTable_Status]  DEFAULT ((0)) FOR [Status]
GO
ALTER TABLE [dbo].[tblTable] ADD  CONSTRAINT [DF_tblTable_Xaxis]  DEFAULT ((27.000)) FOR [Xaxis]
GO
ALTER TABLE [dbo].[tblTable] ADD  CONSTRAINT [DF_tblTable_Yaxis]  DEFAULT ((193.000)) FOR [Yaxis]
GO
ALTER TABLE [dbo].[tblTheme] ADD  CONSTRAINT [DF_tblTheme_FontColorPrice]  DEFAULT ('') FOR [FontColorPrice]
GO
ALTER TABLE [dbo].[tblUser] ADD  CONSTRAINT [DF_tblWaiter_BrandID]  DEFAULT ((0)) FOR [BrandID]
GO
ALTER TABLE [dbo].[tblWebImageSlideShow] ADD  CONSTRAINT [DF_tblWebImageSlideShow_WebImageSequence]  DEFAULT ((0)) FOR [WebImageSequence]
GO
ALTER TABLE [dbo].[tblInvoice]  WITH CHECK ADD  CONSTRAINT [FK_tblInvoice_InvoiceType] FOREIGN KEY([InvoiceType])
REFERENCES [dbo].[tblInvoiceType_Master] ([ID])
GO
ALTER TABLE [dbo].[tblInvoice] CHECK CONSTRAINT [FK_tblInvoice_InvoiceType]
GO
ALTER TABLE [dbo].[tblInvoice]  WITH CHECK ADD  CONSTRAINT [FK_tblInvoice_OrderStatus] FOREIGN KEY([OrderStatusID])
REFERENCES [dbo].[tblOrderStatus] ([OrderStatusID])
GO
ALTER TABLE [dbo].[tblInvoice] CHECK CONSTRAINT [FK_tblInvoice_OrderStatus]
GO
ALTER TABLE [dbo].[tblInvoice]  WITH CHECK ADD  CONSTRAINT [FK_tblInvoice_PaymentType] FOREIGN KEY([PaymentType])
REFERENCES [dbo].[tblInvoicePaymentType] ([ID])
GO
ALTER TABLE [dbo].[tblInvoice] CHECK CONSTRAINT [FK_tblInvoice_PaymentType]
GO
/****** Object:  StoredProcedure [dbo].[AddFeedBackLayout]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[AddFeedBackLayout]
@Question nvarchar (max)=''
,@TypeId int=0
,@Sequence int=0
,@BrandID int=0

AS
BEGIN

insert into [dbo].[Feedback_Layout] (Questions,TypeId,Sequence,BrandID) values (@Question,@TypeId,@Sequence,@BrandID)

END



GO
/****** Object:  StoredProcedure [dbo].[BrandPromotion_ShowHide]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
Create PROCEDURE [dbo].[BrandPromotion_ShowHide]
@brandId int=0,
@IsSelected bit=0
AS
BEGIN
	update tblBrand set ShowPromotion=@IsSelected where BrandID = @brandId  
END
GO
/****** Object:  StoredProcedure [dbo].[Category_UpdateSequence]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create PROCEDURE [dbo].[Category_UpdateSequence]

@CAT_NUM int,

@SEQ_NUM int

AS
BEGIN
 
update tblCategory set SEQ_NUM=@SEQ_NUM where CAT_NUM=@CAT_NUM

END



GO
/****** Object:  StoredProcedure [dbo].[geticatdetails]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create PROCEDURE [dbo].[geticatdetails]


AS
BEGIN

select * 
,(select top (1) imagename  from tblitems where CAT_NUM=c.CAT_NUM   order by Seq_Num )as Imagename

from tblcategory c where ShowInTablet=1;


END
GO
/****** Object:  StoredProcedure [dbo].[Getitem]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create PROCEDURE [dbo].[Getitem]

@CAT_NUM int=0
AS
BEGIN

select 
 ID,
 i.ShowinTablet,
 c.CAT_NUM,
 c.CAT_NAME,
 ITEM_NAME,
i.ITEM_NAME_ARABIC,
PRICE,
i.IMAGENAME,
i.SEQ_NUM
from tblItems i
inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
where i.ShowInTablet=1 and c.CAT_NUM = @CAT_NUM


END



GO
/****** Object:  StoredProcedure [dbo].[Getitemselect]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

create PROCEDURE [dbo].[Getitemselect]

@CAT_NUM int=0,
@itemid int=0

AS
BEGIN

select 
 ID,
 i.ShowinTablet,
 c.CAT_NUM,
 c.CAT_NAME,
 ITEM_NAME,
 INGREDIENT,
i.ITEM_NAME_ARABIC,
PRICE,
i.IMAGENAME,
i.SEQ_NUM
from tblItems i
inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
where i.ShowInTablet=1 and c.CAT_NUM = @CAT_NUM
and i.id = @itemid


END


GO
/****** Object:  StoredProcedure [dbo].[Image_Promotion]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
CREATE PROCEDURE [dbo].[Image_Promotion]
@brandId int=0
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	

	select id,ImageName,ImageSequence,BrandID from tblPromotion where BrandID = @brandId order by ImageSequence 
	select case when ShowPromotion is null or ShowPromotion=0 then 0 else 1 end as ShowPromotion from tblBrand where BrandID=@brandId
END
GO
/****** Object:  StoredProcedure [dbo].[Image_Slideshow]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
CREATE PROCEDURE [dbo].[Image_Slideshow]
@brandId int=0
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	

	select * from tblImageSlideShow where BrandID = @brandId order by ImageSequence 
END
GO
/****** Object:  StoredProcedure [dbo].[Items_UpdateSequence]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

create PROCEDURE [dbo].[Items_UpdateSequence]

@ID int,
@SEQ_NUM int

AS
BEGIN
 
update tblItems set Seq_Num=@SEQ_NUM where ID=@ID

END



GO
/****** Object:  StoredProcedure [dbo].[Mobile_GetFeedBackLayout]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[Mobile_GetFeedBackLayout]

@BrandID int
AS
BEGIN


select [dbo].[Feedback_Layout].*,[Feedback_Type].Type from [dbo].[Feedback_Layout]
inner join [dbo].[Feedback_Type] on [dbo].[Feedback_Type].id=[Feedback_Layout].TypeId
where BrandID=@BrandID

END



GO
/****** Object:  StoredProcedure [dbo].[mvc_sp_AddCategory]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[mvc_sp_AddCategory]
@CAT_NAME nvarchar(max),
@CAT_NAME_ARABIC nvarchar(max)='',

@CategoryName_chinese nvarchar(max)='',
@CategoryName_turkish nvarchar(max)='',
@CategoryName_hindi nvarchar(max)='',
@CategoryName_korean nvarchar(max)='',
@CategoryName_spain nvarchar(max)='',
@CategoryName_bangladeshi nvarchar(max)='',
@CategoryName_srilanka nvarchar(max)='',
@CategoryName_iranian nvarchar(max)='',
@CategoryName_italian nvarchar(max)='',
@CategoryName_urdu nvarchar(max)='',
@CategoryName_philippines nvarchar(max)='',
@CategoryName_french nvarchar(max)='',
@CategoryName_germany nvarchar(max)='',


@SEQ_NUM int=0,
@CatNameMan nvarchar(max)='',
@CatNameRus nvarchar(max)='',
@BrandID int=0,
@ShowInTablet bit,
@MainCategory int=0
AS
BEGIN

declare @count as int
declare @i as int = 1
declare @CAT_NUM int =0

	set @SEQ_NUM= (select isnull(max(SEQ_NUM),0)+1 from tblCategory)
	insert into tblcategory (MainCategory,CAT_NAME,CAT_NAME_ARABIC,SEQ_NUM,ShowInTablet,CatNameMan,CatNameRus,Brandid, IsActive) 
	values (@MainCategory,@CAT_NAME,@CAT_NAME_ARABIC,@SEQ_NUM,@ShowInTablet,@CatNameMan,@CatNameRus,@BrandID,1)
	
	set @CAT_NUM =(select @@IDENTITY)
	if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
	begin	
		insert into tblCategoryName_Languages (CAT_NUM,chinese,turkish,hindi,korean,spain,
		bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
		values(@CAT_NUM,@CategoryName_chinese,@CategoryName_turkish,@CategoryName_hindi,@CategoryName_korean,@CategoryName_spain,
		@CategoryName_bangladeshi,@CategoryName_srilanka,@CategoryName_iranian,@CategoryName_italian,@CategoryName_urdu,@CategoryName_philippines,@CategoryName_french,@CategoryName_germany)
	end

	select MAX(CAT_NUM) as Catnum from tblCategory


END

GO
/****** Object:  StoredProcedure [dbo].[mvc_sp_AddItem]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[mvc_sp_AddItem]
@BrandId int =0,
@CAT_NUM int=0,
@ITEM_NAME nvarchar(max),
@ITEM_NAME_ARABIC nvarchar(max)='',

@ITEMName_chinese nvarchar(max)='',
@ITEMName_turkish nvarchar(max)='',
@ITEMName_hindi nvarchar(max)='',
@ITEMName_korean nvarchar(max)='',
@ITEMName_spain nvarchar(max)='',
@ITEMName_bangladeshi nvarchar(max)='',
@ITEMName_srilanka nvarchar(max)='',
@ITEMName_iranian nvarchar(max)='',
@ITEMName_italian nvarchar(max)='',
@ITEMName_urdu nvarchar(max)='',
@ITEMName_philippines nvarchar(max)='',
@ITEMName_french nvarchar(max)='',
@ITEMName_germany nvarchar(max)='',

@ItemNameMan nvarchar(max)='',
@ItemNameRus nvarchar(max)='',
@PRICE decimal (18,3),
@INGREDIENT nvarchar(max)='',
@INGREDIENT_ARABIC nvarchar(max)='',

@Ingredient_chinese nvarchar(max)='',
@Ingredient_turkish nvarchar(max)='',
@Ingredient_hindi nvarchar(max)='',
@Ingredient_korean nvarchar(max)='',
@Ingredient_spain nvarchar(max)='',
@Ingredient_bangladeshi nvarchar(max)='',
@Ingredient_srilanka nvarchar(max)='',
@Ingredient_iranian nvarchar(max)='',
@Ingredient_italian nvarchar(max)='',
@Ingredient_urdu nvarchar(max)='',
@Ingredient_philippines nvarchar(max)='',
@Ingredient_french nvarchar(max)='',
@Ingredient_germany nvarchar(max)='',


@INGREDIENT_Rus nvarchar(max)='',
@INGREDIENT_Man nvarchar(max)='',
@IMAGENAME nvarchar(max)='no_image.png',
@ShowInTablet bit,
@Video nvarchar(max)='',
@ITEM_DESC_ENG nvarchar(max)='',
@Seq_num int,
@isExtra bit=0

AS
BEGIN
 --//Hardcoding The category Number to 1 
 declare @ID int =0
	set @Seq_num = (select isnull(max(Seq_Num)+1,0) as seq from tblItems where CAT_NUM=@CAT_NUM)
 insert into tblitems(CAT_NUM,ITEM_NAME,PRICE,ITEM_NAME_ARABIC,INGREDIENT,INGREDIENT_ARABIC,IMAGENAME,ITEM_DESC_ENG,Seq_Num,ItemNameMan,ItemNameRus,INGREDIENT_Man,INGREDIENT_Rus,ShowInTablet,Video,isExtra,IsActive, HID, OutOfStock)
  values (@CAT_NUM,@ITEM_NAME,@PRICE,@ITEM_NAME_ARABIC,@INGREDIENT,@INGREDIENT_ARABIC,@IMAGENAME,Case When @ITEM_DESC_ENG = '' then @INGREDIENT else @ITEM_DESC_ENG end,@Seq_Num,@ItemNameMan,@ItemNameRus,@INGREDIENT_Man,@INGREDIENT_Rus,@ShowInTablet,@Video,@isExtra,1,0,0)

   set @ID =(select @@IDENTITY)
	if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
	begin	
		insert into tblItemsName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
		bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
		values(@ID,@ITEMName_chinese,@ITEMName_turkish,@ITEMName_hindi,@ITEMName_korean,@ITEMName_spain,
		@ITEMName_bangladeshi,@ITEMName_srilanka,@ITEMName_iranian,@ITEMName_italian,@ITEMName_urdu,@ITEMName_philippines,@ITEMName_french,@ITEMName_germany)

		insert into tblIngredientName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
		bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
		values(@ID,@Ingredient_chinese,@Ingredient_turkish,@Ingredient_hindi,@Ingredient_korean,@Ingredient_spain,
		@Ingredient_bangladeshi,@Ingredient_srilanka,@Ingredient_iranian,@Ingredient_italian,@Ingredient_urdu,@Ingredient_philippines,@Ingredient_french,@Ingredient_germany)
	end
	select @ID as ItemId
END

GO
/****** Object:  StoredProcedure [dbo].[mvc_sp_AddWaiter]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[mvc_sp_AddWaiter]

@NAME nvarchar(max),
@USERNAME nvarchar(max),
@PASSWORD nvarchar(max),
@Role_ID int,
@BrandID nvarchar(max)=''

AS
BEGIN
 
 insert into tblUser(NAME,USERNAME,PASSWORD,BrandID,RoleID) values (@NAME,@USERNAME,@PASSWORD,@BrandID,@Role_ID)

END



GO
/****** Object:  StoredProcedure [dbo].[mvc_sp_GetItems]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[mvc_sp_GetItems]
@BrandID nvarchar (50)=null
,@CatNo int
AS
BEGIN

select ID,CAT_NUM,ITEM_NAME from tblItems
if (@BrandID is not null)
begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			select distinct tblBrand.BrandName, a.BrandID, i.ID,i.Video,i.ShowinTablet,c.CAT_NUM,ITEM_NAME,c.CAT_NAME_ARABIC,c.CatNameMan,c.CatNameRus,
			c.CAT_NAME,i.ITEM_NAME_ARABIC,i.ItemNameMan,i.ItemNameRus,i.INGREDIENT_Man,i.INGREDIENT_Rus,PRICE,INGREDIENT,INGREDIENT_ARABIC,
			i.IMAGENAME,ITEM_DESC_ENG,i.SEQ_NUM,i.ItemNameRus,i.ItemNameMan 
			,1 as IsOtherLanguages,isnull(i.isExtra,0) isExtra
			--,Item_lag.arabic as ITEM_Name_arabic
			,Item_lag.chinese as ITEMName_chinese
			,Item_lag.turkish as ITEMName_turkish
			,Item_lag.hindi as ITEMName_hindi
			,Item_lag.korean as ITEMName_korean
			,Item_lag.spain as ITEMName_spain
			,Item_lag.bangladeshi as ITEMName_bangladeshi
			,Item_lag.srilanka as ITEMName_srilanka
			,Item_lag.iranian as ITEMName_iranian
			,Item_lag.italian as ITEMName_italian
			,Item_lag.urdu as ITEMName_urdu
			,Item_lag.philippines as ITEMName_philippines
			,Item_lag.french as ITEMName_french
			,Item_lag.germany as ITEMName_germany
			
			--,Ingredient_lag.arabic as Ingredient_arabic
			,Ingredient_lag.chinese as Ingredient_chinese
			,Ingredient_lag.turkish as Ingredient_turkish
			,Ingredient_lag.hindi as Ingredient_hindi
			,Ingredient_lag.korean as Ingredient_korean
			,Ingredient_lag.spain as Ingredient_spain
			,Ingredient_lag.bangladeshi as Ingredient_bangladeshi
			,Ingredient_lag.srilanka as Ingredient_srilanka
			,Ingredient_lag.iranian as Ingredient_iranian
			,Ingredient_lag.italian as Ingredient_italian
			,Ingredient_lag.urdu as Ingredient_urdu
			,Ingredient_lag.philippines as Ingredient_philippines
			,Ingredient_lag.french as Ingredient_french
			,Ingredient_lag.germany as Ingredient_germany
			from tblItems i
			inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
			inner join Assign_Cat a on a.CatNum=c.CAT_NUM
			inner join tblBrand on tblBrand.BrandID=a.BrandID
			left join tblItemsName_Languages Item_lag on Item_lag.ItemId=i.ID
			left join tblIngredientName_Languages Ingredient_lag on Ingredient_lag.ItemId=i.ID
			where a.BrandID in(select cast(item as integer) from dbo.splitstring(@BrandID,',')) and c.CAT_NUM=@CatNo order by i.Seq_Num
		end
		begin
			select distinct tblBrand.BrandName, a.BrandID, i.ID,i.Video,i.ShowinTablet,c.CAT_NUM,ITEM_NAME,
			c.CAT_NAME_ARABIC,c.CatNameMan,c.CatNameRus,c.CAT_NAME,i.ITEM_NAME_ARABIC,i.ItemNameMan,i.ItemNameRus,
			i.INGREDIENT_Man,i.INGREDIENT_Rus,PRICE,INGREDIENT,INGREDIENT_ARABIC,i.IMAGENAME,ITEM_DESC_ENG,
			i.SEQ_NUM,i.ItemNameRus,i.ItemNameMan
			
			,0 as IsOtherLanguages,isnull(i.isExtra,0) isExtra
			
			from tblItems i
			inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
			inner join Assign_Cat a on a.CatNum=c.CAT_NUM
			inner join tblBrand on tblBrand.BrandID=a.BrandID
			left join tblItemsName_Languages Item_lag on Item_lag.ItemId=i.ID
			left join tblIngredientName_Languages Ingredient_lag on Ingredient_lag.ItemId=i.ID
			where a.BrandID in(select cast(item as integer) from dbo.splitstring(@BrandID,',')) and c.CAT_NUM=@CatNo order by i.Seq_Num
		
		end

end

else
begin
	select distinct tblBrand.BrandName,a.BrandID, i.ID,i.Video,i.ShowinTablet,c.CAT_NUM,ITEM_NAME,c.CAT_NAME,i.ITEM_NAME_ARABIC,i.ItemNameMan,i.ItemNameRus,i.INGREDIENT_Man,i.INGREDIENT_Rus,PRICE,INGREDIENT,INGREDIENT_ARABIC,i.IMAGENAME,ITEM_DESC_ENG,i.SEQ_NUM,i.ItemNameRus,i.ItemNameMan 
	,1 as IsOtherLanguages,isnull(i.isExtra,0) isExtra

	--,Item_lag.arabic as ITEM_Name_arabic
	,Item_lag.chinese as ITEMName_chinese
	,Item_lag.turkish as ITEMName_turkish
	,Item_lag.hindi as ITEMName_hindi
	,Item_lag.korean as ITEMName_korean
	,Item_lag.spain as ITEMName_spain
	,Item_lag.bangladeshi as ITEMName_bangladeshi
	,Item_lag.srilanka as ITEMName_srilanka
	,Item_lag.iranian as ITEMName_iranian
	,Item_lag.italian as ITEMName_italian
	,Item_lag.urdu as ITEMName_urdu
	,Item_lag.philippines as ITEMName_philippines
	,Item_lag.french as ITEMName_french
	,Item_lag.germany as ITEMName_germany
	
	--,Ingredient_lag.arabic as Ingredient_arabic
	,Ingredient_lag.chinese as Ingredient_chinese
	,Ingredient_lag.turkish as Ingredient_turkish
	,Ingredient_lag.hindi as Ingredient_hindi
	,Ingredient_lag.korean as Ingredient_korean
	,Ingredient_lag.spain as Ingredient_spain
	,Ingredient_lag.bangladeshi as Ingredient_bangladeshi
	,Ingredient_lag.srilanka as Ingredient_srilanka
	,Ingredient_lag.iranian as Ingredient_iranian
	,Ingredient_lag.italian as Ingredient_italian
	,Ingredient_lag.urdu as Ingredient_urdu
	,Ingredient_lag.philippines as Ingredient_philippines
	,Ingredient_lag.french as Ingredient_french
	,Ingredient_lag.germany as Ingredient_germany
	from tblItems i
	inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
	inner join Assign_Cat a on a.CatNum=c.CAT_NUM 
	inner join tblBrand on tblBrand.BrandID=a.BrandID
	left join tblItemsName_Languages Item_lag on Item_lag.ItemId=i.ID
	left join tblIngredientName_Languages Ingredient_lag on Ingredient_lag.ItemId=i.ID
	where c.CAT_NUM=@CatNo
	order by i.Seq_Num
end

END


GO
/****** Object:  StoredProcedure [dbo].[mvc_sp_GetItems_Mobile]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO






CREATE PROCEDURE [dbo].[mvc_sp_GetItems_Mobile]
@BrandID nvarchar (50)=null
AS
BEGIN




select ID,CAT_NUM,ITEM_NAME from tblItems where ShowInTablet=1
if (@BrandID is not null)
begin
select a.BrandID, ID,i.ShowinTablet,c.CAT_NUM,ITEM_NAME,c.CAT_NAME_ARABIC,c.CatNameMan,c.CatNameRus,c.CAT_NAME,i.ITEM_NAME_ARABIC,i.ItemNameMan,i.ItemNameRus,i.INGREDIENT_Man,i.INGREDIENT_Rus,PRICE,INGREDIENT,INGREDIENT_ARABIC,i.IMAGENAME,ITEM_DESC_ENG,i.SEQ_NUM,i.ItemNameRus,i.ItemNameMan, i.Video from tblItems i
inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
inner join Assign_Cat a on a.CatNum=c.CAT_NUM
where a.BrandID in(select cast(item as integer) from dbo.splitstring(@BrandID,',')) and i.ShowInTablet=1 order by  CAST(c.SEQ_NUM AS Numeric(10,0)),CAST(i.Seq_Num AS Numeric(10,0))
end

else
begin
select a.BrandID, ID,i.ShowinTablet,
c.CAT_NUM,
ITEM_NAME,
c.CAT_NAME,
i.ITEM_NAME_ARABIC,
i.ItemNameMan,
i.ItemNameRus,
i.INGREDIENT_Man,
i.INGREDIENT_Rus,
PRICE,
INGREDIENT,
INGREDIENT_ARABIC,
i.IMAGENAME,ITEM_DESC_ENG,i.SEQ_NUM,i.ItemNameRus,i.ItemNameMan,i.Video 
from tblItems i
inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
inner join Assign_Cat a on a.CatNum=c.CAT_NUM 
where i.ShowInTablet=1
order by CAST(c.SEQ_NUM AS Numeric(10,0)),CAST(i.Seq_Num AS Numeric(10,0))
end

END















GO
/****** Object:  StoredProcedure [dbo].[mvc_sp_GetRole]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[mvc_sp_GetRole]

AS
BEGIN

select * from tblRole

END



GO
/****** Object:  StoredProcedure [dbo].[mvc_sp_GetWaiter]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[mvc_sp_GetWaiter]

AS
BEGIN

SELECT dbo.tblUser.ID, dbo.tblUser.NAME, dbo.tblUser.USERNAME, dbo.tblUser.PASSWORD, dbo.tblUser.DeletePassword,Role_ID,RoleName, dbo.tblUser.BrandID

FROM   dbo.tblUser 
inner join tblrole on tblrole.role_id=tblUser.roleid

END



GO
/****** Object:  StoredProcedure [dbo].[mvc_sp_Login]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[mvc_sp_Login]
@Username nvarchar(max)='',
@Password nvarchar(max)
AS
BEGIN
	--SELECT UserName,Name,Role,TableType FROM tblWaiter INNER JOIN tblUserRole ON tblWaiter.ID=tblUserRole.ID WHERE Username=@Username and Password=@Password
	SELECT ID,UserName,Name,tblUser.BrandID,tblRole.Role_ID,tblRole.RoleName,isnull(b.FeedBack,0) as FeedBack,
	--isnull((select top 1 MultipleBranch from tblSetting),0) as MultipleBranch
	isnull(b.MultipleBranch,0) as MultipleBranch,
	isnull(b.IsCartVisible,0) as IsCartVisible
	FROM tblUser
	inner join tblRole on tblRole.Role_ID=tblUser.roleid
	left join tblBrand b on b.BrandID= tblUser.BrandID
	WHERE  Password=@Password and USERNAME=@Username
END

GO
/****** Object:  StoredProcedure [dbo].[mvc_sp_UpdateCategory]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[mvc_sp_UpdateCategory]
@CAT_NUM int,
@CAT_NAME nvarchar(max),
@CAT_NAME_ARABIC nvarchar(max),

@CategoryName_chinese nvarchar(max)='',
@CategoryName_turkish nvarchar(max)='',
@CategoryName_hindi nvarchar(max)='',
@CategoryName_korean nvarchar(max)='',
@CategoryName_spain nvarchar(max)='',
@CategoryName_bangladeshi nvarchar(max)='',
@CategoryName_srilanka nvarchar(max)='',
@CategoryName_iranian nvarchar(max)='',
@CategoryName_italian nvarchar(max)='',
@CategoryName_urdu nvarchar(max)='',
@CategoryName_philippines nvarchar(max)='',
@CategoryName_french nvarchar(max)='',
@CategoryName_germany nvarchar(max)='',

@CatNameMan nvarchar(max)='',
@CatNameRus nvarchar(max)='',
@ShowInTablet bit,
@SEQ_NUM int=0,
@MainCategory int=0,
@BrandID int =0

AS
BEGIN
 
update tblCategory set CAT_NAME=@CAT_NAME,CAT_NAME_ARABIC=@CAT_NAME_ARABIC,ShowInTablet=@ShowInTablet, 
CatNameMan=@CatNameMan,CatNameRus=@CatNameRus ,MainCategory=@MainCategory where CAT_NUM=@CAT_NUM

	if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
	begin
		if exists (select 1 from tblCategoryName_Languages where CAT_NUM=@CAT_NUM)
		begin
			update tblCategoryName_Languages set
			chinese=@CategoryName_chinese
			,turkish=@CategoryName_turkish
			,hindi=@CategoryName_hindi
			,korean=@CategoryName_korean
			,spain=@CategoryName_spain
			,bangladeshi=@CategoryName_bangladeshi
			,srilanka=@CategoryName_srilanka
			,iranian=@CategoryName_iranian
			,italian=@CategoryName_italian
			,urdu=@CategoryName_urdu
			,philippines=@CategoryName_philippines
			,french=@CategoryName_french
			,germany=@CategoryName_germany
			where CAT_NUM=@CAT_NUM
		end
		else
		begin
			insert into tblCategoryName_Languages (CAT_NUM,chinese,turkish,hindi,korean,spain,
			bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
			values(@CAT_NUM,@CategoryName_chinese,@CategoryName_turkish,@CategoryName_hindi,@CategoryName_korean,@CategoryName_spain,
			@CategoryName_bangladeshi,@CategoryName_srilanka,@CategoryName_iranian,@CategoryName_italian,@CategoryName_urdu,@CategoryName_philippines,@CategoryName_french,@CategoryName_germany)
		end
	end
END



GO
/****** Object:  StoredProcedure [dbo].[mvc_sp_UpdateItem]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




CREATE PROCEDURE [dbo].[mvc_sp_UpdateItem]
@BrandId int =0,
@ID int,
@CAT_NUM int=0,
@ITEM_NAME nvarchar(max),
@ITEM_NAME_ARABIC nvarchar(max)='',

@ITEMName_chinese nvarchar(max)='',
@ITEMName_turkish nvarchar(max)='',
@ITEMName_hindi nvarchar(max)='',
@ITEMName_korean nvarchar(max)='',
@ITEMName_spain nvarchar(max)='',
@ITEMName_bangladeshi nvarchar(max)='',
@ITEMName_srilanka nvarchar(max)='',
@ITEMName_iranian nvarchar(max)='',
@ITEMName_italian nvarchar(max)='',
@ITEMName_urdu nvarchar(max)='',
@ITEMName_philippines nvarchar(max)='',
@ITEMName_french nvarchar(max)='',
@ITEMName_germany nvarchar(max)='',

@ItemNameMan nvarchar(max)='',
@ItemNameRus nvarchar(max)='',
@PRICE decimal (18,3),
@INGREDIENT nvarchar(max)='',
@INGREDIENT_ARABIC nvarchar(max)='',

@Ingredient_chinese nvarchar(max)='',
@Ingredient_turkish nvarchar(max)='',
@Ingredient_hindi nvarchar(max)='',
@Ingredient_korean nvarchar(max)='',
@Ingredient_spain nvarchar(max)='',
@Ingredient_bangladeshi nvarchar(max)='',
@Ingredient_srilanka nvarchar(max)='',
@Ingredient_iranian nvarchar(max)='',
@Ingredient_italian nvarchar(max)='',
@Ingredient_urdu nvarchar(max)='',
@Ingredient_philippines nvarchar(max)='',
@Ingredient_french nvarchar(max)='',
@Ingredient_germany nvarchar(max)='',

@INGREDIENT_Rus nvarchar(max)='',
@INGREDIENT_Man nvarchar(max)='',
@IMAGENAME nvarchar(max)='no_image.png',
@ITEM_DESC_ENG nvarchar(max)='',
@Video nvarchar(max)='',
@ShowInTablet bit,
@Seq_num int,
@isExtra bit=0

--@EXTRAID int

AS
BEGIN
--If there is change in the category then we will make that item as last sequence... else we will just update the items
declare @Old_CatNum int;

set @Old_CatNum= (select CAT_NUM from tblItems where ID=@ID)

if (@Old_CatNum=@CAT_NUM)

begin
	update tblitems set CAT_NUM=@CAT_NUM,ITEM_NAME=@ITEM_NAME,ITEM_NAME_ARABIC=@ITEM_NAME_ARABIC, Video=@Video,
	PRICE= @PRICE,INGREDIENT=@INGREDIENT,INGREDIENT_ARABIC=@INGREDIENT_ARABIC,IMAGENAME=@IMAGENAME,ShowInTablet=@ShowInTablet,
	ITEM_DESC_ENG=@ITEM_DESC_ENG, INGREDIENT_Man=@INGREDIENT_Man,INGREDIENT_Rus=@INGREDIENT_Rus,ItemNameMan=@ItemNameMan,ItemNameRus=@ItemNameRus 
	,isExtra=@isExtra
	where ID=@ID

	if exists (select 1 from tblItemsName_Languages where ItemID=@ID)
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			update tblItemsName_Languages set
			chinese=@ITEMName_chinese
			,turkish=@ITEMName_turkish
			,hindi=@ITEMName_hindi
			,korean=@ITEMName_korean
			,spain=@ITEMName_spain
			,bangladeshi=@ITEMName_bangladeshi
			,srilanka=@ITEMName_srilanka
			,iranian=@ITEMName_iranian
			,italian=@ITEMName_italian
			,urdu=@ITEMName_urdu
			,philippines=@ITEMName_philippines
			,french=@ITEMName_french
			,germany=@ITEMName_germany
			where ItemID=@ID
		end
	end
	else
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			insert into tblItemsName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
			bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
			values(@ID,@ITEMName_chinese,@ITEMName_turkish,@ITEMName_hindi,@ITEMName_korean,@ITEMName_spain,
			@ITEMName_bangladeshi,@ITEMName_srilanka,@ITEMName_iranian,@ITEMName_italian,@ITEMName_urdu,@ITEMName_philippines,@ITEMName_french,@ITEMName_germany)
		end
	
	end

	--update ingredient
	if exists (select 1 from tblIngredientName_Languages where ItemID=@ID)
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			update tblIngredientName_Languages set
			chinese=@Ingredient_chinese
			,turkish=@Ingredient_turkish
			,hindi=@Ingredient_hindi
			,korean=@Ingredient_korean
			,spain=@Ingredient_spain
			,bangladeshi=@Ingredient_bangladeshi
			,srilanka=@Ingredient_srilanka
			,iranian=@Ingredient_iranian
			,italian=@Ingredient_italian
			,urdu=@Ingredient_urdu
			,philippines=@Ingredient_philippines
			,french=@Ingredient_french
			,germany=@Ingredient_germany
			where ItemID=@ID
		end
		
	end
	else
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			insert into tblIngredientName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
			bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
			values(@ID,@Ingredient_chinese,@Ingredient_turkish,@Ingredient_hindi,@Ingredient_korean,@Ingredient_spain,
			@Ingredient_bangladeshi,@Ingredient_srilanka,@Ingredient_iranian,@Ingredient_italian,@Ingredient_urdu,@Ingredient_philippines,@Ingredient_french,@Ingredient_germany)
		end
		
	end
end
else
begin

	set @Seq_num = (select isnull(max(Seq_Num)+1,0) from tblItems where CAT_NUM=@CAT_NUM)

	update tblitems set CAT_NUM=@CAT_NUM, Video=@Video,
	PRICE= @PRICE,INGREDIENT=@INGREDIENT,INGREDIENT_ARABIC=@INGREDIENT_ARABIC,IMAGENAME=@IMAGENAME,ShowInTablet=@ShowInTablet,
	ITEM_DESC_ENG=@ITEM_DESC_ENG,Seq_Num=@Seq_Num, INGREDIENT_Man=@INGREDIENT_Man,INGREDIENT_Rus=@INGREDIENT_Rus,ItemNameMan=@ItemNameMan,ItemNameRus=@ItemNameRus 
	where ID=@ID

	if exists (select 1 from tblItemsName_Languages where ItemID=@ID)
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			update tblItemsName_Languages set
			chinese=@ITEMName_chinese
			,turkish=@ITEMName_turkish
			,hindi=@ITEMName_hindi
			,korean=@ITEMName_korean
			,spain=@ITEMName_spain
			,bangladeshi=@ITEMName_bangladeshi
			,srilanka=@ITEMName_srilanka
			,iranian=@ITEMName_iranian
			,italian=@ITEMName_italian
			,urdu=@ITEMName_urdu
			,philippines=@ITEMName_philippines
			,french=@ITEMName_french
			,germany=@ITEMName_germany
			where ItemID=@ID
		end
		
	end
	else
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			insert into tblItemsName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
			bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
			values(@ID,@ITEMName_chinese,@ITEMName_turkish,@ITEMName_hindi,@ITEMName_korean,@ITEMName_spain,
			@ITEMName_bangladeshi,@ITEMName_srilanka,@ITEMName_iranian,@ITEMName_italian,@ITEMName_urdu,@ITEMName_philippines,@ITEMName_french,@ITEMName_germany)
		end
		
	end

	--update ingredient
	if exists (select 1 from tblIngredientName_Languages where ItemID=@ID)
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			update tblIngredientName_Languages set
			chinese=@Ingredient_chinese
			,turkish=@Ingredient_turkish
			,hindi=@Ingredient_hindi
			,korean=@Ingredient_korean
			,spain=@Ingredient_spain
			,bangladeshi=@Ingredient_bangladeshi
			,srilanka=@Ingredient_srilanka
			,iranian=@Ingredient_iranian
			,italian=@Ingredient_italian
			,urdu=@Ingredient_urdu
			,philippines=@Ingredient_philippines
			,french=@Ingredient_french
			,germany=@Ingredient_germany
			where ItemID=@ID
		end
		
	end
	else
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			insert into tblIngredientName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
			bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
			values(@ID,@Ingredient_chinese,@Ingredient_turkish,@Ingredient_hindi,@Ingredient_korean,@Ingredient_spain,
			@Ingredient_bangladeshi,@Ingredient_srilanka,@Ingredient_iranian,@Ingredient_italian,@Ingredient_urdu,@Ingredient_philippines,@Ingredient_french,@Ingredient_germany)
		end
		
	end
end
BEGIN
if(@ITEM_DESC_ENG = '')
	update tblItems set ITEM_DESC_ENG = @INGREDIENT where ID=@ID

end
END

GO
/****** Object:  StoredProcedure [dbo].[mvc_sp_UpdateWaiter]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[mvc_sp_UpdateWaiter]

@ID int,
@NAME nvarchar(max),
@USERNAME nvarchar(max),
@PASSWORD nvarchar(max)='',
@Role_ID int,
@BrandID nvarchar(max)=''

AS
BEGIN
 

 if(@PASSWORD='')
 begin
 
update tblUser set NAME=@NAME,USERNAME=@USERNAME,RoleID=@Role_ID,BrandID=@BrandID where ID=@ID

 end

 else
 begin
update tblUser set NAME=@NAME,USERNAME=@USERNAME,PASSWORD=@PASSWORD,RoleID=@Role_ID,BrandID=@BrandID where ID=@ID
end
END



GO
/****** Object:  StoredProcedure [dbo].[Promotion_Add]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

Create PROCEDURE [dbo].[Promotion_Add]

@ImageName nvarchar(500)=''
,@brandID int
AS
BEGIN

insert into tblPromotion (ImageSequence,ImageName,BrandID) 
values ((select isnull(max(ImageSequence),0)+1 from tblPromotion),@ImageName,@brandID)
END



GO
/****** Object:  StoredProcedure [dbo].[Promotion_UpdateSequence]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[Promotion_UpdateSequence]

@id int,

@SEQ_NUM int

AS
BEGIN
 
update tblPromotion set ImageSequence=@SEQ_NUM where id=@id

END



GO
/****** Object:  StoredProcedure [dbo].[SlideShow_UpdateSequence]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create PROCEDURE [dbo].[SlideShow_UpdateSequence]

@id int,

@SEQ_NUM int

AS
BEGIN
 
update tblImageSlideShow set ImageSequence=@SEQ_NUM where id=@id

END



GO
/****** Object:  StoredProcedure [dbo].[SlideShows_Add]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[SlideShows_Add]

@ImageName nvarchar(500)=''
,@brandID int


AS
BEGIN

insert into tblImageSlideShow (ImageSequence,SlideImageName,BrandID) values ((select isnull(max(ImageSequence),0)+1 from tblImageSlideShow),@ImageName,@brandID)
END



GO
/****** Object:  StoredProcedure [dbo].[sp_AddBranch]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_AddBranch]

@BrandID int=0,
@branchName nvarchar(500)='',
@BrandNameAr nvarchar(500)='',
@CopyBranchID int =0

AS
BEGIN
 
insert into tblbranch(branchName,branchNameAra,brandId) 
values(@branchName,@BrandNameAr,@BrandID)  

declare @newBrandId int= @@identity

	if @CopyBranchID > 0 
	begin
		--insert into Assign_Cat(CatNum,BrandID)
		--select CatNum,@newBrandId from Assign_Cat where Id=CopyBranchID

		insert into assign_item(itemid,BrandID,branchid)
		select itemid,brandid,@newBrandId from assign_item where branchid=@CopyBranchID
	end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_AddBrand]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_AddBrand]

@BrandName nvarchar(500)='',
@BrandNameAr nvarchar(500)='',
@BrandSeq int,
@Russian int,
@Mandarin int,
@ThemeID int,
@BrandLogo nvarchar(500)='',
@IsOtherLanguages int =0,
@CopyBrandID int =0,
@Brandurl nvarchar(2000)=''
AS
BEGIN
 
insert into tblBrand(BrandName,BrandNameAra,BrandSeq,Russian,Mandarin,Theme,BrandImage,IsOtherLanguages,url) 
values(@BrandName,@BrandNameAr,@BrandSeq,@Russian,@Mandarin,@ThemeID,@BrandLogo,@IsOtherLanguages,@Brandurl)  

--declare @newBrandId int= @@identity

	--if @CopyBrandID > 0 
	--begin
	--	insert into Assign_Cat(CatNum,BrandID)
	--	select CatNum,@newBrandId from Assign_Cat where BrandID=@CopyBrandID

	--	insert into assign_item(itemid,BrandID)
	--	select itemid,@newBrandId from assign_item where BrandID=@CopyBrandID
	--end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_AddEditReservationSlot]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_AddEditReservationSlot]
@id int=0,
@slotName nvarchar(200)=null,
@slotNameArabic nvarchar(200)=null,
@fromTime time=null,
@toTime time=null
AS
BEGIN
	if @id > 0
	begin
		update tblReservationSlot set slotName=@slotName,slotNameArabic=@slotNameArabic,fromTime=@fromTime,toTime=@toTime where Id=@id
	end
	else
	begin
		insert into tblReservationSlot(slotName,slotNameArabic,fromTime,toTime)
		values(@slotName,@slotNameArabic,@fromTime,@toTime)
	end
END


GO
/****** Object:  StoredProcedure [dbo].[sp_AddEditReservationTableStructure]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_AddEditReservationTableStructure]
@TableStructureID int=0,
@TableName nvarchar(200)=null,
@DiningArea nvarchar(200)=null,
@Seating int=0
AS
BEGIN
	if @TableStructureID > 0
	begin
		update tblReservationTableStructure set TableName=@TableName,DiningArea=@DiningArea,Seating=@Seating where Id=@TableStructureID
	end
	else
	begin
		insert into tblReservationTableStructure(TableName,DiningArea,Seating)
		values(@TableName,@DiningArea,@Seating)
	end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_AddGroupModifier]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_AddGroupModifier]
@GroupNameEng nvarchar(1000)='',
@GroupNameArb nvarchar(1000)='',
@Type int=0,
@MinSelect int=0,
@MaxSelect int=0,
@Brandid int=0
AS
BEGIN
	Declare @Seq_Num int=0;
	set @Seq_Num =isnull((select max(Seq_Num) from tblGroup_Modifier_Master
	--where Type=@Type
	),0)+1

	if not exists(select 1 from tblGroup_Modifier_Master where GroupNameEng=@GroupNameEng and brandid=@Brandid)
	begin
		insert into tblGroup_Modifier_Master(GroupNameEng,GroupNameArb,Type,MinSelect,MaxSelect,Seq_Num,brandid)
		values(@GroupNameEng,@GroupNameArb,@Type,@MinSelect,@MaxSelect,@Seq_Num,@Brandid)

		select 'Success' Status
	end
	else
	begin
		select 'Already Exists' Status
	end
	
END

GO
/****** Object:  StoredProcedure [dbo].[sp_AddItem]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_AddItem]
@BrandId int =0,
@CAT_NUM int=0,
@ITEM_NAME nvarchar(max),
@ITEM_NAME_ARABIC nvarchar(max)='',

@ITEMName_chinese nvarchar(max)='',
@ITEMName_turkish nvarchar(max)='',
@ITEMName_hindi nvarchar(max)='',
@ITEMName_korean nvarchar(max)='',
@ITEMName_spain nvarchar(max)='',
@ITEMName_bangladeshi nvarchar(max)='',
@ITEMName_srilanka nvarchar(max)='',
@ITEMName_iranian nvarchar(max)='',
@ITEMName_italian nvarchar(max)='',
@ITEMName_urdu nvarchar(max)='',
@ITEMName_philippines nvarchar(max)='',
@ITEMName_french nvarchar(max)='',
@ITEMName_germany nvarchar(max)='',

@ItemNameMan nvarchar(max)='',
@ItemNameRus nvarchar(max)='',
@PRICE decimal (18,3),
@INGREDIENT nvarchar(max)='',
@INGREDIENT_ARABIC nvarchar(max)='',

@Ingredient_chinese nvarchar(max)='',
@Ingredient_turkish nvarchar(max)='',
@Ingredient_hindi nvarchar(max)='',
@Ingredient_korean nvarchar(max)='',
@Ingredient_spain nvarchar(max)='',
@Ingredient_bangladeshi nvarchar(max)='',
@Ingredient_srilanka nvarchar(max)='',
@Ingredient_iranian nvarchar(max)='',
@Ingredient_italian nvarchar(max)='',
@Ingredient_urdu nvarchar(max)='',
@Ingredient_philippines nvarchar(max)='',
@Ingredient_french nvarchar(max)='',
@Ingredient_germany nvarchar(max)='',


@INGREDIENT_Rus nvarchar(max)='',
@INGREDIENT_Man nvarchar(max)='',
@IMAGENAME nvarchar(max)='no_image.png',
@ShowInTablet bit,
@Video nvarchar(max)='',
@ITEM_DESC_ENG nvarchar(max)='',
@Seq_num int,
@isExtra bit=0,
@ischoice bit=0

AS
BEGIN
 --//Hardcoding The category Number to 1 
 declare @ID int =0
	if @isExtra =1
	begin
		set @Seq_num = isnull((select max(Seq_Num) as seq from tblItems where CAT_NUM=@CAT_NUM and isExtra=1),0)+1
	end
	else if @ischoice =1
	begin
		set @Seq_num = isnull((select max(Seq_Num) as seq from tblItems where CAT_NUM=@CAT_NUM and ischoice=1),0)+1
	end
	else
	begin
		set @Seq_num = isnull((select max(Seq_Num) as seq from tblItems where CAT_NUM=@CAT_NUM and isExtra=0 and ischoice=0),0)+1
	end

	insert into tblitems(CAT_NUM,ITEM_NAME,PRICE,ITEM_NAME_ARABIC,INGREDIENT,INGREDIENT_ARABIC,IMAGENAME,ITEM_DESC_ENG,Seq_Num,ItemNameMan,ItemNameRus,INGREDIENT_Man,INGREDIENT_Rus,ShowInTablet,Video,isExtra,IsActive,ischoice,OutOfStock, HID)
	values (@CAT_NUM,@ITEM_NAME,@PRICE,@ITEM_NAME_ARABIC,@INGREDIENT,@INGREDIENT_ARABIC,@IMAGENAME,Case When @ITEM_DESC_ENG = '' then @INGREDIENT else @ITEM_DESC_ENG end,@Seq_Num,@ItemNameMan,@ItemNameRus,@INGREDIENT_Man,@INGREDIENT_Rus,@ShowInTablet,@Video,@isExtra,1,@ischoice,0,0)

    set @ID =(select @@IDENTITY)

	update tblitems set IMAGENAME=case when @IMAGENAME!='no_image.png' then @IMAGENAME else @IMAGENAME end where id=@ID
	
	if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
	begin	
		insert into tblItemsName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
		bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
		values(@ID,@ITEMName_chinese,@ITEMName_turkish,@ITEMName_hindi,@ITEMName_korean,@ITEMName_spain,
		@ITEMName_bangladeshi,@ITEMName_srilanka,@ITEMName_iranian,@ITEMName_italian,@ITEMName_urdu,@ITEMName_philippines,@ITEMName_french,@ITEMName_germany)

		insert into tblIngredientName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
		bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
		values(@ID,@Ingredient_chinese,@Ingredient_turkish,@Ingredient_hindi,@Ingredient_korean,@Ingredient_spain,
		@Ingredient_bangladeshi,@Ingredient_srilanka,@Ingredient_iranian,@Ingredient_italian,@Ingredient_urdu,@Ingredient_philippines,@Ingredient_french,@Ingredient_germany)
	end
	select @ID as ItemId
END

GO
/****** Object:  StoredProcedure [dbo].[sp_AddItemImage]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
/****** Object:  StoredProcedure [dbo].[sp_AddUpdateBranch]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_AddUpdateBranch]
@BranchId int,
@branchName nvarchar(1000),
@BranchNameAra nvarchar(1000)=null,
@IsActive bit
AS
BEGIN
	If (@BranchId = 0)
	Begin
		insert into tblbranch(branchName,branchNameAra,brandId,IsActive,IsDeleted,createdon,SectionId,SEQ_NUM) 
		values (@branchName, @BranchNameAra,(select top 1 BrandID from tblBrand),@IsActive,0,GETDATE(),1,(select max(SEQ_NUM)+1 from tblbranch))
	End
	Else
	Begin
		Update tblbranch Set branchName = @branchName, branchNameAra = @branchNameAra , IsActive= @IsActive where id = @BranchId
	End
END


GO
/****** Object:  StoredProcedure [dbo].[sp_AddUpdateComments]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_AddUpdateComments]

@id int,
@comments_eng nvarchar(max),
@comments_arb nvarchar(max),
@Brandid int =0
AS
BEGIN
	If (@id = 0)
	Begin
		insert into tblcomments(comments_eng,comments_arb,brandid) values (@comments_eng, @comments_arb,@Brandid)
	End
	Else
	Begin
		Update tblcomments Set comments_eng = @comments_eng, comments_arb = @comments_arb,Brandid=@Brandid Where id = @id
	End
END
GO
/****** Object:  StoredProcedure [dbo].[sp_ArrangeTable]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_ArrangeTable]
@TableStructureID int=0,
@Xaxis decimal(18,10)=0,
@Yaxis decimal(18,10)=0
AS
BEGIN
	update tblReservationTableStructure set Xaxis=@Xaxis ,Yaxis=@Yaxis where Id=@TableStructureID
END

GO
/****** Object:  StoredProcedure [dbo].[sp_Assign_Item_Choices]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_Assign_Item_Choices]
@ChoiceId int,
@Itemid int,
@Count int
AS
BEGIN

if(@Count=0)
begin
	delete from tblItem_Choices where ItemId=@Itemid
end
 insert into tblItem_Choices(ChoiceId,ItemId) values (@ChoiceId,@Itemid)
 insert into Assign_Item (ItemId, BrandID, BranchId) values (@ChoiceId,1,1)
END


GO
/****** Object:  StoredProcedure [dbo].[sp_Assign_Item_Comments]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_Assign_Item_Comments]
@Commentid int,
@Itemid int,
@Count int
AS
BEGIN

if(@Count=0)
begin
	delete from tblItemComments where ItemId=@Itemid
end
 insert into tblItemComments(commentid,ItemId) values (@Commentid,@Itemid)
END


GO
/****** Object:  StoredProcedure [dbo].[sp_Assign_Item_Extras]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_Assign_Item_Extras]
@ExtraItemId int,
@Itemid int,
@Count int
AS
BEGIN

if(@Count=0)
begin
	delete from tblItem_Extras where ItemId=@Itemid
end
 insert into tblItem_Extras(ExtraItemId,ItemId) values (@ExtraItemId,@Itemid)
 insert into Assign_Item (ItemId, BrandID, BranchId) values (@ExtraItemId, 1,1)
END


GO
/****** Object:  StoredProcedure [dbo].[sp_AssignAllergenToItem]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_AssignAllergenToItem]
 @AllergenId int,
 @ItemId int,
 @Isselected bit
AS
BEGIN
 if @Isselected = 1
 begin
  if not exists (select 1 from tbl_Allergen_Assign where ItemId=@ItemId and allergenid=@AllergenId)
  begin
   insert into tbl_Allergen_Assign(ItemId,allergenid)
   values(@ItemId,@AllergenId)
  end
 end
 else
 begin
  delete tbl_Allergen_Assign where ItemId=@ItemId and allergenid=@AllergenId
 end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_AssignBrand]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_AssignBrand]

@BrandID int,
@BranchId int,
@Cat_Num int,
@Count int
AS
BEGIN

if(@Count=0)
begin
delete from Assign_Cat where CatNum=@Cat_Num
end

 insert into Assign_Cat(BrandID,CatNum,BranchId) values (@BrandID,@Cat_Num,@BranchId)

END

GO
/****** Object:  StoredProcedure [dbo].[sp_AssignBrandItems]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_AssignBrandItems]

@BrandID int,
@BranchId int,
@Itemid int,
@Count int
AS
BEGIN

if(@Count=0)
begin
	delete from Assign_Item where ItemId=@Itemid
end

 insert into Assign_Item(BrandID,ItemId,BranchId) values (@BrandID,@Itemid,@BranchId)
END

GO
/****** Object:  StoredProcedure [dbo].[sp_AssignChoiceToItem]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_AssignChoiceToItem]
@ChoiceId int,
@ItemId int,
@Isselected bit
AS
BEGIN
	if @Isselected = 1
	begin
		insert into tblItem_choices(ItemId,ChoiceId)
		values(@ItemId,@ChoiceId)
	end
	else
	begin
		delete tblItem_choices where ItemId=@ItemId and ChoiceId=@ChoiceId 
	end
END


GO
/****** Object:  StoredProcedure [dbo].[sp_AssignCommentToItem]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_AssignCommentToItem]
@Commentid int,
@ItemId int,
@Isselected bit
AS
BEGIN
	if @Isselected = 1
	begin
		insert into tblItemComments(ItemId,commentid)
		values(@ItemId,@Commentid)
	end
	else
	begin
		delete tblItemComments where ItemId=@ItemId and commentid=@Commentid 
	end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_AssignExtraItemToItem]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_AssignExtraItemToItem]
@ExtraItemId int,
@ItemId int,
@Isselected bit
AS
BEGIN
	if @Isselected = 1
	begin
		insert into tblItem_Extras(ItemId,ExtraItemId)
		values(@ItemId,@ExtraItemId)
	end
	else
	begin
		delete tblItem_Extras where ItemId=@ItemId and ExtraItemId=@ExtraItemId 
	end
END


GO
/****** Object:  StoredProcedure [dbo].[sp_AssignGroupModifier]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_AssignGroupModifier]
@dttblGroup_Modifier_Details [DT_tblGroup_Modifier_Details] readonly ,
@MainItemId int=0
AS
BEGIN

	if (select count(1) from @dttblGroup_Modifier_Details) > 0
	begin
		update tblGroup_Modifier_Details set deleted=1 
		from tblGroup_Modifier_Details mt
		inner join @dttblGroup_Modifier_Details tmp on tmp.MainItemId=mt.MainItemId and tmp.GroupId=mt.GroupId
		where mt.Deleted!=1

		insert into tblGroup_Modifier_Details(MainItemId,GroupId,Deleted,ItemID,Seq_Num)
		select MainItemId,GroupId,0,ItemID,Seq_Num from @dttblGroup_Modifier_Details
	end
	else
	begin
		update tblGroup_Modifier_Details set deleted=1 
		from tblGroup_Modifier_Details mt
		--inner join @dttblGroup_Modifier_Details tmp on tmp.MainItemId=mt.MainItemId and tmp.GroupId=mt.GroupId
		where mt.Deleted!=1 and mt.MainItemId=@MainItemId
	end
	

	select 'Success' as Status
END
GO
/****** Object:  StoredProcedure [dbo].[sp_AssignItemToBranch]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_AssignItemToBranch]
@brandId int,
@branchId int,
@ItemId int,
@Isselected bit
AS
BEGIN
	if @Isselected = 1
	begin
		insert into Assign_Item(BrandID,BranchId,ItemId)
		values(@brandId,@branchId,@ItemId)
	end
	else
	begin
		delete Assign_Item where BrandID=@brandId and BranchId=@branchId and ItemId=@ItemId
	end
END


GO
/****** Object:  StoredProcedure [dbo].[sp_AuditTrail]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_AuditTrail]
@ErrorMessaage	nvarchar(MAX),
@StackTrace	nvarchar(MAX),
@InnerException	nvarchar(MAX),
@ControllerName	nvarchar(500),
@MethodName	nvarchar(500),
@Userid	int =null
	
AS
BEGIN
	INSERT INTO AuditTrail (ErrorMessaage,StackTrace,InnerException,ControllerName,MethodName,Userid,CreatedOn)
	values(@ErrorMessaage,@StackTrace,@InnerException,@ControllerName,@MethodName,@Userid,GETDATE())
END
GO
/****** Object:  StoredProcedure [dbo].[sp_Authentication]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create PROCEDURE [dbo].[sp_Authentication]


@Password nvarchar(max)

AS
BEGIN


--SELECT UserName,Name,Role,TableType FROM tblWaiter INNER JOIN tblUserRole ON tblWaiter.ID=tblUserRole.ID WHERE Username=@Username and Password=@Password

select * from tblSetting where Password=@Password




END



GO
/****** Object:  StoredProcedure [dbo].[sp_BrandData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_BrandData]
@Password nvarchar (max)
as

if exists(select 1 from tblSetting where PASSWORD=@Password )
begin
	select dbo.tblbranch.id AS BrandID,
	dbo.tblbranch.branchName AS BrandName,
	dbo.tblbranch.id as BrandSeq,
	--b.BrandSeq,
	dbo.tblbranch.branchNameAra AS BrandNameAra,
	b.BrandImage,
	b.Theme,
	b.Russian,
	b.Mandarin,
	b.FeedBack,
	b.Currency,
	b.Telephone,
	b.Facebook,
	b.Instagram,
	isnull(b.ShowPromotion,'false') as ShowPromotion,
	case when b.ShowPromotion is null then '' else p.ImageName end as PromotionImageName,
	case when b.ShowPromotion is null then 0 else p.ImageSequence end as PromotionImageSequence
	FROM            dbo.tblBrand b RIGHT OUTER JOIN
                         dbo.tblbranch ON b.BrandID = dbo.tblbranch.brandId
						 left join tblPromotion p on  b.BrandID=p.BrandId
end
else
begin
	return 0
end






GO
/****** Object:  StoredProcedure [dbo].[sp_changePassword]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
CREATE PROCEDURE [dbo].[sp_changePassword]
	-- Add the parameters for the stored procedure here
	@UserId Int = 0,
	@OldPassword Varchar(50) = '',
	@NewPassword Varchar(50) = ''
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	
	If Not Exists (Select 1 From tblUser Where PASSWORD = @OldPassword And ID = @UserId)
	Begin
		Select 'Wrong Password' As Msg
	End
	Else
	Begin
		Update tblUser Set PASSWORD = @NewPassword Where ID = @UserId
	End
END
GO
/****** Object:  StoredProcedure [dbo].[sp_DashboardFilter]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_DashboardFilter]
      @CountryId INT = NULL          -- accepted and ignored; one country here
AS
BEGIN
    SET NOCOUNT ON;

    SELECT   val = b.id, txt = ISNULL(b.branchName, N'-')
    FROM     dbo.tblbranch b WITH (NOLOCK)
    WHERE    ISNULL(b.IsDeleted, 0) = 0
    ORDER BY ISNULL(b.SEQ_NUM, 9999), b.branchName;

    SELECT   val = it.ID, txt = ISNULL(it.Name, N'-')
    FROM     dbo.tblInvoiceType_Master it WITH (NOLOCK)
    ORDER BY it.ID;

    SELECT   val = pt.ID, txt = ISNULL(pt.PaymentTypeName, N'-')
    FROM     dbo.tblInvoicePaymentType pt WITH (NOLOCK)
    WHERE    ISNULL(pt.IsDeleted, 0) = 0
    ORDER BY ISNULL(pt.Seqnum, 9999), pt.ID;

    SELECT   val = br.BrandID, txt = ISNULL(br.BrandName, N'-')
    FROM     dbo.tblBrand br WITH (NOLOCK)
    ORDER BY ISNULL(br.BrandSeq, 9999), br.BrandName;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_Dashbord_DeletedItems]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_Dashbord_DeletedItems]
      @FromDate  DATETIME       = NULL
    , @ToDate    DATETIME       = NULL
    , @BranchIds NVARCHAR(1000) = NULL
    , @Waste     BIT            = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();

    SELECT   [Branch]     = ISNULL(b.branchName, N'-')
           , [Invoice No]  = i.InvoiceNo
           , [Item]        = ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
           , [Qty]         = o.Quantity
           , [Amount]      = CAST(ISNULL(o.TotalAmount, 0) AS DECIMAL(18,3))
           , [Deleted On]  = FORMAT(o.DeletedDate, 'dd-MMM-yy hh:mm tt')
           , [Comment]     = o.DeleteOrderComment
           , [Approved By] = u.NAME
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     dbo.tblInvoice i WITH (NOLOCK) ON i.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblbranch b  WITH (NOLOCK) ON b.id = i.BranchID
    LEFT JOIN dbo.tblItems  it WITH (NOLOCK) ON it.ID = o.ItemID
    LEFT JOIN dbo.tblUser   u  WITH (NOLOCK) ON CAST(u.ID AS NVARCHAR(50)) = o.DeletePasswordUserID
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    ISNULL(o.Deleted, 0) = 1 AND ISNULL(o.IsSplit, 0) = 0
      AND    ISNULL(o.Waste, 0)   = @Waste
      AND    i.InvoiceDate >= CAST(@FromDate AS DATE)
      AND    i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
      AND    (NULLIF(@BranchIds, '') IS NULL
              OR i.BranchID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')))
    ORDER BY o.DeletedDate DESC;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_DashbordDeletedReUseWiseItemsData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_DashbordDeletedReUseWiseItemsData]
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_Dashbord_DeletedItems @FromDate = @FromDate, @ToDate = @ToDate,
                                      @BranchIds = @BranchIds, @Waste = 0;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_DashbordDeletedWasteWiseItemsData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_DashbordDeletedWasteWiseItemsData]
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_Dashbord_DeletedItems @FromDate = @FromDate, @ToDate = @ToDate,
                                      @BranchIds = @BranchIds, @Waste = 1;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_DashbordDiscountWiseItemsData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_DashbordDiscountWiseItemsData]
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();

    /*---- what is the name column called? --------------------------------
      The original reads tblDiscount_Type.DiscountTypeName. Nothing else in
      this project references that table by name, so the column is unverified -
      and a wrong column name here would stop this procedure being CREATED at
      all rather than failing at run time. It is resolved instead, and an
      unrecognised table just leaves the names blank.
    ---------------------------------------------------------------------*/
    IF OBJECT_ID('tempdb..#dt') IS NOT NULL DROP TABLE #dt;
    CREATE TABLE #dt (Id INT PRIMARY KEY, DiscountTypeName NVARCHAR(200) NULL);

    DECLARE @nameCol SYSNAME =
        CASE WHEN COL_LENGTH('dbo.tblDiscount_Type', 'DiscountTypeName') IS NOT NULL THEN 'DiscountTypeName'
             WHEN COL_LENGTH('dbo.tblDiscount_Type', 'DiscountType')     IS NOT NULL THEN 'DiscountType'
             WHEN COL_LENGTH('dbo.tblDiscount_Type', 'TypeName')         IS NOT NULL THEN 'TypeName'
             WHEN COL_LENGTH('dbo.tblDiscount_Type', 'Name')             IS NOT NULL THEN 'Name'
             ELSE NULL END;

    IF @nameCol IS NOT NULL AND OBJECT_ID('dbo.tblDiscount_Type') IS NOT NULL
    BEGIN
        DECLARE @sql NVARCHAR(MAX) =
            N'INSERT INTO #dt (Id, DiscountTypeName) SELECT Id, ' + QUOTENAME(@nameCol)
          + N' FROM dbo.tblDiscount_Type WITH (NOLOCK);';
        EXEC sp_executesql @sql;
    END

    -- The line's own discount type when it has one, otherwise the invoice's.
    -- Same rule as the original, written once instead of in a CASE per column.
    SELECT   [Discount Type] = ISNULL(dt.DiscountTypeName, N'(none)')
           , [Branch]        = ISNULL(b.branchName, N'-')
           , [Item]          = ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
           , [Qty]           = CAST(SUM(o.Quantity) AS INT)
           , [Discount]      = CAST(SUM(ISNULL(o.Discount, 0)) AS DECIMAL(18,3))
           , [Line Total]    = CAST(SUM(ISNULL(o.TotalAmount, 0)) AS DECIMAL(18,3))
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     dbo.tblInvoice i WITH (NOLOCK) ON i.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblbranch b WITH (NOLOCK) ON b.id = i.BranchID
    LEFT JOIN dbo.tblItems it WITH (NOLOCK) ON it.ID = o.ItemID
    LEFT JOIN #dt dt
           ON dt.Id = CASE WHEN ISNULL(o.DiscountTypeID, 0) > 0 THEN o.DiscountTypeID ELSE i.DiscountTypeID END
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    ISNULL(o.Deleted, 0) = 0
      AND    (ISNULL(o.Discount, 0) > 0 OR ISNULL(i.Discount, 0) > 0)
      AND    i.InvoiceDate >= CAST(@FromDate AS DATE)
      AND    i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
      AND    (NULLIF(@BranchIds, '') IS NULL
              OR i.BranchID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')))
    GROUP BY ISNULL(dt.DiscountTypeName, N'(none)'), ISNULL(b.branchName, N'-'),
             ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
    ORDER BY [Discount] DESC;

    DROP TABLE #dt;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_DashbordPaymentTypesData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_DashbordPaymentTypesData]
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();

    SELECT   [Branch]        = ISNULL(b.branchName, N'-')
           , [Payment Type]  = ISNULL(pt.PaymentTypeName, ISNULL(p.PaymentType, N'Unknown'))
           , [Orders]        = COUNT(DISTINCT i.InvoiceNo)
           , [Amount]        = CAST(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END) AS DECIMAL(18,3))
    FROM     dbo.tblInvoicePayment p WITH (NOLOCK)
    JOIN     dbo.tblInvoice i WITH (NOLOCK) ON i.InvoiceNo = p.InvoiceId
    LEFT JOIN dbo.tblbranch b WITH (NOLOCK) ON b.id = i.BranchID
    LEFT JOIN dbo.tblInvoicePaymentType pt WITH (NOLOCK) ON pt.ID = p.PaymentTypeID
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    ISNULL(p.isdeleted, 0) = 0
      AND    i.InvoiceDate >= CAST(@FromDate AS DATE)
      AND    i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
      AND    (NULLIF(@BranchIds, '') IS NULL
              OR i.BranchID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')))
    GROUP BY ISNULL(b.branchName, N'-'), ISNULL(pt.PaymentTypeName, ISNULL(p.PaymentType, N'Unknown'))
    ORDER BY [Branch], [Amount] DESC;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_DashbordSalesData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_DashbordSalesData]
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();
    IF @GroupByFlag IS NULL SET @GroupByFlag = 1;

    DECLARE @dFrom DATETIME = CAST(@FromDate AS DATE)
          , @dTo   DATETIME = DATEADD(DAY, 1, CAST(@ToDate AS DATE));

    /*---- filters ---------------------------------------------------------
      Empty or '0' means "all". The dashboard's All option posts 0, and the
      controller strips it for branch and brand but deliberately NOT for
      payment type, where 0 means cash - so a 0 here must not wipe the filter.
    ---------------------------------------------------------------------*/
    DECLARE @Branches TABLE (v INT PRIMARY KEY);
    DECLARE @Brands   TABLE (v INT PRIMARY KEY);
    DECLARE @ITypes   TABLE (v INT PRIMARY KEY);
    DECLARE @PTypes   TABLE (v INT PRIMARY KEY);
    DECLARE @Days     TABLE (d DATE PRIMARY KEY);

    IF NULLIF(LTRIM(RTRIM(@BranchIds)), '') IS NOT NULL
        INSERT INTO @Branches (v)
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')
        WHERE TRY_CAST(value AS INT) IS NOT NULL AND TRY_CAST(value AS INT) > 0;

    IF NULLIF(LTRIM(RTRIM(@BrandIds)), '') IS NOT NULL
        INSERT INTO @Brands (v)
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BrandIds, ',')
        WHERE TRY_CAST(value AS INT) IS NOT NULL AND TRY_CAST(value AS INT) > 0;

    IF NULLIF(LTRIM(RTRIM(@InvoiceTypeIds)), '') IS NOT NULL
        INSERT INTO @ITypes (v)
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@InvoiceTypeIds, ',')
        WHERE TRY_CAST(value AS INT) IS NOT NULL AND TRY_CAST(value AS INT) > 0;

    IF NULLIF(LTRIM(RTRIM(@PaymentTypeIds)), '') IS NOT NULL
        INSERT INTO @PTypes (v)
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@PaymentTypeIds, ',')
        WHERE TRY_CAST(value AS INT) IS NOT NULL;

    -- Operating days, when the user picked specific ones. @IsDefaultLoad = 1
    -- means they have not touched that dropdown, so the date range rules.
    IF ISNULL(@IsDefaultLoad, 0) = 0 AND NULLIF(LTRIM(RTRIM(@EndDates)), '') IS NOT NULL
        INSERT INTO @Days (d)
        SELECT DISTINCT TRY_CAST(value AS DATE) FROM STRING_SPLIT(@EndDates, ',')
        WHERE TRY_CAST(value AS DATE) IS NOT NULL;

    DECLARE @AnyBranch BIT = CASE WHEN EXISTS (SELECT 1 FROM @Branches) THEN 0 ELSE 1 END
          , @AnyBrand  BIT = CASE WHEN EXISTS (SELECT 1 FROM @Brands)   THEN 0 ELSE 1 END
          , @AnyIType  BIT = CASE WHEN EXISTS (SELECT 1 FROM @ITypes)   THEN 0 ELSE 1 END
          , @AnyPType  BIT = CASE WHEN EXISTS (SELECT 1 FROM @PTypes)   THEN 0 ELSE 1 END
          , @AnyDay    BIT = CASE WHEN EXISTS (SELECT 1 FROM @Days)     THEN 0 ELSE 1 END;

    /*---- the invoices in scope, once --------------------------------------
      Every panel below reads this. Building it once rather than repeating the
      filter in nine queries is what keeps them agreeing with each other.
    ---------------------------------------------------------------------*/
    IF OBJECT_ID('tempdb..#inv') IS NOT NULL DROP TABLE #inv;

    SELECT   i.InvoiceNo
           , i.BranchID
           , i.BrandID
           , i.InvoiceType
           , i.PaymentType
           , i.InvoiceDate
           , i.OrderStatusID
           , NetTotal   = CAST(i.FinalAmount + ISNULL(i.DeliveryCharges, 0) AS DECIMAL(18,3))
           , Discount   = CAST(ISNULL(i.Discount, 0) AS DECIMAL(18,3))
           , BranchName = ISNULL(b.branchName, N'-')
    INTO     #inv
    FROM     dbo.tblInvoice i WITH (NOLOCK)
    LEFT JOIN dbo.tblbranch b WITH (NOLOCK) ON b.id = i.BranchID
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    i.InvoiceDate >= @dFrom
      AND    i.InvoiceDate <  @dTo
      AND    (@AnyDay    = 1 OR CAST(i.InvoiceDate AS DATE) IN (SELECT d FROM @Days))
      AND    (@AnyBranch = 1 OR i.BranchID    IN (SELECT v FROM @Branches))
      AND    (@AnyBrand  = 1 OR i.BrandID     IN (SELECT v FROM @Brands))
      AND    (@AnyIType  = 1 OR i.InvoiceType IN (SELECT v FROM @ITypes))
      AND    (@AnyPType  = 1 OR ISNULL(i.PaymentType, 0) IN (SELECT v FROM @PTypes));

    CREATE CLUSTERED INDEX IX_inv ON #inv (InvoiceNo);

    /*======================================================================
      0 : Total sales
    ======================================================================*/
    SELECT   TotalSales = CAST(ISNULL(SUM(NetTotal), 0) AS DECIMAL(18,3))
           , OrderCount = CAST(COUNT(*) AS INT)
    FROM     #inv;

    /*======================================================================
      1 : Total discount. OrderCount counts orders that HAD a discount, not
          all orders - "12 discounts" beside a discount total reads correctly,
          "12 orders" beside it does not.
    ======================================================================*/
    SELECT   TotalDiscount = CAST(ISNULL(SUM(Discount), 0) AS DECIMAL(18,3))
           , OrderCount    = CAST(SUM(CASE WHEN Discount > 0 THEN 1 ELSE 0 END) AS INT)
    FROM     #inv;

    /*======================================================================
      2 : Payment types. Taken from the payment ROWS, so a split payment shows
          under both methods. Orders with no payment row are Unpaid.
    ======================================================================*/
    SELECT   Name   = x.Name
           , orders = CAST(COUNT(DISTINCT x.InvoiceNo) AS INT)
           , Total  = CAST(ISNULL(SUM(x.Amount), 0) AS DECIMAL(18,3))
    FROM   (
        SELECT   v.InvoiceNo
               , Name   = ISNULL(pt.PaymentTypeName, ISNULL(p.PaymentType, N'Unknown'))
               , Amount = CAST(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END AS DECIMAL(18,3))
        FROM     #inv v
        JOIN     dbo.tblInvoicePayment p WITH (NOLOCK) ON p.InvoiceId = v.InvoiceNo
        LEFT JOIN dbo.tblInvoicePaymentType pt WITH (NOLOCK) ON pt.ID = p.PaymentTypeID
        WHERE    ISNULL(p.isdeleted, 0) = 0

        UNION ALL

        SELECT   v.InvoiceNo, N'Unpaid', v.NetTotal
        FROM     #inv v
        WHERE    NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePayment p WITH (NOLOCK)
                             WHERE p.InvoiceId = v.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0)
    ) x
    GROUP BY x.Name
    ORDER BY Total DESC;

    /*======================================================================
      3 : Sales line chart, one series per branch.
          InvoiceDate must be a real DATETIME - the controller reads it with
          Field<DateTime> and formats it itself.
    ======================================================================*/
    SELECT   BranchName = v.BranchName
           , InvoiceDate = CAST(CAST(v.InvoiceDate AS DATE) AS DATETIME)
           , NetTotal    = CAST(ISNULL(SUM(v.NetTotal), 0) AS DECIMAL(18,3))
           , TotalCount  = CAST(COUNT(*) AS INT)
    FROM     #inv v
    GROUP BY v.BranchName, CAST(v.InvoiceDate AS DATE)
    ORDER BY v.BranchName, CAST(CAST(v.InvoiceDate AS DATE) AS DATETIME);

    /*======================================================================
      4 : Sales pivot. One row per branch per day per measure; the view turns
          keyName / KeyValue into columns. Measures are Sales / Orders / Avg
          Per cheque (Discount dropped - the "Sales Data" drill-down grid
          does not show it); InvoiceDate is emitted as yyyy-MM-dd (style 23)
          so SalesPivotBuilder.FormatDate() in DashboardModels.cs can
          TryParseExact it, and so plain-text sort order matches chronological
          order without needing to parse first.
    ======================================================================*/
    SELECT   BranchName = v.BranchName
           , keyName    = k.keyName
           , KeyValue   = CAST(k.KeyValue AS DECIMAL(18,3))
           , InvoiceDate = CONVERT(VARCHAR(10), CAST(v.InvoiceDate AS DATE), 23)
    FROM   (
        SELECT   BranchName, Day = CAST(InvoiceDate AS DATE)
               , Sales = SUM(NetTotal), Cnt = COUNT(*)
        FROM     #inv GROUP BY BranchName, CAST(InvoiceDate AS DATE)
    ) g
    CROSS APPLY (VALUES ('Sales', g.Sales), ('Orders', CAST(g.Cnt AS DECIMAL(18,3))),
                         ('AvgPerCheque', CASE WHEN g.Cnt = 0 THEN 0 ELSE g.Sales / g.Cnt END)) k(keyName, KeyValue)
    JOIN     #inv v ON v.BranchName = g.BranchName AND CAST(v.InvoiceDate AS DATE) = g.Day
    GROUP BY v.BranchName, k.keyName, k.KeyValue, CAST(v.InvoiceDate AS DATE)
    ORDER BY v.BranchName, CAST(v.InvoiceDate AS DATE);

    /*======================================================================
      5 : Order types. The original sorted a literal 'zzzzzTotal' to the bottom
          and the JS renames it - kept, so that code still works.
    ======================================================================*/
    SELECT   Name        = x.Name
           , TotalOrders = CAST(x.TotalOrders AS INT)
           , TotalSales  = CAST(x.TotalSales AS DECIMAL(18,3))
    FROM   (
        SELECT   Name = ISNULL(it.Name, N'Unknown')
               , TotalOrders = COUNT(*)
               , TotalSales  = ISNULL(SUM(v.NetTotal), 0)
               , Ord = 1
        FROM     #inv v
        LEFT JOIN dbo.tblInvoiceType_Master it WITH (NOLOCK) ON it.ID = v.InvoiceType
        GROUP BY ISNULL(it.Name, N'Unknown')

        UNION ALL

        SELECT N'zzzzzTotal', COUNT(*), ISNULL(SUM(v.NetTotal), 0), 2 FROM #inv v
    ) x
    ORDER BY x.Ord, x.TotalSales DESC;

    /*======================================================================
      6 : Cancellations, reuse. Deleted lines whose stock went back.
    ======================================================================*/
    SELECT   TotalDelItems = CAST(ISNULL(SUM(o.TotalAmount), 0) AS DECIMAL(18,3))
           , CountDelItems = CAST(COUNT(*) AS INT)
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     #inv v ON v.InvoiceNo = o.InvoiceNo
    WHERE    ISNULL(o.Deleted, 0) = 1 AND ISNULL(o.IsSplit, 0) = 0 AND ISNULL(o.Waste, 0) = 0;

    /*======================================================================
      7 : Cancellations, waste. Made and thrown away.

          The original added tblWaste / tblWasteDetails here - standalone waste
          not attached to an order. Neither table exists in this database, so
          this is order-line waste only.
    ======================================================================*/
    SELECT   TotalWasteItems = CAST(ISNULL(SUM(o.TotalAmount), 0) AS DECIMAL(18,3))
           , CountWasteItems = CAST(COUNT(*) AS INT)
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     #inv v ON v.InvoiceNo = o.InvoiceNo
    WHERE    ISNULL(o.Waste, 0) = 1;

    /*======================================================================
      8 : placeholder - the controller does not read Tables[8], but the ones
          after it are read by index, so it has to exist.
    ======================================================================*/
    SELECT TOP 0 Placeholder = CAST(NULL AS INT);

    /*======================================================================
      9 : Hourly breakdown.
          GroupByFlag 1 = per branch, 2 = per invoice type, anything else = all
          branches together. HoursBreak is the label the chart plots along the
          x axis, so it is zero-padded - '09-10' sorts before '10-11', '9-10'
          does not.
    ======================================================================*/
    SELECT   Name       = CASE WHEN @GroupByFlag = 2 THEN ISNULL(it.Name, N'Unknown')
                               WHEN @GroupByFlag = 1 THEN v.BranchName
                               ELSE N'All' END
           , HoursBreak = RIGHT('0' + CAST(DATEPART(HOUR, v.InvoiceDate) AS VARCHAR(2)), 2) + '-'
                        + RIGHT('0' + CAST((DATEPART(HOUR, v.InvoiceDate) + 1) % 24 AS VARCHAR(2)), 2)
           , TotalSales = CAST(ISNULL(SUM(v.NetTotal), 0) AS DECIMAL(18,3))
           , TotalCount = CAST(COUNT(*) AS INT)
    FROM     #inv v
    LEFT JOIN dbo.tblInvoiceType_Master it WITH (NOLOCK) ON it.ID = v.InvoiceType
    GROUP BY CASE WHEN @GroupByFlag = 2 THEN ISNULL(it.Name, N'Unknown')
                  WHEN @GroupByFlag = 1 THEN v.BranchName
                  ELSE N'All' END
           , DATEPART(HOUR, v.InvoiceDate)
    ORDER BY 1, DATEPART(HOUR, v.InvoiceDate);

    /*======================================================================
     10 : Top items. Sold lines only - a deleted line is not a sale.
          ItemNameSnapshot is the name AS SOLD; falling back to the live name
          means a renamed item does not rewrite last month's chart.
    ======================================================================*/
    SELECT TOP (20)
             itemName  = ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
           , SoldItems = CAST(SUM(o.Quantity) AS INT)
           , Total     = CAST(ISNULL(SUM(o.TotalAmount), 0) AS DECIMAL(18,3))
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     #inv v ON v.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblItems it WITH (NOLOCK) ON it.ID = o.ItemID
    WHERE    ISNULL(o.Deleted, 0) = 0
    GROUP BY ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
    ORDER BY SoldItems DESC;

    /*====================================================================== 11 */
    SELECT TOP 0 Placeholder = CAST(NULL AS INT);

    /*======================================================================
     12 : Branch sales chart.
    ======================================================================*/
    SELECT   BranchName    = v.BranchName
           , OrderTotalAmt = CAST(ISNULL(SUM(v.NetTotal), 0) AS DECIMAL(18,3))
           , OrderCount    = CAST(COUNT(*) AS INT)
    FROM     #inv v
    GROUP BY v.BranchName
    ORDER BY OrderTotalAmt DESC;

    /*====================================================================== 13 */
    SELECT TOP 0 Placeholder = CAST(NULL AS INT);

    /*======================================================================
     14 : Late orders per branch.

          The original read per-branch tbl_StatusDetails. Here the timings are
          in tblPOS_OrderStatusHistory: an order is late when the gap between
          the invoice and the row that closed it exceeds @LateMinDuration.
          Orders still open are not late - they are not finished.
    ======================================================================*/
    SELECT   BranchName     = v.BranchName
           , LateOrderCount = CAST(SUM(CASE WHEN x.Mins >= @LateMinDuration THEN 1 ELSE 0 END) AS INT)
           , TotalOrders    = CAST(COUNT(*) AS INT)
    FROM     #inv v
    OUTER APPLY (
        SELECT Mins = DATEDIFF(MINUTE, v.InvoiceDate, MAX(h.ChangedOn))
        FROM   dbo.tblPOS_OrderStatusHistory h WITH (NOLOCK)
        JOIN   dbo.tblOrderStatus s WITH (NOLOCK) ON s.OrderStatusID = h.ToStatusID
        WHERE  h.InvoiceNo = v.InvoiceNo AND ISNULL(s.IsTerminal, 0) = 1
    ) x
    GROUP BY v.BranchName
    ORDER BY LateOrderCount DESC;

    /*======================================================================
     15 : Currency. The Call Centre served two countries and read this from a
          country table. There is one here, so it comes from Web.config's
          currency by way of a constant - change the literal if the brand
          trades in something other than KD.
    ======================================================================*/
    SELECT Currency = N'KD';

    DROP TABLE #inv;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_DeleteCategory]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_DeleteCategory]
@CAT_NUM int
AS
BEGIN
declare @issubcat int =0;
declare @issubitems int =0;


	select @issubcat=count(1) from tblCategory where MainCategory=@CAT_NUM
	select @issubitems=count(1) from tblItems where CAT_NUM=@CAT_NUM

	if @issubcat =0 and @issubitems =0
	begin
		delete tblCategory where CAT_NUM=@CAT_NUM
		select 'success' msg
	end
	else if @issubcat !=0 
	begin
		select 'SubCategory Exist' msg
	end
	else if @issubitems !=0
	begin
		select 'Items Exist' msg
	end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_DeleteGroupModifier]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_DeleteGroupModifier]
@ID int=0
AS
BEGIN
	delete tblGroup_Modifier_Master where id =@ID
	update tblGroup_Modifier_Details set deleted=1 where groupid =@ID
	select 'Success' Status
END

GO
/****** Object:  StoredProcedure [dbo].[sp_DeleteItem]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_DeleteItem]
@ID int
AS
BEGIN
	delete tblItems where id=@ID
END

GO
/****** Object:  StoredProcedure [dbo].[sp_DeleteItemImages]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
/****** Object:  StoredProcedure [dbo].[sp_DeleteReservationSlot]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_DeleteReservationSlot]
@id int=0
AS
BEGIN
	update tblReservationSlot set Isdeleted=1 where Id=@id
END

GO
/****** Object:  StoredProcedure [dbo].[sp_DeleteReservationTableStructure]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_DeleteReservationTableStructure]
@TableStructureID int=0
AS
BEGIN
	update tblReservationTableStructure set IsDeleted=1 where Id=@TableStructureID
END


GO
/****** Object:  StoredProcedure [dbo].[sp_editThemes]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_editThemes]
@themeID int,
@themeName nvarchar(500)='',
@categoryActive nvarchar(500)='',
@brandID int=0,
@categoryInActive nvarchar(500)='',
@englishButton nvarchar(500)='',

@arabicButton nvarchar(500)='',
@closeButton nvarchar(500)='',

@homeScreen nvarchar(500)='',
@popUpBackground nvarchar(500)='',

@FontColor nvarchar(500)='',
@FontColorItemName nvarchar(500)='',

@itemBackgroundColor nvarchar(500)='',

@FontColorIngName nvarchar(500)='',
@FontColorPrice nvarchar(500)='',

@Command nvarchar(500)
AS
BEGIN
 
 if (@Command= 'Add')
 begin
 insert into tblTheme (
[ThemeName]
      ,[CategoryActive]
      ,[CategoryInActive]
      ,[Setting]
      ,[SeperatorLine]
      ,[EnglishButton]
      ,[ArabicButton]
      ,[MandarinButton]
      ,[RussianButton]
      ,[CloseButton]
      ,[HomeScreen]
      ,[LeftArrow]
      ,[LeftBottom]
      ,[LeftTop]
      ,[PopUpBackground]
      ,[RightArrow]
      ,[RightButton]
      ,[RightTop]
      ,[FontColor]
      ,[FontColorItemName]
      ,[FontColorIngName]
      ,[FontColorPrice]
      ,[ItemBackgroundColor])
	  select @themeName,@categoryActive,@categoryInActive,'setting.png','separator_line.png',
	  @englishButton,@arabicButton,@englishButton,@englishButton,@closeButton,@homeScreen,'left_arrow.png','left_bottom.png','left_top.png'
	  ,@popUpBackground,'right_arrow.png','right_bottom.png','right_top.png',@FontColor,@FontColorItemName,@FontColorIngName,@FontColorPrice,@itemBackgroundColor

	  update tblBrand set Theme= (select max(ThemeID) from tblTheme) where BrandID=@brandID
 end
 else
 begin
 update tblTheme 
 set ThemeName=@themeName, CategoryActive=@categoryActive,CategoryInActive=@categoryInActive
 ,EnglishButton=@englishButton,ArabicButton= @arabicButton,CloseButton=@closeButton,FontColor=@FontColor,FontColorIngName=@FontColorIngName
 ,FontColorItemName=@FontColorItemName,FontColorPrice=@FontColorPrice,ItemBackgroundColor=@itemBackgroundColor, [HomeScreen]=@homeScreen, [PopUpBackground]=@popUpBackground where ThemeID=@themeID
 
 update tblBrand set Theme=@themeID where BrandID=@brandID
 end

END



GO
/****** Object:  StoredProcedure [dbo].[sp_GenerateCartCommentsObject]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GenerateCartCommentsObject]
@dttblCartComment [DT_tblCartComment] readonly
AS
BEGIN
	select dt.II,c.id as CI,c.comments_eng,c.comments_arb from tblcomments c
	inner join @dttblCartComment as dt on dt.CI=c.id
END






GO
/****** Object:  StoredProcedure [dbo].[sp_GenerateCartExtraAndChoicesObject]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GenerateCartExtraAndChoicesObject]
@dtextras [DT_tblWaiterExtra] readonly,
@dtchoices [DT_tblWaiterChoice] readonly
AS
BEGIN
	select dt.UID,dt.MI,dt.ExId,dt.GId,i.ITEM_NAME,i.ITEM_NAME_ARABIC ,i.PRICE from tblItems i
	inner join @dtextras as dt on dt.ExId=i.ID

	select dt.UID,dt.MI,dt.ChId,dt.GId,i.ITEM_NAME,i.ITEM_NAME_ARABIC ,i.PRICE from tblItems i
	inner join @dtchoices as dt on dt.ChId=i.ID
END



GO
/****** Object:  StoredProcedure [dbo].[sp_GenerateCartExtraItemsObject]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GenerateCartExtraItemsObject]
@dttblCartExtraItems [DT_tblCartExtraItems] readonly
AS
BEGIN
	select dt.II,i.id as EI,i.ITEM_NAME,i.ITEM_NAME_ARABIC ,i.PRICE from tblItems i
	inner join @dttblCartExtraItems as dt on dt.EI=i.ID
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetAllChoices]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetAllChoices]
@Brandid int =0
AS
BEGIN
	if @Brandid > 0
	begin
		select id,CAT_NUM,ITEM_NAME,ITEM_NAME_ARABIC,PRICE,isnull(IMAGENAME,'no_image.png') as IMAGENAME,
		case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
		(select top 1 currency from tblBrand order by brandid) end as Currency
		from tblItems where IsActive=1 and Ischoice=1 
		and tblItems.CAT_NUM in (select CatNum from Assign_Cat where BrandId=@BrandId)
	end
	else
	begin
		select id,CAT_NUM,ITEM_NAME,ITEM_NAME_ARABIC,PRICE,isnull(IMAGENAME,'no_image.png') as IMAGENAME,
		case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
		(select top 1 currency from tblBrand order by brandid) end as Currency
		from tblItems where IsActive=1 and Ischoice=1 
	end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetAllergens]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetAllergens]
@Brandid int =0
AS
BEGIN
	select id,isnull(name,'') as name,isnull(Name_arabic,'') as Name_arabic,image from tbl_Allergen
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetAllExtraItems]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetAllExtraItems]
@Brandid int =0
AS
BEGIN
	if @Brandid > 0
	begin
		select id,CAT_NUM,ITEM_NAME,ITEM_NAME_ARABIC,PRICE,isnull(IMAGENAME,'no_image.png') as IMAGENAME,
		case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
		(select top 1 currency from tblBrand order by brandid) end as Currency
		from tblItems where IsActive=1 and isExtra=1 
		and tblItems.CAT_NUM in (select CatNum from Assign_Cat where BrandId=@BrandId)
	end
	else
	begin
		select id,CAT_NUM,ITEM_NAME,ITEM_NAME_ARABIC,PRICE,isnull(IMAGENAME,'no_image.png') as IMAGENAME,
		case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
		(select top 1 currency from tblBrand order by brandid) end as Currency
		from tblItems where IsActive=1 and isExtra=1 
	end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetAreaListForDeliveryAddress]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_GetAreaListForDeliveryAddress]
      @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @HasMapping BIT = CASE
        WHEN @BranchID IS NOT NULL
         AND EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE BranchID = @BranchID)
        THEN 1 ELSE 0 END;

    SELECT   a.AreaID
           , a.AreaName
           , a.AreaNameAra
           , DeliveryCharges = ISNULL(a.DeliveryCharges, 0)
           , a.Points
           , a.CenterLat
           , a.CenterLng
    FROM     dbo.tblArea a
    WHERE    a.AreaID IS NOT NULL
      AND    ( @HasMapping = 0
               OR EXISTS (SELECT 1 FROM dbo.TblArea_Mapping m
                          WHERE m.AreaID = a.AreaID AND m.BranchID = @BranchID) )
    ORDER BY a.AreaName;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetAssignBranch]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetAssignBranch]

@Cat_Num int
AS
BEGIN

select c.*,b.branchName from Assign_Cat c
inner join tblbranch b on b.id=c.branchid 
 where CatNum=@Cat_Num 
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetAssignBranchItemsAndComments]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetAssignBranchItemsAndComments]
@ItemId int,
@BrandID int
AS
BEGIN

--selected branch list
select br.id as BranchId, br.branchName from Assign_Item I
inner join tblbranch br on br.id=I.BranchId 
 where I.ItemId=@ItemId and I.BrandID=@BrandID

 --selected Extra items id
 select ie.ExtraItemId from tblItem_Extras ie where ie.ItemId=@ItemId

 --selected Comments id
 select ic.commentid from tblItemComments ic where ic.ItemId=@ItemId

END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetAssignBrand]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetAssignBrand]

@Cat_Num int
AS
BEGIN

select c.*,b.BrandName from Assign_Cat c
inner join tblBrand b on b.BrandID=c.BrandID 
 where CatNum=@Cat_Num 
END



GO
/****** Object:  StoredProcedure [dbo].[sp_GetAuditReportsData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
CREATE PROCEDURE [dbo].[sp_GetAuditReportsData]
	-- Add the parameters for the stored procedure here
	@BrandId int =0,
	@FromDate Date = Null,
	@ToDate Date = Null
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	Select Main.TopCard, A.TotalCustomers, 
		IsNull(B.TopCategory, '') AS TopCategory, 
		IsNull(B.TopCategoryCount, '') AS TopCategoryCount, 
		IsNull(C.TopItem, '') AS TopItem, 
		IsNull(C.TopItemCount, '') AS TopItemCount
	From
	(Select 'TopCard' As TopCard) Main
	Left Join
	(--Customer Total
	Select Count(DISTINCT a.IPAddress) As TotalCustomers 
	from tblAudit a
	inner join tblbranch b on b.id=a.BranchId
	inner join tblBrand bd on bd.BrandID=b.brandId
	where Cast(a.CreatedOn As Date) Between Cast(@FromDate As Date) AND Cast(@ToDate As Date)
	and bd.BrandID=@BrandId and b.IsActive=1 and isnull(b.IsDeleted,0) =0
	) A ON 1 = 1
	Left Join
	--Top Category Visited
	--Top Category Visited
	--(Select Top 1 ItemSelectionName AS TopCategory, Count(ItemSelectionName) As TopCategoryCount 
	--from tblAudit ta
	--inner join tblbranch b on b.id=ta.BranchId
	--inner join tblBrand bd on bd.BrandID=b.brandId
	--Inner Join tblAuditDetails tad on ta.ID = tad.AuditID
	--where Cast(tad.CreatedOn As Date) Between Cast(@FromDate As Date) AND Cast(@ToDate As Date)
	--and tad.ItemSelectionType = 2 and bd.BrandID=@BrandId and b.IsActive=1 and isnull(b.IsDeleted,0) =0
	--Group By ItemSelectionName
	--Order by Count(ItemSelectionName) DESC) B ON 1 = 1
	(select top 1 Category as TopCategory,count(visits) as TopCategoryCount from (
	select ta.IPAddress as IPAddress, count(tad.ItemSelectionID) as Visits,
	c.CAT_NAME as Category
	from tblAuditDetails  tad
	inner join tblAudit ta on ta.ID=tad.AuditID
	inner join tblbranch b on b.id=ta.BranchId
	inner join tblBrand bd on bd.BrandID=b.brandId
	inner join tblCategory c on c.CAT_NUM=tad.ItemSelectionID
	where Cast(tad.CreatedOn As Date) between cast(@FromDate as date) and cast(@ToDate as date)
	and tad.ItemSelectionType = 2 and bd.BrandID=@BrandId and b.IsActive=1 and isnull(b.IsDeleted,0) =0
	--and  ItemSelectionID=3
	group by ta.IPAddress,ItemSelectionID,c.CAT_NAME
	) temp group by Category order by count(visits) desc) B ON 1 = 1
	Left Join
	--Top Item Visited
	--(Select Top 1 ItemSelectionName AS TopItem, Count(ItemSelectionName) As TopItemCount from tblAudit ta
	--Inner Join tblAuditDetails tad on ta.ID = tad.AuditID
	--inner join tblbranch b on b.id=tad.BranchId
	--inner join tblBrand bd on bd.BrandID=b.brandId
	--where Cast(tad.CreatedOn As Date) Between Cast(@FromDate As Date) AND Cast(@ToDate As Date)
	--and tad.ItemSelectionType = 3 and  bd.BrandID=@BrandId and b.IsActive=1 and isnull(b.IsDeleted,0) =0
	--Group By ItemSelectionName
	--Order by Count(ItemSelectionName) DESC) C ON 1 = 1
	(select top 1 Item as TopItem,count(visits) as TopItemCount from (
	select ta.IPAddress as IPAddress, count(tad.ItemSelectionID) as Visits,
	i.ITEM_NAME as Item
	from tblAuditDetails  tad
	inner join tblAudit ta on ta.ID=tad.AuditID
	inner join tblbranch b on b.id=ta.BranchId
	inner join tblBrand bd on bd.BrandID=b.brandId
	inner join tblItems i on i.ID=tad.ItemSelectionID
	where Cast(tad.CreatedOn As Date) between cast(@FromDate as date) and cast(@ToDate as date)
	and tad.ItemSelectionType = 3 and bd.BrandID=@BrandId and b.IsActive=1 and isnull(b.IsDeleted,0) =0
	--and  ItemSelectionID=3
	group by ta.IPAddress,ItemSelectionID,i.ITEM_NAME
	) temp group by Item order by count(visits) desc) c ON 1 = 1

	--Show Branch Wise Visit (No. of customer visit ... based on IP address Count)
	Select  tb.branchName, Count(distinct ta.IPAddress) As VisitorsCount
	From tblbranch tb 
	inner join tblBrand bd on bd.BrandID=tb.brandId
	Left Outer Join tblAudit ta on ta.BranchId = tb.id
	Where Cast(ta.CreatedOn As Date) Between Cast(@FromDate As Date) AND Cast(@ToDate As Date)
	and  bd.BrandID=@BrandId and tb.IsActive=1 and isnull(tb.IsDeleted,0) =0
	Group by tb.branchName
	Order by Count(ta.IPAddress) DESC

	--Show Mobile Type wise Graph Chart
	--Select  ta.DeviceModal, Count(ta.IPAddress) As VisitorsCount
	--From tblbranch tb 
	--Left Outer Join tblAudit ta on ta.BranchId = tb.id
	--Where Cast(ta.CreatedOn As Date) Between Cast(@FromDate As Date) AND Cast(@ToDate As Date)
	--Group by ta.DeviceModal
	--Order by Count(ta.IPAddress) DESC
	
	Declare @BranchesIsnull Varchar(MAX) = ''
	select @BranchesIsnull = STUFF((SELECT DISTINCT ',' + 'isnull('+QUOTENAME(tb.branchName) +',0) as ' +QUOTENAME(tb.branchName)
						From tblbranch tb 
						left Join tblAudit ta on ta.BranchId = tb.id
						where  tb.IsActive=1 and isnull(tb.IsDeleted,0) =0
			FOR XML PATH(''), TYPE
			).value('.', 'NVARCHAR(MAX)') 
		,1,1,'')
		--select @BranchesIsnull


	Declare @Branches Varchar(MAX) = ''
	select @Branches = STUFF((SELECT DISTINCT ',' + QUOTENAME(tb.branchName) 
						From tblbranch tb 
						left Join tblAudit ta on ta.BranchId = tb.id
						where  tb.IsActive=1 and isnull(tb.IsDeleted,0) =0
			FOR XML PATH(''), TYPE
			).value('.', 'NVARCHAR(MAX)') 
		,1,1,'')

		--select @Branches


		Declare @Query Varchar(MAX) = ''
		Set @Query = 'SELECT case when DeviceModal=''Linux'' then ''Mobile'' else isnull(DeviceModal,''Computer'') end as DeviceModal,'+@BranchesIsnull+'
	FROM
	(
		select  DeviceModal,branchName,count(IPAddress) as VisitorsCount from(
		select distinct ta.IPAddress,case when ttt.DeviceModal='''' then ''Computer'' when ttt.DeviceModal=''Linux'' then ''Mobile''  else isnull(ttt.DeviceModal,''Computer'') end  as DeviceModal,branchName
		--,Count(ta.IPAddress) As VisitorsCount
		from(
		select DeviceModal,b.branchName
		from tblbranch b
		left join tblAudit ta on b.id=ta.BranchId
		where b.BrandID='+cast(@BrandId as nvarchar(10))+' and b.IsActive=1 and isnull(b.IsDeleted,0) =0
		group by DeviceModal,b.branchName) ttt
		left join tblAudit ta on ta.DeviceModal=ttt.DeviceModal
		Where Cast(ta.CreatedOn As Date) Between '''+cast(Cast(@FromDate As Date) as nvarchar(50))+'''  AND  '''+cast(Cast(@ToDate As Date) as nvarchar(50))+''' ) temp
		Group by DeviceModal, branchName


		--Select  case when DeviceModal=''Linux'' then ''Mobile'' else isnull(DeviceModal,''Computer'') end  as DeviceModal, tb.branchName, Count(ta.IPAddress) As VisitorsCount
		--From tblbranch tb 
		--inner join tblBrand bd on bd.BrandID=tb.brandId
		--left Join tblAudit ta on ta.BranchId = tb.id
		--Where Cast(ta.CreatedOn As Date) Between '''+cast(Cast(@FromDate As Date) as nvarchar(50))+''' AND '''+cast(Cast(@ToDate As Date) as nvarchar(50))+'''
		--and bd.BrandID='+cast(@BrandId as nvarchar(10))+' and tb.IsActive=1 and isnull(tb.IsDeleted,0) =0
		--Group by ta.DeviceModal, tb.branchName
	) AS SourceTable PIVOT(AVG([VisitorsCount]) FOR [branchName] IN('+ @Branches + ')) AS PivotTable;'
	Print (@Query)
	Exec (@Query)

	--Category Wise Graph Chart
	;with cte as(
	select ta.IPAddress as IPAddress, count(tad.ItemSelectionID) as Visits,
	c.CAT_NAME as Category
	from tblAuditDetails  tad
	inner join tblAudit ta on ta.ID=tad.AuditID
	inner join tblbranch b on b.id=ta.BranchId
	inner join tblBrand bd on bd.BrandID=b.brandId
	inner join tblCategory c on c.CAT_NUM=tad.ItemSelectionID
	where Cast(tad.CreatedOn As Date) between cast(@FromDate as date) and cast(@ToDate as date)
	and tad.ItemSelectionType = 2 and bd.BrandID=@BrandId and b.IsActive=1 and isnull(b.IsDeleted,0) =0
	--and  ItemSelectionID=3
	group by ta.IPAddress,ItemSelectionID,c.CAT_NAME
	) 
	select top 5 Category as CAT_NAME,count(visits) as VisitorsCount from cte group by Category order by count(visits) desc

	--Top 10 Items
	;with cte as(
	select ta.IPAddress as IPAddress, count(tad.ItemSelectionID) as Visits,
	i.ITEM_NAME as ITEM_NAME
	from tblAuditDetails  tad
	inner join tblAudit ta on ta.ID=tad.AuditID
	inner join tblbranch b on b.id=ta.BranchId
	inner join tblBrand bd on bd.BrandID=b.brandId
	inner join tblItems i on i.ID=tad.ItemSelectionID
	where Cast(tad.CreatedOn As Date) between cast(@FromDate as date) and cast(@ToDate as date)
	and tad.ItemSelectionType = 3 and bd.BrandID=@BrandId and b.IsActive=1 and isnull(b.IsDeleted,0) =0
	--and  ItemSelectionID=3
	group by ta.IPAddress,ItemSelectionID,i.ITEM_NAME
	) 
	select top 5 ITEM_NAME as ITEM_NAME,count(visits) as VisitorsCount from cte group by ITEM_NAME order by count(visits) desc

END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetAvailability]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetAvailability]

--@TableStructureID int=0,
@TableSeatingCount int=0,
@reservationDate datetime =null,
@DiningArea nvarchar(50) ='Inner Area'

AS
BEGIN
	if @TableSeatingCount = 2 
	begin
		;with cte as(
		select rss.id,rss.slotName,rss.slotNameArabic,rss.fromTime,rss.toTime,
		(select COUNT(id) from tblReservationTableStructure 
		where Seating=@TableSeatingCount and DiningArea=@DiningArea)
		-
		(select count(rs.id) from tblReservation rs
		where TableStructureID in (select id from tblReservationTableStructure tblstruc 
		where tblstruc.Seating=@TableSeatingCount and tblstruc.DiningArea=@DiningArea)
		and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)) as AvailableTable
		
		from tblReservationSlot rss 
		where isnull(rss.IsDeleted,0)=0 and CONVERT(DATETIME, CONVERT(varchar(20), 
		cast( @reservationDate as date) ,101)  + ' ' + CONVERT(varchar(8), rss.fromTime, 108)) > GETDATE()   
		)
		select * from cte where AvailableTable > 0
	end
	else if @TableSeatingCount = 4 
	begin
		;with cte as(
		select 
		rss.id,rss.slotName,rss.slotNameArabic,rss.fromTime,rss.toTime,
		case when 
		((select COUNT(id) from tblReservationTableStructure 
		where Seating=@TableSeatingCount and DiningArea=@DiningArea)
		-
		(select count(rs.id) from tblReservation rs
		where TableStructureID in (select id from tblReservationTableStructure tblstruc 
		where tblstruc.Seating=@TableSeatingCount and tblstruc.DiningArea=@DiningArea)
		and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date))) > 0
		
		then 
		(select COUNT(id) from tblReservationTableStructure 
		where Seating=@TableSeatingCount and DiningArea=@DiningArea)
		-
		(select count(rs.id) from tblReservation rs
		where TableStructureID in (select id from tblReservationTableStructure tblstruc 
		where tblstruc.Seating=@TableSeatingCount and tblstruc.DiningArea=@DiningArea)
		and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date))

		else 
			--set query for check dynamically for mearge table
			--check 2 seating and 2 seating table count available 
			case when(select COUNT(id) from tblReservationTableStructure 
			where Seating=2 and DiningArea=@DiningArea)
			-
			((select count(rs.id) from tblReservation rs
			where TableStructureID in (select id from tblReservationTableStructure tblstruc 
			where tblstruc.Seating=2 and tblstruc.DiningArea=@DiningArea)
			and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date))
			+
			(select count(rs.id) from tblReservation rs
			where TableStructureID in (select id from tblReservationTableStructure tblstruc 
			where tblstruc.Seating=2 and tblstruc.DiningArea=@DiningArea)
			and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date))
			) >= 2 
			then 1 else 0 end
		end 
		as AvailableTable
		
		from tblReservationSlot rss 
		where isnull(rss.IsDeleted,0)=0 and CONVERT(DATETIME, CONVERT(varchar(20), 
		cast( @reservationDate as date) ,101)  + ' ' + CONVERT(varchar(8), rss.fromTime, 108)) > GETDATE()   
		)
		select * from cte where AvailableTable > 0
	end
	else if @TableSeatingCount = 6
	begin
		;with cte as(
		select 
		rss.id,rss.slotName,rss.slotNameArabic,rss.fromTime,rss.toTime,

		isnull((select  top 1 Id  from tblReservationTableStructure where Seating=4 
							and id not in(
							select rs.TableStructureID from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							union all
							select isnull(rs.meargedTableid,0) from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							)  and DiningArea=@DiningArea),0) as TableStructureID,
		isnull((select  top 1 Id  from tblReservationTableStructure where Seating=2 
							and id not in(
							select rs.TableStructureID from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=2 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							union all
							select isnull(rs.meargedTableid,0) from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=2 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							)  and DiningArea=@DiningArea),0) as meargedTableid
		
		from tblReservationSlot rss 
		where isnull(rss.IsDeleted,0)=0 and CONVERT(DATETIME, CONVERT(varchar(20), 
		cast( @reservationDate as date) ,101)  + ' ' + CONVERT(varchar(8), rss.fromTime, 108)) > GETDATE()   
		)
		select *,1 as AvailableTable  from cte where TableStructureID > 0 and meargedTableid > 0
	end
	else if @TableSeatingCount = 8
	begin
		;with cte as(
		select 
		rss.id,rss.slotName,rss.slotNameArabic,rss.fromTime,rss.toTime,
		case when (isnull((select  count(Id) from tblReservationTableStructure where Seating=4 
							and id not in(
							select rs.TableStructureID from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							union all
							select isnull(rs.meargedTableid,0) from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							)  and DiningArea=@DiningArea),0)) > 1 then  --check if more then 1 table of 4 seating then only else not available 

			isnull((select  top 1 Id  from tblReservationTableStructure where Seating=4 
								and id not in(
								select rs.TableStructureID from tblReservation rs where TableStructureID in (
								select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
								) and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)
								union all
								select isnull(rs.meargedTableid,0) from tblReservation rs where TableStructureID in (
								select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
								) and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)
								)  and DiningArea=@DiningArea),0) 
		else 0 end as TableStructureID,
		isnull((select  top 1 Id  from tblReservationTableStructure where Seating=4 
							and id not in(
							select rs.TableStructureID from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							union all
							select isnull(rs.meargedTableid,0) from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							)  and DiningArea=@DiningArea),0) as meargedTableid
		
		from tblReservationSlot rss 
		where isnull(rss.IsDeleted,0)=0 and CONVERT(DATETIME, CONVERT(varchar(20), 
		cast( @reservationDate as date) ,101)  + ' ' + CONVERT(varchar(8), rss.fromTime, 108)) > GETDATE()   
		)
		select *,1 as AvailableTable  from cte where TableStructureID > 0 and meargedTableid > 0
	end
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetAvilableTablesForChangeTable]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetAvilableTablesForChangeTable]
--@reservationDate datetime='2021-01-11',
--@DiningArea nvarchar(50)='Inner Area',
--@Timeslotid int=0
@ReservationId int,
@selectedTableid int
AS
BEGIN

declare @reservationDate datetime,
@DiningArea nvarchar(50),
@Timeslotid int=0,
@Seating int =0

select @reservationDate=reservationDate,@DiningArea= tbl.DiningArea,@Timeslotid=rs.sloteId,@Seating=tbl.Seating
from tblReservation rs 
inner join tblReservationTableStructure tbl on rs.TableStructureID=tbl.Id 
where rs.id=@ReservationId

--select @reservationDate,@DiningArea,@Timeslotid,@Seating



	select tbl.id,tbl.TableName,tbl.DiningArea
	--,tbl.Seating,isnull(tbl.Xaxis,0) as Xaxis,isnull(tbl.Yaxis,0) as Yaxis,
	--isnull(rs.id,0) as Reservationid,cast(rs.reservationDate as date) as reservationDate,rs.customerName,rs.customerMobile,rs.customerEmail,rs.comments,rs.confirmationId,rs.Status,rs.TransactionDate,isnull(rs.IsMearged,0) as IsMearged,
	--slt.slotName,slt.id
	from tblReservationTableStructure tbl 
	--left join tblReservation rs on rs.TableStructureID=tbl.Id and sloteId=@Timeslotid and cast(reservationDate as date)=cast(@reservationDate as date)
	left join (
	select id,reservationDate,customerName,customerMobile,customerEmail,comments,confirmationId,
	Status,TransactionDate,sloteId,TableStructureID,case when MeargedTableid > 0 then 1 else 0 end as IsMearged from tblReservation 
	where sloteId=@Timeslotid and cast(reservationDate as date)=cast(@reservationDate as date)
	union all
	select id,reservationDate,customerName,customerMobile,customerEmail,comments,confirmationId,
	Status,TransactionDate,sloteId,MeargedTableid,1 as IsMearged from tblReservation 
	where sloteId=@Timeslotid and cast(reservationDate as date)=cast(@reservationDate as date) and MeargedTableid > 0
	) rs on rs.TableStructureID=tbl.Id 
	--left join tblReservationSlot slt on slt.id=rs.sloteId
	where tbl.DiningArea=@DiningArea and isnull(rs.id,0) =0 and tbl.Seating =@Seating 

END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetBindAssignGroupModifier]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetBindAssignGroupModifier]
@MainItemId int =0
AS
BEGIN
	select gmd.MainItemId,gmd.GroupId,GMM.Type as GroupTypeid
	from tblGroup_Modifier_Details gmd
	inner join tblGroup_Modifier_Master GMM on GMM.ID=gmd.GroupId
	where gmd.MainItemId=@MainItemId and gmd.Deleted!=1 
	group by gmd.MainItemId,gmd.GroupId,GMM.Type

	select gmd.MainItemId,gmd.GroupId,GMM.Type as GroupTypeid,gmd.ItemID 
	from tblGroup_Modifier_Details gmd
	inner join tblGroup_Modifier_Master GMM on GMM.ID=gmd.GroupId
	where gmd.MainItemId=@MainItemId and gmd.Deleted!=1 order by gmd.Seq_Num
END



GO
/****** Object:  StoredProcedure [dbo].[sp_GetBranchAndSectionList]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetBranchAndSectionList]
@BrandId int=0
AS
BEGIN
	select id,sectionName,SectionNameArabic from tblsection order by SequanceNo
	
	select id,branchName,branchNameAra,brandId,sectionId,Image as branchImg 
	from tblbranch where isnull(IsActive,0) =1 and isnull(IsDeleted,0)=0
	and case when @BrandId >0 then tblbranch.brandId else 1 end  = case when @BrandId >0 then @BrandId else 1 end 
	order by SEQ_NUM
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetBranchs]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetBranchs]
AS
BEGIN

	select br.id As BranchId,br.branchName,br.BranchNameAra,b.BrandID,b.BrandName,b.BrandNameAra from tblbranch br
	inner join tblBrand b on b.BrandID=br.brandid
	--where b.BrandID=@BrandId
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetBranchsBrandWise]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetBranchsBrandWise]
@BrandId int
AS
BEGIN

	select br.id As BranchId,br.branchName,br.BranchNameAra,isnull(br.IsActive,0) as IsActive
	--isnull(br.SEQ_NUM,0) as SEQ_NUM
	from tblbranch br
	inner join tblBrand b on b.BrandID=br.brandid
	where b.BrandID=@BrandId  and isnull(IsDeleted,0)=0  
	order by br.SEQ_NUM
	--and isnull(br.IsActive,0) =1
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetBranchTablesReservations]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetBranchTablesReservations]
@reservationDate datetime='2021-01-11',
@DiningArea nvarchar(50)='Inner Area',
@Timeslotid int=0
AS
BEGIN
	--Table List
	--select tbl.id,tbl.TableName,tbl.DiningArea,tbl.Seating,isnull(tbl.Xaxis,0) as Xaxis,isnull(tbl.Yaxis,0) as Yaxis ,
	--isnull(rs.id,0) as Reservationid,cast(rs.reservationDate as date) as reservationDate,rs.customerName,rs.customerMobile,rs.customerEmail,rs.comments,rs.confirmationId,rs.Status,rs.TransactionDate,
	--slt.slotName
	--from tblReservationTableStructure tbl
	--left join tblReservation rs on rs.TableStructureID=tbl.Id
	--left join tblReservationSlot slt on slt.id=rs.sloteId
	--where isnull(tbl.IsDeleted,0)=0 and slt.id=@Timeslotid
	--and tbl.DiningArea=@DiningArea

	--select tbl.id,tbl.TableName,tbl.DiningArea,tbl.Seating,isnull(tbl.Xaxis,0) as Xaxis,isnull(tbl.Yaxis,0) as Yaxis,
	--isnull(rs.id,0) as Reservationid,cast(rs.reservationDate as date) as reservationDate,rs.customerName,rs.customerMobile,rs.customerEmail,rs.comments,rs.confirmationId,rs.Status,rs.TransactionDate,
	--slt.slotName,slt.id
	--from tblReservationTableStructure tbl 
	--left join tblReservation rs on rs.TableStructureID=tbl.Id and sloteId=@Timeslotid and cast(reservationDate as date)=cast(@reservationDate as date)
	--left join tblReservationSlot slt on slt.id=rs.sloteId
	--where tbl.DiningArea=@DiningArea


	select tbl.id,tbl.TableName,tbl.DiningArea,tbl.Seating,isnull(tbl.Xaxis,0) as Xaxis,isnull(tbl.Yaxis,0) as Yaxis,
	isnull(rs.id,0) as Reservationid,cast(rs.reservationDate as date) as reservationDate,rs.customerName,rs.customerMobile,rs.customerEmail,rs.comments,rs.confirmationId,rs.Status,rs.TransactionDate,isnull(rs.IsMearged,0) as IsMearged,
	slt.slotName,slt.id
	from tblReservationTableStructure tbl 
	--left join tblReservation rs on rs.TableStructureID=tbl.Id and sloteId=@Timeslotid and cast(reservationDate as date)=cast(@reservationDate as date)
	left join (
	select id,reservationDate,customerName,customerMobile,customerEmail,comments,confirmationId,
	Status,TransactionDate,sloteId,TableStructureID,case when MeargedTableid > 0 then 1 else 0 end as IsMearged from tblReservation 
	where sloteId=@Timeslotid and cast(reservationDate as date)=cast(@reservationDate as date)
	union all
	select id,reservationDate,customerName,customerMobile,customerEmail,comments,confirmationId,
	Status,TransactionDate,sloteId,MeargedTableid,1 as IsMearged from tblReservation 
	where sloteId=@Timeslotid and cast(reservationDate as date)=cast(@reservationDate as date) and MeargedTableid > 0
	) rs on rs.TableStructureID=tbl.Id 
	left join tblReservationSlot slt on slt.id=rs.sloteId
	where tbl.DiningArea=@DiningArea

	----TimeSlot List
	--select id,slotName,slotNameArabic,fromTime,toTime from tblReservationSlot
	--where isnull(IsDeleted,0)=0
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetBrandBranchDetails]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_GetBrandBranchDetails]
@brandName varchar(1000),
@branchName varchar(1000),
@branchId int=null
AS
BEGIN
	if @branchId >0 
	begin
		set @brandName=(select top 1 brandname from tblbrand where BrandID in (select BrandID from tblbranch where id =@branchId))
		set @branchName =(select branchName from tblbranch where id =@branchId)
	end
	else if @brandName is null or @brandName =''
	begin
		set @brandName=(select top 1 brandname from tblbrand)
		set @branchName =(select top 1 branchName from tblbranch)
	end

	select bd.Brandid,isnull(bd.BannerImage,'') as BannerImage,
		isnull(bd.MobileImage,'') as MobileImage,
		isnull(DesktopImage,'') as DesktopImage,
		isnull(Css,'') as Css,
		case when @branchName !='' then 
					(select top 1 id from tblbranch where branchName=@branchName and BrandID=bd.BrandID and IsDeleted!=1 and IsActive=1) 
			  else  (select top 1 id from tblbranch where BrandID=bd.BrandID and IsDeleted!=1  and IsActive=1) end as BranchId,
		isnull(IsItemDetailsBackToCategory,1) as IsItemDetailsBackToCategory
	from tblBrand bd where bd.BrandName=@brandName
END
GO
/****** Object:  StoredProcedure [dbo].[sp_GetBrandHomePageImage]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetBrandHomePageImage]
@BrandId int=0
AS
BEGIN
	select BrandHomePageImage,Facebook,Instagram,WhatsAppURL,Currency,CurrencyArabic,
	ExpiryDate,case when ExpiryDate is not null and cast(ExpiryDate as datetime) < GETDATE() then 1 else 0 end as IsExpired,
	Email,EmailReminderContent,EmailReminderCount,ContactDetails,Layout,Alert,
	isnull(IsCartVisible,0) as IsCartVisible,
	isnull(PopupBannerImage,'') as PopupBannerImage,
	isnull(FeedBack,0) as IsFeedBack,
	isnull(ShowAllergen,0) as IsShowAllergen,
	isnull(WaiterLayout,'Design1') WaiterLayout,isnull(DecimalPlaces,3) DecimalPlaces
	from tblBrand where BrandID=
	case when @BrandId = 0 then (select top 1 BrandID from tblBrand) else @BrandId end
END



GO
/****** Object:  StoredProcedure [dbo].[sp_GetBrandHomePaggeImage]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetBrandHomePaggeImage]
@BrandId int=0
AS
BEGIN
	select BrandHomePageImage from tblBrand where BrandID=
	case when @BrandId = 0 then (select top 1 BrandID from tblBrand) else @BrandId end
END
GO
/****** Object:  StoredProcedure [dbo].[sp_GetBrandImages]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetBrandImages]
    @BrandId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT BannerImage, DesktopImage
    FROM   dbo.tblbrand
    WHERE  BrandID = @BrandId;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetBrands]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetBrands]
@WaiterID int
AS
BEGIN

declare @isAdmin bit

set @isAdmin=(select case when roleid=1 then 1 else 0 end Role from tblUser where ID=@WaiterID)

if(@isAdmin=1)
begin

	select b.BrandID,b.Theme,b.BrandImage,b.BrandName,b.BrandNameAra,b.BrandSeq,b.Russian,b.Mandarin,isnull(b.IsOtherLanguages,'') IsOtherLanguages
   ,t.ThemeName,b.url as brandUrl from tblBrand b inner join tblTheme t on t.ThemeID=b.Theme

end
else

begin
declare @BrandID nvarchar(50)

set @BrandID=(select BrandID from tblUser where ID=@WaiterID)

select b.BrandID,b.Theme,b.BrandImage,b.BrandName,b.BrandNameAra,b.BrandSeq,b.Russian,b.Mandarin,isnull(b.IsOtherLanguages,'') IsOtherLanguages
   ,t.ThemeName,b.url as brandUrl from tblBrand b inner join tblTheme t on t.ThemeID=b.Theme  where BrandID in(select cast(item as integer) from dbo.splitstring(@BrandID,','))

end

END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetBrandsMobile]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetBrandsMobile]
@Password nvarchar (max)
as
if exists(select 1 from tblSetting where PASSWORD=@Password )
begin
	select br.id as BrandID,br.branchName as BrandName,br.id as BrandSeq,br.branchNameAra as BrandNameAra,BrandImage,Theme,Russian
	,Mandarin,FeedBack,Currency,isnull(Telephone,'') Telephone,isnull(Facebook,'')Facebook,isnull(Instagram,'')Instagram,ShowPromotion
	,isnull(IsOtherLanguages,0) as IsOtherLanguages,t.ThemeName,tblSetting.ordertaking 
	,isnull(t.categoryActive,'')categoryActive
	,isnull(t.categoryInActive,'')categoryInActive
	,isnull(t.setting,'')setting
	,isnull(t.englishButton,'')englishButton
	,isnull(t.arabicButton,'')arabicButton
	,isnull(t.mandarinButton,'')mandarinButton
	,isnull(t.russianButton,'')russianButton
	,isnull(t.closeButton,'')closeButton
	,isnull(t.homeScreen,'')homeScreen
	,isnull(t.popUpBackground,'')popUpBackground
	,isnull(t.SeperatorLine,'')SeperatorLine
	,isnull(t.leftArrow,'')leftArrow
	,isnull(t.leftBottom,'')leftBottom
	,isnull(t.leftTop,'')leftTop
	,isnull(t.rightArrow,'')rightArrow
	,isnull(t.RightButton,'')RightButton
	,isnull(t.rightTop,'')rightTop
	,isnull(t.FontColor,'')FontColor
	,isnull(t.FontColorItemName,'')FontColorItemName
	,isnull(t.FontColorIngName,'')FontColorIngName
	,isnull(t.FontColorPrice,'')FontColorPrice
	,isnull(t.itemBackgroundColor,'')itemBackgroundColor
	from tblBrand b 
	RIGHT OUTER JOIN dbo.tblbranch br ON b.BrandID = br.brandId
	inner join tblTheme t on t.ThemeID=b.Theme
	inner join tblsetting on 1=1
end
else
begin
	return 0
end


GO
/****** Object:  StoredProcedure [dbo].[sp_GetCartItemChoicesExtraCommentList]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetCartItemChoicesExtraCommentList]
@BrandId int=0,
@Branchid int=0,
--@dttblCartItems [DT_tblCartItems] readonly
@dttblCartItems [DT_tblCartItemsWithUID] readonly,
@dttblCartChoices [DT_tblChoiceItems] readonly,
@dttblCartExtraItems [DT_tblExtraItems] readonly,
@dttblCartComments [DT_tblComments] readonly
AS
BEGIN
	select distinct dt.UID, i.id,c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,i.ITEM_NAME,
	case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
	(select top 1 currency from tblBrand order by brandid) end as Currency,
	(isnull(i.PRICE,0) + isnull(chItem.PRICE,0))  as PRICE, 
	i.ITEM_NAME_ARABIC,
	i.INGREDIENT,i.INGREDIENT_ARABIC,i.ImageName,dt.qty,
	cast(((isnull(i.PRICE,0) + isnull(chItem.PRICE,0))  * dt.qty) as nvarchar(10)) as TotalPrice,i.HID,dt.Comments,
	i.Video
	,chItem.ITEM_NAME as ChoiceName
	,chItem.ITEM_NAME_ARABIC as ChoiceName_ARABIC
	from tblItems i
	inner join @dttblCartItems dt on dt.ItemId=i.ID
	inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
	left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM
	left join Assign_Item as ai on ai.ItemId=i.ID
	left join tblItems as chItem  on chItem.id=dt.choiceid
	where c.ShowInTablet =1 
	and case when @BrandId = 0 then 0 else ai.BrandID end= @BrandId and
	case when @Branchid = 0 then 0 else ai.BranchId end= @Branchid 
	and case when @Branchid =0 then 0 else ac.BranchId end =@Branchid


	------- select choices
	select ch.UID,ch.ChoiceItemId,ch.GroupId,ch.MainItemId,it.Price,it.ITEM_NAME as ItemName 
	from tblGroup_Modifier_Details ms 
	inner join @dttblCartChoices ch on ch.ChoiceItemId=ms.ItemID and ch.MainItemId=ms.MainItemId and ch.GroupId=ms.GroupId
	inner join tblitems it on ch.ChoiceItemId=it.ID
	where ms.Deleted!=1
	order by ms.Seq_Num

	------- select ExtraItems
	select ch.UID,ch.ExtraItemId,ch.GroupId,ch.MainItemId,it.Price,it.ITEM_NAME as ItemName 
	from tblGroup_Modifier_Details ms 
	inner join @dttblCartExtraItems ch on ch.ExtraItemId=ms.ItemID and ch.MainItemId=ms.MainItemId and ch.GroupId=ms.GroupId
	inner join tblitems it on ch.ExtraItemId=it.ID
	where ms.Deleted!=1
	order by ms.Seq_Num

	------- select Comments
	select UID,CommentId,MainItemId,Comment from @dttblCartComments
	--select ch.UID,ch.ChoiceItemId,ch.GroupId,ch.MainItemId,it.Price,it.ItemName 
	--from tblGroup_Modifier_Details ms 
	--inner join @dttblCartComments ch on ch.CommentId=ms.ItemID and ch.MainItemId=ms.MainItemId and ch.GroupId=ms.GroupId
	--inner join tblcomments cm on cm.id=ms.ItemID
	--where ms.Deleted!=1

END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetCartItemList]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetCartItemList]
@BrandId int=0,
@Branchid int=0,
--@dttblCartItems [DT_tblCartItems] readonly
@dttblCartItems [DT_tblCartItemsWithUID] readonly
AS
BEGIN
	select distinct dt.UID, i.id,c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,i.ITEM_NAME,
	case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
	(select top 1 currency from tblBrand order by brandid) end as Currency,
	--case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
	--	(select top 1 currency from tblBrand order by brandid) end +'. '+

	--cast((case when dt.ChoiceId > 0 then
	--chItem.PRICE else i.PRICE end) as nvarchar(10)) as PRICE, 
	--isnull(chItem.PRICE,i.PRICE)  as PRICE, 
	(isnull(i.PRICE,0) + isnull(chItem.PRICE,0))  as PRICE, 


	i.ITEM_NAME_ARABIC,
	i.INGREDIENT,i.INGREDIENT_ARABIC,i.ImageName,dt.qty,
	--case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
	--	(select top 1 currency from tblBrand order by brandid) end +'. '+
	cast(((isnull(i.PRICE,0) + isnull(chItem.PRICE,0))  * dt.qty) as nvarchar(10)) as TotalPrice,i.HID,dt.Comments,
	i.Video
	,chItem.ITEM_NAME as ChoiceName
	,chItem.ITEM_NAME_ARABIC as ChoiceName_ARABIC,
	dt.CartItemUniqID, dt.ParentItemID
	from tblItems i
	inner join @dttblCartItems dt on dt.ItemId=i.ID
	inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
	left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM
	left join Assign_Item as ai on ai.ItemId=i.ID
	left join tblItems as chItem  on chItem.id=dt.choiceid
	where c.ShowInTablet =1 
	--and i.CAT_NUM=@CAT_NUM
	and case when @BrandId = 0 then 0 else ai.BrandID end= @BrandId and
	case when @Branchid = 0 then 0 else ai.BranchId end= @Branchid 
	and case when @Branchid =0 then 0 else ac.BranchId end =@Branchid

	select top 1 BrandID from tblBrand order by BrandID 
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetCategory]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetCategory]
@WaiterID int,
@BrandID int
AS
BEGIN

declare @isAdmin bit

set @isAdmin=(select case when roleid=1 then 1 else 0 end Role from tblUser where ID=@WaiterID)

if(@isAdmin=1 and @BrandID=0)
begin

	select distinct c.CAT_NUM,c.CAT_NAME,c.SEQ_NUM,c.ShowInTablet,c.CAT_NAME_ARABIC,c.CatNameRus,c.CatNameMan
	,c.MainCategory, --a.BrandID 
	isnull(a.BrandID,0) BrandID
	,b.BrandName
	,1 as IsOtherLanguages

	,cl.chinese as CategoryName_chinese
	,cl.turkish as CategoryName_turkish
	,cl.hindi as CategoryName_hindi
	,cl.korean as CategoryName_korean
	,cl.spain as CategoryName_spain
	,cl.bangladeshi as CategoryName_bangladeshi
	,cl.srilanka as CategoryName_srilanka
	,cl.iranian as CategoryName_iranian
	,cl.italian as CategoryName_italian
	,cl.urdu as CategoryName_urdu
	,cl.philippines as CategoryName_philippines
	,cl.french as CategoryName_french
	,cl.germany as CategoryName_germany
	from tblCategory c 
	left join Assign_Cat a on c.CAT_NUM=a.CatNum 
	left join tblBrand b on a.BrandID= b.BrandID
	left join tblCategoryName_Languages cl on cl.CAT_NUM=c.CAT_NUM
	order by SEQ_NUM asc
	
end
else
set @BrandID= (select BrandID from tblUser where id=@WaiterID)
begin

			if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
			begin
				select distinct c.CAT_NUM,c.CAT_NAME,c.SEQ_NUM,c.ShowInTablet,c.CAT_NAME_ARABIC,c.CatNameRus,c.CatNameMan
				,c.MainCategory, isnull(a.BrandID,0) BrandID,b.BrandName
				,1 as IsOtherLanguages
				,cl.chinese as CategoryName_chinese
				,cl.turkish as CategoryName_turkish
				,cl.hindi as CategoryName_hindi
				,cl.korean as CategoryName_korean
				,cl.spain as CategoryName_spain
				,cl.bangladeshi as CategoryName_bangladeshi
				,cl.srilanka as CategoryName_srilanka
				,cl.iranian as CategoryName_iranian
				,cl.italian as CategoryName_italian
				,cl.urdu as CategoryName_urdu
				,cl.philippines as CategoryName_philippines
				,cl.french as CategoryName_french
				,cl.germany as CategoryName_germany
				
				from tblCategory  c 
				left join Assign_Cat a on c.CAT_NUM=a.CatNum 
				left join tblBrand b on a.BrandID= b.BrandID
				left join tblCategoryName_Languages cl on cl.CAT_NUM=c.CAT_NUM
				where a.BrandID=@BrandID or a.BrandID is null order by SEQ_NUM asc
			end
			else begin
				select distinct c.CAT_NUM,c.CAT_NAME,c.SEQ_NUM,c.ShowInTablet,c.CAT_NAME_ARABIC,c.CatNameRus,c.CatNameMan
				,c.MainCategory, isnull(a.BrandID,0) BrandID,b.BrandName
				,0 as IsOtherLanguages
				,cl.chinese as CategoryName_chinese
				,cl.turkish as CategoryName_turkish
				,cl.hindi as CategoryName_hindi
				,cl.korean as CategoryName_korean
				,cl.spain as CategoryName_spain
				,cl.bangladeshi as CategoryName_bangladeshi
				,cl.srilanka as CategoryName_srilanka
				,cl.iranian as CategoryName_iranian
				,cl.italian as CategoryName_italian
				,cl.urdu as CategoryName_urdu
				,cl.philippines as CategoryName_philippines
				,cl.french as CategoryName_french
				,cl.germany as CategoryName_germany
				
				from tblCategory  c 
				left join Assign_Cat a on c.CAT_NUM=a.CatNum 
				left join tblBrand b on a.BrandID= b.BrandID
				left join tblCategoryName_Languages cl on cl.CAT_NUM=c.CAT_NUM
				where a.BrandID=@BrandID or a.BrandID is null order by SEQ_NUM asc
			
			end
	
end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetCategoryBranchwise]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetCategoryBranchwise]
@BrandID int,
@branchid int
AS
BEGIN
	select  c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC from tblCategory c 
	inner join Assign_Cat ac on ac.CatNum=c.CAT_NUM
	where ac.BranchId= @branchid and ac.BrandID=@BrandID
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetCategoryDetails]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetCategoryDetails]
@CAT_NUM int=0
AS
BEGIN
	--select distinct c.CAT_NUM,c.CAT_NAME,c.SEQ_NUM, c.ShowInTablet, c.CAT_NAME_ARABIC, c.CatNameRus, c.CatNameMan, c.MainCategory, c.IsActive, 
	--ac.BranchId
	--from tblCategory c
	--left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM
	--where c.CAT_NUM = @CAT_NUM

	select c.CAT_NUM,c.CAT_NAME,c.SEQ_NUM, c.ShowInTablet, c.CAT_NAME_ARABIC, c.CatNameRus, c.CatNameMan, c.MainCategory, c.IsActive
	from tblCategory c
	where c.CAT_NUM = @CAT_NUM

	select BranchId from Assign_Cat where CatNum=@CAT_NUM
END



GO
/****** Object:  StoredProcedure [dbo].[sp_GetCategoryDragDrop]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetCategoryDragDrop]
@BrandId int=0,
@Branchid int=0,
@MainCategoryId int=0,
@isSubcategoryProject int=0
AS
BEGIN
set @BrandId= case when @BrandId=0 then 1 else @BrandId end
--set @Branchid= case when @Branchid=0 then 1 else @Branchid end


if @isSubcategoryProject =0
begin
	select distinct c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,
	
	IsNull((select top 1 i.IMAGENAME from tblitems i 
	left join Assign_Item as ai on ai.ItemId=i.ID
	where i.CAT_NUM=c.CAT_NUM and i.ShowInTablet=1 
	--and case when @Branchid = 0 then 0 else ai.BranchId end= @Branchid
	and isnull(isExtra,0) =0 and isnull(Ischoice,0) =0 
	order by i.Seq_Num), 'no_image.png') ImageName

	,c.SEQ_NUM,isnull(ShowInTablet,1) as ShowInTablet
	,c.MainCategory
	, case when (select count(cat_name) from tblCategory where MainCategory=c.CAT_NUM) > 0 then 1 else 0 end as IsHaveSubCategory 
	
	from tblCategory c 
	where c.BrandId= @BrandId
	--where isnull(c.MainCategory,0) =0
	--left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM
	--where 
	--c.ShowInTablet =1 and 
	--case when @BrandId = 0 then 0 else ac.BrandID end= @BrandId 
	--and case when @Branchid =0 then 0 else ac.BranchId end =@Branchid
	order by c.SEQ_NUM
end
else
begin
	select distinct c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,
	
	IsNull((select top 1 i.IMAGENAME from tblitems i 
	left join Assign_Item as ai on ai.ItemId=i.ID
	where i.CAT_NUM=isnull((select top 1 aa.CAT_NUM from tblCategory aa where MainCategory=c.CAT_NUM order by Seq_Num),c.CAT_NUM)
	and i.ShowInTablet=1 
	and isnull(isExtra,0) =0 and isnull(Ischoice,0) =0 
	--and case when @Branchid = 0 then 0 else ai.BranchId end= @Branchid
	order by i.Seq_Num), 'no_image.png') ImageName

	,c.SEQ_NUM,isnull(ShowInTablet,1) as ShowInTablet
	,c.MainCategory
	, case when (select count(cat_name) from tblCategory where MainCategory=c.CAT_NUM) > 0 then 1 else 0 end as IsHaveSubCategory 
	
	from tblCategory c 
	left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM
	where isnull(c.MainCategory,0) =@MainCategoryId and
	c.ShowInTablet =1 and 
	--case when @BrandId = 0 then 0 else ac.BrandID end= @BrandId
	c.BrandId= @BrandId
	and case when @Branchid  > 0 then ac.BranchId else 0 end = case when @Branchid  > 0 then @Branchid else 0 end
	order by c.SEQ_NUM
end
END
GO
/****** Object:  StoredProcedure [dbo].[sp_GetCategoryList]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetCategoryList]
@BrandId int=0,
@Branchid int=0,


@IPAddress nVarchar(50) = '',
@BrowserName nVarchar(100) = '',
@DeviceModal nVarchar(50) = '',
@DeviceManufacturer nVarchar(50) = '',

@MainCategoryId int=0,
@isSubcategoryProject int=0

AS
BEGIN
set @BrandId= case when @BrandId=0 then 1 else @BrandId end
set @Branchid= case when @Branchid=0 then (select top 1 id from tblbranch where brandId=@BrandId and IsDeleted=0 and IsActive=1) else @Branchid end

if @isSubcategoryProject =0
begin
	select distinct c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,
	IsNull((select top 1 i.IMAGENAME from tblitems i 
	left join Assign_Item as ai on ai.ItemId=i.ID
	where i.CAT_NUM=c.CAT_NUM and i.ShowInTablet=1 
	and case when @Branchid = 0 then 0 else ai.BranchId end= @Branchid
	order by i.Seq_Num), 'no_image.png') ImageName

	,c.SEQ_NUM
	,c.MainCategory
	, case when (select count(cat_name) from tblCategory where MainCategory=c.CAT_NUM) > 0 then 1 else 0 end as IsHaveSubCategory
	from tblCategory c 
	left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM
	where c.ShowInTablet =1 and c.IsActive!=0
	and case when @BrandId = 0 then 0 else ac.BrandID end= @BrandId 
	and case when @Branchid =0 then 0 else ac.BranchId end =@Branchid
	order by c.SEQ_NUM
end
else
begin
	select distinct c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,
		IsNull((select top 1 i.IMAGENAME from tblitems i 
	left join Assign_Item as ai on ai.ItemId=i.ID
	where i.CAT_NUM=isnull((select top 1 aa.CAT_NUM from tblCategory aa where MainCategory=c.CAT_NUM order by Seq_Num),c.CAT_NUM)
	and i.ShowInTablet=1 
	--un comment on 24-3-2022 for branch wise category thumbnain display
	and case when @Branchid = 0 then 0 else ai.BranchId end= @Branchid
	order by i.Seq_Num), 'no_image.png') ImageName
	,c.SEQ_NUM
	,c.MainCategory
	, case when (select count(cat_name) from tblCategory where IsActive!=0 and MainCategory=c.CAT_NUM) > 0 then 1 else 0 end as IsHaveSubCategory
	from tblCategory c 
	left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM
	where c.ShowInTablet =1 and c.IsActive!=0
	and c.MainCategory=@MainCategoryId
	and case when @BrandId = 0 then 0 else ac.BrandID end= @BrandId 
	and case when @Branchid =0 then 0 else ac.BranchId end =@Branchid
	order by c.SEQ_NUM
end
	


	select distinct i.id,c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,i.ITEM_NAME,
		case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
		(select top 1 currency from tblBrand order by brandid) end as Currency, 
		cast(i.PRICE as nvarchar(10)) as PRICE,
		i.ITEM_NAME_ARABIC,
		i.INGREDIENT,i.INGREDIENT_ARABIC,
		i.ImageName,i.HID,
		i.Seq_Num,i.Video,
		isnull((select max(gm.MinSelect) from tblgroup_modifier_master gm inner join tblGroup_Modifier_Details ie on ie.GroupId=gm.ID
			where ie.MainItemId=i.ID and gm.type=2  and ie.deleted !=1),0) as MinGroupModifierSelection
		from tblItems i 
		inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
		left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM
		left join Assign_Item as ai on ai.ItemId=i.ID
		where c.ShowInTablet =1 and i.ShowInTablet=1 and 
		case when @BrandId = 0 then 0 else ai.BrandID end= @BrandId and
		case when @Branchid = 0 then 0 else ai.BranchId end= @Branchid and
		i.CAT_NUM=case when @MainCategoryId =0 then
		(select top 1 c.cat_num from tblCategory c
		left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM
		where 
		c.IsActive !=0 and
		case when @BrandId = 0 then 0 else ac.BrandID end= @BrandId 
		and case when @Branchid =0 then 0 else ac.BranchId end =@Branchid
		order by c.Seq_Num) else @MainCategoryId end  order by i.Seq_Num


		select distinct c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,
		IsNull((select top 1 i.IMAGENAME from tblitems i 
		left join Assign_Item as ai on ai.ItemId=i.ID
		where i.CAT_NUM=isnull((select top 1 aa.CAT_NUM from tblCategory aa where MainCategory=c.CAT_NUM order by Seq_Num),c.CAT_NUM)
		and i.ShowInTablet=1 
		--un comment on 24-3-2022 for branch wise category thumbnain display
		and case when @Branchid = 0 then 0 else ai.BranchId end= @Branchid
		order by i.Seq_Num), 'no_image.png') ImageName
		,c.SEQ_NUM
		,c.MainCategory
		, case when (select count(cat_name) from tblCategory where MainCategory=c.CAT_NUM) > 0 then 1 else 0 end as IsHaveSubCategory
		from tblCategory c 
		left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM
		where c.ShowInTablet =1 and c.IsActive!=0
		and c.MainCategory =(select top 1 cat_num from tblCategory where IsActive!=0)
		and case when @BrandId = 0 then 0 else ac.BrandID end= @BrandId 
		and case when @Branchid =0 then 0 else ac.BranchId end =@Branchid
		order by c.SEQ_NUM
	
	IF @Branchid <> 0
	Begin
		Declare @BranchName Varchar(50)
		Select @BranchName = branchName From tblbranch Where id = @Branchid
		Exec [sp_UpdateAuditDetails] @IPAddress, @BrowserName, @DeviceModal, @DeviceManufacturer, 1, @Branchid, @BranchName, @Branchid
	End
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetCategoryMobile]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetCategoryMobile]

@BrandID int=0
AS
BEGIN


--SELECT [CAT_NUM]
--      ,[CAT_NAME]
--      ,[SEQ_NUM]
--      ,[ShowInTablet]
--      ,[CAT_NAME_ARABIC]
--      ,@BrandID
--      ,isnull([CatNameRus],'') as [CatNameRus]
--	  ,isnull([CatNameMan],'') as [CatNameMan]
--	  ,MainCategory
--       FROM tblCategory 
--	   where CAT_NUM in (select catnum from assign_cat where BrandID=@BrandID) and ShowInTablet=1 order by SEQ_NUM



SELECT tblCategory.[CAT_NUM]
      ,tblCategory.[CAT_NAME]
      ,tblCategory.[SEQ_NUM]
      ,tblCategory.[ShowInTablet]
      ,tblCategory.[CAT_NAME_ARABIC]
      ,@BrandID
      ,isnull(tblCategory.[CatNameRus],'') as [CatNameRus]
	  ,isnull(tblCategory.[CatNameMan],'') as [CatNameMan]
	  ,tblCategory.MainCategory

	  ,isnull(CatLang.chinese,'') as CategoryName_chinese
	  ,isnull(CatLang.turkish,'') as CategoryName_turkish
	  ,isnull(CatLang.hindi,'') as CategoryName_hindi
	  ,isnull(CatLang.korean,'') as CategoryName_korean
	  ,isnull(CatLang.spain,'') as CategoryName_spain
	  ,isnull(CatLang.bangladeshi,'') as CategoryName_bangladeshi
	  ,isnull(CatLang.srilanka,'') as CategoryName_srilanka
	  ,isnull(CatLang.iranian,'') as CategoryName_iranian
	  ,isnull(CatLang.italian,'') as CategoryName_italian
	  ,isnull(CatLang.urdu,'') as CategoryName_urdu
	  ,isnull(CatLang.philippines,'') as CategoryName_philippines
	  ,isnull(CatLang.french,'') as CategoryName_french
	  ,isnull(CatLang.germany,'') as CategoryName_germany

       FROM tblCategory 
	   left join tblCategoryName_Languages CatLang on CatLang.CAT_NUM=tblCategory.CAT_NUM
	   where tblCategory.CAT_NUM in (select catnum from assign_cat where branchid=@BrandID) and ShowInTablet=1 order by SEQ_NUM

END
GO
/****** Object:  StoredProcedure [dbo].[sp_GetCategoryVisits]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
CREATE PROCEDURE [dbo].[sp_GetCategoryVisits]
	-- Add the parameters for the stored procedure here
	@BrandId int =0,
	@FromDate Date = Null,
	@ToDate Date = Null
AS
BEGIN
	--select * from(
	--	Select  
	--	tc.CAT_NAME, 
	--	--Count(tad.ID) As VisitorsCount
	--	(select count(tad.id) from tblAuditDetails tad
	--	left outer Join tblAudit ta on ta.ID = tad.AuditID
	--	left outer join tblbranch b on b.id=ta.BranchId
	--	left outer join tblBrand bd on bd.BrandID=b.brandId
	--	where tad.ItemSelectionName = tc.CAT_NAME And tad.ItemSelectionType = 2 and
	--	(Cast(tad.CreatedOn As Date) Between Cast(@FromDate As Date) AND Cast(@ToDate  As Date) or tad.CreatedOn is null) and 
	--	bd.BrandID=@BrandId and b.IsActive=1 and isnull(b.IsDeleted,0) =0
	--	) as VisitorsCount
	--	From tblCategory tc )cate
	--	order by VisitorsCount desc,CAT_NAME

	;with cte as(
	select ta.IPAddress as IPAddress, count(tad.ItemSelectionID) as Visits,
	c.CAT_NAME
	from tblAuditDetails  tad
	left outer Join tblAudit ta on ta.ID=tad.AuditID
	left outer Join tblbranch b on b.id=ta.BranchId
	left outer Join tblBrand bd on bd.BrandID=b.brandId
	left outer Join tblCategory c on c.CAT_NUM=tad.ItemSelectionID
	where Cast(tad.CreatedOn As Date) between cast(@FromDate as date) and cast(@ToDate as date)
	and tad.ItemSelectionType = 2 and bd.BrandID=@BrandId and b.IsActive=1 and isnull(b.IsDeleted,0) =0
	group by ta.IPAddress,ItemSelectionID,c.CAT_NAME
	) 
	select CAT_NAME, count(visits) as VisitorsCount from cte group by CAT_NAME order by count(visits) desc
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetCategoryWiseItemList]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetCategoryWiseItemList]
@BrandId int=0,
@Branchid int=0,
@CAT_NUM int=0,


@IPAddress nVarchar(50) = '',
@BrowserName nVarchar(100) = '',
@DeviceModal nVarchar(50) = '',
@DeviceManufacturer nVarchar(50) = ''

AS
BEGIN

	set @BrandId= case when @BrandId=0 then 1 else @BrandId end
	set @Branchid= case when @Branchid=0 then 1 else @Branchid end

	select distinct i.id,c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,i.ITEM_NAME,
	case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
		(select top 1 currency from tblBrand order by brandid) end as Currency, 
	cast(i.PRICE as nvarchar(10)) as PRICE,
	i.ITEM_NAME_ARABIC,
	i.INGREDIENT,i.INGREDIENT_ARABIC,i.ImageName,i.HID,i.Seq_Num,i.Video,
	isnull((select max(gm.MinSelect) from tblgroup_modifier_master gm inner join tblGroup_Modifier_Details ie on ie.GroupId=gm.ID
			where ie.MainItemId=i.ID and gm.type=2  and ie.deleted !=1),0) as MinGroupModifierSelection
	from tblItems i
	inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
	inner join Assign_Cat as ac on ac.CatNum=c.CAT_NUM and case when @Branchid =0 then 0 else ac.BranchId end =@Branchid 
	inner join Assign_Item as ai on ai.ItemId=i.ID
	and case when @BrandId = 0 then 0 else ai.BrandID end= @BrandId and  
	case when @Branchid = 0 then 0 else ai.BranchId end= @Branchid 
	where c.ShowInTablet =1 and i.ShowInTablet=1 and i.CAT_NUM=@CAT_NUM
	and isnull(i.Ischoice,0) =0 and isnull(i.isExtra,0) =0
	order by i.Seq_Num 

	select it.id as itemId,a.id as allergenId,a.name as allergenName,a.Name_arabic as allergenNameArabic,a.image
	--, it.item_name,c.cat_name,c.CAT_NUM 
	from tbl_Allergen a
	inner join tbl_Allergen_Assign aa on a.id=aa.allergenid
	inner join tblItems it on aa.itemid=it.id
	inner join tblCategory c on c.cat_num=it.cat_num
	where c.CAT_NUM=@CAT_NUM

	Declare @CAT_NAME Varchar(50)
	Select @CAT_NAME = CAT_NAME From tblCategory Where CAT_NUM = @CAT_NUM
	Exec [sp_UpdateAuditDetails] @IPAddress, @BrowserName, @DeviceModal, @DeviceManufacturer, 2, @CAT_NUM, @CAT_NAME, @Branchid

	--Update 19th Nov. 2020.
	--Left Outer join conditions should not be into Where condition

	--	select distinct i.id,c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,i.ITEM_NAME,
	--case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
	--	(select top 1 currency from tblBrand order by brandid) end as Currency, 
	--cast(i.PRICE as nvarchar(10)) as PRICE,
	--i.ITEM_NAME_ARABIC,
	--i.INGREDIENT,i.INGREDIENT_ARABIC,i.ImageName,i.HID,i.Seq_Num
	--from tblItems i
	--inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
	--left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM
	--left join Assign_Item as ai on ai.ItemId=i.ID
	--where c.ShowInTablet =1 and i.ShowInTablet=1 and i.CAT_NUM=@CAT_NUM
	--and case when @BrandId = 0 then 0 else ai.BrandID end= @BrandId and  
	--case when @Branchid = 0 then 0 else ai.BranchId end= @Branchid 
	--and case when @Branchid =0 then 0 else ac.BranchId end =@Branchid order by i.Seq_Num

END
GO
/****** Object:  StoredProcedure [dbo].[sp_GetCategoryWiseItemListDragDrop]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetCategoryWiseItemListDragDrop]
@BrandId int=0,
@Branchid int=0,
@CAT_NUM int=0
AS
BEGIN

	set @BrandId= case when @BrandId=0 then 1 else @BrandId end
	set @Branchid= case when @Branchid=0 then 1 else @Branchid end

	select distinct i.id,c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,i.ITEM_NAME,
	case when @BrandId > 0 then (select top 1 currency from tblBrand where BrandID=@BrandId) else
	(select top 1 currency from tblBrand order by brandid) end as Currency,
	cast(i.PRICE as nvarchar(10)) as PRICE,
	i.ITEM_NAME_ARABIC,
	i.INGREDIENT,i.INGREDIENT_ARABIC,isnull(i.ImageName,'no_image.png') as ImageName,i.HID,i.Seq_Num,isnull(i.ShowInTablet,1) as ShowInTablet, i.isExtra
	from tblItems i
	inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
	left join Assign_Cat as ac on ac.CatNum=c.CAT_NUM --and case when @Branchid =0 then 0 else ac.BranchId end =@Branchid
	left join Assign_Item as ai on ai.ItemId=i.ID
	--and case when @BrandId = 0 then 0 else ai.BrandID end= @BrandId and
	--case when @Branchid = 0 then 0 else ai.BranchId end= @Branchid
	where i.CAT_NUM=@CAT_NUM
	and isnull(isExtra,0) =0 and isnull(Ischoice,0) =0 
	order by i.Seq_Num

	select isnull(ShowAllergen,0) ShowAllergen from tblBrand where BrandID=@BrandId

END
GO
/****** Object:  StoredProcedure [dbo].[sp_GetChoicesItemsWise]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetChoicesItemsWise]
@choiceId int
AS
BEGIN
	select ic.ItemId as ItemId from tblItem_choices ic 
	where ic.ChoiceId= @choiceId
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetComments]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetComments]
AS
BEGIN
	select id,comments_eng,comments_arb from tblcomments
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetDashboardLateOrdersData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_GetDashboardLateOrdersData]
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();
    IF @LateMinDuration IS NULL SET @LateMinDuration = 70;

    DECLARE @MaxDuration INT = 1440;   -- a day. Beyond that it is bad data.

    ;WITH steps AS (
        SELECT   h.InvoiceNo
               , Step = DENSE_RANK() OVER (PARTITION BY h.InvoiceNo ORDER BY ISNULL(s.SortOrder, h.ToStatusID))
               , h.ChangedOn
               , s.OrderStatusName
               , IsTerminal = ISNULL(s.IsTerminal, 0)
        FROM     dbo.tblPOS_OrderStatusHistory h WITH (NOLOCK)
        LEFT JOIN dbo.tblOrderStatus s WITH (NOLOCK) ON s.OrderStatusID = h.ToStatusID
    )
    SELECT   BranchName        = ISNULL(b.branchName, N'-')
           , [Invoice No]      = i.InvoiceNo
           , [Bill Amount]     = CAST(i.FinalAmount + ISNULL(i.DeliveryCharges,0) AS DECIMAL(18,3))
           , [Order Received]  = FORMAT(i.InvoiceDate, 'dd-MMM-yy hh:mm tt')
           , [In Kitchen]      = FORMAT(k.ChangedOn, 'hh:mm tt')
           , [Ready]           = FORMAT(r.ChangedOn, 'hh:mm tt')
           , [Closed]          = FORMAT(f.ChangedOn, 'hh:mm tt')
           , [Closed Status]   = f.OrderStatusName
           , [Total Minutes]   = DATEDIFF(MINUTE, i.InvoiceDate, f.ChangedOn)
    FROM     dbo.tblInvoice i WITH (NOLOCK)
    LEFT JOIN dbo.tblbranch b WITH (NOLOCK) ON b.id = i.BranchID
    OUTER APPLY (SELECT TOP 1 ChangedOn FROM steps WHERE InvoiceNo = i.InvoiceNo AND Step = 2 ORDER BY ChangedOn) k
    OUTER APPLY (SELECT TOP 1 ChangedOn FROM steps WHERE InvoiceNo = i.InvoiceNo AND Step = 3 ORDER BY ChangedOn) r
    OUTER APPLY (SELECT TOP 1 ChangedOn, OrderStatusName FROM steps
                 WHERE InvoiceNo = i.InvoiceNo AND IsTerminal = 1 ORDER BY ChangedOn DESC) f
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    i.InvoiceDate >= CAST(@FromDate AS DATE)
      AND    i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
      AND    f.ChangedOn IS NOT NULL
      AND    DATEDIFF(MINUTE, i.InvoiceDate, f.ChangedOn) >= @LateMinDuration
      AND    DATEDIFF(MINUTE, i.InvoiceDate, f.ChangedOn) <= @MaxDuration
      AND    (NULLIF(@BranchIds, '') IS NULL
              OR i.BranchID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')))
    ORDER BY [Total Minutes] DESC, i.InvoiceNo DESC;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetDashboardTopItemsSummaryData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_GetDashboardTopItemsSummaryData]
      @CountryId       INT            = NULL
    , @FromDate        DATETIME       = NULL
    , @ToDate          DATETIME       = NULL
    , @BranchIds       NVARCHAR(1000) = NULL
    , @BrandIds        NVARCHAR(1000) = NULL
    , @InvoiceTypeIds  NVARCHAR(1000) = NULL
    , @PaymentTypeIds  NVARCHAR(1000) = NULL
    , @GroupByFlag     INT            = NULL
    , @EndDates        NVARCHAR(4000) = NULL
    , @LateMinDuration INT            = 70
    , @IsDefaultLoad   BIT            = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = CAST(GETDATE() AS DATE);
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();

    SELECT   Ranks      = ROW_NUMBER() OVER (ORDER BY SUM(o.Quantity) DESC)
           , itemID     = o.ItemID
           , itemName   = ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-'))
           , BrandName  = ISNULL(br.BrandName, N'-')
           , CategoryName = ISNULL(c.CAT_NAME, N'-')
           , UnitPrice  = CAST(MAX(o.Price) AS DECIMAL(18,3))
           , SoldItems  = CAST(SUM(o.Quantity) AS INT)
           , Total      = CAST(ISNULL(SUM(o.TotalAmount), 0) AS DECIMAL(18,3))
    FROM     dbo.tblOrder o WITH (NOLOCK)
    JOIN     dbo.tblInvoice i WITH (NOLOCK) ON i.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblItems    it WITH (NOLOCK) ON it.ID      = o.ItemID
    LEFT JOIN dbo.tblCategory c  WITH (NOLOCK) ON c.CAT_NUM  = it.CAT_NUM
    LEFT JOIN dbo.tblBrand    br WITH (NOLOCK) ON br.BrandID = i.BrandID
    WHERE    ISNULL(i.Deleted, 0) = 0
      AND    ISNULL(o.Deleted, 0) = 0
      AND    i.InvoiceDate >= CAST(@FromDate AS DATE)
      AND    i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
      AND    (NULLIF(@BranchIds, '') IS NULL
              OR i.BranchID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIds, ',')))
      AND    (NULLIF(@BrandIds, '') IS NULL
              OR i.BrandID IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BrandIds, ',')))
    GROUP BY o.ItemID, ISNULL(o.ItemNameSnapshot, ISNULL(it.ITEM_NAME, N'-')),
             ISNULL(br.BrandName, N'-'), ISNULL(c.CAT_NAME, N'-')
    ORDER BY SoldItems DESC;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetDeliveryServiceData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_GetDeliveryServiceData]
      @Mobile  NVARCHAR(50)  = NULL
    , @Email   NVARCHAR(100) = NULL
    , @BrandID INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Mobiles are entered with spaces, dashes and sometimes a +965 prefix.
    -- Comparing them raw means a returning customer looks like a new one, so
    -- both sides are reduced to digits before matching.
    DECLARE @M NVARCHAR(50)  = NULLIF(LTRIM(RTRIM(ISNULL(@Mobile, ''))), '');
    DECLARE @E NVARCHAR(100) = NULLIF(LTRIM(RTRIM(ISNULL(@Email,  ''))), '');

    IF @M IS NOT NULL
    BEGIN
        SET @M = REPLACE(REPLACE(REPLACE(REPLACE(@M, ' ', ''), '-', ''), '(', ''), ')', '');
        IF LEFT(@M, 1) = '+' SET @M = SUBSTRING(@M, 2, 50);
        -- Keep the last 8 digits: that is the significant part of a Kuwaiti
        -- number whether or not the country code was typed.
        IF LEN(@M) > 8 SET @M = RIGHT(@M, 8);
    END

    ----------------------------------------------------------------------------
    -- 0 : saved addresses
    ----------------------------------------------------------------------------
    SELECT TOP (10)
           AddressID      = ca.AddressID
         , CustomerId     = ca.CustomerID
         , AreaID         = ISNULL(ca.AreaID, 0)
         , AreaName       = ISNULL(ar.AreaName, N'')
         , AreaNameAra    = ISNULL(ar.AreaNameAra, N'')
         , Block          = ISNULL(ca.Block, N'')
         , Street         = ISNULL(ca.Street, N'')
         , Lane           = ISNULL(ca.Lane, N'')
         , Building       = ISNULL(ca.Building, N'')
         , Floor          = ISNULL(ca.Floor, N'')
         -- lower case on purpose: BindCustomerAddressList reads obj.flat
         , flat           = ISNULL(ca.Flat, N'')
         , HouseNo        = ISNULL(ca.HouseNo, N'')
         , AddressRemarks = ISNULL(ca.AddressRemark, N'')
         , Latitude       = ISNULL(ca.Lat, N'')
         , Longitude      = ISNULL(ca.Lng, N'')
    FROM       dbo.tblCustomerAddress ca
    INNER JOIN dbo.tblCustomer        c  ON c.id     = ca.CustomerID
    LEFT  JOIN dbo.tblArea            ar ON ar.AreaID = ca.AreaID
    WHERE  ISNULL(ca.IsDeleted, 0) = 0
      AND  ISNULL(c.IsDeleted, 0)  = 0
      AND  ( ( @M IS NOT NULL
               AND RIGHT(REPLACE(REPLACE(REPLACE(ISNULL(c.mobile, ''), ' ', ''), '-', ''), '+', ''), 8) = @M )
          OR ( @E IS NOT NULL AND c.email = @E ) )
    -- Default address first, then most recent: the one a returning customer
    -- most likely wants is the one already at the top of the list.
    ORDER BY ca.IsDefault DESC, ca.AddressID DESC;

    ----------------------------------------------------------------------------
    -- 1 : pickup branches
    --
    -- Built as dynamic SQL purely so that branchNameAra / brandId / SEQ_NUM /
    -- IsDeleted are optional. On a database where one of them is absent the
    -- static version of this statement would not compile, and a procedure that
    -- fails to compile is indistinguishable, from the browser, from a server
    -- that is down - which is the bug this file is fixing.
    --
    -- Scoped to the brand whose menu is open. Without that a customer scanning
    -- one restaurant's QR code is offered another brand's branches.
    ----------------------------------------------------------------------------
    DECLARE @sql   NVARCHAR(MAX);
    DECLARE @NameAra NVARCHAR(200) =
        CASE WHEN COL_LENGTH('dbo.tblbranch', 'branchNameAra') IS NOT NULL
             THEN N'ISNULL(NULLIF(b.branchNameAra, N''''), ISNULL(b.branchName, N''''))'
             ELSE N'ISNULL(b.branchName, N'''')' END;
    DECLARE @Brand   NVARCHAR(200) =
        CASE WHEN COL_LENGTH('dbo.tblbranch', 'brandId') IS NOT NULL
             THEN N'ISNULL(b.brandId, 0)' ELSE N'0' END;
    DECLARE @BrandWhere NVARCHAR(400) =
        CASE WHEN COL_LENGTH('dbo.tblbranch', 'brandId') IS NOT NULL
             THEN N' AND (@pBrandID IS NULL OR @pBrandID = 0 OR b.brandId = @pBrandID)'
             ELSE N'' END;
    DECLARE @DelWhere NVARCHAR(200) =
        CASE WHEN COL_LENGTH('dbo.tblbranch', 'IsDeleted') IS NOT NULL
             THEN N' AND ISNULL(b.IsDeleted, 0) = 0' ELSE N'' END;
    DECLARE @OrderBy NVARCHAR(200) =
        CASE WHEN COL_LENGTH('dbo.tblbranch', 'SEQ_NUM') IS NOT NULL
             THEN N'ISNULL(b.SEQ_NUM, 9999), b.branchName' ELSE N'b.branchName' END;

    SET @sql = N'
        SELECT   BranchID      = b.id
               , BranchName    = ISNULL(b.branchName, N'''')
               , BranchNameAra = ' + @NameAra + N'
               , BrandID       = ' + @Brand + N'
               -- A branch has no area column of its own; the area it sits in is
               -- taken from its delivery mapping. Display only.
               , AreaID        = ISNULL(m.AreaID, 0)
               , AreaName      = ISNULL(ar.AreaName,    N'''')
               , AreaNameAra   = ISNULL(ar.AreaNameAra, N'''')
        FROM       dbo.tblbranch b
        OUTER APPLY (SELECT TOP (1) am.AreaID
                     FROM   dbo.TblArea_Mapping am
                     WHERE  am.BranchID = b.id
                     ORDER BY am.AreaID) m
        LEFT  JOIN dbo.tblArea ar ON ar.AreaID = m.AreaID
        WHERE  1 = 1' + @DelWhere + @BrandWhere + N'
        ORDER BY ' + @OrderBy + N';';

    EXEC sp_executesql @sql, N'@pBrandID INT', @pBrandID = @BrandID;
END
GO
/****** Object:  StoredProcedure [dbo].[sp_GetEndDatesForRptDashboard]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_GetEndDatesForRptDashboard]
      @CountryId INT      = NULL
    , @FromDate  DATETIME = NULL
    , @ToDate    DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @FromDate IS NULL SET @FromDate = DATEADD(DAY, -30, GETDATE());
    IF @ToDate   IS NULL SET @ToDate   = GETDATE();

    SELECT   StartDate     = d.Day
           , StartDateName = FORMAT(d.Day, 'dd-MMM-yy, ddd')
    FROM   (
        SELECT DISTINCT Day = CAST(i.InvoiceDate AS DATE)
        FROM   dbo.tblInvoice i WITH (NOLOCK)
        WHERE  ISNULL(i.Deleted, 0) = 0
          AND  i.InvoiceDate >= CAST(@FromDate AS DATE)
          AND  i.InvoiceDate <  DATEADD(DAY, 1, CAST(@ToDate AS DATE))
    ) d
    ORDER BY d.Day DESC;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetExpiredBrandList]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetExpiredBrandList]
AS
BEGIN
	select BrandID,BrandName,BrandNameAra,ExpiryDate,Email,EmailReminderContent,EmailReminderCount,ContactDetails 
	from tblbrand where ExpiryDate < GETDATE()
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetExtra]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_GetExtra]

@BrandID int=0
AS
BEGIN


select * from tblExtra where brandid=@BrandID


END



GO
/****** Object:  StoredProcedure [dbo].[sp_GetExtraComments]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetExtraComments]
@Brandid int =0
AS
BEGIN
	if @Brandid > 0
	begin
		select id,comments_eng,comments_arb from tblcomments where Brandid=@BrandId
	end
	else
	begin
		select id,comments_eng,comments_arb from tblcomments
	end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetExtraItems]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetExtraItems]
@Cat_Num int =0
AS
BEGIN
	select id,CAT_NUM,ITEM_NAME,ITEM_NAME_ARABIC,PRICE from tblItems where IsActive=1 and isExtra=1 and Cat_Num=@Cat_Num
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetFeedbackFormQuestion]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
/****** Object:  StoredProcedure [dbo].[sp_GetFeedBackLayout]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetFeedBackLayout]

AS
BEGIN



select [dbo].[Feedback_Layout].*,[Feedback_Type].Type from [dbo].[Feedback_Layout]
inner join [dbo].[Feedback_Type] on [dbo].[Feedback_Type].id=[Feedback_Layout].TypeId order by [dbo].Feedback_Layout.Sequence


select * from [dbo].[Feedback_Type]
END



GO
/****** Object:  StoredProcedure [dbo].[sp_GetGroupModifier]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetGroupModifier]
@Brandid int =0
AS
BEGIN
	if @Brandid > 0
	begin
		--select id,comments_eng,comments_arb from tblcomments where Brandid=@BrandId
		select distinct gmm.id,gmm.GroupNameEng,gmm.GroupNameArb,gmm.Type as TypeID,
		gmt.TypeName_TMM as TypeName,gmm.MinSelect,gmm.MaxSelect,gmm.Seq_Num
		from tblGroup_Modifier_Master gmm
		left join tblGroup_Modifier_Type gmt on gmt.ID=gmm.Type
		where gmm.Brandid=@BrandId
		order by gmm.Seq_Num
	end
	else
	begin
		select distinct gmm.id,gmm.GroupNameEng,gmm.GroupNameArb,gmm.Type as TypeID,
		gmt.TypeName_TMM as TypeName,gmm.MinSelect,gmm.MaxSelect,gmm.Seq_Num
		from tblGroup_Modifier_Master gmm
		left join tblGroup_Modifier_Type gmt on gmt.ID=gmm.Type
		order by gmm.Seq_Num
	end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetGroupModifierTypes]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetGroupModifierTypes]
@Brandid int =0
AS
BEGIN
	select ID,TypeName_TMM from tblGroup_Modifier_Type
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetIoutofStock]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO





create PROCEDURE [dbo].[sp_GetIoutofStock]

@BrandID int=0
AS
BEGIN


SELECT i.*,c.* FROM tblItems i
inner join tblCategory c on i.CAT_NUM=c.CAT_NUM
inner join Assign_Cat a on c.CAT_NUM=a.CatNum
 where a.BrandID in(select cast(item as integer) from dbo.splitstring(@BrandID,',')) and i.showintablet=1 and i.OutOfStock=1
order by  CAST(c.SEQ_NUM AS Numeric(10,0)),CAST(i.Seq_Num AS Numeric(10,0))

end
GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemChoices]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetItemChoices]
AS
BEGIN
	select * from tblItem_Choices
End

GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemComments]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetItemComments]
AS
BEGIN
	select * from tblItemComments
End

GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemDetails]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetItemDetails]
@ID int=0
AS
BEGIN

	select distinct i.ID,c.CAT_NUM,c.CAT_NAME,c.CAT_NAME_ARABIC,i.ITEM_NAME,
	cast(i.PRICE as nvarchar(10)) as PRICE,
	i.ITEM_NAME_ARABIC,
	i.INGREDIENT,i.INGREDIENT_ARABIC,i.ImageName,i.Video, i.HID,i.Seq_Num, i.isExtra, i.ShowInTablet
	,isnull(i.IsActive,0) as IsActive
	from tblItems i
	inner join tblCategory c on c.CAT_NUM=i.CAT_NUM
	where i.ID = @ID

	select BranchId from Assign_Item Where ItemId = @ID
	select ExtraItemId from tblItem_Extras Where itemid = @ID
	select commentid from tblItemComments Where itemid = @ID
	select ChoiceId from tblItem_choices Where itemid = @ID
	
END



GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemExtraItemsAndComments]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetItemExtraItemsAndComments]
@itemid int=0,
@Branchid int =0,

@IPAddress nVarchar(50) = '',
@BrowserName nVarchar(100) = '',
@DeviceModal nVarchar(50) = '',
@DeviceManufacturer nVarchar(50) = ''
AS
BEGIN
	--select ie.ExtraItemId as id,iextra.ITEM_NAME,iextra.ITEM_NAME_ARABIC,iextra.PRICE,iextra.HID,iextra.IMAGENAME from tblItems i
	--inner join tblItem_Extras ie on i.ID=ie.ItemId
	--inner join tblItems iextra on iextra.id=ie.ExtraItemId
	--where i.id=@itemid
	--order by iextra.Seq_Num


	---extra items
	select distinct GroupId,groupnameEng,groupnamearb,id,ITEM_NAME,ITEM_NAME_ARABIC,PRICE,HID,IMAGENAME,MinSelect,maxselect,gmSeq_Num,iextraSeq_Num,ModifierType
	from(
		select gm.id as GroupId, gm.groupnameEng,gm.groupnamearb,iextra.id as id,iextra.ITEM_NAME,iextra.ITEM_NAME_ARABIC,iextra.PRICE,iextra.HID,iextra.IMAGENAME
		,gm.MinSelect,gm.maxselect
		,gm.Seq_Num as gmSeq_Num, iextra.Seq_Num as iextraSeq_Num,gm.type as ModifierType
		from tblgroup_modifier_master gm
		inner join tblGroup_Modifier_Details ie on ie.GroupId=gm.ID
		inner join tblItems i on i.ID=ie.MainItemId
		inner join tblItems iextra on iextra.ID= ie.ItemID
		where i.id=@itemid and gm.type=2
		and ie.deleted !=1
		--order by gm.Seq_Num,iextra.Seq_Num
		--order by gm.Seq_Num, iextra.Seq_Num
	
		union all 
		--choices
		select gm.id as GroupId, gm.groupnameEng,gm.groupnamearb,iextra.id as id,iextra.ITEM_NAME,iextra.ITEM_NAME_ARABIC,iextra.PRICE,iextra.HID,iextra.IMAGENAME
		,gm.MinSelect,gm.maxselect
		,gm.Seq_Num as gmSeq_Num, iextra.Seq_Num as iextraSeq_Num,gm.type as ModifierType
		from tblgroup_modifier_master gm
		inner join tblGroup_Modifier_Details ie on ie.GroupId=gm.ID
		inner join tblItems i on i.ID=ie.MainItemId
		inner join tblItems iextra on iextra.ID= ie.ItemID
		where i.id=@itemid and gm.type=1
		and ie.deleted !=1
		--order by gm.Seq_Num,iextra.Seq_Num

	) tt order by gmSeq_Num,iextraSeq_Num

	select c.id,c.comments_arb,c.comments_eng
	from tblItemComments ic 
	inner join tblcomments c on c.id=ic.commentid
	where ic.itemid=@itemid

	--select ie.ChoiceId as id,cho.ITEM_NAME,cho.ITEM_NAME_ARABIC,cho.PRICE,cho.HID,cho.IMAGENAME from tblItems i
	--inner join tblItem_choices ie on i.ID=ie.ItemId
	--inner join tblItems cho on cho.id=ie.ChoiceId
	--where i.id=@itemid
	--order by cho.PRICE 

	
	
	Declare @ItemName Varchar(50)
	Select @ItemName = ITEM_NAME From tblItems Where id = @itemid
	Exec [sp_UpdateAuditDetails] @IPAddress, @BrowserName, @DeviceModal, @DeviceManufacturer, 3, @itemid, @ItemName, @Branchid

END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemExtras]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetItemExtras]
AS
BEGIN
	select * from tblItem_Extras
End

GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemImages]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
/****** Object:  StoredProcedure [dbo].[sp_GetItemMobile]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetItemMobile]

@BrandID int=0
AS
BEGIN


--SELECT i.*,c.* FROM tblItems i
--inner join tblCategory c on i.CAT_NUM=c.CAT_NUM
--inner join Assign_Cat a on c.CAT_NUM=a.CatNum
-- where a.BrandID in(select cast(item as integer) from dbo.splitstring(@BrandID,',')) and i.showintablet=1 and c.ShowInTablet=1
--order by  CAST(c.SEQ_NUM AS Numeric(10,0)),CAST(i.Seq_Num AS Numeric(10,0))
if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) =1)
begin
	SELECT i.ID,i.HID,i.CAT_NUM
	,c.CAT_NAME,c.CAT_NAME_ARABIC,c.CatNameMan,c.CatNameRus,i.ITEM_NAME,i.ITEM_NAME_ARABIC,i.ItemNameMan
	,i.PRICE,i.INGREDIENT,i.INGREDIENT_ARABIC,i.INGREDIENT_Man,i.INGREDIENT_Rus
	,i.IMAGENAME,i.ITEM_DESC_ENG,i.Video,i.Seq_Num,i.ShowInTablet
	,isnull(b.IsOtherLanguages,0) as IsOtherLanguages
	
	--,Item_lag.arabic as ITEM_Name_arabic
	,isnull(Item_lag.chinese,'') as ITEMName_chinese
	,isnull(Item_lag.turkish,'') as ITEMName_turkish
	,isnull(Item_lag.hindi,'') as ITEMName_hindi
	,isnull(Item_lag.korean,'') as ITEMName_korean
	,isnull(Item_lag.spain,'') as ITEMName_spain
	,isnull(Item_lag.bangladeshi,'') as ITEMName_bangladeshi
	,isnull(Item_lag.srilanka,'') as ITEMName_srilanka
	,isnull(Item_lag.iranian,'') as ITEMName_iranian
	,isnull(Item_lag.italian,'') as ITEMName_italian
	,isnull(Item_lag.urdu,'') as ITEMName_urdu
	,isnull(Item_lag.philippines,'') as ITEMName_philippines
	,isnull(Item_lag.french,'') as ITEMName_french
	,isnull(Item_lag.germany,'') as ITEMName_germany
	
	--,Ingredient_lag.arabic as Ingredient_arabic
	,isnull(Ingredient_lag.chinese,'') as Ingredient_chinese
	,isnull(Ingredient_lag.turkish,'') as Ingredient_turkish
	,isnull(Ingredient_lag.hindi,'') as Ingredient_hindi
	,isnull(Ingredient_lag.korean,'') as Ingredient_korean
	,isnull(Ingredient_lag.spain,'') as Ingredient_spain
	,isnull(Ingredient_lag.bangladeshi,'') as Ingredient_bangladeshi
	,isnull(Ingredient_lag.srilanka,'') as Ingredient_srilanka
	,isnull(Ingredient_lag.iranian,'') as Ingredient_iranian
	,isnull(Ingredient_lag.italian,'') as Ingredient_italian
	,isnull(Ingredient_lag.urdu,'') as Ingredient_urdu
	,isnull(Ingredient_lag.philippines,'') as Ingredient_philippines
	,isnull(Ingredient_lag.french,'') as Ingredient_french
	,isnull(Ingredient_lag.germany,'') as Ingredient_germany
	
	,isnull(i.isExtra,0) isExtra ,isnull(i.IsActive,0) IsActive ,isnull(i.Ischoice,0) Ischoice
	FROM tblItems i
	inner join tblCategory c on i.CAT_NUM=c.CAT_NUM
	--inner join Assign_Cat a on c.CAT_NUM=a.CatNum
	inner join Assign_item a on i.ID=a.itemid
	inner join tblBrand b on b.BrandID=a.BrandID
	left join tblItemsName_Languages Item_lag on Item_lag.ItemId=i.ID
	left join tblIngredientName_Languages Ingredient_lag on Ingredient_lag.ItemId=i.ID
	where a.branchid in(select cast(item as integer) from dbo.splitstring(@BrandID,',')) and i.showintablet=1 and c.ShowInTablet=1
	order by  CAST(c.SEQ_NUM AS Numeric(10,0)),CAST(i.Seq_Num AS Numeric(10,0))
	
end
else
begin




	--SELECT i.ID,i.HID,i.CAT_NUM
	--,c.CAT_NAME,c.CAT_NAME_ARABIC,c.CatNameMan,c.CatNameRus,i.ITEM_NAME,i.ITEM_NAME_ARABIC,i.ItemNameMan
	--,i.PRICE,i.INGREDIENT,i.INGREDIENT_ARABIC,i.INGREDIENT_Man,i.INGREDIENT_Rus
	--,i.IMAGENAME,i.ITEM_DESC_ENG,i.Video,i.Seq_Num,i.ShowInTablet
	--,isnull(b.IsOtherLanguages,0) as IsOtherLanguages
	
	
	--FROM tblItems i
	--inner join tblCategory c on i.CAT_NUM=c.CAT_NUM
	--inner join Assign_Cat a on c.CAT_NUM=a.CatNum
	--inner join tblBrand b on b.BrandID=a.BrandID
	--left join tblItemsName_Languages Item_lag on Item_lag.ItemId=i.ID
	--left join tblIngredientName_Languages Ingredient_lag on Ingredient_lag.ItemId=i.ID
	--where a.BrandID in(select cast(item as integer) from dbo.splitstring(@BrandID,',')) and i.showintablet=1 and c.ShowInTablet=1
	--order by  CAST(c.SEQ_NUM AS Numeric(10,0)),CAST(i.Seq_Num AS Numeric(10,0))






	SELECT 
	i.ID,
	i.CAT_NUM
		,i.ITEM_NAME
		,i.PRICE,
		i.ITEM_NAME_ARABIC
		,i.INGREDIENT,
		i.INGREDIENT_ARABIC
			,i.IMAGENAME,
	c.CAT_NAME,
	c.CAT_NAME_ARABIC,
	c.CatNameMan,
	c.CatNameRus,
	i.Seq_Num,
		i.ItemNameMan,
		i.ItemNameRus,
		i.INGREDIENT_Rus,
		i.INGREDIENT_Man,
	
	
	i.ShowInTablet,
	i.Video
	,isnull(b.IsOtherLanguages,0) as IsOtherLanguages
	,i.HID,
	i.ITEM_DESC_ENG
	,isnull(i.isExtra,0) isExtra ,isnull(i.IsActive,0) IsActive ,isnull(i.Ischoice,0) Ischoice

	FROM tblItems i
	inner join tblCategory c on i.CAT_NUM=c.CAT_NUM
	--inner join Assign_Cat a on c.CAT_NUM=a.CatNum
	inner join Assign_item a on i.ID=a.itemid
	inner join tblBrand b on b.BrandID=a.BrandID
	left join tblItemsName_Languages Item_lag on Item_lag.ItemId=i.ID
	left join tblIngredientName_Languages Ingredient_lag on Ingredient_lag.ItemId=i.ID
	where a.branchid=@BrandID and i.showintablet=1 and c.ShowInTablet=1
	order by  CAST(c.SEQ_NUM AS Numeric(10,0)),CAST(i.Seq_Num AS Numeric(10,0))
	
end
End


GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemMobileIPad]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetItemMobileIPad]
@BrandID int=0
AS
BEGIN
if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) =1)
begin
	SELECT i.ID,i.HID,i.CAT_NUM
	,c.CAT_NAME,c.CAT_NAME_ARABIC,c.CatNameMan,c.CatNameRus,i.ITEM_NAME,i.ITEM_NAME_ARABIC,i.ItemNameMan
	,i.PRICE,i.INGREDIENT,i.INGREDIENT_ARABIC,i.INGREDIENT_Man,i.INGREDIENT_Rus
	,i.IMAGENAME,i.ITEM_DESC_ENG,i.Video,i.Seq_Num,i.ShowInTablet
	,isnull(b.IsOtherLanguages,0) as IsOtherLanguages
	
	--,Item_lag.arabic as ITEM_Name_arabic
	,isnull(Item_lag.chinese,'') as ITEMName_chinese
	,isnull(Item_lag.turkish,'') as ITEMName_turkish
	,isnull(Item_lag.hindi,'') as ITEMName_hindi
	,isnull(Item_lag.korean,'') as ITEMName_korean
	,isnull(Item_lag.spain,'') as ITEMName_spain
	,isnull(Item_lag.bangladeshi,'') as ITEMName_bangladeshi
	,isnull(Item_lag.srilanka,'') as ITEMName_srilanka
	,isnull(Item_lag.iranian,'') as ITEMName_iranian
	,isnull(Item_lag.italian,'') as ITEMName_italian
	,isnull(Item_lag.urdu,'') as ITEMName_urdu
	,isnull(Item_lag.philippines,'') as ITEMName_philippines
	,isnull(Item_lag.french,'') as ITEMName_french
	,isnull(Item_lag.germany,'') as ITEMName_germany
	
	--,Ingredient_lag.arabic as Ingredient_arabic
	,isnull(Ingredient_lag.chinese,'') as Ingredient_chinese
	,isnull(Ingredient_lag.turkish,'') as Ingredient_turkish
	,isnull(Ingredient_lag.hindi,'') as Ingredient_hindi
	,isnull(Ingredient_lag.korean,'') as Ingredient_korean
	,isnull(Ingredient_lag.spain,'') as Ingredient_spain
	,isnull(Ingredient_lag.bangladeshi,'') as Ingredient_bangladeshi
	,isnull(Ingredient_lag.srilanka,'') as Ingredient_srilanka
	,isnull(Ingredient_lag.iranian,'') as Ingredient_iranian
	,isnull(Ingredient_lag.italian,'') as Ingredient_italian
	,isnull(Ingredient_lag.urdu,'') as Ingredient_urdu
	,isnull(Ingredient_lag.philippines,'') as Ingredient_philippines
	,isnull(Ingredient_lag.french,'') as Ingredient_french
	,isnull(Ingredient_lag.germany,'') as Ingredient_germany
	
	
	FROM tblItems i
	inner join tblCategory c on i.CAT_NUM=c.CAT_NUM
	--inner join Assign_Cat a on c.CAT_NUM=a.CatNum
	inner join Assign_item a on i.ID=a.itemid
	inner join tblBrand b on b.BrandID=a.BrandID
	left join tblItemsName_Languages Item_lag on Item_lag.ItemId=i.ID
	left join tblIngredientName_Languages Ingredient_lag on Ingredient_lag.ItemId=i.ID
	where a.branchid in(select cast(item as integer) from dbo.splitstring(@BrandID,',')) and i.showintablet=1 and c.ShowInTablet=1
	order by  CAST(c.SEQ_NUM AS Numeric(10,0)),CAST(i.Seq_Num AS Numeric(10,0))
	
end
else
begin
	SELECT 
	i.ID,
	i.CAT_NUM
		,i.ITEM_NAME
		,i.PRICE,
		i.ITEM_NAME_ARABIC
		,i.INGREDIENT,
		i.INGREDIENT_ARABIC
			,i.IMAGENAME,
	c.CAT_NAME,
	c.CAT_NAME_ARABIC,
	c.CatNameMan,
	c.CatNameRus,
	i.Seq_Num,
		i.ItemNameMan,
		i.ItemNameRus,
		i.INGREDIENT_Rus,
		i.INGREDIENT_Man,
	
	
	i.ShowInTablet,
	i.Video
	,isnull(b.IsOtherLanguages,0) as IsOtherLanguages
	,i.HID,
	i.ITEM_DESC_ENG

	FROM tblItems i
	inner join tblCategory c on i.CAT_NUM=c.CAT_NUM
	--inner join Assign_Cat a on c.CAT_NUM=a.CatNum
	inner join Assign_item a on i.ID=a.itemid
	inner join tblBrand b on b.BrandID=a.BrandID
	left join tblItemsName_Languages Item_lag on Item_lag.ItemId=i.ID
	left join tblIngredientName_Languages Ingredient_lag on Ingredient_lag.ItemId=i.ID
	where a.branchid=@BrandID and i.showintablet=1 and c.ShowInTablet=1
	order by  CAST(c.SEQ_NUM AS Numeric(10,0)),CAST(i.Seq_Num AS Numeric(10,0))
	
end
End


GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemsAllergenWise]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetItemsAllergenWise]
@AllergenId int
AS
BEGIN
	select aa.ItemId as ItemId from tbl_Allergen_Assign aa 
	where aa.allergenid= @AllergenId
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemsBranchwise]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetItemsBranchwise]
@BrandID int,
@branchid int
AS
BEGIN
	select i.ID as ItemId,i.ITEM_NAME,i.ITEM_NAME_ARABIC from tblItems i 
	inner join Assign_Item ai on ai.ItemId=i.ID
	where ai.BranchId= @branchid and BrandID=@BrandID
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemsCommentWise]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetItemsCommentWise]
@CommentId int
AS
BEGIN
	select ic.ItemId as ItemId from tblItemComments ic 
	where ic.commentid= @CommentId
END


--rename sp_UpdateItemsBranchAssign to sp_AssignItemToBranch
GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemsExtraItemsWise]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetItemsExtraItemsWise]
@ExtraItemId int
AS
BEGIN
	select ie.ItemId as ItemId from tblItem_Extras ie 
	where ie.ExtraItemId= @ExtraItemId
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetItemsVisits]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
CREATE PROCEDURE [dbo].[sp_GetItemsVisits]
	-- Add the parameters for the stored procedure here
	@BrandId int =0,
	@FromDate Date = Null,
	@ToDate Date = Null
AS
BEGIN

	--select * from(
	--Select ti.ITEM_NAME,c.CAT_NAME, 
	----Count(ta.IPAddress) As VisitorsCount
	--(select count(tad.ID) from tblAuditDetails tad 
	--left outer  Join tblAudit ta on ta.ID = tad.AuditID
	--left outer  join tblbranch b on b.id=ta.BranchId
	--left outer  join tblBrand bd on bd.BrandID=b.brandId
	--Where tad.ItemSelectionName = ti.ITEM_NAME And tad.ItemSelectionType = 3 and 
	--Cast(tad.CreatedOn As Date) Between Cast(@FromDate As Date) AND Cast(@ToDate As Date)
	--and bd.BrandID=@BrandId and b.IsActive=1 and isnull(b.IsDeleted,0) =0) As VisitorsCount
	--From tblItems ti 
	--inner join tblCategory c on ti.CAT_NUM=c.CAT_NUM
	--) item order by VisitorsCount desc, ITEM_NAME


	;with cte as(
	select ta.IPAddress as IPAddress, count(tad.ItemSelectionID) as Visits,
	i.ITEM_NAME as ITEM_NAME,
	c.CAT_NAME
	from tblAuditDetails  tad
	left outer Join tblAudit ta on ta.ID=tad.AuditID
	left outer Join tblbranch b on b.id=ta.BranchId
	left outer Join tblBrand bd on bd.BrandID=b.brandId
	left outer Join tblItems i on i.ID=tad.ItemSelectionID
	inner Join tblCategory c on c.CAT_NUM=i.CAT_NUM
	where Cast(tad.CreatedOn As Date) between cast(@FromDate as date) and cast(@ToDate as date)
	and tad.ItemSelectionType = 3 and bd.BrandID=@BrandId and b.IsActive=1 and isnull(b.IsDeleted,0) =0
	--and  ItemSelectionID=3
	group by ta.IPAddress,ItemSelectionID,i.ITEM_NAME,c.CAT_NAME
	) 
	select ITEM_NAME as ITEM_NAME,CAT_NAME, count(visits) as VisitorsCount from cte group by ITEM_NAME,CAT_NAME order by count(visits) desc

END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetLangLabels]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetLangLabels]
@selectedLang nvarchar(10)='EN'
AS
BEGIN
	IF @selectedLang = 'EN'
	BEGIN
		select [id]
		  ,[labelName]
		  ,[labelNameEng] as LabelTest
       from tblLabelName 
	END

	ELSE

	BEGIN
		select [id]
		  ,[labelName]
		  ,[labelNameArb] as LabelTest
       from tblLabelName 
	END
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetMainCategoryList]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetMainCategoryList]
@Brandid int =0
AS
BEGIN
	if @Brandid > 0
	begin
		select distinct CAT_NUM,CAT_NAME,CAT_NAME_ARABIC,SEQ_NUM
		from tblCategory cm 
		inner join Assign_Cat ac on ac.CatNum=cm.CAT_NUM
		where ac.Brandid=@BrandId and isnull(MainCategory,0) =0 order by SEQ_NUM
	end
	else
	begin
		select CAT_NUM,CAT_NAME,CAT_NAME_ARABIC from tblCategory cm where isnull(MainCategory,0) =0 order by SEQ_NUM
	end
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetMenuColors]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetMenuColors]
    @BrandId  INT,
    @BranchId INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1) *
    FROM   dbo.tbl_Menu_Colors
    WHERE  BrandId = @BrandId
      AND (BranchId = @BranchId OR BranchId = 0)
    ORDER BY CASE WHEN BranchId = @BranchId THEN 0 ELSE 1 END;  -- branch-specific first
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetMenuTheme]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetMenuTheme]
    @BrandId  INT,
    @BranchId INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  Name, Color
    FROM    dbo.tblMenuTheme
    --WHERE   BrandID = @BrandId
    --  AND  (BranchID = @BranchId OR BranchID = 0)
    --ORDER BY CASE WHEN BranchID = @BranchId THEN 0 ELSE 1 END;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetMenuThemeVersion]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetMenuThemeVersion]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1) Color
    FROM   dbo.tblMenuTheme
    WHERE  Name = 'Version';
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetNewThemes]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create PROCEDURE [dbo].[sp_GetNewThemes]

@BrandID int
AS
BEGIN


select * from [dbo].[tblTheme_new] where brandid=@BrandID

END



GO
/****** Object:  StoredProcedure [dbo].[sp_GetOnlinePaymentTypes]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_GetOnlinePaymentTypes]
      @IncludeCOD BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT   PaymentTypeID     = ID
           , PaymentTypeName
           , PaymentTypeNameArb
           , Image
           , IsOnline
           , IsCOD
           , IsCash
           , RequiresReference
           , Provider
           , Seqnum
    FROM     dbo.tblInvoicePaymentType
    WHERE    ISNULL(IsDeleted, 0) = 0
      AND    ISNULL(IsActive, 1) = 1
      AND    ( IsOnline = 1 OR (@IncludeCOD = 1 AND IsCOD = 1) )
    ORDER BY Seqnum, ID;
END
GO
/****** Object:  StoredProcedure [dbo].[sp_GetReservationData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetReservationData]
@slotIds nvarchar(100)='',
@FromDate datetime=null,
@ToDate datetime=null
AS
BEGIN


	if (len(@slotIds) = 0 and  @FromDate is null and @ToDate is null)
	begin
		select  res.id,branchId,
		sloteId,
		FORMAT (reservationDate, 'dd MMM yyyy') as reservationDate,
		customerName,
		customerMobile,
		customerEmail,
		comments,
		rt.TableName,
		rt.DiningArea,
		confirmationId,
		FORMAT (TransactionDate, 'dd MMM yyyy hh:mm:ss') TransactionDate,
		rss.slotName as slotName,
		rss.slotNameArabic as slotNameArabic,
		b.branchName,
		res.status
		from tblreservation res
		inner join tblReservationSlot rss on res.sloteId=rss.id
		inner join tblbranch b on b.id= res.branchId
		inner join tblReservationTableStructure rt on rt.id = res.TableStructureID
		order by res.id desc
	end
	else if (len(@slotIds) > 0 and  @FromDate is null and @ToDate is null)
	begin
		select  res.id,branchId,
		sloteId,
		FORMAT (reservationDate, 'dd MMM yyyy') as reservationDate,
		customerName,
		customerMobile,
		customerEmail,
		comments,
		rt.TableName,
		rt.DiningArea,
		confirmationId,
		FORMAT (TransactionDate, 'dd MMM yyyy hh:mm:ss') TransactionDate,
		rss.slotName as slotName,
		rss.slotNameArabic as slotNameArabic,
		b.branchName,
		res.status
		from tblreservation res
		inner join tblReservationSlot rss on res.sloteId=rss.id
		inner join tblbranch b on b.id= res.branchId
		inner join tblReservationTableStructure rt on rt.id = res.TableStructureID
		where res.sloteId in (select * from dbo.SplitString(@slotIds,','))
		order by res.id desc
	end
	else if (len(@slotIds) > 0 and  @FromDate is not null and @ToDate is not null)
	begin
		select  res.id,branchId,
		sloteId,
		FORMAT (reservationDate, 'dd MMM yyyy') as reservationDate,
		customerName,
		customerMobile,
		customerEmail,
		comments,
		rt.TableName,
		rt.DiningArea,
		confirmationId,
		FORMAT (TransactionDate, 'dd MMM yyyy hh:mm:ss') TransactionDate,
		rss.slotName as slotName,
		rss.slotNameArabic as slotNameArabic,
		b.branchName,
		res.status
		from tblreservation res
		inner join tblReservationSlot rss on res.sloteId=rss.id
		inner join tblbranch b on b.id= res.branchId
		inner join tblReservationTableStructure rt on rt.id = res.TableStructureID
		where res.sloteId in (select * from dbo.SplitString(@slotIds,','))
		and cast(res.reservationDate as date) between cast(@FromDate as date) and cast(@ToDate as date)
		order by res.id desc
	end
	else if (len(@slotIds) = 0 and  @FromDate is not null and @ToDate is not null)
	begin
		select  res.id,branchId,
		sloteId,
		FORMAT (reservationDate, 'dd MMM yyyy') as reservationDate,
		customerName,
		customerMobile,
		customerEmail,
		comments,
		rt.TableName,
		rt.DiningArea,
		confirmationId,
		FORMAT (TransactionDate, 'dd MMM yyyy hh:mm:ss') TransactionDate,
		rss.slotName as slotName,
		rss.slotNameArabic as slotNameArabic,
		b.branchName,
		res.status
		from tblreservation res
		inner join tblReservationSlot rss on res.sloteId=rss.id
		inner join tblbranch b on b.id= res.branchId
		inner join tblReservationTableStructure rt on rt.id = res.TableStructureID
		where 
		cast(res.reservationDate as date) between cast(@FromDate as date) and cast(@ToDate as date)
		order by res.id desc
	end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetReservationMasterData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetReservationMasterData]
AS
BEGIN
	--Table List
	select id,TableName,DiningArea,Seating,isnull(Xaxis,0) as Xaxis,isnull(Yaxis,0) as Yaxis from tblReservationTableStructure
	where isnull(IsDeleted,0)=0

	--TimeSlot List
	select id,slotName,slotNameArabic,fromTime,toTime from tblReservationSlot
	where isnull(IsDeleted,0)=0
END


GO
/****** Object:  StoredProcedure [dbo].[sp_getSetting]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_getSetting]

AS
BEGIN


SELECT id,CAST(ExpiryDate as Date) FROM tblsetting


END



GO
/****** Object:  StoredProcedure [dbo].[sp_GetSettings]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetSettings]
AS
BEGIN
	select isnull(isReservation,0) as isReservation from tblSetting
END


GO
/****** Object:  StoredProcedure [dbo].[sp_GetTabThemes]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetTabThemes]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  ThemeID, ThemeName,
            CategoryActive, CategoryInActive, Setting, SeperatorLine, HomeScreen, PopUpBackground,
            EnglishButton, ArabicButton, MandarinButton, RussianButton, CloseButton,
            LeftArrow, LeftBottom, LeftTop, RightArrow, RightButton, RightTop,
            FontColor, FontColorItemName, FontColorIngName, FontColorPrice, ItemBackgroundColor
    FROM    dbo.tblTheme
    ORDER BY ThemeID;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_GetTheme]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetTheme]

@ThemeID int=0
AS
BEGIN


SELECT [ThemeID]
      ,[ThemeName]
      ,[CategoryActive]
      ,[CategoryInActive]
      ,[Setting]
      ,[SeperatorLine]
      ,[EnglishButton]
      ,[ArabicButton]
      ,[MandarinButton]
      ,[RussianButton]
      ,[CloseButton]
      ,[HomeScreen]
      ,[LeftArrow]
      ,[LeftBottom]
      ,[LeftTop]
      ,[PopUpBackground]
      ,[RightArrow]
      ,[RightButton]
      ,[RightTop]
      ,isnull([FontColor],'#000000')[FontColor]
      ,isnull([FontColorItemName],'#000000')[FontColorItemName]
      ,isnull([FontColorIngName],'#000000')[FontColorIngName]
      ,isnull([FontColorPrice],'#000000')[FontColorPrice]
	  ,isnull([ItemBackgroundColor],'#000000')[ItemBackgroundColor]
	   FROM tblTheme where ThemeID=@ThemeID


END



GO
/****** Object:  StoredProcedure [dbo].[sp_GetThemes]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetThemes]

AS
BEGIN

declare @isAdmin bit

select tblTheme.*,isnull(tblBrand.BrandID,0) as BrandID ,tblBrand.BrandName from tblTheme 
left outer join tblBrand on tblBrand.Theme= tblTheme.ThemeID


END



GO
/****** Object:  StoredProcedure [dbo].[sp_GetTimeSlot]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_GetTimeSlot]
--@TableStructureID int=0,
@reservationDate datetime =null
AS
BEGIN
	select rss.id,rss.slotName,rss.slotNameArabic,rss.fromTime,rss.toTime
	,CONVERT(DATETIME, CONVERT(varchar(20), 
	cast( @reservationDate as date) ,101)  + ' ' + CONVERT(varchar(8), rss.fromTime, 108))
	,GETDATE()
	from tblReservationSlot rss 
	where isnull(rss.IsDeleted,0)=0 and CONVERT(DATETIME, CONVERT(varchar(20), 
	cast( @reservationDate as date) ,101)  + ' ' + CONVERT(varchar(8), rss.fromTime, 108)) > GETDATE()   
END


------------------------------Start Rename OrderItemID to HID in tblItems table  22-04-2021 ----------------------------------
GO
/****** Object:  StoredProcedure [dbo].[sp_GetTimeSlotDataDateWise]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetTimeSlotDataDateWise]
@reservationDate datetime='2021-01-11',
@DiningArea nvarchar(50)='Inner Area'
AS
BEGIN
	----TimeSlot List
	--select id,slotName,slotNameArabic,fromTime,toTime from tblReservationSlot
	--where isnull(IsDeleted,0)=0

	
	select * 
	,((select count(1) from tblReservationTableStructure where isnull(IsDeleted,0)=0 and DiningArea=@DiningArea)- ReservedCount) as AvailableCount
	from (
		select id,slotName,slotNameArabic,fromTime,toTime,
		(select count(1) from tblReservation rs
		inner join tblReservationTableStructure tbl on tbl.Id=rs.TableStructureID
		where rs.reservationDate=@reservationDate  and tbl.DiningArea=@DiningArea
		and rs.sloteId=rst.id) as ReservedCount
		from tblReservationSlot rst
		where isnull(rst.IsDeleted,0)=0
		and CONVERT(DATETIME, CONVERT(varchar(20), 
		cast( @reservationDate as date) ,101)  + ' ' + CONVERT(varchar(8), rst.toTime, 108)) > GETDATE()   
		) temp
		order by fromTime
END

GO
/****** Object:  StoredProcedure [dbo].[sp_InsertIntoBrandSyncCategory]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_InsertIntoBrandSyncCategory]
@dttblCategorySync [DT_tblCategorySync] readonly
AS
BEGIN
	--truncate table tblCategory
	SET IDENTITY_INSERT dbo.tblCategory on

	--insert category if not in the dm category table
	insert into tblCategory(CAT_NUM,CAT_NAME,SEQ_NUM,ShowInTablet,CAT_NAME_ARABIC,
	MainCategory,IsActive,HID)
	SELECT t1.CAT_NUM,t1.CAT_NAME,t1.SEQ_NUM,
	0,
	--t1.ShowInTablet,
	t1.CAT_NAME_ARABIC,
	t1.MainCategory,t1.IsActive,t1.HID
	FROM @dttblCategorySync t1
	left join tblCategory c on c.HID=t1.HID
	where c.HID is null


	--update category if it is in the dm category table
	update c set c.CAT_NAME=t1.CAT_NAME,c.CAT_NAME_ARABIC=t1.CAT_NAME_ARABIC
	FROM tblCategory c
	inner join @dttblCategorySync t1 on c.HID=t1.HID
	where c.HID is not null

	SET IDENTITY_INSERT dbo.tblCategory off
END



GO
/****** Object:  StoredProcedure [dbo].[sp_InsertIntoBrandSyncItems]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_InsertIntoBrandSyncItems]
@dttblItemsSync [DT_tblItemsSync] readonly 
AS
BEGIN

	--truncate table tblItems
	SET IDENTITY_INSERT [dbo].[tblItems] ON 

	insert into tblItems(ID,CAT_NUM,ITEM_NAME,PRICE,ITEM_NAME_ARABIC,INGREDIENT,INGREDIENT_ARABIC,IMAGENAME,
	ITEM_DESC_ENG,Seq_Num,ShowInTablet,isExtra,isactive,Ischoice,HID)
	SELECT t1.ID,t1.CAT_NUM,t1.ITEM_NAME,t1.PRICE,t1.ITEM_NAME_ARABIC,t1.INGREDIENT,t1.INGREDIENT_ARABIC,t1.IMAGENAME,
	t1.ITEM_DESC_ENG,t1.Seq_Num,0,t1.isExtra,t1.isactive,t1.Ischoice,t1.HID
	FROM @dttblItemsSync t1 
	LEFT JOIN tblItems t2 ON  t1.HID=t2.HID
	where t2.HID is null


	update i set i.ITEM_NAME=t1.ITEM_NAME,i.ITEM_NAME_ARABIC=t1.ITEM_NAME_ARABIC,i.PRICE=t1.PRICE,
	i.isExtra=t1.isExtra,i.Ischoice=t1.Ischoice
	from tblItems i 
	inner join @dttblItemsSync t1 on t1.HID=i.HID
	where i.HID is not null

	SET IDENTITY_INSERT [dbo].[tblItems] OFF
END
GO
/****** Object:  StoredProcedure [dbo].[sp_MobileGetGroupModifierAllergenMasterData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_MobileGetGroupModifierAllergenMasterData]
AS
BEGIN
	-- tblGroup_Modifier_Master data
	select ID,GroupNameEng,GroupNameArb,isnull(Type,0) Type,isnull(MinSelect,0) MinSelect,
	isnull(MaxSelect,0) MaxSelect,isnull(Seq_Num,0) Seq_Num,
	isnull(BrandId,0) BrandId
	from tblGroup_Modifier_Master

	--tblGroup_Modifier_Type
	select ID,TypeName_Deliverect,TypeName_TMM
	from tblGroup_Modifier_Type

	--tblGroup_Modifier_Sub_Details
	select ID,isnull(GroupID,0) GroupID,isnull(ItemID,0) ItemID,isnull(ExtraID,0) ExtraID,
	isnull(Seq_Num,0) Seq_Num
	from tblGroup_Modifier_Sub_Details

	--tblGroup_Modifier_Details
	select 
	gmd.id,isnull(gmd.MainItemId,0) MainItemId,isnull(gmd.GroupId,0) GroupId,gmd.Deleted,
	isnull(gmd.ItemID,0) ItemID,isnull(gmd.Seq_Num,0) Seq_Num,
	it.PRICE
	from tblGroup_Modifier_Details gmd 
	inner join tblItems it on gmd.ItemID= it.id

	--tbl_Allergen
	select al.id as allergenid,al.name,al.image,
	isnull(ala.itemid,0) as itemid, isnull(ala.id,0) as Allergen_AssignID, 
	isnull(al.Name_arabic,'') as arabicname
	from tbl_Allergen al 
	inner join tbl_Allergen_Assign ala on ala.allergenid= al.id
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_AddPayment]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_AddPayment]
      @InvoiceNo      BIGINT
    , @PaymentTypeID  INT
    , @Amount         DECIMAL(18,3)
    , @AmountTendered DECIMAL(18,3) = NULL
    , @ReferenceNo    NVARCHAR(100) = NULL
    , @IsRefund       BIT           = 0
    , @UserID         INT           = NULL
    , @UserName       NVARCHAR(100) = NULL
    , @Comments       NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE()
          , @Status INT, @BranchID INT, @Due DECIMAL(18,3), @Paid DECIMAL(18,3)
          , @Err NVARCHAR(500) = NULL, @Change DECIMAL(18,3) = NULL
          , @RequiresRef BIT = 0, @LegacyCol SYSNAME = NULL;

    SELECT @Status = i.OrderStatusID
         , @BranchID = i.BranchID
         , @Due = i.FinalAmount + ISNULL(i.DeliveryCharges, 0)
    FROM   dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;

    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p WHERE p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

    SELECT @RequiresRef = pt.RequiresReference, @LegacyCol = pt.LegacyColumn
    FROM   dbo.tblInvoicePaymentType pt WHERE pt.ID = @PaymentTypeID AND ISNULL(pt.IsDeleted,0) = 0;

    IF @Status IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @LegacyCol IS NULL AND NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType WHERE ID = @PaymentTypeID AND ISNULL(IsDeleted,0)=0)
        SET @Err = N'Unknown payment type.';
    ELSE IF @Amount IS NULL OR @Amount <= 0
        SET @Err = N'Amount must be greater than zero.';
    ELSE IF @Status = 7 AND @IsRefund = 0
        SET @Err = N'Cannot take payment on a cancelled order.';
    ELSE IF @IsRefund = 0 AND (@Paid + @Amount) > @Due + 0.001
        -- Overpayment is almost always a keying error, and it silently breaks
        -- the cash-up. Change due is handled by AmountTendered, not by
        -- recording more money than the order is worth.
        SET @Err = CONCAT(N'Payment exceeds the amount due. Due ', @Due, N', already paid ', @Paid, N'.');
    ELSE IF @IsRefund = 1 AND @Amount > @Paid + 0.001
        SET @Err = CONCAT(N'Refund exceeds the amount paid (', @Paid, N').');
    ELSE IF @RequiresRef = 1 AND NULLIF(LTRIM(RTRIM(@ReferenceNo)),'') IS NULL
        SET @Err = N'A reference number is required for this payment type.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message='Fail', InvoiceNo=@InvoiceNo, AmountPaid=@Paid, AmountDue=@Due,
               ChangeGiven=CAST(NULL AS DECIMAL(18,3)), PaymentStatus=CAST(NULL AS VARCHAR(10)),
               ErrorMessage=@Err;
        RETURN;
    END

    IF @IsRefund = 0 AND @AmountTendered IS NOT NULL AND @AmountTendered > @Amount
        SET @Change = @AmountTendered - @Amount;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.tblInvoicePayment
            (PaymentTypeID, InvoiceId, PaymentType, BranchId, Amount, AmountTendered, ChangeGiven,
             ReferenceNo, IsRefund, ReceivedBy, ReceivedOn, Comments, isdeleted)
        SELECT @PaymentTypeID, @InvoiceNo, pt.PaymentTypeName, @BranchID, @Amount, @AmountTendered, @Change,
               @ReferenceNo, @IsRefund, @UserID, @Now, @Comments, 0
        FROM   dbo.tblInvoicePaymentType pt WHERE pt.ID = @PaymentTypeID;

        SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
        FROM   dbo.tblInvoicePayment p WHERE p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

        UPDATE dbo.tblInvoice
           SET PaidDate   = CASE WHEN @Paid + 0.001 >= @Due THEN ISNULL(PaidDate, @Now) ELSE NULL END
             , ModifiedOn = @Now
             , ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        /*---- Recalculate the legacy per-method columns from the rows.
               Rebuilt rather than incremented, so a refund or a corrected row
               cannot leave the legacy totals drifting away from the truth. ----*/
        DECLARE @col SYSNAME, @sql NVARCHAR(MAX);
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT LegacyColumn FROM dbo.tblInvoicePaymentType WHERE LegacyColumn IS NOT NULL AND COL_LENGTH('dbo.tblInvoice', LegacyColumn) IS NOT NULL;
        OPEN c; FETCH NEXT FROM c INTO @col;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql = N'
                UPDATE i SET ' + QUOTENAME(@col) + N' = ISNULL(x.Amt, 0)
                FROM dbo.tblInvoice i
                OUTER APPLY (
                    SELECT Amt = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                    FROM   dbo.tblInvoicePayment p
                    JOIN   dbo.tblInvoicePaymentType t ON t.ID = p.PaymentTypeID
                    WHERE  p.InvoiceId = @inv AND ISNULL(p.isdeleted,0) = 0 AND t.LegacyColumn = @c
                ) x
                WHERE i.InvoiceNo = @inv;';
            EXEC sp_executesql @sql, N'@inv BIGINT, @c SYSNAME', @inv = @InvoiceNo, @c = @col;
            FETCH NEXT FROM c INTO @col;
        END
        CLOSE c; DEALLOCATE c;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, CASE WHEN @IsRefund = 1 THEN 'Refund' ELSE 'Payment' END,
                @UserID, @UserName,
                CONCAT(N'Type=', @PaymentTypeID, N' Amount=', @Amount,
                       N' Ref=', ISNULL(@ReferenceNo, N''), N' PaidNow=', @Paid, N' Due=', @Due));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message='Fail', InvoiceNo=@InvoiceNo, AmountPaid=@Paid, AmountDue=@Due,
               ChangeGiven=CAST(NULL AS DECIMAL(18,3)), PaymentStatus=CAST(NULL AS VARCHAR(10)),
               ErrorMessage=ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message       = 'Success'
         , InvoiceNo     = @InvoiceNo
         , AmountPaid    = @Paid
         , AmountDue     = @Due
         , ChangeGiven   = @Change
         , PaymentStatus = CASE WHEN @Paid <= 0 THEN 'Unpaid'
                                WHEN @Paid + 0.001 >= @Due THEN 'Paid' ELSE 'Partial' END
         , ErrorMessage  = CAST(NULL AS NVARCHAR(500));
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_CancelOrder]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_CancelOrder]
      @InvoiceNo     BIGINT
    , @CancelReasonID INT           = NULL
    , @Comments      NVARCHAR(1000)
    , @Disposition   TINYINT                    -- 1 = Waste, 2 = Reuse
    , @UserID        INT           = NULL
    , @UserName      NVARCHAR(100) = NULL
    , @RoleID        INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE(), @From INT, @Paid DECIMAL(18,3), @Err NVARCHAR(500) = NULL;

    SELECT @From = i.OrderStatusID FROM dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;

    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p WHERE p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

    IF @From IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @From IN (7, 8)
        SET @Err = N'Order is already cancelled or refunded.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblPOS_OrderStatusTransition WHERE FromStatusID = @From AND ToStatusID = 7)
        SET @Err = N'An order in this status cannot be cancelled.';
    ELSE IF @Disposition NOT IN (1, 2)
        SET @Err = N'Select Waste or Reuse.';
    ELSE IF NULLIF(LTRIM(RTRIM(@Comments)), '') IS NULL
        SET @Err = N'A cancellation comment is required.';
    ELSE IF @Paid > 0
        -- Cancelling paid money without refunding it makes the cash drawer
        -- disagree with the system at end of day, and the difference is very
        -- hard to trace afterwards.
        SET @Err = N'This order has payments recorded. Refund it before cancelling.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, ErrorMessage = @Err;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblInvoice
           SET OrderStatusID     = 7
             , OrderStatus       = 7
             , CancelReasonID    = @CancelReasonID
             , CancelComments    = @Comments
             , CancelDisposition = @Disposition
             , Closed            = 1
             , ClosedDate        = @Now
             , ModifiedOn        = @Now
             , ModifiedBy        = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        -- Waste marks the lines; Reuse does not, because the stock goes back.
        UPDATE dbo.tblOrder
           SET Waste                = CASE WHEN @Disposition = 1 THEN 1 ELSE 0 END
             , DeleteOrderComment   = @Comments
             , DeletePasswordUserID = CAST(@UserID AS NVARCHAR(50))
             , DeletedDate          = @Now
         WHERE InvoiceNo = @InvoiceNo;

        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, ChangedOn, Comments)
        VALUES (@InvoiceNo, @From, 7, @UserID, @UserName, @Now,
                CONCAT(CASE WHEN @Disposition = 1 THEN N'[Waste] ' ELSE N'[Reuse] ' END, @Comments));

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'Cancel', @UserID, @UserName,
                CONCAT(N'Reason=', ISNULL(@CancelReasonID,0),
                       N' Disposition=', CASE WHEN @Disposition = 1 THEN N'Waste' ELSE N'Reuse' END,
                       N' Comments=', @Comments));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message='Fail', InvoiceNo=@InvoiceNo, ErrorMessage=ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message='Success', InvoiceNo=@InvoiceNo, ErrorMessage=CAST(NULL AS NVARCHAR(500));
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_CancelOrderReject]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_CancelOrderReject]
      @InvoiceNo  BIGINT
    , @Comments   NVARCHAR(500)
    , @Password   NVARCHAR(100)
    , @UserID     INT           = NULL        -- who is logged in at the counter
    , @UserName   NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME = GETDATE();
    DECLARE @From INT, @Err NVARCHAR(500), @ApprovedByID INT, @ApprovedBy NVARCHAR(100);

    SET @Comments = NULLIF(LTRIM(RTRIM(ISNULL(@Comments, N''))), N'');

    SELECT @From = i.OrderStatusID
    FROM   dbo.tblInvoice i
    WHERE  i.InvoiceNo = @InvoiceNo AND ISNULL(i.Deleted,0) = 0;

    /*---- who does this password belong to? ------------------------------
      Looked up dynamically so a database without the column returns "no
      match" instead of stopping this procedure from being created at all.
      Blank passwords never match: a manager row with an empty deletePassword
      would otherwise let an empty box through.
    ---------------------------------------------------------------------*/
    IF COL_LENGTH('dbo.tblUser', 'deletePassword') IS NOT NULL
       AND NULLIF(LTRIM(RTRIM(ISNULL(@Password, N''))), N'') IS NOT NULL
    BEGIN
        DECLARE @sql NVARCHAR(MAX) = N'
            SELECT TOP (1) @pID = u.ID, @pName = u.NAME
            FROM   dbo.tblUser u
            WHERE  ISNULL(u.RoleID, 0) = 1
              AND  NULLIF(LTRIM(RTRIM(ISNULL(u.deletePassword, N''''))), N'''') IS NOT NULL
              AND  LTRIM(RTRIM(u.deletePassword)) = LTRIM(RTRIM(@pPwd))
            ORDER BY u.ID;';

        EXEC sp_executesql @sql,
             N'@pPwd NVARCHAR(100), @pID INT OUTPUT, @pName NVARCHAR(100) OUTPUT',
             @pPwd = @Password, @pID = @ApprovedByID OUTPUT, @pName = @ApprovedBy OUTPUT;
    END

    /*---- refuse, in the order the operator would hit them ---------------*/
    IF @From IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @From = 6
        SET @Err = N'This order is already cancelled.';
    ELSE IF @Comments IS NULL
        SET @Err = N'A reason is required.';
    ELSE IF @ApprovedByID IS NULL
        -- One message for a wrong password and for a password that belongs to
        -- someone who is not a manager. Telling them apart would say which
        -- accounts exist.
        SET @Err = N'That password is not recognised.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, ErrorMessage = @Err;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- The reason is APPENDED. Comments may already hold what the customer
        -- asked for ("no onions"), and overwriting that to record why staff
        -- rejected the order destroys the only copy of it.
        UPDATE dbo.tblInvoice
           SET Comments      = LEFT(
                                 CASE WHEN NULLIF(LTRIM(RTRIM(ISNULL(Comments, N''))), N'') IS NULL
                                      THEN N'[Cancelled] ' + @Comments
                                      ELSE Comments + N' | [Cancelled] ' + @Comments
                                 END, 500)
             , OrderStatusID = 6
             , OrderStatus   = 6
             , ModifiedOn    = @Now
             , ModifiedBy    = ISNULL(@UserID, @ApprovedByID)
         WHERE InvoiceNo = @InvoiceNo;

        -- Kept in step with the fuller cancel path in POS_09, so reports that
        -- read the cancellation columns see this one too.
        IF COL_LENGTH('dbo.tblInvoice', 'CancelComments') IS NOT NULL
            UPDATE dbo.tblInvoice SET CancelComments = @Comments WHERE InvoiceNo = @InvoiceNo;

        IF COL_LENGTH('dbo.tblInvoice', 'Closed') IS NOT NULL
            UPDATE dbo.tblInvoice SET Closed = 1, ClosedDate = @Now WHERE InvoiceNo = @InvoiceNo;

        -- Who approved it, on every line. DeletePasswordUserID is the existing
        -- column for exactly this.
        IF COL_LENGTH('dbo.tblOrder', 'DeletePasswordUserID') IS NOT NULL
            UPDATE dbo.tblOrder
               SET DeleteOrderComment   = @Comments
                 , DeletePasswordUserID = CAST(@ApprovedByID AS NVARCHAR(50))
                 , DeletedDate          = @Now
             WHERE InvoiceNo = @InvoiceNo;

        INSERT INTO dbo.tblPOS_OrderStatusHistory
            (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, ChangedOn, Comments)
        VALUES (@InvoiceNo, @From, 6, ISNULL(@UserID, @ApprovedByID),
                ISNULL(@UserName, @ApprovedBy), @Now,
                CONCAT(N'[Cancelled] ', @Comments, N' (approved by ', @ApprovedBy, N')'));

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'Cancel', ISNULL(@UserID, @ApprovedByID),
                ISNULL(@UserName, @ApprovedBy),
                CONCAT(N'From=', @From, N' To=6 ApprovedByUserID=', @ApprovedByID,
                       N' Comments=', @Comments));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT   Message        = 'Success'
           , InvoiceNo      = @InvoiceNo
           , OrderStatusID  = 6
           , ApprovedByID   = @ApprovedByID
           , ApprovedBy     = @ApprovedBy
           , ErrorMessage   = CAST(NULL AS NVARCHAR(500));
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_ChangeStatus]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_ChangeStatus]
      @InvoiceNos  dbo.TVP_POS_BigIntList READONLY
    , @ToStatusID  INT
    , @UserID      INT           = NULL
    , @UserName    NVARCHAR(100) = NULL
    , @RoleID      INT           = NULL
    , @Comments    NVARCHAR(1000)= NULL
    , @DriverID    INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE();

    IF NOT EXISTS (SELECT 1 FROM dbo.tblOrderStatus WHERE OrderStatusID = @ToStatusID)
    BEGIN
        SELECT Message='Fail', Updated=0, ErrorMessage=N'Unknown target status.';
        SELECT TOP 0 InvoiceNo=CAST(NULL AS BIGINT), Reason=CAST(NULL AS NVARCHAR(200));
        RETURN;
    END

    -- Evaluate every candidate once, so the outcome per order is known up front.
    DECLARE @eval TABLE
    (
          InvoiceNo    BIGINT PRIMARY KEY
        , FromStatusID INT
        , OrderType    INT
        , BranchID     INT
        , Allowed      BIT
        , Reason       NVARCHAR(200)
    );

    INSERT INTO @eval (InvoiceNo, FromStatusID, OrderType, BranchID, Allowed, Reason)
    SELECT  i.InvoiceNo
          , i.OrderStatusID
          , i.OrderType
          , i.BranchID
          -- The move-forward sequence used to be enforced here: a target
          -- status had to have a matching row in tblPOS_OrderStatusTransition
          -- or the whole change was refused with "Not a permitted transition
          -- from X." That table now only gates a role requirement where one
          -- is configured - any FromStatus -> ToStatus pair is otherwise
          -- open, so the picker's "confirm before committing" step is the
          -- guard against a stray tap, not a hard-coded sequence.
          , Allowed = CASE
                        WHEN ISNULL(i.Deleted,0) = 1 THEN 0
                        WHEN i.OrderStatusID = @ToStatusID THEN 0
                        WHEN EXISTS (SELECT 1 FROM dbo.tblPOS_OrderStatusTransition t
                                     WHERE t.FromStatusID = i.OrderStatusID AND t.ToStatusID = @ToStatusID
                                       AND t.RequiresRole IS NOT NULL
                                       AND (@RoleID IS NULL OR @RoleID > t.RequiresRole)) THEN 0
                        WHEN (i.OrderType = 1 AND s.AppliesToPickup = 0)
                          OR (i.OrderType <> 1 AND s.AppliesToDelivery = 0) THEN 0
                        ELSE 1
                      END
          , Reason  = CASE
                        WHEN ISNULL(i.Deleted,0) = 1 THEN N'Order is deleted.'
                        WHEN i.OrderStatusID = @ToStatusID THEN N'Already in that status.'
                        WHEN EXISTS (SELECT 1 FROM dbo.tblPOS_OrderStatusTransition t
                                     WHERE t.FromStatusID = i.OrderStatusID AND t.ToStatusID = @ToStatusID
                                       AND t.RequiresRole IS NOT NULL
                                       AND (@RoleID IS NULL OR @RoleID > t.RequiresRole))
                             THEN N'Your role cannot make this change.'
                        WHEN (i.OrderType = 1 AND s.AppliesToPickup = 0)
                          OR (i.OrderType <> 1 AND s.AppliesToDelivery = 0)
                             THEN N'Status does not apply to this order type.'
                        ELSE NULL
                      END
    FROM      dbo.tblInvoice i
    JOIN      @InvoiceNos    n   ON n.Value = i.InvoiceNo
    JOIN      dbo.tblOrderStatus s   ON s.OrderStatusID = @ToStatusID
    LEFT JOIN dbo.tblOrderStatus cur ON cur.OrderStatusID = i.OrderStatusID;

    -- Handing to a driver without saying which driver leaves the dispatch board
    -- unusable and the delivery unattributable.
    IF @ToStatusID = 4 AND @DriverID IS NULL
        UPDATE @eval SET Allowed = 0, Reason = N'Select a driver first.' WHERE Allowed = 1;

    DECLARE @Updated INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE i
           SET i.OrderStatusID    = @ToStatusID
             , i.OrderStatus      = @ToStatusID          -- legacy column kept in step
             , i.Driver           = CASE WHEN @DriverID IS NOT NULL THEN @DriverID ELSE i.Driver END
             , i.DriverName       = CASE WHEN @DriverID IS NOT NULL
                                         THEN (SELECT TOP 1 d.DriverName FROM dbo.tblDriver d WHERE d.DriverID = @DriverID)
                                         ELSE i.DriverName END
             , i.DriverAssignDate = CASE WHEN @ToStatusID = 4 THEN @Now ELSE i.DriverAssignDate END
             , i.Closed           = CASE WHEN s.IsTerminal = 1 THEN 1 ELSE i.Closed END
             , i.ClosedDate       = CASE WHEN s.IsTerminal = 1 AND i.ClosedDate IS NULL THEN @Now ELSE i.ClosedDate END
             , i.ModifiedOn       = @Now
             , i.ModifiedBy       = @UserID
        FROM dbo.tblInvoice i
        JOIN @eval e ON e.InvoiceNo = i.InvoiceNo AND e.Allowed = 1
        JOIN dbo.tblOrderStatus s ON s.OrderStatusID = @ToStatusID;

        SET @Updated = @@ROWCOUNT;

        -- Delivered also means the food left the kitchen: keep tblOrder in step
        -- so kitchen and line-level reports agree with the header.
        IF @ToStatusID = 6
            UPDATE o SET o.Delivered = 1
            FROM dbo.tblOrder o
            JOIN @eval e ON e.InvoiceNo = o.InvoiceNo AND e.Allowed = 1;

        IF @ToStatusID = 2
            UPDATE o SET o.Prepared = 1
            FROM dbo.tblOrder o
            JOIN @eval e ON e.InvoiceNo = o.InvoiceNo AND e.Allowed = 1;

        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, ChangedOn, Comments, DriverID)
        SELECT e.InvoiceNo, e.FromStatusID, @ToStatusID, @UserID, @UserName, @Now, @Comments, @DriverID
        FROM   @eval e WHERE e.Allowed = 1;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        SELECT 'Invoice', e.InvoiceNo, 'StatusChange', @UserID, @UserName,
               CONCAT(N'From=', e.FromStatusID, N' To=', @ToStatusID,
                      CASE WHEN @DriverID IS NOT NULL THEN CONCAT(N' Driver=', @DriverID) ELSE N'' END)
        FROM   @eval e WHERE e.Allowed = 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message='Fail', Updated=0, ErrorMessage=ERROR_MESSAGE();
        SELECT TOP 0 InvoiceNo=CAST(NULL AS BIGINT), Reason=CAST(NULL AS NVARCHAR(200));
        RETURN;
    END CATCH

    SELECT Message = CASE WHEN @Updated = 0 THEN 'Fail' ELSE 'Success' END
         , Updated = @Updated
         , Skipped = (SELECT COUNT(*) FROM @eval WHERE Allowed = 0)
         , ErrorMessage = CAST(NULL AS NVARCHAR(500));

    -- Second result set: exactly which orders did not move, and why.
    SELECT InvoiceNo, Reason FROM @eval WHERE Allowed = 0 ORDER BY InvoiceNo;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_ChangeToPickup]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_ChangeToPickup]
      @InvoiceNo   BIGINT
    , @BranchID    INT
    , @InvoiceType INT           = 3
    , @UserID      INT           = NULL
    , @UserName    NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE()
          , @Err NVARCHAR(500) = NULL, @Warning NVARCHAR(500) = NULL
          , @Status INT, @OrderType INT, @FromBranch INT
          , @OldCharge DECIMAL(18,3), @Bill DECIMAL(18,3), @Discount DECIMAL(18,3)
          , @Paid DECIMAL(18,3), @NewNet DECIMAL(18,3);

    SELECT @Status     = i.OrderStatusID
         , @OrderType  = i.OrderType
         , @FromBranch = i.BranchID
         , @OldCharge  = ISNULL(i.DeliveryCharges, 0)
         , @Bill       = ISNULL(i.BillAmount, 0)
         , @Discount   = ISNULL(i.Discount, 0)
    FROM   dbo.tblInvoice i
    WHERE  i.InvoiceNo = @InvoiceNo AND ISNULL(i.Deleted,0) = 0;

    IF @Status IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @Status IN (6, 7, 8)
        SET @Err = N'A cancelled or completed order cannot be changed to pickup.';
    ELSE IF @Status IN (4, 5)
        -- The food is already on a bike. Telling the system the customer is
        -- collecting it does not bring the driver back.
        SET @Err = N'Order is already with a driver - recall it first.';
    ELSE IF @OrderType = 1
        SET @Err = N'This order is already a pickup.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblbranch
                        WHERE id = @BranchID AND ISNULL(IsDeleted,0) = 0 AND ISNULL(IsActive,1) = 1)
        SET @Err = N'Select a branch for the customer to collect from.';
    ELSE IF @InvoiceType IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM dbo.tblInvoiceType_Master WHERE ID = @InvoiceType)
        SET @Err = CONCAT(N'Invoice type ', @InvoiceType, N' does not exist in tblInvoiceType_Master.');

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, ErrorMessage = @Err,
               Warning = CAST(NULL AS NVARCHAR(500)),
               NetPayable = CAST(NULL AS DECIMAL(18,3));
        RETURN;
    END

    SET @NewNet = (@Bill - @Discount);   -- delivery charge is now zero

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblInvoice
           SET InvoiceType     = @InvoiceType
             , OrderType       = 1
             , BranchID        = @BranchID
             , DeliveryCharges = 0
             , ModifiedOn      = @Now
             , ModifiedBy      = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        -- Line rows carry BranchID, and every branch-level item report reads it
        -- from there rather than from the header.
        UPDATE dbo.tblOrder SET BranchID = @BranchID WHERE InvoiceNo = @InvoiceNo;

        -- A move between branches is a transfer whichever way it was triggered,
        -- so it lands in the same table the transfer screen writes to.
        IF @FromBranch <> @BranchID
            INSERT INTO dbo.tblPOS_OrderTransfer (InvoiceNo, FromBranchID, ToBranchID, Reason, TransferredBy, TransferredOn)
            VALUES (@InvoiceNo, @FromBranch, @BranchID, N'Changed to pickup', @UserID, @Now);

        INSERT INTO dbo.tblPOS_OrderStatusHistory
            (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, ChangedOn, Comments)
        VALUES (@InvoiceNo, @Status, @Status, @UserID, @UserName, @Now,
                CONCAT(N'Changed to pickup at branch ', @BranchID,
                       CASE WHEN @OldCharge > 0
                            THEN CONCAT(N'; delivery charge ', @OldCharge, N' removed')
                            ELSE N'' END));

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'ChangeToPickup', @UserID, @UserName,
                CONCAT(N'Branch=', @FromBranch, N'->', @BranchID,
                       N' InvoiceType=', @InvoiceType,
                       N' OrderType=1 DeliveryCharges=', @OldCharge, N'->0'));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, ErrorMessage = ERROR_MESSAGE(),
               Warning = CAST(NULL AS NVARCHAR(500)), NetPayable = CAST(NULL AS DECIMAL(18,3));
        RETURN;
    END CATCH

    /*---- did removing the charge leave them overpaid? --------------------*/
    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p
    WHERE  p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

    IF @Paid > @NewNet + 0.001
        SET @Warning = CONCAT(N'The order is now overpaid by ',
                              CAST(@Paid - @NewNet AS DECIMAL(18,3)),
                              N' - the delivery charge has been removed. Refund the difference.');
    ELSE IF @OldCharge > 0
        SET @Warning = CONCAT(N'Delivery charge of ', @OldCharge, N' removed.');

    SELECT   Message      = 'Success'
           , InvoiceNo    = @InvoiceNo
           , BranchID     = @BranchID
           , InvoiceType  = @InvoiceType
           , NetPayable   = @NewNet
           , AmountPaid   = @Paid
           , Warning      = @Warning
           , ErrorMessage = CAST(NULL AS NVARCHAR(500));
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_AddItems]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_AddItems]
      @InvoiceNo          BIGINT
    , @DineInTableTypeID  INT           = 0
    , @UserID             INT           = NULL
    , @UserName           NVARCHAR(100) = NULL
    , @dtOrderItems       dbo.TVP_POS_OrderItem READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE(), @Status INT, @BranchID INT, @WaiterID INT
          , @DiscountTypeID INT, @Discount DECIMAL(18,3), @Bill DECIMAL(18,3), @Added INT;

    SELECT @Status = OrderStatusID, @BranchID = BranchID, @WaiterID = WaiterID
         , @DiscountTypeID = DiscountTypeID, @Discount = ISNULL(Discount, 0)
    FROM   dbo.tblInvoice WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;

    IF @Status IS NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'Bill not found.'; RETURN;
    END
    IF @Status IN (6, 7, 8)
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'This bill is cancelled or refunded.'; RETURN;
    END
    IF NOT EXISTS (SELECT 1 FROM @dtOrderItems)
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'Add at least one item.'; RETURN;
    END

    -- @DineInTableTypeID = -1 means a Take Away bill: new lines carry whatever
    -- the bill's first line already carries instead of the Dine-In type.
    DECLARE @LineTableType INT = @DineInTableTypeID;
    IF @DineInTableTypeID < 0
    BEGIN
        SET @LineTableType = NULL;
        SELECT TOP 1 @LineTableType = o.TableType FROM dbo.tblOrder o WHERE o.InvoiceNo = @InvoiceNo ORDER BY o.OrderID;
        SET @LineTableType = ISNULL(@LineTableType, 0);
    END

    DECLARE @lines TABLE
    (
          Seq INT IDENTITY(1,1) PRIMARY KEY, ResolvedItemID INT NULL, ItemName NVARCHAR(200) NULL
        , Quantity INT NOT NULL, UnitPrice DECIMAL(18,3) NOT NULL, LineType TINYINT NOT NULL
        , CartItemUniqID INT NULL, Comments NVARCHAR(MAX) NULL, Extra NVARCHAR(MAX) NULL
    );

    INSERT INTO @lines (ResolvedItemID, ItemName, Quantity, UnitPrice, LineType, CartItemUniqID, Comments, Extra)
    SELECT  it.ID, it.ITEM_NAME
          , CASE WHEN d.Quantity < 1 THEN 1 ELSE d.Quantity END
          , CAST(ISNULL(it.PRICE, 0) AS DECIMAL(18,3))
          , ISNULL(d.LineType, 1), d.CartItemUniqID, d.Comments, d.Extra
    FROM    @dtOrderItems d
    CROSS APPLY (SELECT TOP 1 t.ID, t.ITEM_NAME, t.PRICE FROM dbo.tblItems t
                 WHERE t.ID = d.ItemID OR (d.HID IS NOT NULL AND t.HID = d.HID)
                 ORDER BY CASE WHEN t.ID = d.ItemID THEN 0 ELSE 1 END) it;

    IF NOT EXISTS (SELECT 1 FROM @lines)
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'None of those items could be found.'; RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot
        )
        SELECT @InvoiceNo, l.ResolvedItemID, l.Quantity, l.UnitPrice, 0, l.Comments, l.Extra
             , ISNULL(@UserID, @WaiterID), 0, 0, 0, 0, 0
             , @Now, @LineTableType, 0, @DiscountTypeID, 0, @BranchID
             , l.CartItemUniqID, l.LineType, l.ItemName
        FROM @lines l ORDER BY l.Seq;
        SET @Added = @@ROWCOUNT;

        SELECT @Bill = CAST(ISNULL(SUM(Quantity * Price), 0) AS DECIMAL(18,3))
        FROM   dbo.tblOrder WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;

        UPDATE dbo.tblInvoice
           SET BillAmount = @Bill, ModifiedOn = @Now, ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'DineInAddItems', @UserID, @UserName,
                CONCAT(N'Lines=', @Added, N'; NewBill=', @Bill));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300))
         , InvoiceNo = @InvoiceNo, LinesAdded = @Added, BillAmount = @Bill
         , NetPayable = @Bill - @Discount;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_AttachInvoice]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_AttachInvoice]
      @InvoiceNo          BIGINT
    , @TableID            INT
    , @DineInTableTypeID  INT           = 0
    , @UserID             INT           = NULL
    , @UserName           NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT, @Persons INT, @TableNo NVARCHAR(30);

    SELECT @SessionID = s.SessionID, @Persons = s.Persons
    FROM   dbo.tblPOS_TableSession s WHERE s.TableID = @TableID AND s.ClosedOn IS NULL;

    SELECT @TableNo = LTRIM(RTRIM(CAST(Table_No AS NVARCHAR(30)))) FROM dbo.tblTable WHERE TableID = @TableID;

    IF @SessionID IS NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'The table was freed before the order was saved.';
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblInvoice
           SET TableID = @TableID, TableSessionID = @SessionID, Person = ISNULL(@Persons, 1)
             , WaiterID = ISNULL(@UserID, WaiterID)
         WHERE InvoiceNo = @InvoiceNo;

        UPDATE dbo.tblOrder SET TableType = @DineInTableTypeID, WaiterID = ISNULL(@UserID, WaiterID)
         WHERE InvoiceNo = @InvoiceNo;

        UPDATE dbo.tblPOS_OrderStatusHistory
           SET Comments = N'Dine-In order, table ' + ISNULL(@TableNo, N'?')
             , ChangedBy = @UserID, ChangedByName = ISNULL(@UserName, ChangedByName)
         WHERE InvoiceNo = @InvoiceNo AND FromStatusID IS NULL;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'DineInAttach', @UserID, @UserName,
                CONCAT(N'TableID=', @TableID, N'; Table=', @TableNo, N'; Session=', @SessionID));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_CloseIfSettled]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_CloseIfSettled]
      @TableID   INT
    , @Reason    NVARCHAR(50)  = N'Settled'
    , @UserID    INT           = NULL
    , @UserName  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT =
        (SELECT SessionID FROM dbo.tblPOS_TableSession WHERE TableID = @TableID AND ClosedOn IS NULL);
    DECLARE @Live INT = 0, @Unpaid INT = 0, @Ever INT = 0;

    IF @SessionID IS NOT NULL
    BEGIN
        SELECT @Ever = COUNT(*) FROM dbo.tblInvoice WHERE TableSessionID = @SessionID;

        SELECT @Live   = COUNT(*)
             , @Unpaid = SUM(CASE WHEN i.FinalAmount + ISNULL(i.DeliveryCharges, 0) >
                                       ISNULL(pp.Paid, 0) + 0.001 THEN 1 ELSE 0 END)
        FROM   dbo.tblInvoice i
        OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                     FROM dbo.tblInvoicePayment p
                     WHERE p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0) pp
        WHERE  i.TableSessionID = @SessionID
          AND  ISNULL(i.Deleted, 0) = 0
          AND  ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8);
    END

    IF @SessionID IS NOT NULL AND @Ever > 0 AND ISNULL(@Unpaid, 0) = 0
    BEGIN
        UPDATE dbo.tblPOS_TableSession
           SET ClosedOn = GETDATE(), ClosedBy = @UserID, ClosedByName = @UserName, CloseReason = @Reason
         WHERE SessionID = @SessionID;
        UPDATE dbo.tblTable SET Status = 0 WHERE TableID = @TableID;

        SELECT Message = 'Success', Freed = CAST(1 AS BIT);
        RETURN;
    END

    SELECT Message = 'Success', Freed = CAST(0 AS BIT);
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_Context]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_Context]
      @BrandID  INT = NULL
    , @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DineIn INT, @TakeAway INT, @WalkIn INT, @DineInTT INT, @Cash INT, @BranchBrand INT;

    -- the brand a branch belongs to, when the user record carries none
    IF @BranchID IS NOT NULL AND COL_LENGTH('dbo.tblbranch', 'BrandID') IS NOT NULL
        EXEC sp_executesql N'SELECT TOP 1 @bb = BrandID FROM dbo.tblbranch WHERE id = @b;',
             N'@b INT, @bb INT OUTPUT', @b = @BranchID, @bb = @BranchBrand OUTPUT;
    IF ISNULL(@BrandID, 0) = 0 SET @BrandID = @BranchBrand;

    -- bills start against plain Cash; the real tender is recorded by Pay
    SELECT TOP 1 @Cash = ID FROM dbo.tblInvoicePaymentType
    WHERE  IsCash = 1 AND ISNULL(IsCOD, 0) = 0 AND ISNULL(IsDeleted, 0) = 0 ORDER BY Seqnum, ID;

    SELECT TOP 1 @DineIn = ID FROM dbo.tblInvoiceType_Master
    WHERE  REPLACE(REPLACE(Name, N'-', N''), N' ', N'') = N'DineIn' ORDER BY ID;

    SELECT TOP 1 @TakeAway = ID FROM dbo.tblInvoiceType_Master
    WHERE  REPLACE(REPLACE(Name, N'-', N''), N' ', N'') IN (N'TakeAway', N'Takeaway') ORDER BY ID;

    SELECT TOP 1 @DineInTT = ID FROM dbo.tblTableType
    WHERE  REPLACE(REPLACE(Description, N'-', N''), N' ', N'') = N'DineIn' ORDER BY ID;

    SELECT TOP 1 @WalkIn = id FROM dbo.tblCustomer
    WHERE  firstName = N'Walk-in Customer' AND mobile IS NULL AND ISNULL(IsDeleted, 0) = 0
    ORDER BY id;

    IF @WalkIn IS NULL
    BEGIN
        INSERT INTO dbo.tblCustomer (firstName, BrandID) VALUES (N'Walk-in Customer', @BrandID);
        SET @WalkIn = CAST(SCOPE_IDENTITY() AS INT);
    END

    SELECT DineInTypeID      = @DineIn
         , TakeAwayTypeID    = @TakeAway
         , WalkInCustomerID  = @WalkIn
         , DineInTableTypeID = ISNULL(@DineInTT, 0)
         , CashPaymentTypeID = @Cash
         , BrandID           = ISNULL(@BrandID, 0);
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_GetFloor]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_GetFloor]
AS
BEGIN
    SET NOCOUNT ON;

    -- A TableType added to tblTable after POS_35 ran gets its area row now,
    -- so new tables never go missing for want of a tab. Rename it later in
    -- tblPOS_TableArea.
    INSERT INTO dbo.tblPOS_TableArea (TableType, AreaName, SortOrder)
    SELECT  x.TableType
          , CASE WHEN x.TableType <= 0 THEN N'Main Area' ELSE N'Floor ' + CAST(x.TableType AS NVARCHAR(10)) END
          , x.TableType
    FROM   (SELECT DISTINCT TableType = ISNULL(TableType, 0) FROM dbo.tblTable) x
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.tblPOS_TableArea a WHERE a.TableType = x.TableType);

    -- 0: areas that actually have tables
    SELECT   a.TableType, a.AreaName, a.SortOrder
    FROM     dbo.tblPOS_TableArea a
    WHERE    a.IsActive = 1
      AND    EXISTS (SELECT 1 FROM dbo.tblTable t WHERE ISNULL(t.TableType, 0) = a.TableType)
    ORDER BY a.SortOrder, a.TableType;

    -- 1: tables
    SELECT   f.*
    FROM     dbo.fn_POS_DineIn_Tables() f
    ORDER BY f.TableType, TRY_CAST(f.Table_No AS INT), f.Table_No;
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_GetMenu]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_GetMenu]
    @BrandID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @catWhere NVARCHAR(MAX) = N'1 = 1', @itemWhere NVARCHAR(MAX) = N'ISNULL(i.PRICE, 0) > 0'
          , @catOrder NVARCHAR(200) = N'c.CAT_NAME', @itemOrder NVARCHAR(200) = N'i.ITEM_NAME'
          , @catAr NVARCHAR(100) = N'CAST(NULL AS NVARCHAR(200))'
          , @itemAr NVARCHAR(100) = N'CAST(NULL AS NVARCHAR(200))'
          , @sql NVARCHAR(MAX);

    IF COL_LENGTH('dbo.tblCategory', 'Deleted')  IS NOT NULL SET @catWhere += N' AND ISNULL(c.Deleted, 0) = 0';
    IF COL_LENGTH('dbo.tblCategory', 'IsActive') IS NOT NULL SET @catWhere += N' AND ISNULL(c.IsActive, 1) = 1';
    IF COL_LENGTH('dbo.tblCategory', 'SEQ_NUM')  IS NOT NULL SET @catOrder  = N'ISNULL(c.SEQ_NUM, 9999), c.CAT_NAME';
    IF COL_LENGTH('dbo.tblCategory', 'CAT_NAME_ARABIC') IS NOT NULL SET @catAr = N'c.CAT_NAME_ARABIC';

    IF @BrandID > 0 AND COL_LENGTH('dbo.tblCategory', 'BrandID') IS NOT NULL
    BEGIN
        DECLARE @hasBrand BIT = 0;
        EXEC sp_executesql N'IF EXISTS (SELECT 1 FROM dbo.tblCategory WHERE BrandID = @b) SET @h = 1;',
             N'@b INT, @h BIT OUTPUT', @b = @BrandID, @h = @hasBrand OUTPUT;
        IF @hasBrand = 1 SET @catWhere += N' AND c.BrandID = @BrandID';
    END

    IF COL_LENGTH('dbo.tblItems', 'Deleted')  IS NOT NULL SET @itemWhere += N' AND ISNULL(i.Deleted, 0) = 0';
    IF COL_LENGTH('dbo.tblItems', 'IsActive') IS NOT NULL SET @itemWhere += N' AND ISNULL(i.IsActive, 1) = 1';
    IF COL_LENGTH('dbo.tblItems', 'ITEM_NAME_ARABIC') IS NOT NULL SET @itemAr = N'i.ITEM_NAME_ARABIC';
    IF COL_LENGTH('dbo.tblItems', 'Seq_No') IS NOT NULL       SET @itemOrder = N'ISNULL(i.Seq_No, 9999), i.ITEM_NAME';
    ELSE IF COL_LENGTH('dbo.tblItems', 'SEQ_NUM') IS NOT NULL SET @itemOrder = N'ISNULL(i.SEQ_NUM, 9999), i.ITEM_NAME';

    SET @sql = N'
        SELECT  c.CAT_NUM, c.CAT_NAME, CAT_NAME_ARABIC = ' + @catAr + N'
              , CatSeq = ROW_NUMBER() OVER (ORDER BY ' + @catOrder + N')
        INTO    #cats
        FROM    dbo.tblCategory c
        WHERE   ' + @catWhere + N';

        SELECT  ItemID = i.ID, i.CAT_NUM, i.ITEM_NAME, ITEM_NAME_ARABIC = ' + @itemAr + N'
              , PRICE = CAST(i.PRICE AS DECIMAL(18,3)), RowSeq = ROW_NUMBER() OVER (ORDER BY ' + @itemOrder + N')
        INTO    #items
        FROM    dbo.tblItems i
        WHERE   ' + @itemWhere + N' AND i.CAT_NUM IN (SELECT CAT_NUM FROM #cats);

        SELECT  c.CAT_NUM, c.CAT_NAME, c.CAT_NAME_ARABIC, ItemCount = COUNT(*)
        FROM    #cats c JOIN #items i ON i.CAT_NUM = c.CAT_NUM
        GROUP BY c.CAT_NUM, c.CAT_NAME, c.CAT_NAME_ARABIC
        ORDER BY MIN(c.CatSeq);

        SELECT ItemID, CAT_NUM, ITEM_NAME, ITEM_NAME_ARABIC, PRICE FROM #items ORDER BY RowSeq;';

    EXEC sp_executesql @sql, N'@BrandID INT', @BrandID = @BrandID;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_GetTable]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_GetTable]
    @TableID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT =
        (SELECT SessionID FROM dbo.tblPOS_TableSession WHERE TableID = @TableID AND ClosedOn IS NULL);

    -- 0: the table
    SELECT f.*, AreaName = a.AreaName
    FROM   dbo.fn_POS_DineIn_Tables() f
    LEFT JOIN dbo.tblPOS_TableArea a ON a.TableType = f.TableType
    WHERE  f.TableID = @TableID;

    -- 1: live bills of this seating, oldest first
    SELECT  i.InvoiceNo
          , InvoiceNumShow = CAST(i.InvoiceNumShow AS NVARCHAR(30))
          , i.RunningOrder
          , i.InvoiceDate
          , i.BillAmount
          , Discount    = ISNULL(i.Discount, 0)
          , NetPayable  = i.FinalAmount + ISNULL(i.DeliveryCharges, 0)
          , AmountPaid  = ISNULL(pp.Paid, 0)
          , i.OrderStatusID
          , i.PrintCount
    FROM    dbo.tblInvoice i
    OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                 FROM   dbo.tblInvoicePayment p
                 WHERE  p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0) pp
    WHERE   @SessionID IS NOT NULL
      AND   i.TableSessionID = @SessionID
      AND   ISNULL(i.Deleted, 0) = 0
      AND   ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
    ORDER BY i.InvoiceNo;

    -- 2: lines of those bills
    SELECT  o.InvoiceNo
          , o.OrderID
          , o.ItemID
          , o.ParentOrderID
          , LineType  = ISNULL(o.LineType, 1)
          , ItemName  = ISNULL(o.ItemNameSnapshot, it.ITEM_NAME)
          , o.Quantity
          , o.Price
          , LineTotal = CAST(o.Quantity * o.Price AS DECIMAL(18,3))
          , o.Comments
          , IsTakeAway = CAST(CASE WHEN LEFT(LTRIM(ISNULL(o.Comments, N'')), 9) = N'TAKE AWAY' THEN 1 ELSE 0 END AS BIT)
          , o.OrderDate
    FROM    dbo.tblOrder o
    JOIN    dbo.tblInvoice i ON i.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblItems it ON it.ID = o.ItemID
    WHERE   @SessionID IS NOT NULL
      AND   i.TableSessionID = @SessionID
      AND   ISNULL(i.Deleted, 0) = 0
      AND   ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
      AND   ISNULL(o.Deleted, 0) = 0
    ORDER BY o.InvoiceNo, o.OrderID;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_LockTable]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_LockTable]
      @TableID   INT
    , @BranchID  INT           = NULL
    , @UserID    INT           = NULL
    , @UserName  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Err NVARCHAR(300), @Code VARCHAR(20) = 'Error', @SessionID INT, @By NVARCHAR(100);

    IF NOT EXISTS (SELECT 1 FROM dbo.tblTable WHERE TableID = @TableID)
        SET @Err = N'Table not found.';
    ELSE
    BEGIN
        SELECT @SessionID = SessionID, @By = OpenedByName
        FROM   dbo.tblPOS_TableSession WHERE TableID = @TableID AND ClosedOn IS NULL;

        IF @SessionID IS NOT NULL
            SELECT @Err = N'This table was just taken' + ISNULL(N' by ' + @By, N'') + N'.', @Code = 'Occupied';
        ELSE IF EXISTS (SELECT 1 FROM dbo.tblTable WHERE TableID = @TableID AND ISNULL(TRY_CAST(Status AS INT), 0) = 1)
            SELECT @Err = N'This table is marked occupied. Free it first.', @Code = 'Occupied';
    END

    IF @Err IS NULL
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;

            INSERT INTO dbo.tblPOS_TableSession (TableID, BranchID, OpenedBy, OpenedByName)
            VALUES (@TableID, @BranchID, @UserID, @UserName);
            SET @SessionID = CAST(SCOPE_IDENTITY() AS INT);

            UPDATE dbo.tblTable SET Status = 1 WHERE TableID = @TableID;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
            -- 2601 / 2627: another device won the race on UX_tblPOS_TableSession_Open
            IF ERROR_NUMBER() IN (2601, 2627)
                SELECT @Err = N'This table was just taken on another device.', @Code = 'Occupied';
            ELSE
                SET @Err = ERROR_MESSAGE();
        END CATCH
    END

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', Code = @Code, ErrorMessage = @Err, SessionID = CAST(NULL AS INT);
        RETURN;
    END

    SELECT Message = 'Success', Code = 'OK', ErrorMessage = CAST(NULL AS NVARCHAR(300)), SessionID = @SessionID;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_ReleaseTable]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_ReleaseTable]
      @TableID   INT
    , @Reason    NVARCHAR(50)  = N'Released'
    , @UserID    INT           = NULL
    , @UserName  NVARCHAR(100) = NULL
    , @Force     BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT =
        (SELECT SessionID FROM dbo.tblPOS_TableSession WHERE TableID = @TableID AND ClosedOn IS NULL);

    IF @Force = 0 AND @SessionID IS NOT NULL AND EXISTS
    (
        SELECT 1
        FROM   dbo.tblInvoice i
        WHERE  i.TableSessionID = @SessionID
          AND  ISNULL(i.Deleted, 0) = 0
          AND  ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
          AND  i.FinalAmount + ISNULL(i.DeliveryCharges, 0) >
               ISNULL((SELECT SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                       FROM dbo.tblInvoicePayment p
                       WHERE p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0), 0) + 0.001
    )
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'This table still has an unpaid bill. Pay or delete it first.';
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @SessionID IS NOT NULL
            UPDATE dbo.tblPOS_TableSession
               SET ClosedOn = GETDATE(), ClosedBy = @UserID, ClosedByName = @UserName, CloseReason = @Reason
             WHERE SessionID = @SessionID;

        UPDATE dbo.tblTable SET Status = 0 WHERE TableID = @TableID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_SaveLayout]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_SaveLayout]
      @UserID     INT           = NULL
    , @UserName   NVARCHAR(100) = NULL
    , @Positions  dbo.TVP_POS_TablePosition READONLY
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE t
       SET t.Xaxis = CASE WHEN p.Xaxis < 0 THEN 0 ELSE p.Xaxis END
         , t.Yaxis = CASE WHEN p.Yaxis < 0 THEN 0 ELSE p.Yaxis END
    FROM   dbo.tblTable t
    JOIN   @Positions p ON p.TableID = t.TableID;

    DECLARE @n INT = @@ROWCOUNT;

    INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
    VALUES ('Table', NULL, 'DineInLayout', @UserID, @UserName, CONCAT(N'TablesMoved=', @n));

    SELECT Message = 'Success', Updated = @n;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_SetGuest]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_SetGuest]
      @TableID       INT
    , @CustomerName  NVARCHAR(200) = NULL
    , @Mobile        NVARCHAR(30)  = NULL
    , @Persons       INT           = 1
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.tblPOS_TableSession
       SET CustomerName = NULLIF(LTRIM(RTRIM(@CustomerName)), N'')
         , Mobile       = NULLIF(LTRIM(RTRIM(@Mobile)), N'')
         , Persons      = CASE WHEN @Persons < 1 THEN 1 WHEN @Persons > 999 THEN 999 ELSE @Persons END
     WHERE TableID = @TableID AND ClosedOn IS NULL;

    IF @@ROWCOUNT = 0
        SELECT Message = 'Fail', ErrorMessage = N'This table is no longer open.';
    ELSE
        SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_SetLineTakeAway]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_SetLineTakeAway]
      @InvoiceNo  BIGINT
    , @OrderID    BIGINT
    , @On         BIT
    , @UserID     INT           = NULL
    , @UserName   NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Status INT, @Found BIT = 0, @c NVARCHAR(MAX);

    SELECT @Status = OrderStatusID FROM dbo.tblInvoice WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;
    IF @Status IS NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'Bill not found.'; RETURN;
    END
    IF @Status IN (6, 7, 8)
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'This bill is cancelled or refunded.'; RETURN;
    END

    SELECT @c = o.Comments, @Found = 1
    FROM   dbo.tblOrder o
    WHERE  o.OrderID = @OrderID AND o.InvoiceNo = @InvoiceNo AND ISNULL(o.Deleted, 0) = 0
      AND  o.ParentOrderID IS NULL;

    IF @Found = 0
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = N'That item is not on this bill any more.'; RETURN;
    END

    SET @c = LTRIM(RTRIM(ISNULL(@c, N'')));
    IF LEFT(@c, 9) = N'TAKE AWAY'
    BEGIN
        SET @c = LTRIM(SUBSTRING(@c, 10, 4000));
        IF LEFT(@c, 1) = N'-' SET @c = LTRIM(SUBSTRING(@c, 2, 4000));
    END
    IF @On = 1
        SET @c = N'TAKE AWAY' + CASE WHEN @c = N'' THEN N'' ELSE N' - ' + @c END;

    BEGIN TRY
        UPDATE dbo.tblOrder SET Comments = NULLIF(@c, N'')
        WHERE  OrderID = @OrderID AND InvoiceNo = @InvoiceNo;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, CASE WHEN @On = 1 THEN 'DineInMarkTakeAway' ELSE 'DineInUnmarkTakeAway' END,
                @UserID, @UserName, CONCAT(N'OrderID=', @OrderID));
    END TRY
    BEGIN CATCH
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE(); RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_SplitInvoice]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_SplitInvoice]
      @InvoiceNo  BIGINT
    , @UserID     INT           = NULL
    , @UserName   NVARCHAR(100) = NULL
    , @Lines      dbo.TVP_POS_DineInSplitLine READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE(), @Today DATE = CAST(GETDATE() AS DATE)
          , @Err NVARCHAR(300), @Status INT, @BranchID INT, @NewNo BIGINT, @Running INT
          , @Paid DECIMAL(18,3), @Remaining INT, @Discount DECIMAL(18,3)
          , @BillOld DECIMAL(18,3), @BillNew DECIMAL(18,3);

    SELECT @Status = OrderStatusID, @BranchID = BranchID, @Discount = ISNULL(Discount, 0)
    FROM   dbo.tblInvoice WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;

    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p WHERE p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted, 0) = 0;

    -- the chosen item rows (whole rows only)
    DECLARE @req TABLE (OrderID BIGINT PRIMARY KEY);
    INSERT INTO @req (OrderID)
    SELECT DISTINCT o.OrderID
    FROM   @Lines l
    JOIN   dbo.tblOrder o ON o.OrderID = l.OrderID AND o.InvoiceNo = @InvoiceNo
                         AND ISNULL(o.Deleted, 0) = 0 AND ISNULL(o.LineType, 1) = 1
                         AND o.ParentOrderID IS NULL;

    SELECT @Remaining = COUNT(*)
    FROM   dbo.tblOrder o
    WHERE  o.InvoiceNo = @InvoiceNo AND ISNULL(o.Deleted, 0) = 0
      AND  ISNULL(o.LineType, 1) = 1 AND o.ParentOrderID IS NULL
      AND  NOT EXISTS (SELECT 1 FROM @req r WHERE r.OrderID = o.OrderID);

    IF @Status IS NULL                      SET @Err = N'Bill not found.';
    ELSE IF @Status IN (6, 7, 8)            SET @Err = N'This bill is cancelled or refunded.';
    ELSE IF @Paid > 0                       SET @Err = N'This bill already has a payment on it and cannot be split.';
    ELSE IF NOT EXISTS (SELECT 1 FROM @req) SET @Err = N'Select at least one item to split.';
    ELSE IF @Remaining <= 0                 SET @Err = N'Leave at least one item on the original bill. To pay everything, use Pay.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = @Err, NewInvoiceNo = CAST(NULL AS BIGINT); RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        /* new running number for the day, same counter sp_POS_ProcessOrder uses */
        UPDATE dbo.tblPOS_DailyCounter WITH (UPDLOCK, HOLDLOCK)
           SET @Running = LastNumber = LastNumber + 1
         WHERE BranchID = @BranchID AND CounterDate = @Today;
        IF @Running IS NULL
        BEGIN
            INSERT INTO dbo.tblPOS_DailyCounter (BranchID, CounterDate, LastNumber) VALUES (@BranchID, @Today, 1);
            SET @Running = 1;
        END

        /* header copied from the original */
        INSERT INTO dbo.tblInvoice
        (
              WaiterID, BillAmount, Discount, Comments, Person, Status
            , InvoiceDate, InvoiceTime, PaymentType, Printed, Mobile, MobileText
            , CustomerName, OrderStatus, CustomerId, OrderStatusID, Deleted
            , BranchID, AddressID, BrandID, DeliveryDate, InvoiceType
            , DiscountTypeID, DeliveryCharges, OrderType, TrackingCode
            , ClientOrderGuid, DiscountCode, SourceID, RunningOrder
            , PromisedTime, PrintCount, PaidDate, TableID, TableSessionID
        )
        SELECT  ISNULL(@UserID, i.WaiterID), 0, 0, N'Split from bill ' + CAST(i.InvoiceNo AS NVARCHAR(20)), 1, i.Status
              , @Now, @Now, i.PaymentType, 0, i.Mobile, i.MobileText
              , i.CustomerName, i.OrderStatus, i.CustomerId, i.OrderStatusID, 0
              , i.BranchID, i.AddressID, i.BrandID, i.DeliveryDate, i.InvoiceType
              , 0, 0, i.OrderType, NULL
              , NULL, NULL, i.SourceID, @Running
              , i.PromisedTime, 0, NULL, i.TableID, i.TableSessionID
        FROM    dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;

        SET @NewNo = CAST(SCOPE_IDENTITY() AS BIGINT);

        DECLARE @seed BIGINT = @NewNo * 2654435761 % 456976;
        UPDATE dbo.tblInvoice
           SET TrackingCode = CHAR(65 + (@seed/17576)%26) + CHAR(65 + (@seed/676)%26)
                            + CHAR(65 + (@seed/26)%26)    + CHAR(65 + @seed%26)
                            + '-' + RIGHT('0000' + CAST(@NewNo % 10000 AS VARCHAR(4)), 4)
         WHERE InvoiceNo = @NewNo;

        /* copies of the chosen items go on the new bill.
           The identity column is handed out in the order of the SELECT ... ORDER BY,
           so the n-th copy belongs to the n-th original; that pairs a copy with its
           original so the extras can be attached to the right parent. */
        DECLARE @map TABLE (Rn INT IDENTITY(1,1) PRIMARY KEY, OldID BIGINT NOT NULL, NewID BIGINT NULL);
        INSERT INTO @map (OldID) SELECT OrderID FROM @req ORDER BY OrderID;

        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot, SplitFromOrderID
        )
        SELECT @NewNo, o.ItemID, o.Quantity, o.Price, o.SentToPrinter, o.Comments, o.Extra
             , o.WaiterID, o.Prepared, o.Combined, o.Delivered, o.Dispatcher, 0
             , o.OrderDate, o.TableType, 0, o.DiscountTypeID, ISNULL(o.Discount, 0), o.BranchID
             , o.CartItemUniqID, o.LineType, o.ItemNameSnapshot, o.OrderID
        FROM   dbo.tblOrder o
        JOIN   @map m ON m.OldID = o.OrderID
        ORDER BY m.Rn;

        ;WITH nn AS (SELECT OrderID, Rn = ROW_NUMBER() OVER (ORDER BY OrderID)
                     FROM   dbo.tblOrder WHERE InvoiceNo = @NewNo)
        UPDATE m SET m.NewID = nn.OrderID
        FROM   @map m JOIN nn ON nn.Rn = m.Rn;

        /* their extras / choices, attached to the new parent */
        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot, ParentOrderID, SplitFromOrderID
        )
        SELECT @NewNo, k.ItemID, k.Quantity, k.Price, k.SentToPrinter, k.Comments, k.Extra
             , k.WaiterID, k.Prepared, k.Combined, k.Delivered, k.Dispatcher, 0
             , k.OrderDate, k.TableType, 0, k.DiscountTypeID, ISNULL(k.Discount, 0), k.BranchID
             , k.CartItemUniqID, k.LineType, k.ItemNameSnapshot, m.NewID, k.OrderID
        FROM   dbo.tblOrder k
        JOIN   @map m ON m.OldID = k.ParentOrderID
        WHERE  ISNULL(k.Deleted, 0) = 0;

        /* the originals stay, flagged: not deleted, not wasted, not counted -
           they now live on the new bill */
        UPDATE o
           SET o.Deleted = 1, o.IsSplit = 1, o.SplitToInvoiceNo = @NewNo
        FROM   dbo.tblOrder o
        WHERE  o.InvoiceNo = @InvoiceNo AND ISNULL(o.Deleted, 0) = 0
          AND  (o.OrderID IN (SELECT OrderID FROM @req)
             OR o.ParentOrderID IN (SELECT OrderID FROM @req));

        /* re-total both bills from the lines that count */
        SELECT @BillOld = CAST(ISNULL(SUM(Quantity * Price), 0) AS DECIMAL(18,3))
        FROM   dbo.tblOrder WHERE InvoiceNo = @InvoiceNo AND ISNULL(Deleted, 0) = 0;
        SELECT @BillNew = CAST(ISNULL(SUM(Quantity * Price), 0) AS DECIMAL(18,3))
        FROM   dbo.tblOrder WHERE InvoiceNo = @NewNo AND ISNULL(Deleted, 0) = 0;

        UPDATE dbo.tblInvoice
           SET BillAmount = @BillOld
             , Discount   = CASE WHEN @Discount > @BillOld THEN @BillOld ELSE @Discount END
             , ModifiedOn = @Now, ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;
        UPDATE dbo.tblInvoice SET BillAmount = @BillNew WHERE InvoiceNo = @NewNo;

        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, Comments)
        SELECT @NewNo, NULL, OrderStatusID, @UserID, @UserName, N'Split from bill ' + CAST(@InvoiceNo AS NVARCHAR(20))
        FROM   dbo.tblInvoice WHERE InvoiceNo = @NewNo;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'DineInSplit', @UserID, @UserName,
                CONCAT(N'NewInvoice=', @NewNo, N'; OldBill=', @BillOld, N'; NewBill=', @BillNew));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE(), NewInvoiceNo = CAST(NULL AS BIGINT);
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300)), NewInvoiceNo = @NewNo
         , OldBill = @BillOld, NewBill = @BillNew;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_TakeAwayList]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_TakeAwayList]
    @BranchID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TA INT
          , @Today DATETIME = CAST(CAST(GETDATE() AS DATE) AS DATETIME);

    SELECT TOP 1 @TA = ID FROM dbo.tblInvoiceType_Master
    WHERE  REPLACE(REPLACE(Name, N'-', N''), N' ', N'') IN (N'TakeAway', N'Takeaway') ORDER BY ID;

    SELECT  i.InvoiceNo
          , InvoiceNumShow = CAST(i.InvoiceNumShow AS NVARCHAR(30))
          , i.RunningOrder
          , i.InvoiceDate
          , CustomerName   = NULLIF(LTRIM(RTRIM(CAST(i.CustomerName AS NVARCHAR(200)))), N'')
          , Mobile         = NULLIF(LTRIM(RTRIM(CAST(i.Mobile AS NVARCHAR(30)))), N'')
          , i.BillAmount
          , Discount       = ISNULL(i.Discount, 0)
          , NetPayable     = i.FinalAmount + ISNULL(i.DeliveryCharges, 0)
          , AmountPaid     = ISNULL(pp.Paid, 0)
          , i.OrderStatusID
          , i.PrintCount
    INTO    #b
    FROM    dbo.tblInvoice i
    OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                 FROM   dbo.tblInvoicePayment p
                 WHERE  p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted, 0) = 0) pp
    WHERE   @TA IS NOT NULL
      AND   i.InvoiceType = @TA
      AND   i.TableSessionID IS NULL
      AND   ISNULL(i.Deleted, 0) = 0
      AND   ISNULL(i.OrderStatusID, 0) NOT IN (6, 7, 8)
      AND   (@BranchID IS NULL OR i.BranchID = @BranchID)
      AND   (   i.InvoiceDate >= @Today
             OR (    i.InvoiceDate >= DATEADD(DAY, -7, @Today)
                 AND (i.FinalAmount + ISNULL(i.DeliveryCharges, 0)) - ISNULL(pp.Paid, 0) > 0.0005));

    SELECT * FROM #b ORDER BY InvoiceNo DESC;

    SELECT  o.InvoiceNo
          , o.OrderID
          , o.ItemID
          , o.ParentOrderID
          , LineType  = ISNULL(o.LineType, 1)
          , ItemName  = ISNULL(o.ItemNameSnapshot, it.ITEM_NAME)
          , o.Quantity
          , o.Price
          , LineTotal = CAST(o.Quantity * o.Price AS DECIMAL(18,3))
          , o.Comments
          , IsTakeAway = CAST(0 AS BIT)
          , o.OrderDate
    FROM    dbo.tblOrder o
    JOIN    #b b ON b.InvoiceNo = o.InvoiceNo
    LEFT JOIN dbo.tblItems it ON it.ID = o.ItemID
    WHERE   ISNULL(o.Deleted, 0) = 0
    ORDER BY o.InvoiceNo, o.OrderID;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_DineIn_TransferTable]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_DineIn_TransferTable]
      @FromTableID  INT
    , @ToTableID    INT
    , @UserID       INT           = NULL
    , @UserName     NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionID INT, @Err NVARCHAR(300);

    SELECT @SessionID = SessionID FROM dbo.tblPOS_TableSession WHERE TableID = @FromTableID AND ClosedOn IS NULL;

    IF @FromTableID = @ToTableID
        SET @Err = N'Pick a different table.';
    ELSE IF @SessionID IS NULL
        SET @Err = N'There is nobody seated at this table.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblTable WHERE TableID = @ToTableID)
        SET @Err = N'Target table not found.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.fn_POS_DineIn_Tables() WHERE TableID = @ToTableID AND Status = 1)
        SET @Err = N'That table is occupied. Pick a vacant one.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', ErrorMessage = @Err; RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblPOS_TableSession SET TableID = @ToTableID WHERE SessionID = @SessionID;
        UPDATE dbo.tblInvoice SET TableID = @ToTableID WHERE TableSessionID = @SessionID;
        UPDATE dbo.tblTable SET Status = 0 WHERE TableID = @FromTableID;
        UPDATE dbo.tblTable SET Status = 1 WHERE TableID = @ToTableID;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('TableSession', @SessionID, 'DineInTransfer', @UserID, @UserName,
                CONCAT(N'FromTableID=', @FromTableID, N'; ToTableID=', @ToTableID));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail',
               ErrorMessage = CASE WHEN ERROR_NUMBER() IN (2601, 2627)
                                   THEN N'That table was just taken on another device.'
                                   ELSE ERROR_MESSAGE() END;
        RETURN;
    END CATCH

    SELECT Message = 'Success', ErrorMessage = CAST(NULL AS NVARCHAR(300));
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_GeoCacheGet]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_GeoCacheGet]
      @Lat DECIMAL(10,4)
    , @Lng DECIMAL(10,4)
AS
BEGIN
    SET NOCOUNT ON;

    -- A miss is a row that was never found, not a row that was found empty:
    -- caching "no block here" is correct and stops us asking Nominatim the
    -- same unanswerable question forever.
    UPDATE dbo.tblPOS_GeoCache
       SET HitCount = HitCount + 1
     WHERE Lat = @Lat AND Lng = @Lng;

    SELECT Block, Neighbourhood
    FROM   dbo.tblPOS_GeoCache
    WHERE  Lat = @Lat AND Lng = @Lng
      AND  CreatedOn > DATEADD(DAY, -180, GETDATE());   -- refresh twice a year
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_GeoCacheSet]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_GeoCacheSet]
      @Lat           DECIMAL(10,4)
    , @Lng           DECIMAL(10,4)
    , @Block         NVARCHAR(50)  = NULL
    , @Neighbourhood NVARCHAR(200) = NULL
    , @RawJson       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Two customers can tap the same spot at the same moment, so this has to
    -- tolerate a concurrent insert rather than throwing a duplicate key.
    BEGIN TRY
        MERGE dbo.tblPOS_GeoCache WITH (HOLDLOCK) AS t
        USING (SELECT @Lat AS Lat, @Lng AS Lng) AS s
           ON t.Lat = s.Lat AND t.Lng = s.Lng
        WHEN MATCHED THEN
            UPDATE SET Block = @Block, Neighbourhood = @Neighbourhood,
                       RawJson = @RawJson, CreatedOn = GETDATE()
        WHEN NOT MATCHED THEN
            INSERT (Lat, Lng, Block, Neighbourhood, RawJson)
            VALUES (@Lat, @Lng, @Block, @Neighbourhood, @RawJson);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() NOT IN (2601, 2627) THROW;   -- ignore a lost race only
    END CATCH
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_GetInvoiceNumShow]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_GetInvoiceNumShow]
      @InvoiceNo BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT   InvoiceNo
           , InvoiceNumShow
           , TrackingCode
    FROM     dbo.tblInvoice
    WHERE    InvoiceNo = @InvoiceNo;
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_GetLookups]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_GetLookups]
      @BrandID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 0: branches
    SELECT   BranchID = id, BranchName = branchName, BranchNameAra = branchNameAra, BrandID = brandId
    FROM     dbo.tblbranch
    WHERE    ISNULL(IsDeleted,0) = 0 AND ISNULL(IsActive,1) = 1
      AND    (@BrandID IS NULL OR brandId = @BrandID)
    ORDER BY ISNULL(SEQ_NUM, 9999), branchName;

    -- 1: statuses
    SELECT   OrderStatusID, OrderStatusName, OrderStatusNameAra, SortOrder, ColorHex,
             IsTerminal, AppliesToPickup, AppliesToDelivery
    FROM     dbo.tblOrderStatus
    WHERE    ISNULL(IsActive,1) = 1
    ORDER BY SortOrder;

    -- 2: payment types
    SELECT   PaymentTypeID = ID, PaymentTypeName, PaymentTypeNameArb,
             IsCash, IsOnline, IsCOD, RequiresReference
    FROM     dbo.tblInvoicePaymentType
    WHERE    ISNULL(IsDeleted,0) = 0 AND ISNULL(IsActive,1) = 1
    ORDER BY Seqnum, ID;

    -- 3: cancellation reasons
    SELECT   CancelReasonID, ReasonName, ReasonNameAra, DefaultDisposition
    FROM     dbo.tblPOS_CancelReason_Master
    WHERE    IsActive = 1
    ORDER BY CancelReasonID;

    -- 4: channels
    SELECT   InvoiceTypeID = ID, Name, ShowInCallCentre
    FROM     dbo.tblInvoiceType_Master ORDER BY ID;

    -- 5: cash denominations for the tender pad
    SELECT   id, DenominationType, DenominationValue
    FROM     dbo.tblDenomination ORDER BY DenominationValue DESC;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_GetOrderChanges]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_GetOrderChanges]
      @SinceRowVer BINARY(8)    = NULL
    , @BranchIDs   VARCHAR(200) = NULL
    , @MaxRows     INT          = 200
AS
BEGIN
    SET NOCOUNT ON;

    -- MIN_ACTIVE_ROWVERSION, not @@DBTS: a transaction that has stamped a row
    -- but not yet committed would otherwise be skipped by this poll and never
    -- returned again - the order would simply never appear in the POS.
    DECLARE @Upper BINARY(8) = MIN_ACTIVE_ROWVERSION();

    IF @SinceRowVer IS NULL
    BEGIN
        -- First poll only establishes the watermark, so every order already on
        -- screen is not announced as new.
        SELECT CurrentRowVer = @Upper;
        SELECT TOP 0 InvoiceNo = CAST(NULL AS BIGINT);
        RETURN;
    END

    DECLARE @Branches TABLE (BranchID INT PRIMARY KEY);
    IF NULLIF(LTRIM(RTRIM(@BranchIDs)),'') IS NOT NULL
        INSERT INTO @Branches
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIDs, ',')
        WHERE TRY_CAST(value AS INT) IS NOT NULL;

    DECLARE @AnyBranch BIT = CASE WHEN EXISTS (SELECT 1 FROM @Branches) THEN 0 ELSE 1 END;

    SELECT CurrentRowVer = @Upper;

    SELECT TOP (@MaxRows)
          i.InvoiceNo
        , i.RowVer
        , i.TrackingCode
        , i.RunningOrder
        , i.OrderStatusID
        , OrderStatusName = st.OrderStatusName
        , StatusColor     = st.ColorHex
        , i.CustomerName
        , Mobile          = i.MobileText
        , AreaName        = ar.AreaName
        , AreaNameAra     = ar.AreaNameAra
        , i.BranchID
        , BranchName      = b.branchName
        , i.OrderType
        , OrderTypeName   = CASE i.OrderType WHEN 1 THEN 'Pickup' WHEN 2 THEN 'Delivery' WHEN 3 THEN 'Dine In' ELSE 'Other' END
        , i.BillAmount
        , i.FinalAmount
        , NetPayable      = i.FinalAmount + ISNULL(i.DeliveryCharges,0)
        , i.PrintCount
        , i.Deleted
        , i.InvoiceDate
        -- "New" is a hint for the client, which also keeps its own list of
        -- invoices it has already announced. Without that, a status change a
        -- minute after the order was placed would sound the alarm again.
        , IsNewOrder      = CASE WHEN i.InvoiceDate > DATEADD(MINUTE,-3,GETDATE()) THEN 1 ELSE 0 END
    FROM      dbo.tblInvoice i
    LEFT JOIN dbo.tblOrderStatus     st ON st.OrderStatusID = i.OrderStatusID
    LEFT JOIN dbo.tblbranch          b  ON b.id             = i.BranchID
    LEFT JOIN dbo.tblCustomerAddress ca ON ca.AddressID     = i.AddressID
    LEFT JOIN dbo.tblArea            ar ON ar.AreaID        = ca.AreaID
    WHERE     i.RowVer > @SinceRowVer
      AND     i.RowVer < @Upper
      AND     (@AnyBranch = 1 OR i.BranchID IN (SELECT BranchID FROM @Branches))
    ORDER BY  i.RowVer;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_GetOrderDetails]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_GetOrderDetails]
      @InvoiceNo BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -- 0: header
    SELECT
          i.InvoiceNo, i.InvoiceNumShow, i.TrackingCode, i.RunningOrder, i.InvoiceDate, i.PromisedTime
        , i.DeliveryDate, i.CustomerName, Mobile = i.MobileText, i.CustomerId
        , i.BranchID, BranchName = b.branchName, i.BrandID, BrandName = br.BrandName
        , InvoiceTypeID   = i.InvoiceType
        , InvoiceTypeName = it.Name
        , i.OrderType
        , OrderTypeName   = CASE i.OrderType WHEN 1 THEN 'Pickup' WHEN 2 THEN 'Delivery' WHEN 3 THEN 'Dine In' ELSE 'Other' END
        , i.OrderStatusID, OrderStatusName = st.OrderStatusName, StatusColor = st.ColorHex
        , IsTerminal      = ISNULL(st.IsTerminal,0)
        , i.BillAmount, i.Discount, i.DiscountCode
        , DeliveryCharges = ISNULL(i.DeliveryCharges,0)
        , i.FinalAmount
        -- FinalAmount is a computed column that EXCLUDES DeliveryCharges.
        -- NetPayable is what the customer actually pays.
        , NetPayable      = i.FinalAmount + ISNULL(i.DeliveryCharges,0)
        , i.PaymentType, PaymentTypeName = pt.PaymentTypeName, IsCOD = ISNULL(pt.IsCOD,0)
        , AmountPaid      = ISNULL((SELECT SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                                    FROM dbo.tblInvoicePayment p
                                    WHERE p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted,0) = 0), 0)
        , i.Comments, i.Complaints
        , i.CancelReasonID, i.CancelComments, i.CancelDisposition
        , i.Driver, i.DriverName, i.DriverAssignDate
        , i.PrintCount, i.LastPrintedOn, i.SourceID, i.Deleted
        , AddressID = ca.AddressID, ca.Block, ca.Street, ca.Lane, ca.Building
        , ca.Floor, ca.Flat, ca.HouseNo, ca.PACI, ca.AddressRemark, ca.Lat, ca.Lng
        , AreaID = ca.AreaID, AreaName = ar.AreaName, AreaNameAra = ar.AreaNameAra
    FROM      dbo.tblInvoice i
    LEFT JOIN dbo.tblOrderStatus        st ON st.OrderStatusID = i.OrderStatusID
    LEFT JOIN dbo.tblbranch             b  ON b.id             = i.BranchID
    LEFT JOIN dbo.tblBrand              br ON br.BrandID       = i.BrandID
    LEFT JOIN dbo.tblInvoiceType_Master it ON it.ID            = i.InvoiceType
    LEFT JOIN dbo.tblInvoicePaymentType pt ON pt.ID            = i.PaymentType
    LEFT JOIN dbo.tblCustomerAddress    ca ON ca.AddressID     = i.AddressID
    LEFT JOIN dbo.tblArea               ar ON ar.AreaID        = ca.AreaID
    WHERE     i.InvoiceNo = @InvoiceNo;

    -- 1: lines.  ItemNameSnapshot is the name as sold, so a reprint months
    --    later still shows what the customer actually bought.
    SELECT
          o.OrderID, o.ItemID, o.LineType, o.ParentOrderID, o.CartItemUniqID
        , ItemName    = ISNULL(o.ItemNameSnapshot, it.ITEM_NAME)
        , ItemNameAra = it.ITEM_NAME_ARABIC
        , o.Quantity, o.Price
        , Discount    = ISNULL(o.Discount, 0)
        , o.TotalAmount
        , OrderTime   = o.OrderDate
        , o.Comments, o.Extra, o.Prepared, o.Delivered, o.Deleted, o.Waste
    FROM      dbo.tblOrder o
    LEFT JOIN dbo.tblItems it ON it.ID = o.ItemID
    WHERE     o.InvoiceNo = @InvoiceNo
    ORDER BY  o.OrderID;

    -- 2: status timeline
    SELECT    h.HistoryID, h.FromStatusID, h.ToStatusID
            , FromStatusName = sf.OrderStatusName
            , ToStatusName   = stt.OrderStatusName
            , StatusColor    = stt.ColorHex
            , h.ChangedBy, h.ChangedByName, h.ChangedOn, h.Comments, h.DriverID
    FROM      dbo.tblPOS_OrderStatusHistory h
    LEFT JOIN dbo.tblOrderStatus sf  ON sf.OrderStatusID  = h.FromStatusID
    LEFT JOIN dbo.tblOrderStatus stt ON stt.OrderStatusID = h.ToStatusID
    WHERE     h.InvoiceNo = @InvoiceNo
    ORDER BY  h.HistoryID;

    -- 3: payments
    SELECT    p.id AS PaymentID, p.PaymentTypeID, p.PaymentType, p.Amount
            , p.AmountTendered, p.ChangeGiven, p.ReferenceNo, p.IsRefund
            , p.ReceivedBy, p.ReceivedOn, p.Comments
    FROM      dbo.tblInvoicePayment p
    WHERE     p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0
    ORDER BY  p.id;

    -- 4: transfers
    SELECT    t.TransferID, t.FromBranchID, FromBranch = bf.branchName
            , t.ToBranchID, ToBranch = bt.branchName
            , t.Reason, t.TransferredBy, t.TransferredOn
    FROM      dbo.tblPOS_OrderTransfer t
    LEFT JOIN dbo.tblbranch bf ON bf.id = t.FromBranchID
    LEFT JOIN dbo.tblbranch bt ON bt.id = t.ToBranchID
    WHERE     t.InvoiceNo = @InvoiceNo
    ORDER BY  t.TransferID;

    -- 5: allowed next statuses, so the UI can never offer an invalid move
    SELECT    tr.ToStatusID, s.OrderStatusName, s.ColorHex, tr.RequiresRole
    FROM      dbo.tblPOS_OrderStatusTransition tr
    JOIN      dbo.tblOrderStatus s ON s.OrderStatusID = tr.ToStatusID
    JOIN      dbo.tblInvoice     i ON i.InvoiceNo     = @InvoiceNo
    WHERE     tr.FromStatusID = i.OrderStatusID
      AND     ((i.OrderType = 1 AND s.AppliesToPickup = 1) OR (i.OrderType <> 1 AND s.AppliesToDelivery = 1))
    ORDER BY  s.SortOrder;
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_GetOrderFacets]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_GetOrderFacets]
      @BrandIDs       VARCHAR(200)  = NULL
    , @BranchIDs      VARCHAR(200)  = NULL
    , @InvoiceTypeIDs VARCHAR(200)  = NULL
    , @StatusIDs      VARCHAR(200)  = NULL
    , @DateMode       VARCHAR(10)   = 'Today'
    , @FromDate       DATE          = NULL
    , @ToDate         DATE          = NULL
    , @Search         NVARCHAR(100) = NULL
    , @PaymentStatus  VARCHAR(10)   = NULL
    , @ScheduledOnly  BIT           = 0    -- 1 = only orders whose DeliveryDate is a later calendar day than InvoiceDate
AS
BEGIN
    SET NOCOUNT ON;

    /*---- date window ----------------------------------------------------*/
    DECLARE @dFrom DATETIME, @dTo DATETIME, @Today DATE = CAST(GETDATE() AS DATE);
    IF      @DateMode = 'Today'  BEGIN SET @dFrom = @Today;                SET @dTo = DATEADD(DAY,1,@Today); END
    ELSE IF @DateMode = 'Future' BEGIN SET @dFrom = DATEADD(DAY,1,@Today); SET @dTo = NULL; END
    ELSE IF @DateMode = 'Past'   BEGIN SET @dFrom = NULL;                  SET @dTo = @Today; END
    ELSE IF @DateMode = 'Range'  BEGIN SET @dFrom = @FromDate;             SET @dTo = DATEADD(DAY,1,@ToDate); END
    -- 'All' leaves both NULL

    /*---- CSV filters ----------------------------------------------------*/
    DECLARE @Brands dbo.TVP_POS_IntList, @Branches dbo.TVP_POS_IntList,
            @ITypes dbo.TVP_POS_IntList, @Statuses dbo.TVP_POS_IntList;

    IF NULLIF(LTRIM(RTRIM(@BrandIDs)),'')       IS NOT NULL INSERT INTO @Brands   (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BrandIDs,',')       WHERE TRY_CAST(value AS INT) IS NOT NULL;
    IF NULLIF(LTRIM(RTRIM(@BranchIDs)),'')      IS NOT NULL INSERT INTO @Branches (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIDs,',')      WHERE TRY_CAST(value AS INT) IS NOT NULL;
    IF NULLIF(LTRIM(RTRIM(@InvoiceTypeIDs)),'') IS NOT NULL INSERT INTO @ITypes   (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@InvoiceTypeIDs,',') WHERE TRY_CAST(value AS INT) IS NOT NULL;
    IF NULLIF(LTRIM(RTRIM(@StatusIDs)),'')      IS NOT NULL INSERT INTO @Statuses (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@StatusIDs,',')      WHERE TRY_CAST(value AS INT) IS NOT NULL;

    DECLARE @AnyBrand  BIT = CASE WHEN EXISTS (SELECT 1 FROM @Brands)   THEN 0 ELSE 1 END
          , @AnyBranch BIT = CASE WHEN EXISTS (SELECT 1 FROM @Branches) THEN 0 ELSE 1 END
          , @AnyIType  BIT = CASE WHEN EXISTS (SELECT 1 FROM @ITypes)   THEN 0 ELSE 1 END
          , @AnyStatus BIT = CASE WHEN EXISTS (SELECT 1 FROM @Statuses) THEN 0 ELSE 1 END;

    DECLARE @SearchNum  BIGINT        = TRY_CAST(REPLACE(REPLACE(ISNULL(@Search,''),'+',''),' ','') AS BIGINT);
    DECLARE @SearchLike NVARCHAR(102) = CASE WHEN NULLIF(@Search,'') IS NULL THEN NULL ELSE '%' + @Search + '%' END;

    /*---- working set: date + search + payment only ----------------------
      Status is NOT applied here any more (each group applies it, except the
      status group itself), and deleted rows are kept but flagged.
    ---------------------------------------------------------------------*/
    IF OBJECT_ID('tempdb..#scoped') IS NOT NULL DROP TABLE #scoped;

    CREATE TABLE #scoped
    (
          InvoiceNo   BIGINT PRIMARY KEY
        , BrandID     INT NULL
        , BranchID    INT NULL
        , InvoiceType INT NULL
        , StatusID    INT NULL
        , IsDeleted   BIT NOT NULL
    );

    INSERT INTO #scoped (InvoiceNo, BrandID, BranchID, InvoiceType, StatusID, IsDeleted)
    SELECT     i.InvoiceNo, i.BrandID, i.BranchID, i.InvoiceType
             , i.OrderStatusID, CAST(ISNULL(i.Deleted,0) AS BIT)
    FROM       dbo.tblInvoice i
    LEFT JOIN  dbo.tblCustomerAddress ca ON ca.AddressID = i.AddressID
    LEFT JOIN  dbo.tblArea            ar ON ar.AreaID    = ca.AreaID
    OUTER APPLY (SELECT Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
                 FROM   dbo.tblInvoicePayment p
                 WHERE  p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted,0) = 0) pay
    WHERE   (@dFrom IS NULL OR i.InvoiceDate >= @dFrom)
      AND   (@dTo   IS NULL OR i.InvoiceDate <  @dTo)
      AND   (@SearchLike IS NULL
             OR i.TrackingCode LIKE @SearchLike
             OR i.CustomerName LIKE @SearchLike
             OR i.MobileText   LIKE @SearchLike
             OR ar.AreaName    LIKE @SearchLike
             OR (@SearchNum IS NOT NULL AND (i.InvoiceNo = @SearchNum OR i.Mobile = @SearchNum OR i.RunningOrder = @SearchNum)))
      AND   (@PaymentStatus IS NULL
             OR (@PaymentStatus = 'Unpaid'  AND ISNULL(pay.Paid,0) <= 0)
             OR (@PaymentStatus = 'Paid'    AND ISNULL(pay.Paid,0) + 0.001 >= i.FinalAmount + ISNULL(i.DeliveryCharges,0))
             OR (@PaymentStatus = 'Partial' AND ISNULL(pay.Paid,0) > 0
                                           AND ISNULL(pay.Paid,0) + 0.001 < i.FinalAmount + ISNULL(i.DeliveryCharges,0)))
      -- Same rule as sp_POS_GetOrders: a later calendar day, not just a later
      -- time slot the same day. Raw i.DeliveryDate - NULL is never scheduled.
      AND   (@ScheduledOnly = 0 OR CAST(i.DeliveryDate AS DATE) > CAST(i.InvoiceDate AS DATE));

    CREATE NONCLUSTERED INDEX IX_scoped ON #scoped (BrandID, BranchID, InvoiceType, StatusID);

    /*======================================================================
      Each group is counted with every filter applied EXCEPT ITS OWN, so a
      tick never hides the other options in the same group. Rows with a zero
      count are still returned: the panel keeps a stable shape instead of
      items appearing and vanishing as filters change.

      LEFT JOIN, not INNER: a brand with no orders today must still be listed.
    ======================================================================*/

    -- 0: brands (respects branch + type + status)
    SELECT   BrandID   = br.BrandID
           , BrandName = ISNULL(br.BrandName, N'-')
           , Cnt       = COUNT(s.InvoiceNo)
    FROM     dbo.tblBrand br
    LEFT JOIN #scoped s
           ON s.BrandID = br.BrandID
          AND s.IsDeleted = 0
          AND (@AnyBranch = 1 OR s.BranchID    IN (SELECT Value FROM @Branches))
          AND (@AnyIType  = 1 OR s.InvoiceType IN (SELECT Value FROM @ITypes))
          AND (@AnyStatus = 1 OR s.StatusID    IN (SELECT Value FROM @Statuses))
    GROUP BY br.BrandID, br.BrandName, br.BrandSeq
    ORDER BY ISNULL(br.BrandSeq, 9999), br.BrandName;

    -- 1: branches (respects brand + type + status)
    SELECT   BranchID   = b.id
           , BranchName = ISNULL(b.branchName, N'-')
           , BrandID    = b.brandId
           , Cnt        = COUNT(s.InvoiceNo)
    FROM     dbo.tblbranch b
    LEFT JOIN #scoped s
           ON s.BranchID = b.id
          AND s.IsDeleted = 0
          AND (@AnyBrand  = 1 OR s.BrandID     IN (SELECT Value FROM @Brands))
          AND (@AnyIType  = 1 OR s.InvoiceType IN (SELECT Value FROM @ITypes))
          AND (@AnyStatus = 1 OR s.StatusID    IN (SELECT Value FROM @Statuses))
    WHERE    ISNULL(b.IsDeleted,0) = 0
    GROUP BY b.id, b.branchName, b.brandId, b.SEQ_NUM
    ORDER BY ISNULL(b.SEQ_NUM, 9999), b.branchName;

    -- 2: invoice types (respects brand + branch + status)
    SELECT   InvoiceTypeID   = it.ID
           , InvoiceTypeName = ISNULL(it.Name, N'-')
           , Cnt             = COUNT(s.InvoiceNo)
    FROM     dbo.tblInvoiceType_Master it
    LEFT JOIN #scoped s
           ON s.InvoiceType = it.ID
          AND s.IsDeleted = 0
          AND (@AnyBrand  = 1 OR s.BrandID  IN (SELECT Value FROM @Brands))
          AND (@AnyBranch = 1 OR s.BranchID IN (SELECT Value FROM @Branches))
          AND (@AnyStatus = 1 OR s.StatusID IN (SELECT Value FROM @Statuses))
    GROUP BY it.ID, it.Name
    ORDER BY it.ID;

    -- 3: order statuses (respects brand + branch + type, NOT status)
    --
    -- Deleted rows are counted here so the "Deleted" entry shows a real
    -- number. Every status row in the table is returned, ticked or not, in the
    -- same order the panel lists them.
    SELECT   OrderStatusID   = os.OrderStatusID
           , OrderStatusName = ISNULL(os.OrderStatusName, N'-')
           , Cnt             = COUNT(s.InvoiceNo)
    FROM     dbo.tblOrderStatus os
    LEFT JOIN #scoped s
           ON s.StatusID = os.OrderStatusID
          AND (@AnyBrand  = 1 OR s.BrandID     IN (SELECT Value FROM @Brands))
          AND (@AnyBranch = 1 OR s.BranchID    IN (SELECT Value FROM @Branches))
          AND (@AnyIType  = 1 OR s.InvoiceType IN (SELECT Value FROM @ITypes))
    GROUP BY os.OrderStatusID, os.OrderStatusName, os.SortOrder
    ORDER BY ISNULL(os.SortOrder, 9999), os.OrderStatusID;

    DROP TABLE #scoped;
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_GetOrders]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_GetOrders]
      @BrandIDs       VARCHAR(200)  = NULL   -- CSV, NULL = all
    , @BranchIDs      VARCHAR(200)  = NULL
    , @InvoiceTypeIDs VARCHAR(200)  = NULL
    , @StatusIDs      VARCHAR(200)  = NULL
    , @DateMode       VARCHAR(10)   = 'Today'
    , @FromDate       DATE          = NULL
    , @ToDate         DATE          = NULL
    , @Search         NVARCHAR(100) = NULL
    , @OrderType      INT           = NULL
    , @PaymentTypeID  INT           = NULL
    , @PaymentStatus  VARCHAR(10)   = NULL
    , @SourceID       INT           = NULL
    , @DriverID       INT           = NULL
    , @MinAmount      DECIMAL(18,3) = NULL
    , @MaxAmount      DECIMAL(18,3) = NULL
    , @IncludeDeleted BIT           = 0
    , @ScheduledOnly  BIT           = 0    -- 1 = only orders whose DeliveryDate is a later calendar day than InvoiceDate
    , @Skip           INT           = 0
    , @Take           INT           = 50
    , @SortCol        VARCHAR(30)   = 'InvoiceDate'
    , @SortDir        VARCHAR(4)    = 'DESC'
AS
BEGIN
    SET NOCOUNT ON;

    IF @Take IS NULL OR @Take <= 0 SET @Take = 50;
    IF @Take > 500                 SET @Take = 500;
    IF @Skip IS NULL OR @Skip < 0  SET @Skip = 0;

    /* Whitelisted sort - user input never reaches the SQL text.

       The grid sends the DataTables column key, which is the alias in the
       SELECT below (InvoiceTypeName, OrderStatusName), not the underlying
       column. Both spellings are accepted so a column header sorts by what it
       displays instead of silently falling back to the invoice date. */
    DECLARE @SortExpr NVARCHAR(200) =
        CASE UPPER(@SortCol)
            WHEN 'INVOICENO'       THEN 'i.InvoiceNo'
            WHEN 'TRACKINGCODE'    THEN 'i.TrackingCode'
            WHEN 'INVOICETYPE'     THEN 'it.Name'
            WHEN 'INVOICETYPENAME' THEN 'it.Name'
            WHEN 'CUSTOMERNAME'    THEN 'i.CustomerName'
            WHEN 'MOBILE'          THEN 'i.MobileText'
            WHEN 'AREANAME'        THEN 'ar.AreaName'
            WHEN 'DELIVERYDATE'    THEN 'ISNULL(i.DeliveryDate, i.InvoiceDate)'
            WHEN 'INVOICEDATE'     THEN 'i.InvoiceDate'
            WHEN 'AMOUNT'          THEN '(i.FinalAmount + ISNULL(i.DeliveryCharges,0))'
            WHEN 'DRIVERNAME'      THEN 'i.DriverName'
            WHEN 'BRANDNAME'       THEN 'br.BrandName'
            WHEN 'BRANCHNAME'      THEN 'b.branchName'
            WHEN 'ORDERSTATUS'     THEN 'st.SortOrder'
            WHEN 'ORDERSTATUSNAME' THEN 'st.SortOrder'
            ELSE 'i.InvoiceDate'
        END;

    /* InvoiceNo is appended as a tiebreaker so equal values - two orders in the
       same minute - keep a stable order across pages. Without it, row 50 can
       come back as row 51 on the next page.

       It is NOT appended when the user is already sorting by InvoiceNo. SQL
       Server rejects a column listed twice in ORDER BY:

           Msg 169 - A column has been specified more than once in the order by
                     list. Columns in the order by list must be unique.

       The dynamic SQL then fails and the browser shows it as the DataTables
       "Query failed" warning, which is exactly what clicking the Invoice No
       header produced. */
    DECLARE @OrderBy NVARCHAR(300) =
        @SortExpr
      + CASE WHEN UPPER(ISNULL(@SortDir,'DESC')) = 'ASC' THEN ' ASC' ELSE ' DESC' END
      + CASE WHEN @SortExpr = 'i.InvoiceNo' THEN N'' ELSE N', i.InvoiceNo DESC' END;

    DECLARE @dFrom DATETIME, @dTo DATETIME, @Today DATE = CAST(GETDATE() AS DATE);
    IF      @DateMode = 'Today'  BEGIN SET @dFrom = @Today;                  SET @dTo = DATEADD(DAY,1,@Today); END
    ELSE IF @DateMode = 'Future' BEGIN SET @dFrom = DATEADD(DAY,1,@Today);   SET @dTo = NULL; END
    ELSE IF @DateMode = 'Past'   BEGIN SET @dFrom = NULL;                    SET @dTo = @Today; END
    ELSE IF @DateMode = 'Range'  BEGIN SET @dFrom = @FromDate;               SET @dTo = DATEADD(DAY,1,@ToDate); END

    DECLARE @Brands   dbo.TVP_POS_IntList, @Branches dbo.TVP_POS_IntList,
            @ITypes   dbo.TVP_POS_IntList, @Statuses dbo.TVP_POS_IntList;

    IF NULLIF(LTRIM(RTRIM(@BrandIDs)),'')       IS NOT NULL INSERT INTO @Brands   (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BrandIDs,',')       WHERE TRY_CAST(value AS INT) IS NOT NULL;
    IF NULLIF(LTRIM(RTRIM(@BranchIDs)),'')      IS NOT NULL INSERT INTO @Branches (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@BranchIDs,',')      WHERE TRY_CAST(value AS INT) IS NOT NULL;
    IF NULLIF(LTRIM(RTRIM(@InvoiceTypeIDs)),'') IS NOT NULL INSERT INTO @ITypes   (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@InvoiceTypeIDs,',') WHERE TRY_CAST(value AS INT) IS NOT NULL;
    IF NULLIF(LTRIM(RTRIM(@StatusIDs)),'')      IS NOT NULL INSERT INTO @Statuses (Value) SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@StatusIDs,',')      WHERE TRY_CAST(value AS INT) IS NOT NULL;

    DECLARE @AnyBrand  BIT = CASE WHEN EXISTS (SELECT 1 FROM @Brands)   THEN 0 ELSE 1 END
          , @AnyBranch BIT = CASE WHEN EXISTS (SELECT 1 FROM @Branches) THEN 0 ELSE 1 END
          , @AnyIType  BIT = CASE WHEN EXISTS (SELECT 1 FROM @ITypes)   THEN 0 ELSE 1 END
          , @AnyStatus BIT = CASE WHEN EXISTS (SELECT 1 FROM @Statuses) THEN 0 ELSE 1 END;

    DECLARE @SearchNum  BIGINT        = TRY_CAST(REPLACE(REPLACE(ISNULL(@Search,''),'+',''),' ','') AS BIGINT);
    DECLARE @SearchLike NVARCHAR(102) = CASE WHEN NULLIF(@Search,'') IS NULL THEN NULL ELSE '%' + @Search + '%' END;

    /* InvoiceNumShow is the number printed on the invoice the customer holds -
       a real column on tblInvoice, not assembled here, so there is one formula
       in one place. It is added to the SELECT below.

       NOTE FOR ANYONE EDITING THE STATEMENT BELOW: it is a STRING. An
       apostrophe anywhere inside it - including in a comment - closes the
       literal, and the rest of the procedure is then parsed as SQL. That
       produces a pile of "Incorrect syntax near ..." errors pointing at lines
       that are perfectly fine, ending in "Unclosed quotation mark". Write
       comments about this statement out here, not in there. */
    DECLARE @sql NVARCHAR(MAX) = N'
    SELECT
          TotalRows       = COUNT(*) OVER ()
        , i.InvoiceNo
        , i.InvoiceNumShow
        , i.TrackingCode
        , i.RunningOrder
        , InvoiceTypeID   = i.InvoiceType
        , InvoiceTypeName = ISNULL(it.Name, N''-'')
        , i.CustomerName
        , Mobile          = i.MobileText
        , i.CustomerId
        , AreaID          = ca.AreaID
        , AreaName        = ar.AreaName
        , DeliveryDate    = ISNULL(i.DeliveryDate, i.InvoiceDate)
        , i.InvoiceDate
        , AgeMinutes      = DATEDIFF(MINUTE, i.InvoiceDate, GETDATE())
        , IsLate          = CASE WHEN i.PromisedTime IS NOT NULL AND GETDATE() > i.PromisedTime
                                  AND ISNULL(st.IsTerminal,0) = 0 THEN 1 ELSE 0 END
        -- Amount = bill - discount + delivery. FinalAmount is a computed column
        -- that EXCLUDES DeliveryCharges, so it is added back here.
        , Amount          = i.FinalAmount + ISNULL(i.DeliveryCharges,0)
        , i.BillAmount
        , i.Discount
        , DeliveryCharges = ISNULL(i.DeliveryCharges,0)
        , DriverID        = i.Driver
        , DriverName      = ISNULL(NULLIF(i.DriverName,N''''), dr.DriverName)
        , BrandID         = i.BrandID
        , BrandName       = ISNULL(br.BrandName, N''-'')
        , i.BranchID
        , BranchName      = ISNULL(b.branchName, N''-'')
        , i.OrderStatusID
        , OrderStatusName = st.OrderStatusName
        , StatusColor     = st.ColorHex
        , IsTerminal      = ISNULL(st.IsTerminal,0)
        , i.OrderType
        , OrderTypeName   = CASE i.OrderType WHEN 1 THEN ''Pickup'' WHEN 2 THEN ''Delivery'' WHEN 3 THEN ''Dine In'' ELSE ''Other'' END
        , PaymentTypeID   = i.PaymentType
        , PaymentTypeName = pt.PaymentTypeName
        , IsCOD           = ISNULL(pt.IsCOD,0)
        , AmountPaid      = ISNULL(pay.Paid,0)
        , PaymentStatus   = CASE WHEN ISNULL(pay.Paid,0) <= 0 THEN ''Unpaid''
                                 WHEN ISNULL(pay.Paid,0) + 0.001 >= i.FinalAmount + ISNULL(i.DeliveryCharges,0) THEN ''Paid''
                                 ELSE ''Partial'' END
        , i.PrintCount
        , i.Deleted
    FROM        dbo.tblInvoice i
    LEFT JOIN   dbo.tblOrderStatus         st ON st.OrderStatusID = i.OrderStatusID
    LEFT JOIN   dbo.tblbranch              b  ON b.id             = i.BranchID
    LEFT JOIN   dbo.tblBrand               br ON br.BrandID       = i.BrandID
    LEFT JOIN   dbo.tblInvoiceType_Master  it ON it.ID            = i.InvoiceType
    LEFT JOIN   dbo.tblInvoicePaymentType  pt ON pt.ID            = i.PaymentType
    LEFT JOIN   dbo.tblCustomerAddress     ca ON ca.AddressID     = i.AddressID
    LEFT JOIN   dbo.tblArea                ar ON ar.AreaID        = ca.AreaID
    LEFT JOIN   dbo.tblDriver              dr ON dr.DriverID      = i.Driver
    OUTER APPLY (SELECT Paid = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                 FROM dbo.tblInvoicePayment p
                 WHERE p.InvoiceId = i.InvoiceNo AND ISNULL(p.isdeleted,0) = 0) pay
    WHERE  (@IncludeDeleted = 1 OR ISNULL(i.Deleted,0) = 0)
      AND  (@AnyBrand  = 1 OR i.BrandID       IN (SELECT Value FROM @Brands))
      AND  (@AnyBranch = 1 OR i.BranchID      IN (SELECT Value FROM @Branches))
      AND  (@AnyIType  = 1 OR i.InvoiceType   IN (SELECT Value FROM @ITypes))
      AND  (@AnyStatus = 1 OR i.OrderStatusID IN (SELECT Value FROM @Statuses))
      AND  (@dFrom IS NULL OR i.InvoiceDate >= @dFrom)
      AND  (@dTo   IS NULL OR i.InvoiceDate <  @dTo)
      AND  (@OrderType     IS NULL OR i.OrderType   = @OrderType)
      AND  (@PaymentTypeID IS NULL OR i.PaymentType = @PaymentTypeID)
      AND  (@SourceID      IS NULL OR i.SourceID    = @SourceID)
      AND  (@DriverID      IS NULL OR i.Driver      = @DriverID)
      AND  (@MinAmount     IS NULL OR i.FinalAmount + ISNULL(i.DeliveryCharges,0) >= @MinAmount)
      AND  (@MaxAmount     IS NULL OR i.FinalAmount + ISNULL(i.DeliveryCharges,0) <= @MaxAmount)
      AND  (@SearchLike IS NULL
            OR i.TrackingCode LIKE @SearchLike
            OR i.CustomerName LIKE @SearchLike
            OR i.MobileText   LIKE @SearchLike
            OR ar.AreaName    LIKE @SearchLike
            OR (@SearchNum IS NOT NULL AND (i.InvoiceNo = @SearchNum OR i.Mobile = @SearchNum OR i.RunningOrder = @SearchNum)))
      AND  (@PaymentStatus IS NULL
            OR (@PaymentStatus = ''Unpaid''  AND ISNULL(pay.Paid,0) <= 0)
            OR (@PaymentStatus = ''Paid''    AND ISNULL(pay.Paid,0) + 0.001 >= i.FinalAmount + ISNULL(i.DeliveryCharges,0))
            OR (@PaymentStatus = ''Partial'' AND ISNULL(pay.Paid,0) > 0
                                            AND ISNULL(pay.Paid,0) + 0.001 < i.FinalAmount + ISNULL(i.DeliveryCharges,0)))
      -- "Scheduled" = the customer picked a delivery date past the day the
      -- order was placed, not just a later time slot the same day. Raw
      -- i.DeliveryDate, not the ISNULL(...,InvoiceDate) fallback used in the
      -- SELECT above - a NULL DeliveryDate was never scheduled, and NULL >
      -- anything is unknown rather than true, so it is excluded either way.
      AND  (@ScheduledOnly = 0 OR CAST(i.DeliveryDate AS DATE) > CAST(i.InvoiceDate AS DATE))
    ORDER BY ' + @OrderBy + N'
    OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY
    OPTION (RECOMPILE);';

    EXEC sp_executesql @sql,
        N'@IncludeDeleted BIT, @AnyBrand BIT, @AnyBranch BIT, @AnyIType BIT, @AnyStatus BIT,
          @dFrom DATETIME, @dTo DATETIME, @OrderType INT, @PaymentTypeID INT, @SourceID INT, @DriverID INT,
          @MinAmount DECIMAL(18,3), @MaxAmount DECIMAL(18,3), @SearchLike NVARCHAR(102), @SearchNum BIGINT,
          @PaymentStatus VARCHAR(10), @ScheduledOnly BIT, @Skip INT, @Take INT,
          @Brands dbo.TVP_POS_IntList READONLY, @Branches dbo.TVP_POS_IntList READONLY,
          @ITypes dbo.TVP_POS_IntList READONLY, @Statuses dbo.TVP_POS_IntList READONLY',
        @IncludeDeleted, @AnyBrand, @AnyBranch, @AnyIType, @AnyStatus,
        @dFrom, @dTo, @OrderType, @PaymentTypeID, @SourceID, @DriverID,
        @MinAmount, @MaxAmount, @SearchLike, @SearchNum, @PaymentStatus, @ScheduledOnly, @Skip, @Take,
        @Brands, @Branches, @ITypes, @Statuses;
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_GetPaymentProvider]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_GetPaymentProvider]
      @PaymentTypeID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT   PaymentTypeID = ID
           , PaymentTypeName
           , IsOnline      = CAST(ISNULL(IsOnline, 0) AS BIT)
           -- An inactive or deleted method reports no provider: it must not be
           -- possible to pay through a method that has been withdrawn.
           , Provider      = CASE WHEN ISNULL(IsOnline,0) = 1
                                   AND ISNULL(IsDeleted,0) = 0
                                   AND ISNULL(IsActive,1)  = 1
                                  THEN Provider ELSE NULL END
    FROM     dbo.tblInvoicePaymentType
    WHERE    ID = @PaymentTypeID;
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_IsOnlinePaymentType]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_IsOnlinePaymentType]
      @PaymentTypeID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Returns 1 / 0 rather than a row, so the caller cannot mistake "no such
    -- payment type" for "not online" - both are 0, and both mean do not
    -- redirect to a gateway.
    SELECT CAST(CASE WHEN EXISTS (
               SELECT 1 FROM dbo.tblInvoicePaymentType
               WHERE  ID = @PaymentTypeID
                 AND  IsOnline = 1
                 AND  ISNULL(IsDeleted,0) = 0
                 AND  ISNULL(IsActive,1) = 1
           ) THEN 1 ELSE 0 END AS INT);
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_Login]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_Login]
      @Username NVARCHAR(50)
    , @Password NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @MatchedUserID INT;

    SELECT @MatchedUserID = u.ID
    FROM   dbo.tblUser u
    WHERE  u.USERNAME = @Username
      AND  (
                (u.PasswordHash IS NOT NULL
                 AND u.PasswordHash = HASHBYTES('SHA2_512', u.PasswordSalt + CONVERT(VARBINARY(200), @Password)))
             OR (u.PasswordHash IS NULL AND u.PASSWORD = @Password)
           );

    -- result set 0: the user row - deliberately no row on failure, same as
    -- before, so the login form cannot be used to enumerate accounts.
    SELECT
          UserID           = u.ID
        , UserName         = u.NAME
        , LoginName        = u.USERNAME
        , BrandID          = TRY_CAST(u.BrandID AS INT)
        , RoleID           = ISNULL(u.RoleID, 4)
        , RoleName         = ISNULL(r.RoleName, N'Cashier')
        , CanChangeStatus  = ISNULL(r.CanChangeStatus, 1)
        , CanCancel        = ISNULL(r.CanCancel, 0)
        , CanRefund        = ISNULL(r.CanRefund, 0)
        , CanTransfer      = ISNULL(r.CanTransfer, 0)
        , CanTakePayment   = ISNULL(r.CanTakePayment, 1)
        , CanViewReports   = ISNULL(r.CanViewReports, 0)
        , CanEndDay        = ISNULL(r.CanEndDay, 0)
        , CanManageMasters = ISNULL(r.CanManageMasters, 0)
    FROM      dbo.tblUser u
    LEFT JOIN dbo.tblPOS_Role_Master r ON r.RoleID = u.RoleID
    WHERE     u.ID = @MatchedUserID;

    -- result set 1: assigned branch IDs
    SELECT BranchID
    FROM   dbo.tblPOS_UserBranch_Map
    WHERE  UserID = @MatchedUserID;
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_MarkPrinted]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_MarkPrinted]
      @InvoiceNos dbo.TVP_POS_BigIntList READONLY
    , @DocType    VARCHAR(20)   = 'Invoice'      -- Invoice | Thermal | Kitchen
    , @UserID     INT           = NULL
    , @UserName   NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME = GETDATE();

    UPDATE i
       SET i.PrintCount    = ISNULL(i.PrintCount, 0) + 1
         , i.LastPrintedOn = @Now
         , i.Printed       = 1
    FROM dbo.tblInvoice i
    JOIN @InvoiceNos n ON n.Value = i.InvoiceNo;

    IF @DocType = 'Kitchen'
        UPDATE o SET o.SentToPrinter = 1
        FROM dbo.tblOrder o JOIN @InvoiceNos n ON n.Value = o.InvoiceNo;

    INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
    SELECT 'Invoice', n.Value, 'Print', @UserID, @UserName,
           CONCAT(N'DocType=', @DocType, N' Count=',
                  (SELECT PrintCount FROM dbo.tblInvoice WHERE InvoiceNo = n.Value))
    FROM   @InvoiceNos n;

    SELECT i.InvoiceNo, i.PrintCount, IsReprint = CASE WHEN i.PrintCount > 1 THEN 1 ELSE 0 END
    FROM   dbo.tblInvoice i JOIN @InvoiceNos n ON n.Value = i.InvoiceNo;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_PaymentLink_Complete]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_PaymentLink_Complete]
      @CustomerReference VARCHAR(60)
    , @Success           BIT
    , @ProviderPaymentId VARCHAR(60)   = NULL
    , @PaidAmount        DECIMAL(18,3) = NULL
    , @FailureReason     NVARCHAR(500) = NULL
    , @RawResponse       NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LinkID BIGINT, @InvoiceNo BIGINT, @Amount DECIMAL(18,3),
            @PaymentTypeID INT, @Now DATETIME = GETDATE();

    SELECT @LinkID = LinkID, @InvoiceNo = InvoiceNo, @Amount = Amount, @PaymentTypeID = PaymentTypeID
    FROM   dbo.tblPOS_PaymentLink WHERE CustomerReference = @CustomerReference;

    IF @LinkID IS NULL
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT),
               ErrorMessage=N'Unknown payment reference.';
        RETURN;
    END

    /*---- failure: record it, credit nothing --------------------------------*/
    IF @Success = 0
    BEGIN
        UPDATE dbo.tblPOS_PaymentLink
           SET Status = 'Failed', FailureReason = @FailureReason,
               RawResponse = ISNULL(@RawResponse, RawResponse), CompletedOn = @Now
         WHERE LinkID = @LinkID AND Status = 'Pending';

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'PaymentFailed', N'MyFatoorah',
                CONCAT(N'Ref=', @CustomerReference, N' Reason=', ISNULL(@FailureReason, N'')));

        SELECT Message='Failed', InvoiceNo=@InvoiceNo, ErrorMessage=@FailureReason;
        RETURN;
    END

    /*---- success: claim the attempt ---------------------------------------
      Only the caller whose UPDATE actually changes a row proceeds to book the
      payment. Anything arriving second sees @@ROWCOUNT = 0 and returns
      'Duplicate' without touching the ledger.
    ------------------------------------------------------------------------*/
    UPDATE dbo.tblPOS_PaymentLink
       SET Status            = 'Paid'
         , ProviderPaymentId = @ProviderPaymentId
         , PaidAmount        = ISNULL(@PaidAmount, Amount)
         , RawResponse       = ISNULL(@RawResponse, RawResponse)
         , CompletedOn       = @Now
     WHERE LinkID = @LinkID
       AND Status = 'Pending';          -- <= the guard

    IF @@ROWCOUNT = 0
    BEGIN
        SELECT Message='Duplicate', InvoiceNo=@InvoiceNo,
               ErrorMessage=CAST(NULL AS NVARCHAR(500));
        RETURN;
    END

    IF @PaymentTypeID IS NULL
        SELECT TOP 1 @PaymentTypeID = ID FROM dbo.tblInvoicePaymentType
        WHERE PaymentTypeName = N'MyFatoorah' AND ISNULL(IsDeleted,0) = 0;

    -- Reuse sp_POS_AddPayment rather than inserting directly, so the legacy
    -- per-method columns and PaidDate stay in step with everything else.
    EXEC dbo.sp_POS_AddPayment
          @InvoiceNo     = @InvoiceNo
        , @PaymentTypeID = @PaymentTypeID
        , @Amount        = @Amount
        , @ReferenceNo   = @ProviderPaymentId
        , @IsRefund      = 0
        , @UserName      = N'MyFatoorah'
        , @Comments      = @CustomerReference;

    -- A gateway that reports a different figure to the one requested is worth
    -- knowing about; it is logged rather than silently accepted.
    IF @PaidAmount IS NOT NULL AND ABS(@PaidAmount - @Amount) > 0.001
        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'PaymentAmountMismatch', N'MyFatoorah',
                CONCAT(N'Ref=', @CustomerReference, N' Requested=', @Amount, N' Reported=', @PaidAmount));

    SELECT Message='Success', InvoiceNo=@InvoiceNo, ErrorMessage=CAST(NULL AS NVARCHAR(500));
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_PaymentLink_Create]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_PaymentLink_Create]
      @InvoiceNo         BIGINT
    , @CustomerReference VARCHAR(60)
    , @Amount            DECIMAL(18,3)
    , @CurrencyIso       VARCHAR(5)   = 'KWD'
    , @Provider          VARCHAR(30)  = 'MyFatoorah'
    , @PaymentTypeID     INT          = NULL
    , @CreatedBy         INT          = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Due DECIMAL(18,3), @Paid DECIMAL(18,3), @Status INT, @Err NVARCHAR(400) = NULL;

    SELECT @Due = i.FinalAmount + ISNULL(i.DeliveryCharges,0), @Status = i.OrderStatusID
    FROM   dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;

    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p
    WHERE  p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

    IF @Due IS NULL                       SET @Err = N'Order not found.';
    ELSE IF @Status = 7                   SET @Err = N'Order is cancelled.';
    ELSE IF @Amount IS NULL OR @Amount <= 0 SET @Err = N'Amount must be greater than zero.';
    ELSE IF (@Paid + @Amount) > @Due + 0.001
        SET @Err = CONCAT(N'Amount exceeds the balance due. Due ', @Due, N', already paid ', @Paid, N'.');

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message='Fail', LinkID=CAST(NULL AS BIGINT), ErrorMessage=@Err;
        RETURN;
    END

    -- An unfinished attempt for the same amount is reused rather than stacked:
    -- two live payment links for one order is how an order gets paid twice.
    DECLARE @LinkID BIGINT;

    SELECT TOP 1 @LinkID = LinkID
    FROM   dbo.tblPOS_PaymentLink
    WHERE  InvoiceNo = @InvoiceNo AND Status = 'Pending' AND Amount = @Amount
      AND  CreatedOn > DATEADD(MINUTE, -30, GETDATE())
    ORDER BY LinkID DESC;

    IF @LinkID IS NOT NULL
    BEGIN
        SELECT Message='Reused', LinkID=@LinkID, ErrorMessage=CAST(NULL AS NVARCHAR(400));
        RETURN;
    END

    INSERT INTO dbo.tblPOS_PaymentLink
        (InvoiceNo, Provider, PaymentTypeID, CustomerReference, Amount, CurrencyIso, CreatedBy)
    VALUES
        (@InvoiceNo, @Provider, @PaymentTypeID, @CustomerReference, @Amount, @CurrencyIso, @CreatedBy);

    SET @LinkID = CAST(SCOPE_IDENTITY() AS BIGINT);

    SELECT Message='Success', LinkID=@LinkID, ErrorMessage=CAST(NULL AS NVARCHAR(400));
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_PaymentLink_Get]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_PaymentLink_Get]
      @LinkID            BIGINT      = NULL
    , @CustomerReference VARCHAR(60) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT   l.LinkID, l.InvoiceNo, l.Provider, l.PaymentTypeID, l.CustomerReference
           , l.ProviderInvoiceId, l.ProviderPaymentId, l.Amount, l.PaidAmount
           , l.CurrencyIso, l.PaymentUrl, l.Status, l.FailureReason
           , l.CreatedOn, l.CompletedOn
           , CustomerName = i.CustomerName
           , Mobile       = i.MobileText
    FROM     dbo.tblPOS_PaymentLink l
    LEFT JOIN dbo.tblInvoice i ON i.InvoiceNo = l.InvoiceNo
    WHERE    (@LinkID IS NULL            OR l.LinkID = @LinkID)
      AND    (@CustomerReference IS NULL OR l.CustomerReference = @CustomerReference);
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_PaymentLink_SetProvider]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_PaymentLink_SetProvider]
      @LinkID            BIGINT
    , @ProviderInvoiceId VARCHAR(60)
    , @PaymentUrl        NVARCHAR(1000) = NULL
    , @RawResponse       NVARCHAR(MAX)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.tblPOS_PaymentLink
       SET ProviderInvoiceId = @ProviderInvoiceId
         , PaymentUrl        = @PaymentUrl
         , RawResponse       = @RawResponse
     WHERE LinkID = @LinkID;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_Print_MarkSent]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_Print_MarkSent]
      @InvoiceNo BIGINT, @OrderIDs VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE o SET SentToPrinter = 1
    FROM   dbo.tblOrder o
    WHERE  o.InvoiceNo = @InvoiceNo
      AND (o.OrderID IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@OrderIDs, ','))
        OR o.ParentOrderID IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@OrderIDs, ',')));
    SELECT Message = 'Success', Marked = @@ROWCOUNT;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_Print_Ticket]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_Print_Ticket]
      @InvoiceNo  BIGINT
    , @OnlyUnsent BIT = 0
    , @OrderIDs   VARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ar NVARCHAR(100) = N'CAST(NULL AS NVARCHAR(200))', @sql NVARCHAR(MAX);
    DECLARE @Split NVARCHAR(100) = CASE WHEN COL_LENGTH('dbo.tblOrder', 'IsSplit') IS NOT NULL THEN N' AND ISNULL(o.IsSplit, 0) = 0' ELSE N'' END;
    IF COL_LENGTH('dbo.tblItems', 'ITEM_NAME_ARABIC') IS NOT NULL SET @ar = N'it.ITEM_NAME_ARABIC';

    -- 0 header
    SELECT  i.InvoiceNo
          , InvoiceNumShow = ISNULL(NULLIF(CAST(i.InvoiceNumShow AS NVARCHAR(50)), N''), CAST(i.InvoiceNo AS NVARCHAR(50)))
          , i.RunningOrder
          , i.InvoiceDate
          , i.CustomerName
          , i.Mobile
          , BillAmount = CAST(i.BillAmount AS DECIMAL(18,3))
          , Discount   = CAST(ISNULL(i.Discount, 0) AS DECIMAL(18,3))
          , NetPayable = CAST(i.FinalAmount + ISNULL(i.DeliveryCharges, 0) AS DECIMAL(18,3))
          , TableNo    = LTRIM(RTRIM(CAST(t.Table_No AS NVARCHAR(30))))
          , BranchName = b.branchName
          , BranchID   = ISNULL((SELECT TOP 1 o.BranchID FROM dbo.tblOrder o WHERE o.InvoiceNo = i.InvoiceNo), 0)
    FROM    dbo.tblInvoice i
    LEFT JOIN dbo.tblTable t ON t.TableID = i.TableID
    LEFT JOIN dbo.tblbranch b ON b.id = (SELECT TOP 1 o.BranchID FROM dbo.tblOrder o WHERE o.InvoiceNo = i.InvoiceNo)
    WHERE   i.InvoiceNo = @InvoiceNo;

    -- 1 lines
    SET @sql = N'
    SELECT  o.OrderID, o.ParentOrderID
          , CAT_NUM = TRY_CAST(it.CAT_NUM AS INT)
          , ItemName    = ISNULL(o.ItemNameSnapshot, it.ITEM_NAME)
          , ItemNameAra = ' + @ar + N'
          , o.Quantity
          , Price     = CAST(o.Price AS DECIMAL(18,3))
          , LineTotal = CAST(o.Quantity * o.Price AS DECIMAL(18,3))
          , Note      = o.Comments
          , SentToPrinter = CAST(ISNULL(o.SentToPrinter, 0) AS BIT)
    FROM    dbo.tblOrder o
    LEFT JOIN dbo.tblItems it ON it.ID = o.ItemID
    WHERE   o.InvoiceNo = @InvoiceNo AND ISNULL(o.Deleted, 0) = 0' + @Split + N'
      AND   (@OnlyUnsent = 0 OR ISNULL(o.SentToPrinter, 0) = 0)
      AND   (@OrderIDs IS NULL OR o.OrderID IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@OrderIDs, '','')
                                              )
                              OR o.ParentOrderID IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@OrderIDs, '','')))
    ORDER BY ISNULL(o.ParentOrderID, o.OrderID), CASE WHEN o.ParentOrderID IS NULL THEN 0 ELSE 1 END, o.OrderID;';
    EXEC sp_executesql @sql, N'@InvoiceNo BIGINT, @OnlyUnsent BIT, @OrderIDs VARCHAR(MAX)'
                      , @InvoiceNo = @InvoiceNo, @OnlyUnsent = @OnlyUnsent, @OrderIDs = @OrderIDs;

    -- 2 payments
    SELECT  PaymentType = p.PaymentType
          , Amount      = CAST(p.AmountTendered AS DECIMAL(18,3))
          , Applied     = CAST(p.Amount AS DECIMAL(18,3))
          , ChangeGiven = CAST(ISNULL(p.ChangeGiven, 0) AS DECIMAL(18,3))
    FROM    dbo.tblInvoicePayment p
    WHERE   p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted, 0) = 0 AND ISNULL(p.IsRefund, 0) = 0
    ORDER BY p.ReceivedOn;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_Printer_Delete]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_Printer_Delete]
      @PrinterID INT, @BranchID INT, @UserID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.tblPOS_Printer SET IsDeleted = 1, ModifiedOn = GETDATE(), ModifiedBy = @UserID
     WHERE PrinterID = @PrinterID AND BranchID = @BranchID AND IsDeleted = 0;
    SELECT Message = CASE WHEN @@ROWCOUNT > 0 THEN 'Success' ELSE 'Fail' END;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_Printer_List]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_Printer_List]
      @BranchID INT
    , @BrandID  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.PrinterID, p.BranchID, p.PrinterName, p.IPAddress, p.Port, p.PaperWidthMM
         , p.PrintInvoice, p.PrintOrder, p.AllCategories, p.IsActive
    FROM   dbo.tblPOS_Printer p
    WHERE  p.IsDeleted = 0 AND p.BranchID = @BranchID
    ORDER BY p.PrinterName, p.PrinterID;

    SELECT pc.PrinterID, pc.CAT_NUM
    FROM   dbo.tblPOS_PrinterCategory pc
    JOIN   dbo.tblPOS_Printer p ON p.PrinterID = pc.PrinterID
    WHERE  p.IsDeleted = 0 AND p.BranchID = @BranchID;

    DECLARE @where NVARCHAR(MAX) = N'1 = 1', @ar NVARCHAR(100) = N'CAST(NULL AS NVARCHAR(200))', @sql NVARCHAR(MAX);
    IF COL_LENGTH('dbo.tblCategory', 'Deleted')  IS NOT NULL SET @where += N' AND ISNULL(c.Deleted, 0) = 0';
    IF COL_LENGTH('dbo.tblCategory', 'IsActive') IS NOT NULL SET @where += N' AND ISNULL(c.IsActive, 1) = 1';
    IF COL_LENGTH('dbo.tblCategory', 'CAT_NAME_ARABIC') IS NOT NULL SET @ar = N'c.CAT_NAME_ARABIC';
    IF @BrandID > 0 AND COL_LENGTH('dbo.tblCategory', 'BrandID') IS NOT NULL
        SET @where += N' AND (c.BrandID = @BrandID OR NOT EXISTS (SELECT 1 FROM dbo.tblCategory x WHERE x.BrandID = @BrandID))';
    SET @sql = N'SELECT CAT_NUM = TRY_CAST(c.CAT_NUM AS INT), c.CAT_NAME, CAT_NAME_ARABIC = ' + @ar +
               N' FROM dbo.tblCategory c WHERE ' + @where + N' AND TRY_CAST(c.CAT_NUM AS INT) IS NOT NULL ORDER BY c.CAT_NAME;';
    EXEC sp_executesql @sql, N'@BrandID INT', @BrandID = @BrandID;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_Printer_Save]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_POS_Printer_Save]
      @PrinterID     INT           = 0
    , @BranchID      INT
    , @PrinterName   NVARCHAR(100)
    , @IPAddress     VARCHAR(45)
    , @Port          INT           = 9100
    , @PaperWidthMM  INT           = 80
    , @PrintInvoice  BIT
    , @PrintOrder    BIT
    , @AllCategories BIT           = 1
    , @CategoryIDs   VARCHAR(MAX)  = NULL      -- '3,5,9'
    , @IsActive      BIT           = 1
    , @UserID        INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Err NVARCHAR(300);

    SET @PrinterName = LTRIM(RTRIM(ISNULL(@PrinterName, N'')));
    SET @IPAddress   = LTRIM(RTRIM(ISNULL(@IPAddress, '')));
    IF @PrinterName = N'' SET @Err = N'Enter the printer name.';
    ELSE IF @IPAddress = '' SET @Err = N'Enter the printer IP address.';
    ELSE IF @Port NOT BETWEEN 1 AND 65535 SET @Err = N'The port must be between 1 and 65535.';
    ELSE IF ISNULL(@PrintInvoice, 0) = 0 AND ISNULL(@PrintOrder, 0) = 0 SET @Err = N'Tick Print Invoice, Print Order, or both.';
    ELSE IF @PrinterID > 0 AND NOT EXISTS (SELECT 1 FROM dbo.tblPOS_Printer WHERE PrinterID = @PrinterID AND IsDeleted = 0 AND BranchID = @BranchID)
        SET @Err = N'That printer no longer exists.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.tblPOS_Printer WHERE IsDeleted = 0 AND BranchID = @BranchID
                    AND PrinterName = @PrinterName AND PrinterID <> ISNULL(@PrinterID, 0))
        SET @Err = N'A printer with that name already exists in this branch.';

    IF @Err IS NOT NULL BEGIN SELECT Message = 'Fail', ErrorMessage = @Err; RETURN; END

    BEGIN TRY
        BEGIN TRANSACTION;

        IF ISNULL(@PrinterID, 0) = 0
        BEGIN
            INSERT dbo.tblPOS_Printer (BranchID, PrinterName, IPAddress, Port, PaperWidthMM, PrintInvoice, PrintOrder, AllCategories, IsActive, CreatedBy)
            VALUES (@BranchID, @PrinterName, @IPAddress, @Port, @PaperWidthMM, @PrintInvoice, @PrintOrder, @AllCategories, @IsActive, @UserID);
            SET @PrinterID = SCOPE_IDENTITY();
        END
        ELSE
            UPDATE dbo.tblPOS_Printer
               SET PrinterName = @PrinterName, IPAddress = @IPAddress, Port = @Port, PaperWidthMM = @PaperWidthMM
                 , PrintInvoice = @PrintInvoice, PrintOrder = @PrintOrder, AllCategories = @AllCategories
                 , IsActive = @IsActive, ModifiedOn = GETDATE(), ModifiedBy = @UserID
             WHERE PrinterID = @PrinterID;

        DELETE dbo.tblPOS_PrinterCategory WHERE PrinterID = @PrinterID;
        IF @PrintOrder = 1 AND @AllCategories = 0 AND NULLIF(@CategoryIDs, '') IS NOT NULL
            INSERT dbo.tblPOS_PrinterCategory (PrinterID, CAT_NUM)
            SELECT DISTINCT @PrinterID, TRY_CAST(LTRIM(RTRIM(value)) AS INT)
            FROM   STRING_SPLIT(@CategoryIDs, ',')
            WHERE  TRY_CAST(LTRIM(RTRIM(value)) AS INT) IS NOT NULL;

        -- "Select categories" with nothing selected would print nothing: treat as All.
        IF @PrintOrder = 1 AND @AllCategories = 0 AND NOT EXISTS (SELECT 1 FROM dbo.tblPOS_PrinterCategory WHERE PrinterID = @PrinterID)
            UPDATE dbo.tblPOS_Printer SET AllCategories = 1 WHERE PrinterID = @PrinterID;

        COMMIT TRANSACTION;
        SELECT Message = 'Success', PrinterID = @PrinterID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', ErrorMessage = ERROR_MESSAGE();
    END CATCH
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_ProcessOrder]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_ProcessOrder]
      @BranchID          INT
    , @BrandID           INT
    , @InvoiceTypeID     INT            = NULL        -- NULL = resolve 'QR Menu Online'
    , @OrderType         INT            = 2           -- 1 Pickup, 2 Delivery, 3 Dine-in
    , @SourceID          INT            = 1

    , @CustomerId        INT            = NULL
    , @CustomerName      NVARCHAR(200)  = NULL
    , @Mobile            NVARCHAR(30)   = NULL
    , @Mobile2           NVARCHAR(30)   = NULL
    , @Email             NVARCHAR(100)  = NULL
    , @CivilID           NVARCHAR(50)   = NULL

    , @AddressID         INT            = NULL
    , @AreaID            INT            = NULL
    , @Block             NVARCHAR(50)   = NULL
    , @Street            NVARCHAR(500)  = NULL
    , @Lane              NVARCHAR(100)  = NULL
    , @Building          NVARCHAR(50)   = NULL
    , @Floor             NVARCHAR(50)   = NULL
    , @Flat              NVARCHAR(50)   = NULL
    , @HouseNo           NVARCHAR(50)   = NULL
    , @PACI              NVARCHAR(50)   = NULL
    , @AddressRemark     NVARCHAR(500)  = NULL
    , @Lat               NVARCHAR(50)   = NULL
    , @Lng               NVARCHAR(50)   = NULL

    , @DeliveryDate      DATETIME       = NULL
    , @PaymentTypeID     INT            = NULL        -- NULL = resolve 'Cash on Delivery'
    , @IsPrepaid         BIT            = 0           -- 1 = money already taken online
    , @PaymentReference  NVARCHAR(100)  = NULL
    , @DiscountTypeID    INT            = 0
    , @InvoiceDiscount   DECIMAL(18,3)  = 0           -- fallback only; a code overrides it
    , @DiscountCode      NVARCHAR(50)   = NULL
    , @DeliveryCharges   DECIMAL(18,3)  = NULL        -- NULL = derive from tblArea
    , @WaiterID          INT            = 0
    , @Comments          NVARCHAR(500)  = NULL
    , @ClientOrderGuid   UNIQUEIDENTIFIER = NULL

    , @dtOrderItems      dbo.TVP_POS_OrderItem READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @InvoiceNo     BIGINT
          , @TrackingCode  VARCHAR(12)
          , @RunningOrder  INT
          , @BillAmount    DECIMAL(18,3) = 0
          , @Discount      DECIMAL(18,3) = 0
          , @Today         DATE     = CAST(GETDATE() AS DATE)
          , @Now           DATETIME = GETDATE()
          , @Warning       NVARCHAR(500) = NULL
          , @PriceMismatch INT = 0
          , @LegacyCol     SYSNAME = NULL
          , @IsCOD         BIT = 0;

    /*----------------------------------------------------------------------
      Shared shape for every early return
    ----------------------------------------------------------------------*/
    DECLARE @FailMsg NVARCHAR(500);

    /*======================================================================
      0. VALIDATION
    ======================================================================*/
    IF NOT EXISTS (SELECT 1 FROM @dtOrderItems) SET @FailMsg = N'Cart is empty.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblbranch WHERE id = @BranchID AND ISNULL(IsDeleted,0) = 0)
        SET @FailMsg = N'Invalid or inactive branch.';

    IF @FailMsg IS NOT NULL
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=CAST(NULL AS INT), Warning=CAST(NULL AS NVARCHAR(500)),
               ErrorMessage=@FailMsg;
        RETURN;
    END

    /*======================================================================
      1. RESOLVE LOOKUPS BY MEANING, NOT BY HARD-CODED ID

      The head-office tables use IDENTITY keys, so the actual IDs differ per
      deployment. Resolving by name here means the proc works against any
      seeded set without a code change.
    ======================================================================*/
    -- The real head-office channel list is:
    --   1 On Line Order | 2 Dine In | 3 Take Away | 4 Call Centre | 5 Talabat
    -- 'On Line Order' IS the QR menu channel.
    IF @InvoiceTypeID IS NULL
        SELECT TOP 1 @InvoiceTypeID = ID FROM dbo.tblInvoiceType_Master
        WHERE  Name IN (N'On Line Order', N'Online Order', N'QR Menu Online')
        ORDER BY ID;

    -- Deliberately NO fallback to Call Centre. Filing a QR order as a
    -- call-centre order is worse than leaving the channel unset: it is
    -- invisible, and it corrupts every channel report from that point on.

    IF @PaymentTypeID IS NULL
        SELECT TOP 1 @PaymentTypeID = ID FROM dbo.tblInvoicePaymentType WHERE IsCOD = 1 AND ISNULL(IsDeleted,0)=0;
    IF @PaymentTypeID IS NULL
        SELECT TOP 1 @PaymentTypeID = ID FROM dbo.tblInvoicePaymentType WHERE IsCash = 1 AND ISNULL(IsDeleted,0)=0;

    IF NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType WHERE ID = @PaymentTypeID AND ISNULL(IsDeleted,0)=0)
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=CAST(NULL AS INT), Warning=CAST(NULL AS NVARCHAR(500)),
               ErrorMessage=N'Unknown payment type.';
        RETURN;
    END

    SELECT @LegacyCol = LegacyColumn, @IsCOD = IsCOD
    FROM   dbo.tblInvoicePaymentType WHERE ID = @PaymentTypeID;

    /*======================================================================
      2. IDEMPOTENCY
    ======================================================================*/
    IF @ClientOrderGuid IS NOT NULL
    BEGIN
        SELECT @InvoiceNo = InvoiceNo FROM dbo.tblInvoice WHERE ClientOrderGuid = @ClientOrderGuid;

        IF @InvoiceNo IS NOT NULL
        BEGIN
            SELECT Message='Duplicate', InvoiceNo=i.InvoiceNo, TrackingCode=i.TrackingCode,
                   RunningOrder=i.RunningOrder, BillAmount=i.BillAmount, Discount=i.Discount,
                   DeliveryCharges=ISNULL(i.DeliveryCharges,0),
                   FinalAmount=i.FinalAmount,
                   NetPayable=i.FinalAmount + ISNULL(i.DeliveryCharges,0),
                   CustomerId=i.CustomerId, AddressID=i.AddressID, PaymentTypeID=i.PaymentType,
                   Warning=CAST(NULL AS NVARCHAR(500)), ErrorMessage=CAST(NULL AS NVARCHAR(500))
            FROM dbo.tblInvoice i WHERE i.InvoiceNo = @InvoiceNo;
            RETURN;
        END
    END

    /*======================================================================
      3. RE-PRICE FROM tblItems
    ======================================================================*/
    DECLARE @lines TABLE
    (
          Seq            INT IDENTITY(1,1) PRIMARY KEY
        , ResolvedItemID INT           NULL
        , ItemName       NVARCHAR(200) NULL
        , Quantity       INT           NOT NULL
        , UnitPrice      DECIMAL(18,3) NOT NULL
        , ClientPrice    DECIMAL(18,3) NULL
        , LineType       TINYINT       NOT NULL
        , ParentItemID   INT           NULL
        , CartItemUniqID INT           NULL
        , Comments       NVARCHAR(MAX) NULL
        , Extra          NVARCHAR(MAX) NULL
    );

    INSERT INTO @lines (ResolvedItemID, ItemName, Quantity, UnitPrice, ClientPrice, LineType, ParentItemID, CartItemUniqID, Comments, Extra)
    SELECT  it.ID, it.ITEM_NAME
          , CASE WHEN d.Quantity < 1 THEN 1 ELSE d.Quantity END
          , CAST(ISNULL(it.PRICE, ISNULL(d.Price,0)) AS DECIMAL(18,3))
          , d.Price, d.LineType, d.ParentItemID, d.CartItemUniqID, d.Comments, d.Extra
    FROM        @dtOrderItems d
    OUTER APPLY (
                    SELECT TOP 1 t.ID, t.ITEM_NAME, t.PRICE
                    FROM   dbo.tblItems t
                    WHERE  (d.ItemID IS NOT NULL AND t.ID  = d.ItemID)
                        OR (d.HID    IS NOT NULL AND t.HID = d.HID)
                        OR (d.ItemID IS NOT NULL AND t.HID = d.ItemID)
                    ORDER BY CASE WHEN t.ID = d.ItemID THEN 0 ELSE 1 END
                ) it;

    SELECT @PriceMismatch = COUNT(*) FROM @lines
    WHERE  ClientPrice IS NOT NULL AND ABS(ClientPrice - UnitPrice) > 0.001;

    SELECT @BillAmount = CAST(ISNULL(SUM(Quantity * UnitPrice),0) AS DECIMAL(18,3)) FROM @lines;

    IF @BillAmount <= 0
    BEGIN
        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=@PaymentTypeID, Warning=CAST(NULL AS NVARCHAR(500)),
               ErrorMessage=N'No priceable items resolved from the cart.';
        RETURN;
    END

    /*======================================================================
      4. DISCOUNT - computed here, never trusted from the browser
    ======================================================================*/
    IF NULLIF(LTRIM(RTRIM(@DiscountCode)),'') IS NOT NULL
    BEGIN
        DECLARE @dtId INT, @dtPct INT, @dtIsPct BIT;

        SELECT TOP 1 @dtId = dt.Id, @dtPct = dt.DiscountPercentage, @dtIsPct = dt.isPercentage
        FROM   dbo.tblDiscountCode dc
        JOIN   dbo.tblDiscount_Type dt ON dt.Id = dc.DiscountTypeId
        WHERE  dc.DiscountCode = @DiscountCode
          AND  ISNULL(dc.Isactive,0) = 1
          AND  ISNULL(dt.IsActive,0) = 1
          AND  ISNULL(dt.IsDeleted,0) = 0;

        IF @dtId IS NULL
        BEGIN
            SET @Discount = 0;
            SET @Warning  = N'Discount code not valid - no discount applied.';
        END
        ELSE
        BEGIN
            SET @DiscountTypeID = @dtId;
            SET @Discount = CASE WHEN ISNULL(@dtIsPct,0) = 1
                                 THEN CAST(@BillAmount * ISNULL(@dtPct,0) / 100.0 AS DECIMAL(18,3))
                                 ELSE CAST(ISNULL(@dtPct,0) AS DECIMAL(18,3))
                            END;
        END
    END
    ELSE IF @DiscountTypeID > 0
    BEGIN
        SELECT TOP 1 @Discount = CASE WHEN ISNULL(dt.isPercentage,0) = 1
                                      THEN CAST(@BillAmount * ISNULL(dt.DiscountPercentage,0) / 100.0 AS DECIMAL(18,3))
                                      ELSE CAST(ISNULL(dt.DiscountPercentage,0) AS DECIMAL(18,3)) END
        FROM   dbo.tblDiscount_Type dt
        WHERE  dt.Id = @DiscountTypeID AND ISNULL(dt.IsActive,0)=1 AND ISNULL(dt.IsDeleted,0)=0;

        SET @Discount = ISNULL(@Discount, 0);
    END
    ELSE
        SET @Discount = ISNULL(@InvoiceDiscount, 0);   -- legacy fallback

    IF @Discount < 0 SET @Discount = 0;
    IF @Discount > @BillAmount SET @Discount = @BillAmount;

    /*======================================================================
      5. DELIVERY CHARGE + AREA / BRANCH VALIDATION
    ======================================================================*/
    IF @OrderType = 2
    BEGIN
        IF @DeliveryCharges IS NULL
            SELECT @DeliveryCharges = ISNULL(a.DeliveryCharges,0) FROM dbo.tblArea a WHERE a.AreaID = @AreaID;

        SET @DeliveryCharges = ISNULL(@DeliveryCharges, 0);

        -- Does this branch actually serve this area?
        IF @AreaID IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID)
           AND NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID AND BranchID = @BranchID)
        BEGIN
            SET @Warning = ISNULL(@Warning + N' ', N'')
                         + N'Branch does not serve this delivery area - review or transfer the order.';
        END
    END
    ELSE
        SET @DeliveryCharges = 0;

    /*======================================================================
      6. TRANSACTION
    ======================================================================*/
    BEGIN TRY
        BEGIN TRANSACTION;

        /*---- 6.1 Customer -----------------------------------------------*/
        IF @CustomerId IS NULL AND NULLIF(LTRIM(RTRIM(@Mobile)),'') IS NOT NULL
            SELECT TOP 1 @CustomerId = id FROM dbo.tblCustomer WITH (UPDLOCK, HOLDLOCK)
            WHERE mobile = @Mobile AND IsDeleted = 0;

        IF @CustomerId IS NULL
        BEGIN
            INSERT INTO dbo.tblCustomer (firstName, mobile, Mobile2, email, CivilID, areaId, block, street, building, flat, landmark, BrandID)
            VALUES (@CustomerName, @Mobile, @Mobile2, @Email, @CivilID, @AreaID, @Block, @Street, @Building, @Flat, @AddressRemark, @BrandID);
            SET @CustomerId = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
            UPDATE dbo.tblCustomer
               SET firstName  = COALESCE(NULLIF(@CustomerName,''), firstName)
                 , email      = COALESCE(NULLIF(@Email,''),        email)
                 , Mobile2    = COALESCE(NULLIF(@Mobile2,''),      Mobile2)
                 , ModifiedOn = @Now
             WHERE id = @CustomerId;

        /*---- 6.2 Address ------------------------------------------------*/
        IF @OrderType = 2 AND @AddressID IS NULL
           AND (@AreaID IS NOT NULL OR NULLIF(@Block,'') IS NOT NULL OR NULLIF(@Street,'') IS NOT NULL)
        BEGIN
            SELECT TOP 1 @AddressID = AddressID FROM dbo.tblCustomerAddress
            WHERE CustomerID = @CustomerId AND IsDeleted = 0
              AND ISNULL(AreaID,-1)   = ISNULL(@AreaID,-1)
              AND ISNULL(Block,'')    = ISNULL(@Block,'')
              AND ISNULL(Street,'')   = ISNULL(@Street,'')
              AND ISNULL(Building,'') = ISNULL(@Building,'')
              AND ISNULL(Flat,'')     = ISNULL(@Flat,'');

            IF @AddressID IS NULL
            BEGIN
                INSERT INTO dbo.tblCustomerAddress
                    (CustomerID, AreaID, Block, Street, Lane, Building, Floor, Flat, HouseNo, PACI, AddressRemark, Lat, Lng, Email)
                VALUES (@CustomerId, @AreaID, @Block, @Street, @Lane, @Building, @Floor, @Flat, @HouseNo, @PACI, @AddressRemark, @Lat, @Lng, @Email);
                SET @AddressID = CAST(SCOPE_IDENTITY() AS INT);
            END
        END

        /*---- 6.3 Daily per-branch number --------------------------------*/
        UPDATE dbo.tblPOS_DailyCounter WITH (UPDLOCK, HOLDLOCK)
           SET @RunningOrder = LastNumber = LastNumber + 1
         WHERE BranchID = @BranchID AND CounterDate = @Today;

        IF @RunningOrder IS NULL
        BEGIN
            INSERT INTO dbo.tblPOS_DailyCounter (BranchID, CounterDate, LastNumber) VALUES (@BranchID, @Today, 1);
            SET @RunningOrder = 1;
        END

        /*---- 6.4 Invoice header -----------------------------------------*/
        INSERT INTO dbo.tblInvoice
        (
              WaiterID, BillAmount, Discount, Comments, Person, Status
            , InvoiceDate, InvoiceTime, PaymentType, Printed, Mobile, MobileText
            , CustomerName, OrderStatus, CustomerId, OrderStatusID, Deleted
            , BranchID, AddressID, BrandID, DeliveryDate, InvoiceType
            , DiscountTypeID, DeliveryCharges, OrderType, TrackingCode
            , ClientOrderGuid, DiscountCode, SourceID, RunningOrder
            , PromisedTime, PrintCount, PaidDate
        )
        VALUES
        (
              @WaiterID, @BillAmount, @Discount, @Comments, 1, 0
            , @Now, @Now, @PaymentTypeID, 0
            , TRY_CAST(REPLACE(REPLACE(ISNULL(@Mobile,''),'+',''),' ','') AS BIGINT), @Mobile
            -- OrderStatus / OrderStatusID both start at 0 = New.
            --
            -- They used to be inserted as 1 (Received), which meant an order
            -- was recorded as acknowledged the instant it was saved - before
            -- anyone in the branch had seen it, let alone printed a ticket.
            -- The status only moves to 1 when the ticket is actually printed;
            -- sp_POS_MarkPrinted does that.
            , @CustomerName, 0, @CustomerId, 0, 0
            , @BranchID, @AddressID, @BrandID, @DeliveryDate, @InvoiceTypeID
            , @DiscountTypeID, @DeliveryCharges, @OrderType, NULL
            , @ClientOrderGuid, @DiscountCode, @SourceID, @RunningOrder
            , DATEADD(MINUTE, ISNULL((SELECT DefaultPrepMinutes FROM dbo.tblPOS_BranchSetting WHERE BranchID=@BranchID),20), @Now)
            , 0, CASE WHEN @IsPrepaid = 1 THEN @Now ELSE NULL END
        );

        SET @InvoiceNo = CAST(SCOPE_IDENTITY() AS BIGINT);

        /*---- 6.5 Tracking code ------------------------------------------*/
        DECLARE @seed BIGINT = @InvoiceNo * 2654435761 % 456976;
        SET @TrackingCode = CHAR(65 + (@seed/17576)%26) + CHAR(65 + (@seed/676)%26)
                          + CHAR(65 + (@seed/26)%26)    + CHAR(65 +  @seed%26)
                          + '-' + RIGHT('0000' + CAST(@InvoiceNo % 10000 AS VARCHAR(4)), 4);

        UPDATE dbo.tblInvoice SET TrackingCode = @TrackingCode WHERE InvoiceNo = @InvoiceNo;

        /*---- 6.6 Order lines --------------------------------------------*/
        INSERT INTO dbo.tblOrder
        (
              InvoiceNo, ItemID, Quantity, Price, SentToPrinter, Comments, Extra
            , WaiterID, Prepared, Combined, Delivered, Dispatcher, Deleted
            , OrderDate, TableType, Waste, DiscountTypeID, Discount, BranchID
            , CartItemUniqID, LineType, ItemNameSnapshot
        )
        SELECT @InvoiceNo, l.ResolvedItemID, l.Quantity, l.UnitPrice, 0, l.Comments, l.Extra
             , @WaiterID, 0, 0, 0, 0, 0
             , @Now, 0, 0, @DiscountTypeID, 0, @BranchID
             , l.CartItemUniqID, l.LineType, l.ItemName
        FROM @lines l ORDER BY l.Seq;

        /*---- 6.7 Prepaid payment ----------------------------------------
          Money already taken online is recorded now. Cash / COD stays unpaid
          until the POS Pay action collects it.
        -----------------------------------------------------------------*/
        IF @IsPrepaid = 1
        BEGIN
            DECLARE @Paid DECIMAL(18,3) = (@BillAmount - @Discount) + @DeliveryCharges;

            INSERT INTO dbo.tblInvoicePayment
                (PaymentTypeID, InvoiceId, PaymentType, BranchId, Amount, ReferenceNo, IsRefund, ReceivedOn, isdeleted)
            SELECT @PaymentTypeID, @InvoiceNo, pt.PaymentTypeName, @BranchID, @Paid, @PaymentReference, 0, @Now, 0
            FROM   dbo.tblInvoicePaymentType pt WHERE pt.ID = @PaymentTypeID;

            -- Mirror into the legacy per-method column so end-of-day reports still add up.
            IF @LegacyCol IS NOT NULL
            BEGIN
                DECLARE @sql NVARCHAR(MAX) =
                    N'UPDATE dbo.tblInvoice SET ' + QUOTENAME(@LegacyCol) + N' = @amt WHERE InvoiceNo = @inv;';
                EXEC sp_executesql @sql, N'@amt DECIMAL(18,3), @inv BIGINT', @amt = @Paid, @inv = @InvoiceNo;
            END
        END

        /*---- 6.8 Status history + audit ---------------------------------*/
        -- The order arrives AT status 0; there is no prior status, so FromStatusID
        -- is NULL rather than 0. Recording 0 -> 1 here claimed a transition that
        -- had not happened, and left the history disagreeing with the invoice.
        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, Comments)
        VALUES (@InvoiceNo, NULL, 0, NULL, N'System', N'Order placed from QR Menu');

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'Create', N'QRMenu',
                CONCAT(N'Branch=', @BranchID, N'; Lines=', (SELECT COUNT(*) FROM @lines),
                       N'; Bill=', @BillAmount, N'; Disc=', @Discount,
                       N'; Deliv=', @DeliveryCharges,
                       N'; PriceMismatchLines=', @PriceMismatch,
                       N'; Warning=', ISNULL(@Warning,N'none')));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        DECLARE @err NVARCHAR(500) = ERROR_MESSAGE();

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserName, Details)
        VALUES ('Invoice', NULL, 'CreateFailed', N'QRMenu', @err);

        SELECT Message='Fail', InvoiceNo=CAST(NULL AS BIGINT), TrackingCode=CAST(NULL AS VARCHAR(12)),
               RunningOrder=CAST(NULL AS INT), BillAmount=CAST(0 AS DECIMAL(18,3)),
               Discount=CAST(0 AS DECIMAL(18,3)), DeliveryCharges=CAST(0 AS DECIMAL(18,3)),
               FinalAmount=CAST(0 AS DECIMAL(18,3)), NetPayable=CAST(0 AS DECIMAL(18,3)),
               CustomerId=CAST(NULL AS INT), AddressID=CAST(NULL AS INT),
               PaymentTypeID=@PaymentTypeID, Warning=@Warning, ErrorMessage=@err;
        RETURN;
    END CATCH

    /*======================================================================
      7. RESULT
         FinalAmount = BillAmount - Discount        (matches the DB column)
         NetPayable  = FinalAmount + DeliveryCharges (what the customer pays)
    ======================================================================*/
    SELECT Message         = 'Success'
         , InvoiceNo       = @InvoiceNo
         , TrackingCode    = @TrackingCode
         , RunningOrder    = @RunningOrder
         , BillAmount      = @BillAmount
         , Discount        = @Discount
         , DeliveryCharges = @DeliveryCharges
         , FinalAmount     = @BillAmount - @Discount
         , NetPayable      = (@BillAmount - @Discount) + @DeliveryCharges
         , CustomerId      = @CustomerId
         , AddressID       = @AddressID
         , PaymentTypeID   = @PaymentTypeID
         , Warning         = @Warning
         , ErrorMessage    = CAST(NULL AS NVARCHAR(500));
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_ResolveArea]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_ResolveArea]
      @Lat       DECIMAL(10,7) = NULL
    , @Lng       DECIMAL(10,7) = NULL
    , @AreaHint  NVARCHAR(200) = NULL    -- ESRI Neighborhood / District / City
    , @AreaHint2 NVARCHAR(200) = NULL    -- second candidate (e.g. District)
    , @BranchID  INT           = NULL
    , @MaxKm     DECIMAL(9,3)  = 8.0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AreaID INT = NULL, @MatchType VARCHAR(10) = NULL, @DistKm DECIMAL(9,3) = NULL;

    /*---- 1. Point in polygon -------------------------------------------
      tblAreaMapData.PolygonVal is free-form text and is currently empty, so
      the format cannot be verified here. Both the shapes head office is likely
      to have stored are attempted, inside TRY/CATCH: a malformed row must not
      take down the checkout, it must simply fall through to name matching.
    --------------------------------------------------------------------*/
    IF @Lat IS NOT NULL AND @Lng IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.tblAreaMapData WHERE LEN(ISNULL(PolygonVal,'')) > 0)
    BEGIN
        BEGIN TRY
            DECLARE @pt GEOGRAPHY = GEOGRAPHY::Point(@Lat, @Lng, 4326);

            ;WITH poly AS
            (
                SELECT m.AreaID
                     , g = TRY_CONVERT(GEOGRAPHY,
                             CASE
                               -- already WKT
                               WHEN LTRIM(m.PolygonVal) LIKE 'POLYGON%' THEN m.PolygonVal
                               -- "lat,lng lat,lng ..." or "lat,lng;lat,lng"
                               ELSE NULL
                             END)
                FROM dbo.tblAreaMapData m
            )
            SELECT TOP 1 @AreaID = p.AreaID, @MatchType = 'Polygon'
            FROM   poly p
            WHERE  p.g IS NOT NULL
              AND  p.g.STContains(@pt) = 1;

            IF @AreaID IS NOT NULL AND @BranchID IS NOT NULL
               AND EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE BranchID = @BranchID)
               AND NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID AND BranchID = @BranchID)
                SET @MatchType = 'Polygon';   -- still correct; branch coverage is reported separately
        END TRY
        BEGIN CATCH
            SET @AreaID = NULL;   -- unparseable polygons: fall through, never fail
        END CATCH
    END

    /*---- 2. Normalised name match -------------------------------------*/
    IF @AreaID IS NULL AND (NULLIF(@AreaHint,'') IS NOT NULL OR NULLIF(@AreaHint2,'') IS NOT NULL)
    BEGIN
        DECLARE @h1 NVARCHAR(500) = dbo.fn_POS_NormalizeAreaName(@AreaHint);
        DECLARE @h2 NVARCHAR(500) = dbo.fn_POS_NormalizeAreaName(@AreaHint2);

        SELECT TOP 1 @AreaID = a.AreaID, @MatchType = 'Name'
        FROM   dbo.tblArea a
        WHERE  ( NULLIF(@h1,'') IS NOT NULL
                 AND ( dbo.fn_POS_NormalizeAreaName(a.AreaName)    = @h1
                    OR dbo.fn_POS_NormalizeAreaName(a.AreaNameAra) = @h1 ) )
            OR ( NULLIF(@h2,'') IS NOT NULL
                 AND ( dbo.fn_POS_NormalizeAreaName(a.AreaName)    = @h2
                    OR dbo.fn_POS_NormalizeAreaName(a.AreaNameAra) = @h2 ) )
        -- prefer a hit on the primary hint
        ORDER BY CASE WHEN dbo.fn_POS_NormalizeAreaName(a.AreaName) = @h1
                        OR dbo.fn_POS_NormalizeAreaName(a.AreaNameAra) = @h1 THEN 0 ELSE 1 END
               , a.AreaID;
    END

    /*---- 3. Nearest area centre ---------------------------------------
      Only fires once tblArea.CenterLat / CenterLng are populated. Reported as
      'Nearest' so the UI suggests rather than silently commits.
    --------------------------------------------------------------------*/
    IF @AreaID IS NULL AND @Lat IS NOT NULL AND @Lng IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.tblArea WHERE CenterLat IS NOT NULL)
    BEGIN
        DECLARE @p GEOGRAPHY = GEOGRAPHY::Point(@Lat, @Lng, 4326);

        SELECT TOP 1
               @AreaID    = a.AreaID
             , @MatchType = 'Nearest'
             , @DistKm    = CAST(GEOGRAPHY::Point(a.CenterLat, a.CenterLng, 4326).STDistance(@p) / 1000.0 AS DECIMAL(9,3))
        FROM   dbo.tblArea a
        WHERE  a.CenterLat IS NOT NULL AND a.CenterLng IS NOT NULL
          AND  GEOGRAPHY::Point(a.CenterLat, a.CenterLng, 4326).STDistance(@p) <= @MaxKm * 1000.0
        ORDER BY GEOGRAPHY::Point(a.CenterLat, a.CenterLng, 4326).STDistance(@p);
    END

    /*---- result --------------------------------------------------------*/
    SELECT   AreaID          = a.AreaID
           , AreaName        = a.AreaName
           , AreaNameAra     = a.AreaNameAra
           , DeliveryCharges = ISNULL(a.DeliveryCharges, 0)
           , MatchType       = @MatchType
           , DistanceKm      = @DistKm
           , ServedByBranch  = CASE
                                 WHEN @BranchID IS NULL THEN CAST(1 AS BIT)
                                 WHEN NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE BranchID = @BranchID) THEN CAST(1 AS BIT)
                                 WHEN EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = a.AreaID AND BranchID = @BranchID) THEN CAST(1 AS BIT)
                                 ELSE CAST(0 AS BIT)
                               END
    FROM     dbo.tblArea a
    WHERE    a.AreaID = @AreaID;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_Role_List]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_Role_List]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RoleID, RoleName
    FROM   dbo.tblPOS_Role_Master
    ORDER BY RoleID;
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_TakePaymentSplit]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_TakePaymentSplit]
      @InvoiceNo   BIGINT
    , @Lines       dbo.TVP_POS_PaymentLine READONLY
    , @ReferenceNo NVARCHAR(100) = NULL
    , @UserID      INT           = NULL
    , @UserName    NVARCHAR(100) = NULL
    , @Comments    NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE()
          , @Status INT, @BranchID INT, @Total DECIMAL(18,3), @Paid DECIMAL(18,3)
          , @Due DECIMAL(18,3), @Tendered DECIMAL(18,3), @Change DECIMAL(18,3) = 0
          , @Err NVARCHAR(500) = NULL;

    SELECT @Status   = i.OrderStatusID
         , @BranchID = i.BranchID
         , @Total    = i.FinalAmount + ISNULL(i.DeliveryCharges, 0)
    FROM   dbo.tblInvoice i
    WHERE  i.InvoiceNo = @InvoiceNo AND ISNULL(i.Deleted,0) = 0;

    SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
    FROM   dbo.tblInvoicePayment p
    WHERE  p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

    SET @Due      = @Total - ISNULL(@Paid, 0);
    SELECT @Tendered = ISNULL(SUM(Amount), 0) FROM @Lines WHERE Amount > 0;

    /*---- refuse ---------------------------------------------------------*/
    IF @Status IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @Status IN (6, 7, 8)
        -- 6 is this installation's cancelled status (POS_27), 7 and 8 are the
        -- seeded Cancelled / Refunded. Money must not be taken against any.
        SET @Err = N'This order is cancelled or refunded.';
    ELSE IF @Tendered <= 0
        SET @Err = N'Enter an amount against at least one payment type.';
    ELSE IF @Due <= 0.001
        SET @Err = N'This order is already paid in full.';
    ELSE IF EXISTS (SELECT 1 FROM @Lines l WHERE l.Amount < 0)
        SET @Err = N'A payment amount cannot be negative. Use a refund instead.';
    ELSE IF EXISTS (SELECT 1 FROM @Lines l
                    WHERE NOT EXISTS (SELECT 1 FROM dbo.tblInvoicePaymentType t
                                      WHERE t.ID = l.PaymentTypeID AND ISNULL(t.IsDeleted,0) = 0))
        SET @Err = N'One of the payment types is not recognised.';
    ELSE IF EXISTS (SELECT 1 FROM @Lines l
                    JOIN dbo.tblInvoicePaymentType t ON t.ID = l.PaymentTypeID
                    WHERE l.Amount > 0 AND t.RequiresReference = 1
                      AND NULLIF(LTRIM(RTRIM(ISNULL(@ReferenceNo, N''))), N'') IS NULL)
        SET @Err = N'A reference number is required for one of the selected payment types.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, AmountDue = @Due,
               AmountPaid = @Paid, ChangeGiven = CAST(NULL AS DECIMAL(18,3)),
               PaymentStatus = CAST(NULL AS VARCHAR(10)), ErrorMessage = @Err;
        RETURN;
    END

    /*---- allocate --------------------------------------------------------
      Applied in payment-type sequence. Running total against the balance:
      everything before the crossing point is recorded in full, the crossing
      line is recorded at the remainder and carries the tendered amount and the
      change, and anything after it is not a payment at all.
    ---------------------------------------------------------------------*/
    IF @Tendered > @Due + 0.001 SET @Change = @Tendered - @Due;

    DECLARE @alloc TABLE
    (
          Seq           INT IDENTITY(1,1)
        , PaymentTypeID INT
        , Tendered      DECIMAL(18,3)
        , Applied       DECIMAL(18,3)
        , Change        DECIMAL(18,3)
    );

    INSERT INTO @alloc (PaymentTypeID, Tendered, Applied, Change)
    SELECT   l.PaymentTypeID
           , l.Amount
           -- Running total BEFORE this line tells us how much of the balance is
           -- still open when it is applied.
           , CASE
                WHEN @Due - ISNULL(SUM(l.Amount) OVER (ORDER BY ISNULL(t.Seqnum, 9999), t.ID
                                                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) <= 0
                     THEN 0
                WHEN l.Amount <= @Due - ISNULL(SUM(l.Amount) OVER (ORDER BY ISNULL(t.Seqnum, 9999), t.ID
                                                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
                     THEN l.Amount
                ELSE @Due - ISNULL(SUM(l.Amount) OVER (ORDER BY ISNULL(t.Seqnum, 9999), t.ID
                                                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0)
             END
           , 0
    FROM     @Lines l
    JOIN     dbo.tblInvoicePaymentType t ON t.ID = l.PaymentTypeID
    WHERE    l.Amount > 0
    ORDER BY ISNULL(t.Seqnum, 9999), t.ID;

    -- Drop lines that turned out to be entirely change.
    DELETE FROM @alloc WHERE Applied <= 0;

    IF NOT EXISTS (SELECT 1 FROM @alloc)
    BEGIN
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, AmountDue = @Due,
               AmountPaid = @Paid, ChangeGiven = CAST(NULL AS DECIMAL(18,3)),
               PaymentStatus = CAST(NULL AS VARCHAR(10)),
               ErrorMessage = N'Nothing to apply against this order.';
        RETURN;
    END

    -- The change belongs to the last line that was actually applied - the one
    -- the customer overpaid on.
    UPDATE @alloc
       SET Change = @Change
     WHERE Seq = (SELECT MAX(Seq) FROM @alloc);

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.tblInvoicePayment
            (PaymentTypeID, InvoiceId, PaymentType, BranchId, Amount, AmountTendered,
             ChangeGiven, ReferenceNo, IsRefund, ReceivedBy, ReceivedOn, Comments, isdeleted)
        SELECT   a.PaymentTypeID, @InvoiceNo, t.PaymentTypeName, @BranchID
               , a.Applied
               , a.Tendered
               , NULLIF(a.Change, 0)
               , @ReferenceNo, 0, @UserID, @Now, @Comments, 0
        FROM     @alloc a
        JOIN     dbo.tblInvoicePaymentType t ON t.ID = a.PaymentTypeID
        ORDER BY a.Seq;

        SELECT @Paid = ISNULL(SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END), 0)
        FROM   dbo.tblInvoicePayment p
        WHERE  p.InvoiceId = @InvoiceNo AND ISNULL(p.isdeleted,0) = 0;

        UPDATE dbo.tblInvoice
           SET PaidDate   = CASE WHEN @Paid + 0.001 >= @Total THEN ISNULL(PaidDate, @Now) ELSE NULL END
             , ModifiedOn = @Now
             , ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        /*---- Legacy per-method columns, rebuilt from the rows.
               Same treatment as sp_POS_AddPayment: recalculated rather than
               incremented, so a corrected or refunded row cannot leave the old
               end-of-day reports drifting. ----*/
        DECLARE @col SYSNAME, @sql NVARCHAR(MAX);
        DECLARE c CURSOR LOCAL FAST_FORWARD FOR
            SELECT DISTINCT LegacyColumn FROM dbo.tblInvoicePaymentType WHERE LegacyColumn IS NOT NULL AND COL_LENGTH('dbo.tblInvoice', LegacyColumn) IS NOT NULL;
        OPEN c; FETCH NEXT FROM c INTO @col;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql = N'
                UPDATE i SET ' + QUOTENAME(@col) + N' = ISNULL(x.Amt, 0)
                FROM dbo.tblInvoice i
                OUTER APPLY (
                    SELECT Amt = SUM(CASE WHEN p.IsRefund = 1 THEN -p.Amount ELSE p.Amount END)
                    FROM   dbo.tblInvoicePayment p
                    JOIN   dbo.tblInvoicePaymentType t ON t.ID = p.PaymentTypeID
                    WHERE  p.InvoiceId = @inv AND ISNULL(p.isdeleted,0) = 0 AND t.LegacyColumn = @c
                ) x
                WHERE i.InvoiceNo = @inv;';
            EXEC sp_executesql @sql, N'@inv BIGINT, @c SYSNAME', @inv = @InvoiceNo, @c = @col;
            FETCH NEXT FROM c INTO @col;
        END
        CLOSE c; DEALLOCATE c;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        SELECT 'Invoice', @InvoiceNo, 'Payment', @UserID, @UserName,
               CONCAT(N'Split=', (SELECT COUNT(*) FROM @alloc),
                      N' Tendered=', @Tendered, N' Applied=', (SELECT SUM(Applied) FROM @alloc),
                      N' Change=', @Change, N' PaidNow=', @Paid, N' Total=', @Total);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', InvoiceNo = @InvoiceNo, AmountDue = @Due,
               AmountPaid = @Paid, ChangeGiven = CAST(NULL AS DECIMAL(18,3)),
               PaymentStatus = CAST(NULL AS VARCHAR(10)), ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT   Message       = 'Success'
           , InvoiceNo     = @InvoiceNo
           , AmountDue     = @Total
           , AmountPaid    = @Paid
           , ChangeGiven   = @Change
           , PaymentStatus = CASE WHEN @Paid <= 0 THEN 'Unpaid'
                                  WHEN @Paid + 0.001 >= @Total THEN 'Paid' ELSE 'Partial' END
           , ErrorMessage  = CAST(NULL AS NVARCHAR(500));
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_TransferOrder]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_TransferOrder]
      @InvoiceNo   BIGINT
    , @ToBranchID  INT
    , @Reason      NVARCHAR(500) = NULL
    , @UserID      INT           = NULL
    , @UserName    NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME = GETDATE()
          , @FromBranch INT, @Status INT, @AreaID INT
          , @Err NVARCHAR(500) = NULL, @Warning NVARCHAR(500) = NULL;

    SELECT @FromBranch = i.BranchID, @Status = i.OrderStatusID, @AreaID = ca.AreaID
    FROM      dbo.tblInvoice i
    LEFT JOIN dbo.tblCustomerAddress ca ON ca.AddressID = i.AddressID
    WHERE     i.InvoiceNo = @InvoiceNo;

    IF @FromBranch IS NULL
        SET @Err = N'Order not found.';
    ELSE IF @Status IN (6, 7, 8)
        SET @Err = N'A completed, cancelled or refunded order cannot be transferred.';
    ELSE IF @Status IN (4, 5)
        -- Once a driver has the food, moving the order to another branch means
        -- the branch that will actually deliver it is not the one on record.
        SET @Err = N'Order is already with a driver - recall it first.';
    ELSE IF @ToBranchID = @FromBranch
        SET @Err = N'Order is already at that branch.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblbranch WHERE id = @ToBranchID AND ISNULL(IsDeleted,0) = 0 AND ISNULL(IsActive,1) = 1)
        SET @Err = N'Target branch is invalid or inactive.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message='Fail', InvoiceNo=@InvoiceNo, ErrorMessage=@Err, Warning=CAST(NULL AS NVARCHAR(500));
        RETURN;
    END

    -- Coverage is advisory, not blocking: a manager moving an order to a branch
    -- that is not mapped usually knows something the mapping does not.
    IF @AreaID IS NOT NULL
       AND EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID)
       AND NOT EXISTS (SELECT 1 FROM dbo.TblArea_Mapping WHERE AreaID = @AreaID AND BranchID = @ToBranchID)
        SET @Warning = N'Target branch is not mapped to this delivery area.';

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.tblInvoice
           SET BranchID   = @ToBranchID
             , ModifiedOn = @Now
             , ModifiedBy = @UserID
         WHERE InvoiceNo = @InvoiceNo;

        -- Line rows carry BranchID too; leaving them behind would make every
        -- branch-level item report disagree with the header.
        UPDATE dbo.tblOrder SET BranchID = @ToBranchID WHERE InvoiceNo = @InvoiceNo;

        INSERT INTO dbo.tblPOS_OrderTransfer (InvoiceNo, FromBranchID, ToBranchID, Reason, TransferredBy, TransferredOn)
        VALUES (@InvoiceNo, @FromBranch, @ToBranchID, @Reason, @UserID, @Now);

        INSERT INTO dbo.tblPOS_OrderStatusHistory (InvoiceNo, FromStatusID, ToStatusID, ChangedBy, ChangedByName, ChangedOn, Comments)
        VALUES (@InvoiceNo, @Status, @Status, @UserID, @UserName, @Now,
                CONCAT(N'Transferred from branch ', @FromBranch, N' to ', @ToBranchID,
                       CASE WHEN @Reason IS NULL THEN N'' ELSE N': ' + @Reason END));

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('Invoice', @InvoiceNo, 'Transfer', @UserID, @UserName,
                CONCAT(N'From=', @FromBranch, N' To=', @ToBranchID, N' Reason=', ISNULL(@Reason, N'')));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message='Fail', InvoiceNo=@InvoiceNo, ErrorMessage=ERROR_MESSAGE(), Warning=CAST(NULL AS NVARCHAR(500));
        RETURN;
    END CATCH

    SELECT Message='Success', InvoiceNo=@InvoiceNo, ErrorMessage=CAST(NULL AS NVARCHAR(500)), Warning=@Warning;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_POS_User_ChangeRole]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_User_ChangeRole]
      @UserID         INT
    , @RoleID         INT
    , @ActorUserID    INT           = NULL
    , @ActorUserName  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Err NVARCHAR(500) = NULL, @OldRoleID INT;

    SELECT @OldRoleID = RoleID FROM dbo.tblUser WHERE ID = @UserID;

    IF @OldRoleID IS NULL
        SET @Err = N'User not found.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @RoleID)
        SET @Err = N'Unknown role.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @OldRoleID AND CanManageMasters = 1)
        AND NOT EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @RoleID AND CanManageMasters = 1)
        AND (SELECT COUNT(*) FROM dbo.tblUser u3
             JOIN dbo.tblPOS_Role_Master r3 ON r3.RoleID = u3.RoleID
             WHERE r3.CanManageMasters = 1) <= 1
        SET @Err = N'This is the only user who can manage Settings/User Management - assign another user that role first.';

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', UserID = @UserID, ErrorMessage = @Err;
        RETURN;
    END

    BEGIN TRY
        UPDATE dbo.tblUser SET RoleID = @RoleID WHERE ID = @UserID;

        INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
        VALUES ('User', @UserID, 'ChangeRole', @ActorUserID, @ActorUserName,
                CONCAT(N'RoleID ', ISNULL(@OldRoleID,0), N'->', @RoleID));
    END TRY
    BEGIN CATCH
        SELECT Message = 'Fail', UserID = @UserID, ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', UserID = @UserID, RoleID = @RoleID, ErrorMessage = CAST(NULL AS NVARCHAR(500));
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_User_List]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_User_List]
AS
BEGIN
    SET NOCOUNT ON;

    -- result set 0: the grid, unchanged
    SELECT
          u.ID
        , u.NAME
        , u.USERNAME
        , BranchID          = TRY_CAST(u.BrandID AS INT)
        , BranchName        = b.branchName
        , u.RoleID
        , RoleName          = ISNULL(r.RoleName, N'(no role)')
        , CanManageMasters  = ISNULL(r.CanManageMasters, 0)
        , HasHashedPassword = CASE WHEN u.PasswordHash IS NOT NULL THEN 1 ELSE 0 END
    FROM      dbo.tblUser u
    LEFT JOIN dbo.tblPOS_Role_Master r ON r.RoleID = u.RoleID
    LEFT JOIN dbo.tblbranch          b ON b.id     = TRY_CAST(u.BrandID AS INT)
    ORDER BY  u.NAME;

    -- result set 1: every user's assigned branches (Order List / Dashboard
    -- access) - a different thing from BrandID above, which is unrelated.
    SELECT
          m.UserID
        , m.BranchID
        , BranchName = ISNULL(ab.branchName, N'?')
    FROM      dbo.tblPOS_UserBranch_Map m
    LEFT JOIN dbo.tblbranch ab ON ab.id = m.BranchID
    ORDER BY  m.UserID, ab.branchName;
END
GO
/****** Object:  StoredProcedure [dbo].[sp_POS_User_Save]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_POS_User_Save]
      @UserID         INT           = NULL
    , @Name           NVARCHAR(100)
    , @Username       NVARCHAR(50)
    , @NewPassword    NVARCHAR(50)  = NULL
    , @BranchID       INT           = NULL
    , @RoleID         INT
    , @BranchIDs      NVARCHAR(1000) = NULL   -- CSV of dbo.tblbranch.id - Order List / Dashboard access
    , @ActorUserID    INT           = NULL
    , @ActorUserName  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Name     = NULLIF(LTRIM(RTRIM(ISNULL(@Name, N''))), N'');
    SET @Username = NULLIF(LTRIM(RTRIM(ISNULL(@Username, N''))), N'');
    SET @NewPassword = NULLIF(LTRIM(RTRIM(ISNULL(@NewPassword, N''))), N'');
    IF @UserID IS NOT NULL AND @UserID <= 0 SET @UserID = NULL;

    DECLARE @IsInsert BIT = CASE WHEN @UserID IS NULL THEN 1 ELSE 0 END;
    DECLARE @Err NVARCHAR(500) = NULL;
    DECLARE @OldRoleID INT;

    /*---- validation, in the order the admin would hit it ------------------*/
    IF @Name IS NULL
        SET @Err = N'Name is required.';
    ELSE IF @Username IS NULL
        SET @Err = N'Username is required.';
    ELSE IF @IsInsert = 1 AND @NewPassword IS NULL
        SET @Err = N'A password is required for a new user.';
    ELSE IF NOT EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @RoleID)
        SET @Err = N'Unknown role.';
    ELSE IF EXISTS (SELECT 1 FROM dbo.tblUser WHERE USERNAME = @Username AND ISNULL(ID,0) <> ISNULL(@UserID,0))
        SET @Err = N'That username is already in use.';
    ELSE IF @IsInsert = 0 AND NOT EXISTS (SELECT 1 FROM dbo.tblUser WHERE ID = @UserID)
        SET @Err = N'User not found.';

    IF @Err IS NULL AND @IsInsert = 0
    BEGIN
        SELECT @OldRoleID = RoleID FROM dbo.tblUser WHERE ID = @UserID;

        -- Would this update take the CanManageMasters permission away from
        -- the only user who currently has it?
        IF EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @OldRoleID AND CanManageMasters = 1)
           AND NOT EXISTS (SELECT 1 FROM dbo.tblPOS_Role_Master WHERE RoleID = @RoleID AND CanManageMasters = 1)
           AND (SELECT COUNT(*) FROM dbo.tblUser u3
                JOIN dbo.tblPOS_Role_Master r3 ON r3.RoleID = u3.RoleID
                WHERE r3.CanManageMasters = 1) <= 1
            SET @Err = N'This is the only user who can manage Settings/User Management - assign another user that role first.';
    END

    IF @Err IS NOT NULL
    BEGIN
        SELECT Message = 'Fail', UserID = @UserID, ErrorMessage = @Err;
        RETURN;
    END

    DECLARE @Salt VARBINARY(32), @Hash VARBINARY(64);
    IF @NewPassword IS NOT NULL
    BEGIN
        SET @Salt = CRYPT_GEN_RANDOM(16);
        SET @Hash = HASHBYTES('SHA2_512', @Salt + CONVERT(VARBINARY(200), @NewPassword));
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @IsInsert = 1
        BEGIN
            INSERT INTO dbo.tblUser (NAME, USERNAME, PASSWORD, PasswordHash, PasswordSalt, BrandID, RoleID)
            VALUES (@Name, @Username, N'', @Hash, @Salt, @BranchID, @RoleID);

            SET @UserID = SCOPE_IDENTITY();

            INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
            VALUES ('User', @UserID, 'Create', @ActorUserID, @ActorUserName,
                    CONCAT(N'Username=', @Username, N' RoleID=', @RoleID));
        END
        ELSE
        BEGIN
            -- BrandID is deliberately NOT touched here - it is a separate,
            -- chain-level field (see sp_POS_GetLookups) that User Management
            -- does not manage. It is only ever set on INSERT, above, and is
            -- left exactly as it was on every UPDATE.
            IF @NewPassword IS NOT NULL
            BEGIN
                UPDATE dbo.tblUser
                   SET NAME          = @Name
                     , USERNAME      = @Username
                     , RoleID        = @RoleID
                     , PasswordHash  = @Hash
                     , PasswordSalt  = @Salt
                     , PASSWORD      = N''
                 WHERE ID = @UserID;
            END
            ELSE
            BEGIN
                UPDATE dbo.tblUser
                   SET NAME          = @Name
                     , USERNAME      = @Username
                     , RoleID        = @RoleID
                 WHERE ID = @UserID;
            END

            INSERT INTO dbo.tblPOS_AuditLog (EntityType, EntityID, Action, UserID, UserName, Details)
            VALUES ('User', @UserID, 'Update', @ActorUserID, @ActorUserName,
                    CONCAT(N'Username=', @Username,
                           N' RoleID ', ISNULL(@OldRoleID,0), N'->', @RoleID,
                           CASE WHEN @NewPassword IS NOT NULL THEN N' PasswordChanged' ELSE N'' END));
        END

        -- Order List / Dashboard branch access - always replaced with the
        -- complete set submitted, per the comment above the parameter list.
        DELETE FROM dbo.tblPOS_UserBranch_Map WHERE UserID = @UserID;

        INSERT INTO dbo.tblPOS_UserBranch_Map (UserID, BranchID)
        SELECT DISTINCT @UserID, TRY_CAST(value AS INT)
        FROM   STRING_SPLIT(ISNULL(@BranchIDs, N''), ',')
        WHERE  TRY_CAST(value AS INT) IS NOT NULL;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT Message = 'Fail', UserID = @UserID, ErrorMessage = ERROR_MESSAGE();
        RETURN;
    END CATCH

    SELECT Message = 'Success', UserID = @UserID, ErrorMessage = CAST(NULL AS NVARCHAR(500));
END
GO
/****** Object:  StoredProcedure [dbo].[sp_PostFeedbackData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
/****** Object:  StoredProcedure [dbo].[sp_SaveMenuColors]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_SaveMenuColors]
    @BrandId  INT,
    @BranchId INT = 0,
    @header_background_color                         NVARCHAR(50) = NULL,
    @header_icon_color                               NVARCHAR(50) = NULL,
    @scroll_header_background_color                  NVARCHAR(50) = NULL,
    @scroll_header_icon_color                        NVARCHAR(50) = NULL,
    @fixd_item_list_title_background_color           NVARCHAR(50) = NULL,
    @fixd_item_list_title_text_color                 NVARCHAR(50) = NULL,
    @category_page_background_color                  NVARCHAR(50) = NULL,
    @category_page_card_primary_background_color     NVARCHAR(50) = NULL,
    @category_page_categoryname_color                NVARCHAR(50) = NULL,
    @item_page_background_color                      NVARCHAR(50) = NULL,
    @item_page_category_title_bg_color               NVARCHAR(50) = NULL,
    @item_page_category_title_font_color             NVARCHAR(50) = NULL,
    @item_page_item_background_color                 NVARCHAR(50) = NULL,
    @item_page_itemname_color                        NVARCHAR(50) = NULL,
    @item_page_price_color                           NVARCHAR(50) = NULL,
    @item_page_plus_button_color                     NVARCHAR(50) = NULL,
    @item_page_plus_button_icon_color                NVARCHAR(50) = NULL,
    @product_details_title_bg_color                  NVARCHAR(50) = NULL,
    @product_details_title_font_color                NVARCHAR(50) = NULL,
    @product_details_background_color                NVARCHAR(50) = NULL,
    @product_name                                    NVARCHAR(50) = NULL,
    @product_details_text                            NVARCHAR(50) = NULL,
    @product_details_price                           NVARCHAR(50) = NULL,
    @product_details_price_text                      NVARCHAR(50) = NULL,
    @product_details_price_background_color          NVARCHAR(50) = NULL,
    @product_details_plus_button_color               NVARCHAR(50) = NULL,
    @product_details_plus_button_icon_color          NVARCHAR(50) = NULL,
    @category_carousel_background_color              NVARCHAR(50) = NULL,
    @Item_details_price_background_color             NVARCHAR(50) = NULL,
    @item_details_price_text                         NVARCHAR(50) = NULL,
    @item_details_price_total_price_background_color  NVARCHAR(50) = NULL,
    @item_details_price_total_price_text             NVARCHAR(50) = NULL,
    @item_details_extra_price_text_color            NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    
        UPDATE dbo.tbl_Menu_Colors SET
            header_background_color                         = @header_background_color,
            header_icon_color                               = @header_icon_color,
            scroll_header_background_color                  = @scroll_header_background_color,
            scroll_header_icon_color                        = @scroll_header_icon_color,
            fixd_item_list_title_background_color           = @fixd_item_list_title_background_color,
            fixd_item_list_title_text_color                 = @fixd_item_list_title_text_color,
            category_page_background_color                  = @category_page_background_color,
            category_page_card_primary_background_color     = @category_page_card_primary_background_color,
            category_page_categoryname_color                = @category_page_categoryname_color,
            item_page_background_color                      = @item_page_background_color,
            item_page_category_title_bg_color               = @item_page_category_title_bg_color,
            item_page_category_title_font_color             = @item_page_category_title_font_color,
            item_page_item_background_color                 = @item_page_item_background_color,
            item_page_itemname_color                        = @item_page_itemname_color,
            item_page_price_color                           = @item_page_price_color,
            item_page_plus_button_color                     = @item_page_plus_button_color,
            item_page_plus_button_icon_color                = @item_page_plus_button_icon_color,
            product_details_title_bg_color                  = @product_details_title_bg_color,
            product_details_title_font_color                = @product_details_title_font_color,
            product_details_background_color                = @product_details_background_color,
            product_name                                    = @product_name,
            product_details_text                            = @product_details_text,
            product_details_price                           = @product_details_price,
            product_details_price_text                      = @product_details_price_text,
            product_details_price_background_color          = @product_details_price_background_color,
            product_details_plus_button_color               = @product_details_plus_button_color,
            product_details_plus_button_icon_color          = @product_details_plus_button_icon_color,
            category_carousel_background_color              = @category_carousel_background_color,
            Item_details_price_background_color             = @Item_details_price_background_color,
            item_details_price_text                         = @item_details_price_text,
            item_details_price_total_price_background_color  = @item_details_price_total_price_background_color,
            item_details_price_total_price_text             = @item_details_price_total_price_text,
            item_details_extra_price_text_color            = @item_details_extra_price_text_color
        --WHERE BrandId = @BrandId AND BranchId = @BranchId;
    

    SELECT 'Success' AS Result;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_SaveMenuTheme]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_SaveMenuTheme]
    @BrandId  INT,
    @BranchId INT = 0,
    @Items    dbo.MenuThemeTVP READONLY
AS
BEGIN
    SET NOCOUNT ON;

    -- update the fields that already have a row for THIS brand/branch
    UPDATE  t
    SET     t.Color = s.Color
    FROM    dbo.tblMenuTheme t
    INNER JOIN @Items s
        ON  t.Name = s.Name
    WHERE   t.BrandID = @BrandId
      AND   t.BranchID = @BranchId;

    -- insert the fields that don't have a row yet for THIS brand/branch
    -- (first time this field is ever saved - e.g. the new popup_* fields)
    INSERT INTO dbo.tblMenuTheme (Name, Color, BrandID, BranchID)
    SELECT  s.Name, s.Color, @BrandId, @BranchId
    FROM    @Items s
    WHERE   NOT EXISTS (
                SELECT 1 FROM dbo.tblMenuTheme t
                WHERE  t.BrandID = @BrandId
                  AND  t.BranchID = @BranchId
                  AND  t.Name = s.Name
            );

    -- The theme editor only ever writes brand-level rows (@BranchId = 0), but
    -- sp_GetMenuTheme PREFERS branch-specific rows. A leftover BranchID <> 0
    -- row would shadow a brand-level edit, so once a field is saved at brand
    -- level, drop any branch-specific copies of it for this brand.
    IF @BranchId = 0
        DELETE  t
        FROM    dbo.tblMenuTheme t
        INNER JOIN @Items s
            ON  t.Name = s.Name
        WHERE   t.BrandID = @BrandId
          AND   t.BranchID <> 0;

    -- bump the single version row (its Color holds the number)
    UPDATE  dbo.tblMenuTheme
    SET     Color = CAST(ISNULL(TRY_CONVERT(INT, Color), 0) + 1 AS NVARCHAR(50))
    WHERE   Name = 'Version';
END

GO
/****** Object:  StoredProcedure [dbo].[sp_SaveTabTheme]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_SaveTabTheme]
    @ThemeID             INT,
    @ThemeName           NVARCHAR(255),
    -- images (file names saved in ~/images)
    @CategoryActive      NVARCHAR(255),
    @CategoryInActive    NVARCHAR(255),
    @Setting             NVARCHAR(255),
    @SeperatorLine       NVARCHAR(255),
    @HomeScreen          NVARCHAR(255),
    @PopUpBackground     NVARCHAR(255),
    -- colours
    @EnglishButton       NVARCHAR(50),
    @ArabicButton        NVARCHAR(50),
    @MandarinButton      NVARCHAR(50),
    @RussianButton       NVARCHAR(50),
    @CloseButton         NVARCHAR(50),
    @LeftArrow           NVARCHAR(50),
    @LeftBottom          NVARCHAR(50),
    @LeftTop             NVARCHAR(50),
    @RightArrow          NVARCHAR(50),
    @RightButton         NVARCHAR(50),
    @RightTop            NVARCHAR(50),
    @FontColor           NVARCHAR(50),
    @FontColorItemName   NVARCHAR(50),
    @FontColorIngName    NVARCHAR(50),
    @FontColorPrice      NVARCHAR(50),
    @ItemBackgroundColor NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.tblTheme
    SET ThemeName           = @ThemeName,
        CategoryActive      = @CategoryActive,
        CategoryInActive    = @CategoryInActive,
        Setting             = @Setting,
        SeperatorLine       = @SeperatorLine,
        HomeScreen          = @HomeScreen,
        PopUpBackground     = @PopUpBackground,
        EnglishButton       = @EnglishButton,
        ArabicButton        = @ArabicButton,
        MandarinButton      = @MandarinButton,
        RussianButton       = @RussianButton,
        CloseButton         = @CloseButton,
        LeftArrow           = @LeftArrow,
        LeftBottom          = @LeftBottom,
        LeftTop             = @LeftTop,
        RightArrow          = @RightArrow,
        RightButton         = @RightButton,
        RightTop            = @RightTop,
        FontColor           = @FontColor,
        FontColorItemName   = @FontColorItemName,
        FontColorIngName    = @FontColorIngName,
        FontColorPrice      = @FontColorPrice,
        ItemBackgroundColor = @ItemBackgroundColor
    WHERE ThemeID = @ThemeID;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_SetArrived]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_SetArrived]
@Reservationid int=0
AS
BEGIN
	update tblreservation set Status=2 where id=@Reservationid
END


--GO
--/****** Object:  StoredProcedure [dbo].[sp_GetAvailability]    Script Date: 18-10-2020 22:28:21 ******/
--SET ANSI_NULLS ON
--GO
--SET QUOTED_IDENTIFIER ON
--GO
--ALTER PROCEDURE [dbo].[sp_GetAvailability]
--@guestCnt int=0,
--@reservationDate datetime=null
--AS
--BEGIN
--	;with cte as(
--	select rss.id,rss.slotName,rss.slotNameArabic,rss.fromTime,rss.toTime,guestLimit
--	,(select isnull((rss.guestLimit-sum(rs.noofguest)),rss.guestLimit) from tblreservation rs 
--	where rs.sloteId=rss.id and cast(rs.reservationDate as date) = cast(@reservationDate as date)) as AvailableGuest
--	from tblReservationSlot rss 

--	where CONVERT(DATETIME, CONVERT(varchar(20), cast( @reservationDate as date) ,101)  + ' ' + CONVERT(varchar(8), rss.fromTime, 108)) > GETDATE()   
--	)
--	select * from cte where AvailableGuest >= @guestCnt
--END


GO
/****** Object:  StoredProcedure [dbo].[sp_SubmitReservationData]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_SubmitReservationData]
@branchid int=0,
@slotId int=0,
@reservationDate datetime=null,
@customerName nvarchar(200)=null,
@customerMobile nvarchar(40)=null,
@customerEmail nvarchar(200)=null,
@comments nvarchar(500)=null,
@TableSeatingCount int=0,
@DiningArea nvarchar(50)=null

AS
BEGIN
	--get available tablestructureid
	declare @tableStructureID int=0
	declare @meargedTableid int =0
		set @tableStructureID=isnull((select top 1 Id from tblReservationTableStructure where Seating=@TableSeatingCount 
							and id not in(
							select rs.TableStructureID from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=@TableSeatingCount and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							union all
							select isnull(rs.meargedTableid,0) from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=@TableSeatingCount and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							
							) and Seating=@TableSeatingCount and DiningArea=@DiningArea),0)

	---------------start for check if seatingcount selected 4 and all 4 seater tabled booked then mearge 2 seater two tables --------------------
	if @TableSeatingCount =4 and @tableStructureID=0
	begin
		select Id INTO #TempTable from tblReservationTableStructure where Seating=2 
		and id not in(
			select rs.TableStructureID from tblReservation rs where TableStructureID in (
			select id from tblReservationTableStructure tblstruc where tblstruc.Seating=2 and tblstruc.DiningArea=@DiningArea
			) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
			union all
			select isnull(rs.meargedTableid,0) from tblReservation rs where TableStructureID in (
			select id from tblReservationTableStructure tblstruc where tblstruc.Seating=2 and tblstruc.DiningArea=@DiningArea
			) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
		)  and DiningArea=@DiningArea

		;with cte as
		(
			select *
			, ROW_NUMBER() over (order by Id) as rn
			from #TempTable
		) 
		select @tableStructureID=id from cte where rn = 1

		;with cte as
		(
			select *
			, ROW_NUMBER() over (order by Id) as rn
			from #TempTable
		) 
		select @meargedTableid=id from cte where rn = 2

		drop table #TempTable

		--check if meargedtable not found then set main tablestructuredid is 0 and not submit data
		if isnull(@meargedTableid,0) = 0
		begin 
			set @tableStructureID=0
		end
	end
	---------------End for check if seatingcount selected 4 and all 4 seater tabled booked then mearge 2 seater two tables --------------------

	---------------start for check if seatingcount selected 6 and check one 4 seater and one 2 seater table available or not --------------------
	if @TableSeatingCount =6 
	begin
		set @tableStructureID =(select  top 1 Id  from tblReservationTableStructure where Seating=4 
							and id not in(
							select rs.TableStructureID from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							union all
							select isnull(rs.meargedTableid,0) from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							)  and DiningArea=@DiningArea) 


		set @meargedTableid =(select  top 1 Id  from tblReservationTableStructure where Seating=2 
							and id not in(
							select rs.TableStructureID from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=2 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							union all
							select isnull(rs.meargedTableid,0) from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=2 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							)  and DiningArea=@DiningArea and id!=@tableStructureID) 

		--check if meargedtable not found then set main tablestructuredid is 0 and not submit data
		if isnull(@meargedTableid,0) = 0
		begin 
			set @tableStructureID=0
		end
	end
	---------------start for check if seatingcount selected 6 and check one 4 seater and one 2 seater table available or not --------------------

	---------------start for check if seatingcount selected 8 and check one 4 seater and one 4 seater table available or not --------------------
	if @TableSeatingCount =8 
	begin
		set @tableStructureID =(select  top 1 Id  from tblReservationTableStructure where Seating=4 
							and id not in(
							select rs.TableStructureID from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							union all
							select isnull(rs.meargedTableid,0) from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							)  and DiningArea=@DiningArea) 


		set @meargedTableid =(select  top 1 Id  from tblReservationTableStructure where Seating=4 
							and id not in(
							select rs.TableStructureID from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							union all
							select isnull(rs.meargedTableid,0) from tblReservation rs where TableStructureID in (
							select id from tblReservationTableStructure tblstruc where tblstruc.Seating=4 and tblstruc.DiningArea=@DiningArea
							) and rs.sloteId=@slotId and cast(rs.reservationDate as date) = cast(@reservationDate as date)
							)  and DiningArea=@DiningArea and id!=@tableStructureID) 

		--check if meargedtable not found then set main tablestructuredid is 0 and not submit data
		if isnull(@meargedTableid,0) = 0
		begin 
			set @tableStructureID=0
		end
	end
	---------------start for check if seatingcount selected 8 and check one 4 seater and one 4 seater table available or not --------------------

if @tableStructureID > 0
begin
	insert into tblreservation(
	branchId,
	sloteId,
	reservationDate,
	customerName,
	customerMobile,
	customerEmail,
	comments,
	tableStructureID,
	meargedTableid,
	--confirmationId,
	Status,
	TransactionDate)

	values(@branchid,@slotId,@reservationDate,@customerName,@customerMobile,@customerEmail,@comments,@tableStructureID,@meargedTableid,1,getdate())

	declare @id int= @@identity;

	update tblreservation 
	set confirmationId= cast(id as nvarchar(10)) +'-' + 
	cast(branchId as nvarchar(10)) + '-' + 
	cast(sloteId as nvarchar(10)) + '-' + 
	cast(@tableStructureID as nvarchar(10)) where id =@id

	select  res.id,branchId,
	sloteId,
	FORMAT (reservationDate, 'dd MMM yyyy') as reservationDate,
	customerName,
	customerMobile,
	customerEmail,
	comments,
	tableStructureID,
	rts.TableName,
	confirmationId,
	TransactionDate,
	rss.slotName as slotName,
	rss.slotNameArabic as slotNameArabic,
	b.branchName,
	meargedTableid
	
	from tblreservation res
	inner join tblReservationSlot rss on res.sloteId=rss.id
	inner join tblbranch b on b.id= res.branchId
	inner join tblReservationTableStructure rts on rts.Id=res.TableStructureID
	
	where res.id=@id
end
else
begin
	select 'Table not Available Please Try again' as Error
end

END

GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateAuditDetails]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_UpdateAuditDetails]
	-- Add the parameters for the stored procedure here
	@IPAddress nVarchar(50) = '',
	@BrowserName nVarchar(100) = '',
	@DeviceModal nVarchar(50) = '',
	@DeviceManufacturer nVarchar(50) = '',
	
	@ItemSelectionType Int = '',
	@ItemSelectionID Int = '',
	@ItemSelectionName nVarchar(50) = '',
	@BranchId int =0

AS
BEGIN
	SET NOCOUNT ON;
	
	--Exec [sp_UpdateAuditDetails] @IP, @BrowserName, @DeviceModal, @DeviceManufacturer, 2, @CAT_NUM, @Cat_Name

	Declare @AuditID Int = 0
	Select @AuditID = IsNull(ID, 0) From tblAudit Where IPAddress = @IPAddress and BranchId =@BranchId

	IF @AuditID = 0 or @ItemSelectionType =1
	Begin
		Insert Into tblAudit (IPAddress, BrowserName, DeviceModal, DeviceManufacturer,CreatedOn,BranchId) 
		Values (@IPAddress, @BrowserName, 
			CASE @DeviceModal WHEN 'Unknown' THEN 'Computer' ELSE @DeviceModal END, 
			CASE @DeviceManufacturer WHEN 'Unknown' THEN 'Computer' ELSE @DeviceManufacturer END,
			Getdate(),@BranchId)
		
		Set @AuditID = SCOPE_IDENTITY()
	End

	--ItemSelectionType  = Branch Selection as 1 and Category as 2 and Item Selection as 3
    Insert Into tblAuditDetails(AuditID, ItemSelectionType, ItemSelectionID, ItemSelectionName,CreatedOn,BranchId) 
	Values (@AuditID, @ItemSelectionType, @ItemSelectionID, @ItemSelectionName,Getdate(),@BranchId)

END
GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateBranch]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create PROCEDURE [dbo].[sp_UpdateBranch]
@BranchId int,
@BrandID int,
@branchName nvarchar(500)='',
@branchNameAra nvarchar(500)=''
AS
BEGIN
	update tblbranch set BrandID=@BrandID,branchName=@branchName, branchNameAra=@branchNameAra where id=@BranchId
END

GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateBranchSequence]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_UpdateBranchSequence]
@BranchId int=0,
@SortingType varchar(50)
AS
BEGIN
	update tblbranch set SEQ_NUM=id where SEQ_NUM is null
	declare @oldSeq int=0,
	@Seq_Num int=0,
	@max_SeqNum int=0
	set @oldSeq =isnull((select top 1 Seq_Num from tblbranch where id =@BranchId),1)
	select @max_SeqNum=count(1) from tblbranch
	
	if @SortingType ='down' and @oldSeq != @max_SeqNum
	begin
		update tblbranch set Seq_Num=Seq_Num -1 where id in (
		select top 1 id from tblbranch where Seq_Num >=@oldSeq and id !=@BranchId order by Seq_Num) 

		update tblbranch set Seq_Num=@oldSeq+1 where id =@BranchId
	end

	if @SortingType ='up' and @oldSeq != 1
	begin
		update tblbranch set Seq_Num=isnull(Seq_Num,0) +1 where id in (
		select top 1 id from tblbranch where Seq_Num <=@oldSeq and id !=@BranchId order by Seq_Num desc) 

		update tblbranch set Seq_Num=@oldSeq-1 where id =@BranchId
	end

	select 'Success' Status
END
GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateBranchStatus]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_UpdateBranchStatus]
@BranchId int,
@IsActive int
AS
BEGIN
	update tblbranch set isactive=@isactive  where id=@BranchId
	select 'Success' Status
END


GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateBrand]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_UpdateBrand]

@BrandID int,
@BrandName nvarchar(500)='',
@BrandNameAr nvarchar(500)='',
@BrandSeq int,
@Russian int,
@Mandarin int,
@ThemeID int,
@BrandLogo nvarchar(500)='',
@IsOtherLanguages int =0,
@Brandurl nvarchar(2000)=''
AS
BEGIN
 
update tblBrand set BrandName=@BrandName, BrandNameAra=@BrandNameAr,BrandSeq=@BrandSeq ,
Russian=@Russian,Mandarin=@Mandarin,Theme=@ThemeID,BrandImage=@BrandLogo,IsOtherLanguages=@IsOtherLanguages,url=@Brandurl where BrandID=@BrandID

END

GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateBrandImage]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_UpdateBrandImage]
    @BrandId  INT,
    @Type     NVARCHAR(20),
    @FileName NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Type = 'desktop'
        UPDATE dbo.tblbrand SET DesktopImage = @FileName WHERE BrandID = @BrandId;
    ELSE
        UPDATE dbo.tblbrand SET BannerImage = @FileName, MobileImage = @FileName WHERE BrandID = @BrandId;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateBrandLayout]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_UpdateBrandLayout]
    @BrandId INT,
    @Layout  NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.tblbrand
    SET    Layout = @Layout
    WHERE  BrandID = @BrandId;
END

GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateCategoryBranchAssign]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_UpdateCategoryBranchAssign]
@brandId int,
@branchId int,
@cat_num int,
@Isselected bit
AS
BEGIN
	if @Isselected = 1
	begin
		insert into Assign_Cat(BrandID,BranchId,CatNum)
		values(@brandId,@branchId,@cat_num)
	end
	else
	begin
		delete Assign_Cat where BrandID=@brandId and BranchId=@branchId and CatNum=@cat_num
	end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_updateCategorySequance]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_updateCategorySequance]
@dttblCatSeq [DT_tblCategorySeqUpdate] readonly
AS
BEGIN
	update c set c.SEQ_NUM=dt.SEQ_NUM
	from tblCategory c
	inner join @dttblCatSeq dt on dt.CAT_NUM=c.CAT_NUM
END









GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateGroupModifier]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_UpdateGroupModifier]
@ID int=0,
@GroupNameEng nvarchar(1000)='',
@GroupNameArb nvarchar(1000)='',
@Type int=0,
@MinSelect int=0,
@MaxSelect int=0,
@Brandid int=0
AS
BEGIN
	if not exists(select 1 from tblGroup_Modifier_Master where GroupNameEng=@GroupNameEng and brandid=@Brandid and id !=@ID )
	begin
		update tblGroup_Modifier_Master set GroupNameEng=@GroupNameEng,GroupNameArb=@GroupNameArb,
		Type=@Type,MinSelect=@MinSelect,MaxSelect=@MaxSelect,brandid=@Brandid where id =@ID

		select 'Success' Status
	end
	else
	begin
		select 'Already Exists' Status
	end
END

GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateGroupModifierSequence]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_UpdateGroupModifierSequence]
@ID int=0,
--@Seq_Num int=0
@SortingType varchar(50)
AS
BEGIN
	declare @oldSeq int=0,
	@Seq_Num int=0,
	@max_SeqNum int=0
	set @oldSeq =(select top 1 Seq_Num from tblGroup_Modifier_Master where id =@ID)
	select @max_SeqNum=count(1) from tblGroup_Modifier_Master
	
	if @SortingType ='down' and @oldSeq != @max_SeqNum
	begin
		update tblGroup_Modifier_Master set Seq_Num=Seq_Num -1 where id in (
		select top 1 id from tblGroup_Modifier_Master where Seq_Num >=@oldSeq and id !=@ID order by Seq_Num) 

		update tblGroup_Modifier_Master set Seq_Num=@oldSeq+1 where id =@ID
	end

	if @SortingType ='up' and @oldSeq != 1
	begin
		update tblGroup_Modifier_Master set Seq_Num=Seq_Num +1 where id in (
		select top 1 id from tblGroup_Modifier_Master where Seq_Num <=@oldSeq and id !=@ID order by Seq_Num desc) 

		update tblGroup_Modifier_Master set Seq_Num=@oldSeq-1 where id =@ID
	end

	select 'Success' Status
END

GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateItem]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_UpdateItem]
@BrandId int =0,
@ID int,
@CAT_NUM int=0,
@ITEM_NAME nvarchar(max),
@ITEM_NAME_ARABIC nvarchar(max)='',

@ITEMName_chinese nvarchar(max)='',
@ITEMName_turkish nvarchar(max)='',
@ITEMName_hindi nvarchar(max)='',
@ITEMName_korean nvarchar(max)='',
@ITEMName_spain nvarchar(max)='',
@ITEMName_bangladeshi nvarchar(max)='',
@ITEMName_srilanka nvarchar(max)='',
@ITEMName_iranian nvarchar(max)='',
@ITEMName_italian nvarchar(max)='',
@ITEMName_urdu nvarchar(max)='',
@ITEMName_philippines nvarchar(max)='',
@ITEMName_french nvarchar(max)='',
@ITEMName_germany nvarchar(max)='',

@ItemNameMan nvarchar(max)='',
@ItemNameRus nvarchar(max)='',
@PRICE decimal (18,3),
@INGREDIENT nvarchar(max)='',
@INGREDIENT_ARABIC nvarchar(max)='',

@Ingredient_chinese nvarchar(max)='',
@Ingredient_turkish nvarchar(max)='',
@Ingredient_hindi nvarchar(max)='',
@Ingredient_korean nvarchar(max)='',
@Ingredient_spain nvarchar(max)='',
@Ingredient_bangladeshi nvarchar(max)='',
@Ingredient_srilanka nvarchar(max)='',
@Ingredient_iranian nvarchar(max)='',
@Ingredient_italian nvarchar(max)='',
@Ingredient_urdu nvarchar(max)='',
@Ingredient_philippines nvarchar(max)='',
@Ingredient_french nvarchar(max)='',
@Ingredient_germany nvarchar(max)='',

@INGREDIENT_Rus nvarchar(max)='',
@INGREDIENT_Man nvarchar(max)='',
@IMAGENAME nvarchar(max)='no_image.png',
@ITEM_DESC_ENG nvarchar(max)='',
@Video nvarchar(max)='',
@ShowInTablet bit,
@Seq_num int,
@isExtra bit=0,
@ischoice bit=0

--@EXTRAID int

AS
BEGIN
--If there is change in the category then we will make that item as last sequence... else we will just update the items
declare @Old_CatNum int;

set @Old_CatNum= (select CAT_NUM from tblItems where ID=@ID)

if (@Old_CatNum=@CAT_NUM)

begin
	update tblitems set CAT_NUM=@CAT_NUM,ITEM_NAME=@ITEM_NAME,ITEM_NAME_ARABIC=@ITEM_NAME_ARABIC, Video=@Video,
	PRICE= @PRICE,INGREDIENT=@INGREDIENT,INGREDIENT_ARABIC=@INGREDIENT_ARABIC,
	IMAGENAME=case when @IMAGENAME!='no_image.png' then @IMAGENAME else @IMAGENAME end,
	ShowInTablet=@ShowInTablet,
	ITEM_DESC_ENG=@ITEM_DESC_ENG, INGREDIENT_Man=@INGREDIENT_Man,INGREDIENT_Rus=@INGREDIENT_Rus,ItemNameMan=@ItemNameMan,ItemNameRus=@ItemNameRus 
	,isExtra=@isExtra,ischoice=@ischoice
	where ID=@ID

	if exists (select 1 from tblItemsName_Languages where ItemID=@ID)
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			update tblItemsName_Languages set
			chinese=@ITEMName_chinese
			,turkish=@ITEMName_turkish
			,hindi=@ITEMName_hindi
			,korean=@ITEMName_korean
			,spain=@ITEMName_spain
			,bangladeshi=@ITEMName_bangladeshi
			,srilanka=@ITEMName_srilanka
			,iranian=@ITEMName_iranian
			,italian=@ITEMName_italian
			,urdu=@ITEMName_urdu
			,philippines=@ITEMName_philippines
			,french=@ITEMName_french
			,germany=@ITEMName_germany
			where ItemID=@ID
		end
	end
	else
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			insert into tblItemsName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
			bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
			values(@ID,@ITEMName_chinese,@ITEMName_turkish,@ITEMName_hindi,@ITEMName_korean,@ITEMName_spain,
			@ITEMName_bangladeshi,@ITEMName_srilanka,@ITEMName_iranian,@ITEMName_italian,@ITEMName_urdu,@ITEMName_philippines,@ITEMName_french,@ITEMName_germany)
		end
	
	end

	--update ingredient
	if exists (select 1 from tblIngredientName_Languages where ItemID=@ID)
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			update tblIngredientName_Languages set
			chinese=@Ingredient_chinese
			,turkish=@Ingredient_turkish
			,hindi=@Ingredient_hindi
			,korean=@Ingredient_korean
			,spain=@Ingredient_spain
			,bangladeshi=@Ingredient_bangladeshi
			,srilanka=@Ingredient_srilanka
			,iranian=@Ingredient_iranian
			,italian=@Ingredient_italian
			,urdu=@Ingredient_urdu
			,philippines=@Ingredient_philippines
			,french=@Ingredient_french
			,germany=@Ingredient_germany
			where ItemID=@ID
		end
		
	end
	else
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			insert into tblIngredientName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
			bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
			values(@ID,@Ingredient_chinese,@Ingredient_turkish,@Ingredient_hindi,@Ingredient_korean,@Ingredient_spain,
			@Ingredient_bangladeshi,@Ingredient_srilanka,@Ingredient_iranian,@Ingredient_italian,@Ingredient_urdu,@Ingredient_philippines,@Ingredient_french,@Ingredient_germany)
		end
		
	end
end
else
begin

	set @Seq_num = isnull((select max(Seq_Num) from tblItems where CAT_NUM=@CAT_NUM) ,0)+1

	update tblitems set CAT_NUM=@CAT_NUM, Video=@Video,
	PRICE= @PRICE,INGREDIENT=@INGREDIENT,INGREDIENT_ARABIC=@INGREDIENT_ARABIC,
	IMAGENAME=case when @IMAGENAME!='no_image.png' then @IMAGENAME else @IMAGENAME end,
	ShowInTablet=@ShowInTablet,
	ITEM_DESC_ENG=@ITEM_DESC_ENG,Seq_Num=@Seq_Num, INGREDIENT_Man=@INGREDIENT_Man,INGREDIENT_Rus=@INGREDIENT_Rus,ItemNameMan=@ItemNameMan,ItemNameRus=@ItemNameRus 
	where ID=@ID

	if exists (select 1 from tblItemsName_Languages where ItemID=@ID)
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			update tblItemsName_Languages set
			chinese=@ITEMName_chinese
			,turkish=@ITEMName_turkish
			,hindi=@ITEMName_hindi
			,korean=@ITEMName_korean
			,spain=@ITEMName_spain
			,bangladeshi=@ITEMName_bangladeshi
			,srilanka=@ITEMName_srilanka
			,iranian=@ITEMName_iranian
			,italian=@ITEMName_italian
			,urdu=@ITEMName_urdu
			,philippines=@ITEMName_philippines
			,french=@ITEMName_french
			,germany=@ITEMName_germany
			where ItemID=@ID
		end
		
	end
	else
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			insert into tblItemsName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
			bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
			values(@ID,@ITEMName_chinese,@ITEMName_turkish,@ITEMName_hindi,@ITEMName_korean,@ITEMName_spain,
			@ITEMName_bangladeshi,@ITEMName_srilanka,@ITEMName_iranian,@ITEMName_italian,@ITEMName_urdu,@ITEMName_philippines,@ITEMName_french,@ITEMName_germany)
		end
		
	end

	--update ingredient
	if exists (select 1 from tblIngredientName_Languages where ItemID=@ID)
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			update tblIngredientName_Languages set
			chinese=@Ingredient_chinese
			,turkish=@Ingredient_turkish
			,hindi=@Ingredient_hindi
			,korean=@Ingredient_korean
			,spain=@Ingredient_spain
			,bangladeshi=@Ingredient_bangladeshi
			,srilanka=@Ingredient_srilanka
			,iranian=@Ingredient_iranian
			,italian=@Ingredient_italian
			,urdu=@Ingredient_urdu
			,philippines=@Ingredient_philippines
			,french=@Ingredient_french
			,germany=@Ingredient_germany
			where ItemID=@ID
		end
		
	end
	else
	begin
		if((select IsOtherLanguages from tblBrand where BrandID=@BrandID) = 1)
		begin	
			insert into tblIngredientName_Languages (ItemID,chinese,turkish,hindi,korean,spain,
			bangladeshi,srilanka,iranian,italian,urdu,philippines,french,germany)
			values(@ID,@Ingredient_chinese,@Ingredient_turkish,@Ingredient_hindi,@Ingredient_korean,@Ingredient_spain,
			@Ingredient_bangladeshi,@Ingredient_srilanka,@Ingredient_iranian,@Ingredient_italian,@Ingredient_urdu,@Ingredient_philippines,@Ingredient_french,@Ingredient_germany)
		end
		
	end
end
BEGIN
if(@ITEM_DESC_ENG = '')
	update tblItems set ITEM_DESC_ENG = @INGREDIENT where ID=@ID

end
END


GO
/****** Object:  StoredProcedure [dbo].[sp_updateItemsSequance]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_updateItemsSequance]
@dttblItemsSeq [DT_tblItemsSeqUpdate] readonly
AS
BEGIN
	update i set i.SEQ_NUM=dt.SEQ_NUM
	from tblitems i
	inner join @dttblItemsSeq dt on dt.ItemId=i.id
END

GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateOutOfStock]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_UpdateOutOfStock]

@ItemID nvarchar(max)

AS
BEGIN
 update tblItems set OutOfStock=0
 update tblItems set OutOfStock=1 where id in (select cast(item as integer) from dbo.splitstring(@ItemID,','))

END
GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateReservedTable]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
Create PROCEDURE [dbo].[sp_UpdateReservedTable]
--@reservationDate datetime='2021-01-11',
--@DiningArea nvarchar(50)='Inner Area',
--@Timeslotid int=0
@currentTableid int,
@NewTableid int,
@Reservationid int
AS
BEGIN
	declare @IsMeargeTable int=0;
	select @IsMeargeTable =case when MeargedTableid=@currentTableid then 1 else 0 end  from tblReservation where id =@Reservationid
	if @IsMeargeTable =1
	begin
		update tblReservation set MeargedTableid=@NewTableid where id =@Reservationid
	end
	else
	begin
		update tblReservation set TableStructureID=@NewTableid where id =@Reservationid
	end
END




GO
/****** Object:  StoredProcedure [dbo].[sp_updatethemes]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

create PROCEDURE [dbo].[sp_updatethemes]

@themeID int,
@englishButton nvarchar(500)='',
@homeScreen nvarchar(500)='',
@popUpBackground nvarchar(500)='',
@leftArrow nvarchar(50)='',
@leftBottom nvarchar(50)='',
@FontColor nvarchar(500)='',
@FontColorItemName nvarchar(500)='',
@itemBackgroundColor nvarchar(500)='',
@FontColorPrice nvarchar(500)='',
@FontColorIngName nvarchar(500)=''
AS
begin
 update tblTheme 
 set [HomeScreen]=@homeScreen,
 [PopUpBackground]=@popUpBackground,
  englishButton=@englishButton,
 LeftArrow=@leftArrow,
  LeftBottom=@leftBottom,
   FontColor=@FontColor,
    FontColorItemName=@FontColorItemName,
	 itemBackgroundColor=@itemBackgroundColor,
	  FontColorPrice=@FontColorPrice,
	 FontColorIngName=@FontColorIngName


 where ThemeID=@themeID
 
 
 end


GO
/****** Object:  StoredProcedure [dbo].[UpdateFeedBackLayout]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[UpdateFeedBackLayout]
@Question nvarchar (max)=''
,@TypeId int=0
,@Sequence int=0
,@BrandID int=0
,@id int=0
AS
BEGIN

update [dbo].[Feedback_Layout]
set TypeId=@TypeId,Questions=@Question,BrandID=@BrandID,Sequence=@Sequence where id=@id
END



GO
/****** Object:  StoredProcedure [dbo].[WebSlideshow_GetImages]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
CREATE PROCEDURE [dbo].[WebSlideshow_GetImages]
@brandId int=0
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	

	select * from tblWebImageSlideShow where BrandID = @brandId order by WebImageSequence 
END
GO
/****** Object:  StoredProcedure [dbo].[WebSlideShow_UpdateSequence]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

create PROCEDURE [dbo].[WebSlideShow_UpdateSequence]

@id int,

@SEQ_NUM int

AS
BEGIN
 
update tblWebImageSlideShow set WebImageSequence=@SEQ_NUM where id=@id

END



GO
/****** Object:  StoredProcedure [dbo].[WebSlideShows_Add]    Script Date: 30/10/2026 13:37:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[WebSlideShows_Add]

@ImageName nvarchar(500)=''
,@brandID int

AS
BEGIN

insert into tblWebImageSlideShow (WebImageSequence,WebSlideImageName,BrandID) values ((select isnull(max(WebImageSequence),0)+1 from tblWebImageSlideShow),@ImageName,@brandID)
END


 
GO

GO
/*------------------------------------------------------------------------------
  2. COPY DATA FROM Pistachio_v4  (identity values kept, one transaction)
------------------------------------------------------------------------------*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET XACT_ABORT ON;
GO
DECLARE @Tables TABLE (Name sysname PRIMARY KEY);
INSERT INTO @Tables (Name) VALUES
    (N'tblPOS_TableSession'),
    (N'tblInvoicePayment'),
    (N'tblInvoice'),
    (N'tblTable'),
    (N'Assign_Cat'),
    (N'Assign_Item'),
    (N'AuditTrail'),
    (N'Feedback_Customer'),
    (N'Feedback_Data'),
    (N'Feedback_Layout'),
    (N'Feedback_Type'),
    (N'tbl_Allergen'),
    (N'tbl_Allergen_Assign'),
    (N'tbl_Menu_Colors'),
    (N'tblArea'),
    (N'TblArea_Mapping'),
    (N'tblAreaMapData'),
    (N'tblAudit'),
    (N'tblAuditDetails'),
    (N'tblbranch'),
    (N'tblBrand'),
    (N'tblCategory'),
    (N'tblCategoryName_Languages'),
    (N'tblcomments'),
    (N'tblcompany'),
    (N'tblCustomer'),
    (N'tblCustomerAddress'),
    (N'tblDenomination'),
    (N'tblDenominationDetails'),
    (N'tblDiscount_Type'),
    (N'tblDiscountCode'),
    (N'tblDriver'),
    (N'tblDriverTracking'),
    (N'tblEndDay'),
    (N'tblEndDayDiscount'),
    (N'tblEndDayPayment'),
    (N'tblEndDayPaymentTypeDetails'),
    (N'tblEndshiftPaymentTypeDetails'),
    (N'tblExtra'),
    (N'tblGroup_Modifier_Details'),
    (N'tblGroup_Modifier_Master'),
    (N'tblGroup_Modifier_Sub_Details'),
    (N'tblGroup_Modifier_Type'),
    (N'tblImageSlideShow'),
    (N'tblIngredientName_Languages'),
    (N'tblInvoicePaymentType'),
    (N'tblInvoiceType_Master'),
    (N'tblInvoiceType_Master_Details'),
    (N'tblItem_Choices'),
    (N'tblItem_Extras'),
    (N'tblItemComments'),
    (N'tblItemImages'),
    (N'tblItems'),
    (N'tblItemsName_Languages'),
    (N'tblLabelName'),
    (N'tblMenuTheme'),
    (N'tblOrder'),
    (N'tblOrderStatus'),
    (N'tblPaymentVoucher'),
    (N'tblPaymentVoucherDetails'),
    (N'tblPaymentVoucherType'),
    (N'tblPOS_AuditLog'),
    (N'tblPOS_BranchSetting'),
    (N'tblPOS_CancelReason_Master'),
    (N'tblPOS_DailyCounter'),
    (N'tblPOS_GeoCache'),
    (N'tblPOS_OrderStatusHistory'),
    (N'tblPOS_OrderStatusTransition'),
    (N'tblPOS_OrderTransfer'),
    (N'tblPOS_PaymentLink'),
    (N'tblPOS_Printer'),
    (N'tblPOS_PrinterCategory'),
    (N'tblPOS_Role_Master'),
    (N'tblPOS_TableArea'),
    (N'tblPOS_UserBranch_Map'),
    (N'tblPrinter'),
    (N'tblPromotion'),
    (N'tblReservation'),
    (N'tblReservationSlot'),
    (N'tblReservationStatus'),
    (N'tblReservationTableStructure'),
    (N'tblRole'),
    (N'tblSection'),
    (N'tblSetting'),
    (N'tblTableType'),
    (N'tblTheme'),
    (N'tblUser'),
    (N'tblWebImageSlideShow');

DECLARE @name sysname, @cols nvarchar(max), @sql nvarchar(max), @hasId bit, @rows bigint;

BEGIN TRANSACTION;

/* constraints off while rows go in (order between tables does not matter) */
DECLARE cOff CURSOR LOCAL FAST_FORWARD FOR SELECT Name FROM @Tables;
OPEN cOff; FETCH NEXT FROM cOff INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'ALTER TABLE dbo.' + QUOTENAME(@name) + N' NOCHECK CONSTRAINT ALL;';
    EXEC sys.sp_executesql @sql;
    FETCH NEXT FROM cOff INTO @name;
END;
CLOSE cOff; DEALLOCATE cOff;

DECLARE cCopy CURSOR LOCAL FAST_FORWARD FOR SELECT Name FROM @Tables ORDER BY Name;
OPEN cCopy; FETCH NEXT FROM cCopy INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    /* every writable column: no computed, no rowversion */
    SELECT @cols = STRING_AGG(CONVERT(nvarchar(max), QUOTENAME(col.name)), N', ') WITHIN GROUP (ORDER BY col.column_id)
    FROM sys.columns col
    JOIN sys.types ty ON ty.user_type_id = col.user_type_id
    WHERE col.object_id = OBJECT_ID(N'dbo.' + QUOTENAME(@name))
      AND col.is_computed = 0
      AND ty.name NOT IN (N'timestamp', N'rowversion');

    SET @hasId = OBJECTPROPERTY(OBJECT_ID(N'dbo.' + QUOTENAME(@name)), 'TableHasIdentity');

    SET @sql =
          CASE WHEN @hasId = 1 THEN N'SET IDENTITY_INSERT dbo.' + QUOTENAME(@name) + N' ON; ' ELSE N'' END
        + N'INSERT INTO dbo.' + QUOTENAME(@name) + N' (' + @cols + N') '
        + N'SELECT ' + @cols + N' FROM [Pistachio_v4].dbo.' + QUOTENAME(@name) + N'; '
        + N'SET @r = @@ROWCOUNT; '
        + CASE WHEN @hasId = 1 THEN N'SET IDENTITY_INSERT dbo.' + QUOTENAME(@name) + N' OFF;' ELSE N'' END;
    EXEC sys.sp_executesql @sql, N'@r bigint OUTPUT', @r = @rows OUTPUT;
    PRINT CONCAT(N'  copied ', @rows, N' rows  dbo.', @name);

    FETCH NEXT FROM cCopy INTO @name;
END;
CLOSE cCopy; DEALLOCATE cCopy;

COMMIT TRANSACTION;
PRINT N'Data copy committed.';
SET XACT_ABORT OFF;

/* constraints back on. WITH CHECK re-validates; rows that were already orphaned in
   Pistachio_v4 make that fail - then the constraint is enabled for NEW rows only and
   listed, so you can clean the old rows later. */
DECLARE cOn CURSOR LOCAL FAST_FORWARD FOR SELECT Name FROM @Tables ORDER BY Name;
OPEN cOn; FETCH NEXT FROM cOn INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @sql = N'ALTER TABLE dbo.' + QUOTENAME(@name) + N' WITH CHECK CHECK CONSTRAINT ALL;';
        EXEC sys.sp_executesql @sql;
    END TRY
    BEGIN CATCH
        SET @sql = N'ALTER TABLE dbo.' + QUOTENAME(@name) + N' CHECK CONSTRAINT ALL;';
        EXEC sys.sp_executesql @sql;
        PRINT CONCAT(N'  WARNING dbo.', @name, N': existing rows break a constraint (', ERROR_MESSAGE(), N'). Enabled for new rows only.');
    END CATCH;
    FETCH NEXT FROM cOn INTO @name;
END;
CLOSE cOn; DEALLOCATE cOn;
GO
/*------------------------------------------------------------------------------
  3. PERMISSIONS for the HRMS application role
     (procedures, scalar functions and table types; table-valued function SELECT)
------------------------------------------------------------------------------*/
IF DATABASE_PRINCIPAL_ID(N'hrms_app_role') IS NOT NULL
BEGIN
    DECLARE @g nvarchar(max) = N'';
    SELECT @g += N'GRANT EXECUTE ON OBJECT::dbo.' + QUOTENAME(o.name) + N' TO [hrms_app_role];' + CHAR(10)
    FROM sys.objects o
    WHERE o.schema_id = SCHEMA_ID(N'dbo') AND o.type IN ('P', 'FN') AND o.is_ms_shipped = 0
      AND o.name NOT IN (N'sp_Get_DelegateRoleList', N'sp_Update_DelegateRole');
    SELECT @g += N'GRANT SELECT ON OBJECT::dbo.' + QUOTENAME(o.name) + N' TO [hrms_app_role];' + CHAR(10)
    FROM sys.objects o
    WHERE o.schema_id = SCHEMA_ID(N'dbo') AND o.type IN ('IF', 'TF');
    SELECT @g += N'GRANT EXECUTE ON TYPE::dbo.' + QUOTENAME(t.name) + N' TO [hrms_app_role];' + CHAR(10)
    FROM sys.table_types t WHERE t.schema_id = SCHEMA_ID(N'dbo');
    EXEC sys.sp_executesql @g;
    PRINT N'Permissions granted to hrms_app_role.';
END;
GO
/*------------------------------------------------------------------------------
  4. VERIFY
------------------------------------------------------------------------------*/
SELECT N'Tables'          AS Kind, 88 AS Expected, COUNT(*) AS Found FROM sys.tables      WHERE schema_id = SCHEMA_ID(N'dbo')
UNION ALL SELECT N'Procedures',  221,  COUNT(*) FROM sys.procedures  WHERE schema_id = SCHEMA_ID(N'dbo') AND name NOT IN (N'sp_Get_DelegateRoleList', N'sp_Update_DelegateRole')
UNION ALL SELECT N'Functions',   3,   COUNT(*) FROM sys.objects     WHERE schema_id = SCHEMA_ID(N'dbo') AND type IN ('FN','IF','TF')
UNION ALL SELECT N'Table types', 22,  COUNT(*) FROM sys.table_types WHERE schema_id = SCHEMA_ID(N'dbo');

DECLARE @v nvarchar(max) =
    (SELECT STRING_AGG(CONVERT(nvarchar(max),
        N'SELECT N''' + t.name + N''' AS TableName, '
      + N'(SELECT COUNT_BIG(*) FROM [Pistachio_v4].dbo.' + QUOTENAME(t.name) + N') AS SourceRows, '
      + N'(SELECT COUNT_BIG(*) FROM dbo.' + QUOTENAME(t.name) + N') AS TargetRows'), N' UNION ALL ')
     FROM sys.tables t
     WHERE t.schema_id = SCHEMA_ID(N'dbo') AND OBJECT_ID(N'[Pistachio_v4].dbo.' + QUOTENAME(t.name)) IS NOT NULL);
SET @v = N'SELECT TableName, SourceRows, TargetRows, CASE WHEN SourceRows = TargetRows THEN N''OK'' ELSE N''MISMATCH'' END AS Result FROM ('
       + @v + N') x ORDER BY CASE WHEN SourceRows = TargetRows THEN 1 ELSE 0 END, TableName;';
EXEC sys.sp_executesql @v;
PRINT N'Merge finished. Check the two result grids: every row should say OK.';
GO
SET NOEXEC OFF;
GO
