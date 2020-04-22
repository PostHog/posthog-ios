import Quick
import Nimble
import PostHog

class mockTransaction: SKPaymentTransaction {
  override var transactionIdentifier: String? {
    return "tid"
  }
  override var transactionState: SKPaymentTransactionState {
    return SKPaymentTransactionState.purchased
  }
  override var payment: SKPayment {
    return mockPayment()
  }
}

class mockPayment: SKPayment {
  override var productIdentifier: String { return "pid" }
}

class mockProduct: SKProduct {
  override var productIdentifier: String { return "pid" }
  override var price: NSDecimalNumber { return 3 }
  override var localizedTitle: String { return "lt" }

}

class mockProductResponse: SKProductsResponse {
  override var products: [SKProduct] {
    return [mockProduct()]
  }
}

class StoreKitCapturerTests: QuickSpec {
  override func spec() {

    var test: TestMiddleware!
    var capturer: PHGStoreKitCapturer!
    var posthog: PHGPostHog!

    beforeEach {
      let config = PHGPostHogConfiguration(apiKey: "foobar")
      test = TestMiddleware()
      config.middlewares = [test]
      posthog = PHGPostHog(configuration: config)
      capturer = PHGStoreKitCapturer.captureTransactions(for: posthog)
    }

    it("SKPaymentQueue Observer") {
      let transaction = mockTransaction()
      expect(transaction.transactionIdentifier) == "tid"
      capturer.paymentQueue(SKPaymentQueue(), updatedTransactions: [transaction])
      
      capturer.productsRequest(SKProductsRequest(), didReceive: mockProductResponse())
      
      let payload = test.lastContext?.payload as? PHGCapturePayload
      
      expect(payload?.event) == "Order Completed"
    }

  }

}
