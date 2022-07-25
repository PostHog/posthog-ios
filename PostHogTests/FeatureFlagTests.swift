import Quick
import Nimble
import Nocilla
import PostHog

class FeatureFlagTests: QuickSpec {
  override func spec() {
    var posthog: PHGPostHog!

    beforeEach {
      LSNocilla.sharedInstance().start()
      let config = PHGPostHogConfiguration(apiKey: "QUI5ydwIGeFFTa1IvCBUhxL9PyW5B0jE", host: "https://app.posthog.test")
      posthog = PHGPostHog(configuration: config)
    }

    afterEach {
      posthog.reset()
      LSNocilla.sharedInstance().clearStubs()
      LSNocilla.sharedInstance().stop()
    }

    it("checks flag is enabled") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=2" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"true\"}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let isEnabled = posthog.isFeatureEnabled("some-flag")
      expect(isEnabled).to(beTrue())
    }
      
    it("checks multivariate flag is enabled - integer") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=2" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":1}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagValue = posthog.getFeatureFlag("some-flag")
      expect(flagValue).to(be(1))
    }
    
    it("checks multivariate flag is enabled - string") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=2" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagValue = posthog.getFeatureFlag("some-flag")
      expect(flagValue).to(be("variant-1"))
    }

  }

}
