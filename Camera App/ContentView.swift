//
//  ContentView.swift
//  Camera App
//
//  Created by Léo Frati on 30/05/2025.
//

import SwiftUI

struct ContentView: View {
    @State private var takePhoto = false
    @State private var presetValue: Double = 0.5
    
    var body: some View {
        ZStack {
            CameraView(takePhoto: $takePhoto, presetValue: $presetValue)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                Slider(value: $presetValue, in: 0...1)
                    .padding(.horizontal, 40)
                    .accentColor(.white)
                
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.prepare()
                    generator.impactOccurred()
                    takePhoto = true
                }) {
                    Circle()
                        .frame(width: 70, height: 70)
                        .padding(4)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
                .padding(.bottom, 40)
            }
        }
    }
}
