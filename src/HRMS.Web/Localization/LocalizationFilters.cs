using HRMS.Web.Models.Organization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace HRMS.Web.Localization;

/// <summary>
/// Translates every <see cref="ActionResponse"/> on its way out. Messages come
/// from stored procedures (@ResultMessage), controllers and validation - all in
/// English - and are matched against Core.UiLabels.SourceText, so a new message
/// is translated by adding a row, not by touching code.
/// </summary>
public sealed class ActionResponseLocalizationFilter : IResultFilter
{
    private readonly IUiText _text;

    public ActionResponseLocalizationFilter(IUiText text) => _text = text;

    public void OnResultExecuting(ResultExecutingContext context)
    {
        if (!_text.IsArabic || context.Result is not JsonResult { Value: ActionResponse response } json)
        {
            return;
        }

        json.Value = new ActionResponse
        {
            Success   = response.Success,
            Id        = response.Id,
            ErrorCode = response.ErrorCode,
            // Only the main message is captured when untranslated (procedure and
            // controller sentences). Field errors are usually already Arabic
            // (DataAnnotations go through LabelStringLocalizer) and may echo
            // what the user typed, so they are translated but never captured.
            Message   = _text.Tr(response.Message, capture: true),
            Errors    = response.Errors?.ToDictionary(
                entry => entry.Key,
                entry => entry.Value.Select(message => _text.Tr(message)).ToArray())
        };
    }

    public void OnResultExecuted(ResultExecutedContext context)
    {
    }
}
