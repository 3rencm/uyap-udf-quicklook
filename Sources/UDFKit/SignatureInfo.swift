import Foundation

// MARK: - İmza özeti
//
// UYAP .udf dosyalarının "sign.sgn" girdisi PKCS#7/CMS SignedData yapısındadır.
// Burada imzalayan kişi (CN), imza zincirinin kökü (issuer) ve imza zamanı çıkarılır.

public struct SignatureInfo {
    public let signerName: String?
    public let issuerName: String?
    public let signedAt: String?
    public let isSigned: Bool

    public init(signerName: String?, issuerName: String?, signedAt: String?, isSigned: Bool) {
        self.signerName = signerName
        self.issuerName = issuerName
        self.signedAt = signedAt
        self.isSigned = isSigned
    }

    public static let unsigned = SignatureInfo(signerName: nil, issuerName: nil, signedAt: nil, isSigned: false)

    public static func parse(data: Data) -> SignatureInfo {
        let roots = DERParser.parse(data)
        guard let contentInfo = roots.first(where: { $0.tag == 0x30 }) else {
            return heuristicFallback(data)
        }

        // ContentInfo ::= SEQUENCE { contentType OID, content [0] EXPLICIT ANY }
        guard let explicit = contentInfo.children.first(where: { $0.tag == 0xA0 }),
              let signedData = explicit.children.first(where: { $0.tag == 0x30 })
        else {
            return heuristicFallback(data)
        }

        // SignedData içindeki alanlar
        let certificatesNode = signedData.children.first(where: { $0.tag == 0xA0 })
        // signerInfos, SignedData içindeki son SET'tir (öncesinde digestAlgorithms SET'i bulunur).
        let signerInfosNode = signedData.children.last(where: { $0.tag == 0x31 })

        var signerName: String?
        var issuerName: String?

        if let certificate = certificatesNode?.children.first(where: { $0.tag == 0x30 }),
           let tbs = certificate.children.first(where: { $0.tag == 0x30 }) {
            // X.509 tbsCertificate: [0] version, serialNumber, signature, issuer, validity,
            // subject, subjectPublicKeyInfo...
            // Name alanları SET (RDN) içeren SEQUENCE'lardır; validity ise UTC zaman içerir.
            let names = tbs.children.filter { node in
                node.tag == 0x30 && node.children.contains(where: { $0.tag == 0x31 })
            }
            issuerName = names.first?.commonName()
            if names.count > 1 {
                signerName = names[1].commonName()
            }
            if signerName == nil, names.count == 1 {
                signerName = names[0].commonName()
            }
        }

        // İmza zamanı: SignerInfo içindeki signedAttrs -> signingTime (UTCTime)
        var signedAt: String?
        if let signerInfo = signerInfosNode?.children.first(where: { $0.tag == 0x30 }) {
            let times = signerInfo.descendants(where: { $0.tag == 0x17 || $0.tag == 0x18 })
            for time in times {
                if let value = time.stringValue() {
                    signedAt = value
                    break
                }
            }
        }

        if signerName == nil && issuerName == nil {
            return heuristicFallback(data)
        }

        return SignatureInfo(
            signerName: signerName,
            issuerName: issuerName,
            signedAt: signedAt,
            isSigned: true
        )
    }

    /// Yapısal ayrıştırma başarısız olursa, ham metin taramasıyla CN değerleri bulunur.
    private static func heuristicFallback(_ data: Data) -> SignatureInfo {
        let nodes = DERParser.parse(data)
        let strings = nodes.flatMap { node -> [String] in
            node.children.compactMap { $0.stringValue() }
        }
        let all = strings + nodes.compactMap { $0.stringValue() }

        var issuer: String?
        var signer: String?

        for value in all {
            let upper = value.uppercased()
            if issuer == nil, upper.contains("TRUST") || upper.contains("TÜRKTRUST") || upper.contains("T.C.") {
                issuer = value
            }
        }
        for value in all {
            let upper = value.uppercased()
            if upper.contains("MAHKEME") || upper.contains("TRUST") || upper.contains("TÜRKTRUST") { continue }
            if upper.contains("İSTANBUL") || upper.contains("ANKARA") || upper.contains("IZMIR") { continue }
            if value.rangeOfCharacter(from: .decimalDigits) != nil { continue }
            if signer == nil, value.count >= 4, value.contains(" ") {
                signer = value
            }
        }

        guard signer != nil || issuer != nil else { return .unsigned }
        return SignatureInfo(signerName: signer, issuerName: issuer, signedAt: nil, isSigned: true)
    }
}
