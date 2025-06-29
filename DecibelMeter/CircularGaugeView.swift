import SwiftUI

/// A simple circular gauge that scales with its container.
struct CircularGaugeView: View {
    /// Current level between 0 and 140 dB.
    var level: Float

    var body: some View {
        GeometryReader { geo in
            let size = geo.size.width * 0.75
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: size * 0.05)

                // Progress arc
                Circle()
                    .trim(from: 0, to: CGFloat(min(level / 140, 1)))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.cyan, .blue, .purple]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: size * 0.05, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(Int(level)) dB")
                    .font(.system(size: size * 0.2, weight: .bold, design: .rounded))
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

#Preview {
    CircularGaugeView(level: 70)
        .frame(width: 300, height: 300)
        .padding()
}
