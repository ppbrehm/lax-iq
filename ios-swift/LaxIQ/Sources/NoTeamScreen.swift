import SwiftUI

struct NoTeamScreen: View {
    var onSignOut: () -> Void

    var body: some View {
        ZStack {
            Color(white: 0.95).ignoresSafeArea()

            VStack(spacing: 12) {
                Text("🥍").font(.system(size: 48))
                Text("Not Linked to a Team").font(.system(size: 24, weight: .heavy))
                Text("Your account isn't connected to a team yet. Ask your head coach or the app administrator to invite your email, then sign up again.")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                Button("Sign Out", action: onSignOut)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.top, 16)
            }
            .padding(28)
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.1), radius: 24, x: 0, y: 8)
            .frame(maxWidth: 400)
            .padding(.horizontal, 24)
        }
    }
}
