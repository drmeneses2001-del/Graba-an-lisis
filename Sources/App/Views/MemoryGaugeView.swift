import SwiftUI

/// Indicador permanente de consumo. Que el usuario vea el margen que queda es
/// parte del contrato: la app se autolimita y lo dice.
struct MemoryGaugeView: View {
    @EnvironmentObject private var governor: MemoryGovernor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Memoria", systemImage: "memorychip")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(governor.pressure.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(pressureColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(pressureColor)
            }

            ProgressView(value: governor.usedFraction)
                .tint(pressureColor)

            HStack {
                Text("\(MemoryReporter.formatted(governor.footprintBytes)) de \(MemoryReporter.formatted(governor.estimatedLimitBytes))")
                Spacer()
                Text("Perfil \(governor.deviceClass.displayName)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Text("Máx. sesión \(Int(governor.limits.maxSessionSeconds / 60)) min")
                Spacer()
                Text("Audio hasta \(MemoryReporter.formatted(governor.limits.maxAudioBytes))")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var pressureColor: Color {
        switch governor.pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
