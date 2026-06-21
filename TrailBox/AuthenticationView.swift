import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .login
    @State private var username = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    enum Mode { case login, register }

    var body: some View {
        NavigationStack {
            ZStack {
                TrailBoxColor.background.ignoresSafeArea()
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text("小野box").font(.title.bold()).foregroundStyle(TrailBoxColor.text)
                        Text(mode == .login ? "登录后管理你的运动记录" : "创建账号，开始保存路线")
                            .font(.subheadline).foregroundStyle(TrailBoxColor.secondaryText)
                    }.padding(.top, 28)
                    SectionCard {
                        VStack(spacing: 14) {
                            TextField("用户名", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                            SecureField("密码（至少 8 位）", text: $password).textFieldStyle(.roundedBorder)
                            if mode == .register { TextField("昵称（可选）", text: $nickname).textFieldStyle(.roundedBorder) }
                            if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(TrailBoxColor.danger).frame(maxWidth: .infinity, alignment: .leading) }
                            Button { submit() } label: { if isSubmitting { ProgressView().tint(.white) } else { Text(mode == .login ? "登录" : "注册") .frame(maxWidth: .infinity) } }
                                .buttonStyle(.borderedProminent).tint(TrailBoxColor.primary).disabled(isSubmitting || username.isEmpty || password.isEmpty)
                        }
                    }
                    Button(mode == .login ? "没有账号？去注册" : "已有账号？去登录") { mode = mode == .login ? .register : .login; errorMessage = nil }
                        .font(.subheadline).foregroundStyle(TrailBoxColor.primaryDark)
                    Spacer()
                }.padding(.horizontal, 16)
            }
            .navigationTitle(mode == .login ? "登录" : "注册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } } }
        }
    }

    private func submit() {
        isSubmitting = true; errorMessage = nil
        Task {
            do {
                if mode == .login { try await session.login(username: username, password: password) }
                else { try await session.register(username: username, password: password, nickname: nickname.isEmpty ? nil : nickname) }
                dismiss()
            } catch { errorMessage = error.localizedDescription }
            isSubmitting = false
        }
    }
}
