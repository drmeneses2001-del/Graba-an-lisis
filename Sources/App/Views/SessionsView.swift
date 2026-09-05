import SwiftUI

struct SessionsView: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView("Sin sesiones",
                                           systemImage: "waveform",
                                           description: Text("Graba una reunión o una difusión del sistema y aparecerá aquí."))
                } else {
                    List {
                        ForEach(store.sessions) { session in
                            NavigationLink(value: session.id) {
                                SessionRow(session: session)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { store.delete(store.sessions[index]) }
                        }
                    }
                    .navigationDestination(for: UUID.self) { id in
                        SessionDetailView(sessionID: id)
                    }
                }
            }
            .navigationTitle("Sesiones")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(MemoryReporter.formatted(store.diskUsage()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .refreshable { store.reload() }
            .onAppear { store.reload() }
        }
    }
}

struct SessionRow: View {
    let session: RecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title).font(.headline).lineLimit(2)
            HStack(spacing: 8) {
                Label(ReportComposer.formatDuration(session.duration), systemImage: "clock")
                Label(MemoryReporter.formatted(session.audioBytes), systemImage: "waveform")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Text(session.stage.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(stageColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(stageColor)
                Text(session.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var stageColor: Color {
        switch session.stage {
        case .recording: return .red
        case .captured: return .orange
        case .transcribed, .analyzed: return .blue
        case .reported: return .green
        case .failed: return .red
        }
    }
}
