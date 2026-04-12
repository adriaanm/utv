import SwiftSyntax
import SwiftSyntaxMacros

/// Generates all SwiftData boilerplate for a model class:
/// - memberAttribute: attaches @_StoredProperty to each stored var
/// - member: backing store, schemaMetadata, init(backingData:), observation registrar
/// - extension: PersistentModel + Observable conformances
public struct StoredModelMacro: MemberAttributeMacro, MemberMacro, ExtensionMacro {

    // MARK: - MemberAttribute role
    // Attaches @_StoredProperty to every stored var (skipping computed properties)

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let varDecl = member.as(VariableDeclSyntax.self),
              isStoredProperty(varDecl)
        else { return [] }

        return [AttributeSyntax(stringLiteral: "@_StoredProperty")]
    }

    // MARK: - Member role
    // Generates backing store, schemaMetadata, init(backingData:), observation support

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw MacroError("@StoredModel can only be applied to a class")
        }

        let className = classDecl.name.trimmedDescription
        let storedProps = collectStoredProperties(from: classDecl)

        var members: [DeclSyntax] = []

        // _$backingData
        members.append(
            """
            @Transient
            private var _$backingData: any BackingData<\(raw: className)> = \(raw: className).createBackingData()
            """
        )

        // persistentBackingData
        members.append(
            """
            public var persistentBackingData: any BackingData<\(raw: className)> {
                get { _$backingData }
                set { _$backingData = newValue }
            }
            """
        )

        // schemaMetadata
        let metadataEntries = storedProps.map { prop in
            let metadata: String
            if prop.isUnique {
                metadata = "Schema.Attribute(.unique)"
            } else if let rel = prop.relationship {
                metadata = rel
            } else {
                metadata = "nil"
            }
            let defaultValue = prop.defaultValue ?? "nil"
            return "Schema.PropertyMetadata(name: \"\(prop.name)\", keypath: \\\(className).\(prop.name), defaultValue: \(defaultValue), metadata: \(metadata))"
        }.joined(separator: ",\n            ")

        members.append(
            """
            class var schemaMetadata: [Schema.PropertyMetadata] {
                return [
                    \(raw: metadataEntries),
                ]
            }
            """
        )

        // init(backingData:)
        let peerInits = storedProps.map { "_\($0.name) = _SwiftDataNoType()" }.joined(separator: "\n        ")
        members.append(
            """
            init(backingData: any BackingData<\(raw: className)>) {
                \(raw: peerInits)
                self.persistentBackingData = backingData
            }
            """
        )

        // Observation registrar
        members.append(
            """
            @Transient
            private let _$observationRegistrar = ObservationRegistrar()
            """
        )

        // access helper
        members.append(
            """
            internal nonisolated func access<_M>(keyPath: KeyPath<\(raw: className), _M>) {
                _$observationRegistrar.access(self, keyPath: keyPath)
            }
            """
        )

        // withMutation helper
        members.append(
            """
            internal nonisolated func withMutation<_M, _MR>(
                keyPath: KeyPath<\(raw: className), _M>,
                _ mutation: () throws -> _MR
            ) rethrows -> _MR {
                try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            """
        )

        // _SwiftDataNoType
        members.append(
            """
            struct _SwiftDataNoType {}
            """
        )

        return members
    }

    // MARK: - Extension role
    // Adds PersistentModel and Observable conformances

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let persistentModel: DeclSyntax = "extension \(type.trimmed): PersistentModel {}"
        let observable: DeclSyntax = "extension \(type.trimmed): Observable {}"
        return [
            persistentModel.cast(ExtensionDeclSyntax.self),
            observable.cast(ExtensionDeclSyntax.self),
        ]
    }

    // MARK: - Helpers

    struct StoredProperty {
        let name: String
        let defaultValue: String?
        let isUnique: Bool
        let relationship: String?  // e.g. "Schema.Relationship(.cascade, ...)"
    }

    static func isStoredProperty(_ varDecl: VariableDeclSyntax) -> Bool {
        guard let binding = varDecl.bindings.first else { return false }
        // Has accessor block with get → computed
        if let accessorBlock = binding.accessorBlock {
            // willSet/didSet are stored, get/set are computed
            if case .accessors(let accessors) = accessorBlock.accessors {
                for accessor in accessors {
                    if accessor.accessorSpecifier.tokenKind == .keyword(.get) {
                        return false
                    }
                }
                return true
            }
            // Single expression body → computed (e.g. `var x: Int { 42 }`)
            return false
        }
        return true
    }

    static func collectStoredProperties(from classDecl: ClassDeclSyntax) -> [StoredProperty] {
        var result: [StoredProperty] = []
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  isStoredProperty(varDecl),
                  let binding = varDecl.bindings.first,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.trimmedDescription
            else { continue }

            let hasUnique = varDecl.attributes.contains { attr in
                guard case .attribute(let a) = attr else { return false }
                return a.attributeName.trimmedDescription == "Unique"
            }

            let relationship = extractRelationship(from: varDecl)

            let defaultValue: String?
            if let initializer = binding.initializer {
                defaultValue = initializer.value.trimmedDescription
            } else {
                defaultValue = nil
            }

            result.append(StoredProperty(
                name: name,
                defaultValue: defaultValue,
                isUnique: hasUnique,
                relationship: relationship
            ))
        }
        return result
    }

    static func extractRelationship(from varDecl: VariableDeclSyntax) -> String? {
        for attr in varDecl.attributes {
            guard case .attribute(let a) = attr,
                  a.attributeName.trimmedDescription == "Relation"
            else { continue }

            guard let args = a.arguments?.as(LabeledExprListSyntax.self) else {
                return "Schema.Relationship()"
            }

            var deleteRule: String?
            var inverseKeypath: String?

            for arg in args {
                let label = arg.label?.trimmedDescription
                let value = arg.expression.trimmedDescription
                if label == "deleteRule" {
                    deleteRule = value
                } else if label == "inverse" {
                    inverseKeypath = value
                }
            }

            var parts: [String] = []
            if let rule = deleteRule {
                parts.append("deleteRule: \(rule)")
            }
            if let inv = inverseKeypath {
                parts.append("inverse: \(inv)")
            }
            return "Schema.Relationship(\(parts.joined(separator: ", ")))"
        }
        return nil
    }
}

struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }
}
