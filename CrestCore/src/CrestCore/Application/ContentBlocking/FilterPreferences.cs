using CrestCore.Contracts;

namespace CrestCore.Application;

/// What the person chose for filtering on this device: the level, the catalog
/// lists turned on or off against what it turns on, the lists added by
/// address, their own filters, and whether copied links leave out their
/// tracking.
internal sealed record FilterPreferences(ContentBlockingLevel Level, IReadOnlyDictionary<FilterList, bool> Choices,
    IReadOnlyList<CustomFilterList> CustomLists, string CustomFilters, bool CleansCopiedLinks);
