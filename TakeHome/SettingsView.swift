//
//  SettingsView.swift
//  TakeHome
//
//  Created by Gal Blank on 4/7/23.
//

import SwiftUI
import Vision

struct SettingsView: View {
    @State var iosThreshold = 0.3
    @State var confidenceThreshold = 0.6
    @Environment(\.presentationMode) var presentationMode
    var body: some View {
            VStack {
                HStack {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.title2)
                            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                            .lineLimit(1)
                            .foregroundColor(.white)
                            .background(.blue)
                            .cornerRadius(15.0)
                    }
                    .padding()
                    Spacer()
                    Button {
                        Camera.shared.updateThresholds(iou: iosThreshold,
                                                       confidence: confidenceThreshold)
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Text("Set")
                            .font(.title2)
                            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                            .lineLimit(1)
                            .foregroundColor(.white)
                            .background(.blue)
                            .cornerRadius(15.0)
                    }
                    .padding()
                }
                Slider(
                    value: $confidenceThreshold,
                    in: 0...100,
                    step: 5
                ) {

                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("100")
                }
                Text("Confidence level: \(Int(confidenceThreshold))%")
                    .foregroundColor(.blue)
                    .font(.headline)

                Slider(
                    value: $iosThreshold,
                    in: 0...100,
                    step: 5
                ) {

                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("100")
                }
                Text("IoU level: \(Int(iosThreshold))%")
                    .foregroundColor(.blue)
                    .font(.headline)
            }
        .padding()
        .background(Color.white)
        .onAppear {
            iosThreshold = Camera.shared.iouThreshold * 100
            confidenceThreshold = Camera.shared.confidenceValue * 100
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
