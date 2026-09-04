import SwiftUI

struct RecordView: View {
    @StateObject private var model = RecorderViewModel()
    @EnvironmentObject private var governor: MemoryGovernor
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    modePicker
                    titleField
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
            .alert("No se pudo grabar",
                   isPresented: Binding(get: { model.errorMessage != nil },
                                        set: { if !$0 { model.errorMessage = nil } })) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    // MARK: - Piezas

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Fuente", selection: $model.mode) {
                ForEach(RecorderViewModel.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.microphone.isRecording || model.isBroadcasting)

            Text(model.mode.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var titleField: some View {
        TextField("Título de la sesión", text: $model.title, prompt: Text(model.suggestedTitle))
            .textFieldStyle(.roundedBorder)
            .disabled(model.microphone.isRecording)
    }

    @ViewBuilder
    private var captureCard: some View {
        switch model.mode {
        case .microphone:
            microphoneCard
        case .broadcast:
            broadcastCard
        }
    }

    private var microphoneCard: some View {
        VStack(spacing: 16) {
            LevelMeterView(level: model.microphone.level, active: model.microphone.isRecording)
                .frame(height: 56)

            Text(elapsedText(model.microphone.elapsed))
                .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())

            Button {
                if model.microphone.isRecording {
                    model.stopMicrophone()
                } else {
                    model.startMicrophone()
                }
            } label: {
                Label(model.microphone.isRecording ? "Detener" : "Grabar",
                      systemImage: model.microphone.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.microphone.isRecording ? .red : .accentColor)

            Text("Límite para este dispositivo: \(Int(settings.effectiveSessionSeconds(limits: governor.limits) / 60)) minutos. La grabación se cierra sola al llegar y se guarda íntegra.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var broadcastCard: some View {
        VStack(spacing: 16) {
            if let handoff = model.broadcastHandoff, model.isBroadcasting {
                Label("Difusión en curso", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(elapsedText(handoff.seconds))
                    .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                HStack(spacing: 18) {
                    trackBadge("Dispositivo", bytes: handoff.bytesDevice)
                    trackBadge("Micrófono", bytes: handoff.bytesLocal)
                }
                Text("Memoria de la extensión: \(MemoryReporter.formatted(handoff.footprintBytes)) de un tope propio de 38 MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Para terminar, toca la barra roja de estado o usa el Centro de control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("Pulsa el botón del sistema, elige «Graba y Análisis» y activa el micrófono si también quieres tu voz.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                BroadcastPickerView(extensionBundleID: RecorderViewModel.broadcastExtensionBundleID)
                    .frame(width: 64, height: 64)
                Text("El sistema silencia el audio protegido (música con DRM, algunas apps de vídeo). Las llamadas, reuniones, podcasts y navegador se capturan sin problema.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private func trackBadge(_ name: String, bytes: UInt64) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text(MemoryReporter.formatted(bytes)).font(.footnote.monospacedDigit())
        }
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

/// Medidor de nivel: barras que suben con la energía de la señal.
struct LevelMeterView: View {
    let level: Float
    let active: Bool

    private let bars = 28

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<bars, id: \.self) { index in
                let threshold = Float(index) / Float(bars)
                let lit = active && min(1, level * 6) > threshold
                RoundedRectangle(cornerRadius: 2)
                    .fill(lit ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: CGFloat(8 + index * 2))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
