//
//  ViewController.swift
//  Desync
//
// This project simulates an issue when trying to use Metal in conjuction
// with UIKit. Specifically, it highlights that when using the recommended
// method specified by Apple in the documentation (1) for .presentsWithTransaction
// on CAMetalLayer: if a spike in CPU usage occurs the render loop can become
// starved of drawables – apparently desynchronised – until subsequent CPU spike
// knocks it back into sync.
//
// This project simulates this issue in nearly the simplest Metal project possible
// (drawing a single quad to screen) and simulating a typical background load
// (a short wait on each frame of the render loop).
//
// In usual operation, the duration for the CPU to submit and schedule its work on
// the GPU is ~1ms. However, when a CPU spike occurs, desynchronisation may take
// place after which this can rise to around ~8ms. (This can be simulated by
// pressing the 'do heavy work button' which will force a short delay on the main
// thread.) Observing this behaviour in the Metal instruments panel, we can see
// that the render loop is becoming blocked waiting for a drawable on each frame.
// A subsequent CPU spike can knock the render loop back into sync.
//
// This wait on the main thread seems to cause issues elsewhere in UIKit. In the
// example project, you can see that when the loop is desynchronised dragging the
// circle appears jerky – touch events appear delayed.
//
// Desynchronisation only seems to occur if there is some quantity of work
// occuring on the main thread. On an iPhone X, 6ms worth seems to expose the
// issue, but this may need to be tweaked for other devices. Usually, pressing
// the 'do heavy work' button a couple of times will cause a desync/resync to
// occur, but occasionally requires a few more.
//
// 1: https://developer.apple.com/documentation/quartzcore/cametallayer/1478157-presentswithtransaction

import UIKit
import MetalKit

// MARK: - App constants
// the duration for which the main thread will be delayed (usleep) when the
// 'heavy work' button is pressed to simulate in in-app/system CPU spike
// and consequential delay on the main thread.
let heavyWorkSimulatedDelayMicroseconds = UInt32(200_000)

// the duration for which the main thread will be delayed each frame to simulate
// work undertaken to update state or other necessary work that is completed each
// frame. A value of 6_000 seems to expose the issue on an iPhone X.
let stateUpdatePerFrameSimulatedDelayMicroseconds = UInt32(8_000)

final class MetalKitViewController: UIViewController {
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    lazy private var metalKitView = MTKView(frame: .zero, device: device)
    lazy private var overlayView = OverlayView(frame: .zero)
    
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
        //metalKitView.presentsWithTransaction = true
        
        containerView.addSubview(metalKitView)
        
        overlayView.frame = containerView.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        containerView.addSubview(overlayView)
        
        self.view = containerView
    }
}

// MARK: - MTKViewDelegate conformance / main render loop
extension MetalKitViewController: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        
        // update label
        
        overlayView.frameRateLabel.text = "\(String(format: "%.3f", waitTimeAverage * 1000)) ms"
        
        // simulate state update/arbitrary CPU work
        
        usleep(stateUpdatePerFrameSimulatedDelayMicroseconds)
        
        let nextDrawableRequestTime = CACurrentMediaTime()
        
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
        commandBuffer.commit()
        
        // Wait until current buffer scheduled
        
        commandBuffer.waitUntilScheduled()
        
        metalKitView.currentDrawable?.present()
        
        updateWaitTimeAverage(CACurrentMediaTime() - nextDrawableRequestTime)
    }
    
    private func updateWaitTimeAverage(_ waitTime: Double) {
        waitTimeAverage = (waitTime * lowPassFactor) + (waitTimeAverage * (1-lowPassFactor))
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

// MARK: - Overlay view definition
final class OverlayView: UIView {
    
    // MARK: - Properties
    
    lazy var frameRateLabel = UILabel(frame: .zero)
    
    lazy var heavyWorkButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Do Heavy Work", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 36)
        return button
    }()
    
    lazy private var dragView: UIView = {
        let dragView = UIView(frame: .zero)
        dragView.backgroundColor = .gray
        dragView.layer.cornerRadius = 100
        return dragView
    }()
    
    private lazy var panGestureRecognizer = UIPanGestureRecognizer(
        target: self, action: #selector(panGestureRecognizerDidUpdate))
    
    // MARK: - Initialiser
    
    override init(frame: CGRect) {
        
        super.init(frame: frame)
        
        dragView.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        dragView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        dragView.addGestureRecognizer(panGestureRecognizer)
        dragView.autoresizingMask = [
            .flexibleTopMargin,
            .flexibleRightMargin,
            .flexibleBottomMargin,
            .flexibleLeftMargin
        ]
        addSubview(dragView)
        
        frameRateLabel.backgroundColor = .clear
        frameRateLabel.textColor = .white
        frameRateLabel.font = UIFont.systemFont(ofSize: 72, weight: .heavy)
        frameRateLabel.textAlignment = .center
        frameRateLabel.frame = CGRect(x: 0, y: 50, width: bounds.size.width, height: 72)
        frameRateLabel.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
        addSubview(frameRateLabel)
        
        heavyWorkButton.frame = CGRect(x: 0, y: bounds.size.height - 120, width: 0, height: 80)
        heavyWorkButton.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        heavyWorkButton.addTarget(self, action: #selector(buttonAction), for: .touchUpInside)
        addSubview(heavyWorkButton)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Input handlers
    
    @objc private func panGestureRecognizerDidUpdate(_ gestureRecognizer: UIPanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .changed:
            let currentSample = gestureRecognizer.translation(in: self)
            dragView.transform = CGAffineTransform(translationX: currentSample.x, y: currentSample.y)
        case .ended:
            dragView.transform = .identity
        default: break
        }
    }
    
    @objc private func buttonAction(_ sender: UIButton) {
        // simulate arbitrary/intermittent CPU spike
        usleep(heavyWorkSimulatedDelayMicroseconds)
    }
}
