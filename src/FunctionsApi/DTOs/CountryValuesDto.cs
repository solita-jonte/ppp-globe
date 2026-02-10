public record CountryValuesDto(
    string Iso2,
    string Name,
    IEnumerable<YearValueDto> Values
);
