import Quick
import Nimble
import Nocilla
import PostHog

class HTTPClientTest: QuickSpec {
  override func spec() {

    var client: PHGHTTPClient!
    let host = URL(string: "https://app.posthog.test")!

    beforeEach {
      LSNocilla.sharedInstance().start()
      client = PHGHTTPClient(requestFactory: nil)
    }
    afterEach {
      LSNocilla.sharedInstance().clearStubs()
      LSNocilla.sharedInstance().stop()
    }

    describe("defaultRequestFactory") {
      it("preserves url") {
        let factory = PHGHTTPClient.defaultRequestFactory()
        let url = URL(string: "https://app.posthog.test/batch")
        let request = factory(url!)
        expect(request.url) == url
      }
    }
    
    describe("sharedSessionUpload") {
      it("works") {
        let payload: [String: Any] = [
          "token": "some-token"
        ]

        _ = stubRequest("POST", "https://app.posthog.test/decide" as LSMatcheable)
          .withHeaders(
          [
              "Content-Length": "22",
              "Content-Type": "application/json"
          ])!
          .withBody(
            "{\"token\":\"some-token\"}" as LSMatcheable)
        
        var done = false;
        let task = client.sharedSessionUpload(payload, host: URL(string:"https://app.posthog.test/decide")!){ responseDict in
          expect(responseDict).toNot(beNil())
          done = true
        } failure: { error in

          expect(error).to(beNil())
          done = true
        }

        expect(task).toNot(beNil())
        expect(done).toEventually(beTrue())
      }
    }

    describe("upload") {
      it("does not ask to retry for json error") {
        let batch: [String: Any] = [
          // Dates cannot be serialized as is so the json serialzation will fail.
          "sent_at": NSDate(),
          "batch": [["type": "capture", "event": "foo"]],
        ]
        var done = false
        let task = client.upload(batch, host: host) { retry in
          expect(retry) == false
          done = true
        }
        expect(task).to(beNil())
        expect(done).toEventually(beTrue())
      }

      let batch: [String: Any] = ["sent_at":"2016-07-19'T'19:25:06Z", "batch":[["type":"capture", "event":"foo"]], "api_key": "foobar"]

      it("does not ask to retry for 2xx response") {
        _ = stubRequest("POST", "https://app.posthog.test/batch" as NSString)
          .withHeader("User-Agent", "posthog-ios/" + PHGPostHog.version())!
          .withJsonGzippedBody(batch as AnyObject)
          .andReturn(200)
        var done = false
        let task = client.upload(batch, host: host) { retry in
          expect(retry) == false
          done = true
        }
        expect(done).toEventually(beTrue())
        expect(task.state).toEventually(equal(URLSessionTask.State.completed))
      }

      it("asks to retry for 3xx response") {
        _ = stubRequest("POST", "https://app.posthog.test/batch" as NSString)
          .withHeader("User-Agent", "posthog-ios/" + PHGPostHog.version())!
          .withJsonGzippedBody(batch as AnyObject)
          .andReturn(304)
        var done = false
        let task = client.upload(batch, host: host) { retry in
          expect(retry) == true
          done = true
        }
        expect(done).toEventually(beTrue())
        expect(task.state).toEventually(equal(URLSessionTask.State.completed))
      }

      it("does not ask to retry for 4xx response") {
        _ = stubRequest("POST", "https://app.posthog.test/batch" as NSString)
          .withHeader("User-Agent", "posthog-ios/" + PHGPostHog.version())!
          .withJsonGzippedBody(batch as AnyObject)
          .andReturn(401)
        var done = false
        let task = client.upload(batch, host: host) { retry in
          expect(retry) == false
          done = true
        }
        expect(done).toEventually(beTrue())
        expect(task.state).toEventually(equal(URLSessionTask.State.completed))
      }

      it("asks to retry for 429 response") {
        _ = stubRequest("POST", "https://app.posthog.test/batch" as NSString)
          .withHeader("User-Agent", "posthog-ios/" + PHGPostHog.version())!
          .withJsonGzippedBody(batch as AnyObject)
          .andReturn(429)
        var done = false
        let task = client.upload(batch, host: host) { retry in
          expect(retry) == true
          done = true
        }
        expect(done).toEventually(beTrue())
        expect(task.state).toEventually(equal(URLSessionTask.State.completed))
      }

      it("asks to retry for 5xx response") {
        _ = stubRequest("POST", "https://app.posthog.test/batch" as NSString)
          .withHeader("User-Agent", "posthog-ios/" + PHGPostHog.version())!
          .withJsonGzippedBody(batch as AnyObject)
          .andReturn(504)
        var done = false
        let task = client.upload(batch, host: host) { retry in
          expect(retry) == true
          done = true
        }
        expect(done).toEventually(beTrue())
        expect(task.state).toEventually(equal(URLSessionTask.State.completed))
      }
    }
  }
}
