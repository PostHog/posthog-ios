//
//  SegmentedControl.swift
//  PostHog
//
//  Created by Ioannis Josephides on 11/03/2025.
//

#if os(iOS)
    import SwiftUI

    struct SegmentedControl<Indicator: View, Segment: View, Separator: View>: View {
        var range: ClosedRange<Int>
        var height: CGFloat = 45

        @Binding var selectedValue: Int?
        @ViewBuilder var segmentView: (_ value: Int, _ selected: Bool) -> Segment
        @ViewBuilder var separatorView: (_ value: Int, _ selected: Bool) -> Separator
        @ViewBuilder var indicatorView: (CGSize) -> Indicator

        @State private var minX: CGFloat = .zero

        var body: some View {
            GeometryReader {
                let size = $0.size
                let containerWidthForEachTab = size.width / CGFloat(range.count)

                HStack(spacing: 0) {
                    ForEach(range, id: \.self) { value in
                        let isSelected = selectedValue == value
                        Button {
                            if selectedValue == value {
                                withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                                    selectedValue = nil
                                }

                            } else {
                                let index = value - range.lowerBound
                                if selectedValue == nil {
                                    minX = containerWidthForEachTab * CGFloat(index)
                                    withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                                        selectedValue = value
                                    }
                                } else {
                                    selectedValue = selectedValue == value ? nil : value
                                    withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                                        minX = containerWidthForEachTab * CGFloat(index)
                                    }
                                }
                            }

                        } label: {
                            segmentView(value, isSelected)
                                .contentShape(.rect)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.borderless)
                        .animation(.snappy, value: selectedValue)
                        .background(
                            Group {
                                if value == range.lowerBound, selectedValue != nil {
                                    GeometryReader {
                                        let size = $0.size
                                        indicatorView(size)
                                            .frame(width: size.width, height: size.height, alignment: .leading)
                                            .offset(x: minX)
                                    }
                                }
                            },
                            alignment: .leading
                        )
                        .overlay(
                            separatorView(value, isSelected)
                        )
                    }
                }
                .preference(key: SizeKey.self, value: size)
                .onPreferenceChange(SizeKey.self) { _ in
                    if let selectedValue {
                        let index = selectedValue - range.lowerBound
                        minX = containerWidthForEachTab * CGFloat(index)
                    }
                }
            }
            .frame(height: height)
        }
    }

    extension SegmentedControl where Indicator == EmptyView, Separator == EmptyView {
        init(range: ClosedRange<Int>, height: CGFloat, selectedValue: Binding<Int?>, segmentView: @escaping (Int, Bool) -> Segment) {
            self.range = range
            self.height = height
            _selectedValue = selectedValue
            self.segmentView = segmentView
            separatorView = { _, _ in EmptyView() }
            indicatorView = { _ in EmptyView() }
        }
    }

    private struct SizeKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            value = nextValue()
        }
    }

    struct EdgeBorder: Shape {
        var lineWidth: CGFloat
        var edges: [Edge]

        func path(in rect: CGRect) -> Path {
            edges.map { edge -> Path in
                switch edge {
                case .top: return Path(.init(x: rect.minX, y: rect.minY, width: rect.width, height: lineWidth))
                case .bottom: return Path(.init(x: rect.minX, y: rect.maxY - lineWidth, width: rect.width, height: lineWidth))
                case .leading: return Path(.init(x: rect.minX, y: rect.minY, width: lineWidth, height: rect.height))
                case .trailing: return Path(.init(x: rect.maxX - lineWidth, y: rect.minY, width: lineWidth, height: rect.height))
                }
            }.reduce(into: Path()) { $0.addPath($1) }
        }
    }
#endif
