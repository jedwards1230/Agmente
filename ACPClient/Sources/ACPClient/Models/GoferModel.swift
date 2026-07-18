import Foundation
import ACP

/// A model advertised by a gofer daemon via the gofer-native `gofer/models`
/// request.
///
/// > Important: `gofer/models` is **not** part of the ACP spec. It is used only
/// > for model *discovery* to feed the picker. Applying a selection goes through
/// > the spec method `session/set_config_option` (`configId` =
/// > ``GoferModelConfig/configId``). Callers must degrade gracefully when the
/// > connected agent does not answer `gofer/models` (see ``GoferModelsParser``).
public struct GoferModel: Identifiable, Sendable, Equatable, Hashable {
    /// The stable model identifier, used as the `session/set_config_option`
    /// select value.
    public let id: String
    /// The provider that serves the model (e.g. `anthropic`, `openai`), when known.
    public let provider: String?
    /// A human-facing label; falls back to ``id`` when the daemon omits one.
    public let displayName: String
    /// The model's context window in tokens, when advertised.
    public let contextWindow: Int?
    /// A short description of the model, when advertised.
    public let description: String?
    /// Whether the daemon can currently run this model. Defaults to `true` when
    /// the daemon omits the flag.
    public let available: Bool

    public init(
        id: String,
        provider: String? = nil,
        displayName: String,
        contextWindow: Int? = nil,
        description: String? = nil,
        available: Bool = true
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.contextWindow = contextWindow
        self.description = description
        self.available = available
    }
}

/// Constants for the gofer model config option applied over spec ACP.
public enum GoferModelConfig {
    /// The `session/set_config_option` `configId` used to apply a model
    /// selection. Discovery is gofer-native; *setting* stays spec-general.
    public static let configId = "model"
}

/// Parses the result payload of a gofer-native `gofer/models` response into
/// typed models.
///
/// The parser is resilient to partial payloads and to agents that don't
/// implement the method: a `nil`/non-array result yields `[]`, which drives the
/// picker's graceful degradation. Callers should distinguish a *thrown* RPC
/// error (method-not-found on a non-gofer agent) from an empty parse — both hide
/// the picker, but only the thrown case means "discovery unsupported".
public enum GoferModelsParser {
    /// Parses models from either a top-level array or a `{ "models": [...] }`
    /// envelope. Returns `[]` for any other shape.
    public static func parse(from result: ACP.Value?) -> [GoferModel] {
        let items: [ACP.Value]
        if let array = result?.arrayValue {
            items = array
        } else if let array = result?.objectValue?["models"]?.arrayValue {
            items = array
        } else {
            return []
        }
        return items.compactMap(parseModel(from:))
    }

    private static func parseModel(from value: ACP.Value) -> GoferModel? {
        guard let object = value.objectValue,
              let id = object["id"]?.stringValue ?? object["model"]?.stringValue,
              !id.isEmpty else {
            return nil
        }

        let displayName = object["displayName"]?.stringValue
            ?? object["name"]?.stringValue
            ?? id
        let provider = object["provider"]?.stringValue
        let contextWindow = object["contextWindow"]?.intValue
        let description = object["description"]?.stringValue
        // Present-but-false hides the model; absent means available.
        let available = object["available"]?.boolValue ?? true

        return GoferModel(
            id: id,
            provider: provider,
            displayName: displayName,
            contextWindow: contextWindow,
            description: description,
            available: available
        )
    }
}
