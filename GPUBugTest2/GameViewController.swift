//
//  ViewController.swift
//
// This project simulates an issue when trying to use Metal in conjuction
// with UIKit. Specifically, it highlights a likely bug in Apple's driver / internal
// implementation of GPU throttling and waiting for the next drawable on iOS.

// On:
// iPhone 11 Pro - 15.4.1
// When we run this project at forced maximum GPU performance state through XCode, the
// frame rate is 60 FPS and GPU total frame time is 8.5ms. When we run the project normally
// (without any forced states) the total CPU frame time jumps to 25ms, GPU frame time jumps
// to 19ms, and frame rate drops to steady 40 FPS. In that case, we can observe long CPU main
// thread blocked waiting for next drawable times in Instruments, and on the GPU side
// we observe GPU not being busy all of the time (likely due to GPU/CPU bubbles).

// On:
// iPhone 12 Pro - 14.8.1
// iPhone 12 mini - 15.4
// iPhone 10 - 15.4.1
// You can observe 40 FPS (25ms CPU, ~20ms GPU per frame time) in the first 3-4 seconds after
// project startup, then it recovers to 60 FPS.

import UIKit
import MetalKit

// Switching this flag to true enables .presentsWithTransaction, workarounds this
// bug and restores frames per second from 40 FPS -> 60 FPS
let presentWithTransactionWorkaround = false

final class MetalKitViewController: UIViewController {
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    lazy private var metalKitView = MTKView(frame: .zero, device: device)
    
    var pipelineState: MTLRenderPipelineState?
    var vertexBuffer: MTLBuffer?
    
    let vertices: [Vertex] = [
        Vertex(position: float3(x: -1, y: 1, z: 0), color: float4(1,0,0,1)),
        Vertex(position: float3(x: 1, y: 1, z: 0), color: float4(1,1,0,1)),
        Vertex(position: float3(x: -1, y: -1, z: 0), color: float4(0,1,0,1)),
        Vertex(position: float3(x: 1, y: -1, z: 0), color: float4(0,1,1,1))
    ]
    
    private let lowPassFactor = Double(0.1)
    private var waitTimeAverage = Double(0)
    
    // MARK: - Initialiser
    
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    init(device: MTLDevice, commandQueue: MTLCommandQueue, library: MTLLibrary) {
        
        self.device = device
        self.commandQueue = commandQueue
        self.library = library
        
        super.init(nibName: nil, bundle: nil)
        
        buildModel(device: device)
        buildPipelineState(device: device, library: library)
    }
    
    // MARK: - Configuration hooks
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return [.portrait, .portraitUpsideDown]
    }
}

// MARK: - Render pipeline intialisation
extension MetalKitViewController {
    
    private func buildPipelineState(device: MTLDevice, library: MTLLibrary) {
        
        let vertexFunction = library.makeFunction(name: Vertex.functionName)
        let fragmentFunction = library.makeFunction(name: "fragment_color_shader")
        
        let desc = MTLRenderPipelineDescriptor()
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.vertexDescriptor = Vertex.vertexDescriptor
        desc.vertexFunction = vertexFunction
        desc.fragmentFunction = fragmentFunction
        
        self.pipelineState = try? device.makeRenderPipelineState(descriptor: desc)
    }
    
    private func buildModel(device: MTLDevice) {
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Vertex>.stride, options: [.cpuCacheModeWriteCombined])
    }
}

// MARK: - View lifecycle
extension MetalKitViewController {
    
    override func loadView() {
        
        let containerView = UIView(frame: .zero)
        
        metalKitView.frame = containerView.bounds
        metalKitView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalKitView.delegate = self
        metalKitView.clearColor =  MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalKitView.presentsWithTransaction = presentWithTransactionWorkaround
        
        containerView.addSubview(metalKitView)
        
        self.view = metalKitView
    }
}

// MARK: - MTKViewDelegate conformance / main render loop
extension MetalKitViewController: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let pipelineState = pipelineState,
            let descriptor = view.currentRenderPassDescriptor, // here's where we wait on the next drawable
            let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
            else { return }
        
        commandEncoder.setRenderPipelineState(pipelineState)
        commandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
        commandEncoder.endEncoding()
        if (!presentWithTransactionWorkaround) {
            let mtl_drawable = self.metalKitView.currentDrawable
            commandBuffer.addScheduledHandler { cb in
                mtl_drawable?.present()
            }
        }
        commandBuffer.commit()

        if (presentWithTransactionWorkaround) {
            // Wait until current buffer scheduled, connected to presentsWithTransaction
            commandBuffer.waitUntilScheduled()
        
            // Alternative present, connected to presentsWithTransaction
            metalKitView.currentDrawable?.present()
        }
    }
}

// MARK: - Vertex definition
struct Vertex {
    var position: float3
    var color: float4
}

extension Vertex {
    
    static let functionName = "vertex_shader"
    
    static var vertexDescriptor: MTLVertexDescriptor = {
        
        let vertexDescriptor = MTLVertexDescriptor()
        
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<float3>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        return vertexDescriptor
    }()
}
