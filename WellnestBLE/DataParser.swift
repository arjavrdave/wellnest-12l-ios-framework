//
//  DataParser.swift
//  wellnest-ios
//
//  Created by Arjav on 04/12/19.
//  Copyright © 2019 WellNest. All rights reserved.

import UIKit

open class DataParser: NSObject {
    
    private var x: [[Double]]? = [];
    private var y: [[Double]]? = [];
    private var n: Int = 0;
    private var i: Int = 0;
    private let a: [Double] = [1.0
    ,-1.5789478550001697
    ,1.0120725453024577
    ,-0.22712139734776327];

    private let b: [Double] = [0.025750411619315607
    ,0.07725123485794683
    ,0.07725123485794683
    ,0.025750411619315607];
    public override init() {
        x = Array(repeating: Array(repeating: 0.0, count: 10), count: 9)
        y = Array(repeating: Array(repeating: 0.0, count: 10), count: 9)
    }
    
    private func dataFromMSB(_ msb: Double, _ data: Double) -> Double{
        guard !(msb.isInfinite || msb.isNaN) else {
            return 0;
        }
        
        if msb >= Double(Int.min) && msb < Double(Int.max) {
            let temp1 = (Int(msb) & 240) >> 4
            let value = Double(data) + (256 * Double(temp1))
            return (Double(value) - 2048) / 124.1
        }
        
        return 0;
    }
    
    private func dataFromLSB(_ lsb: Double, _ data: Double) -> Double{
        guard !(lsb.isInfinite || lsb.isNaN) else {
            return 0;
        }
        
        if lsb >= Double(Int.min) && lsb < Double(Int.max) {
            let temp1 = (Int(lsb) & 15)
            let value = Double(data) + (256 * Double(temp1))
            return (Double(value) - 2048) / 124.1
        }
        
        return 0;
    }
    
    private func caluclateXY(index: Int, value: Double, n: Int) -> Double {
        x![index][n] = value;

        let m: Int = 10;
        let val: Double = b[0] * x![index][n] + b[1] * x![index][(n-1+m)%m] + b[2] * x![index][(n-2+m)%m] + b[3] * x![index][(n-3+m)%m] - a[1] * y![index][(n-1+m)%m] - a[2] * y![index][(n-2+m)%m] - a[3] * y![index][(n-3+m)%m];
        y![index][n] = val;

        return val;

    }
    
    open func setUpDataForRecording(_ bytesList: [[Double]]) -> [[Double]]{
       
                
//        x = Array(repeating: Array(repeating: 0.0, count: 10), count: 9)
//        y = Array(repeating: Array(repeating: 0.0, count: 10), count: 9)
        
        
        var chartsData = [[Double]]()
        for reading in bytesList {
            
            if i % 1 == 0 {
                var finalData = [Double]()

                finalData.append(self.caluclateXY(index: 0, value: dataFromMSB(reading[11], reading[2]), n: n)); //L1
                finalData.append(self.caluclateXY(index: 1, value: dataFromLSB(reading[11], reading[3]), n: n)); //L2
                
                finalData.append(self.caluclateXY(index: 2, value: dataFromMSB(reading[12], reading[4]), n: n)); //L3
                
                let lead10 = (finalData[0] + finalData[1]) / -2
                let lead11 = (finalData[0] - finalData[2]) / 2
                let lead12 = (finalData[1] + finalData[2]) / 2
                finalData.append(lead10)
                finalData.append(lead11)
                finalData.append(lead12)
                
                
                finalData.append(self.caluclateXY(index: 3, value: dataFromLSB(reading[12], reading[5]), n: n)); //L4
                
                finalData.append(self.caluclateXY(index: 4, value: dataFromMSB(reading[13], reading[6]), n: n)); //L5
                finalData.append(self.caluclateXY(index: 5, value: dataFromLSB(reading[13], reading[7]), n: n)); //L6
                
                finalData.append(self.caluclateXY(index: 6, value: dataFromMSB(reading[14], reading[8]), n: n)); //L7
                finalData.append(self.caluclateXY(index: 7, value: dataFromLSB(reading[14], reading[9]), n: n)); //L8
                
                finalData.append(self.caluclateXY(index: 8, value: dataFromMSB(reading[15], reading[10]), n: n)); //L9
                
                chartsData.append(finalData)
                self.n = (n + 1) % 10;
            }
            self.i = self.i + 1
        }
        return chartsData
    }
    
}

