import SwiftUI

struct DebugLogView: View {
    @State private var entries: [NetworkLogService.Entry] = []
    @State private var selectedEntry: NetworkLogService.Entry?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("\(entries.count) requests logged")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        NetworkLogService.shared.clear()
                        entries = []
                    }
                    .disabled(entries.isEmpty)
                    Button("Refresh") {
                        entries = NetworkLogService.shared.entries
                    }
                }
            }

            if entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Network Logs",
                        systemImage: "network.slash",
                        description: Text("API requests will appear here as they are made.")
                    )
                }
            } else {
                Section("Recent Requests") {
                    ForEach(entries.reversed()) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            HStack {
                                Circle()
                                    .fill(statusColor(entry.statusCode))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(entry.method) \(shortenURL(entry.url))")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(entry.timestamp.formatted(.dateTime.hour().minute().second())) · \(Int(entry.duration * 1000))ms")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if let code = entry.statusCode {
                                    Text("\(code)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(statusColor(code))
                                } else if let error = entry.error {
                                    Text(error)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { entries = NetworkLogService.shared.entries }
        .sheet(item: $selectedEntry) { entry in
            NetworkLogDetailView(entry: entry)
        }
    }

    private func statusColor(_ code: Int?) -> Color {
        guard let code else { return .red }
        if code < 300 { return .green }
        if code < 400 { return .yellow }
        return .red
    }

    private func shortenURL(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "")
           .replacingOccurrences(of: "http://", with: "")
    }
}

struct NetworkLogDetailView: View {
    let entry: NetworkLogService.Entry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Request Detail")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        label("Method", entry.method)
                        label("URL", entry.url)
                        if let code = entry.statusCode {
                            label("Status", "\(code)")
                        }
                        label("Duration", "\(Int(entry.duration * 1000))ms")
                        label("Time", entry.timestamp.formatted())
                    }

                    if !entry.requestHeaders.isEmpty {
                        Text("Request Headers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(entry.requestHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            Text("\(key): \(value)")
                                .font(.system(.caption2, design: .monospaced))
                        }
                    }

                    if !entry.responseHeaders.isEmpty {
                        Text("Response Headers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(entry.responseHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            Text("\(key): \(value)")
                                .font(.system(.caption2, design: .monospaced))
                        }
                    }

                    if let body = entry.responseBody {
                        Text("Response Body")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(body.prefix(2000))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    if let error = entry.error {
                        Text("Error")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.system(.caption2, design: .monospaced))
                    }
                }
                .padding()
            }
        }
        .frame(width: 500, height: 400)
    }

    private func label(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
