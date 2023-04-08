//
//  SwiftCookbook.swift
//  TakeHome
//
//  Created by Arthur Alaniz on 10/28/22.
//

import Foundation

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}
