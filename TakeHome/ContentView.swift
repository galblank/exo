//
//  ContentView.swift
//  TakeHome
//
//  Created by Arthur Alaniz on 10/28/22.
//

import SwiftUI

struct DrawingView: UIViewRepresentable {

    private let view = UIView(frame: UIScreen.main.bounds)

    let detectionLayer: CALayer?

    var addedLayer = false

    func makeUIView(context: Context) -> UIView {
        if let layer = detectionLayer {
            view.layer.addSublayer(layer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {

    }
}

struct ContentView: View {
    @ObservedObject var camera = Camera.shared

    private let label = Text("camera image")

    @State var loadSettings = false

    var body: some View {
        if let image = camera.image {
            ZStack {
                Image(image, scale: 1.0, orientation: .up, label: label)
                    .resizable()
                    .scaledToFill()
                DrawingView(detectionLayer: camera.detectionLayer)
                    .border(.white, width: 4)
                    .cornerRadius(15.0)
                    .zIndex(1)
                HStack {
                    Spacer()
                    Button {
                        loadSettings.toggle()
                    } label: {
                        Image("ico_settings")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 50)
                    }
                    .padding()
                    .sheet(isPresented: $loadSettings) {
                        SettingsView()
                            .zIndex(5)
                    }
                }
                .zIndex(3)
            }
        } else {
            Text(camera.debug_string)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
