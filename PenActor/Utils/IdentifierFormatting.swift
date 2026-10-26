import Foundation

func identifierText<T: BinaryInteger>(_ value: T) -> String {
    "\(value) / 0x\(String(value, radix: 16).uppercased())"
}
