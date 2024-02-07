//
//  SavGolFilter.swift
//  Wellnest Technician
//
//  Created by Dhruvi Prajapati on 05/01/24.
//  Copyright © 2024 Wellnest Inc. All rights reserved.

import Foundation
// Define a type alias for DoubleArray using Swift's native array type
typealias DoubleArray = [Double]

// Define the SGGOptions struct for clarity
struct SGGOptions {
    var windowSize: Int = 9
    var derivative: Int = 0
    var polynomial: Int = 3
}

// Declare the sgg function with appropriate type annotations
func sgg(
    ys: DoubleArray,
    xs: DoubleArray? = nil, // Optional xs array
    options: SGGOptions = SGGOptions()
) -> [Double] {
    
    // Extract options for readability
    let windowSize = options.windowSize
    let derivative = options.derivative
    let polynomial = options.polynomial
    
    // Validate window size with a guard statement
    if windowSize % 2 == 0 || windowSize < 5 || (windowSize % 1 != 0) {
        print("Invalid window size (should be odd, at least 5, and an integer)")
    }
    
    // Validate input types and values
    if Array(ys).count <= 0  { // Check if ys is an array and not empty
        print("Y values must be an array")
    }
    if xs == nil  { // Ensure xs is not nil
        print("X must be defined")
    }
    if windowSize > ys.count {
        print("Window size is higher than the data length \(windowSize)>\(ys.count)")
    }
    if derivative < 0 || (derivative % 1 != 0)  {
        print("Derivative should be a positive integer")
    }
    if polynomial < 1 || (polynomial % 1 != 0) {
        print("Polynomial should be a positive integer")
    }
    
    if polynomial >= 6 {
        print("Warning: You should not use polynomial grade higher than 5 if you are not sure that your data arises from such a model. Possible polynomial oscillation problems")
    }

// Core algorithm logic
   let np = ys.count
   var ans = [Double](repeating: 0, count: np)
    let weights = fullWeights(m: windowSize, n: polynomial, s: derivative)
    var hs = 0.0
   var constantH = true

   if let xs = xs as? [Double] { // Safely cast xs to DoubleArray
       constantH = false
   } else {
       hs = Double(pow(xs as! Double, Double(derivative))) // Force-unwrap as Double
   }

   // Handle borders
   let half = windowSize / 2
   for i in 0..<half {
       let wg1 = weights[half - i - 1]
       let wg2 = weights[half + i + 1]
       var d1 = 0.0
       var d2 = 0.0

       for j in 0..<windowSize {
           d1 += wg1[j] * ys[j]
           d2 += wg2[j] * ys[np - windowSize + j]
       }

       if constantH {
           ans[half - i - 1] = Double(d1 / hs)
           ans[np - half + i] = Double(d2 / hs)
       } else {
           hs = Double(getHs(xs: xs, i: half - i - 1, half: half, derivative: derivative))
           ans[half - i - 1] = Double(d1 / hs)
           hs = Double(getHs(xs: xs, i: np - half + i, half: half, derivative: derivative))
           ans[np - half + i] = Double(d2 / hs)
       }
   }

   // Handle internal points
   let wg = weights[half]
   for i in windowSize..<np {
       var d = 0.0
       for l in 0..<windowSize {
           d += (wg[l] * ys[l + i - windowSize])
       }

       if !constantH {
           hs = (getHs(xs: xs, i: i - half - 1, half: half, derivative: derivative))
       }

       ans[i - half - 1] = Double(d / hs)
   }

   return ans
}

func getHs(xs: [Double]?, i: Int, half: Int, derivative: Int) -> Double {
    var hs = 0.0
    var count = 0
    for j in i - half...i + half {
        if j >= 0 && j < (xs?.count ?? 0) - 1 {
            hs += xs![j + 1] - xs![j]
            count += 1
        }
    }
    return pow(hs / Double((count)), Double((derivative)))
}

func gramPoly(i: Int, m: Int, k: Int, s: Int) -> Double {
    if k > 0 {
        let poly1 = gramPoly(i: i, m: m, k: k - 1, s: s)
        let poly2 = gramPoly(i: i, m: m, k: k - 1, s: s - 1)
        
        
        let expr1 = Double(4 * k - 2)
        let expr2 = Double(k * (2 * m - k + 1))
        let expr3 = (Double(i) * poly1) + (Double(s) * poly2)
        let expr4 = Double((k - 1) * (2 * m + k))
        let expr5 = Double(k * (2 * m - k + 1))
        let poly3 = gramPoly(i: i, m: m, k: k - 2, s: s)
        return (expr1 / expr2) * expr3  - (expr4 / expr5) * poly3

    } else {
        return k == 0 && s == 0 ? 1.0 : 0.0
    }
}

func genFact(a: Int, b: Int) -> Double {
    var gf = 1
    if a >= b {
        for j in stride(from: a - b + 1, through: a, by: 1) {
            gf *= j
        }
    }
    return Double(gf)
}

func weight(i: Int, t: Int, m: Int, n: Int, s: Int) -> Double {
    var sum = 0.0
    for k in 0...n {
        let genFact1 = (genFact(a: 2 * m, b: (k)) / genFact(a: 2 * m + (k) + 1, b: Int(Double(k)) + 1))
        let gramPoly1 = gramPoly(i: i, m: m, k: Int((k)), s: 0)
        let gramPoly2 = gramPoly(i: t, m: m, k: Int((k)), s: s)
        sum += (2.0 * Double(k) + 1.0) * genFact1 * gramPoly1 * gramPoly2
        
    }
    return sum
}

func fullWeights(m: Int, n: Int, s: Int) -> [[Double]] {
    var weights = [[Double]](repeating: [Double](repeating: 0.0, count: m), count: m)
    let np = m / 2
    for t in -np...np {
        weights[t + np] = [Float64](repeating: 0, count: m)
        for j in -np...np {
            weights[t + np][j + np] = weight(i: j, t: t, m: np, n: n, s: s)
        }
    }
    return weights
}





