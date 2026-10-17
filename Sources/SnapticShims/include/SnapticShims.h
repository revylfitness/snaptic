// Umbrella header for the SnapticShims module. Every per-area header must be
// imported here (clang warns about headers missing from an umbrella).
//
// Rules for all shim code:
//  - Private classes are only ever looked up at runtime (NSClassFromString);
//    no @interface for a private class, so a missing class can't stop launch.
//  - Every selector is checked with method_getTypeEncoding before use.
//  - @try/@catch wraps only Objective-C code inside .m files; exceptions never
//    cross into Swift.
#import "SNEncoding.h"
#import "SNSpawn.h"
#import "SNProcess.h"
#import "SNMonitorPanel.h"
#import "SNCGSModes.h"
#import "SNDDC.h"
#import "SNColorSync.h"
#import "SNNightShift.h"
#import "SNOSD.h"
#import "SNVirtualDisplay.h"
