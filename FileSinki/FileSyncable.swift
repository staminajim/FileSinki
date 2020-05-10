//
//  FileSyncable.swift
//  FileSinki
//
//  See LICENSE file for licensing information
//
//  Created by James Van-As on 6/11/19.
//  Copyright © 2019 James Van-As. All rights reserved.
//

import Foundation
import Compression

// MARK: - FileSyncable Protocol

public protocol FileSyncable: Codable, Equatable {

    // MARK: - Overwriting

    /**
    Decide whether self should overwrite other.
     If self conforms to Comparable, this defaults to "overwrite if self > other"
    - Parameter other: The other object to compare with.
    - Returns: Return true if this object should overwrite the other
    */
    func shouldOverwrite(other: Self) -> Bool

    /**
    Implement this method to allow for interactive checks for overwriting other. Inside, call keep() with the FileSyncable
     that you wish to keep.

    - Parameter other: The other object to check whether to overwrite against.
    - Parameter keep: Pass in the FileSyncable that you wish to keep.
    */
    func interactiveShouldOverwrite(other: Self, keep:  @escaping ShouldOverwriteClosure)

    // MARK: - Merging

    /**
    Inherit from FileMergable and also implement this method to merge self with other. Return the merged object.
    - Parameter with: The other object to merge with.
    - Returns: The merged object. Returning nil makes FileSinki fall back to no merging using a shouldOverwrite check.
    */
    func merge(with other: Self) -> Self?

    /**
    Interactively mege two FileMergables

    Inherit from FileMergable and also implement this method to allow for interactive merges with other.

    Inside, call merged() with the merged FileSyncable item.

    - Parameter with: The other object to merge with.
    - Parameter merged: Pass in the merged object to use. Passing nil makes FileSinki fall back to no merging using a shouldOverwrite check.
    */
    func interactiveMerge(with other: Self, merged: @escaping MergedClosure)

    // MARK: - Deleting

    /**
     Called if the local copy exists, but has been deleted in the cloud.
     Given the otherDeleted item, decide whether the local copy of the file should also be deleted.
      Defaults to return false.
     - Parameter local: The local copy of the FileSyncable.
     - Parameter remoteDeleted: The cloud copy of the FileSyncable, which has been marked as deleted.
     - Returns: Return true if the local copy of this object object should be deleted. Defaults to return true.
     */
    static func shouldDelete(local: Self, remoteDeleted: Self) -> Bool

    /**
    Decide whether self should overwrite other.
     If self conforms to Comparable, this defaults to "overwrite if self > other"
    - Parameter other: The other object to compare with.
    - Returns: Return true if this object should overwrite the other
    */
    static func interactiveShouldDelete(local: Self, remoteDeleted: Self, delete:  @escaping ShouldDeleteClosure)

}

// MARK: - FileMergable Protocol
/**
FileMergable

Inherit from FileMergable and implement either `merge(with other:)` or `interactiveMerge(with:)` to allow for merge operations
*/
public protocol FileMergable {
    // inherit from FileMergable and implement
    //  merge(with other:) or interactiveMerge(with:)
    //  to allow for merge operations
}

// MARK: - Closures

public extension FileSyncable {
    typealias ShouldOverwriteClosure = ((_ keep: Self) -> ())
    typealias MergedClosure = ((_ mergedItem: Self?) -> ())
    typealias ShouldDeleteClosure = ((_ delete: Bool) -> ())
}
public typealias BinaryMergedClosure = ((_ mergedData: Data) -> ())
public typealias BinaryFileMergeClosure = ((_ left: Data, _ right: Data, _ merged: @escaping BinaryMergedClosure) -> ())

