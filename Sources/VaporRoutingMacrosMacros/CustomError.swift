import SwiftSyntax


enum CustomError: Error, CustomStringConvertible {
    case message(String)
    
    var description: String {
        switch self {
            case .message(let text):
                return text
            }
    }
}