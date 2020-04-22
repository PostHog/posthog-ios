import Quick
import Nimble
import PostHog

class ContextTests: QuickSpec {
  override func spec() {
    
    var posthog: PHGPostHog!
    
    beforeEach {
      let config = PHGPostHogConfiguration(apiKey: "foobar")
      posthog = PHGPostHog(configuration: config)
    }
    
    it("throws when used incorrectly") {
      var context: PHGContext?
      var exception: Error?

      do {
        try ObjC.catchException {
          context = PHGContext()
        }
      }
      catch {
        exception = error
      }

      expect(context).to(beNil())
      expect(exception).toNot(beNil())
    }

    
    it("initialized correctly") {
      let context = PHGContext(postHog: posthog)
      expect(context._posthog) == posthog
      expect(context.eventType) == PHGEventType.undefined
    }
    
    it("accepts modifications") {
      let context = PHGContext(postHog: posthog)
      
      let newContext = context.modify { context in
        context.distinctId = "sloth"
        context.eventType = .capture;
      }
      expect(newContext.distinctId) == "sloth"
      expect(newContext.eventType) == PHGEventType.capture;
      
    }
    
    it("modifies copy in debug mode to catch bugs") {
      let context = PHGContext(postHog: posthog).modify { context in
        context.debug = true
      }
      expect(context.debug) == true
      
      let newContext = context.modify { context in
        context.distinctId = "123"
      }
      expect(context) !== newContext
      expect(newContext.distinctId) == "123"
      expect(context.distinctId).to(beNil())
    }
    
    it("modifies self in non-debug mode to optimize perf.") {
      let context = PHGContext(postHog: posthog).modify { context in
        context.debug = false
      }
      expect(context.debug) == false
      
      let newContext = context.modify { context in
        context.distinctId = "123"
      }
      expect(context) === newContext
      expect(newContext.distinctId) == "123"
      expect(context.distinctId) == "123"
    }
    
  }
  
}
