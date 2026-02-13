public class Country
{
    public int Id { get; set; }
    public string Iso2 { get; set; } = default!;
    public string Iso3 { get; set; } = default!;
    public string Name { get; set; } = default!;
    public ICollection<PppGdpPerCapita> PppValues { get; set; } = [];
}
