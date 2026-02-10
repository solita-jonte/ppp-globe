using Microsoft.Azure.Functions.Worker.Http;
using System.Web;

namespace FunctionsApi;

public static class HttpRequestDataExtensions
{
    public static IReadOnlyDictionary<string, string?> GetQueryParams(this HttpRequestData req)
    {
        var query = HttpUtility.ParseQueryString(req.Url.Query);
        var dict = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);

        foreach (var key in query.AllKeys)
        {
            if (key is null) continue;
            dict[key] = query[key];
        }

        return dict;
    }
}
