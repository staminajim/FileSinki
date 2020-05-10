# FileSinki

Easy file syncing between iOS, MacOS and tvOS, using CloudKit.

## Setup

## Usage

### FileSyncable

Adopt the FileSyncable protocol to get automatic coding and decoding of your data.

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

// save a saveGame to a file with path: "SaveGames/player1.save"
FileSinki.save(saveGame,
               toPath: "SaveGames/player1.save") { finalVersion in
    // closure *may* be called with finalVersion 
    // if the saveGame changed as a result of a merge
    // or a better available version
}

// delete the saveGame
FileSinki.delete(saveGame, at: "SaveGames/player1.save")
```

### Mergables

Adopt the FileMergable and implement `merge(with:)` to merge FileSyncables between devices.

```swift
struct SaveGame: FileSyncable, FileMergable {
    let trophies: [Trophy]

    func merge(with other: Self) -> Self? {
        let combinedTrophies = (trophies + other.trophies).sorted()
        return SaveGame(trophies: combinedTrophies)
    }
}
```
If your return nil from `merge(with:)` then FileSinki falls back to `shouldOverwrite(other:)`
