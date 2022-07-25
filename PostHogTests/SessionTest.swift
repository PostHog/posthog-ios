import Quick
import Nimble
import PostHog

class SessionTest: QuickSpec {
  override func spec() {
    
    var sessionHandler: PHGSession!
    
    beforeEach {
      sessionHandler = PHGSession()
    }
    
    it("Generates a session id") {
      let sessionId = sessionHandler.getId()
      expect(sessionId).toNot(beNil())
      
      let anotherSessionId = sessionHandler.getId()
      expect(anotherSessionId).to(equal(sessionId))
      
    }
    
    it("Generates a new session id after refresh") {
      let sessionId = sessionHandler.getId()
      expect(sessionId).toNot(beNil())
      
      let timeInterval = Date().addingTimeInterval(TimeInterval(40.0 * 60.0)).timeIntervalSince1970
      sessionHandler.checkAndSetSessionId(timeInterval)
      
      let anotherSessionId = sessionHandler.getId()
      expect(anotherSessionId).toNot(equal(sessionId))
      
    }
    
  }
  
}
