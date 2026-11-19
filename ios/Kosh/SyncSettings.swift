import SwiftUI
import UIKit

/// More → Sync between devices.
struct SyncSettings: View {
    @Environment(KoshStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sync = SyncService.shared
    @State private var url = ""
    @State private var key = ""
    @State private var email = ""
    @State private var password = ""
    @State private var message: String?
    @State private var working = false

    static let setupSQL = """
    create table if not exists finance_docs (
      user_id uuid primary key references auth.users on delete cascade default auth.uid(),
      data jsonb not null,
      updated_at timestamptz not null default now()
    );
    alter table finance_docs enable row level security;
    create policy "own row" on finance_docs for all
      using (auth.uid() = user_id) with check (auth.uid() = user_id);
    """

    var body: some View {
        NavigationStack {
            Form {
                if sync.isSignedIn {
                    Section {
                        LabeledContent("Signed in as", value: sync.email)
                        LabeledContent("Status", value: sync.status.isEmpty ? "Ready" : sync.status)
                        Button {
                            Task { await sync.syncNow(store) }
                        } label: { Label(sync.busy ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath") }
                            .disabled(sync.busy)
                        Button("Sign out", role: .destructive) { sync.signOut() }
                    } footer: {
                        Text("Kosh syncs when you open it and a couple of seconds after each change. Use the same login in the web app on your Mac and PC.")
                    }
                } else {
                    Section {
                        HStack {
                            TextField("https://xxxx.supabase.co", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            pasteButton { url = $0 }
                        }
                        HStack {
                            TextField("Publishable (anon) key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                            pasteButton { key = $0 }
                        }
                    } header: { Text("1 · Your Supabase project") } footer: {
                        Text("Copy these on your Mac (Supabase → Project Settings → API Keys) and tap Paste here. Copying on the Mac and pasting on the iPhone works through Universal Clipboard.")
                    }
                    Section {
                        TextField("Email", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress).textContentType(.username)
                        SecureField("Password", text: $password).textContentType(.password)
                        Button { go(create: false) } label: { Text(working ? "Working…" : "Sign in") }.disabled(working)
                        Button { go(create: true) } label: { Text("Create login") }.disabled(working)
                    } header: { Text("2 · Your login") } footer: {
                        Text("Use the same email and password you use in the Kosh web app.")
                    }
                    if let message { Section { Text(message).foregroundStyle(message.hasPrefix("✓") ? K.good : K.warn) } }
                    Section {
                        Text(Self.setupSQL).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Button("Copy setup code") { UIPasteboard.general.string = Self.setupSQL; message = "✓ Copied. Paste it into Supabase → SQL Editor → Run." }
                    } header: { Text("One-time database setup") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x121215))
            .navigationTitle("Sync between devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { url = sync.url; key = sync.key; email = sync.email }
        }
        .tint(K.brand)
    }

    func pasteButton(_ set: @escaping (String) -> Void) -> some View {
        Button("Paste") { if let s = UIPasteboard.general.string { set(s.trimmingCharacters(in: .whitespacesAndNewlines)) } }
            .font(.system(size: 14, weight: .semibold))
            .buttonStyle(.borderless)
    }

    func go(create: Bool) {
        guard url.hasPrefix("https://"), key.count > 20 else { message = "Check the project URL and key."; return }
        guard email.contains("@"), password.count >= 6 else { message = "Enter your email and a password of at least 6 characters."; return }
        sync.configure(url: url, key: key)
        working = true
        Task {
            defer { working = false }
            do {
                let ok = try await sync.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password, create: create)
                if ok {
                    password = ""
                    message = "✓ Signed in. Syncing…"
                    await sync.syncNow(store)
                    message = "✓ " + sync.status
                } else {
                    message = "Check your email and tap the confirm link, then come back and tap Sign in."
                }
            } catch {
                message = (error as? SyncService.SyncError)?.text ?? error.localizedDescription
            }
        }
    }
}
