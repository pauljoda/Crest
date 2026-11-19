namespace CrestCore.Contracts;

/// A named color Crest offers and draws Spaces with: the colors a Space picks
/// from, and the tinctures each house's look is made of.
public sealed class Tincture {
    #region Variables

    public static readonly Tincture Ink = new("ink", "Ink", new(0.08, 0.15, 0.23));
    public static readonly Tincture Indigo = new("indigo", "Indigo", new(0.29, 0.25, 0.58));
    public static readonly Tincture Ocean = new("ocean", "Ocean", new(0.22, 0.42, 0.64));
    public static readonly Tincture Sky = new("sky", "Sky", new(0.35, 0.66, 0.84));
    public static readonly Tincture Teal = new("teal", "Teal", new(0.12, 0.49, 0.52));
    public static readonly Tincture Sage = new("sage", "Sage", new(0.39, 0.56, 0.42));
    public static readonly Tincture Gold = new("gold", "Gold", new(0.88, 0.67, 0.25));
    public static readonly Tincture Ember = new("ember", "Ember", new(0.85, 0.27, 0.20));
    public static readonly Tincture Rose = new("rose", "Rose", new(0.72, 0.25, 0.42));
    public static readonly Tincture Sand = new("sand", "Sand", new(0.82, 0.72, 0.56));
    public static readonly Tincture WinterSlate = new("winterSlate", "Slate", new(0.198, 0.257, 0.309));
    public static readonly Tincture WinterSteel = new("winterSteel", "Steel", new(0.302, 0.364, 0.419));
    public static readonly Tincture WinterIce = new("winterIce", "Ice", new(0.725, 0.872, 0.934));
    public static readonly Tincture LionOxblood = new("lionOxblood", "Oxblood", new(0.306, 0.053, 0.179));
    public static readonly Tincture LionCrimson = new("lionCrimson", "Crimson", new(0.56, 0.213, 0.243));
    public static readonly Tincture LionGold = new("lionGold", "Antique Gold", new(0.88, 0.603, 0.273));
    public static readonly Tincture StormMidnight = new("stormMidnight", "Midnight", new(0.12, 0.18, 0.278));
    public static readonly Tincture StormGunmetal = new("stormGunmetal", "Gunmetal", new(0.131, 0.303, 0.386));
    public static readonly Tincture StormBrass = new("stormBrass", "Brass", new(0.871, 0.723, 0.401));
    public static readonly Tincture DragonChar = new("dragonChar", "Char", new(0.214, 0.071, 0.051));
    public static readonly Tincture DragonBlood = new("dragonBlood", "Blood", new(0.423, 0.043, 0.016));
    public static readonly Tincture DragonScarlet = new("dragonScarlet", "Scarlet", new(0.745, 0.267, 0.220));
    public static readonly Tincture MeadowForest = new("meadowForest", "Forest", new(0.118, 0.356, 0.202));
    public static readonly Tincture MeadowMoss = new("meadowMoss", "Moss", new(0.271, 0.468, 0.251));
    public static readonly Tincture MeadowWheat = new("meadowWheat", "Wheat", new(0.737, 0.655, 0.400));
    public static readonly Tincture IronBlack = new("ironBlack", "Iron", new(0.103, 0.126, 0.143));
    public static readonly Tincture IronPewter = new("ironPewter", "Pewter", new(0.198, 0.223, 0.242));
    public static readonly Tincture IronPatina = new("ironPatina", "Patina", new(0.411, 0.686, 0.591));
    public static readonly Tincture RiverNavy = new("riverNavy", "Navy", new(0.0, 0.33, 0.579));
    public static readonly Tincture RiverLapis = new("riverLapis", "Lapis", new(0.0, 0.51, 0.61));
    public static readonly Tincture RiverRust = new("riverRust", "Rust", new(0.659, 0.361, 0.255));
    public static readonly Tincture SunUmber = new("sunUmber", "Umber", new(0.208, 0.086, 0.043));
    public static readonly Tincture SunTerracotta = new("sunTerracotta", "Terracotta", new(0.789, 0.349, 0.231));
    public static readonly Tincture SunDune = new("sunDune", "Dune", new(0.792, 0.533, 0.245));
    public static readonly Tincture VigilOnyx = new("vigilOnyx", "Onyx", new(0.091, 0.095, 0.106));
    public static readonly Tincture VigilCharcoal = new("vigilCharcoal", "Charcoal", new(0.184, 0.189, 0.202));
    public static readonly Tincture VigilAsh = new("vigilAsh", "Ash", new(0.482, 0.514, 0.549));
    public static readonly Tincture WinterArgent = new("winterArgent", "Argent", new(0.871, 0.894, 0.910));
    public static readonly Tincture WinterWolf = new("winterWolf", "Wolf Grey", new(0.341, 0.384, 0.427));
    public static readonly Tincture LionGules = new("lionGules", "Gules", new(0.433, 0.092, 0.141));
    public static readonly Tincture LionOr = new("lionOr", "Or", new(0.922, 0.776, 0.411));
    public static readonly Tincture StormOr = new("stormOr", "Storm Gold", new(0.835, 0.655, 0.231));
    public static readonly Tincture StormSable = new("stormSable", "Sable", new(0.090, 0.094, 0.106));
    public static readonly Tincture DragonSable = new("dragonSable", "Night", new(0.071, 0.059, 0.063));
    public static readonly Tincture DragonFire = new("dragonFire", "Fire", new(0.651, 0.236, 0.0));
    public static readonly Tincture MeadowVert = new("meadowVert", "Vert", new(0.238, 0.469, 0.308));
    public static readonly Tincture MeadowRose = new("meadowRose", "Rose Gold", new(0.965, 0.78, 0.603));
    public static readonly Tincture IronOr = new("ironOr", "Kraken Gold", new(0.883, 0.72, 0.36));
    public static readonly Tincture RiverAzure = new("riverAzure", "Azure", new(0.149, 0.446, 0.716));
    public static readonly Tincture RiverGules = new("riverGules", "River Red", new(0.643, 0.157, 0.188));
    public static readonly Tincture RiverArgent = new("riverArgent", "Silver", new(0.859, 0.921, 0.952));
    public static readonly Tincture SunTenne = new("sunTenne", "Tenné", new(0.751, 0.392, 0.124));
    public static readonly Tincture SunGules = new("sunGules", "Sunset Red", new(0.655, 0.227, 0.106));
    public static readonly Tincture SunOr = new("sunOr", "Saffron", new(0.975, 0.83, 0.42));
    public static readonly Tincture VigilBone = new("vigilBone", "Bone", new(0.894, 0.868, 0.814));
    public static readonly Tincture NeutralSmoke = new("neutralSmoke", "Smoke", new(0.337, 0.337, 0.337));
    public static readonly Tincture NeutralGray = new("neutralGray", "Gray", new(0.588, 0.588, 0.588));
    public static readonly Tincture DragonFlame = new("dragonFlame", "Flame", new(0.985, 0.825, 0.42));

    /// The slate a Storm sidebar's pattern draws in.
    public static readonly Tincture StormSlate = new("stormSlate", "Slate Blue", new(0.219, 0.283, 0.388));

    /// The cinder a Dragon crest's field stands on.
    public static readonly Tincture DragonCinder = new("dragonCinder", "Cinder", new(0.324, 0.169, 0.145));

    /// The deep sea teal an Iron sidebar runs down into.
    public static readonly Tincture IronTide = new("ironTide", "Tide", new(0.114, 0.207, 0.218));

    /// The ink a Crest sidebar starts from at its head.
    public static readonly Tincture CrestInk = new("crestInk", "Crest Ink", new(0.090, 0.133, 0.220));

    /// The dusk a Crest sidebar passes through on its way into sky.
    public static readonly Tincture CrestDusk = new("crestDusk", "Dusk", new(0.180, 0.294, 0.408));

    /// The sky a Crest sidebar washes into at its foot.
    public static readonly Tincture CrestSky = new("crestSky", "Crest Sky", new(0.353, 0.608, 0.784));

    /// The butter of the front banner in Crest's mark, which a Crest Space's
    /// figure and highlights wear.
    public static readonly Tincture CrestButter = new("crestButter", "Butter", new(0.949, 0.757, 0.306));

    /// The coral of the middle banner in Crest's mark, which a Crest crest's
    /// field wears.
    public static readonly Tincture CrestCoral = new("crestCoral", "Coral", new(0.914, 0.376, 0.294));

    // The simple houses' colors, from Crest's brand.
    public static readonly Tincture CrestCream = new("crestCream", "Cream", new(0.984, 0.961, 0.902));
    public static readonly Tincture CrestSage = new("crestSage", "Soft Sage", new(0.553, 0.749, 0.604));
    public static readonly Tincture MoonNight = new("moonNight", "Night", new(0.118, 0.161, 0.271));
    public static readonly Tincture MoonTide = new("moonTide", "Moonlit Blue", new(0.184, 0.306, 0.494));
    public static readonly Tincture SummitButter = new("summitButter", "Pale Butter", new(0.965, 0.878, 0.627));
    public static readonly Tincture LensMist = new("lensMist", "Mist", new(0.933, 0.961, 0.918));
    public static readonly Tincture LensFern = new("lensFern", "Fern", new(0.796, 0.886, 0.812));
    public static readonly Tincture SparkTwilight = new("sparkTwilight", "Twilight", new(0.165, 0.118, 0.227));
    public static readonly Tincture SparkMulberry = new("sparkMulberry", "Mulberry", new(0.349, 0.188, 0.31));
    public static readonly Tincture GroveDeep = new("groveDeep", "Deep Forest", new(0.118, 0.169, 0.133));
    public static readonly Tincture GroveMoss = new("groveMoss", "Grove Moss", new(0.243, 0.361, 0.263));

    public static IReadOnlyList<Tincture> All { get; } = [
        Ink, Indigo, Ocean, Sky, Teal, Sage, Gold, Ember, Rose, Sand, WinterSlate, WinterSteel, WinterIce, LionOxblood,
        LionCrimson, LionGold, StormMidnight, StormGunmetal, StormBrass, DragonChar, DragonBlood, DragonScarlet,
        MeadowForest, MeadowMoss, MeadowWheat, IronBlack, IronPewter, IronPatina, RiverNavy, RiverLapis, RiverRust,
        SunUmber, SunTerracotta, SunDune, VigilOnyx, VigilCharcoal, VigilAsh, WinterArgent, WinterWolf, LionGules, LionOr,
        StormOr, StormSable, DragonSable, DragonFire, MeadowVert, MeadowRose, IronOr, RiverAzure, RiverGules, RiverArgent,
        SunTenne, SunGules, SunOr, VigilBone, NeutralSmoke, NeutralGray, DragonFlame, StormSlate, DragonCinder, IronTide,
        CrestInk, CrestDusk, CrestSky, CrestButter, CrestCoral, CrestCream, CrestSage, MoonNight, MoonTide, SummitButter, LensMist,
        LensFern, SparkTwilight, SparkMulberry, GroveDeep, GroveMoss
    ];

    public string Name { get; }

    /// The color's name where a person sees it, such as a palette's tooltip.
    [Localized]
    public string Title { get; }

    public BrandColor Color { get; }

    #endregion

    #region Constructors

    private Tincture(string name, string title, BrandColor color) {
        Name = name;
        Title = title;
        Color = color;
    }

    #endregion

    #region Actions - Lookup

    public static Tincture? Named(string? name) => All.FirstOrDefault(tincture => tincture.Name == name);

    /// The tincture that looks like `color`, allowing for rounding.
    public static Tincture? Matching(BrandColor color) {
        ArgumentNullException.ThrowIfNull(color);
        return All.FirstOrDefault(tincture => Math.Abs(tincture.Color.Red - color.Red) < 0.004
            && Math.Abs(tincture.Color.Green - color.Green) < 0.004 && Math.Abs(tincture.Color.Blue - color.Blue) < 0.004);
    }

    #endregion
}
