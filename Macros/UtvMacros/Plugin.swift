import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct UtvMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StoredModelMacro.self,
        StoredPropertyMacro.self,
        MarkerMacro.self,
    ]
}
