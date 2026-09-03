#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGChoicePickerVC : UITableViewController

- (instancetype)initWithTitle:(NSString *)title
                  defaultsKey:(NSString *)key
                      options:(NSArray<NSDictionary<NSString *, NSString *> *> *)options;

@property (nonatomic, copy, nullable) NSString *footerText;

@end

NS_ASSUME_NONNULL_END
