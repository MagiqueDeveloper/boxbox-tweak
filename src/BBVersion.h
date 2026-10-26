//
//  BBVersion.h
//  BoxBox
//
//  Single source of truth for the tweak version.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Marketing version of the tweak.
///
/// **Single source of truth.** `scripts/lib/common.sh` and the release workflow
/// both parse this literal, and `BoxBoxInit()` logs it, so bump it here and
/// nowhere else. `make lint` fails if the tag and this value disagree.
#define BB_VERSION_STRING @"1.0.0"

NS_ASSUME_NONNULL_END
