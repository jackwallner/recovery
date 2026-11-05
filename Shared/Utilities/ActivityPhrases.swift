import Foundation

/// A stored activity label ("run", "lifting session") inside a sentence.
///
/// `displayLabel` hands back a bare noun, which is only right where a noun
/// stands alone ("Moderate · run"). Inside a sentence the noun's gender, its
/// case after a preposition, and the possessive or demonstrative in front of it
/// all vary by language (Polish "Twój ostatni bieg" against "Twoja ostatnia
/// jazda", "po tym biegu"), so a translated noun cannot be inserted into one
/// sentence and reused in another. Each function here is one slot: its own
/// catalog key per activity, translated together with the words around it.
///
/// The argument is always the stored English `activityLabel`, which is never
/// rewritten. A label written by a later version that this build does not know
/// reads as a plain "workout" in the slot, because a sentence cannot be built
/// around a noun it has no form for.
extension WorkoutClassifier {
    /// "Your last run": the preview label on the conversion card.
    static func lastSessionTitle(_ stored: String) -> String {
        switch stored {
        case "run": return String(localized: "Your last run", bundle: .recharge)
        case "ride": return String(localized: "Your last ride", bundle: .recharge)
        case "walk": return String(localized: "Your last walk", bundle: .recharge)
        case "swim": return String(localized: "Your last swim", bundle: .recharge)
        case "row": return String(localized: "Your last row", bundle: .recharge)
        case "hike": return String(localized: "Your last hike", bundle: .recharge)
        case "elliptical session": return String(localized: "Your last elliptical session", bundle: .recharge)
        case "stair session": return String(localized: "Your last stair session", bundle: .recharge)
        case "lifting session": return String(localized: "Your last lifting session", bundle: .recharge)
        case "functional session": return String(localized: "Your last functional session", bundle: .recharge)
        case "HIIT session": return String(localized: "Your last HIIT session", bundle: .recharge)
        case "core session": return String(localized: "Your last core session", bundle: .recharge)
        case "cross-training session": return String(localized: "Your last cross-training session", bundle: .recharge)
        case "yoga session": return String(localized: "Your last yoga session", bundle: .recharge)
        case "pilates session": return String(localized: "Your last pilates session", bundle: .recharge)
        case "barre session": return String(localized: "Your last barre session", bundle: .recharge)
        case "mobility session": return String(localized: "Your last mobility session", bundle: .recharge)
        case "boxing session": return String(localized: "Your last boxing session", bundle: .recharge)
        case "martial arts session": return String(localized: "Your last martial arts session", bundle: .recharge)
        case "tennis match": return String(localized: "Your last tennis match", bundle: .recharge)
        case "basketball game": return String(localized: "Your last basketball game", bundle: .recharge)
        case "soccer game": return String(localized: "Your last soccer game", bundle: .recharge)
        case "triathlon session": return String(localized: "Your last triathlon session", bundle: .recharge)
        case "cardio session": return String(localized: "Your last cardio session", bundle: .recharge)
        case "jump rope session": return String(localized: "Your last jump rope session", bundle: .recharge)
        case "climb": return String(localized: "Your last climb", bundle: .recharge)
        case "ski": return String(localized: "Your last ski", bundle: .recharge)
        case "ski run": return String(localized: "Your last ski run", bundle: .recharge)
        case "snowboard session": return String(localized: "Your last snowboard session", bundle: .recharge)
        default: return String(localized: "Your last workout", bundle: .recharge)
        }
    }

    /// "For your last run. <caption>": the Settings row's detail line.
    static func lastSessionDetail(_ stored: String, caption: String) -> String {
        switch stored {
        case "run": return String(localized: "For your last run. \(caption)", bundle: .recharge)
        case "ride": return String(localized: "For your last ride. \(caption)", bundle: .recharge)
        case "walk": return String(localized: "For your last walk. \(caption)", bundle: .recharge)
        case "swim": return String(localized: "For your last swim. \(caption)", bundle: .recharge)
        case "row": return String(localized: "For your last row. \(caption)", bundle: .recharge)
        case "hike": return String(localized: "For your last hike. \(caption)", bundle: .recharge)
        case "elliptical session": return String(localized: "For your last elliptical session. \(caption)", bundle: .recharge)
        case "stair session": return String(localized: "For your last stair session. \(caption)", bundle: .recharge)
        case "lifting session": return String(localized: "For your last lifting session. \(caption)", bundle: .recharge)
        case "functional session": return String(localized: "For your last functional session. \(caption)", bundle: .recharge)
        case "HIIT session": return String(localized: "For your last HIIT session. \(caption)", bundle: .recharge)
        case "core session": return String(localized: "For your last core session. \(caption)", bundle: .recharge)
        case "cross-training session": return String(localized: "For your last cross-training session. \(caption)", bundle: .recharge)
        case "yoga session": return String(localized: "For your last yoga session. \(caption)", bundle: .recharge)
        case "pilates session": return String(localized: "For your last pilates session. \(caption)", bundle: .recharge)
        case "barre session": return String(localized: "For your last barre session. \(caption)", bundle: .recharge)
        case "mobility session": return String(localized: "For your last mobility session. \(caption)", bundle: .recharge)
        case "boxing session": return String(localized: "For your last boxing session. \(caption)", bundle: .recharge)
        case "martial arts session": return String(localized: "For your last martial arts session. \(caption)", bundle: .recharge)
        case "tennis match": return String(localized: "For your last tennis match. \(caption)", bundle: .recharge)
        case "basketball game": return String(localized: "For your last basketball game. \(caption)", bundle: .recharge)
        case "soccer game": return String(localized: "For your last soccer game. \(caption)", bundle: .recharge)
        case "triathlon session": return String(localized: "For your last triathlon session. \(caption)", bundle: .recharge)
        case "cardio session": return String(localized: "For your last cardio session. \(caption)", bundle: .recharge)
        case "jump rope session": return String(localized: "For your last jump rope session. \(caption)", bundle: .recharge)
        case "climb": return String(localized: "For your last climb. \(caption)", bundle: .recharge)
        case "ski": return String(localized: "For your last ski. \(caption)", bundle: .recharge)
        case "ski run": return String(localized: "For your last ski run. \(caption)", bundle: .recharge)
        case "snowboard session": return String(localized: "For your last snowboard session. \(caption)", bundle: .recharge)
        default: return String(localized: "For your last workout. \(caption)", bundle: .recharge)
        }
    }

    /// "How hard was your run?": the effort sheet on the phone.
    static func effortQuestion(_ stored: String) -> String {
        switch stored {
        case "run": return String(localized: "How hard was your run?", bundle: .recharge)
        case "ride": return String(localized: "How hard was your ride?", bundle: .recharge)
        case "walk": return String(localized: "How hard was your walk?", bundle: .recharge)
        case "swim": return String(localized: "How hard was your swim?", bundle: .recharge)
        case "row": return String(localized: "How hard was your row?", bundle: .recharge)
        case "hike": return String(localized: "How hard was your hike?", bundle: .recharge)
        case "elliptical session": return String(localized: "How hard was your elliptical session?", bundle: .recharge)
        case "stair session": return String(localized: "How hard was your stair session?", bundle: .recharge)
        case "lifting session": return String(localized: "How hard was your lifting session?", bundle: .recharge)
        case "functional session": return String(localized: "How hard was your functional session?", bundle: .recharge)
        case "HIIT session": return String(localized: "How hard was your HIIT session?", bundle: .recharge)
        case "core session": return String(localized: "How hard was your core session?", bundle: .recharge)
        case "cross-training session": return String(localized: "How hard was your cross-training session?", bundle: .recharge)
        case "yoga session": return String(localized: "How hard was your yoga session?", bundle: .recharge)
        case "pilates session": return String(localized: "How hard was your pilates session?", bundle: .recharge)
        case "barre session": return String(localized: "How hard was your barre session?", bundle: .recharge)
        case "mobility session": return String(localized: "How hard was your mobility session?", bundle: .recharge)
        case "boxing session": return String(localized: "How hard was your boxing session?", bundle: .recharge)
        case "martial arts session": return String(localized: "How hard was your martial arts session?", bundle: .recharge)
        case "tennis match": return String(localized: "How hard was your tennis match?", bundle: .recharge)
        case "basketball game": return String(localized: "How hard was your basketball game?", bundle: .recharge)
        case "soccer game": return String(localized: "How hard was your soccer game?", bundle: .recharge)
        case "triathlon session": return String(localized: "How hard was your triathlon session?", bundle: .recharge)
        case "cardio session": return String(localized: "How hard was your cardio session?", bundle: .recharge)
        case "jump rope session": return String(localized: "How hard was your jump rope session?", bundle: .recharge)
        case "climb": return String(localized: "How hard was your climb?", bundle: .recharge)
        case "ski": return String(localized: "How hard was your ski?", bundle: .recharge)
        case "ski run": return String(localized: "How hard was your ski run?", bundle: .recharge)
        case "snowboard session": return String(localized: "How hard was your snowboard session?", bundle: .recharge)
        default: return String(localized: "How hard was your workout?", bundle: .recharge)
        }
    }

    /// "How hard was that run?": the effort sheet on the Watch.
    static func watchEffortQuestion(_ stored: String) -> String {
        switch stored {
        case "run": return String(localized: "How hard was that run?", bundle: .recharge)
        case "ride": return String(localized: "How hard was that ride?", bundle: .recharge)
        case "walk": return String(localized: "How hard was that walk?", bundle: .recharge)
        case "swim": return String(localized: "How hard was that swim?", bundle: .recharge)
        case "row": return String(localized: "How hard was that row?", bundle: .recharge)
        case "hike": return String(localized: "How hard was that hike?", bundle: .recharge)
        case "elliptical session": return String(localized: "How hard was that elliptical session?", bundle: .recharge)
        case "stair session": return String(localized: "How hard was that stair session?", bundle: .recharge)
        case "lifting session": return String(localized: "How hard was that lifting session?", bundle: .recharge)
        case "functional session": return String(localized: "How hard was that functional session?", bundle: .recharge)
        case "HIIT session": return String(localized: "How hard was that HIIT session?", bundle: .recharge)
        case "core session": return String(localized: "How hard was that core session?", bundle: .recharge)
        case "cross-training session": return String(localized: "How hard was that cross-training session?", bundle: .recharge)
        case "yoga session": return String(localized: "How hard was that yoga session?", bundle: .recharge)
        case "pilates session": return String(localized: "How hard was that pilates session?", bundle: .recharge)
        case "barre session": return String(localized: "How hard was that barre session?", bundle: .recharge)
        case "mobility session": return String(localized: "How hard was that mobility session?", bundle: .recharge)
        case "boxing session": return String(localized: "How hard was that boxing session?", bundle: .recharge)
        case "martial arts session": return String(localized: "How hard was that martial arts session?", bundle: .recharge)
        case "tennis match": return String(localized: "How hard was that tennis match?", bundle: .recharge)
        case "basketball game": return String(localized: "How hard was that basketball game?", bundle: .recharge)
        case "soccer game": return String(localized: "How hard was that soccer game?", bundle: .recharge)
        case "triathlon session": return String(localized: "How hard was that triathlon session?", bundle: .recharge)
        case "cardio session": return String(localized: "How hard was that cardio session?", bundle: .recharge)
        case "jump rope session": return String(localized: "How hard was that jump rope session?", bundle: .recharge)
        case "climb": return String(localized: "How hard was that climb?", bundle: .recharge)
        case "ski": return String(localized: "How hard was that ski?", bundle: .recharge)
        case "ski run": return String(localized: "How hard was that ski run?", bundle: .recharge)
        case "snowboard session": return String(localized: "How hard was that snowboard session?", bundle: .recharge)
        default: return String(localized: "How hard was that workout?", bundle: .recharge)
        }
    }

    /// "Your countdown from that run has finished.": the Ready notification.
    static func readyBody(_ stored: String) -> String {
        switch stored {
        case "run": return String(localized: "Your countdown from that run has finished.", bundle: .recharge)
        case "ride": return String(localized: "Your countdown from that ride has finished.", bundle: .recharge)
        case "walk": return String(localized: "Your countdown from that walk has finished.", bundle: .recharge)
        case "swim": return String(localized: "Your countdown from that swim has finished.", bundle: .recharge)
        case "row": return String(localized: "Your countdown from that row has finished.", bundle: .recharge)
        case "hike": return String(localized: "Your countdown from that hike has finished.", bundle: .recharge)
        case "elliptical session": return String(localized: "Your countdown from that elliptical session has finished.", bundle: .recharge)
        case "stair session": return String(localized: "Your countdown from that stair session has finished.", bundle: .recharge)
        case "lifting session": return String(localized: "Your countdown from that lifting session has finished.", bundle: .recharge)
        case "functional session": return String(localized: "Your countdown from that functional session has finished.", bundle: .recharge)
        case "HIIT session": return String(localized: "Your countdown from that HIIT session has finished.", bundle: .recharge)
        case "core session": return String(localized: "Your countdown from that core session has finished.", bundle: .recharge)
        case "cross-training session": return String(localized: "Your countdown from that cross-training session has finished.", bundle: .recharge)
        case "yoga session": return String(localized: "Your countdown from that yoga session has finished.", bundle: .recharge)
        case "pilates session": return String(localized: "Your countdown from that pilates session has finished.", bundle: .recharge)
        case "barre session": return String(localized: "Your countdown from that barre session has finished.", bundle: .recharge)
        case "mobility session": return String(localized: "Your countdown from that mobility session has finished.", bundle: .recharge)
        case "boxing session": return String(localized: "Your countdown from that boxing session has finished.", bundle: .recharge)
        case "martial arts session": return String(localized: "Your countdown from that martial arts session has finished.", bundle: .recharge)
        case "tennis match": return String(localized: "Your countdown from that tennis match has finished.", bundle: .recharge)
        case "basketball game": return String(localized: "Your countdown from that basketball game has finished.", bundle: .recharge)
        case "soccer game": return String(localized: "Your countdown from that soccer game has finished.", bundle: .recharge)
        case "triathlon session": return String(localized: "Your countdown from that triathlon session has finished.", bundle: .recharge)
        case "cardio session": return String(localized: "Your countdown from that cardio session has finished.", bundle: .recharge)
        case "jump rope session": return String(localized: "Your countdown from that jump rope session has finished.", bundle: .recharge)
        case "climb": return String(localized: "Your countdown from that climb has finished.", bundle: .recharge)
        case "ski": return String(localized: "Your countdown from that ski has finished.", bundle: .recharge)
        case "ski run": return String(localized: "Your countdown from that ski run has finished.", bundle: .recharge)
        case "snowboard session": return String(localized: "Your countdown from that snowboard session has finished.", bundle: .recharge)
        default: return String(localized: "Your countdown from that workout has finished.", bundle: .recharge)
        }
    }

    /// "your run", as the object of "from" in the line under the countdown.
    static func sourceObject(_ stored: String) -> String {
        switch stored {
        case "run": return String(localized: "your run", bundle: .recharge)
        case "ride": return String(localized: "your ride", bundle: .recharge)
        case "walk": return String(localized: "your walk", bundle: .recharge)
        case "swim": return String(localized: "your swim", bundle: .recharge)
        case "row": return String(localized: "your row", bundle: .recharge)
        case "hike": return String(localized: "your hike", bundle: .recharge)
        case "elliptical session": return String(localized: "your elliptical session", bundle: .recharge)
        case "stair session": return String(localized: "your stair session", bundle: .recharge)
        case "lifting session": return String(localized: "your lifting session", bundle: .recharge)
        case "functional session": return String(localized: "your functional session", bundle: .recharge)
        case "HIIT session": return String(localized: "your HIIT session", bundle: .recharge)
        case "core session": return String(localized: "your core session", bundle: .recharge)
        case "cross-training session": return String(localized: "your cross-training session", bundle: .recharge)
        case "yoga session": return String(localized: "your yoga session", bundle: .recharge)
        case "pilates session": return String(localized: "your pilates session", bundle: .recharge)
        case "barre session": return String(localized: "your barre session", bundle: .recharge)
        case "mobility session": return String(localized: "your mobility session", bundle: .recharge)
        case "boxing session": return String(localized: "your boxing session", bundle: .recharge)
        case "martial arts session": return String(localized: "your martial arts session", bundle: .recharge)
        case "tennis match": return String(localized: "your tennis match", bundle: .recharge)
        case "basketball game": return String(localized: "your basketball game", bundle: .recharge)
        case "soccer game": return String(localized: "your soccer game", bundle: .recharge)
        case "triathlon session": return String(localized: "your triathlon session", bundle: .recharge)
        case "cardio session": return String(localized: "your cardio session", bundle: .recharge)
        case "jump rope session": return String(localized: "your jump rope session", bundle: .recharge)
        case "climb": return String(localized: "your climb", bundle: .recharge)
        case "ski": return String(localized: "your ski", bundle: .recharge)
        case "ski run": return String(localized: "your ski run", bundle: .recharge)
        case "snowboard session": return String(localized: "your snowboard session", bundle: .recharge)
        default: return String(localized: "your workout", bundle: .recharge)
        }
    }

    /// "Your run", as the subject that opens the ready explanation.
    static func sourceSubject(_ stored: String) -> String {
        switch stored {
        case "run": return String(localized: "Your run", bundle: .recharge)
        case "ride": return String(localized: "Your ride", bundle: .recharge)
        case "walk": return String(localized: "Your walk", bundle: .recharge)
        case "swim": return String(localized: "Your swim", bundle: .recharge)
        case "row": return String(localized: "Your row", bundle: .recharge)
        case "hike": return String(localized: "Your hike", bundle: .recharge)
        case "elliptical session": return String(localized: "Your elliptical session", bundle: .recharge)
        case "stair session": return String(localized: "Your stair session", bundle: .recharge)
        case "lifting session": return String(localized: "Your lifting session", bundle: .recharge)
        case "functional session": return String(localized: "Your functional session", bundle: .recharge)
        case "HIIT session": return String(localized: "Your HIIT session", bundle: .recharge)
        case "core session": return String(localized: "Your core session", bundle: .recharge)
        case "cross-training session": return String(localized: "Your cross-training session", bundle: .recharge)
        case "yoga session": return String(localized: "Your yoga session", bundle: .recharge)
        case "pilates session": return String(localized: "Your pilates session", bundle: .recharge)
        case "barre session": return String(localized: "Your barre session", bundle: .recharge)
        case "mobility session": return String(localized: "Your mobility session", bundle: .recharge)
        case "boxing session": return String(localized: "Your boxing session", bundle: .recharge)
        case "martial arts session": return String(localized: "Your martial arts session", bundle: .recharge)
        case "tennis match": return String(localized: "Your tennis match", bundle: .recharge)
        case "basketball game": return String(localized: "Your basketball game", bundle: .recharge)
        case "soccer game": return String(localized: "Your soccer game", bundle: .recharge)
        case "triathlon session": return String(localized: "Your triathlon session", bundle: .recharge)
        case "cardio session": return String(localized: "Your cardio session", bundle: .recharge)
        case "jump rope session": return String(localized: "Your jump rope session", bundle: .recharge)
        case "climb": return String(localized: "Your climb", bundle: .recharge)
        case "ski": return String(localized: "Your ski", bundle: .recharge)
        case "ski run": return String(localized: "Your ski run", bundle: .recharge)
        case "snowboard session": return String(localized: "Your snowboard session", bundle: .recharge)
        default: return String(localized: "Your workout", bundle: .recharge)
        }
    }

    /// "30-minute run", as it reads inside the reasons.
    static func minuteSession(_ minutes: Int, _ stored: String) -> String {
        switch stored {
        case "run": return String(localized: "\(minutes)-minute run", bundle: .recharge)
        case "ride": return String(localized: "\(minutes)-minute ride", bundle: .recharge)
        case "walk": return String(localized: "\(minutes)-minute walk", bundle: .recharge)
        case "swim": return String(localized: "\(minutes)-minute swim", bundle: .recharge)
        case "row": return String(localized: "\(minutes)-minute row", bundle: .recharge)
        case "hike": return String(localized: "\(minutes)-minute hike", bundle: .recharge)
        case "elliptical session": return String(localized: "\(minutes)-minute elliptical session", bundle: .recharge)
        case "stair session": return String(localized: "\(minutes)-minute stair session", bundle: .recharge)
        case "lifting session": return String(localized: "\(minutes)-minute lifting session", bundle: .recharge)
        case "functional session": return String(localized: "\(minutes)-minute functional session", bundle: .recharge)
        case "HIIT session": return String(localized: "\(minutes)-minute HIIT session", bundle: .recharge)
        case "core session": return String(localized: "\(minutes)-minute core session", bundle: .recharge)
        case "cross-training session": return String(localized: "\(minutes)-minute cross-training session", bundle: .recharge)
        case "yoga session": return String(localized: "\(minutes)-minute yoga session", bundle: .recharge)
        case "pilates session": return String(localized: "\(minutes)-minute pilates session", bundle: .recharge)
        case "barre session": return String(localized: "\(minutes)-minute barre session", bundle: .recharge)
        case "mobility session": return String(localized: "\(minutes)-minute mobility session", bundle: .recharge)
        case "boxing session": return String(localized: "\(minutes)-minute boxing session", bundle: .recharge)
        case "martial arts session": return String(localized: "\(minutes)-minute martial arts session", bundle: .recharge)
        case "tennis match": return String(localized: "\(minutes)-minute tennis match", bundle: .recharge)
        case "basketball game": return String(localized: "\(minutes)-minute basketball game", bundle: .recharge)
        case "soccer game": return String(localized: "\(minutes)-minute soccer game", bundle: .recharge)
        case "triathlon session": return String(localized: "\(minutes)-minute triathlon session", bundle: .recharge)
        case "cardio session": return String(localized: "\(minutes)-minute cardio session", bundle: .recharge)
        case "jump rope session": return String(localized: "\(minutes)-minute jump rope session", bundle: .recharge)
        case "climb": return String(localized: "\(minutes)-minute climb", bundle: .recharge)
        case "ski": return String(localized: "\(minutes)-minute ski", bundle: .recharge)
        case "ski run": return String(localized: "\(minutes)-minute ski run", bundle: .recharge)
        case "snowboard session": return String(localized: "\(minutes)-minute snowboard session", bundle: .recharge)
        default: return String(localized: "\(minutes)-minute workout", bundle: .recharge)
        }
    }

    /// "a 30-minute run", with its article, for the reason a session fell below the threshold.
    static func indefiniteMinuteSession(_ minutes: Int, _ stored: String) -> String {
        switch stored {
        case "run": return String(localized: "a \(minutes)-minute run", bundle: .recharge)
        case "ride": return String(localized: "a \(minutes)-minute ride", bundle: .recharge)
        case "walk": return String(localized: "a \(minutes)-minute walk", bundle: .recharge)
        case "swim": return String(localized: "a \(minutes)-minute swim", bundle: .recharge)
        case "row": return String(localized: "a \(minutes)-minute row", bundle: .recharge)
        case "hike": return String(localized: "a \(minutes)-minute hike", bundle: .recharge)
        case "elliptical session": return String(localized: "a \(minutes)-minute elliptical session", bundle: .recharge)
        case "stair session": return String(localized: "a \(minutes)-minute stair session", bundle: .recharge)
        case "lifting session": return String(localized: "a \(minutes)-minute lifting session", bundle: .recharge)
        case "functional session": return String(localized: "a \(minutes)-minute functional session", bundle: .recharge)
        case "HIIT session": return String(localized: "a \(minutes)-minute HIIT session", bundle: .recharge)
        case "core session": return String(localized: "a \(minutes)-minute core session", bundle: .recharge)
        case "cross-training session": return String(localized: "a \(minutes)-minute cross-training session", bundle: .recharge)
        case "yoga session": return String(localized: "a \(minutes)-minute yoga session", bundle: .recharge)
        case "pilates session": return String(localized: "a \(minutes)-minute pilates session", bundle: .recharge)
        case "barre session": return String(localized: "a \(minutes)-minute barre session", bundle: .recharge)
        case "mobility session": return String(localized: "a \(minutes)-minute mobility session", bundle: .recharge)
        case "boxing session": return String(localized: "a \(minutes)-minute boxing session", bundle: .recharge)
        case "martial arts session": return String(localized: "a \(minutes)-minute martial arts session", bundle: .recharge)
        case "tennis match": return String(localized: "a \(minutes)-minute tennis match", bundle: .recharge)
        case "basketball game": return String(localized: "a \(minutes)-minute basketball game", bundle: .recharge)
        case "soccer game": return String(localized: "a \(minutes)-minute soccer game", bundle: .recharge)
        case "triathlon session": return String(localized: "a \(minutes)-minute triathlon session", bundle: .recharge)
        case "cardio session": return String(localized: "a \(minutes)-minute cardio session", bundle: .recharge)
        case "jump rope session": return String(localized: "a \(minutes)-minute jump rope session", bundle: .recharge)
        case "climb": return String(localized: "a \(minutes)-minute climb", bundle: .recharge)
        case "ski": return String(localized: "a \(minutes)-minute ski", bundle: .recharge)
        case "ski run": return String(localized: "a \(minutes)-minute ski run", bundle: .recharge)
        case "snowboard session": return String(localized: "a \(minutes)-minute snowboard session", bundle: .recharge)
        default: return String(localized: "a \(minutes)-minute workout", bundle: .recharge)
        }
    }

    /// "Your 30-minute run", as the subject of the effort sheet's note.
    static func yourMinuteSession(_ minutes: Int, _ stored: String) -> String {
        switch stored {
        case "run": return String(localized: "Your \(minutes)-minute run", bundle: .recharge)
        case "ride": return String(localized: "Your \(minutes)-minute ride", bundle: .recharge)
        case "walk": return String(localized: "Your \(minutes)-minute walk", bundle: .recharge)
        case "swim": return String(localized: "Your \(minutes)-minute swim", bundle: .recharge)
        case "row": return String(localized: "Your \(minutes)-minute row", bundle: .recharge)
        case "hike": return String(localized: "Your \(minutes)-minute hike", bundle: .recharge)
        case "elliptical session": return String(localized: "Your \(minutes)-minute elliptical session", bundle: .recharge)
        case "stair session": return String(localized: "Your \(minutes)-minute stair session", bundle: .recharge)
        case "lifting session": return String(localized: "Your \(minutes)-minute lifting session", bundle: .recharge)
        case "functional session": return String(localized: "Your \(minutes)-minute functional session", bundle: .recharge)
        case "HIIT session": return String(localized: "Your \(minutes)-minute HIIT session", bundle: .recharge)
        case "core session": return String(localized: "Your \(minutes)-minute core session", bundle: .recharge)
        case "cross-training session": return String(localized: "Your \(minutes)-minute cross-training session", bundle: .recharge)
        case "yoga session": return String(localized: "Your \(minutes)-minute yoga session", bundle: .recharge)
        case "pilates session": return String(localized: "Your \(minutes)-minute pilates session", bundle: .recharge)
        case "barre session": return String(localized: "Your \(minutes)-minute barre session", bundle: .recharge)
        case "mobility session": return String(localized: "Your \(minutes)-minute mobility session", bundle: .recharge)
        case "boxing session": return String(localized: "Your \(minutes)-minute boxing session", bundle: .recharge)
        case "martial arts session": return String(localized: "Your \(minutes)-minute martial arts session", bundle: .recharge)
        case "tennis match": return String(localized: "Your \(minutes)-minute tennis match", bundle: .recharge)
        case "basketball game": return String(localized: "Your \(minutes)-minute basketball game", bundle: .recharge)
        case "soccer game": return String(localized: "Your \(minutes)-minute soccer game", bundle: .recharge)
        case "triathlon session": return String(localized: "Your \(minutes)-minute triathlon session", bundle: .recharge)
        case "cardio session": return String(localized: "Your \(minutes)-minute cardio session", bundle: .recharge)
        case "jump rope session": return String(localized: "Your \(minutes)-minute jump rope session", bundle: .recharge)
        case "climb": return String(localized: "Your \(minutes)-minute climb", bundle: .recharge)
        case "ski": return String(localized: "Your \(minutes)-minute ski", bundle: .recharge)
        case "ski run": return String(localized: "Your \(minutes)-minute ski run", bundle: .recharge)
        case "snowboard session": return String(localized: "Your \(minutes)-minute snowboard session", bundle: .recharge)
        default: return String(localized: "Your \(minutes)-minute workout", bundle: .recharge)
        }
    }

    /// "Your estimate after that run ran out.", the effort sheet's footnote.
    static func estimateAfter(_ stored: String) -> String {
        switch stored {
        case "run": return String(localized: "Your estimate after that run ran out.", bundle: .recharge)
        case "ride": return String(localized: "Your estimate after that ride ran out.", bundle: .recharge)
        case "walk": return String(localized: "Your estimate after that walk ran out.", bundle: .recharge)
        case "swim": return String(localized: "Your estimate after that swim ran out.", bundle: .recharge)
        case "row": return String(localized: "Your estimate after that row ran out.", bundle: .recharge)
        case "hike": return String(localized: "Your estimate after that hike ran out.", bundle: .recharge)
        case "elliptical session": return String(localized: "Your estimate after that elliptical session ran out.", bundle: .recharge)
        case "stair session": return String(localized: "Your estimate after that stair session ran out.", bundle: .recharge)
        case "lifting session": return String(localized: "Your estimate after that lifting session ran out.", bundle: .recharge)
        case "functional session": return String(localized: "Your estimate after that functional session ran out.", bundle: .recharge)
        case "HIIT session": return String(localized: "Your estimate after that HIIT session ran out.", bundle: .recharge)
        case "core session": return String(localized: "Your estimate after that core session ran out.", bundle: .recharge)
        case "cross-training session": return String(localized: "Your estimate after that cross-training session ran out.", bundle: .recharge)
        case "yoga session": return String(localized: "Your estimate after that yoga session ran out.", bundle: .recharge)
        case "pilates session": return String(localized: "Your estimate after that pilates session ran out.", bundle: .recharge)
        case "barre session": return String(localized: "Your estimate after that barre session ran out.", bundle: .recharge)
        case "mobility session": return String(localized: "Your estimate after that mobility session ran out.", bundle: .recharge)
        case "boxing session": return String(localized: "Your estimate after that boxing session ran out.", bundle: .recharge)
        case "martial arts session": return String(localized: "Your estimate after that martial arts session ran out.", bundle: .recharge)
        case "tennis match": return String(localized: "Your estimate after that tennis match ran out.", bundle: .recharge)
        case "basketball game": return String(localized: "Your estimate after that basketball game ran out.", bundle: .recharge)
        case "soccer game": return String(localized: "Your estimate after that soccer game ran out.", bundle: .recharge)
        case "triathlon session": return String(localized: "Your estimate after that triathlon session ran out.", bundle: .recharge)
        case "cardio session": return String(localized: "Your estimate after that cardio session ran out.", bundle: .recharge)
        case "jump rope session": return String(localized: "Your estimate after that jump rope session ran out.", bundle: .recharge)
        case "climb": return String(localized: "Your estimate after that climb ran out.", bundle: .recharge)
        case "ski": return String(localized: "Your estimate after that ski ran out.", bundle: .recharge)
        case "ski run": return String(localized: "Your estimate after that ski run ran out.", bundle: .recharge)
        case "snowboard session": return String(localized: "Your estimate after that snowboard session ran out.", bundle: .recharge)
        default: return String(localized: "Your estimate after that workout ran out.", bundle: .recharge)
        }
    }
}
