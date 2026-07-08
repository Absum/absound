//
//  SongArrangerView.swift
//  The Song tab: chain patterns into a full-length arrangement. Tap a pattern to
//  append a section; the sequence plays through, highlighting the current pattern.
//  Shares the Studio's TransportController, so edits to a pattern show everywhere
//  it is used.
//

import SwiftUI

struct SongArrangerView: View {
    @ObservedObject var transport: TransportController

    private var song: [Int] { transport.project.song }
    private var names: [String] { transport.patternNames }

    var body: some View {
        ZStack {
            ArcticBackground(glow: transport.songPlaying)
            VStack(alignment: .leading, spacing: 18) {
                Text("SONG").font(Theme.display(24)).foregroundStyle(Theme.frost).tracking(4)

                palette
                arrangement
                Spacer()
                transportRow
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        }
        .onAppear { transport.onAppear() }
    }

    // Tap a pattern to append it as a section.
    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PATTERNS — tap to add a section").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.5)).tracking(1)
            HStack(spacing: 8) {
                ForEach(Array(names.enumerated()), id: \.offset) { idx, name in
                    Button { transport.appendSection(idx) } label: {
                        Text(name).font(Theme.title(18)).foregroundStyle(Theme.frost)
                            .frame(width: 46, height: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cyan.opacity(0.18)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.frost.opacity(0.18), lineWidth: 1))
                    }
                }
            }
        }
    }

    private var arrangement: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ARRANGEMENT").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.5)).tracking(1)
                Spacer()
                if !song.isEmpty {
                    Text("tap a section to remove").font(Theme.light(11)).foregroundStyle(Theme.frost.opacity(0.35))
                }
            }
            if song.isEmpty {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04))
                    .frame(height: 70)
                    .overlay(Text("Add patterns above to build your song")
                        .font(Theme.body(14)).foregroundStyle(Theme.frost.opacity(0.4)))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(song.enumerated()), id: \.offset) { i, patternIdx in
                            let playing = transport.songPlaying && transport.songPosition == i
                            Button { transport.removeSection(at: i) } label: {
                                Text(names.indices.contains(patternIdx) ? names[patternIdx] : "?")
                                    .font(Theme.title(18))
                                    .foregroundStyle(playing ? Theme.bgTop : Theme.frost)
                                    .frame(width: 52, height: 70)
                                    .background(RoundedRectangle(cornerRadius: 10)
                                        .fill(playing ? Theme.teal.opacity(0.95) : Color.white.opacity(0.08)))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.frost.opacity(0.15), lineWidth: 1))
                                    .shadow(color: playing ? Theme.teal.opacity(0.7) : .clear, radius: 8)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var transportRow: some View {
        HStack(spacing: 18) {
            Button { transport.toggleSong() } label: {
                Image(systemName: transport.songPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.bgTop)
                    .frame(width: 58, height: 58).background(Circle().fill(Theme.teal))
                    .shadow(color: Theme.teal.opacity(transport.songPlaying ? 0.7 : 0.3), radius: 12)
            }
            .disabled(song.isEmpty)
            .opacity(song.isEmpty ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.isEmpty ? "No sections" : "\(song.count) section\(song.count == 1 ? "" : "s")")
                    .font(Theme.title(16)).foregroundStyle(Theme.frost)
                Text("\(Int(transport.tempo)) BPM").font(Theme.light(12)).foregroundStyle(Theme.frost.opacity(0.5))
            }
            Spacer()
            if !song.isEmpty {
                Button { transport.clearSong() } label: {
                    Text("Clear").font(Theme.body(14)).foregroundStyle(Theme.frost.opacity(0.7))
                        .padding(.vertical, 9).padding(.horizontal, 16)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                }
            }
        }
    }
}
