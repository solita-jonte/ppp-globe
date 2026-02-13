public record CountryValuesDto(
    string Iso2,
    string Iso3,
    string Name,
    IEnumerable<YearValueDto> Values
);
