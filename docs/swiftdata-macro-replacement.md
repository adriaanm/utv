# Custom SwiftData Macros (replacing Apple's @Model)

## Why

SwiftData's `@Model`, `@Attribute`, and `@Relationship` macros live in `libSwiftDataMacros.dylib`, which ships only inside Xcode.app. Our custom macros generate the same expansion but are built from source via SwiftPM using swift-syntax, eliminating the Xcode dependency for compilation.

## Macros

| Macro | Replaces | Roles | Purpose |
|-------|----------|-------|---------|
| `@StoredModel` | `@Model` | member + memberAttribute + extension | Class-level boilerplate + attaches `@_StoredProperty` to stored vars + adds `PersistentModel`/`Observable` |
| `@_StoredProperty` | `@_PersistedProperty` | accessor + peer | Per-property init/get/set accessors + `_foo` peer |
| `@Unique` | `@Attribute(.unique)` | peer (no-op) | Marker read by `@StoredModel` for schemaMetadata |
| `@Relation(...)` | `@Relationship(...)` | peer (no-op) | Marker read by `@StoredModel` for schemaMetadata |

`@Unique` and `@Relation` expand to nothing — they exist only so the compiler accepts them as attributes. `@StoredModel` reads them from the syntax tree when generating `schemaMetadata`.

## File layout

```
Sources/Macros.swift              Public macro declarations (app-visible)
Macros/UtvMacros/
  Plugin.swift                    @main CompilerPlugin entry point
  StoredModelMacro.swift          @StoredModel (member + memberAttribute + extension)
  StoredPropertyMacro.swift       @_StoredProperty (accessor + peer)
  MarkerMacro.swift               @Unique, @Relation (peer, expand to nothing)
```

## What @StoredModel generates

### Per stored property (via @_StoredProperty)

The memberAttribute role attaches `@_StoredProperty` to every stored var. Computed properties (those with a `get` accessor) are skipped.

**Accessor role** transforms `var foo: Type [= default]` into init/get/set using `@storageRestrictions`, `getValue(forKey:)`, `setValue(forKey:to:)`, and the observation registrar.

**Peer role** adds `var _foo: _SwiftDataNoType` (empty placeholder for definite initialization).

### Per class (member role)

- `_$backingData` / `persistentBackingData` — SwiftData backing store
- `schemaMetadata` — static property metadata array (reads `@Unique`/`@Relation` annotations)
- `init(backingData:)` — SwiftData reconstitution init
- `_$observationRegistrar` + `access(keyPath:)` + `withMutation(keyPath:_:)` — Observation support
- `_SwiftDataNoType` — empty placeholder struct

### Extension role

Adds `PersistentModel` and `Observable` conformances.

## Gotchas

- **Optional properties need explicit `= nil`**: Properties like `var foo: Bar?` must be written as `var foo: Bar? = nil` so the init accessor fires during initialization. Without it, the `_foo` peer variable is never initialized and the compiler errors.
- **Computed properties**: Any property with a `get` accessor (including single-expression bodies) is automatically skipped by both the memberAttribute and member roles.
- **`@Relation` delete rule**: The macro generates `Schema.Relationship(deleteRule: .cascade, ...)` — the delete rule must be a labeled argument.

## Official @Model features not yet implemented

This section documents Apple's SwiftData macro features we haven't needed. Use it as a checklist if a new model requires something beyond basic stored properties, `@Unique`, and `@Relation`.

### @Attribute options

Apple's `@Attribute` accepts a variadic list of `Schema.Attribute.Option` plus optional named parameters. Our `@Unique` covers only `.unique`. To add others:

| Option | What it does | How to add |
|--------|-------------|------------|
| `.externalStorage` | Store large values (e.g. `Data`) in separate files instead of inline in the database | New marker macro (like `@Unique`), read in `StoredModelMacro.collectStoredProperties`, emit `Schema.Attribute(.externalStorage)` in schemaMetadata |
| `.ephemeral` | Property exists in-memory but is not persisted to disk | Same pattern — marker macro + schemaMetadata entry with `Schema.Attribute(.ephemeral)` |
| `.spotlight` | Index the property for Spotlight search | Same pattern |
| `.encrypt` | Encrypt the field at rest | Same pattern |
| `.transformable(by:)` | Custom `ValueTransformer` for serialization | Needs a marker macro that takes a transformer name argument |
| `.preserveValueOnDeletion` | Retain value in the store when the owning model is deleted | Same pattern as `.externalStorage` |
| `originalName:` | Map property to a different column name in the schema (for renames) | Add `originalName` parameter to a new or existing marker macro; emit `Schema.Attribute(..., originalName: "old_name")` |
| `hashModifier:` | Customize the hash used for unique constraint resolution | Add `hashModifier` parameter; emit in schemaMetadata |

**Implementation pattern**: Each option follows the same approach — (1) define a no-op marker macro in `MarkerMacro.swift` with `@attached(peer)`, (2) declare it in `Sources/Macros.swift`, (3) detect it in `StoredModelMacro.collectStoredProperties`, (4) emit the corresponding `Schema.Attribute(...)` in schemaMetadata. Multiple options on the same property can be combined: `Schema.Attribute(.unique, .externalStorage)`.

Alternatively, instead of many single-purpose markers, you could define a general `@StoredAttribute(...)` macro that accepts the same options as Apple's `@Attribute` and translates them all. This is more work upfront but scales better if you need more than one or two options.

### @Relationship options

Our `@Relation` supports `deleteRule` and `inverse`. Additional parameters Apple supports:

| Option | What it does | How to add |
|--------|-------------|------------|
| `minimumModelCount` | Minimum cardinality for to-many relationships | Add parameter to `@Relation` macro declaration in `Macros.swift`; read in `extractRelationship`; emit in `Schema.Relationship(...)` |
| `maximumModelCount` | Maximum cardinality for to-many relationships | Same |
| `originalName` | Map relationship to a different name in the schema | Same |
| `hashModifier` | Customize the relationship hash | Same |

These are straightforward — just add parameters to `@Relation`'s declaration and extend `extractRelationship` in `StoredModelMacro.swift` to read and emit them.

### @Transient

Apple's `@Transient` marks a stored property as non-persisted. Our macro already uses `@Transient` internally (on `_$backingData` and `_$observationRegistrar`), but doesn't expose it for user properties.

**Why we haven't needed it**: Properties not listed in `schemaMetadata` aren't persisted by SwiftData regardless. A computed property is already skipped. If you need a stored property that isn't persisted (e.g. a cache), you have two options:
1. Add a `@Transient` marker macro (same no-op peer pattern) and have `StoredModelMacro` skip transient-marked properties from both `@_StoredProperty` attachment and `schemaMetadata`.
2. Just make it a computed property with a backing store outside the model.

### willSet/didSet observers

Our macro detects properties with only `willSet`/`didSet` (no `get`) as stored, which is correct. However, the `@_StoredProperty` accessor expansion replaces the property body entirely — **any user-written observers are discarded**. Apple's `@_PersistedProperty` has the same behavior: observers on `@Model` properties don't fire.

If you need side effects on property changes, use SwiftUI's `onChange` or KVO-style observation from outside the model, not `didSet`.

### Model inheritance

Our macro does not handle class inheritance. Specifically:
- `schemaMetadata` only collects properties declared directly on the class, not inherited ones.
- `init(backingData:)` only initializes peer vars for the class's own properties.

SwiftData supports model inheritance (a `@Model` subclass of another `@Model`), but it's rarely used and has its own quirks. If needed, the macro would need to walk the superclass chain (which is hard from syntax alone — you'd need to rely on naming conventions or an explicit parameter like `@StoredModel(extending: ParentModel.self)`).
