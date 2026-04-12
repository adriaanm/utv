import SwiftSyntax
import SwiftSyntaxMacros

/// Generates SwiftData accessor (init/get/set) and peer (`_foo`) for each stored property.
public struct StoredPropertyMacro: AccessorMacro, PeerMacro {

    // MARK: - Accessor role

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmedDescription
        else { return [] }

        let initAccessor: AccessorDeclSyntax =
            """
            @storageRestrictions(accesses: _$backingData, initializes: _\(raw: name))
            init(initialValue) {
                _$backingData.setValue(forKey: \\.\(raw: name), to: initialValue)
                _\(raw: name) = _SwiftDataNoType()
            }
            """

        let getAccessor: AccessorDeclSyntax =
            """
            get {
                _$observationRegistrar.access(self, keyPath: \\.\(raw: name))
                return self.getValue(forKey: \\.\(raw: name))
            }
            """

        let setAccessor: AccessorDeclSyntax =
            """
            set {
                _$observationRegistrar.withMutation(of: self, keyPath: \\.\(raw: name)) {
                    self.setValue(forKey: \\.\(raw: name), to: newValue)
                }
            }
            """

        return [initAccessor, getAccessor, setAccessor]
    }

    // MARK: - Peer role

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmedDescription
        else { return [] }

        return ["var _\(raw: name): _SwiftDataNoType"]
    }
}
