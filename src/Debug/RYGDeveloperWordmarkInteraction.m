#import "RYGDeveloperGateViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "../Settings/RYGSetting.h"
#import "../UI/RYGIcon.h"
#import "../UI/RYGLiquidGlass.h"
#import "../Utils.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface RYGDeveloperGateViewController (RYGWordmarkPrivate)
- (RYGSetting *)wordmarkPreviewSetting;
- (void)presentActionsForGate:(RYGRuntimeBoolMethod *)row displayTitle:(NSString *)displayTitle;
@end

static NSArray<NSDictionary<NSString *, NSString *> *> *RYGWordmarkVariants(void) {
    static NSArray *variants;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        variants = @[
            @{@"label": @"1A", @"asset": @"instagram-wordmark-1a", @"selector": @"isIGWordmark1aEnabled"},
            @{@"label": @"1A Alt", @"asset": @"instagram-wordmark-1a-alt", @"selector": @"isIGWordmark1aAltEnabled"},
            @{@"label": @"1B", @"asset": @"instagram-wordmark-1b", @"selector": @"isIGWordmark1bEnabled"},
            @{@"label": @"1B Alt", @"asset": @"instagram-wordmark-1b-alt", @"selector": @"isIGWordmark1bAltEnabled"},
        ];
    });
    return variants;
}

@implementation RYGDeveloperGateViewController (RYGDeveloperWordmarkInteraction)

- (RYGSetting *)ryg_interactiveWordmarkPreviewSetting {
    __weak typeof(self) weakSelf = self;
    return [RYGSetting customCellWithHeight:244.0 provider:^UITableViewCell *(UITableView *tableView, NSIndexPath *indexPath) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = UIColor.clearColor;

        UIVisualEffectView *glass = RYGLiquidGlassView(NO, NO, nil);
        glass.translatesAutoresizingMaskIntoConstraints = NO;
        glass.userInteractionEnabled = YES;
        glass.layer.cornerCurve = kCACornerCurveContinuous;
        glass.layer.cornerRadius = 22.0;
        glass.clipsToBounds = YES;
        [cell.contentView addSubview:glass];

        UIStackView *vertical = [UIStackView new];
        vertical.translatesAutoresizingMaskIntoConstraints = NO;
        vertical.axis = UILayoutConstraintAxisVertical;
        vertical.spacing = 8.0;
        vertical.distribution = UIStackViewDistributionFillEqually;
        [glass.contentView addSubview:vertical];

        NSArray *variants = RYGWordmarkVariants();
        for (NSInteger rowIndex = 0; rowIndex < 2; rowIndex++) {
            UIStackView *horizontal = [UIStackView new];
            horizontal.axis = UILayoutConstraintAxisHorizontal;
            horizontal.spacing = 8.0;
            horizontal.distribution = UIStackViewDistributionFillEqually;
            [vertical addArrangedSubview:horizontal];

            for (NSInteger column = 0; column < 2; column++) {
                NSInteger variantIndex = rowIndex * 2 + column;
                NSDictionary *variant = variants[(NSUInteger)variantIndex];
                UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
                tile.tag = 9100 + variantIndex;
                tile.backgroundColor = [UIColor.secondarySystemFillColor colorWithAlphaComponent:0.22];
                tile.layer.cornerCurve = kCACornerCurveContinuous;
                tile.layer.cornerRadius = 15.0;
                tile.accessibilityLabel = [NSString stringWithFormat:@"IGWordMark %@", variant[@"label"]];
                [tile addTarget:weakSelf action:@selector(ryg_wordmarkTileTapped:) forControlEvents:UIControlEventTouchUpInside];

                UIImageView *imageView = [UIImageView new];
                imageView.translatesAutoresizingMaskIntoConstraints = NO;
                imageView.contentMode = UIViewContentModeScaleAspectFit;
                imageView.tintColor = UIColor.labelColor;
                imageView.userInteractionEnabled = NO;
                UIImage *asset = [RYGIcon fbImageNamed:variant[@"asset"]];
                imageView.image = asset;
                [tile addSubview:imageView];

                UILabel *label = [UILabel new];
                label.translatesAutoresizingMaskIntoConstraints = NO;
                label.text = variant[@"label"];
                label.textAlignment = NSTextAlignmentCenter;
                label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
                label.textColor = UIColor.secondaryLabelColor;
                label.userInteractionEnabled = NO;
                [tile addSubview:label];

                [NSLayoutConstraint activateConstraints:@[
                    [imageView.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:10.0],
                    [imageView.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-10.0],
                    [imageView.topAnchor constraintEqualToAnchor:tile.topAnchor constant:10.0],
                    [imageView.bottomAnchor constraintEqualToAnchor:label.topAnchor constant:-5.0],
                    [label.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:6.0],
                    [label.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-6.0],
                    [label.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor constant:-7.0],
                    [label.heightAnchor constraintEqualToConstant:17.0],
                ]];

                if (!asset) {
                    UILabel *missing = [UILabel new];
                    missing.translatesAutoresizingMaskIntoConstraints = NO;
                    missing.text = @"asset unavailable";
                    missing.font = [UIFont systemFontOfSize:10.0];
                    missing.textColor = UIColor.tertiaryLabelColor;
                    missing.textAlignment = NSTextAlignmentCenter;
                    missing.userInteractionEnabled = NO;
                    [tile addSubview:missing];
                    [NSLayoutConstraint activateConstraints:@[
                        [missing.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
                        [missing.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor constant:-5.0],
                    ]];
                }
                [horizontal addArrangedSubview:tile];
            }
        }

        [NSLayoutConstraint activateConstraints:@[
            [glass.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:8.0],
            [glass.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-8.0],
            [glass.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6.0],
            [glass.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6.0],
            [vertical.leadingAnchor constraintEqualToAnchor:glass.contentView.leadingAnchor constant:10.0],
            [vertical.trailingAnchor constraintEqualToAnchor:glass.contentView.trailingAnchor constant:-10.0],
            [vertical.topAnchor constraintEqualToAnchor:glass.contentView.topAnchor constant:10.0],
            [vertical.bottomAnchor constraintEqualToAnchor:glass.contentView.bottomAnchor constant:-10.0],
        ]];
        return cell;
    }];
}

- (void)ryg_wordmarkTileTapped:(UIButton *)sender {
    NSInteger index = sender.tag - 9100;
    NSArray *variants = RYGWordmarkVariants();
    if (index < 0 || index >= (NSInteger)variants.count) return;
    NSDictionary *variant = variants[(NSUInteger)index];
    NSString *selector = variant[@"selector"];

    NSArray *rows = nil;
    @try { rows = [self valueForKey:@"gateRows"]; } @catch (__unused NSException *exception) {}
    for (id candidate in rows) {
        if (![candidate isKindOfClass:RYGRuntimeBoolMethod.class]) continue;
        RYGRuntimeBoolMethod *row = candidate;
        if ([row.selectorName isEqualToString:selector]) {
            [self presentActionsForGate:row
                           displayTitle:[NSString stringWithFormat:@"IG WordMark %@", variant[@"label"]]];
            return;
        }
    }
    [RYGUtils showToastForDuration:1.6
                             title:@"Gate not loaded"
                          subtitle:[NSString stringWithFormat:@"%@ is not present in the current runtime", selector]];
}

@end

__attribute__((constructor(65440))) static void RYGInstallWordmarkInteraction(void) {
    @autoreleasepool {
        Class cls = RYGDeveloperGateViewController.class;
        Method original = class_getInstanceMethod(cls, @selector(wordmarkPreviewSetting));
        Method replacement = class_getInstanceMethod(cls, @selector(ryg_interactiveWordmarkPreviewSetting));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    }
}
