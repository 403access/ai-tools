import XCTest
@testable import OpenCodeBar

final class QRCodeTests: XCTestCase {
    func testRendersPairingLink() {
        let link = "opencodebar://pair?url=http%3A%2F%2F192.168.1.5%3A8787&token=secret"
        let image = QRCode.image(for: link)
        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertEqual(image?.size.width, image?.size.height)
    }
}
