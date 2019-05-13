//
//  Scanner.swift
//  ConnectPlus
//
//  Created by madi on 1/3/19.
//  Copyright © 2019 IBM. All rights reserved.
//

import AVFoundation
import UIKit

class Scanner {
    private var scannerView: UIView
    private var captureSession: AVCaptureSession?
    private var codeOutputHandler: (_ code: String) -> Void
    
    private var sessionQueue = DispatchQueue(label: "Session Queue", qos: DispatchQoS.userInteractive)
    
    private let scannerHelptextLabel = CATextLayer()
    private let scannerBoundary = CAShapeLayer()
    private let maskLayer = CAShapeLayer()
    
    private var isAppInBackground = false
    private var registeredObservers = false
    private let scannerHelpText = "Position the barcode within the \n square and it will be scanned \n automatically."
    
    // MARK: - Create capture session
    private func createCaptureSession(withViewController viewController: UIViewController?) -> AVCaptureSession? {
        let captureSession = AVCaptureSession()
        
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            print("***Capture device setup failed")
            return nil
        }
        
        // Creating and adding inputs and outputs to the capture session
        do {
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
            let metaDataOutput = AVCaptureMetadataOutput()
            
            if captureSession.canAddInput(deviceInput) {
                captureSession.addInput(deviceInput)
            } else {
                print("***Capture device add input failed")
                return nil
            }
            
            // Output gets the data from the barcode scanned
            if captureSession.canAddOutput(metaDataOutput) {
                captureSession.addOutput(metaDataOutput)
                
                // Cast the view controller to AVCaptureMetadataOutputObjectsDelegate and use the delegate method (scannerDelegate) to process the info
                if let viewController = viewController as? AVCaptureMetadataOutputObjectsDelegate {
                    metaDataOutput.setMetadataObjectsDelegate(viewController, queue: DispatchQueue.main)
                    metaDataOutput.metadataObjectTypes = self.metaObjectTypes()
                }
            } else {
                print("***Capture device add output failed")
                return nil
            }
        } catch {
            print("***Capture device input setup failed")
            return nil
        }
        
        return captureSession
    }
    
    // Support code types to scan
    private func metaObjectTypes() -> [AVMetadataObject.ObjectType] {
        return [
            .qr,
            .code128,
            .code39,
            .code39Mod43,
            .code93,
            .ean13,
            .ean8,
            .interleaved2of5,
            .itf14,
            .pdf417,
            .upce
        ]
    }
    
    // MARK: - Preview layer
    // This layer shows the video stream from the camera
    private func createPreviewLayer(withCaptureSession captureSession: AVCaptureSession, view: UIView) -> AVCaptureVideoPreviewLayer {
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.session = captureSession
        
        return previewLayer
    }
    
    // This layer shows the yellow rectangle area where barcode should be placed
    private func drawScanner() -> CAShapeLayer {
        let height = scannerView.frame.height
        let width = scannerView.frame.width
        
        // path of yellow rectangle
        let scannerPath = UIBezierPath(rect: CGRect(x: 0.15 * width, y: 0.25 * height, width: 0.70 * width, height: 0.5 * height))
        // path of the camera preview layer
        let outerPath = UIBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height))
        
        outerPath.append(scannerPath)
        outerPath.usesEvenOddFillRule = true
        
        scannerBoundary.path = outerPath.cgPath
        scannerBoundary.fillRule = CAShapeLayerFillRule.evenOdd
        scannerBoundary.fillColor = UIColor.black.cgColor
        scannerBoundary.opacity = 0.7
        scannerBoundary.strokeColor = UIColor.yellow.cgColor
        // Set the stroke start to draw border for barcode scanner coverage
        scannerBoundary.strokeStart = 0.6335
        scannerBoundary.strokeEnd = 1.0
        scannerBoundary.lineWidth = 4
        
        return scannerBoundary
    }
    
    // This layer adds the help text to be displayed on top of camera preview layer
    private func drawScannerHelpText() -> CATextLayer {
        let height = scannerView.frame.height
        let width = scannerView.frame.width
        
        scannerHelptextLabel.frame = CGRect(x: 0, y: height - 100, width: width, height: 60)
        scannerHelptextLabel.string = scannerHelpText
        scannerHelptextLabel.foregroundColor = UIColor.white.cgColor
        // Font has to be explicitly set to text layer
        scannerHelptextLabel.fontSize = 17.0
        scannerHelptextLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        scannerHelptextLabel.alignmentMode = .center
        // Text layer has to use the same scale as the screen, else the text becomes blurry
        scannerHelptextLabel.contentsScale = UIScreen.main.scale
        
        return scannerHelptextLabel
    }
    
    // MARK: - init
    // viewController passed here must conform to AVCaptureMetadataOutputObjectsDelegate
    // view is used to set the bounds of camera preview layer
    // codeOutputHandler is used to pass the value of barcode back to the calling function
    init(withViewController viewController: UIViewController, view: UIView, codeOutputHandler: @escaping (String) -> Void) {
        weak var weakViewController = viewController
        self.codeOutputHandler = codeOutputHandler
        self.scannerView = view
        
        if let captureSession = self.createCaptureSession(withViewController: weakViewController) {
            self.captureSession = captureSession
            let previewLayer = self.createPreviewLayer(withCaptureSession: captureSession, view: view)
            view.layer.addSublayer(previewLayer)
            view.layer.addSublayer(drawScanner())
            view.layer.addSublayer(drawScannerHelpText())
            
            activateScanner()
        }
    }
    
    deinit {
        deactivateScanner()
    }
    
    // MARK: - Capture Session
    // Start the capture session
    func requestCaptureSessionStartRunning() {
        // Starting the capture session is a time consuming process and it is synchronous, so it blocks the receiver until started. Run this step in a seperate thread other than main thread
        sessionQueue.async {
            guard let captureSession = self.captureSession else {
                return
            }
            
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
        }
    }
    
    // Stop the captuer session
    func requestCaptureSessionStopRunning() {
        // Stopping the capture session is a time consuming process and it is synchronous, so it blocks the receiver until stopped. Run this step in a seperate thread other than main thread
        sessionQueue.async {
            guard let captureSession = self.captureSession else {
                return
            }
            
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }
    
    // Release capture session by removing all its inputs and outputs. Call this method when the view disappears.
    func removeInputOutput() {
        if let captureSession = captureSession {
            for input in captureSession.inputs {
                captureSession.removeInput(input)
            }
            
            for output in captureSession.outputs {
                captureSession.removeOutput(output)
            }
        }
    }
    
    // MARK: - Delegate
    // This delegate method helps us to get the metadata from the video stream which we use to get the data from the barcode scanned
    func scannerDelegate(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // process the barcode only if app is in foreground
        if !isAppInBackground {
            // Stop the capture session as barcode is scanned and this prevents from scanning the same barcode multiple times
            self.requestCaptureSessionStopRunning()
            
            // Get the readable object from the metadataObjects and get the string value of that readable object
            if let metadataObject = metadataObjects.first {
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else {
                    return
                }
                
                guard let stringValue = readableObject.stringValue else {
                    return
                }
                
                self.codeOutputHandler(stringValue)
            }
        }
    }
}

extension Scanner {
    // MARK: - Blur Effects
    // Blur the camera preview layer and pause the preview
    func showBlurEffect() {
        let blurEffect = UIBlurEffect(style: .regular)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = scannerView.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scannerView.addSubview(blurView)
        
        // pause the camera whenever app goes to background
        for layer in scannerView.layer.sublayers! {
            if let layer = layer as? AVCaptureVideoPreviewLayer {
                layer.connection?.isEnabled = false
            }
        }
        
        // stoping the camera and starting it is a time consuming process, so pause the camera and use this var to decide whether we should scan the code or not
        isAppInBackground = true
    }
    
    // Remove the blur from camera preview layer and resume the preview
    func hideBlurEffect() {
        for subview in scannerView.subviews {
            if subview is UIVisualEffectView {
                subview.removeFromSuperview()
            }
        }
        
        // resume the camera whenever app comes to foreground
        for layer in scannerView.layer.sublayers! {
            if let layer = layer as? AVCaptureVideoPreviewLayer {
                layer.connection?.isEnabled = true
            }
        }
        
        isAppInBackground = false
    }
    
    func activateScanner() {
        if !registeredObservers {
            // Register observers
            addObservers()
            registeredObservers = true
        }
    }
    
    func deactivateScanner() {
        if registeredObservers {
            // Unregister observers
            removeObservers()
            registeredObservers = false
        }
    }
}

extension Scanner {
    // MARK: - Observers
    private func addObservers() {
        // handles interruption like phone call, etc
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterupted), name: .AVCaptureSessionWasInterrupted, object: captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnd), name: .AVCaptureSessionInterruptionEnded, object: captureSession)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: captureSession)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionWasInterrupted, object: captureSession)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionInterruptionEnded, object: captureSession)
        NotificationCenter.default.removeObserver(self, name: .AVCaptureSessionRuntimeError, object: captureSession)
    }
    
    @objc
    func sessionInterupted(notification: Notification) {
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?, let reason = AVCaptureSession.InterruptionReason(rawValue: userInfoValue.integerValue) {
            print("Capture session was interrupted with reason: \(reason)")
        }
        showBlurEffect()
    }
    
    @objc
    func sessionInterruptionEnd(notification: Notification) {
        print("Capture session interrupt ended")
        hideBlurEffect()
    }
    
    @objc
    func sessionRuntimeError(notification: Notification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else {
            return
        }
        
        print("Capture session runtime error with: \(error)")
        if error.code == .mediaServicesWereReset {
            // restart capture session if OS resets media server
            requestCaptureSessionStartRunning()
        }
    }
}
