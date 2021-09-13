//
//  main.swift
//  bzfilelist_diff
//
//  Created by YourMJK on 07.09.21.
//  Copyright © 2021 YourMJK. All rights reserved.
//

import Foundation


let usage = """
Usage:
    \(ProgramName) [option ...] <old file> <new file> <output directory>

Options:
    -f           Overwrite files in output directory if they already exists.
    -l <number>  Specify the number of lines to load simultaneously. Larger numbers may increase or decrease memory usage. Default is 10000.

Example:
    \(ProgramName) old/v0000_root_filelist.dat new/v0000_root_filelist.dat diff/
"""


var arguments = CommandLine.arguments[1...]
func nextArg() -> String {
	guard !arguments.isEmpty else {
		exit(error: "Too few arguments")
	}
	return arguments.removeFirst()
}

// Parse options
var overwrite: Bool = false
var linesPerRound: UInt = 10000

while arguments.first?.first == "-" {
	let option = nextArg()
	switch option {
		case "-f":
			overwrite = true
		case "-l":
			let numberString = nextArg()
			guard let number = UInt(numberString) else {
				exit(error: "Invalid number \"\(numberString)\"")
			}
			linesPerRound = number
		default:
			exit(error: "Unknown option \"\(option)\"")
	}
}

// Parse arguments
guard arguments.count >= 3 else {
	exit(error: usage, noPrefix: true)
}

let oldFile = URL(fileURLWithPath: nextArg())
let newFile = URL(fileURLWithPath: nextArg())
let outputDirectory = URL(fileURLWithPath: nextArg(), isDirectory: true)


// Run program
do {
	let bzFileListDiff = BZFileListDiff(oldFile: oldFile, newFile: newFile, outputDirectory: outputDirectory, overwrite: overwrite, linesPerRound: linesPerRound)
	let summary = try bzFileListDiff.compareLists()
	
	let sizeFormatter = ByteCountFormatter()
	sizeFormatter.countStyle = .file
	sizeFormatter.includesActualByteCount = true
	func formatSize(_ size: UInt) -> String {
		sizeFormatter.string(fromByteCount: Int64(size))
	}
	func formatStat(files: UInt, sizeA: UInt, sizeB: UInt? = nil) -> String {
		"\(files) — \(formatSize(sizeA))" + (sizeB.flatMap { " vs. \(formatSize($0))" } ?? "")
	}
	func formatStat(_ stat: BZFileListDiff.FileEntryCollectionStats) -> String {
		formatStat(files: stat.numberOfFiles, sizeA: stat.totalSize)
	}
	
	print("")
	print("Missing files:", formatStat(summary.missingFiles), separator: "\t")
	print("New files:", formatStat(summary.newFiles), separator: "\t")
	print("Changed files:", formatStat(
		files: summary.changedFiles.numberOfFiles,
		sizeA: summary.changedFiles.totalOldSize,
		sizeB: summary.changedFiles.totalNewSize
	), separator: "\t")
}
catch {
	exit(error: "\(error)")
}
