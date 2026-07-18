import Foundation

/// gofer-native (non-spec) JSON-RPC methods.
///
/// These are **not** part of the ACP spec. They live apart from ``ACPMethods``
/// so the spec surface stays clean, and must only be used where graceful
/// degradation is in place for agents that don't implement them.
enum GoferMethods {
    /// gofer-native model discovery. Returns the models the daemon can run.
    static let models = "gofer/models"
}
