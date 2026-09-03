import AppKit
import SwiftUI

/// One Meridian lane: the Location's day rendered as a smooth
/// night → twilight → day gradient on the shared home-time axis, with the
/// sun/moon indicator at the meridian. Dragging anywhere on the lane scrubs
/// the Global Instant.
struct MeridianLaneView: View {
    let lane: DayLine
    /// The sun-altitude curve across the home day (degrees), driving the
    /// shader's sky ramp, daylight wash, and star visibility.
    let altitudes: [Float]
    /// Decorrelates the star field between lanes.
    let starSeed: Float
    let theme: PanelTheme
    /// When off, night shows a plain disc instead of the phase-correct moon.
    var showsMoonPhase: Bool = true
    /// Called with the drag's day fraction and pointer velocity (pt/s) while
    /// scrubbing; the fraction may run past [0, 1] when the drag leaves the bar.
    var onScrub: ((Double, CGFloat) -> Void)?
    /// Called when the drag ends, so the scrub anchor can be released.
    var onScrubEnded: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let indicatorRadius: CGFloat = 6
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white)
                    .colorEffect(ShaderLibrary.meridianLane(
                        .float2(Float(geometry.size.width), Float(geometry.size.height)),
                        .floatArray(altitudes),
                        .color(theme.night),
                        .color(theme.twilight),
                        .color(theme.day),
                        .float(starSeed)
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.white.opacity(0.05), lineWidth: 1)
                    )
                indicatorView
                    .frame(width: indicatorRadius * 2, height: indicatorRadius * 2)
                    .position(
                        x: min(max(lane.indicatorPosition * width, indicatorRadius), width - indicatorRadius),
                        y: geometry.size.height / 2
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard width > 0 else { return }
                        onScrub?(value.location.x / width, abs(value.velocity.width))
                    }
                    .onEnded { _ in
                        onScrubEnded?()
                    }
            )
        }
        .frame(height: 26)
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch lane.indicator {
        case .sun:
            Circle()
                .fill(RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.96, blue: 0.82),
                        Color(red: 1.0, green: 0.78, blue: 0.27),
                        Color(red: 1.0, green: 0.66, blue: 0.16),
                    ],
                    center: UnitPoint(x: 0.4, y: 0.4),
                    startRadius: 0,
                    endRadius: 7
                ))
                .shadow(color: Color(red: 1.0, green: 0.75, blue: 0.27).opacity(0.7), radius: 3)
                .shadow(color: Color(red: 1.0, green: 0.67, blue: 0.24).opacity(0.3), radius: 8)
        case let .moon(phase):
            ZStack {
                Circle()
                    .fill(Color(red: 0.23, green: 0.26, blue: 0.4))
                if showsMoonPhase {
                    MoonShape(phase: phase)
                        .fill(Color(red: 0.95, green: 0.96, blue: 0.99))
                } else {
                    Circle()
                        .fill(Color(red: 0.55, green: 0.58, blue: 0.72))
                        .padding(2)
                }
            }
            .shadow(color: Color(red: 0.78, green: 0.84, blue: 1.0).opacity(0.5), radius: 3)
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
