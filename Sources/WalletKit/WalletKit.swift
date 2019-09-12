import Core
import Crypto
import ZIPFoundation

enum WalletKitError: Error {
    case invalidPassJSON
    case cannotGenerateKey(underlying: Error)
    case cannotGenerateCertificate(underlying: Error)
    case cannotGenerateSignature(underlying: Error)
}

public struct WalletKit {
    
    private let certificatePath: String
    private let certificatePassword: String
    private let wwdrPath: String
    private let templateDirectoryPath: String
    private let fileManager = FileManager.default
    
    public init(certificatePath: String, certificatePassword: String, wwdrPath: String, templateDirectoryPath: String) {
        self.certificatePath = certificatePath
        self.certificatePassword = certificatePassword
        self.wwdrPath = wwdrPath
        self.templateDirectoryPath = templateDirectoryPath
    }
    
    public func savePass(pass: Pass, destination: String) throws {
        let passData = try generatePass(pass: pass)
        fileManager.createFile(atPath: destination, contents: passData, attributes: nil)
    }
    
    public func generatePass(pass: Pass) throws -> Data {
        let directory = fileManager.currentDirectoryPath
        let temporaryDirectory = directory + UUID().uuidString + "/"
        let passDirectory = temporaryDirectory + "pass/"
        defer {
            try? fileManager.removeItem(atPath: temporaryDirectory)
        }
        try fileManager.createDirectory(atPath: temporaryDirectory, withIntermediateDirectories: false, attributes: nil)
        try fileManager.copyItem(atPath: templateDirectoryPath, toPath: passDirectory)
        
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        let passData: Data
        do {
            passData = try jsonEncoder.encode(pass)
        } catch {
            throw WalletKitError.invalidPassJSON
        }
        fileManager.createFile(atPath: passDirectory + "pass.json", contents: passData, attributes: nil)
        
        try generateManifest(directory: passDirectory)
        
        try generateKey(directory: temporaryDirectory)
        try generateCertificate(directory: temporaryDirectory)
        
        try generateSignature(directory: temporaryDirectory, passDirectory: passDirectory)
        
        let passURL = URL(fileURLWithPath: passDirectory, isDirectory: true)
        let zipURL = URL(fileURLWithPath: temporaryDirectory + "/pass.pkpass")
        try fileManager.zipItem(at: passURL, to: zipURL, shouldKeepParent: false)
        return try Data(contentsOf: zipURL)
    }
}

private extension WalletKit {
    
    func generateManifest(directory: String) throws {
        let contents = try fileManager.contentsOfDirectory(atPath: directory)
        var manifest: [String: String] = [:]
        try contents.forEach({ (item) in
            guard let data = fileManager.contents(atPath: directory + item) else { return }
            let hash = try SHA1.hash(data).hexEncodedString()
            manifest[item] = hash
        })
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
        fileManager.createFile(atPath: directory + "manifest.json", contents: manifestData, attributes: nil)
    }
    
    func generateKey(directory: String) throws {
        let keyPath = directory + "key.pem"
        do {
            _ = try Process.execute("openssl",
                                    "pkcs12",
                                    "-in",
                                    certificatePath,
                                    "-nocerts",
                                    "-out",
                                    keyPath,
                                    "-passin",
                                    "pass:" + certificatePassword,
                                    "-passout",
                                    "pass:" + certificatePassword)
        } catch {
            throw WalletKitError.cannotGenerateKey(underlying: error)
        }
    }
    
    func generateCertificate(directory: String) throws {
        let certPath = directory + "cert.pem"
        do {
            _ = try Process.execute("openssl",
                                    "pkcs12",
                                    "-in",
                                    certificatePath,
                                    "-clcerts",
                                    "-nokeys",
                                    "-out",
                                    certPath,
                                    "-passin",
                                    "pass:" + certificatePassword)
        } catch {
            throw WalletKitError.cannotGenerateCertificate(underlying: error)
        }
    }
    
    func generateSignature(directory: String, passDirectory: String) throws {
        do {
            _ = try Process.execute("openssl",
                                    "smime",
                                    "-sign",
                                    "-signer",
                                    directory + "cert.pem",
                                    "-inkey",
                                    directory + "key.pem",
                                    "-certfile",
                                    wwdrPath,
                                    "-in",
                                    passDirectory + "manifest.json",
                                    "-out",
                                    passDirectory + "signature",
                                    "-outform",
                                    "der",
                                    "-binary",
                                    "-passin",
                                    "pass:" + certificatePassword)
        } catch {
            throw WalletKitError.cannotGenerateSignature(underlying: error)
        }
    }
}
