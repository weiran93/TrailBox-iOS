import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode: Mode = .login
    @State private var username = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var showsPassword = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showPrivacyPolicy = false
    @FocusState private var focusedField: Field?

    private enum Mode: String, CaseIterable, Identifiable {
        case login = "登录"
        case register = "注册"

        var id: String { rawValue }
    }

    private enum Field: Hashable {
        case username
        case nickname
        case password
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    modePicker
                    formCard
                    privacyFooter
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(TrailPageBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                NavigationStack { PrivacyPolicyView() }
            }
            .interactiveDismissDisabled(isSubmitting)
            .onAppear {
                if errorMessage == nil {
                    errorMessage = session.consumeAuthenticationError()
                }
            }
            .onChange(of: mode) { _ in
                password = ""
                showsPassword = false
                errorMessage = nil
                focusedField = nil
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [TrailBoxColor.primaryDark, TrailBoxColor.primary, TrailBoxColor.moss],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: TrailBoxColor.primaryDark.opacity(0.22), radius: 16, y: 8)

                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 5) {
                Text(mode == .login ? "欢迎回到小野box" : "加入小野box")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(TrailBoxColor.text)
                Text(mode == .login ? "继续管理路线、记录与训练分析" : "保存你的每一次出发与抵达")
                    .font(.subheadline)
                    .foregroundStyle(TrailBoxColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { option in
                Button {
                    guard option != mode else { return }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
                        mode = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(mode == option ? .white : TrailBoxColor.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(mode == option ? TrailBoxColor.primaryDark : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(TrailBoxColor.surfaceMuted, in: Capsule())
        .overlay(Capsule().stroke(TrailBoxColor.border, lineWidth: 0.75))
    }

    private var formCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("账号信息")
                        .font(.headline)
                        .foregroundStyle(TrailBoxColor.text)
                    Text(mode == .login ? "请输入已注册的用户名和密码" : "用户名用于登录，昵称可以稍后修改")
                        .font(.caption)
                        .foregroundStyle(TrailBoxColor.secondaryText)
                }

                inputRow(
                    title: "用户名",
                    systemImage: "person.fill",
                    text: $username,
                    field: .username,
                    submitLabel: .next
                ) {
                    focusedField = mode == .register ? .nickname : .password
                }

                if mode == .register {
                    inputRow(
                        title: "昵称（可选）",
                        systemImage: "leaf.fill",
                        text: $nickname,
                        field: .nickname,
                        submitLabel: .next
                    ) {
                        focusedField = .password
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                passwordRow

                if mode == .register {
                    Label(password.count >= 8 ? "密码长度符合要求" : "密码至少需要 8 位", systemImage: password.count >= 8 ? "checkmark.circle.fill" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(password.count >= 8 ? TrailBoxColor.primaryDark : TrailBoxColor.secondaryText)
                        .transition(.opacity)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(TrailBoxColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TrailBoxColor.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button { submit() } label: {
                    HStack(spacing: 9) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(mode == .login ? "登录并继续" : "创建账号")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                }
                .buttonStyle(.plain)
                .background(canSubmit ? TrailBoxColor.primaryDark : TrailBoxColor.stone.opacity(0.55), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .disabled(!canSubmit || isSubmitting)
                .accessibilityLabel(isSubmitting ? "正在提交" : (mode == .login ? "登录并继续" : "创建账号"))
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: mode)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: errorMessage)
        }
    }

    private func inputRow(
        title: String,
        systemImage: String,
        text: Binding<String>,
        field: Field,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(focusedField == field ? TrailBoxColor.primaryDark : TrailBoxColor.secondaryText)
                .frame(width: 22)
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(TrailBoxColor.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focusedField == field ? TrailBoxColor.primary : TrailBoxColor.border, lineWidth: focusedField == field ? 1.4 : 0.75)
        )
    }

    private var passwordRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(focusedField == .password ? TrailBoxColor.primaryDark : TrailBoxColor.secondaryText)
                .frame(width: 22)

            Group {
                if showsPassword {
                    TextField("密码", text: $password)
                } else {
                    SecureField("密码", text: $password)
                }
            }
            .textContentType(mode == .login ? .password : .newPassword)
            .focused($focusedField, equals: .password)
            .submitLabel(.go)
            .onSubmit { if canSubmit { submit() } }

            Button { showsPassword.toggle() } label: {
                Image(systemName: showsPassword ? "eye.slash" : "eye")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TrailBoxColor.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsPassword ? "隐藏密码" : "显示密码")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 52)
        .background(TrailBoxColor.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focusedField == .password ? TrailBoxColor.primary : TrailBoxColor.border, lineWidth: focusedField == .password ? 1.4 : 0.75)
        )
    }

    private var privacyFooter: some View {
        VStack(spacing: 8) {
            if mode == .register {
                Text("创建账号即表示你已阅读并同意隐私政策。")
                    .font(.caption)
                    .foregroundStyle(TrailBoxColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
            Button("查看隐私政策") { showPrivacyPolicy = true }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TrailBoxColor.primaryDark)
                .frame(minHeight: 44)
        }
    }

    private var canSubmit: Bool {
        let hasCredentials = !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        return hasCredentials && (mode == .login || password.count >= 8)
    }

    private func submit() {
        guard canSubmit, !isSubmitting else { return }
        focusedField = nil
        isSubmitting = true
        errorMessage = nil
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                if mode == .login {
                    try await session.login(username: cleanUsername, password: password)
                } else {
                    try await session.register(
                        username: cleanUsername,
                        password: password,
                        nickname: cleanNickname.isEmpty ? nil : cleanNickname
                    )
                }
                dismiss()
            } catch {
                errorMessage = ErrorMessage.display(error)
            }
            isSubmitting = false
        }
    }
}
