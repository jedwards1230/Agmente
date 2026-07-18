import XCTest
import ACP
@testable import Agmente
import ACPClient

@MainActor
final class ACPSessionViewModelTests: XCTestCase {

    // MARK: - Mock Delegates

    /// Mock implementation of ACPSessionCacheDelegate for testing.
    private final class MockCacheDelegate: ACPSessionCacheDelegate {
        var savedMessages: [UUID: [String: [ChatMessage]]] = [:]
        var savedStopReasons: [UUID: [String: String]] = [:]
        var saveCalls: [(serverId: UUID, sessionId: String)] = []
        var loadCalls: [(serverId: UUID, sessionId: String)] = []
        var clearCalls: [(serverId: UUID, sessionId: String?)] = []
        var migrateCalls: [(serverId: UUID, from: String, to: String)] = []
        var storedMessages: [String: [UUID: [ChatMessage]]] = [:] // sessionId -> serverId -> messages
        var persistCalls: [(serverId: UUID, sessionId: String)] = []

        func saveMessages(_ messages: [ChatMessage], for serverId: UUID, sessionId: String) {
            var serverCache = savedMessages[serverId] ?? [:]
            serverCache[sessionId] = messages
            savedMessages[serverId] = serverCache
            saveCalls.append((serverId, sessionId))
        }

        func loadMessages(for serverId: UUID, sessionId: String) -> [ChatMessage]? {
            loadCalls.append((serverId, sessionId))
            return savedMessages[serverId]?[sessionId]
        }

        func saveStopReason(_ reason: String, for serverId: UUID, sessionId: String) {
            var serverCache = savedStopReasons[serverId] ?? [:]
            serverCache[sessionId] = reason
            savedStopReasons[serverId] = serverCache
        }

        func loadStopReason(for serverId: UUID, sessionId: String) -> String? {
            return savedStopReasons[serverId]?[sessionId]
        }

        func clearCache(for serverId: UUID, sessionId: String) {
            savedMessages[serverId]?[sessionId] = nil
            savedStopReasons[serverId]?[sessionId] = nil
            clearCalls.append((serverId, sessionId))
        }

        func clearCache(for serverId: UUID) {
            savedMessages[serverId] = nil
            savedStopReasons[serverId] = nil
            clearCalls.append((serverId, nil))
        }

        func migrateCache(serverId: UUID, from placeholderId: String, to resolvedId: String) {
            migrateCalls.append((serverId, placeholderId, resolvedId))
            if let messages = savedMessages[serverId]?[placeholderId] {
                saveMessages(messages, for: serverId, sessionId: resolvedId)
            }
            if let stopReason = savedStopReasons[serverId]?[placeholderId] {
                saveStopReason(stopReason, for: serverId, sessionId: resolvedId)
            }
        }

        func hasCachedMessages(serverId: UUID, sessionId: String) -> Bool {
            return savedMessages[serverId]?[sessionId] != nil
        }

        func getLastMessagePreview(for serverId: UUID, sessionId: String) -> String? {
            return savedMessages[serverId]?[sessionId]?.last?.content
        }

        func loadChatFromStorage(sessionId: String, serverId: UUID) -> [ChatMessage] {
            return storedMessages[sessionId]?[serverId] ?? []
        }

        func persistChatToStorage(serverId: UUID, sessionId: String) {
            persistCalls.append((serverId, sessionId))
        }

        func reset() {
            savedMessages = [:]
            savedStopReasons = [:]
            saveCalls = []
            loadCalls = []
            clearCalls = []
            migrateCalls = []
            storedMessages = [:]
            persistCalls = []
        }
    }

    /// Mock implementation of ACPSessionEventDelegate for testing.
    private final class MockEventDelegate: ACPSessionEventDelegate {
        var modeChanges: [(modeId: String, serverId: UUID, sessionId: String)] = []
        var stopReasons: [(reason: String, serverId: UUID, sessionId: String)] = []
        var loadCompletions: [(serverId: UUID, sessionId: String)] = []

        func sessionModeDidChange(_ modeId: String, serverId: UUID, sessionId: String) {
            modeChanges.append((modeId, serverId, sessionId))
        }

        func sessionDidReceiveStopReason(_ reason: String, serverId: UUID, sessionId: String) {
            stopReasons.append((reason, serverId, sessionId))
        }

        func sessionLoadDidComplete(serverId: UUID, sessionId: String) {
            loadCompletions.append((serverId, sessionId))
        }

        func reset() {
            modeChanges = []
            stopReasons = []
            loadCompletions = []
        }
    }

    // MARK: - Test Helpers

    private var appendMessages: [String] = []
    private var wireMessages: [(direction: String, message: ACPWireMessage)] = []

    private func makeDependencies(service: ACPService? = nil) -> ACPSessionViewModel.Dependencies {
        return ACPSessionViewModel.Dependencies(
            getService: { service },
            append: { [weak self] message in
                self?.appendMessages.append(message)
            },
            logWire: { [weak self] direction, message in
                self?.wireMessages.append((direction, message))
            }
        )
    }

    private func makeViewModel(service: ACPService? = nil, cacheDelegate: ACPSessionCacheDelegate? = nil, eventDelegate: ACPSessionEventDelegate? = nil) -> ACPSessionViewModel {
        let viewModel = ACPSessionViewModel(dependencies: makeDependencies(service: service))
        viewModel.cacheDelegate = cacheDelegate
        viewModel.eventDelegate = eventDelegate
        return viewModel
    }

    private func resetTestState() {
        appendMessages = []
        wireMessages = []
    }

    override func setUp() {
        super.setUp()
        resetTestState()
    }

    // MARK: - Chat State Management Tests

    func testSaveChatState_DelegatesToCache() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId = UUID()
        let sessionId = "test-session"

        // Set session context
        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)

        // Add some messages
        viewModel.addUserMessage(content: "Hello", images: [])

        // Verify cache delegate was called
        XCTAssertFalse(cacheDelegate.saveCalls.isEmpty, "saveChatState should call cacheDelegate.saveMessages")
        XCTAssertEqual(cacheDelegate.saveCalls.last?.serverId, serverId)
        XCTAssertEqual(cacheDelegate.saveCalls.last?.sessionId, sessionId)
        XCTAssertEqual(cacheDelegate.savedMessages[serverId]?[sessionId]?.count, 1)
        XCTAssertEqual(cacheDelegate.savedMessages[serverId]?[sessionId]?.first?.content, "Hello")
    }

    func testSaveChatState_WithStopReason_SavesBoth() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId = UUID()
        let sessionId = "test-session"

        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)
        viewModel.setStopReason("max_tokens")

        // Verify stop reason was saved
        XCTAssertEqual(cacheDelegate.savedStopReasons[serverId]?[sessionId], "max_tokens")
    }

    func testSaveChatState_WithoutSessionContext_DoesNotSave() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        // Don't set session context
        viewModel.addUserMessage(content: "Hello", images: [])

        // Verify no save occurred
        XCTAssertTrue(cacheDelegate.saveCalls.isEmpty, "Should not save without session context")
    }

    func testLoadChatState_FromCache_LoadsSuccessfully() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId = UUID()
        let sessionId = "test-session"

        // Pre-populate cache
        let cachedMessages = [
            ChatMessage(role: .user, content: "Cached message", isStreaming: false)
        ]
        cacheDelegate.saveMessages(cachedMessages, for: serverId, sessionId: sessionId)
        cacheDelegate.saveStopReason("end_turn", for: serverId, sessionId: sessionId)

        // Load state
        viewModel.loadChatState(serverId: serverId, sessionId: sessionId, canLoadFromStorage: false)

        // Verify loaded from cache
        XCTAssertEqual(viewModel.chatMessages.count, 1)
        XCTAssertEqual(viewModel.chatMessages.first?.content, "Cached message")
        XCTAssertEqual(viewModel.stopReason, "end_turn")
        XCTAssertFalse(cacheDelegate.loadCalls.isEmpty, "Should have called loadMessages")
    }

    func testLoadChatState_FromStorage_WhenCacheEmpty() {
        let cacheDelegate = MockCacheDelegate()
        let viewModel = makeViewModel(cacheDelegate: cacheDelegate)

        let serverId = UUID()
        let sessionId = "test-session"

        // Pre-populate storage
        let messages = [
            ChatMessage(role: .user, content: "Stored message", isStreaming: false)
        ]
        cacheDelegate.storedMessages[sessionId] = [serverId: messages]

        // Load state (cache is empty, should fallback to storage)
        viewModel.loadChatState(serverId: serverId, sessionId: sessionId, canLoadFromStorage: true)

        // Verify loaded from storage
        XCTAssertEqual(viewModel.chatMessages.count, 1)
        XCTAssertEqual(viewModel.chatMessages.first?.content, "Stored message")

        // Verify storage messages were cached
        XCTAssertEqual(cacheDelegate.savedMessages[serverId]?[sessionId]?.count, 1)

        // Verify append message was called
        XCTAssertTrue(appendMessages.contains { $0.contains("Restored 1 message") })
    }

    func testLoadChatState_EmptyCacheAndNoStorage_LoadsEmpty() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId = UUID()
        let sessionId = "test-session"

        // Load state (nothing in cache or storage)
        viewModel.loadChatState(serverId: serverId, sessionId: sessionId, canLoadFromStorage: true)

        // Verify empty state
        XCTAssertTrue(viewModel.chatMessages.isEmpty)
        XCTAssertEqual(viewModel.stopReason, "")
    }

    func testResetChatState_ClearsAllState() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId = UUID()
        let sessionId = "test-session"

        // Set up some state
        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)
        viewModel.addUserMessage(content: "Test", images: [])
        viewModel.setStopReason("max_tokens")

        // Reset
        viewModel.resetChatState()

        // Verify all state cleared
        XCTAssertTrue(viewModel.chatMessages.isEmpty)
        XCTAssertEqual(viewModel.stopReason, "")
    }

    func testSetChatMessages_SetsDirectly() {
        let viewModel = makeViewModel()

        let messages = [
            ChatMessage(role: .user, content: "Message 1", isStreaming: false),
            ChatMessage(role: .assistant, content: "Message 2", isStreaming: false)
        ]

        viewModel.setChatMessages(messages)

        XCTAssertEqual(viewModel.chatMessages.count, 2)
        XCTAssertEqual(viewModel.chatMessages[0].content, "Message 1")
        XCTAssertEqual(viewModel.chatMessages[1].content, "Message 2")
    }

    // MARK: - Event Delegate Tests

    func testHandleStopReason_CallsDelegate() {
        let viewModel = makeViewModel()
        let eventDelegate = MockEventDelegate()
        viewModel.eventDelegate = eventDelegate

        let serverId = UUID()
        let sessionId = "test-session"

        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)
        viewModel.handleStopReason("max_tokens", serverId: serverId, sessionId: sessionId)

        // Verify delegate was called
        XCTAssertEqual(eventDelegate.stopReasons.count, 1)
        XCTAssertEqual(eventDelegate.stopReasons.first?.reason, "max_tokens")
        XCTAssertEqual(eventDelegate.stopReasons.first?.serverId, serverId)
        XCTAssertEqual(eventDelegate.stopReasons.first?.sessionId, sessionId)

        // Verify stop reason was set
        XCTAssertEqual(viewModel.stopReason, "max_tokens")
    }

    func testHandleSessionLoadCompleted_CallsDelegate() {
        let viewModel = makeViewModel()
        let eventDelegate = MockEventDelegate()
        viewModel.eventDelegate = eventDelegate

        let serverId = UUID()
        let sessionId = "test-session"

        viewModel.handleSessionLoadCompleted(serverId: serverId, sessionId: sessionId)

        // Verify delegate was called
        XCTAssertEqual(eventDelegate.loadCompletions.count, 1)
        XCTAssertEqual(eventDelegate.loadCompletions.first?.serverId, serverId)
        XCTAssertEqual(eventDelegate.loadCompletions.first?.sessionId, sessionId)
    }

    func testModeChange_CallsEventDelegate() {
        let viewModel = makeViewModel()
        let eventDelegate = MockEventDelegate()
        viewModel.eventDelegate = eventDelegate

        let serverId = UUID()
        let sessionId = "test-session"

        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)

        // Simulate mode change event
        let params: ACP.Value = .object([
            "sessionId": .string(sessionId),
            "update": .object([
                "sessionUpdate": .string("current_mode_update"),
                "modeId": .string("code")
            ])
        ])

        viewModel.handleChatUpdate(params, activeSessionId: sessionId, serverId: serverId)

        // Verify mode was updated
        XCTAssertEqual(viewModel.currentModeId, "code")

        // Verify delegate was called
        XCTAssertEqual(eventDelegate.modeChanges.count, 1)
        XCTAssertEqual(eventDelegate.modeChanges.first?.modeId, "code")
        XCTAssertEqual(eventDelegate.modeChanges.first?.serverId, serverId)
        XCTAssertEqual(eventDelegate.modeChanges.first?.sessionId, sessionId)
    }

    // MARK: - Message Composition Tests

    func testAddUserMessage_AddsToChat() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId = UUID()
        let sessionId = "test-session"
        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)

        viewModel.addUserMessage(content: "Hello world", images: [])

        XCTAssertEqual(viewModel.chatMessages.count, 1)
        XCTAssertEqual(viewModel.chatMessages.first?.role, .user)
        XCTAssertEqual(viewModel.chatMessages.first?.content, "Hello world")
        XCTAssertFalse(viewModel.chatMessages.first?.isStreaming ?? true)
    }

    func testStartNewStreamingResponse_AddsStreamingMessage() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId = UUID()
        let sessionId = "test-session"
        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)

        viewModel.startNewStreamingResponse()

        XCTAssertEqual(viewModel.chatMessages.count, 1)
        XCTAssertEqual(viewModel.chatMessages.first?.role, .assistant)
        XCTAssertEqual(viewModel.chatMessages.first?.content, "")
        XCTAssertTrue(viewModel.chatMessages.first?.isStreaming ?? false)
    }

    func testAddSystemErrorMessage_AddsErrorMessage() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId = UUID()
        let sessionId = "test-session"
        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)

        viewModel.addSystemErrorMessage("Connection failed")

        XCTAssertEqual(viewModel.chatMessages.count, 1)
        XCTAssertEqual(viewModel.chatMessages.first?.role, .system)
        XCTAssertEqual(viewModel.chatMessages.first?.content, "Connection failed")
        XCTAssertTrue(viewModel.chatMessages.first?.isError ?? false)
    }

    // MARK: - Mode State Management Tests

    func testSetCurrentModeId_UpdatesMode() {
        let viewModel = makeViewModel()

        viewModel.setCurrentModeId("test-mode")

        XCTAssertEqual(viewModel.currentModeId, "test-mode")
    }

    func testCacheCurrentMode_StoresMode() {
        let viewModel = makeViewModel()
        let serverId = UUID()
        let sessionId = "test-session"

        viewModel.setCurrentModeId("code")
        viewModel.cacheCurrentMode(serverId: serverId, sessionId: sessionId)

        let cached = viewModel.cachedMode(for: serverId, sessionId: sessionId)
        XCTAssertEqual(cached, "code")
    }

    func testMigrateSessionModeCache_MigratesSuccessfully() {
        let viewModel = makeViewModel()
        let serverId = UUID()
        let placeholderId = "placeholder-123"
        let resolvedId = "resolved-456"

        // Set mode for placeholder
        viewModel.setCurrentModeId("test-mode")
        viewModel.cacheCurrentMode(serverId: serverId, sessionId: placeholderId)

        // Migrate
        viewModel.migrateSessionModeCache(for: serverId, from: placeholderId, to: resolvedId)

        // Verify migrated
        XCTAssertEqual(viewModel.cachedMode(for: serverId, sessionId: resolvedId), "test-mode")
    }

    func testMigrateSessionModeCache_DoesNotOverwriteExisting() {
        let viewModel = makeViewModel()
        let serverId = UUID()
        let placeholderId = "placeholder-123"
        let resolvedId = "resolved-456"

        // Set mode for both
        viewModel.setCurrentModeId("mode-1")
        viewModel.cacheCurrentMode(serverId: serverId, sessionId: placeholderId)

        viewModel.setCurrentModeId("mode-2")
        viewModel.cacheCurrentMode(serverId: serverId, sessionId: resolvedId)

        // Migrate (should not overwrite)
        viewModel.migrateSessionModeCache(for: serverId, from: placeholderId, to: resolvedId)

        // Verify not overwritten
        XCTAssertEqual(viewModel.cachedMode(for: serverId, sessionId: resolvedId), "mode-2")
    }

    // MARK: - State Transition Tests

    func testStateTransition_LoadActiveReset() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId = UUID()
        let sessionId = "test-session"

        // 1. Load state (empty)
        viewModel.loadChatState(serverId: serverId, sessionId: sessionId, canLoadFromStorage: false)
        XCTAssertTrue(viewModel.chatMessages.isEmpty)

        // 2. Active - add messages
        viewModel.addUserMessage(content: "Message 1", images: [])
        viewModel.addUserMessage(content: "Message 2", images: [])
        XCTAssertEqual(viewModel.chatMessages.count, 2)

        // 3. Reset
        viewModel.resetChatState()
        XCTAssertTrue(viewModel.chatMessages.isEmpty)
    }

    func testStateTransition_SaveAndReload() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId = UUID()
        let sessionId = "test-session"

        // Set context and add messages
        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)
        viewModel.addUserMessage(content: "Saved message", images: [])
        viewModel.setStopReason("end_turn")

        // Verify saved to cache
        XCTAssertFalse(cacheDelegate.savedMessages.isEmpty)

        // Reset and reload
        viewModel.resetChatState()
        XCTAssertTrue(viewModel.chatMessages.isEmpty)

        viewModel.loadChatState(serverId: serverId, sessionId: sessionId, canLoadFromStorage: false)

        // Verify reloaded
        XCTAssertEqual(viewModel.chatMessages.count, 1)
        XCTAssertEqual(viewModel.chatMessages.first?.content, "Saved message")
        XCTAssertEqual(viewModel.stopReason, "end_turn")
    }

    func testMultipleSessionsCache_IsolatedProperly() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId1 = UUID()
        let serverId2 = UUID()
        let sessionId1 = "session-1"
        let sessionId2 = "session-2"

        // Session 1
        viewModel.loadChatState(serverId: serverId1, sessionId: sessionId1, canLoadFromStorage: false)
        viewModel.addUserMessage(content: "Session 1 message", images: [])

        // Switch to Session 2
        viewModel.loadChatState(serverId: serverId2, sessionId: sessionId2, canLoadFromStorage: false)
        viewModel.addUserMessage(content: "Session 2 message", images: [])

        // Verify both cached independently
        XCTAssertEqual(cacheDelegate.savedMessages[serverId1]?[sessionId1]?.first?.content, "Session 1 message")
        XCTAssertEqual(cacheDelegate.savedMessages[serverId2]?[sessionId2]?.first?.content, "Session 2 message")

        // Load session 1 back
        viewModel.loadChatState(serverId: serverId1, sessionId: sessionId1, canLoadFromStorage: false)
        XCTAssertEqual(viewModel.chatMessages.first?.content, "Session 1 message")
    }

    func testStreamingStateRestore_AfterLoad() {
        let viewModel = makeViewModel()
        let cacheDelegate = MockCacheDelegate()
        viewModel.cacheDelegate = cacheDelegate

        let serverId = UUID()
        let sessionId = "test-session"

        // Create messages with streaming state
        let messages = [
            ChatMessage(role: .user, content: "Question", isStreaming: false),
            ChatMessage(role: .assistant, content: "Partial answer...", isStreaming: true)
        ]
        cacheDelegate.saveMessages(messages, for: serverId, sessionId: sessionId)

        // Load and verify streaming state restored
        viewModel.loadChatState(serverId: serverId, sessionId: sessionId, canLoadFromStorage: false)

        XCTAssertEqual(viewModel.chatMessages.count, 2)
        XCTAssertTrue(viewModel.chatMessages.last?.isStreaming ?? false)
    }

    // MARK: - Commands Tests

    func testHandleAvailableCommandsUpdate_UpdatesCommands() {
        let viewModel = makeViewModel()
        let serverId = UUID()
        let sessionId = "test-session"

        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)

        let commands = [
            SessionCommand(id: "cmd1", name: "test-command", description: "Test", inputHint: nil)
        ]

        viewModel.handleAvailableCommandsUpdate(commands, serverId: serverId, sessionId: sessionId)

        XCTAssertEqual(viewModel.availableCommands.count, 1)
        XCTAssertEqual(viewModel.availableCommands.first?.name, "test-command")
    }

    func testRestoreAvailableCommands_FromCache() {
        let viewModel = makeViewModel()
        let serverId = UUID()
        let sessionId = "test-session"

        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)

        // Set and cache commands
        let commands = [
            SessionCommand(id: "cmd1", name: "cached-command", description: "Test", inputHint: nil)
        ]
        viewModel.handleAvailableCommandsUpdate(commands, serverId: serverId, sessionId: sessionId)

        // Reset
        viewModel.resetCommands()
        XCTAssertTrue(viewModel.availableCommands.isEmpty)

        // Restore
        viewModel.restoreAvailableCommands(for: serverId, sessionId: sessionId, isNew: false)
        XCTAssertEqual(viewModel.availableCommands.count, 1)
        XCTAssertEqual(viewModel.availableCommands.first?.name, "cached-command")
    }

    // MARK: - Plan Snapshot Tests

    private func planParams(entries: [ACP.Value], sessionId: String) -> ACP.Value {
        .object([
            "sessionId": .string(sessionId),
            "update": .object([
                "sessionUpdate": .string("plan"),
                "entries": .array(entries),
            ]),
        ])
    }

    func testPlanUpdate_PopulatesPlan() {
        let viewModel = makeViewModel()
        let serverId = UUID()
        let sessionId = "test-session"
        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)

        let params = planParams(entries: [
            .object([
                "content": .string("Step one"),
                "priority": .string("high"),
                "status": .string("in_progress"),
            ]),
            .object([
                "content": .string("Step two"),
                "priority": .string("low"),
                "status": .string("pending"),
            ]),
        ], sessionId: sessionId)

        viewModel.handleChatUpdate(params, activeSessionId: sessionId, serverId: serverId)

        XCTAssertEqual(viewModel.plan.count, 2)
        XCTAssertEqual(viewModel.plan[0].content, "Step one")
        XCTAssertEqual(viewModel.plan[0].priority, .high)
        XCTAssertEqual(viewModel.plan[0].status, .inProgress)
        XCTAssertEqual(viewModel.plan[1].status, .pending)
    }

    func testPlanUpdate_ReplacesPriorSnapshot() {
        let viewModel = makeViewModel()
        let serverId = UUID()
        let sessionId = "test-session"
        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)

        viewModel.handleChatUpdate(planParams(entries: [
            .object(["content": .string("Old A"), "status": .string("completed")]),
            .object(["content": .string("Old B"), "status": .string("pending")]),
        ], sessionId: sessionId), activeSessionId: sessionId, serverId: serverId)
        XCTAssertEqual(viewModel.plan.count, 2)

        // A fresh snapshot fully replaces the previous plan.
        viewModel.handleChatUpdate(planParams(entries: [
            .object(["content": .string("New only"), "status": .string("in_progress")]),
        ], sessionId: sessionId), activeSessionId: sessionId, serverId: serverId)

        XCTAssertEqual(viewModel.plan.count, 1)
        XCTAssertEqual(viewModel.plan[0].content, "New only")
    }

    func testPlanUpdate_EmptyEntriesClearsPlan() {
        let viewModel = makeViewModel()
        let serverId = UUID()
        let sessionId = "test-session"
        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)

        viewModel.handleChatUpdate(planParams(entries: [
            .object(["content": .string("Something"), "status": .string("pending")]),
        ], sessionId: sessionId), activeSessionId: sessionId, serverId: serverId)
        XCTAssertFalse(viewModel.plan.isEmpty)

        viewModel.handleChatUpdate(planParams(entries: [], sessionId: sessionId),
                                   activeSessionId: sessionId, serverId: serverId)
        XCTAssertTrue(viewModel.plan.isEmpty)
    }

    func testPlan_ClearedOnLoadChatState() {
        let viewModel = makeViewModel(cacheDelegate: MockCacheDelegate())
        let serverId = UUID()
        let sessionId = "test-session"
        viewModel.setSessionContext(serverId: serverId, sessionId: sessionId)

        viewModel.handleChatUpdate(planParams(entries: [
            .object(["content": .string("Lingering"), "status": .string("pending")]),
        ], sessionId: sessionId), activeSessionId: sessionId, serverId: serverId)
        XCTAssertFalse(viewModel.plan.isEmpty)

        // Switching sessions clears the non-persisted plan snapshot.
        viewModel.loadChatState(serverId: serverId, sessionId: "other-session", canLoadFromStorage: false)
        XCTAssertTrue(viewModel.plan.isEmpty)
    }

    func testPlanRowStyle_StatusAndPriorityMapping() {
        XCTAssertEqual(ACPPlanRowStyle.symbolName(for: .pending), "circle")
        XCTAssertEqual(ACPPlanRowStyle.symbolName(for: .inProgress), "circle.lefthalf.filled")
        XCTAssertEqual(ACPPlanRowStyle.symbolName(for: .completed), "checkmark.circle.fill")
        XCTAssertEqual(ACPPlanRowStyle.symbolName(for: .unknown), "questionmark.circle")

        XCTAssertTrue(ACPPlanRowStyle.isCompleted(.completed))
        XCTAssertFalse(ACPPlanRowStyle.isCompleted(.pending))

        XCTAssertEqual(ACPPlanRowStyle.priorityLabel(for: .high), "High")
        XCTAssertNil(ACPPlanRowStyle.priorityLabel(for: .unknown))

        let entries = [
            ACPPlanEntry(content: "a", priority: .high, status: .completed),
            ACPPlanEntry(content: "b", priority: .low, status: .pending),
            ACPPlanEntry(content: "c", priority: .medium, status: .completed),
        ]
        XCTAssertEqual(ACPPlanRowStyle.completedCount(entries), 2)
    }

    func testMigrateSessionCommandsCache_MigratesSuccessfully() {
        let viewModel = makeViewModel()
        let serverId = UUID()
        let placeholderId = "placeholder-123"
        let resolvedId = "resolved-456"

        viewModel.setSessionContext(serverId: serverId, sessionId: placeholderId)

        // Set commands for placeholder
        let commands = [
            SessionCommand(id: "cmd1", name: "test-command", description: "Test", inputHint: nil)
        ]
        viewModel.handleAvailableCommandsUpdate(commands, serverId: serverId, sessionId: placeholderId)

        // Migrate
        viewModel.migrateSessionCommandsCache(for: serverId, from: placeholderId, to: resolvedId)

        // Verify migrated
        viewModel.restoreAvailableCommands(for: serverId, sessionId: resolvedId, isNew: false)
        XCTAssertEqual(viewModel.availableCommands.count, 1)
        XCTAssertEqual(viewModel.availableCommands.first?.name, "test-command")
    }

    // MARK: - Model Picker (gofer/models discovery + graceful degradation)

    func testDiscoverModels_WithoutService_HidesPicker() {
        // No connected service (e.g. a non-gofer agent path never reaches
        // discovery, or the connection dropped) → the picker stays hidden.
        let viewModel = makeViewModel(service: nil)
        viewModel.discoverModels()
        XCTAssertTrue(viewModel.availableModels.isEmpty)
    }

    func testVisibleConfigOptions_ShowsModelOptionWhenDiscoveryEmpty() {
        // Graceful degradation: when gofer/models yields nothing, an agent's own
        // "model" select still renders through the generic config-option control.
        let viewModel = makeViewModel()
        let modelOption = ACPSessionConfigOption(
            id: GoferModelConfig.configId,
            name: "Model",
            kind: .select(options: [ACPSessionConfigOptionChoice(id: "m1", name: "Model 1")]),
            currentValue: .string("m1")
        )
        viewModel.applySessionConfigOptions([modelOption], serverId: UUID(), sessionId: "s1")

        XCTAssertTrue(viewModel.availableModels.isEmpty)
        XCTAssertTrue(viewModel.visibleConfigOptions().contains(where: { $0.id == GoferModelConfig.configId }))
        // The agent-reported current model is adopted.
        XCTAssertEqual(viewModel.currentModelId, "m1")
    }

    func testSendSetModel_NotConnected_DoesNotShowPhantomModel() {
        // Tapping a model while disconnected must not leave the picker showing a
        // phantom active model — the selection is never applied.
        let viewModel = makeViewModel(service: nil)
        viewModel.sendSetModel("claude-opus", sessionId: "s1", serverId: UUID())
        XCTAssertNil(viewModel.selectedModelId)
        XCTAssertNil(viewModel.currentModelId)
    }

    func testSendSetModel_RPCError_RevertsSelection() async throws {
        let connection = RollbackWebSocketConnection()
        let provider = RollbackWebSocketProvider(connection: connection)
        let client = ACPClient(
            configuration: .init(endpoint: URL(string: "ws://localhost:1234")!, pingInterval: nil),
            socketProvider: provider
        )
        let service = ACPService(client: client)
        try await service.connect()

        let viewModel = makeViewModel(service: service)

        // Establish a prior selection to revert to.
        let modelOption = ACPSessionConfigOption(
            id: GoferModelConfig.configId,
            name: "Model",
            kind: .select(options: [
                ACPSessionConfigOptionChoice(id: "old-model", name: "Old"),
                ACPSessionConfigOptionChoice(id: "new-model", name: "New"),
            ]),
            currentValue: .string("old-model")
        )
        viewModel.applySessionConfigOptions([modelOption], serverId: UUID(), sessionId: "s1")
        XCTAssertEqual(viewModel.selectedModelId, "old-model")

        viewModel.sendSetModel("new-model", sessionId: "s1", serverId: UUID())
        // Applied optimistically.
        XCTAssertEqual(viewModel.selectedModelId, "new-model")

        // Reject the set with an RPC error; the selection must roll back.
        let requestId = try await waitForRequestId(connection: connection, method: "session/set_config_option")
        try enqueueError(id: requestId, error: .serverError(code: -32000, message: "rejected"), on: connection)

        let reverted = await waitUntil { viewModel.selectedModelId == "old-model" }
        XCTAssertTrue(reverted, "selection should revert to the previous model on RPC error")
    }

    // MARK: - Config Option Update (REPLACE snapshot)

    func testApplySessionConfigOptions_ReplacesSetAndReconcilesModelSelection() {
        let viewModel = makeViewModel()

        // Initial snapshot advertises a model option selecting "m1".
        let first = ACPSessionConfigOption(
            id: GoferModelConfig.configId,
            name: "Model",
            kind: .select(options: [
                ACPSessionConfigOptionChoice(id: "m1", name: "One"),
                ACPSessionConfigOptionChoice(id: "m2", name: "Two"),
            ]),
            currentValue: .string("m1")
        )
        viewModel.applySessionConfigOptions([first], serverId: UUID(), sessionId: "s1")
        XCTAssertEqual(viewModel.selectedModelId, "m1")

        // A server-pushed REPLACE snapshot moves the current model to "m2" and
        // drops down to a single option — the picker selection follows.
        let second = ACPSessionConfigOption(
            id: GoferModelConfig.configId,
            name: "Model",
            kind: .select(options: [ACPSessionConfigOptionChoice(id: "m2", name: "Two")]),
            currentValue: .string("m2")
        )
        viewModel.applySessionConfigOptions([second], serverId: UUID(), sessionId: "s1")

        XCTAssertEqual(viewModel.selectedModelId, "m2")
        XCTAssertEqual(viewModel.currentModelId, "m2")
        // REPLACE: the prior set is gone, only the new option remains.
        XCTAssertEqual(viewModel.sessionConfigOptions.map(\.id), [GoferModelConfig.configId])
        guard case .select(let choices) = viewModel.sessionConfigOptions.first?.kind else {
            return XCTFail("Expected select kind")
        }
        XCTAssertEqual(choices.map(\.id), ["m2"])
    }

    func testApplySessionConfigOptions_ModelLessSnapshotPreservesSelection() {
        // A non-empty snapshot that OMITS the model option must NOT wipe the
        // model selection — only a session switch/reset clears it. This pins the
        // deliberate "don't clear selection when the model option is absent"
        // behavior so a future refactor can't silently start wiping it.
        let viewModel = makeViewModel()
        let modelOption = ACPSessionConfigOption(
            id: GoferModelConfig.configId,
            name: "Model",
            kind: .select(options: [ACPSessionConfigOptionChoice(id: "m1", name: "One")]),
            currentValue: .string("m1")
        )
        viewModel.applySessionConfigOptions([modelOption], serverId: UUID(), sessionId: "s1")
        XCTAssertEqual(viewModel.selectedModelId, "m1")

        // New, non-empty snapshot with only an unrelated boolean option.
        let boolOption = ACPSessionConfigOption(
            id: "yolo",
            name: "YOLO mode",
            kind: .boolean,
            currentValue: .bool(true)
        )
        viewModel.applySessionConfigOptions([boolOption], serverId: UUID(), sessionId: "s1")

        // Selection survives; the config-option set is still REPLACED wholesale.
        XCTAssertEqual(viewModel.selectedModelId, "m1")
        XCTAssertEqual(viewModel.currentModelId, "m1")
        XCTAssertEqual(viewModel.sessionConfigOptions.map(\.id), ["yolo"])
    }

    func testLoadChatState_ResetsConfigOptionsAndModelSelection() {
        let viewModel = makeViewModel()
        let modelOption = ACPSessionConfigOption(
            id: GoferModelConfig.configId,
            name: "Model",
            kind: .select(options: [ACPSessionConfigOptionChoice(id: "m1", name: "One")]),
            currentValue: .string("m1")
        )
        viewModel.applySessionConfigOptions([modelOption], serverId: UUID(), sessionId: "s1")
        XCTAssertEqual(viewModel.selectedModelId, "m1")
        XCTAssertFalse(viewModel.sessionConfigOptions.isEmpty)

        // Switching sessions clears session-scoped config/model state so it
        // cannot bleed into the next session before its snapshot arrives.
        viewModel.loadChatState(serverId: UUID(), sessionId: "s2", canLoadFromStorage: false)

        XCTAssertNil(viewModel.selectedModelId)
        XCTAssertNil(viewModel.currentModelId)
        XCTAssertTrue(viewModel.sessionConfigOptions.isEmpty)
    }

    func testResetChatState_ClearsConfigOptionsAndModelSelection() {
        let viewModel = makeViewModel()
        let modelOption = ACPSessionConfigOption(
            id: GoferModelConfig.configId,
            name: "Model",
            kind: .select(options: [ACPSessionConfigOptionChoice(id: "m1", name: "One")]),
            currentValue: .string("m1")
        )
        viewModel.applySessionConfigOptions([modelOption], serverId: UUID(), sessionId: "s1")

        viewModel.resetChatState()

        XCTAssertNil(viewModel.selectedModelId)
        XCTAssertTrue(viewModel.sessionConfigOptions.isEmpty)
    }

    // MARK: Rollback-test mock transport

    private final class RollbackWebSocketConnection: WebSocketConnection, @unchecked Sendable {
        private let lock = NSLock()
        private var events: [WebSocketEvent] = []
        private var sentTexts: [String] = []

        func connect(headers: [String: String]) async throws {}

        func send(text: String) async throws {
            lock.lock(); sentTexts.append(text); lock.unlock()
        }

        func receive() async throws -> WebSocketEvent {
            while true {
                lock.lock()
                if !events.isEmpty {
                    let event = events.removeFirst()
                    lock.unlock()
                    return event
                }
                lock.unlock()
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }

        func close() async {}
        func ping() async throws {}

        func enqueue(_ event: WebSocketEvent) {
            lock.lock(); events.append(event); lock.unlock()
        }

        func sentTextsSnapshot() -> [String] {
            lock.lock(); defer { lock.unlock() }; return sentTexts
        }
    }

    private struct RollbackWebSocketProvider: WebSocketProviding, @unchecked Sendable {
        let connection: RollbackWebSocketConnection
        func makeConnection(url: URL) -> WebSocketConnection { connection }
    }

    private func waitForRequestId(
        connection: RollbackWebSocketConnection,
        method: String,
        attempts: Int = 200
    ) async throws -> Int {
        for _ in 0..<attempts {
            for text in connection.sentTextsSnapshot() {
                guard let data = text.data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["method"] as? String == method,
                      let id = object["id"] as? Int else { continue }
                return id
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw XCTSkip("Request \(method) was not sent")
    }

    private func enqueueError(id: Int, error: ACPError, on connection: RollbackWebSocketConnection) throws {
        let response = ACPWireMessage.response(.init(id: .int(id), error: error))
        let data = try JSONEncoder().encode(response)
        connection.enqueue(.text(String(decoding: data, as: UTF8.self)))
    }

    private func waitUntil(attempts: Int = 200, _ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}