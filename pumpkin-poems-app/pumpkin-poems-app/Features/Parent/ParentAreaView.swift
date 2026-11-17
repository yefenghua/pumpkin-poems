import SwiftData
import SwiftUI

/// 家长区域 (L08–L10): learners and profiles, the weekly report, sync, the parent account and feedback.
/// The arithmetic gate only keeps children from wandering in; it is not authentication — the account itself
/// is an account ID + password, verified by the server.
struct ParentAreaView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(AccountStore.self) private var account
    @Environment(ProfileManager.self) private var profiles
    @Environment(SyncEngine.self) private var sync

    @State private var unlocked = false
    @State private var newNickname = ""
    @State private var newStage: String?
    @State private var guestSummary: (poems: Int, drafts: Int) = (0, 0)
    @State private var migrationTarget: ChildProfile?
    @State private var confirmSignOut = false
    @State private var confirmDeleteAccount = false
    @State private var profileToDelete: ChildProfile?
    @State private var notice: String?
    @State private var accountID = ""
    @State private var password = ""
    @State private var showChangePassword = false
    @State private var currentPassword = ""
    @State private var newPassword = ""

    var body: some View {
        Group {
            if unlocked {
                content
            } else {
                ParentGate { unlocked = true }
            }
        }
        .pageBackground()
        .navigationTitle(settings.t("家長區域", "家长区域"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        Form {
            learnerSection
            Section {
                Button {
                    router.push(.weeklyReport)
                } label: {
                    Label(settings.t("學習周報", "学习周报"), systemImage: "chart.bar.doc.horizontal")
                }
                Button {
                    router.push(.feedback)
                } label: {
                    Label(settings.t("意見反饋", "意见反馈"), systemImage: "envelope")
                }
            }
            if account.isSignedIn {
                profilesSection
                if guestSummary.poems + guestSummary.drafts > 0 {
                    migrationSection
                }
                syncSection
            }
            accountSection
            if let notice {
                Section {
                    Text(notice).font(.footnote).foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { guestSummary = SyncEngine.guestSummary() }
        .task {
            if account.isSignedIn { try? await account.refreshProfiles() }
        }
        .confirmationDialog(settings.t("退出家長賬號？", "退出家长账号？"), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(settings.t("退出", "退出"), role: .destructive) { account.signOut() }
        } message: {
            Text(settings.t("各兒童檔案的記錄會從這部裝置移除（雲端保留），App 回到遊客模式，下一位使用者看不到這些記錄。",
                            "各儿童档案的记录会从这台设备移除（云端保留），App 回到游客模式，下一位使用者看不到这些记录。"))
        }
        .confirmationDialog(settings.t("刪除賬號和雲端資料？", "删除账号和云端数据？"), isPresented: $confirmDeleteAccount,
                            titleVisibility: .visible) {
            Button(settings.t("永久刪除", "永久删除"), role: .destructive) {
                Task {
                    if await account.deleteAccount() {
                        notice = settings.t("賬號、所有兒童檔案和雲端作品已刪除；這部裝置上的檔案記錄也已清除，遊客記錄保留。",
                                            "账号、所有儿童档案和云端作品已删除；这台设备上的档案记录也已清除，游客记录保留。")
                    }
                }
            }
        } message: {
            Text(settings.t("會刪除家長賬號、全部兒童檔案、學習記錄和雲端作品，無法恢復。這部裝置上這些檔案的緩存也會刪除；遊客模式的記錄不受影響。",
                            "会删除家长账号、全部儿童档案、学习记录和云端作品，无法恢复。这台设备上这些档案的缓存也会删除；游客模式的记录不受影响。"))
        }
        .confirmationDialog(settings.t("刪除這個兒童檔案？", "删除这个儿童档案？"),
                            isPresented: Binding(get: { profileToDelete != nil }, set: { if !$0 { profileToDelete = nil } }),
                            titleVisibility: .visible) {
            Button(settings.t("刪除", "删除"), role: .destructive) {
                if let profile = profileToDelete { Task { await account.deleteProfile(profile.id) } }
            }
        } message: {
            Text(settings.t("檔案的學習記錄和作品會從雲端和這部裝置刪除。", "档案的学习记录和作品会从云端和这台设备删除。"))
        }
    }

    // MARK: Sections

    private var learnerSection: some View {
        Section {
            LabeledContent(settings.t("現在使用", "现在使用"),
                           value: account.profile(profiles.currentProfileID)?.nickname ?? settings.t("遊客（本機）", "游客（本机）"))
            if !profiles.isGuest {
                Button(settings.t("切換到遊客", "切换到游客")) { profiles.switchTo(nil) }
            }
        } header: {
            Text(settings.t("學習者", "学习者"))
        } footer: {
            Text(account.isSignedIn
                 ? settings.t("每個兒童檔案的記錄分開保存，切換不會互相影響。", "每个儿童档案的记录分开保存，切换不会互相影响。")
                 : settings.t("不登錄也可以完整學習，記錄只保存在這部裝置。", "不登录也可以完整学习，记录只保存在这台设备。"))
        }
    }

    private var profilesSection: some View {
        Section {
            ForEach(account.profiles) { profile in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.nickname)
                        if let stage = profile.stage {
                            Text(Self.stageTitle(stage, settings)).font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                    if profiles.currentProfileID == profile.id {
                        Text(settings.t("使用中", "使用中")).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.Colors.successGreen)
                    } else {
                        Button(settings.t("切換", "切换")) {
                            profiles.switchTo(profile.id)
                            Task { await sync.syncNow() }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .swipeActions {
                    Button(settings.t("刪除", "删除"), role: .destructive) { profileToDelete = profile }
                }
            }
            HStack {
                TextField(settings.t("孩子的暱稱", "孩子的昵称"), text: $newNickname)
                Picker("", selection: $newStage) {
                    Text(settings.t("年級（可不填）", "年级（可不填）")).tag(String?.none)
                    ForEach(["p4", "p5", "p6", "s1"], id: \.self) { stage in
                        Text(Self.stageTitle(stage, settings)).tag(String?.some(stage))
                    }
                }
                .labelsHidden()
            }
            Button(settings.t("新增兒童檔案", "新增儿童档案")) {
                let name = newNickname.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    if await account.createProfile(nickname: name, stage: newStage) != nil {
                        newNickname = ""
                        newStage = nil
                    }
                }
            }
            .disabled(newNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || account.isWorking)
        } header: {
            Text(settings.t("兒童檔案", "儿童档案"))
        } footer: {
            Text(settings.t("只需要暱稱，不需要真實姓名、學校、電話或生日。年級只用來推薦內容。",
                            "只需要昵称，不需要真实姓名、学校、电话或生日。年级只用来推荐内容。"))
        }
    }

    private var migrationSection: some View {
        Section {
            Text(settings.t("這部裝置上有遊客記錄：\(guestSummary.poems) 首詩的學習記錄、\(guestSummary.drafts) 首作品。",
                            "这台设备上有游客记录：\(guestSummary.poems) 首诗的学习记录、\(guestSummary.drafts) 首作品。"))
            Picker(settings.t("歸入", "归入"), selection: $migrationTarget) {
                Text(settings.t("請選擇檔案", "请选择档案")).tag(ChildProfile?.none)
                ForEach(account.profiles) { profile in
                    Text(profile.nickname).tag(ChildProfile?.some(profile))
                }
            }
            Button(settings.t("歸入這個檔案", "归入这个档案")) {
                guard let target = migrationTarget else { return }
                Task {
                    if await sync.migrateGuest(into: target.id) {
                        notice = settings.t("遊客記錄已歸入「\(target.nickname)」。", "游客记录已归入“\(target.nickname)”。")
                        guestSummary = (0, 0)
                    }
                }
            }
            .disabled(migrationTarget == nil || sync.status == .syncing)
        } header: {
            Text(settings.t("遊客記錄", "游客记录"))
        } footer: {
            Text(settings.t("由家長選擇歸入哪個孩子。重複操作不會重複計算進度。", "由家长选择归入哪个孩子。重复操作不会重复计算进度。"))
        }
    }

    private var syncSection: some View {
        Section {
            LabeledContent(settings.t("狀態", "状态"), value: syncStatusText)
            if let last = sync.lastSyncedAt {
                LabeledContent(settings.t("上次同步", "上次同步"), value: last.formatted(date: .omitted, time: .shortened))
            }
            Button(settings.t("立即同步", "立即同步")) { Task { await sync.syncNow() } }
                .disabled(profiles.isGuest || sync.status == .syncing)
            if sync.newConflictCopies > 0 {
                Text(settings.t("有作品在兩部裝置上同時修改過，兩個版本都保留在「我的詩集」，標記為「衝突副本」。",
                                "有作品在两台设备上同时修改过，两个版本都保留在“我的诗集”，标记为“冲突副本”。"))
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.accentOrange)
            }
        } header: {
            Text(settings.t("多設備同步", "多设备同步"))
        } footer: {
            Text(profiles.isGuest
                 ? settings.t("遊客記錄不會上傳。切換到兒童檔案後才會同步。", "游客记录不会上传。切换到儿童档案后才会同步。")
                 : settings.t("網絡不好時先保存在本機，恢復後自動上傳。", "网络不好时先保存在本机，恢复后自动上传。"))
        }
    }

    private var syncStatusText: String {
        if profiles.isGuest { return settings.t("遊客不同步", "游客不同步") }
        switch sync.status {
        case .syncing: return settings.t("同步中…", "同步中…")
        case .failed: return settings.t("待同步（\(sync.pendingCount)），稍後重試", "待同步（\(sync.pendingCount)），稍后重试")
        case .idle: return sync.pendingCount > 0 ? settings.t("待同步（\(sync.pendingCount)）", "待同步（\(sync.pendingCount)）")
                                                 : settings.t("已同步", "已同步")
        }
    }

    private var accountSection: some View {
        Section {
            if account.isSignedIn {
                LabeledContent(settings.t("賬號", "账号"), value: account.accountID ?? "")
                Button(showChangePassword ? settings.t("取消修改密碼", "取消修改密码") : settings.t("修改密碼", "修改密码")) {
                    showChangePassword.toggle()
                    currentPassword = ""
                    newPassword = ""
                    account.clearError()
                }
                if showChangePassword {
                    SecureField(settings.t("目前密碼", "当前密码"), text: $currentPassword)
                    SecureField(settings.t("新密碼（至少 8 個字）", "新密码（至少 8 个字）"), text: $newPassword)
                    Button(settings.t("確認修改", "确认修改")) {
                        Task {
                            if await account.changePassword(current: currentPassword, new: newPassword) {
                                showChangePassword = false
                                currentPassword = ""
                                newPassword = ""
                                notice = settings.t("密碼已修改，其他裝置已登出。", "密码已修改，其他设备已登出。")
                            }
                        }
                    }
                    .disabled(currentPassword.isEmpty || newPassword.count < 8 || account.isWorking)
                }
                Button(settings.t("退出家長賬號", "退出家长账号")) { confirmSignOut = true }
                Button(settings.t("刪除賬號和雲端資料", "删除账号和云端数据"), role: .destructive) { confirmDeleteAccount = true }
            } else {
                TextField(settings.t("賬號 ID（字母、數字、. _ -）", "账号 ID（字母、数字、. _ -）"), text: $accountID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.username)
                SecureField(settings.t("密碼（至少 8 個字）", "密码（至少 8 个字）"), text: $password)
                    .textContentType(.password)
                HStack {
                    Button(settings.t("登錄", "登录")) {
                        Task { await account.signIn(accountID: accountID, password: password) }
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Button(settings.t("註冊新賬號", "注册新账号")) {
                        Task {
                            await account.register(accountID: accountID, password: password)
                            if account.isSignedIn { password = "" }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(!credentialsFilled || account.isWorking)
            }
            if let error = accountErrorText {
                Text(error).font(.footnote).foregroundStyle(Color.hintRed)
            }
        } header: {
            Text(settings.t("家長賬號", "家长账号"))
        } footer: {
            Text(account.isSignedIn
                 ? settings.t("賬號只給家長使用，用來管理兒童檔案和在多部裝置同步。孩子不需要登錄。",
                              "账号只给家长使用，用来管理儿童档案和在多台设备同步。孩子不需要登录。")
                 : settings.t("賬號只給家長使用，用來管理兒童檔案和在多部裝置同步。孩子不需要登錄。\n服務端不保存郵箱或電話，密碼忘記後無法找回，請記好。",
                              "账号只给家长使用，用来管理儿童档案和在多台设备同步。孩子不需要登录。\n服务端不保存邮箱或电话，密码忘记后无法找回，请记好。"))
        }
    }

    private var credentialsFilled: Bool {
        accountID.trimmingCharacters(in: .whitespaces).count >= 4 && password.count >= 8
    }

    /// Server error codes (docs/api/phase2-api.md §3) in the parent's language; anything else is shown as sent.
    private var accountErrorText: String? {
        guard let code = account.lastErrorCode ?? account.lastError else { return nil }
        switch code {
        case "invalid_credentials": return settings.t("賬號或密碼不對。", "账号或密码不对。")
        case "too_many_attempts": return settings.t("嘗試太多次，請 15 分鐘後再試。", "尝试太多次，请 15 分钟后再试。")
        case "account_id_taken": return settings.t("這個賬號 ID 已被使用，請換一個或直接登錄。", "这个账号 ID 已被使用，请换一个或直接登录。")
        case "invalid_account_id": return settings.t("賬號 ID 須為 4–32 個字母、數字、. _ -，以字母或數字開頭。",
                                                      "账号 ID 须为 4–32 个字母、数字、. _ -，以字母或数字开头。")
        case "weak_password": return settings.t("密碼須為 8–128 個字，且不能與賬號 ID 相同。", "密码须为 8–128 个字，且不能与账号 ID 相同。")
        case "wrong_password": return settings.t("目前密碼不對。", "当前密码不对。")
        case "unauthorized": return settings.t("登錄已過期，請重新登錄。", "登录已过期，请重新登录。")
        case "Server not configured": return settings.t("未設置服務地址（設置 → 服務地址）。", "未设置服务地址（设置 → 服务地址）。")
        default: return account.lastError
        }
    }

    static func stageTitle(_ stage: String, _ settings: AppSettings) -> String {
        switch stage {
        case "p4": settings.t("小四", "小四")
        case "p5": settings.t("小五", "小五")
        case "p6": settings.t("小六", "小六")
        case "s1": settings.t("中一", "中一")
        default: stage
        }
    }
}

/// Keeps children from wandering into parent settings. Not authentication.
struct ParentGate: View {
    var unlock: () -> Void

    @Environment(AppSettings.self) private var settings
    @State private var a = Int.random(in: 12...29)
    @State private var b = Int.random(in: 3...9)
    @State private var answer = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: AppTheme.Spacing.section) {
            PendingArtwork(name: ArtworkAsset.parentScene)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.container, style: .continuous))
            VStack(spacing: 12) {
                Text(settings.t("請家長回答", "请家长回答"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("\(a) × \(b) = ?")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                TextField(settings.t("答案", "答案"), text: $answer)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title2)
                    .frame(maxWidth: 160, minHeight: 50)
                    .background(AppTheme.Colors.backgroundCream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppTheme.Colors.borderWarm, lineWidth: 1.5))
                if wrong {
                    Text(settings.t("不對，換一題再試。", "不对，换一题再试。"))
                        .font(.footnote)
                        .foregroundStyle(Color.hintRed)
                }
                Button {
                    if Int(answer) == a * b {
                        unlock()
                    } else {
                        wrong = true
                        answer = ""
                        a = Int.random(in: 12...29)
                        b = Int.random(in: 3...9)
                    }
                } label: {
                    Text(settings.t("進入", "进入"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(answer.isEmpty)
                Text(settings.t("這只是防止小朋友誤入，不是賬號登錄。", "这只是防止小朋友误入，不是账号登录。"))
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .card(padding: AppTheme.Spacing.cardInset, radius: AppTheme.CornerRadius.container)
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 12)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
