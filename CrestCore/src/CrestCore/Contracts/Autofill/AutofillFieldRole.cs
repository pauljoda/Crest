using System.Globalization;
using System.Text.RegularExpressions;

using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What a field of an address or card form is for. Each role carries the
/// autocomplete tokens of the HTML standard that declare it, the words that
/// name it in what a page calls a field, how it spells its value from an
/// address or a card for the field it fills, and how it reads a value the
/// person sent back into one. A role travels as its index in `All`, so `All`
/// is append-only.
///
/// The words are those of English, German, French, Spanish, Italian, Dutch
/// and Portuguese forms, partly adapted from Chromium's BSD-licensed autofill
/// regular expressions. They match a field's names as `FoldedText` folds
/// them: in lowercase, without diacritics, with `ß` spelled `ss` and every
/// other character than letters and digits one space. A role's defining
/// phrase, such as "Straße und Hausnummer", wins over every other role's
/// words; otherwise the roles are tried in `Inference` order, the most
/// specific first, so "Name on card" is a cardholder and "Company name" an
/// organization before either is a person's name.
public sealed class AutofillFieldRole {
    #region Static Variables

    /// The size of a part of a card number split across fields that does not
    /// say its own.
    private const int CardNumberPart = 4;

    /// The words of a street, shared by a street address in one text area and
    /// its first line.
    private const string StreetWords =
        @"address|\baddr\b|street|strasse|\bstr\b|anschrift|adresse|\brue\b|\bvoie\b|direccion|\bcalle\b|domicilio|indirizzo|\bvia\b|straat|\badres\b|morada|endereco|\brua\b|logradouro|adresszeile";

    public static readonly AutofillFieldRole FullName = ForAddress(name: "fullName", tokens: ["name"],
        definedBy: @"full\s?name|your\s?name|complete\s?name|first\s?and\s?last\s?name|vor\s?und\s?(nach|zu)\s?name|vollstandiger\s?name|nom\s?complet|nom\s?et\s?prenom|prenom\s?et\s?nom|nombre\s?completo|nombre\s?y\s?apellidos?|nome\s?completo|nome\s?e\s?cognome|nome\s?e\s?sobrenome|volledige\s?naam|voor\s?en\s?achternaam",
        suggestedBy: @"\bname\b|\bnaam\b|recipient|empfanger|destinataire|destinatario|ontvanger|contact\s?person|ansprechpartner",
        spell: SpellFullName, capture: CaptureFullName);

    public static readonly AutofillFieldRole GivenName = ForAddress(name: "givenName", tokens: ["given-name"],
        suggestedBy: @"first\s?name|\bfirst\b|\bfname\b|given\s?name|forename|vorname|prenom|\bnombre\b|\bnome\b|voornaam|primeiro\s?nome",
        spell: (address, _, _) => [address.GivenName], capture: (draft, spellings) => draft.GivenName = spellings[0]);

    public static readonly AutofillFieldRole AdditionalName = ForAddress(name: "additionalName", tokens: ["additional-name"],
        suggestedBy: @"middle\s?(name|initial)|\bmiddle\b|\bmname\b|zweiter\s?vorname|weitere\s?vornamen|segundo\s?nombre|deuxieme\s?prenom|second\s?prenom|secondo\s?nome|tweede\s?voornaam|nome\s?do\s?meio",
        spell: (address, _, _) => [address.AdditionalName, address.AdditionalName.Trim() is { Length: > 0 } middle ? middle[..1] : null],
        capture: (draft, spellings) => draft.AdditionalName = spellings[0]);

    public static readonly AutofillFieldRole FamilyName = ForAddress(name: "familyName", tokens: ["family-name"],
        suggestedBy: @"last\s?name|\blname\b|surname|family\s?name|nachname|zuname|familienname|\bnom\b|apellidos?|cognome|achternaam|sobrenome|apelido|\blast\b",
        spell: (address, _, _) => [address.FamilyName], capture: (draft, spellings) => draft.FamilyName = spellings[0]);

    public static readonly AutofillFieldRole Organization = ForAddress(name: "organization", tokens: ["organization"],
        suggestedBy: @"company(?!\s?address)|business(?!\s?address)|organi[sz]ation|\bfirma\b|firmenname|unternehmen|societe|entreprise|raison\s?sociale|empresa|azienda|ragione\s?sociale|societa|bedrijf|organisatie|\borg\b",
        spell: (address, _, _) => [address.Organization], capture: (draft, spellings) => draft.Organization = spellings[0]);

    /// The whole street address in one field: its lines on lines of their own
    /// in a text area, and joined by commas in a single line.
    public static readonly AutofillFieldRole StreetAddress = ForAddress(name: "streetAddress", tokens: ["street-address"],
        suggestedBy: StreetWords, accepts: field => field.InputType.SpansLines,
        spell: SpellStreetAddress, capture: CaptureStreetAddress);

    /// The first line of the street address, which also takes the lines after
    /// it when the section has no field for them, and leaves out the house
    /// number when it has one for that.
    public static readonly AutofillFieldRole AddressLine1 = ForAddress(name: "addressLine1", tokens: ["address-line1"],
        definedBy: @"strasse\s?(und\s?|u\s?)?(haus\s?)?(nummer|nr)|street\s?and\s?(house\s?)?number|(rue|calle|via|straat|rua)\s?(et|y|e|en)\s?(numero|num|nummer|huisnummer)|straat\s?(en\s?)?huisnummer|address\s?line\s?1|\baddress\s?1\b|\baddr\s?1\b",
        suggestedBy: StreetWords,
        spell: SpellFirstLine, capture: (draft, spellings) => draft.StreetLines[0] = spellings[0]);

    public static readonly AutofillFieldRole AddressLine2 = ForAddress(name: "addressLine2", tokens: ["address-line2"],
        suggestedBy: @"address\s?line\s?2|\baddress\s?2|\baddr\s?2|\bline\s?2|street\s?2|\bapt\b|apartment|\bsuite\b|\bunit\b|\bflat\b|building(?!\s?(number|no|nr))|\bfloor\b|adresszusatz|zusatz|adresszeile\s?2|address\s?(complement|supplement|addition)|complement|appartement|batiment|\betage\b|lieu\s?dit|direccion\s?2|\bpiso\b|indirizzo\s?2|\binterno\b|\bscala\b|toevoeging|adresregel\s?2|endereco\s?2|\bc\s?o\b|care\s?of",
        spell: SpellSecondLine,
        capture: (draft, spellings) => draft.StreetLines[1] = spellings[0]);

    public static readonly AutofillFieldRole AddressLine3 = ForAddress(name: "addressLine3", tokens: ["address-line3"],
        suggestedBy: @"address\s?line\s?3|\baddress\s?3|\baddr\s?3|\bline\s?3|street\s?3|adresszeile\s?3|indirizzo\s?3|direccion\s?3|adresregel\s?3|endereco\s?3",
        spell: (address, _, _) => [string.Join(", ", address.Lines.Skip(2))],
        capture: (draft, spellings) => draft.StreetLines[2] = spellings[0]);

    /// The number on the street, which the standard has no token for. A form
    /// that asks for it apart takes the street alone in its first line.
    public static readonly AutofillFieldRole HouseNumber = ForAddress(name: "houseNumber", tokens: [],
        suggestedBy: @"house\s?(number|no|nr|num)|hausnummer|haus\s?nr|\bhnr\b|huisnummer|huis\s?nr|numero\s?civico|\bcivico\b|street\s?number|building\s?number|numero\s?(de\s?)?(rue|calle|casa|porta|voie)|\bnr\b|\bnumero\b|\bnum\b",
        spell: (address, _, _) => [StreetLine.Split(Line(address, 0)).HouseNumber],
        capture: (draft, spellings) => draft.HouseNumber = spellings[0]);

    /// The city or town, the standard's second address level.
    public static readonly AutofillFieldRole City = ForAddress(name: "city", tokens: ["address-level2"],
        suggestedBy: @"city|\btown\b|\bort\b|stadt|wohnort|\bville\b|localite|commune|ciudad|localidad|poblacion|municipio|citta|comune|localita|plaats|woonplaats|\bstad\b|cidade|localidade|suburb|municipality",
        spell: (address, _, _) => [address.City], capture: (draft, spellings) => draft.City = spellings[0]);

    /// The state, province or region, the standard's first address level. A
    /// select may spell it by name or by code.
    public static readonly AutofillFieldRole Region = ForAddress(name: "region", tokens: ["address-level1"],
        suggestedBy: @"state\b|\bprovince\b|provincia|\bprov\b|\bregion\b|\bcounty\b|bundesland|\bkanton\b|\bcanton\b|departement|\bestado\b|regione|provincie|distrito|prefecture|\bterritory\b",
        spell: (address, _, _) => Domain.Country.Coded(address.Country)?.RegionSpellings(address.Region) ?? [address.Region],
        capture: (draft, spellings) => draft.Region = spellings[0]);

    public static readonly AutofillFieldRole PostalCode = ForAddress(name: "postalCode", tokens: ["postal-code"],
        suggestedBy: @"zip|postal\s?code|postalcode|post\s?code|postcode|\bpcode\b|postleitzahl|\bplz\b|code\s?postal|\bcp\b|codigo\s?postal|\bcap\b|codice\s?postale|\bcep\b|postnummer",
        spell: (address, _, _) => [address.PostalCode], capture: (draft, spellings) => draft.PostalCode = spellings[0]);

    /// The country. A text field takes its English name, or its code when it
    /// holds too few characters for the name; a select its option of any of
    /// the country's codes or names.
    public static readonly AutofillFieldRole Country = ForAddress(name: "country", tokens: ["country", "country-name"],
        suggestedBy: @"country|countries|\bland\b|\bpays\b|\bpais\b|nazione|\bpaese\b|\bstaat\b|\bnation\b",
        spell: (address, _, _) => Domain.Country.Coded(address.Country)?.Spellings ?? [],
        capture: (draft, spellings) => draft.Country = spellings.Select(Domain.Country.Named).OfType<Domain.Country>().FirstOrDefault()?.Code ?? "");

    public static readonly AutofillFieldRole Phone = ForAddress(name: "phone", tokens: ["tel"], impliedBy: FormInputType.Telephone,
        suggestedBy: @"phone|mobile|\btel\b|telephone|telefon|telefono|telefone|telefoon|\bhandy\b|\bmobil|portable|cellulare|cellular|celular|\bcell\b|mobiel|telemovel|contact\s?number|rufnummer",
        repeats: true,
        spell: (address, _, _) => [address.Phone, string.Concat(address.Phone.Where(character => char.IsAsciiDigit(character) || character == '+'))],
        capture: (draft, spellings) => draft.Phone = spellings[0]);

    public static readonly AutofillFieldRole Email = ForAddress(name: "email", tokens: ["email"], impliedBy: FormInputType.Email,
        impliedOverNames: true, suggestedBy: @"e\s?mail|courriel|correo|posta\s?elettronica",
        repeats: true, spell: (address, _, _) => [address.Email], capture: (draft, spellings) => draft.Email = spellings[0]);

    public static readonly AutofillFieldRole CardholderName = ForCard(name: "cardholderName", tokens: ["cc-name"],
        suggestedBy: @"card\s?holder|cardholder|\bholder\b|name\s?on\s?(the\s?)?card|card\s?name|\bcc\s?name|ccname|name\s?of\s?card|card\s?owner|karteninhaber|\binhaber\b|name\s?auf\s?der\s?karte|titulaire|nom\s?(du\s?titulaire|sur\s?la\s?carte|du\s?porteur)|porteur|titular|nombre\s?(del\s?titular|en\s?la\s?tarjeta)|intestatario|titolare|nome\s?(sulla\s?carta|del\s?titolare|no\s?cartao|impresso)|kaarthouder|naam\s?op\s?(de\s?)?kaart|portador",
        spell: (card, _, _) => [card.Cardholder], capture: (draft, spellings) => draft.Cardholder = spellings[0]);

    public static readonly AutofillFieldRole CardholderGivenName = ForCard(name: "cardholderGivenName", tokens: ["cc-given-name"],
        suggestedBy: @"(card\s?holder|cardholder|\bcc|name\s?on\s?card|karteninhaber)\s?(first|given|vor)|\bcc\s?fname",
        spell: (card, _, _) => [PersonName.Split(card.Cardholder).Forenames],
        capture: (draft, spellings) => draft.CardholderGivenName = spellings[0]);

    public static readonly AutofillFieldRole CardholderFamilyName = ForCard(name: "cardholderFamilyName", tokens: ["cc-family-name"],
        suggestedBy: @"(card\s?holder|cardholder|\bcc|name\s?on\s?card|karteninhaber)\s?(last|family|sur|nach)|\bcc\s?lname",
        spell: (card, _, _) => [PersonName.Split(card.Cardholder).Family],
        capture: (draft, spellings) => draft.CardholderFamilyName = spellings[0]);

    /// The card number: its digits, or its network's groups where the
    /// placeholder shows groups and the field holds them, or its part of the
    /// digits when the number is split across consecutive fields.
    public static readonly AutofillFieldRole CardNumber = ForCard(name: "cardNumber", tokens: ["cc-number"], repeats: true,
        suggestedBy: @"card\s?(number|no|num|nr|nummer)\b|cardnumber|cardnum|\bcc\s?(number|num|no|nr)\b|ccnum|credit\s?card|creditcard|debit\s?card|kreditkarte|kartennummer|karten\s?nummer|numero\s?(de\s?|del\s?|della\s?|do\s?|da\s?)?(la\s?)?(carte|tarjeta|cartao|carta)|kaartnummer|kaart\s?nummer|\bpan\b",
        spell: (card, field, filling) => Domain.CardNumber.Read(card.Number) is { } number ? NumberSpellings(number, field, filling) : [],
        capture: (draft, spellings) => draft.CardDigits.Append(string.Concat(spellings[^1].Where(character => character is not (' ' or '-')))));

    /// The expiry in one field, spelled as the field shows or its length
    /// suggests, or as its year and month in a month field. A select whose
    /// options are months or years is read as that part.
    public static readonly AutofillFieldRole Expiry = ForCard(name: "expiry", tokens: ["cc-exp"],
        suggestedBy: @"expir|\bexp\b|exp\s?date|expdate|valid\s?(thru|through|until|till|to)|good\s?thru|gultig\s?bis|gultigkeit|ablauf|verfall|date\s?d\s?expiration|validite|caducidad|vencimiento|fecha\s?de\s?exp|scadenza|vervaldatum|geldig\s?tot|validade|vencimento|\bmm\s?(yy|jj|aa)|\bmm(yy|jj|aa)\b",
        refine: ExpiryPart,
        spell: (card, field, _) => field.InputType.TakesMonth
            ? [string.Create(CultureInfo.InvariantCulture, $"{card.ExpiryYear:0000}-{card.ExpiryMonth:00}")]
            : field.InputType.OffersChoices ? [.. ExpiryFormat.Spelled.Select(format => format.Spell(card.ExpiryMonth, card.ExpiryYear))]
            : [ExpiryFormat.Of(field).Spell(card.ExpiryMonth, card.ExpiryYear)],
        capture: (draft, spellings) => {
            if (spellings.Select(ExpiryFormat.Parse).FirstOrDefault(parsed => parsed is not null) is not { } expiry) return;
            (draft.ExpiryMonth, draft.ExpiryYear) = expiry;
        });

    public static readonly AutofillFieldRole ExpiryMonth = ForCard(name: "expiryMonth", tokens: ["cc-exp-month"],
        suggestedBy: @"month\b|monat\b|\bmois\b|\bmes\b|\bmese\b|maand\b|^mm$|\bexp\w*\s?mo\b",
        spell: (card, _, _) => CalendarMonth.Numbered(card.ExpiryMonth)?.Spellings ?? [],
        capture: (draft, spellings) => draft.ExpiryMonth = spellings.Select(CalendarMonth.Named).OfType<CalendarMonth>().FirstOrDefault()?.Number);

    public static readonly AutofillFieldRole ExpiryYear = ForCard(name: "expiryYear", tokens: ["cc-exp-year"],
        suggestedBy: @"year\b|jahr\b|\bannee\b|\bano\b|\banno\b|jaar\b|^(yy|yyyy|jj|jjjj|aa|aaaa)$|\bexp\w*\s?(yr|yy)\b",
        spell: (card, field, _) => {
            int digits = ExpiryFormat.YearDigitsOf(field);
            return [ExpiryFormat.SpellYear(card.ExpiryYear, digits), ExpiryFormat.SpellYear(card.ExpiryYear, digits == 2 ? 4 : 2)];
        },
        capture: (draft, spellings) => draft.ExpiryYear = spellings.Select(ExpiryFormat.Year).FirstOrDefault(year => year is not null));

    /// The security code, filled only from a card that keeps one and never
    /// read from a sent form.
    public static readonly AutofillFieldRole SecurityCode = ForCard(name: "securityCode", tokens: ["cc-csc"],
        suggestedBy: @"\b(cvc|cvv|cvn|csc|cvd|cid|ccv|cvc2|cvv2|cav2)\b|security\s?(code|number|value)|card\s?(verification|identification|code)|verification\s?(value|number)|card\s?pin|prufnummer|prufziffer|pruefnummer|sicherheits\s?code|sicherheitsnummer|cryptogramme|code\s?(de\s?)?securite|codigo\s?(de\s?)?seguridad|codice\s?(di\s?)?sicurezza|codice\s?di\s?verifica|beveiligingscode|kaartverificatie|codigo\s?(de\s?)?seguranca|cod\s?seguranca",
        spell: (card, _, _) => [card.SecurityCode], capture: (_, _) => { });

    public static IReadOnlyList<AutofillFieldRole> All { get; } = [
        FullName, GivenName, AdditionalName, FamilyName, Organization, StreetAddress, AddressLine1, AddressLine2, AddressLine3,
        HouseNumber, City, Region, PostalCode, Country, Phone, Email, CardholderName, CardholderGivenName, CardholderFamilyName,
        CardNumber, Expiry, ExpiryMonth, ExpiryYear, SecurityCode
    ];

    /// The roles in the order a field's names are tried for them, the most
    /// specific first: the card's before the address's, contact details, the
    /// postal code, city, country and region before the street, whose words
    /// their fields often bear too, and a person's name last of all.
    private static readonly IReadOnlyList<AutofillFieldRole> Inference = [
        SecurityCode, ExpiryMonth, ExpiryYear, Expiry, CardholderGivenName, CardholderFamilyName, CardholderName, CardNumber, Email,
        Phone, Organization, PostalCode, City, Country, Region, AddressLine3, AddressLine2, HouseNumber, StreetAddress, AddressLine1,
        AdditionalName, GivenName, FamilyName, FullName
    ];

    /// What a page calls a field that autofill leaves alone, whatever else
    /// its names say: a search, a code or voucher, an account's name or
    /// password, a birthday, a tax number, a note or a quantity.
    private static readonly Regex Unrelated = Pattern(
        @"\b(search|suche|suchen|recherche|rechercher|buscar|busca|cerca|zoek|zoeken|pesquisa|pesquisar|query|q)\b|coupon|promo|voucher|gutschein|rabatt|discount|gift\s?card|geschenk|captcha|user\s?name|username|benutzer|\blogin\b|nickname|usuario|utilisateur|identifiant|utente|gebruiker|password|passwort|kennwort|mot\s?de\s?passe|contrasena|birth|\bbday\b|geburt|naissance|nacimiento|nascita|geboorte|nascimento|segundo\s?apellido|second\s?(last\s?name|surname)|\bvat\b|tax\s?id|steuer|\bust\s?id|\btva\b|\biva\b|\bnif\b|\bcpf\b|\bcnpj\b|\bbtw\b|comment|kommentar|anmerkung|bemerkung|commentaire|comentario|commento|opmerking|\bnotes?\b|instruction|quantity|\bmenge\b|anzahl|quantite|cantidad|quantita|aantal|quantidade");

    /// A card number placeholder shown in groups, such as `1234 1234 1234
    /// 1234`, and the character between them.
    private static readonly Regex GroupedPlaceholder = new(@"^\s*[0-9x•*·#]{4}(?<separator>[ -])[0-9x•*·#]{4}",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    #endregion

    #region Variables

    public string Name { get; }

    /// The kind of section a field of the role belongs to.
    public AutofillSectionKind Kind { get; }

    /// Whether a section may hold several fields of the role: a phone number
    /// and a mobile one, an email address and its confirmation, or a card
    /// number split across fields. A second field of any other role starts a
    /// section of its own.
    internal bool Repeats { get; }

    /// The autocomplete field names that declare the role.
    private readonly IReadOnlyList<string> tokens;

    /// A phrase that names the role outright, which wins over every other
    /// role's words.
    private readonly Regex? definedBy;

    /// The words that suggest the role.
    private readonly Regex? suggestedBy;

    /// The input type that suggests the role without its names, and whether
    /// it does so whatever its names say.
    private readonly FormInputType? impliedBy;

    private readonly bool impliedOverNames;

    /// Whether a field may have the role at all, such as only a text area a
    /// whole street address.
    private readonly Func<FormField, bool> accepts;

    /// The role a field read as having this one has, given its options.
    private readonly Func<FormField, AutofillFieldRole> refine;

    /// The ways of spelling the role's value for a field of a fill, in order
    /// of preference.
    private readonly Func<FormField, AutofillFilling, IEnumerable<string?>> spell;

    /// What a value sent from a field of the role, read as its spellings,
    /// adds to a draft.
    private readonly Action<AutofillDraft, IReadOnlyList<string>> capture;

    #endregion

    #region Constructors

    private AutofillFieldRole(string name, AutofillSectionKind kind, IReadOnlyList<string> tokens, string? definedBy, string? suggestedBy,
        FormInputType? impliedBy, bool impliedOverNames, bool repeats, Func<FormField, bool>? accepts,
        Func<FormField, AutofillFieldRole>? refine, Func<FormField, AutofillFilling, IEnumerable<string?>> spell,
        Action<AutofillDraft, IReadOnlyList<string>> capture) {
        Name = name;
        Kind = kind;
        Repeats = repeats;
        this.tokens = tokens;
        this.definedBy = definedBy is null ? null : Pattern(definedBy);
        this.suggestedBy = suggestedBy is null ? null : Pattern(suggestedBy);
        this.impliedBy = impliedBy;
        this.impliedOverNames = impliedOverNames;
        this.accepts = accepts ?? (_ => true);
        this.refine = refine ?? (_ => this);
        this.spell = spell;
        this.capture = capture;
    }

    /// A role of an address section, which spells its value from the address
    /// a fill writes.
    private static AutofillFieldRole ForAddress(string name, IReadOnlyList<string> tokens, string? suggestedBy,
        Func<AddressRecord, FormField, AutofillFilling, IEnumerable<string?>> spell, Action<AutofillDraft, IReadOnlyList<string>> capture,
        string? definedBy = null, FormInputType? impliedBy = null, bool impliedOverNames = false, bool repeats = false,
        Func<FormField, bool>? accepts = null) =>
        new(name, AutofillSectionKind.Address, tokens, definedBy, suggestedBy, impliedBy, impliedOverNames, repeats, accepts, null,
            (field, filling) => filling.Address is { } address ? spell(address, field, filling) : [], capture);

    /// A role of a card section, which spells its value from the card a fill
    /// writes.
    private static AutofillFieldRole ForCard(string name, IReadOnlyList<string> tokens, string? suggestedBy,
        Func<CardRecord, FormField, AutofillFilling, IEnumerable<string?>> spell, Action<AutofillDraft, IReadOnlyList<string>> capture,
        bool repeats = false, Func<FormField, AutofillFieldRole>? refine = null) =>
        new(name, AutofillSectionKind.Card, tokens, null, suggestedBy, null, false, repeats, null, refine,
            (field, filling) => filling.Card is { } card ? spell(card, field, filling) : [], capture);

    #endregion

    #region Actions - Lookup

    public static AutofillFieldRole? Named(string? name) => All.FirstOrDefault(role => role.Name == name);

    #endregion

    #region Actions - Reading

    /// How `field` reads: the role the page declares in its autocomplete
    /// attribute, with the section and shipping or billing mode it declares,
    /// or else the role its type and names suggest. A field the page declares
    /// to hold something else, or whose names say it is unrelated, reads as
    /// nothing.
    internal static (AutofillFieldReading Reading, string? Scope)? Read(FormField field) {
        ArgumentNullException.ThrowIfNull(field);
        var attribute = AutocompleteAttribute.Read(field.Autocomplete);
        if (attribute.FieldName is { } fieldName && All.FirstOrDefault(role => role.tokens.Contains(fieldName)) is { } declared)
            return (new(field.Index, declared, IsDeclared: true), attribute.Scope);
        if (attribute.NamesOtherField) return null;
        return Inferred(field) is { } inferred ? (new(field.Index, inferred, IsDeclared: false), attribute.Scope) : null;
    }

    /// The role `field`'s type and names suggest: an email address for an
    /// email field whatever its names say, else a role whose defining phrase
    /// it bears, else the first in `Inference` order whose words it bears,
    /// else the one its type suggests, such as a phone number for a telephone
    /// field that names nothing else. A card number or postal code in a
    /// telephone field, as pages use for a numeric keyboard, is still one.
    private static AutofillFieldRole? Inferred(FormField field) {
        var names = field.FoldedNames;
        if (names.Any(name => name.Matches(Unrelated))) return null;
        var implied = All.FirstOrDefault(role => role.impliedBy == field.InputType);
        if (implied is { impliedOverNames: true }) return implied;
        var named = Inference.FirstOrDefault(role => role.definedBy is { } phrase && role.Bears(field, names, phrase))
            ?? Inference.FirstOrDefault(role => role.suggestedBy is { } words && role.Bears(field, names, words));
        return (named ?? implied)?.refine(field);
    }

    private bool Bears(FormField field, IReadOnlyList<FoldedText> names, Regex pattern) =>
        accepts(field) && names.Any(name => name.Matches(pattern));

    /// The part of the expiry a select read as an expiry takes, by its
    /// options: the month, the year, or the whole expiry.
    private static AutofillFieldRole ExpiryPart(FormField field) =>
        field.ChoosesMonth ? ExpiryMonth : field.ChoosesYear ? ExpiryYear : Expiry;

    private static Regex Pattern(string pattern) => new(pattern, RegexOptions.CultureInvariant);

    #endregion

    #region Actions - Filling

    /// The ways of spelling this role's value for `field` in `filling`, in
    /// order of preference; none when the fill writes nothing of the role.
    internal IEnumerable<string?> Spellings(FormField field, AutofillFilling filling) => spell(field, filling);

    /// Adds what `spellings`, a value sent from a field of this role, says to
    /// `draft`.
    internal void Capture(AutofillDraft draft, IReadOnlyList<string> spellings) {
        if (spellings.Count > 0) capture(draft, spellings);
    }

    /// A person's whole name, or the family name alone where the section
    /// asks for the given name and then only "Name", as a German form that
    /// asks for the Vorname and the Name does.
    private static IEnumerable<string?> SpellFullName(AddressRecord address, FormField field, AutofillFilling filling) =>
        filling.Has(GivenName) && !filling.Has(FamilyName) ? [address.FamilyName] : [address.FullName];

    private static void CaptureFullName(AutofillDraft draft, IReadOnlyList<string> spellings) {
        if (draft.Has(GivenName) && !draft.Has(FamilyName)) draft.FamilyName = spellings[0];
        else draft.FullName = spellings[0];
    }

    /// The street address: its first line where the section has fields for
    /// the others, its lines on lines of their own in a text area, or joined
    /// by commas.
    private static IEnumerable<string?> SpellStreetAddress(AddressRecord address, FormField field, AutofillFilling filling) =>
        filling.Has(AddressLine2) || filling.Has(AddressLine3) ? [Line(address, 0)]
            : [string.Join(field.InputType.SpansLines ? "\n" : ", ", address.Lines)];

    /// The street lines a street address field sent: its first line where
    /// the section has fields for the others, or else each of its lines, the
    /// last taking any beyond the lines a record keeps.
    private static void CaptureStreetAddress(AutofillDraft draft, IReadOnlyList<string> spellings) {
        if (draft.Has(AddressLine2) || draft.Has(AddressLine3)) {
            draft.StreetLines[0] = spellings[0];
            return;
        }
        var lines = spellings[0].Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        int last = draft.StreetLines.Length - 1;
        for (int place = 0; place < last; place++) draft.StreetLines[place] = lines.ElementAtOrDefault(place);
        draft.StreetLines[last] = string.Join(", ", lines.Skip(last));
    }

    /// The first street line, without its house number where the section asks
    /// for that apart, and with the lines after it where it has no field for
    /// them.
    private static IEnumerable<string?> SpellFirstLine(AddressRecord address, FormField field, AutofillFilling filling) {
        string first = filling.Has(HouseNumber) ? StreetLine.Split(Line(address, 0)).Street : Line(address, 0);
        return [filling.Has(AddressLine2) ? first : string.Join(", ", address.Lines.Skip(1).Prepend(first).Where(line => line.Length > 0))];
    }

    /// The second street line, with the third where the section has no field
    /// for it.
    private static IEnumerable<string?> SpellSecondLine(AddressRecord address, FormField field, AutofillFilling filling) =>
        [filling.Has(AddressLine3) ? Line(address, 1) : string.Join(", ", address.Lines.Skip(1))];

    /// The street line of `address` at `place`, or empty.
    private static string Line(AddressRecord address, int place) => address.Lines.ElementAtOrDefault(place) ?? "";

    /// The spellings of `number` for `field`: its part of the digits when the
    /// section splits the number across fields, each taking as many digits as
    /// it holds and the last the rest; otherwise its groups where the field's
    /// placeholder shows groups, then its digits.
    private static IEnumerable<string?> NumberSpellings(Domain.CardNumber number, FormField field, AutofillFilling filling) {
        var parts = filling.FieldsOf(CardNumber);
        if (parts.Count < 2)
            return GroupedPlaceholder.Match(field.Placeholder) is { Success: true } grouped
                ? [number.Grouped(grouped.Groups["separator"].Value), number.Digits] : [number.Digits];
        int start = 0;
        foreach (var part in parts) {
            int size = part.Index == parts[^1].Index ? number.Digits.Length : part.MaxLength ?? CardNumberPart;
            if (part.Index == field.Index)
                return start < number.Digits.Length ? [number.Digits.Substring(start, Math.Min(size, number.Digits.Length - start))] : [];
            start += size;
        }
        return [];
    }

    #endregion
}
