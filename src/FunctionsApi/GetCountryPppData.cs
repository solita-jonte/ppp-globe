using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Http;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.EntityFrameworkCore;
using System.Net;

namespace FunctionsApi;

public class GetCountryPppData
{
    private readonly PppContext _db; // Inject your DbContext
    private readonly ILogger<GetCountryPppData> _logger;

    public GetCountryPppData(PppContext db, ILogger<GetCountryPppData> logger)
    {
        _db = db;
        _logger = logger;
    }

    [Function("GetCountryPppData")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "country-ppp")] HttpRequestData req)
    {
        _logger.LogInformation("C# HTTP trigger function processed a request for country PPP data.");

        // 1. Define default year span
        int startYear = 1800;
        int endYear = 2100;

        var query = req.GetQueryParams();

        // 2. Parse optional 'startYear' from query parameters
        if (query.TryGetValue("startYear", out var startYearString) && int.TryParse(startYearString, out int parsedStartYear))
        {
            startYear = parsedStartYear;
        }

        // 3. Parse optional 'endYear' from query parameters
        if (query.TryGetValue("endYear", out var endYearString) && int.TryParse(endYearString, out int parsedEndYear))
        {
            endYear = parsedEndYear;
        }

        // Optional: Ensure startYear is not greater than endYear
        if (startYear > endYear)
        {
            _logger.LogWarning($"startYear ({startYear}) was greater than endYear ({endYear}). Swapping them.");
            (startYear, endYear) = (endYear, startYear); // Tuple swap for C# 7.0+
        }

        _logger.LogInformation($"Filtering country PPP data for years between {startYear} and {endYear}.");

        // 4. Modify the LINQ query to include the year span filter
        var data = await _db.Countries
            .Select(c => new CountryValuesDto(
                c.Iso2,
                c.Name,
                c.PppValues
                    // Apply the year filter here
                    .Where(v => v.Year >= startYear && v.Year <= endYear)
                    .OrderBy(v => v.Year)
                    .Select(v => new YearValueDto(v.Year, v.Value))
            ))
            .ToListAsync();

        var response = req.CreateResponse(HttpStatusCode.OK);
        await response.WriteAsJsonAsync(data); // Serialize the result to JSON
        return response;
    }
}
