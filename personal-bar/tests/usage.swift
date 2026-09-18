// Synthetic data only: never copy authenticated provider responses here.
let now = ISO8601DateFormatter().date(from: "2026-09-08T12:00:00Z")!
func parseFixture(_ json: String) -> [String: AIUsageState] {
    parseAIUsage(Data(json.utf8), now: now)!
}
let states = parseFixture("""
[
 {"provider":"codex","error":{"message":"expired account"}},
 {"provider":"unrelated","usage":{"primary":{"usedPercent":99}}},
 {"provider":"codex","usage":{"updatedAt":"2026-09-08T11:59:00Z","primary":null,"secondary":{"usedPercent":22,"windowMinutes":10080},"extraRateWindows":[{"title":"Codex Spark","window":{"usedPercent":42}}],"codexResetCredits":{"availableCount":2}}},
 {"provider":"claude","usage":{"updatedAt":"2026-09-08T11:59:00.000Z","primary":{"usedPercent":18,"windowMinutes":300},"secondary":{"usedPercent":9},"tertiary":{"usedPercent":50,"resetsAt":"2026-09-09T12:00:00Z"}}},
 {"provider":"cursor","error":{"message":"no session"}}
]
""")
assert(states["codex"]?.usage?.windows.map(\.usedPercent).max() == 42)
assert(states["codex"]?.usage?.resetCredits == 2)
assert(states["codex"]?.usage?.windows.last?.title == "Spark")
assert(states["claude"]?.usage?.windows.map(\.usedPercent).max() == 50)
assert(states["claude"]?.usage?.windows.count == 3)
assert(states["claude"]?.usage?.windows.last?.resetDescription.isEmpty == false)
assert(states["cursor"]?.usage?.windows.map(\.usedPercent).max() == nil)
assert(states["cursor"]?.status.contains("sign in") == true)
assert(parseFixture("[]").count == 3)
assert(parseFixture("[]")["codex"]?.usage?.windows.map(\.usedPercent).max() == nil)
assert(parseAIUsage(Data("{}".utf8), now: now) == nil)
assert(parseAIUsage(Data("invalid".utf8), now: now) == nil)
for timestamp in ["2026-09-08T11:00:00Z", "invalid", "2026-09-09T12:00:00Z"] {
    let result = parseFixture("""
    [{"provider":"codex","usage":{"updatedAt":"\(timestamp)","primary":{"usedPercent":10}}}]
    """)
    assert(result["codex"]?.usage?.windows.map(\.usedPercent).max() == nil)
    assert(result["codex"]?.status.hasPrefix("Stale") == true)
}
let recovery = parseFixture("""
[{"provider":"codex","usage":{"updatedAt":"2026-09-07T12:00:00Z","primary":{"usedPercent":90}}},
 {"provider":"codex","usage":{"updatedAt":"2026-09-08T12:00:00Z","primary":{"usedPercent":0}}}]
""")
assert(recovery["codex"]?.usage?.windows.map(\.usedPercent).max() == 0)
assert(recovery["claude"]?.usage?.windows.map(\.usedPercent).max() == nil)
assert(parseCodexWindow(["usedPercent": true], fallbackTitle: "test") == nil)
assert(parseCodexWindow(["usedPercent": Double.infinity], fallbackTitle: "test") == nil)
assert(parseCodexWindow(["usedPercent": 1e100], fallbackTitle: "test")?.usedPercent == 100)
assert(parseCodexWindow(["usedPercent": -5], fallbackTitle: "test")?.usedPercent == 0)
assert(parseCodexWindow(["usedPercent": "5"], fallbackTitle: "test") == nil)
print("AI usage fixtures passed: provider isolation, account recovery, all windows, stale/missing/error states, numeric validation")

let sequenceData = Data("""
[{"provider":"codex","usage":{"updatedAt":"2026-09-08T12:00:00Z","primary":{"usedPercent":23}}},
 {"provider":"claude","usage":{"updatedAt":"2026-09-08T12:00:00Z","primary":{"usedPercent":18}}}]
""".utf8)
let initial = reduceAIUsage(previous: [:], data: sequenceData, now: now)
let aged = reduceAIUsage(previous: initial, data: sequenceData, now: now.addingTimeInterval(360))
guard aged["codex"]?.usage?.windows.map(\.usedPercent).max() == 23 && aged["claude"]?.usage?.windows.map(\.usedPercent).max() == 18 else {
    print("FAIL: reducer drops both percentages at cache age 6m")
    exit(1)
}

assert(aged["codex"]?.stale == true)
let outage = reduceAIUsage(previous: aged, data: nil, now: now.addingTimeInterval(420))
assert(outage["codex"]?.usage?.windows.map(\.usedPercent).max() == 23 && outage["claude"]?.usage?.windows.map(\.usedPercent).max() == 18)
assert(outage["codex"]?.stale == true)
assert(outage["codex"]?.detail.contains("unavailable") == true)
assert(outage["codex"]?.updatedAt == now)
let partialData = Data("""
[{"provider":"codex","error":{"message":"temporary"}},
 {"provider":"claude","usage":{"updatedAt":"2026-09-08T12:08:00Z","primary":{"usedPercent":20}}}]
""".utf8)
let partial = reduceAIUsage(previous: outage, data: partialData, now: now.addingTimeInterval(480))
assert(partial["codex"]?.usage?.windows.map(\.usedPercent).max() == 23 && partial["codex"]?.stale == true)
assert(partial["claude"]?.usage?.windows.map(\.usedPercent).max() == 20 && partial["claude"]?.stale == false)
let recoveredData = Data(String(data: sequenceData, encoding: .utf8)!.replacingOccurrences(of: "12:00:00", with: "12:09:00").utf8)
let recovered = reduceAIUsage(previous: partial, data: recoveredData, now: now.addingTimeInterval(540))
assert(recovered["codex"]?.usage?.windows.map(\.usedPercent).max() == 23 && recovered["codex"]?.stale == false)
let expired = reduceAIUsage(previous: recovered, data: nil, now: now.addingTimeInterval(4140))
assert(expired["codex"]?.usage?.windows.map(\.usedPercent).max() == nil)
assert(expired["claude"]?.usage?.windows.map(\.usedPercent).max() == nil)
print("AI reducer sequence passed: success, aged cache, outage, partial failure, recovery, expiry")
let older = reduceAIUsage(previous: recovered, data: sequenceData, now: now.addingTimeInterval(600))
assert(older["codex"]?.updatedAt == recovered["codex"]?.updatedAt)
assert(older["codex"]?.stale == true)
let malformed = reduceAIUsage(previous: recovered, data: Data("invalid".utf8), now: now.addingTimeInterval(600))
assert(malformed["codex"]?.usage?.windows.map(\.usedPercent).max() == 23 && malformed["codex"]?.stale == true)
let missing = reduceAIUsage(previous: recovered, data: Data("[]".utf8), now: now.addingTimeInterval(600))
assert(missing["codex"]?.usage?.windows.map(\.usedPercent).max() == 23 && missing["codex"]?.stale == true)
assert(missing["cursor"]?.usage?.windows.map(\.usedPercent).max() == nil)
assert(aged["codex"]?.detail.contains("Cached") == true)
assert(aged["codex"]?.detail.contains("updated") == true)

let cursorCLI = Data("""
[{"provider":"cursor","usage":{"updatedAt":"2026-09-08T12:00:00Z","primary":{"usedPercent":26.4488},"secondary":{"usedPercent":23.7314},"tertiary":{"usedPercent":40.715}}}]
""".utf8)
let connected = reduceAIUsage(previous: initial, data: cursorCLI, now: now, providerIDs: ["cursor"])
assert(connected["cursor"]?.usage?.windows.map(\.usedPercent).max() == 40)
assert(connected["codex"] == initial["codex"] && connected["claude"] == initial["claude"])
let othersAfterCursor = reduceAIUsage(previous: connected, data: sequenceData, now: now, providerIDs: ["codex", "claude"])
assert(othersAfterCursor["cursor"] == connected["cursor"])
let cliFailure = reduceAIUsage(previous: othersAfterCursor, data: nil, now: now.addingTimeInterval(60), providerIDs: ["cursor"])
assert(cliFailure["cursor"]?.usage?.windows.map(\.usedPercent).max() == 40 && cliFailure["cursor"]?.stale == true)
assert(cliFailure["codex"] == othersAfterCursor["codex"])
let fullCLI = Data("""
[{"provider":"codex","usage":{"updatedAt":"2026-09-08T12:00:00Z","primary":{"usedPercent":11},"secondary":{"usedPercent":22}}},
 {"provider":"claude","usage":{"updatedAt":"2026-09-08T12:00:00Z","primary":{"usedPercent":18}}},
 {"provider":"cursor","usage":{"updatedAt":"2026-09-08T12:00:00Z","tertiary":{"usedPercent":41}}}]
""".utf8)
let unified = reduceAIUsage(previous: cliFailure, data: fullCLI, now: now)
assert(unified["codex"]?.usage?.windows.map(\.usedPercent).max() == 22)
assert(unified["claude"]?.usage?.windows.map(\.usedPercent).max() == 18)
assert(unified["cursor"]?.usage?.windows.map(\.usedPercent).max() == 41)
let unifiedOutage = reduceAIUsage(previous: unified, data: nil, now: now.addingTimeInterval(60))
assert(unifiedOutage.values.allSatisfy { $0.stale == true })
assert(unifiedOutage["codex"]?.usage?.windows.map(\.usedPercent).max() == 22)
print("CLI source merge passed: partial provider updates, full usage payload, outage retention")
let echoed = codexbarCLIUsage(executable: "/bin/echo", arguments: ["ok"])
assert(echoed == Data("ok\n".utf8))
assert(codexbarCLIUsage(executable: "/usr/bin/false", arguments: []) == nil)
assert(codexbarCLIUsage(executable: "/missing/codexbar", arguments: []) == nil)
let started = ProcessInfo.processInfo.systemUptime
assert(codexbarCLIUsage(executable: "/bin/sleep", arguments: ["5"], timeout: 0.1) == nil)
assert(ProcessInfo.processInfo.systemUptime - started < 1)
assert(codexbarCLIUsage(executable: "/usr/bin/yes", arguments: [], outputLimit: 1024) == nil)
print("CodexBar process passed: success, exit failure, missing executable, bounded timeout/output")
if CommandLine.arguments.contains("--live") || CommandLine.arguments.contains("--live-cursor") {
    let liveNow = Date()
    let live = reduceAIUsage(previous: [:], data: codexbarCLIUsage(), now: liveNow)
    for provider in aiProviders {
        guard let reserve = live[provider.id]?.reserve else {
            print("FAIL: live production \(provider.name) retrieval has no reserve")
            exit(1)
        }
        let horizon = reserve.horizon(now: liveNow)
        let pill = horizon.map { "\(reserve.figure) \($0.tag)" } ?? reserve.figure
        let phrase = horizon.map { " · \($0.phrase)" } ?? ""
        print("Live production \(provider.name) retrieval PASS: \(reserve.detail)\(phrase) · pill \(pill)")
    }
}

// Reserve checks use the real parser without adding synthetic fields to live payloads.
let reserveData = Data("""
[{"provider":"codex","pace":{"secondary":{"deltaPercent":16,"stage":"farAhead"}},"usage":{"updatedAt":"2026-09-08T12:00:00Z","primary":{"usedPercent":99},"secondary":{"usedPercent":23},"extraRateWindows":[{"id":"codex-base-model-inference","title":"gpt-reserve","window":{"usedPercent":100}}]}},
 {"provider":"claude","pace":{"secondary":{"deltaPercent":-41,"stage":"farBehind"}},"usage":{"updatedAt":"2026-09-08T12:00:00Z","primary":{"usedPercent":99},"secondary":{"usedPercent":9},"extraRateWindows":[{"id":"unrelated","title":"Fable only","window":{"usedPercent":100}},{"id":"claude-weekly-scoped-fable","title":"Fable only","window":{"usedPercent":16,"windowMinutes":10080,"resetsAt":"2026-09-12T00:00:00Z"}}]}},
 {"provider":"cursor","pace":{"primary":{"deltaPercent":-90,"stage":"farBehind"},"tertiary":{"deltaPercent":-13,"stage":"farBehind"}},"usage":{"updatedAt":"2026-09-08T12:00:00Z","primary":{"usedPercent":99},"secondary":{"usedPercent":95},"tertiary":{"usedPercent":41.465}}}]
""".utf8)
let reserves = parseAIUsage(reserveData, now: now, workDays: nil)!
assert(reserves["codex"]?.reserve?.percent == -16)
assert(reserves["claude"]?.reserve?.percent == 34)
assert(reserves["cursor"]?.reserve?.percent == 13)
assert(reserves["codex"]?.reserve?.text == "-16%")
assert(reserves["cursor"]?.reserve?.text == "+13%")
assert(reserves["codex"]?.reserve?.figure == "-16")
assert(reserves["cursor"]?.reserve?.figure == "+13")
assert(reserves["claude"]?.reserve?.figure == "+34")
assert(reserves["claude"]?.reserve?.resetsAt == aiUsageDate("2026-09-12T00:00:00Z"))
assert(reserves["codex"]?.reserve?.resetsAt == nil)
assert(reserves["cursor"]?.reserve?.resetsAt == nil)
assert(reserves["claude"]?.reserve?.detail == "Fable weekly · 34% in reserve")
assert(reserves["codex"]?.reserve?.severity == 2)
assert(reserves["cursor"]?.reserve?.severity == 0)
assert(AIReserve(percent: -6, scope: "test").severity == 1)
assert(AIReserve(percent: 0, scope: "test").detail == "test · On pace")
assert(AIReserve(percent: 0, scope: "test").text == "0%")
assert(AIReserve(percent: 0, scope: "test").figure == "0")
assert(states["codex"]?.reserve == nil) // Never fall back to usage or an unrelated model's "reserve".
assert(states["claude"]?.reserve == nil) // Never use general Claude in place of Fable.
let reserveOutage = reduceAIUsage(previous: reserves, data: nil, now: now.addingTimeInterval(420))
for provider in aiProviders {
    assert(reserveOutage[provider.id]?.reserve == reserves[provider.id]?.reserve)
    assert(reserveOutage[provider.id]?.stale == true)
}
let reserveExpiry = reduceAIUsage(previous: reserves, data: nil, now: now.addingTimeInterval(3600))
assert(reserveExpiry.values.allSatisfy { $0.reserve == nil })
let missingScoped = reduceAIUsage(previous: reserves, data: sequenceData, now: now)
assert(missingScoped["claude"]?.reserve == nil) // New valid snapshot without the scope must not retain its old reserve.
var utc = Calendar(identifier: .gregorian)
utc.timeZone = TimeZone(secondsFromGMT: 0)!
func fable(_ used: Any, reset: String = "2026-09-12T00:00:00Z", minutes: Int = 10080,
           at: Date = now, days: Int? = nil, calendar: Calendar = utc) -> AIReserve? {
    fableReserve(["usedPercent": used, "resetsAt": reset, "windowMinutes": minutes],
                 now: at, workDays: days, calendar: calendar)
}
assert(fable(48)?.percent == 0)
assert(fable(52)?.percent == 0)
assert(fable(47.99)?.percent == 2) // Stage uses raw delta, not rounded delta.
assert(fable(52.01)?.percent == -2)
assert(fable(46.5)?.percent == 4)
assert(fable(53.5)?.percent == -4)
assert(fable(true) == nil && fable(Double.infinity) == nil)
assert(fable(10, reset: "invalid") == nil)
assert(fable(10, reset: "2026-09-08T12:00:00Z") == nil)
assert(fable(10, reset: "2026-09-16T12:00:00Z") == nil)
assert(fable(10, minutes: 300) == nil)
assert(fable(0, reset: "2026-09-15T12:00:00Z")?.percent == 0)
assert(fable(0.5, reset: "2026-09-15T11:00:00Z")?.percent == 0)
assert(fable(4, reset: "2026-09-15T11:00:00Z")?.percent == -3)
assert(fable(10, reset: "2026-09-15T11:00:00Z")?.percent == -9, "Early Fable usage stays visible")
assert(fable(100, reset: "2026-09-15T11:00:00Z")?.percent == -99) // GUI shows exhausted weekly pace.
assert(fable(0, days: 5)?.percent == 30) // Mon + half Tue / five workdays.
assert(fable(0, days: 2)?.percent == 75)
assert(fable(0, days: 7)?.percent == 50)
assert(fable(0, days: 1)?.percent == 50) // Source ignores values outside 2..<7.
assert(fable(0, reset: "2026-09-13T00:00:00Z", at: aiUsageDate("2026-09-06T12:00:00Z")!, days: 5)?.percent == 0)
assert(fable(48)?.resetsAt == aiUsageDate("2026-09-12T00:00:00Z"))
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-08T18:00:00Z")!, calendar: utc) == .today)
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-08T18:00:00Z")!, calendar: utc)?.tag == "0")
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-08T18:00:00Z")!, calendar: utc)?.phrase == "resets today")
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-09T01:00:00Z")!, calendar: utc) == .tomorrow)
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-09T01:00:00Z")!, calendar: utc)?.tag == "t")
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-09T01:00:00Z")!, calendar: utc)?.phrase == "resets tomorrow")
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-11T00:00:00Z")!, calendar: utc) == .days(3))
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-11T00:00:00Z")!, calendar: utc)?.tag == "3")
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-11T00:00:00Z")!, calendar: utc)?.phrase == "resets in 3 days")
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-17T00:00:00Z")!, calendar: utc) == .days(9))
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-17T00:00:00Z")!, calendar: utc)?.tag == "9")
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-18T00:00:00Z")!, calendar: utc) == .weeks(2))
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-18T00:00:00Z")!, calendar: utc)?.tag == "w")
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-18T00:00:00Z")!, calendar: utc)?.phrase == "resets within 2 weeks")
assert(ResetHorizon(from: now, to: aiUsageDate("2026-09-23T00:00:00Z")!, calendar: utc) == .weeks(3))
assert(ResetHorizon(from: now, to: now, calendar: utc) == nil)
assert(ResetHorizon(from: now, to: now.addingTimeInterval(-60), calendar: utc) == nil)
assert(reserves["claude"]?.reserve?.horizon(now: now, calendar: utc) == .days(4))
assert(reserves["claude"]?.reserve?.horizon(now: now, calendar: utc)?.tag == "4")
assert(reserveOutage["claude"]?.reserve?.resetsAt == reserves["claude"]?.reserve?.resetsAt)
assert(reserveOutage["claude"]?.reserve?.horizon(now: now.addingTimeInterval(420), calendar: utc) == .days(4))
assert(reserveOutage["claude"]?.reserve?.horizon(now: now.addingTimeInterval(3 * 24 * 3600), calendar: utc) == .tomorrow)
let fableBeforeReset = Data("""
[{"provider":"claude","usage":{"updatedAt":"2026-09-18T13:59:00Z","primary":{"usedPercent":4},"extraRateWindows":[{"id":"claude-weekly-scoped-fable","window":{"usedPercent":4,"windowMinutes":10080,"resetsAt":"2026-09-18T14:00:00Z"}}]}}]
""".utf8)
let beforeResetNow = aiUsageDate("2026-09-18T13:59:00Z")!
let staleFable = reduceAIUsage(previous: reduceAIUsage(previous: [:], data: fableBeforeReset, now: beforeResetNow),
                                data: nil, now: beforeResetNow.addingTimeInterval(60))
assert(staleFable["claude"]?.stale == true)
assert(staleFable["claude"]?.reserve != nil)
let fableAfterReset = Data("""
[{"provider":"claude","usage":{"updatedAt":"2026-09-18T14:01:00Z","primary":{"usedPercent":4},"extraRateWindows":[{"id":"claude-weekly-scoped-fable","window":{"usedPercent":4,"windowMinutes":10080,"resetsAt":"2026-09-25T14:00:00Z"}}]}}]
""".utf8)
let afterResetNow = aiUsageDate("2026-09-18T14:01:00Z")!
let resetFable = reduceAIUsage(previous: staleFable, data: fableAfterReset, now: afterResetNow)
assert(resetFable["claude"]?.stale == false)
assert(resetFable["claude"]?.reserve?.percent == -4)
assert(resetFable["claude"]?.reserve?.resetsAt == aiUsageDate("2026-09-25T14:00:00Z"))
assert(resetFable["claude"]?.reserve?.horizon(now: afterResetNow, calendar: utc) == .days(7), "Fresh Fable reset stays visible")
let absentFable = Data("""
[{"provider":"claude","usage":{"updatedAt":"2026-09-18T14:01:00Z","primary":{"usedPercent":4},"extraRateWindows":[]}}]
""".utf8)
let invalidFable = Data(String(data: fableAfterReset, encoding: .utf8)!
    .replacingOccurrences(of: "\"windowMinutes\":10080", with: "\"windowMinutes\":300").utf8)
assert(parseAIUsage(absentFable, now: afterResetNow)?["claude"]?.reserve == nil)
assert(parseAIUsage(invalidFable, now: afterResetNow)?["claude"]?.reserve == nil)
let scopedResets = parseAIUsage(Data("""
[{"provider":"codex","pace":{"secondary":{"deltaPercent":5,"stage":"ahead"}},"usage":{"updatedAt":"2026-09-08T12:00:00Z","secondary":{"usedPercent":10,"resetsAt":"2026-09-09T18:00:00Z"}}},
 {"provider":"cursor","pace":{"tertiary":{"deltaPercent":-8,"stage":"behind"}},"usage":{"updatedAt":"2026-09-08T12:00:00Z","tertiary":{"usedPercent":20,"resetsAt":"2026-09-10T08:00:00Z"}}}]
""".utf8), now: now, workDays: nil)!
assert(scopedResets["codex"]?.reserve?.resetsAt == aiUsageDate("2026-09-09T18:00:00Z"))
assert(scopedResets["cursor"]?.reserve?.resetsAt == aiUsageDate("2026-09-10T08:00:00Z"))
assert(scopedResets["codex"]?.reserve?.horizon(now: now, calendar: utc) == .tomorrow)
assert(scopedResets["cursor"]?.reserve?.horizon(now: now, calendar: utc) == .days(2))
var zurich = Calendar(identifier: .gregorian)
zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
let dstNow = aiUsageDate("2026-03-30T10:00:00Z")!
// Fixed seven-day window starts Monday at 01:00 local before DST; end Monday 02:00 after DST.
assert(fable(0, reset: "2026-03-31T00:00:00Z", at: dstNow, days: 5, calendar: zurich)?.percent == 88)
let onPaceData = Data(String(data: reserveData, encoding: .utf8)!
    .replacingOccurrences(of: "\"deltaPercent\":16,\"stage\":\"farAhead\"", with: "\"deltaPercent\":2,\"stage\":\"onTrack\"").utf8)
assert(parseAIUsage(onPaceData, now: now, workDays: nil)?["codex"]?.reserve?.percent == 0)
print("Reserve passed: exact provider lanes, signed labels/colors, Fable boundaries/workdays/DST, missing scopes, cache and expiry")
let cursorWithoutThirdParty = Data(String(data: reserveData, encoding: .utf8)!
    .replacingOccurrences(of: "\"tertiary\":{\"usedPercent\":41.465}", with: "\"tertiary\":null").utf8)
assert(parseAIUsage(cursorWithoutThirdParty, now: now, workDays: nil)?["cursor"]?.reserve == nil)
let cursorWithoutPace = Data(String(data: reserveData, encoding: .utf8)!
    .replacingOccurrences(of: "\"deltaPercent\":-13", with: "\"deltaPercent\":true").utf8)
assert(parseAIUsage(cursorWithoutPace, now: now, workDays: nil)?["cursor"]?.reserve == nil)
let wrongFableID = Data(String(data: reserveData, encoding: .utf8)!
    .replacingOccurrences(of: "claude-weekly-scoped-fable", with: "claude-weekly-other").utf8)
assert(parseAIUsage(wrongFableID, now: now, workDays: nil)?["claude"]?.reserve == nil)
let reserveSourceIsolation = reduceAIUsage(previous: reserves, data: nil, now: now.addingTimeInterval(60), providerIDs: ["cursor"])
assert(reserveSourceIsolation["codex"] == reserves["codex"])
assert(reserveSourceIsolation["claude"] == reserves["claude"])
assert(reserveSourceIsolation["cursor"]?.reserve == reserves["cursor"]?.reserve)
let reserveRecovery = reduceAIUsage(previous: reserveSourceIsolation, data: reserveData, now: now, providerIDs: ["cursor"])
assert(reserveRecovery["cursor"] == reserves["cursor"])
print("Reserve source isolation passed: unavailable scoped lane, malformed pace, exact Fable id, outage/recovery")
