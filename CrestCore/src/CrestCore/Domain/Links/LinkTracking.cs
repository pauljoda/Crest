namespace CrestCore.Domain;

#region Types

/// An item page a site answers by its identity alone: a path holding one of
/// `Markers` and then, as a whole segment, an identity of `IdentityLength`
/// ASCII letters and digits. Its address becomes https, its host, `Path` and
/// the identity, with only the parameters `Keeps` names, which choose what
/// the page offers rather than track who followed it, and no fragment.
internal sealed record ItemPage(IReadOnlyList<string> Markers, int IdentityLength, string Path, IReadOnlyList<string> Keeps);

#endregion

/// What a link carries only to tell who followed it, which a copied link
/// leaves out. A redirect wrapper gives way to its destination; a site's
/// address rewrites a filter cannot express, such as an item page's slug or a
/// trailing path segment, are each a member here; and the query parameters
/// that track go by `$removeparam` filters: Crest's own baseline, and the
/// maintained list the device downloads.
internal sealed class LinkTracking {
    #region Static Variables

    /// Crest's own parameter filters, which apply with or without the
    /// maintained list: campaign tags, ad-click identifiers, newsletter and
    /// marketing-mail identifiers, analytics cookies carried in the address
    /// and share attribution on every site, then the parameters of sites
    /// people share most.
    public const string BaselineFilters = """
        ! Title: Crest link tracking baseline
        $removeparam=/^utm_/i
        $removeparam=fbclid
        $removeparam=gclid
        $removeparam=gclsrc
        $removeparam=dclid
        $removeparam=gbraid
        $removeparam=wbraid
        $removeparam=msclkid
        $removeparam=yclid
        $removeparam=twclid
        $removeparam=ttclid
        $removeparam=li_fat_id
        $removeparam=igshid
        $removeparam=igsh
        $removeparam=mc_cid
        $removeparam=mc_eid
        $removeparam=_hsenc
        $removeparam=_hsmi
        $removeparam=__hssc
        $removeparam=__hstc
        $removeparam=__hsfp
        $removeparam=hsCtaTracking
        $removeparam=mkt_tok
        ! Marketo's unsubscribe links need their token.
        @@unsubscribe$removeparam=mkt_tok
        $removeparam=oly_anon_id
        $removeparam=oly_enc_id
        $removeparam=rb_clickid
        $removeparam=s_cid
        $removeparam=vero_conv
        $removeparam=vero_id
        $removeparam=wickedid
        $removeparam=_openstat
        $removeparam=ml_subscriber
        $removeparam=ml_subscriber_hash
        $removeparam=srsltid
        $removeparam=_ga
        $removeparam=_gl
        $removeparam=mibextid
        $removeparam=epik
        $removeparam=ref_src
        ! Amazon: referral, placement, search-rank and affiliate parameters
        $removeparam=ref,domain=amazon.*
        $removeparam=ref_,domain=amazon.*
        $removeparam=/^pf_rd_/,domain=amazon.*
        $removeparam=/^pd_rd_/,domain=amazon.*
        $removeparam=qid,domain=amazon.*
        $removeparam=sr,domain=amazon.*
        $removeparam=crid,domain=amazon.*
        $removeparam=sprefix,domain=amazon.*
        $removeparam=dib,domain=amazon.*
        $removeparam=dib_tag,domain=amazon.*
        $removeparam=content-id,domain=amazon.*
        $removeparam=psc,domain=amazon.*
        $removeparam=th,domain=amazon.*
        $removeparam=linkCode,domain=amazon.*
        $removeparam=linkId,domain=amazon.*
        $removeparam=tag,domain=amazon.*
        $removeparam=ascsubtag,domain=amazon.*
        $removeparam=spIA,domain=amazon.*
        $removeparam=_encoding,domain=amazon.*
        ! YouTube
        ||youtube.com^$removeparam=si
        ||youtube.com^$removeparam=feature
        ||youtube.com^$removeparam=pp
        ||youtube.com^$removeparam=ab_channel
        ||youtu.be^$removeparam=si
        ||youtu.be^$removeparam=feature
        ||youtu.be^$removeparam=pp
        ||youtu.be^$removeparam=ab_channel
        ! Spotify
        ||open.spotify.com^$removeparam=si
        ||open.spotify.com^$removeparam=context
        ||open.spotify.com^$removeparam=nd
        ! X
        ||x.com^$removeparam=s
        ||x.com^$removeparam=t
        ||x.com^$removeparam=ref_url
        ||twitter.com^$removeparam=s
        ||twitter.com^$removeparam=t
        ||twitter.com^$removeparam=ref_url
        ! Facebook, whose `__cft__` carries an index, as in `__cft__[0]`
        ||facebook.com^$removeparam=__tn__
        ||facebook.com^$removeparam=/^__cft__(\[[^\]]*\])?=/
        ||facebook.com^$removeparam=rdid
        ||facebook.com^$removeparam=share_url
        ! LinkedIn
        ||linkedin.com^$removeparam=trk
        ||linkedin.com^$removeparam=trkInfo
        ||linkedin.com^$removeparam=trackingId
        ||linkedin.com^$removeparam=lipi
        ||linkedin.com^$removeparam=refId
        ||linkedin.com^$removeparam=midToken
        ||linkedin.com^$removeparam=midSig
        ||linkedin.com^$removeparam=eid
        ||linkedin.com^$removeparam=otpToken
        ! TikTok
        ||tiktok.com^$removeparam=is_from_webapp
        ||tiktok.com^$removeparam=sender_device
        ||tiktok.com^$removeparam=sender_web_id
        ||tiktok.com^$removeparam=_r
        ||tiktok.com^$removeparam=_t
        ||tiktok.com^$removeparam=is_copy_url
        ||tiktok.com^$removeparam=share_app_id
        ||tiktok.com^$removeparam=share_link_id
        ||tiktok.com^$removeparam=social_sharing
        ||tiktok.com^$removeparam=tt_from
        ||tiktok.com^$removeparam=u_code
        ! Reddit
        ||reddit.com^$removeparam=share_id
        ||reddit.com^$removeparam=rdt
        ||reddit.com^$removeparam=ref_source
        ! Google results pages only: what the query, its filters and its page
        ! leave are how the search was typed, timed and sized
        ||google.*/search?$removeparam=ved
        ||google.*/search?$removeparam=ei
        ||google.*/search?$removeparam=sca_esv
        ||google.*/search?$removeparam=sxsrf
        ||google.*/search?$removeparam=gs_lcrp
        ||google.*/search?$removeparam=gs_lp
        ||google.*/search?$removeparam=gs_ssp
        ||google.*/search?$removeparam=oq
        ||google.*/search?$removeparam=aqs
        ||google.*/search?$removeparam=sourceid
        ||google.*/search?$removeparam=ie
        ||google.*/search?$removeparam=uact
        ||google.*/search?$removeparam=iflsig
        ||google.*/search?$removeparam=sclient
        ||google.*/search?$removeparam=bih
        ||google.*/search?$removeparam=biw
        ||google.*/search?$removeparam=rlz
        ||google.*/search?$removeparam=client
        ||google.*/search?$removeparam=source
        ||google.*/search?$removeparam=sa
        ||google.*/search?$removeparam=dpr
        ||google.*/search?$removeparam=fbs
        ||google.*/search?$removeparam=stick
        ||google.*/search?$removeparam=uds
        ||google.*/search?$removeparam=sei
        ! Bing
        ||bing.com^$removeparam=form
        ||bing.com^$removeparam=cvid
        ||bing.com^$removeparam=pq
        ||bing.com^$removeparam=qs
        ||bing.com^$removeparam=sc
        ||bing.com^$removeparam=sk
        ||bing.com^$removeparam=sp
        ||bing.com^$removeparam=ghc
        ||bing.com^$removeparam=lq
        ||bing.com^$removeparam=ghsh
        ||bing.com^$removeparam=ghacc
        """;

    private static readonly ParameterFilterList Baseline = ParameterFilterList.Read(BaselineFilters);

    /// A product page becomes its `/dp/` address, keeping `smid`, which picks
    /// the seller whose offer it shows; any other page loses its `/ref=`
    /// segment.
    public static readonly LinkTracking Amazon = new(site: "amazon.*", trailingSegment: "ref=",
        item: new(["/dp/", "/gp/product/", "/gp/aw/d/"], IdentityLength: 10, Path: "/dp/", Keeps: ["smid"]));

    public static IReadOnlyList<LinkTracking> All { get; } = [Amazon];

    #endregion

    #region Variables

    /// The site the member rewrites addresses of.
    private readonly SiteDomain site;
    private readonly ItemPage? item;
    /// How a last path segment the member removes starts.
    private readonly string? trailingSegment;

    #endregion

    #region Constructors

    private LinkTracking(string site, string? trailingSegment = null, ItemPage? item = null) {
        this.site = new(site);
        this.item = item;
        this.trailingSegment = trailingSegment;
    }

    #endregion

    #region Actions - Cleaning

    /// The address Crest copies for `url`: the destination of the redirect
    /// wrappers it is wrapped in, rewritten by the members for its site, and
    /// without the query parameters Crest's baseline and the `maintained`
    /// list remove. Every other parameter keeps its spelling and order, the
    /// `?` goes when none is left, and the fragment stays unless an item
    /// page's address replaces the whole. An address that is not http or
    /// https, or does not read, comes back as it is.
    public static string Cleaned(string url, ParameterFilterList? maintained) {
        ArgumentNullException.ThrowIfNull(url);
        string destination = LinkRedirect.Unwrapped(url);
        if (LinkAddress.Read(destination) is not { } address) return destination;
        foreach (var tracking in All.Where(tracking => tracking.site.Holds(address.Host)))
            address = LinkAddress.Read(tracking.Rewritten(address)) ?? address;
        return ParameterFilterList.Cleaned(address, maintained is null ? [Baseline] : [Baseline, maintained]);
    }

    /// `address` as the member rewrites it: its item page's address, or
    /// without the last segment the member removes.
    private string Rewritten(LinkAddress address) {
        if (ItemPath(address.Path) is { } itemPath) {
            string[] kept = [.. address.Parameters.Where(parameter => item!.Keeps.Contains(parameter.Name)).Select(parameter => parameter.Spelling)];
            return kept.Length == 0 ? $"https://{address.Host}{itemPath}" : $"https://{address.Host}{itemPath}?{string.Join('&', kept)}";
        }
        string trimmed = Trimming(address.Path);
        return trimmed == address.Path ? address.Spelling : address.Spelled(trimmed, address.Parameters);
    }

    /// The path an item page at `pagePath` becomes, or null when the member
    /// names no item page or `pagePath` is not one.
    private string? ItemPath(string pagePath) {
        if (item is null) return null;
        foreach (string marker in item.Markers) {
            int start = pagePath.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
            if (start < 0) continue;
            string rest = pagePath[(start + marker.Length)..];
            int end = rest.IndexOf('/', StringComparison.Ordinal);
            string identity = end < 0 ? rest : rest[..end];
            if (identity.Length == item.IdentityLength && identity.All(char.IsAsciiLetterOrDigit)) return $"{item.Path}{identity}";
        }
        return null;
    }

    /// `rawPath` without a last segment the member removes; a path left empty
    /// is `/`.
    private string Trimming(string rawPath) {
        int slash = rawPath.LastIndexOf('/');
        if (trailingSegment is null || slash < 0 || !rawPath[(slash + 1)..].StartsWith(trailingSegment, StringComparison.OrdinalIgnoreCase))
            return rawPath;
        return slash == 0 ? "/" : rawPath[..slash];
    }

    #endregion
}
