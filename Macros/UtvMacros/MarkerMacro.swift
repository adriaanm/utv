import SwiftSyntax
import SwiftSyntaxMacros

/// No-op peer macro used as a marker annotation.
/// @Unique and @Relation expand to nothing — they exist only so the compiler
/// accepts them as attributes, and @StoredModel reads them from the syntax tree.
public struct MarkerMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
