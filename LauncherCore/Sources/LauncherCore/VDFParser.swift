import Foundation

/// A value in Valve's KeyValues (VDF/ACF) text format.
public indirect enum VDFValue: Sendable, Equatable {
    case string(String)
    case object([String: VDFValue])

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: VDFValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Keys are stored lowercased, because Steam isn't consistent about capitalization.
    public subscript(key: String) -> VDFValue? {
        objectValue?[key.lowercased()]
    }
}

/// Parses Steam's KeyValues files, e.g.:
///
///     "AppState"
///     {
///         "appid"      "228980"
///         "name"       "Some Game"
///     }
public enum VDFParser {
    private enum Token: Equatable {
        case open
        case close
        case text(String)
    }

    public static func parse(_ text: String) -> VDFValue? {
        let tokens = tokenize(text)
        var index = 0

        func parseObject() -> [String: VDFValue] {
            var result: [String: VDFValue] = [:]
            while index < tokens.count {
                switch tokens[index] {
                case .close:
                    index += 1
                    return result
                case .open:
                    // A brace without a key; skip it.
                    index += 1
                case .text(let key):
                    index += 1
                    guard index < tokens.count else { return result }
                    switch tokens[index] {
                    case .open:
                        index += 1
                        result[key.lowercased()] = .object(parseObject())
                    case .text(let value):
                        index += 1
                        result[key.lowercased()] = .string(value)
                    case .close:
                        return result
                    }
                }
            }
            return result
        }

        let root = parseObject()
        return root.isEmpty ? nil : .object(root)
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace {
                index += 1
            } else if character == "/" && index + 1 < characters.count && characters[index + 1] == "/" {
                // Comment until the end of the line.
                while index < characters.count && characters[index] != "\n" {
                    index += 1
                }
            } else if character == "{" {
                tokens.append(.open)
                index += 1
            } else if character == "}" {
                tokens.append(.close)
                index += 1
            } else if character == "\"" {
                index += 1
                var value = ""
                while index < characters.count && characters[index] != "\"" {
                    if characters[index] == "\\" && index + 1 < characters.count {
                        let next = characters[index + 1]
                        switch next {
                        case "n": value.append("\n")
                        case "t": value.append("\t")
                        default: value.append(next)
                        }
                        index += 2
                    } else {
                        value.append(characters[index])
                        index += 1
                    }
                }
                index += 1 // closing quote
                tokens.append(.text(value))
            } else {
                // Unquoted token.
                var value = ""
                while index < characters.count,
                      !characters[index].isWhitespace,
                      !"{}\"".contains(characters[index]) {
                    value.append(characters[index])
                    index += 1
                }
                tokens.append(.text(value))
            }
        }
        return tokens
    }
}
