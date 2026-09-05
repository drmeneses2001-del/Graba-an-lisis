import SwiftUI
import PDFKit

struct SessionDetailView: View {
    let sessionID: UUID

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var governor: MemoryGovernor
    @StateObject private var pipeline = SessionPipeline()
    @State private var tab = 0
    @State private var showDeleteConfirmation = false

    private var session: RecordingSession? { store.session(id: sessionID) }

    var body: some View {
        Group {
            if let session {
                content(for: session)
            } else {
                ContentUnavailableView("Sesión no encontrada", systemImage: "questionmark.folder")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let session { pipeline.loadExisting(for: session) }
        }
    }

    private func content(for session: RecordingSession) -> some View {
        VStack(spacing: 0) {
            header(session)
            Picker("Vista", selection: $tab) {
                Text("Informe").tag(0)
                Text("Análisis").tag(1)
                Text("Transcripción").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            switch tab {
            case 0: reportTab(session)
            case 1: analysisTab
            default: transcriptTab
            }
        }
        .navigationTitle(session.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rehacer todo", systemImage: "arrow.clockwise") {
                        pipeline.run(session: session, force: true)
                    }
                    .disabled(pipeline.phase.isRunning)
                    Button("Rehacer solo el PDF", systemImage: "doc.badge.arrow.up") {
                        pipeline.regenerateReport(session: session)
                    }
                    .disabled(pipeline.report == nil || pipeline.phase.isRunning)
                    Divider()
                    Button("Eliminar sesión", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("¿Eliminar la sesión y su audio?",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { store.delete(session) }
        }
    }

    // MARK: - Cabecera con progreso

    private func header(_ session: RecordingSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(ReportComposer.formatDuration(session.duration), systemImage: "clock")
                Label("Salida de audio", systemImage: "waveform")
                Spacer()
                Text(MemoryReporter.formatted(session.audioBytes))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let reason = session.truncationReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if pipeline.phase.isRunning {
                ProgressView(value: pipeline.phase.fraction) {
                    Text(pipeline.phase.description).font(.caption)
                }
                HStack {
                    Text("Memoria \(MemoryReporter.formatted(governor.footprintBytes)) · presión \(governor.pressure.displayName.lowercased())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancelar", role: .cancel) { pipeline.cancel() }
                        .font(.caption)
                }
            } else if case .failed(let message) = pipeline.phase {
                Label(message, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
                runButton(session, title: "Reintentar")
            } else if pipeline.report == nil {
                runButton(session, title: "Transcribir, analizar y generar PDF")
            }
        }
        .padding()
    }

    private func runButton(_ session: RecordingSession, title: String) -> some View {
        Button {
            pipeline.run(session: session)
        } label: {
            Label(title, systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(session.stage == .recording)
    }

    // MARK: - Pestañas

    @ViewBuilder
    private func reportTab(_ session: RecordingSession) -> some View {
        if let url = pipeline.reportURL, FileManager.default.fileExists(atPath: url.path) {
            VStack(spacing: 0) {
                PDFPreview(url: url)
                HStack {
                    ShareLink(item: url, preview: SharePreview(session.title, image: Image(systemName: "doc.richtext"))) {
                        Label("Compartir PDF", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Text(fileSize(url))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        } else {
            ContentUnavailableView("Todavía no hay informe",
                                   systemImage: "doc.richtext",
                                   description: Text("Pulsa el botón de arriba para transcribir, analizar y componer el PDF."))
        }
    }

    @ViewBuilder
    private var analysisTab: some View {
        if let report = pipeline.report {
            AnalysisSummaryView(report: report)
        } else {
            ContentUnavailableView("Sin análisis", systemImage: "text.magnifyingglass")
        }
    }

    @ViewBuilder
    private var transcriptTab: some View {
        if let transcript = pipeline.transcript {
            List(transcript.utterances.sorted { $0.start < $1.start }) { utterance in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(Transcript.timestamp(utterance.start)).monospacedDigit()
                        Spacer()
                        Text("\(Int(utterance.confidence * 100)) %")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Text(utterance.text).font(.callout)
                }
            }
            .listStyle(.plain)
        } else {
            ContentUnavailableView("Sin transcripción", systemImage: "text.quote")
        }
    }

    private func fileSize(_ url: URL) -> String {
        let size = FileManager.default.fileSizeBytes(at: url)
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

/// Vista previa del PDF con PDFKit. Carga página a página desde disco.
struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

/// Resumen navegable del análisis dentro de la app, para no depender del PDF.
struct AnalysisSummaryView: View {
    let report: AnalysisReport

    var body: some View {
        List {
            Section("Resumen ejecutivo") {
                Text(report.executiveSummary).font(.callout)
            }
            if !report.keyPoints.isEmpty {
                Section("Puntos clave") {
                    ForEach(report.keyPoints, id: \.self) { Text($0).font(.callout) }
                }
            }
            if !report.commitments.isEmpty {
                Section("Compromisos (\(report.commitments.count))") {
                    ForEach(report.commitments) { commitment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commitment.statement).font(.callout)
                            Text("\(commitment.owner) · \(commitment.dueDescription) · \(commitment.status.displayName)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !report.decisions.isEmpty {
                Section("Decisiones (\(report.decisions.count))") {
                    ForEach(report.decisions) { Text($0.statement).font(.callout) }
                }
            }
            if !report.proposals.isEmpty {
                Section("Propuestas (\(report.proposals.count))") {
                    ForEach(report.proposals) { proposal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proposal.statement).font(.callout)
                            Text("\(proposal.proposedBy) · esfuerzo \(proposal.effort.displayName.lowercased())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !report.critiques.isEmpty {
                Section("Críticas (\(report.critiques.count))") {
                    ForEach(report.critiques) { critique in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(critique.statement).font(.callout)
                            Text("\(critique.raisedBy) · gravedad \(critique.severity.displayName.lowercased())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !report.risks.isEmpty {
                Section("Riesgos (\(report.risks.count))") {
                    ForEach(report.risks) { risk in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(risk.statement).font(.callout)
                            Text("Probabilidad \(risk.likelihood.displayName.lowercased()) · impacto \(risk.impact.displayName.lowercased())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !report.openQuestions.isEmpty {
                Section("Preguntas abiertas") {
                    ForEach(report.openQuestions, id: \.self) { Text($0).font(.callout) }
                }
            }
            Section("Trazabilidad") {
                Text("\(report.provenance.engine)\(report.provenance.model.map { " · \($0)" } ?? "")")
                    .font(.caption)
                if !report.provenance.notes.isEmpty {
                    Text(report.provenance.notes).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
