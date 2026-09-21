namespace CrestCore.Domain;

public readonly record struct SyncPreferences(bool SavedStructure, bool CurrentTabs, bool HistoryAndArchive) {
    public bool Includes(TabPlacement placement) => placement == TabPlacement.Current ? CurrentTabs : SavedStructure;
}
