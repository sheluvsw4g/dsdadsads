//
//  DOActionButton.h
//  Dopamine
//
//  Created by tomt000 on 07/01/2024.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DOActionMenuButton : UIButton

@property (nonatomic) BOOL bottomSeparator;

+(DOActionMenuButton*)buttonWithAction:(UIAction *)action chevron:(BOOL)chevron;
+(DOActionMenuButton*)centeredButtonWithAction:(UIAction *)action;

@end

NS_ASSUME_NONNULL_END
