//
//  BBTabTransitions.h
//  BoxBox
//
//  Cross-fades the tab bar's content instead of letting it cut. See
//  BBTabTransitions.m for the funnel it hooks and the tunables.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Arms the tab-switch transition. Call once, from the constructor.
void BBInstallTabTransitions(void);

NS_ASSUME_NONNULL_END
