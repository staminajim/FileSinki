# FileSinki

*Easy file syncing between iOS, MacOS and tvOS, using CloudKit.*

![Swift Version 5](https://img.shields.io/badge/Swift-v5-green.svg)
[![CocoaPods Badge](https://img.shields.io/badge/CocoaPods-Yes-green.svg)](https://cocoapods.org/pods/FileSinki)
![SwiftPM Badge](https://img.shields.io/badge/SwiftPM-Yes-green.svg)
![Supported Platforms Badge](https://img.shields.io/badge/Supported%20Platforms-iOS%20%7C%20MacOS%20%7C%20tvOS-yellowgreen.svg)
[![license](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/staminajim/FileSinki/blob/master/LICENSE)

- [Basic Usage](#basic-usage)
  * [FileSyncable](#filesyncable)
    + [Saving, Loading and Deleting](#saving-loading-and-deleting)
- [Advanced Usage](#advanced-usage)
    + [Mergables](#mergables)
    + [Interactive / Asynchronous Selection and Merging](#interactive--asynchronous-selection-and-merging)
    + [Observing Changes](#observing-changes)
  * [Binary Files](#binary-files)
    + [Saving, Loading and Deleting](#saving-loading-and-deleting-1)
    + [Observing Changes](#observing-changes-1)
  * [URLs and Folders](#urls-and-folders)
  * [Compression](#compression)
- [Objective-C](#objective-c)
- [Installation and Setup](#installation-and-setup)
  * [Installation](#installation)
  * [CloudKit Setup](#cloudkit-setup)
  * [AppDelegate](#appdelegate)
- [Author](#author)
- [License](#license)

# Basic Usage

```swift
import FileSinki
```

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
# Advanced Usage

### Mergables

Adopt the FileMergable protocol and implement `merge(with:)` to merge FileSyncables between devices.
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

By default FileSinki puts files in `.applicationSupportDirectory + bundle name`. You can specify a different location using the optional `root` parameter.

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

*Note that tvOS only supports writing to the `.caches` folder. FileSinki automatically uses this folder instead of `.applicationSupportDirectory` so you don't have to worry about it.*

## Compression

Internally FileSinki always stores compressed versions of your data in the cloud. It can also be advantageous to store compressed versions locally. Compression and decompression is often much faster than disk access, and Codable files generally compress extremely well.

There are compressed versions of all of the above FileSinki operations. For example:

```swift
// load a compressed SaveGame from a file with path: "SaveGames/player1.save"
FileSinki.loadCompressed(SaveGame.self,
                         fromPath: "SaveGames/player1.save") { saveGame, wasRemote in
}
```
```swift
// save a compressed saveGame to a file with path: "SaveGames/player1.save"
FileSinki.saveCompressed(saveGame,
                         toPath: "SaveGames/player1.save") { finalVersion in
    // closure *may* be called with finalVersion 
    // if the saveGame changed as a result of a merge
    // or a better available version
}
```
```swift
// delete the compressed saveGame
FileSinki.deleteCompressed(saveGame, at: "SaveGames/player1.save")
```

The compression used is Apple's LZFSE

There are also a few handy compression functions in `Data+Compression.swift` and `Codable+Compression.swift` which don't involve file syncing

# Objective-C

FileSinki works with Objective-C, but functionality is limited to saving and loading `NSData`. Here are some Objective-C equivalents of the above features:

```objective-c
@import FileSinki;
```
```
[FileSinki setupWithCloudKitContainer:@"Blaa"];
```
```
[FileSinki receivedNotification:notificationInfo];
```
```objective-c
[FileSinki loadBinaryFileFromPath:@"test.pdf"
                             root:NSApplicationSupportDirectory
                       mergeAsync:^(NSData *left, NSData *right, void (^merged)(NSData *data)) {
    // decode left and right data, merge and then pass on the final mergedData to merged()           
    NSData *mergedData = [mergedPDF data];
    merged(mergedData);
 } loaded:^(NSData *finalData, BOOL wasRemote) {
     if (!finalData) {
         return;
     }         
 }];
```
```objective-c
[FileSinki saveBinaryFile:pdfData
                   toPath:@"test.pdf"
                     root:NSApplicationSupportDirectory
               mergeAsync:^(NSData *left, NSData *right, void (^ merge)(NSData *mergedData)) {
    // decode left and right data, merge and then pass on the final mergedData to merged()           
    NSData *mergedData = [mergedPDF data];
    merged(mergedData);
} finalVersion:^(NSData *finalVersion) {
    // do stuff with the final merged data  
}];
```
```objective-c
[FileSinki deleteBinaryFile:pdfData
                   atPath:@"test.pdf"
                     root:NSApplicationSupportDirectory];
```
```objective-c
[FileSinki addObserver:self 
                  path:@"SaveGames/"
                  root:NSApplicationSupportDirectory
              itemsChanged:^(NSArray<ChangeItem *> * changedItems) {
    for (ChangeItem *item in changedItems) {
        printf("File changed at %s\n", item.localURL.absoluteString.UTF8String);
    }
}];
```

# Installation and Setup

## Installation

FileSinki can be installed via the **Swift Package Manager** or **Cocoapods**:
```ruby
pod 'FileSinki'
```

## CloudKit Setup

1. Enable `CloudKit` in your app's `Capabilities`. Note your application's CloudKit container identifier for use later on.

<img width="500" alt="App Capabilities" src="https://user-images.githubusercontent.com/1085877/81517496-3eb6df80-938f-11ea-97f7-1b9136a4b725.png">

2. In the https://icloud.developer.apple.com go to your application's Development `Schema`, and add a new `Record Type` called `FileSinki` with the following `Custom Fields`:

* `path` (Type String)
* `type` (Type String)
* `asset` (Type Asset)
* `data` (Type Bytes)
* `deleted` (Type Int(64))

3. In the FileSinki Record Schema, click `Edit Indexes`, add the following Indexes:

* `recordName` (`QUERYABLE`)
* `type` (`QUERYABLE`)
* `path` (`SEARCHABLE`)

And save changes.

The final result should look like:

<img width="500" alt="CloudKitRecordType" src="https://user-images.githubusercontent.com/1085877/81517502-437b9380-938f-11ea-99c7-f0b6233c977b.png">

*Note: Once you have verfied that FileSinki is working correctly in the development environment, don't forget to deploy the schema to `Production`:*

<img width="500" alt="Deploy to Production" src="https://user-images.githubusercontent.com/1085877/81517504-46768400-938f-11ea-8ffc-65314133c60b.png">

## AppDelegate

Add the following code to your AppDelegate (or equivalent MacOS delegate functions)

1. Add `FileSinki.setup()` and `registerForRemoteNotifications()` to `didFinishLaunchingWithOptions` with your CloudKit  container identifier
```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    FileSinki.setup(cloudKitContainer: "iCloud.com.MyCompanyName.MyCoolApp")
    application.registerForRemoteNotifications()    // required for live change observing
}
```
2. Add `FileSinki.didBecomeActive()` to `applicationDidBecomeActive`
```swift
func applicationDidBecomeActive(_ application: UIApplication) {      
    FileSinki.didBecomeActive()
}
```

3. Add `FileSinki.receivedNotification(userInfo)` to `didReceiveRemoteNotification`
```swift
func application(_ application: UIApplication,
                 didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                 fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    FileSinki.receivedNotification(userInfo)
    completionHandler(.newData)
}
```

*Note: In my experience `application.registerForRemoteNotifications()` will do nothing and `didReceiveRemoteNotification` nor it's `didFail` equivalent will be called for at least 24 hours after the first call. At some point it will just start working once Apple Push Notification Service has finished doing it's thing.*

# Author

- James Vanas ([@jamesvanas](https://twitter.com/jamesvanas))

# License

FileSinki is released under the MIT license. See LICENSE for details.
