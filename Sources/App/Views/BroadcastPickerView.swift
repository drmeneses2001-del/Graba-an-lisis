import SwiftUI
import ReplayKit

/// Botón del sistema que arranca la difusión. iOS exige que el usuario la
/// inicie desde este control o desde el Centro de control: una app no puede
/// empezar a capturar el audio del dispositivo por su cuenta.
struct BroadcastPickerView: UIViewRepresentable {

    let extensionBundleID: String

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = extensionBundleID
        picker.showsMicrophoneButton = true
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
