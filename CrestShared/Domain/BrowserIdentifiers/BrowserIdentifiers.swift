import Foundation

// TRANSITIONAL until S6.9, which gives each use a semantic `UUID` name and
// deletes this file. The names are plain `UUID`s: never extend one, because
// the extension would reach every `UUID` in the app.

typealias BrowserWindowID = UUID
typealias FolderID = UUID
typealias SpaceID = UUID
typealias SplitGroupID = UUID
typealias TabID = UUID
