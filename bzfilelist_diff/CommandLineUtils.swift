//
//  CommandLine.swift
//  bzfilelist_diff
//
//  Created by YourMJK on 24.10.18.
//  Copyright © 2021 YourMJK. All rights reserved.
//

import Foundation


let ProgramName = URL(fileURLWithPath: CommandLine.arguments.first!).lastPathComponent


extension FileHandle: TextOutputStream {
	public func write(_ string: String) {
		guard let data = string.data(using: .utf8) else { return }
		self.write(data)
	}
}
var standardOutput = FileHandle.standardOutput
var standardError = FileHandle.standardError

func stdout(_ string: String, terminator: String = "\n") {
	print(string, terminator: terminator, to: &standardOutput)
	//FileHandle.standardOutput.write(string.appending("\n").data(using: .utf8)!)
}
func stderr(_ string: String, terminator: String = "\n") {
	print(string, terminator: terminator, to: &standardError)
	//FileHandle.standardError.write(string.appending("\n").data(using: .utf8)!)
}


func exit(error string: String, noPrefix: Bool = false) -> Never {
	stderr(noPrefix ? string : ("Error:  " + string))
	exit(1)
}
