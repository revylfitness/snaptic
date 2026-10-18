import XCTest
@testable import SnapticKit

final class KitArgsTests: XCTestCase {
    // MARK: Mode

    func testHelperModesComeFromFirstArgument() {
        XCTAssertEqual(KitArgs.mode(arguments: ["/A/Snaptic", "--display-guard", "--parent", "1"]), .displayGuard)
        XCTAssertEqual(KitArgs.mode(arguments: ["/A/Snaptic", "--virtual-host"]), .virtualHost)
        XCTAssertEqual(KitArgs.mode(arguments: ["/A/Snaptic", "--selftest-helpers"]), .selftestHelpers)
        XCTAssertEqual(KitArgs.mode(arguments: ["/A/Snaptic", "--selftest-child"]), .selftestChild)
        XCTAssertEqual(KitArgs.mode(arguments: ["/A/Snaptic", "cli", "list"]), .cli)
    }

    func testHelperFlagsLaterInArgvDontCount() {
        XCTAssertEqual(KitArgs.mode(arguments: ["/A/Snaptic", "--safe-mode", "--display-guard"]), .app)
    }

    func testLowercaseSymlinkIsCLI() {
        XCTAssertEqual(KitArgs.mode(arguments: ["/usr/local/bin/snaptic", "list"]), .cli)
        XCTAssertEqual(KitArgs.mode(arguments: ["snaptic"]), .cli)
        XCTAssertEqual(KitArgs.mode(arguments: ["/Applications/Snaptic.app/Contents/MacOS/Snaptic"]), .app)
        XCTAssertEqual(KitArgs.mode(arguments: []), .app)
    }

    // MARK: App arguments

    func testNoArgumentsIsFine() {
        XCTAssertEqual(try KitArgs.parseApp([]).get(), AppLaunchOptions())
    }

    func testSafeModeAndRelaunch() {
        let parsed = try? KitArgs.parseApp(["--relaunch-from", "4242", "--safe-mode"]).get()
        XCTAssertEqual(parsed, AppLaunchOptions(safeMode: true, relaunchFrom: 4242))
    }

    func testProcessSerialNumberAllowedOnce() {
        XCTAssertNoThrow(try KitArgs.parseApp(["-psn_0_123456"]).get())
        XCTAssertEqual(KitArgs.parseApp(["-psn_0_1", "-psn_0_2"]), .failure(.duplicate("-psn_0_2")))
        XCTAssertEqual(KitArgs.parseApp(["-psn_"]), .failure(.unknownArgument("-psn_")))
        XCTAssertEqual(KitArgs.parseApp(["-psn_0_1x"]), .failure(.unknownArgument("-psn_0_1x")))
    }

    func testDefaultsOverridesAreRefused() {
        XCTAssertEqual(KitArgs.parseApp(["-NSDocumentRevisionsDebugMode", "YES"]),
                       .failure(.unknownArgument("-NSDocumentRevisionsDebugMode")))
        XCTAssertEqual(KitArgs.parseApp(["-AppleLanguages", "(en)"]), .failure(.unknownArgument("-AppleLanguages")))
        XCTAssertEqual(KitArgs.parseApp(["-SnapticConfig.v1", "x"]), .failure(.unknownArgument("-SnapticConfig.v1")))
    }

    func testUnknownAndHelperFlagsAreRefused() {
        XCTAssertEqual(KitArgs.parseApp(["--verbose"]), .failure(.unknownArgument("--verbose")))
        XCTAssertEqual(KitArgs.parseApp(["--safe-mode", "--display-guard"]), .failure(.unknownArgument("--display-guard")))
        XCTAssertEqual(KitArgs.parseApp([""]), .failure(.unknownArgument("")))
    }

    func testDuplicatesAreRefused() {
        XCTAssertEqual(KitArgs.parseApp(["--safe-mode", "--safe-mode"]), .failure(.duplicate("--safe-mode")))
        XCTAssertEqual(KitArgs.parseApp(["--relaunch-from", "1", "--relaunch-from", "2"]),
                       .failure(.duplicate("--relaunch-from")))
    }

    func testRelaunchNeedsAValidPID() {
        XCTAssertEqual(KitArgs.parseApp(["--relaunch-from"]), .failure(.missingValue("--relaunch-from")))
        for bad in ["0", "-1", "+5", "12a", " 7", "99999999999", "2147483648", ""] {
            XCTAssertEqual(KitArgs.parseApp(["--relaunch-from", bad]), .failure(.invalidPID(bad)), bad)
        }
        XCTAssertEqual(KitArgs.parsePID("2147483647"), Int32.max)
        XCTAssertEqual(KitArgs.parsePID("1"), 1)
    }

    func testRelaunchValueIsNotReparsedAsAFlag() {
        XCTAssertEqual(KitArgs.parseApp(["--relaunch-from", "--safe-mode"]), .failure(.invalidPID("--safe-mode")))
    }

    func testFuzzedArgumentsNeverCrashAndOnlyAllowedShapesPass() {
        var rng = SeededGenerator(seed: 0xA265)
        let pieces = ["--safe-mode", "--relaunch-from", "-psn_0_1", "12", "-NS", "x", "", "--", "-psn_9", "0"]
        for _ in 0..<5_000 {
            let count = Int(rng.next() % 5)
            let args = (0..<count).map { _ in pieces[Int(rng.next() % UInt64(pieces.count))] }
            if case .success(let options) = KitArgs.parseApp(args) {
                for a in args {
                    XCTAssertTrue(a == "--safe-mode" || a == "--relaunch-from" || KitArgs.isProcessSerialNumber(a)
                                  || KitArgs.parsePID(a) != nil, "\(args)")
                }
                XCTAssertEqual(options.safeMode, args.contains("--safe-mode"))
            }
        }
    }

    func testMessagesAreCleanedAndShort() {
        let long = String(repeating: "x", count: 500) + "\u{202E}"
        let message = AppArgumentError.unknownArgument(long).message
        XCTAssertLessThan(message.count, 120)
        XCTAssertFalse(message.unicodeScalars.contains { $0.value == 0x202E })
    }

    // MARK: Environment

    func testDeniedEnvironment() {
        let env = ["HOME": "/Users/a", "PATH": "/usr/bin", "DYLD_INSERT_LIBRARIES": "/tmp/x.dylib",
                   "MallocStackLogging": "1", "OBJC_DISABLE_INITIALIZE_FORK_SAFETY": "YES",
                   "NSZombieEnabled": "YES", "CFFIXED_USER_HOME": "/tmp", "SWIFT_DEBUG": "1",
                   "LIBDISPATCH_COOPERATIVE_POOL_STRICT": "1", "OS_ACTIVITY_MODE": "disable",
                   "__CF_USER_TEXT_ENCODING": "0x1F5:0:0", "XPC_FLAGS": "0"]
        XCTAssertEqual(KitArgs.deniedEnvironmentVariables(env), [
            "CFFIXED_USER_HOME", "DYLD_INSERT_LIBRARIES", "LIBDISPATCH_COOPERATIVE_POOL_STRICT",
            "MallocStackLogging", "NSZombieEnabled", "OBJC_DISABLE_INITIALIZE_FORK_SAFETY", "OS_ACTIVITY_MODE",
            "SWIFT_DEBUG",
        ])
    }

    func testOrdinaryLaunchEnvironmentPasses() {
        let env = ["HOME": "/Users/a", "PATH": "/usr/bin:/bin", "TMPDIR": "/var/folders/x/T/", "USER": "a",
                   "SHELL": "/bin/zsh", "LOGNAME": "a", "__CF_USER_TEXT_ENCODING": "0x1F5:0x0:0x0",
                   "XPC_SERVICE_NAME": "0", "XPC_FLAGS": "0x0", "SSH_AUTH_SOCK": "/private/tmp/x"]
        XCTAssertEqual(KitArgs.deniedEnvironmentVariables(env), [])
    }

    func testHome() {
        XCTAssertTrue(KitArgs.homeMatches(environmentHome: "/Users/a", accountHome: "/Users/a"))
        XCTAssertTrue(KitArgs.homeMatches(environmentHome: "/Users/a/", accountHome: "/Users/a"))
        XCTAssertTrue(KitArgs.homeMatches(environmentHome: nil, accountHome: "/Users/a"))
        XCTAssertFalse(KitArgs.homeMatches(environmentHome: "/tmp/fake", accountHome: "/Users/a"))
        XCTAssertFalse(KitArgs.homeMatches(environmentHome: "/Users/a", accountHome: ""))
        XCTAssertTrue(KitArgs.homeMatches(environmentHome: "/", accountHome: "/"))
    }

    func testTranslocation() {
        XCTAssertTrue(KitArgs.isTranslocated("/private/var/folders/ab/xyz/T/AppTranslocation/1234/d/Snaptic.app"))
        XCTAssertFalse(KitArgs.isTranslocated("/Applications/Snaptic.app"))
        XCTAssertFalse(KitArgs.isTranslocated("/Users/a/AppTranslocation/Snaptic.app"))
    }

    func testNarrowPrefixesLetOrdinaryNSAndCFNamesThrough() {
        let allowed = ["NSUnbufferedIO": "YES", "CFNETWORK_DIAGNOSTICS": "0", "NSDocumentRevisionsDebugMode": "YES",
                       "CFBundleIdentifier": "x", "__CF_USER_TEXT_ENCODING": "0x1F5:0:0", "NSAppleEventsDebug": "x"]
        XCTAssertEqual(KitArgs.deniedEnvironmentVariables(allowed), [])
        let denied = ["CF_CHARSET_PATH": "/tmp", "CFFIXED_USER_HOME": "/tmp", "CFZombieLevel": "1",
                      "NSZombieEnabled": "YES", "NSDeallocateZombies": "NO", "NSDebugEnabled": "YES",
                      "NSObjCMessageLoggingEnabled": "YES", "NSAutoreleaseFreedObjectCheckEnabled": "YES",
                      "DYLD_LIBRARY_PATH": "/tmp", "OBJC_PRINT_LOAD_METHODS": "YES", "MallocNanoZone": "0",
                      "LIBDISPATCH_STRICT": "1", "SWIFT_DETERMINISTIC_HASHING": "1", "OS_ACTIVITY_DT_MODE": "1"]
        XCTAssertEqual(KitArgs.deniedEnvironmentVariables(denied), denied.keys.sorted())
        // Prefixes are case-sensitive, like the variables themselves.
        XCTAssertEqual(KitArgs.deniedEnvironmentVariables(["dyld_x": "1", "nszombieenabled": "YES"]), [])
    }
}
