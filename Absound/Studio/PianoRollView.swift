//
//  PianoRollView.swift
//  Logic/GarageBand-style editing surfaces rendered as scrollable Canvas grids
//  with a piano-key gutter and drag-to-paint. Vertical one-finger drags scroll;
//  horizontal drags paint; taps toggle a single cell.
//

import SwiftUI

// MARK: - Melody piano roll

struct PianoRollView: View {
    @ObservedObject var transport: TransportController
    @ObservedObject var playhead: PlayheadState

    init(transport: TransportController, rowHeight: CGFloat = 30) {
        self.transport = transport
        self.playhead = transport.playhead
        self.rowHeight = rowHeight
    }
    var rowHeight: CGFloat = 30
    private let gutter: CGFloat = 42
    @State private var didDrag = false

    var body: some View {
        GeometryReader { geo in
            let cols = transport.stepCount
            let stepW = (geo.size.width - gutter) / CGFloat(cols)
            let rowCount = transport.melodyRowCount
            let contentH = CGFloat(rowCount) * rowHeight

            ScrollView(.vertical, showsIndicators: true) {
                Canvas { ctx, size in draw(ctx, size: size, stepW: stepW, cols: cols, rowCount: rowCount) }
                    .frame(width: geo.size.width, height: contentH)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { onChanged($0, stepW: stepW, cols: cols, rowCount: rowCount) }
                            .onEnded { onEnded($0, stepW: stepW, cols: cols, rowCount: rowCount) }
                    )
            }
            .background(RollBackground())
        }
    }

    private func cell(_ loc: CGPoint, stepW: CGFloat, cols: Int, rowCount: Int) -> (row: Int, step: Int)? {
        guard loc.x >= gutter else { return nil }
        let step = Int((loc.x - gutter) / stepW)
        let visRow = Int(loc.y / rowHeight)
        guard step >= 0, step < cols, visRow >= 0, visRow < rowCount else { return nil }
        return (rowCount - 1 - visRow, step)
    }

    private func onChanged(_ v: DragGesture.Value, stepW: CGFloat, cols: Int, rowCount: Int) {
        let dx = abs(v.translation.width), dy = abs(v.translation.height)
        guard dx + dy > 12 else { return }     // still might be a tap
        if dy > dx { return }                  // vertical drag -> let the ScrollView scroll
        didDrag = true
        if let c = cell(v.location, stepW: stepW, cols: cols, rowCount: rowCount) {
            transport.placeMelody(row: c.row, step: c.step)
        }
    }
    private func onEnded(_ v: DragGesture.Value, stepW: CGFloat, cols: Int, rowCount: Int) {
        defer { didDrag = false }
        guard !didDrag else { return }
        if let c = cell(v.location, stepW: stepW, cols: cols, rowCount: rowCount) {
            transport.toggleMelody(row: c.row, step: c.step)
        }
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, stepW: CGFloat, cols: Int, rowCount: Int) {
        let ctxM = transport.context
        let melody = transport.selectedMelody
        let others = transport.showShadow ? transport.otherMelodies : []
        for visRow in 0..<rowCount {
            let row = rowCount - 1 - visRow
            let y = CGFloat(visRow) * rowHeight
            let isRoot = (ctxM.midiNote(forRow: row) - ctxM.root) % 12 == 0

            // Gutter pitch label + faint root-row band.
            if isRoot {
                ctx.fill(Path(CGRect(x: gutter, y: y, width: size.width - gutter, height: rowHeight)),
                         with: .color(Theme.teal.opacity(0.05)))
            }
            ctx.draw(Text(ctxM.noteName(forRow: row)).font(Theme.light(11))
                        .foregroundColor(isRoot ? Theme.teal : Theme.frost.opacity(0.45)),
                     at: CGPoint(x: 6, y: y + rowHeight / 2), anchor: .leading)

            for step in 0..<cols {
                let x = gutter + CGFloat(step) * stepW
                let rect = CGRect(x: x + 1, y: y + 1, width: stepW - 2, height: rowHeight - 2)
                let path = Path(roundedRect: rect, cornerRadius: 4)
                let on = melody[step] == row
                let ghost = others.contains { $0[step] == row }
                let playh = step == playhead.currentStep
                if on {
                    ctx.fill(path, with: .color(Theme.cyan.opacity(playh ? 1.0 : 0.85)))
                } else if ghost {
                    ctx.fill(path, with: .color(Theme.cyan.opacity(0.20)))
                } else {
                    ctx.fill(path, with: .color(.white.opacity(step % 4 == 0 ? 0.08 : 0.04)))
                }
                if playh { ctx.stroke(path, with: .color(Theme.frost.opacity(0.85)), lineWidth: 1.5) }
            }
        }
    }
}

// MARK: - Drum lanes

struct DrumLanesView: View {
    @ObservedObject var transport: TransportController
    @ObservedObject var playhead: PlayheadState

    init(transport: TransportController, rowHeight: CGFloat = 34) {
        self.transport = transport
        self.playhead = transport.playhead
        self.rowHeight = rowHeight
    }
    var rowHeight: CGFloat = 34
    private let gutter: CGFloat = 58
    @State private var didDrag = false
    @State private var paintOn: Bool? = nil

    private let colors: [Color] = [Theme.teal, Theme.steel, Theme.frost, Theme.cyan]

    var body: some View {
        GeometryReader { geo in
            let cols = transport.stepCount
            let stepW = (geo.size.width - gutter) / CGFloat(cols)
            let lanes = transport.drumLayers
            let contentH = max(CGFloat(lanes.count) * rowHeight, geo.size.height)

            ScrollView(.vertical, showsIndicators: true) {
                Canvas { ctx, size in draw(ctx, size: size, stepW: stepW, cols: cols, lanes: lanes) }
                    .frame(width: geo.size.width, height: contentH)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { onChanged($0, stepW: stepW, cols: cols, lanes: lanes) }
                            .onEnded { onEnded($0, stepW: stepW, cols: cols, lanes: lanes) }
                    )
            }
            .background(RollBackground())
        }
    }

    private func cell(_ loc: CGPoint, stepW: CGFloat, cols: Int, lanes: [Layer]) -> (lane: Layer, step: Int)? {
        guard loc.x >= gutter else { return nil }
        let step = Int((loc.x - gutter) / stepW)
        let laneIdx = Int(loc.y / rowHeight)
        guard step >= 0, step < cols, laneIdx >= 0, laneIdx < lanes.count else { return nil }
        return (lanes[laneIdx], step)
    }

    private func onChanged(_ v: DragGesture.Value, stepW: CGFloat, cols: Int, lanes: [Layer]) {
        let dx = abs(v.translation.width), dy = abs(v.translation.height)
        guard dx + dy > 12 else { return }
        if dy > dx { return }
        didDrag = true
        guard let c = cell(v.location, stepW: stepW, cols: cols, lanes: lanes) else { return }
        if paintOn == nil { paintOn = !transport.drumLane(c.lane.id)[c.step] }   // first cell sets the brush
        transport.setDrum(c.lane.id, step: c.step, on: paintOn ?? true)
    }
    private func onEnded(_ v: DragGesture.Value, stepW: CGFloat, cols: Int, lanes: [Layer]) {
        defer { didDrag = false; paintOn = nil }
        guard !didDrag else { return }
        if let c = cell(v.location, stepW: stepW, cols: cols, lanes: lanes) {
            transport.toggleDrum(c.lane.id, step: c.step)
        }
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, stepW: CGFloat, cols: Int, lanes: [Layer]) {
        for (laneIdx, lane) in lanes.enumerated() {
            let y = CGFloat(laneIdx) * rowHeight
            let color = colors[laneIdx % colors.count]
            let hits = transport.drumLane(lane.id)
            ctx.draw(Text(lane.displayName).font(Theme.body(12))
                        .foregroundColor(lane.muted ? Theme.frost.opacity(0.35) : Theme.frost.opacity(0.8)),
                     at: CGPoint(x: 6, y: y + rowHeight / 2), anchor: .leading)
            for step in 0..<cols {
                let x = gutter + CGFloat(step) * stepW
                let rect = CGRect(x: x + 1, y: y + 3, width: stepW - 2, height: rowHeight - 6)
                let path = Path(roundedRect: rect, cornerRadius: 4)
                let on = hits[step]
                let playh = step == playhead.currentStep
                if on {
                    ctx.fill(path, with: .color(color.opacity(playh ? 1.0 : 0.85)))
                } else {
                    ctx.fill(path, with: .color(.white.opacity(step % 4 == 0 ? 0.08 : 0.04)))
                }
                if playh { ctx.stroke(path, with: .color(Theme.frost.opacity(0.85)), lineWidth: 1.5) }
            }
        }
    }
}

/// Shared dark backdrop for the roll/lanes — squared off (the grid is a field of cells).
struct RollBackground: View {
    var body: some View {
        Rectangle().fill(Color.black.opacity(0.18))
            .overlay(Rectangle().stroke(Theme.frost.opacity(0.10), lineWidth: 1))
    }
}
