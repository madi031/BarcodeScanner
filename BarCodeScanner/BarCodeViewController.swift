//
//  BarCodeViewController.swift
//  ConnectPlus
//
//  Created by madi on 1/3/19.
//  Copyright © 2019 IBM. All rights reserved.
//

import AVFoundation
import UIKit

class BarCodeViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    
    @IBOutlet weak var scannerView: UIView!
    @IBOutlet weak var noCameraAccessView: UIView!
    @IBOutlet weak var searchTextView: UIView!
    
    private var scanner: Scanner?
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    // Barcode scanner should not rotate to landscape mode, so explicitly set autorotate to false and orientation to portrait
    override var shouldAutorotate: Bool {
        get {
            return false
        }
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        get {
            return UIInterfaceOrientationMask.portrait
        }
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        get {
            return UIInterfaceOrientation.portrait
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        var grantedAccess = true
        
        // Check user permission for camera usage
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // User already granted access to the camera, do nothing
            break
        case .notDetermined:
            // First time opening barcode scanner - User has neither granted nor denied camera permission yet, ask for permission
            // App has to wait for the user to select the permisssion before setting up the scanner, so suspend the session queue and call the scanner setup in session queue. This ensures setup is done only when session queue is resumed
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video) { (granted) in
                if !granted {
                    self.showNoCameraAccess()
                    return
                }
                self.sessionQueue.resume()
            }
        default:
            // User denied access to camera, show the page to enable to camera access
            grantedAccess = false
        }
        sessionQueue.async {
            self.setupScanner(grantedAccess: grantedAccess)
        }
        addObservers()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let scanner = self.scanner {
            scanner.requestCaptureSessionStopRunning()
            scanner.removeInputOutput()
            scanner.deactivateScanner()
        }
        removeObservers()
        
        // There is a strong reference cycle here and to force break the cycle scanner object has to be set to nil
        // Scanner holds a strong ref to view, view holds strong ref to view controller and view controller holds strong ref to scanner
        scanner = nil
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        searchTextView.layer.cornerRadius = 10
    }
    
    // MARK: - Camera preview layer setup
    // Setup the camera preview layer to scan the barcode
    func setupScanner(grantedAccess: Bool) {
        if !grantedAccess {
            showNoCameraAccess()
            return
        } else {
            hideNoCameraAccess()
        }
        
        DispatchQueue.main.async {
            // Setup video preview layer to scan barcode
            self.scanner = Scanner(withViewController: self, view: self.scannerView) { code in
                self.searchTextView.isHidden = false
                self.scannerView.bringSubviewToFront(self.searchTextView)
                
                self.displayBarCodeString(code: code)
                // End of code block
            }
            
            // Camera preview layer setup is complete. Start the capture session to scan the barcode
            if let scanner = self.scanner {
                scanner.requestCaptureSessionStartRunning()
                scanner.activateScanner()
            }
        }
    }
    
    func displayBarCodeString(code: String) {
        // TODO: Add the messages to the bundle and ask MBE people to add it in MBE bundle as well
        let title = "Barcode Scanned!!"
        let message = code
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Scan Again!", style: .cancel, handler: { (action) in
            self.searchTextView.isHidden = true
            if let scanner = self.scanner {
                scanner.requestCaptureSessionStartRunning()
            }
        }))
        
        self.present(alert, animated: true, completion: nil)
    }
    
    // Informs the delegate that the capture output object emitted new metadata objects
    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        self.scanner?.scannerDelegate(output, didOutput: metadataObjects, from: connection)
    }
    
    // This opens the app settings for user to change the camera permissions
    @IBAction func enableCameraAccess(_ sender: UIButton) {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            print("*** App Settings URL not present")
            return
        }
        
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl) { (success) in
                print("*** App Settings opened successfully")
            }
        } else {
            print("*** App settings cannot be opened")
        }
    }
}

extension BarCodeViewController {
    private func hideNoCameraAccess() {
        DispatchQueue.main.async {
            self.noCameraAccessView.isHidden = true
            self.scannerView.isHidden = false
        }
    }
    
    // Inform the user to grant camera permission to scan the barcode
    private func showNoCameraAccess() {
        DispatchQueue.main.async {
            self.noCameraAccessView.isHidden = false
            self.scannerView.isHidden = true
        }
    }
    
    // blur the camera preview layer, show when camera is interrupted
    private func showBlurEffect() {
        if let scanner = scanner {
            scanner.showBlurEffect()
        }
    }
    
    // remove the blur effect when interruption is over
    private func hideBlurEffect() {
        if let scanner = scanner {
            scanner.hideBlurEffect()
        }
    }
}

extension BarCodeViewController {
    // MARK: - Observers
    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(appBecomeInactive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    @objc
    func appBecomeInactive() {
        print("*** App went background")
        showBlurEffect()
    }
    
    @objc
    func appBecomeActive() {
        print("*** App became active")
        hideBlurEffect()
    }
}
