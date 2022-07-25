#import <PostHog/PostHog.h>
#import "ViewController.h"


@interface ViewController ()

@end


@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[PHGPostHog sharedPostHog] capture:@"Manual Example Main View Loaded"];
    [[PHGPostHog sharedPostHog] flush];

    [[PHGPostHog sharedPostHog] isFeatureEnabled:@"test-flag"];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)fireEvent:(id)sender
{
    [[PHGPostHog sharedPostHog] capture:@"Manual Example Fire Event"];
    [[PHGPostHog sharedPostHog] flush];
}

@end
