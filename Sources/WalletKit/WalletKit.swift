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
    
    /// Creates a new `WalletKit`.
    /// - parameters:
    ///     - certificatePath: Path to the pass certificate.
    ///     - certificatePassword: Password of the pass certificate.
    ///     - wwdrPath: Path to the WWDR certificate https://developer.apple.com/certificationauthority/AppleWWDRCA.cer.
    ///     - templateDirectoryPath: Path of the template to be used for the pass, containing the images etc.
    public init(certificatePath: String, certificatePassword: String, wwdrPath: String, templateDirectoryPath: String) {
        self.certificatePath = certificatePath
        self.certificatePassword = certificatePassword
        self.wwdrPath = wwdrPath
        self.templateDirectoryPath = templateDirectoryPath
    }
    
    /// Generate a signed .pkpass file
    /// - parameters:
    ///     - pass: A Pass object containing all pass information, ensure the `passTypeIdentifier` and `teamIdentifier` match those in supplied certificate.
    ///     - destination: The destination of the .pkpass to be saved, if nil the pass will be saved to the execution directory (generally the case if the result Data is used).
    ///     - arguments: An array of arguments to pass to the program.
    ///     - worker: Worker to perform async task on.
    /// - returns: A future containing the data of the generated pass.
    public func generatePass(pass: Pass, destination: String? = nil, on worker: Worker) throws -> Future<Data> {
        let directory = fileManager.currentDirectoryPath
        let temporaryDirectory = directory + UUID().uuidString + "/"
        let passDirectory = temporaryDirectory + "pass/"
        
        let prepare = { try self.preparePass(pass: pass, temporaryDirectory: temporaryDirectory, passDirectory: passDirectory, on: worker) }
        let manifest = { try self.generateManifest(directory: passDirectory, on: worker) }
        return [prepare, manifest].syncFlatten(on: worker).flatMap(to: Void.self, {
            let keyGeneration = try self.generateKey(directory: temporaryDirectory, on: worker)
            let certificateGeneration = try self.generateCertificate(directory: temporaryDirectory, on: worker)
            return [keyGeneration, certificateGeneration].flatten(on: worker)
        }).flatMap(to: Data.self, { _ in
            let passURL = URL(fileURLWithPath: passDirectory, isDirectory: true)
            let destinationPath = destination ?? temporaryDirectory + "/pass.pkpass"
            let zipURL = URL(fileURLWithPath: destinationPath)
            return try self.zipPass(passURL: passURL, zipURL: zipURL, on: worker).map { try Data(contentsOf: zipURL) }
        }).catchMap { error in
            // Ensure temporary directory is removed after a failure occurs
            try self.fileManager.removeItem(atPath: temporaryDirectory)
            throw error
        }
    }
}

private extension WalletKit {
    
    func preparePass(pass: Pass, temporaryDirectory: String, passDirectory: String, on worker: Worker) throws -> EventLoopFuture<Void> {
        let promise = worker.eventLoop.newPromise(Void.self)
        DispatchQueue.global().async {
            do {
                try self.fileManager.createDirectory(atPath: temporaryDirectory, withIntermediateDirectories: false, attributes: nil)
                try self.fileManager.copyItem(atPath: self.templateDirectoryPath, toPath: passDirectory)
                
                let jsonEncoder = JSONEncoder()
                jsonEncoder.dateEncodingStrategy = .iso8601
                let passData: Data
                do {
                    passData = try jsonEncoder.encode(pass)
                } catch {
                    throw WalletKitError.invalidPassJSON
                }
                self.fileManager.createFile(atPath: passDirectory + "pass.json", contents: passData, attributes: nil)
                promise.succeed()
            } catch {
                promise.fail(error: error)
            }
        }
        return promise.futureResult
    }
    
    func generateManifest(directory: String, on worker: Worker) throws -> EventLoopFuture<Void> {
        let promise = worker.eventLoop.newPromise(Void.self)
        DispatchQueue.global().async {
            do {
                let contents = try self.fileManager.contentsOfDirectory(atPath: directory)
                var manifest: [String: String] = [:]
                try contents.forEach({ (item) in
                    guard let data = self.fileManager.contents(atPath: directory + item) else { return }
                    let hash = try SHA1.hash(data).hexEncodedString()
                    manifest[item] = hash
                })
                let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
                self.fileManager.createFile(atPath: directory + "manifest.json", contents: manifestData, attributes: nil)
                promise.succeed()
            } catch {
                promise.fail(error: error)
            }
        }
        return promise.futureResult
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
    
    func zipPass(passURL: URL, zipURL: URL, on worker: Worker) throws -> EventLoopFuture<Void> {
        let promise = worker.eventLoop.newPromise(Void.self)
        DispatchQueue.global().async {
            do {
                try self.fileManager.zipItem(at: passURL, to: zipURL, shouldKeepParent: false)
                promise.succeed()
            } catch {
                promise.fail(error: error)
            }
        }
        return promise.futureResult
    }
}
