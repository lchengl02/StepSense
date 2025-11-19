//
//  PressureOverlay.swift
//  GazeDetection
//
//  Created by clli02 on 11/3/25.
//

import SwiftUI
import Combine


final class PressureOverlayViewModel: ObservableObject {
    @Published var leftOpacity: CGFloat = 0.35
    @Published var rightOpacity: CGFloat = 0.35
}

struct PressureOverlay: View {
    @ObservedObject var vm: BLEPressureManager

    var diameterFraction: CGFloat = 0.16
    var horizontalInset: CGFloat = 24
    var color: Color = .white

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let diameter = max(w * diameterFraction, 36)

            ZStack {
                Circle()
                    .fill(color.opacity(vm.leftOpacity))
                    .frame(width: diameter, height: diameter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, horizontalInset)
                    .padding(.vertical, max(0, (h - diameter) / 2))

                Circle()
                    .fill(color.opacity(vm.rightOpacity))
                    .frame(width: diameter, height: diameter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, horizontalInset)
                    .padding(.vertical, max(0, (h - diameter) / 2))
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}
