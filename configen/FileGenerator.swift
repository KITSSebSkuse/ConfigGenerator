//
//  FileGenerator.swift
//  configen
//
//  Created by Dónal O'Brien on 11/08/2016.
//  Copyright © 2016 The App Business. All rights reserved.
//

import Foundation

class FileGenerator {
  
  struct EncryptionConfig {
    let key: String
    let iv: String
    let name: String
  }
    
  let optionsParser: OptionsParser
  var encryptionConfig: EncryptionConfig?
    
  init (optionsParser: OptionsParser) {
    self.optionsParser = optionsParser
  }
    
  var autoGenerationComment: String { return "// auto-generated by \(optionsParser.appName)\n// to add or remove properties, edit the mapping file: '\(optionsParser.inputHintsFilePath)'.\n// README: https://github.com/theappbusiness/ConfigGenerator/blob/master/README.md\n\n" }
  
  func generateHeaderFile(withTemplate template: HeaderTemplate) {
    
    var headerBodyContent = ""
    for (variableName, type) in optionsParser.hintsDictionary {
      let headerLine = methodDeclarationForVariableName(variableName: variableName, type: type, template: template)
      headerBodyContent.append("\n" + headerLine + ";" + "\n")
    }
    
    var headerBody = template.headerBody
    headerBody.replace(token: template.bodyToken, withString: headerBodyContent)
    
    do {
      let headerOutputString = autoGenerationComment + template.headerImportStatements + headerBody
      try headerOutputString.write(toFile: template.outputHeaderFileName, atomically: true, encoding: String.Encoding.utf8)
    }
    catch {
      fatalError("Failed to write to file at path \(template.outputHeaderFileName)")
    }

  }
  
  func generateImplementationFile(withTemplate template: ImplementationTemplate) {
    
    loadEncryptionSettings()
    
    var implementationBodyContent = ""
    for (variableName, type) in optionsParser.hintsDictionary {
      let implementationLine = methodImplementationForVariableName(variableName: variableName, type: type, template: template)
      implementationBodyContent.append("\n" + implementationLine + "\n")
    }
    
    var implementationBody = template.implementationBody
    implementationBody.replace(token: template.bodyToken, withString: implementationBodyContent)
    
    do {
      let implementationOutputString = autoGenerationComment + template.implementationImportStatements + implementationBody
      try implementationOutputString.write(toFile: template.outputImplementationFileName, atomically: true, encoding: String.Encoding.utf8)
    }
    catch {
      fatalError("Failed to write to file at path \(template.outputImplementationFileName)")
    }
    
  }
  
  private func loadEncryptionSettings() {
    guard let fieldKey = optionsParser.hintsDictionary.first(where: { return $1 == "EncryptionKey" })?.key,
        let key = optionsParser.plistDictionary[fieldKey] as? String else {
        return
    }
    
    // Generate the IV from the current state of the plist dictionary, this prevents
    // it changing every time the config is rebuilt.
    do {
        let iv = try optionsParser.plistDictionary.hashRepresentation()

        encryptionConfig = EncryptionConfig(key: key, iv: iv, name: fieldKey)

        // Add the IV option
        let ivFieldName = fieldKey.appending("IV")
        optionsParser.hintsDictionary[ivFieldName] = "ByteArray"
        optionsParser.plistDictionary[ivFieldName] = NSString(string: iv)
    } catch {
        fatalError("Unable to create initialization vector from input plist dictionary")
    }
  }
  
  func methodDeclarationForVariableName(variableName: String, type: String, template: HeaderTemplate) -> String {
    var line = ""
    
    switch (type) {
    case ("Double"):
      line = template.doubleDeclaration
      
    case ("Int"):
      line = template.integerDeclaration
      
    case ("String"):
      line = template.stringDeclaration
      
    case ("Bool"):
      line = template.booleanDeclaration
      
    case ("URL"):
      line = template.urlDeclaration
        
    case ("EncryptionKey"), ("ByteArray"):
        line = template.byteArrayDeclaration

    case ("Dictionary"):
        line = template.dictionaryDeclaration
        
    default:
      line = template.customDeclaration
      line.replace(token: template.customTypeToken, withString: type)
    }
    
    line.replace(token: template.variableNameToken, withString: variableName)
    
    return line
  }
  
  
  func methodImplementationForVariableName(variableName: String, type: String, template: ImplementationTemplate) -> String {
    
    guard var value: Any = optionsParser.plistDictionary[variableName] else {
      fatalError("No configuration setting for variable name: \(variableName)")
    }
    
    var line = ""
    
    switch (type) {
    case ("Double"):
      line = template.doubleImplementation
      
    case ("Int"):
      line = template.integerImplementation
      
    case ("String"):
      line = template.stringImplementation
      
    case ("Bool"):
      let boolString = value as! Bool ? template.trueString : template.falseString
      line = template.booleanImplementation
      line.replace(token: template.valueToken, withString: boolString)
      
    case ("URL"):
      let url = URL(string: "\(value)")!
      guard url.host != nil else {
        fatalError("Found URL without host: \(url) for setting: \(variableName)")
      }
      line = template.urlImplementation
      
    case ("EncryptionKey"), ("ByteArray"):
      guard let valueString = value as? String else {
        fatalError("EncryptionKey / ByteArray is not the expected type - String")
      }
      line = template.byteArrayImplementation  
      value = byteArrayOutput(from: Array(valueString.utf8))
        
    case ("Encrypted"):
        guard let options = encryptionConfig else {
            fatalError("Found an Encrypted value with no encryption key set. Please set a EncryptionKey value.")
        }
        
        guard let valueString = value as? String else {
            fatalError("\(variableName) is not the expected type - String")
        }
        
        line = template.byteArrayImplementation
        guard let encryptedString = valueString.encrypt(key: Array(options.key.utf8), iv: Array(options.iv.utf8)) else {
            fatalError("Unable to encrypt \(variableName) with key")
        }
        value = byteArrayOutput(from: encryptedString)

    case ("Dictionary"):
        line = template.dictionaryImplementation
        guard let dict = value as? [String: Any] else { fatalError("Expected a dictionary") }
        value = dictionaryValue(dict)
        
    default:
      guard value is String else {
        fatalError("Value (\(value)) must be a string in order to be used by custom type \(type)")
      }
      line = template.customImplementation
      line.replace(token: template.customTypeToken, withString: type)
    }
    
    line.replace(token: template.variableNameToken, withString: variableName)
    line.replace(token: template.valueToken, withString: "\(value)")
    
    return line
  }
  
  private func byteArrayOutput(from: [UInt8]) -> NSString {
    let transformedByteArray: [String] = from.map({ return "UInt8(\($0))" })
    return transformedByteArray.joined(separator: ", ") as NSString
  }
    
}

func dictionaryValue( _ dict: [String: Any]) -> String {
    let values = dict.map { (key, value) -> String in
        let updatedValue: Any
        switch value {
        case is String:
            updatedValue = "\"\(value)\""
        case is NSNumber:
            updatedValue = numericValue(value as! NSNumber)
        case is [String: Any]:
            updatedValue = dictionaryValue(value as! [String: Any])
        default:
            updatedValue = value
        }
        return "\"\(key)\": \(updatedValue)"
    }
    return "[\(values.joined(separator: ", "))]"
}

func numericValue(_ number: NSNumber) -> Any {
    if case .charType = CFNumberGetType(number) {
        return number.boolValue
    }
    return number
}

extension String {
  mutating func replace(token: String, withString string: String) {
    self = replacingOccurrences(of: token, with: string)
  }
  
  var trimmed: String {
    return (self as NSString).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
  }
}
