//
//  EntityOtherDetailsTableViewCell.h
//  ios-objective-c-chat-app
//
//  Created by Budhabhooshan Patil on 27/03/19.
//  Copyright © 2019 Inscripts.com. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppConstants.h"

NS_ASSUME_NONNULL_BEGIN

@interface EntityOtherDetailsTableViewCell : UITableViewCell
+ (NSString *)cellIdentifier;
@property (nonatomic ,retain) UILabel *alabel;
@property (nonatomic ,retain) UIImageView *aImageView;
@end

NS_ASSUME_NONNULL_END
