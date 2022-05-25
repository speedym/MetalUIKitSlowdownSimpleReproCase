//
//  AppDelegate.swift
//  Desync
//
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        guard
            let device = MTLCreateSystemDefaultDevice()
        else { preconditionFailure("Unable to setup Metal device") }
        
        guard
            let commandQueue = device.makeCommandQueue()
        else { preconditionFailure("Unable to setup Metal device 2") }
        
        guard
            let library = device.makeDefaultLibrary()
        else { preconditionFailure("Unable to setup Metal device 3") }
        
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = MetalKitViewController(device: device, commandQueue: commandQueue, library: library)
        window.makeKeyAndVisible()
        self.window = window
        
        return true
    }
}
