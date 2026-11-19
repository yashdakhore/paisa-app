import SwiftUI
import UIKit

/// More → Connect Gmail.
struct GmailSetup: View {
    @Environment(KoshStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var gmail = GmailService.shared
    @State private var clientId = ""
    @State private var extra = ""
    @State private var myName = ""

    var body: some View {
        NavigationStack {
            Form {
                if gmail.isConnected {
                    Section {
                        LabeledContent("Connected as", value: gmail.email.isEmpty ? "Gmail" : gmail.email)
                        LabeledContent("Last checked", value: gmail.lastCheck?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
                        if !gmail.status.isEmpty { LabeledContent("Status", value: gmail.status) }
                        Button {
                            Task { await gmail.check(days: 7) }
                        } label: { Label(gmail.busy ? "Checking…" : "Check now", systemImage: "arrow.clockwise") }
                            .disabled(gmail.busy)
                        Button("Disconnect Gmail", role: .destructive) { gmail.disconnect() }
                    } footer: {
                        Text("Kosh checks when you open it, and in the background when iOS allows (with a notification). New transactions appear on Home under “From your bank”.")
                    }
                } else if gmail.clientId.isEmpty {
                    Section {
                        TextField("Paste the client ID", text: $clientId, axis: .vertical).lineLimit(1...3)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button {
                            clientId = UIPasteboard.general.string ?? ""
                            save()
                        } label: { Label("Paste from clipboard", systemImage: "doc.on.clipboard") }
                        if !clientId.isEmpty, GmailService.extractClientId(clientId) == nil {
                            Text("That doesn't look like a client ID. It ends in .apps.googleusercontent.com").font(.system(size: 13)).foregroundStyle(K.warn)
                        }
                    } header: { Text("Step 1 · Google client ID") } footer: {
                        Text("A one-time ID from Google Cloud that lets Kosh ask for read-only Gmail access. It isn't a password.")
                    }
                    .onChange(of: clientId) { _, _ in save() }
                } else {
                    Section {
                        Button {
                            Task { await gmail.connect() }
                        } label: { Label(gmail.busy ? "Connecting…" : "Connect Gmail", systemImage: "envelope.badge") }
                            .buttonStyle(PrimaryButton()).disabled(gmail.busy)
                            .listRowBackground(Color.clear)
                        if !gmail.status.isEmpty { Text(gmail.status).font(.system(size: 14)).foregroundStyle(K.warn) }
                        Button("Change client ID") { gmail.setClientId(""); clientId = "" }.font(.system(size: 14))
                    } header: { Text("Step 2 · Connect") } footer: {
                        Text("Google will say the app isn't verified, because it's your own private app. Tap Advanced → Go to Kosh, then allow read access.")
                    }
                }

                Section {
                    TextField("e.g. alerts@mybank.com", text: $extra).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                        .onChange(of: extra) { _, v in gmail.setExtraSenders(v) }
                } header: { Text("Other alert senders (optional)") } footer: {
                    Text("Kosh only reads emails from bank alert senders: SBI, IDFC, slice, BillDesk, OneCard, super.money, HDFC, ICICI, Axis, Kotak and a few more. Add any other bank's address here. Card and account numbers are never stored.")
                }
                Section {
                    TextField("e.g. Asha Kumar", text: $myName).textInputAutocapitalization(.words).autocorrectionDisabled()
                        .onChange(of: myName) { _, v in store.saveMyName(v) }
                } header: { Text("Your name") } footer: {
                    Text("Money you send to your own name (another of your accounts) is skipped.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x121215))
            .navigationTitle("Connect Gmail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                extra = gmail.extraSenders
                myName = store.data.settings.myName ?? ""
            }
        }
        .tint(K.brand)
    }

    func save() {
        if let id = GmailService.extractClientId(clientId) { gmail.setClientId(id) }
    }
}
