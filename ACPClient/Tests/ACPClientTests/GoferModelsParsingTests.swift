import XCTest
import ACP
@testable import ACPClient

final class GoferModelsParsingTests: XCTestCase {
    func testParseTopLevelArray() {
        let result: ACP.Value = .array([
            .object([
                "id": .string("claude-opus"),
                "provider": .string("anthropic"),
                "displayName": .string("Claude Opus"),
                "contextWindow": .int(200_000),
                "description": .string("Most capable"),
                "available": .bool(true),
            ]),
            .object([
                "id": .string("gpt-5"),
                "provider": .string("openai"),
                "name": .string("GPT-5"),
                "available": .bool(false),
            ]),
        ])

        let models = GoferModelsParser.parse(from: result)

        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models[0].id, "claude-opus")
        XCTAssertEqual(models[0].provider, "anthropic")
        XCTAssertEqual(models[0].displayName, "Claude Opus")
        XCTAssertEqual(models[0].contextWindow, 200_000)
        XCTAssertEqual(models[0].description, "Most capable")
        XCTAssertTrue(models[0].available)

        // `name` used as the display fallback; `available:false` preserved.
        XCTAssertEqual(models[1].displayName, "GPT-5")
        XCTAssertFalse(models[1].available)
    }

    func testParseModelsEnvelope() {
        let result: ACP.Value = .object([
            "models": .array([
                .object(["id": .string("m1"), "displayName": .string("Model 1")]),
            ]),
        ])

        let models = GoferModelsParser.parse(from: result)

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].id, "m1")
    }

    func testDisplayNameAndAvailabilityDefaults() {
        // No displayName/name → id fallback; no `available` → defaults to true.
        let result: ACP.Value = .array([
            .object(["id": .string("bare-model")]),
        ])

        let models = GoferModelsParser.parse(from: result)

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].displayName, "bare-model")
        XCTAssertTrue(models[0].available)
        XCTAssertNil(models[0].provider)
        XCTAssertNil(models[0].contextWindow)
    }

    func testDropsEntriesWithoutId() {
        let result: ACP.Value = .array([
            .object(["displayName": .string("no id")]),
            .object(["id": .string(""), "displayName": .string("empty id")]),
            .object(["id": .string("ok")]),
        ])

        let models = GoferModelsParser.parse(from: result)

        XCTAssertEqual(models.map(\.id), ["ok"])
    }

    // Graceful degradation: an unsupported/absent result parses to no models,
    // which hides the picker. (The thrown-error path is exercised at the
    // view-model layer.)
    func testUnsupportedShapesYieldNoModels() {
        XCTAssertTrue(GoferModelsParser.parse(from: nil).isEmpty)
        XCTAssertTrue(GoferModelsParser.parse(from: .null).isEmpty)
        XCTAssertTrue(GoferModelsParser.parse(from: .string("nope")).isEmpty)
        XCTAssertTrue(GoferModelsParser.parse(from: .object([:])).isEmpty)
    }
}

final class SetConfigOptionModelEncodingTests: XCTestCase {
    // A model selection is applied via the spec method `session/set_config_option`
    // with `configId: "model"` and the model id as a string select value —
    // never via a gofer-native set method.
    func testModelSelectionEncodesAsSetConfigOption() {
        let payload = ACPSessionSetConfigOptionPayload(
            sessionId: "sess-1",
            configId: GoferModelConfig.configId,
            value: .string("claude-opus")
        )

        let params = payload.params()

        guard case let .object(dict) = params else {
            return XCTFail("Expected object params")
        }
        XCTAssertEqual(dict["sessionId"]?.stringValue, "sess-1")
        XCTAssertEqual(dict["configId"]?.stringValue, "model")
        XCTAssertEqual(dict["value"]?.stringValue, "claude-opus")
    }
}
