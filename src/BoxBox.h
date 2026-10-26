//
//  BoxBox.h
//  BoxBox
//
//  Umbrella header for the tweak. Import this from a new hook file; each module
//  also declares its own header if you only need one piece.
//
//  Layout:
//
//      BBVersion.h          version constant (single source of truth)
//      BBLog.h              BBLog / BBLogOnce
//      BBRuntime.h          swizzling, hooking, recon helpers
//      BBPreferences.h      typed reads of this tweak's own tunables
//      BBPremium.h          paid-tier unlock + shared-suite seeding
//      BBTabTransitions.h   animated tab switches
//      BBPaywall.h          launch-funnel subscription cover suppression
//

#import <Foundation/Foundation.h>

#import "BBLog.h"
#import "BBPaywall.h"
#import "BBPreferences.h"
#import "BBPremium.h"
#import "BBRuntime.h"
#import "BBTabTransitions.h"
#import "BBVersion.h"
