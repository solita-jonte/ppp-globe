public class PppGdpPerCapita
{
    public int Id { get; set; }
    public int CountryId { get; set; }
    public int Year { get; set; }
    public decimal Value { get; set; }
    public string Source { get; set; } = default!;

    public Country? Country { get; set; }
}
