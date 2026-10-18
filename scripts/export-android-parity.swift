import Foundation

let now = AthleteMatrix.now
func optional(_ value: Any?) -> Any { value ?? NSNull() }
func sessionJSON(_ s: SessionInput) -> [String: Any] {
    ["id": s.id, "profile": s.profile.rawValue, "start": s.startDate.timeIntervalSince1970,
     "end": s.endDate.timeIntervalSince1970, "minutes": s.durationMinutes,
     "average": optional(s.averageHeartRate), "resting": optional(s.restingHeartRate),
     "maximum": optional(s.maxHeartRate), "coverage": s.heartRateCoverage,
     "energy": optional(s.activeEnergyKilocalories), "effort": optional(s.reportedEffort),
     "override": optional(s.intensityOverride?.rawValue), "mass": optional(s.bodyMassKilograms),
     "label": s.activityLabel,
     "distribution": optional(s.heartRateDistribution.map { ["lowest": $0.lowestBPM, "seconds": $0.seconds] as [String: Any] })]
}
func contextJSON(_ c: RecoveryContext) -> [String: Any] {
    ["sleep": optional(c.sleepHours), "hrv": optional(c.heartRateVariability),
     "hrvBase": optional(c.heartRateVariabilityBaseline), "resting": optional(c.restingHeartRate),
     "restingBase": optional(c.restingHeartRateBaseline), "respiratory": optional(c.respiratoryRate),
     "respiratoryBase": optional(c.respiratoryRateBaseline),
     "nights": c.followingNights.map { n in ["date": n.date.timeIntervalSince1970,
        "sleep": optional(n.sleepHours), "hrv": optional(n.heartRateVariability),
        "resting": optional(n.restingHeartRate), "respiratory": optional(n.respiratoryRate)] as [String: Any] }]
}
func resultJSON(_ e: RecoveryEstimate) -> [String: Any] {
    ["hours": e.hours, "carried": e.carriedHours, "cost": e.recoveryCostHours,
     "total": e.totalHours, "low": e.windowLowHours, "high": e.windowHighHours,
     "load": e.load.value, "source": e.load.source.rawValue, "relative": e.relativeLoad,
     "confidence": e.confidence.rawValue, "category": e.category.rawValue,
     "factor": e.personalFactor, "standard": e.standardHours,
     "ready": e.readyAt.timeIntervalSince1970, "reasons": e.reasons]
}
var cases: [[String: Any]] = []
func add(_ name: String, _ input: SessionInput, _ baseline: RecoveryBaseline,
         context: RecoveryContext = .empty, personal: RecoveryPersonalization = .standard,
         calibration: Double = 1, carried: Double = 0, manual: Double? = nil) {
    let result = RecoveryCalculator.estimate(for: input, baseline: baseline, context: context,
        calibration: calibration, personalization: personal, carriedHours: carried, manualHours: manual, now: now)
    cases.append(["name": name, "session": sessionJSON(input), "loads": baseline.loads,
        "daily": baseline.dailyLoads, "fitness": baseline.fitnessScale, "context": contextJSON(context),
        "tier": personal.tier.rawValue, "factor": personal.factor, "calibration": calibration,
        "carried": carried, "manual": optional(manual), "expected": resultJSON(result)])
}

// The original audit matrix, collapsed only across equivalent classified sports.
// All activity codes are exported separately below, so classification cannot drift.
for code: UInt in [37, 50, 63, 52] {
    for shape in AthleteMatrix.shapes {
        for persona in AthleteMatrix.personas {
            for sensors in AthleteMatrix.sensorScenarios {
                let input = AthleteMatrix.session(code: code, shape: shape, persona: persona, sensors: sensors)
                add("matrix-standard-" + input.id, input,
                    .standard(for: input.profile, fitnessScale: persona.profile.fitnessScale))
                add("matrix-personalized-" + input.id, input,
                    persona.baseline(for: input.profile), personal: persona.personalization)
            }
        }
    }
}

let named = [RecoveryFixtures.easyWalk30, RecoveryFixtures.easyRun45, RecoveryFixtures.thresholdRun60,
    RecoveryFixtures.longRun90, RecoveryFixtures.ride45, RecoveryFixtures.strengthNoHeartRate,
    RecoveryFixtures.strengthWithEffort, RecoveryFixtures.mixedHyrox]
let contexts = [RecoveryFixtures.noContext, RecoveryFixtures.goodContext, RecoveryFixtures.poorContext,
    RecoveryContext(sleepHours: 8, heartRateVariabilityBaseline: 60, restingHeartRateBaseline: 52,
        respiratoryRateBaseline: 14, followingNights: [
            .init(date: now.addingTimeInterval(4 * 3600), sleepHours: 8.5, heartRateVariability: 74, restingHeartRate: 49, respiratoryRate: 12),
            .init(date: now.addingTimeInterval(26 * 3600), sleepHours: 4, heartRateVariability: 40, restingHeartRate: 62, respiratoryRate: 17)])]
for (index, input) in named.enumerated() {
    for (ci, context) in contexts.enumerated() {
        for carried: Double in [0, 6, 30, 100] {
            for manual: Double? in [nil, 2, 30, 120] {
                add("fixture-" + String(index) + "-" + String(ci) + "-" + String(carried) + "-" + String(describing: manual),
                    input, RecoveryBaseline(loads: [28, 34, 41, 47, 52, 58, 63, 68, 74, 86, 102, 131], profile: input.profile),
                    context: context, personal: .personalized(factor: 0.86), calibration: 1.05, carried: carried, manual: manual)
            }
        }
    }
}
for profile in WorkoutProfile.allCases {
    for intensity in SessionIntensity.allCases {
        for minutes: Double in [0, 10, 60, 180] {
            let input = RecoveryFixtures.session(id: profile.rawValue + intensity.rawValue + String(minutes),
                profile: intensity.profile(promoting: profile), minutes: minutes,
                averageHR: 175, coverage: 0.98, energy: minutes * 12, effort: 9, intensity: intensity)
            add("override-" + input.id, input, .standard(for: input.profile))
        }
    }
}
for minutes: Double in [30, 60, 120, 225] {
    for reserve in [0.55, 0.8, 0.9] {
        let samples = Array(repeating: 60 + reserve * 125 - 15, count: 30) + Array(repeating: 60 + reserve * 125 + 15, count: 30)
        let input = SessionInput(id: "distribution", profile: .endurance,
            startDate: now.addingTimeInterval(-minutes * 60), endDate: now,
            averageHeartRate: 60 + reserve * 125, restingHeartRate: 60, maxHeartRate: 185,
            heartRateCoverage: 1, heartRateDistribution: .init(samples: samples, secondsEach: minutes))
        add("distribution-" + String(minutes) + "-" + String(reserve), input, .standard(for: .endurance))
    }
}

let codes: [[String: Any]] = (WorkoutClassifier.ActivityCode.allCases.map(\.rawValue) + [9_999]).map { code in
    ["code": Int(code), "name": WorkoutClassifier.ActivityCode(rawValue: code).map { String(describing: $0) } ?? "unknown",
     "profile": WorkoutClassifier.profile(activityCode: code).rawValue, "label": WorkoutClassifier.label(activityCode: code),
     "ambiguous": WorkoutClassifier.ambiguousCodes.contains(code)]
}
let profiles: [[String: Any]] = AthleteMatrix.personas.map { p in
    let data = try! JSONEncoder().encode(p.profile)
    return ["name": p.name, "input": try! JSONSerialization.jsonObject(with: data),
        "fitness": p.profile.fitnessScale, "prior": optional(p.profile.prior),
        "predicted": optional(p.profile.predictedMaxHeartRate), "gaps": p.profile.gaps.map(\.rawValue)]
}
var analyses: [[String: Any]] = []
for (pi, persona) in AthleteMatrix.personas.enumerated() {
    for count in [0, 2, 4, 12] {
        for recovery: Double? in [nil, 15, 45] {
            for slow in [false, true] {
                let offsets = (0..<count).map { 3 + $0 * 2 }
                let sessions = offsets.enumerated().map { index, offset in
                    let end = now.addingTimeInterval(-Double(offset) * 86_400)
                    return PersonalRecoveryModel.HistorySession(id: String(index), profile: .endurance,
                        startDate: end.addingTimeInterval(-3600), endDate: end, load: 80 + Double(index),
                        intensityFraction: slow && index % 2 == 0 ? 0.48 : 0.62, standardHours: 72)
                }
                let days = (0...34).map { offset in
                    let disturbed = offsets.contains(offset + 1) || (slow && offsets.contains(offset + 2))
                    return PersonalRecoveryModel.DayPoint(date: now.addingTimeInterval(-Double(offset) * 86_400),
                        restingHeartRate: disturbed ? 58 : 52, heartRateVariability: disturbed ? 44 : 62,
                        heartRateRecovery: recovery)
                }
                let analysis = PersonalRecoveryModel.analyse(profile: persona.profile, sessions: sessions, days: days, now: now)
                analyses.append(["name": String(pi) + "-" + String(count) + "-" + String(describing: recovery) + "-" + String(slow),
                    "profile": profiles[pi]["input"]!,
                    "sessions": sessions.map { ["id": $0.id, "profile": $0.profile.rawValue,
                        "start": $0.startDate.timeIntervalSince1970, "end": $0.endDate.timeIntervalSince1970,
                        "load": $0.load, "intensity": optional($0.intensityFraction), "standard": $0.standardHours] as [String: Any] },
                    "days": days.map { ["date": $0.date.timeIntervalSince1970, "resting": optional($0.restingHeartRate),
                        "hrv": optional($0.heartRateVariability), "recovery": optional($0.heartRateRecovery)] as [String: Any] },
                    "expected": ["factor": analysis.factor, "prior": optional(analysis.prior),
                        "rebound": optional(analysis.reboundFactor), "reboundSamples": analysis.reboundSamples,
                        "tolerance": optional(analysis.toleranceFactor), "toleranceSamples": analysis.toleranceSamples,
                        "kinetics": optional(analysis.kineticsFactor), "kineticsSamples": analysis.kineticsSamples,
                        "medianRecovery": optional(analysis.medianHeartRateRecovery), "weekly": analysis.weeklyLoad,
                        "frequency": analysis.sessionsPerWeek, "count": analysis.qualifyingSessions,
                        "weight": analysis.evidenceWeight, "summary": PersonalRecoveryModel.summary(analysis)]])
            }
        }
    }
}
var patterns: [[String: Any]] = []
for count in [0, 2, 4, 8, 12] {
    for gap in [0.25, 1, 2, 5, 10] {
        for style in 0..<3 {
            let sessions = (0..<count).map { index in
                let end = now.addingTimeInterval(-Double(count - index) * gap * 86_400)
                return ObservedRecoveryPattern.Session(profile: style == 2 ? .easy : .endurance,
                    startDate: end.addingTimeInterval(-3600), endDate: end,
                    load: style == 1 && index % 2 == 0 ? 25 : 100, id: String(index))
            }
            let pattern = ObservedRecoveryPattern.analyse(sessions: sessions, now: now)
            patterns.append(["name": String(count) + "-" + String(gap) + "-" + String(style),
                "sessions": sessions.map { ["id": $0.id, "profile": $0.profile.rawValue,
                    "start": $0.startDate.timeIntervalSince1970, "end": $0.endDate.timeIntervalSince1970, "load": $0.load] as [String: Any] },
                "light": pattern.lightCeiling, "moderate": pattern.moderateCeiling, "count": pattern.sessionCount,
                "gaps": SessionIntensity.allCases.map { intensity -> Any in
                    let band = ObservedRecoveryPattern.EffortBand(rawValue: intensity.rawValue)!
                    return ["band": intensity.rawValue, "hours": optional(pattern.usualGapHours(for: band)),
                        "samples": optional(pattern.evidence(for: band)?.sampleCount), "specific": pattern.isBandSpecific(band)]
                }])
        }
    }
}
let target = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
let document: [String: Any] = ["modelVersion": recoveryModelVersion, "now": now.timeIntervalSince1970,
    "calculations": cases, "profiles": profiles, "activityCodes": codes, "analyses": analyses, "patterns": patterns]
try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]).write(to: target)
let production = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: production.deletingLastPathComponent(), withIntermediateDirectories: true)
try JSONSerialization.data(withJSONObject: codes, options: [.sortedKeys, .prettyPrinted]).write(to: production)
let content: [String: Any] = ["announcementVersion": WhatsNew.currentVersion,
    "updates": WhatsNew.items.map { ["title": $0.title, "detail": $0.detail] },
    "features": ProFeature.allCases.map { ["title": $0.title, "detail": $0.detail] },
    "questions": Dictionary(uniqueKeysWithValues: ProfileQuestion.allCases.map { ($0.rawValue, ["title": $0.title, "detail": $0.detail]) })]
try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys, .prettyPrinted])
    .write(to: production.deletingLastPathComponent().appendingPathComponent("app-content.json"))
print("Exported \(cases.count) calculations, \(analyses.count) personal analyses, \(patterns.count) observed patterns, \(profiles.count) profiles and \(codes.count) activity classifications")
