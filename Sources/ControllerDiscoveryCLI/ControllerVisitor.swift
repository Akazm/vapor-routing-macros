import Foundation
import SwiftSyntax

final class ControllerVisitor: SyntaxVisitor {
    var identifiers: [String] = []
    
    override func visit(_ node: InheritanceClauseSyntax) -> SyntaxVisitorContinueKind {
        guard
            node.isControllerDiscoverable,
            let parent = node.parent,
            let identifier = parent.classStructOrExtensionIdentifier
        else {
            return .skipChildren
        }
        identifiers.append(identifier)
        return .skipChildren
    }
}

extension Syntax {
    var classStructOrExtensionIdentifier: String? {
        let tokenSyntax: TokenSyntax
        if let asClass = self.as(ClassDeclSyntax.self) {
            tokenSyntax = asClass.name
        } else if let asStruct = self.as(StructDeclSyntax.self) {
            tokenSyntax = asStruct.name
        } else if let asExtension = self.as(ExtensionDeclSyntax.self), let token = asExtension.extendedType.as(IdentifierTypeSyntax.self)?.name {
            tokenSyntax = token
        } else {
            return nil
        }
        return tokenSyntax.text
    }
}

extension InheritanceClauseSyntax {
  var isControllerDiscoverable: Bool {
    inheritedTypeCollection.contains { node in
        let typeNameText = IdentifierTypeSyntax(node.type)?.name.text
      return typeNameText == "ControllerDiscoverable"
    }
  }
}
