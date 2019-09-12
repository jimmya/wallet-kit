import Core
import Crypto
import ZIPFoundation

enum WalletKitError: Error {
    case invalidPassJSON
    case cannotGenerateKey
    case cannotGenerateCertificate
    case cannotGenerateSignature
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
    
    public func savePass(pass: Pass, destination: String, on worker: Worker) throws -> Future<Void> {
        return try generatePass(pass: pass, on: worker).map { passData in
            self.fileManager.createFile(atPath: destination, contents: passData, attributes: nil)
        }
    }
    
    public func generatePass(pass: Pass, on worker: Worker) throws -> Future<Data> {
        let directory = fileManager.currentDirectoryPath
        let temporaryDirectory = directory + UUID().uuidString + "/"
        let passDirectory = temporaryDirectory + "pass/"
        
        do {
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
            
            let keyGeneration = try generateKey(directory: temporaryDirectory, on: worker)
            let certificateGeneration = try generateCertificate(directory: temporaryDirectory, on: worker)
            
            return flatMap(keyGeneration, certificateGeneration, { (_, _) in
                return try self.generateSignature(directory: temporaryDirectory, passDirectory: passDirectory, on: worker)
            }).map(to: Data.self, { _ in
                let passURL = URL(fileURLWithPath: passDirectory, isDirectory: true)
                let zipURL = URL(fileURLWithPath: temporaryDirectory + "/pass.pkpass")
                try self.fileManager.zipItem(at: passURL, to: zipURL, shouldKeepParent: false)
                return try Data(contentsOf: zipURL)
            }).catchMap { error in
                try self.fileManager.removeItem(atPath: temporaryDirectory)
                throw error
            }
        } catch {
            try fileManager.removeItem(atPath: temporaryDirectory)
            throw error
        }
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
    
    func generateKey(directory: String, on worker: Worker) throws -> EventLoopFuture<Void> {
        let keyPath = directory + "key.pem"
        return Process.asyncExecute("openssl",
                                    "pkcs12",
                                    "-in",
                                    certificatePath,
                                    "-nocerts",
                                    "-out",
                                    keyPath,
                                    "-passin",
                                    "pass:" + certificatePassword,
                                    "-passout",
                                    "pass:" + certificatePassword, on: worker) { _ in }.map(to: Void.self, { result in
                                        guard result == 0 else {
                                            throw WalletKitError.cannotGenerateKey
                                        }
                                    })
    }
    
    func generateCertificate(directory: String, on worker: Worker) throws -> EventLoopFuture<Void> {
        let certPath = directory + "cert.pem"
        return Process.asyncExecute("openssl",
                                    "pkcs12",
                                    "-in",
                                    certificatePath,
                                    "-clcerts",
                                    "-nokeys",
                                    "-out",
                                    certPath,
                                    "-passin",
                                    "pass:" + certificatePassword, on: worker) { _ in }.map(to: Void.self, { result in
                                        guard result == 0 else {
                                            throw WalletKitError.cannotGenerateCertificate
                                        }
                                    })
    }
    
    func generateSignature(directory: String, passDirectory: String, on worker: Worker) throws -> EventLoopFuture<Void> {
        return Process.asyncExecute("openssl",
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
                                    "pass:" + certificatePassword, on: worker) { _ in }.map(to: Void.self, { result in
                                        guard result == 0 else {
                                            throw WalletKitError.cannotGenerateCertificate
                                        }
                                    })
    }
}
