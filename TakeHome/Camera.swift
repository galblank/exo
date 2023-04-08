//
//  Camera.swift
//  TakeHome
//
//  Created by Arthur Alaniz on 10/28/22.
//

import AVFoundation
import VideoToolbox
import Vision
import UIKit
import SwiftUI
import Accelerate

class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, ObservableObject {

    static let shared = Camera()
    // technically we can read those from thresholds.values
    var confidenceValue: Double = 0.7
    var iouThreshold: Double = 0.6
    var thresholds = SettingsProvider()
    let capture_session = AVCaptureSession()
    let capture_queue = DispatchQueue(label: "camera_capture")
    @Published var image: CGImage? = nil
    @Published var debug_string: String = "camera init"
    // this will publish boxes to SwiftUI view
    @Published var detectionLayer = CALayer()
    var requests = [VNRequest]()
    var screenRect: CGRect = UIScreen.main.bounds
    var visionModel: VNCoreMLModel!
    var predictionModel: MLModel!
    var model: YOLOv3TinyFP16!

    private override init() {
        super.init()
        detectionLayer.frame = CGRect(x: 0, y: 0, width: screenRect.size.width, height: screenRect.size.height)
        Task {
            do {
                try await get_authorized()
                try setup_input()
                try setup_output()
                setupDetector()
                capture_queue.async { [weak self] in
                    guard let sSelf = self else { return }
                    sSelf.capture_session.startRunning()
                }
            } catch {
                print("camera init failed: \(error)")
            }
        }
    }

    func get_authorized() async throws {
        let authorized = await withCheckedContinuation({ continuation in
            if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
                AVCaptureDevice.requestAccess(for: .video) { authorized in
                    continuation.resume(returning: authorized)
                }
            } else {
                continuation.resume(returning: true)
            }
        })
        if !authorized {
            throw "camera not authorized"
        }
    }

    func setup_input() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw "no back camera"
        }
        let capture_input = try AVCaptureDeviceInput(device: device)
        capture_session.addInput(capture_input)
    }

    func setup_output() throws {
        let capture_ouptut = AVCaptureVideoDataOutput()
        capture_ouptut.setSampleBufferDelegate(self, queue: capture_queue)
        capture_ouptut.videoSettings = [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA
        ]
        capture_session.addOutput(capture_ouptut)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let image_buffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        if let scaledBuffer = scale(sampleBuffer) {
            benchMarkInference(for: scaledBuffer)
        }

        var cg_image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(image_buffer, options: nil, imageOut: &cg_image)
        DispatchQueue.main.async {
            self.image = cg_image
        }

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: image_buffer, orientation: .up, options: [:])
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }

    private func scale(_ sampleBuffer: CMSampleBuffer) -> CVPixelBuffer?
        {
            guard let imgBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return nil
            }
            CVPixelBufferLockBaseAddress(imgBuffer, CVPixelBufferLockFlags(rawValue: 0))
            // create vImage_Buffer out of CVImageBuffer
            var inBuff: vImage_Buffer = vImage_Buffer()
            inBuff.width = UInt(CVPixelBufferGetWidth(imgBuffer))
            inBuff.height = UInt(CVPixelBufferGetHeight(imgBuffer))
            inBuff.rowBytes = CVPixelBufferGetBytesPerRow(imgBuffer)
            inBuff.data = CVPixelBufferGetBaseAddress(imgBuffer)

            var scaleBuffer: vImage_Buffer = vImage_Buffer()
            scaleBuffer.data = UnsafeMutableRawPointer.allocate(byteCount: Int(416 * 416 * 4), alignment: MemoryLayout<UInt>.size)
                    scaleBuffer.width = vImagePixelCount(416)
                    scaleBuffer.height = vImagePixelCount(416)
                    scaleBuffer.rowBytes = Int(416 * 4)
            // perform scale
            var err = vImageScale_ARGB8888(&inBuff, &scaleBuffer, nil, 0)
            if err != kvImageNoError {
                print("Can't scale a buffer")
                return nil
            }
            CVPixelBufferUnlockBaseAddress(imgBuffer, CVPixelBufferLockFlags(rawValue: 0))

            var newBuffer: CVPixelBuffer?
            let attributes : [NSObject:AnyObject] = [
                kCVPixelBufferCGImageCompatibilityKey : true as AnyObject,
                kCVPixelBufferCGBitmapContextCompatibilityKey : true as AnyObject
            ]

            let status = CVPixelBufferCreateWithBytes(kCFAllocatorDefault,
                                                      Int(scaleBuffer.width), Int(scaleBuffer.height),
                                                      kCVPixelFormatType_32BGRA, scaleBuffer.data,
                                                      Int(scaleBuffer.width) * 4,
                                                      nil, nil,
                                                      attributes as CFDictionary?, &newBuffer)
            return newBuffer
        }

    func benchMarkInference(for image_buffer: CVPixelBuffer) {
        DispatchQueue(label: "benchmark").async { [weak self] in
            guard let sSelf = self else { return }
            do {
                let startTimeCM = CACurrentMediaTime()
                let input = YOLOv3TinyFP16Input(image: image_buffer,iouThreshold: sSelf.iouThreshold, confidenceThreshold: sSelf.confidenceValue)
                guard let _ = try? sSelf.model.prediction(input: input) else {
                    fatalError("Unexpected runtime error.")
                }
                let endTimeCM = CACurrentMediaTime()
                let intervalCM = 1000.0*(endTimeCM - startTimeCM)
                print("inference time: \(intervalCM)")
            }
        }
    }

    func updateThresholds(iou: Double, confidence: Double) {
        iouThreshold = iou / 100.0
        confidenceValue = confidence / 100.0
        thresholds.values = [
            "iouThreshold": MLFeatureValue(double: iouThreshold),
            "confidenceThreshold": MLFeatureValue(double: confidenceValue)
            ]
    }

    func setupDetector() {
        guard let modelURL = Bundle.main.url(forResource: "YOLOv3TinyFP16", withExtension: "mlmodelc") else {
            self.debug_string = "failed to init YOLO model"
            return
        }
        do {
            predictionModel = try MLModel(contentsOf: modelURL)
            model = YOLOv3TinyFP16(model: predictionModel)
            visionModel = try VNCoreMLModel(for: predictionModel)
            let objectRecognition = VNCoreMLRequest(model: visionModel,
                                                    completionHandler: detectionComplete)
            objectRecognition.imageCropAndScaleOption = .scaleFill
            self.requests = [objectRecognition]
        } catch let error {
            print(error)
        }
    }

    func detectionComplete(request: VNRequest, error: Error?) {
        if let results = request.results {
            visionModel.featureProvider = thresholds
            DispatchQueue.main.async { [weak self] in
                self?.extractDetections(results)
            }
        }
    }

    func extractDetections(_ results: [VNObservation]) {
        detectionLayer.sublayers = nil // Remove all previous detections
        let color = CGColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 0.4)
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation, let label = objectObservation.labels.first else {  continue }

            //print("Detected '\(label.identifier)' confidence '\(label.confidence)'")
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(screenRect.size.width), Int(screenRect.size.height))
            let transformedBounds = CGRect(x: objectBounds.minX, y: screenRect.size.height - objectBounds.maxY, width: objectBounds.maxX - objectBounds.minX, height: objectBounds.maxY - objectBounds.minY)
            let layer = createRectLayerWithBounds(transformedBounds, color: color)
            let textLayer = createTextLayerWithBounds(layer.bounds, label: label)
            layer.addSublayer(textLayer)
            detectionLayer.addSublayer(layer)
        }
    }

    func createRectLayerWithBounds(_ bounds: CGRect, color:CGColor) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.borderWidth = 4.0
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.borderColor = CGColor.init(red: 7.0, green: 8.0, blue: 7.0, alpha: 1.0)
        shapeLayer.cornerRadius = 5
        shapeLayer.backgroundColor = CGColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 0.4)
        return shapeLayer
    }

    func createTextLayerWithBounds(_ bounds: CGRect,
                                   label: VNClassificationObservation) -> CATextLayer {
        var string = "\(label.identifier)\nConfidence: \(Int(label.confidence * 100))%"
        if label.timeRange != .zero {
            print("Timeframe \(label.timeRange.duration.value)")
            string += "\n\(label.timeRange.duration)"
        }
        let textLayer = CATextLayer()
        textLayer.string = string
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.width - 10, height: bounds.size.height - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.shadowOpacity = 0.7
        textLayer.fontSize = 16
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 1.0, 1.0])
        textLayer.contentsScale = 2.0 // 2.0 for retina display
        return textLayer
    }
}
