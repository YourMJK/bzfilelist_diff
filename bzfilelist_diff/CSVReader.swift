//
//  CSVReader.swift
//  bzfilelist_diff
//
//  Created by YourMJK on 13.10.20.
//  Stolen from https://github.com/Flinesoft/CSVImporter/blob/stable/Frameworks/CSVImporter/CSVImporter.swift
//

import Foundation


/// Importer for CSV files that maps your lines to a specified data structure.
public class CSVReader {
	
	enum ReaderError: Error, CustomStringConvertible {
		case noFileHandle(url: URL)
		
		var description: String {
			switch self {
				case .noFileHandle(let url): return "Couldn't open file handle for \"\(url.path)\""
			}
		}
		var localizedDescription: String {
			self.description
		}
	}
	
	// MARK: - Stored Instance Properties
	let fileURL: URL
	let delimiter: String
	let encoding: String.Encoding
	
	// Various private constants used for reading lines
	private let startPartRegex = try! NSRegularExpression(pattern: "\\A\"[^\"]*\\z", options: .caseInsensitive) // swiftlint:disable:this force_try
	private let middlePartRegex = try! NSRegularExpression(pattern: "\\A[^\"]*\\z", options: .caseInsensitive) // swiftlint:disable:this force_try
	private let endPartRegex = try! NSRegularExpression(pattern: "\\A[^\"]*\"\\z", options: .caseInsensitive) // swiftlint:disable:this force_try
	private let substitute: String = "\u{001a}"
	private let delimiterQuoteDelimiter: String
	private let delimiterDelimiter: String
	private let quoteDelimiter: String
	private let delimiterQuote: String
	
	// MARK: - Initializers
	/// Internal initializer to prevent duplicate code.
	init(fileURL: URL, delimiter: String, encoding: String.Encoding) {
		self.fileURL = fileURL
		self.delimiter = delimiter
		self.encoding = encoding
		
		delimiterQuoteDelimiter = "\(delimiter)\"\"\(delimiter)"
		delimiterDelimiter = delimiter + delimiter
		quoteDelimiter = "\"\"\(delimiter)"
		delimiterQuote = "\(delimiter)\"\""
	}
	
	
	public func readRecords(dropFirst: Bool = false, dropComments: Bool = false, closure: ([String], UInt, inout Bool) throws -> Void) throws {
		guard let lineReader = FileLineReader(path: fileURL.path, encoding: encoding) else {
			throw ReaderError.noFileHandle(url: fileURL)
		}
		defer {
			lineReader.close()
		}
		
		var lineNumber: UInt = 1
		var stop = false
		
		// Drop first line containing header of CSV
		if dropFirst {
			_ = lineReader.next()
			lineNumber += 1
		}
		
		for line in lineReader {
			// Skip lines starting with #
			if dropComments && line.first == "#" {
				continue
			}
			try autoreleasepool {
				let record = readValuesInLineSimple(line)
				try closure(record, lineNumber, &stop)
			}
			if stop {
				break
			}
			lineNumber += 1
		}
	}
	
	
	/// Reads the line and returns the fields found. Doesn't handle double quotes.
	///
	/// - Parameters:
	///   - line: The line to read values from.
	/// - Returns: An array of values found in line.
	func readValuesInLineSimple(_ line: String) -> [String] {
		return line.components(separatedBy: delimiter)
	}
	
	
	/// Reads the line and returns the fields found. Handles double quotes according to RFC 4180.
	///
	/// - Parameters:
	///   - line: The line to read values from.
	/// - Returns: An array of values found in line.
	func readValuesInLine(_ line: String) -> [String] {
		var correctedLine = line
		while correctedLine.contains(delimiterQuoteDelimiter) {
			correctedLine = correctedLine.replacingOccurrences(of: delimiterQuoteDelimiter, with: delimiterDelimiter)
		}
		
		if correctedLine.hasPrefix(quoteDelimiter) {
			correctedLine = String(correctedLine.suffix(from: correctedLine.index(correctedLine.startIndex, offsetBy: 2)))
		}
		
		if correctedLine.hasSuffix(delimiterQuote) {
			correctedLine = String(correctedLine.prefix(upTo: correctedLine.index(correctedLine.startIndex, offsetBy: correctedLine.utf16.count - 2)))
		}
		
		correctedLine = correctedLine.replacingOccurrences(of: "\"\"", with: substitute)
		var components = correctedLine.components(separatedBy: delimiter)
		
		var index = 0
		while index < components.count {
			let element = components[index]
			
			if index < components.count - 1 && startPartRegex.firstMatch(in: element, options: .anchored, range: element.fullRange) != nil {
				var elementsToMerge = [element]
				
				while middlePartRegex.firstMatch(in: components[index + 1], options: .anchored, range: components[index + 1].fullRange) != nil {
					elementsToMerge.append(components[index + 1])
					components.remove(at: index + 1)
				}
				
				if endPartRegex.firstMatch(in: components[index + 1], options: .anchored, range: components[index + 1].fullRange) != nil {
					elementsToMerge.append(components[index + 1])
					components.remove(at: index + 1)
					components[index] = elementsToMerge.joined(separator: delimiter)
				} else {
					print("Invalid CSV format in line, opening \" must be closed – line: \(line).")
				}
			}
			
			index += 1
		}
		
		components = components.map { $0.replacingOccurrences(of: "\"", with: "") }
		components = components.map { $0.replacingOccurrences(of: substitute, with: "\"") }
		
		return components
	}
	
}

// MARK: - Helpers
extension String {
	var fullRange: NSRange {
		return NSRange(location: 0, length: self.utf16.count)
	}
}
