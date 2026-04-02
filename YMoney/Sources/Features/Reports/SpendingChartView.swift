import SwiftUI
import Charts

/// Spending by category pie/bar chart
struct SpendingChartView: View {
    let data: [ReportsViewModel.CategorySpending]

    var body: some View {
        if #available(iOS 17.0, *) {
            Chart(data) { item in
                SectorMark(
                    angle: .value("Amount", item.amount),
                    innerRadius: .ratio(0.6),
                    angularInset: 1
                )
                .foregroundStyle(chartColor(item.color))
                .cornerRadius(4)
            }
            .frame(height: 200)
        } else {
            // Fallback bar chart for older iOS
            barChart
        }
    }

    private var barChart: some View {
        VStack(spacing: 4) {
            let maxAmount = data.map(\.amount).max() ?? 1
            ForEach(data.prefix(10)) { item in
                HStack {
                    Text(item.name)
                        .font(.caption)
                        .frame(width: 100, alignment: .trailing)
                        .lineLimit(1)

                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(chartColor(item.color))
                            .frame(width: geo.size.width * (item.amount / maxAmount))
                    }
                    .frame(height: 16)

                    Text(CurrencyFormatter.format(item.amount))
                        .font(.caption2.monospacedDigit())
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    private func chartColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .red, .purple, .teal, .pink, .yellow, .indigo, .brown, .mint, .cyan, .gray, .black, .white]
        return colors[index % colors.count]
    }
}
