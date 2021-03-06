/*********************************************************************************
* Copyright 2013 appscape gmbh
* Copyright 2014-2015 SPECURE GmbH
* 
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
* 
*   http://www.apache.org/licenses/LICENSE-2.0
* 
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*********************************************************************************/

//
//  RMBTTestParams.swift
//  RMBT
//
//  Created by Benjamin Pucher on 27.03.15.
//  Copyright (c) 2015 Specure GmbH. All rights reserved.
//

import Foundation

///
@objc class RMBTTestParams {

    ///
    let clientRemoteIp: String
    
    ///
    let pingCount: UInt = UInt(RMBT_TEST_PING_COUNT)
    
    ///
    let pretestDuration: NSTimeInterval = RMBT_TEST_PRETEST_DURATION_S
    
    ///
    let pretestMinChunkCountForMultithreading: UInt = UInt(RMBT_TEST_PRETEST_MIN_CHUNKS_FOR_MULTITHREADED_TEST)
    
    ///
    let serverAddress: String
    
    ///
    let serverEncryption: Bool
    
    ///
    let serverName: NSString
    
    ///
    let serverPort: UInt
    
    ///
    let resultURLString: String
    
    ///
    let testDuration: NSTimeInterval
    
    ///
    let testToken: String
    
    ///
    let testUUID: String
    
    ///
    let threadCount: UInt
    
    ///
    let waitDuration: NSTimeInterval
    
    //
    
    ///
    init(response: [NSObject:AnyObject]) { // TODO: remove NSObject after complete swift rewrite...
        // TODO: why are some values NSNumber (or long) and some String?
        
        logger.debug("test parameters response: \(response)")
        
        clientRemoteIp      = response["client_remote_ip"] as! String//.copy()
        serverAddress       = response["test_server_address"] as! String//.copy()
        serverEncryption    = (response["test_server_encryption"] as! NSNumber).boolValue
        serverName          = response["test_server_name"] as! String//.copy()
        
        // We use -integerValue as it's defined both on NSNumber and NSString, so we're more resilient in parsing:
        
        serverPort = UInt((response["test_server_port"] as! NSNumber).integerValue)
        //assert(serverPort > 0 && serverPort < 65536, "Invalid port")
        
        resultURLString = response["result_url"] as! String//.copy()
        testDuration    = NSTimeInterval((response["test_duration"] as! NSString).integerValue)
        //assert(testDuration > 0 && testDuration <= 100, "Invalid test duration")
        
        testToken   = response["test_token"] as! String//.copy()
        testUUID    = response["test_uuid"] as! String//.copy()
        threadCount = UInt((response["test_numthreads"] as! NSString).integerValue)
        //assert(threadCount > 0 && threadCount <= 128, "Invalid thread count")
        
        waitDuration = NSTimeInterval((response["test_wait"] as! NSNumber).integerValue)
        //assert(waitDuration >= 0 && waitDuration <= 128, "Invalid wait duration")
    }
}
