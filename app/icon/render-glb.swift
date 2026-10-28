// render-glb.swift: render a simple glTF binary (.glb) model to a square PNG with a transparent background.
// It supports what the icon model uses: triangle meshes with POSITION, NORMAL, and COLOR_0, and node transforms.
// The model fills the inner part of the image, with a transparent margin around it.
//
//   swift render-glb.swift <model.glb> <output.png> [yaw degrees] [pitch degrees]
//
// The app icon (laptop.png) comes from the "Laptop" model by Polyfork:
// https://polyfork.dev/asset/laptop-e775ba
// This repository does not include the model file, because its license does not allow sharing the file.

import AppKit
import SceneKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: render-glb.swift <model.glb> <output.png> [yaw] [pitch]\n".data(using: .utf8)!)
    exit(1)
}
let yaw = (args.count > 3 ? Double(args[3]) : nil) ?? 30
let pitch = (args.count > 4 ? Double(args[4]) : nil) ?? 22
let renderSize = 2048, canvas = 1024, inner = 832

// MARK: Read the .glb file

let file = try! Data(contentsOf: URL(fileURLWithPath: args[1]))
func uint32(_ offset: Int) -> Int { Int(file.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }) }
guard file.count > 20, String(data: file.prefix(4), encoding: .ascii) == "glTF" else { fatalError("Not a .glb file") }
let jsonLength = uint32(12)
let json = try! JSONSerialization.jsonObject(with: file.subdata(in: 20..<20 + jsonLength)) as! [String: Any]
let binStart = 20 + jsonLength + 8
let bin = file.subdata(in: binStart..<binStart + uint32(20 + jsonLength))

let accessors = json["accessors"] as! [[String: Any]]
let views = json["bufferViews"] as! [[String: Any]]
let meshes = json["meshes"] as! [[String: Any]]
let nodes = json["nodes"] as! [[String: Any]]

/// The values of an accessor, as floats (VEC3 or SCALAR, float or unsigned integer components).
func values(_ index: Int) -> [Float] {
    let accessor = accessors[index]
    let view = views[accessor["bufferView"] as! Int]
    let components = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4][accessor["type"] as! String]!
    let type = accessor["componentType"] as! Int
    let size = [5126: 4, 5125: 4, 5123: 2, 5121: 1][type]!
    let stride = view["byteStride"] as? Int ?? components * size
    let start = (view["byteOffset"] as? Int ?? 0) + (accessor["byteOffset"] as? Int ?? 0)
    var result: [Float] = []
    bin.withUnsafeBytes { raw in
        for item in 0..<(accessor["count"] as! Int) {
            for component in 0..<components {
                let offset = start + item * stride + component * size
                switch type {
                case 5126: result.append(raw.loadUnaligned(fromByteOffset: offset, as: Float.self))
                case 5125: result.append(Float(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                case 5123: result.append(Float(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
                default: result.append(Float(raw.load(fromByteOffset: offset, as: UInt8.self)))
                }
            }
        }
    }
    return result
}

func vectors(_ index: Int) -> [SCNVector3] {
    let v = values(index)
    return stride(from: 0, to: v.count, by: 3).map { SCNVector3(v[$0], v[$0 + 1], v[$0 + 2]) }
}

// MARK: Build the scene

let material = SCNMaterial()
material.lightingModel = .physicallyBased
material.diffuse.contents = NSColor.white
material.metalness.contents = 0.0
material.roughness.contents = 0.85

func geometry(_ meshIndex: Int) -> SCNGeometry {
    let primitive = (meshes[meshIndex]["primitives"] as! [[String: Any]])[0]
    let attributes = primitive["attributes"] as! [String: Int]
    var sources = [SCNGeometrySource(vertices: vectors(attributes["POSITION"]!))]
    if let normal = attributes["NORMAL"] { sources.append(SCNGeometrySource(normals: vectors(normal))) }
    if let color = attributes["COLOR_0"] {
        let components = accessors[color]["type"] as! String == "VEC4" ? 4 : 3
        let data = values(color).withUnsafeBufferPointer { Data(buffer: $0) }
        sources.append(SCNGeometrySource(data: data, semantic: .color, vectorCount: data.count / (4 * components),
                                         usesFloatComponents: true, componentsPerVector: components,
                                         bytesPerComponent: 4, dataOffset: 0, dataStride: 4 * components))
    }
    let count = accessors[attributes["POSITION"]!]["count"] as! Int
    let indices = (primitive["indices"] as? Int).map { values($0).map { UInt32($0) } } ?? (0..<UInt32(count)).map { $0 }
    let shape = SCNGeometry(sources: sources, elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    shape.materials = [material]
    return shape
}

func makeNode(_ index: Int) -> SCNNode {
    let info = nodes[index]
    let node = SCNNode()
    if let mesh = info["mesh"] as? Int { node.geometry = geometry(mesh) }
    if let m = (info["matrix"] as? [Double])?.map({ CGFloat($0) }) {
        // glTF matrices are column-major, which has the same order as the SCNMatrix4 fields.
        node.transform = SCNMatrix4(m11: m[0], m12: m[1], m13: m[2], m14: m[3], m21: m[4], m22: m[5], m23: m[6], m24: m[7],
                                    m31: m[8], m32: m[9], m33: m[10], m34: m[11], m41: m[12], m42: m[13], m43: m[14], m44: m[15])
    } else {
        if let t = info["translation"] as? [Double] { node.position = SCNVector3(t[0], t[1], t[2]) }
        if let r = info["rotation"] as? [Double] { node.orientation = SCNQuaternion(r[0], r[1], r[2], r[3]) }
        if let s = info["scale"] as? [Double] { node.scale = SCNVector3(s[0], s[1], s[2]) }
    }
    for child in info["children"] as? [Int] ?? [] { node.addChildNode(makeNode(child)) }
    return node
}

let scene = SCNScene()
scene.background.contents = NSColor.clear
let sceneIndex = json["scene"] as? Int ?? 0
let roots = ((json["scenes"] as! [[String: Any]])[sceneIndex]["nodes"] as! [Int]).map(makeNode)
let model = SCNNode()
roots.forEach(model.addChildNode)
scene.rootNode.addChildNode(model)

// Soft light from all sides, a key light from the upper left, and a fill light from the right.
scene.lightingEnvironment.contents = NSColor(white: 0.55, alpha: 1)
scene.lightingEnvironment.intensity = 1.0
func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ euler: SCNVector3) {
    let node = SCNNode()
    node.light = SCNLight()
    node.light!.type = type
    node.light!.intensity = intensity
    node.eulerAngles = euler
    scene.rootNode.addChildNode(node)
}
light(.directional, 1150, SCNVector3(-0.9, -0.5, 0))
light(.directional, 500, SCNVector3(-0.3, 0.9, 0))

// The camera looks at the center of the model from the yaw and pitch angles.
let (low, high) = model.boundingBox
let center = SCNVector3((low.x + high.x) / 2, (low.y + high.y) / 2, (low.z + high.z) / 2)
let radius = CGFloat(sqrt(pow(Double(high.x - low.x), 2) + pow(Double(high.y - low.y), 2) + pow(Double(high.z - low.z), 2))) / 2
let camera = SCNNode()
camera.camera = SCNCamera()
camera.camera!.fieldOfView = 25
camera.camera!.zNear = 0.001
let distance = radius * 5
let y = yaw * .pi / 180, p = pitch * .pi / 180
camera.position = SCNVector3(center.x + distance * CGFloat(sin(y) * cos(p)),
                             center.y + distance * CGFloat(sin(p)),
                             center.z + distance * CGFloat(cos(y) * cos(p)))
camera.look(at: center)
scene.rootNode.addChildNode(camera)

// MARK: Render, then fit the model into the canvas

let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
renderer.scene = scene
renderer.pointOfView = camera
let image = renderer.snapshot(atTime: 0, with: CGSize(width: renderSize, height: renderSize), antialiasingMode: .multisampling4X)
let rendered = NSBitmapImageRep(data: image.tiffRepresentation!)!

// Find the pixels that are not transparent.
var minX = rendered.pixelsWide, minY = rendered.pixelsHigh, maxX = 0, maxY = 0
for py in 0..<rendered.pixelsHigh {
    for px in 0..<rendered.pixelsWide where (rendered.colorAt(x: px, y: py)?.alphaComponent ?? 0) > 0.02 {
        minX = min(minX, px); maxX = max(maxX, px); minY = min(minY, py); maxY = max(maxY, py)
    }
}
guard maxX > minX, maxY > minY else { fatalError("The render is empty") }

let crop = NSRect(x: minX, y: rendered.pixelsHigh - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
let scale = CGFloat(inner) / max(crop.width, crop.height)
let target = NSRect(x: (CGFloat(canvas) - crop.width * scale) / 2, y: (CGFloat(canvas) - crop.height * scale) / 2,
                    width: crop.width * scale, height: crop.height * scale)
let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
NSGraphicsContext.current?.imageInterpolation = .high
// A soft shadow below the model, so that a light model shows clearly on a white background.
let shadow = NSShadow()
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 28
shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
shadow.set()
rendered.draw(in: target, from: crop, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
NSGraphicsContext.restoreGraphicsState()
try! output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("Wrote \(args[2])")
