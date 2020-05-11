# FileSinki

Easy file syncing between iOS, MacOS and tvOS, using CloudKit.

## Setup

## Usage

## FileSyncable

Adopt the FileSyncable protocol to make your data work with FileSinki.

The most basic function is `shouldOverwrite`, which decides what to do if a local copy and a remote (cloud) copy of the data conflicts.

```swift
struct SaveGame: FileSyncable {
    let score: Double

    func shouldOverwrite(other: Self) -> Bool {
        return score > other.score
    }
}
```
If your struct / class already conforms to Comparable, shouldOverwrite by default overwrites if self > other

### Saving, Loading and Deleting

```swift
// load a SaveGame from a file with path: "SaveGames/player1.save"
FileSinki.load(SaveGame.self,
               fromPath: "SaveGames/player1.save") { saveGame, wasRemote in
    // closure *may* be called multiple times, 
    // if the cloud has a better version of saveGame
}
```
```swift
// save a saveGame to a file with path: "SaveGames/player1.save"
FileSinki.save(saveGame,
               toPath: "SaveGames/player1.save") { finalVersion in
    // closure *may* be called with finalVersion 
    // if the saveGame changed as a result of a merge
    // or a better available version
}
```
```swift
// delete the saveGame
FileSinki.delete(saveGame, at: "SaveGames/player1.save")
```

### Mergables

Adopt the FileMergable and implement `merge(with:)` to merge FileSyncables between devices.
Return the new merged object / struct which will be used.

```swift
struct SaveGame: FileSyncable, FileMergable {
    let trophies: [Trophy]

    func merge(with other: Self) -> Self? {
        let combinedTrophies = (trophies + other.trophies).sorted()
        return SaveGame(trophies: combinedTrophies)
    }
}
```
If you return nil from `merge(with:)` then FileSinki falls back to `shouldOverwrite(other:)`

### Interactive / Asynchronous Selection and Merging

If your decisions whether to overwrite / how to merge are more involved and require either user intervention or asynchromous work, implement one of the following functions:

```swift
extension SaveGame: FileSyncable {

    func shouldOverwriteAsync(other: SaveGame,
                              keep: @escaping ShouldOverwriteClosure) {
        // Do any kind of async decision making necessary.
        // You just have to call keep() with the version you want to keep
        SomeUserPrompt.chooseBetween(self, other) { userSelection in
            keep(userSelection)
        }       
    }
}
```
```swift
extension SaveGame: FileMergable, FileSyncable  {

    func mergeAsync(with other: SaveGame,
                    merged: @escaping MergedClosure) {
        // Do any kind of async merging necessary.
        // You just have to call merged() with the 
        // final merged version you want to keep
        SomeSaveGameMergerThing.merge(self, other) { mergedSaveGame in
            merged(mergedSaveGame)
        }       
    }
}
```
Inside you can do any work asynchronously or in different threads, you just have to call `keep` or `merged` once the work is complete with the final item to use.

### Observing Changes

Similar to adding observers to the `NotificationCenter`, you can watch for changes to items that happen on other devices:

```swift
FileSinki.addObserver(self,
                      for: SaveGame.self,
                      path: "SaveGames/player1.save") { changed in
    // any time a SaveGame in the file player1.save changes remotely, this closure will be called.
    let changedSaveGame = changed.item
    print("Observed FileSinki change in \(changedSaveGame) with local URL \(changed.localURL) and path: \(changed.path)")
}
```
If the path provided ends in a trailing slash `/`, then any files in that folder will be recursively checked for changes:
```swift
FileSinki.addObserver(self,
                      for: SaveGame.self,
                      path: "SaveGames/") { changed in
    // any time a SaveGame anywhere in SaveGames/ changes remotely, this closure will be called.
    let changedSaveGame = changed.item
    print("Observed change in \(changedSaveGame) with local URL \(changed.localURL) and path: \(changed.path)")
}
```

## Binary Files

If you are dealing with raw Data files or non Codable objects/structs you can use FileSinki at the raw data level.

### Saving, Loading and Deleting
```swift
// load a PDF from a file with path: "test.pdf"
FileSinki.loadBinaryFile(fromPath: "test.pdf",
                         mergeAsync: { left, right, merged in
    let leftPDF = PDF(data: left)
    let rightPDF = PDF(data: right)
    SomePDFMerger.merge(leftPDF, rightPDF) { finalMergedPDF in {
        merged(finalMergedPDF.data)
    }
}) { data, wasRemote in
    // closure *may* be called multiple times, 
    // if the cloud has a better version of your data
    let loadedPDF = PDF(data: data)    // the final data object which has been merged across devices
}
```
```swift
FileSinki.saveBinaryFile(pdf.data,
                         toPath: "test.pdf",
                         mergeAsync: { left, right, merged in
    let leftPDF = PDF(data: left)
    let rightPDF = PDF(data: right)
    SomePDFMerger.merge(leftPDF, rightPDF) { finalMergedPDF in {
        merged(finalMergedPDF.data)
    }
}) { finalData in
    // closure *may* be called with finalData 
    // if the data changed as a result of a merge
    // or a better available version
    let loadedPDF = PDF(data: finalData)    // the final data object which has been merged across devices
}
```
```swift
FileSinki.deleteBinaryFile(pdf.data, at: "test.pdf")
```
### Observing Changes
Observing remote changes with binary files is more limited than with FileSyncables. You will only be notified of which paths / local urls which have changed. It is your responsibility to then load the binary files yourself.
```swift
FileSinki.addObserver(self,
                      path: "test.pdf") { changed in
    // any time test.pdf changes remotely, this closure will be called.    
    print("Observed a binary file change with path: \(changed.path)")
    // You'll probably want to actually do something now that you know a binary file has changed remotely.
    FileSinki.loadBinaryFile(...
}
```

## URLs and Folders

By default FileSinki puts files in ` .applicationSupportDirectory + bundle name`. You can specify a different location using the optional `root` parameter.

```swift
// load a SaveGame from a file with path: "SaveGames/player1.save" inside the Documents directory
FileSinki.load(SaveGame.self,
               fromPath: "SaveGames/player1.save",
               root: .documentDirectory) { saveGame, wasRemote in
}
```
You can also pass in a full path from a local url:

```swift
let saveGameURL: URL = ...  // some local file URL
FileSinki.load(SaveGame.self,
               fromPath: saveGameURL.path) { saveGame, wasRemote in
}
```
