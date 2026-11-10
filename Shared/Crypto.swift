//
//  Crypto.swift
//  MobileDock — the shared secret both ends derive from the pairing PIN.
//

import Foundation
import CryptoKit

public enum PairingCrypto {
    /// The TLS pre-shared key. Knowing the PIN is what lets a device open an
    /// encrypted channel at all, so a wrong PIN fails during the handshake.
    public static func preSharedKey(pin: String) -> Data {
        let material = "MobileDock/psk/v1/" + pin.trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(SHA256.hash(data: Data(material.utf8)))
    }

    public static let pskIdentity = Data("MobileDock".utf8)
}
