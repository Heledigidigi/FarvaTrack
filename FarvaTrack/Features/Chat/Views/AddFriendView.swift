import SwiftUI

/// Arkadaş ekle: önce kendi kullanıcı adını seç, sonra kullanıcı adıyla ara ve istek gönder.
/// Gelen ve gönderilen istekler de burada.
struct AddFriendView: View {
    @Bindable var friends: FriendsViewModel
    /// Bir isteği kabul edince açılan sohbete geçmek için.
    var onOpenRoom: (String) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var editingUsername = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch friends.myUsername {
                case .none:
                    VStack(spacing: 12) {
                        ProgressView().tint(Color.ftAccentLight)
                        Button("Tekrar dene") { Task { await friends.loadUsername() } }
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .some(let name) where name.isEmpty || editingUsername:
                    UsernameSetupView(friends: friends, isChange: !name.isEmpty) {
                        editingUsername = false
                    }
                default:
                    searchList
                }
            }
            .ftScreenBackground()
            .navigationTitle("Arkadaş ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Kapat")
                }
            }
            .alert("Bir sorun oluştu", isPresented: Binding(get: { friends.errorMessage != nil },
                                                           set: { if !$0 { friends.errorMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(friends.errorMessage ?? "")
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Arama

    private var searchList: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.ftTextSecondary)
                    Text("@").foregroundStyle(Color.ftTextSecondary)
                    TextField("kullanıcı adı", text: $friends.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .accessibilityLabel("Kullanıcı adıyla ara")
                    if friends.isSearching { ProgressView().controlSize(.small) }
                }
            } footer: {
                if let me = friends.me {
                    HStack(spacing: 4) {
                        Text("Senin kullanıcı adın: @\(me.username)")
                        Button("Değiştir") {
                            friends.usernameInput = me.username
                            editingUsername = true
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
            }
            .listRowBackground(Color.ftCard)

            if !friends.query.isEmpty {
                Section("Sonuçlar") {
                    if friends.results.isEmpty, !friends.isSearching {
                        Text("Bu adla başlayan kimse yok.")
                            .foregroundStyle(Color.ftTextSecondary)
                    }
                    ForEach(friends.results) { profile in
                        FriendResultRow(profile: profile, friends: friends)
                    }
                }
                .listRowBackground(Color.ftCard)
            }

            if !friends.incoming.isEmpty {
                Section("Gelen istekler") {
                    ForEach(friends.incoming) { request in
                        FriendRequestRow(request: request, friends: friends) {
                            onOpenRoom(ChatID.make(request.from.userID, request.to.userID))
                        }
                    }
                }
                .listRowBackground(Color.ftCard)
            }

            if !friends.outgoing.isEmpty {
                Section("Gönderdiğin istekler") {
                    ForEach(friends.outgoing) { request in
                        HStack(spacing: 12) {
                            FriendIdentity(profile: request.to)
                            Spacer()
                            Button("Geri çek") { Task { await friends.remove(request) } }
                                .font(.subheadline)
                                .buttonStyle(.borderless)
                                .tint(Color.ftTextSecondary)
                                .disabled(friends.busy.contains(request.to.userID))
                        }
                    }
                }
                .listRowBackground(Color.ftCard)
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { if friends.incoming.isEmpty { searchFocused = true } }
    }
}

// MARK: - Kullanıcı adı seçimi

private struct UsernameSetupView: View {
    @Bindable var friends: FriendsViewModel
    let isChange: Bool
    let onDone: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isChange ? "Kullanıcı adını değiştir" : "Önce bir kullanıcı adı seç")
                        .font(.title3.bold())
                    Text("Arkadaşların seni bu adla bulup ekleyecek. Harf, rakam, nokta ve alt çizgi kullanabilirsin.")
                        .font(.subheadline)
                        .foregroundStyle(Color.ftTextSecondary)
                }

                HStack(spacing: 4) {
                    Text("@").font(.title3.weight(.semibold)).foregroundStyle(Color.ftTextSecondary)
                    TextField("kullaniciadi", text: $friends.usernameInput)
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityLabel("Kullanıcı adı")
                }
                .padding(.horizontal, 14)
                .frame(height: Constants.Layout.fieldHeight)
                .background(Color.ftCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                let normalized = ChatUsername.normalize(friends.usernameInput)
                if let problem = friends.usernameProblem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.ftWarning)
                } else if !normalized.isEmpty, normalized != friends.usernameInput {
                    Text("Şöyle kaydedilecek: @\(normalized)")
                        .font(.footnote)
                        .foregroundStyle(Color.ftTextSecondary)
                }

                Button("Kaydet", action: save)
                    .buttonStyle(PrimaryButtonStyle(isLoading: friends.isSavingUsername))
                    .disabled(friends.isSavingUsername || !ChatUsername.isValid(normalized))

                if isChange {
                    Button("Vazgeç", action: onDone)
                        .frame(maxWidth: .infinity)
                        .tint(Color.ftTextSecondary)
                }
            }
            .padding(Constants.Layout.screenPadding)
        }
        .onAppear { focused = true }
    }

    private func save() {
        Task {
            if await friends.saveUsername() { onDone() }
        }
    }
}

// MARK: - Satırlar

/// Avatar + ad + @kullanıcı adı.
struct FriendIdentity: View {
    let profile: FriendProfile

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: profile.displayName, photoURL: profile.photoURL)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName.isEmpty ? "@\(profile.username)" : profile.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !profile.username.isEmpty {
                    Text("@\(profile.username)")
                        .font(.caption)
                        .foregroundStyle(Color.ftTextSecondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FriendResultRow: View {
    let profile: FriendProfile
    let friends: FriendsViewModel

    var body: some View {
        HStack(spacing: 12) {
            FriendIdentity(profile: profile)
            Spacer()
            switch friends.relation(to: profile.userID) {
            case .me:
                Text("Sen").font(.subheadline).foregroundStyle(Color.ftTextSecondary)
            case .friend:
                Label("Arkadaşsınız", systemImage: "checkmark")
                    .font(.subheadline)
                    .foregroundStyle(Color.ftTextSecondary)
            case .requestSent:
                Text("İstek gönderildi").font(.subheadline).foregroundStyle(Color.ftTextSecondary)
            case .requestReceived:
                actionButton("Kabul et")
            case .none:
                actionButton("Ekle")
            }
        }
    }

    private func actionButton(_ title: String) -> some View {
        Button {
            Task { await friends.add(profile) }
        } label: {
            if friends.busy.contains(profile.userID) {
                ProgressView().controlSize(.small)
            } else {
                Text(title).font(.subheadline.weight(.semibold))
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.ftAccent)
        .disabled(friends.busy.contains(profile.userID))
        .accessibilityLabel("\(profile.displayName) kişisini \(title == "Ekle" ? "arkadaş olarak ekle" : "kabul et")")
    }
}

/// Gelen istek: Kabul et / Reddet.
struct FriendRequestRow: View {
    let request: FriendRequest
    let friends: FriendsViewModel
    var onAccepted: () -> Void = {}

    var body: some View {
        let busy = friends.busy.contains(request.from.userID)
        HStack(spacing: 10) {
            FriendIdentity(profile: request.from)
            Spacer(minLength: 4)
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await friends.remove(request) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(Color.ftCardElevated, in: Circle())
                }
                .buttonStyle(.borderless)
                .tint(.white)
                .accessibilityLabel("\(request.from.displayName) isteğini reddet")

                Button {
                    Task {
                        if await friends.accept(request) { onAccepted() }
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.ftAccent, in: Circle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(request.from.displayName) isteğini kabul et")
            }
        }
    }
}
