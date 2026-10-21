#!/usr/bin/swift
import AppKit

// Editable vector geometry is shared by SVG, PDF and legacy macOS PNG exports.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let design = root.appendingPathComponent("Design/Icons")
let assets = root.appendingPathComponent("PenActor/Assets.xcassets")
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16)&255)/255, CGFloat((hex >> 8)&255)/255, CGFloat(hex&255)/255, alpha])!
}
struct Shape {
    var path = CGMutablePath()
    var svg = ""
    mutating func move(_ x: Double, _ y: Double) { path.move(to: CGPoint(x:x,y:y)); svg += "M\(x) \(y) " }
    mutating func line(_ x: Double, _ y: Double) { path.addLine(to: CGPoint(x:x,y:y)); svg += "L\(x) \(y) " }
    mutating func curve(_ x1: Double,_ y1: Double,_ x2: Double,_ y2: Double,_ x: Double,_ y: Double) {
        path.addCurve(to: CGPoint(x:x,y:y), control1: CGPoint(x:x1,y:y1), control2: CGPoint(x:x2,y:y2))
        svg += "C\(x1) \(y1) \(x2) \(y2) \(x) \(y) "
    }
    mutating func close() { path.closeSubpath(); svg += "Z " }
}
var nib = Shape()
nib.move(374,660); nib.line(430,449); nib.line(608,300); nib.line(742,434); nib.line(592,612); nib.close()
var slit = Shape(); slit.move(398,636); slit.line(550,484)
var wave = Shape()
// A single tapered ribbon leaves the exact tip, turns below it, then rises with pressure.
wave.move(382,648); wave.curve(295,729,320,770,416,766)
wave.curve(550,762,572,657,766,657)
wave.line(766,699); wave.curve(588,699,570,806,420,811)
wave.curve(274,824,243,747,390,656); wave.close()
var mark = Shape()
mark.move(5.5,17.4); mark.line(7.3,9.4); mark.line(13.8,4.8); mark.line(19,10); mark.line(14,16.1); mark.line(6.7,17.9); mark.line(12.4,12.2); mark.line(11.3,11.1); mark.close()
// Cut-outs are independent paths with even-odd filling: no white paint in the template.

let hole = CGPath(ellipseIn: CGRect(x:11.6,y:9.7,width:2.7,height:2.7), transform:nil)
mark.path.addPath(hole)
mark.svg += "M14.3 11.05 A1.35 1.35 0 1 0 11.6 11.05 A1.35 1.35 0 1 0 14.3 11.05 Z"
var underline = Shape(); underline.move(5.5,17.4)
underline.curve(2.3,20.2,4.2,22,8,21.5); underline.curve(13,21,13.3,18.2,20,18.2)
func gradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations:nil)!
    ctx.drawLinearGradient(g, start:from, end:to, options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
}
// Enlarge the entire emblem; optical correction compensates for the bright nib and low ink sweep.
let emblemScale: CGFloat = 1.18
let emblemOrigin = CGPoint(x: 512*(1-emblemScale)-28, y: 512*(1-emblemScale)-48)
func drawApp(_ ctx: CGContext) {
    ctx.saveGState()
    let tile = CGPath(roundedRect: CGRect(x:64,y:64,width:896,height:896), cornerWidth:202, cornerHeight:202, transform:nil)
    ctx.addPath(tile); ctx.clip()
    gradient(ctx,[color(0x246CE8),color(0x5C41CE),color(0xAA35BA)],from:CGPoint(x:148,y:132),to:CGPoint(x:906,y:960))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.translateBy(x: emblemOrigin.x, y: emblemOrigin.y)
    ctx.scaleBy(x: emblemScale, y: emblemScale)
    ctx.saveGState(); ctx.addPath(wave.path); ctx.clip()
    gradient(ctx,[color(0x64E9FF),color(0xACF7ED)],from:CGPoint(x:374,y:660),to:CGPoint(x:766,y:699))
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(nib.path); ctx.clip()
    gradient(ctx,[color(0xFFFFFF),color(0xC8F8FF)],from:CGPoint(x:620,y:270),to:CGPoint(x:390,y:680))
    ctx.restoreGState()
    ctx.setStrokeColor(color(0x5148CA)); ctx.setLineWidth(20); ctx.setLineCap(.round)
    ctx.addPath(slit.path); ctx.strokePath()
    ctx.setFillColor(color(0x5148CA)); ctx.fillEllipse(in:CGRect(x:525,y:459,width:50,height:50))
    ctx.restoreGState()
}
func drawMenu(_ ctx: CGContext) {
    ctx.setFillColor(color(0)); ctx.addPath(mark.path); ctx.drawPath(using:.eoFill)
    ctx.setStrokeColor(color(0)); ctx.setLineWidth(1.7); ctx.setLineCap(.round)
    ctx.addPath(underline.path); ctx.strokePath()
}
func png(size: Int, canvas: Double, draw: (CGContext)->Void, to url: URL) throws {
    let ctx = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x:0,y:CGFloat(size)); ctx.scaleBy(x:CGFloat(size)/canvas,y: -CGFloat(size)/canvas)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage:ctx.makeImage()!)
    try rep.representation(using:.png,properties:[:])!.write(to:url)
}
func pdf(size: Double, canvas: Double, draw: (CGContext)->Void, to url: URL) {
    var box = CGRect(x:0,y:0,width:size,height:size)
    let ctx = CGContext(url as CFURL,mediaBox:&box,nil)!
    ctx.beginPDFPage(nil); ctx.translateBy(x:0,y:size); ctx.scaleBy(x:size/canvas,y: -size/canvas)
    draw(ctx); ctx.endPDFPage(); ctx.closePDF()
}
func json(_ value: Any, to url: URL) throws {
    try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:url)
}
try json(["info":["author":"xcode","version":1]],to:assets.appendingPathComponent("Contents.json"))
var images: [[String:String]] = []
for points in [16,32,128,256,512] {
    for scale in [1,2] {
        let filename = "AppIcon-\(points)@\(scale)x.png"
        try png(size:points*scale,canvas:1024,draw:drawApp,to:assets.appendingPathComponent("AppIcon.appiconset/\(filename)"))
        images.append(["idiom":"mac","size":"\(points)x\(points)","scale":"\(scale)x","filename":filename])
    }
}
try json(["images":images,"info":["author":"xcode","version":1]],to:assets.appendingPathComponent("AppIcon.appiconset/Contents.json"))
pdf(size:18,canvas:24,draw:drawMenu,to:assets.appendingPathComponent("MenuBarIcon.imageset/MenuBarIcon.pdf"))
try json(["images":[["idiom":"mac","filename":"MenuBarIcon.pdf"]],"info":["author":"xcode","version":1],"properties":["preserves-vector-representation":true,"template-rendering-intent":"template"]],to:assets.appendingPathComponent("MenuBarIcon.imageset/Contents.json"))
let appSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<title>PenActor — pen and pressure</title>
<defs>
<linearGradient id="tile" gradientUnits="userSpaceOnUse" x1="148" y1="132" x2="906" y2="960"><stop stop-color="#246CE8"/><stop offset=".5" stop-color="#5C41CE"/><stop offset="1" stop-color="#AA35BA"/></linearGradient>
<linearGradient id="nib" gradientUnits="userSpaceOnUse" x1="620" y1="270" x2="390" y2="680"><stop stop-color="#FFFFFF"/><stop offset="1" stop-color="#C8F8FF"/></linearGradient>
<linearGradient id="wave" gradientUnits="userSpaceOnUse" x1="374" y1="660" x2="766" y2="699"><stop stop-color="#64E9FF"/><stop offset="1" stop-color="#ACF7ED"/></linearGradient>
</defs>
<rect x="64" y="64" width="896" height="896" rx="202" fill="url(#tile)"/>
<g transform="translate(\(emblemOrigin.x) \(emblemOrigin.y)) scale(\(emblemScale))">
<path d="\(wave.svg)" fill="url(#wave)"/>
<path d="\(nib.svg)" fill="url(#nib)"/>
<path d="\(slit.svg)" stroke="#5148CA" stroke-width="20" stroke-linecap="round"/>
<circle cx="550" cy="484" r="25" fill="#5148CA"/>
</g>
</svg>
"""
let menuSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24">
<title>PenActor menu bar template</title>
<path d="\(mark.svg)" fill="black" fill-rule="evenodd"/>
<path d="\(underline.svg)" fill="none" stroke="black" stroke-width="1.7" stroke-linecap="round"/>
</svg>
"""
try appSVG.write(to:design.appendingPathComponent("AppIcon.svg"),atomically:true,encoding:.utf8)
try menuSVG.write(to:design.appendingPathComponent("MenuBarIcon.svg"),atomically:true,encoding:.utf8)
pdf(size:1024,canvas:1024,draw:drawApp,to:design.appendingPathComponent("AppIcon.pdf"))
try png(size:512,canvas:1024,draw:drawApp,to:design.appendingPathComponent("AppIcon-preview.png"))
try png(size:144,canvas:24,draw:drawMenu,to:design.appendingPathComponent("MenuBarIcon-preview.png"))
try png(size:512,canvas:128,draw:{ ctx in
    ctx.setFillColor(color(0xF5F5F7)); ctx.fill(CGRect(x:0,y:0,width:64,height:128))
    ctx.setFillColor(color(0x202124)); ctx.fill(CGRect(x:64,y:0,width:64,height:128))
    ctx.saveGState(); ctx.translateBy(x:20,y:52); drawMenu(ctx); ctx.restoreGState()
    ctx.saveGState(); ctx.translateBy(x:84,y:52)
    ctx.setFillColor(color(0xFFFFFF)); ctx.addPath(mark.path); ctx.drawPath(using:.eoFill)
    ctx.setStrokeColor(color(0xFFFFFF)); ctx.setLineWidth(1.7); ctx.setLineCap(.round)
    ctx.addPath(underline.path); ctx.strokePath(); ctx.restoreGState()
},to:design.appendingPathComponent("MenuBarIcon-appearance-preview.png"))
print("Generated vector sources, template PDF and 10 macOS app icon sizes.")
