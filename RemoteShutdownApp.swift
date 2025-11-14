import SwiftUI
import Network

// MARK: - UDP Server Class
class RemoteShutdownServer: ObservableObject {
    @Published var isRunning = false
    @Published var logs: [LogEntry] = []
    @Published var port: UInt16 = 9999
    @Published var machineIdentifier = "mac01"
    
    private var listener: NWListener?
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let type: LogType
        
        enum LogType {
            case info, success, warning, error
            
            var color: Color {
                switch self {
                case .info: return .blue
                case .success: return .green
                case .warning: return .orange
                case .error: return .red
                }
            }
            
            var icon: String {
                switch self {
                case .info: return "ℹ️"
                case .success: return "✅"
                case .warning: return "⚠️"
                case .error: return "❌"
                }
            }
        }
    }
    
    func start() {
        guard !isRunning else { return }
        
        do {
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.addLog("Server started on UDP port \(self?.port ?? 0)", type: .success)
                        self?.addLog("Listening for: /\(self?.machineIdentifier ?? "")/reboot and /\(self?.machineIdentifier ?? "")/shutdown", type: .info)
                    case .failed(let error):
                        self?.isRunning = false
                        self?.addLog("Server failed: \(error.localizedDescription)", type: .error)
                    case .cancelled:
                        self?.isRunning = false
                        self?.addLog("Server stopped", type: .warning)
                    default:
                        break
                    }
                }
            }
            
            listener?.start(queue: .main)
            
        } catch {
            addLog("Failed to start server: \(error.localizedDescription)", type: .error)
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        addLog("Server stopped by user", type: .warning)
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        
        connection.receiveMessage { [weak self] (data, context, isComplete, error) in
            guard let self = self else { return }
            
            if let data = data, let message = String(data: data, encoding: .utf8) {
                let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
                
                DispatchQueue.main.async {
                    self.addLog("Received command: \(trimmedMessage)", type: .info)
                    self.processCommand(trimmedMessage)
                }
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.addLog("Receive error: \(error.localizedDescription)", type: .error)
                }
            }
            
            connection.cancel()
        }
    }
    
    private func processCommand(_ command: String) {
        let rebootCommand = "/\(machineIdentifier)/reboot"
        let shutdownCommand = "/\(machineIdentifier)/shutdown"
        
        switch command {
        case rebootCommand:
            addLog("Reboot command matched! Rebooting in 3 seconds...", type: .warning)
            executeReboot()
            
        case shutdownCommand:
            addLog("Shutdown command matched! Shutting down in 3 seconds...", type: .warning)
            executeShutdown()
            
        default:
            addLog("Unknown command: \(command)", type: .error)
            addLog("Expected: \(rebootCommand) or \(shutdownCommand)", type: .info)
        }
    }
    
    private func executeReboot() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", "tell application \"System Events\" to restart"]
            
            do {
                try task.run()
                self?.addLog("Reboot command executed", type: .success)
            } catch {
                self?.addLog("Failed to execute reboot: \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    private func executeShutdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", "tell application \"System Events\" to shut down"]
            
            do {
                try task.run()
                self?.addLog("Shutdown command executed", type: .success)
            } catch {
                self?.addLog("Failed to execute shutdown: \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    private func addLog(_ message: String, type: LogEntry.LogType) {
        let entry = LogEntry(timestamp: Date(), message: message, type: type)
        logs.insert(entry, at: 0)
        
        // Keep only last 100 logs
        if logs.count > 100 {
            logs = Array(logs.prefix(100))
        }
    }
    
    func clearLogs() {
        logs.removeAll()
        addLog("Logs cleared", type: .info)
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var server = RemoteShutdownServer()
    @State private var tempPort = "9999"
    @State private var tempMachineID = "mac01"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()
            
            Divider()
            
            // Configuration Panel
            ConfigurationPanel(
                server: server,
                tempPort: $tempPort,
                tempMachineID: $tempMachineID
            )
            
            Divider()
            
            // Control Buttons
            ControlButtons(server: server)
            
            Divider()
            
            // Status Display
            StatusDisplay(server: server)
            
            Divider()
            
            // Log View
            LogView(server: server)
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

// MARK: - Header View
struct HeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "power")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("Remote Shutdown/Reboot Server")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            Text("Control your Mac remotely via UDP commands")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Configuration Panel
struct ConfigurationPanel: View {
    @ObservedObject var server: RemoteShutdownServer
    @Binding var tempPort: String
    @Binding var tempMachineID: String
    
    var body: some View {
        GroupBox(label: Label("Configuration", systemImage: "gearshape.fill")) {
            VStack(spacing: 15) {
                HStack {
                    Text("UDP Port:")
                        .frame(width: 120, alignment: .leading)
                        .fontWeight(.medium)
                    
                    TextField("Port", text: $tempPort)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 100)
                        .disabled(server.isRunning)
                    
                    Text("(Default: 9999)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                HStack {
                    Text("Machine ID:")
                        .frame(width: 120, alignment: .leading)
                        .fontWeight(.medium)
                    
                    TextField("Machine Identifier", text: $tempMachineID)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 150)
                        .disabled(server.isRunning)
                    
                    Text("(e.g., mac01, office-mac)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Command Strings:")
                        .fontWeight(.medium)
                    
                    HStack {
                        Text("Reboot:")
                            .frame(width: 80, alignment: .leading)
                            .foregroundColor(.secondary)
                        Text("/\(tempMachineID)/reboot")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    HStack {
                        Text("Shutdown:")
                            .frame(width: 80, alignment: .leading)
                            .foregroundColor(.secondary)
                        Text("/\(tempMachineID)/shutdown")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            .padding()
        }
        .padding()
    }
}

// MARK: - Control Buttons
struct ControlButtons: View {
    @ObservedObject var server: RemoteShutdownServer
    
    var body: some View {
        HStack(spacing: 20) {
            Button(action: {
                if server.isRunning {
                    server.stop()
                } else {
                    server.start()
                }
            }) {
                HStack {
                    Image(systemName: server.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                    Text(server.isRunning ? "Stop Server" : "Start Server")
                        .fontWeight(.semibold)
                }
                .frame(width: 180)
                .padding()
                .background(server.isRunning ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                server.clearLogs()
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear Logs")
                }
                .frame(width: 150)
                .padding()
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
    }
}

// MARK: - Status Display
struct StatusDisplay: View {
    @ObservedObject var server: RemoteShutdownServer
    
    var body: some View {
        HStack(spacing: 30) {
            StatusItem(
                icon: "circle.fill",
                label: "Status",
                value: server.isRunning ? "Running" : "Stopped",
                color: server.isRunning ? .green : .red
            )
            
            StatusItem(
                icon: "network",
                label: "Port",
                value: "\(server.port)",
                color: .blue
            )
            
            StatusItem(
                icon: "desktopcomputer",
                label: "Machine ID",
                value: server.machineIdentifier,
                color: .purple
            )
            
            StatusItem(
                icon: "doc.text",
                label: "Log Entries",
                value: "\(server.logs.count)",
                color: .orange
            )
        }
        .padding()
    }
}

struct StatusItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Log View
struct LogView: View {
    @ObservedObject var server: RemoteShutdownServer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activity Log")
                .font(.headline)
                .padding()
            
            Divider()
            
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(server.logs) { log in
                            LogEntryView(log: log)
                                .id(log.id)
                        }
                    }
                    .padding()
                    .onChange(of: server.logs.count) { _ in
                        if let firstLog = server.logs.first {
                            withAnimation {
                                proxy.scrollTo(firstLog.id, anchor: .top)
                            }
                        }
                    }
                }
            }
            .background(Color.gray.opacity(0.05))
        }
    }
}

struct LogEntryView: View {
    let log: RemoteShutdownServer.LogEntry
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(log.type.icon)
            
            Text(timeFormatter.string(from: log.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Text(log.message)
                .font(.system(.body, design: .default))
                .foregroundColor(log.type.color)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(log.type.color.opacity(0.05))
        .cornerRadius(6)
    }
}

// MARK: - App Entry Point
@main
struct RemoteShutdownApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
