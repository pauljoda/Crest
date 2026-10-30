import CryptoKit
import XCTest

@testable import Crest

/// The helper's wire format: framing, byte encodings, the sealed layouts, and
/// the typed requests and replies built on them. The sealed vectors were made
/// with the reference implementation (AES-128-GCM, 16-byte nonce) and cross-checked
/// against CryptoKit.
final class ApplePasswordsCodecTests: XCTestCase {
    private static let key = "51e2cb3ad8339ec79f4a5b60a9b506aa"
    private static let nonce = "cbd10cb94c77ca0d4099c3bfe40c4318"
    private static let plaintext = """
        {"STATUS":0,"Entries":[{"USR":"ada@example.com","PWD":"p4ss\u{e9}word"}]}
        """
    private static let ciphertext = """
        9b6252462dc9fe5d80a0016e288f9af59ad9e6504775789ade12e9ecca2e533ade6c0657080c48ff\
        fb5ebc92cbf6b2eb9360e37dc5c8c44368268791ffd95bb2b529104eb9
        """
    private static let tag = "98b2eaa6c5cc2740c78ef2deb97e95fe"
    private static let identity = "0x00112233445566778899aabbccddeeff"

    private var session: ApplePasswordsSecretSession {
        // The shared key is 32 bytes; the cipher uses the first 16.
        ApplePasswordsSecretSession(
            identity: Self.identity,
            sharedKey: Data(testHexadecimal: Self.key) + Data(repeating: 0xEE, count: 16),
            byteEncoding: .hexadecimal
        )
    }

    // MARK: - Framing

    func testAFrameCarriesALittleEndianLengthAndSurvivesFragmentation() throws {
        let first = Data(repeating: 0x41, count: 258)
        let second = Data("{}".utf8)
        let wire = try ApplePasswordsFrameStream.frame(first) + ApplePasswordsFrameStream.frame(second)
        XCTAssertEqual(Array(wire.prefix(4)), [0x02, 0x01, 0x00, 0x00])

        var stream = ApplePasswordsFrameStream()
        var payloads: [Data] = []
        for byte in wire { payloads += try stream.append(Data([byte])) }
        XCTAssertEqual(payloads, [first, second])

        var whole = ApplePasswordsFrameStream()
        XCTAssertEqual(try whole.append(wire), [first, second])
    }

    func testFramesThatBreakTheLengthRulesAreRefused() throws {
        let tooLong = UInt32(ApplePasswordsFrameStream.maximumPayloadLength + 1).littleEndian
        for length in [UInt32(0), tooLong] {
            var stream = ApplePasswordsFrameStream()
            let prefix = withUnsafeBytes(of: length) { Data($0) }
            XCTAssertThrowsError(try stream.append(prefix + Data([0x7B])))
        }
        XCTAssertThrowsError(try ApplePasswordsFrameStream.frame(Data()))
        XCTAssertThrowsError(
            try ApplePasswordsFrameStream.frame(Data(count: ApplePasswordsFrameStream.maximumPayloadLength + 1))
        )
    }

    // MARK: - Byte encodings

    func testHexadecimalAndBase64SpellBytesAsTheHelperDoes() throws {
        let bytes = Data([0x00, 0x0A, 0xFF])
        XCTAssertEqual(ApplePasswordsByteEncoding.hexadecimal.string(for: bytes, prefixed: true), "0x000aff")
        XCTAssertEqual(ApplePasswordsByteEncoding.hexadecimal.string(for: bytes, prefixed: false), "000aff")
        XCTAssertEqual(ApplePasswordsByteEncoding.base64.string(for: bytes, prefixed: true), "AAr/")

        XCTAssertEqual(try ApplePasswordsByteEncoding.hexadecimal.bytes(from: "0x000aff"), bytes)
        XCTAssertEqual(try ApplePasswordsByteEncoding.hexadecimal.bytes(from: "000AFF"), bytes)
        XCTAssertEqual(try ApplePasswordsByteEncoding.base64.bytes(from: "AAr/"), bytes)
        // An odd number of digits reads as if it had a leading zero.
        XCTAssertEqual(try ApplePasswordsByteEncoding.hexadecimal.bytes(from: "0xabc"), Data([0x0A, 0xBC]))
        XCTAssertEqual(try ApplePasswordsByteEncoding.hexadecimal.bytes(from: "f"), Data([0x0F]))
        XCTAssertThrowsError(try ApplePasswordsByteEncoding.hexadecimal.bytes(from: "0xzz"))
        XCTAssertThrowsError(try ApplePasswordsByteEncoding.hexadecimal.bytes(from: "+f"))
    }

    func testCapabilitiesPickTheByteEncodingAndFailClosedOnAnotherSessionVersion() throws {
        let decoder = JSONDecoder()
        let base64 = try decoder.decode(
            ApplePasswordsCapabilities.self,
            from: Data(#"{"secretSessionVersion":1,"shouldUseBase64":true,"somethingNew":[1]}"#.utf8)
        )
        XCTAssertTrue(base64.isRecognized)
        XCTAssertEqual(base64.byteEncoding.string(for: Data([0xFF]), prefixed: true), "/w==")

        let empty = try decoder.decode(ApplePasswordsCapabilities.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.isRecognized)
        XCTAssertEqual(empty.byteEncoding.string(for: Data([0xFF]), prefixed: true), "0xff")

        let old = try decoder.decode(ApplePasswordsCapabilities.self, from: Data(#"{"secretSessionVersion":0}"#.utf8))
        XCTAssertFalse(old.isRecognized)
    }

    // MARK: - Sealed layouts

    func testInboundSealedDataIsNonceThenCiphertextThenTag() throws {
        let inbound = Data(testHexadecimal: Self.nonce + Self.ciphertext + Self.tag)
        XCTAssertEqual(String(decoding: try session.open(inbound), as: UTF8.self), Self.plaintext)

        var tampered = inbound
        tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try session.open(tampered))
        XCTAssertThrowsError(try session.open(Data(inbound.prefix(20))))
    }

    func testOutboundSealedDataIsCiphertextThenTagThenNonce() throws {
        let sealed = try session.seal(Data(Self.plaintext.utf8), nonce: Data(testHexadecimal: Self.nonce))
        XCTAssertEqual(sealed, Data(testHexadecimal: Self.ciphertext + Self.tag + Self.nonce))
    }

    // MARK: - Typed requests

    func testASealedReplyOpensAsAStringOrAnObjectAndNamesTheLogins() throws {
        for envelope in [try inboundReply(sealedAs: .string), try inboundReply(sealedAs: .object)] {
            let names = ApplePasswordsLoginNamesRequest(session: session, tabID: 1, host: "example.com")
            XCTAssertEqual(
                try names.reply(from: envelope),
                ApplePasswordsLoginNamesRequest.Logins(usernames: ["ada@example.com"], neverSaves: false)
            )
            // The vector's entry names no sites, so no password may be taken from it.
            let password = ApplePasswordsPasswordRequest(
                session: session,
                tabID: 1,
                host: "example.com",
                username: "ada@example.com"
            )
            XCTAssertNil(try password.reply(from: envelope))
        }
    }

    func testEntriesComeFromTheEntriesArrayOrFromEntryKeys() throws {
        let array = try queryResult(
            #"{"STATUS":0,"Entries":[{"USR":"ada","PWD":"a","sites":["example.com"]}]}"#
        )
        XCTAssertEqual(array.logins.map(\.username), ["ada"])

        let keyed = try queryResult(
            """
            {"STATUS":0,"RequiresUserAuthenticationToFill":true,
             "Entry_10":{"USR":"third","PWD":"Not Included","sites":["example.com"],"customTitle":"t"},
             "Entry_2":{"USR":"second","sites":["example.com"],"highLevelDomain":"example.com"},
             "Entry_1":{"USR":"first","sites":["example.com"],"CDate":1,"ModDate":2}}
            """
        )
        XCTAssertEqual(keyed.logins.map(\.username), ["first", "second", "third"])
        XCTAssertEqual(keyed.logins.last?.password, "Not Included")
    }

    func testTheNeverSaveMarkerIsAFactAndNeverALogin() throws {
        let result = try queryResult(
            """
            {"STATUS":0,"Entry_0":{"USR":"Passwords\u{00A0}not\u{00A0}saved","PWD":"Not Included","sites":["example.com"]}}
            """
        )
        let request = ApplePasswordsLoginNamesRequest(session: session, tabID: 1, host: "example.com")
        XCTAssertEqual(
            try request.reply(from: result),
            ApplePasswordsLoginNamesRequest.Logins(usernames: [], neverSaves: true)
        )

        let mixed = try queryResult(
            """
            {"STATUS":0,"Entries":[{"USR":"Passwords not saved","sites":["example.com"]},
            {"USR":"ada","sites":["example.com"]}]}
            """
        )
        XCTAssertEqual(
            try request.reply(from: mixed),
            ApplePasswordsLoginNamesRequest.Logins(usernames: ["ada"], neverSaves: true)
        )
        // The marker never yields a password, even when asked for by its own name.
        let password = ApplePasswordsPasswordRequest(
            session: session,
            tabID: 1,
            host: "example.com",
            username: "Passwords\u{00A0}not\u{00A0}saved"
        )
        XCTAssertNil(try password.reply(from: result))
    }

    func testATabEventAndLaunchingThePasswordsAppAreSentAsApplesExtensionSendsThem() throws {
        func fields(_ data: Data) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let activated = try fields(ApplePasswordsTabEventMessage.encoded(tabID: 3, event: .activated))
        XCTAssertEqual(activated["cmd"] as? Int, 8)
        XCTAssertEqual(activated["tabId"] as? Int, 3)
        XCTAssertEqual(activated["event"] as? Int, 1)
        XCTAssertEqual(try fields(ApplePasswordsTabEventMessage.encoded(tabID: 3, event: .closed))["event"] as? Int, 0)

        let origin = CredentialOrigin(scheme: "https", host: "example.com", port: 443)
        let launch = try fields(ApplePasswordsLaunchPasswordsAppMessage.encoded(origin: origin))
        XCTAssertEqual(launch["cmd"] as? Int, 13)
        XCTAssertEqual(launch["searchQueryURL"] as? String, "https://example.com")
        XCTAssertThrowsError(
            try ApplePasswordsLaunchPasswordsAppMessage.encoded(
                origin: CredentialOrigin(scheme: "http", host: "example.com", port: 80)))
    }

    func testOddEntriesAreSkippedAndRepeatedUsernamesListOnce() throws {
        let result = try queryResult(
            """
            {"STATUS":0,"Entries":[{"USR":7,"PWD":"x"},"junk",{"USR":"ada","PWD":3,"sites":"example.com"},
              {"USR":"ada","sites":["example.com"]},{"USR":"grace","sites":["example.com"]}],
             "Entry_1":{"USR":["not","a","string"]},"Entry_2":5,"Entry_3":{"USR":"ada","sites":["example.com"]}}
            """
        )
        let request = ApplePasswordsLoginNamesRequest(session: session, tabID: 1, host: "example.com")
        XCTAssertEqual(try request.reply(from: result).usernames, ["ada", "grace"])
    }

    func testAPasswordIsTakenFromTheEntryForTheUsernameAndTheFrameHost() throws {
        let result = try queryResult(
            """
            {"STATUS":0,"Entries":[
              {"USR":"ada","PWD":"other-site","sites":["other.example"]},
              {"USR":"grace","PWD":"grace-pass","sites":["login.example.com"]},
              {"USR":"ada","PWD":"right","sites":["example.com","login.example.com"]}]}
            """
        )
        func password(host: String, username: String) throws -> String? {
            try ApplePasswordsPasswordRequest(session: session, tabID: 1, host: host, username: username)
                .reply(from: result)
        }
        XCTAssertEqual(try password(host: "login.example.com", username: "ada"), "right")
        XCTAssertEqual(try password(host: "login.example.com", username: "grace"), "grace-pass")
        XCTAssertNil(try password(host: "example.com", username: "grace"))
        XCTAssertNil(try password(host: "evil.example", username: "ada"))
        XCTAssertNil(try password(host: "login.example.com", username: "nobody"))
    }

    func testAReplyForAnotherSessionIsRefused() throws {
        let envelope = try inboundReply(sealedAs: .string, identity: "0xdeadbeef")
        let request = ApplePasswordsLoginNamesRequest(session: session, tabID: 1, host: "example.com")
        XCTAssertThrowsError(try request.reply(from: envelope)) {
            XCTAssertEqual($0 as? ApplePasswordsError, .malformedReply)
        }
    }

    func testAQueryNamesTheFrameHostAndSealsItsBodyWithTheOutboundLayout() throws {
        let request = ApplePasswordsPasswordRequest(
            session: session,
            tabID: 7,
            host: "login.example.com",
            username: "ada@example.com"
        )
        let message = try jsonObject(request.encoded())
        XCTAssertEqual(message["cmd"] as? Int, 5)
        XCTAssertEqual(message["tabId"] as? Int, 7)
        XCTAssertEqual(message["frameId"] as? Int, 0)
        XCTAssertEqual(message["url"] as? String, "login.example.com")
        // The payload is a JSON string, as the extension sends it.
        let payload = try jsonObject(Data(try XCTUnwrap(message["payload"] as? String).utf8))
        XCTAssertEqual(payload["QID"] as? String, "CmdGetPassword4LoginName")

        // The sealed message travels as a JSON string.
        let sealedText = try XCTUnwrap(payload["SMSG"] as? String)
        let sealed = try jsonObject(Data(sealedText.utf8))
        XCTAssertEqual(sealed["TID"] as? String, Self.identity)
        let outbound = try ApplePasswordsByteEncoding.hexadecimal.bytes(from: try XCTUnwrap(sealed["SDATA"] as? String))
        let nonce = outbound.suffix(ApplePasswordsSecretSession.nonceLength)
        let body = try session.open(nonce + outbound.dropLast(ApplePasswordsSecretSession.nonceLength))
        let fields = try jsonObject(body)
        XCTAssertEqual(fields["ACT"] as? Int, 2)
        XCTAssertEqual(fields["URL"] as? String, "login.example.com")
        XCTAssertEqual(fields["USR"] as? String, "ada@example.com")
    }

    func testSavingNamesTheLoginWithoutAnEnvelopeURLAndTheQueryFollowsTheFormKind() throws {
        let expected: [(ApplePasswordsFormKind, String)] = [
            (.signIn, "CmdSetPassword4LoginName_URL"),
            (.signUp, "CmdNewAccount4URL"),
            (.changePassword, "CmdChangePasswordForLoginName_URL"),
        ]
        for (form, queryID) in expected {
            let request = ApplePasswordsSaveRequest(
                session: session,
                tabID: 1,
                host: "example.com",
                username: "ada@example.com",
                password: "secret",
                form: form
            )
            let envelope = try jsonObject(request.encoded())
            XCTAssertEqual(envelope["cmd"] as? Int, 6)
            XCTAssertNil(envelope["url"])
            let payload = try jsonObject(Data(try XCTUnwrap(envelope["payload"] as? String).utf8))
            XCTAssertEqual(payload["QID"] as? String, queryID)
        }

        let request = ApplePasswordsSaveRequest(
            session: session,
            tabID: 1,
            host: "example.com",
            username: "ada@example.com",
            password: "secret",
            form: .signUp
        )
        let fields = try openedBody(of: request.encoded())
        XCTAssertEqual(fields["ACT"] as? Int, 4)
        XCTAssertEqual(fields["URL"] as? String, "")
        XCTAssertEqual(fields["USR"] as? String, "")
        XCTAssertEqual(fields["PWD"] as? String, "")
        XCTAssertEqual(fields["NURL"] as? String, "example.com")
        XCTAssertEqual(fields["NUSR"] as? String, "ada@example.com")
        XCTAssertEqual(fields["NPWD"] as? String, "secret")
    }

    func testOneTimeCodeQueriesNameOnlyOriginsAndSealTheirBodyLikeTheExtension() throws {
        let frame = CredentialOrigin(scheme: "https", host: "login.example.com", port: 8443)
        let top = CredentialOrigin(scheme: "https", host: "example.com", port: 443)
        let frameURLs = try ApplePasswordsFrameURLs(frame: frame, topLevel: top)

        let listing = ApplePasswordsOneTimeCodesRequest(
            session: session, tabID: 3, host: "login.example.com", frameURLs: frameURLs, username: nil)
        let envelope = try jsonObject(listing.encoded())
        XCTAssertEqual(envelope["cmd"] as? Int, 16)
        XCTAssertEqual(envelope["tabId"] as? Int, 3)
        XCTAssertEqual(envelope["frameId"] as? Int, 0)
        XCTAssertNil(envelope["url"])
        let payload = try jsonObject(Data(try XCTUnwrap(envelope["payload"] as? String).utf8))
        XCTAssertEqual(payload["QID"] as? String, "CmdGetOneTimeCodes")
        let listed = try openedBody(of: listing.encoded())
        XCTAssertEqual(listed["ACT"] as? Int, 5)
        XCTAssertEqual(listed["TYPE"] as? String, "oneTimeCodes")
        XCTAssertEqual(
            listed["frameURLs"] as? [String], ["https://login.example.com:8443", "https://example.com"])
        XCTAssertNil(listed["username"])

        let filling = ApplePasswordsFillOneTimeCodeRequest(
            session: session, tabID: 3, host: "login.example.com", frameURLs: frameURLs, username: "ada",
            domain: "login.example.com")
        let fillEnvelope = try jsonObject(filling.encoded())
        XCTAssertEqual(fillEnvelope["cmd"] as? Int, 17)
        XCTAssertNil(fillEnvelope["url"])
        let fillPayload = try jsonObject(Data(try XCTUnwrap(fillEnvelope["payload"] as? String).utf8))
        XCTAssertEqual(fillPayload["QID"] as? String, "CmdDidFillOneTimeCode")
        let filled = try openedBody(of: filling.encoded())
        XCTAssertEqual(filled["ACT"] as? Int, 2)
        XCTAssertEqual(filled["TYPE"] as? String, "oneTimeCodes")
        XCTAssertEqual(filled["username"] as? String, "ada")

        // Origins only, https only, and the top-level origin only when it differs.
        XCTAssertEqual(try ApplePasswordsFrameURLs(frame: top, topLevel: top).origins, ["https://example.com"])
        let plain = CredentialOrigin(scheme: "http", host: "example.com", port: 80)
        XCTAssertEqual(try ApplePasswordsFrameURLs(frame: top, topLevel: plain).origins, ["https://example.com"])
        XCTAssertThrowsError(try ApplePasswordsFrameURLs(frame: plain, topLevel: top)) {
            XCTAssertEqual($0 as? ApplePasswordsError, .insecureOrigin)
        }
    }

    func testOneTimeCodeRepliesKeepTheirSourceAndFillsNeverTakeAnotherAccountsCode() throws {
        let example = CredentialOrigin(scheme: "https", host: "example.com", port: 443)
        let result = try queryResult(
            """
            {"STATUS":0,"RequiresUserAuthenticationToFill":true,"Entries":[
              {"source":"totp","code":"","username":"ada","domain":"example.com"},
              {"source":"sms","code":"123456","username":"","domain":"example.com"},
              {"source":"totp","code":"654321","username":"grace","domain":"example.com"}]}
            """
        )
        let listing = ApplePasswordsOneTimeCodesRequest(
            session: session, tabID: 1, host: "example.com",
            frameURLs: try ApplePasswordsFrameURLs(frame: example, topLevel: example), username: nil)
        let codes = try listing.reply(from: result)
        XCTAssertEqual(codes.map(\.source), [.generated, .delivered, .generated])
        XCTAssertEqual(codes.map(\.username), ["ada", "", "grace"])

        func current(
            username: String?, domain: String? = "example.com", in result: ApplePasswordsQueryResult,
            frame: CredentialOrigin? = nil
        ) throws -> String? {
            try ApplePasswordsFillOneTimeCodeRequest(
                session: session, tabID: 1, host: (frame ?? example).host,
                frameURLs: try ApplePasswordsFrameURLs(frame: frame ?? example, topLevel: example),
                username: username, domain: domain
            ).reply(from: result)
        }
        XCTAssertEqual(try current(username: "grace", in: result), "654321")
        XCTAssertNil(try current(username: "nobody", in: result))
        // The extension matches the source, the username and the domain, all three.
        XCTAssertNil(try current(username: "grace", domain: "other.example", in: result))
        XCTAssertNil(try current(username: "", in: result), "A delivered entry is never a generated code.")
        // Several entries that still match fill nothing.
        let twice = try queryResult(
            """
            {"STATUS":0,"Entries":[
              {"source":"totp","code":"111111","username":"ada","domain":"example.com"},
              {"source":"totp","code":"222222","username":"ada","domain":"example.com"}]}
            """)
        XCTAssertNil(try current(username: "ada", in: twice))
        let single = try queryResult(
            #"{"STATUS":0,"Entries":[{"source":"totp","code":"111222","username":"ada","domain":"example.com"}]}"#)
        XCTAssertEqual(try current(username: "ada", in: single), "111222")

        // A frame other than the top-level page gets only entries for its own host.
        let embedded = CredentialOrigin(scheme: "https", host: "login.example.net", port: 443)
        let mixed = try queryResult(
            """
            {"STATUS":0,"Entries":[
              {"source":"totp","code":"111111","username":"ada","domain":"example.com"},
              {"source":"sms","code":"222222","username":"ada","domain":"https://LOGIN.example.net/path"},
              {"source":"sms","code":"333333","username":"ada"},
              {"source":"sms","code":"444444","username":"ada","domain":"::bad::"}]}
            """)
        let embeddedListing = ApplePasswordsOneTimeCodesRequest(
            session: session, tabID: 1, host: embedded.host,
            frameURLs: try ApplePasswordsFrameURLs(frame: embedded, topLevel: example), username: nil)
        XCTAssertEqual(try embeddedListing.reply(from: mixed).map(\.code), ["222222"])
        XCTAssertNil(
            try current(username: "ada", in: mixed, frame: embedded), "The top-level site's code is not the frame's.")
    }

    // MARK: - Handshake

    func testTheFirstHandshakeMessageCarriesTheSessionAndTheMinimalPublicValue() throws {
        let request = ApplePasswordsClientHelloRequest(
            identity: Self.identity,
            publicKey: Data([0x01, 0xAB]),
            byteEncoding: .hexadecimal
        )
        let message = try jsonObject(request.encoded())
        XCTAssertEqual(message["cmd"] as? Int, 2)
        // The message is a JSON string, as the extension sends it.
        let inner = try jsonObject(Data(try XCTUnwrap(message["msg"] as? String).utf8))
        XCTAssertEqual(inner["QID"] as? String, "m0")
        XCTAssertEqual(inner["HSTBRSR"] as? String, ApplePasswordsClientHelloRequest.browserName)
        // The step is base64 JSON even when byte strings are hexadecimal.
        let step = try jsonObject(try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(inner["PAKE"] as? String))))
        XCTAssertEqual(step["TID"] as? String, Self.identity)
        XCTAssertEqual(step["MSG"] as? Int, 0)
        XCTAssertEqual(step["A"] as? String, "0x01ab")
        XCTAssertEqual(step["VER"] as? String, "1.0")
        XCTAssertEqual(step["PROTO"] as? [Int], [1])
    }

    func testTheChallengeKeepsTheSaltBytesAndAcceptsTheStageAsAStringOrNumber() throws {
        let request = ApplePasswordsClientHelloRequest(
            identity: Self.identity,
            publicKey: Data([1]),
            byteEncoding: .hexadecimal
        )
        for stage: Any in ["1", 1] {
            // An error code of zero is success.
            let envelope = try handshakeReply([
                "TID": Self.identity, "MSG": stage, "PROTO": 1, "B": "0x0102ff", "s": "0x00ff", "ErrCode": 0,
            ])
            let hello = try request.reply(from: envelope)
            XCTAssertEqual(hello.publicKey, Data([0x01, 0x02, 0xFF]))
            XCTAssertEqual(hello.salt, Data([0x00, 0xFF]))
        }
        for broken: [String: Any] in [
            ["TID": "0xother", "MSG": 1, "PROTO": 1, "B": "0x01", "s": "0x01"],
            ["TID": Self.identity, "MSG": 1, "PROTO": 1, "B": "0x01", "s": "0x01", "ErrCode": 5],
            ["TID": Self.identity, "MSG": 3, "PROTO": 1, "B": "0x01", "s": "0x01"],
            ["TID": Self.identity, "MSG": 1, "PROTO": 2, "B": "0x01", "s": "0x01"],
            // The old verification protocol is never accepted: pairing fails closed.
            ["TID": Self.identity, "MSG": 1, "PROTO": 0, "B": "0x01", "s": "0x01"],
        ] {
            XCTAssertThrowsError(try request.reply(from: handshakeReply(broken)))
        }
    }

    func testTheVerificationReplyNamesAWrongCodeAndOtherRefusals() throws {
        let request = ApplePasswordsClientVerificationRequest(
            identity: Self.identity,
            clientProof: Data([0xAA]),
            byteEncoding: .hexadecimal
        )
        let sent = try jsonObject(request.encoded())
        let inner = try jsonObject(Data(try XCTUnwrap(sent["msg"] as? String).utf8))
        XCTAssertEqual(inner["QID"] as? String, "m2")
        let step = try jsonObject(try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(inner["PAKE"] as? String))))
        XCTAssertEqual(step["MSG"] as? Int, 2)
        XCTAssertEqual(step["M"] as? String, "aa")

        let accepted = try request.reply(
            from: handshakeReply(["TID": Self.identity, "MSG": 3, "ErrCode": 0, "HAMK": "01ff"])
        )
        XCTAssertEqual(accepted.proof, Data([0x01, 0xFF]))
        XCTAssertThrowsError(
            try request.reply(from: handshakeReply(["TID": Self.identity, "MSG": 3, "ErrCode": 1]))
        ) { XCTAssertEqual($0 as? ApplePasswordsPairingError, .wrongCode) }
        XCTAssertThrowsError(
            try request.reply(from: handshakeReply(["TID": Self.identity, "MSG": 3, "ErrCode": 4]))
        ) { XCTAssertEqual($0 as? ApplePasswordsPairingError, .rejected(code: 4)) }
    }

    // MARK: - Commands

    func testPushesBecomeTypedEventsAndOtherCommandsAreIgnoredOrUnknown() {
        XCTAssertEqual(ApplePasswordsCommand.numbered(9)?.push, .passwordsDisabled)
        XCTAssertEqual(ApplePasswordsCommand.numbered(10)?.push, .reloginNeeded)
        XCTAssertEqual(ApplePasswordsCommand.numbered(15)?.push, .oneTimeCodeAvailable)
        XCTAssertEqual(ApplePasswordsCommand.numbered(15)?.push?.endsSession, false)
        XCTAssertEqual(ApplePasswordsCommand.numbered(9)?.push?.endsSession, true)
        XCTAssertEqual(ApplePasswordsCommand.numbered(16), .getOneTimeCodes)
        XCTAssertEqual(ApplePasswordsCommand.numbered(17), .didFillOneTimeCode)
        XCTAssertEqual(ApplePasswordsCommand.numbered(19), .cancelPairing)
        let cancel = try? jsonObject(ApplePasswordsCancelPairingMessage.encoded())
        XCTAssertEqual(cancel?["cmd"] as? Int, 19)
        XCTAssertNil(ApplePasswordsCommand.numbered(11))
        XCTAssertNil(ApplePasswordsCommand.numbered(1984))
    }

    // MARK: - Fixtures

    private enum SealedForm {
        case string
        case object
    }

    private func inboundReply(sealedAs form: SealedForm, identity: String = ApplePasswordsCodecTests.identity) throws
        -> ApplePasswordsInboundEnvelope
    {
        let sealed: [String: Any] = [
            "TID": identity,
            "SDATA": "0x" + Self.nonce + Self.ciphertext + Self.tag,
        ]
        let smsg: Any =
            switch form {
            case .string: String(decoding: try JSONSerialization.data(withJSONObject: sealed), as: UTF8.self)
            case .object: sealed
            }
        let message: [String: Any] = ["cmd": 5, "payload": ["SMSG": smsg]]
        return try JSONDecoder().decode(
            ApplePasswordsInboundEnvelope.self,
            from: JSONSerialization.data(withJSONObject: message)
        )
    }

    private func handshakeReply(_ step: [String: Any]) throws -> ApplePasswordsInboundEnvelope {
        let pake = try JSONSerialization.data(withJSONObject: step).base64EncodedString()
        let message: [String: Any] = ["cmd": 2, "payload": ["PAKE": pake]]
        return try JSONDecoder().decode(
            ApplePasswordsInboundEnvelope.self,
            from: JSONSerialization.data(withJSONObject: message)
        )
    }

    private func queryResult(_ json: String) throws -> ApplePasswordsQueryResult {
        try JSONDecoder().decode(ApplePasswordsQueryResult.self, from: Data(json.utf8))
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The decrypted body of an outbound query envelope.
    private func openedBody(of envelope: Data) throws -> [String: Any] {
        let payload = try jsonObject(Data(try XCTUnwrap(try jsonObject(envelope)["payload"] as? String).utf8))
        let sealed = try jsonObject(Data(try XCTUnwrap(payload["SMSG"] as? String).utf8))
        let outbound = try ApplePasswordsByteEncoding.hexadecimal.bytes(from: try XCTUnwrap(sealed["SDATA"] as? String))
        let nonce = outbound.suffix(ApplePasswordsSecretSession.nonceLength)
        return try jsonObject(session.open(nonce + outbound.dropLast(ApplePasswordsSecretSession.nonceLength)))
    }
}

extension Data {
    /// The bytes a string of hexadecimal digits spells, for test fixtures.
    init(testHexadecimal digits: String) {
        precondition(digits.count.isMultiple(of: 2), "A fixture spells whole bytes.")
        var bytes = Data()
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            bytes.append(UInt8(digits[index..<next], radix: 16)!)
            index = next
        }
        self = bytes
    }
}
