using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

// ----- EF Core entities and context ------

var connectionString = Environment.GetEnvironmentVariable("ConnectionStrings__PppDb");

var optionsBuilder = new DbContextOptionsBuilder<PppContext>()
    .UseSqlServer(connectionString);

using var db = new PppContext(optionsBuilder.Options);

// Test DB connection
Console.WriteLine("Testing DB connection...");
await db.Database.OpenConnectionAsync();
await db.Database.CloseConnectionAsync();
Console.WriteLine("DB OK.");

using var http = new HttpClient();

// ----- 1) Load country list from World Bank -----

Console.WriteLine("Downloading country list from World Bank...");

var countryUrl = "http://api.worldbank.org/v2/country?format=json&per_page=400";
var countryJson = await http.GetStringAsync(countryUrl);
using var countryDoc = JsonDocument.Parse(countryJson);
var countryArray = countryDoc.RootElement[1];

var countriesToInsert = new List<Country>();

foreach (var item in countryArray.EnumerateArray())
{
    var capital = item.GetProperty("capitalCity").GetString()!;

    // Filter: keep only real countries (capital is not empty)
    if (string.IsNullOrWhiteSpace(capital))
    {
        continue;
    }

    var iso2 = item.GetProperty("iso2Code").GetString()!;
    var iso3 = item.GetProperty("id").GetString()!;
    var countryName = item.GetProperty("name").GetString()!;

    // Check if already in DB
    var exists = await db.Countries.AnyAsync(c => c.Iso3 == iso3);
    if (!exists)
    {
        countriesToInsert.Add(new Country
        {
            Iso2 = iso2,
            Iso3 = iso3,
            Name = countryName
        });
    }
}

if (countriesToInsert.Any())
{
    db.Countries.AddRange(countriesToInsert);
    await db.SaveChangesAsync();
    Console.WriteLine($"Inserted {countriesToInsert.Count} countries.");
}
else
{
    Console.WriteLine("No new countries to insert.");
}

// Reload all countries (now from DB) for PPP loading
var allCountries = await db.Countries.AsNoTracking().ToListAsync();
Console.WriteLine($"Total countries in DB: {allCountries.Count}");

// ----- 2) For each country, load PPP GDP per capita -----

// Build dictionary: Iso2 -> Country
var countriesByIso2 = allCountries
    .ToDictionary(c => c.Iso2, c => c, StringComparer.OrdinalIgnoreCase);

Console.WriteLine($"Downloading PPP-adjusted GPD/capita...");

const string IndicatorCode = "NY.GDP.PCAP.PP.KD";  // PPP-adjusted GDP/capita
var url = $"https://api.worldbank.org/v2/country/all/indicator/{IndicatorCode}?format=json&per_page=20000";

string json = await http.GetStringAsync(url);
using var doc = JsonDocument.Parse(json);
var dataArray = doc.RootElement[1];

var observationsToInsert = new List<PppGdpPerCapita>();

foreach (var item in dataArray.EnumerateArray())
{
    var iso2 = item.GetProperty("country").GetProperty("id").GetString() ?? "";  // e.g. "AT"
    if (!countriesByIso2.TryGetValue(iso2, out var country)) {
        continue;
    }

    var dateStr = item.GetProperty("date").GetString()!;  // e.g., "2023"
    if (!int.TryParse(dateStr, out var year)) {
        continue;
    }

    var valueElement = item.GetProperty("value");
    if (valueElement.ValueKind == JsonValueKind.Null) {
        continue;
    }
    var value = valueElement.GetDecimal()!;

    // Skip if already present (CountryId, Year) is unique in DB
    var exists = await db.PppGdpPerCapita
        .AnyAsync(x => x.CountryId == country.Id && x.Year == year);

    if (!exists)
    {
        observationsToInsert.Add(new PppGdpPerCapita
        {
            CountryId = country.Id,
            Year = year,
            Value = value,
            Source = "WorldBank"
        });
    }
}

if (observationsToInsert.Any())
{
    db.PppGdpPerCapita.AddRange(observationsToInsert);
    await db.SaveChangesAsync();
    Console.WriteLine($"Inserted {observationsToInsert.Count} observations");
}
else
{
    Console.WriteLine($"No new observations");
}

Console.WriteLine("Data load completed.");
