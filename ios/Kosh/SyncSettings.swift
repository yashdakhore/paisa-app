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
                        Button {
                            let clip = UIPasteboard.general.string ?? ""
                            let u = SyncService.extractURL(clip)
                            let k = SyncService.extractKey(clip)
                            if let u { url = u }
                            if let k { key = k }
                            message = (u != nil && k != nil) ? "✓ Address and key pasted." :
                                (u == nil && k == nil) ? "Nothing found. Copy the whole note (address and key) first." :
                                (u == nil ? "Found the key, but no address. Copy the https://…supabase.co line too." : "Found the address, but no key. Copy the sb_publishable_… line too.")
                        } label: { Label("Paste address and key", systemImage: "doc.on.clipboard") }
                        HStack {
                            TextField("https://xxxx.supabase.co", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            pasteButton { url = $0 }
                        }
                        HStack {
                            TextField("Publishable (anon) key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                            pasteButton { key = $0 }
                        }
                    } header: { Text("1 · Your Supabase project") } footer: {
                        Text("Easiest: copy the whole note that has both the address and the key, then tap “Paste address and key”. Extra text is ignored.")
                    }
                    Section {
                        TextField("Email", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress).textContentType(.username)
                        SecureField("Password", text: $password).textContentType(.password)
                        Button { go(create: true) } label: { Text(working ? "Working…" : "Create login (first time)") }.disabled(working)
                        Button { go(create: false) } label: { Text("Sign in (already have a login)") }.disabled(working)
                        if let message { Text(message).font(.system(size: 14)).foregroundStyle(message.hasPrefix("✓") ? K.good : K.warn) }
                    } header: { Text("2 · Your login") } footer: {
                        Text("Use the same email and password later in the Kosh web app on your Mac.")
                    }
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
            // Remember what's pasted right away, so switching to Notes and back doesn't lose it.
            .onChange(of: url) { _, v in sync.configure(url: v, key: key) }
            .onChange(of: key) { _, v in sync.configure(url: url, key: v) }
        }
        .tint(K.brand)
    }

    func pasteButton(_ set: @escaping (String) -> Void) -> some View {
        Button("Paste") { if let s = UIPasteboard.general.string { set(s.trimmingCharacters(in: .whitespacesAndNewlines)) } }
            .font(.system(size: 14, weight: .semibold))
            .buttonStyle(.borderless)
    }

    func go(create: Bool) {
        if let u = SyncService.extractURL(url) { url = u }
        if let k = SyncService.extractKey(key) { key = k }
        guard url.trimmingCharacters(in: .whitespaces).hasPrefix("https://") else { message = "The first box needs the address starting with https://"; return }
        guard key.trimmingCharacters(in: .whitespaces).count > 20 else { message = "The second box needs the key starting with sb_publishable_"; return }
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
