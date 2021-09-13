//
//  BZFileListDiff.swift
//  bzfilelist_diff
//
//  Created by YourMJK on 08.09.21.
//  Copyright © 2021 YourMJK. All rights reserved.
//

import Foundation


struct BZFileListDiff {
	
	struct FileEntry: Equatable {
		let type: String
		let hash: String
		let size: String
		let path: String
	}
	
	typealias FileEntryDict = [String: FileEntry]
	
	
	struct FileEntryCollectionStats {
		let numberOfFiles: UInt
		let totalSize: UInt
	}
	struct Summary {
		var missingFiles: FileEntryCollectionStats
		var newFiles: FileEntryCollectionStats
		var changedFiles: (numberOfFiles: UInt, totalOldSize: UInt, totalNewSize: UInt)
	}
	
	
	enum ArgumentError: Error, CustomStringConvertible {
		case inputFileDoesntExist(url: URL)
		case outputDirectoryDoesntExist(url: URL)
		case outputFileAlreadyExists(url: URL)
		
		var description: String {
			switch self {
				case .inputFileDoesntExist(let url): return "No such input file \"\(url.path)\""
				case .outputDirectoryDoesntExist(let url): return "No such output directory \"\(url.path)\""
				case .outputFileAlreadyExists(let url): return "Output file \"\(url.path)\" already exists. Delete it, specify a different output directory or use option -f to overwrite"
			}
		}
		var localizedDescription: String {
			self.description
		}
	}
	enum ReadError: Error, CustomStringConvertible {
		case tooFewComponents(url: URL, lineNumber: UInt)
		case invalidValue(value: String, component: String)
		
		var description: String {
			switch self {
				case .tooFewComponents(let url, let lineNumber): return "Too few components in line \(lineNumber) of \"\(url.path)\""
				case .invalidValue(let value, let component): return "Invalid value \"\(value)\" for component \"\(component)\""
			}
		}
		var localizedDescription: String {
			self.description
		}
	}
	enum DiffError: Error, CustomStringConvertible {
		case duplicatePathInList(url: URL, path: String)
		
		var description: String {
			switch self {
				case .duplicatePathInList(let url, let path): return "Duplicate file path \"\(path)\" listed in \"\(url.path)\""
			}
		}
		var localizedDescription: String {
			self.description
		}
	}
	
	
	let oldFile: URL
	let newFile: URL
	let outputDirectory: URL
	let overwrite: Bool
	let linesPerRound: UInt
	
	
	public func compareLists() throws -> Summary {
		let missingFilesListURL = outputDirectory.appendingPathComponent("onlyInOld___\(oldFile.lastPathComponent).txt")
		let newFilesListURL = outputDirectory.appendingPathComponent("onlyInNew___\(newFile.lastPathComponent).txt")
		let changedOldFilesListURL = outputDirectory.appendingPathComponent("changedOld___\(oldFile.lastPathComponent).txt")
		let changedNewFilesListURL = outputDirectory.appendingPathComponent("changedNew___\(newFile.lastPathComponent).txt")
		
		// Check URLs
		if !fileExists(url: outputDirectory, directory: true) {
			//throw ArgumentError.outputDirectoryDoesntExist(url: outputDirectory)
			try createDir(url: outputDirectory)
		}
		for url in [missingFilesListURL, newFilesListURL, changedOldFilesListURL, changedNewFilesListURL] {
			if fileExists(url: url) {
				guard overwrite else {
					throw ArgumentError.outputFileAlreadyExists(url: url)
				}
				try deleteFile(url: url)
			}
		}
		
		
		var oldEntries = FileEntryDict()
		var newEntries = FileEntryDict()
		var changedOldEntries = [FileEntry]()
		var changedNewEntries = [FileEntry]()
		var oldLineNumber: UInt = 0
		var newLineNumber: UInt = 0
		
		// Setup progress display
		stdout("Reading lines...")
		let printProgress = {
			stdout("\r> \(String(format: "%-7d %-7d", oldLineNumber, newLineNumber))", terminator: "")
		}
		let progressTimer = DispatchSource.makeTimerSource()
		progressTimer.setEventHandler(handler: printProgress)
		progressTimer.schedule(deadline: .now(), repeating: 0.05)
		progressTimer.resume()
		
		// Setup concurrency handling
		let processingQueue = DispatchQueue(label: "processingQueue", qos: .userInteractive, attributes: .concurrent)
		let processingGroup = DispatchGroup()
		let processingSemaphoreOld = DispatchSemaphore(value: 1)
		let processingSemaphoreNew = DispatchSemaphore(value: 0)
		var processingFirstIsDone = false
		var processingShouldStop = false
		var processingError: Error?
		
		func concurrentAsync(execute closure: @escaping () throws -> Void) -> Void {
			processingGroup.enter()
			processingQueue.async {
				do {
					try closure()
				}
				catch {
					processingShouldStop = true
					processingError = error
				}
				processingGroup.leave()
			}
		}
		
		// Process lists
		concurrentAsync {
			try self.processList(fileURL: self.oldFile, lineNumber: &oldLineNumber, entries: &oldEntries, counterEntries: &newEntries, conflictingEntries: &changedOldEntries, conflictingCounterEntries: &changedNewEntries, semaphore: processingSemaphoreOld, counterSemaphore: processingSemaphoreNew, firstIsDone: &processingFirstIsDone, shouldStop: &processingShouldStop)
		}
		concurrentAsync {
			try self.processList(fileURL: self.newFile, lineNumber: &newLineNumber, entries: &newEntries, counterEntries: &oldEntries, conflictingEntries: &changedNewEntries, conflictingCounterEntries: &changedOldEntries, semaphore: processingSemaphoreNew, counterSemaphore: processingSemaphoreOld, firstIsDone: &processingFirstIsDone, shouldStop: &processingShouldStop)
		}
		
		// Wait for processing tasks to complete/fail
		processingGroup.wait()
		if let error = processingError {
			throw error
		}
		
		progressTimer.cancel()
		printProgress()
		stdout("")
		
		// Balance semaphores if needed
		if processingSemaphoreNew.wait(timeout: .now()) == .success {
			processingSemaphoreOld.signal()
		}
		
		
		// Create files
		stdout("Creating output files...")
		try writeToFile(url: missingFilesListURL, entries: &oldEntries)
		try writeToFile(url: newFilesListURL, entries: &newEntries)
		try writeToFile(url: changedOldFilesListURL, entries: &changedOldEntries)
		try writeToFile(url: changedNewFilesListURL, entries: &changedNewEntries)
		
		
		// Summary
		stdout("Creating summary...")
		func stats<C: Collection>(entries: C) throws -> FileEntryCollectionStats where C.Element == FileEntry {
			var totalSize: UInt = 0
			for entry in entries {
				guard let size = UInt(entry.size) else {
					throw ReadError.invalidValue(value: entry.size, component: "size")
				}
				totalSize += size
			}
			return FileEntryCollectionStats(numberOfFiles: UInt(entries.count), totalSize: totalSize)
		}
		
		return Summary(
			missingFiles: try stats(entries: oldEntries.values),
			newFiles: try stats(entries: newEntries.values),
			changedFiles: (
				numberOfFiles: UInt(changedOldEntries.count),
				totalOldSize: try stats(entries: changedOldEntries).totalSize,
				totalNewSize: try stats(entries: changedNewEntries).totalSize
			)
		)
	}
	
	
	private func processList(fileURL: URL, lineNumber: inout UInt, entries: inout FileEntryDict, counterEntries: inout FileEntryDict, conflictingEntries: inout [FileEntry], conflictingCounterEntries: inout [FileEntry], semaphore: DispatchSemaphore, counterSemaphore: DispatchSemaphore, firstIsDone: inout Bool, shouldStop: UnsafePointer<Bool>) throws {
		// Wait for turn
		semaphore.wait()
		defer {
			counterSemaphore.signal()
			firstIsDone = true
		}
		
		try readEntries(fileURL: fileURL) { (entry, currentLineNumber, stop) in
			lineNumber = currentLineNumber
			
			// Abort if stop was requested (e.g. error thrown)
			if shouldStop.pointee {
				stop = true
				return
			}
			
			let key = entry.path
			let counterEntry = counterEntries.removeValue(forKey: key)
			// Check if entry exists in other list
			if let counterEntry = counterEntry {
				// Check if entries weren't the same
				if !(entry.hash == counterEntry.hash && entry.size == counterEntry.size && entry.type == counterEntry.type) {
					conflictingEntries.append(entry)
					conflictingCounterEntries.append(counterEntry)
				}
			}
			else {
//				guard entries[key] == nil else {
//					throw DiffError.duplicatePathInList(url: fileURL, path: entry.path)
//				}
				entries[key] = entry
			}
			
			// Give up turn and wait for next turn
			if !firstIsDone, currentLineNumber % linesPerRound == 0 {
				counterSemaphore.signal()
				semaphore.wait()
			}
		}
	}
	
	private func readEntries(fileURL: URL, closure: (FileEntry, UInt, inout Bool) throws -> Void) throws {
		guard fileExists(url: fileURL) else {
			throw ArgumentError.inputFileDoesntExist(url: fileURL)
		}
		let csvReader = CSVReader(fileURL: fileURL, delimiter: "\t", encoding: .utf8)
		try csvReader.readRecords(dropComments: true) { (components, lineNumber, stop) in
			guard components.count >= 4 else {
				throw ReadError.tooFewComponents(url: fileURL, lineNumber: lineNumber)
			}
			try closure(FileEntry(type: components[0], hash: components[1], size: components[2], path: components[3]), lineNumber, &stop)
		}
	}
	
	
	private func fileExists(url: URL, directory: Bool = false) -> Bool {
		var isDirectory: ObjCBool = false
		return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && (isDirectory.boolValue == directory)
	}
	
	private func deleteFile(url: URL) throws {
		try FileManager.default.removeItem(at: url)
	}
	
	private func createDir(url: URL) throws {
		try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
	}
	
	private func writeToFile<C: Collection>(url: URL, entries: UnsafePointer<C>) throws where C.Element == FileEntry {
		var fileHandle = try startWritingToFile(url: url)
		for entry in entries.pointee {
			autoreleasepool {
				print(entry.type, entry.hash, entry.size, entry.path, separator: "\t", to: &fileHandle)
			}
		}
		stopWritingToFile(url: url, handle: fileHandle)
	}
	private func writeToFile(url: URL, entries: UnsafePointer<FileEntryDict>) throws {
		var fileHandle = try startWritingToFile(url: url)
		for key in entries.pointee.keys.sorted() {
			autoreleasepool {
				let entry = entries.pointee[key]!
				print(entry.type, entry.hash, entry.size, entry.path, separator: "\t", to: &fileHandle)
			}
		}
		stopWritingToFile(url: url, handle: fileHandle)
	}
	private func startWritingToFile(url: URL) throws -> FileHandle {
		FileManager.default.createFile(atPath: url.path, contents: nil)
		return try FileHandle(forWritingTo: url)
	}
	private func stopWritingToFile(url: URL, handle: FileHandle) {
		handle.closeFile()
		stdout("> \(url.path)")
	}
	
}
