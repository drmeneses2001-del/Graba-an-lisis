import SwiftUI

struct RecordView: View {
    @StateObject private var model = RecorderViewModel()
    @EnvironmentObject private var governor: MemoryGovernor
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    captureCard
                    MemoryGaugeView()
                    if let session = model.lastSession {
                        lastSessionCard(session)
                    }
                    privacyNote
                }
                .padding()
            }
            .navigationTitle("Grabar")
        }
    }

    // MARK: - Piezas

    private var captureCard: some View {
        VStack(spacing: 16) {
            if let handoff = model.broadcastHandoff, model.isBroadcasting {
                Label("Grabando", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(elapsedText(handoff.seconds))
                    .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                Text(MemoryReporter.formatted(handoff.bytes))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Para terminar, toca la barra roja de estado o usa el Centro de control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("Toca el botón, elige «Graba y Análisis» y arranca la difusión. La app grabará todo lo que suene por la salida de audio del dispositivo: una llamada, un vídeo, un podcast.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                BroadcastPickerView(extensionBundleID: RecorderViewModel.broadcastExtensionBundleID)
                    .frame(width: 64, height: 64)
                Text("El sistema silencia el audio protegido (música con DRM, algunas apps de vídeo). Llamadas, reuniones, podcasts y navegador se capturan sin problema.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private func lastSessionCard(_ session: RecordingSession) -> some View {
        NavigationLink {
            SessionDetailView(sessionID: session.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Última grabación").font(.caption).foregroundStyle(.secondary)
                    Text(session.title).font(.headline)
                    Text("\(ReportComposer.formatDuration(session.duration)) · \(session.stage.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let reason = session.truncationReason {
                        Text(reason).font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var privacyNote: some View {
        Text("El audio y la transcripción se guardan solo en este dispositivo. Nada sale de él salvo que actives el análisis en la nube en Ajustes.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    private func elapsedText(_ seconds: TimeInterval) -> String {
        Transcript.timestamp(seconds)
    }
}
