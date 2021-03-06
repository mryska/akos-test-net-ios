/*********************************************************************************
* Copyright 2014-2015 SPECURE GmbH
* 
* Redistribution and use of the RMBT code or any derivative works are 
* permitted provided that the following conditions are met:
* 
*   - Redistributions may not be sold, nor may they be used in a commercial 
*     product or activity.
*   - Redistributions that are modified from the original source must include 
*     the complete source code, including the source code for all components
*     used by a binary built from the modified sources. However, as a special 
*     exception, the source code distributed need not include anything that is 
*     normally distributed (in either source or binary form) with the major 
*     components (compiler, kernel, and so on) of the operating system on which 
*     the executable runs, unless that component itself accompanies the executable.
*   - Redistributions must reproduce the above copyright notice, this list of 
*     conditions and the following disclaimer in the documentation and/or
*     other materials provided with the distribution.
* 
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
* IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
* INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
* BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
* DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
* LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
* OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED 
* OF THE POSSIBILITY OF SUCH DAMAGE.
*********************************************************************************/

//
//  QualityOfServiceTest.swift
//  RMBT
//
//  Created by Benjamin Pucher on 16.01.15.
//  Copyright (c) 2015 Specure GmbH. All rights reserved.
//

import Foundation

///
public class QualityOfServiceTest {
    
    ///
    typealias ConcurrencyGroup = UInt
    
    ///
    typealias JsonObjectivesType = [String:[[String:AnyObject]]]
    
    //
    
    ///
    private let executorQueue = dispatch_queue_create("com.specure.rmbt.executorQueue", DISPATCH_QUEUE_CONCURRENT)
    
    ///
    private let qosQueue = dispatch_queue_create("com.specure.rmbt.qosQueue", DISPATCH_QUEUE_CONCURRENT)
    
    ///
    private let mutualExclusionQueue = dispatch_queue_create("com.specure.rmbt.qos.mutualExclusionQueue", DISPATCH_QUEUE_SERIAL)
    
    ///
    var delegate: QualityOfServiceTestDelegate?
    
    ///
    private let testToken: String
    
    ///
    private let speedtestStartTime: UInt64
    
    ///
//    private let qosStartTime: UInt64
    
    ///
    private var testCount: UInt16 = 0
    
    ///
    private var currentTestCount: UInt16 = 0
    
    ///
    private var activeTestsInConcurrencyGroup = 0
    
    ///
    private var controlConnectionMap = [String:QOSControlConnection]()
    
    ///
    private var qosTestConcurrencyGroupMap = [ConcurrencyGroup:[QOSTest]]()
    
    ///
    private var testTypeCountMap = [QOSTestType:UInt16]()
    
    ///
    private var sortedConcurrencyGroups = [ConcurrencyGroup]()
    
    ///
    private var resultArray = [QOSTestResult]()
    
    ///
    private var stopped = false
    
    //
    
    ///
    convenience init() {
        self.init(testToken: "f7e75c4c-f81f-41d6-b5c5-53b9452a459b_1424341414_dXX9tW1uNORSPPw0xaKvYQatfbU=", speedtestStartTime: nanoTime() - 30 * UInt64(NSEC_PER_SEC)) // for testing
    }
    
    ///
    init(testToken: String, speedtestStartTime: UInt64) {
        self.testToken = testToken
        self.speedtestStartTime = speedtestStartTime
        
        logger.debug("QualityOfServiceTest initialized with test token: \(testToken) at start time \(speedtestStartTime)")
    }
    
    ///
    public func start() {
        if (!stopped) {
            dispatch_async(qosQueue) {
                self.fetchQOSTestParameters()
            }
        }
    }
    
    ///
    public func stop() {
        logger.debug("ABORTING QOS TEST")
        
        dispatch_sync(mutualExclusionQueue) {
            self.stopped = true
            
            // close all control connections
            self.closeAllControlConnections()
            
            // inform delegate
            dispatch_async(dispatch_get_main_queue()) {
                self.delegate?.qualityOfServiceTestDidStop(self)
                return
            }
        }
    }
    
    //
    
    ///
    private func fetchQOSTestParameters() {
        if (stopped) {
            return
        }
        
        ControlServer.sharedControlServer.getQOSObjectives({ (response) -> () in
            dispatch_async(self.qosQueue) {
                self.continueWithQOSParameters(response)
            }
        }, error: { (error, info) -> () in
            logger.debug("ERROR fetching qosTestRequest")
            
            self.fail(nil) // TODO: error message...
        })
    }
    
    ///
    private func continueWithQOSParameters(responseObject: AnyObject) {
        if (stopped) {
            return
        }
        
        // call didStart delegate method // TODO: right place here?
        dispatch_async(dispatch_get_main_queue()) {
            self.delegate?.qualityOfServiceTestDidStart(self)
            return
        }
        
        parseRequestResult(responseObject)
        createTestTypeCountMap()
        openAllControlConnections() // open all control connections before tests
        runQOSTests()
    }
    
    ///
    private func parseRequestResult(responseObject: AnyObject) {
        if (stopped) {
            return
        }
        
        if let resultDictionary = responseObject as? [String:AnyObject] {
            
            if let errorArray = resultDictionary["error"] as? [AnyObject] { // TODO: type
                if (!errorArray.isEmpty) { // error element is always present in json, therefore check if it is empty to find an error
                    logger.debug("ERROR ON QOS TEST REQUEST: \(errorArray)")
                    // TODO: call did fail delegate method
                    self.fail(nil) // TODO: error message...
                    
                    return
                }
            }
            
            // loop through objectives
            if let objectives = resultDictionary["objectives"] as? JsonObjectivesType {
                
                // objective type is TCP, UDP, etc.
                // objective values are arrays of dictionaries for each test
                for (objectiveType, objectiveValues) in objectives {
                    
                    // loop each test
                    for (objectiveParams) in objectiveValues {
                        logger.verbose("-----")
                        logger.verbose("\(objectiveType): \(objectiveParams)")
                        logger.verbose("-------------------")
                        
                        // try to create qos test object from params
                        if let qosTest = QOSFactory.createQOSTest(objectiveType, params: objectiveParams) {
                            
                            logger.debug("created qos test: \(qosTest)")
                            
                            var concurrencyGroupArray: [QOSTest]? = qosTestConcurrencyGroupMap[qosTest.concurrencyGroup]
                            if (concurrencyGroupArray == nil) {
                                concurrencyGroupArray = [QOSTest]()
                            }
                            
                            concurrencyGroupArray!.append(qosTest)
                            qosTestConcurrencyGroupMap[qosTest.concurrencyGroup] = concurrencyGroupArray // is this line needed? wasn't this passed by reference?
                            
                            // increase test count
                            testCount++
                            
                        } else {
                            logger.debug("unimplemented/unknown qos type: \(objectiveType)")
                        }
                    }
                }
            }
            
            currentTestCount = testCount
        }
        
        // create sorted array of keys to let the concurrencyGroups increase
        /*let */sortedConcurrencyGroups = Array(qosTestConcurrencyGroupMap.keys).sorted(<)
        
        logger.debug("sorted concurrency groups: \(sortedConcurrencyGroups)")
    }
    
    ///
    private func createTestTypeCountMap() {
        if (stopped) {
            return
        }
        
        var testTypeSortDictionary = [QOSTestType:ConcurrencyGroup]()
        
        // fill testTypeCount map (used for displaying the finished test types in ui)
        for (cg, testArray) in qosTestConcurrencyGroupMap { // loop each concurrency group
            for test in testArray { // loop the tests inside each concurrency group
                let testType = test.getType()
                
                var count: UInt16? = testTypeCountMap[testType]
                if (count == nil) {
                    count = 0
                }
                
                count! += 1
                
                testTypeCountMap[testType] = count!
                
                //////
                
                if (testTypeSortDictionary[testType] == nil) {
                    testTypeSortDictionary[testType] = cg
                }
            }
        }
        
        // get test types and sort them according to their first execution
        var testTypeArray = Array<QOSTestType>(self.testTypeCountMap.keys)
        testTypeArray.sort() { lhs, rhs in
            testTypeSortDictionary[lhs] < testTypeSortDictionary[rhs]
        }
        
        // call didFetchTestTypes delegate method
        dispatch_async(dispatch_get_main_queue()) {
            self.delegate?.qualityOfServiceTest(self, didFetchTestTypes: testTypeArray)
            return
        }
        
        logger.debug("TEST TYPE COUNT MAP: \(testTypeCountMap)")
    }
    
    ///
    private func runQOSTests() {
        if (stopped) {
            return
        }
        
        // start with first concurrency group
        runTestsOfNextConcurrencyGroup()
    }
    
    ///
    private func runTestsOfNextConcurrencyGroup(/*concurrencyGroup: ConcurrencyGroup*/) {
        if (stopped) {
            return
        }
        
        if (sortedConcurrencyGroups.count > 0) {
            let concurrencyGroup = sortedConcurrencyGroups.removeAtIndex(0) // what happens if empty?
            
            if let testArray = qosTestConcurrencyGroupMap[concurrencyGroup] {
                
                // set count of tests
                activeTestsInConcurrencyGroup = testArray.count
                
                // calculate control connection timeout (TODO: improve)
                //var controlConnectionTimeout: UInt64 = 0
                //for qosTest in testArray {
                //    controlConnectionTimeout += qosTest.timeout
                //}
                /////
                
                // loop test array
                for qosTest in testArray {
                    if (stopped) {
                        return
                    }
                    
                    // get previously opened control connection
                    let controlConnection = getControlConnection(qosTest) // blocking if new connection has to be established
                    
                    // get test executor
                    if let testExecutor = QOSFactory.createTestExecutor(qosTest, controlConnection: controlConnection, delegateQueue: executorQueue, speedtestStartTime: speedtestStartTime) {
                        // TODO: which queue?
                        
                        // set test token (TODO: IMPROVE)
                        testExecutor.setTestToken(self.testToken)
                        
                        if (testExecutor.needsControlConnection()) {
                            // set control connection timeout (TODO: compute better! (not all tests may use same control connection))
                            logger.debug("setting control connection timeout to \(/*controlConnectionTimeout*/nsToMs(qosTest.timeout)) ms")
                            controlConnection.setTimeout(/*controlConnectionTimeout*/qosTest.timeout)
                        
                            // TODO: DETERMINE IF TEST NEEDS CONTROL CONNECTION
                            // IF IT NEEDS IT, AND CONTROL CONNECTION CONNECT FAILED THEN SKIP THIS TEST AND DON'T SEND RESULT TO SERVER
                            if (!controlConnection.connected) {
                                // don't do this test
                                logger.info("skipping test because it needs control connection but we don't have this connection. \(qosTest)")
                            
                                dispatch_sync(self.mutualExclusionQueue) {
                                    self.qosTestFinishedWithResult(qosTest.getType(), withTestResult: nil) // no result because test didn't run
                                }
                            
                                continue
                            }
                        }
                        
                        logger.debug("starting execution of test: \(qosTest)")
                        
                        // execute tests
                        dispatch_async(self.executorQueue) {
                            testExecutor.execute() { (testResult: QOSTestResult) in
                                
                                dispatch_sync(self.mutualExclusionQueue) {
                                    self.qosTestFinishedWithResult(testResult.testType, withTestResult: testResult)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    ///
    private func qosTestFinishedWithResult(testType: QOSTestType, withTestResult testResult: QOSTestResult?) {
        if (stopped) {
            return
        }
        
        logger.debug("qos test finished with result: \(testResult)")
        
        if let testResult = testResult {
            
            if (testResult.fatalError) {
                // TODO: quit whole test due to fatal error
                // !!
                
                // TODO: dispatch delegate method
                self.fail(nil) // TODO: error message...
            }
            
            // add result to result map
            resultArray.append(testResult)
        }
        
        checkProgress()
        checkTypeCount(testType)
        checkTestState()
    }
    
    ///
    private func checkProgress() {
        if (stopped) {
            return
        }
        
        // decrement test counts
        self.currentTestCount -= 1
        
        // check for progress
        let testsLeft = self.testCount - self.currentTestCount
        let percent: Float = Float(testsLeft) / Float(self.testCount)
        
        logger.debug("QOS: increasing progress to \(percent)")
        
        dispatch_async(dispatch_get_main_queue()) {
            self.delegate?.qualityOfServiceTest(self, didProgressToValue: percent)
            return
        }
    }
    
    ///
    private func checkTypeCount(testType: QOSTestType) {
        if (stopped) {
            return
        }
        
        // check for finished test type
        self.testTypeCountMap[testType]! -= 1
        if (self.testTypeCountMap[testType]! == 0) {
         
            logger.debug("QOS: finished test type: \(testType)")
            
            dispatch_async(dispatch_get_main_queue()) {
                self.delegate?.qualityOfServiceTest(self, didFinishTestType: testType)
                return
            }
        }
    }
    
    ///
    private func checkTestState() {
        if (stopped) {
            return
        }
        
        activeTestsInConcurrencyGroup -= 1
        
        if (activeTestsInConcurrencyGroup == 0) {
            // all tests in concurrency group finished
            // -> go on with next concurrency group
            
            if (sortedConcurrencyGroups.count > 0) {
                // there are more concurrency groups (and tests)
                
                dispatch_async(self.qosQueue) {
                    self.runTestsOfNextConcurrencyGroup()
                }
                
            } else {
                // all concurrency groups finished
                dispatch_async(self.qosQueue) {
                    self.finalizeQOSTests()
                }
            }
        }
    }
    
    ///
    private func finalizeQOSTests() {
        if (stopped) {
            return
        }
        
        logger.debug("ALL FINISHED")
        
        closeAllControlConnections()
        
        // debug log:
        /*logger.debugExec() {
            logger.debug("\n\n\n\n\nRESULT \(self.resultArray.count):")
            logger.debug("\(self.resultArray)")
        }*/
        
        // submit results
        submitQOSTestResults()
    }
    
    ///
    private func getControlConnection(qosTest: QOSTest) -> QOSControlConnection {
        // determine control connection
        let controlConnectionKey: String = "\(qosTest.serverAddress)_\(qosTest.serverPort)"
        
        // TODO: make instantiation of control connection synchronous with locks!
        var conn: QOSControlConnection! = self.controlConnectionMap[controlConnectionKey]
        if (conn == nil) {
            logger.debug("\(controlConnectionKey): trying to open new control connection")
            //logger.debug("NO CONTROL CONNECTION PRESENT FOR \(controlConnectionKey), creating a new one")
            logger.debug("\(controlConnectionKey): BEFORE LOCK")
            
            // TODO: fail after timeout if qos server not available
            
            conn = QOSControlConnection(testToken: testToken)
            //conn.delegate = self
            
            // connect
            let isConnected = conn.connect(qosTest.serverAddress, onPort: qosTest.serverPort) // blocking
            
            //logger.debug("AFTER LOCK: have control connection?: \(isConnected)")
            // TODO: return nil? if not connected
            
            logger.debug("\(controlConnectionKey): AFTER LOCK -> CONTROL CONNECTION READY TO USE")
            
            controlConnectionMap[controlConnectionKey] = conn
        } else {
            logger.debug("\(controlConnectionKey): control connection already opened")
        }
        
        return conn
    }

    ///
    private func openAllControlConnections() {
        logger.info("opening all control connections")
        
        for concurrencyGroup in self.sortedConcurrencyGroups {
            if let testArray = qosTestConcurrencyGroupMap[concurrencyGroup] {
                for qosTest in testArray {
                    //dispatch_sync(mutualExclusionQueue) {
                        let controlConnection = self.getControlConnection(qosTest)
                        //logger.debug("opened control connection for qosTest \(qosTest)")
                    //}
                }
            }
        }
    }
    
    ///
    private func closeAllControlConnections() {
        logger.info("closing all control connections")
        
        // TODO: if everything is done: close all control connections
        for (_, controlConnection: QOSControlConnection) in self.controlConnectionMap {
            logger.debug("closing control connection \(controlConnection)")
            controlConnection.disconnect()
        }
    }
    
    ///////////////
    
    ///
    private func fail(error: NSError?) {
        if (stopped) {
            return
        }
        
        stop()
        
        dispatch_async(dispatch_get_main_queue()) {
            self.delegate?.qualityOfServiceTest(self, didFailWithError: error)
            return
        }
    }

    ///
    private func success() {
        if (stopped) {
            return
        }
        
        dispatch_async(dispatch_get_main_queue()) {
            self.delegate?.qualityOfServiceTest(self, didFinishWithResults: self.resultArray)
            return
        }
    }
    
    ////////////////////////////////////////////
    
    ///
    private func submitQOSTestResults() {
        if (stopped) {
            return
        }
        
        var _testResultArray = [QOSTestResults]()
        
        for testResult in resultArray { // TODO: resultArray == _testResultArray? just use resultArray?
            if (!testResult.isEmpty()) {
                _testResultArray.append(testResult.resultDictionary)
            }
        }
        
        // don't send results if all results are empty (e.g. only tcp tests and no control connection)
        if (_testResultArray.isEmpty) {

            // inform delegate
            success()
            
            return
        }
        
        //let qosDuration = nanoTime() - qosStartTime
        
        var params: [String:AnyObject] = [
            "time": NSNumber(unsignedLongLong: /*qosDuration*//*nanoTime()*/currentTimeMillis()), // currently unused on server!
            "test_token": testToken,
        ]
    
        params["qos_result"] = _testResultArray as NSArray // because array is a struct, nsarray is array's objc counterpart and this is an object...
        
        logger.debug("\(params)")
        
        ControlServer.sharedControlServer.submitQOSTestResult(params, success: { () -> () in
            logger.debug("QOS TEST RESULT SUBMIT SUCCESS")
        
            // now the test has finished...succeeding methods should go here
            self.success()
            
        }) { (error, info) -> () in
            logger.debug("QOS TEST RESULT SUBMIT ERROR: \(error)")
            
            // TODO: here the test failed...
            self.fail(error)
        }
    }
}
