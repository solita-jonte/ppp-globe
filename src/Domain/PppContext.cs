using Microsoft.EntityFrameworkCore;

public class PppContext : DbContext
{
    public PppContext(DbContextOptions<PppContext> options) : base(options) { }

    public DbSet<Country> Countries => Set<Country>();
    public DbSet<PppGdpPerCapita> PppGdpPerCapita => Set<PppGdpPerCapita>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Country>(entity =>
        {
            entity.ToTable("Country");
            entity.HasKey(x => x.Id);
            entity.HasIndex(x => x.Iso2).IsUnique();

            entity.Property(x => x.Iso2).IsRequired().HasMaxLength(2);
            entity.Property(x => x.Name).IsRequired().HasMaxLength(200);
        });

        modelBuilder.Entity<PppGdpPerCapita>(entity =>
        {
            entity.ToTable("PppGdpPerCapita");
            entity.HasKey(x => x.Id);
            entity.HasIndex(x => new { x.CountryId, x.Year }).IsUnique();

            entity.Property(x => x.Source).IsRequired().HasMaxLength(50);

            entity.HasOne(x => x.Country)
                .WithMany(c => c.PppValues)
                .HasForeignKey(x => x.CountryId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
