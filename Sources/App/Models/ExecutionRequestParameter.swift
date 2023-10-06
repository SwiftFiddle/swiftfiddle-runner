import Foundation

struct ExecutionRequestParameter: Decodable {
  let command: String?
  let options: String?
  let code: String?
  let timeout: Int?
  let _color: Bool?
  let _nonce: String?
}
