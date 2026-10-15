// Comprueba que una firma EdDSA (la que genera sign_update de Sparkle) es válida para una
// clave pública concreta: la SUPublicEDKey de la app que se publica. Así el workflow falla si
// el secreto SPARKLE_PRIVATE_KEY no corresponde a la clave que llevan las apps instaladas.
// Uso: swift verify_ed_signature.swift <SUPublicEDKey base64> <firma base64> <fichero>
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4,
      let publicKeyData = Data(base64Encoded: args[1]),
      let signature = Data(base64Encoded: args[2]) else {
    FileHandle.standardError.write("uso: verify_ed_signature.swift <clave pública b64> <firma b64> <fichero>\n".data(using: .utf8)!)
    exit(2)
}

let data = try Data(contentsOf: URL(fileURLWithPath: args[3]), options: .mappedIfSafe)
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)

if publicKey.isValidSignature(signature, for: data) {
    print("Firma EdDSA válida para la SUPublicEDKey de la app.")
} else {
    FileHandle.standardError.write("La firma no corresponde a la SUPublicEDKey de la app: revisa el secreto SPARKLE_PRIVATE_KEY.\n".data(using: .utf8)!)
    exit(1)
}
