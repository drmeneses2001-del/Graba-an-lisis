import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var governor: MemoryGovernor
    @EnvironmentObject private var store: SessionStore

    @State private var apiKeyDraft = ""
    @State private var hasKey = KeychainStore.hasAPIKey
    @State private var keyStatus: String?
    @State private var validating = false
    @State private var confirmWipe = false

    var body: some View {
        NavigationStack {
            Form {
                transcriptionSection
                engineSection
                reportSection
                limitsSection
                dataSection
                aboutSection
            }
            .navigationTitle("Ajustes")
        }
    }

    // MARK: - Secciones

    private var transcriptionSection: some View {
        Section {
            Picker("Idioma", selection: $settings.localeIdentifier) {
                ForEach(AppSettings.supportedLocales, id: \.id) { locale in
                    Text(locale.name).tag(locale.id)
                }
            }
            Toggle("Solo en el dispositivo", isOn: $settings.forceOnDeviceRecognition)
        } header: {
            Text("Transcripción")
        } footer: {
            Text("Con «Solo en el dispositivo» el audio nunca sale del aparato. Requiere que el idioma esté descargado en Ajustes › General › Teclado › Dictado.")
        }
    }

    private var engineSection: some View {
        Section {
            Picker("Motor", selection: $settings.engine) {
                ForEach(AppSettings.AnalysisEngineKind.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            Text(settings.engine.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if settings.engine == .claude {
                SecureField(hasKey ? "Clave guardada en el llavero" : "sk-ant-…", text: $apiKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("Guardar clave") {
                        KeychainStore.saveAPIKey(apiKeyDraft)
                        hasKey = KeychainStore.hasAPIKey
                        apiKeyDraft = ""
                        keyStatus = hasKey ? "Clave guardada." : "Clave eliminada."
                    }
                    .disabled(apiKeyDraft.isEmpty)
                    Spacer()
                    Button("Probar") { validateKey() }
                        .disabled(!hasKey || validating)
                    if hasKey {
                        Button("Borrar", role: .destructive) {
                            KeychainStore.deleteAPIKey()
                            hasKey = false
                            keyStatus = "Clave eliminada."
                        }
                    }
                }
                if let keyStatus {
                    Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Análisis")
        } footer: {
            if settings.engine == .claude {
                Text("El modelo usado es \(ClaudeClient.model). La transcripción se envía por bloques a api.anthropic.com; el audio nunca se envía. La clave vive en el llavero de este dispositivo.")
            }
        }
    }

    private var reportSection: some View {
        Section("Informe PDF") {
            TextField("Organización (portada)", text: $settings.organizationName)
            Toggle("Incluir la transcripción como anexo", isOn: $settings.includeTranscriptInReport)
        }
    }

    private var limitsSection: some View {
        Section {
            LabeledContent("Perfil del aparato", value: "\(governor.deviceClass.displayName) · \(MemoryReporter.formatted(MemoryReporter.physicalMemoryBytes))")
            LabeledContent("Duración máxima", value: "\(Int(governor.limits.maxSessionSeconds / 60)) min")
            LabeledContent("Audio por sesión", value: MemoryReporter.formatted(governor.limits.maxAudioBytes))
            LabeledContent("Ventana de reconocimiento", value: "\(Int(governor.limits.transcriptionWindowSeconds)) s")
            LabeledContent("Bloque de análisis", value: "\(governor.limits.analysisChunkChars) caracteres")
            LabeledContent("Texto en memoria", value: "\(governor.limits.maxTranscriptCharsInMemory / 1000) k caracteres")
            LabeledContent("Puntos por gráfica", value: "\(governor.limits.maxChartPoints)")

            Stepper(value: $settings.userSessionMinuteCap, in: 0...360, step: 15) {
                LabeledContent("Tope manual", value: settings.userSessionMinuteCap == 0 ? "Automático" : "\(settings.userSessionMinuteCap) min")
            }
        } header: {
            Text("Límites de recursos")
        } footer: {
            Text("Los límites se calculan con la RAM del aparato, la memoria que iOS deja disponible en cada momento y el espacio libre en disco. Si el sistema avisa de presión de memoria, se reducen a la mitad automáticamente. El tope manual solo puede recortar, nunca ampliar.")
        }
    }

    private var dataSection: some View {
        Section {
            LabeledContent("Sesiones", value: "\(store.sessions.count)")
            LabeledContent("Audio guardado", value: MemoryReporter.formatted(store.diskUsage()))
            LabeledContent("Disco libre", value: MemoryReporter.formatted(MemoryReporter.freeDiskBytes()))
            Button("Borrar todas las sesiones", role: .destructive) { confirmWipe = true }
        } header: {
            Text("Datos")
        }
        .confirmationDialog("Se eliminarán audio, transcripciones e informes de todas las sesiones.",
                            isPresented: $confirmWipe,
                            titleVisibility: .visible) {
            Button("Borrar todo", role: .destructive) { store.deleteAll() }
        }
    }

    private var aboutSection: some View {
        Section("Privacidad") {
            Text("iOS no permite que una app lea la salida de audio de otras apps. Para grabar «todo lo que se escucha» la app usa la extensión de difusión del sistema (ReplayKit): tú la inicias, tú la paras, y el sistema muestra la barra roja mientras está activa.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func validateKey() {
        validating = true
        keyStatus = "Comprobando…"
        Task {
            let result = await ClaudeClient().validateKey()
            switch result {
            case .success(let model): keyStatus = "Clave válida. Modelo: \(model)."
            case .failure(let error): keyStatus = error.localizedDescription
            }
            validating = false
        }
    }
}
