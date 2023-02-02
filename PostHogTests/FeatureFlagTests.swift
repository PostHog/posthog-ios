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
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"true\"}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let isEnabled = posthog.isFeatureEnabled("some-flag")
      expect(isEnabled).to(beTrue())
    }
      
    it("checks multivariate flag is enabled - integer") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":1}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagValue = posthog.getFeatureFlag("some-flag")
      expect(flagValue).to(be(1))
    }
    
    it("checks multivariate flag is enabled - string") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagValue = posthog.getFeatureFlag("some-flag")
      
      expect(flagValue).to(be("variant-1"))
    }
    
    it("retrieves feature flag payload - string") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}, \"featureFlagPayloads\":{\"some-flag\":\"variant-payload\"}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagPayload = posthog.getFeatureFlagStringPayload("some-flag", defaultValue: "default-payload")

      expect(flagPayload).to(equal("variant-payload"))
    }
    
    it("retrieves feature flag payload - integer") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}, \"featureFlagPayloads\":{\"some-flag\": 2000}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagPayload = posthog.getFeatureFlagIntegerPayload("some-flag", defaultValue: 3)

      expect(flagPayload).to(be(2000))
    }
    
    it("retrieves feature flag payload - double") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}, \"featureFlagPayloads\":{\"some-flag\": 2.000}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagPayload = posthog.getFeatureFlagDoublePayload("some-flag", defaultValue: 3.0)

      expect(flagPayload).to(be(2.000))
    }
    
    it("retrieves feature flag payload error - double") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}, \"featureFlagPayloads\":{\"some-flag\": {\"some-flag\":\"variant-1\"}}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagPayload = posthog.getFeatureFlagDoublePayload("some-flag", defaultValue: 3.0)

      expect(flagPayload).to(be(3.0))
    }
    
    it("retrieves feature flag payload - json") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}, \"featureFlagPayloads\":{\"some-flag\": {\"some-flag\":\"variant-1\"}}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagPayload = posthog.getFeatureFlagDictionaryPayload("some-flag", defaultValue: ["some-flag": "default-payload"])
      expect((flagPayload as! [String: String]) == (["some-flag": "variant-1"])).to(be(true))
    }

    it("retrieves feature flag payload error - json") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}, \"featureFlagPayloads\":{\"some-flag\": 2.00}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagPayload = posthog.getFeatureFlagDictionaryPayload("some-flag", defaultValue: ["some-flag": "default-payload"])

      expect((flagPayload as! [String: String]) == (["some-flag": "default-payload"])).to(be(true))
    }
    
    it("retrieves feature flag payload - array") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}, \"featureFlagPayloads\":{\"some-flag\": [\"some-flag\",\"variant-1\"]}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagPayload = posthog.getFeatureFlagArrayPayload("some-flag", defaultValue: ["some-flag", "default-payload"])
      expect((flagPayload as! [String]) == (["some-flag", "variant-1"])).to(be(true))
    }
    
    it("retrieves feature flag payload error - array") {
      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
        .andReturn(200)?
        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}, \"featureFlagPayloads\":{\"some-flag\": 2.00}}" as LSHTTPBody);
      posthog.reloadFeatureFlags()
      // Hacky: Need to buffer for async request to happen without stub being cleaned up
      sleep(1)
      let flagPayload = posthog.getFeatureFlagArrayPayload("some-flag", defaultValue: ["some-flag", "default-payload"])
      expect((flagPayload as! [String]) == (["some-flag", "default-payload"])).to(be(true))
    }
    
//    it("retrieves feature flag payload - number") {
//      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
//        .andReturn(200)?
//        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}}" as LSHTTPBody);
//      posthog.reloadFeatureFlags()
//      // Hacky: Need to buffer for async request to happen without stub being cleaned up
//      sleep(1)
//      let flagValue = posthog.getFeatureFlag("some-flag")
//      expect(flagValue).to(be("variant-1"))
//    }
//
//    it("retrieves feature flag payload - object") {
//      _ = stubRequest("POST", "https://app.posthog.test/decide/?v=3" as LSMatcheable)
//        .andReturn(200)?
//        .withBody("{\"featureFlags\":{\"some-flag\":\"variant-1\"}}" as LSHTTPBody);
//      posthog.reloadFeatureFlags()
//      // Hacky: Need to buffer for async request to happen without stub being cleaned up
//      sleep(1)
//      let flagValue = posthog.getFeatureFlag("some-flag")
//      expect(flagValue).to(be("variant-1"))
//    }

  }

}
