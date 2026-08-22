import SwiftUI

// MARK: - App Store / investor showcase
// Sign in: info@erdanimates.shop · 1234567890 → curated screens for screenshots.

struct AppStoreShowcaseView: View {
    var onSignOut: () -> Void
    @State private var shot: Shot = .doctorHome

    enum Shot: String, CaseIterable, Identifiable {
        case doctorHome = "Doctor Home"
        case doctorMarket = "Open Shifts"
        case hospitalDash = "Hospital Dashboard"
        case alterRates = "Alter Rates"
        case approvals = "Approvals"
        case analytics = "Analytics"

        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .doctorHome: return "Assigned coverage at a glance"
            case .doctorMarket: return "Claim open call with locked rates"
            case .hospitalDash: return "Fill rate and gaps under control"
            case .alterRates: return "Smart Algo or locked hospital rates"
            case .approvals: return "Verify doctors before they cover"
            case .analytics: return "Savings you can audit"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    shotPicker
                    TabView(selection: $shot) {
                        ForEach(Shot.allCases) { s in
                            ShowcaseFrame(title: s.rawValue, subtitle: s.subtitle) {
                                shotContent(s)
                            }
                            .tag(s)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("MD Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Screenshot kit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.textTertiary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out", action: onSignOut)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Store size: 1284 × 2778")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Upload the PNGs from the AppStoreScreenshots folder (not a phone screenshot). Wrong sizes come from newer Pro Max simulators.")
                        .font(.caption2)
                        .foregroundStyle(Brand.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Brand.surfaceHigh)
            }
        }
    }

    private var shotPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Shot.allCases) { s in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { shot = s }
                    } label: {
                        Text(s.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                shot == s ? Brand.accent : Brand.surfaceHigh,
                                in: Capsule()
                            )
                            .foregroundStyle(shot == s ? Color.white : Brand.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func shotContent(_ shot: Shot) -> some View {
        switch shot {
        case .doctorHome: DoctorHomeShot()
        case .doctorMarket: OpenShiftsShot()
        case .hospitalDash: HospitalDashboardShot()
        case .alterRates: AlterRatesShot()
        case .approvals: ApprovalsShot()
        case .analytics: AnalyticsShot()
        }
    }
}

// MARK: - Frame

private struct ShowcaseFrame<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Brand.textPrimary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Brand.textSecondary)
                }
                .padding(.horizontal, 4)

                content
            }
            .padding(20)
            .padding(.bottom, 40)
        }
    }
}

private struct ShowcaseCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                    .strokeBorder(Brand.border, lineWidth: 1)
            )
    }
}

// MARK: - Shots

private struct DoctorHomeShot: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good evening, Dr. Dunn")
                        .font(.headline)
                    Text("2 shifts this week · Orthopedics")
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Brand.accent)
            }

            HStack(spacing: 10) {
                metric("Tokens", "3", Brand.accent)
                metric("Assigned", "2", Brand.success)
                metric("Trades", "1", Brand.warning)
            }

            ShowcaseCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Upcoming").font(.subheadline.weight(.semibold))
                    shiftRow(day: "Fri", date: "Aug 28", place: "Average Hospital", rate: "$1,450", status: "Confirmed", tone: Brand.success)
                    shiftRow(day: "Sun", date: "Aug 30", place: "Riverside General", rate: "$1,650", status: "Confirmed", tone: Brand.success)
                    shiftRow(day: "Wed", date: "Sep 2", place: "Average Hospital", rate: "$1,450", status: "Trade pending", tone: Brand.warning)
                }
            }

            ShowcaseCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Availability").font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { d in
                            Text(d)
                                .font(.caption2.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    ["T", "F", "S"].contains(d) ? Brand.accent.opacity(0.25) : Brand.surfaceHigh,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .foregroundStyle(Brand.textPrimary)
                        }
                    }
                    Text("Green days are open for call.").font(.caption).foregroundStyle(Brand.textTertiary)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Brand.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct OpenShiftsShot: View {
    var body: some View {
        VStack(spacing: 12) {
            ShowcaseCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Orthopedics").font(.caption.weight(.semibold)).foregroundStyle(Brand.accent)
                        Spacer()
                        Text("Locked rate").font(.caption2.weight(.bold)).foregroundStyle(Brand.success)
                    }
                    Text("Average Hospital").font(.headline)
                    Text("Sat Sep 5 · 24h call").font(.subheadline).foregroundStyle(Brand.textSecondary)
                    HStack {
                        Text("$1,850 / day").font(.title3.weight(.bold)).foregroundStyle(Brand.textPrimary)
                        Spacer()
                        Text("Claim")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Brand.accent, in: Capsule())
                    }
                }
            }
            ShowcaseCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Emergency Medicine").font(.caption.weight(.semibold)).foregroundStyle(Brand.accent)
                        Spacer()
                        Text("Smart Algo").font(.caption2.weight(.bold)).foregroundStyle(Brand.warning)
                    }
                    Text("Riverside General").font(.headline)
                    Text("Mon Sep 7 · 24h call").font(.subheadline).foregroundStyle(Brand.textSecondary)
                    HStack {
                        Text("$1,620 / day").font(.title3.weight(.bold))
                        Spacer()
                        Text("Claim")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Brand.accent, in: Capsule())
                    }
                }
            }
            ShowcaseCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("St. Anne's Medical Center").font(.headline)
                    Text("Thu Sep 10 · Orthopedics").font(.subheadline).foregroundStyle(Brand.textSecondary)
                    HStack {
                        Text("$1,450 / day").font(.title3.weight(.bold))
                        Spacer()
                        Text("1 token")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
            }
        }
    }
}

private struct HospitalDashboardShot: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                dashStat("Fill rate", "94%", Brand.success)
                dashStat("Open", "3", Brand.warning)
                dashStat("Pending", "5", Brand.accent)
            }

            ShowcaseCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tonight").font(.subheadline.weight(.semibold))
                    coverageRow("Orthopedics", "Dr. Dunn", true)
                    coverageRow("Emergency", "Dr. Ellison", true)
                    coverageRow("Anesthesiology", "Unfilled", false)
                }
            }

            ShowcaseCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This week").font(.subheadline.weight(.semibold))
                    ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { d in
                        HStack {
                            Text(d).frame(width: 36, alignment: .leading).font(.caption.weight(.semibold))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(d == "Wed" || d == "Sat" ? Brand.warning.opacity(0.35) : Brand.success.opacity(0.35))
                                .frame(height: 10)
                            Text(d == "Wed" || d == "Sat" ? "1 open" : "Covered")
                                .font(.caption2)
                                .foregroundStyle(Brand.textTertiary)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func dashStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Brand.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func coverageRow(_ specialty: String, _ who: String, _ filled: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(specialty).font(.subheadline.weight(.semibold))
                Text(who).font(.caption).foregroundStyle(Brand.textSecondary)
            }
            Spacer()
            Text(filled ? "Filled" : "Needs cover")
                .font(.caption.weight(.bold))
                .foregroundStyle(filled ? Brand.success : Brand.warning)
        }
        .padding(.vertical, 4)
    }
}

private struct AlterRatesShot: View {
    var body: some View {
        VStack(spacing: 12) {
            ShowcaseCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Saturday · Orthopedics").font(.headline)
                    HStack {
                        Label("Smart Algo", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.accent)
                        Spacer()
                        Text("$1,450 → $1,850")
                            .font(.subheadline.weight(.bold))
                    }
                    ProgressView(value: 0.72)
                        .tint(Brand.accent)
                    Text("Escalating as the shift approaches. Floor locked at hospital policy.")
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            ShowcaseCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Monday · Emergency").font(.headline)
                    HStack {
                        Text("Locked rate").font(.caption.weight(.semibold)).foregroundStyle(Brand.success)
                        Spacer()
                        Text("$1,600 / day").font(.title3.weight(.bold))
                    }
                    Text("Hospital proprietary rate — no algo range, no ambiguity.")
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            ShowcaseCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apply to all Mondays").font(.subheadline.weight(.semibold))
                    Text("One tap pushes this rate pattern across the month.")
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)
                    Text("Apply Smart Algo to Mondays")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Brand.accent, in: RoundedRectangle(cornerRadius: Brand.buttonRadius, style: .continuous))
                }
            }
        }
    }
}

private struct ApprovalsShot: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                filterChip("Needs review", true)
                filterChip("Approved", false)
                filterChip("Waitlisted", false)
            }

            approvalCard(name: "Maya Ellison, MD", detail: "Emergency Medicine · NPI 1487290365", wait: "Waiting 2 days")
            approvalCard(name: "Carlos Rivera, DO", detail: "Orthopedics · NPI 1678934210", wait: "Applied today")
            approvalCard(name: "Riverside General", detail: "Hospital · NPI 1902847365", wait: "Waiting 1 day")
        }
    }

    private func filterChip(_ title: String, _ on: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(on ? Brand.accent : Brand.surfaceHigh, in: Capsule())
            .foregroundStyle(on ? Color.white : Brand.textSecondary)
    }

    private func approvalCard(name: String, detail: String, wait: String) -> some View {
        ShowcaseCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.subheadline.weight(.semibold))
                        Text(detail).font(.caption).foregroundStyle(Brand.textSecondary)
                    }
                    Spacer()
                    Text(wait)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Brand.warning)
                }
                HStack(spacing: 8) {
                    Text("Approve")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Brand.success, in: Capsule())
                    Text("Waitlist")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Brand.accentSoft, in: Capsule())
                        .foregroundStyle(Brand.accent)
                    Text("Reject")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.danger)
                }
            }
        }
    }
}

private struct AnalyticsShot: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                moneyTile("Saved this month", "$48,200", Brand.success)
                moneyTile("Per day avg", "$1,606", Brand.accent)
            }

            ShowcaseCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Where it came from").font(.subheadline.weight(.semibold))
                    moneyLine("Early fills vs escalation", "$31,400", Brand.success)
                    moneyLine("Late cancel penalties", "$9,800", Brand.warning)
                    moneyLine("Trade settlements", "$7,000", Brand.accent)
                    Text("Every dollar is an auditable event — same numbers on web admin.")
                        .font(.caption)
                        .foregroundStyle(Brand.textTertiary)
                        .padding(.top, 4)
                }
            }

            ShowcaseCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fill performance").font(.subheadline.weight(.semibold))
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach([0.55, 0.7, 0.82, 0.76, 0.91, 0.88, 0.94], id: \.self) { h in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Brand.accent.opacity(0.85))
                                .frame(height: 80 * h)
                        }
                    }
                    .frame(height: 90)
                    Text("Last 7 days · higher is healthier coverage")
                        .font(.caption2)
                        .foregroundStyle(Brand.textTertiary)
                }
            }
        }
    }

    private func moneyTile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(Brand.textTertiary)
            Text(value).font(.title2.weight(.bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func moneyLine(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Brand.textSecondary)
            Spacer()
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(color)
        }
    }
}

// Shared row helper
private func shiftRow(day: String, date: String, place: String, rate: String, status: String, tone: Color) -> some View {
    HStack(spacing: 12) {
        VStack(spacing: 2) {
            Text(day).font(.caption2.weight(.bold)).foregroundStyle(Brand.textTertiary)
            Text(date.suffix(2)).font(.headline)
        }
        .frame(width: 44)
        VStack(alignment: .leading, spacing: 2) {
            Text(place).font(.subheadline.weight(.semibold))
            Text(rate).font(.caption).foregroundStyle(Brand.textSecondary)
        }
        Spacer()
        Text(status)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tone)
    }
    .padding(.vertical, 4)
}
