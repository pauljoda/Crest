namespace CrestCore.Domain;

#region Types

/// A region of a country, as its first address level: its code, such as `CA`
/// for California or `BY` for Bavaria, and the names forms spell it with.
internal sealed record Region(string Code, IReadOnlyList<string> Names);

#endregion

/// A country as forms spell it: its ISO 3166-1 alpha-2 and alpha-3 codes, its
/// English name and the names it goes by in German, French, Spanish, Italian,
/// Dutch and Portuguese, and for the United States, Canada, Australia and
/// Germany its regions. The core carries its own table, since it runs without
/// the system's locale data.
internal sealed class Country {
    #region Static Variables

    /// One row per country: its alpha-2 and alpha-3 codes, its English name,
    /// then any other names, separated by bars.
    private static readonly string[] Rows = [
        "AD|AND|Andorra|Andorre",
        "AE|ARE|United Arab Emirates|Vereinigte Arabische Emirate|Émirats arabes unis|Emiratos Árabes Unidos|Emirati Arabi Uniti|Verenigde Arabische Emiraten|Emirados Árabes Unidos|UAE",
        "AF|AFG|Afghanistan|Afganistán|Afeganistão",
        "AG|ATG|Antigua and Barbuda|Antigua und Barbuda|Antigua-et-Barbuda|Antigua y Barbuda",
        "AI|AIA|Anguilla",
        "AL|ALB|Albania|Albanien|Albanie|Albanië|Albânia",
        "AM|ARM|Armenia|Armenien|Arménie|Armenië|Arménia|Armênia",
        "AO|AGO|Angola",
        "AQ|ATA|Antarctica|Antarktis|Antarctique|Antártida|Antartide|Antarctica",
        "AR|ARG|Argentina|Argentinien|Argentine|Argentinië",
        "AS|ASM|American Samoa|Amerikanisch-Samoa|Samoa américaines|Samoa Americana",
        "AT|AUT|Austria|Österreich|Autriche|Oostenrijk|Áustria",
        "AU|AUS|Australia|Australien|Australie|Australië|Austrália",
        "AW|ABW|Aruba",
        "AX|ALA|Åland Islands|Åland|Ålandinseln|Îles Åland|Islas Åland",
        "AZ|AZE|Azerbaijan|Aserbaidschan|Azerbaïdjan|Azerbaiyán|Azerbaigian|Azerbeidzjan|Azerbaijão",
        "BA|BIH|Bosnia and Herzegovina|Bosnien und Herzegowina|Bosnie-Herzégovine|Bosnia y Herzegovina|Bosnia ed Erzegovina|Bosnië en Herzegovina|Bósnia e Herzegovina",
        "BB|BRB|Barbados",
        "BD|BGD|Bangladesh|Bangladesch|Bangladés",
        "BE|BEL|Belgium|Belgien|Belgique|Bélgica|Belgio|België",
        "BF|BFA|Burkina Faso",
        "BG|BGR|Bulgaria|Bulgarien|Bulgarie|Bulgarije|Bulgária",
        "BH|BHR|Bahrain|Bahreïn|Baréin|Bahrein",
        "BI|BDI|Burundi",
        "BJ|BEN|Benin|Bénin",
        "BL|BLM|Saint Barthélemy|Saint-Barthélemy",
        "BM|BMU|Bermuda|Bermudes",
        "BN|BRN|Brunei|Brunei Darussalam",
        "BO|BOL|Bolivia|Bolivien|Bolivie|Bolívia",
        "BQ|BES|Caribbean Netherlands|Bonaire, Sint Eustatius and Saba|Karibische Niederlande|Pays-Bas caribéens|Caribisch Nederland",
        "BR|BRA|Brazil|Brasilien|Brésil|Brasil|Brasile|Brazilië",
        "BS|BHS|Bahamas",
        "BT|BTN|Bhutan|Bhoutan|Bután",
        "BV|BVT|Bouvet Island|Bouvetinsel|Île Bouvet",
        "BW|BWA|Botswana",
        "BY|BLR|Belarus|Weißrussland|Biélorussie|Bielorrusia|Bielorussia|Wit-Rusland|Bielorrússia",
        "BZ|BLZ|Belize|Belice",
        "CA|CAN|Canada|Kanada|Canadá",
        "CC|CCK|Cocos (Keeling) Islands|Kokosinseln|Îles Cocos",
        "CD|COD|Democratic Republic of the Congo|Congo (DRC)|Congo, Democratic Republic of the|Demokratische Republik Kongo|République démocratique du Congo|República Democrática del Congo|Repubblica Democratica del Congo|Democratische Republiek Congo|República Democrática do Congo",
        "CF|CAF|Central African Republic|Zentralafrikanische Republik|République centrafricaine|República Centroafricana|Repubblica Centrafricana|Centraal-Afrikaanse Republiek|República Centro-Africana",
        "CG|COG|Republic of the Congo|Congo|Congo-Brazzaville|Republik Kongo|République du Congo|República del Congo|Repubblica del Congo|Republiek Congo|República do Congo",
        "CH|CHE|Switzerland|Schweiz|Suisse|Suiza|Svizzera|Zwitserland|Suíça",
        "CI|CIV|Côte d’Ivoire|Côte d'Ivoire|Ivory Coast|Elfenbeinküste|Costa de Marfil|Costa d'Avorio|Ivoorkust|Costa do Marfim",
        "CK|COK|Cook Islands|Cookinseln|Îles Cook|Islas Cook",
        "CL|CHL|Chile|Chili|Cile",
        "CM|CMR|Cameroon|Kamerun|Cameroun|Camerún|Camerun|Kameroen|Camarões",
        "CN|CHN|China|Chine|Cina",
        "CO|COL|Colombia|Kolumbien|Colombie|Colômbia",
        "CR|CRI|Costa Rica",
        "CU|CUB|Cuba|Kuba",
        "CV|CPV|Cape Verde|Cabo Verde|Kap Verde|Cap-Vert|Capo Verde|Kaapverdië",
        "CW|CUW|Curaçao",
        "CX|CXR|Christmas Island|Weihnachtsinsel|Île Christmas",
        "CY|CYP|Cyprus|Zypern|Chypre|Chipre|Cipro",
        "CZ|CZE|Czechia|Czech Republic|Tschechien|Tschechische Republik|Tchéquie|République tchèque|Chequia|República Checa|Cechia|Repubblica Ceca|Tsjechië|Chéquia|República Tcheca",
        "DE|DEU|Germany|Deutschland|Allemagne|Alemania|Germania|Duitsland|Alemanha",
        "DJ|DJI|Djibouti|Dschibuti|Yibuti|Gibuti",
        "DK|DNK|Denmark|Dänemark|Danemark|Dinamarca|Danimarca|Denemarken",
        "DM|DMA|Dominica|Dominique",
        "DO|DOM|Dominican Republic|Dominikanische Republik|République dominicaine|República Dominicana|Repubblica Dominicana|Dominicaanse Republiek",
        "DZ|DZA|Algeria|Algerien|Algérie|Argelia|Algerije|Argélia",
        "EC|ECU|Ecuador|Équateur|Equador",
        "EE|EST|Estonia|Estland|Estonie|Estónia|Estônia",
        "EG|EGY|Egypt|Ägypten|Égypte|Egipto|Egitto|Egypte|Egito",
        "EH|ESH|Western Sahara|Westsahara|Sahara occidental",
        "ER|ERI|Eritrea|Érythrée",
        "ES|ESP|Spain|Spanien|Espagne|España|Spagna|Spanje|Espanha",
        "ET|ETH|Ethiopia|Äthiopien|Éthiopie|Etiopía|Etiopia|Ethiopië",
        "FI|FIN|Finland|Finnland|Finlande|Finlandia|Finlândia",
        "FJ|FJI|Fiji|Fidschi|Fidji",
        "FK|FLK|Falkland Islands|Falklandinseln|Îles Malouines|Islas Malvinas",
        "FM|FSM|Micronesia|Mikronesien|Micronésie",
        "FO|FRO|Faroe Islands|Färöer|Îles Féroé|Islas Feroe|Isole Fær Øer|Faeröer|Ilhas Feroé",
        "FR|FRA|France|Frankreich|Francia|Frankrijk|França",
        "GA|GAB|Gabon|Gabun|Gabón",
        "GB|GBR|United Kingdom|UK|Great Britain|Vereinigtes Königreich|Großbritannien|Royaume-Uni|Grande-Bretagne|Reino Unido|Gran Bretaña|Regno Unito|Gran Bretagna|Verenigd Koninkrijk|Groot-Brittannië|Grã-Bretanha",
        "GD|GRD|Grenada|Grenade",
        "GE|GEO|Georgia|Georgien|Géorgie|Georgië|Geórgia",
        "GF|GUF|French Guiana|Französisch-Guayana|Guyane|Guyane française|Guayana Francesa",
        "GG|GGY|Guernsey|Guernesey",
        "GH|GHA|Ghana",
        "GI|GIB|Gibraltar",
        "GL|GRL|Greenland|Grönland|Groenland|Groenlandia|Groenlândia",
        "GM|GMB|Gambia|Gambie",
        "GN|GIN|Guinea|Guinée|Guinee|Guiné",
        "GP|GLP|Guadeloupe|Guadalupe",
        "GQ|GNQ|Equatorial Guinea|Äquatorialguinea|Guinée équatoriale|Guinea Ecuatorial|Guinea Equatoriale|Equatoriaal-Guinea|Guiné Equatorial",
        "GR|GRC|Greece|Griechenland|Grèce|Grecia|Griekenland|Grécia",
        "GS|SGS|South Georgia and the South Sandwich Islands",
        "GT|GTM|Guatemala",
        "GU|GUM|Guam",
        "GW|GNB|Guinea-Bissau|Guinée-Bissau|Guiné-Bissau",
        "GY|GUY|Guyana",
        "HK|HKG|Hong Kong|Hongkong",
        "HM|HMD|Heard Island and McDonald Islands",
        "HN|HND|Honduras",
        "HR|HRV|Croatia|Kroatien|Croatie|Croacia|Croazia|Kroatië|Croácia",
        "HT|HTI|Haiti|Haïti|Haití",
        "HU|HUN|Hungary|Ungarn|Hongrie|Hungría|Ungheria|Hongarije|Hungria",
        "ID|IDN|Indonesia|Indonesien|Indonésie|Indonesië|Indonésia",
        "IE|IRL|Ireland|Irland|Irlande|Irlanda|Ierland",
        "IL|ISR|Israel|Israël|Israele",
        "IM|IMN|Isle of Man|Île de Man|Isla de Man|Isola di Man|Ilha de Man",
        "IN|IND|India|Indien|Inde|Índia",
        "IO|IOT|British Indian Ocean Territory",
        "IQ|IRQ|Iraq|Irak|Iraque",
        "IR|IRN|Iran|Irán|Irã|Irão",
        "IS|ISL|Iceland|Island|Islande|Islandia|Islanda|IJsland|Islândia",
        "IT|ITA|Italy|Italien|Italie|Italia|Italië|Itália",
        "JE|JEY|Jersey",
        "JM|JAM|Jamaica|Jamaika|Jamaïque",
        "JO|JOR|Jordan|Jordanien|Jordanie|Jordania|Giordania|Jordanië|Jordânia",
        "JP|JPN|Japan|Japon|Japón|Giappone|Japão",
        "KE|KEN|Kenya|Kenia|Quénia|Quênia",
        "KG|KGZ|Kyrgyzstan|Kirgisistan|Kirghizistan|Kirguistán",
        "KH|KHM|Cambodia|Kambodscha|Cambodge|Camboya|Cambogia|Cambodja|Camboja",
        "KI|KIR|Kiribati",
        "KM|COM|Comoros|Komoren|Comores|Comore",
        "KN|KNA|Saint Kitts and Nevis|St. Kitts und Nevis|Saint-Christophe-et-Niévès|San Cristóbal y Nieves",
        "KP|PRK|North Korea|Nordkorea|Corée du Nord|Corea del Norte|Corea del Nord|Noord-Korea|Coreia do Norte",
        "KR|KOR|South Korea|Korea, Republic of|Republic of Korea|Südkorea|Corée du Sud|Corea del Sur|Corea del Sud|Zuid-Korea|Coreia do Sul",
        "KW|KWT|Kuwait|Koweït|Koeweit",
        "KY|CYM|Cayman Islands|Kaimaninseln|Îles Caïmans|Islas Caimán",
        "KZ|KAZ|Kazakhstan|Kasachstan|Kazajistán|Kazakistan|Kazachstan|Cazaquistão",
        "LA|LAO|Laos",
        "LB|LBN|Lebanon|Libanon|Liban|Líbano|Libano",
        "LC|LCA|Saint Lucia|St. Lucia|Sainte-Lucie|Santa Lucía",
        "LI|LIE|Liechtenstein",
        "LK|LKA|Sri Lanka",
        "LR|LBR|Liberia|Libéria",
        "LS|LSO|Lesotho",
        "LT|LTU|Lithuania|Litauen|Lituanie|Lituania|Litouwen|Lituânia",
        "LU|LUX|Luxembourg|Luxemburg|Luxemburgo|Lussemburgo",
        "LV|LVA|Latvia|Lettland|Lettonie|Letonia|Lettonia|Letland|Letónia|Letônia",
        "LY|LBY|Libya|Libyen|Libye|Libia|Libië|Líbia",
        "MA|MAR|Morocco|Marokko|Maroc|Marruecos|Marocco|Marrocos",
        "MC|MCO|Monaco|Mónaco",
        "MD|MDA|Moldova|Moldau|Republik Moldau|Moldavie|Moldavia|Moldavië|Moldávia",
        "ME|MNE|Montenegro|Monténégro",
        "MF|MAF|Saint Martin|Saint-Martin",
        "MG|MDG|Madagascar|Madagaskar",
        "MH|MHL|Marshall Islands|Marshallinseln|Îles Marshall|Islas Marshall",
        "MK|MKD|North Macedonia|Nordmazedonien|Macédoine du Nord|Macedonia del Norte|Macedonia del Nord|Noord-Macedonië|Macedónia do Norte|Macedônia do Norte",
        "ML|MLI|Mali",
        "MM|MMR|Myanmar|Burma",
        "MN|MNG|Mongolia|Mongolei|Mongolie|Mongolië|Mongólia",
        "MO|MAC|Macao|Macau",
        "MP|MNP|Northern Mariana Islands|Nördliche Marianen|Îles Mariannes du Nord",
        "MQ|MTQ|Martinique|Martinica",
        "MR|MRT|Mauritania|Mauretanien|Mauritanie",
        "MS|MSR|Montserrat",
        "MT|MLT|Malta|Malte",
        "MU|MUS|Mauritius|Maurice|Mauricio|Maurizio",
        "MV|MDV|Maldives|Malediven|Maldivas|Maldive",
        "MW|MWI|Malawi",
        "MX|MEX|Mexico|Mexiko|Mexique|México|Messico",
        "MY|MYS|Malaysia|Malaisie|Malasia|Maleisië|Malásia",
        "MZ|MOZ|Mozambique|Mosambik|Mozambico|Moçambique",
        "NA|NAM|Namibia|Namibie|Namíbia",
        "NC|NCL|New Caledonia|Neukaledonien|Nouvelle-Calédonie|Nueva Caledonia",
        "NE|NER|Niger",
        "NF|NFK|Norfolk Island|Norfolkinsel|Île Norfolk",
        "NG|NGA|Nigeria|Nigéria",
        "NI|NIC|Nicaragua",
        "NL|NLD|Netherlands|The Netherlands|Holland|Niederlande|Pays-Bas|Países Bajos|Holanda|Paesi Bassi|Olanda|Nederland|Países Baixos",
        "NO|NOR|Norway|Norwegen|Norvège|Noruega|Norvegia|Noorwegen",
        "NP|NPL|Nepal|Népal",
        "NR|NRU|Nauru",
        "NU|NIU|Niue",
        "NZ|NZL|New Zealand|Neuseeland|Nouvelle-Zélande|Nueva Zelanda|Nuova Zelanda|Nieuw-Zeeland|Nova Zelândia",
        "OM|OMN|Oman|Omán",
        "PA|PAN|Panama|Panamá",
        "PE|PER|Peru|Pérou|Perú|Perù",
        "PF|PYF|French Polynesia|Französisch-Polynesien|Polynésie française|Polinesia Francesa",
        "PG|PNG|Papua New Guinea|Papua-Neuguinea|Papouasie-Nouvelle-Guinée|Papúa Nueva Guinea",
        "PH|PHL|Philippines|Philippinen|Filipinas|Filippine|Filipijnen",
        "PK|PAK|Pakistan|Pakistán|Paquistão",
        "PL|POL|Poland|Polen|Pologne|Polonia|Polónia|Polônia",
        "PM|SPM|Saint Pierre and Miquelon|Saint-Pierre-et-Miquelon",
        "PN|PCN|Pitcairn Islands|Pitcairn",
        "PR|PRI|Puerto Rico|Porto Rico",
        "PS|PSE|Palestine|Palestinian Territories|Palästina|Palestina",
        "PT|PRT|Portugal|Portogallo",
        "PW|PLW|Palau",
        "PY|PRY|Paraguay|Paraguai",
        "QA|QAT|Qatar|Katar|Catar",
        "RE|REU|Réunion|La Réunion|Reunión",
        "RO|ROU|Romania|Rumänien|Roumanie|Rumania|Roemenië|Roménia|Romênia",
        "RS|SRB|Serbia|Serbien|Serbie|Servië|Sérvia",
        "RU|RUS|Russia|Russian Federation|Russland|Russie|Rusia|Rusland|Rússia",
        "RW|RWA|Rwanda|Ruanda",
        "SA|SAU|Saudi Arabia|Saudi-Arabien|Arabie saoudite|Arabia Saudita|Arabia Saudí|Saoedi-Arabië|Arábia Saudita",
        "SB|SLB|Solomon Islands|Salomonen|Îles Salomon|Islas Salomón",
        "SC|SYC|Seychelles|Seychellen",
        "SD|SDN|Sudan|Soudan|Sudán|Sudão",
        "SE|SWE|Sweden|Schweden|Suède|Suecia|Svezia|Zweden|Suécia",
        "SG|SGP|Singapore|Singapur|Singapour|Singapura",
        "SH|SHN|Saint Helena|Saint Helena, Ascension and Tristan da Cunha|Sainte-Hélène",
        "SI|SVN|Slovenia|Slowenien|Slovénie|Eslovenia|Slovenië|Eslovénia|Eslovênia",
        "SJ|SJM|Svalbard and Jan Mayen|Svalbard und Jan Mayen|Svalbard et Jan Mayen",
        "SK|SVK|Slovakia|Slowakei|Slovaquie|Eslovaquia|Slovacchia|Slowakije|Eslováquia",
        "SL|SLE|Sierra Leone|Sierra Leona|Serra Leoa",
        "SM|SMR|San Marino|Saint-Marin",
        "SN|SEN|Senegal|Sénégal",
        "SO|SOM|Somalia|Somalie|Somália",
        "SR|SUR|Suriname|Surinam",
        "SS|SSD|South Sudan|Südsudan|Soudan du Sud|Sudán del Sur|Sud Sudan|Zuid-Soedan|Sudão do Sul",
        "ST|STP|São Tomé and Príncipe|São Tomé und Príncipe|Sao Tomé-et-Principe|Santo Tomé y Príncipe",
        "SV|SLV|El Salvador|Salvador",
        "SX|SXM|Sint Maarten",
        "SY|SYR|Syria|Syrien|Syrie|Siria|Syrië|Síria",
        "SZ|SWZ|Eswatini|Swaziland",
        "TC|TCA|Turks and Caicos Islands|Turks- und Caicosinseln|Îles Turques-et-Caïques|Islas Turcas y Caicos",
        "TD|TCD|Chad|Tschad|Tchad|Ciad|Tsjaad|Chade",
        "TF|ATF|French Southern Territories|Terres australes françaises",
        "TG|TGO|Togo",
        "TH|THA|Thailand|Thaïlande|Tailandia|Thailandia|Tailândia",
        "TJ|TJK|Tajikistan|Tadschikistan|Tadjikistan|Tayikistán",
        "TK|TKL|Tokelau",
        "TL|TLS|Timor-Leste|East Timor|Osttimor|Timor oriental",
        "TM|TKM|Turkmenistan|Turkménistan|Turkmenistán",
        "TN|TUN|Tunisia|Tunesien|Tunisie|Túnez|Tunesië|Tunísia",
        "TO|TON|Tonga",
        "TR|TUR|Turkey|Türkiye|Türkei|Turquie|Turquía|Turchia|Turkije|Turquia",
        "TT|TTO|Trinidad and Tobago|Trinidad und Tobago|Trinité-et-Tobago|Trinidad y Tobago",
        "TV|TUV|Tuvalu",
        "TW|TWN|Taiwan|Taïwan|Taiwán",
        "TZ|TZA|Tanzania|Tansania|Tanzanie|Tanzânia",
        "UA|UKR|Ukraine|Ucrania|Ucraina|Oekraïne|Ucrânia",
        "UG|UGA|Uganda|Ouganda",
        "UM|UMI|United States Minor Outlying Islands",
        "US|USA|United States|United States of America|America|Vereinigte Staaten|Vereinigte Staaten von Amerika|États-Unis|États-Unis d’Amérique|Estados Unidos|Estados Unidos de América|Stati Uniti|Stati Uniti d’America|Verenigde Staten|Verenigde Staten van Amerika|Estados Unidos da América",
        "UY|URY|Uruguay|Uruguai",
        "UZ|UZB|Uzbekistan|Usbekistan|Ouzbékistan|Uzbekistán",
        "VA|VAT|Vatican City|Holy See|Vatikanstadt|Vatican|Ciudad del Vaticano|Città del Vaticano|Vaticaanstad|Vaticano",
        "VC|VCT|Saint Vincent and the Grenadines|St. Vincent und die Grenadinen|Saint-Vincent-et-les-Grenadines|San Vicente y las Granadinas",
        "VE|VEN|Venezuela",
        "VG|VGB|British Virgin Islands|Britische Jungferninseln|Îles Vierges britanniques|Islas Vírgenes Británicas",
        "VI|VIR|U.S. Virgin Islands|Amerikanische Jungferninseln|Îles Vierges des États-Unis|Islas Vírgenes de los Estados Unidos",
        "VN|VNM|Vietnam|Viet Nam|Viêt Nam|Vietnã|Vietname",
        "VU|VUT|Vanuatu",
        "WF|WLF|Wallis and Futuna|Wallis-et-Futuna",
        "WS|WSM|Samoa",
        "XK|XKX|Kosovo",
        "YE|YEM|Yemen|Jemen|Yémen",
        "YT|MYT|Mayotte",
        "ZA|ZAF|South Africa|Südafrika|Afrique du Sud|Sudáfrica|Sudafrica|Zuid-Afrika|África do Sul",
        "ZM|ZMB|Zambia|Sambia|Zambie|Zâmbia",
        "ZW|ZWE|Zimbabwe|Simbabwe|Zimbabue"
    ];

    /// One row per region: its country's alpha-2 code, its own code, then
    /// its names, separated by bars.
    private static readonly string[] RegionRows = [
        "US|AL|Alabama", "US|AK|Alaska", "US|AZ|Arizona", "US|AR|Arkansas", "US|CA|California", "US|CO|Colorado",
        "US|CT|Connecticut", "US|DE|Delaware", "US|DC|District of Columbia|Washington, D.C.", "US|FL|Florida", "US|GA|Georgia",
        "US|HI|Hawaii", "US|ID|Idaho", "US|IL|Illinois", "US|IN|Indiana", "US|IA|Iowa", "US|KS|Kansas", "US|KY|Kentucky",
        "US|LA|Louisiana", "US|ME|Maine", "US|MD|Maryland", "US|MA|Massachusetts", "US|MI|Michigan", "US|MN|Minnesota",
        "US|MS|Mississippi", "US|MO|Missouri", "US|MT|Montana", "US|NE|Nebraska", "US|NV|Nevada", "US|NH|New Hampshire",
        "US|NJ|New Jersey", "US|NM|New Mexico", "US|NY|New York", "US|NC|North Carolina", "US|ND|North Dakota", "US|OH|Ohio",
        "US|OK|Oklahoma", "US|OR|Oregon", "US|PA|Pennsylvania", "US|RI|Rhode Island", "US|SC|South Carolina",
        "US|SD|South Dakota", "US|TN|Tennessee", "US|TX|Texas", "US|UT|Utah", "US|VT|Vermont", "US|VA|Virginia",
        "US|WA|Washington", "US|WV|West Virginia", "US|WI|Wisconsin", "US|WY|Wyoming", "US|AS|American Samoa", "US|GU|Guam",
        "US|MP|Northern Mariana Islands", "US|PR|Puerto Rico", "US|VI|U.S. Virgin Islands|Virgin Islands",
        "US|AA|Armed Forces Americas", "US|AE|Armed Forces Europe", "US|AP|Armed Forces Pacific",
        "CA|AB|Alberta", "CA|BC|British Columbia|Colombie-Britannique", "CA|MB|Manitoba", "CA|NB|New Brunswick|Nouveau-Brunswick",
        "CA|NL|Newfoundland and Labrador|Newfoundland|Terre-Neuve-et-Labrador", "CA|NS|Nova Scotia|Nouvelle-Écosse",
        "CA|NT|Northwest Territories|Territoires du Nord-Ouest", "CA|NU|Nunavut", "CA|ON|Ontario",
        "CA|PE|Prince Edward Island|Île-du-Prince-Édouard", "CA|QC|Quebec|Québec", "CA|SK|Saskatchewan", "CA|YT|Yukon",
        "AU|ACT|Australian Capital Territory", "AU|NSW|New South Wales", "AU|NT|Northern Territory", "AU|QLD|Queensland",
        "AU|SA|South Australia", "AU|TAS|Tasmania", "AU|VIC|Victoria", "AU|WA|Western Australia",
        "DE|BW|Baden-Württemberg", "DE|BY|Bayern|Bavaria|Bavière", "DE|BE|Berlin", "DE|BB|Brandenburg", "DE|HB|Bremen",
        "DE|HH|Hamburg", "DE|HE|Hessen|Hesse", "DE|MV|Mecklenburg-Vorpommern|Mecklenburg-Western Pomerania",
        "DE|NI|Niedersachsen|Lower Saxony|Basse-Saxe", "DE|NW|Nordrhein-Westfalen|North Rhine-Westphalia|Rhénanie-du-Nord-Westphalie",
        "DE|RP|Rheinland-Pfalz|Rhineland-Palatinate|Rhénanie-Palatinat", "DE|SL|Saarland|Sarre", "DE|SN|Sachsen|Saxony|Saxe",
        "DE|ST|Sachsen-Anhalt|Saxony-Anhalt|Saxe-Anhalt", "DE|SH|Schleswig-Holstein", "DE|TH|Thüringen|Thuringia|Thuringe"
    ];

    public static IReadOnlyList<Country> All { get; } = [.. Rows.Select(row => new Country(row.Split('|')))];

    #endregion

    #region Variables

    /// Its ISO 3166-1 alpha-2 code, in capitals.
    public string Code { get; }

    /// Its ISO 3166-1 alpha-3 code, in capitals.
    public string LongCode { get; }

    /// Its names, its English one first.
    public IReadOnlyList<string> Names { get; }

    public IReadOnlyList<Region> Regions { get; }

    /// What a form may spell the country with, the way a person reads it
    /// first: its English name, its codes, then its other names.
    public IReadOnlyList<string> Spellings => [Names[0], Code, LongCode, .. Names.Skip(1)];

    /// Its spellings folded for comparison.
    private readonly IReadOnlyList<FoldedText> folded;

    #endregion

    #region Constructors

    private Country(string[] row) {
        Code = row[0];
        LongCode = row[1];
        Names = row[2..];
        Regions = [.. RegionRows.Select(region => region.Split('|')).Where(region => region[0] == Code)
            .Select(region => new Region(region[1], region[2..]))];
        folded = [.. Spellings.Select(FoldedText.Of)];
    }

    #endregion

    #region Actions - Lookup

    /// The country whose alpha-2 code is `code`, in either case.
    public static Country? Coded(string? code) =>
        All.FirstOrDefault(country => string.Equals(country.Code, code?.Trim(), StringComparison.OrdinalIgnoreCase));

    /// The country `text` names: one of its codes or names, in any case and
    /// with or without diacritics.
    public static Country? Named(string? text) {
        var wanted = FoldedText.Of(text);
        return wanted.IsEmpty ? null : All.FirstOrDefault(country => country.folded.Contains(wanted));
    }

    /// The country's region `text` names, by its code or one of its names.
    public Region? RegionNamed(string? text) {
        var wanted = FoldedText.Of(text);
        return wanted.IsEmpty ? null : Regions.FirstOrDefault(region =>
            FoldedText.Of(region.Code) == wanted || region.Names.Any(name => FoldedText.Of(name) == wanted));
    }

    /// What a form may spell the region `text` with: `text` itself, then the
    /// region's names, its code and its ISO 3166-2 code, such as `US-CA`.
    public IReadOnlyList<string> RegionSpellings(string text) =>
        RegionNamed(text) is { } region ? [text, .. region.Names, region.Code, $"{Code}-{region.Code}"] : [text];

    #endregion
}
