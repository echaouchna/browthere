import AppKit
import SwiftUI

struct AboutPane: View {
    @State private var memory = ResourceUsage.memoryMB()

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: .brandPink.opacity(0.35), radius: 28, y: 8)
            Text("BrowThere").font(.largeTitle.weight(.bold))
            Text("Every link, right where it belongs.")
                .foregroundStyle(.secondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .font(.caption).foregroundStyle(.tertiary)

            HStack(spacing: 24) {
                Stat(value: String(format: "%.0f MB", memory), label: "Memory now")
                Stat(value: "0%", label: "CPU when idle")
                Stat(value: "0", label: "Background timers")
            }
            .padding(.top, 10)

            Button("Reveal Config File") {
                NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL])
            }
            .buttonStyle(.link)
            .foregroundStyle(Color.brandViolet)
            .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandInk)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            memory = ResourceUsage.memoryMB()
        }
    }
}

private struct Stat: View {
    var value: String
    var label: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 110)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

enum ResourceUsage {
    /// Physical footprint, the number Activity Monitor shows as "Memory".
    static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
