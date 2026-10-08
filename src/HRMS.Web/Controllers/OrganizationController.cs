using HRMS.Data.Infrastructure;
using HRMS.Data.Repositories;
using HRMS.Domain.Common;
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
    public IActionResult Index(string? tab)
    {
        if (!CanView) return Forbid();
        var model = new OrganizationIndexViewModel
        {
            ActiveTab = OrganizationTabs.Resolve(tab)
        };

        return View(model);
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
        // a pinned user's own company always wins over a CompanyId in the query string
        request.CompanyId = _currentUser.ActiveCompanyId ?? request.CompanyId;

        // Top-bar company filter (cookie). Companies tab ignores it (Core.usp_Company_Manage
        // accepts but does not apply @CompanyIds) so every company stays listed there.
        request.CompanyIds = _companyFilter.Csv;

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
