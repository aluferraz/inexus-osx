import Foundation
import NexusCore

let argv = Array(CommandLine.arguments.dropFirst())

func usage() {
    let prog = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "nexusctl"
    print("""
    \(prog) — control the Corsair iCUE Nexus from the command line

    Usage:
      \(prog) info
      \(prog) brightness <0-100>
      \(prog) blank
      \(prog) anim <1|2|3> [--loop]
      \(prog) stop-anim
      \(prog) image <path>
      \(prog) touch [seconds]
      \(prog) demo
    """)
}

guard !argv.isEmpty else { usage(); exit(1) }

func openDevice() -> NexusDevice {
    do {
        return try NexusDevice.open()
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(2)
    }
}

let cmd = argv[0]
let rest = Array(argv.dropFirst())

do {
    switch cmd {
    case "info":
        let d = openDevice()
        print("Firmware: \(try d.firmwareVersion())")

    case "brightness":
        guard let v = rest.first.flatMap(Int.init) else { usage(); exit(1) }
        try openDevice().setBrightness(v)
        print("Brightness set to \(v)")

    case "blank":
        try openDevice().blankScreen()
        print("Screen blanked")

    case "anim":
        guard let n = rest.first.flatMap(Int.init), (1...3).contains(n) else { usage(); exit(1) }
        let loop = rest.contains("--loop")
        try openDevice().playAnimation(n, loop: loop)
        print("Playing animation \(n)\(loop ? " (loop)" : "")")

    case "stop-anim":
        try openDevice().stopAnimation()
        print("Animation stopped")

    case "image":
        guard let path = rest.first else { usage(); exit(1) }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let frame = try NexusImage.loadAsFrame(url: url)
        try openDevice().showFrame(frame)
        print("Pushed \(frame.count) bytes")

    case "touch":
        let timeout = TimeInterval(rest.first.flatMap(Double.init) ?? 10)
        let device = openDevice()
        device.scheduleOnRunLoop()
        let recognizer = NexusGestureRecognizer()
        var done = false
        device.onTouch { event in
            switch event.phase {
            case .began: print("down @ \(event.x)")
            case .moved: print("move @ \(event.x)")
            case .ended: print("up   @ \(event.x)")
            }
            if let gesture = recognizer.feed(event) {
                print(">> gesture: \(gesture)")
                done = true
            }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !done, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        if !done { print("--") }

    case "demo":
        let d = openDevice()
        let frame = try NexusImage.renderToFrame { ctx in
            ctx.setFillColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: NexusProtocol.width, height: NexusProtocol.height))
            // Vertical bars sweeping through the rainbow as a visual sanity check.
            for x in 0..<NexusProtocol.width {
                let hue = CGFloat(x) / CGFloat(NexusProtocol.width)
                let r = abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1)
                ctx.setFillColor(red: 1 - r, green: r, blue: 0.5, alpha: 1)
                ctx.fill(CGRect(x: CGFloat(x), y: 4, width: 1, height: 40))
            }
        }
        try d.setBrightness(100)
        try d.showFrame(frame)
        print("Demo pattern pushed")

    case "help", "-h", "--help":
        usage()

    default:
        usage(); exit(1)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(3)
}
