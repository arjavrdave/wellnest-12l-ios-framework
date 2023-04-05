//
//  WellnestPeripheral.swift
//  WellnestModule
//
//  Created by Arjav on 25/08/20.
//  Copyright © 2020 Royale Cheese. All rights reserved.
//

import CoreBluetooth

open class WellnestPeripheral : NSObject, Codable {
    public var identifier: UUID
    public var name: String?
    public var id: Int?
    
    required public override init() {
        self.identifier = UUID.init()
    }
    
    required public init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        self.identifier = (try! container?.decodeIfPresent(UUID.self, forKey: .identifier))!
        self.name = try container?.decodeIfPresent(String.self, forKey: .name) ?? "Unknown"
        self.id = try container?.decodeIfPresent(Int.self, forKey: .id) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case identifier
        case name
        case id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try? container.encodeIfPresent(identifier, forKey: .identifier)
        try? container.encodeIfPresent(name, forKey: .name)
        try? container.encodeIfPresent(id, forKey: .id)
    }
}
