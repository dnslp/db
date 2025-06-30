//
//  ParametricEQVisualizerView.swift
//  DecibelMeter
//
//  Created by Jules on 7/26/24.
//

import SwiftUI

struct ParametricEQVisualizerView: View {
    let data: [Float]
    let lineColor: Color
    let fillColor: Color
    let opacity: Double
    let lineWidth: CGFloat
    let backgroundColor: Color

    var body: some View {
        GeometryReader { geometry in
            if data.isEmpty {
                Text("No data available")
                    .foregroundColor(lineColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(backgroundColor)
            } else {
                ZStack {
                    backgroundColor.edgesIgnoringSafeArea(.all)

                    Path { path in
                        let width = geometry.size.width
                        let height = geometry.size.height
                        let stepX = width / CGFloat(data.count - 1)
                        let dataMax = data.max() ?? 1.0
                        let normalizedData = data.map { $0 / dataMax }

                        path.move(to: CGPoint(x: 0, y: height * CGFloat(1.0 - normalizedData[0])))

                        for i in 1..<normalizedData.count {
                            let x = CGFloat(i) * stepX
                            let y = height * CGFloat(1.0 - normalizedData[i])
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    .stroke(lineColor.opacity(opacity), lineWidth: lineWidth)
                    .background(fillColor.opacity(opacity * 0.3)) // Optional: fill under the line
                    .animation(.linear(duration: 0.1), value: data) // Smooth animation for data changes
                }
            }
        }
    }
}

struct ParametricEQVisualizerView_Previews: PreviewProvider {
    static var previews: some View {
        // Sample data for preview
        let sampleData: [Float] = (0..<60).map { _ in Float.random(in: 0.1...1.0) }

        VStack {
            Text("Customizable Parametric EQ Visualizer")
                .font(.headline)
                .padding(.bottom)

            ParametricEQVisualizerView(
                data: sampleData,
                lineColor: .blue,
                fillColor: .cyan,
                opacity: 0.8,
                lineWidth: 2,
                backgroundColor: .black
            )
            .frame(height: 200)
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)

            Text("Empty Data State")
                .font(.headline)
                .padding(.top)

            ParametricEQVisualizerView(
                data: [],
                lineColor: .red,
                fillColor: .orange,
                opacity: 1.0,
                lineWidth: 3,
                backgroundColor: Color(white: 0.1)
            )
            .frame(height: 100)
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
        }
        .padding()
    }
}
