import SwiftUI

/// Renders a DayLine: a capsule of night/twilight/day segments with the time
/// indicator — a sun by day, a phase-correct moon by night. Custom paths, not
/// emoji.
struct DayLineView: View {
    let dayLine: DayLine
    /// Called with the drag's day fraction while scrubbing; may run past
    /// [0, 1] when the drag leaves the bar.
    var onScrub: ((Double) -> Void)?
    /// Called when the drag ends, so the scrub anchor can be released.
    var onScrubEnded: (() -> Void)?

    private static let nightColor = Color(red: 0.10, green: 0.12, blue: 0.25)
    private static let twilightColor = Color(red: 0.80, green: 0.45, blue: 0.30)
    private static let dayColor = Color(red: 0.99, green: 0.82, blue: 0.38)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let indicatorRadius: CGFloat = 5.5
            ZStack(alignment: .leading) {
                Canvas { context, size in
                    let bar = CGRect(x: 0, y: size.height / 2 - 2, width: size.width, height: 4)
                    context.clip(to: Path(roundedRect: bar, cornerRadius: 2))
                    for segment in dayLine.segments {
                        let rect = CGRect(
                            x: segment.start * size.width,
                            y: bar.minY,
                            width: (segment.end - segment.start) * size.width,
                            height: bar.height
                        )
                        context.fill(Path(rect), with: .color(color(for: segment.kind)))
                    }
                }

                indicatorView
                    .frame(width: indicatorRadius * 2, height: indicatorRadius * 2)
                    .position(
                        x: min(max(dayLine.indicatorPosition * width, indicatorRadius), width - indicatorRadius),
                        y: geometry.size.height / 2
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard width > 0 else { return }
                        onScrub?(value.location.x / width)
                    }
                    .onEnded { _ in
                        onScrubEnded?()
                    }
            )
        }
        .frame(height: 14)
    }

    private func color(for kind: DayLine.SegmentKind) -> Color {
        switch kind {
        case .night: Self.nightColor
        case .twilight: Self.twilightColor
        case .day: Self.dayColor
        }
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch dayLine.indicator {
        case .sun:
            Circle()
                .fill(Color(red: 1.0, green: 0.85, blue: 0.3))
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.2).opacity(0.8), radius: 3)
        case let .moon(phase):
            ZStack {
                Circle()
                    .fill(Color(red: 0.16, green: 0.18, blue: 0.30))
                MoonShape(phase: phase)
                    .fill(Color(red: 0.92, green: 0.93, blue: 0.98))
            }
            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 2)
        }
    }
}

/// The lit portion of the moon's disc for a phase fraction (0 new, 0.25 first
/// quarter, 0.5 full, 0.75 last quarter). The lit region is bounded by the
/// bright limb on one side and the terminator ellipse on the other.
struct MoonShape: Shape {
    let phase: Double

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let waxing = phase < 0.5
        let terminatorFactor = cos(2 * .pi * phase)
        let limbX: CGFloat = waxing ? radius : -radius
        let terminatorX = CGFloat(waxing ? terminatorFactor : -terminatorFactor) * radius

        var path = Path()
        let steps = 24
        func point(_ step: Int, xRadius: CGFloat) -> CGPoint {
            let theta = -Double.pi / 2 + .pi * Double(step) / Double(steps)
            return CGPoint(
                x: center.x + xRadius * CGFloat(cos(theta)),
                y: center.y + radius * CGFloat(sin(theta))
            )
        }
        path.move(to: point(0, xRadius: limbX))
        for step in 1...steps {
            path.addLine(to: point(step, xRadius: limbX))
        }
        for step in (0...steps).reversed() {
            path.addLine(to: point(step, xRadius: terminatorX))
        }
        path.closeSubpath()
        return path
    }
}
