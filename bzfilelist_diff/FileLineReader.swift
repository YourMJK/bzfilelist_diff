//
//  FileLineReader.swift
//  bzfilelist_diff
//
//  Created by YourMJK on 12.10.20.
//  Stolen from https://stackoverflow.com/questions/24581517/read-a-file-url-line-by-line-in-swift
//

import Foundation


class FileLineReader: IteratorProtocol, Sequence {
	typealias Element = String
	
	let file: UnsafeMutablePointer<FILE>!
	let encoding: String.Encoding
	let path: String
	
	// MARK: - Initialization
	
	/// - Parameter path:     the file path
	/// - Parameter encoding: file encoding (default: NSUTF8StringEncoding)
	init?(path: String, encoding: String.Encoding) {
		self.encoding = encoding
		self.path = path
		
		guard let file = fopen(path, "r") else {
			return nil
		}
		//stderr("File \(path) opened")
		self.file = file
	}
	
	
	// MARK: - Public Methods
	
	/// Returns the next line, or nil on EOF.
	func next() -> String? {
		// Read data chunks from file until a line delimiter is found:
		var line: UnsafeMutablePointer<CChar>?
		var linecap: Int = 0
		defer { free(line) }
		
		let nCharacters = getline(&line, &linecap, file) 
		if nCharacters > 0 {
			// Remove newline character at the end
			line![nCharacters-1] = 0
			return String(cString: line!, encoding: encoding)
		}
		else {
			close()
			return nil
		}
	}
	
	/// Close the underlying file. No reading must be done after calling this method.
	func close() {
		fclose(file)
		//stderr("File \(path) closed")
	}
	
	
	// MARK: - Deinitialization
	
	deinit {
		self.close()
	}
	
}
