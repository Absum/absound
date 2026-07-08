//
//  AuroraHighwayView.swift
//  The signature scrolling "Highway" melody input (inherited from Pickup).
//
//  Existing melody notes flow as glowing blocks down one-octave pitch lanes
//  toward a now-line; the scale-strip pads beneath are all in-key, so tapping
//  plays good notes. Arm Rec + Play and taps record (quantized) into the same
//  melody track the piano-roll edits.
//

import SwiftUI

struct AuroraHighwayView: View {
    @ObservedObject var transport: TransportController

    /// Octave offset (in scale degrees) of the lowest visible lane.
    @State private var octaveBase = 0

    private var degreeCount: Int { transport.context.scale.degreeCount }
    private var laneCount: Int { degreeCount + 1 }          // root..root inclusive
    private var maxBase: Int { transport.melodyRowCount - 1 - degreeCount }

    var body: some View {
        VStack(spacing: 10) {
            controls
            highway
            padStrip
        }
        // The 60fps playhead stream only runs while the Highway is visible.
        .onAppear { transport.playheadEnabled = true }
        .onDisappear { transport.playheadEnabled = false }
    }

    // MARK: Controls (Rec arm + octave shift)

    private var controls: some View {
        HStack(spacing: 12) {
            Button { transport.toggleRecord() } label: {
                HStack(spacing: 6) {
                    Circle().fill(transport.isRecording ? Color.red : Theme.frost.opacity(0.5))
                        .frame(width: 10, height: 10)
                    Text("REC").font(Theme.title(14)).tracking(1)
                }
                .foregroundStyle(transport.isRecording ? .red : Theme.frost.opacity(0.7))
                .padding(.vertical, 7).padding(.horizontal, 14)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().stroke(transport.isRecording ? Color.red.opacity(0.6) : Theme.frost.opacity(0.12), lineWidth: 1))
            }
            Spacer()
            Text("Octave").font(Theme.light(12)).foregroundStyle(Theme.frost.opacity(0.5))
            stepper("minus") { octaveBase = max(0, octaveBase - degreeCount) }
            stepper("plus") { octaveBase = min(maxBase, octaveBase + degreeCount) }
        }
    }

    private func stepper(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.frost)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
    }

    // MARK: Highway canvas

    private var highway: some View {
        Canvas { ctx, size in
            let lanes = laneCount
            let laneW = size.width / CGFloat(lanes)
            let topMargin: CGFloat = 8
            let nowY = size.height - 6
            let span = CGFloat(Project.stepCount)     // whole loop visible
            let pos = transport.playPosition          // -1 when stopped
            let ctxM = transport.context

            // Lane separators + root-lane tint.
            for lane in 0..<lanes {
                let row = octaveBase + lane
                let isRoot = (ctxM.midiNote(forRow: row) - ctxM.root) % 12 == 0
                if isRoot {
                    let rect = CGRect(x: CGFloat(lane) * laneW, y: 0, width: laneW, height: size.height)
                    ctx.fill(Path(rect), with: .color(Theme.teal.opacity(0.06)))
                }
                let x = CGFloat(lane) * laneW
                ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(.white.opacity(0.05)), lineWidth: 1)
            }

            // Now-line.
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: nowY)); p.addLine(to: CGPoint(x: size.width, y: nowY)) },
                       with: .color(Theme.frost.opacity(0.5)), lineWidth: 2)

            // Notes — scroll the loop so each note hits the now-line on its step.
            let p = pos < 0 ? 0 : pos

            // Shadow notes from the other layers (drawn dimmer, behind).
            if transport.showShadow {
                for gm in transport.otherMelodies {
                    for step in 0..<Project.stepCount {
                        guard let row = gm[step], row >= octaveBase, row <= octaveBase + degreeCount else { continue }
                        let lane = row - octaveBase
                        var dt = (Double(step) - p).truncatingRemainder(dividingBy: Double(Project.stepCount))
                        if dt < 0 { dt += Double(Project.stepCount) }
                        let y = nowY - CGFloat(dt) / span * (nowY - topMargin)
                        let x = CGFloat(lane) * laneW + laneW / 2
                        let w = laneW * 0.5
                        let rect = CGRect(x: x - w / 2, y: y - 5, width: w, height: 10)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(Theme.cyan.opacity(0.16)))
                    }
                }
            }

            let melody = transport.selectedMelody
            for step in 0..<Project.stepCount {
                guard let row = melody[step] else { continue }
                guard row >= octaveBase && row <= octaveBase + degreeCount else { continue }
                let lane = row - octaveBase
                var dt = (Double(step) - p).truncatingRemainder(dividingBy: Double(Project.stepCount))
                if dt < 0 { dt += Double(Project.stepCount) }
                let frac = CGFloat(dt) / span                       // 0 at now-line, 1 at top
                let y = nowY - frac * (nowY - topMargin)
                let x = CGFloat(lane) * laneW + laneW / 2
                let glow = pos >= 0 ? (1.0 - frac * 0.7) : 0.6      // brighter as it nears the line
                let w = laneW * 0.66, h: CGFloat = 14
                let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
                let path = Path(roundedRect: rect, cornerRadius: 5)
                ctx.fill(path, with: .color(Theme.cyan.opacity(0.35 + 0.55 * glow)))
                ctx.stroke(path, with: .color(Theme.frost.opacity(0.6 * glow)), lineWidth: 1)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.frost.opacity(0.10), lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(maxHeight: .infinity)
    }

    // MARK: Scale-strip pads

    private var padStrip: some View {
        HStack(spacing: 5) {
            ForEach(0..<laneCount, id: \.self) { lane in
                let row = octaveBase + lane
                let ctxM = transport.context
                let isRoot = (ctxM.midiNote(forRow: row) - ctxM.root) % 12 == 0
                Button { transport.highwayTap(row: row) } label: {
                    VStack(spacing: 2) {
                        Text(ctxM.noteName(forRow: row))
                            .font(Theme.body(12))
                            .foregroundStyle(isRoot ? Theme.bgTop : Theme.frost)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isRoot ? Theme.teal.opacity(0.85) : Theme.cyan.opacity(0.18))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.frost.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
