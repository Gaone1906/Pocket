import Foundation

let stamp = ISO8601DateFormatter()

let logFile: FileHandle? = {
    let path = NSHomeDirectory() + "/Library/Logs/pocket.log"
    let files = FileManager.default
    if let size = (try? files.attributesOfItem(atPath: path))?[.size] as? Int, size > 5_000_000 {
        try? files.removeItem(atPath: path + ".1")
        try? files.moveItem(atPath: path, toPath: path + ".1")
    }
    if !files.fileExists(atPath: path) { files.createFile(atPath: path, contents: nil) }
    let handle = FileHandle(forWritingAtPath: path)
    handle?.seekToEndOfFile()
    return handle
}()

func note(_ message: String) {
    let line = Data("\(stamp.string(from: Date())) \(message)\n".utf8)
    if let logFile { logFile.write(line) } else { FileHandle.standardError.write(line) }
}
