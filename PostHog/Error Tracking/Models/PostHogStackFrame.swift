//
//  PostHogStackFrame.swift
//  PostHog
//
//  Created by Ioannis Josephides on 02/12/2025.
//

import Foundation

/// Information about a single stack frame
struct PostHogStackFrame {
    /// Format string for converting UInt64 addresses to hex strings (e.g., "0x7fff12345678")
    static let hexAddressFormat = "0x%llx"
    
    /// The instruction address where the frame was executing
    let instructionAddress: UInt64
    
    /// Name of the binary module (e.g., "MyApp", "Foundation")
    let module: String?
    
    /// Corresponding package
    let package: String?
    
    /// Load address of the binary image in memory
    let imageAddress: UInt64?
    
    /// Whether this frame is considered part of the application code
    let inApp: Bool
    
    /// Function or symbol name (raw symbol without demangling)
    let function: String?
    
    /// Address of the symbol/function
    let symbolAddress: UInt64?
    
    var toDictionary: [String: Any] {
        var dict: [String: Any] = [:]
        
        dict["instruction_addr"] = String(format: Self.hexAddressFormat, instructionAddress)
        dict["platform"] = "apple" // always the same for posthog-ios (may need to revisit)
        dict["in_app"] = inApp
        
        if let module = module {
            dict["module"] = module
        }
        
        if let package = package {
            dict["package"] = package
        }
        
        if let imageAddress = imageAddress {
            dict["image_addr"] = String(format: Self.hexAddressFormat, imageAddress)
        }
        
        if let function = function {
            dict["function"] = function
        }
        
        if let symbolAddress = symbolAddress {
            dict["symbol_addr"] = String(format: Self.hexAddressFormat, symbolAddress)
        }
        
        return dict
    }
}
