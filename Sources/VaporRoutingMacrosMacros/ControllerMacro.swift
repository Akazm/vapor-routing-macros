import SwiftSyntax
import SwiftSyntaxMacros

public struct ControllerMacro: MemberMacro, ExtensionMacro {

    public static let formatMode: FormatMode = .auto
    
    public static func expansion<D, C>(
        of node: AttributeSyntax,
        providingMembersOf decl: D,
        in context: C
    ) throws -> [SwiftSyntax.DeclSyntax]
    where D: DeclGroupSyntax, C: MacroExpansionContext {
        
        guard
            let classDeclaration = decl.as(ClassDeclSyntax.self),
            classDeclaration.modifiers.first(where: { $0.name.text == "final" }) != nil
        else {
            throw CustomError.message("@Controller only works with classes including the 'final' modifier")
        }
        
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let pathArgValue = arguments.first?.expression.description,
              pathArgValue != "\"\""
        else {
            throw CustomError.message("@Controller requires that the provided path be non-empty")
        }
        
        var middlewareArg: String? = nil
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self),
           let middlewareArgValue = arguments.first(where: { $0.label?.description == "middleware" })?.expression.description {
            middlewareArg = middlewareArgValue
        }
        
        let handlers = try classDeclaration.memberBlock.members
            .compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter { funcDecl in
                for attr in funcDecl.attributes {
                    guard case let .attribute(attribute) = attr,
                          let attributeType = attribute.attributeName.as(IdentifierTypeSyntax.self) else {
                        return false
                    }
                    return HandlerMacro.knownMacroNames.contains(attributeType.name.text)
                }
                return false
            }
            .enumerated()
            .map { index, fun in try expansion(of: fun, with: pathArgValue, in: context, at: index) }
            .compactMap { $0 }
        
        let functionDecl = try FunctionDeclSyntax("public func boot(routes: RoutesBuilder)") {
            DeclSyntax("let controllerPath = \(raw: pathArgValue)")
            if let middlewareArg = middlewareArg {
                DeclSyntax("let routesWithMiddleware = routes.grouped(\(raw: middlewareArg))")
                DeclSyntax("let controller = routesWithMiddleware.grouped(controllerPath.pathComponents)")
            } else {
                DeclSyntax("let controller = routes.grouped(controllerPath.pathComponents)")
            }
            for (index, handler) in handlers.enumerated() {
                if let path = handler.path {
                    DeclSyntax("let handler\(raw: index)Path = \(raw: StringLiteralExprSyntax(content: path).description)")
                }
                handler.fun
            }
        }
        
        return [functionDecl.formatted().as(DeclSyntax.self)].compactMap { $0 }
    }
    public static func expansion(
        of node: SwiftSyntax.AttributeSyntax,
        attachedTo declaration: some SwiftSyntax.DeclGroupSyntax,
        providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol,
        conformingTo protocols: [SwiftSyntax.TypeSyntax],
        in context: some SwiftSyntaxMacros.MacroExpansionContext
    ) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
        try [
            ExtensionDeclSyntax(
                """
                
                extension \(raw: type.trimmed): RouteCollection {
                }
                """
            )
        ]
    }

    private static func expansion(
        of declaration: FunctionDeclSyntax,
        with controllerPath: String?,
        in context: some MacroExpansionContext,
        at index: Int
    ) throws -> (path: String?, fun: FunctionCallExprSyntax)? {
        let attributes = declaration.attributes
        guard
            let (method, path, streamingStrategy) = try getMethodAndPath(attributes)
        else {
            return nil
        }
        
        let closureSignature = ClosureSignatureSyntax(
            leadingTrivia: .space,
            parameterClause: .simpleInput(
                ClosureShorthandParameterListSyntax {
                    ClosureShorthandParameterSyntax(name: .identifier("req"))
                }
            )
            ,
            effectSpecifiers: TypeEffectSpecifiersSyntax(
                asyncSpecifier: .keyword(.async), throwsClause: .init(throwsSpecifier: .keyword(.throws))
            )
        )
        
        let handlerParams = getHandlerParameters(decl: declaration)
        let validHandlerParams = handlerParams.filter { $0.valid }
        let validHandlerParamsWithoutRequest = validHandlerParams.filter { $0.type != "Request" }
        let guardStatments = validHandlerParamsWithoutRequest
                            .filter { $0.attribute != "QueryParam" }
                            .map { expandHandlerParam(param: $0)}
                            .compactMap { $0 }
        let queryParamStatements = validHandlerParamsWithoutRequest
                                .filter { $0.attribute == "QueryParam" }
                                .map { DeclSyntax("let \(raw: $0.name)Param: \(raw: $0.type) = req.query[\"\(raw: $0.name)\"]")
}
        
        let argumentList = validHandlerParams
            .map { $0.type == "Request" ? "\($0.argName): req" : "\($0.argName): \($0.name)Param" }
            .joined(separator: ",")
        
        let expr = "self.\(raw: declaration.name.text)(\(raw: argumentList))" as ExprSyntax
        var finalExpr = expr
        if declaration.signature.effectSpecifiers?.asyncSpecifier != nil,
           declaration.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil {
            if let tryAwaitExpr = ExprSyntax(TryExprSyntax(expression: AwaitExprSyntax(expression: expr))) {
                finalExpr = tryAwaitExpr
            }
        } else if declaration.signature.effectSpecifiers?.asyncSpecifier != nil,
                  declaration.signature.effectSpecifiers?.throwsClause?.throwsSpecifier == nil {
            if let awaitExpr = ExprSyntax(AwaitExprSyntax(expression: expr)) {
                finalExpr = awaitExpr
            }
        } else if declaration.signature.effectSpecifiers?.asyncSpecifier == nil,
                  declaration.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil {
            if let tryExpr = ExprSyntax(TryExprSyntax(expression: expr)) {
                finalExpr = tryExpr
            }
        }
        
        let functionCall = FunctionCallExprSyntax(
            calledExpression: ExprSyntax("controller.on"),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax {
                LabeledExprSyntax(expression: "\(raw: method)" as ExprSyntax)
                if path != nil {
                    LabeledExprSyntax(expression: "handler\(raw: index)Path.pathComponents" as ExprSyntax)
                }
                if let strategy = streamingStrategy {
                    LabeledExprSyntax(label: "body", expression: "\(raw: strategy)" as ExprSyntax)
                }
                LabeledExprSyntax(label: "use", expression: ClosureExprSyntax(signature: closureSignature) {
                    for stmt in guardStatments {
                        stmt
                    }
                    for stmt in queryParamStatements {
                        stmt
                    }
                    ReturnStmtSyntax(expression: finalExpr)
                })
            },
            rightParen: .rightParenToken()
        )
        
        return (path, functionCall)
        
    }
    
    private static func expandHandlerParam(param: HandlerParam) -> GuardStmtSyntax? {
        let expression: ExprSyntax
        switch param.attribute {
        case "PathParam":
            expression = "req.parameters.get(\"\(raw: param.name)\", as: \(raw: param.type).self)" as ExprSyntax
        case "QueryContent":
            expression = "try? req.query.decode(\(raw: param.type).self)" as ExprSyntax
        case "BodyContent":
            expression = "try? req.content.decode(\(raw: param.type).self)" as ExprSyntax
        default:
            return nil
        }
        return expandParameterGuardStatement(param: param, expression: expression)
    }
    
    private static func expandParameterGuardStatement(param: HandlerParam, expression: ExprSyntax) -> GuardStmtSyntax? {
        GuardStmtSyntax(conditions: ConditionElementListSyntax {
            ConditionElementSyntax(
                condition: .optionalBinding(
                    OptionalBindingConditionSyntax(
                        bindingSpecifier: .keyword(.let),
                        pattern: PatternSyntax(stringLiteral: param.name + "Param"),
                        initializer: InitializerClauseSyntax(value: expression)
                    )
                )
            )
        }, body: CodeBlockSyntax {
            ThrowStmtSyntax(expression: "Abort(.badRequest)" as ExprSyntax)
        })
    }
}

