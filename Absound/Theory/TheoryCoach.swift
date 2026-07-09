//
//  TheoryCoach.swift
//  The "learn as you go" pillar: reads a melody straight off the scale-degree
//  model (no audio analysis) and names what's happening — anchoring, contour,
//  motion — with a short plain-language lesson for anyone curious why it works.
//
//  Pure Swift, no UIKit — unit-tested in Tests/.
//

import Foundation

struct TheoryReading: Equatable {
    /// One compact line for the coach strip, e.g. "Anchored on the root & fifth · arch shape".
    let headline: String
    /// Two-three sentences of plain-language teaching.
    let lesson: String
}

enum TheoryCoach {

    /// Analyze a melody lane (grid rows, nil = rest) in a key/scale context.
    /// Returns nil when there is nothing meaningful to say (fewer than 2 notes).
    static func read(melody: [Int?], context: MusicalContext) -> TheoryReading? {
        let notes = melody.enumerated().compactMap { i, r in r.map { (step: i, row: $0) } }
        guard notes.count >= 2 else { return nil }

        let n = context.scale.degreeCount
        let intervals = context.scale.intervals
        func degree(_ row: Int) -> Int { ((row % n) + n) % n }
        let fifthIdx = intervals.firstIndex(of: 7)

        // --- Anchoring: do strong beats sit on the stable tones (root/fifth)? ---
        let strongNotes = notes.filter { $0.step % 4 == 0 }
        let stable: Set<Int> = fifthIdx.map { [0, $0] } ?? [0]
        let anchoredCount = strongNotes.filter { stable.contains(degree($0.row)) }.count
        let anchoring = strongNotes.isEmpty ? 0.0 : Double(anchoredCount) / Double(strongNotes.count)

        // --- Contour: rising / falling / arch / wave ---
        let rows = notes.map(\.row)
        let first = rows.first!, last = rows.last!
        let peak = rows.max()!, peakIdx = rows.firstIndex(of: peak)!
        let contour: String
        if last - first >= 3 { contour = "rising line" }
        else if first - last >= 3 { contour = "falling line" }
        else if peak - max(first, last) >= 2 && peakIdx > 0 && peakIdx < rows.count - 1 { contour = "arch shape" }
        else { contour = "wave shape" }

        // --- Motion: stepwise vs leaps ---
        var steps = 0, leaps = 0, octaveLeaps = 0
        for (a, b) in zip(rows, rows.dropFirst()) {
            let d = abs(b - a)
            if d <= 1 { steps += 1 }
            else if d >= n { octaveLeaps += 1; leaps += 1 }
            else if d >= 3 { leaps += 1 }
        }
        let moves = max(rows.count - 1, 1)
        let stepwise = Double(steps) / Double(moves)

        // --- Range in octaves ---
        let span = rows.max()! - rows.min()!
        let octaves = Double(span) / Double(n)

        // --- Headline: pick the two most telling traits ---
        var traits: [String] = []
        if anchoring >= 0.6 {
            traits.append(fifthIdx != nil ? "anchored on the root & fifth" : "anchored on the root")
        } else if anchoring <= 0.25 && strongNotes.count >= 2 {
            traits.append("floats off the strong beats")
        }
        traits.append(contour)
        if octaveLeaps > 0 { traits.append("octave leap") }
        else if stepwise >= 0.7 { traits.append("stepwise") }
        let headline = traits.prefix(2).joined(separator: " · ")

        // --- Lesson: assemble 2-3 plain-language sentences ---
        var sentences: [String] = []
        if anchoring >= 0.6 {
            sentences.append("Most of your strong beats land on the root\(fifthIdx != nil ? " or the fifth" : "") of \(context.displayName) — the most stable notes in the key. That's what makes the line feel grounded.")
        } else if anchoring <= 0.25 && strongNotes.count >= 2 {
            sentences.append("Your strong beats mostly avoid the root and fifth, which gives the line a floating, unresolved feel — landing on the root at the end would release that tension.")
        }
        if stepwise >= 0.7 {
            sentences.append("The melody moves mostly in single scale-steps — stepwise motion is what makes a line easy to sing and remember.")
        } else if leaps >= 2 {
            sentences.append("There are several leaps here; leaps grab attention, and following a leap with steps in the opposite direction smooths it back out.")
        }
        if octaveLeaps > 0 {
            sentences.append("The octave jump is a classic energy move — same note, new register.")
        }
        if octaves >= 1.5 {
            sentences.append("The line spans over one and a half octaves — a wide range reads as expressive, but keeping hooks within one octave makes them easier to hum.")
        }
        sentences.append(scaleFlavor(context.scale))

        return TheoryReading(headline: headline, lesson: sentences.prefix(3).joined(separator: " "))
    }

    /// One sentence of character per scale — why it sounds the way it does.
    static func scaleFlavor(_ scale: Scale) -> String {
        switch scale {
        case .major: return "Major is the bright default: its third and seventh pull strongly home to the root."
        case .naturalMinor: return "Natural minor gets its melancholy from the flattened third — everything else works just like major."
        case .harmonicMinor: return "Harmonic minor's raised seventh creates that exotic, dramatic pull back to the root."
        case .dorian: return "Dorian is minor with a raised sixth — darker than major, brighter than minor; the classic groove scale."
        case .phrygian: return "Phrygian's flattened second right above the root gives it an unmistakable dark, Spanish flavor."
        case .mixolydian: return "Mixolydian is major with a relaxed, flattened seventh — the sound of classic rock and funk."
        case .lydian: return "Lydian's raised fourth floats — it's major that never quite touches the ground; the film-score scale."
        case .majorPentatonic: return "The major pentatonic drops the two tension notes of major, so every note is safe — pure sunshine."
        case .minorPentatonic: return "The minor pentatonic skips the scale's tense notes entirely, so nothing can clash — the backbone of countless riffs."
        case .blues: return "Blues is the minor pentatonic plus one forbidden note — the flat five — and that little clash is the whole point."
        }
    }
}
