import Foundation
import NIO
import OpenCrypto
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
    public func generatePass(pass: Pass, destination: String? = nil, on eventLoop: EventLoop) throws -> EventLoopFuture<Data> {
        let directory = fileManager.currentDirectoryPath
        let temporaryDirectory = directory + UUID().uuidString + "/"
        let passDirectory = temporaryDirectory + "pass/"
        
        let prepare = preparePass(pass: pass, temporaryDirectory: temporaryDirectory, passDirectory: passDirectory, on: eventLoop)
        return prepare.flatMap { _ in
            return self.generateManifest(directory: passDirectory, on: eventLoop)
        }.flatMap { _ in
            return self.generateKey(directory: temporaryDirectory, on: eventLoop)
        }.flatMap { _ in
            return self.generateCertificate(directory: temporaryDirectory, on: eventLoop)
        }.flatMap { _ in
            return self.generateSignature(directory: temporaryDirectory, passDirectory: passDirectory, on: eventLoop)
        }.flatMap { _ in
            let passURL = URL(fileURLWithPath: passDirectory, isDirectory: true)
            let destinationPath = destination ?? temporaryDirectory + "/pass.pkpass"
            let zipURL = URL(fileURLWithPath: destinationPath)
            return self.zipPass(passURL: passURL, zipURL: zipURL, on: eventLoop).flatMap { _ in
                do {
                    return eventLoop.makeSucceededFuture(try Data(contentsOf: zipURL))
                } catch {
                    return eventLoop.makeFailedFuture(error)
                }
            }
        }.always { _ in
            try? self.fileManager.removeItem(atPath: temporaryDirectory)
        }
    }
}

private extension WalletKit {
    
    func preparePass(pass: Pass, temporaryDirectory: String, passDirectory: String, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
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
                promise.succeed(())
            } catch {
                promise.fail(error)
            }
        }
        return promise.futureResult
    }
    
    func generateManifest(directory: String, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        DispatchQueue.global().async {
            do {
                let contents = try self.fileManager.contentsOfDirectory(atPath: directory)
                var manifest: [String: String] = [:]
                contents.forEach({ (item) in
                    guard let data = self.fileManager.contents(atPath: directory + item) else { return }
                    let hash = Insecure.SHA1.hash(data: data)
                    manifest[item] = hash.description
                })
                let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
                self.fileManager.createFile(atPath: directory + "manifest.json", contents: manifestData, attributes: nil)
                promise.succeed(())
            } catch {
                promise.fail(error)
            }
        }
        return promise.futureResult
    }
    
    func generateKey(directory: String, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
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
                                    "pass:" + certificatePassword, on: eventLoop) { _ in }.flatMapThrowing { result in
                                        guard result == 0 else {
                                            throw WalletKitError.cannotGenerateKey
                                        }
        }
    }
    
    func generateCertificate(directory: String, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
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
                                    "pass:" + certificatePassword, on: eventLoop) { _ in }.flatMapThrowing { result in
                                        guard result == 0 else {
                                            throw WalletKitError.cannotGenerateCertificate
                                        }
        }
    }
    
    func generateSignature(directory: String, passDirectory: String, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
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
                                    "pass:" + certificatePassword, on: eventLoop) { _ in }.flatMapThrowing { result in
                                        guard result == 0 else {
                                            throw WalletKitError.cannotGenerateCertificate
                                        }
        }
    }
    
    func zipPass(passURL: URL, zipURL: URL, on eventLoop: EventLoop) -> EventLoopFuture<Void> {
        let promise = eventLoop.makePromise(of: Void.self)
        DispatchQueue.global().async {
            do {
                try self.fileManager.zipItem(at: passURL, to: zipURL, shouldKeepParent: false)
                promise.succeed(())
            } catch {
                promise.fail(error)
            }
        }
        return promise.futureResult
    }
}
