using HRMS.Data.Infrastructure;
using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Assets;
using HRMS.Domain.Organization;
using HRMS.Web.Models.Organization;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Organization Setup - one page, eight tabs, every panel loaded over AJAX.
/// <para>
/// The eight masters differ only in their entity type, so the read/write plumbing
/// lives in four private generics at the bottom of this file and each public
/// action is a dispatch table. Adding a ninth master adds one line per switch.
/// </para>
/// </summary>
[Route("organization")]
public sealed class OrganizationController : Controller
{
    private readonly ICompanyRepository _companies;
    private readonly IBranchRepository _branches;
    private readonly IDepartmentRepository _departments;
    private readonly ISectionRepository _sections;
    private readonly IDesignationRepository _designations;
    private readonly IJobPositionRepository _jobPositions;
    private readonly ILocationRepository _locations;
    private readonly ICostCenterRepository _costCenters;
    private readonly IDocumentTypeRepository _documentTypes;
    private readonly IDocumentSectionRepository _documentSections;
    private readonly IOrgDocumentTypeRepository _orgDocumentTypes;
    private readonly IIssuingAuthorityRepository _issuingAuthorities;
    private readonly IAssetTypeRepository _assetTypes;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly ILogger<OrganizationController> _logger;

    public OrganizationController(
        ICompanyRepository companies,
        IBranchRepository branches,
        IDepartmentRepository departments,
        ISectionRepository sections,
        IDesignationRepository designations,
        IJobPositionRepository jobPositions,
        ILocationRepository locations,
        ICostCenterRepository costCenters,
        IDocumentTypeRepository documentTypes,
        IDocumentSectionRepository documentSections,
        IOrgDocumentTypeRepository orgDocumentTypes,
        IIssuingAuthorityRepository issuingAuthorities,
        IAssetTypeRepository assetTypes,
        ILookupRepository lookups,
        ICurrentUser currentUser,
        ICompanyFilter companyFilter,
        ILogger<OrganizationController> logger)
    {
        _companies = companies;
        _branches = branches;
        _departments = departments;
        _sections = sections;
        _designations = designations;
        _jobPositions = jobPositions;
        _locations = locations;
        _costCenters = costCenters;
        _documentTypes = documentTypes;
        _documentSections = documentSections;
        _orgDocumentTypes = orgDocumentTypes;
        _issuingAuthorities = issuingAuthorities;
        _assetTypes = assetTypes;
        _lookups = lookups;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _logger = logger;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;

    /// <summary>Company pre-selected on a new record: the user's own, else the one picked in the top-bar filter.</summary>
    // Security > Create Roles (AccessCatalog "ORG.*")
    private bool Can(string permission) => _currentUser.HasPermission(permission);
    private bool CanView => Can("ORGANIZATION_VIEW");
    private static bool IsCompanies(string? tab) => OrganizationTabs.Resolve(tab).Key == OrganizationTabs.Companies;
    /// <summary>Add (new) or change (existing) a record of a tab; Companies also needs its own right.</summary>
    private bool CanWrite(string? tab, bool isNew) =>
        Can(isNew ? "ORGANIZATION_CREATE" : "ORGANIZATION_EDIT") && (!IsCompanies(tab) || Can("ORGANIZATION_COMPANY_EDIT"));
    private bool CanDelete(string? tab) =>
        Can("ORGANIZATION_DELETE") && (!IsCompanies(tab) || Can("ORGANIZATION_COMPANY_DELETE"));
    private IActionResult NoRight() => Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));

    private int DefaultCompanyId => _currentUser.ActiveCompanyId ?? _companyFilter.SingleCompanyId ?? 0;

    // =======================================================================
    // Shell
    // =======================================================================

    // "/" used to be mapped here; it now belongs to DashboardController (the
    // landing page). This screen lives at /organization.
    [HttpGet("")]
    [HttpGet("index")]
    public async Task<IActionResult> Index(string? tab)
    {
        if (!CanView) return Forbid();
        var model = new OrganizationIndexViewModel
        {
            ActiveTab = OrganizationTabs.Resolve(tab),
            TabCounts = await TabCountsAsync()
        };

        return View(model);
    }

    /// <summary>
    /// Every tab's record count for the tab strip, so the badges show on page load - the same
    /// scoping as its grid (active company, top-bar company filter), without search or status filter.
    /// </summary>
    private async Task<IReadOnlyDictionary<string, int>> TabCountsAsync()
    {
        var counts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        async Task Count<T>(string key, IMasterRepository<T> repository) where T : class
        {
            try
            {
                // a pinned user's companies are filtered after the list (see GridAsync), so read them all
                var pinnedCompanies = typeof(T) == typeof(Company) && _currentUser.ActiveCompanyId is not null;
                var page = await repository.ListAsync(ScopedRequest(new GridRequest { PageSize = pinnedCompanies ? int.MaxValue : 1 }), Ct);
                counts[key] = pinnedCompanies
                    ? page.Items.Count(x => _currentUser.Allows(CompanyScope.CompanyOf(x)))
                    : page.TotalCount;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // a badge is not worth failing the page for (e.g. db/63 not run yet): the tab fills it in when opened
                _logger.LogWarning(ex, "Record count for the {Tab} tab could not be read.", key);
            }
        }

        // one after the other: each is a single one-row page query
        await Count(OrganizationTabs.Companies, _companies);
        await Count(OrganizationTabs.Branches, _branches);
        await Count(OrganizationTabs.Departments, _departments);
        await Count(OrganizationTabs.Sections, _sections);
        await Count(OrganizationTabs.Designations, _designations);
        await Count(OrganizationTabs.JobPositions, _jobPositions);
        await Count(OrganizationTabs.Locations, _locations);
        await Count(OrganizationTabs.CostCenters, _costCenters);
        await Count(OrganizationTabs.DocumentTypes, _documentTypes);
        await Count(OrganizationTabs.OrgDocumentTypes, _orgDocumentTypes);
        await Count(OrganizationTabs.AssetTypes, _assetTypes);
        return counts;
    }

    /// <summary>Scopes a grid request to the user's active company and the top-bar company filter.</summary>
    private GridRequest ScopedRequest(GridRequest request)
    {
        // a pinned user's own company always wins over a CompanyId in the query string
        request.CompanyId = _currentUser.ActiveCompanyId ?? request.CompanyId;

        // Top-bar company filter (cookie). Companies tab ignores it (Core.usp_Company_Manage
        // accepts but does not apply @CompanyIds) so every company stays listed there.
        request.CompanyIds = _companyFilter.Csv;
        return request;
    }

    // =======================================================================
    // Grid - returns the table partial for one tab
    // =======================================================================

    [HttpGet("grid")]
    public Task<IActionResult> Grid(string tab, [FromQuery] GridRequest request)
    {
        if (!CanView) return Task.FromResult<IActionResult>(Forbid());
        var descriptor = OrganizationTabs.Resolve(tab);

        // Scope every grid to the user's active company once they have one.
        ScopedRequest(request);

        return descriptor.Key switch
        {
            OrganizationTabs.Companies    => GridAsync(_companies,    descriptor, request),
            OrganizationTabs.Branches     => GridAsync(_branches,     descriptor, request),
            OrganizationTabs.Departments  => GridAsync(_departments,  descriptor, request),
            OrganizationTabs.Sections     => GridAsync(_sections,     descriptor, request),
            OrganizationTabs.Designations => GridAsync(_designations, descriptor, request),
            OrganizationTabs.JobPositions => GridAsync(_jobPositions, descriptor, request),
            OrganizationTabs.Locations    => GridAsync(_locations,    descriptor, request),
            OrganizationTabs.CostCenters  => GridAsync(_costCenters,  descriptor, request),
            // every type on one page, so whole sections can be dragged into order
            OrganizationTabs.DocumentTypes => GridAsync(_documentTypes, descriptor, WholeList(request)),
            // db/99: every type on one page too, so rows can be dragged into their sequence
            OrganizationTabs.OrgDocumentTypes => GridAsync(_orgDocumentTypes, descriptor, WholeList(request)),
            // db/100: every type on one page too, so rows can be dragged into their sequence
            OrganizationTabs.AssetTypes => GridAsync(_assetTypes, descriptor, WholeList(request)),
            _ => GridAsync(_companies, OrganizationTabs.All[0], request)
        };
    }

    // =======================================================================
    // Form - returns the add/edit partial, with its dropdowns pre-loaded
    // =======================================================================

    [HttpGet("form")]
    public async Task<IActionResult> Form(string tab, long id = 0)
    {
        var descriptor = OrganizationTabs.Resolve(tab);
        var isNew = id <= 0;
        // an existing record opens read-only for a user who may only view it (Save is refused)
        if (isNew ? !CanWrite(tab, true) : !CanView) return Forbid();

        return descriptor.Key switch
        {
            OrganizationTabs.Companies => await FormAsync(
                _companies, descriptor, id,
                () => new Company(),
                [LookupType.Country, LookupType.Currency]),

            OrganizationTabs.Branches => await FormAsync(
                _branches, descriptor, id,
                () => new Branch { CompanyId = DefaultCompanyId },
                [LookupType.Company, LookupType.Governorate]),

            OrganizationTabs.Departments => await FormAsync(
                _departments, descriptor, id,
                () => new Department { CompanyId = DefaultCompanyId },
                [LookupType.Company, LookupType.Department, LookupType.CostCenter]),

            OrganizationTabs.Sections => await FormAsync(
                _sections, descriptor, id,
                () => new Section(),
                [LookupType.Company, LookupType.Department]),

            OrganizationTabs.Designations => await FormAsync(
                _designations, descriptor, id,
                () => new Designation { CompanyId = DefaultCompanyId },
                [LookupType.Company, LookupType.Grade]),

            OrganizationTabs.JobPositions => await FormAsync(
                _jobPositions, descriptor, id,
                () => new JobPosition { CompanyId = DefaultCompanyId },
                [LookupType.Company, LookupType.Grade]),

            OrganizationTabs.Locations => await FormAsync(
                _locations, descriptor, id,
                () => new Location { CompanyId = DefaultCompanyId },
                [LookupType.Company, LookupType.Branch, LookupType.Governorate]),

            OrganizationTabs.CostCenters => await FormAsync(
                _costCenters, descriptor, id,
                () => new CostCenter { CompanyId = DefaultCompanyId },
                [LookupType.Company, LookupType.CostCenter]),

            OrganizationTabs.DocumentTypes => await DocumentTypeFormAsync(descriptor, id),

            OrganizationTabs.OrgDocumentTypes => await OrgDocumentTypeFormAsync(descriptor, id),

            OrganizationTabs.AssetTypes => await FormAsync(
                _assetTypes, descriptor, id,
                () => new AssetType { AlertRules = "M1,W2,D0" },
                []),

            _ => NotFound()
        };
    }

    // =======================================================================
    // Write actions
    // =======================================================================

    [HttpPost("save")]
    public Task<IActionResult> Save(string tab) =>
        !CanWrite(tab, isNew: !PostedId(tab)) ? Task.FromResult(NoRight()) :
        OrganizationTabs.Resolve(tab).Key switch
        {
            OrganizationTabs.Companies    => SaveAsync<Company>(_companies),
            OrganizationTabs.Branches     => SaveAsync<Branch>(_branches),
            OrganizationTabs.Departments  => SaveAsync<Department>(_departments),
            OrganizationTabs.Sections     => SaveAsync<Section>(_sections),
            OrganizationTabs.Designations => SaveAsync<Designation>(_designations),
            OrganizationTabs.JobPositions => SaveAsync<JobPosition>(_jobPositions),
            OrganizationTabs.Locations    => SaveAsync<Location>(_locations),
            OrganizationTabs.CostCenters  => SaveAsync<CostCenter>(_costCenters),
            OrganizationTabs.DocumentTypes => SaveAsync<DocumentType>(_documentTypes),
            OrganizationTabs.OrgDocumentTypes => SaveAsync<OrgDocumentType>(_orgDocumentTypes),
            OrganizationTabs.AssetTypes => SaveAsync<AssetType>(_assetTypes),
            _ => Task.FromResult<IActionResult>(BadRequest())
        };

    [HttpPost("delete")]
    public Task<IActionResult> Delete(string tab, long id) =>
        !CanDelete(tab) ? Task.FromResult(NoRight()) :
        OrganizationTabs.Resolve(tab).Key switch
        {
            OrganizationTabs.Companies    => GuardedAsync(_companies, id, ct => _companies.DeleteAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.Branches     => GuardedAsync(_branches, id, ct => _branches.DeleteAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.Departments  => GuardedAsync(_departments, id, ct => _departments.DeleteAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.Sections     => GuardedAsync(_sections, id, ct => _sections.DeleteAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.Designations => GuardedAsync(_designations, id, ct => _designations.DeleteAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.JobPositions => GuardedAsync(_jobPositions, id, ct => _jobPositions.DeleteAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.Locations    => GuardedAsync(_locations, id, ct => _locations.DeleteAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.CostCenters  => GuardedAsync(_costCenters, id, ct => _costCenters.DeleteAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.DocumentTypes => GuardedAsync(_documentTypes, id, ct => _documentTypes.DeleteAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.OrgDocumentTypes => GuardedAsync(_orgDocumentTypes, id, ct => _orgDocumentTypes.DeleteAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.AssetTypes => GuardedAsync(_assetTypes, id, ct => _assetTypes.DeleteAsync(id, _currentUser.UserId, ct)),
            _ => Task.FromResult<IActionResult>(BadRequest())
        };

    [HttpPost("toggle")]
    public Task<IActionResult> Toggle(string tab, long id) =>
        !CanDelete(tab) ? Task.FromResult(NoRight()) :
        OrganizationTabs.Resolve(tab).Key switch
        {
            OrganizationTabs.Companies    => GuardedAsync(_companies, id, ct => _companies.ToggleActiveAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.Branches     => GuardedAsync(_branches, id, ct => _branches.ToggleActiveAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.Departments  => GuardedAsync(_departments, id, ct => _departments.ToggleActiveAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.Sections     => GuardedAsync(_sections, id, ct => _sections.ToggleActiveAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.Designations => GuardedAsync(_designations, id, ct => _designations.ToggleActiveAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.JobPositions => GuardedAsync(_jobPositions, id, ct => _jobPositions.ToggleActiveAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.Locations    => GuardedAsync(_locations, id, ct => _locations.ToggleActiveAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.CostCenters  => GuardedAsync(_costCenters, id, ct => _costCenters.ToggleActiveAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.DocumentTypes => GuardedAsync(_documentTypes, id, ct => _documentTypes.ToggleActiveAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.OrgDocumentTypes => GuardedAsync(_orgDocumentTypes, id, ct => _orgDocumentTypes.ToggleActiveAsync(id, _currentUser.UserId, ct)),
            OrganizationTabs.AssetTypes => GuardedAsync(_assetTypes, id, ct => _assetTypes.ToggleActiveAsync(id, _currentUser.UserId, ct)),
            _ => Task.FromResult<IActionResult>(BadRequest())
        };

    // =======================================================================
    // Shared endpoints
    // =======================================================================

    /// <summary>Feeds cascading dropdowns. Read-only, so no anti-forgery token needed.</summary>
    [HttpGet("lookup")]
    public async Task<IActionResult> Lookup(string type, int? companyId, int? parentId, bool includeInactive = false)
    {
        try
        {
            // a user pinned to a company only gets that company's lists, whatever companyId is asked for
            var items = await _lookups.GetAsync(type, _currentUser.LookupCompany(companyId), parentId, includeInactive, Ct);
            return Json(_currentUser.OwnCompanies(type, items));
        }
        catch (ArgumentException)
        {
            // Unknown lookup type - a wiring mistake, not something to leak detail about.
            return BadRequest();
        }
    }

    /// <summary>Inline uniqueness check fired when the user leaves the Code field.</summary>
    [HttpGet("check-duplicate")]
    public async Task<IActionResult> CheckDuplicate(string tab, string? code, long id = 0, int? scopeId = null)
    {
        if (string.IsNullOrWhiteSpace(code))
        {
            return Json(new { isDuplicate = false });
        }

        var descriptor = OrganizationTabs.Resolve(tab);

        var isDuplicate = await _lookups.IsDuplicateCodeAsync(
            descriptor.DuplicateEntity, code, id, scopeId, Ct);

        return Json(new { isDuplicate });
    }

    // =======================================================================
    // Employee Documents (db/63) - document types and their sections
    // =======================================================================

    /// <summary>
    /// The "+" next to Section on the document type form: adds a section and returns it,
    /// so the form selects it without reloading. Same right as adding a record.
    /// </summary>
    [HttpPost("document-section")]
    public async Task<IActionResult> AddDocumentSection(string? nameEng, string? nameArb)
    {
        if (!CanWrite(OrganizationTabs.DocumentTypes, isNew: true)) return NoRight();
        // document types and sections are group-wide: not for a user pinned to one company
        if (_currentUser.ActiveCompanyId is not null) return NoRight();

        nameEng = nameEng?.Trim();
        nameArb = nameArb?.Trim();
        if (string.IsNullOrEmpty(nameEng) || nameEng.Length > 150 || (nameArb?.Length ?? 0) > 150)
        {
            return Json(ActionResponse.Invalid(new Dictionary<string, string[]>
            {
                ["SectionNameEng"] = [string.IsNullOrEmpty(nameEng) ? "Enter the section name." : "Use 150 characters or fewer."]
            }));
        }

        var result = await _documentSections.AddAsync(nameEng, nameArb, _currentUser.UserId, Ct);
        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    /// <summary>
    /// The drag on the Employee Documents grid: one section's document types in their new order.
    /// Same right as editing a record.
    /// </summary>
    [HttpPost("document-type-order")]
    public async Task<IActionResult> ReorderDocumentTypes([FromForm] int[]? ids)
    {
        if (!CanWrite(OrganizationTabs.DocumentTypes, isNew: false)) return NoRight();
        // document types are group-wide: not for a user pinned to one company
        if (_currentUser.ActiveCompanyId is not null) return NoRight();

        var ordered = (ids ?? []).Where(id => id > 0).Distinct().ToList();
        if (ordered.Count == 0 || ordered.Count > 500)
        {
            return Json(ActionResponse.Failed("The new order could not be read.", "VALIDATION"));
        }

        var result = await _documentTypes.ReorderAsync(ordered, _currentUser.UserId, Ct);
        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    /// <summary>
    /// db/99: the drag on the Organization Documents grid - every type in its new sequence.
    /// Same right as editing a record.
    /// </summary>
    [HttpPost("org-document-type-order")]
    public async Task<IActionResult> ReorderOrgDocumentTypes([FromForm] int[]? ids)
    {
        if (!CanWrite(OrganizationTabs.OrgDocumentTypes, isNew: false)) return NoRight();
        // organization document types are group-wide: not for a user pinned to one company
        if (_currentUser.ActiveCompanyId is not null) return NoRight();

        var ordered = (ids ?? []).Where(id => id > 0).Distinct().ToList();
        if (ordered.Count == 0 || ordered.Count > 500)
        {
            return Json(ActionResponse.Failed("The new order could not be read.", "VALIDATION"));
        }

        var result = await _orgDocumentTypes.ReorderAsync(ordered, _currentUser.UserId, Ct);
        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    /// <summary>db/100: the drag on the Asset Types grid - every type in its new sequence.</summary>
    [HttpPost("asset-type-order")]
    public async Task<IActionResult> ReorderAssetTypes([FromForm] int[]? ids)
    {
        if (!CanWrite(OrganizationTabs.AssetTypes, isNew: false)) return NoRight();
        // asset types are group-wide: not for a user pinned to one company
        if (_currentUser.ActiveCompanyId is not null) return NoRight();

        var ordered = (ids ?? []).Where(id => id > 0).Distinct().ToList();
        if (ordered.Count == 0 || ordered.Count > 500)
        {
            return Json(ActionResponse.Failed("The new order could not be read.", "VALIDATION"));
        }

        var result = await _assetTypes.ReorderAsync(ordered, _currentUser.UserId, Ct);
        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    /// <summary>The ViewData key of the issuing authorities on the organization document type form.</summary>
    public const string IssuingAuthoritiesKey = "IssuingAuthorities";

    /// <summary>The organization document type form: its issuing authority comes from Documents.IssuingAuthorities (db/75).</summary>
    private async Task<IActionResult> OrgDocumentTypeFormAsync(OrgTab tab, long id)
    {
        var isNew = id <= 0;
        var model = isNew ? new OrgDocumentType { AlertRules = "M3,M1,W1" } : await _orgDocumentTypes.GetByIdAsync(id, Ct);
        if (model is null) return NotFound();

        IReadOnlyList<IssuingAuthority> authorities = Array.Empty<IssuingAuthority>();
        try
        {
            authorities = await _issuingAuthorities.ListAsync(Ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "The issuing authorities could not be read (run db/75).");
        }

        // active ones, plus the type's own if it was deactivated since
        ViewData[IssuingAuthoritiesKey] = authorities
            .Where(a => a.IsActive || a.IssuingAuthorityId == model.IssuingAuthorityId)
            .ToList();

        return PartialView(tab.FormPartial, new FormViewModel<OrgDocumentType>
        {
            Tab = tab,
            Model = model,
            IsNew = isNew,
            Lookups = new Dictionary<string, IReadOnlyList<LookupItem>>(StringComparer.OrdinalIgnoreCase)
        });
    }

    private static GridRequest WholeList(GridRequest request)
    {
        request.PageNumber = 1;
        request.PageSize = int.MaxValue; // clamped to the grid maximum (200)
        return request;
    }

    /// <summary>The document type form: its sections come from Documents.DocumentSections, not a lookup.</summary>
    private async Task<IActionResult> DocumentTypeFormAsync(OrgTab tab, long id)
    {
        var isNew = id <= 0;
        var model = isNew ? new DocumentType() : await _documentTypes.GetByIdAsync(id, Ct);
        if (model is null) return NotFound();

        // active sections, plus the type's own section if it was deactivated since;
        // the option shows the Arabic name in the Arabic UI (Code carries it)
        var sections = (await _documentSections.ListAsync(Ct))
            .Where(x => x.IsActive || x.SectionId == model.SectionId)
            .Select(x => new LookupItem { Id = x.SectionId, Text = x.NameEng, Code = x.NameArb ?? string.Empty })
            .ToList();

        return PartialView(tab.FormPartial, new FormViewModel<DocumentType>
        {
            Tab = tab,
            Model = model,
            IsNew = isNew,
            Lookups = new Dictionary<string, IReadOnlyList<LookupItem>>(StringComparer.OrdinalIgnoreCase) { [DocumentSectionsKey] = sections }
        });
    }

    /// <summary>The key of the sections list in the document type form's lookups.</summary>
    internal const string DocumentSectionsKey = "DOCUMENT_SECTION";

    // =======================================================================
    // Private generics - the actual work, written once
    // =======================================================================

    private async Task<IActionResult> GridAsync<T>(
        IMasterRepository<T> repository,
        OrgTab tab,
        GridRequest request) where T : class
    {
        var page = await repository.ListAsync(request, Ct);

        // Core.usp_Company_Manage lists every company - a pinned user sees only their own
        if (_currentUser.ActiveCompanyId is not null && typeof(T) == typeof(Company))
        {
            var own = page.Items.Where(x => _currentUser.Allows(CompanyScope.CompanyOf(x))).ToList();
            page = new PagedResult<T> { Items = own, TotalCount = own.Count, PageNumber = 1, PageSize = page.PageSize };
        }

        return PartialView(tab.GridPartial, new GridViewModel<T>
        {
            Tab = tab,
            Page = page,
            Request = request
        });
    }

    private async Task<IActionResult> FormAsync<T>(
        IMasterRepository<T> repository,
        OrgTab tab,
        long id,
        Func<T> createNew,
        string[] lookupTypes) where T : class
    {
        var isNew = id <= 0;
        T? model = isNew ? createNew() : await repository.GetByIdAsync(id, Ct);

        // another company's record answers "not found", like a missing one
        if (model is null || (!isNew && !_currentUser.Allows(CompanyScope.CompanyOf(model))))
        {
            return NotFound();
        }

        var lookups = new Dictionary<string, IReadOnlyList<LookupItem>>(StringComparer.OrdinalIgnoreCase);

        foreach (var type in lookupTypes)
        {
            // includeInactive on edit, so a value pointing at a deactivated row
            // does not silently disappear from its dropdown.
            lookups[type] = _currentUser.OwnCompanies(type, await _lookups.GetAsync(
                type,
                companyId: _currentUser.LookupCompany(null),
                parentId: null,
                includeInactive: !isNew,
                cancellationToken: Ct));
        }

        return PartialView(tab.FormPartial, new FormViewModel<T>
        {
            Tab = tab,
            Model = model,
            IsNew = isNew,
            Lookups = lookups
        });
    }

    private async Task<IActionResult> SaveAsync<T>(IMasterRepository<T> repository)
        where T : class, new()
    {
        var model = new T();

        // Binds the posted form to a fresh instance and runs data annotations.
        if (!await TryUpdateModelAsync(model))
        {
            return Json(ActionResponse.Invalid(CollectErrors()));
        }

        if (!await MaySaveAsync(repository, model))
        {
            return Json(ActionResponse.Failed("That record was not found.", "NOT_FOUND"));
        }

        var result = await repository.SaveAsync(model, _currentUser.UserId, Ct);

        if (!result.Success)
        {
            _logger.LogInformation(
                "Save of {Entity} rejected by the database with {Code}.",
                typeof(T).Name, result.ErrorCode);
        }

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    /// <summary>The posted form edits an existing record: the tab's own key field (BranchId, ...) is set.</summary>
    private bool PostedId(string? tab)
    {
        var key = OrganizationTabs.Resolve(tab).Key switch
        {
            OrganizationTabs.Companies => "CompanyId",
            OrganizationTabs.Branches => "BranchId",
            OrganizationTabs.Departments => "DepartmentId",
            OrganizationTabs.Sections => "SectionId",
            OrganizationTabs.Designations => "DesignationId",
            OrganizationTabs.JobPositions => "PositionId",
            OrganizationTabs.Locations => "LocationId",
            OrganizationTabs.CostCenters => "CostCenterId",
            OrganizationTabs.DocumentTypes => "DocumentTypeId",
            OrganizationTabs.OrgDocumentTypes => "OrgDocumentTypeId",
            OrganizationTabs.AssetTypes => "AssetTypeId",
            _ => null
        };
        return key is not null && Request.HasFormContentType && long.TryParse(Request.Form[key], out var v) && v > 0;
    }

    /// <summary>
    /// A pinned user may only save their own company's records: the company posted, the record
    /// being edited (its id property, e.g. BranchId), and - for a section - its department.
    /// </summary>
    private async Task<bool> MaySaveAsync<T>(IMasterRepository<T> repository, T model) where T : class
    {
        if (_currentUser.ActiveCompanyId is null) return true;

        if (model is Section section)
        {
            var department = section.DepartmentId > 0 ? await _departments.GetByIdAsync(section.DepartmentId, Ct) : null;
            if (department is null || !_currentUser.Allows(department.CompanyId)) return false;
        }
        else if (!_currentUser.Allows(CompanyScope.CompanyOf(model)))
        {
            return false;
        }

        // the record's key: <Type>Id (BranchId, SectionId, ...), PositionId for a job position
        var keyName = typeof(T) == typeof(JobPosition) ? nameof(JobPosition.PositionId) : typeof(T).Name + "Id";
        var key = typeof(T).GetProperty(keyName)?.GetValue(model);
        var id = key switch { int i => i, long l => l, _ => 0L };
        return id <= 0 || await OwnsAsync(repository, id);
    }

    /// <summary>The record an id names exists and is in the user's company (CompanyScope).</summary>
    private async Task<bool> OwnsAsync<T>(IMasterRepository<T> repository, long id) where T : class
    {
        if (_currentUser.ActiveCompanyId is null) return true;
        if (id <= 0) return false;
        var record = await repository.GetByIdAsync(id, Ct);
        return record is not null && _currentUser.Allows(CompanyScope.CompanyOf(record));
    }

    /// <summary>A delete / toggle, only on a record of the user's company.</summary>
    private async Task<IActionResult> GuardedAsync<T>(IMasterRepository<T> repository, long id, Func<CancellationToken, Task<SaveResult>> operation) where T : class
    {
        if (!await OwnsAsync(repository, id))
        {
            return Json(ActionResponse.Failed("That record was not found.", "NOT_FOUND"));
        }
        return await WriteAsync(operation);
    }

    private async Task<IActionResult> WriteAsync(Func<CancellationToken, Task<SaveResult>> operation)
    {
        var result = await operation(Ct);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    private Dictionary<string, string[]> CollectErrors() =>
        ModelState
            .Where(entry => entry.Value?.Errors.Count > 0)
            .ToDictionary(
                entry => entry.Key,
                entry => entry.Value!.Errors.Select(e => e.ErrorMessage).ToArray());
}
