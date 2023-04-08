//
//  SettingsProvider.swift
//  TakeHome
//
//  Created by Gal Blank on 4/7/23.
//

import Foundation
import Vision

class SettingsProvider: MLFeatureProvider {
   var values = [
       "iouThreshold": MLFeatureValue(double: 0.6),
       "confidenceThreshold": MLFeatureValue(double: 0.9)
       ]

   var featureNames: Set<String> {
       return Set(values.keys)
   }
   func featureValue(for featureName: String) -> MLFeatureValue? {
       return values[featureName]
   }
}
