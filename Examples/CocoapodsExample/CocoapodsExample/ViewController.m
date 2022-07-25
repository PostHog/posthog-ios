#import <PostHog/PHGPostHog.h>
// TODO: Test and see if this works
// @import PostHog;
#import "ViewController.h"


@interface ViewController ()

@end


@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    NSUserActivity *userActivity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
    userActivity.webpageURL = [NSURL URLWithString:@"http://www.posthog.com"];
    [[PHGPostHog sharedPostHog] continueUserActivity:userActivity];
    [[PHGPostHog sharedPostHog] capture:@"test"];
    [[PHGPostHog sharedPostHog] flush];

    [[PHGPostHog sharedPostHog] isFeatureEnabled:@"test-flag"];
}

- (IBAction)fireEvent:(id)sender
{
    [[PHGPostHog sharedPostHog] capture:@"Cocoapods Example Button"];
    [[PHGPostHog sharedPostHog] flush];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
