//
//  BBPaywall.h
//  BoxBox
//
//  Suppresses the launch funnel's SwiftUI subscription cover. See BBPaywall.m
//  for the matcher and the two available modes.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Arms the paywall suppression. Call once, from the constructor.
void BBInstallPaywallSkip(void);

NS_ASSUME_NONNULL_END
