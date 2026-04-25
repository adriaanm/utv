import Foundation
import SwiftData
import SwiftUI

@attached(memberAttribute)
@attached(member, names: named(_$backingData), named(persistentBackingData), named(schemaMetadata), named(_$observationRegistrar), named(access), named(withMutation), named(_SwiftDataNoType), arbitrary)
@attached(extension, conformances: PersistentModel, Observable)
public macro StoredModel() = #externalMacro(module: "UtvMacros", type: "StoredModelMacro")

@attached(accessor, names: named(init), named(get), named(set))
@attached(peer, names: prefixed(`_`))
public macro _StoredProperty() = #externalMacro(module: "UtvMacros", type: "StoredPropertyMacro")

@attached(peer)
public macro Unique() = #externalMacro(module: "UtvMacros", type: "MarkerMacro")

@attached(peer)
public macro Relation(deleteRule: Schema.Relationship.DeleteRule = .nullify, inverse: AnyKeyPath? = nil) = #externalMacro(module: "UtvMacros", type: "MarkerMacro")

@attached(peer)
public macro Transient() = #externalMacro(module: "UtvMacros", type: "MarkerMacro")

@attached(accessor, names: named(get), named(set))
@attached(peer, names: prefixed(`_`))
public macro StoredQuery<Value: Comparable, Element: PersistentModel>(
    filter: Predicate<Element>? = nil,
    sort keyPath: KeyPath<Element, Value>,
    order: SortOrder = .forward,
    transaction: Transaction? = nil
) = #externalMacro(module: "UtvMacros", type: "QueryMacro")
