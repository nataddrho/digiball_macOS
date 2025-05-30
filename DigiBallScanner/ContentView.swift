//  ContentView.swift
//  DigiBallScanner App
//
//  Created by Nathan Rhoades on 4/5/25.
//
import SwiftUI
import CoreBluetooth
import CoreGraphics
import Observation
import AppKit

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var discoveredDigiBallsDevices: [String] = []// Array to store discovered DigiBall devices in format shortMac
    @Published var discoveredDigiBallsRSSI = [String: NSNumber]() // Dict to store discovered DigiBall devices in format shortMac:rssi
    @Published var discoveredDigiBallsManufData = [String: NSData]() //Dict to store advertisement data in format shortMac:manufData
    private var centralManager: CBCentralManager! // Central manager for BLE operations
        
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        if centralManager.state == .poweredOn {
            let options = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            centralManager.scanForPeripherals(withServices: nil, options: options) // Scan for all BLE devices
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
    }
    
    // MARK: - CBCentralManagerDelegate methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Check if Bluetooth is powered on and start scanning if needed
        if central.state == .poweredOn {
            startScanning()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        let adData = advertisementData[CBAdvertisementDataManufacturerDataKey]
        if (adData != nil)
        {
            let data : NSData = adData as! NSData
            if (data[0]==0xDE && data[1]==0x03) { //NRLLC identifier
                
                let shortMac: String = String(format: "%02X:%02X:%02X",data[2],data[3],data[4])
                
                if ((0xF&data[5])==1) { //Device type 1 is a DigiBall
                    
                    if (!discoveredDigiBallsDevices.contains(shortMac)) {
                        discoveredDigiBallsDevices.append(shortMac)
                    }
                    discoveredDigiBallsRSSI[shortMac] = RSSI
                    discoveredDigiBallsManufData[shortMac] = data
                }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var bluetoothManager = BluetoothManager()// Create an instance of BluetoothManager
    @Environment(\.scenePhase) var scenePhase
    @State private var showFileImporter = false
    @EnvironmentObject var settings: GlobalSettings
    let exportSize = CGSize(width: 200, height: 200)
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        @State private var counter = 0
                            
    var body: some View {
                
        let savedDeviceID = UserDefaults.standard.string(forKey: "deviceID") ?? ""
        let imageName = "DigiBall.png"
        let devices = bluetoothManager.discoveredDigiBallsDevices;
        let foundID: Bool = devices.contains(savedDeviceID)
        let rssi: Int = foundID ? bluetoothManager.discoveredDigiBallsRSSI[savedDeviceID]!.intValue : 0
        let manufData: NSData? = foundID ? bluetoothManager.discoveredDigiBallsManufData[savedDeviceID] : nil
        
        HStack {
                
            List(devices, id: \.self) { device in
                DeviceListItem(
                    text: String(format: "%@  %i dBm (%is)", device, bluetoothManager.discoveredDigiBallsRSSI[device]!.intValue,
                                 (Int(manufData![9]&3)*256 + Int(manufData![10]))),
                    device: device,
                    selected: device == savedDeviceID
                )
                
            }
            
            BallView(manufData: manufData, rssi: rssi)
                .overlay(
                    ZStack{
                        Text("Select a DigiBall device")
                            .multilineTextAlignment(.center)
                            .background(Color.black.opacity(0.75))
                            .opacity(savedDeviceID == "" ? 1 : 0)
                    }
                )
            
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        bluetoothManager.startScanning()
                    }
                }
                .onAppear {
                    bluetoothManager.startScanning()
                    //let _ = print("started scanning")/// Start scanning when the view appears
                }
                .onDisappear {
                    //bluetoothManager.stopScanning()
                    //let _ = print("stopped scanning")// Stop scanning when the view disappears
                }
        }
        .onReceive(timer) { time in
            if (manufData != nil) {
                let shotNumber: UInt8 = manufData![8] & 0x7F
                let dataReady: Bool = manufData![19]>>6 == 1
                if (dataReady && shotNumber != settings.lastShotNumber) {
                    settings.updateShotNumber(value: shotNumber)
                    
                    //Save image into Pictures directory when shot number changes
                    let view = BallView(manufData: manufData, rssi: rssi)
                    let image = imageFromView(view, size: exportSize)

                    do {
                        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
                        let fileURL = picturesURL.appendingPathComponent(imageName)
                        
                        try saveImageAsPNG(image, to: fileURL)
                    } catch {
                        print("Error saving image: \(error)")
                    }
                }
            }
            counter += 1
        }
        
    }
        
    struct DeviceListItem: View {
        let text: String
        let device: String
        let selected: Bool
        var body: some View {
            
            Text(text)
                .listRowBackground(selected ? Color.blue : nil)
                .onTapGesture {
                    UserDefaults.standard.set(device, forKey: "deviceID")
                }
        }
    }
    
    struct BallView: View {
                
        let manufData: NSData?
        let rssi: Int
        
        var body: some View {
            
            ZStack {
                
                GeometryReader { geometry in
                    //Draw ball with clean edges.
                    Circle()
                        .fill(Color(red: 1.0, green: 0.9, blue: 0.7))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            
                //Overlay with ball image.
                Image("ball")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                
                GeometryReader { geometry in
                    
                    var centerX: CGFloat {geometry.size.width / 2}
                    var centerY: CGFloat {geometry.size.height / 2}
                    var radius: CGFloat {min(centerX, centerY)}
                    
                    //Draw grid
                    ForEach(0..<12) { i in
                        var x: CGFloat {0.6 * radius * CGFloat(cos(Double.pi * 2 / 12 * Double(i)))}
                        var y: CGFloat {0.6 * radius * CGFloat(sin(Double.pi * 2 / 12 * Double(i)))}
                        
                        Path { path in
                            path.move(to: CGPoint(x: centerX, y: centerY))
                            path.addLine(to: CGPoint(x: centerX+x, y: centerY+y))
                        }
                        .stroke(Color.black.opacity(0.5), lineWidth: 1)
                    }
                    ForEach(1..<7) { i in
                        var r: CGFloat {0.1*Double(i)*radius}
                        Circle()
                            .stroke(Color.black.opacity(0.5), lineWidth: 1)
                            .frame(width: 2*r, height: 2*r)
                            .position(x: centerX, y: centerY)
                        
                    }
                    
                    if (manufData != nil) {
                        
                        let ballTypes: [Double] = [2.25,2.438,2.438,2.063,2,2.688]
                        //pool, carom, carom (yellow), snooker, english pool, russian pyramid
                        
                        let ballType: UInt8 = (manufData![5]>>4) & 0xF
                        let tipPercent: UInt8 = manufData![13]
                        let spinHorzDPS: Int16 = Int16(manufData![15])<<8 | Int16(manufData![16])
                        let spinVertDPS: Int16 = Int16(manufData![17])<<8 | Int16(manufData![18])
                        let angleDegrees: Double = 180/Double.pi * atan2(Double(spinHorzDPS),Double(spinVertDPS))
                        let dataReady: Bool = manufData![19]>>6 == 1
                        
                        
                        //Calculate tip outline position
                        let ball_diameter: Double = ballTypes[Int(ballType)]
                        let tip_diameter: Double = 11.8 / 25.4
                        let tip_curvature: Double = 0.358
                        let ball_radius: Double = ball_diameter / 2
                        let tip_radius: Double = tip_diameter / 2
                        let tip_radius_curvature_ratio: Double = tip_curvature / ball_radius
                        let t: Double = Double(Double(tipPercent)>55 ? 55 : tipPercent)
                        let r1: Double = ball_radius * t/100
                        let draw_offset: Double = r1 * tip_radius_curvature_ratio
                        let s1: Double = r1 + draw_offset
                        let px1: Double = ((s1-tip_radius) > r1) ? r1 + tip_radius : s1
                        
                        //Draw tip outline
                        let ax: Double = sin(Double.pi / 180 * angleDegrees)
                        let ay: Double = -cos(Double.pi / 180 * angleDegrees)
                        let x: Double = centerX + radius * ax * px1 / ball_radius
                        let y: Double = centerY + radius * ay * px1 / ball_radius
                        let tr: Double = radius * tip_radius / ball_radius
                        
                        if (dataReady) {
                            Circle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: 2*tr, height: 2*tr)
                                .position(x: x, y: y)
                        }
                        
                        //Draw tip contact point
                        let x_contact: Double = centerX + radius * ax * r1 / ball_radius
                        let y_contact: Double = centerY + radius * ay * r1 / ball_radius
                        if (dataReady) {
                            Circle()
                                .fill(Color.cyan)
                                .frame(width: 5, height: 5)
                                .position(x: x_contact, y: y_contact)
                        }
                        
                    }
                }
            }
        }
    }
}

// MARK: - Rendering Helpers

func imageFromView<V: View>(_ view: V, size: CGSize) -> NSImage {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)

    let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)!
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)

    let image = NSImage(size: size)
    image.addRepresentation(bitmapRep)

    return image
}

func saveImageAsPNG(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ImageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
    }

    try pngData.write(to: url)
}
