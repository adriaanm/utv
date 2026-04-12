import SwiftSyntax
import SwiftSyntaxMacros

/// Replaces SwiftData's @Query macro (which lives in SwiftDataMacros.dylib,
/// shipped only in Xcode.app). Generates the same accessor + peer expansion
/// that delegates to the SwiftData `Query` property wrapper type.
public struct QueryMacro: AccessorMacro, PeerMacro {

    // MARK: - Accessor role

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let name = propertyName(from: declaration) else { return [] }

        let getAccessor: AccessorDeclSyntax =
            """
            get {
                _\(raw: name).wrappedValue
            }
            """

        // Query.wrappedValue has a nonmutating set
        let setAccessor: AccessorDeclSyntax =
            """
            set {
            }
            """

        return [getAccessor, setAccessor]
    }

    // MARK: - Peer role

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let name = propertyName(from: declaration) else { return [] }

        // Forward the macro arguments directly to the Query initializer
        let args = node.arguments.map { "\($0)" } ?? ""

        return ["var _\(raw: name) = Query(\(raw: args))"]
    }

    // MARK: - Helpers

    private static func propertyName(from declaration: some DeclSyntaxProtocol) -> String? {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmedDescription
        else { return nil }
        return name
    }
}
