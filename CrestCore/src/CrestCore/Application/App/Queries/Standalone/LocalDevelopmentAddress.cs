using System.Net;
using System.Net.Sockets;

using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Whether an address is the person's own development work, so developer mode
/// turns on by itself: a local file, a single-label host, a loopback, private
/// or link-local address, or a name reserved for one device or one local
/// network (see `AddressResolution`). The address arrives as the scheme and
/// host the platform's own parser reported. It reads no state, so a page asks
/// it without an app.
public sealed record LocalDevelopmentAddress(string? Scheme, string? Host) : StandaloneQuery<DevelopmentAddressVerdict> {
    #region Variables

    internal bool IsLocal {
        get {
            if (string.Equals(Scheme, "file", StringComparison.OrdinalIgnoreCase)) return true;
            string host = (Host ?? "").Trim('.');
            if (host.Length == 0) return false;
            if (Address(host) is { } address) return IsLocalAddress(address);
            // A dotted host is local when it is a reserved name, such as
            // `home.arpa`, or a name under one.
            return !host.Contains('.') || AddressResolution.IsLocalName("." + host);
        }
    }

    #endregion

    #region Actions - Answering

    internal override DevelopmentAddressVerdict Answer(StandaloneContext context) => new(IsLocal);

    /// The IP address `host` spells: IPv4 only as four dotted numbers, and
    /// IPv6 with or without brackets, its zone set aside.
    private static IPAddress? Address(string host) {
        if (host.Contains(':')) {
            string unzoned = host.Trim('[', ']').Split('%')[0];
            return IPAddress.TryParse(unzoned, out var v6) && v6.AddressFamily == AddressFamily.InterNetworkV6 ? v6 : null;
        }
        bool dotted = host.Split('.').Length == 4 && host.All(c => char.IsAsciiDigit(c) || c == '.');
        return dotted && IPAddress.TryParse(host, out var v4) ? v4 : null;
    }

    /// Whether `address` is unspecified, loopback, private or link-local.
    private static bool IsLocalAddress(IPAddress address) {
        if (address.IsIPv4MappedToIPv6) return IsLocalAddress(address.MapToIPv4());
        byte[] bytes = address.GetAddressBytes();
        if (address.AddressFamily == AddressFamily.InterNetwork)
            return bytes.All(b => b == 0) || bytes[0] is 10 or 127 || (bytes[0] == 169 && bytes[1] == 254)
                || (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 172 && bytes[1] is >= 16 and <= 31);
        return address.Equals(IPAddress.IPv6Any) || address.Equals(IPAddress.IPv6Loopback) || (bytes[0] & 0xFE) == 0xFC
            || (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80);
    }

    #endregion
}
