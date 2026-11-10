//
//  TLSOptions.swift
//  MobileDock — TLS-PSK parameters shared by the listener and the client.
//

import Foundation
import Network

public enum SecureTransport {

    /// TCP wrapped in TLS 1.3 keyed by the pairing PIN.
    public static func parameters(pin: String, includePeerToPeer: Bool = true) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions

        let key = PairingCrypto.preSharedKey(pin: pin)
        key.withUnsafeBytes { keyBytes in
            let keyData = DispatchData(bytes: keyBytes)
            PairingCrypto.pskIdentity.withUnsafeBytes { identityBytes in
                let identityData = DispatchData(bytes: identityBytes)
                sec_protocol_options_add_pre_shared_key(options,
                                                        keyData as __DispatchData,
                                                        identityData as __DispatchData)
            }
        }
        // External pre-shared keys are negotiated with the TLS 1.2 PSK suite;
        // the 1.3 suites here would leave the handshake hanging.
        if let suite = tls_ciphersuite_t(rawValue: 0x00A8) {   // TLS_PSK_WITH_AES_128_GCM_SHA256
            sec_protocol_options_append_tls_ciphersuite(options, suite)
        }
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)

        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = includePeerToPeer
        return parameters
    }
}
